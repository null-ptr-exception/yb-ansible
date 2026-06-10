# yb-ansible

Ansible playbooks for deploying YugabyteDB on RHEL-compatible Linux VMs (CentOS 7 / RHEL 7).

## Requirements

**Controller (where you run Ansible):**

- Python 3.12+
- Ansible Core 2.16
- Molecule (for local test scenarios)
- [crane](https://github.com/google/go-containerregistry/tree/main/cmd/crane) — used to extract packages from OCI images before pushing to nodes

Or use the pre-built [controller image](#controller-image) which includes all dependencies.

**Target nodes:**

- CentOS 7 / RHEL 7
- SSH access with sudo privileges

## Quick Start

### Option A: Using the controller image

```bash
docker run --rm -it \
  -v "$PWD:/ansible" \
  -v "$HOME/.ssh:/root/.ssh:ro" \
  ghcr.io/<owner>/yb-ansible-controller:latest \
  bash
```

Then inside the container:

```bash
cp inventory.example.ini inventory.ini
# Edit inventory.ini with your host IPs
ansible-playbook -i inventory.ini playbooks/deploy.yml
```

### Option B: Local install

1. Install prerequisites and set up the Python environment:

```bash
# crane is required on the controller to extract files from OCI images
CRANE_VERSION=0.21.5
curl -sL "https://github.com/google/go-containerregistry/releases/download/v${CRANE_VERSION}/go-containerregistry_Linux_x86_64.tar.gz" | sudo tar -xzf - -C /usr/local/bin crane

python3 -m venv .venv
source .venv/bin/activate
pip install 'ansible-core>=2.16,<2.17' molecule
```

2. Create your inventory:

```bash
cp inventory.example.ini inventory.ini
# Edit inventory.ini with your host IPs
```

3. Deploy:

```bash
ansible-playbook -i inventory.ini playbooks/deploy.yml
```

### Option C: Docker Compose Sandbox (Local Testing)

For local development and testing without provisioning actual VMs, a Docker Compose environment is provided. It spins up:
- **`source` universe** (`source-master` and `source-tserver` containers)
- **`target` universe** (`target-master` and `target-tserver` containers)
- **`minio`** (an S3-compatible storage service for backup/restore targets)
- **`ansible-controller`** (pre-configured with Ansible, crane, yq, s5cmd, MinIO, and network dependencies)

1. **Start the sandbox**:
   ```bash
   docker-compose up -d
   # Wait ~30s for the universes and MinIO to be ready
   ```

2. **Run automated verification tests** inside the controller container:
   * **xCluster Replication Test**:
     ```bash
     docker exec ansible-controller ./tests/verify_docker_xcluster.sh
     ```
   * **Backup & Restore Test**:
     ```bash
     docker exec ansible-controller ./tests/verify_backup_restore.sh
     ```

3. **Shut down and wipe data**:
   ```bash
   docker-compose down -v
   ```

## Inventory

Define two host groups — `masters` and `tservers`:

```ini
[masters]
10.0.0.1 ansible_user=centos
10.0.0.2 ansible_user=centos
10.0.0.3 ansible_user=centos

[tservers]
10.0.0.4 ansible_user=centos
10.0.0.5 ansible_user=centos
10.0.0.6 ansible_user=centos
```

In production, masters and tservers should run on separate VMs.

## Playbooks

| Playbook | Purpose |
|---|---|
| `playbooks/site.yml` | Basic deploy path without the stricter day-2 pre-flight checks |
| `playbooks/deploy.yml` | Day 1 fresh install, day 2 add tservers |
| `playbooks/upgrade.yml` | Version upgrades and config changes (rolling restart) |
| `playbooks/restart.yml` | Rolling restart without config changes |
| `playbooks/xcluster.yml` | Setup xCluster replication between universes |
| `playbooks/snapshot.yml` | Create and manage YSQL database snapshots |
| `playbooks/backup.yml` | Distributed YSQL backup to S3/MinIO |
| `playbooks/restore.yml` | Distributed YSQL restore from S3/MinIO |
| `playbooks/verify.yml` | Comprehensive health checks (services, ports, cluster state) |
| `playbooks/clean.yml` | Stop services, remove units, wipe data dirs |

`deploy.yml` includes pre-flight checks (master count validation, cluster membership verification) and will reject config or version changes on running nodes — use `upgrade.yml` for those.

See [docs/playbooks.md](docs/playbooks.md) for detailed behavior and safety checks.

## Roles

### common

Sets up shared prerequisites on all nodes:

- **yugabyte user/group** — system account for running YB processes
- **s5cmd binary** — uses `/usr/local/bin/s5cmd` on the controller when present, otherwise downloads and caches `s5cmd`, then ships it to nodes for backup and restore tasks

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

### yb-xcluster

Sets up transactional xCluster replication between independent YB universes:
- Uses a stable, overridable replication ID (`xcluster_repl_id`).
- The configured admin host resolves source table IDs for the selected databases and optional per-database table allowlists.
- Connects source and target masters, configures transactional xCluster replication, and checks `yb-admin get_replication_status`.

### yb-snapshot

Manages distributed YSQL database snapshots:
- Initiates YSQL snapshots via `yb-admin`.
- Polls and waits for snapshot state to reach `COMPLETE`.

### yb-backup

Orchestrates distributed backups of YSQL database snapshots to S3/MinIO:
- Imports `yb-snapshot` on the configured admin master to create a fresh snapshot.
- Exports snapshot metadata from the configured admin master to the S3-compatible target.
- TServers locate local snapshot directories and mirror tablet data in parallel directly to the target.

### yb-restore

Restores database snapshots from S3/MinIO:
- Downloads metadata to the configured admin master and imports snapshot structure into the target cluster.
- Maps old-to-new table/tablet IDs.
- TServers mirror tablet data in parallel from the S3/MinIO target.
- Runs the restore from the configured admin master and waits for completion.

## Configuration

Override variables in `group_vars/`, `host_vars/`, or via `-e` flags.

Key variables:

| Variable | Default | Description |
|---|---|---|
| `yb_shipper_tag` | `2.20.11.1` | YugabyteDB version |
| `yb_shipper_image` | `ghcr.io/.../yb-shipper:{{ yb_shipper_tag }}` | OCI image containing the YB tarball |
| `yb_install_dir` | `/opt/yugabyte` | YugabyteDB installation directory |
| `yb_data_dir` | `/data/yugabyte` | YugabyteDB data directory |
| `yb_replication_factor` | `3` | Replication factor |
| `yb_tserver_flags` | `{}` | Additional tserver gflags |
| `node_exporter_tag` | `v1.11.1-distroless` | Node-exporter image tag |
| `node_exporter_port` | `9200` | Node-exporter listen port |
| `xcluster_source_masters` | `""` | Source cluster master addresses for xCluster |
| `xcluster_target_masters` | `""` | Target cluster master addresses for xCluster |
| `xcluster_id_prefix` | `repl` | Prefix used when deriving the default xCluster replication ID |
| `xcluster_repl_id` | derived from database names | Stable xCluster replication ID; override to use a fixed external name |
| `xcluster_databases` | `[]` | Databases to replicate; each entry supports `name`, `type`, and optional `tables` allowlist |
| `yb_snapshot_db` | `yugabyte` | Target YSQL database name for snapshot/backup |
| `yb_backup_minio_endpoint` | `""` | S3/MinIO endpoint for backup and restore |
| `yb_backup_minio_access_key` | `""` | S3/MinIO access key |
| `yb_backup_minio_secret_key` | `""` | S3/MinIO secret key |
| `yb_backup_minio_bucket` | `yb-backups` | Bucket used for snapshot metadata and tablet data |
| `yb_restore_source` | `minio` | Source storage type for restore (`minio` or `local`) |
| `yb_restore_source_hostname` | `{{ inventory_hostname }}` | Source host to map data from during restore |

### Adding tserver gflags

```yaml
yb_tserver_flags:
  yb_num_shards_per_tserver: 2
  ysql_num_shards_per_tserver: 2
```

## Controller Image

A pre-built Docker image with all controller dependencies (Ansible, crane, yq,
s5cmd, MinIO client/server, SSH, and common network tools). Useful
for running playbooks from a K8s pod or any environment where you don't want to
install tools locally.

```bash
docker build -t yb-ansible-controller controller/
```

The image is also published to GHCR on every push to `main` that changes
`controller/`.



## Development

### Prerequisites

The Molecule scenarios use **libvirt + QEMU on Linux**. The same environment is
used for both CI (self-hosted Linux runner) and local development. On macOS, use
[Lima](https://lima-vm.io/) to get an identical Linux environment.

#### Linux (CI / native)

```bash
# libvirt and VM tools (Fedora/RHEL)
sudo dnf install -y qemu-kvm libvirt virt-install genisoimage

# ensure your user can manage VMs
sudo usermod -aG libvirt $USER
# (log out and back in for group change to take effect)

# verify the default network is active
virsh net-list --all
# if not: virsh net-start default

# Python dependencies
python3 -m venv .venv
source .venv/bin/activate
pip install 'ansible-core>=2.16,<2.17' molecule
```

#### macOS (via Lima)

Lima runs a Linux VM on macOS with full libvirt support. The Molecule scenarios
run inside Lima and match CI.

```bash
# 1. Install Lima
brew install lima

# 2. Start a Fedora Lima instance with libvirt
limactl start --name=yb-dev template://fedora

# 3. Enter the Lima VM
limactl shell yb-dev

# 4. Inside Lima: install required packages
sudo dnf install -y qemu-kvm libvirt virt-install genisoimage python3

# 5. Enable libvirt and activate the default NAT network
sudo systemctl enable --now libvirtd
sudo virsh net-autostart default
sudo virsh net-start default   # if not already active

# 6. Allow your user to manage VMs
sudo usermod -aG libvirt $USER
# Re-enter the Lima shell for the group to take effect:
exit && limactl shell yb-dev

# 7. Navigate to the project (Lima mounts your macOS home automatically)
cd ~/Projects/null-ptr-exception/yb-ansible

# 8. Set up Python environment and run tests
python3 -m venv .venv
source .venv/bin/activate
pip install 'ansible-core>=2.16,<2.17' molecule
molecule test -s default
```

> **Note:** All molecule commands must be run **inside the Lima shell**,
> not from the macOS terminal.

### Molecule test lifecycle

Activate the project virtualenv before running any Ansible or Molecule command:

```bash
source .venv/bin/activate
```

Molecule manages local libvirt VMs with snapshot caching for fast iteration.
The active scenarios are:

- `default` — deploy, idempotence, read-only verify, and clean validation.
- `xcluster` — source/target universes with transactional xCluster setup and status checks.
- `backup-restore` — snapshot backup and restore against an isolated `minio-1` object-storage VM.

Local runs need an SSH key pair exported for VM access:

```bash
export MOLECULE_SSH_PUB_KEY="$(cat ~/.ssh/id_ed25519.pub)"
export MOLECULE_SSH_IDENTITY_FILE="$HOME/.ssh/id_ed25519"

molecule test -s default
molecule test -s xcluster
molecule test -s backup-restore
```

The common lifecycle commands accept `-s <scenario>`:

```bash
molecule test -s default      # full cycle: create, converge, idempotence, verify, destroy
molecule create -s default    # provision VMs only, or revert to snapshot
molecule converge -s default  # run the scenario converge playbook
molecule verify -s default    # run verification checks
molecule destroy -s default   # shut down VMs, preserve snapshots for next run
```

First `molecule create` builds VMs from scratch and takes a `clean-base` snapshot after cloud-init completes. Subsequent runs revert to the snapshot instead of recreating. The `backup-restore` scenario also creates a small `minio-1` VM that is excluded from YugabyteDB deployment and used only as temporary object storage.

To fully destroy VMs and snapshots:

```bash
MOLECULE_FULL_DESTROY=true molecule destroy -s default
```

### Running all tests

```bash
make test              # run all tests (controller image + ordered molecule scenarios)
make test-controller   # build and verify the controller image only
make test-molecule     # run default, xcluster, and backup-restore scenarios
make help              # list all targets
```

To run one or more selected scenarios through the Makefile:

```bash
MOLECULE_SCENARIOS="xcluster" make test-molecule
MOLECULE_SCENARIOS="default backup-restore" make test-molecule
```

GitHub CI runs the same ordered Molecule scenario runner on the self-hosted
libvirt runner. The runner executes scenarios serially, stops at the first
failure, runs Molecule cleanup for the failed scenario, and prints a timing
summary for completed and failed scenarios.

### Manual testing with molecule VMs

`molecule create` writes a `.vms/inventory` file for running playbooks directly:

```bash
molecule create -s default
ansible-playbook -i .vms/inventory playbooks/deploy.yml
ansible-playbook -i .vms/inventory playbooks/upgrade.yml
molecule destroy -s default && molecule create -s default    # reset to clean OS
```

## Supported Platforms

- CentOS 7 / RHEL 7
