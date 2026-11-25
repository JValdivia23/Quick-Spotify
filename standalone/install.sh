#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
prefix="${HOME}/.local"
setup_noctalia=0
device_name="Quick Spotify"
setup_args=()

usage() {
  cat <<'EOF'
Usage: standalone/install.sh [OPTIONS]

Install Quick Spotify in standalone mode for any Linux Wayland distribution
(Arch/CachyOS, Fedora, Debian/Ubuntu, openSUSE, NixOS) and desktop bar/shell
(Noctalia, Waybar, Hyprland, Sway, Niri, KDE, GNOME).

Options:
  --prefix DIR            User install prefix (default: ~/.local)
  --noctalia              Install Noctalia live dynamic color template
  --device-name NAME      Spotify Connect receiver name (default: "Quick Spotify")
  --install-spotifyd      Also install distro spotifyd fallback
  --skip-backend-build    Skip compiling/downloading the Rust backend
  -h, --help              Show this help
EOF
}

while (( $# > 0 )); do
  case $1 in
    --prefix)
      [[ $# -ge 2 ]] || { echo "install.sh: --prefix requires a path" >&2; exit 2; }
      prefix=$2
      shift 2
      ;;
    --noctalia)
      setup_noctalia=1
      shift
      ;;
    --device-name)
      [[ $# -ge 2 ]] || { echo "install.sh: --device-name requires a value" >&2; exit 2; }
      device_name=$2
      shift 2
      ;;
    --install-spotifyd)
      setup_args+=(--install-spotifyd)
      shift
      ;;
    --skip-backend-build)
      setup_args+=(--skip-backend-build)
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "install.sh: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

print_distro_hints() {
  cat >&2 <<'EOF'

Install required dependencies for your distribution:
  Arch / CachyOS : sudo pacman -S quickshell qt6-declarative qt6-svg qt6-5compat libsecret openssl python avahi wl-clipboard xdg-utils rust libpulse pkgconf
  Fedora         : sudo dnf install quickshell qt6-qtdeclarative qt6-qtsvg qt6-qt5compat libsecret openssl python3 avahi-tools wl-clipboard xdg-utils cargo pulseaudio-libs-devel pkgconf
  Debian / Ubuntu: sudo apt install qt6-declarative-dev libqt6svg6 libsecret-tools openssl python3 avahi-utils wl-clipboard xdg-utils cargo libpulse-dev libssl-dev pkg-config
                   (plus Quickshell from upstream packages / Nix / source)
  openSUSE       : sudo zypper install quickshell qt6-declarative-imports libsecret-tools openssl python3 avahi-utils wl-clipboard xdg-utils cargo libpulse-devel
  NixOS          : nix-shell -p quickshell kdePackages.qtdeclarative kdePackages.qtsvg libsecret openssl python3 avahi wl-clipboard xdg-utils cargo libpulseaudio pkg-config
EOF
}

if ! command -v qs >/dev/null 2>&1 && ! command -v quickshell >/dev/null 2>&1; then
  echo "install.sh: missing required runtime: quickshell (qs)" >&2
  print_distro_hints
  exit 1
fi

for req in secret-tool openssl xdg-open systemctl python3 avahi-browse; do
  if ! command -v "$req" >/dev/null 2>&1; then
    echo "install.sh: missing required command: $req" >&2
    print_distro_hints
    exit 1
  fi
done

"$source_root/standalone/validate-manifest.sh" "$source_root"
"$source_root/scripts/setup.sh" --require-native --device-name "$device_name" "${setup_args[@]}"

bin_dir="$prefix/bin"
apps_dir="$prefix/share/applications"
icons_dir="$prefix/share/icons/hicolor/scalable/apps"

install -d -m 755 -- "$bin_dir" "$apps_dir" "$icons_dir"

launcher_tmp=$(mktemp)
cat >"$launcher_tmp" <<EOF
#!/usr/bin/env bash
export QUICK_SPOTIFY_ROOT="\${QUICK_SPOTIFY_ROOT:-$source_root}"
exec "\$QUICK_SPOTIFY_ROOT/standalone/bin/quick-spotify" "\$@"
EOF
install -m 755 -- "$launcher_tmp" "$bin_dir/quick-spotify"
rm -f -- "$launcher_tmp"

desktop_tmp=$(mktemp)
cat >"$desktop_tmp" <<EOF
[Desktop Entry]
Type=Application
Version=1.5
Name=Quick Spotify
GenericName=Music Player
Comment=Lightweight native Quickshell Spotify client (~60 MB RAM)
Exec=$bin_dir/quick-spotify toggle
Icon=quick-spotify
Terminal=false
Categories=AudioVideo;Audio;Music;Player;
Keywords=spotify;music;player;quickshell;connect;
StartupNotify=false
StartupWMClass=quick-spotify
Actions=MiniPlayer;PlayPause;Next;Previous;

[Desktop Action MiniPlayer]
Name=Toggle Mini Player
Exec=$bin_dir/quick-spotify mini

[Desktop Action PlayPause]
Name=Play / Pause
Exec=$bin_dir/quick-spotify play-pause

[Desktop Action Next]
Name=Next Track
Exec=$bin_dir/quick-spotify next

[Desktop Action Previous]
Name=Previous Track
Exec=$bin_dir/quick-spotify previous
EOF
install -m 644 -- "$desktop_tmp" "$apps_dir/quick-spotify.desktop"
rm -f -- "$desktop_tmp"

install -m 644 -- "$source_root/standalone/desktop/quick-spotify.svg" "$icons_dir/quick-spotify.svg"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$apps_dir" >/dev/null 2>&1 || true
fi

if (( setup_noctalia )); then
  noctalia_dir="${XDG_CONFIG_HOME:-$HOME/.config}/noctalia"
  install -d -m 755 -- "$noctalia_dir/templates"
  install -m 644 -- "$source_root/standalone/themes/noctalia-colors.toml" \
    "$noctalia_dir/templates/quick-spotify-colors.toml"
  install -m 644 -- "$source_root/standalone/themes/noctalia-quick-spotify.toml" \
    "$noctalia_dir/quick-spotify.toml"
  if command -v noctalia >/dev/null 2>&1 && pgrep -x noctalia >/dev/null 2>&1; then
    noctalia msg config-reload >/dev/null 2>&1 || true
  fi
  echo "Configured Noctalia live theme sync: $noctalia_dir/quick-spotify.toml"
fi

echo "Installed CLI launcher: $bin_dir/quick-spotify"
echo "Installed desktop entry: $apps_dir/quick-spotify.desktop"
echo "Run 'quick-spotify' to open Quick Spotify and pair your Spotify Premium account."
