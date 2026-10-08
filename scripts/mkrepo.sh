#!/bin/sh
# Index and sign every .xbps in a directory as an xbps repository.
# Usage: scripts/mkrepo.sh REPODIR PRIVKEY
set -eu
REPO=$1
KEY=$2
SIGNEDBY=${SIGNEDBY:-cloudflare-warp-void <https://github.com/KrishnaSSH/cloudflare-warp-void>}

for arch in x86_64 aarch64; do
	set -- "$REPO"/*."$arch".xbps
	[ -e "$1" ] || continue
	XBPS_TARGET_ARCH=$arch xbps-rindex -a "$@"
	XBPS_TARGET_ARCH=$arch xbps-rindex --sign --signedby "$SIGNEDBY" --privkey "$KEY" "$REPO"
	XBPS_TARGET_ARCH=$arch xbps-rindex --sign-pkg --privkey "$KEY" "$@"
done
ls -l "$REPO"
