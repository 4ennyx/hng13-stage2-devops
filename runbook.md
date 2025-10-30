# Blue/Green Deployment Runbook

## Alert Types and Meanings

### 🚨 Failover Detected
**What happened**: Traffic has switched from one pool to another (Blue → Green or Green → Blue)

**Possible Causes**:
- Primary pool health checks failing (5xx errors, timeouts)
- Manual pool switch for deployment
- Infrastructure issues

**Immediate Actions**:
1. Check primary pool health:
   ```bash
   curl http://localhost:8081/healthz  # Blue
   curl http://localhost:8082/healthz  # Green