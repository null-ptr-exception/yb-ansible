#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/rg" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$tmp_dir/rg"

verifiers=(
  tests/verify_ansible_builtin_fqcn.sh
  tests/verify_molecule_ssh_key.sh
  tests/verify_playbook_service_names.sh
  tests/verify_xcluster_replication_id.sh
)

for verifier in "${verifiers[@]}"; do
  (
    cd "$repo_root"
    PATH="$tmp_dir:/usr/bin:/bin" bash "$verifier"
  ) || fail "$verifier failed without rg"
done

echo "PASS: static verifiers do not require rg"
