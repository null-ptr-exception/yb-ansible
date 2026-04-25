# yb-ansible: Ansible Playbooks for YugabyteDB on Linux

## Purpose

General-purpose Ansible playbooks for deploying YugabyteDB on Linux VMs.
No assumptions about benchmarking, monitoring backends, or workload tooling —
just the database and basic host observability.

## Project Structure

Plain repo of roles (not an Ansible Galaxy collection):

```
roles/
  common/
  node-exporter/
  yb-build/
  yb-master/
  yb-tserver/
site.yml
verify.yml
molecule/
inventory.ini
```

## Scope

Five roles:

| Role | Responsibility |
|---|---|
| `common` | Install shared prerequisites (podman, yugabyte user/group) |
| `node-exporter` | Install Prometheus node-exporter from OCI image as a systemd service |
| `yb-build` | Download and install YugabyteDB tarball via OCI shipper image, run `post_install.sh` |
| `yb-master` | Deploy a YB master instance as a systemd service |
| `yb-tserver` | Deploy a YB tserver instance as a systemd service |

### Out of scope (current phase)

- Benchmark tooling (k6, sysbench)
- Prometheus / Grafana / monitoring backends
- Kubernetes deployment (use the upstream Helm chart for that)
- Cloud-specific provisioning (VMs are assumed to exist)
- Upgrades / rolling restarts
- Placement info (`--placement_cloud`, `--placement_region`, `--placement_zone`)
- Multiple `--fs_data_dirs` for tserver

## Architecture

In production, masters and tservers run on separate VMs. Single-node
(colocated master + tserver) is supported for local development and
testing only.

```
┌─────────────────────────────────────────────────┐
│              Ansible Control Host                │
│                                                  │
│  ansible-playbook site.yml -i inventory.ini      │
└──────────────────┬───────────────────────────────┘
                   │ SSH
       ┌───────────┼───────────────┐
       ▼           ▼               ▼
  ┌─────────┐ ┌─────────┐    ┌─────────┐
  │ master  │ │ tserver  │    │ tserver  │
  │ node    │ │ node 1   │    │ node N   │
  │         │ │          │    │          │
  │ roles:  │ │ roles:      │    │ roles:      │
  │ common  │ │ common      │    │ common      │
  │ node-exp│ │ node-exp    │    │ node-exp    │
  │ yb-build│ │ yb-build    │    │ yb-build    │
  │ yb-master│ │ yb-tserver │    │ yb-tserver  │
  └─────────┘ └─────────┘    └─────────┘
```

### Role: common

Installs shared prerequisites on all nodes:

- **podman** — container runtime for OCI image handling. Lightweight
  and daemonless.
- **yugabyte user/group** — system account for running YB processes.

### Role: node-exporter

Installs Prometheus node-exporter from an OCI image:

- Pulls `prom/node-exporter:v1.11.1-distroless` via podman
- Extracts the binary to `/opt/node-exporter/`
- Installs as a systemd service on port 9200 (avoids conflict with
  yb-tserver RPC default 9100)

### Role: yb-build

Downloads and installs YugabyteDB on all nodes:

- Pulls the YB shipper OCI image (or loads from a pre-staged tar)
- Extracts the tarball to `yb_install_dir` (default `/opt/yugabyte`)
- Runs `./bin/post_install.sh` to fix library paths

#### post_install.sh

Ships inside the YB tarball at `bin/post_install.sh`. It uses `patchelf`
to rewrite hardcoded Linuxbrew library paths to match the actual
installation directory. Without it, YB binaries may fail to find shared
libraries at runtime.

- Must be run from the real (non-symlinked) install path
- Idempotent — the role creates a `.post_install_done` marker file after successful execution
- Must be re-run after upgrades

### Role: yb-master

Deploys one YB master instance per node:

- Creates data directory
- Installs systemd unit
- Configures `--master_addresses` (auto-generated from inventory),
  `--replication_factor`, bind addresses
- Starts and enables the service

