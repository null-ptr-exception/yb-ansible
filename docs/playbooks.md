# Playbooks

## Overview

| Playbook | Purpose | Execution |
|---|---|---|
| `deploy.yml` | Day 1 fresh install, day 2 add tservers | Parallel |
| `upgrade.yml` | Version upgrades and config changes | Rolling (serial: 1) |
| `restart.yml` | Rolling restart without config changes | Rolling (serial: 1) |
| `verify.yml` | Read-only health check | Parallel |

## deploy.yml

For initial deployment and safe day-2 additions. All plays run in parallel.

### Workflow

```
Pre-flight checks (localhost)
│
├─ Assert master count is odd and non-zero
├─ If any master is responding:
│   └─ Query /api/v1/masters
│   └─ Assert cluster membership matches inventory
│
▼
Common prerequisites (all nodes)
│
├─ common: create yugabyte user/group, install directory
├─ node-exporter: ship binary to nodes, symlink, start service
└─ yb-build: ship tarball to nodes, extract, run post_install.sh
    │
    ├─ Controller: crane export from OCI image → .cache/packages/
    ├─ Ship to /opt/packages/<product>/<version>/ on each node
    ├─ Skip if correct version already installed
    └─ Fail if version change detected on running services
│
▼
Deploy masters (masters group)
│
├─ yb-master role: configure + start systemd service
└─ Verify: RPC/web ports, cluster has LEADER, all masters registered
│
▼
Deploy tservers (tservers group)
│
├─ yb-tserver role: configure + start systemd service
└─ Verify: RPC/YSQL ports, health check, tserver ALIVE, SELECT 1
```

### What it handles

- **Day 1 fresh install**: Deploy all masters and tservers from scratch.
- **Day 2 add tservers**: Add new tserver nodes to inventory and re-run. Existing nodes are unchanged (idempotent). New tservers heartbeat to the master leader and the cluster auto-rebalances tablets.
- **Day 2 idempotent re-run**: Same inventory, same config — no changes, no restarts.

### Safety checks

- **Master count validation**: Must be odd and non-zero. Fails immediately otherwise.
- **Master membership validation**: If any master is already responding, queries `/api/v1/masters` and compares cluster membership against inventory. Fails on mismatch — master changes require `replace-master.yml`.
- **Version change protection**: If a running node would receive a different YugabyteDB version, fails early. Version changes belong in `upgrade.yml`.

### What it does NOT handle

- Adding or removing master nodes (master count equals RF, fixed at cluster creation).
- Config changes on running nodes (requires rolling restart via `upgrade.yml`).
- Version upgrades (requires rolling restart via `upgrade.yml`).

## upgrade.yml

For version upgrades and config changes on existing nodes. Applies changes
first, then triggers a rolling restart.

### Workflow

```
Common prerequisites (all nodes)
│
├─ common, node-exporter, yb-build (same as deploy.yml)
└─ yb_allow_version_change: true (allows version changes on running nodes)
│
▼
Apply config to masters (masters group)
│
├─ yb-master role with yb_allow_config_change: true
└─ Config/version changes are applied but service not yet restarted
│
▼
Apply config to tservers (tservers group)
│
├─ yb-tserver role with yb_allow_config_change: true
└─ Config/version changes are applied but service not yet restarted
│
▼
Rolling restart (imports restart.yml)
│
├─ Masters first, one at a time (serial: 1)
│   ├─ Stop yb-master
│   ├─ Start yb-master (with daemon_reload)
│   ├─ Verify master health
│   └─ Pause 60s for cluster to stabilize
│
└─ Tservers second, one at a time (serial: 1)
    ├─ Stop yb-tserver
    ├─ Start yb-tserver (with daemon_reload)
    ├─ Verify tserver health
    └─ Pause 60s for tablet rebalancing
```

Following [YugabyteDB upgrade docs](https://docs.yugabyte.com/stable/manage/upgrade-deployment/),
masters are restarted before tservers.

### What it handles

- YugabyteDB version upgrades (new binary via `yb-build` role).
- Configuration changes (gflags, ports) on existing masters and tservers.

## restart.yml

Rolling restart of all YugabyteDB services without any config or version changes.
Useful for recovering from issues or applying OS-level changes that require
service restarts.

### Workflow

```
Masters (serial: 1)
│
├─ Stop yb-master
├─ Start yb-master (daemon_reload)
├─ Verify: RPC/web ports, cluster status, RAFT roles
└─ Pause 60s before next master
│
▼
Tservers (serial: 1)
│
├─ Stop yb-tserver
├─ Start yb-tserver (daemon_reload)
├─ Verify: RPC/YSQL ports, health check, tablet server status
└─ Pause 60s before next tserver
```

Each node is verified healthy before proceeding to the next. If verification
fails, the playbook stops — remaining nodes are not restarted.

### Tags

- `--tags masters` — restart only masters
- `--tags tservers` — restart only tservers

## verify.yml

Read-only health check playbook. Makes no changes to any host.

### Workflow

```
All nodes
│
├─ YugabyteDB binary exists at /opt/yugabyte/bin/yb-master
├─ node-exporter listening on port 9200
└─ node-exporter /metrics returns 200
│
▼
Masters
│
├─ yb-master systemd service is active
├─ RPC port 7100 listening
├─ Web UI port 7000 reachable
├─ Cluster has exactly one LEADER
└─ All inventory masters have LEADER or FOLLOWER role
│
▼
Tservers
│
├─ yb-tserver systemd service is active
├─ RPC port 9100 listening
├─ YSQL port 5433 listening
├─ Health check API returns 200
├─ All tservers ALIVE in master's tablet-server list
└─ YSQL responds to SELECT 1
```

### Usage

```bash
ansible-playbook -i inventory.ini verify.yml
```

## clean.yml

Stops all YugabyteDB and node-exporter services, removes systemd units, and
wipes data directories. Install directories and packages are preserved for
quick redeploys.

### Workflow

```
All nodes (parallel)
│
├─ Stop yb-tserver, yb-master, node-exporter
├─ Remove systemd unit files
├─ Reload systemd daemon
├─ Wipe data dirs (master + tserver under yb_data_dir)
└─ Remove post_install marker (so post_install.sh re-runs on next deploy)
```

### Usage

```bash
ansible-playbook -i inventory.ini clean.yml
```

After clean, run `deploy.yml` to redeploy. Packages and binaries are still
in place, so no image pull or file transfer is needed.

## Future Playbooks

| Playbook | Purpose |
|---|---|
| `replace-master.yml` | Replace a failed master node at a different IP using `yb-admin change_master_config` |
| `decommission-tserver.yml` | Safely remove tserver nodes by draining tablets first |
