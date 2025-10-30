
**DECISION.md**
```markdown
# Implementation Decisions

## Nginx Configuration Choices

### 1. Upstream Design
- Used `backup` directive for secondary upstream to ensure it only receives traffic when primary fails
- Set `max_fails=2` and `fail_timeout=5s` for quick failure detection
- This ensures Nginx marks upstream as unhealthy after 2 consecutive failures within 5 seconds

### 2. Retry Logic
- `proxy_next_upstream` configured to retry on errors, timeouts, and 5xx status codes
- `proxy_next_upstream_tries 2` ensures single retry within same request
- Combined timeout of 10s ensures requests don't exceed the constraint

### 3. Header Preservation
- Explicit `proxy_pass_header` directives ensure `X-App-Pool` and `X-Release-Id` are forwarded
- No header stripping or modification occurs

### 4. Timeout Optimization
- `proxy_connect_timeout 2s`: Fast connection failure detection
- `proxy_send_timeout 5s` & `proxy_read_timeout 5s`: Balanced for responsiveness
- Total request timeout < 10s as required

## Failover Mechanism
The combination of:
1. Primary/backup upstream configuration
2. Aggressive health checking (5s intervals)
3. Smart retry policy with fast timeouts
4. Immediate failover to backup on primary failure

Ensures zero failed client requests during Blue service failures.