# scripts/after.sh
# Runs in the publish job, on a fresh runner where no code of the repository has run: the only
# job that holds the tokens that can write. The agent job's result ($RESULT) is data: its changes
# are applied as a patch on the commit the agent started from, built again here from the agent
# job's outputs written before Claude ran (workspace.sh), and every check runs on the whole change.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
B="${BRANCH:-agent/issue-$ISSUE}"
BASE="${BASE:-${BASE_BRANCH:-main}}"
REMOTE="https://x-access-token:${AGENT_TOKEN}@github.com/${REPO}.git"

# Time budget: add this run's working minutes to the issue counter
used=$(GH_TOKEN="$APP_TOKEN" marker_get "$ISSUE" minutes)
spent=$(( ($(date +%s) - CLAUDE_START) / 60 + 1 ))
GH_TOKEN="$APP_TOKEN" marker_set "$ISSUE" minutes $(( ${used:-0} + spent ))

# The commit the agent started from: the tip of its branch, of its base, or the merge of a sync
# work unit, made again here on the same two commits
git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/origin/$BASE"
if [ -n "$(git ls-remote --heads "$REMOTE" "$B")" ]; then
  git fetch -q "$REMOTE" "+refs/heads/$B:refs/remotes/origin/$B"
fi
if [ -n "${MERGE_PARENTS:-}" ]; then
  read -r p1 p2 <<< "$MERGE_PARENTS"
  git fetch -q "$REMOTE" "+refs/heads/${BASE_BRANCH:-main}:refs/remotes/origin/${BASE_BRANCH:-main}"
  git fetch -q "$REMOTE" "$p1" "$p2"
  git checkout -q -B "$B" "$p1"
  git update-ref "refs/remotes/origin/${BASE_BRANCH:-main}" "$p2"
  sync_merge "${BASE_BRANCH:-main}" > /dev/null
else
  git fetch -q "$REMOTE" "$START"
  git checkout -q -B "$B" "$START"
fi
if [ "$(git rev-parse 'HEAD^{tree}')" != "$START_TREE" ]; then
  add_label "$ISSUE" "needs human"
  notify_blocked "Could not rebuild the commit the agent started from on #$ISSUE: nothing was pushed. $RUN_URL"
  exit 0
fi

# The agent's files: the question, the answer, the replies. The review being answered comes from
# the prepare job, not from the agent
rm -rf .agent; mkdir -p .agent
for f in question.md answer.md; do
  if [ -f "$RESULT/$f" ] && [ ! -L "$RESULT/$f" ]; then cp "$RESULT/$f" ".agent/$f"; fi
done
if [ -d "$RESULT/replies" ] && [ ! -L "$RESULT/replies" ]; then
  mkdir -p .agent/replies
  find "$RESULT/replies" -maxdepth 1 -type f -name '*.md' -exec cp {} .agent/replies/ \;
fi
if [ -s "$TASK_DIR/review-id" ]; then cp "$TASK_DIR/review-id" .agent/review-id; fi
failure=$(head -c 10 "$RESULT/failure" 2> /dev/null || true)

if [ "$OUTCOME" != success ]; then
  if [ "$failure" = token ]; then
    add_label "$ISSUE" "needs human"
    notify_blocked "Claude token rejected while working on #$ISSUE: run 'claude setup-token' and update the CLAUDE_CODE_OAUTH_TOKEN secret."
  elif [ "$failure" = quota ]; then
    add_label "$ISSUE" "awaiting quota"
    notify_info "Claude quota exhausted while working on #$ISSUE: will retry automatically."
  else
    add_label "$ISSUE" "needs human"
    notify_blocked "Agent error on #$ISSUE: $RUN_URL"
  fi
  exit 0
fi

if [ -s .agent/question.md ]; then
  # The answer the agent recommends goes in the same comment, after a marker: the bot's
  # Accept button reads it back from there (accept in bot/bot.py)
  recommended=""
  if [ -s .agent/answer.md ]; then recommended=$(cat .agent/answer.md); fi
  if [ -n "$recommended" ]; then
    printf '%s\n\n%s\n**Recommended answer**\n\n%s\n' "$(cat .agent/question.md)" "$RECOMMENDED_MARK" "$recommended" \
      | gh issue comment "$ISSUE" -R "$REPO" --body-file -
  else
    gh issue comment "$ISSUE" -R "$REPO" --body-file .agent/question.md
  fi
  add_label "$ISSUE" "question open"
  if [ -n "$recommended" ]; then
    notify "Question on #$ISSUE:
