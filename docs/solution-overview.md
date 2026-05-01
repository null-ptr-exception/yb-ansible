# Solution Overview

## Purpose

Ansible playbooks for deploying and managing YugabyteDB on Linux VMs.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Ansible Controller                        │
│                                                             │
│  crane export ──►  .cache/packages/  ──►  push to nodes    │
│  (OCI images)      (local cache)          (copy/unarchive)  │
└──────────────────────┬──────────────────────────────────────┘
                       │ SSH
           ┌───────────┼───────────────┐
           ▼           ▼               ▼
      ┌─────────┐ ┌─────────┐    ┌─────────┐
      │ master  │ │ tserver  │    │ tserver  │
      │ node    │ │ node 1   │    │ node N   │
      │         │ │          │    │          │
      │ common  │ │ common   │    │ common   │
      │ node-exp│ │ node-exp │    │ node-exp │
      │ yb-build│ │ yb-build │    │ yb-build │
      │ yb-mstr │ │ yb-tsvr  │    │ yb-tsvr  │
      └─────────┘ └─────────┘    └─────────┘
```

In production, masters and tservers run on separate VMs. Single-node
(colocated master + tserver) is supported for development and testing.

## Package Distribution (Push Mode)

The controller pulls OCI images, extracts binaries/tarballs locally, and
pushes them to nodes. Target nodes do not need crane or registry access.

```
OCI Registry
    │
    ▼ crane export (controller only, once)
.cache/packages/<product>/<version>/
    │
    ▼ ansible copy/unarchive (to each node)
/opt/packages/<product>/<version>/
    │
    ▼ extract or symlink
/opt/yugabyte/          (YB tarball extracted here)
/opt/node-exporter/     (symlink to package dir)
```

This approach:
- Works in air-gapped environments (controller pulls from a private registry)
- Only the controller needs registry credentials — nodes need nothing
- Caches packages on both the controller and each node for reinstalls
- Only crane (single static binary) is needed on the controller, no container runtime required

A pre-built **controller image** (`controller/Dockerfile`) packages Ansible,
crane, and common network tools into a single Docker image. This is useful for
running playbooks from a K8s pod or CI environment without installing
dependencies on the host.

### OCI Shipper Image

The YugabyteDB tarball is distributed via a minimal `scratch`-based OCI image
("YB shipper") containing only `/tarball/yugabyte.tar.gz`. Built via
`shipper/Dockerfile` and published to GHCR via GitHub Actions.

## Roles

| Role | Responsibility |
|---|---|
| `common` | Create yugabyte user/group and install directory |
| `node-exporter` | Install Prometheus node-exporter binary, run as systemd service (port 9200) |
| `yb-build` | Ship and extract YugabyteDB tarball, run `post_install.sh` |
| `yb-master` | Deploy a YB master instance as a systemd service |
| `yb-tserver` | Deploy a YB tserver instance as a systemd service |

### node-exporter

- Controller extracts binary from `prom/node-exporter` OCI image
- Binary shipped to `/opt/packages/node-exporter/<version>/` on each node
- Symlinked to `/opt/node-exporter/node_exporter`
- Runs on port 9200 (avoids conflict with yb-tserver RPC default 9100)

### yb-build

- Controller extracts tarball from the YB shipper OCI image
- Tarball shipped to `/opt/packages/yugabytedb/<version>/` on each node
- Extracted to `/opt/yugabyte/` with `--strip-components=1`
- Runs `bin/post_install.sh` to rewrite hardcoded library paths via `patchelf`
- Idempotent: `.post_install_done` marker prevents re-running

### yb-master

- Creates data directory at `yb_data_dir`
- `--master_addresses` auto-derived from the `masters` inventory group
- Configures `--replication_factor`, bind addresses
- Installs and starts systemd service

### yb-tserver

- Creates data directory at `yb_data_dir`
- Connects to masters via `--tserver_master_addrs` (auto-derived)
- YSQL proxy on port 5433 (configurable via `db_port`)
- Supports arbitrary gflags via `yb_tserver_flags`
- Installs and starts systemd service

## Verification

Two complementary layers:

### Role verify tasks

Each role includes `verify.yml` that runs at the end of deployment.
If verification fails, deployment fails immediately.

- **yb-build** — binary exists, version matches `yb_shipper_tag`
- **node-exporter** — port listening, `/metrics` returns 200
- **yb-master** — RPC/web ports listening, master API returns LEADER/FOLLOWER roles
- **yb-tserver** — RPC/YSQL ports listening, health-check API returns 200, `SELECT 1` succeeds

### Standalone verify.yml playbook

Read-only playbook for on-demand health checks. Performs cluster-level assertions:

- Cluster has exactly one LEADER master
- All inventory masters are present in the cluster
- All tservers are ALIVE in the master's tablet-server list

```bash
ansible-playbook -i inventory.ini verify.yml
```

## Supported Platforms

- Ubuntu 22.04 LTS
