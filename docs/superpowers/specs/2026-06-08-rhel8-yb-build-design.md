# RHEL 8 YugabyteDB Build Design

Date: 2026-06-08
Branch: feature/rhel8-yb-build
Base branch: split/docs

## Goal

Move the project to a RHEL 8-only support target and upgrade the default
YugabyteDB package version to `2025.2.3.2-b1`. Molecule will use CentOS Stream 8
GenericCloud VMs as the RHEL 8-compatible test environment.

## Scope

This work removes RHEL 7 and CentOS 7 as supported and tested targets. README,
solution overview, playbook documentation, Molecule VM creation, and Molecule
inventory defaults will be aligned to RHEL 8-compatible hosts only.

The YugabyteDB version is pinned to the full build tag `2025.2.3.2-b1`. The
implementation must not fall back to a floating latest version or silently
replace this version with another release.

This work does not add a multi-OS test matrix, RHEL subscription registration,
Rocky Linux or AlmaLinux scenarios, or rolling upgrade behavior for existing
production clusters.

## Ansible Role Changes

`roles/yb-build` will update the default `yb_shipper_tag` to
`2025.2.3.2-b1`. Controller and node cache paths will continue to derive from
that tag.

The install decision will continue to use `yb-master --version` when a binary is
already present. Verification will assert the full build tag so
`2025.2.3.2` and `2025.2.3.2-b1` are not treated as interchangeable.

The `post_install.sh` marker will become version-specific. The preferred marker
shape is a file such as:

```text
/opt/yugabyte/.post_install_done_2025.2.3.2-b1
```

The old unversioned `/opt/yugabyte/.post_install_done` marker will no longer be
used to skip `post_install.sh`, because it can incorrectly skip post-install
work after a version change.

RHEL 8 runtime dependencies will be handled in the existing role boundaries.
Initial clean-VM setup should cover Python and SSH. Additional packages such as
`libatomic`, `libstdc++`, `ncurses-compat-libs`, or OpenSSL compatibility
packages should be added only when Molecule or binary checks show they are
required by `2025.2.3.2-b1`.

## Molecule And CI

The libvirt Molecule VM flow will use the CentOS Stream 8 GenericCloud image:

```text
https://cloud.centos.org/centos/8-stream/x86_64/images/CentOS-Stream-GenericCloud-8-latest.x86_64.qcow2
```

CentOS 7-specific vault repository repair commands will be removed. The VM
creation flow will update the base image filename, `virt-install --os-variant`,
cloud-init user, SSH wait logic, generated inventory, and every Molecule
scenario `ansible_user` to match the CentOS Stream 8 image.

The current `.vms` and clean-base snapshot behavior remains in place. This
change does not reorder scenarios, share an already-installed YugabyteDB cluster
between scenarios, or add a new persistent package-preinstalled snapshot.

`tests/run_molecule_scenarios.sh` remains the full local validation entry point.
Scenario verify files will be updated to expect `2025.2.3.2-b1`.

## Documentation

README and docs will describe RHEL 8-compatible Linux hosts as the target.
RHEL 7 and CentOS 7 support claims will be removed. Inventory examples will use
the new default cloud image login user where Molecule examples are involved, and
production examples will avoid implying CentOS 7.

Documentation that describes the YugabyteDB artifact will distinguish between
the release version `2025.2.3.2` and the full build tag `2025.2.3.2-b1` when
that distinction matters for tarball or image names.

Docs that mention `post_install.sh` idempotency will describe the
version-specific marker.

## Verification

Before the branch is considered complete, run:

```bash
source .venv/bin/activate && ansible-playbook --syntax-check tests/syntax_check.yml
source .venv/bin/activate && molecule test -s default
source .venv/bin/activate && tests/run_molecule_scenarios.sh
```

Completion requires all Molecule scenarios to pass locally on CentOS Stream 8,
no remaining RHEL 7 or CentOS 7 support claims in docs or Molecule config, and a
clean git worktree containing only this feature's changes.

If the `2025.2.3.2-b1` shipper image or tarball layout is unavailable or
incompatible with the current extractor, the implementation should stop with the
observed error and update the design or plan explicitly. It must not substitute
another YugabyteDB version without approval.
