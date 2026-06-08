#!/usr/bin/env bash
set -euo pipefail

scenarios="${MOLECULE_SCENARIOS:-default xcluster backup-restore}"
run_started_at="$(date +%s)"
scenario_names=()
scenario_statuses=()
scenario_durations=()

if ! command -v molecule >/dev/null 2>&1; then
  echo "molecule command not found" >&2
  exit 127
fi

cleanup_stale_vms() {
  local vm

  command -v virsh >/dev/null 2>&1 || return 0

  while IFS= read -r vm; do
    [[ -n "$vm" ]] || continue
    virsh destroy "$vm" 2>/dev/null || true
    virsh undefine "$vm" --snapshots-metadata --remove-all-storage 2>/dev/null \
      || virsh undefine "$vm" --snapshots-metadata 2>/dev/null || true
  done < <(virsh list --all --name 2>/dev/null | grep '^yb-ansible-' || true)
}

format_duration() {
  local seconds="$1"
  local minutes hours

  if (( seconds < 60 )); then
    printf '%ss' "$seconds"
  elif (( seconds < 3600 )); then
    minutes=$((seconds / 60))
    seconds=$((seconds % 60))
    printf '%dm%02ds' "$minutes" "$seconds"
  else
    hours=$((seconds / 3600))
    minutes=$(((seconds % 3600) / 60))
    seconds=$((seconds % 60))
    printf '%dh%02dm%02ds' "$hours" "$minutes" "$seconds"
  fi
}

record_scenario() {
  local scenario="$1"
  local status="$2"
  local duration="$3"

  scenario_names+=("$scenario")
  scenario_statuses+=("$status")
  scenario_durations+=("$duration")
}

print_timing_summary() {
  local total_elapsed index
  total_elapsed=$(($(date +%s) - run_started_at))

  echo "==> Molecule scenario timing summary"
  printf '%-18s %-8s %s\n' "Scenario" "Status" "Duration"
  for index in "${!scenario_names[@]}"; do
    printf '%-18s %-8s %s\n' \
      "${scenario_names[$index]}" \
      "${scenario_statuses[$index]}" \
      "$(format_duration "${scenario_durations[$index]}")"
  done
  printf 'Total elapsed: %s\n' "$(format_duration "$total_elapsed")"
}

rm -rf logs
mkdir -p logs

for scenario in $scenarios; do
  scenario_started_at="$(date +%s)"
  echo "==> molecule test -s $scenario"
  cleanup_stale_vms

  if molecule test -s "$scenario"; then
    record_scenario "$scenario" "pass" "$(($(date +%s) - scenario_started_at))"
    continue
  else
    status="$?"
  fi

  record_scenario "$scenario" "fail($status)" "$(($(date +%s) - scenario_started_at))"
  molecule cleanup -s "$scenario" || true
  print_timing_summary
  exit "$status"
done

print_timing_summary
