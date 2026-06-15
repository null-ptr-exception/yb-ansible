#!/bin/bash
set -euo pipefail

# Global to track snapshot ID for cleanup
SNAPSHOT_ID=""

cleanup() {
    echo "===> Cleaning up test resources..."
    # Drop tables
    docker exec source-tserver /home/yugabyte/bin/ysqlsh -h source-tserver -p 5433 -c "DROP TABLE IF EXISTS test_restore;" >/dev/null 2>&1 || true
    docker exec target-tserver /home/yugabyte/bin/ysqlsh -h target-tserver -p 5433 -c "DROP TABLE IF EXISTS test_restore;" >/dev/null 2>&1 || true
    # Delete snapshot from source and target
    if [ -n "$SNAPSHOT_ID" ]; then
        docker exec ansible-controller yb-admin -master_addresses source-master:7100 delete_snapshot "$SNAPSHOT_ID" >/dev/null 2>&1 || true
        docker exec ansible-controller yb-admin -master_addresses target-master:7100 delete_snapshot "$SNAPSHOT_ID" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

echo "===> Checking environment..."
REQUIRED_SERVICES=("source-master" "source-tserver" "target-master" "target-tserver" "ansible-controller" "minio")
RUNNING_SERVICES=$(docker-compose ps --services --filter "status=running")

MISSING_SERVICES=()
for service in "${REQUIRED_SERVICES[@]}"; do
    if ! echo "$RUNNING_SERVICES" | grep -Fqx "$service"; then
        MISSING_SERVICES+=("$service")
    fi
done

if [ ${#MISSING_SERVICES[@]} -ne 0 ]; then
    echo "Error: The following required Docker Compose services are not running: ${MISSING_SERVICES[*]}"
    echo "Please run 'docker-compose up -d' to start them."
    exit 1
fi

echo "===> Environment OK."

# Error Path Test 1: Invalid Snapshot ID
echo "===> Testing backup error path (invalid snapshot ID)..."
if docker exec ansible-controller ansible-playbook -i inventory.docker.ini playbooks/backup.yml \
  --limit source-master,source-tserver \
  -e "yb_master_addresses=source-master:7100" \
  -e "yb_snapshot_id=00000000-0000-0000-0000-000000000000" \
  -e "yb_backup_minio_endpoint=http://minio:9000" \
  -e "yb_backup_minio_access_key=minioadmin" \
  -e "yb_backup_minio_secret_key=minioadmin" \
  -e "yb_tserver_data_dir=/home/yugabyte/yb_data"; then
    echo "Error: Backup playbook succeeded with an invalid snapshot ID!"
    exit 1
else
    echo "Success: Backup playbook failed as expected with invalid snapshot ID."
fi

# Error Path Test 2: Unreachable MinIO
echo "===> Testing backup error path (unreachable Minio)..."
if docker exec ansible-controller ansible-playbook -i inventory.docker.ini playbooks/backup.yml \
  --limit source-master,source-tserver \
  -e "yb_master_addresses=source-master:7100" \
  -e "yb_snapshot_id=00000000-0000-0000-0000-000000000000" \
  -e "yb_backup_minio_endpoint=http://localhost:9999" \
  -e "yb_backup_minio_access_key=minioadmin" \
  -e "yb_backup_minio_secret_key=minioadmin" \
  -e "yb_tserver_data_dir=/home/yugabyte/yb_data"; then
    echo "Error: Backup playbook succeeded with unreachable Minio endpoint!"
    exit 1
else
    echo "Success: Backup playbook failed as expected with unreachable Minio."
fi

# Happy Path Test
echo "===> Seeding data on source cluster..."
docker exec source-tserver /home/yugabyte/bin/ysqlsh -h source-tserver -p 5433 -c "
DROP TABLE IF EXISTS test_restore;
CREATE TABLE test_restore (id INT PRIMARY KEY, val TEXT);
INSERT INTO test_restore VALUES (1, 'verified data $(date +%s)');
"

EXPECTED_VAL=$(docker exec source-tserver /home/yugabyte/bin/ysqlsh -h source-tserver -p 5433 -Atc "SELECT val FROM test_restore WHERE id = 1;")
echo "Seed data: $EXPECTED_VAL"

echo "===> Creating snapshot on source..."
SNAPSHOT_OUT=$(docker exec ansible-controller ansible-playbook -i inventory.docker.ini playbooks/snapshot.yml -e "yb_master_addresses=source-master:7100")
SNAPSHOT_ID=$(echo "$SNAPSHOT_OUT" | grep -oP 'Snapshot ID: \K[a-f0-9-]+' | head -1)
echo "Snapshot ID: $SNAPSHOT_ID"

echo "===> Backing up source to Minio..."
docker exec ansible-controller ansible-playbook -i inventory.docker.ini playbooks/backup.yml \
  --limit source-master,source-tserver \
  -e "yb_master_addresses=source-master:7100" \
  -e "yb_snapshot_id=$SNAPSHOT_ID" \
  -e "yb_backup_minio_endpoint=http://minio:9000" \
  -e "yb_backup_minio_access_key=minioadmin" \
  -e "yb_backup_minio_secret_key=minioadmin" \
  -e "yb_tserver_data_dir=/home/yugabyte/yb_data"

echo "===> Preparing target cluster..."
docker exec target-tserver /home/yugabyte/bin/ysqlsh -h target-tserver -p 5433 -c "
DROP TABLE IF EXISTS test_restore;
CREATE TABLE test_restore (id INT PRIMARY KEY, val TEXT);
"

echo "===> Restoring to target cluster..."
docker exec ansible-controller ansible-playbook -i inventory.docker.ini playbooks/restore.yml \
  --limit target-master,target-tserver \
  -e "yb_master_addresses=target-master:7100" \
  -e "yb_snapshot_id=$SNAPSHOT_ID" \
  -e "yb_restore_source_hostname=source-tserver" \
  -e "yb_restore_source=minio" \
  -e "yb_backup_minio_endpoint=http://minio:9000" \
  -e "yb_backup_minio_access_key=minioadmin" \
  -e "yb_backup_minio_secret_key=minioadmin" \
  -e "yb_tserver_data_dir=/home/yugabyte/yb_data"

echo "===> Verifying data on target cluster..."
ACTUAL_VAL=$(docker exec target-tserver /home/yugabyte/bin/ysqlsh -h target-tserver -p 5433 -Atc "SELECT val FROM test_restore WHERE id = 1;")

if [ "$ACTUAL_VAL" == "$EXPECTED_VAL" ]; then
    echo "SUCCESS: Data restored correctly!"
else
    echo "FAILURE: Data mismatch. Expected '$EXPECTED_VAL', got '$ACTUAL_VAL'"
    exit 1
fi
