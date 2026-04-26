## Creating a VM from Ubuntu Cloud Image with virt-install

### Prerequisites

```bash
sudo apt install -y qemu-kvm libvirt-daemon-system virtinst genisoimage
sudo usermod -aG libvirt $USER
# log out and back in for group change

# verify default network is active
virsh net-list --all
# if inactive: virsh net-start default && virsh net-autostart default
```

### 1. Download the base image

```bash
mkdir -p ~/vms
wget -O ~/vms/ubuntu-22.04-cloudimg.img \
  https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img
```

This is a qcow2 file (~660 MiB on disk, 2.2 GiB virtual). It contains a minimal Ubuntu with cloud-init pre-installed but no users, no network config, and no SSH keys.

### 2. Create a copy-on-write disk overlay

```bash
qemu-img create -f qcow2 \
  -b ~/vms/ubuntu-22.04-cloudimg.img -F qcow2 \
  ~/vms/my-vm.qcow2 20G
```

- The overlay starts nearly empty (a few KB)
- Reads fall through to the base image; writes go to the overlay
- The base image is never modified — safe to share across many VMs
- `20G` is the virtual disk size the guest will see; cloud-init auto-grows the partition on first boot

### 3. Write cloud-init configuration files

Cloud-init expects three files: `meta-data`, `user-data`, and `network-config`.

**meta-data** — instance identity:
```bash
cat > ~/vms/my-vm-meta-data <<'EOF'
instance-id: my-vm
local-hostname: my-vm
EOF
```

**user-data** — users, SSH keys, packages:
```bash
cat > ~/vms/my-vm-user-data <<'EOF'
#cloud-config
hostname: my-vm
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAA...your-public-key... user@host
packages:
  - openssh-server
EOF
```

Replace `ssh-ed25519 AAAA...` with your actual public key from `cat ~/.ssh/id_ed25519.pub`.

**network-config** — enable DHCP:
```bash
cat > ~/vms/my-vm-network-config <<'EOF'
version: 2
ethernets:
  enp1s0:
    dhcp4: true
EOF
```

### 4. Create the cloud-init ISO

Cloud-init discovers its config via a CD-ROM with volume label `cidata`. The filenames inside the ISO **must** be exactly `user-data`, `meta-data`, and `network-config`.

```bash
genisoimage -output ~/vms/my-vm-cidata.iso \
  -volid cidata -joliet -rock -graft-points \
  user-data=~/vms/my-vm-user-data \
  meta-data=~/vms/my-vm-meta-data \
  network-config=~/vms/my-vm-network-config
```

The `-graft-points` flag with `target=source` syntax ensures correct filenames inside the ISO regardless of the source file paths. Without it, the full path basename ends up in the ISO and cloud-init won't find the files.

Verify the ISO contents:
```bash
isoinfo -i ~/vms/my-vm-cidata.iso -J -l
# Should show: meta-data, network-config, user-data
```

### 5. Create and boot the VM

```bash
virt-install \
  --name my-vm \
  --vcpus 2 \
  --memory 2048 \
  --disk path=~/vms/my-vm.qcow2,format=qcow2,bus=virtio \
  --disk path=~/vms/my-vm-cidata.iso,device=cdrom \
  --os-variant ubuntu22.04 \
  --network network=default \
  --graphics none \
  --noautoconsole \
  --import
```

Key flags:
- `--import` — boot from existing disk image (no OS installer)
- `--disk ...device=cdrom` — attaches the cidata ISO so cloud-init can find it
- `--network network=default` — uses libvirt's default NAT network with DHCP
- `--noautoconsole` — returns to the shell instead of attaching to the VM console

### 6. Wait for the VM and get its IP

```bash
# Wait for DHCP to assign an IP (usually 10-30 seconds)
virsh domifaddr my-vm
```

Output looks like:
```
 Name       MAC address          Protocol     Address
---------------------------------------------------------------
 vnet0      52:54:00:xx:xx:xx    ipv4         192.168.122.123/24
```

### 7. Wait for cloud-init before SSH

SSH port 22 opens before cloud-init finishes writing `authorized_keys`. Connecting too early gives `Permission denied (publickey)`.

```bash
# Wait for cloud-init to complete
ssh -o StrictHostKeyChecking=no ubuntu@192.168.122.123 'cloud-init status --wait'

# Now SSH works normally
ssh ubuntu@192.168.122.123
```

### 8. Managing the VM

```bash
virsh list --all              # list VMs
virsh start my-vm             # start
virsh shutdown my-vm          # graceful shutdown
virsh destroy my-vm           # force stop (like pulling the power)
virsh console my-vm           # serial console (Ctrl+] to exit)

# Snapshots (VM must be shut off for offline snapshots)
virsh shutdown my-vm
virsh snapshot-create-as my-vm clean-base --description "Fresh OS"
virsh start my-vm
# ... use the VM ...
virsh destroy my-vm
virsh snapshot-revert my-vm clean-base   # restore to snapshot
virsh start my-vm                        # boots from clean state

# Delete VM completely
virsh destroy my-vm 2>/dev/null
virsh snapshot-delete my-vm clean-base 2>/dev/null
virsh undefine my-vm --snapshots-metadata --remove-all-storage
rm -f ~/vms/my-vm-cidata.iso ~/vms/my-vm-meta-data ~/vms/my-vm-user-data ~/vms/my-vm-network-config
```

### Troubleshooting

If SSH never works:

1. **Check cidata ISO filenames**: `isoinfo -i ~/vms/my-vm-cidata.iso -J -l` — must be `user-data`, `meta-data`, `network-config`
2. **Check your SSH key matches**: compare `cat ~/.ssh/id_ed25519.pub` with what's in `my-vm-user-data`
3. **Serial console**: `virsh console my-vm` — but needs a password in user-data to log in:
   ```yaml
   chpasswd:
     list: |
       ubuntu:debug
     expire: false
   ```
4. **Mount disk offline**: shut down VM, then `sudo qemu-nbd --connect=/dev/nbd0 ~/vms/my-vm.qcow2 && sudo mount /dev/nbd0p1 /mnt && cat /mnt/var/log/cloud-init.log`
