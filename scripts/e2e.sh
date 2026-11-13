# scripts/e2e.sh plan
# Decides whether a CI job of end-to-end tests runs (.github/workflows/ci.yml): only on the pull
# request of a feature branch into the base branch, and only when the repository has the command
# (COMMAND, from PEPPEC_E2E_FEATURE or PEPPEC_E2E_ALL). Outputs run=true and the command, with
# {spec} replaced by the number of the specification, read from the marker the workflow puts in
# the body of that pull request (feature_pr in lib.sh)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[ "${1:-}" = plan ] || { echo "usage: e2e.sh plan" >&2; exit 2; }
skip() { echo "End-to-end tests not run: $1"; exit 0; }
[ -n "${COMMAND:-}" ] || skip "no command for this level"
[ -n "${HEAD_REF:-}" ] || skip "not a pull request"
[ "$BASE_REF" = "$BASE_BRANCH" ] && is_feature_branch "$HEAD_REF" || skip "not a feature branch into $BASE_BRANCH"
spec=$(sed -nE 's/.*<!-- peppec:feature=([0-9]+) -->.*/\1/p' <<< "${PR_BODY:-}" | head -1)
[ -n "$spec" ] || skip "no specification marker in the pull request"
echo "Specification #$spec"
{
  echo "run=true"
  d="PEPPEC_${RANDOM}${RANDOM}"
  printf 'command<<%s\n%s\n%s\n' "$d" "${COMMAND//\{spec\}/$spec}" "$d"
} >> "$GITHUB_OUTPUT"
