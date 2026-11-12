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
add_label() { gh api -X POST "repos/$REPO/issues/$1/labels" -f "labels[]=$2" > /dev/null; }
rm_label() { gh api -X DELETE "repos/$REPO/issues/$1/labels/$(jq -rn --arg l "$2" '$l|@uri')" > /dev/null 2>&1 || true; }
labels_of() { gh api "repos/$REPO/issues/$1/labels" --jq '.[].name'; }
# GitHub closes an issue by itself only when its pull request is merged into the default
# branch: with another base branch, or if that did not happen, the workflow closes it
close_merged() {
  gh api -X PATCH "repos/$REPO/issues/$1" -f state=closed -f state_reason=completed > /dev/null
  rm_label "$1" "in progress"
}
# The engine's own working branches, and nothing else: this is the only place that knows their name
is_agent_branch() { [[ "$1" =~ ^agent/issue-[0-9]+$ ]]; }
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
# Tells you when the last sub-issue of a parent issue is closed: the whole feature is merged
# and can be tried. $1 is the sub-issue just closed, counted as closed even if the API still
# lists it as open. The number of sub-issues is remembered on the parent, so the message is
# sent once, and again only if sub-issues are added later and closed in turn.
notify_feature_done() {
  local parent pn subs total open
  parent=$(gh api "repos/$REPO/issues/$1/parent" 2> /dev/null) || return 0
  [ "$(jq -r .repository_url <<< "$parent")" = "https://api.github.com/repos/$REPO" ] || return 0
  pn=$(jq -r .number <<< "$parent")
  subs=$(gh api --paginate "repos/$REPO/issues/$pn/sub_issues?per_page=100" | jq -s 'add // []')
  total=$(jq length <<< "$subs")
  open=$(jq --argjson n "$1" '[.[] | select(.state == "open" and .number != $n)] | length' <<< "$subs")
  [ "$open" -eq 0 ] || return 0
  [ "$(marker_get "$pn" done)" != "$total" ] || return 0
  marker_set "$pn" done "$total"
  # The button asks the bot for one sentence and makes it a new sub-issue (report in bot/bot.py)
  notify "All $total sub-issues of #$pn \"$(jq -r .title <<< "$parent")\" are merged into ${BASE_BRANCH:-main}: the feature is ready to be tried. https://github.com/$REPO/issues/$pn" \
    "{\"inline_keyboard\":[[{\"text\":\"Report a problem\",\"callback_data\":\"report|$pn|\"}]]}"
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
