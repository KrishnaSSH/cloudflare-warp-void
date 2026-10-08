#!/bin/sh
# Install Cloudflare WARP on Void Linux from the cloudflare-warp-void xbps repo.
#
#   curl -fsSL https://raw.githubusercontent.com/KrishnaSSH/cloudflare-warp-void/main/install.sh | sudo sh
#
# Adds the repository to /etc/xbps.d, installs cloudflare-warp and enables
# the warp-svc runit service.
set -eu

REPO_URL=${REPO_URL:-https://github.com/KrishnaSSH/cloudflare-warp-void/releases/latest/download}
CONF=/etc/xbps.d/20-cloudflare-warp.conf

if [ "$(id -u)" != 0 ]; then
	echo "Please run as root, e.g.: curl -fsSL <url>/install.sh | sudo sh" >&2
	exit 1
fi
if ! command -v xbps-install >/dev/null; then
	echo "This installer is for Void Linux (xbps)." >&2
	exit 1
fi
case $(xbps-uhelper arch) in
x86_64 | aarch64) ;;
*)
	echo "Unsupported architecture $(xbps-uhelper arch): Cloudflare only ships glibc x86_64/aarch64 builds." >&2
	exit 1
	;;
esac

echo ">> Adding repository $REPO_URL"
mkdir -p /etc/xbps.d /var/db/xbps/keys
echo "repository=$REPO_URL" >"$CONF"

# Pin the repository signing key (also in keys/ of the git repo), so xbps
# does not have to ask whether to trust it.
KEY=/var/db/xbps/keys/91:5e:4e:5f:89:9c:46:23:b7:4d:d1:77:57:c6:50:fa.plist
[ -e "$KEY" ] || cat >"$KEY" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple Computer//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>public-key</key>
	<data>LS0tLS1CRUdJTiBQVUJMSUMgS0VZLS0tLS0KTUlJQ0lqQU5CZ2txaGtpRzl3MEJBUUVGQUFPQ0FnOEFNSUlDQ2dLQ0FnRUFtb3JiL3RKaDgwZnRON1A5TzIwagpveTd5cGZacjhvUWRvUStqL2lXa1VaQkZHQWRSU1lscFVCTjZHem9la3ZVVkcyUHk5cXJhZk1pYUc4K2lvWFRnCkN0dDFQbGYyclN2VU1uTnVJRnRBdDkrakdvbFJndVhBRXRkQTlNYWM1TFdqK0xQODlOTklNcGtQYjZSR1ZiOHcKcGhOV0ZtSnlNSk1wdWVicXpzNFRDNFdhV0hUYnF0dkhMWFJYTmtxQjhVVDlyLzV0a3JGdUplWmRYaUpyUmI1awptaWd6UnFtQlkweFhVbjgxNzRQMVB0NWh5N2ZXcG8xOSt6MWZRaWlvT3RUNms5T0JqLzY0MGJRb3JFc0trVFJ6Ckt3WHRENXhtRjdOTE5BWXhON0NTak1GMmlnMHJtRzJKWWF1VzlybnZvQ2kxZDZlYXJ2Vk00eEZTTG9oREdWbWwKWVRHZFlHN29wWURMcktFOUdJejFPK2xtV1A0TU9LeVlXeCtqYmFzcVUzRFplVDRtVXdLSFE4VVBGelZ3bS9WWQpwOExLbm9GL3BOcWNmQzZMU0lvLzZGam5BM3IvdVNaSXRzZEVrVkFreHFVazFWK1UzczhxaHBnSWhkRDRlOG9NCjJuNWY3VnFwMC9hckZQTWNpVXVYMDlDTnBtR2FsTXhnRjhGVGVLekxkR2Uxek9qUmFic0lNWW9ESlRINWFOamIKS3dRcXRwZGxBN3d1R1B4ZWpTRWwyakdNUXhSVjNTTUhscjNkU1dQalh5emJXeWtKSXg0Z2xUWGlwcmcxOEpqbwpJWXhDV1pZbStsSGdVMjRyZ2RVOXNMMEEzNWsyMldrLytxdm1SK2xKL0lkSUl4U2tZcklaTDArZ29kMmtkaC9WCklyUUlCYkJPOUwzd2dLQVVuckc4MnlNQ0F3RUFBUT09Ci0tLS0tRU5EIFBVQkxJQyBLRVktLS0tLQo=</data>
	<key>public-key-size</key>
	<integer>4096</integer>
	<key>signature-by</key>
	<string>cloudflare-warp-void &lt;https://github.com/KrishnaSSH/cloudflare-warp-void&gt;</string>
</dict>
</plist>
PLIST

# stdin may be this script (curl | sh): never let xbps read from it.
echo ">> Installing cloudflare-warp"
force=
if xbps-query cloudflare-warp >/dev/null 2>&1 &&
	[ "$(xbps-query -p repository cloudflare-warp)" != "$REPO_URL" ]; then
	# Installed from somewhere else (e.g. a local/xdeb build): replace it.
	force=-f
fi
xbps-install -Sy $force cloudflare-warp </dev/null

if [ -d /var/service ] && [ ! -e /var/service/warp-svc ]; then
	echo ">> Enabling warp-svc service"
	ln -s /etc/sv/warp-svc /var/service/
fi

cat <<'EOF'

Done. Next steps (as your normal user):
  warp-cli registration new     # once
  warp-cli connect
  warp-taskbar                  # GUI / tray icon (Cloudflare One Client)

Updates arrive with the normal `xbps-install -Su`.
EOF
