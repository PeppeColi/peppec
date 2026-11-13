# scripts/workspace.sh
# Runs in the agent job before Claude, with only the workflow's read-only token: puts the
# workspace on the issue's branch, and for a sync work unit makes the merge of the base branch.
# Its outputs describe the commit the agent starts from, so the publish job can build the same
# commit again and apply the agent's changes on top of it (after.sh): nothing written after
# Claude has run is trusted.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
B="${BRANCH:-agent/issue-$ISSUE}"
BASE="${BASE:-${BASE_BRANCH:-main}}"
# The checkout keeps no credentials, and a private repository answers nothing without them
REMOTE="https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"
# The workspace is on BASE_BRANCH, where the configuration was read. The issue's base may be a
# feature branch: a new branch starts from it, and after.sh compares the work with origin/$BASE
git fetch -q "$REMOTE" "+refs/heads/$BASE:refs/remotes/origin/$BASE"
if [ -n "$(git ls-remote --heads "$REMOTE" "$B")" ]; then
  git fetch -q "$REMOTE" "+refs/heads/$B:refs/remotes/origin/$B" && git checkout -q -B "$B" "origin/$B"
else
  git checkout -q -b "$B" "origin/$BASE"
fi
# A sync work unit, on its first run: the workflow merges the base branch into the feature itself
# and commits the merge as it comes, conflict markers included, without pushing it. The agent
# then only resolves the markers, and after.sh checks its changes against that commit, so the
# changes coming from the base branch are not taken for the agent's (protected paths). The
# work unit's pull request is merged with a merge commit, which keeps the base branch as a parent
merge_parents=""
conflicts=""
if [ "$ACTION" = start ] && [ "$KIND" = sync ] && [ "$BASE" != "${BASE_BRANCH:-main}" ] \
   && [ "$(git rev-parse HEAD)" = "$(git rev-parse "origin/$BASE")" ]; then
  git fetch -q "$REMOTE" "+refs/heads/${BASE_BRANCH:-main}:refs/remotes/origin/${BASE_BRANCH:-main}"
  merge_parents="$(git rev-parse HEAD) $(git rev-parse "origin/${BASE_BRANCH:-main}")"
  conflicts=$(sync_merge "${BASE_BRANCH:-main}")
fi
mkdir -p .agent
if [ -n "$conflicts" ]; then
  {
    echo; echo "## Files with conflict markers"
    echo "The workflow merged \`${BASE_BRANCH:-main}\` into the feature; these files still hold \`<<<<<<<\`, \`=======\` and \`>>>>>>>\` markers. Resolve them all, then run the checks."
    echo "$conflicts" | sed 's/^/- /'
  } >> .agent/task.md
fi
{
  echo "start=$(git rev-parse HEAD)"
  echo "start_tree=$(git rev-parse 'HEAD^{tree}')"
  echo "merge_parents=$merge_parents"
  # The app's short name, for the bots allowed to trigger Claude: "name[bot]" -> "name"
  echo "app_slug=${APP_LOGIN%\[bot\]}"
} >> "$GITHUB_OUTPUT"