$(cat .agent/question.md)

Recommended answer:
$recommended

Press Accept to send it, or reply to this message with your own answer." \
      "{\"inline_keyboard\":[[{\"text\":\"Accept #$ISSUE\",\"callback_data\":\"accept|$ISSUE|\"}]]}"
  else
    notify "Question on #$ISSUE:
$(cat .agent/question.md)

Reply to this message to unblock it."
  fi
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
# The agent's changes, as a patch: git refuses paths inside .git or outside the repository
if [ -s "$RESULT/changes.patch" ] && ! git apply --index --binary "$RESULT/changes.patch"; then
  add_label "$ISSUE" "needs human"
  notify_blocked "The agent's changes on #$ISSUE could not be applied, nothing was pushed. $RUN_URL"
  exit 0
fi
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
# A sync work unit: no conflict marker may be left in what goes to the feature branch
if [ "$BASE" != "${BASE_BRANCH:-main}" ] && [ "$(kind_of "$ISSUE")" = sync ]; then
  left=$(git diff -z --cached --name-only "origin/$BASE" -- \
    | xargs -0 -r git grep --cached -l -E '^(<<<<<<<|>>>>>>>)( |$)' -- 2> /dev/null || true)
  if [ -n "$left" ]; then
    add_label "$ISSUE" "needs human"
    notify_blocked "Conflict markers are still in these files on #$ISSUE, nothing was pushed:
$left
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

# Findings the agent left unchanged on purpose: its reasons go to CodeRabbit, in the thread of
# each finding (.agent/replies/<comment id>.md) or on the pull request (.agent/replies/review.md).
# CodeRabbit weighs them and approves when convinced; decide.sh gives it time before the next round
replied=false
if [ "$ACTION" = fix_review ] && [ -d .agent/replies ] && [ -s .agent/review-id ]; then
  marker="<!-- peppec:reply=$(cat .agent/review-id) -->"
  for f in .agent/replies/*.md; do
    [ -s "$f" ] || continue
    id=$(basename "$f" .md)
    body="@coderabbitai $(cat "$f")

$marker"
    if [ "$id" = review ]; then
      gh pr comment "$PR" -R "$REPO" --body "$body" > /dev/null && replied=true
    elif [[ "$id" =~ ^[0-9]+$ ]]; then
      if gh api "repos/$REPO/pulls/$PR/comments/$id/replies" -f body="$body" > /dev/null; then
        replied=true
      else
        echo "Could not reply to review comment $id"
      fi
    fi
  done
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
    if [ "$BASE" != "${BASE_BRANCH:-main}" ] && [ "$(kind_of "$ISSUE")" = sync ]; then
      body="$body

It brings \`${BASE_BRANCH:-main}\` into the feature: merge it with a **merge commit**, not a squash, or the feature will conflict again."
    fi
    # Which issue the pull request belongs to, whatever its branch is called
    body="$body

<!-- peppec:issue=$ISSUE -->"
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

if [ "$pushed" = false ] && [ "$replied" = false ]; then
  add_label "$ISSUE" "needs human"
  notify_blocked "The agent produced no changes on #$ISSUE."
  exit 0
fi
if [ "$pushed" = false ]; then
  notify_info "The agent changed nothing on #$ISSUE and answered CodeRabbit instead: https://github.com/$REPO/pull/$PR"
fi

case "$ACTION" in
  fix_ci)
    [ "$CI_TRIES" -gt 1 ] && rm_label "$PR" "ci $((CI_TRIES - 1))"
    add_label "$PR" "ci $CI_TRIES";;
  fix_review)
    rm_label "$PR" "review $((ROUND - 1))"; add_label "$PR" "review $ROUND"
    for n in 1 2 3 4 5; do rm_label "$PR" "ci $n"; done;;
esac
