# scripts/summary.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"
if [ "$GITHUB_EVENT_NAME" = schedule ] && [ "$(TZ=$TZ_NAME date +%-H)" != "$SUMMARY_HOUR" ]; then exit 0; fi
since=$(TZ=$TZ_NAME date -d 'yesterday 22:00' -Iseconds)
list() { jq -r '.[] | "- #\(.number) \(.title)"'; }
merged=$(gh pr list -R "$REPO" --state merged --search "merged:>=$since" --json number,title | list)
blocked=$(gh issue list -R "$REPO" --state open --label "needs human" --json number,title | list)
questions=$(gh issue list -R "$REPO" --state open --label "question open" --json number,title | list)
queue=$(gh issue list -R "$REPO" --state open --label ready --limit 200 --json number --jq length)
expiry=""
if [ -n "${CLAUDE_TOKEN_EXPIRES:-}" ]; then
  days=$(( ($(date -d "$CLAUDE_TOKEN_EXPIRES" +%s) - $(date +%s)) / 86400 ))
  if [ "$days" -le 30 ]; then
    expiry="

Warning: the Claude token expires in $days days. Run 'claude setup-token' and update CLAUDE_CODE_OAUTH_TOKEN and CLAUDE_TOKEN_EXPIRES."
  fi
fi
notify "Overnight summary

Merged PRs:
${merged:-none}

Blocked:
${blocked:-none}

Open questions:
${questions:-none}

Issues in queue: $queue${expiry}"
