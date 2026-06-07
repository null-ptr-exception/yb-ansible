# Backup-Restore Molecule Scenario Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move database snapshot, backup, and restore integration tests from the `default` Molecule scenario to a dedicated `backup-restore` scenario.

**Architecture:** Create a new `backup-restore` scenario directory and symlink its creation/cleanup playbooks to `default/`. Reorganize verify playbooks by extracting snapshot/backup/restore verification tests to `molecule/backup-restore/verify.yml` and leaving basic cluster health checks in `molecule/default/verify.yml`.

**Tech Stack:** Ansible, Molecule, YAML

---

### Task 1: Set up new Molecule scenario directory and symlinks

**Files:**
- Create: symlinks under `molecule/backup-restore/` pointing back to `molecule/default/`

- [ ] **Step 1: Create the directory and the required symlinks**

  Run these bash commands from the workspace root:
  ```bash
  mkdir -p molecule/backup-restore
  cd molecule/backup-restore
  ln -sf ../default/create.yml create.yml
  ln -sf ../default/destroy.yml destroy.yml
  ln -sf ../default/cleanup.yml cleanup.yml
  ln -sf ../default/converge.yml converge.yml
  ln -sf ../default/tasks tasks
  ```

- [ ] **Step 2: Run verification commands to check symlinks**

  Run: `ls -la molecule/backup-restore`
  Expected: All symlinks are present and point correctly to `../default/<filename>`.

- [ ] **Step 3: Commit the new symlinks**

  Run:
  ```bash
  git add molecule/backup-restore/create.yml molecule/backup-restore/destroy.yml molecule/backup-restore/cleanup.yml molecule/backup-restore/converge.yml molecule/backup-restore/tasks
  git commit -m "chore: symlink default scenario files to backup-restore scenario"
  ```

---

### Task 2: Configure the `backup-restore` Molecule scenario

**Files:**
- Create: `molecule/backup-restore/molecule.yml`

- [ ] **Step 1: Write `molecule/backup-restore/molecule.yml`**

  Create the file `/home/zx1986/Projects/yb-ansible/molecule/backup-restore/molecule.yml` with the following content:
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

- [ ] **Step 2: Commit the configuration**

  Run:
  ```bash
  git add molecule/backup-restore/molecule.yml
  git commit -m "chore: add backup-restore scenario molecule.yml configuration"
  ```

---

### Task 3: Create `backup-restore` verify playbook

**Files:**
- Create: `molecule/backup-restore/verify.yml`

