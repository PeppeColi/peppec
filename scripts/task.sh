# scripts/task.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
# The issue's branch and its base, from decide.sh: agent/issue-N on BASE_BRANCH, or the names of
# PEPPEC_BRANCHES (a work unit of a specification starts from the feature branch)
B="${BRANCH:-agent/issue-$ISSUE}"
BASE="${BASE:-${BASE_BRANCH:-main}}"
# A branch left from a pull request already merged, with nothing new on it (an issue reopened
# after a merge whose branch was not removed): the work starts again from the base branch
# The checkout keeps no credentials, and a private repository answers nothing without them
REMOTE="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
tip=$(git ls-remote --heads "$REMOTE" "$B" | cut -f1)
if [ -n "$tip" ] && [ -n "$(gh pr list -R "$REPO" --head "$B" --state merged --json headRefOid \
     --jq "[.[] | select(.headRefOid == \"$tip\")] | .[0].headRefOid // empty")" ]; then
  delete_agent_branch "$B"
fi
# The workspace is on BASE_BRANCH, where the configuration was read. The issue's base may be a
# feature branch: a new branch starts from it, and after.sh compares the work with origin/$BASE
git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/origin/$BASE"
if [ -n "$(git ls-remote --heads "$REMOTE" "$B")" ]; then
  git fetch -q "$REMOTE" "+refs/heads/$B:refs/remotes/origin/$B" && git checkout -q "$B"
else
  git checkout -q -b "$B" "origin/$BASE"
fi
if [ "$ACTION" = start ]; then
  add_label "$ISSUE" "in progress"; rm_label "$ISSUE" "ready"
fi
# A sync work unit, on its first run: the workflow merges the base branch into the feature itself
# and commits the merge as it comes, conflict markers included, without pushing it. The agent
# then only resolves the markers, and after.sh checks its changes against that commit, so the
# changes coming from the base branch are not taken for the agent's (protected paths). The
# work unit's pull request is merged with a merge commit, which keeps the base branch as a parent
conflicts=""
if [ "$ACTION" = start ] && [ "$BASE" != "${BASE_BRANCH:-main}" ] && [ "$(kind_of "$ISSUE")" = sync ] \
   && [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BASE")" ]; then
  id=(-c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL")
  if git "${id[@]}" merge -q --no-edit "origin/${BASE_BRANCH:-main}"; then
    echo "${BASE_BRANCH:-main} merged into $BASE without conflicts"
  else
    conflicts=$(git diff --name-only --diff-filter=U)
    git add -u
    git "${id[@]}" commit -q --no-edit
    echo "Merged ${BASE_BRANCH:-main} into $BASE, conflicts left in: ${conflicts//$'\n'/, }"
  fi
fi
mkdir -p .agent; rm -rf .agent/question.md .agent/answer.md .agent/spec.md .agent/replies .agent/review-id
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
  if [ -n "$conflicts" ]; then
    echo; echo "## Files with conflict markers"
    echo "The workflow merged \`${BASE_BRANCH:-main}\` into the feature; these files still hold \`<<<<<<<\`, \`=======\` and \`>>>>>>>\` markers. Resolve them all, then run the checks."
    echo "$conflicts" | sed 's/^/- /'
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
