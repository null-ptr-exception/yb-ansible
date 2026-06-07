#!/bin/bash
set -euo pipefail

cleanup() {
    echo "=== Cleaning up environment ==="
    docker-compose down -v || true
}
trap cleanup EXIT

wait_for_ready() {
    local container=$1
    local port=$2
    local timeout=60
    local elapsed=0
    echo "Waiting for database in $container to be ready..."
    until docker exec "$container" /home/yugabyte/bin/ysqlsh -h "$container" -p "$port" -c "SELECT 1;" >/dev/null 2>&1; do
        sleep 1
        elapsed=$((elapsed + 1))
        if [ $elapsed -ge $timeout ]; then
            echo "Error: Timeout waiting for $container to be ready."
            exit 1
        fi
    done
    echo "$container is ready."
}

verify_replication() {
  local id=$1
  local val=$2

  echo "--- Verifying replication for ID: $id ---"

  echo "Inserting (id=$id, val='$val') into source..."
  docker exec source-tserver /home/yugabyte/bin/ysqlsh -h source-tserver -p 5433 -c "INSERT INTO test_xcluster VALUES ($id, '$val');"

  echo "Waiting for replication (up to 30s)..."
  local timeout=30
  local elapsed=0
  local result=""
  while [ $elapsed -lt $timeout ]; do
    result=$(docker exec target-tserver /home/yugabyte/bin/ysqlsh -h target-tserver -p 5433 -t -A -c "SELECT val FROM test_xcluster WHERE id = $id;")
    if [ "$result" == "$val" ]; then
      break
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  if [ "$result" == "$val" ]; then
    echo "SUCCESS: Data matched!"
  else
    echo "FAILURE: Data mismatch! Expected '$val', got '$result'"
    exit 1
  fi
}

echo "=== Building controller image ==="
docker build -t yb-ansible-controller:test controller/

echo "=== Starting YugabyteDB clusters ==="
docker-compose down -v
docker-compose up -d

echo "=== Waiting for clusters to be ready ==="
wait_for_ready source-tserver 5433
wait_for_ready target-tserver 5433

echo "=== Creating test table on source ==="
docker exec source-tserver /home/yugabyte/bin/ysqlsh -h source-tserver -p 5433 -c "CREATE TABLE test_xcluster (id INT PRIMARY KEY, val TEXT);"

echo "=== Creating test table on target ==="
docker exec target-tserver /home/yugabyte/bin/ysqlsh -h target-tserver -p 5433 -c "CREATE TABLE test_xcluster (id INT PRIMARY KEY, val TEXT);"

echo "=== Running xcluster playbook ==="
docker exec ansible-controller ansible-playbook -vvv -i inventory.docker.ini playbooks/xcluster.yml \
  -e "xcluster_source_masters=source-master:7100" \
  -e "xcluster_target_masters=target-master:7100" \
  -e '{"xcluster_databases": [{"name": "yugabyte", "type": "ysql"}]}'

echo "=== Verifying Data Replication ==="
verify_replication 1 "verified_sync_data"
verify_replication 2 "secondary_sync_check"

echo "=== All Verifications Passed ==="