`yb_master_addresses` is automatically derived from the `masters`
inventory group and `yb_master_rpc_port`, not manually specified.

Key variables:
```yaml
yb_master_rpc_port: 7100
yb_master_web_port: 7000
yb_replication_factor: 3
```

### Role: yb-tserver

Deploys one YB tserver instance per node:

- Creates data directory
- Installs systemd unit with configurable gflags
- Connects to masters via `--tserver_master_addrs` (auto-generated)
- Binds YSQL proxy on configurable port (default 5433)
- Starts and enables the service

Key variables:
```yaml
yb_tserver_flags:
  yb_num_shards_per_tserver: 2
  ysql_num_shards_per_tserver: 2
```

Additional flags are passed as key-value pairs and rendered into the
systemd ExecStart line.

## Post-Deployment Verification

Two complementary verification layers:

### Role verify tasks

Each role includes a `verify.yml` that runs at the end of deployment.
If verification fails, the deployment fails immediately.

- **node-exporter** — node-exporter listening and responding on configured port
- **yb-build** — YB binary exists at install path
- **yb-master** — RPC/web ports listening, master API returns LEADER/FOLLOWER roles
- **yb-tserver** — RPC/YSQL ports listening, health-check API returns 200, YSQL responds to `SELECT 1`

### Standalone verify.yml playbook

A read-only playbook for on-demand health checks (`ansible-playbook verify.yml`).
Performs deeper cluster-level assertions:

- Cluster has exactly one LEADER master
- All inventory masters are present in the cluster
- All tservers are ALIVE in the master's tablet-server list

## YugabyteDB Distribution

The playbooks use an OCI image ("YB shipper") to distribute the
YugabyteDB tarball. This approach:

- Works in air-gapped environments (pre-pull the image to a local registry)
- Avoids downloading multi-hundred-MB tarballs over the internet on each node
- Caches image layers so version upgrades are incremental
- Uses podman (rootless, daemonless) — no Docker required

The shipper image is built via `shipper/Dockerfile` and published to
GHCR via GitHub Actions (`.github/workflows/build-shipper.yml`).
The image contains only the YB tarball at `/tarball/yugabyte.tar.gz`.

## Credentials

No credentials are hardcoded in the playbooks or default variables.
Database credentials must be provided via a `.env` file or equivalent
mechanism that is gitignored. The repository includes a `.env.example`
template.

## Example Inventory

```ini
[masters]
10.0.0.1 ansible_user=ubuntu
10.0.0.2 ansible_user=ubuntu
10.0.0.3 ansible_user=ubuntu

[tservers]
10.0.0.4 ansible_user=ubuntu
10.0.0.5 ansible_user=ubuntu
10.0.0.6 ansible_user=ubuntu
```

## Example Playbook

```yaml
- hosts: all
  roles:
    - common
    - node-exporter
    - yb-build

- hosts: masters
  roles:
    - yb-master

- hosts: tservers
  roles:
    - yb-tserver
```

## Default Variables

```yaml
# YugabyteDB version and paths
yb_version: "2025.2.2.2"
yb_shipper_image: "ghcr.io/null-ptr-exception/yb-shipper:{{ yb_version }}-<git-sha>"
yb_install_dir: /opt/yugabyte
yb_data_dir: /data/yugabyte
yb_replication_factor: 3

# Node-exporter
node_exporter_version: "1.11.1"
node_exporter_image: "docker.io/prom/node-exporter:v{{ node_exporter_version }}-distroless"
node_exporter_port: 9200

# Ports
yb_master_rpc_port: 7100
yb_master_web_port: 7000
yb_tserver_rpc_port: 9100
yb_tserver_web_port: 9000
db_port: 5433
```

## Supported Platforms

- Ubuntu 22.04 LTS

## Future Work

- Placement info (cloud/region/zone) for multi-DC and rack-aware deployments
- Multiple `--fs_data_dirs` for tserver (multiple disks)
- Upgrades / rolling restart playbook
- Ansible Galaxy collection packaging
