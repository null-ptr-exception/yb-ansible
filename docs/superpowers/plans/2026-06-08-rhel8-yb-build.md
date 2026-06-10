# RHEL 8 YugabyteDB Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move yb-ansible to a RHEL 8-only target, use CentOS Stream 8 for Molecule VMs, and pin YugabyteDB to `2025.2.3.2-b1`.

**Architecture:** Keep the existing Ansible role and Molecule scenario layout. Change the default YB artifact tag in `roles/yb-build`, make `post_install.sh` idempotency version-specific, update the libvirt VM factory to create CentOS Stream 8 guests, and align docs/tests with the RHEL 8-only support boundary.

**Tech Stack:** Ansible, Molecule, libvirt/virt-install, cloud-init, Bash tests, GitHub Actions self-hosted runner.

---

## File Structure

- Create `tests/test_rhel8_yb_build_config.sh`: fast static regression test for the RHEL 8-only/YB version contract.
- Modify `roles/yb-build/defaults/main.yml`: default YB shipper tag.
- Modify `roles/yb-build/tasks/main.yml`: version-specific `post_install.sh` marker.
- Modify `roles/yb-build/tasks/verify.yml`: keep full build-tag verification intact.
- Modify `molecule/default/create.yml`: CentOS Stream 8 base image, cloud user, generated inventory.
- Modify `molecule/default/tasks/create_vm.yml`: remove CentOS 7 repo repair, set CentOS Stream 8 cloud-init user and `virt-install` OS variant.
- Modify `molecule/default/molecule.yml`, `molecule/xcluster/molecule.yml`, `molecule/backup-restore/molecule.yml`: `ansible_user` and YB tag expectations.
- Modify `molecule/default/verify.yml`: expected YB version.
- Modify `README.md`, `docs/solution-overview.md`, `docs/playbooks.md`: RHEL 8-only support, YugabyteDB `2025.2.3.2-b1`, versioned post-install marker.
- No workflow changes are expected in `.github/workflows/ci-test.yml` unless local Molecule proves CentOS Stream 8 requires a CI environment variable.

---

### Task 1: Add Static Contract Test

**Files:**
- Create: `tests/test_rhel8_yb_build_config.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/test_rhel8_yb_build_config.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local pattern="$2"

  grep -Eq "$pattern" "$file" || fail "$file does not contain pattern: $pattern"
}

assert_not_contains() {
  local file="$1"
  local pattern="$2"

  if grep -Eq "$pattern" "$file"; then
    fail "$file still contains forbidden pattern: $pattern"
  fi
}

assert_contains roles/yb-build/defaults/main.yml 'yb_shipper_tag: "2025\.2\.3\.2-b1"'
assert_contains molecule/default/create.yml 'CentOS-Stream-GenericCloud-8-latest\.x86_64\.qcow2'
assert_contains molecule/default/create.yml "'user': 'cloud-user'"
assert_contains molecule/default/tasks/create_vm.yml '--os-variant (centos-stream8|rhel8\.[0-9]+|rhel8-unknown)'
assert_contains molecule/default/tasks/create_vm.yml 'name: cloud-user'
assert_contains molecule/default/verify.yml 'yb_shipper_tag: "2025\.2\.3\.2-b1"'

assert_not_contains README.md 'CentOS 7|RHEL 7'
assert_not_contains docs/solution-overview.md 'CentOS 7|RHEL 7'
assert_not_contains molecule/default/create.yml 'CentOS-7|centos@|ansible_user=centos'
assert_not_contains molecule/default/tasks/create_vm.yml 'CentOS-\\*|vault\\.centos\\.org|centos7\\.0|name: centos'
assert_not_contains molecule/default/molecule.yml 'ansible_user: centos'
assert_not_contains molecule/xcluster/molecule.yml 'ansible_user: centos'
assert_not_contains molecule/backup-restore/molecule.yml 'ansible_user: centos'

echo "PASS: RHEL 8 YugabyteDB build config"
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
source .venv/bin/activate && bash tests/test_rhel8_yb_build_config.sh
```

Expected: FAIL because `yb_shipper_tag` is still `2.20.11.1`, Molecule still references CentOS 7, and docs still claim RHEL 7 support.

