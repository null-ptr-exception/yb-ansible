#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
runner="$repo_root/tests/run_molecule_scenarios.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file_equals() {
  local expected="$1"
  local file="$2"
  local actual

  actual="$(cat "$file")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'Expected:\n%s\nActual:\n%s\n' "$expected" "$actual" >&2
    fail "$file did not match expected content"
  fi
}

make_fake_bin() {
  local bin_dir="$1"
  local log_file="$2"
  local fail_scenario="${3:-}"
  local fail_code="${4:-7}"

  cat > "$bin_dir/molecule" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "molecule \$*" >> "$log_file"
if [[ "\$1" == "test" && "\${3:-}" == "$fail_scenario" ]]; then
  exit "$fail_code"
fi
EOF
  chmod +x "$bin_dir/molecule"

  cat > "$bin_dir/virsh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
echo "virsh \$*" >> "$log_file"
if [[ "\$*" == "list --all --name" ]]; then
  printf '%s\n' yb-ansible-old unrelated yb-ansible-stale
fi
EOF
  chmod +x "$bin_dir/virsh"
}

run_with_fake_bin() {
  local work_dir="$1"
  local bin_dir="$2"
  shift 2

  (
    cd "$work_dir"
    PATH="$bin_dir:/usr/bin:/bin" "$runner" "$@"
  )
}

test_default_order_and_vm_cleanup() {
  local tmp_dir bin_dir log_file
  tmp_dir="$(mktemp -d)"
  bin_dir="$tmp_dir/bin"
  log_file="$tmp_dir/calls.log"
  mkdir -p "$bin_dir" "$tmp_dir/logs"
  touch "$tmp_dir/logs/stale"
  make_fake_bin "$bin_dir" "$log_file"

  run_with_fake_bin "$tmp_dir" "$bin_dir"

  [[ ! -e "$tmp_dir/logs/stale" ]] || fail "runner did not recreate logs directory"
  assert_file_equals "virsh list --all --name
virsh destroy yb-ansible-old
virsh undefine yb-ansible-old --snapshots-metadata --remove-all-storage
virsh destroy yb-ansible-stale
virsh undefine yb-ansible-stale --snapshots-metadata --remove-all-storage
molecule test -s default
virsh list --all --name
virsh destroy yb-ansible-old
virsh undefine yb-ansible-old --snapshots-metadata --remove-all-storage
virsh destroy yb-ansible-stale
virsh undefine yb-ansible-stale --snapshots-metadata --remove-all-storage
molecule test -s xcluster
virsh list --all --name
virsh destroy yb-ansible-old
virsh undefine yb-ansible-old --snapshots-metadata --remove-all-storage
virsh destroy yb-ansible-stale
virsh undefine yb-ansible-stale --snapshots-metadata --remove-all-storage
molecule test -s backup-restore" "$log_file"
}

test_override_order() {
  local tmp_dir bin_dir log_file
  tmp_dir="$(mktemp -d)"
  bin_dir="$tmp_dir/bin"
  log_file="$tmp_dir/calls.log"
  mkdir -p "$bin_dir"
  make_fake_bin "$bin_dir" "$log_file"

  (
    cd "$tmp_dir"
    MOLECULE_SCENARIOS="xcluster" PATH="$bin_dir:/usr/bin:/bin" "$runner"
  )

  [[ "$(grep -c '^molecule test' "$log_file")" == "1" ]] || fail "override ran more than one scenario"
  grep -q '^molecule test -s xcluster$' "$log_file" || fail "override did not run xcluster"
}

test_failure_runs_cleanup_and_preserves_exit_code() {
  local tmp_dir bin_dir log_file status
  tmp_dir="$(mktemp -d)"
  bin_dir="$tmp_dir/bin"
  log_file="$tmp_dir/calls.log"
  mkdir -p "$bin_dir"
  make_fake_bin "$bin_dir" "$log_file" "xcluster" "23"

  set +e
  run_with_fake_bin "$tmp_dir" "$bin_dir"
  status="$?"
  set -e

  [[ "$status" == "23" ]] || fail "runner returned $status instead of Molecule failure code"
  grep -q '^molecule cleanup -s xcluster$' "$log_file" || fail "runner did not clean up failed scenario"
  ! grep -q '^molecule test -s backup-restore$' "$log_file" || fail "runner continued after failure"
}

test_missing_molecule_fails_before_logs_reset() {
  local tmp_dir bin_dir status
  tmp_dir="$(mktemp -d)"
  bin_dir="$tmp_dir/bin"
  mkdir -p "$bin_dir" "$tmp_dir/logs"
  touch "$tmp_dir/logs/keep"

  set +e
  (
    cd "$tmp_dir"
    PATH="/usr/bin:/bin" "$runner" >/dev/null 2>&1
  )
  status="$?"
  set -e

  [[ "$status" == "127" ]] || fail "missing molecule returned $status instead of 127"
  [[ -e "$tmp_dir/logs/keep" ]] || fail "runner reset logs before checking molecule"
}

test_success_prints_timing_summary() {
  local tmp_dir bin_dir log_file output_file
  tmp_dir="$(mktemp -d)"
  bin_dir="$tmp_dir/bin"
  log_file="$tmp_dir/calls.log"
  output_file="$tmp_dir/output.log"
  mkdir -p "$bin_dir"
  make_fake_bin "$bin_dir" "$log_file"

  run_with_fake_bin "$tmp_dir" "$bin_dir" >"$output_file"

  grep -q '^==> Molecule scenario timing summary$' "$output_file" || fail "summary header was not printed"
  grep -Eq '^default[[:space:]]+pass[[:space:]]+[0-9]+s$' "$output_file" || fail "default timing was not printed"
  grep -Eq '^xcluster[[:space:]]+pass[[:space:]]+[0-9]+s$' "$output_file" || fail "xcluster timing was not printed"
  grep -Eq '^backup-restore[[:space:]]+pass[[:space:]]+[0-9]+s$' "$output_file" || fail "backup-restore timing was not printed"
  grep -Eq '^Total elapsed:[[:space:]]+[0-9]+s$' "$output_file" || fail "total timing was not printed"
}

test_failure_prints_timing_summary_before_exit() {
  local tmp_dir bin_dir log_file output_file status
  tmp_dir="$(mktemp -d)"
  bin_dir="$tmp_dir/bin"
  log_file="$tmp_dir/calls.log"
  output_file="$tmp_dir/output.log"
  mkdir -p "$bin_dir"
  make_fake_bin "$bin_dir" "$log_file" "xcluster" "23"

  set +e
  run_with_fake_bin "$tmp_dir" "$bin_dir" >"$output_file"
  status="$?"
  set -e

  [[ "$status" == "23" ]] || fail "runner returned $status instead of Molecule failure code"
  grep -q '^==> Molecule scenario timing summary$' "$output_file" || fail "summary header was not printed on failure"
  grep -Eq '^default[[:space:]]+pass[[:space:]]+[0-9]+s$' "$output_file" || fail "passed scenario timing was not printed on failure"
  grep -Eq '^xcluster[[:space:]]+fail\(23\)[[:space:]]+[0-9]+s$' "$output_file" || fail "failed scenario timing was not printed"
  ! grep -Eq '^backup-restore[[:space:]]+' "$output_file" || fail "unstarted scenario was included in summary"
}

test_default_order_and_vm_cleanup
test_override_order
test_failure_runs_cleanup_and_preserves_exit_code
test_missing_molecule_fails_before_logs_reset
test_success_prints_timing_summary
test_failure_prints_timing_summary_before_exit

echo "PASS: run_molecule_scenarios tests"
