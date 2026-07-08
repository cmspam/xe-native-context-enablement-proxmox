# xe-native-context-enablement-proxmox

Drop-in `.deb` packages for Proxmox VE 9 (trixie) that enable
`drm_native_context` for Intel Xe (and other supported GPUs) in guests,
giving VA-API hardware video decode/encode and direct GPU command
submission from the VM.

Two pieces are needed and both are shipped here:

1. `virglrenderer` rebuilt from upstream with the
   [xe-native-context patch][xe] and all `drm-renderers` enabled
   (`amdgpu`, `panfrost`, `asahi`, `msm`, `i915`, `xe`), plus `venus`,
   `video`, and `sysprof` tracing.
2. `pve-qemu-kvm` rebuilt to link that `virglrenderer`. This is the part
   that is easy to miss: stock `pve-qemu-kvm` is built against Debian
   trixie's `virglrenderer` (1.1.0), which lacks the native-context API
   at build time, so QEMU stubs it out. Shipping a patched
   `virglrenderer` alone does nothing until QEMU is rebuilt against it.

[xe]: https://github.com/cmspam/xe-native-context-enablement

## Install

On the Proxmox host:

```sh
curl -fsSL https://raw.githubusercontent.com/cmspam/xe-native-context-enablement-proxmox/main/install.sh | sudo bash
```

This installs `libvirglrenderer1`, `virgl-server`, and `pve-qemu-kvm`,
then `apt-mark hold`s them so `apt upgrade` does not replace them.

Stop and start (not just reboot from inside) your VMs afterwards so they
launch under the rebuilt QEMU.

Or download the `.deb` files from the latest [release][rel] and
`dpkg -i` them yourself.

[rel]: https://github.com/cmspam/xe-native-context-enablement-proxmox/releases/latest

## Enabling native context in a VM

Installing the packages is not enough on its own; each guest also has to
be told to use the native-context GPU. Do this in the VM's own config,
not by editing anything under `/usr/share/perl5/PVE`.

Set the display to VirGL and add QEMU `-set` overrides that turn on
native context for the device Proxmox already builds:

```sh
qm set <vmid> --vga virtio-gl
qm set <vmid> --args "-set device.vga.blob=on -set device.vga.hostmem=4G -set device.vga.max_hostmem=4G -set device.vga.drm_native_context=on"
```

which leaves the config (`/etc/pve/qemu-server/<vmid>.conf`) as:

```
vga: virtio-gl
args: -set device.vga.blob=on -set device.vga.hostmem=4G -set device.vga.max_hostmem=4G -set device.vga.drm_native_context=on
```

`vga: virtio-gl` makes Proxmox build a `virtio-vga-gl` device with an
`egl-headless` display and its normal managed SPICE, so the web
`Console -> SPICE` button keeps working. The `-set device.vga.<prop>`
lines modify that same device by id (`vga`), so nothing is duplicated
and no Proxmox file is patched, and it survives package upgrades. Adjust
`hostmem`/`max_hostmem` to taste; `max_hostmem` must be at least
`hostmem`.

The host needs `libgl1` and `libegl1` installed; Proxmox's VirGL display
refuses to start without both.

Stop and start the VM, then confirm inside the guest that the real
driver is in use rather than the virgl translation layer:

```sh
glxinfo -B | grep -i renderer
```

A working AMD guest reports something like `AMD Radeon Graphics
(radeonsi, ...)`. If it says `virgl`, native context did not engage.

## Uninstall

Release the holds and reinstall the stock Proxmox versions:

```sh
sudo apt-mark unhold libvirglrenderer1 virgl-server pve-qemu-kvm
sudo apt-get install --reinstall --allow-downgrades \
  libvirglrenderer1 virgl-server pve-qemu-kvm
```

## How it works

A daily GitHub Actions job checks for a new upstream `virglrenderer`
release, a new commit to the patch in
`cmspam/xe-native-context-enablement`, or a new `pve-qemu` version. If
any changed, it rebuilds both packages and publishes them to a new
GitHub Release.

- `virglrenderer` is built in a `debian:trixie` container.
- `pve-qemu-kvm` is built from `git.proxmox.com/git/pve-qemu.git` with
  the just-built `libvirglrenderer-dev` installed, so QEMU compiles in
  native context.

`virglrenderer` is versioned `1:<upstream>-1+xe.<patch-sha>` (the epoch
makes it outrank Trixie's copy). `pve-qemu-kvm` is versioned
`<pve-qemu-version>+virgl<virgl-version>` so it outranks the exact stock
package it was built from. `apt-mark hold` keeps both in place.

## License

MIT.
