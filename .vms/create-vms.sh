#!/usr/bin/env bash
set -euo pipefail

BASE_IMG="/home/rophy/projects/db-perf-test/.vms/ubuntu-22.04-cloudimg.img"
VM_DIR="/home/rophy/projects/yb-ansible/.vms"
SSH_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINtJBZHaT6eSByrSE/min8SywDzig9Kou1Q5TwCPpsCD rophy"

create_vm() {
  local name=$1 vcpus=$2 ram_mb=$3 disk_gb=${4:-10}

  echo "=== Creating $name (${vcpus} vCPU, ${ram_mb} MB RAM, ${disk_gb} GB disk) ==="

  # Create disk from base image
  qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "${VM_DIR}/${name}.qcow2" "${disk_gb}G"

  # Create cloud-init meta-data
  cat > "${VM_DIR}/${name}-meta-data" <<METAEOF
instance-id: ${name}
local-hostname: ${name}
METAEOF

  # Create cloud-init user-data
  cat > "${VM_DIR}/${name}-user-data" <<USEREOF
#cloud-config
hostname: ${name}
packages:
  - openssh-server
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ${SSH_KEY}
USEREOF

  # Create cloud-init network-config
  cat > "${VM_DIR}/${name}-network-config" <<NETEOF
version: 2
ethernets:
  enp1s0:
    dhcp4: true
NETEOF

  # Create cloud-init ISO (files must be named user-data, meta-data, network-config)
  local tmpdir
  tmpdir=$(mktemp -d)
  cp "${VM_DIR}/${name}-user-data" "${tmpdir}/user-data"
  cp "${VM_DIR}/${name}-meta-data" "${tmpdir}/meta-data"
  cp "${VM_DIR}/${name}-network-config" "${tmpdir}/network-config"
  genisoimage -output "${VM_DIR}/${name}-cidata.iso" \
    -volid cidata -joliet -rock \
    "${tmpdir}/user-data" "${tmpdir}/meta-data" "${tmpdir}/network-config" 2>/dev/null
  rm -rf "$tmpdir"

  # Create and start VM
  virt-install \
    --name "$name" \
    --vcpus "$vcpus" \
    --memory "$ram_mb" \
    --disk "path=${VM_DIR}/${name}.qcow2,format=qcow2,bus=virtio,cache=none,io=native" \
    --disk "path=${VM_DIR}/${name}-cidata.iso,device=cdrom" \
    --os-variant ubuntu22.04 \
    --network network=default \
    --graphics none \
    --noautoconsole \
    --import

  echo "=== $name created ==="
}

# Masters: 1 vCPU, 1 GB RAM, 10 GB disk
create_vm ygvm-master-1 1 1024
create_vm ygvm-master-2 1 1024
create_vm ygvm-master-3 1 1024

# TServers: 2 vCPU, 2 GB RAM, 20 GB disk
create_vm ygvm-tserver-1 2 2048 20

echo ""
echo "All VMs created. Waiting for IPs..."
sleep 30

for vm in ygvm-master-1 ygvm-master-2 ygvm-master-3 ygvm-tserver-1; do
  ip=$(virsh domifaddr "$vm" 2>/dev/null | grep -oP '(\d+\.){3}\d+' || echo "pending...")
  echo "$vm: $ip"
done
