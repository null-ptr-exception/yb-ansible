# Molecule Stabilization and Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stabilize the existing Molecule scenarios, make CI scenario coverage explicit, and harden the backup/restore integration test before adding new workflow coverage.

**Architecture:** Keep the current role and scenario split. Make narrow changes to the existing `default`, `xcluster`, and `backup-restore` scenarios first, then update Makefile and CI orchestration. Do not refactor role boundaries while fixing test determinism.

**Tech Stack:** Ansible playbooks and roles, Molecule scenarios, GitHub Actions, Makefile, YugabyteDB CLI tools, MinIO, s5cmd.

---

## Scope And Priority

### P0: Stabilize Existing Scenarios

1. Make `molecule/xcluster` rerunnable and compatible with Molecule idempotence.
2. Remove write operations from `molecule/default/verify.yml`.
3. Verify syntax and run focused Molecule checks when libvirt is available.

### P1: Make Scenario Execution Explicit

1. Update `Makefile` to enumerate scenarios.
2. Update `.github/workflows/ci-test.yml` to use a scenario matrix.
3. Preserve failure log upload behavior.

### P2: Harden Backup-Restore

1. Keep MinIO handling lightweight; it only needs to provide temporary object storage for backup/restore verification.
2. Do not spend effort on MinIO version pinning or checksum validation unless it becomes a real blocker.
3. Assert backup artifacts exist before restore.

### P3: Expand Workflow Coverage Later

Add new scenarios after P0-P2 are stable:

1. `upgrade-restart`
2. `clean`
3. `failure-preflight`
4. Variable matrix coverage for non-default ports, non-default `yb_tserver_flags`, multiple tservers, RF=3, and `yb_restore_source=local`

---

## Files To Modify

- `molecule/xcluster/converge.yml`: Make schema creation idempotent.
- `molecule/xcluster/verify.yml`: Make source data writes rerunnable and read-only checks non-mutating.
- `roles/yb-xcluster/defaults/main.yml`: Add stable, overridable replication ID default.
- `roles/yb-xcluster/tasks/main.yml`: Stop generating timestamped replication IDs.
- `molecule/default/verify.yml`: Remove backup/restore data seeding from deployment smoke verification.
- `Makefile`: Run known Molecule scenarios explicitly.
- `.github/workflows/ci-test.yml`: Run known Molecule scenarios via matrix.
- `molecule/backup-restore/verify.yml`: Keep temporary MinIO object storage working and add artifact assertions.

---

## Task 1: Make xCluster Schema Creation Idempotent

**Files:**
- Modify: `molecule/xcluster/converge.yml`
- Verify: `molecule/xcluster/converge.yml`

- [ ] **Step 1: Inspect current schema creation**

Run:

```bash
sed -n '95,112p' molecule/xcluster/converge.yml
```

Expected: The `Create Schemas` task uses `CREATE TABLE test_table` without `IF NOT EXISTS` and has `changed_when: true`.

- [ ] **Step 2: Replace schema task with idempotent command**

Change the task to:

```yaml
    - name: Create Schemas
      ansible.builtin.command: >
        /opt/yugabyte/bin/ysqlsh -h {{ ansible_host }} -p {{ item }}
        -c "CREATE TABLE IF NOT EXISTS test_table (id INT PRIMARY KEY, val TEXT);"
      loop: [5433, 5434]
      changed_when: false
```

- [ ] **Step 3: Run syntax check**

Run:

```bash
ansible-playbook --syntax-check molecule/xcluster/converge.yml
```

Expected: `playbook: molecule/xcluster/converge.yml`

- [ ] **Step 4: Commit focused change**

Run:

```bash
git add molecule/xcluster/converge.yml
git commit -m "test: make xcluster schema setup idempotent"
```

Expected: Commit succeeds. If the working tree already contains user changes in this file, do not overwrite them; inspect with `git diff -- molecule/xcluster/converge.yml` and preserve unrelated edits.

---

## Task 2: Make xCluster Verification Rerunnable

**Files:**
- Modify: `molecule/xcluster/verify.yml`
- Verify: `molecule/xcluster/verify.yml`

- [ ] **Step 1: Inspect current insert**

Run:

```bash
sed -n '1,28p' molecule/xcluster/verify.yml
```

