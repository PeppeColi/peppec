# scripts/lib.sh
notify() {
  # The repository comes first: one bot and one chat can follow several, and the bot
  # reads it back when you reply to a message
  local text="[$REPO] $1"
  # Telegram shows plain text: a backtick from Markdown (titles, questions) is only noise
  text="${text//\`/}"
  text="${text:0:4000}"
  # Also in the job log, so the reason of a stop can be read without Telegram
  echo "notify: $text"
  # $2, optional: the buttons under the message, as the reply_markup of the Telegram API
  # Telegram's refusal (wrong chat, bot blocked, bad markup) is only in its answer: log it
  local answer
  answer=$(curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" --data-urlencode text="$text" \
    ${2:+--data-urlencode "reply_markup=$2"}) || true
  jq -e .ok <<< "$answer" > /dev/null 2>&1 \
    || echo "notify: Telegram did not deliver it: $(jq -r '.description // empty' <<< "$answer" 2> /dev/null || echo "$answer")"
}
# A notification about a blocked issue, with the buttons the bot acts on: "action|value|",
# the repository being the one the message starts with (see press in bot/bot.py)
notify_blocked() {
  notify "$1" "{\"inline_keyboard\":[[{\"text\":\"Unblock #$ISSUE\",\"callback_data\":\"unblock|$ISSUE|\"},{\"text\":\"Hint #$ISSUE\",\"callback_data\":\"hint|$ISSUE|\"}]]}"
}
# Separates the agent's question from the answer it recommends, in the comment that asks it.
# Same text as RECOMMENDED in bot/bot.py
RECOMMENDED_MARK='<!-- peppec:recommended -->'
add_label() { gh api -X POST "repos/$REPO/issues/$1/labels" -f "labels[]=$2" > /dev/null; }
rm_label() { gh api -X DELETE "repos/$REPO/issues/$1/labels/$(jq -rn --arg l "$2" '$l|@uri')" > /dev/null 2>&1 || true; }
labels_of() { gh api "repos/$REPO/issues/$1/labels" --jq '.[].name'; }
# GitHub closes an issue by itself only when its pull request is merged into the default
# branch: with another base branch, or if that did not happen, the workflow closes it
close_merged() {
  gh api -X PATCH "repos/$REPO/issues/$1" -f state=closed -f state_reason=completed > /dev/null
  rm_label "$1" "in progress"
}
# Branch names. PEPPEC_BRANCHES (repository variable) holds one "kind=template" per line:
#   feature  the integration branch of a specification, based on BASE_BRANCH
#   work     a work unit of a specification, based on its feature branch
#   hotfix   a problem found on a feature (Report a problem), based on its feature branch
#   sync     BASE_BRANCH brought into a feature branch, based on that feature branch
#   single   an issue without a specification, based on BASE_BRANCH
# {spec} is the number of the specification and the slug of its title ("78-stats"), {n} the
# number of the issue, {slug} the slug of its title. A kind left out takes its default below.
# Without the variable every issue gets agent/issue-{n} on BASE_BRANCH, and there are no
# feature branches. A variable and not .github/peppec.yml: a feature branch carries the
# configuration of the day it was created, and would name the branches the old way
BRANCH_DEFAULTS='feature=feature/{spec}/dev
work=feature/{spec}/parte-{n}
hotfix=feature/{spec}/hotfix-{n}
sync=feature/{spec}/sync-{n}
single=fix/{n}-{slug}'
template() {
  if [ -z "${PEPPEC_BRANCHES:-}" ]; then
    [ "$1" = feature ] || echo 'agent/issue-{n}'
    return 0
  fi
  local t
  t=$( { grep -m1 "^[[:space:]]*$1[[:space:]]*=" <<< "$PEPPEC_BRANCHES" || true; } | cut -d= -f2- | tr -d '[:space:]')
  [ -n "$t" ] || t=$(grep -m1 "^$1=" <<< "$BRANCH_DEFAULTS" | cut -d= -f2-)
  echo "$t"
}
# A template the engine can use: feature names {spec} and not {n}; every other kind names {n},
# which is how a branch is traced back to its issue. A template without it would claim
# branches that are not the engine's, and the engine deletes its merged branches
template_ok() {
  case "$1" in
    feature) [[ "$2" == *"{spec}"* && "$2" != *"{n}"* ]];;
    *) [[ "$2" == *"{n}"* ]];;
  esac
}
# Lowercase ASCII letters and digits joined by dashes, at most 30 characters
slug() {
  local a
  a=$(iconv -f utf-8 -t ascii//TRANSLIT <<< "$1" 2> /dev/null) || a=$1
  printf '%s\n' "$a" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//' | cut -c1-30 | sed -E 's/-+$//'
}
# $1 template, $2 {spec}, $3 {n}, $4 {slug}
fill() {
  local t=$1
  t=${t//\{spec\}/$2}; t=${t//\{n\}/$3}; t=${t//\{slug\}/$4}
  echo "$t"
}
# A regular expression matching the names a template gives; only {n} is captured
template_regex() {
  local t=$1
  t=${t//\{spec\}/@S@}; t=${t//\{n\}/@N@}; t=${t//\{slug\}/@G@}
  t=$(sed -E 's/[.^$*+?()|\\{}]/\\&/g; s/\[/\\[/g; s/\]/\\]/g' <<< "$t")
  t=${t//@S@/[0-9][a-z0-9-]*}; t=${t//@N@/([0-9]+)}; t=${t//@G@/[a-z0-9-]*}
  echo "^$t\$"
}
# The engine's own working branches, and nothing else: the old agent/issue-N names, and the
# names of the templates of PEPPEC_BRANCHES. A feature branch is not one: the engine never
# merges it, and removes it only once you have merged it (delete_feature_branch)
is_agent_branch() {
  [[ "$1" =~ ^agent/issue-[0-9]+$ ]] && return 0
  [ -n "${PEPPEC_BRANCHES:-}" ] || return 1
  is_feature_branch "$1" && return 1
  local k t re
  for k in work hotfix sync single; do
    t=$(template "$k"); template_ok "$k" "$t" || continue
    re=$(template_regex "$t")
    [[ "$1" =~ $re ]] && return 0
  done
  return 1
}
# The issue a working branch belongs to
issue_of_branch() {
  [[ "$1" =~ ^agent/issue-([0-9]+)$ ]] && { echo "${BASH_REMATCH[1]}"; return; }
  is_agent_branch "$1" || return 0
  local k t re
  for k in work hotfix sync single; do
    t=$(template "$k"); template_ok "$k" "$t" || continue
    re=$(template_regex "$t")
    [[ "$1" =~ $re ]] && { echo "${BASH_REMATCH[1]}"; return; }
  done
}
is_feature_branch() {
  local t re; t=$(template feature)
  template_ok feature "$t" || return 1
  re=$(template_regex "$t")
  [[ "$1" =~ $re ]]
}
# The branch of an issue and the branch it is based on, as "branch:base" (a colon never appears
# in a branch name). Worked out once, when the issue starts (plan_branch), and remembered on the
# issue: renaming the issue or its specification, or changing PEPPEC_BRANCHES, never moves work
# already under way. Issues started before the marker existed keep agent/issue-N
branch_of() {
  local s; s=$(marker_get "$1" branch)
  echo "${s:-agent/issue-$1:${BASE_BRANCH:-main}}"
}
# The specification of an issue: its parent, when you wrote it in this repository and it is not
# a wayfinder map. The parent as JSON, or nothing
spec_of() {
  local p
  p=$(gh api "repos/$REPO/issues/$1/parent" 2> /dev/null) || return 0
  jq -e --arg r "https://api.github.com/repos/$REPO" --arg o "${OWNER_LOGIN:-}" \
    '.repository_url == $r and .user.login == $o and (any(.labels[].name; . == "wayfinder:map") | not)' \
    <<< "$p" > /dev/null || return 0
  echo "$p"
}
# The kind of a work unit of a specification, from the hidden marker in its body: "hotfix" for a
# problem reported on the feature, "sync" for a merge of the base branch; "work" otherwise
kind_of() {
  local k
  k=$(gh api "repos/$REPO/issues/$1" --jq '.body // ""' | sed -nE 's/.*<!-- peppec:kind=(hotfix|sync) -->.*/\1/p' | head -1)
  echo "${k:-work}"
}
valid_branch() { [ -n "$1" ] && git check-ref-format --branch "$1" > /dev/null 2>&1; }
# Works out the branch of issue $1 the first time it starts, and remembers it (see branch_of).
# Sets the variables branch and base; creates the feature branch from BASE_BRANCH when it is
# missing. Returns 1, with the reason in plan_error, when PEPPEC_BRANCHES gives a bad name
plan_branch() {
  local n=$1 saved spec sn sname ft kind fb title
  saved=$(marker_get "$n" branch)
  if [ -n "$saved" ]; then branch=${saved%%:*} base=${saved#*:}; ensure_feature_branch "$base"; return; fi
  base=${BASE_BRANCH:-main} kind=single sname=""
  spec=$(spec_of "$n")
  if [ -n "$spec" ]; then
    kind=work
    sn=$(jq -r .number <<< "$spec")
    sname=$sn; title=$(slug "$(jq -r .title <<< "$spec")"); [ -z "$title" ] || sname="$sn-$title"
    ft=$(template feature)
    if [ -n "$ft" ] && ! template_ok feature "$ft"; then
      plan_error="the feature template of PEPPEC_BRANCHES must contain {spec} and not {n}: '$ft'"; return 1
    fi
    if [ -n "$ft" ]; then
      kind=$(kind_of "$n")
      fb=$(marker_get "$sn" feature)
      if [ -z "$fb" ]; then
        fb=$(fill "$ft" "$sname" "$sn" "")
        if ! valid_branch "$fb" || ! is_feature_branch "$fb" || [ "$fb" = "$base" ]; then
          plan_error="PEPPEC_BRANCHES gives the feature branch of #$sn a bad name: '$fb'"; return 1
        fi
        marker_set "$sn" feature "$fb"
      fi
      base=$fb
    fi
  fi
  if ! template_ok "$kind" "$(template "$kind")"; then
    plan_error="the $kind template of PEPPEC_BRANCHES must contain {n}: '$(template "$kind")'"; return 1
  fi
  branch=$(fill "$(template "$kind")" "$sname" "$n" "$(slug "$(gh api "repos/$REPO/issues/$n" --jq .title)")")
  if ! valid_branch "$branch" || ! is_agent_branch "$branch" || [ "$branch" = "$base" ]; then
    plan_error="PEPPEC_BRANCHES gives #$n a bad branch name: '$branch'"; return 1
  fi
  ensure_feature_branch "$base"
  marker_set "$n" branch "$branch:$base"
}
# Creates a feature branch from the tip of BASE_BRANCH when it does not exist
ensure_feature_branch() {
  [ "$1" != "${BASE_BRANCH:-main}" ] || return 0
  gh api "repos/$REPO/branches/$1" --jq .name > /dev/null 2>&1 && return 0
  local sha
  sha=$(gh api "repos/$REPO/branches/${BASE_BRANCH:-main}" --jq .commit.sha)
  gh api -X POST "repos/$REPO/git/refs" -f ref="refs/heads/$1" -f sha="$sha" > /dev/null
  echo "Created the feature branch $1 from ${BASE_BRANCH:-main}"
}
# Removes a working branch whose pull request is merged. GitHub is told not to delete merged
# branches (peppec init turns that off): it would also delete the base branch each time it is
# brought to main. So the engine removes its own, never a branch with another name, and never
# one that still has an open pull request
delete_agent_branch() {
  is_agent_branch "$1" || return 0
  [ -z "$(gh pr list -R "$REPO" --head "$1" --state open --json number --jq '.[0].number // empty')" ] || return 0
  if gh api -X DELETE "repos/$REPO/git/refs/heads/$1" > /dev/null 2>&1; then
    echo "Deleted the merged branch $1"
  else
    echo "Branch $1 not deleted: it is already gone"
  fi
}
# A feature branch you have merged into the base branch: the specification is done. Closes the
# specification (GitHub closes issues only on merges into the default branch) and removes the
# branch, unless a pull request still starts from it or goes into it
finish_feature() {
  local branch=$1 spec
  is_feature_branch "$branch" || return 0
  spec=$(gh pr list -R "$REPO" --head "$branch" --state merged --json body --jq '.[0].body // ""' \
    | sed -nE 's/.*<!-- peppec:feature=([0-9]+) -->.*/\1/p' | head -1)
  if [ -n "$spec" ] && [ "$(gh api "repos/$REPO/issues/$spec" --jq .state)" = open ]; then
    gh api -X PATCH "repos/$REPO/issues/$spec" -f state=closed -f state_reason=completed > /dev/null
    echo "Closed specification #$spec: its feature branch is merged"
  fi
  [ -z "$(gh pr list -R "$REPO" --head "$branch" --state open --json number --jq '.[0].number // empty')" ] || return 0
  [ -z "$(gh pr list -R "$REPO" --base "$branch" --state open --json number --jq '.[0].number // empty')" ] || return 0
  if gh api -X DELETE "repos/$REPO/git/refs/heads/$branch" > /dev/null 2>&1; then
    echo "Deleted the merged feature branch $branch"
  fi
}
# True only when GitHub says the base branch is not there. Any other failure (network, rate
# limit) ends the script: a queue is never stopped on a guess
base_branch_missing() {
  local out
  out=$(gh api "repos/$REPO/branches/$BASE_BRANCH" --jq .name 2>&1) && return 1
  grep -q "HTTP 404" <<< "$out" || { echo "$out" >&2; exit 1; }
}
has() { grep -qxF -- "$2" <<< "$1"; }
age_minutes() { echo $(( ($(date +%s) - $(date -d "$1" +%s)) / 60 )); }
# Hidden marker comments on an issue or PR: <!-- peppec:KEY=VALUE -->
marker_get() {
  gh api --paginate "repos/$REPO/issues/$1/comments?per_page=100" \
    --jq ".[] | select(.body | contains(\"<!-- peppec:$2=\")) | .body" \
    | { grep -oP "peppec:$2=\K[^ ]+" || true; } | tail -1
}
marker_set() {
  local id
  id=$(gh api --paginate "repos/$REPO/issues/$1/comments?per_page=100" \
    --jq ".[] | select(.body | contains(\"<!-- peppec:$2=\")) | .id" | tail -1)
  if [ -n "$id" ]; then
    gh api -X PATCH "repos/$REPO/issues/comments/$id" -f body="<!-- peppec:$2=$3 -->" > /dev/null
  else
    gh api -X POST "repos/$REPO/issues/$1/comments" -f body="<!-- peppec:$2=$3 -->" > /dev/null
  fi
}
# jq test on an issue from the REST API: true when it is not a work unit the agent can build, that
# is a specification (it has sub-issues) or a wayfinder map or ticket. Same rule in bot/bot.py
NOT_WORK_UNIT='((.sub_issues_summary.total // 0) > 0 or any(.labels[].name; startswith("wayfinder:")))'

# Tells you when the last sub-issue of a parent issue is closed: the whole feature is merged
# and can be tried. $1 is the sub-issue just closed, counted as closed even if the API still
# lists it as open. The number of sub-issues is remembered on the parent, so the message is
# sent once, and again only if sub-issues are added later and closed in turn.
notify_feature_done() {
  local parent pn subs total open
  parent=$(gh api "repos/$REPO/issues/$1/parent" 2> /dev/null) || return 0
  [ "$(jq -r .repository_url <<< "$parent")" = "https://api.github.com/repos/$REPO" ] || return 0
  pn=$(jq -r .number <<< "$parent")
  # A cleared wayfinder map is not a feature: its destination is a specification still to write
  jq -e 'any(.labels[].name; . == "wayfinder:map")' <<< "$parent" > /dev/null && return 0
  subs=$(gh api --paginate "repos/$REPO/issues/$pn/sub_issues?per_page=100" | jq -s 'add // []')
  total=$(jq length <<< "$subs")
  open=$(jq --argjson n "$1" '[.[] | select(.state == "open" and .number != $n)] | length' <<< "$subs")
  [ "$open" -eq 0 ] || return 0
  [ "$(marker_get "$pn" done)" != "$total" ] || return 0
  local where="${BASE_BRANCH:-main}" link="https://github.com/$REPO/issues/$pn" fb pr synced
  # With a feature branch, the pull request that brings it into the base branch: opened here,
  # merged only by you, after trying the feature. Its merge closes the specification (finish_feature)
  fb=$(marker_get "$pn" feature)
  if [ -n "$fb" ]; then
    where=$fb
    pr=$(feature_pr "$pn" "$fb" "$(jq -r .title <<< "$parent")")
    [ -z "$pr" ] || link=$pr
    # The base branch went on while the feature was built: it is brought in first, so what you try
    # is what the merge will give. A conflict becomes a work unit, and this message waits for it
    synced=$(sync_feature "$pn" "$fb") || return 0
    [ "$synced" != conflict ] || return 0
    # With end-to-end tests the message waits for their result on the pull request (judge_features)
    if [ -n "${PEPPEC_E2E_FEATURE:-}" ]; then
      echo "Feature of #$pn finished: waiting for its end-to-end tests on $link"
      return 0
    fi
  fi
  ready_to_try "$pn" "$total" "$(jq -r .title <<< "$parent")" "$where" "$link"
}

# The "ready to be tried" message, once per number of sub-issues ($2) of specification $1
ready_to_try() {
  marker_set "$1" done "$2"
  # The button asks the bot for one sentence and makes it a new sub-issue (report in bot/bot.py)
  notify "All $2 sub-issues of #$1 \"$3\" are merged into $4: the feature is ready to be tried. $5" \
    "{\"inline_keyboard\":[[{\"text\":\"Report a problem\",\"callback_data\":\"report|$1|\"}]]}"
}

# The end-to-end tests of the finished features. CI runs them on the pull request of each feature
# branch into the base branch (job e2e_feature of the reusable CI workflow, PEPPEC_E2E_FEATURE);
# here their result on the latest commit is read, once per commit (marker e2e):
# - passed: "ready to be tried", if not sent yet for these sub-issues;
# - failed: a hotfix work unit of size L with the end of the log, as a sub-issue, so the feature
#   is finished again only once it is merged. After E2E_HOTFIXES of them the tests still fail:
#   you are told, and nothing more is opened until they pass;
# - no result after STALL_MINUTES: you are told once.
# The check is named after the caller's job, like CI_CHECK ("ci / ci" -> "ci / e2e_feature")
E2E_CHECK="${CI_CHECK:-ci / ci}"; E2E_CHECK="${E2E_CHECK% / *} / e2e_feature"; E2E_HOTFIXES=2
judge_features() {
  [ -n "${PEPPEC_E2E_FEATURE:-}" ] && [ -n "$(template feature)" ] || return 0
  local prs head sha pn spec total check fails log url
  prs=$(gh pr list -R "$REPO" --base "${BASE_BRANCH:-main}" --state open --json url,headRefName,headRefOid,body \
    --jq '.[] | select(.body | contains("<!-- peppec:feature=")) | "\(.headRefName) \(.headRefOid) \(.url) \(.body | capture("<!-- peppec:feature=(?<n>[0-9]+) -->").n)"')
  while read -r head sha url pn; do
    [ -n "$pn" ] && is_feature_branch "$head" || continue
    spec=$(gh api "repos/$REPO/issues/$pn")
    total=$(jq '.sub_issues_summary.total // 0' <<< "$spec")
    [ "$(jq '.sub_issues_summary.completed // 0' <<< "$spec")" -eq "$total" ] || continue
    [ "$(marker_get "$pn" e2e)" != "$sha" ] || continue
    check=$(gh api -X GET "repos/$REPO/commits/$sha/check-runs" -f check_name="$E2E_CHECK" \
      --jq '.check_runs[0] | if . == null then "pending" elif .status != "completed" then "pending" else "\(.conclusion) \(.id)" end')
    case "$check" in
      pending)
        if [ "$(age_minutes "$(gh api "repos/$REPO/commits/$sha" --jq .commit.committer.date)")" -ge "${STALL_MINUTES:-30}" ] \
           && [ "$(marker_get "$pn" e2ewait)" != "$sha" ]; then
          marker_set "$pn" e2ewait "$sha"
          notify "No result of the end-to-end tests of #$pn after ${STALL_MINUTES:-30} minutes: check the $E2E_CHECK job on $url"
        else
          echo "Waiting for the end-to-end tests of #$pn"
        fi;;
      success*|skipped*|neutral*)
        marker_set "$pn" e2e "$sha"; marker_set "$pn" e2efail 0
        echo "End-to-end tests of #$pn passed on $sha"
        if [ "$(marker_get "$pn" done)" != "$total" ]; then
          ready_to_try "$pn" "$total" "$(jq -r .title <<< "$spec")" "$head" "$url"
        fi;;
      *)
        marker_set "$pn" e2e "$sha"
        fails=$(( $(marker_get "$pn" e2efail || true) + 0 ))
        if [ "$fails" -ge "$E2E_HOTFIXES" ]; then
          notify "The end-to-end tests of #$pn still fail after $fails hotfixes: fix them by hand, or press Report a problem. $url" \
            "{\"inline_keyboard\":[[{\"text\":\"Report a problem\",\"callback_data\":\"report|$pn|\"}]]}"
          continue
        fi
        marker_set "$pn" e2efail $(( fails + 1 ))
        log=$(gh api "repos/$REPO/actions/jobs/${check#* }/logs" 2> /dev/null \
          | sed -E 's/^[0-9-]+T[0-9:.]+Z //' | tail -n 80 || true)
        e2e_hotfix "$pn" "$head" "$sha" "$log";;
    esac
  done <<< "$prs"
}

# A work unit of size L that fixes the failing end-to-end tests of a feature: a hotfix sub-issue
# of its specification, with the end of the log
e2e_hotfix() {
  local pn=$1 fb=$2 sha=$3 log=$4 issue n
  issue=$(gh api -X POST "repos/$REPO/issues" -f title="Fix the failing end-to-end tests of #$pn" \
    -f body="The end-to-end tests of the feature of #$pn failed on \`$fb\` (commit $sha). Find the cause and fix it: the feature as its specification (the parent issue) describes it, or the tests if they are the ones that are wrong. Run them with:

\`\`\`
${PEPPEC_E2E_FEATURE//\{spec\}/$pn}
\`\`\`

End of the log:

\`\`\`
${log:-(not available)}
\`\`\`

<!-- peppec:kind=hotfix -->")
  gh api -X POST "repos/$REPO/issues/$pn/sub_issues" -F sub_issue_id="$(jq -r .id <<< "$issue")" > /dev/null
  n=$(jq -r .number <<< "$issue")
  add_label "$n" ready; add_label "$n" "size: L"
  notify "The end-to-end tests of #$pn failed: #$n will fix them. https://github.com/$REPO/issues/$n"
}

# The open pull request of a feature branch into the base branch, opened when missing. Its URL
feature_pr() {
  local pn=$1 fb=$2 title=$3 pr
  pr=$(gh pr list -R "$REPO" --head "$fb" --base "${BASE_BRANCH:-main}" --state open --json url --jq '.[0].url // empty')
  if [ -z "$pr" ]; then
    pr=$(gh pr create -R "$REPO" --head "$fb" --base "${BASE_BRANCH:-main}" --title "$title (#$pn)" \
      --body "Feature of specification #$pn. Try it on \`$fb\`, then merge this pull request: the workflow closes the specification and removes the branch. Never merged automatically.

<!-- peppec:feature=$pn -->") || pr=""
  fi
  echo "$pr"
}

# Brings the base branch into feature branch $2 of specification $1, with a merge commit made by
# GitHub. Prints "merged", "current" (nothing to bring in) or "conflict"; on a conflict a sync
# work unit is opened, once (sync_issue). Any other failure is reported and returns 1
sync_feature() {
  local pn=$1 fb=$2 out
  if out=$(gh api -X POST "repos/$REPO/merges" -f base="$fb" -f head="${BASE_BRANCH:-main}" \
             -f commit_message="Merge ${BASE_BRANCH:-main} into $fb" --jq '.sha // empty' 2>&1); then
    if [ -n "$out" ]; then echo "Merged ${BASE_BRANCH:-main} into $fb" >&2; echo merged; else echo current; fi
    return 0
  fi
  if grep -q "HTTP 409" <<< "$out"; then
    echo "${BASE_BRANCH:-main} and $fb conflict" >&2
    sync_issue "$pn" "$fb" >&2
    echo conflict
    return 0
  fi
  echo "Could not bring ${BASE_BRANCH:-main} into $fb: $out" >&2
  notify "Could not bring ${BASE_BRANCH:-main} into $fb (#$pn): $out ${RUN_URL:-}" >&2
  return 1
}

# A work unit that resolves the conflicts between the base branch and a feature branch: a
# sub-issue of the specification, so the feature is not finished until it is merged. The workflow
# makes the merge and leaves the conflict markers (task.sh); the agent resolves them. Opened once
sync_issue() {
  local pn=$1 fb=$2 subs n log issue
  subs=$(gh api --paginate "repos/$REPO/issues/$pn/sub_issues?per_page=100" | jq -s 'add // []')
  n=$(jq -r '[.[] | select(.state == "open" and ((.body // "") | contains("<!-- peppec:kind=sync -->")))] | .[0].number // empty' <<< "$subs")
  if [ -n "$n" ]; then echo "Sync work unit #$n already open" >&2; return 0; fi
  # What the base branch has and the feature does not: usually the titles of merged pull requests
  log=$(gh api "repos/$REPO/compare/$fb...${BASE_BRANCH:-main}" \
    --jq '.commits[-30:][] | "- " + (.commit.message | split("\n")[0])' 2> /dev/null || true)
  issue=$(gh api -X POST "repos/$REPO/issues" -f title="Resolve the conflicts between ${BASE_BRANCH:-main} and the feature of #$pn" \
    -f body="\`${BASE_BRANCH:-main}\` changed while the feature of #$pn was built on \`$fb\`, and the two conflict. The workflow merges \`${BASE_BRANCH:-main}\` into the feature and leaves the conflict markers in the files listed in the task.

Resolve every conflict so that both sides keep working: the feature, as its specification (the parent issue) describes it, and the changes below, which are already on \`${BASE_BRANCH:-main}\`. Do not drop either side to make the conflict go away. If the two cannot both stand, ask a question.

Changes on \`${BASE_BRANCH:-main}\` that the feature does not have yet:

${log:-- (not available)}

<!-- peppec:kind=sync -->")
  gh api -X POST "repos/$REPO/issues/$pn/sub_issues" -F sub_issue_id="$(jq -r .id <<< "$issue")" > /dev/null
  n=$(jq -r .number <<< "$issue")
  add_label "$n" ready
  notify "${BASE_BRANCH:-main} and the feature of #$pn conflict: #$n will resolve it. https://github.com/$REPO/issues/$n"
}

# The base branch went on (another feature merged, a single issue) while a finished feature waits
# for you: it is brought into the feature again, so what you try stays what the merge will give.
# Only features whose pull request is open and that have no open sub-issue
resync_features() {
  local prs pn head ahead synced
  [ -n "$(template feature)" ] || return 0
  prs=$(gh pr list -R "$REPO" --base "${BASE_BRANCH:-main}" --state open --json headRefName,body \
    --jq '.[] | select(.body | contains("<!-- peppec:feature=")) | "\(.headRefName) \(.body | capture("<!-- peppec:feature=(?<n>[0-9]+) -->").n)"')
  while read -r head pn; do
    [ -n "$pn" ] && is_feature_branch "$head" || continue
    [ "$(gh api "repos/$REPO/issues/$pn" --jq '(.sub_issues_summary.total // 0) - (.sub_issues_summary.completed // 0)')" -eq 0 ] || continue
    ahead=$(gh api "repos/$REPO/compare/$head...${BASE_BRANCH:-main}" --jq .ahead_by 2> /dev/null || echo 0)
    [ "${ahead:-0}" -gt 0 ] || continue
    synced=$(sync_feature "$pn" "$head") || continue
    if [ "$synced" = merged ]; then
      notify "${BASE_BRANCH:-main} changed, and it is now merged into the feature of #$pn: try its latest version on $head. https://github.com/$REPO/issues/$pn"
    fi
  done <<< "$prs"
}

# The text under the "Out of scope" heading of a Markdown text on standard input, up to the
# next heading of the same or a higher level. Empty when there is no such heading
out_of_scope() {
  tr -d '\r' | awk '
    /^#+[ \t]/ && on { match($0, /^#+/); if (RLENGTH <= lvl) on = 0 }
    on { print }
    !on && tolower($0) ~ /^#+[ \t]+out of scope[ \t]*$/ { match($0, /^#+/); lvl = RLENGTH; on = 1 }
  ' | sed -e '/./,$!d' | awk '{ l[NR] = $0 } /./ { last = NR } END { for (i = 1; i <= last; i++) print l[i] }'
}
