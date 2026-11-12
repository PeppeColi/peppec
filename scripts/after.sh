# scripts/after.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
B="agent/issue-$ISSUE"
BASE="${BASE_BRANCH:-main}"

# Time budget: add this run's working minutes to the issue counter
used=$(GH_TOKEN="$APP_TOKEN" marker_get "$ISSUE" minutes)
spent=$(( ($(date +%s) - CLAUDE_START) / 60 + 1 ))
GH_TOKEN="$APP_TOKEN" marker_set "$ISSUE" minutes $(( ${used:-0} + spent ))

if [ "$OUTCOME" != success ]; then
  log=${EXEC_FILE:-/dev/null}; [ -f "$log" ] || log=/dev/null
  if grep -qiE '\b401\b|invalid.{0,20}token|authentication' "$log"; then
    add_label "$ISSUE" "needs human"
    notify_blocked "Claude token rejected while working on #$ISSUE: run 'claude setup-token' and update the CLAUDE_CODE_OAUTH_TOKEN secret."
  elif grep -qiE 'usage limit|limit reached|rate limit|resets at' "$log"; then
    add_label "$ISSUE" "awaiting quota"
    notify "Claude quota exhausted while working on #$ISSUE: will retry automatically."
  else
    add_label "$ISSUE" "needs human"
    notify_blocked "Agent error on #$ISSUE: $RUN_URL"
  fi
  exit 0
fi

if [ -s .agent/question.md ]; then
  gh issue comment "$ISSUE" -R "$REPO" --body-file .agent/question.md
  add_label "$ISSUE" "question open"
  notify "Question on #$ISSUE:
$(cat .agent/question.md)

Reply to this message to unblock it."
  exit 0
fi

pushed=false
# Stage everything, then take back out of the index the working folders of the workflow and
# the paths that are never committed (git pathspecs, one per line: dependencies, caches).
# Naming them as excluded pathspecs of "git add" fails when the host's .gitignore lists them
skip=(.agent _ctl _preset _extra)
while IFS= read -r p; do
  if [ -n "$p" ]; then skip+=("$p"); fi
done <<< "${NEVER_COMMIT:-}"
git add -A
git reset -q -- "${skip[@]}"

# Protected paths (git pathspecs, one per line): changes to them are never committed
prot=()
while IFS= read -r p; do
  if [ -n "$p" ]; then prot+=("$p"); fi
done <<< "${PROTECTED_PATHS:-}"
if [ "${#prot[@]}" -gt 0 ]; then
  touched=$(git diff --cached --name-only -- "${prot[@]}")
  if [ -n "$touched" ]; then
    add_label "$ISSUE" "needs human"
    notify_blocked "The agent changed protected files on #$ISSUE, nothing was committed:
$touched
$RUN_URL"
    exit 0
  fi
fi
if ! git diff --cached --quiet; then
  case "$ACTION" in
    start) MSG="feat: $TITLE (#$ISSUE)";;
    fix_ci) MSG="fix: checks, attempt $CI_TRIES (#$ISSUE)";;
    fix_review) MSG="fix: review round $ROUND (#$ISSUE)";;
  esac
  git -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" commit -q -m "$MSG"
  git push -q "https://x-access-token:${AGENT_TOKEN}@github.com/${REPO}.git" "HEAD:$B"
  pushed=true
fi

if [ "$ACTION" = start ]; then
  # Also recovers a branch pushed in an earlier run whose PR was never created
  if [ "$(git rev-list --count "origin/$BASE..HEAD")" -gt 0 ]; then
    [ "$pushed" = true ] || git push -q "https://x-access-token:${AGENT_TOKEN}@github.com/${REPO}.git" "HEAD:$B"
    # "Closes" works only towards the default branch. Towards another base it is left out:
    # the workflow closes the issue, and the keyword would close it a second time, even if
    # reopened in the meantime, when the base branch is later merged into the default one
    body="Closes #$ISSUE"
    if [ "$BASE" != "$(gh api "repos/$REPO" --jq .default_branch)" ]; then
      body="Issue #$ISSUE. The workflow closes it when this pull request is merged into \`$BASE\`."
    fi
    # What the issue leaves out goes into the pull request: the reviewer sees only the pull
    # request, and would otherwise ask for work that belongs to another issue of the feature
    out=$(gh issue view "$ISSUE" -R "$REPO" --json body --jq '.body // ""' | out_of_scope)
    if [ -n "$out" ]; then
      body="$body

## Out of scope

The issue leaves the following out on purpose, usually because another issue covers it. Please do not ask for it in the review.

$out"
    fi
    url=$(gh pr create -R "$REPO" --head "$B" --base "$BASE" --title "$TITLE" --body "$body")
    add_label "${url##*/}" "review 1"
    exit 0
  fi
fi

if [ "$pushed" = false ]; then
  add_label "$ISSUE" "needs human"
  notify_blocked "The agent produced no changes on #$ISSUE."
  exit 0
fi

case "$ACTION" in
  fix_ci)
    [ "$CI_TRIES" -gt 1 ] && rm_label "$PR" "ci $((CI_TRIES - 1))"
    add_label "$PR" "ci $CI_TRIES";;
  fix_review)
    rm_label "$PR" "review $((ROUND - 1))"; add_label "$PR" "review $ROUND"
    for n in 1 2 3 4 5; do rm_label "$PR" "ci $n"; done;;
esac
