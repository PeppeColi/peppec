# scripts/control.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
case "$ACTION" in
  stop)
    if [ "${SKIP_IF_BLOCKED:-false}" = true ]; then
      il=$(labels_of "$ISSUE")
      for b in "needs human" "question open" "awaiting quota"; do
        has "$il" "$b" && { echo "Already handled: $b"; exit 0; }
      done
    fi
    add_label "$ISSUE" "needs human"
    if [ -n "${PR:-}" ]; then add_label "$PR" "needs human"; fi
    notify_blocked "Queue stopped on #$ISSUE: $REASON. $RUN_URL";;
  merge)
    head=$(gh pr view "$PR" -R "$REPO" --json headRefName --jq .headRefName)
    # A sync work unit keeps the base branch as a parent: a squash would lose it (task.sh)
    method=--squash; [ "$(kind_of "$ISSUE")" != sync ] || method=--merge
    # Only the commit decide.sh judged: a push in between leaves the pull request unmerged
    # REASON set: the review passed at its last round with minor findings only (decide.sh).
    # CodeRabbit's requests for changes are dismissed with that reason: on the pull request it
    # reads as a decision, not as findings ignored, and a branch rule cannot hold the merge on them
    if [ -n "${REASON:-}" ]; then
      for id in $(gh api "repos/$REPO/pulls/$PR/reviews?per_page=100" \
                    --jq '.[] | select(.user.login == "coderabbitai[bot]" and .state == "CHANGES_REQUESTED") | .id'); do
        gh api -X PUT "repos/$REPO/pulls/$PR/reviews/$id/dismissals" -f event=DISMISS \
          -f message="PEPPEC: $REASON. They are left as they are, with no follow-up issue." > /dev/null \
          || echo "Could not dismiss CodeRabbit's review $id"
      done
    fi
    gh pr merge "$PR" -R "$REPO" "$method" --match-head-commit "$SHA"
    delete_agent_branch "$head"
    close_merged "$ISSUE"
    notify_info "Merged PR #$PR (issue #$ISSUE)${REASON:+: $REASON}."
    notify_feature_done "$ISSUE";;
  notify_ready)
    add_label "$PR" "ready to merge"
    notify "PR #$PR for issue #$ISSUE is ready to merge${REASON:+ ($REASON)}: https://github.com/$REPO/pull/$PR";;
  rerequest)
    # Posted with your token: CodeRabbit ignores commands written by bots, the app included
    GH_TOKEN="$AGENT_TOKEN" gh pr comment "$PR" -R "$REPO" --body "@coderabbitai review

<!-- peppec:rerequest=$SHA -->";;
  full_review)
    # Reviews the whole pull request again, and ends with a verdict on its latest commit
    GH_TOKEN="$AGENT_TOKEN" gh pr comment "$PR" -R "$REPO" --body "@coderabbitai full review

<!-- peppec:full-review=$SHA -->";;
esac
