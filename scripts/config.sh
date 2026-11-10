# scripts/config.sh
# Resolves the configuration of the host repository (PEPPEC_CONFIG, by default
# .github/peppec.yml in the workspace) against the presets of the engine checkout this script
# lives in, and copies the chosen preset to a fixed path so the workflow can run it with
# "uses: ./_preset" (the "uses" key does not accept expressions).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${PEPPEC_CONFIG:-${GITHUB_WORKSPACE:-$PWD}/.github/peppec.yml}"
DEST="${GITHUB_WORKSPACE:-$PWD}/_preset"
BASE_TOOLS="Read,Write,Edit,Glob,Grep"
die() { echo "::error::$1"; exit 1; }

[ -f "$CONF" ] || die "Missing configuration file: $CONF"
conf=$(yq -o=json '.' "$CONF")
preset=$(jq -r '.preset // ""' <<< "$conf")
[[ "$preset" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "Invalid preset name: '$preset'"
PDIR="$ROOT/presets/$preset"
[ -f "$PDIR/action.yml" ] && [ -f "$PDIR/preset.yml" ] || die "Unknown preset: $preset"

# Repository values replace the preset defaults; protected paths are added together,
# on top of the ones the engine always protects
cfg=$(jq -n --argjson p "$(yq -o=json '.' "$PDIR/preset.yml")" --argjson c "$conf" '
  ($p + ($c | del(.preset)))
  | .protected_paths = ([".github"] + ($p.protected_paths // []) + ($c.protected_paths // []) | unique)
  | .notes //= [] | .allowed_tools //= [] | .disallowed_tools //= []')

problems=$(jq -r '
  def strings(f): (f | type) == "array" and all(f[]; type == "string");
  def plain(f): all(f[]; test("[\",\n]") | not);
  [ (select((.description | type) != "string" or (.description | test("^[^\n]+$") | not)) | "description must be one line of text"),
    (select((.check | type) != "string" or (.check | test("\\S") | not)) | "check must be a non-empty string"),
    ((["notes", "allowed_tools", "disallowed_tools", "protected_paths"][]) as $k
      | select(strings(.[$k]) | not) | "\($k) must be a list of strings"),
    ((["allowed_tools", "disallowed_tools"][]) as $k
      | select(strings(.[$k]) and (plain(.[$k]) | not)) | "\($k) entries cannot contain quotes, commas or line breaks")
  ] | .[]' <<< "$cfg")
[ -z "$problems" ] || die "Invalid configuration: ${problems//$'\n'/; }"

check=$(jq -r '.check' <<< "$cfg")
protected=$(jq -r '.protected_paths[]' <<< "$cfg")
tool_args=$(jq -r --arg base "$BASE_TOOLS" '
  "--allowedTools \"" + ([$base] + .allowed_tools | join(",")) + "\""
  + (if (.disallowed_tools | length) > 0
     then " --disallowedTools \"" + (.disallowed_tools | join(",")) + "\"" else "" end)' <<< "$cfg")
# Placeholders are replaced literally, one line of the template at a time
prompt=$(jq -r --rawfile t "$ROOT/scripts/prompt.md" '
  def indent: split("\n") | map(select(test("\\S")) | "    " + .) | join("\n");
  . as $c
  | { "{{description}}": $c.description,
      "{{check}}": ($c.check | indent),
      "{{protected_paths}}": ($c.protected_paths | join("\n") | indent),
      "{{notes}}": ($c.notes | map("- " + .) | join("\n")) } as $v
  | reduce ($v | keys[]) as $k ($t; split($k) | join($v[$k]))
  | split("\n") | map(select(. != "")) | join("\n")' <<< "$cfg")

rm -rf "$DEST"
cp -R "$PDIR" "$DEST"

out() {
  local d="PEPPEC_${RANDOM}${RANDOM}${RANDOM}"
  printf '%s<<%s\n%s\n%s\n' "$1" "$d" "$2" "$d" >> "$GITHUB_OUTPUT"
}
out preset "$preset"
out check "$check"
out protected_paths "$protected"
out tool_args "$tool_args"
out prompt "$prompt"
echo "Preset: $preset"
echo "Protected paths: ${protected//$'\n'/, }"
echo "Tools: $tool_args"
