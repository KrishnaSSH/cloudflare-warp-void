# cloudflare-warp-void

[Cloudflare WARP / Cloudflare One Client](https://developers.cloudflare.com/warp-client/) for **Void Linux** (glibc, x86_64 + aarch64): CLI, daemon **and the GUI / tray app**.

A GitHub Actions workflow checks Cloudflare's official apt repository every 6 hours. When a new version appears it:

1. downloads the `.deb`, verifies the signed apt index with Cloudflare's pinned GPG key and checks the `.deb` SHA256,
2. repackages it as a native `.xbps` with a **runit** service instead of systemd units,
3. tests it end to end in a Void container: install with `install.sh`, start the runit service, `warp-cli registration new`, `warp-cli connect`, check that `cdn-cgi/trace` reports `warp=on`, then start the GUI as a normal user on Xvfb and check that it connects to the daemon and opens its window,
4. signs the package and repo index, and publishes them as a GitHub release, which works as an xbps repository,
5. installs again from the published release to make sure it works.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/KrishnaSSH/cloudflare-warp-void/main/install.sh | sudo sh
```

That adds the repository (`/etc/xbps.d/20-cloudflare-warp.conf`), pins its signing key, installs `cloudflare-warp` and enables the `warp-svc` service. After that you get updates with the usual `sudo xbps-install -Su`.

<details><summary>Manual install</summary>

```sh
echo 'repository=https://github.com/KrishnaSSH/cloudflare-warp-void/releases/latest/download' \
  | sudo tee /etc/xbps.d/20-cloudflare-warp.conf
sudo xbps-install -S cloudflare-warp      # accept the key, fingerprint 91:5e:4e:5f:89:9c:46:23:b7:4d:d1:77:57:c6:50:fa
sudo ln -s /etc/sv/warp-svc /var/service/
```

You can also download a `.xbps` from [Releases](../../releases) and run `sudo xbps-install -R <dir> cloudflare-warp`.
</details>

## Use

```sh
warp-cli registration new   # once
warp-cli connect
warp-cli status
```

**GUI:** run `warp-taskbar` (or open *Cloudflare One Client* from your app launcher). It runs in the system tray, so click the tray icon to open the window. Running `warp-taskbar` again while it's already running also opens the window.

- GNOME/KDE/XFCE and other desktops that follow `/etc/xdg/autostart` start it on login.
- On sway, Hyprland, i3, river and similar, add `exec warp-taskbar` to your config. Your bar needs a tray (swaybar has one; for waybar add the `tray` module).

## Differences from the .deb

| Debian package | This package |
| --- | --- |
| `warp-svc.service` (systemd) | `/etc/sv/warp-svc` (runit) |
| `warp-taskbar.service` (systemd --user) | `/etc/xdg/autostart/com.cloudflare.WarpTaskbar.desktop` |
| binaries in `/bin` | binaries in `/usr/bin` |
| needs `libpcap.so.0.8` | `libpcap.so.0.8 -> libpcap.so.1` compat symlink (same ABI) |

The binaries are Cloudflare's and are not modified. This repo is not affiliated with Cloudflare. The client is proprietary software under Cloudflare's terms.

## Building locally

```sh
./build.sh                    # newest upstream version, host arch -> out/*.xbps
./build.sh -a aarch64 -v 2026.8.2100.0
sudo xbps-install -R out cloudflare-warp
```

To ship a packaging fix without a new upstream version, bump `REVISION`.

Maintainer setup: the repository secret `XBPS_SIGNING_KEY` holds the RSA private key whose public half is `keys/xbps-repo-key.plist` (fingerprint `91:5e:4e:5f:89:9c:46:23:b7:4d:d1:77:57:c6:50:fa`) (it's also embedded in `install.sh`).
