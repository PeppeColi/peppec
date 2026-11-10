# scripts/lint-presets.sh
# Checks the rules for presets that can be verified automatically (see CONTRIBUTING.md).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
err() { echo "::error::$1"; fail=1; }

for dir in "$ROOT"/presets/*/; do
  name=$(basename "$dir")
  [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*-v[0-9]+$ ]] || err "$name: the directory name must look like <name>-v<N>"
  for f in action.yml preset.yml README.md; do
    [ -f "$dir$f" ] || err "$name: missing $f"
  done
  [ -d "${dir}fixture" ] || err "$name: missing the fixture/ project"
  [ -f "${dir}action.yml" ] && [ -f "${dir}preset.yml" ] || continue

  # Third-party actions must be pinned to a full commit SHA
  while IFS= read -r ref; do
    [[ "$ref" =~ ^[^@[:space:]]+@[0-9a-f]{40}$ ]] || err "$name: '$ref' must be pinned to a full commit SHA"
  done < <(yq -o=json '.' "${dir}action.yml" | jq -r '.runs.steps[]? | .uses // empty')
  [ "$(yq -o=json '.' "${dir}action.yml" | jq -r '.runs.using // ""')" = composite ] \
    || err "$name: action.yml must be a composite action"

  # The agent gets only the tools of the language, and the checks stay protected
  p=$(yq -o=json '.' "${dir}preset.yml")
  while IFS= read -r tool; do
    err "$name: allowed_tools cannot contain '$tool'"
  done < <(jq -r '.allowed_tools[]? | select(test("^Bash$|^Bash\\((\\*|:\\*)\\)$|^Bash\\((sudo|bash|sh|zsh|env|eval|curl|wget|git|gh|docker|ssh|nc)\\b"))' <<< "$p")
  for key in description check; do
    [ -n "$(jq -r --arg k "$key" '.[$k] // "" | tostring | gsub("\\s"; "")' <<< "$p")" ] || err "$name: preset.yml must set '$key'"
  done
  [ "$(jq -r '.disallowed_tools // [] | length' <<< "$p")" -gt 0 ] \
    || err "$name: disallowed_tools must block at least running and publishing the project"
  if grep -qE '\|\|[[:space:]]*(true|:)[[:space:]]*$' <<< "$(jq -r '.check // ""' <<< "$p")"; then
    err "$name: check commands cannot ignore failures"
  fi
done

[ "$fail" -eq 0 ] && echo "Presets OK"
exit "$fail"
