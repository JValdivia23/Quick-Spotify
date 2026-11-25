#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
prefix="${HOME}/.local"
purge=0

while (( $# > 0 )); do
  case $1 in
    --prefix)
      [[ $# -ge 2 ]] || exit 2
      prefix=$2
      shift 2
      ;;
    --purge)
      purge=1
      shift
      ;;
    *)
      echo "uninstall.sh: unknown option: $1" >&2
      exit 2
      ;;
  esac
done

"$prefix/bin/quick-spotify" quit >/dev/null 2>&1 || true
rm -f -- "$prefix/bin/quick-spotify" \
  "$prefix/share/applications/quick-spotify.desktop" \
  "$prefix/share/icons/hicolor/scalable/apps/quick-spotify.svg"

if (( purge )); then
  "$source_root/scripts/soloist-runtime.sh" clear-key >/dev/null 2>&1 || true
  rm -f -- "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/quick-spotify-soloist.service"
  rm -rf -- "$HOME/.local/lib/quick-spotify" "${XDG_CONFIG_HOME:-$HOME/.config}/quick-spotify"
  "$source_root/scripts/remove-runtime.sh" --purge
else
  "$source_root/scripts/soloist-runtime.sh" stop >/dev/null 2>&1 || true
  "$source_root/scripts/remove-runtime.sh"
fi

echo "Uninstalled Quick Spotify standalone files."
