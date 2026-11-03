// k6 load test for TravelAgency: login -> hotel search -> booking, through the nginx load balancer.
//
// Run (see k6/README.md):
//   BASE_URL=http://192.168.18.106 TEST_TYPE=load ./k6/run-k6.sh
//
// Test types (env TEST_TYPE):
//   smoke  - 1 user, 1 minute. Checks that the script and the site work.
//   load   - up to VUS users (default 30), 10 minutes. Normal busy day.
//   stress - steps 20 -> 50 -> 100 -> 150 users. Finds where it breaks.
//   spike  - 5 users, then 150 at once for 1 minute, then back.
//
// Every virtual user (VU) is one customer with its own account (k6user<N>),
// created in setup() through the normal sign-up form.

import http from 'k6/http';
import { check, group, sleep, fail } from 'k6';
import { Trend, Counter } from 'k6/metrics';

const BASE_URL = (__ENV.BASE_URL || 'http://192.168.18.106').replace(/\/$/, '');
const TEST_TYPE = __ENV.TEST_TYPE || 'smoke';
const VUS = parseInt(__ENV.VUS || '30', 10);
const USERS = parseInt(__ENV.USERS || '200', 10);       // accounts made in setup(); >= max VUs
const PASSWORD = __ENV.K6_USER_PASSWORD || 'K6load123';  // matches the app rule: digit + lower + upper, 6+
const USER_PREFIX = __ENV.USER_PREFIX || 'k6user';      // logins: k6user1, k6user2, ...
const THINK = parseFloat(__ENV.THINK || '1');            // seconds a user "reads" a page

const SCENARIOS = {
  smoke: { executor: 'constant-vus', vus: 1, duration: '1m' },
  load: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '2m', target: VUS },
      { duration: '6m', target: VUS },
      { duration: '2m', target: 0 },
    ],
    gracefulRampDown: '30s',
  },
  stress: {
    executor: 'ramping-vus',
    startVUs: 0,
    stages: [
      { duration: '2m', target: 20 },
      { duration: '3m', target: 20 },
      { duration: '2m', target: 50 },
      { duration: '3m', target: 50 },
      { duration: '2m', target: 100 },
      { duration: '3m', target: 100 },
      { duration: '2m', target: 150 },
      { duration: '3m', target: 150 },
      { duration: '2m', target: 0 },
    ],
    gracefulRampDown: '30s',
  },
  spike: {
    executor: 'ramping-vus',
    startVUs: 5,
    stages: [
      { duration: '1m', target: 5 },
      { duration: '10s', target: 150 },
      { duration: '1m', target: 150 },
      { duration: '10s', target: 5 },
      { duration: '2m', target: 5 },
    ],
    gracefulRampDown: '30s',
  },
};

if (!SCENARIOS[TEST_TYPE]) {
  throw new Error(`Unknown TEST_TYPE=${TEST_TYPE}. Use: ${Object.keys(SCENARIOS).join(', ')}`);
}

export const options = {
  scenarios: { [TEST_TYPE]: SCENARIOS[TEST_TYPE] },
  // setup() signs up USERS accounts one by one (bcrypt is slow), give it time
  setupTimeout: '10m',
  // Pass/fail goals (SLO). The run exits with code 99 if one fails, so CI can see it.
  thresholds: {
    http_req_failed: ['rate<0.01'],                    // < 1% errors
    http_req_duration: ['p(95)<1500'],                 // 95% of all requests faster than 1.5 s
    'http_req_duration{step:login}': ['p(95)<1500'],
    'http_req_duration{step:search}': ['p(95)<2000'],
    'http_req_duration{step:book}': ['p(95)<2000'],
    checks: ['rate>0.99'],
    bookings_failed: ['count<10'],
  },
  // Only these tags become labels in Prometheus. The "url" tag is left out:
  // it has ids inside (/booking/123) and would create thousands of series.
  systemTags: ['status', 'method', 'name', 'group', 'check', 'scenario', 'expected_response', 'error_code'],
  summaryTrendStats: ['avg', 'min', 'med', 'p(90)', 'p(95)', 'p(99)', 'max'],
};

// Business metrics: one full user journey and its result
const journeyDuration = new Trend('journey_duration', true);
const bookingsOk = new Counter('bookings_ok');
const bookingsFailed = new Counter('bookings_failed');

// Form POST that does NOT follow the redirect, so we can check where it points
function postForm(path, body, step, name) {
  return http.post(`${BASE_URL}${path}`, body, {
    redirects: 0,
    tags: { step, name: name || path },
  });
}

function get(path, step, name) {
  return http.get(`${BASE_URL}${path}`, { tags: { step, name: name || path } });
}

function login(n) {
  return `${USER_PREFIX}${n}`;
}

