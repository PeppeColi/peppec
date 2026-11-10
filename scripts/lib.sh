# scripts/lib.sh
notify() {
  local text="${1:0:4000}"
  # Also in the job log, so the reason of a stop can be read without Telegram
  echo "notify: $text"
  curl -sS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" --data-urlencode text="$text" > /dev/null
}
add_label() { gh api -X POST "repos/$REPO/issues/$1/labels" -f "labels[]=$2" > /dev/null; }
rm_label() { gh api -X DELETE "repos/$REPO/issues/$1/labels/$(jq -rn --arg l "$2" '$l|@uri')" > /dev/null 2>&1 || true; }
labels_of() { gh api "repos/$REPO/issues/$1/labels" --jq '.[].name'; }
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
