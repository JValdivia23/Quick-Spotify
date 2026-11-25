#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
config_root=${XDG_CONFIG_HOME:-"$HOME/.config"}
data_root=${XDG_DATA_HOME:-"$HOME/.local/share"}
cache_root=${XDG_CACHE_HOME:-"$HOME/.cache"}

runtime_dir=${QUICK_SPOTIFY_SOLOIST_DIR:-"$HOME/.local/lib/quick-spotify"}
managed_bin="$runtime_dir/soloist"
runner_bin="$runtime_dir/run-soloist"
soloist_data_dir=${QUICK_SPOTIFY_SOLOIST_DATA_DIR:-"$data_root/soloist"}
soloist_cache_dir=${QUICK_SPOTIFY_SOLOIST_CACHE_DIR:-"$cache_root/soloist"}
soloist_config_dir="$config_root/quick-spotify"
soloist_env_file="$soloist_config_dir/soloist.env"
unit_dir="$config_root/systemd/user"
unit_name="quick-spotify-soloist.service"
unit_file="$unit_dir/$unit_name"

resolve_soloist_bin() {
  if [[ -n ${QUICK_SPOTIFY_SOLOIST_BIN:-} && -x $QUICK_SPOTIFY_SOLOIST_BIN ]]; then
    printf '%s\n' "$QUICK_SPOTIFY_SOLOIST_BIN"
    return 0
  fi
  if [[ -x $managed_bin ]]; then
    printf '%s\n' "$managed_bin"
    return 0
  fi
  if command -v soloist >/dev/null 2>&1; then
    command -v soloist
    return 0
  fi
  return 1
}

read_device_name() {
  if [[ -f $soloist_env_file ]]; then
    local val
    val=$(sed -n 's/^SOLOIST_DEVICE_NAME=//p' "$soloist_env_file" | tail -n1)
    val=${val%\"}
    val=${val#\"}
    if [[ -n $val ]]; then
      printf '%s\n' "$val"
      return 0
    fi
  fi
  printf '%s\n' "Quick Spotify"
}

write_env_file() {
  local name=${1:-"Quick Spotify"}
  name=$(printf '%s' "$name" | tr -d '\r\n"' | cut -c1-64)
  [[ -n $name ]] || name="Quick Spotify"
  install -d -m 700 -- "$soloist_config_dir"
  local tmp
  tmp=$(mktemp "$soloist_config_dir/.soloist.env.XXXXXX")
  printf 'SOLOIST_DEVICE_NAME="%s"\n' "$name" >"$tmp"
  chmod 600 "$tmp"
  mv -f -- "$tmp" "$soloist_env_file"
}

install_runner_and_unit() {
  install -d -m 700 -- "$runtime_dir" "$soloist_data_dir" "$soloist_cache_dir" "$unit_dir"
  local runner_tmp
  runner_tmp=$(mktemp "$runtime_dir/.run-soloist.XXXXXX")
  cat >"$runner_tmp" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
data_dir="${XDG_DATA_HOME:-$HOME/.local/share}/soloist"
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/soloist"
mkdir -p -m 700 -- "$data_dir" "$cache_dir"
bin="$HOME/.local/lib/quick-spotify/soloist"
if [[ ! -x "$bin" ]]; then
  bin=$(command -v soloist)
fi
exec "$bin" -v \
  -n "${SOLOIST_DEVICE_NAME:-Quick Spotify}" \
  -D "$data_dir" \
  -C "$cache_dir" \
  -z 1024 \
  -w 127.0.0.1:0
EOF
  chmod 755 "$runner_tmp"
  mv -f -- "$runner_tmp" "$runner_bin"

  install -m 644 -- "$source_root/systemd/$unit_name" "$unit_file"
  systemctl --user daemon-reload
}

download_soloist() {
  local arch archive_url tmp_dir
  arch=$(uname -m)
  case $arch in
    x86_64) archive_url="https://soloist-builds.spotifycdn.com/soloist_release_x86_64.tar.gz" ;;
    aarch64|arm64) archive_url="https://soloist-builds.spotifycdn.com/soloist_release_arm64.tar.gz" ;;
    armv7l|armv7h) archive_url="https://soloist-builds.spotifycdn.com/soloist_release_arm32.tar.gz" ;;
    *)
      echo "soloist-runtime: unsupported CPU architecture for Spotify Soloist: $arch" >&2
      exit 1
      ;;
  esac

  install -d -m 700 -- "$runtime_dir"
  tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/quick-spotify-soloist.XXXXXX")
  trap 'rm -rf -- "$tmp_dir"' RETURN

  curl --proto '=https' --proto-redir '=https' --tlsv1.2 -fsSL --retry 2 \
    --connect-timeout 10 --max-time 120 --max-filesize 67108864 \
    -o "$tmp_dir/soloist.tar.gz" "$archive_url"

  tar -xzf "$tmp_dir/soloist.tar.gz" -C "$tmp_dir"
  [[ -f "$tmp_dir/soloist" ]] || {
    echo "soloist-runtime: downloaded archive did not contain soloist binary" >&2
    exit 1
  }
  chmod 755 "$tmp_dir/soloist"
  "$tmp_dir/soloist" --version >/dev/null

  local bin_tmp
  bin_tmp=$(mktemp "$runtime_dir/.soloist.XXXXXX")
  install -m 755 -- "$tmp_dir/soloist" "$bin_tmp"
  mv -f -- "$bin_tmp" "$managed_bin"
  if [[ -f "$tmp_dir/THIRD_PARTY_LICENSES.txt" ]]; then
    install -m 644 -- "$tmp_dir/THIRD_PARTY_LICENSES.txt" "$runtime_dir/SOLOIST_THIRD_PARTY_LICENSES.txt"
  fi
}