// Random stay: starts 1..300 days from now, 1..7 nights. Spreads bookings over dates
// so the "free rooms" query has real work to do.
function randomStay() {
  const day = 24 * 3600 * 1000;
  const start = new Date(Date.now() + (1 + Math.floor(Math.random() * 300)) * day);
  const end = new Date(start.getTime() + (1 + Math.floor(Math.random() * 7)) * day);
  const fmt = (d) => d.toISOString().slice(0, 10);
  return { startDate: fmt(start), endDate: fmt(end) };
}

// --- setup: create test accounts through the sign-up form (runs once) ---
export function setup() {
  const res = http.get(`${BASE_URL}/form-login`, { tags: { name: 'setup' } });
  if (res.status !== 200) {
    fail(`Site is not reachable: GET ${BASE_URL}/form-login -> ${res.status}`);
  }
  let created = 0;
  for (let i = 1; i <= USERS; i++) {
    const r = http.post(
      `${BASE_URL}/create`,
      {
        login: login(i),
        name: 'Load',
        surname: 'Test',
        email: `${login(i)}@k6.test`,
        password: PASSWORD,
      },
      { redirects: 0, tags: { name: 'setup' }, responseCallback: http.expectedStatuses(302, 500) },
    );
    // 302 = created; 500 = this login already exists from an earlier run (unique key). Both are fine.
    if (r.status === 302) created++;
  }
  console.log(`setup: ${created} new accounts, ${USERS - created} already existed`);
  // Accounts that existed before must have the same password, otherwise every login fails
  const probe = http.post(`${BASE_URL}/form-login`, { username: login(1), password: PASSWORD }, { redirects: 0, tags: { name: 'setup' } });
  if (String(probe.headers.Location || '').includes('error')) {
    fail(`Login ${login(1)} / K6_USER_PASSWORD does not work. Use another USER_PREFIX or the old password.`);
  }
  return { users: USERS };
}

// --- one iteration = one customer visit ---
export default function (data) {
  // VU 1 -> k6user1, VU 2 -> k6user2 ... Each VU keeps its own cookie (JSESSIONID / SESSION).
  const n = ((__VU - 1) % data.users) + 1;
  const t0 = Date.now();
  let ok = true;

  group('01 login', () => {
    get('/form-login', 'login');
    const r = postForm('/form-login', { username: login(n), password: PASSWORD }, 'login');
    ok = check(r, {
      'login: redirected': (x) => x.status === 302,
      'login: not back to login form': (x) => !String(x.headers.Location || '').includes('error'),
    }) && ok;
  });
  if (!ok) {
    sleep(THINK);
    return;
  }
  sleep(THINK);

  group('02 hotels', () => {
    const r = get('/hotel/', 'browse', '/hotel/');
    ok = check(r, { 'hotels: 200': (x) => x.status === 200 }) && ok;
  });
  sleep(THINK);

  let bookAction = null;
  const stay = randomStay();
  group('03 search', () => {
    get('/hotel/book', 'search', '/hotel/book (form)');
    // The app saves a draft booking on every search and puts its id into the "Book" buttons
    const r = postForm('/hotel/book', stay, 'search', '/hotel/book (search)');
    const actions = (r.body || '').match(/\/booking\/\d+\/create\/\d+/g) || [];
    ok = check(r, {
      'search: 200': (x) => x.status === 200,
      'search: has free rooms': () => actions.length > 0,
    }) && ok;
    if (actions.length > 0) {
      bookAction = actions[Math.floor(Math.random() * actions.length)];
    }
  });
  sleep(THINK);

  group('04 book', () => {
    if (!bookAction) {
      bookingsFailed.add(1);
      return;
    }
    const r = postForm(bookAction, stay, 'book', '/booking/{id}/create/{room}');
    const booked = check(r, {
      'book: redirected to booking': (x) => x.status === 302 && /\/booking\/\d+/.test(x.headers.Location || ''),
    });
    if (booked) {
      bookingsOk.add(1);
      // Location is absolute (http://host/booking/123); keep only the path
      const path = (r.headers.Location || '').match(/\/booking\/\d+/)[0];
      const info = get(path, 'book', '/booking/{id}');
      check(info, { 'booking page: 200': (x) => x.status === 200 });
    } else {
      bookingsFailed.add(1);
    }
    ok = booked && ok;
  });
  sleep(THINK);

  group('05 my bookings and logout', () => {
    get('/booking/user', 'browse', '/booking/user');
    const r = http.get(`${BASE_URL}/logout`, { redirects: 0, tags: { step: 'logout', name: '/logout' } });
    check(r, { 'logout: redirected to login form': (x) => x.status === 302 && /form-login/.test(x.headers.Location || '') });
  });

  journeyDuration.add(Date.now() - t0);
  sleep(THINK);
}