- [ ] **Step 3: Commit the failing test**

```bash
git add tests/test_rhel8_yb_build_config.sh
git commit -m "test: add rhel8 yb build contract"
```

---

### Task 2: Update yb-build Version And post_install Marker

**Files:**
- Modify: `roles/yb-build/defaults/main.yml`
- Modify: `roles/yb-build/tasks/main.yml`
- Modify: `roles/yb-build/tasks/verify.yml`

- [ ] **Step 1: Update the default YB shipper tag**

In `roles/yb-build/defaults/main.yml`, change the tag line to:

```yaml
yb_shipper_tag: "2025.2.3.2-b1"
```

Keep the derived values unchanged:

```yaml
yb_shipper_image: "{{ yb_shipper_registry }}/{{ yb_shipper_repository }}:{{ yb_shipper_tag }}"
yb_package_dir: /opt/packages/yugabytedb/{{ yb_shipper_tag }}
yb_package_cache_dir: "{{ playbook_dir }}/.cache/packages/yugabytedb/{{ yb_shipper_tag }}"
```

- [ ] **Step 2: Add a version-specific marker fact**

In `roles/yb-build/tasks/main.yml`, after `Determine if install is needed`, add:

```yaml
- name: Set post_install marker path
  ansible.builtin.set_fact:
    _yb_post_install_marker: "{{ yb_install_dir }}/.post_install_done_{{ yb_shipper_tag }}"
```

- [ ] **Step 3: Use the version-specific marker**

Replace the current marker tasks in `roles/yb-build/tasks/main.yml` with:

```yaml
- name: Check if post_install.sh has been run for this version
  ansible.builtin.stat:
    path: "{{ _yb_post_install_marker }}"
  register: post_install_done

- name: Run post_install.sh
  ansible.builtin.command:
    cmd: ./bin/post_install.sh
    chdir: "{{ yb_install_dir }}"
  when:
    - _yb_needs_install | bool or not post_install_done.stat.exists

- name: Mark post_install.sh as completed for this version
  ansible.builtin.file:
    path: "{{ _yb_post_install_marker }}"
    state: touch
    owner: "{{ yb_user }}"
    group: "{{ yb_group }}"
    mode: "0644"
  when:
    - _yb_needs_install | bool or not post_install_done.stat.exists
```

- [ ] **Step 4: Keep full build-tag verification**

Confirm `roles/yb-build/tasks/verify.yml` still contains:

```yaml
- name: Assert YB version matches
  ansible.builtin.assert:
    that: "yb_shipper_tag in _yb_verify_version.stdout"
    fail_msg: "Version mismatch: expected {{ yb_shipper_tag }}, got {{ _yb_verify_version.stdout }}"
```

- [ ] **Step 5: Run focused checks**

Run:

```bash
source .venv/bin/activate && ansible-playbook --syntax-check tests/syntax_check.yml
source .venv/bin/activate && bash tests/test_rhel8_yb_build_config.sh
```

Expected: syntax check passes. Static contract still fails on Molecule/docs until later tasks.

- [ ] **Step 6: Commit**

```bash
git add roles/yb-build/defaults/main.yml roles/yb-build/tasks/main.yml roles/yb-build/tasks/verify.yml
git commit -m "feat(yb-build): pin yugabytedb 2025.2.3.2-b1"
```

---

### Task 3: Convert Molecule VM Creation To CentOS Stream 8

**Files:**
- Modify: `molecule/default/create.yml`
- Modify: `molecule/default/tasks/create_vm.yml`

- [ ] **Step 1: Update the base image variables**

In `molecule/default/create.yml`, set:

```yaml
base_img: "{{ vm_dir }}/CentOS-Stream-GenericCloud-8-latest.x86_64.qcow2"
base_img_url: https://cloud.centos.org/centos/8-stream/x86_64/images/CentOS-Stream-GenericCloud-8-latest.x86_64.qcow2
molecule_ssh_user: cloud-user
```

Keep `vm_prefix`, `vm_dir`, `ssh_pub_key`, and `ssh_identity_file` as they are.

- [ ] **Step 2: Use the Molecule SSH user in generated instance config**

In `molecule/default/create.yml`, change the `instance_conf` user value to:

