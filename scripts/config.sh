# scripts/config.sh
# Resolves the configuration of the host repository (PEPPEC_CONFIG, by default
# .github/peppec.yml in the workspace) against the presets of the engine checkout this script
# lives in, and copies the chosen preset to a fixed path so the workflow can run it with
# "uses: ./_preset" (the "uses" key does not accept expressions). The optional extra setup
# action of the host is copied to ./_extra in the same way.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONF="${PEPPEC_CONFIG:-${GITHUB_WORKSPACE:-$PWD}/.github/peppec.yml}"
HOST="$(cd "$(dirname "$CONF")/.." 2> /dev/null && pwd || true)"
DEST="${GITHUB_WORKSPACE:-$PWD}/_preset"
EXTRA="${GITHUB_WORKSPACE:-$PWD}/_extra"
BASE_TOOLS="Read,Write,Edit,Glob,Grep"
die() { echo "::error::$1"; exit 1; }

[ -f "$CONF" ] || die "Missing configuration file: $CONF"
conf=$(yq -o=json '.' "$CONF")
preset=$(jq -r '.preset // ""' <<< "$conf")
[[ "$preset" =~ ^[a-z0-9][a-z0-9._-]*$ ]] || die "Invalid preset name: '$preset'"
PDIR="$ROOT/presets/$preset"
[ -f "$PDIR/action.yml" ] && [ -f "$PDIR/preset.yml" ] || die "Unknown preset: $preset"

# Repository values replace the preset defaults; protected paths are added together,
# on top of the ones the engine always protects, and so are the paths never committed
cfg=$(jq -n --argjson p "$(yq -o=json '.' "$PDIR/preset.yml")" --argjson c "$conf" '
  def mapping(f): if f == null then {} elif (f | type) == "object" then f else null end;
  ($p + ($c | del(.preset)))
  | .models = (if mapping($p.models) != null and mapping($c.models) != null
               then {s: "haiku", m: "sonnet", l: "opus"} + mapping($p.models) + mapping($c.models)
               else "invalid" end)
  | .protected_paths = ([".github"] + ($p.protected_paths // []) + ($c.protected_paths // []) | unique)
  | .never_commit = (($p.never_commit // []) + ($c.never_commit // []) | unique)
  | .notes //= [] | .allowed_tools //= [] | .disallowed_tools //= []
  | .options //= {} | .extra_setup //= ""')

problems=$(jq -r '
  def strings(f): (f | type) == "array" and all(f[]; type == "string");
  def plain(f): all(f[]; test("[\",\n]") | not);
  [ (select((.description | type) != "string" or (.description | test("^[^\n]+$") | not)) | "description must be one line of text"),
    (select((.check | type) != "string" or (.check | test("\\S") | not)) | "check must be a non-empty string"),
    ((["notes", "allowed_tools", "disallowed_tools", "protected_paths", "never_commit"][]) as $k
      | select(strings(.[$k]) | not) | "\($k) must be a list of strings"),
    ((["allowed_tools", "disallowed_tools"][]) as $k
      | select(strings(.[$k]) and (plain(.[$k]) | not)) | "\($k) entries cannot contain quotes, commas or line breaks"),
    (select((.options | type) != "object") | "options must be a mapping"),
    (select((.models | type) != "object" or (.models | keys - ["l", "m", "s"] | length) > 0
       or (.models | all(.[]; type == "string" and test("^[A-Za-z0-9][A-Za-z0-9._-]*$")) | not))
     | "models must map the sizes s, m and l to model names made of letters, digits, dots and dashes"),
    (select((.extra_setup | type) != "string"
       or (.extra_setup != "" and (.extra_setup | test("^\\.github/[A-Za-z0-9._/-]+$") | not))
       or (.extra_setup | test("\\.\\.")))
     | "extra_setup must be the path of an action directory under .github/")
  ] | .[]' <<< "$cfg")
[ -z "$problems" ] || die "Invalid configuration: ${problems//$'\n'/; }"

check=$(jq -r '.check' <<< "$cfg")
# The size comes from the issue's label, through decide.sh; M when nothing asks for a model
size="${SIZE:-m}"
[[ "$size" =~ ^[sml]$ ]] || die "Invalid size: '$size'"
model=$(jq -r --arg s "$size" '.models[$s]' <<< "$cfg")
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

rm -rf "$DEST" "$EXTRA"
cp -R "$PDIR" "$DEST"
# The extra setup comes from the same checkout as the configuration, never from the agent's branch
extra_setup=$(jq -r '.extra_setup' <<< "$cfg")
if [ -n "$extra_setup" ]; then
  [ -f "$HOST/$extra_setup/action.yml" ] || [ -f "$HOST/$extra_setup/action.yaml" ] \
    || die "extra_setup: no action.yml in $extra_setup"
  cp -R "$HOST/$extra_setup" "$EXTRA"
fi

out() {
  local d="PEPPEC_${RANDOM}${RANDOM}${RANDOM}"
  printf '%s<<%s\n%s\n%s\n' "$1" "$d" "$2" "$d" >> "$GITHUB_OUTPUT"
}
out preset "$preset"
out check "$check"
out protected_paths "$protected"
out never_commit "$(jq -r '.never_commit[]' <<< "$cfg")"
out tool_args "$tool_args"
out model "$model"
out options "$(jq -c '.options' <<< "$cfg")"
out extra_setup "$extra_setup"
out prompt "$prompt"
echo "Preset: $preset"
echo "Protected paths: ${protected//$'\n'/, }"
echo "Tools: $tool_args"
echo "Model: $model (size $size; $(jq -r '.models | "S \(.s), M \(.m), L \(.l)"' <<< "$cfg"))"
echo "Extra setup: ${extra_setup:-none}"
