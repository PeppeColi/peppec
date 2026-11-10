# Setup guide

Follow the phases in order: each one assumes the previous ones are done. Replace every placeholder in angle brackets with your own value.

| Placeholder | Meaning |
| --- | --- |
| `<USER>` | Your GitHub account, owner of the repository |
| `<REPO>` | The repository name |
| `<APP_SLUG>` | The GitHub App's short name, as in its URL (Phase 2) |
| `<APP_ID>` | The GitHub App's numeric ID (Phase 2) |
| `<N_CONTROL>` | The number of the "Control panel" issue (Phase 4) |

Prerequisites:

- [ ] `git`, `gh` (GitHub CLI, signed in with `gh auth login`) and `jq` on your computer
- [ ] Claude Code installed and signed in with your subscription
- [ ] A Telegram account
- [ ] An always-on machine with Docker and Docker Compose for the bot (a Raspberry Pi with a 64-bit system is enough)
- [ ] A repository whose default branch is `main`, with a project one of the [presets](../presets) can build

All `gh` commands run on your computer, signed in as `<USER>`.

## Phase 1 — Repository settings and labels

1. Add the working folders of the workflows to `.gitignore`:

```bash
printf '.agent/\n_ctl/\n_preset/\n_base/\n' >> .gitignore
```

2. Protect `main`: **Settings → Rules → Rulesets → New branch ruleset**, target `main`, enable "Require a pull request before merging" (0 approvals) and "Block force pushes". Under **Bypass list** add the **Repository admin** role, so you can push the setup files straight to `main`. The required status check is added in Phase 5.
3. **Settings → Actions → General**: under "Approval for running fork pull request workflows" choose "Require approval for all external contributors".
4. **Settings → General → Pull Requests**: enable "Automatically delete head branches".
5. Create the labels:

```bash
R=<USER>/<REPO>
while IFS='|' read -r name desc; do
  gh label create "$name" -R "$R" --description "$desc" --force
done <<'EOF'
ready|Ready to be picked up by the agents
complexity: simple|Handled by Sonnet
complexity: complex|Handled by Opus
in progress|An agent is working on this issue
question open|The agent is waiting for an answer
awaiting quota|Paused until the Claude quota resets
needs human|Limits exceeded, manual action required
ready to merge|Review passed, waiting for manual merge
review 1|Review round 1
review 2|Review round 2
review 3|Review round 3
ci 1|Check fix attempt 1
ci 2|Check fix attempt 2
ci 3|Check fix attempt 3
ci 4|Check fix attempt 4
ci 5|Check fix attempt 5
paused|Queue paused (control panel)
auto mode|Automatic merge enabled (control panel)
EOF
```

## Phase 2 — GitHub App, tokens and secrets

Labels, merges, counters and the Telegram bot act through a GitHub App of yours, so they appear on GitHub as `<APP_SLUG>[bot]`. The agent's commits and pull requests stay under your account.

| Secret | Source | Permissions |
| --- | --- | --- |
| `CLAUDE_CODE_OAUTH_TOKEN` | `claude setup-token` | Uses your subscription's quota |
| `AGENT_TOKEN` | Fine-grained token of your account, `<REPO>` only | Contents, Issues, Pull requests: read and write; Actions: read. **No** Workflows |
| `APP_PRIVATE_KEY` | The app's private key (`.pem` file) | Those of the app, below |
| `TELEGRAM_BOT_TOKEN` | BotFather | — |
| `TELEGRAM_CHAT_ID` | Telegram API | — |

Never write these values in a file of the repository, in an issue or in a note.

1. Create the app: **Settings → Developer settings → GitHub Apps → New GitHub App**.
   - Name: any free name; the name in the app's URL is your `<APP_SLUG>`.
   - Homepage URL: the repository URL.
   - Webhook: untick **Active**.
   - Repository permissions: Actions, Contents, Issues and Pull requests set to **Read and write**; Checks set to **Read-only**.
   - Where can this GitHub App be installed: **Only on this account**.
