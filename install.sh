#!/usr/bin/env bash
set -euo pipefail

REPO=cmspam/xe-native-context-enablement-proxmox
PKGS=(libvirglrenderer1 virgl-server pve-qemu-kvm)

if [[ $EUID -ne 0 ]]; then
  echo "Run as root (sudo)." >&2
  exit 1
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
cd "$tmpdir"

echo "Querying latest release of $REPO..."
urls=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
  | grep -oE '"browser_download_url": *"[^"]+\.deb"' \
  | sed -E 's/.*"(https[^"]+)".*/\1/')

if [[ -z "$urls" ]]; then
  echo "No .deb assets found in latest release." >&2
  exit 1
fi

want=()
for pkg in "${PKGS[@]}"; do
  match=$(echo "$urls" | grep -E "/${pkg}_[^/]+\.deb$" | head -1 || true)
  if [[ -z "$match" ]]; then
    echo "Missing $pkg .deb in latest release." >&2
    exit 1
  fi
  want+=("$match")
done

echo "Downloading:"
for u in "${want[@]}"; do
  echo "  $u"
  curl -fsSL -O "$u"
done

echo "Installing..."
apt-get install -y --reinstall ./*.deb

echo "Holding packages so apt upgrade does not replace them..."
apt-mark hold "${PKGS[@]}"

echo
echo "Done. The pve-qemu-kvm rebuild only takes effect for VMs started"
echo "afterwards, so stop and start (not just reboot) your VMs, or migrate"
echo "them, to pick up drm_native_context."
