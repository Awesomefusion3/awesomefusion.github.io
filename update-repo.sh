#!/usr/bin/env bash
# update-repo.sh — rebuild an iOS tweak repo's index files.
#
# Usage:
#   ./update-repo.sh            rebuild Packages + Release
#   ./update-repo.sh --push     rebuild, then git commit and push
#
# Run from the root of your repo folder (the one containing debs/).
# Requires: dpkg-scanpackages (macOS: brew install dpkg; Linux: apt install dpkg-dev)
# Optional: apt-ftparchive (adds checksums to Release), xz, zstd

set -euo pipefail

# ---- Edit these to match your repo ----
ORIGIN="awesomefusion"
LABEL="awesomefusion"
DESCRIPTION="Petal, Nebula & Sky for iOS 16"
ARCHITECTURES="iphoneos-arm64"
DEBS_DIR="debs"
# ---------------------------------------

cd "$(dirname "$0")"

die() { echo "Error: $*" >&2; exit 1; }

command -v dpkg-scanpackages >/dev/null 2>&1 \
  || die "dpkg-scanpackages not found. Install with 'brew install dpkg' (macOS) or 'sudo apt install dpkg-dev' (Linux)."

[ -d "$DEBS_DIR" ] || die "No '$DEBS_DIR/' folder found. Create it and put your .deb files inside."

shopt -s nullglob
debs=("$DEBS_DIR"/*.deb)
[ ${#debs[@]} -gt 0 ] || die "No .deb files in '$DEBS_DIR/'."

echo "==> Scanning ${#debs[@]} package(s)..."
rm -f Packages Packages.bz2 Packages.gz Packages.xz Packages.zst
dpkg-scanpackages -m "./$DEBS_DIR" /dev/null > Packages 2>/dev/null

echo "==> Compressing Packages..."
bzip2 -kf9 Packages
gzip -kf9 Packages
command -v xz   >/dev/null 2>&1 && xz -kf9 Packages
command -v zstd >/dev/null 2>&1 && zstd -qkf -19 Packages

echo "==> Writing Release..."
cat > Release <<EOF
Origin: $ORIGIN
Label: $LABEL
Suite: stable
Version: 1.0
Codename: ios
Architectures: $ARCHITECTURES
Components: main
Description: $DESCRIPTION
EOF

if command -v apt-ftparchive >/dev/null 2>&1; then
  # Hash only the index files, not the debs or the Release file itself
  apt-ftparchive \
    -o APT::FTPArchive::Release::Patterns::="Packages*" \
    release . | grep -v '^Date:' >> Release || true
  echo "    (checksums added)"
else
  echo "    (apt-ftparchive not found — skipping checksums; repo still works)"
fi

echo "==> Done. $(grep -c '^Package:' Packages) package entr(ies) indexed."

if [ "${1:-}" = "--push" ]; then
  command -v git >/dev/null 2>&1 || die "git not found."
  echo "==> Committing and pushing..."
  git add -A
  if git diff --cached --quiet; then
    echo "    Nothing changed."
  else
    git commit -m "Update repo $(date '+%Y-%m-%d %H:%M')"
    git push
  fi
fi