```yaml
'user': molecule_ssh_user,
```

- [ ] **Step 3: Use the Molecule SSH user while waiting for cloud-init**

In `molecule/default/create.yml`, change the SSH command user segment to:

```yaml
{{ molecule_ssh_user }}@{{ item.address }}
```

- [ ] **Step 4: Use the Molecule SSH user in `.vms/inventory`**

In `molecule/default/create.yml`, change:

```ini
ansible_user=centos
```

to:

```ini
ansible_user={{ molecule_ssh_user }}
```

- [ ] **Step 5: Replace CentOS 7 cloud-init user-data**

In `molecule/default/tasks/create_vm.yml`, replace the `runcmd` and `users` block with:

```yaml
          runcmd:
            - dnf install -y python3 openssh-server
            - systemctl enable --now sshd
            - setenforce 0 || true
            - sed -i 's/^SELINUX=enforcing/SELINUX=permissive/g' /etc/selinux/config
            - dd if=/dev/zero of=/swapfile bs=1M count=2048
            - chmod 600 /swapfile
            - mkswap /swapfile
            - swapon /swapfile
            - echo "/swapfile none swap sw 0 0" >> /etc/fstab
          users:
            - name: cloud-user
              sudo: ALL=(ALL) NOPASSWD:ALL
              shell: /bin/bash
              ssh_authorized_keys:
                - {{ ssh_pub_key }}
```

- [ ] **Step 6: Update virt-install OS variant**

In `molecule/default/tasks/create_vm.yml`, change:

```text
--os-variant centos7.0
```

to:

```text
--os-variant centos-stream8
```

If local `virt-install` rejects `centos-stream8`, replace it with the accepted RHEL 8 variant shown by:

```bash
osinfo-query os | awk '/rhel8|centos-stream8/ { print $1 }'
```

The replacement must remain RHEL 8-compatible and must not use a CentOS 7 variant.

- [ ] **Step 7: Run focused static checks**

Run:

```bash
source .venv/bin/activate && bash tests/test_rhel8_yb_build_config.sh
```

Expected: static contract still fails on scenario inventory/docs until later tasks, but it no longer fails on `molecule/default/create.yml` or `molecule/default/tasks/create_vm.yml`.

- [ ] **Step 8: Commit**

```bash
git add molecule/default/create.yml molecule/default/tasks/create_vm.yml
git commit -m "test(molecule): use centos stream 8 vms"
```

---

### Task 4: Align Molecule Scenario Defaults And Verify Version

**Files:**
- Modify: `molecule/default/molecule.yml`
- Modify: `molecule/xcluster/molecule.yml`
- Modify: `molecule/backup-restore/molecule.yml`
- Modify: `molecule/default/verify.yml`

- [ ] **Step 1: Update scenario SSH users**

In all three Molecule scenario files, replace:

```yaml
ansible_user: centos
```

with:

```yaml
ansible_user: cloud-user
```

- [ ] **Step 2: Update default scenario expected YB tag**

In `molecule/default/verify.yml`, replace:

```yaml
yb_shipper_tag: "2.20.11.1"
```

with:

```yaml
yb_shipper_tag: "2025.2.3.2-b1"
```

- [ ] **Step 3: Run static contract test**

Run:

```bash
source .venv/bin/activate && bash tests/test_rhel8_yb_build_config.sh
```

Expected: static contract now fails only on README/docs RHEL 7/CentOS 7 references.

- [ ] **Step 4: Run syntax check**

Run:

```bash
source .venv/bin/activate && ansible-playbook --syntax-check tests/syntax_check.yml
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add molecule/default/molecule.yml molecule/xcluster/molecule.yml molecule/backup-restore/molecule.yml molecule/default/verify.yml
git commit -m "test(molecule): align scenarios with rhel8 target"
```

---

### Task 5: Update Documentation To RHEL 8-only

**Files:**
- Modify: `README.md`
- Modify: `docs/solution-overview.md`
- Modify: `docs/playbooks.md`

- [ ] **Step 1: Update supported platform text**

Replace support claims that say:

```text
CentOS 7 / RHEL 7
```

with:

```text
RHEL 8-compatible Linux hosts
```

Use `CentOS Stream 8` only when describing local Molecule test VMs.

