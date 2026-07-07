#!/usr/bin/env bash
#
# Rebuild pve-qemu-kvm against our patched virglrenderer so that
# drm_native_context is compiled in. Stock Proxmox pve-qemu-kvm links
# Debian trixie's virglrenderer (1.1.0), which lacks the native-context
# API at build time and stubs it out. Building against our 1.3.0 + xe
# libvirglrenderer-dev turns it back on.
#
# Runs inside a debian:trixie container. Expects:
#   /host                     working directory (mounted from the runner)
#   /host/virgl/*.deb         our virglrenderer .debs (libvirglrenderer1 + -dev)
# Environment:
#   VIRGL_VER                 upstream virglrenderer version (for the qemu version suffix)
# Produces:
#   /host/out/pve-qemu-kvm_*.deb
#
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

: "${VIRGL_VER:?VIRGL_VER must be set}"

# Proxmox Trixie Release Key (rsa4096, expires 2034-11-10). Proxmox does not
# publish this key at a stable standalone URL yet, only inside the keyring
# .deb, and download.proxmox.com is served over HTTP (its repos rely on GPG
# signatures, not TLS). We bootstrap trust by fetching that .deb and refusing
# to proceed unless the embedded key matches this pinned fingerprint; a
# fingerprint is a cryptographic hash of the key, so HTTP transport cannot be
# used to substitute a different key, and apt then verifies the signed repo.
PMX_KEY_FPR="24B30F06ECC1836A4E5EFECBA7BCD1420BFE778E"
PMX_KEYRING_DEB="http://download.proxmox.com/debian/pve/dists/trixie/pve-no-subscription/binary-amd64/proxmox-archive-keyring_4.0_all.deb"

echo "::group::Install build prerequisites"
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg git \
  build-essential devscripts dpkg-dev equivs fakeroot quilt meson
echo "::endgroup::"

echo "::group::Bootstrap Proxmox trixie repository (fingerprint-pinned)"
tmp="$(mktemp -d)"
curl -fsSL "$PMX_KEYRING_DEB" -o "$tmp/keyring.deb"
dpkg-deb -x "$tmp/keyring.deb" "$tmp/kr"
key="$tmp/kr/usr/share/keyrings/proxmox-release-trixie.gpg"
got="$(gpg --show-keys --with-colons "$key" | awk -F: '/^fpr:/{print $10; exit}')"
if [[ "$got" != "$PMX_KEY_FPR" ]]; then
  echo "Proxmox trixie key fingerprint mismatch: got '$got', want '$PMX_KEY_FPR'" >&2
  exit 1
fi
install -Dm0644 "$key" /etc/apt/keyrings/proxmox-release-trixie.gpg
echo "deb [signed-by=/etc/apt/keyrings/proxmox-release-trixie.gpg] http://download.proxmox.com/debian/pve trixie pve-no-subscription" \
  > /etc/apt/sources.list.d/pve.list
# pve-qemu build-deps may pull firmware/contrib packages.
sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
apt-get update
echo "::endgroup::"

echo "::group::Install patched virglrenderer and pin it"
apt-get install -y --no-install-recommends \
  /host/virgl/libvirglrenderer1_*.deb \
  /host/virgl/libvirglrenderer-dev_*.deb
apt-mark hold libvirglrenderer1 libvirglrenderer-dev
echo "virglrenderer at build time:"
dpkg-query -W -f='  ${Package} ${Version}\n' libvirglrenderer1 libvirglrenderer-dev
echo "::endgroup::"

echo "::group::Fetch pve-qemu source"
cd /host
rm -rf pve-qemu
git clone --depth 1 https://git.proxmox.com/git/pve-qemu.git
cd pve-qemu
BASE="$(dpkg-parsechangelog -S Version)"   # e.g. 11.0.2-1
UPSTREAM="${BASE%-*}"                        # e.g. 11.0.2
NEWVER="${BASE}+virgl${VIRGL_VER}"           # e.g. 11.0.2-1+virgl1.3.0
echo "pve-qemu base=$BASE upstream=$UPSTREAM new=$NEWVER"
echo "::endgroup::"

echo "::group::Bump changelog"
# A new higher version so the rebuild outranks the stock package on the exact
# base it was built from, and so the host can 'apt-mark hold' it.
DATE="$(date -uR)"
tmpcl="$(mktemp)"
cat > "$tmpcl" <<EOF
pve-qemu-kvm (${NEWVER}) trixie; urgency=medium

  * Rebuild of pve-qemu-kvm ${BASE} linked against virglrenderer ${VIRGL_VER}
    with the xe-native-context patch, enabling drm_native_context in guests.

 -- cmspam <cmspam@users.noreply.github.com>  ${DATE}

EOF
cat debian/changelog >> "$tmpcl"
mv "$tmpcl" debian/changelog
echo "::endgroup::"

echo "::group::Install pve-qemu build dependencies"
# Our held virglrenderer (epoch 1:) already satisfies the unversioned
# libvirglrenderer-dev build-dep, so apt keeps it instead of pulling 1.1.0.
mk-build-deps -i -t 'apt-get -y --no-install-recommends' debian/control
rm -f pve-qemu-kvm-build-deps_*.deb
echo "::endgroup::"

echo "::group::Build pve-qemu-kvm"
# 'make <builddir>' runs the submodule init, 'meson subprojects download',
# and blob purge, then stages the debian/ tree. We drive dpkg-buildpackage
# ourselves to skip the lintian gate that 'make deb' would run.
make "pve-qemu-kvm-${UPSTREAM}"
cd "pve-qemu-kvm-${UPSTREAM}"
dpkg-buildpackage -b -us -uc
echo "::endgroup::"

echo "::group::Collect artifacts"
mkdir -p /host/out
# The main runtime package only; the -dbgsym package is large and not needed.
mv /host/pve-qemu/pve-qemu-kvm_*.deb /host/out/
ls -la /host/out
echo "::endgroup::"
