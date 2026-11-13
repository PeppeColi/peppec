# scripts/summary.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
if [ "$GITHUB_EVENT_NAME" = schedule ] && [ "$(TZ=$TZ_NAME date +%-H)" != "$SUMMARY_HOUR" ]; then exit 0; fi
since=$(date -u -d '24 hours ago' +%Y-%m-%dT%H:%M:%SZ)
list() { jq -r '.[] | "- #\(.number) \(.title)"'; }
merged=$(gh pr list -R "$REPO" --state merged --search "merged:>=$since" --json number,title | list)
blocked=$(gh issue list -R "$REPO" --state open --label "needs human" --json number,title | list)
questions=$(gh issue list -R "$REPO" --state open --label "question open" --json number,title | list)
ready=$(gh issue list -R "$REPO" --state open --label ready --limit 200 --json number --jq '.[].number')
queue=$(grep -c . <<< "$ready" || true)
# Ready issues that an open issue blocks: they start only when that one is closed
waiting=0
for n in $ready; do
  if [ "$(gh api "repos/$REPO/issues/$n" --jq '.issue_dependencies_summary.blocked_by // 0')" -gt 0 ]; then
    waiting=$((waiting + 1))
  fi
done
if [ "$waiting" -gt 0 ]; then queue="$queue, $waiting of them waiting for a blocking issue"; fi
expiry=""
# expires_soon DATE "what expires" "what to do": adds a warning during the last 30 days
expires_soon() {
  if [ -z "$1" ]; then return 0; fi
  local days=$(( ($(date -d "$1" +%s) - $(date +%s)) / 86400 ))
  if [ "$days" -le 30 ]; then
    expiry="$expiry

Warning: $2 expires in $days days. $3"
  fi
}
expires_soon "${CLAUDE_TOKEN_EXPIRES:-}" "the Claude token" \
  "Run 'claude setup-token' and update CLAUDE_CODE_OAUTH_TOKEN and CLAUDE_TOKEN_EXPIRES."
expires_soon "${AGENT_TOKEN_EXPIRES:-}" "your personal token (AGENT_TOKEN)" \
  "Regenerate it on GitHub and update AGENT_TOKEN and AGENT_TOKEN_EXPIRES: when it expires the queue stops."
# Nothing happened and nothing waits: no message. Otherwise it arrives silently, unless a token
# is about to expire, which needs your action
if [ -z "$merged$blocked$questions$expiry" ] && [ -z "$ready" ]; then
  echo "Nothing to report: no summary today"
  exit 0
fi
[ -n "$expiry" ] || export NOTIFY_SILENT=1
notify "Daily summary

Merged PRs in the last 24 hours:
${merged:-none}

Blocked:
${blocked:-none}

Open questions:
${questions:-none}

Issues in queue: $queue${expiry}"