- [ ] **Step 2: Update inventory examples**

Replace example users such as:

```ini
10.0.0.1 ansible_user=centos
```

with:

```ini
10.0.0.1 ansible_user=cloud-user
```

If an example is meant for production instead of Molecule, add one sentence near the inventory example:

```markdown
Use the SSH user configured on your RHEL 8-compatible images; `cloud-user` is used by the Molecule CentOS Stream 8 image.
```

- [ ] **Step 3: Update YB version tables and text**

Replace `2.20.11.1` defaults with:

```markdown
`2025.2.3.2-b1`
```

When the release/build distinction matters, use:

```markdown
The release version is `2025.2.3.2`; the package and shipper tag are pinned to the full build tag `2025.2.3.2-b1`.
```

- [ ] **Step 4: Update post_install marker docs**

Replace text describing:

```text
.post_install_done
```

with:

```text
.post_install_done_<yb_shipper_tag>
```

For the default version, the marker is:

```text
/opt/yugabyte/.post_install_done_2025.2.3.2-b1
```

- [ ] **Step 5: Run doc/config scans**

Run:

```bash
rg -n "CentOS 7|RHEL 7|2\\.20\\.11\\.1|ansible_user=centos|\\.post_install_done([^_]|$)" README.md docs molecule roles
source .venv/bin/activate && bash tests/test_rhel8_yb_build_config.sh
```

