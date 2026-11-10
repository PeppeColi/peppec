# scripts/decide.sh
# shellcheck disable=SC2034  # outputs are read indirectly by emit()
set -euo pipefail
source "$(dirname "$0")/lib.sh"
action=none issue="" pr="" sha="" model="" round="" ci_tries="" reason="" minutes=""
emit() {
  for k in action issue pr sha model round ci_tries reason minutes; do
    echo "$k=${!k}" >> "$GITHUB_OUTPUT"
  done
}
trap emit EXIT
[ -n "${GH_TOKEN:-}" ] || { echo "No secrets: event from a fork"; exit 0; }

in_window() {
  local h; h=$(TZ="$TZ_NAME" date +%-H)
  if [ "$WORK_START_HOUR" -le "$WORK_END_HOUR" ]; then
    [ "$h" -ge "$WORK_START_HOUR" ] && [ "$h" -lt "$WORK_END_HOUR" ]
  else
    [ "$h" -ge "$WORK_START_HOUR" ] || [ "$h" -lt "$WORK_END_HOUR" ]
  fi
}
budget() { local used; used=$(marker_get "$1" minutes); echo $(( MAX_ISSUE_MINUTES - ${used:-0} )); }

ctrl=$(labels_of "$CONTROL_ISSUE")
if has "$ctrl" "paused"; then echo "Queue paused"; exit 0; fi
mode=manual; has "$ctrl" "auto mode" && mode=automatic

active=$(gh issue list -R "$REPO" --state open --label "in progress" --json number,createdAt \
  --jq 'sort_by(.createdAt) | .[0].number // empty')

if [ -z "$active" ]; then
  ok=false
  if in_window || [ "$FORCE" = true ]; then ok=true; fi
  if [ "$mode" = manual ] && [ "$EVENT_NAME" = pull_request ] && [ "$EVENT_MERGED" = true ] \
     && [[ "$EVENT_HEAD_REF" == agent/* ]]; then ok=true; fi
  [ "$ok" = true ] || { echo "Outside the work window"; exit 0; }
  issue=$(gh issue list -R "$REPO" --state open --label ready --limit 200 --json number,createdAt,labels \
    --jq '[.[] | select([.labels[].name] | index("needs human") | not)] | sort_by(.createdAt) | .[0].number // empty')
  [ -n "$issue" ] || { echo "No ready issues"; exit 0; }
  model=sonnet; has "$(labels_of "$issue")" "complexity: complex" && model=opus
  action=start; round=1; minutes=$(( $(budget "$issue") + 10 )); exit 0
fi

issue=$active
il=$(labels_of "$issue")
for b in "needs human" "question open"; do
  has "$il" "$b" && { echo "Stopped: $b"; exit 0; }
done
if has "$il" "awaiting quota"; then
  since=$(gh api --paginate "repos/$REPO/issues/$issue/events?per_page=100" \
    --jq '.[] | select(.event == "labeled" and .label.name == "awaiting quota") | .created_at' | tail -1)
  if [ -n "$since" ]; then
    age=$(age_minutes "$since")
    [ "$age" -ge "$QUOTA_RETRY_MINUTES" ] || { echo "Waiting for quota ($age min)"; exit 0; }
  fi
  rm_label "$issue" "awaiting quota"
fi

base=sonnet; has "$il" "complexity: complex" && base=opus
pr=$(gh pr list -R "$REPO" --head "agent/issue-$issue" --state open --json number --jq '.[0].number // empty')
left=$(budget "$issue")
if [ "$left" -le 0 ]; then action=stop; reason="time budget of $MAX_ISSUE_MINUTES minutes used up"; exit 0; fi
minutes=$(( left + 10 ))
if [ -z "$pr" ]; then action=start; model=$base; round=1; exit 0; fi

sha=$(gh pr view "$pr" -R "$REPO" --json headRefOid --jq .headRefOid)
waited=$(age_minutes "$(gh api "repos/$REPO/commits/$sha" --jq .commit.committer.date)")
pl=$(labels_of "$pr")
round=$( { grep -oP '^review \K[0-9]+' <<< "$pl" || true; } | sort -n | tail -1); round=${round:-1}
tries=$( { grep -oP '^ci \K[0-9]+' <<< "$pl" || true; } | sort -n | tail -1); tries=${tries:-0}
model=$base; [ "$round" -ge "$OPUS_FROM_ROUND" ] && model=opus

# CI_CHECK is the name of the check run to wait for ("ci / ci" with the reusable CI workflow)
ci=$(gh api -X GET "repos/$REPO/commits/$sha/check-runs" -f check_name="$CI_CHECK" \
  --jq '.check_runs[0] | if . == null then "pending" elif .status != "completed" then "pending" else .conclusion end')
case "$ci" in
  pending)
    if [ "$waited" -ge "$STALL_MINUTES" ]; then action=stop; reason="no CI result after $waited minutes"; exit 0; fi
    echo "CI running ($waited min)"; exit 0;;
  success) ;;
  *)
    if [ "$tries" -ge "$MAX_CI_ATTEMPTS" ]; then
      action=stop; reason="checks still failing after $tries attempts"; exit 0
    fi
    action=fix_ci; ci_tries=$((tries + 1)); exit 0;;
esac

state=$(gh api "repos/$REPO/pulls/$pr/reviews?per_page=100" --jq "[.[] | select(.user.login == \"coderabbitai[bot]\" and .commit_id == \"$sha\" and (.state == \"APPROVED\" or .state == \"CHANGES_REQUESTED\"))] | last | .state // \"none\"")
case "$state" in
  none)
    # Reviews start only on request: ask once per commit, as soon as the checks are green
    if [ "$(marker_get "$pr" rerequest)" != "$sha" ]; then
      action=rerequest
    elif [ "$waited" -ge $(( 2 * STALL_MINUTES )) ]; then
      action=stop; reason="no CodeRabbit review after $waited minutes"
    else
      echo "Waiting for CodeRabbit ($waited min)"
    fi
    exit 0;;
  APPROVED)
    if [ "$mode" = automatic ]; then action=merge
    elif ! has "$pl" "ready to merge"; then action=notify_ready; fi
    exit 0;;
  CHANGES_REQUESTED)
    if [ "$round" -ge "$MAX_REVIEW_ROUNDS" ]; then
      action=stop; reason="review not passed after $round rounds"; exit 0
    fi
    round=$((round + 1)); model=$base; [ "$round" -ge "$OPUS_FROM_ROUND" ] && model=opus
    action=fix_review; exit 0;;
esac