Expected: The `Insert data into Source` task inserts a fixed primary key without upsert.

- [ ] **Step 2: Replace insert with upsert**

Change the task to:

```yaml
    - name: Upsert data into Source
      ansible.builtin.command: >
        /opt/yugabyte/bin/ysqlsh -h {{ ansible_host }} -p 5433
        -c "INSERT INTO test_table VALUES (1, 'replicated')
            ON CONFLICT (id) DO UPDATE SET val = EXCLUDED.val;"
      changed_when: false
```

Keep the target query task unchanged:

```yaml
    - name: Verify data on Target
      ansible.builtin.command: >
        /opt/yugabyte/bin/ysqlsh -h {{ ansible_host }} -p 5434 -t -c "SELECT val FROM test_table WHERE id = 1;"
      register: _target_val
      until: "'replicated' in _target_val.stdout"
      retries: 30
      delay: 1
      changed_when: false
```

- [ ] **Step 3: Mark replication status check read-only**

Ensure the replication status task includes `changed_when: false`:

```yaml
    - name: Verify replication status ACTIVE
      ansible.builtin.command: >
        /opt/yugabyte/bin/yb-admin -master_addresses {{ ansible_host }}:7101 get_universe_replication
      register: _rep_status
      failed_when: "'ACTIVE' not in _rep_status.stdout"
      changed_when: false
```

- [ ] **Step 4: Run syntax check**

Run:

```bash
ansible-playbook --syntax-check molecule/xcluster/verify.yml
```

Expected: `playbook: molecule/xcluster/verify.yml`

- [ ] **Step 5: Commit focused change**

Run:

```bash
git add molecule/xcluster/verify.yml
git commit -m "test: make xcluster verification rerunnable"
```

Expected: Commit succeeds.

---

## Task 3: Make xCluster Replication ID Stable By Default

**Files:**
- Modify: `roles/yb-xcluster/defaults/main.yml`
- Modify: `roles/yb-xcluster/tasks/main.yml`
- Verify: `tests/syntax_check.yml`

- [ ] **Step 1: Inspect existing defaults and task**

Run:

```bash
sed -n '1,80p' roles/yb-xcluster/defaults/main.yml
sed -n '1,60p' roles/yb-xcluster/tasks/main.yml
```

Expected: Defaults define `xcluster_id_prefix` but not `xcluster_repl_id`; task generates `xcluster_repl_id` with `lookup('pipe', 'date +%Y%m%d%H%M')`.

- [ ] **Step 2: Add stable default**

Add this default to `roles/yb-xcluster/defaults/main.yml` after `xcluster_id_prefix`:

```yaml
xcluster_repl_id: "{{ xcluster_id_prefix }}_{{ (xcluster_databases | map(attribute='name') | list | join('_') | hash('md5'))[:8] }}"
```

- [ ] **Step 3: Remove timestamp generation task**

Delete this task from `roles/yb-xcluster/tasks/main.yml`:

```yaml
- name: Generate unique replication ID
  set_fact:
    xcluster_repl_id: "{{ xcluster_id_prefix }}_{{ (xcluster_databases | map(attribute='name') | list | join('_') | hash('md5'))[:8] }}_{{ lookup('pipe', 'date +%Y%m%d%H%M') }}"
```

Keep the existing debug task:

```yaml
- name: Debug generated replication ID
  debug:
    var: xcluster_repl_id
```

- [ ] **Step 4: Run syntax check**

Run:

```bash
ansible-playbook --syntax-check tests/syntax_check.yml
ansible-playbook --syntax-check molecule/xcluster/converge.yml
```

Expected:

```text
playbook: tests/syntax_check.yml
playbook: molecule/xcluster/converge.yml
```

- [ ] **Step 5: Commit focused change**

Run:

```bash
git add roles/yb-xcluster/defaults/main.yml roles/yb-xcluster/tasks/main.yml
git commit -m "fix: make xcluster replication id stable"
```

Expected: Commit succeeds.

---

## Task 4: Remove Data Seeding From Default Verification

**Files:**
- Modify: `molecule/default/verify.yml`
- Verify: `molecule/default/verify.yml`

- [ ] **Step 1: Inspect the default verify tail**

