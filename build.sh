#!/bin/bash
# Repackage Cloudflare's official cloudflare-warp .deb as a Void Linux .xbps.
#
# Usage: ./build.sh [-a x86_64|aarch64] [-v VERSION] [-d local.deb] [-o OUTDIR]
#
# Without -v the newest version in Cloudflare's apt repository is used.
# The apt index is verified with Cloudflare's pinned GPG key (keys/) and the
# .deb is checked against the SHA256 in that signed index.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
APT_URL=https://pkg.cloudflareclient.com
APT_SUITE=noble
ARCH=$(xbps-uhelper arch 2>/dev/null || uname -m)
VERSION=
LOCAL_DEB=
OUTDIR=$HERE/out
REVISION=$(cat "$HERE/REVISION")

while getopts a:v:d:o: opt; do
	case $opt in
	a) ARCH=$OPTARG ;;
	v) VERSION=$OPTARG ;;
	d) LOCAL_DEB=$(realpath "$OPTARG") ;;
	o) OUTDIR=$OPTARG ;;
	*) exit 1 ;;
	esac
done

case $ARCH in
x86_64) DEB_ARCH=amd64 ;;
aarch64) DEB_ARCH=arm64 ;;
*) echo "unsupported arch: $ARCH" >&2; exit 1 ;;
esac

msg() { printf '==> %s\n' "$*" >&2; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUTDIR"
OUTDIR=$(realpath "$OUTDIR")

# --- locate and verify the upstream .deb ------------------------------------
msg "Fetching signed apt index ($APT_SUITE/$DEB_ARCH)"
curl -fsSL "$APT_URL/dists/$APT_SUITE/InRelease" -o "$WORK/InRelease"
gpg --dearmor <"$HERE/keys/cloudflare-pkg.gpg" >"$WORK/cloudflare.kbx"
gpgv --keyring "$WORK/cloudflare.kbx" --output "$WORK/Release" "$WORK/InRelease" 2>/dev/null ||
	{ echo "InRelease signature verification FAILED" >&2; exit 1; }

curl -fsSL "$APT_URL/dists/$APT_SUITE/main/binary-$DEB_ARCH/Packages" -o "$WORK/Packages"
pkgs_sum=$(sha256sum "$WORK/Packages" | cut -d' ' -f1)
grep -q " $pkgs_sum .* main/binary-$DEB_ARCH/Packages\$" "$WORK/Release" ||
	{ echo "Packages index does not match signed Release" >&2; exit 1; }

# Split the Packages index into "version filename sha256" lines.
awk '
	/^Package: /  { p=$2 }
	/^Version: /  { v=$2 }
	/^Filename: / { f=$2 }
	/^SHA256: /   { s=$2 }
	/^$/ { if (p=="cloudflare-warp") print v, f, s; p=v=f=s="" }
	END  { if (p=="cloudflare-warp") print v, f, s }
' "$WORK/Packages" | sort -V >"$WORK/versions"

if [ -z "$VERSION" ]; then
	VERSION=$(tail -n1 "$WORK/versions" | cut -d' ' -f1)
fi
read -r _ DEB_PATH DEB_SHA < <(awk -v v="$VERSION" '$1==v' "$WORK/versions" | tail -n1) ||
	{ echo "version $VERSION not found upstream" >&2; exit 1; }

PKGVER="cloudflare-warp-${VERSION}_${REVISION}"
msg "Building $PKGVER for $ARCH"

if [ -n "$LOCAL_DEB" ]; then
	cp "$LOCAL_DEB" "$WORK/warp.deb"
else
	curl -fSL "$APT_URL/$DEB_PATH" -o "$WORK/warp.deb"
	echo "$DEB_SHA  $WORK/warp.deb" | sha256sum -c - >/dev/null ||
		{ echo "SHA256 mismatch for $DEB_PATH" >&2; exit 1; }
fi

# --- unpack -----------------------------------------------------------------
mkdir -p "$WORK/deb" "$WORK/data"
(cd "$WORK/deb" && ar x "$WORK/warp.deb")
tar -xf "$WORK"/deb/data.tar.* -C "$WORK/data"
D=$WORK/data
DEST=$WORK/destdir

# --- lay out the Void package -----------------------------------------------
install -d "$DEST/usr/bin" "$DEST/usr/lib" "$DEST/usr/share"
for b in warp-cli warp-svc warp-diag warp-dex; do
	install -m755 "$D/bin/$b" "$DEST/usr/bin/$b"
done
cp -a "$D/usr/lib/warp" "$DEST/usr/lib/warp"
ln -s ../lib/warp/warp-taskbar "$DEST/usr/bin/warp-taskbar"
cp -a "$D/usr/share/." "$DEST/usr/share/"

# Debian/Ubuntu ship libpcap with soname .so.0.8; Void ships .so.1 (same ABI).
ln -s libpcap.so.1 "$DEST/usr/lib/libpcap.so.0.8"

# Desktop integration: drop the systemd bits and point at /usr/bin.
for f in "$DEST"/usr/share/applications/*.desktop "$DEST"/usr/share/dbus-1/services/*.service; do
	sed -i -e 's|/bin/warp-|/usr/bin/warp-|g' -e '/^SystemdService=/d' "$f"
done
# Start the tray/GUI on login (replaces upstream's systemd --user unit).
install -d "$DEST/etc/xdg/autostart"
sed -e '/^DBusActivatable=/d' "$DEST/usr/share/applications/com.cloudflare.WarpTaskbar.desktop" \
	>"$DEST/etc/xdg/autostart/com.cloudflare.WarpTaskbar.desktop"

# runit service for the daemon (replaces upstream's warp-svc.service).
cp -a "$HERE/files/sv" "$DEST/etc/sv"
chmod 755 "$DEST"/etc/sv/warp-svc/*
ln -s /run/runit/supervise.warp-svc "$DEST/etc/sv/warp-svc/supervise"

install -Dm644 "$HERE/files/README.voidlinux" "$DEST/usr/share/doc/cloudflare-warp/README.voidlinux"
install -m644 "$HERE/files/INSTALL" "$HERE/files/REMOVE" "$DEST/"
chmod 755 "$DEST/INSTALL" "$DEST/REMOVE"

# --- create the .xbps -------------------------------------------------------
deps=(
	glibc libgcc libstdc++ zlib dbus-libs libcurl nss tpm2-tss libpcap
	iproute2 nftables gnupg ca-certificates desktop-file-utils
	gtk+3 glib atk cairo pango gdk-pixbuf libepoxy fontconfig libharfbuzz
	libsoup3 libwebkit2gtk41 libayatana-appindicator libayatana-indicator
	ayatana-ido libdbusmenu-glib
)
dep_str=
for d in "${deps[@]}"; do dep_str+="$d>=0 "; done

cd "$OUTDIR"
rm -f "$PKGVER.$ARCH.xbps"
XBPS_ARCH=$ARCH xbps-create -A "$ARCH" \
	-n "$PKGVER" \
	-s "Cloudflare WARP / Cloudflare One client (repackaged from the official .deb)" \
	-H "https://developers.cloudflare.com/warp-client/" \
	-l "custom:Proprietary" \
	-m "cloudflare-warp-void <https://github.com/KrishnaSSH/cloudflare-warp-void>" \
	-D "${dep_str% }" \
	"$DEST"

msg "Created $OUTDIR/$PKGVER.$ARCH.xbps"
echo "$VERSION" >"$OUTDIR/VERSION"
