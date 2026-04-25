# yb-ansible

Ansible playbooks for deploying YugabyteDB on Ubuntu Linux VMs.

## Requirements

- Python 3.12+ (use [mise](https://mise.jdx.dev/) — `mise install`)
- Ubuntu 22.04 LTS target hosts
- SSH access to all target hosts with sudo privileges

## Quick Start

1. Set up the Python environment and install Ansible:

```bash
mise install
python -m venv .venv
source .venv/bin/activate
pip install ansible
```

2. Create your inventory and credentials:

```bash
cp inventory.example.ini inventory.ini
# Edit inventory.ini with your host IPs

cp .env.example .env
# Edit .env with your values
```

3. Run the playbook:

```bash
source .venv/bin/activate
ansible-playbook site.yml
```

## Inventory

Define two host groups — `masters` and `tservers`:

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

In production, masters and tservers should run on separate VMs.

## Roles

### common

Installs shared prerequisites on all nodes:

- **podman** — container runtime for OCI image handling
- **node-exporter** — host metrics via `prometheus-node-exporter`
- **yugabyte user/group** — system account for running YB processes

### yb-build

Downloads and installs YugabyteDB on all nodes:

- Pulls the OCI shipper image (or loads from a pre-staged tar)
- Extracts the YugabyteDB tarball from the image
- Runs `bin/post_install.sh` to fix library paths

### yb-master

Deploys one YB master per node as a systemd service. `master_addresses` is
auto-derived from the `masters` inventory group.

### yb-tserver

Deploys one YB tserver per node as a systemd service. Connects to masters
automatically. Supports arbitrary gflags via `yb_tserver_flags`.

## Configuration

Override variables in `group_vars/`, `host_vars/`, or via `-e` flags.

Key variables:

| Variable | Default | Description |
|---|---|---|
| `yb_version` | `2025.2.2.1` | YugabyteDB version |
| `yb_shipper_image` | `yb-shipper:{{ yb_version }}` | OCI image containing the YB tarball |
| `yb_install_dir` | `/opt/yugabyte` | Installation directory |
| `yb_data_dir` | `/data/yugabyte` | Data directory |
| `yb_replication_factor` | `3` | Replication factor |
| `yb_master_rpc_port` | `7100` | Master RPC port |
| `yb_master_web_port` | `7000` | Master web UI port |
| `yb_tserver_rpc_port` | `9100` | TServer RPC port |
| `yb_tserver_web_port` | `9000` | TServer web UI port |
| `db_port` | `5433` | YSQL proxy port |
| `yb_tserver_flags` | `{}` | Additional tserver gflags |

### Adding tserver gflags

```yaml
yb_tserver_flags:
  yb_num_shards_per_tserver: 2
  ysql_num_shards_per_tserver: 2
```

## Local Development VMs

For local testing, `.vms/create-vms.sh` creates 6 VMs using libvirt/virsh:

- 3 master VMs (1 vCPU, 512 MB RAM)
- 3 tserver VMs (2 vCPU, 4 GB RAM)

Requires an Ubuntu 22.04 cloud image at the path specified in the script.

```bash
bash .vms/create-vms.sh
```

After VMs are created, update `inventory.ini` with the assigned IPs.

## Supported Platforms

- Ubuntu 22.04 LTS
