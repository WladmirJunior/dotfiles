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

tart attaches a cloud-init seed as a read-only disk (a filesystem labelled
`cidata` holding `user-data` + `meta-data`). cloud-init's NoCloud datasource
reads either ISO9660 **or** vfat.

For Kali, just use the script — it does all of this:

```bash
scripts/provision-kali-vm.sh            # build seed, boot, install, PASS/FAIL
```

To build a seed by hand, note that the obvious `hdiutil makehybrid -iso` path
**is blocked on the corporate Mac** (`hdiutil: makehybrid failed - Operation
not permitted`, an MDM/TCC restriction). Build a FAT image instead — that verb
(`hdiutil create`) is allowed and needs no sudo:

```bash
# 1. Pick the template for your distro
SEED=user-data.arch        # or user-data.kali

# 2. Template user-data + minimal meta-data
mkdir -p /tmp/seedfiles
cp "config/cloud-init/$SEED" /tmp/seedfiles/user-data
printf 'instance-id: tart-%s\nlocal-hostname: devvm\n' "$(date +%s)" > /tmp/seedfiles/meta-data

# 3. Build a FAT image labelled CIDATA, copy the seed files in, detach
hdiutil create -size 4m -fs MS-DOS -volname CIDATA -layout NONE -ov /tmp/cidata.img
hdiutil attach /tmp/cidata.img.dmg          # auto-mounts at /Volumes/CIDATA
cp /tmp/seedfiles/user-data /tmp/seedfiles/meta-data /Volumes/CIDATA/
hdiutil detach /Volumes/CIDATA

# 4. Clone a Linux base and boot with the seed attached read-only
tart clone ghcr.io/cirruslabs/debian:latest devvm   # arch/kali → see the script
tart run devvm --disk="/tmp/cidata.img.dmg:ro"
```

cloud-init on the guest reads the `cidata` disk on first boot and runs the
`runcmd`. Watch progress inside the guest with `cloud-init status --wait` and
`journalctl -u cloud-final` (or `tart exec devvm sudo cloud-init status --wait`).

## Before using

- SSH keys: `user-data.arch` has a `REPLACE_WITH_YOUR_SSH_PUBLIC_KEY` placeholder;
  `user-data.kali` uses a `{{SSH_AUTHORIZED_KEY}}` token that
  `provision-kali-vm.sh` templates (or strips the whole block from, since its
  Guest-Agent path needs no key). Never commit a private key.
- These are templates: the username defaults to `dev`. Adjust per VM.
- No real Kali OCI image exists for tart (checked ghcr.io/cirruslabs: `debian`
  yes, `kali` no). `user-data.kali` therefore boots the Debian base and adds the
  Kali repo + `kali-linux-headless` on first boot. Confirm any base image boots
  cloud-init (NoCloud datasource) before relying on it.
