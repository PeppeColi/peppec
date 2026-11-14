# scripts/decide.sh
# shellcheck disable=SC2034  # outputs are read indirectly by emit()
set -euo pipefail
source "$(dirname "$0")/lib.sh"
action=none issue="" pr="" sha="" size="" round="" ci_tries="" reason="" minutes="" branch="" base=""
emit() {
  for k in action issue pr sha size round ci_tries reason minutes branch base; do
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
# The size label of an issue picks the model (models in .github/peppec.yml); M without a label
size_of() {
  if has "$1" "size: L"; then echo l; elif has "$1" "size: S"; then echo s; else echo m; fi
}
# A review request that CodeRabbit does not answer at all is repeated after this many minutes,
# up to this many requests per commit
REVIEW_RETRY_MINUTES=20 REVIEW_REQUESTS=3
budget() { local used; used=$(marker_get "$1" minutes); echo $(( MAX_ISSUE_MINUTES - ${used:-0} )); }

# A pull request of the agent merged by hand: its branch is removed here.
# A feature branch you merged: its specification is closed and the branch removed
if [ "$EVENT_NAME" = pull_request ] && [ "$EVENT_MERGED" = true ]; then
  delete_agent_branch "$EVENT_HEAD_REF"
  finish_feature "$EVENT_HEAD_REF"
fi

ctrl=$(labels_of "$CONTROL_ISSUE")
# "paused" on the control panel stops only new issues: the issue in progress goes on to its merge
# (or "ready to merge"), merges done by hand are tidied up, and the sync and hotfix work units the
# queue opens to finish a feature already built still start
paused=false; has "$ctrl" "paused" && paused=true
mode=manual; has "$ctrl" "auto mode" && mode=automatic

# Without its base branch (deleted by hand, or by GitHub after a merge into the default branch)
# the queue has nothing to start from or to merge into: every issue would fail in turn. So the
# whole queue stops here and you are told once. The "base missing" label on the control panel
# remembers that the message was sent; the queue goes on by itself when the branch is back
if base_branch_missing; then
  echo "The base branch $BASE_BRANCH does not exist: queue stopped"
  if ! has "$ctrl" "base missing"; then
    add_label "$CONTROL_ISSUE" "base missing"
    notify "Queue stopped: the base branch $BASE_BRANCH does not exist. Create it again, for example with: git push origin $(gh api "repos/$REPO" --jq .default_branch):$BASE_BRANCH. The queue goes on by itself once the branch is back. $RUN_URL"
  fi
  exit 0
fi
if has "$ctrl" "base missing"; then
  rm_label "$CONTROL_ISSUE" "base missing"
  notify_info "The base branch $BASE_BRANCH is back: the queue goes on."
fi

# Finished features waiting for you get the base branch again when it went on (resync_features),
# and their end-to-end tests are read (judge_features)
resync_features
judge_features

# True when issue $1 is a work unit of a feature already started (its feature branch exists) whose
# pull request into the base branch is not open yet: the feature is still being built
under_construction() {
  local spec fb
  spec=$(spec_of "$1"); [ -n "$spec" ] || return 1
  fb=$(feature_of "$(jq -r .number <<< "$spec")"); [ -n "$fb" ] || return 1
  [ -z "$(pr_from "$fb")" ]
}

# $1, optional: an issue to leave out
active_issue() {
  gh issue list -R "$REPO" --state open --label "in progress" --json number,createdAt \
    --jq "[.[] | select(.number != ${1:-0})] | sort_by(.createdAt) | .[0].number // empty"
}
# The agent's pull request of an issue, if it was merged since the issue last entered
# "in progress" or was reopened: an issue reopened after a merge is worked on again
merged_pr() {
  local since
  since=$(gh api --paginate "repos/$REPO/issues/$1/events?per_page=100" \
    --jq '.[] | select(.event == "reopened" or (.event == "labeled" and .label.name == "in progress")) | .created_at' | tail -1)
  [ -n "$since" ] || return 0
  local b; b=$(branch_of "$1")
  gh pr list -R "$REPO" --head "${b%%:*}" --state merged --json number,mergedAt,isCrossRepository \
    --jq "[.[] | select((.isCrossRepository | not) and .mergedAt >= \"$since\")] | sort_by(.mergedAt) | last | .number // empty"
}

# The open issues that block an issue (GitHub's "blocked by" relationship), on one line.
# $2, optional: an issue to count as closed
open_blockers() {
  gh api --paginate "repos/$REPO/issues/$1/dependencies/blocked_by?per_page=100" \
    --jq ".[] | select(.state == \"open\" and .number != ${2:-0}) | \"#\(.number)\"" | paste -sd' ' -
}

active=$(active_issue) closed=""
# An open issue whose pull request is merged: the base branch is not the default one, so
# GitHub did not close it, and it was merged by hand or the run that merged it stopped early
if [ -n "$active" ]; then
  done_pr=$(merged_pr "$active")
  if [ -n "$done_pr" ]; then
    echo "PR #$done_pr of issue #$active is merged: closing the issue"
    close_merged "$active"
    # Still there when the run that follows the merge was skipped or stopped early
    b=$(branch_of "$active"); delete_agent_branch "${b%%:*}"
    # Left out by number: right after the close the lists may still show it as open
    closed=$active
    notify_feature_done "$closed"
    active=$(active_issue "$closed")
  fi
fi

# A merge done by hand into the default branch: GitHub has closed the issue by itself
if [ "$EVENT_NAME" = pull_request ] && [ "$EVENT_MERGED" = true ]; then
  merged_issue=$(issue_of_branch "$EVENT_HEAD_REF")
  if [ -n "$merged_issue" ] && [ "$merged_issue" != "$closed" ]; then notify_feature_done "$merged_issue"; fi
fi

# Issues the planning skills labelled ready-for-agent but not ready: the label map in
# docs/agents/triage-labels.md is not the one init wrote, or the skills changed with an update.
# The queue never builds them; told once per issue
for n in $(gh api "repos/$REPO/issues?state=open&labels=ready-for-agent&per_page=100" \
    --jq '.[] | select(.pull_request | not) | select([.labels[].name] | index("ready") | not) | .number' 2> /dev/null || true); do
  echo "Issue #$n has ready-for-agent but not ready"
  [ -z "$(marker_get "$n" labelmap)" ] || continue
  marker_set "$n" labelmap 1
  notify "#$n has the label ready-for-agent but not ready: the queue never builds it. The planning skills did not use the label map PEPPEC needs: run peppec doctor (and peppec skills) on your computer, then label it ready. https://github.com/$REPO/issues/$n"
done

if [ -z "$active" ]; then
  ok=false
  # "always on" on the control panel: new issues start at any hour
  if in_window || has "$ctrl" "always on" || [ "$FORCE" = true ]; then ok=true; fi
  if [ "$mode" = manual ] && [ "$EVENT_NAME" = pull_request ] && [ "$EVENT_MERGED" = true ] \
     && is_agent_branch "$EVENT_HEAD_REF"; then ok=true; fi
  [ "$ok" = true ] || { echo "Outside the work window"; exit 0; }
  # The oldest ready issue that no open issue blocks
  open_ready=$(gh api --paginate "repos/$REPO/issues?state=open&labels=ready&per_page=100" \
    | jq -s '[add // [] | .[] | select(.pull_request | not)
              | select([.labels[].name] | index("needs human") | not)] | sort_by(.created_at)')
  # Not a work unit: a specification (it has sub-issues) or a wayfinder map or ticket, labelled
  # ready by mistake. Built in one run it would skip the split into work units; told once per issue
  for n in $(jq -r '.[] | select('"$NOT_WORK_UNIT"') | .number' <<< "$open_ready"); do
    echo "Issue #$n is not a work unit: skipped"
    [ -z "$(marker_get "$n" notworkunit)" ] || continue
    marker_set "$n" notworkunit 1
    notify "#$n has the ready label but is not a work unit (it has sub-issues, or a wayfinder label): the queue skips it. Remove ready from it, and put it on its sub-issues instead. https://github.com/$REPO/issues/$n"
  done
  # Written by someone else: its body would reach the agent's prompt, and its author can still
  # edit it after you label it. The label goes, so the bot and the dashboard do not count it
  [ -n "${OWNER_LOGIN:-}" ] || { echo "OWNER_LOGIN is not set: no issue starts (peppec doctor)"; exit 0; }
  for n in $(jq -r --arg o "$OWNER_LOGIN" --arg a "${APP_LOGIN:-}" \
      '.[] | select(.user.login != $o and .user.login != $a) | .number' <<< "$open_ready"); do
    echo "Issue #$n was not written by $OWNER_LOGIN or the app: ready removed"
    rm_label "$n" ready
    notify "#$n has the ready label but was not written by you: the queue never builds it, and the label is removed. Its author could change its text after you label it. Copy what you want built into an issue of your own. https://github.com/$REPO/issues/$n"
  done
  open_ready=$(jq --arg o "$OWNER_LOGIN" --arg a "${APP_LOGIN:-}" \
    '[.[] | select(.user.login == $o or .user.login == $a)]' <<< "$open_ready")
  ready=$(jq -r '.[] | select('"$NOT_WORK_UNIT"' | not) | .number' <<< "$open_ready")
  first=""
  for n in $ready; do
    if [ "$paused" = true ] && [ "$(kind_of "$n")" = work ]; then
      echo "Issue #$n waits: the queue is paused, no new issue starts"; continue
    fi
    blockers=$(open_blockers "$n" "$closed")
    if [ -n "$blockers" ]; then echo "Issue #$n waits for $blockers"; continue; fi
    [ -n "$first" ] || first=$n
    # With feature branches, one feature is built at a time: the work units of a feature already
    # started and not yet finished come first. Finished features wait for you meanwhile
    [ -n "$(template feature)" ] || break
    # A sync work unit first of all: a finished feature waits for it
    if [ "$(kind_of "$n")" = sync ] || under_construction "$n"; then issue=$n; break; fi
  done
  issue=${issue:-$first}
  [ -n "$issue" ] || { echo "No ready issues to start"; exit 0; }
  if ! plan_branch "$issue"; then action=stop; reason=$plan_error; exit 0; fi
  echo "Issue #$issue on $branch, based on $base"
  size=$(size_of "$(labels_of "$issue")")
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

isize=$(size_of "$il")
# Only the agent's own branch: the merges of a feature branch into the base branch and of the base
# branch into main are the owner's end-to-end sign-off, never automatic
# An issue already in progress keeps the branch it started on (agent/issue-N if it started before
# branch names were remembered)
bb=$(branch_of "$issue"); branch=${bb%%:*} base=${bb#*:}
pr=$(pr_from "$branch")
left=$(budget "$issue")
if [ "$left" -le 0 ]; then action=stop; reason="time budget of $MAX_ISSUE_MINUTES minutes used up"; exit 0; fi
minutes=$(( left + 10 ))
if [ -z "$pr" ]; then action=start; size=$isize; round=1; exit 0; fi

sha=$(gh pr view "$pr" -R "$REPO" --json headRefOid --jq .headRefOid)
waited=$(age_minutes "$(gh api "repos/$REPO/commits/$sha" --jq .commit.committer.date)")
pl=$(labels_of "$pr")
round=$( { grep -oP '^review \K[0-9]+' <<< "$pl" || true; } | sort -n | tail -1); round=${round:-1}
tries=$( { grep -oP '^ci \K[0-9]+' <<< "$pl" || true; } | sort -n | tail -1); tries=${tries:-0}
# From this round on the largest model takes over, whatever the size of the issue
size=$isize; [ "$round" -ge "$LARGE_FROM_ROUND" ] && size=l

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

reviews=$(gh api "repos/$REPO/pulls/$pr/reviews?per_page=100" --jq '[.[] | select(.user.login == "coderabbitai[bot]")]')
state=$(jq -r --arg sha "$sha" '[.[] | select(.commit_id == $sha and (.state == "APPROVED" or .state == "CHANGES_REQUESTED"))] | last | .state // "none"' <<< "$reviews")

# CodeRabbit gives no new verdict on a commit with nothing it reviews. Its reply to our request
# then says "Review finished" (nothing left to review, for example a deleted file) or "Path
# filters excluded N files from this review" (only files it never reviews, for example a
# lockfile). In that case the previous approval stands, provided that all of these hold:
# - CodeRabbit submitted no review at all on this commit, and its latest verdict is an approval;
# - it answered the request made for this commit with one of those two sentences.
# If the wording of that reply ever changes, this simply stops matching and the queue waits.
# The comments of the pull request, read only when there is no verdict on this commit
comments='[]'
if [ "$state" = none ]; then
  comments=$(gh api --paginate "repos/$REPO/issues/$pr/comments?per_page=100" \
    --jq '.[] | {login: .user.login, body, created_at}' | jq -s .)
fi
carried_approval() {
  jq -e --arg sha "$sha" '
    all(.[]; .commit_id != $sha)
    and (([.[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED")] | last | .state) == "APPROVED")' \
    <<< "$reviews" > /dev/null || return 1
  jq -e --arg sha "$sha" --arg o "${OWNER_LOGIN:-}" '
    (map(select(.login == $o and (.body | contains("<!-- peppec:rerequest=" + $sha + " -->")))) | last | .created_at) as $asked
    | $asked != null
      and any(.[]; .login == "coderabbitai[bot]" and .created_at >= $asked
                   and (.body | test("Review finished|Path filters excluded [0-9]+ files? from this review"; "i")))' \
    <<< "$comments" > /dev/null
}
if [ "$state" = none ] && carried_approval; then
  echo "CodeRabbit found nothing to review in $sha: the previous approval stands"
  state=APPROVED
fi

case "$state" in
  none)
    # Reviews start only on request: ask as soon as the checks are green. CodeRabbit answers
    # every request with a comment within a minute or two: a request with no answer at all
    # was lost (CodeRabbit not installed yet, or down), so it is repeated, up to
    # REVIEW_REQUESTS times per commit.
    asks=$(jq -r --arg sha "$sha" --arg o "${OWNER_LOGIN:-}" '
      map(select(.login == $o and (.body | contains("<!-- peppec:rerequest=" + $sha + " -->")))) as $asks
      | ($asks | last | .created_at) as $asked
      | "\($asks | length) \($asked // "-") \($asked != null and any(.[]; .login == "coderabbitai[bot]" and .created_at >= $asked))"' \
      <<< "$comments")
    read -r asked_count asked_at answered <<< "$asks"
    if [ "$asked_count" -eq 0 ]; then
      action=rerequest
    elif [ "$answered" = false ] && [ "$asked_count" -lt "$REVIEW_REQUESTS" ] \
         && [ "$(age_minutes "$asked_at")" -ge "$REVIEW_RETRY_MINUTES" ]; then
      echo "No answer from CodeRabbit to request $asked_count: asking again"
      action=rerequest
    elif [ "$waited" -ge $(( 2 * STALL_MINUTES )) ]; then
      action=stop; reason="no CodeRabbit review after $waited minutes"
      if [ "$answered" = false ]; then
        reason="no answer from CodeRabbit after $waited minutes: check that it is installed on this repository"
      fi
    else
      echo "Waiting for CodeRabbit ($waited min)"
    fi
    exit 0;;
  APPROVED)
    if [ "$mode" = automatic ]; then action=merge
    elif ! has "$pl" "ready to merge"; then action=notify_ready; fi
    exit 0;;
  CHANGES_REQUESTED)
    # The agent may have answered this review instead of changing the code (after.sh): CodeRabbit
    # replies within a minute or two, and approves when convinced. Without an approval by
    # REVIEW_RETRY_MINUTES the next round starts, and the agent reads CodeRabbit's replies
    rid=$(jq -r --arg sha "$sha" '[.[] | select(.commit_id == $sha and .state == "CHANGES_REQUESTED")] | last | .id' <<< "$reviews")
    replied_at=$( {
      gh api --paginate "repos/$REPO/pulls/$pr/comments?per_page=100" --jq '.[] | {login: .user.login, body, created_at}'
      gh api --paginate "repos/$REPO/issues/$pr/comments?per_page=100" --jq '.[] | {login: .user.login, body, created_at}'
    } | jq -rs --arg m "<!-- peppec:reply=$rid -->" --arg o "${OWNER_LOGIN:-}" 'map(select(.login == $o and (.body | contains($m))) | .created_at) | sort | last // empty')
    if [ -n "$replied_at" ] && [ "$(age_minutes "$replied_at")" -lt "$REVIEW_RETRY_MINUTES" ]; then
      echo "Waiting for CodeRabbit to weigh the agent's reply ($(age_minutes "$replied_at") min)"; exit 0
    fi
    if [ "$round" -ge "$MAX_REVIEW_ROUNDS" ]; then
      action=stop; reason="review not passed after $round rounds"; exit 0
    fi
    round=$((round + 1)); size=$isize; [ "$round" -ge "$LARGE_FROM_ROUND" ] && size=l
    action=fix_review; exit 0;;
esac
