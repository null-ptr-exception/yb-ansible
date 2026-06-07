# xCluster Molecule Scenario Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refactor the `xcluster` Molecule scenario to use standard groups (`masters`, `tservers`) and rename the single VM node to `yb-node`.

**Architecture:** Change platform name to `yb-node` and assign it to groups `masters` and `tservers`. Update playbooks `converge.yml` and `verify.yml` to target `hosts: all` (or specific groups), enabling automatic derivation of `yb_master_addresses` from the standard groups.

**Tech Stack:** Ansible, Molecule, YAML

---

### Task 1: Refactor `xcluster` Molecule Configuration

**Files:**
- Modify: `molecule/xcluster/molecule.yml`

- [ ] **Step 1: Update platform name and groups**

  Modify the file `/home/zx1986/Projects/yb-ansible/molecule/xcluster/molecule.yml` to change the platform name to `yb-node` and set its groups to `masters` and `tservers`:
  ```yaml
  platforms:
    - name: yb-node
      groups:
        - masters
        - tservers
      vcpus: 2
      ram_mb: 4096
      disk_gb: 20
  ```

- [ ] **Step 2: Commit the configuration changes**

  Run:
  ```bash
  git add molecule/xcluster/molecule.yml
  git commit -m "refactor: rename platform to yb-node and map to masters and tservers groups"
  ```

---

### Task 2: Update xCluster converge playbook

**Files:**
- Modify: `molecule/xcluster/converge.yml`

- [ ] **Step 1: Target `hosts: all` in converge playbook**

  Modify the file `/home/zx1986/Projects/yb-ansible/molecule/xcluster/converge.yml` to change `hosts: xcluster_nodes` to `hosts: all` in both plays:
  ```yaml
  ---
  - name: Converge xCluster Setup
    hosts: all
    become: true
    vars:
      yb_replication_factor: 1
    tasks:
      # ...

  - name: Establish Replication
    hosts: all
    run_once: true
    vars:
      yb_admin_path: /opt/yugabyte/bin/yb-admin
      xcluster_source_masters: "{{ ansible_host }}:7100"
      xcluster_target_masters: "{{ ansible_host }}:7101"
      xcluster_databases:
        - name: yugabyte
          type: ysql
    roles:
      - yb-xcluster
  ```

- [ ] **Step 2: Commit the converge playbook changes**

  Run:
  ```bash
  git add molecule/xcluster/converge.yml
  git commit -m "refactor: target hosts all in xcluster converge playbook"
  ```

---

### Task 3: Update xCluster verify playbook

**Files:**
- Modify: `molecule/xcluster/verify.yml`

- [ ] **Step 1: Target `hosts: all` in verify playbook**

  Modify the file `/home/zx1986/Projects/yb-ansible/molecule/xcluster/verify.yml` to change `hosts: xcluster_nodes` to `hosts: all`:
  ```yaml
  ---
  - name: Verify xCluster Replication
    hosts: all
    tasks:
      # ...
  ```

- [ ] **Step 2: Commit the verify playbook changes**

  Run:
  ```bash
  git add molecule/xcluster/verify.yml
  git commit -m "refactor: target hosts all in xcluster verify playbook"
  ```

---

### Task 4: Verify the changes

- [ ] **Step 1: Run xcluster Molecule tests**

  Run:
  ```bash
  export LIBVIRT_DEFAULT_URI=qemu:///system
  export MOLECULE_SSH_PUB_KEY="$(cat ~/.ssh/id_ed25519.pub)"
  export MOLECULE_SSH_IDENTITY_FILE="$HOME/.ssh/id_ed25519"
  export MOLECULE_CRANE_INSECURE="true"
  molecule test --scenario-name xcluster
  ```
  Expected: PASS

- [ ] **Step 2: Verify git status is clean**

  Run: `git status`
  Expected: clean working directory.
