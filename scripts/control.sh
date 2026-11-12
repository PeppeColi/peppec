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
    gh pr merge "$PR" -R "$REPO" --squash
    close_merged "$ISSUE"
    notify "Merged PR #$PR (issue #$ISSUE).";;
  notify_ready)
    add_label "$PR" "ready to merge"
    notify "PR #$PR for issue #$ISSUE is ready to merge: https://github.com/$REPO/pull/$PR";;
  rerequest)
    # Posted with your token: CodeRabbit ignores commands written by bots, the app included
    GH_TOKEN="$AGENT_TOKEN" gh pr comment "$PR" -R "$REPO" --body "@coderabbitai review

<!-- peppec:rerequest=$SHA -->";;
esac