Run:

```bash
sed -n '200,230p' molecule/default/verify.yml
```

Expected: The file contains `Seed snapshot_test table in yugabyte database`.

- [ ] **Step 2: Delete the seeding task**

Remove this task from `molecule/default/verify.yml`:

```yaml
    - name: Seed snapshot_test table in yugabyte database
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
```

- [ ] **Step 3: Run syntax check**

Run:

```bash
ansible-playbook --syntax-check molecule/default/verify.yml
```

Expected: `playbook: molecule/default/verify.yml`

- [ ] **Step 4: Commit focused change**

Run:

```bash
git add molecule/default/verify.yml
git commit -m "test: keep default verification read only"
```

Expected: Commit succeeds.

---

## Task 5: Run P0 Verification

**Files:**
- Verify: `molecule/default/verify.yml`
- Verify: `molecule/xcluster/converge.yml`
- Verify: `molecule/xcluster/verify.yml`
- Verify: `roles/yb-xcluster/tasks/main.yml`

- [ ] **Step 1: Run syntax checks**

Run:

```bash
ansible-playbook --syntax-check molecule/default/converge.yml
ansible-playbook --syntax-check molecule/default/verify.yml
ansible-playbook --syntax-check molecule/xcluster/converge.yml
ansible-playbook --syntax-check molecule/xcluster/verify.yml
ansible-playbook --syntax-check tests/syntax_check.yml
```

Expected: Each command prints `playbook: <path>` and exits with status `0`.

- [ ] **Step 2: Run focused xCluster lifecycle when libvirt is available**

Run:

```bash
molecule converge -s xcluster
molecule idempotence -s xcluster
molecule verify -s xcluster
```

Expected: All commands exit with status `0`. `molecule idempotence -s xcluster` reports no changed tasks from xCluster setup.

- [ ] **Step 3: Run default scenario when libvirt is available**

Run:

```bash
molecule test -s default
```

Expected: Scenario exits with status `0`.

- [ ] **Step 4: Commit verification notes only if files changed**

Run:

```bash
git status --short
```

Expected: No verification-generated source changes. If logs are generated under `logs/`, do not commit them unless the repository intentionally tracks those logs.

---

## Task 6: Make Makefile Scenario Execution Explicit

**Files:**
- Modify: `Makefile`
- Verify: `Makefile`

- [ ] **Step 1: Inspect current Makefile target**

Run:

```bash
sed -n '1,40p' Makefile
```

Expected: `test-molecule` runs plain `molecule test`.

- [ ] **Step 2: Add scenario list and loop**

Change the file to include:

```makefile
.PHONY: help test test-controller test-molecule

MOLECULE_SCENARIOS ?= default xcluster backup-restore

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

test: test-controller test-molecule ## Run all tests

test-controller: ## Build and verify the controller Docker image
	@controller/test.sh

test-molecule: ## Run molecule scenarios (requires libvirt)
	@for scenario in $(MOLECULE_SCENARIOS); do \
		echo "==> molecule test -s $$scenario"; \
		molecule test -s $$scenario || exit 1; \
	done
```

- [ ] **Step 3: Run a dry shell parse**

Run:

```bash
make -n test-molecule
```

Expected: Output shows a loop over `default xcluster backup-restore` without executing Molecule.

- [ ] **Step 4: Commit focused change**

Run:

```bash
git add Makefile
git commit -m "ci: enumerate molecule scenarios in make target"
```

Expected: Commit succeeds.

---

## Task 7: Make GitHub Actions Scenario Execution Explicit

**Files:**
- Modify: `.github/workflows/ci-test.yml`

- [ ] **Step 1: Inspect current CI Molecule step**

Run:

```bash
sed -n '1,90p' .github/workflows/ci-test.yml
```

Expected: Single job runs plain `molecule test`.

- [ ] **Step 2: Add matrix strategy**

Under `jobs.test`, add:

```yaml
    strategy:
      fail-fast: false
      matrix:
        scenario: [default, xcluster, backup-restore]
```

Keep `runs-on` and `env` unchanged.

- [ ] **Step 3: Update Molecule step**

Change:

```yaml
      - name: Run molecule test
        run: |
          source .venv/bin/activate
          molecule test
```

To:

