# Playbooks

## Overview

Each playbook handles a distinct operational scenario. Roles are reusable building blocks (configure + ensure running); playbooks own the orchestration, verification, and restart strategy.

| Playbook | Purpose | Execution |
|---|---|---|
| `deploy.yml` | Day 1 fresh install, day 2 add tservers | Parallel |
| `upgrade.yml` | Version upgrades, config changes | Rolling (serial: 1) |
| `replace-master.yml` | Replace a failed master node | Sequential, uses `yb-admin` |
| `decommission-tserver.yml` | Remove tserver nodes | Sequential, drains tablets first |

## deploy.yml

For initial deployment and safe day-2 additions. All plays run in parallel (no `serial`).

### What it handles

- **Day 1 fresh install**: Deploy all masters and tservers from scratch.
- **Day 2 add tservers**: Add new tserver nodes to inventory and re-run. Existing nodes are unchanged (idempotent). New tservers heartbeat to the master leader and the cluster auto-rebalances tablets.
- **Day 2 idempotent re-run**: Same inventory, same config — no changes, no restarts.

### Safety checks

- **Master count validation (static)**: `groups['masters'] | length` must be odd (1, 3, 5, 7). Fails immediately if even or zero.
- **Master membership validation (runtime)**: If any master is already responding, query `/api/v1/masters` and compare cluster membership against inventory. Fail on mismatch — master changes require `replace-master.yml`.
- **Config change detection**: If a running node would receive config changes that trigger a handler restart, fail early. Config changes on running nodes belong in `upgrade.yml`.

### What it does NOT handle

- Adding or removing master nodes (master count is fixed to RF, set at cluster creation).
- Config changes on existing nodes (requires rolling restart).
- Version upgrades (requires rolling restart).

## upgrade.yml

For rolling restarts: version upgrades and config changes on existing nodes. Uses `serial: 1` to process one node at a time.

### Procedure

Following [YugabyteDB upgrade docs](https://docs.yugabyte.com/stable/manage/upgrade-deployment/):

1. **Masters first** (one at a time):
   - Apply role (config + restart via handler)
   - Verify master health (RPC port, web UI, cluster status, RAFT role)
   - Pause 60s for cluster to stabilize before next master
2. **Tservers second** (one at a time):
   - Apply role (config + restart via handler)
   - Verify tserver health (RPC port, web UI, tablet server status)
   - Pause 60s for tablet load to rebalance before next tserver

### What it handles

- YugabyteDB version upgrades (new binary via `yb-build` role).
- Configuration changes on existing masters and tservers.

## replace-master.yml (future)

For replacing a failed master node with a new one at a different IP.

### Procedure

1. Start new master process on replacement node.
2. `yb-admin change_master_config ADD_SERVER <new_ip> <port>` — temporarily 4 members.
3. `yb-admin change_master_config REMOVE_SERVER <old_ip> <port>` — back to RF members.
4. Update `master_addresses` on all nodes to reflect new membership.

### Notes

- `change_master_config` changes RAFT group membership, not quorum size. RF stays the same.
- Master count must always equal RF (e.g., RF=3 means exactly 3 masters).

## decommission-tserver.yml (future)

For safely removing tserver nodes from the cluster.

### Notes

- Tablets must be drained from the node before stopping it.
- The cluster rebalances remaining tablets across other tservers.
- Distinct from simply stopping a tserver (which would leave under-replicated tablets).
