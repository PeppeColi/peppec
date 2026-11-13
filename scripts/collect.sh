# scripts/collect.sh
# Runs in the agent job after Claude, and so is not trusted: whatever it writes is data that the
# publish job checks (after.sh). Gathers the agent's work in $RESULT: its changes as one binary
# patch against the commit the agent started from (commits made in between included), the
# question, the recommended answer, the replies to CodeRabbit, and what the run's log says
# about a failure.
set -uo pipefail
mkdir -p "$RESULT"
git add -A > /dev/null 2>&1
skip=(.agent _ctl _preset _extra)
while IFS= read -r p; do
  if [ -n "$p" ]; then skip+=("$p"); fi
done <<< "${NEVER_COMMIT:-}"
git reset -q -- "${skip[@]}" > /dev/null 2>&1
git diff --cached --binary "$START" > "$RESULT/changes.patch"
for f in question.md answer.md; do
  if [ -s ".agent/$f" ]; then cp ".agent/$f" "$RESULT/$f"; fi
done
if [ -d .agent/replies ]; then cp -R .agent/replies "$RESULT/replies"; fi
failure=""
if [ "$OUTCOME" != success ]; then
  log=${EXEC_FILE:-/dev/null}; [ -f "$log" ] || log=/dev/null
  if grep -qiE '\b401\b|invalid.{0,20}token|authentication' "$log"; then failure=token
  elif grep -qiE 'usage limit|limit reached|rate limit|resets at' "$log"; then failure=quota
  else failure=error; fi
fi
echo "$failure" > "$RESULT/failure"
ls -l "$RESULT"
