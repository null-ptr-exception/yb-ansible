# Implementation Guide: Post-Deployment Verification

## Overview

Three complementary verification layers:

1. **Role verify tasks** — run at the end of every deployment
2. **`verify.yml` playbook** — standalone on-demand health check
3. **Molecule tests** — CI/pre-merge role testing (future phase)

## 1. Role Verify Tasks

Added as the final tasks in each role. Deployment fails immediately if
verification doesn't pass.

### common role

- Assert `yb-master` or `yb-tserver` binary exists and is executable
- Assert node-exporter is listening on `node_exporter_port`

### yb-master role

- Wait for yb-master process to be listening on `yb_master_rpc_port`
- Query `http://localhost:{{ yb_master_web_port }}/api/v1/masters`
- Assert this master appears in the response with a role (LEADER or FOLLOWER)

### yb-tserver role

- Wait for yb-tserver process to be listening on `yb_tserver_rpc_port`
- Wait for YSQL proxy to be listening on `db_port`
- Query `http://localhost:{{ yb_tserver_web_port }}/api/v1/health-check`

## 2. verify.yml Playbook

A standalone playbook that performs read-only checks. No changes to any host.
Intended for:

- Post-deployment validation
- On-demand health checks by operators
- Scheduled monitoring (via cron or CI)

### Checks performed

#### All nodes
- node-exporter responding on `node_exporter_port`

#### Masters
- yb-master systemd service is active
- Master RPC port is listening
- Master web UI is reachable
- Cluster has exactly one LEADER
- All masters in inventory are present in the cluster

#### TServers
- yb-tserver systemd service is active
- TServer RPC port is listening
- YSQL proxy port is listening
- TServer appears as ALIVE in master's tablet-server list
- YSQL responds to `SELECT 1`

### Usage

```bash
ansible-playbook verify.yml
```

### Output

Uses `ansible.builtin.debug` to print a summary. All checks use
`ansible.builtin.assert` so the playbook fails with a clear message
on the first unhealthy node.

## 3. Molecule Tests (Future Phase)

- Driver: delegated (using existing libvirt VMs) or docker
- Scenarios: default (full deploy + verify), idempotency
- Verify phase: reuses the same assert tasks from the roles
- CI integration: GitHub Actions workflow

## Files to Create/Modify

| File | Action |
|---|---|
| `roles/common/tasks/verify.yml` | Create — binary and node-exporter checks |
| `roles/common/tasks/main.yml` | Modify — include verify.yml at end |
| `roles/yb-master/tasks/verify.yml` | Create — master cluster checks |
| `roles/yb-master/tasks/main.yml` | Modify — include verify.yml at end |
| `roles/yb-tserver/tasks/verify.yml` | Create — tserver and YSQL checks |
| `roles/yb-tserver/tasks/main.yml` | Modify — include verify.yml at end |
| `verify.yml` | Create — standalone health check playbook |