2. On the app page note the **App ID**, then under **Private keys** click **Generate a private key**: a `.pem` file downloads.
3. Install it: **Install App → your account → Only select repositories → `<REPO>`**.
4. Claude token: run `claude setup-token` and copy the token. It lasts one year: note the date.
5. Personal token: **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate**, "Only select repositories" → `<REPO>`, with the permissions in the table.
6. Telegram bot: message `@BotFather`, send `/newbot` and follow the prompts; copy the token.
7. Chat ID: send any message to your new bot, then:

```bash
curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates" | jq '.result[0].message.chat.id'
```

8. Store everything. The loop asks for each value to paste; the key is read from the file:

```bash
R=<USER>/<REPO>
for s in CLAUDE_CODE_OAUTH_TOKEN AGENT_TOKEN TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID; do
  gh secret set "$s" -R "$R"
done
gh secret set APP_PRIVATE_KEY -R "$R" < ~/Downloads/<downloaded-file>.pem
```

Keep the `.pem` file until Phase 6, where the bot needs it, then delete it from your computer.

## Phase 3 — CodeRabbit

1. Go to coderabbit.ai, sign in with GitHub and install the app on `<REPO>` only.
2. Copy [`examples/coderabbit.yaml`](../examples/coderabbit.yaml) to `.coderabbit.yaml` in the root of your repository, commit and push.

CodeRabbit approves a pull request once its comments are resolved, and the workflow uses that approval as the "review passed" signal. Automatic reviews are switched off: the workflow asks for one review per commit, as soon as the checks are green. On public repositories with few stars CodeRabbit does not start on its own anyway, and this avoids spending the review allowance on commits that do not pass CI.

## Phase 4 — Control panel and variables

Pause and merge mode are labels on a "Control panel" issue, so you can see them on GitHub and the bot can change them. The other parameters are repository variables.

1. Create and pin the panel, and note its number:

```bash
R=<USER>/<REPO>
gh issue create -R "$R" --title "Control panel" \
  --body "Labels: paused = queue stopped; auto mode = automatic merge. Do not close."
gh issue pin <N_CONTROL> -R "$R"
```

2. Get the name and noreply email that will author the agent's commits:

```bash
gh api user --jq '.name, "\(.id)+\(.login)@users.noreply.github.com"'
```

3. Set the variables:

```bash
gh variable set CONTROL_ISSUE -R "$R" -b "<N_CONTROL>"
gh variable set OWNER_LOGIN -R "$R" -b "<USER>"
gh variable set APP_ID -R "$R" -b "<APP_ID>"
gh variable set APP_LOGIN -R "$R" -b "<APP_SLUG>[bot]"
gh variable set AGENT_GIT_NAME -R "$R" -b "<your name>"
gh variable set AGENT_GIT_EMAIL -R "$R" -b "<noreply email>"
gh variable set TZ_NAME -R "$R" -b "<your time zone, for example Europe/Rome>"
gh variable set WORK_START_HOUR -R "$R" -b 22
gh variable set WORK_END_HOUR -R "$R" -b 9
gh variable set MAX_REVIEW_ROUNDS -R "$R" -b 3
gh variable set OPUS_FROM_ROUND -R "$R" -b 3
gh variable set MAX_CI_ATTEMPTS -R "$R" -b 5
gh variable set MAX_ISSUE_MINUTES -R "$R" -b 120
gh variable set STALL_MINUTES -R "$R" -b 120
gh variable set QUOTA_RETRY_MINUTES -R "$R" -b 60
gh variable set SUMMARY_HOUR -R "$R" -b 9
gh variable set CLAUDE_TOKEN_EXPIRES -R "$R" -b "<one year after claude setup-token, YYYY-MM-DD>"
```

| Variable | Meaning |
| --- | --- |
| `WORK_START_HOUR`, `WORK_END_HOUR` | Hours between which new issues are started, in `TZ_NAME`. The window may cross midnight |
| `MAX_ISSUE_MINUTES` | The agent's total working time per issue. Waits for quota, CI and CodeRabbit do not count |
| `STALL_MINUTES` | How long a pull request may wait for a CI result; a review may take twice as long |
| `OPUS_FROM_ROUND` | Review round from which Opus replaces Sonnet on simple issues |
| `SUMMARY_HOUR` | Hour of the daily summary, in `TZ_NAME` |
| `CLAUDE_TOKEN_EXPIRES` | The summary warns you during the 30 days before this date |