```yaml
      - name: Run molecule scenario
        run: |
          source .venv/bin/activate
          molecule test -s "${{ matrix.scenario }}"
```

Keep the existing `env` block unchanged.

- [ ] **Step 4: Make artifact names scenario-specific**

Change:

```yaml
          name: molecule-logs
```

To:

```yaml
          name: molecule-logs-${{ matrix.scenario }}
```

- [ ] **Step 5: Commit focused change**

Run:

```bash
git add .github/workflows/ci-test.yml
git commit -m "ci: run molecule scenarios as a matrix"
```

Expected: Commit succeeds.

---

## Task 8: Add Backup Artifact Assertions

**Files:**
- Modify: `molecule/backup-restore/verify.yml`
- Verify: `molecule/backup-restore/verify.yml`

- [ ] **Step 1: Inspect backup flow**

Run:

```bash
sed -n '150,190p' molecule/backup-restore/verify.yml
```

Expected: Backup role runs, then the test immediately drops data and restores without checking uploaded artifacts.

- [ ] **Step 2: Add metadata assertion after backup role**

Insert after `Run backup role`:

```yaml
        - name: Verify backup metadata exists in Minio
          ansible.builtin.command: >
            /usr/local/bin/s5cmd --endpoint-url {{ yb_backup_minio_endpoint }}
            ls s3://{{ yb_backup_minio_bucket }}/{{ yb_snapshot_id }}/metadata/metadata.snapshot
          environment:
            AWS_ACCESS_KEY_ID: "{{ yb_backup_minio_access_key }}"
            AWS_SECRET_ACCESS_KEY: "{{ yb_backup_minio_secret_key }}"
          delegate_to: "{{ groups['masters'][0] }}"
          run_once: true
          changed_when: false
```

- [ ] **Step 3: Add tablet data assertion**

Insert after metadata assertion:

```yaml
        - name: Verify tablet data was uploaded
          ansible.builtin.command: >
            /usr/local/bin/s5cmd --endpoint-url {{ yb_backup_minio_endpoint }}
            ls s3://{{ yb_backup_minio_bucket }}/{{ yb_snapshot_id }}/data/
          environment:
            AWS_ACCESS_KEY_ID: "{{ yb_backup_minio_access_key }}"
            AWS_SECRET_ACCESS_KEY: "{{ yb_backup_minio_secret_key }}"
          delegate_to: "{{ groups['masters'][0] }}"
          run_once: true
          register: _backup_objects
          changed_when: false

        - name: Assert backup contains tablet data
          ansible.builtin.assert:
            that:
              - _backup_objects.stdout_lines | length > 0
            fail_msg: "Backup did not upload tablet data for snapshot {{ yb_snapshot_id }}"
          run_once: true
```

- [ ] **Step 4: Run syntax check**

Run:

```bash
ansible-playbook --syntax-check molecule/backup-restore/verify.yml
```

Expected: `playbook: molecule/backup-restore/verify.yml`

- [ ] **Step 5: Commit focused change**

Run:

```bash
git add molecule/backup-restore/verify.yml
git commit -m "test: assert backup artifacts before restore"
```

Expected: Commit succeeds.

---

## Task 9: Keep MinIO Handling Lightweight

**Files:**
- Verify: `controller/Dockerfile`
- Verify: `molecule/backup-restore/verify.yml`

- [ ] **Step 1: Confirm MinIO is available from the controller image**

Run:

```bash
sed -n '1,90p' controller/Dockerfile
```

Expected: `controller/Dockerfile` installs `/usr/local/bin/minio`. Do not add version pinning or checksum work in this task.

- [ ] **Step 2: Confirm backup-restore can copy or download MinIO**

Run:

```bash
sed -n '90,125p' molecule/backup-restore/verify.yml
```

Expected: The scenario first checks for `/usr/local/bin/minio` on the controller and copies it to the master when present. A fallback download is acceptable for now because MinIO is only a temporary object storage service for the integration scenario.

- [ ] **Step 3: Commit only if files changed**

Run:

```bash
git status --short
```

Expected: This task normally produces no source changes. If no files changed, skip commit and continue.

---

## Task 10: Keep MinIO Lifecycle Simple