- [ ] **Step 1: Write `molecule/backup-restore/verify.yml`**

  Create the file `/home/zx1986/Projects/yb-ansible/molecule/backup-restore/verify.yml` with the following content:
  ```yaml
  ---
  - name: Seed snapshot_test table in yugabyte database
    hosts: "{{ groups['tservers'][0] }}"
    gather_facts: false
    vars:
      yb_install_dir: /opt/yugabyte
      db_port: 5433
    tasks:
      - name: Seed snapshot_test table
        ansible.builtin.command:
          cmd: >-
            {{ yb_install_dir }}/bin/ysqlsh -h 127.0.0.1 -p {{ db_port }}
            -c "CREATE TABLE IF NOT EXISTS snapshot_test (id INT PRIMARY KEY, data TEXT);
            INSERT INTO snapshot_test VALUES (1, 'seed') ON CONFLICT DO NOTHING;"
        changed_when: false
        register: _seed_result
        retries: 18
        delay: 10
        until: _seed_result.rc == 0

  - name: Verify snapshot role
    hosts: "{{ groups['masters'][0] }}"
    become: false
    gather_facts: false
    vars:
      yb_admin_path: /opt/yugabyte/bin/yb-admin
      yb_snapshot_db: yugabyte
      yb_install_dir: /opt/yugabyte
      db_port: 5433
      yb_master_addresses: "{{ groups['masters'] | map('extract', hostvars, 'ansible_host') | join(',') }}"
    tasks:
      - name: Run snapshot role
        block:
          - name: Include yb-snapshot role
            ansible.builtin.include_role:
              name: yb-snapshot

          - name: Assert yb_snapshot_id was set
            ansible.builtin.assert:
              that:
                - yb_snapshot_id is defined
                - yb_snapshot_id | length > 0
              fail_msg: "yb_snapshot_id was not set by the role"
            when: yb_snapshot_id is defined

          - name: Verify snapshot exists in list_snapshots
            ansible.builtin.command:
              cmd: "{{ yb_admin_path }} -master_addresses {{ yb_master_addresses }} list_snapshots"
            register: _snapshots_list
            when: yb_snapshot_id is defined

          - name: Assert snapshot ID is in the list
            ansible.builtin.assert:
              that: yb_snapshot_id in _snapshots_list.stdout
              fail_msg: "Snapshot ID {{ yb_snapshot_id }} not found in list_snapshots output"
            when: yb_snapshot_id is defined

        rescue:
          - name: Debug snapshot role failure
            ansible.builtin.debug:
              msg: "yb-snapshot role failed. Check role output above for details."

          - name: Fail play on snapshot role failure
            ansible.builtin.fail:
              msg: "The yb-snapshot role execution failed. Failed task: {{ ansible_failed_task.name | default('unknown') }}. Error: {{ ansible_failed_result | default('none') }}"

  - name: Verify backup and restore roles
    hosts: all
    become: false
    gather_facts: false
    vars:
      yb_install_dir: /opt/yugabyte
      db_port: 5433
      yb_backup_minio_endpoint: "http://{{ hostvars[groups['masters'][0]]['ansible_host'] | default(groups['masters'][0]) }}:9000"
      yb_backup_minio_access_key: minioadmin
      yb_backup_minio_secret_key: minioadmin
      yb_restore_source_hostname: "{{ groups['tservers'][0] }}"
    tasks:
      - name: Clear yb_snapshot_id fact
        ansible.builtin.set_fact:
          yb_snapshot_id: null

      - block:
          - name: Create Minio data directory
            ansible.builtin.file:
              path: /tmp/minio_data
              state: directory
              mode: "0755"
            delegate_to: "{{ groups['masters'][0] }}"
            run_once: true
            become: true

          - name: Check if Minio exists on controller
            ansible.builtin.stat:
              path: /usr/local/bin/minio
            delegate_to: localhost
            run_once: true
            register: _minio_local

          - name: Copy Minio binary from controller
            ansible.builtin.copy:
              src: /usr/local/bin/minio
              dest: /usr/local/bin/minio
              mode: "0755"
            delegate_to: "{{ groups['masters'][0] }}"
            run_once: true
            become: true
            when: _minio_local.stat.exists

          - name: Download Minio binary to master if not on controller
            ansible.builtin.get_url:
              url: https://dl.min.io/server/minio/release/linux-amd64/minio
              dest: /usr/local/bin/minio
              mode: "0755"
            delegate_to: "{{ groups['masters'][0] }}"
            run_once: true
            become: true
            when: not _minio_local.stat.exists

          - name: Start Minio in the background
            ansible.builtin.shell:
              cmd: "nohup /usr/local/bin/minio server /tmp/minio_data --address ':9000' > /tmp/minio.log 2>&1 &"
            delegate_to: "{{ groups['masters'][0] }}"
            run_once: true
            become: true
            changed_when: true

          - name: Wait for Minio port 9000
            block:
              - name: Wait for Minio port 9000 (up to 90 seconds)
                ansible.builtin.wait_for:
                  port: 9000
                  host: 127.0.0.1
                  timeout: 90
                delegate_to: "{{ groups['masters'][0] }}"
                run_once: true
            rescue:
              - name: Check if Minio process is running
                ansible.builtin.command: pgrep -f "/usr/local/bin/minio server"
                delegate_to: "{{ groups['masters'][0] }}"
                run_once: true
                become: true
                register: _minio_pgrep
                failed_when: false

              - name: Retrieve Minio log on failure
                ansible.builtin.command: cat /tmp/minio.log
                delegate_to: "{{ groups['masters'][0] }}"
                run_once: true
                become: true
                register: _minio_log
                failed_when: false

              - name: Fail with detailed error message
                ansible.builtin.fail:
                  msg: |
                    Minio server failed to start or bind to port 9000 within 90 seconds.
                    Process status (pgrep output): {{ _minio_pgrep.stdout | default('Not running') }}
                    Last log lines from /tmp/minio.log:
                    {{ _minio_log.stdout | default('No log output found') }}

          - name: Seed test data for backup verification
            ansible.builtin.command:
              cmd: "{{ yb_install_dir }}/bin/ysqlsh -h 127.0.0.1 -p {{ db_port }} -c \"CREATE TABLE IF NOT EXISTS test_restore (id INT PRIMARY KEY, val TEXT); INSERT INTO test_restore VALUES (1, 'restore_verified') ON CONFLICT DO NOTHING;\""
            delegate_to: "{{ groups['tservers'][0] }}"
            run_once: true
            changed_when: true

          - name: Run backup role
            ansible.builtin.include_role:
              name: yb-backup
            run_once: false

          - name: Simulate data loss (Drop table)
            ansible.builtin.command:
              cmd: "{{ yb_install_dir }}/bin/ysqlsh -h 127.0.0.1 -p {{ db_port }} -c \"DROP TABLE test_restore;\""
            delegate_to: "{{ groups['tservers'][0] }}"
            run_once: true
            changed_when: true

          - name: Pre-create empty schema for restore
            ansible.builtin.command:
              cmd: "{{ yb_install_dir }}/bin/ysqlsh -h 127.0.0.1 -p {{ db_port }} -c \"CREATE TABLE test_restore (id INT PRIMARY KEY, val TEXT);\""
            delegate_to: "{{ groups['tservers'][0] }}"
            run_once: true
            changed_when: true

          - name: Run restore role
            ansible.builtin.include_role:
              name: yb-restore
            run_once: false

          - name: Verify data was successfully restored
            ansible.builtin.command:
              cmd: "{{ yb_install_dir }}/bin/ysqlsh -h 127.0.0.1 -p {{ db_port }} -t -c \"SELECT val FROM test_restore WHERE id = 1;\""
            delegate_to: "{{ groups['tservers'][0] }}"
            run_once: true
            register: _restore_select
            failed_when: "'restore_verified' not in _restore_select.stdout"

        always:
          - name: Stop Minio server on Master
            ansible.builtin.shell:
              cmd: "pkill -f '/usr/local/bin/minio server' && rm -rf /tmp/minio_data"
            delegate_to: "{{ groups['masters'][0] }}"
            run_once: true
            become: true
            changed_when: true
            failed_when: false
  ```

