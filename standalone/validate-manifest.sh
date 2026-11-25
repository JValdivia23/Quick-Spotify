#!/usr/bin/env bash
set -euo pipefail

# Standalone validator mirroring Omarchy 4's `omarchy plugin validate` checks so
# dual-mode compatibility is verified on every Linux distribution and CI runner.

fail() {
  echo "validate-manifest: $*" >&2
  exit 1
}

PLUGIN_DIR=${1:-.}
[[ -d $PLUGIN_DIR ]] || fail "plugin folder not found: $PLUGIN_DIR"

MANIFEST="$PLUGIN_DIR/manifest.json"
[[ -f $MANIFEST ]] || fail "missing manifest.json in $PLUGIN_DIR"
jq -e . "$MANIFEST" >/dev/null 2>&1 || fail "manifest.json is not valid JSON"
jq -e '.schemaVersion == 1' "$MANIFEST" >/dev/null 2>&1 || fail "expected schemaVersion 1"

for field in id name version kinds entryPoints; do
  jq -e --arg f "$field" 'has($f)' "$MANIFEST" >/dev/null 2>&1 \
    || fail "manifest missing required field '$field'"
done

ID=$(jq -r '.id // ""' "$MANIFEST")
[[ $ID =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && $ID != *".."* && $ID != omarchy.* ]] \
  || fail "invalid plugin id '$ID'"

jq -e '(.kinds | type) == "array" and (.kinds | length) > 0 and (.entryPoints | type) == "object"' \
  "$MANIFEST" >/dev/null 2>&1 || fail "invalid kinds or entryPoints"

while IFS= read -r ep_json; do
  [[ -n $ep_json ]] || continue
  ep=$(jq -r '.' <<<"$ep_json")
  [[ -n $ep && $ep != /* && $ep != *".."* && -f "$PLUGIN_DIR/$ep" ]] \
    || fail "invalid or missing entryPoint '$ep'"
done < <(jq -c '.entryPoints | to_entries[] | .value' "$MANIFEST")

link=$(find "$PLUGIN_DIR" -name .git -prune -o -type l -print -quit 2>/dev/null || true)
[[ -z $link ]] || fail "symlinks are not allowed inside a plugin folder: $link"

exit 0
