# yb-ansible

Ansible playbooks for deploying YugabyteDB on Ubuntu Linux VMs.

## Requirements

**Controller (where you run Ansible):**

- Python 3.12+
- Ansible
- podman — used to pull OCI shipper images and extract packages locally before pushing to nodes

**Target nodes:**

- Ubuntu 22.04 LTS
- SSH access with sudo privileges

## Quick Start

1. Install prerequisites and set up the Python environment:

```bash
# podman is required on the controller to pull and extract OCI images
sudo apt install -y podman

python3 -m venv .venv
source .venv/bin/activate
pip install ansible
```

2. Create your inventory:

```bash
cp inventory.example.ini inventory.ini
# Edit inventory.ini with your host IPs
```

3. Deploy:

```bash
ansible-playbook -i inventory.ini deploy.yml
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

## Playbooks

| Playbook | Purpose |
|---|---|
| `deploy.yml` | Day 1 fresh install, day 2 add tservers |
| `upgrade.yml` | Version upgrades and config changes (rolling restart) |
| `restart.yml` | Rolling restart without config changes |
| `clean.yml` | Stop services, remove units, wipe data dirs |

`deploy.yml` includes pre-flight checks (master count validation, cluster membership verification) and will reject config or version changes on running nodes — use `upgrade.yml` for those.

See [docs/playbooks.md](docs/playbooks.md) for detailed behavior and safety checks.

## Roles

### common

Sets up shared prerequisites on all nodes:

- **yugabyte user/group** — system account for running YB processes

### node-exporter

Installs Prometheus node-exporter on all nodes:

- Controller pulls the `prom/node-exporter` OCI image and extracts the binary
- Binary shipped to `/opt/packages/node-exporter/<version>/` on each node
- Symlinked to `/opt/node-exporter/node_exporter`
- Runs as a systemd service on port 9200 (avoids conflict with yb-tserver RPC default 9100)

### yb-build

Downloads and installs YugabyteDB on all nodes:

- Controller pulls the OCI shipper image and extracts the tarball
- Tarball shipped to `/opt/packages/yugabytedb/<version>/` on each node
- Extracted to `/opt/yugabyte/`
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
| `yb_shipper_tag` | `2025.2.2.2` | YugabyteDB version |
| `yb_shipper_image` | `ghcr.io/.../yb-shipper:{{ yb_shipper_tag }}` | OCI image containing the YB tarball |
| `yb_install_dir` | `/opt/yugabyte` | YugabyteDB installation directory |
| `yb_data_dir` | `/data/yugabyte` | YugabyteDB data directory |
| `yb_replication_factor` | `3` | Replication factor |
| `yb_tserver_flags` | `{}` | Additional tserver gflags |
| `node_exporter_tag` | `v1.11.1-distroless` | Node-exporter image tag |
| `node_exporter_port` | `9200` | Node-exporter listen port |

### Adding tserver gflags

```yaml
yb_tserver_flags:
  yb_num_shards_per_tserver: 2
  ysql_num_shards_per_tserver: 2
```

## Development

### Prerequisites

Ubuntu dev machine with libvirt and Python tooling:

```bash
# libvirt and VM tools
sudo apt install -y qemu-kvm libvirt-daemon-system virtinst genisoimage

# ensure your user can manage VMs
sudo usermod -aG libvirt $USER
# (log out and back in for group change to take effect)

# verify the default network is active
virsh net-list --all
# if not: virsh net-start default

# Python dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install ansible molecule
```

### Molecule test lifecycle

Molecule manages local libvirt VMs (3 masters + 1 tserver) with snapshot caching for fast iteration:

```bash
molecule test          # full cycle: create → converge → idempotence → verify → destroy
molecule create        # provision VMs only (or revert to snapshot, ~46s)
molecule converge      # run deploy.yml against the VMs
molecule verify        # run verification checks
molecule destroy       # shut down VMs, preserve snapshots for next run
```

First `molecule create` builds VMs from scratch and takes a `clean-base` snapshot after cloud-init completes. Subsequent runs revert to the snapshot instead of recreating.

To fully destroy VMs and snapshots:

```bash
MOLECULE_FULL_DESTROY=true molecule destroy
```

### Manual testing with molecule VMs

`molecule create` writes a `.vms/inventory` file for running playbooks directly:

```bash
molecule create
ansible-playbook -i .vms/inventory deploy.yml
ansible-playbook -i .vms/inventory upgrade.yml
molecule destroy && molecule create    # reset to clean OS
```

## Supported Platforms

- Ubuntu 22.04 LTS