## Phase 5 — Workflows and configuration

1. Copy the three workflows and the configuration from [`examples/`](../examples):

```bash
base=https://raw.githubusercontent.com/PeppeColi/peppec/v1/examples
mkdir -p .github/workflows
for f in agent ci summary; do curl -fsSL "$base/$f.yml" -o ".github/workflows/$f.yml"; done
curl -fsSL "$base/peppec.yml" -o .github/peppec.yml
```

2. In `.github/peppec.yml` choose the [preset](../presets) for your project. Each preset's README lists what it installs and checks; any default can be overridden.
3. In `summary.yml`, adjust the cron hours to your time zone as explained in the file.
4. Commit and push to `main` from your account. Check that the `ci` workflow passes.
5. Go back to the ruleset of Phase 1 and add **`ci / ci`** to "Require status checks to pass".

Workflow and configuration changes are always yours to make: the agent's token cannot touch workflows, and the agent's changes under `.github` are refused.

## Phase 6 — Telegram bot

The bot is a container that keeps asking Telegram for new messages. It answers only your chat and acts on GitHub as the app, with one-hour tokens it generates from the app's private key.

1. On the bot's machine create the folder, then copy the key into it from your computer and protect it:

```bash
# on the bot's machine
mkdir -p ~/peppec-bot/data
# on your computer
scp ~/Downloads/<downloaded-file>.pem <user>@<address>:~/peppec-bot/data/app.pem
# on the bot's machine
chmod 600 ~/peppec-bot/data/app.pem
cd ~/peppec-bot
```

2. Download the compose file and the environment template:

```bash
base=https://raw.githubusercontent.com/PeppeColi/peppec/v1/bot
curl -fsSL "$base/docker-compose.yml" -o docker-compose.yml
curl -fsSL "$base/.env.example" -o .env && chmod 600 .env
```

3. Fill in `.env`, then start the bot and follow the logs:

```bash
docker compose up -d
docker compose logs -f
```

4. Send `/status` to the bot: it answers with mode, pause and queue.
5. Optional: in `@BotFather` use `/setcommands` to show the commands in Telegram's menu.

The final layout:

```text
~/peppec-bot/
├── docker-compose.yml
├── .env
└── data/
    ├── app.pem
    └── offset      (created by the bot)
```

## Phase 7 — End-to-end test

Test during the day, with dummy issues and the work window overridden.

- [ ] On `main`: CI green, ruleset active, bot answering `/status`
- [ ] Create an easy issue labelled `ready` and `complexity: simple`
- [ ] Start it ignoring the window: `gh workflow run agent.yml -R <USER>/<REPO> -f force=true`
- [ ] An `agent/issue-N` branch and a pull request labelled `review 1` appear; CI runs; a "@coderabbitai review" comment appears when CI is green
- [ ] In manual mode you get "ready to merge": merge and check that the next issue starts right away
- [ ] Create a deliberately vague issue: a "Question on #N" reaches you on Telegram. Reply to it and check that the work resumes
- [ ] Create an issue that asks to change a protected file: you get a question, or the queue stops with the list of files
- [ ] Try `/pause`, `/unblock`, `/hint` and `/mode automatic`, then go back to `/mode manual`
- [ ] Run `summary.yml` manually from the Actions tab and check the message
- [ ] Close the test issues

If something gets stuck, look first at the log of the `decide` job: it always says which move it chose and why.

## Upgrading

The engine version is the ref after `@` in the three workflows, repeated in `engine_ref`. To upgrade, change both in each file. `v1` follows every compatible release; use a full version or a commit SHA if you prefer to upgrade deliberately.

The bot follows the same versions: `docker compose pull && docker compose up -d`, then `/version`.

## Maintenance

- **Claude token**: it lasts one year. Run `claude setup-token` again, then update the `CLAUDE_CODE_OAUTH_TOKEN` secret and the `CLAUDE_TOKEN_EXPIRES` variable.
- **Scheduled workflows**: on public repositories GitHub disables them after 60 days without activity. Re-enable `agent` and `summary` from the Actions tab.
- **App permissions**: if a step fails with "Resource not accessible by integration", add the missing permission on the app's page and accept the change in the installation settings.
