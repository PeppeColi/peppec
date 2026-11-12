# scripts/task.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
B="agent/issue-$ISSUE"
# A branch left from a pull request already merged, with nothing new on it (an issue reopened
# after a merge whose branch was not removed): the work starts again from the base branch
# The checkout keeps no credentials, and a private repository answers nothing without them
REMOTE="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
tip=$(git ls-remote --heads "$REMOTE" "$B" | cut -f1)
if [ -n "$tip" ] && [ -n "$(gh pr list -R "$REPO" --head "$B" --state merged --json headRefOid \
     --jq "[.[] | select(.headRefOid == \"$tip\")] | .[0].headRefOid // empty")" ]; then
  delete_agent_branch "$B"
fi
if [ -n "$(git ls-remote --heads "$REMOTE" "$B")" ]; then
  git fetch -q "$REMOTE" "+refs/heads/$B:refs/remotes/origin/$B" && git checkout -q "$B"
else
  git checkout -q -b "$B"
fi
if [ "$ACTION" = start ]; then
  add_label "$ISSUE" "in progress"; rm_label "$ISSUE" "ready"
fi
mkdir -p .agent; rm -rf .agent/question.md .agent/spec.md .agent/replies .agent/review-id
# The issue this one is a sub-issue of, when you wrote it: the specification of the larger
# piece of work, given to the agent as background in a file of its own
if parent=$(gh api "repos/$REPO/issues/$ISSUE/parent" 2> /dev/null) \
   && [ "$(jq -r .user.login <<< "$parent")" = "$OWNER_LOGIN" ]; then
  {
    echo "# Specification: $(jq -r .title <<< "$parent") (#$(jq -r .number <<< "$parent"))"
    echo; jq -r '.body // ""' <<< "$parent"
  } > .agent/spec.md
fi
I=$(gh issue view "$ISSUE" -R "$REPO" --json title,body)
echo "title=$(jq -r .title <<< "$I")" >> "$GITHUB_OUTPUT"
# The app's short name, for the bots allowed to trigger Claude: "name[bot]" -> "name"
echo "app_slug=${APP_LOGIN%\[bot\]}" >> "$GITHUB_OUTPUT"
{
  echo "# Issue #$ISSUE: $(jq -r .title <<< "$I")"
  echo; jq -r .body <<< "$I"
  echo; echo "## Authorized comments"
  # Read with the REST API: "gh issue view" names the app without "[bot]", so the answers
  # and hints the Telegram bot posts as the app would not match APP_LOGIN
  gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" | jq -r --arg a "$OWNER_LOGIN" --arg b "$APP_LOGIN" \
    '.[] | select(.user.login == $a or .user.login == $b)
     | select(.body | startswith("<!-- peppec:") | not) | "- \(.user.login): \(.body)"'
  if [ "$ACTION" = fix_ci ]; then
    echo; echo "## Failed checks (last 200 lines)"
    run=$(gh run list -R "$REPO" --workflow "$CI_WORKFLOW" --branch "$B" --limit 1 --json databaseId --jq '.[0].databaseId')
    gh run view "$run" -R "$REPO" --log-failed | tail -n 200
  fi
  if [ "$ACTION" = fix_review ]; then
    rid=$(gh api "repos/$REPO/pulls/$PR/reviews?per_page=100" \
      --jq '[.[] | select(.user.login == "coderabbitai[bot]" and .state == "CHANGES_REQUESTED")] | last | .id')
    # after.sh posts the agent's replies as answers to this review
    echo "$rid" > .agent/review-id
    echo; echo "## CodeRabbit review to address"
    gh api "repos/$REPO/pulls/$PR/reviews/$rid" --jq .body
    # Each finding with its number, followed by the replies in its thread from the owner (and
    # so the agent's earlier replies), the app and CodeRabbit: nobody else's text reaches the agent
    thread=$(mktemp)
    gh api --paginate "repos/$REPO/pulls/$PR/comments?per_page=100" | jq -s 'add // []' > "$thread"
    gh api "repos/$REPO/pulls/$PR/reviews/$rid/comments?per_page=100" \
      | jq -r --slurpfile all "$thread" --arg a "$OWNER_LOGIN" --arg b "$APP_LOGIN" '.[] | . as $c
        | "### \(.path):\(.line // .original_line) (comment \(.id))\n\(.body)\n",
          ($all[0][] | select(.in_reply_to_id == $c.id
              and (.user.login == $a or .user.login == $b or .user.login == "coderabbitai[bot]"))
           | "#### Reply from \(.user.login)\n\(.body)\n")'
    rm -f "$thread"
  fi
} > .agent/task.md
