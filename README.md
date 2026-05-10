# xe-native-context-enablement-proxmox

`virglrenderer` `.deb` packages for Proxmox VE 9 (trixie) with the
[xe-native-context patch][xe] applied and all upstream `drm-renderers`
enabled (`amdgpu`, `panfrost`, `asahi`, `msm`, `i915`, `xe`), plus
`venus`, `video`, and `sysprof` tracing.

This lets Proxmox VMs use `drm_native_context` for Intel Xe (and other
supported GPUs), enabling VA-API hardware video decode/encode and direct
GPU command submission from the guest.

[xe]: https://github.com/cmspam/xe-native-context-enablement

## Install

On the Proxmox host:

```sh
curl -fsSL https://raw.githubusercontent.com/cmspam/xe-native-context-enablement-proxmox/main/install.sh | sudo bash
```

Or download `.deb` files from the latest [release][rel] and `dpkg -i`
them yourself.

[rel]: https://github.com/cmspam/xe-native-context-enablement-proxmox/releases/latest

## Uninstall

```sh
sudo apt-mark unhold libvirglrenderer1 virgl-server
sudo apt-get install --reinstall libvirglrenderer1 virgl-server
```

## How it works

A daily GitHub Actions job checks for a new upstream `virglrenderer`
release or a new commit to the patch in `cmspam/xe-native-context-enablement`.
If either changed, it rebuilds inside a `debian:trixie` container and
publishes the `.deb` files to a new GitHub Release.

Versions are stamped `1:<upstream>-1+xe.<patch-sha>` — the epoch makes
the package outrank Trixie's distribution copy, and `apt-mark hold`
prevents `apt upgrade` from touching it.

## License

MIT.
