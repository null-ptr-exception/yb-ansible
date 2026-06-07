# Design Specification: Backup-Restore Molecule Scenario Refactor

## 1. Overview
The current `molecule/default/verify.yml` playbook contains too many responsibilities, blending basic cluster verification with snapshot, backup, and restore verification tests. This design refactors those responsibilities by moving the snapshot, backup, and restore integration tests to a dedicated Molecule scenario named `backup-restore`.

## 2. Directory Structure and Symlinks
To keep the Molecule configuration DRY (Don't Repeat Yourself) and avoid duplicating VM provisioning logic, we will symlink the default lifecycle playbooks in `molecule/backup-restore/` pointing back to `molecule/default/`:

```
molecule/backup-restore/
├── cleanup.yml -> ../default/cleanup.yml
├── create.yml -> ../default/create.yml
├── destroy.yml -> ../default/destroy.yml
├── tasks -> ../default/tasks
├── converge.yml -> ../default/converge.yml
├── molecule.yml
└── verify.yml
```

## 3. Configuration

### 3.1. `molecule/backup-restore/molecule.yml`
This file will be created to configure the exact same 3-master + 1-tserver VM topology as `default`:

```yaml
---
driver:
  name: default
platforms:
  - name: master-1
    groups:
      - masters
    vcpus: 1
    ram_mb: 1024
    disk_gb: 10
  - name: master-2
    groups:
      - masters
    vcpus: 1
    ram_mb: 1024
    disk_gb: 10
  - name: master-3
    groups:
      - masters
    vcpus: 1
    ram_mb: 1024
    disk_gb: 10
  - name: tserver-1
    groups:
      - tservers
    vcpus: 2
    ram_mb: 1024
    disk_gb: 20
provisioner:
  name: ansible
  inventory:
    group_vars:
      all:
        ansible_user: centos
        ansible_python_interpreter: /usr/bin/python3
        yb_shipper_registry: ${MOLECULE_YB_SHIPPER_REGISTRY:-ghcr.io}
        node_exporter_registry: ${MOLECULE_NODE_EXPORTER_REGISTRY:-docker.io}
        crane_insecure: ${MOLECULE_CRANE_INSECURE:-false}
        yb_replication_factor: 1
  env:
    LIBVIRT_DEFAULT_URI: ${LIBVIRT_DEFAULT_URI:-qemu:///system}
    ANSIBLE_ROLES_PATH: ${MOLECULE_PROJECT_DIRECTORY}/roles
  config_options:
    ssh_connection:
      ssh_args: -o UserKnownHostsFile=${MOLECULE_PROJECT_DIRECTORY}/.vms/known_hosts
verifier:
  name: ansible
```

---

## 4. Playbook Reorganization

### 4.1. Clean Up `molecule/default/verify.yml`
We will remove the plays:
* `Verify snapshot role` (lines 228-274)
* `Verify backup and restore roles` (lines 275-418)

It will only contain tasks up to line 227 to check the cluster, node-exporter, and YSQL connectivity.

### 4.2. Create `molecule/backup-restore/verify.yml`
We will create this file to contain:
* Seeding snapshot test data in `yugabyte` database.
* Running the `yb-snapshot` role and verifying the snapshot is created.
* Seeding backup test data.
* Starting MinIO in the background on `master-1`.
* Running `yb-backup` to back up to S3/MinIO.
* Dropping the test table to simulate database data loss.
* Pre-creating the empty schema on the target cluster.
* Running `yb-restore` to restore data from MinIO.
* Running queries to verify data was successfully restored.
* Stopping MinIO and performing cleanup.

---

## 5. Verification Plan
To verify the success of the refactoring:
1. Run `molecule test --scenario-name default` to ensure the default scenario passes (verifying basic deployment health).
2. Run `molecule test --scenario-name backup-restore` to ensure the backup/restore integration test runs and passes successfully.
