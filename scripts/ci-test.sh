#!/bin/bash
# End-to-end test of the published-style repo, run as root inside a
# privileged Void Linux container:
#   install via install.sh -> runit service -> register -> connect -> GUI.
# Usage: scripts/ci-test.sh REPO_URL [ARTIFACT_DIR]
set -euo pipefail

REPO_URL=$1
OUT=$(realpath -m "${2:-test-artifacts}")
HERE=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$OUT"
chmod 777 "$OUT"

step() { printf '\n\033[1;34m=== %s\033[0m\n' "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }
wait_for() { # wait_for SECONDS CMD...
	local t=$1; shift
	for _ in $(seq "$t"); do "$@" >/dev/null 2>&1 && return 0; sleep 1; done
	return 1
}

step "Install with install.sh (REPO_URL=$REPO_URL)"
REPO_URL=$REPO_URL sh "$HERE/install.sh"
xbps-query cloudflare-warp | grep -E '^(pkgver|repository):'
xbps-pkgdb cloudflare-warp

step "Shared libraries resolve"
missing=$(for f in /usr/bin/warp-{cli,svc,diag,dex} /usr/lib/warp/warp-taskbar /usr/lib/warp/lib/*.so; do  # plugins resolve libflutter via the exe RUNPATH
	LD_LIBRARY_PATH=/usr/lib/warp/lib ldd "$f" 2>/dev/null | grep 'not found' | grep -v libjvm | sed "s|^|$f: |" || true
done)
[ -z "$missing" ] || fail "missing libraries:
$missing"
echo ok

step "Start warp-svc through its runit service directory"
# Docker bind-mounts resolv.conf; make it a plain file like on a real system
# so WARP can manage DNS.
if mountpoint -q /etc/resolv.conf; then
	cp /etc/resolv.conf /tmp/resolv.conf
	umount /etc/resolv.conf
	cp /tmp/resolv.conf /etc/resolv.conf
fi
mkdir -p /run/runit
runsv /etc/sv/warp-svc &
wait_for 30 test -S /run/cloudflare-warp/warp_service || fail "daemon socket never appeared"
sv status /etc/sv/warp-svc

# Everything below runs as an unprivileged desktop user, like real usage.
useradd -m tester 2>/dev/null || true
as_user() { su tester -s /bin/sh -c "$*"; }

step "warp-cli as a normal user"
as_user "warp-cli --accept-tos status" || true
as_user "warp-cli --accept-tos registration new"
as_user "warp-cli --accept-tos connect"
if ! wait_for 60 sh -c "su tester -s /bin/sh -c 'warp-cli --accept-tos status' | grep -q Connected"; then
	as_user "warp-cli --accept-tos status" || true
	tail -n 80 /var/log/cloudflare-warp/cfwarp_service_log.txt || true
	fail "WARP did not connect"
fi
as_user "warp-cli --accept-tos status"
curl -fsS --max-time 20 https://www.cloudflare.com/cdn-cgi/trace | tee "$OUT/trace.txt"
grep -qE '^warp=(on|plus)$' "$OUT/trace.txt" || fail "traffic is not going through WARP"
as_user "warp-cli --accept-tos disconnect"

step "GUI (warp-taskbar) as a normal user on Xvfb"
Xvfb :99 -screen 0 1280x800x24 >/dev/null 2>&1 &
wait_for 15 test -e /tmp/.X11-unix/X99 || fail "Xvfb did not start"
cat >/tmp/gui-test.sh <<EOF
#!/bin/sh
export DISPLAY=:99 NO_AT_BRIDGE=1
cd "\$HOME"
warp-taskbar >"$OUT/gui.log" 2>&1 &
sleep 12
# A second launch activates the running instance and opens its window.
warp-taskbar >>"$OUT/gui.log" 2>&1
sleep 8
xdotool search --name 'Cloudflare One Client' >"$OUT/gui-windows.txt" || true
import -window root "$OUT/gui.png"
EOF
chmod 755 /tmp/gui-test.sh
su tester -s /bin/sh -c "dbus-run-session -- /tmp/gui-test.sh"

grep -q 'IPC client created' "$OUT/gui.log" || { cat "$OUT/gui.log"; fail "GUI did not connect to the daemon"; }
if grep -q 'DaemonNotRunning\|Bootstrap failed' "$OUT/gui.log"; then
	cat "$OUT/gui.log"; fail "GUI reported daemon errors"
fi
[ -s "$OUT/gui-windows.txt" ] || { cat "$OUT/gui.log"; fail "GUI window never appeared"; }
echo "GUI window(s): $(tr '\n' ' ' <"$OUT/gui-windows.txt")"

step "Remove package cleanly"
sv force-stop /etc/sv/warp-svc || true
sv exit /etc/sv/warp-svc || true
xbps-remove -Ry cloudflare-warp </dev/null
! xbps-query cloudflare-warp >/dev/null || fail "package still installed"

step "ALL TESTS PASSED"