Expected: `rg` prints no forbidden support claims or old defaults except historical references inside the committed design/spec if the scan is widened beyond these paths. The static contract test passes.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/solution-overview.md docs/playbooks.md
git commit -m "docs: document rhel8 yugabytedb target"
```

---

### Task 6: Run Default Molecule And Fix RHEL 8 Runtime Gaps

**Files:**
- Modify only the file that owns the observed failure:
  - `molecule/default/tasks/create_vm.yml` for clean VM bootstrap gaps.
  - `roles/yb-build/tasks/main.yml` or role defaults for YB install/runtime gaps.
  - `molecule/default/verify.yml` only for verify assumptions that no longer match the new YB version.

- [ ] **Step 1: Run default scenario**

Run:

```bash
source .venv/bin/activate && molecule test -s default
```

Expected: PASS on the first attempt, or FAIL with a concrete CentOS Stream 8/YB `2025.2.3.2-b1` error.

- [ ] **Step 2: If `virt-install` rejects the OS variant, apply this exact fallback**

Run:

```bash
osinfo-query os | awk '/rhel8|centos-stream8/ { print $1 }'
```

If `centos-stream8` is not present and `rhel8.10` is present, change `molecule/default/tasks/create_vm.yml` to:

```text
--os-variant rhel8.10
```

If `rhel8.10` is not present and `rhel8-unknown` is present, change it to:

```text
--os-variant rhel8-unknown
```

Run `molecule test -s default` again.

- [ ] **Step 3: If YB binaries fail due to missing shared libraries, add only the missing package**

Find the missing library:

```bash
source .venv/bin/activate && molecule login -s default -h master-1 -- bash -lc 'ldd /opt/yugabyte/bin/yb-master | grep "not found" || true'
```

Use these mappings:

```text
libatomic.so.1 -> libatomic
libstdc++.so.6 -> libstdc++
libncurses.so.5 -> ncurses-compat-libs
libtinfo.so.5 -> ncurses-compat-libs
libssl.so.10 -> compat-openssl10
libcrypto.so.10 -> compat-openssl10
```

Add the required package to the clean VM bootstrap command in `molecule/default/tasks/create_vm.yml`, for example:

```yaml
- dnf install -y python3 openssh-server libatomic ncurses-compat-libs
```

Run `molecule test -s default` again.

- [ ] **Step 4: If the shipper image is missing, stop and report**

If the failure contains:

```text
MANIFEST_UNKNOWN
```

or:

```text
not found
```

for `ghcr.io/null-ptr-exception/yb-shipper:2025.2.3.2-b1`, stop implementation and report the exact `crane export` error. Do not substitute another YB version.

- [ ] **Step 5: Commit default Molecule fixes**

After `molecule test -s default` passes, commit only the fixes needed for default:

```bash
git add molecule/default/tasks/create_vm.yml molecule/default/create.yml roles/yb-build/tasks/main.yml molecule/default/verify.yml
git commit -m "fix: support rhel8 yugabytedb runtime"
```

If no files changed during this task, skip the commit and record that default passed without runtime fixes.

---

### Task 7: Run Full Scenario Verification

**Files:**
- Modify scenario files only if full Molecule exposes a scenario-specific RHEL 8 or YB `2025.2.3.2-b1` incompatibility.

- [ ] **Step 1: Run the full local suite**

Run:

```bash
source .venv/bin/activate && tests/run_molecule_scenarios.sh
```

Expected: PASS with timing summary for `default`, `xcluster`, and `backup-restore`.

- [ ] **Step 2: If a scenario fails, preserve logs and inspect the failing role boundary**

Run:

```bash
find logs -maxdepth 2 -type f -print | sort
```

Open the log file for the failed scenario and identify the first failing Ansible task. Apply the smallest fix in the role or scenario file that owns that task.

- [ ] **Step 3: Re-run the failed scenario**

For an `xcluster` failure, run:

```bash
source .venv/bin/activate && molecule test -s xcluster
```

For a `backup-restore` failure, run:

```bash
source .venv/bin/activate && molecule test -s backup-restore
```

Expected: PASS.

- [ ] **Step 4: Re-run the full local suite**

Run:

```bash
source .venv/bin/activate && tests/run_molecule_scenarios.sh
```

Expected: PASS.

- [ ] **Step 5: Commit scenario fixes**

If scenario-specific files changed, run:

```bash
git add molecule roles tests
git commit -m "fix: pass molecule scenarios on rhel8"
```

If no files changed during this task, skip the commit and record that the full suite passed without scenario fixes.

---

### Task 8: Final Verification And Branch Hygiene

**Files:**
- No planned file changes.

- [ ] **Step 1: Run fast tests**

Run:

```bash
source .venv/bin/activate && bash tests/test_rhel8_yb_build_config.sh
source .venv/bin/activate && bash tests/test_run_molecule_scenarios.sh
source .venv/bin/activate && ansible-playbook --syntax-check tests/syntax_check.yml
```

Expected:

```text
PASS: RHEL 8 YugabyteDB build config
PASS: run_molecule_scenarios tests
```

and Ansible syntax check reports no errors.

- [ ] **Step 2: Confirm old support claims are gone**

Run:

```bash
rg -n "CentOS 7|RHEL 7|centos7\\.0|ansible_user: centos|ansible_user=centos|2\\.20\\.11\\.1" README.md docs roles molecule tests
```

Expected: no matches outside historical design/plan files if `docs/superpowers` is included by mistake.

- [ ] **Step 3: Run full Molecule one final time**

Run:

```bash
source .venv/bin/activate && tests/run_molecule_scenarios.sh
```

Expected: all scenarios pass and the timing summary prints all three scenarios.

- [ ] **Step 4: Inspect git status and commit any final doc/test cleanup**

Run:

```bash
git status --short --branch
git log --oneline --decorate -8
```

Expected: branch is `feature/rhel8-yb-build`; worktree is clean after any final cleanup commit.

- [ ] **Step 5: Prepare handoff summary**

Summarize:

```text
Branch: feature/rhel8-yb-build
Base: split/docs
YugabyteDB: 2025.2.3.2-b1
Molecule OS: CentOS Stream 8 GenericCloud
Verification:
- bash tests/test_rhel8_yb_build_config.sh
- bash tests/test_run_molecule_scenarios.sh
- ansible-playbook --syntax-check tests/syntax_check.yml
- molecule test -s default
- tests/run_molecule_scenarios.sh
```

Do not claim completion unless every listed verification command has passed in the active workspace.

---

## Self-Review

- Spec coverage: RHEL 8-only support, CentOS Stream 8 Molecule, YB `2025.2.3.2-b1`, versioned post-install marker, docs alignment, and full local verification each have tasks.
- Placeholder scan: no unfinished marker tokens or open-ended implementation placeholders remain.
- Scope check: the plan avoids OS matrix expansion, RHEL subscription handling, Rocky/Alma scenarios, scenario reordering, and cross-scenario installed-cluster reuse.
