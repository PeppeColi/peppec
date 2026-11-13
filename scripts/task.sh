# scripts/task.sh
# Runs in the prepare job, with the app's token, before the agent job: labels the issue and
# writes what the agent reads (.agent/task.md, .agent/spec.md), uploaded for the agent job. No
# code of the repository runs here, and the agent job never receives a token that can write
set -euo pipefail
source "$(dirname "$0")/lib.sh"
B="${BRANCH:-agent/issue-$ISSUE}"
# A branch left from a pull request already merged, with nothing new on it (an issue reopened
# after a merge whose branch was not removed): the work starts again from the base branch
REMOTE="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
tip=$(git ls-remote --heads "$REMOTE" "$B" | cut -f1)
if [ -n "$tip" ] && [ -n "$(gh pr list -R "$REPO" --head "$B" --state merged --json headRefOid,isCrossRepository \
     --jq "[.[] | select((.isCrossRepository | not) and .headRefOid == \"$tip\")] | .[0].headRefOid // empty")" ]; then
  delete_agent_branch "$B"
fi
if [ "$ACTION" = start ]; then
  add_label "$ISSUE" "in progress"; rm_label "$ISSUE" "ready"
fi
rm -rf .agent; mkdir -p .agent
# The issue this one is a sub-issue of, when you wrote it: the specification of the larger
# piece of work, given to the agent as background in a file of its own
if parent=$(gh api "repos/$REPO/issues/$ISSUE/parent" 2> /dev/null) \
   && [ "$(jq -r .user.login <<< "$parent")" = "$OWNER_LOGIN" ]; then
  {
    echo "# Specification: $(jq -r .title <<< "$parent") (#$(jq -r .number <<< "$parent"))"
    echo; jq -r '.body // ""' <<< "$parent"
  } > .agent/spec.md
fi
I=$(gh api "repos/$REPO/issues/$ISSUE")
# The queue builds only issues you or the app wrote (decide.sh): a second check, since the body
# goes to the agent as it is
author=$(jq -r .user.login <<< "$I")
if [ "$author" != "$OWNER_LOGIN" ] && [ "$author" != "$APP_LOGIN" ]; then
  echo "::error::Issue #$ISSUE was written by $author, not by $OWNER_LOGIN or the app: not given to the agent"
  exit 1
fi
{
  echo "title<<PEPPEC_TITLE_END"; jq -r .title <<< "$I"; echo "PEPPEC_TITLE_END"
  echo "kind=$(kind_of "$ISSUE")"
} >> "$GITHUB_OUTPUT"
{
  echo "# Issue #$ISSUE: $(jq -r .title <<< "$I")"
  echo; jq -r '.body // ""' <<< "$I"
  echo; echo "## Authorized comments"
  # Read with the REST API: "gh issue view" names the app without "[bot]", so the answers
  # and hints the Telegram bot posts as the app would not match APP_LOGIN
  gh api --paginate "repos/$REPO/issues/$ISSUE/comments?per_page=100" | jq -r --arg a "$OWNER_LOGIN" --arg b "$APP_LOGIN" \
    '.[] | select(.user.login == $a or .user.login == $b)
     | select(.body | startswith("<!-- peppec:") | not) | "- \(.user.login): \(.body)"'
  # The end-to-end tests of the feature are selected by the number of its specification: the
  # agent writes the specification's scenarios so that the command picks them
  if [ -n "${PEPPEC_E2E_FEATURE:-}" ] && [ -s .agent/spec.md ]; then
    sn=$(head -1 .agent/spec.md | sed -nE 's/.*\(#([0-9]+)\)$/\1/p')
    if [ -n "$sn" ]; then
      echo; echo "## End-to-end tests"
      echo "This repository runs the end-to-end tests of this feature with:"
      echo; echo "    ${PEPPEC_E2E_FEATURE//\{spec\}/$sn}"
      echo; echo "When this work unit writes end-to-end tests (for example the scenarios of the specification), make sure that command selects them, and that it still passes."
    fi
  fi
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
