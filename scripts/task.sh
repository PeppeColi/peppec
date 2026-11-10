# scripts/task.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
B="agent/issue-$ISSUE"
if git ls-remote --exit-code --heads origin "$B" > /dev/null; then
  git fetch -q origin "$B" && git checkout -q "$B"
else
  git checkout -q -b "$B"
fi
if [ "$ACTION" = start ]; then
  add_label "$ISSUE" "in progress"; rm_label "$ISSUE" "ready"
fi
mkdir -p .agent; rm -f .agent/question.md
I=$(gh issue view "$ISSUE" -R "$REPO" --json title,body,comments)
echo "title=$(jq -r .title <<< "$I")" >> "$GITHUB_OUTPUT"
# The app's short name, for the bots allowed to trigger Claude: "name[bot]" -> "name"
echo "app_slug=${APP_LOGIN%\[bot\]}" >> "$GITHUB_OUTPUT"
{
  echo "# Issue #$ISSUE: $(jq -r .title <<< "$I")"
  echo; jq -r .body <<< "$I"
  echo; echo "## Authorized comments"
  jq -r --arg a "$OWNER_LOGIN" --arg b "$APP_LOGIN" \
    '.comments[] | select(.author.login == $a or .author.login == $b)
     | select(.body | startswith("<!-- peppec:") | not) | "- \(.author.login): \(.body)"' <<< "$I"
  if [ "$ACTION" = fix_ci ]; then
    echo; echo "## Failed checks (last 200 lines)"
    run=$(gh run list -R "$REPO" --workflow "$CI_WORKFLOW" --branch "$B" --limit 1 --json databaseId --jq '.[0].databaseId')
    gh run view "$run" -R "$REPO" --log-failed | tail -n 200
  fi
  if [ "$ACTION" = fix_review ]; then
    rid=$(gh api "repos/$REPO/pulls/$PR/reviews?per_page=100" \
      --jq '[.[] | select(.user.login == "coderabbitai[bot]" and .state == "CHANGES_REQUESTED")] | last | .id')
    echo; echo "## CodeRabbit review to address"
    gh api "repos/$REPO/pulls/$PR/reviews/$rid" --jq .body
    gh api "repos/$REPO/pulls/$PR/reviews/$rid/comments?per_page=100" \
      --jq '.[] | "### \(.path):\(.line // .original_line)\n\(.body)\n"'
  fi
} > .agent/task.md
