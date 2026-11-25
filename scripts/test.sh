#!/usr/bin/env bash
set -euo pipefail

source_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
cd "$source_root"

qmllint_bin=$(command -v qmllint || printf '/usr/lib/qt6/bin/qmllint')
[[ -x $qmllint_bin ]] || {
  echo "test.sh: missing Qt 6 qmllint: $qmllint_bin" >&2
  exit 1
}

if command -v cargo >/dev/null 2>&1; then
  cargo fmt --manifest-path backend/Cargo.toml --all -- --check
  cargo test --locked --manifest-path backend/Cargo.toml --quiet
  cargo clippy --locked --manifest-path backend/Cargo.toml --all-targets -- -D warnings
fi

qml_test_runner=$(command -v qmltestrunner || printf '/usr/lib/qt6/bin/qmltestrunner')
[[ -x $qml_test_runner ]] || {
  echo "test.sh: Qt 6 qmltestrunner is missing: $qml_test_runner" >&2
  exit 1
}

"$source_root/standalone/validate-manifest.sh" .
if command -v omarchy >/dev/null 2>&1; then
  omarchy plugin validate .
fi

lint_import_root=$(mktemp -d)
trap 'rm -rf -- "$lint_import_root"' EXIT
mkdir -p "$lint_import_root/qs"
if [[ -d /usr/share/omarchy/shell/Commons && -d /usr/share/omarchy/shell/Ui ]]; then
  cp -r /usr/share/omarchy/shell/Commons /usr/share/omarchy/shell/Ui "$lint_import_root/qs/"
else
  cp -r "$source_root/standalone/Commons" "$source_root/standalone/Ui" "$lint_import_root/qs/"
fi

"$qmllint_bin" -I "$lint_import_root" Api.js OAuth.js AuthManager.qml \
  NativeSession.qml SpotifyApi.qml SearchController.qml FilterScanController.qml SpotifyConnectManager.qml DaemonManager.qml BackendClient.qml Service.qml \
  BarWidget.qml PlaybackSlider.qml ArtistLinks.qml MediaByline.qml MediaRow.qml MediaCollection.qml \
  ArtistSearchSection.qml LyricsInstallPrompt.qml RetryImage.qml ShortcutHint.qml \
  TransportButton.qml Panel.qml standalone/shell.qml

QT_QPA_PLATFORM=offscreen "$qml_test_runner" \
  -input tests \
  -import "$source_root" \
  -o -,txt

PYTHONDONTWRITEBYTECODE=1 python3 "$source_root/tests/test_connect_helper.py"
PYTHONDONTWRITEBYTECODE=1 python3 "$source_root/tests/test_oauth_listener.py"
"$source_root/tests/test-scripts.sh"
"$source_root/scripts/test-quickshell.sh"

if rg -n 'QtWebEngine|WebEngineView|WebView|playerctl|node_modules' \
  --glob '*.qml' --glob '*.js' --glob '*.sh' --glob '*.service' \
  --glob '!scripts/test.sh' .; then
  echo "test.sh: forbidden heavyweight runtime dependency found" >&2
  exit 1
fi

echo "All validation and tests passed."