- [ ] **Step 2: Commit the verify playbook**

  Run:
  ```bash
  git add molecule/backup-restore/verify.yml
  git commit -m "chore: add backup-restore verify.yml playbook"
  ```

---

### Task 4: Clean up `default` verify playbook

**Files:**
- Modify: `molecule/default/verify.yml:228-418`

- [ ] **Step 1: Remove backup and restore verification from `molecule/default/verify.yml`**

  Modify the file `/home/zx1986/Projects/yb-ansible/molecule/default/verify.yml` by removing lines 228 to 418 completely.
  The file should end right after:
  ```yaml
      register: _seed_result
      retries: 18
      delay: 10
      until: _seed_result.rc == 0
  ```

- [ ] **Step 2: Verify the edits**

  Check the end of `/home/zx1986/Projects/yb-ansible/molecule/default/verify.yml`. Ensure there are no leftover references to `Verify snapshot role` or `Verify backup and restore roles`.

- [ ] **Step 3: Commit the changes**

  Run:
  ```bash
  git add molecule/default/verify.yml
  git commit -m "refactor: remove snapshot/backup/restore verification from default verify playbook"
  ```

---

### Task 5: Run verification tests

- [ ] **Step 1: Run default scenario tests**

  Run:
  ```bash
  export LIBVIRT_DEFAULT_URI=qemu:///system
  export MOLECULE_SSH_PUB_KEY="$(cat ~/.ssh/id_ed25519.pub)"
  export MOLECULE_SSH_IDENTITY_FILE="$HOME/.ssh/id_ed25519"
  export MOLECULE_CRANE_INSECURE="true"
  molecule test --scenario-name default
  ```
  Expected: PASS

- [ ] **Step 2: Run backup-restore scenario tests**

  Run:
  ```bash
  export LIBVIRT_DEFAULT_URI=qemu:///system
  export MOLECULE_SSH_PUB_KEY="$(cat ~/.ssh/id_ed25519.pub)"
  export MOLECULE_SSH_IDENTITY_FILE="$HOME/.ssh/id_ed25519"
  export MOLECULE_CRANE_INSECURE="true"
  molecule test --scenario-name backup-restore
  ```
  Expected: PASS

- [ ] **Step 3: Commit after full verification**

  Run:
  ```bash
  git status
  ```
  Expected: clean working directory.
