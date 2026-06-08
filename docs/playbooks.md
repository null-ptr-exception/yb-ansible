# Playbooks

## Overview

| Playbook | Purpose | Execution |
|---|---|---|
| `playbooks/deploy.yml` | Day 1 fresh install, day 2 add tservers | Parallel |
| `playbooks/upgrade.yml` | Version upgrades and config changes | Rolling (serial: 1) |
| `playbooks/restart.yml` | Rolling restart without config changes | Rolling (serial: 1) |
| `playbooks/verify.yml` | Read-only health check | Parallel |
| `playbooks/xcluster.yml` | Setup xCluster replication between universes | Admin host |
| `playbooks/snapshot.yml` | Create a distributed YSQL snapshot | Admin host |
| `playbooks/backup.yml` | Backup a snapshot to an S3-compatible target | Mixed |
| `playbooks/restore.yml` | Restore a backup from an S3-compatible target | Mixed |
| `playbooks/clean.yml` | Stop services and wipe data dirs for redeploy | Parallel |

## playbooks/deploy.yml

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
├─ common: create yugabyte user/group, install directory, ship s5cmd binary
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

## playbooks/upgrade.yml

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

## playbooks/restart.yml

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

## playbooks/verify.yml

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
ansible-playbook -i inventory.ini playbooks/verify.yml
```

## playbooks/xcluster.yml

Configures asynchronous xCluster replication between two independent YugabyteDB
universes.

### Workflow

```
Admin host (`yb_admin_delegate_host` or first master)
│
├─ Build or use the stable replication ID (`xcluster_repl_id`)
├─ Resolve source Table IDs for specified databases and optional table allowlists
├─ Run setup_universe_replication on target cluster
└─ Poll get_replication_status until status output is healthy and error-free
```

### Usage

```bash
ansible-playbook -i inventory.ini playbooks/xcluster.yml \
  -e "xcluster_source_masters=10.0.0.1:7100,10.0.0.2:7100" \
  -e "xcluster_target_masters=10.0.0.4:7100,10.0.0.5:7100" \
  -e "xcluster_repl_id=prod_yugabyte_repl" \
  -e '{"xcluster_databases": [{"name": "yugabyte", "type": "ysql", "tables": ["orders", "customers"]}]}'
```

If `xcluster_repl_id` is omitted, the role derives a stable ID from
`xcluster_id_prefix` and the database names. Omit `tables` to replicate all
non-system tables in a database.

## playbooks/snapshot.yml

Creates a distributed YSQL database snapshot.

### Workflow

```
Admin host (`yb_admin_delegate_host` or first master)
│
├─ Create database snapshot via yb-admin
├─ Extract Snapshot ID from output
└─ Wait for snapshot state to reach COMPLETE
```

### Usage

```bash
ansible-playbook -i inventory.ini playbooks/snapshot.yml -e "yb_master_addresses=10.0.0.1:7100"
```

## playbooks/backup.yml

Backs up a YSQL snapshot to an S3-compatible target (e.g., MinIO or AWS S3).
Metadata is exported from the configured admin master, while tablet data is
shipped directly from tservers to the target to avoid controller bottlenecks.

### Workflow

```
Admin master (`yb_admin_delegate_host`)
│
├─ Create fresh database snapshot (imports yb-snapshot)
├─ Export snapshot metadata to temp directory
└─ Upload metadata to S3-compatible target
│
▼
Tservers (parallel)
│
├─ Find snapshot directories on local disk
└─ Upload tablet data directly to S3-compatible target
```

Backups are stored under `s3://<yb_backup_minio_bucket>/<yb_snapshot_id>/`.
The metadata object is `metadata/metadata.snapshot`; tablet data is stored
under `data/<tserver-hostname>/`.

### Usage

```bash
ansible-playbook playbooks/backup.yml \
  -e "yb_master_addresses=10.0.0.1:7100" \
  -e "yb_backup_minio_endpoint=http://minio:9000" \
  -e "yb_backup_minio_access_key=minioadmin" \
  -e "yb_backup_minio_secret_key=minioadmin" \
  -e "yb_backup_minio_bucket=yb-backups"
```

## playbooks/restore.yml

Restores a YSQL backup from an S3-compatible target to a YugabyteDB cluster.
Handles metadata import and coordinate data relocation on tservers.

### Workflow

```
Admin master (`yb_admin_delegate_host`)
│
├─ Download metadata from S3-compatible target
├─ Import snapshot into target cluster
└─ Extract ID and table/tablet mappings
│
▼
Tservers (parallel)
│
├─ Mirror data from S3-compatible target to temp directory
└─ Relocate data to final tablet snapshot directories (mapping applied)
│
▼
Admin master (`yb_admin_delegate_host`)
│
└─ Restore snapshot via yb-admin
```

### Usage

```bash
ansible-playbook playbooks/restore.yml \
  -e "yb_master_addresses=10.0.0.4:7100" \
  -e "yb_snapshot_id=<source-snapshot-id>" \
  -e "yb_restore_source_hostname=<source-tserver-hostname>" \
  -e "yb_backup_minio_endpoint=http://minio:9000" \
  -e "yb_backup_minio_access_key=minioadmin" \
  -e "yb_backup_minio_secret_key=minioadmin" \
  -e "yb_backup_minio_bucket=yb-backups" \
  -e "yb_tserver_data_dir=/data/yugabyte/tserver"
```

## playbooks/clean.yml

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
ansible-playbook -i inventory.ini playbooks/clean.yml
```

After clean, run `playbooks/deploy.yml` to redeploy. Packages and binaries are still
in place, so no image pull or file transfer is needed.

## Future Playbooks

| Playbook | Purpose |
|---|---|
| `playbooks/replace-master.yml` | Replace a failed master node at a different IP using `yb-admin change_master_config` |
| `playbooks/decommission-tserver.yml` | Safely remove tserver nodes by draining tablets first |
