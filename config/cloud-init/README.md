# cloud-init seeds for Linux tart VMs

cloud-init is the Linux first-boot provisioner (the layer below Ansible in the
IaC stack). macOS VMs don't use it — for those, use `scripts/provision-vm.sh`,
which provisions via the tart Guest Agent (`tart exec`).

These `user-data` files configure a fresh Linux VM on first boot: create the
user, inject an SSH key, install git, clone the dotfiles, and run
`install.sh minimal`. Result: "create a Linux VM + provision it" = one boot.

## Files

- `user-data.arch` — Arch Linux (pacman)
- `user-data.kali`  — Kali Linux (apt)

Both read the same dotfiles installer; they differ only in the package manager
bootstrap (cloud-init needs git present before the runcmd clone).

## How to seed a tart Linux VM

tart attaches a cloud-init seed as a read-only disk (an ISO with `user-data` +
`meta-data` labelled `cidata`). Build the seed and boot:

```bash
# 1. Pick the template for your distro
SEED=user-data.arch        # or user-data.kali

# 2. Build a cidata ISO (needs a NoCloud seed: user-data + minimal meta-data)
mkdir -p /tmp/seed && cp "config/cloud-init/$SEED" /tmp/seed/user-data
printf 'instance-id: tart-%s\nlocal-hostname: devvm\n' "$(date +%s)" > /tmp/seed/meta-data
# hdiutil makes a labelled ISO on macOS:
hdiutil makehybrid -iso -joliet -default-volume-name cidata \
  -o /tmp/cidata.iso /tmp/seed

# 3. Clone a Linux base and boot with the seed attached read-only
tart clone ghcr.io/cirruslabs/ubuntu:latest devvm   # or an arch/kali base image
tart run devvm --disk="/tmp/cidata.iso:ro"
```

cloud-init on the guest reads the `cidata` disk on first boot and runs the
`runcmd`. Watch progress inside the guest with `cloud-init status --wait` and
`journalctl -u cloud-final`.

## Before using

- Replace `REPLACE_WITH_YOUR_SSH_PUBLIC_KEY` with your actual public key (or wire
  it in from 1Password at seed-build time — never commit a private key).
- These are templates: the username defaults to `dev`. Adjust per VM.
- A real Arch/Kali base image for tart is needed (cirruslabs publishes some; or
  build your own). Confirm the image boots cloud-init (NoCloud datasource).
