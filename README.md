# Quick Spotify

**Spotify in Quickshell—not Chromium. Works standalone on any Linux Wayland distro & bar, and natively as an Omarchy 4 plugin.**

Quick Spotify brings the full Spotify experience into a fast, native Quickshell + Rust application using **~60 MB of RAM** instead of **~950 MB** for the Chromium-based desktop client. Adapted from [stappmus/Omarchy-Spotify](https://github.com/stappmus/Omarchy-Spotify), Quick Spotify decouples the UI from Omarchy so it runs cleanly on **Arch / CachyOS, Fedora, NixOS, Debian / Ubuntu, and openSUSE** alongside **Noctalia, Waybar, Hyprland, Sway, Niri, KDE, or GNOME**—while preserving 100% compatibility with `omarchy plugin add`.

Requires a personal **Spotify Premium** account (no Spotify Developer Client ID or API keys needed).

![Vietnam War Music playlist in Quick Spotify](docs/screenshots/vietnam-war-playlist.png)

---

## Highlights

- **~60 MB RAM total**: Native `Quickshell` UI + `librespot`-backed Rust engine (`omarchy-spotify-backend`) supervised on-demand via `systemd --user`.
- **Dual-Mode Architecture**:
  - **Standalone Linux Mode (`quick-spotify`)**: Runs independently with bundled MIT `Commons`/`Ui` QML components, multi-monitor mini-player dropdown, full 980×720 window, MPRIS integration, and CLI IPC (`quick-spotify toggle | mini | play-pause | status`).
  - **Omarchy 4 Plugin Mode**: Retains `manifest.json` and root QML entrypoints with zero symlinks, passing `omarchy plugin validate` out of the box.
- **Live Dynamic Theming**: Watches `~/.config/quick-spotify/colors.toml` (with automatic fallback to `~/.local/state/omarchy/current/theme/colors.toml`) for live hot-reload from **Noctalia**, **Matugen**, **Wallust**, **Pywal**, or **Omarchy**.
- **Full Library & Connect**: Browser-paired native sign-in, playlists, Liked Songs, Discover, albums/artists, queue management, up to 320 kbps audio, and Spotify Connect speaker/Sonos control.
- **Built-in Managed Spotify Soloist Support (Lossless + Audio-Key Fix)**: One-paste in-app setup for [Spotify Soloist](https://developer.spotify.com/documentation/soloist) when Spotify blocks legacy `librespot` eSDK v1 audio keys—auto-downloads `soloist`, runs it on demand via `systemd --user`, and pairs locally over loopback with **zero phone or UFW firewall rules**.

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
  sudo pacman -S quickshell qt6-declarative qt6-svg qt6-5compat libsecret openssl python avahi wl-clipboard xdg-utils rust libpulse pkgconf
  ```
- **Fedora**:
  ```bash
  sudo dnf install quickshell qt6-qtdeclarative qt6-qtsvg qt6-qt5compat libsecret openssl python3 avahi-tools wl-clipboard xdg-utils cargo pulseaudio-libs-devel pkgconf
  ```
- **Debian / Ubuntu** *(plus Quickshell)*:
  ```bash
  sudo apt install qt6-declarative-dev libqt6svg6 libsecret-tools openssl python3 avahi-utils wl-clipboard xdg-utils cargo libpulse-dev libssl-dev pkg-config
  ```
- **NixOS**:
  Include `quickshell`, `kdePackages.qtdeclarative`, `kdePackages.qtsvg`, `libsecret`, `openssl`, `python3`, `avahi`, `wl-clipboard`, `xdg-utils`, `cargo`, `libpulseaudio`, `pkg-config`.

</details>

### Option B: Omarchy 4 Plugin Mode

```bash
omarchy plugin add https://github.com/JValdivia23/Quick-Spotify.git --enable
```

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