key_is_configured() {
  [[ -s "$soloist_data_dir/soloist.api_key" ]] \
    || compgen -G "$soloist_data_dir/*key*" >/dev/null 2>&1 \
    || compgen -G "$soloist_data_dir/credentials/*" >/dev/null 2>&1
}

cmd=${1:-status}
shift || true

case $cmd in
  status)
    bin_path=$(resolve_soloist_bin || true)
    installed=false
    version=""
    if [[ -n $bin_path ]]; then
      installed=true
      version=$("$bin_path" --version 2>/dev/null | head -n1 | awk '{print $2}' || true)
    fi
    key_configured=false
    if key_is_configured; then
      key_configured=true
    fi
    running=false
    if systemctl --user is-active --quiet "$unit_name" 2>/dev/null; then
      running=true
    fi
    logged_in=false
    if [[ $running == true && -n $bin_path ]]; then
      ctl_out=$("$bin_path" ctl -D "$soloist_data_dir" status 2>/dev/null || true)
      if printf '%s\n' "$ctl_out" | grep -q 'logged in:[[:space:]]*yes'; then
        logged_in=true
      fi
    elif [[ -s "$soloist_data_dir/settings" ]]; then
      logged_in=true
    fi
    desktop_helper=false
    if command -v spotify-launcher >/dev/null 2>&1 || command -v spotify >/dev/null 2>&1; then
      desktop_helper=true
    fi
    dev_name=$(read_device_name)
    dev_id=""
    if [[ -f "$soloist_data_dir/.device_id" ]]; then
      dev_id=$(tr -d '\r\n[:space:]' <"$soloist_data_dir/.device_id" 2>/dev/null || true)
    fi
    python3 -c 'import json,sys; print(json.dumps({
      "installed": sys.argv[1] == "true",
      "keyConfigured": sys.argv[2] == "true",
      "running": sys.argv[3] == "true",
      "loggedIn": sys.argv[4] == "true",
      "version": sys.argv[5],
      "deviceName": sys.argv[6],
      "deviceId": sys.argv[7],
      "unitReady": sys.argv[8] == "true",
      "desktopHelperAvailable": sys.argv[9] == "true"
    }))' "$installed" "$key_configured" "$running" "$logged_in" "$version" "$dev_name" "$dev_id" "$([[ -f $unit_file ]] && echo true || echo false)" "$desktop_helper"
    ;;

  install)
    device_name=$(read_device_name)
    while (( $# > 0 )); do
      case $1 in
        --device-name) device_name=${2:-"Quick Spotify"}; shift 2 ;;
        *) shift ;;
      esac
    done
    if ! resolve_soloist_bin >/dev/null 2>&1; then
      download_soloist
    fi
    write_env_file "$device_name"
    install_runner_and_unit
    ;;

  setup-key)
    device_name=$(read_device_name)
    while (( $# > 0 )); do
      case $1 in
        --device-name) device_name=${2:-"Quick Spotify"}; shift 2 ;;
        *) shift ;;
      esac
    done

    IFS= read -r api_key || true
    api_key=$(printf '%s' "$api_key" | tr -d '\r\n[:space:]')
    if [[ ${#api_key} -lt 16 ]]; then
      echo "Enter a valid Spotify Soloist API key." >&2
      exit 3
    fi

    if ! resolve_soloist_bin >/dev/null 2>&1; then
      download_soloist
    fi
    bin_path=$(resolve_soloist_bin)
    write_env_file "$device_name"
    install_runner_and_unit

    umask 077
    install -d -m 700 -- "$soloist_data_dir"
    chmod -R u+rwX,go= "$soloist_data_dir" 2>/dev/null || true
    printf '%s\n' "$api_key" | "$bin_path" setup-api-key -D "$soloist_data_dir" >/dev/null
    api_key=""
    chmod -R u+rwX,go= "$soloist_data_dir" 2>/dev/null || true

    systemctl --user stop omarchy-spotify.service omarchy-spotifyd.service 2>/dev/null || true
    systemctl --user reset-failed "$unit_name" 2>/dev/null || true
    systemctl --user restart "$unit_name"

    for (( i = 0; i < 30; i++ )); do
      if systemctl --user is-active --quiet "$unit_name" 2>/dev/null; then
        if journalctl --user -u "$unit_name" -n 25 --no-pager 2>/dev/null | grep -q 'Started ZeroConf service on port'; then
          break
        fi
      fi
      sleep 0.2
    done

    if ! systemctl --user is-active --quiet "$unit_name" 2>/dev/null; then
      echo "Soloist stopped during startup. Verify your Soloist API key on Spotify Developer Dashboard." >&2
      exit 4
    fi
    ;;

  configure)
    device_name=$(read_device_name)
    while (( $# > 0 )); do
      case $1 in
        --device-name) device_name=${2:-"Quick Spotify"}; shift 2 ;;
        *) shift ;;
      esac
    done
    previous_name=$(read_device_name)
    write_env_file "$device_name"
    if [[ -f $unit_file ]] && systemctl --user is-active --quiet "$unit_name" 2>/dev/null && [[ $previous_name != "$device_name" ]]; then
      systemctl --user restart "$unit_name"
    fi
    ;;

  start)
    if ! resolve_soloist_bin >/dev/null 2>&1 || [[ ! -f $unit_file ]]; then
      echo "Spotify Soloist is not set up yet." >&2
      exit 3
    fi
    systemctl --user stop omarchy-spotify.service omarchy-spotifyd.service 2>/dev/null || true
    systemctl --user reset-failed "$unit_name" 2>/dev/null || true
    systemctl --user start "$unit_name"
    ;;

  stop)
    systemctl --user stop "$unit_name" 2>/dev/null || true
    ;;

  clear-key)
    systemctl --user stop "$unit_name" 2>/dev/null || true
    chmod -R u+rwX,go= "$soloist_data_dir" 2>/dev/null || true
    rm -rf -- "$soloist_data_dir/credentials" "$soloist_data_dir/soloist.api_key" "$soloist_data_dir"/*key* 2>/dev/null || true
    ;;

  activate)
    bin_path=$(resolve_soloist_bin || true)
    if [[ -n $bin_path ]] && systemctl --user is-active --quiet "$unit_name" 2>/dev/null; then
      "$bin_path" ctl -D "$soloist_data_dir" activate >/dev/null 2>&1 || true
    fi
    ;;

  trace)
    bin_path=$(resolve_soloist_bin || exit 1)
    exec "$bin_path" ctl -D "$soloist_data_dir" trace
    ;;

  ctl)
    bin_path=$(resolve_soloist_bin || exit 1)
    exec "$bin_path" ctl -D "$soloist_data_dir" "$@"
    ;;

  launch-pair-helper)
    if command -v spotify-launcher >/dev/null 2>&1; then
      nohup spotify-launcher >/dev/null 2>&1 &
    elif command -v spotify >/dev/null 2>&1; then
      nohup spotify >/dev/null 2>&1 &
    else
      xdg-open "https://open.spotify.com" >/dev/null 2>&1 &
    fi
    ;;

  clipboard)
    if command -v wl-paste >/dev/null 2>&1; then
      wl-paste --no-newline 2>/dev/null | head -c 4096 || true
    elif command -v xclip >/dev/null 2>&1; then
      xclip -o -selection clipboard 2>/dev/null | head -c 4096 || true
    fi
    ;;

  *)
    echo "soloist-runtime: unknown command: $cmd" >&2
    exit 2
    ;;
esac
