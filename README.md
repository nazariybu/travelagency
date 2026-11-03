# Load test with k6

k6 plays real customers: **log in → open hotels → search free rooms → book → my bookings → log out**,
all through nginx on vm-lb. Results go to Prometheus (remote write) and are shown in Grafana
on the dashboard **TravelAgency load test (k6)**, next to CPU, Tomcat threads, JVM heap and MySQL.

```
 k6 (ansible host / PC) ──HTTP──> nginx vm-lb ──> Tomcat vm-app, vm-app2 ──> MySQL vm-db
        │                                               └──> Redis vm-redis (sessions)
        └──remote write──> Prometheus vm-monitor <──scrape── node / jmx / mysqld / redis / pve exporters
                                  └──> Grafana: "TravelAgency load test (k6)"
```

## Files

| File | What it is |
|------|------------|
| `k6/travelagency.js` | The test: user journey, test types, pass/fail goals (thresholds) |
| `k6/run-k6.sh` | Runs k6 in Docker (`grafana/k6`) and pushes results to Prometheus |
| `k6/seed-rooms.sql` | 240 test rooms. The seed data has hotels but **no rooms**, so search finds nothing to book |
| `monitoring/grafana/dashboards/k6-load-test.json` | Grafana dashboard (added by `monitoring.yml` with the other dashboards) |
| `monitoring/docker-compose.yml` | Prometheus gets `--web.enable-remote-write-receiver`, so k6 can push |
| `k6/REPORT.md` | Results, bottleneck and scaling plan |

## Test types

| `TEST_TYPE` | Users (VUs) | Time | Question it answers |
|-------------|-------------|------|---------------------|
| `smoke` | 1 | 1 min | Does the script work? Run it first |
| `load` | `VUS` (default 30) | 10 min | Is a normal busy day OK? |
| `stress` | 20 → 50 → 100 → 150 | 24 min | Where does it break, and what breaks first? |
| `spike` | 5 → 150 → 5 | 4.5 min | Does it survive a sudden crowd and recover? |

Each virtual user is one customer with its own account (`k6user1`, `k6user2`, ...). The test makes
the accounts itself in `setup()` through the normal sign-up form (`USERS`, default 200).
Between pages a user "reads" for `THINK` seconds (default 1).

Pass/fail goals (the run ends with exit code 99 if one fails):

| Metric | Goal |
|--------|------|
| Failed HTTP requests | < 1% |
| p95 of all requests | < 1.5 s |
| p95 login / search / book | < 1.5 s / 2 s / 2 s |
| k6 checks passed | > 99% |

## Run

**1. Prometheus must accept remote write** (once). On the ansible host:

```bash
cd ansible
ansible-playbook monitoring.yml     # copies the new compose file and dashboard, recreates Prometheus
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://192.168.18.108:9090/api/v1/write   # 404 = flag missing, 400/415 = ready
```

**2. Add test rooms** (once). On vm-db:

```bash
mysql -u root -p travelagency < seed-rooms.sql
mysql -u root -p travelagency -e "SELECT COUNT(*) FROM Room"    # 240
```

**3. Run k6** from a machine that is **not** one of the tested servers (ansible host, your PC
or vm-agent) and has Docker. Otherwise k6 uses the CPU of the server it measures.

```bash
TEST_TYPE=smoke  ./k6/run-k6.sh     # first: everything green?
TEST_TYPE=load   ./k6/run-k6.sh
TEST_TYPE=stress ./k6/run-k6.sh
```

The script prints a Grafana link for this run. Settings (environment variables):

| Variable | Default | Meaning |
|----------|---------|---------|
| `BASE_URL` | `http://192.168.18.106` | nginx on vm-lb |
| `PROMETHEUS` | `http://192.168.18.108:9090` | where to push results |
| `GRAFANA` | `http://192.168.18.108:3000` | only for the printed link |
| `TESTID` | `<type>-<date>-<time>` | name of the run in Grafana (`Test run` list) |
| `VUS` | `30` | users for `load` |
| `USERS` | `200` | test accounts (≥ max users) |
| `THINK` | `1` | seconds between pages |
| `USER_PREFIX`, `K6_USER_PASSWORD` | `k6user`, `K6load123` | test accounts |

Without Docker: install k6 and run the same thing by hand:

```bash
K6_PROMETHEUS_RW_SERVER_URL=http://192.168.18.108:9090/api/v1/write \
K6_PROMETHEUS_RW_TREND_AS_NATIVE_HISTOGRAM=true \
BASE_URL=http://192.168.18.106 TEST_TYPE=smoke \
k6 run -o experimental-prometheus-rw --tag testid=smoke-1 k6/travelagency.js
```

The summary of every run is also saved to `k6/results/<testid>.json`.

## Read the dashboard

Every server panel also shows the number of users as a dashed line, so you see what happens
to the servers when users go up.

1. **Requests/s stops growing while users grow** → the system is full. Note the number of users
   at that moment: that is the capacity.
2. **At the same moment**, find the first resource at its limit:
   - CPU of `vm-app*` near 100% → app nodes (add a node, more CPU)
   - busy Tomcat threads = max → threads wait for something slower (usually the DB)
   - `vm-db` CPU high, many running MySQL queries → database
   - heap near 100%, GC time high → JVM memory
   - `vm-lb` CPU high → nginx (unlikely)
3. **Errors/s** and HTTP codes: 502/504 from nginx = Tomcat is too slow or down.

## Clean up after tests

The test leaves accounts `k6user*` and their bookings. On vm-db:

```sql
-- Room.booking_id points to the booking, so first free the rooms:
UPDATE Room r JOIN Booking b ON r.booking_id = b.bookingId JOIN User u ON b.user_id = u.userId
   SET r.booking_id = NULL WHERE u.login LIKE 'k6user%';
DELETE b FROM Booking b JOIN User u ON b.user_id = u.userId WHERE u.login LIKE 'k6user%';
DELETE FROM User WHERE login LIKE 'k6user%';
```

Run the test on a test copy of the data, not on real customers.
