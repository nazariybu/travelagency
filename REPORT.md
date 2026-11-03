# Report: central logging with Loki

## 1. Goal

Collect the logs of the app nodes and the load balancer in one place, search them in Grafana next to
the metrics, and get a Telegram message when the logs show errors. Stage: "Logging".

## 2. Choices

| Need | Option | Plus | Minus |
|------|--------|------|-------|
| Log storage | **Loki** ✅ | Same Grafana as metrics, indexes only labels → little RAM and disk, LogQL looks like PromQL | Full-text search is slower than in Elasticsearch on big volumes |
| | ELK (Elasticsearch + Logstash + Kibana) | Powerful full-text search | Java, needs 4+ GB RAM only for Elasticsearch, one more UI |
| | Graylog | Good UI for logs | Needs MongoDB + OpenSearch |
| Log shipper | **Grafana Alloy** ✅ | Successor of Promtail, one agent for logs (and later metrics/traces), UI with the pipeline graph | New config language (Alloy syntax) |
| | Promtail | Simple YAML | End of life since 2 March 2026, no new versions |
| | Fluent Bit | Very light, many outputs | Separate project, no Grafana UI |
| Where Loki runs | **Docker Compose on vm-monitor** ✅ | Next to Grafana and Alertmanager, deployed by the same `monitoring.yml` | One server for all monitoring (no HA) |
| Storage | **Local disk (filesystem)** ✅ | Nothing else to run | Not for many servers; S3/MinIO for that |
| Tomcat logs | **systemd journal** ✅ | Ubuntu's Tomcat 9 already sends stdout/stderr there, nothing to configure in Tomcat | `catalina.out` has the same lines, so we read only one of them |
| nginx log format | **JSON** ✅ | Fields (status, upstream, request_time) without regex | Line is longer than `combined` |

## 3. Design

- Labels: `job` (tomcat / nginx), `type` (access / error), `instance` (vm-app, vm-app2, vm-lb).
  `instance` has the same values as in Prometheus, so a log line and a metric of the same server match.
  Status, URL, user are **not** labels (many values = many streams = slow Loki); they are parsed at query time.
- Retention: 7 days (`limits_config.retention_period`, the compactor deletes old chunks). Prometheus keeps 15 days.
- Noise: `hibernate.show_sql=true` prints every SQL query to stdout (~300 lines per HTTP request in the
  k6 test). Alloy drops them (`stage.drop`), the counter `loki_process_dropped_lines_total` shows how many.
- Stack traces: one Java error is 20–100 lines. Alloy glues them into one entry (`stage.multiline`):
  a new entry starts with a date (`2026-11-03 10:00:00` from logback or `03-Nov-2026 10:00:00` from Tomcat).
- App logging: `pom.xml` had two SLF4J bindings (`slf4j-nop` and `logback-classic`). SLF4J uses the one it
  finds first, and the order is not defined: either all app logs disappear (nop) or logback writes everything at DEBUG. Removed `slf4j-nop`,
  added `logback.xml`: INFO for `org.project`, WARN for libraries, the line starts with date and level.
- Is the shipper alive? Prometheus scrapes Alloy (`job="alloy"`, port 12345) and Loki (`job="loki"`).
  The existing `TargetDown` alert covers them.

## 4. Found in the logs

First look on 03.11, during a k6 run (dashboard **TravelAgency logs**, last 1 hour).

| # | What | Where (LogQL) | Meaning |
|---|------|---------------|---------|
| 1 | **HTTP 500 on sign-up of existing users.** k6 `setup()` registers `k6user1..200` again, they are already in the DB from earlier runs. The app logs `SqlExceptionHelper - Duplicate entry 'k6user200@k6.test' for key 'User.uk_user_email'` (SQLState 23000) and `GlobalExceptionHandler - Exception raised = could not execute statement :: URL = .../create`, and nginx returns **500** | `{job="tomcat"} \|= "Duplicate entry"`, panel "Requests by HTTP status" (orange 500 bars) | A bug: sign-up must check if the login/email exists and show a form error, not a 500. k6 ignores the sign-up result, so only the logs showed it |
| 2 | **Hibernate SQL noise:** up to **~20 000** `Hibernate: ...` lines per second on the app nodes during the test, all dropped by Alloy | Prometheus: `sum by (instance) (rate(loki_process_dropped_lines_total{reason="hibernate_sql"}[1m]))` | Same as problem #4 of the k6 report (`show_sql: true`). Without the filter this would be ~99% of all log lines in Loki |
| 3 | **Round-robin works:** requests are split about equally between `192.168.18.101:8080` (vm-app) and `192.168.18.105:8080` (vm-app2) | `sum by (upstream) (count_over_time({job="nginx", type="access"} \| json [1m]))` | The `ip_hash` problem from the first k6 run would be visible here at once |
| 4 | **Slow requests:** p95 up to ~4 s per node, single `POST /form-login` and `POST /hotel/book` take 4–5 s | panel "p95 response time per app node", `{job="nginx", type="access"} \| json \| request_time > 1` | Confirms the k6 result (p95 far above the 1.5 s goal), now per request and per node |
| 5 | **HTTP 499:** the client closed the connection before the answer (k6 request timeout) | `{job="nginx", type="access"} \| json \| status = 499` | Requests so slow that the client gave up; nginx logs them, Tomcat does not |
| 6 | Log alert `Nginx5xxErrors` (Tomcat stopped on both nodes) | `{job="nginx", type="error"}` | |