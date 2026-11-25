# Quick Spotify

**Spotify in Quickshell—not Chromium. Works standalone on any Linux Wayland distro & bar, and natively as an Omarchy 4 plugin.**

Quick Spotify brings the full Spotify experience into a fast, native Quickshell + Rust application using **~60 MB of RAM** instead of **~950 MB** for the Chromium-based desktop client. Adapted from [stappmus/Omarchy-Spotify](https://github.com/stappmus/Omarchy-Spotify), Quick Spotify decouples the UI from Omarchy so it runs cleanly on **Arch / CachyOS, Fedora, NixOS, Debian / Ubuntu, and openSUSE** alongside **Noctalia, Waybar, Hyprland, Sway, Niri, KDE, or GNOME**—while preserving 100% compatibility with `omarchy plugin add`.

Requires a personal **Spotify Premium** account. Browsing, search, library management, and controlling external Spotify Connect devices require **no Developer Client ID or API keys**; for **local audio playback on this computer** (when Spotify blocks legacy `librespot` audio keys), Quick Spotify includes built-in setup for a free personal [Spotify Soloist API key](https://developer.spotify.com/documentation/soloist).

![Vietnam War Music playlist in Quick Spotify](docs/screenshots/vietnam-war-playlist.png)

---

## Highlights

- **~60 MB RAM total**: Native `Quickshell` UI + `librespot`-backed Rust engine (`omarchy-spotify-backend`) supervised on-demand via `systemd --user`.
- **Dual-Mode Architecture**:
  - **Standalone Linux Mode (`quick-spotify`)**: Runs independently with bundled MIT `Commons`/`Ui` QML components, multi-monitor mini-player dropdown, full 980×720 window (`QS_APP_ID=quick-spotify`), and CLI IPC (`quick-spotify toggle | mini | play-pause | status`).
  - **Omarchy 4 Plugin Mode**: Retains `manifest.json` and root QML entrypoints with zero symlinks, passing `omarchy plugin validate` out of the box.
- **Built-in Managed Spotify Soloist Support (Lossless + Audio-Key Fix)**:
  - In-app and CLI (`quick-spotify setup-soloist`) setup for [Spotify Soloist](https://developer.spotify.com/documentation/soloist) when Spotify rejects legacy `librespot` eSDK v1 audio keys (`error audio key 0 1`).
  - Auto-downloads `soloist`, manages it on demand via `systemd --user` (`quick-spotify-soloist.service`), streams live playback state over `soloist ctl trace`, and executes transport/volume controls directly via `soloist ctl` (0ms latency, zero Web API rate limits).
  - Ships a lightweight **Soloist → MPRIS2 D-Bus bridge** (`org.mpris.MediaPlayer2.quick_spotify`) so **Noctalia Media, lock screens, Waybar, GNOME/KDE applets, and `XF86Audio*` media keys** see live artwork, metadata, progress, and controls even when the Quick Spotify window is closed.
- **Live Dynamic Theming**: Watches `~/.config/quick-spotify/colors.toml` (with automatic fallback to `~/.local/state/omarchy/current/theme/colors.toml`) for live hot-reload from **Noctalia**, **Matugen**, **Wallust**, **Pywal**, or **Omarchy**.
- **Full Library & Connect**: Browser-paired native sign-in, playlists, Liked Songs, Discover, albums/artists, queue management, up to 320 kbps / Lossless audio, and Spotify Connect speaker/Sonos control.

---

## Install

### Option A: Standalone on Any Linux Wayland Distro (Noctalia, Waybar, Hyprland, Sway, Niri, KDE, GNOME)

```bash
git clone https://github.com/JValdivia23/Quick-Spotify.git ~/dev/Quick-Spotify
cd ~/dev/Quick-Spotify

# Standard install (~/.local/bin/quick-spotify + desktop entry + Rust backend)
./standalone/install.sh

# Or include automatic Noctalia live wallpaper/M3 palette syncing:
./standalone/install.sh --noctalia
```

<details>
<summary><strong>Distribution package prerequisites</strong></summary>

- **Arch / CachyOS**:
  ```bash
  sudo pacman -S quickshell qt6-declarative qt6-svg qt6-5compat libsecret openssl python python-gobject avahi wl-clipboard xdg-utils rust libpulse pkgconf
  ```
- **Fedora**:
  ```bash
  sudo dnf install quickshell qt6-qtdeclarative qt6-qtsvg qt6-qt5compat libsecret openssl python3 python3-gobject avahi-tools wl-clipboard xdg-utils cargo pulseaudio-libs-devel pkgconf
  ```
- **Debian / Ubuntu** *(plus Quickshell)*:
  ```bash
  sudo apt install qt6-declarative-dev libqt6svg6 libsecret-tools openssl python3 python3-gi avahi-utils wl-clipboard xdg-utils cargo libpulse-dev libssl-dev pkg-config
  ```
- **NixOS**:
  Include `quickshell`, `kdePackages.qtdeclarative`, `kdePackages.qtsvg`, `libsecret`, `openssl`, `python3`, `python3Packages.pygobject3`, `avahi`, `wl-clipboard`, `xdg-utils`, `cargo`, `libpulseaudio`, `pkg-config`.

</details>

### Option B: Omarchy 4 Plugin Mode

```bash
omarchy plugin add https://github.com/JValdivia23/Quick-Spotify.git --enable
```

---

## Local Playback with Spotify Soloist (Recommended)

If playing a track on the built-in `librespot` receiver fails with *"Spotify did not provide the audio key required to play this track on this computer"*, switch to Spotify's official **Soloist** receiver right inside Quick Spotify:

1. Open **Settings → Spotify Soloist** (or run `quick-spotify setup-soloist`).
2. Click **1. Get Soloist API Key** (`https://developer.spotify.com/documentation/soloist`), paste your key, and click **2. Save & Activate**. Quick Spotify downloads `soloist`, stores the key privately (`~/.local/share/soloist/credentials/api_key`, `0600`), disables the legacy `librespot` receiver, and starts `quick-spotify-soloist.service` + the MPRIS2 bridge.
3. **One-time Connect pairing**: Soloist (`Core Playback SDK 2.10+`) uses DPoP-bound Connect auth and needs one initial transfer from an official Spotify client to persist its cloud session (`~/.local/share/soloist/settings`):
   - **Desktop (zero firewall changes):** Click **3. Open Spotify Desktop to Pair** (if `spotify-launcher` / `spotify` is installed), select **Quick Spotify** in Devices once over local loopback, wait ~3 seconds for Quick Spotify to show **`Soloist receiver active & paired`**, then close Spotify Desktop.
   - **Phone on LAN:** Select **Quick Spotify** in the Spotify mobile app once *(if `ufw` is active, temporarily allow LAN traffic on Soloist's ZeroConf TCP port logged by `journalctl --user -u quick-spotify-soloist.service`)*.

After that one-time handshake, Soloist reconnects automatically over Spotify Cloud on every startup without needing Spotify Desktop or open firewall ports.

---

## Standalone CLI & Keybinding Setup

```bash
quick-spotify              # Toggle configured player (Full player by default)
quick-spotify full         # Toggle full Spotify window
quick-spotify mini         # Toggle dropdown mini-player on focused monitor
quick-spotify play-pause   # Play/pause active local or Spotify Connect device
quick-spotify next         # Next track
quick-spotify previous     # Previous track
quick-spotify volume-up    # +5% Spotify volume
quick-spotify volume-down  # -5% Spotify volume
quick-spotify setup-soloist # Configure Spotify Soloist API key from CLI
quick-spotify status       # JSON status for custom Waybar / bar scripts
```

### Hyprland (Native Lua `0.55+`)
```lua
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd(os.getenv("HOME") .. "/.local/bin/quick-spotify toggle"))
```

### Hyprland / Sway (`.conf`)
```ini
bind = SUPER SHIFT, M, exec, ~/.local/bin/quick-spotify toggle
```

---

## Keyboard Shortcuts Inside Quick Spotify

| Shortcut | Action |
| --- | --- |
| `Ctrl+F` or `/` | Search all of Spotify (press again to toggle current area / global) |
| `Tab` / `F6` | Cycle between sidebar, search, track list, and player |
| `Arrow keys` / `Enter` | Navigate controls and activate |
| `C` | Open context actions on selected row |
| `Space` | Play or pause |
| `Ctrl+Left` / `Ctrl+Right` | Previous or next track |
| `Shift+Left` / `Shift+Right` | Seek 10 seconds |
| `Ctrl+Up` / `Ctrl+Down` | Adjust Spotify volume |
| `M` | Mute or restore volume |
| `Ctrl+Shift+A` / `Ctrl+Shift+B` | Open current artist / album |
| `Ctrl+/` | Show all keyboard shortcuts |
| `Ctrl+H` | Hide visible shortcut hints |

![Mini player](docs/screenshots/mini-player-under-the-bridge.png)

---

## Dynamic Theme Format (`~/.config/quick-spotify/colors.toml`)

Any theme generator (Noctalia, Matugen, Wallust, Pywal) can write hex tokens to `~/.config/quick-spotify/colors.toml` and Quick Spotify updates live without restarting:

```toml
background = "#121318"
foreground = "#e3e1e9"
accent = "#bac3ff"
muted = "#90909a"
red = "#ffb4ab"
```

---

## Remove it completely

### Standalone Mode
```bash
~/dev/Quick-Spotify/standalone/uninstall.sh --purge
```

### Omarchy 4 Plugin Mode
```bash
cd "$HOME" && "$HOME/.config/omarchy/plugins/quickshell.spotify/scripts/uninstall.sh"
```

---

## Credits & License

- Built on **[Omarchy Spotify](https://github.com/stappmus/Omarchy-Spotify)** by `stappmus` and contributors (MIT).
- Standalone UI components in `standalone/Commons` and `standalone/Ui` adapted from **[Omarchy](https://github.com/basecamp/omarchy)** (MIT).
- Native Spotify JSON mappers in `backend/src/spotify/` adapted from **[spotatui](https://github.com/LargeModGames/spotatui)** (MIT).
- See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [docs/TECHNICAL.md](docs/TECHNICAL.md) for full details.

Quick Spotify is an independent project and is not affiliated with Spotify AB. Licensed under the [MIT License](LICENSE).