**Files:**
- Verify: `molecule/backup-restore/verify.yml`

- [ ] **Step 1: Inspect current MinIO start and cleanup**

Run:

```bash
sed -n '115,135p' molecule/backup-restore/verify.yml
sed -n '198,208p' molecule/backup-restore/verify.yml
```

Expected: MinIO is started with `nohup /usr/local/bin/minio server ... &` and cleanup uses `pkill -f '/usr/local/bin/minio server'; rm -rf /tmp/minio_data`. This is acceptable unless backup-restore verification shows a real startup or cleanup failure.

- [ ] **Step 2: Make no lifecycle change unless evidence requires it**

Use this decision rule:

```text
If backup-restore passes with the current nohup/pkill lifecycle, leave it alone.
If MinIO startup or cleanup fails repeatedly, make the smallest targeted fix required by the observed failure.
```

- [ ] **Step 3: Run syntax check if files changed**

Run:

```bash
ansible-playbook --syntax-check molecule/backup-restore/verify.yml
```

Expected: `playbook: molecule/backup-restore/verify.yml`. If `ansible-playbook` is unavailable in the local environment, record that verification could not run.

- [ ] **Step 4: Commit only if files changed**

Run:

```bash
git status --short
```

Expected: This task normally produces no source changes. If no files changed, skip commit and continue.

---

## Task 11: Run Full Scenario Verification

**Files:**
- Verify: `molecule/default`
- Verify: `molecule/xcluster`
- Verify: `molecule/backup-restore`

- [ ] **Step 1: Run all syntax checks**

Run:

```bash
ansible-playbook --syntax-check molecule/default/converge.yml
ansible-playbook --syntax-check molecule/default/verify.yml
ansible-playbook --syntax-check molecule/xcluster/converge.yml
ansible-playbook --syntax-check molecule/xcluster/verify.yml
ansible-playbook --syntax-check molecule/backup-restore/verify.yml
ansible-playbook --syntax-check tests/syntax_check.yml
```

Expected: Every command exits with status `0`.

- [ ] **Step 2: Run all Molecule scenarios when libvirt is available**

Run:

```bash
molecule test -s default
molecule test -s xcluster
molecule test -s backup-restore
```

Expected: Every scenario exits with status `0`.

- [ ] **Step 3: Inspect final working tree**

Run:

```bash
git status --short
```

Expected: Only intentional source changes remain. Generated logs under `logs/` are not committed unless explicitly required.

---

## Backlog: New Coverage Scenarios

Create separate plans before implementing these items.

### `upgrade-restart`

Target files:

- `molecule/upgrade-restart/molecule.yml`
- `molecule/upgrade-restart/converge.yml`
- `molecule/upgrade-restart/verify.yml`

Coverage:

- `playbooks/upgrade.yml`
- `playbooks/restart.yml`
- `yb_allow_config_change`
- Service health after rolling restart

### `clean`

Target files:

- `molecule/clean/molecule.yml`
- `molecule/clean/converge.yml`
- `molecule/clean/verify.yml`

Coverage:

- `playbooks/clean.yml`
- Services stopped or absent
- Expected data cleanup behavior

### `failure-preflight`

Target files:

- `molecule/failure-preflight/molecule.yml`
- `molecule/failure-preflight/converge.yml`
- `molecule/failure-preflight/verify.yml`

Coverage:

- Invalid master count fails early
- Master membership mismatch fails early
- Version change protection fails without upgrade flow
- Missing snapshot metadata fails clearly

### Pin Controller MinIO Artifact

Target files:

- `controller/Dockerfile`
- `controller/test.sh`

Coverage:

- Replace the current unversioned MinIO download in `controller/Dockerfile` with a versioned archive URL.
- Verify the archive checksum during Docker build.
- Keep `controller/test.sh` checking that `minio` is available in the image.
- Use only a checksum verified from the selected MinIO release artifact; do not guess or reuse a checksum from another version.

---

## Execution Notes

Before implementation, run:

```bash
git status --short
```

Current repository state may contain user changes and generated logs. Do not revert unrelated changes. If `molecule/xcluster/converge.yml` is already modified, inspect it before editing and preserve the existing change.

For isolated development, use a worktree before executing this plan if the user wants protection from the current dirty checkout.
