# Setup guide

Follow the phases in order: each one assumes the previous ones are done. Replace every placeholder in angle brackets with your own value.

| Placeholder | Meaning |
| --- | --- |
| `<USER>` | Your GitHub account, owner of the repository |
| `<REPO>` | The repository name |
| `<APP_SLUG>` | The GitHub App's short name, as in its URL (Phase 2) |
| `<APP_ID>` | The GitHub App's numeric ID (Phase 2) |
| `<N_CONTROL>` | The number of the "Control panel" issue (Phase 4) |

## Quick path: the command line

`peppec init` automates Phases 1, 4 and 5 and the storing of the secrets of Phase 2. It is safe to run again: it keeps what is already set and only asks for what is missing.

The simplest way to get it is the gh extension:

```bash
gh extension install PeppeColi/gh-peppec
```

Then type `gh peppec` wherever this guide says `peppec`. Each run downloads the command line of the engine version it installs (`v1`, or the one given with `--ref`), so there is nothing to update.

Or install the script once, outside your projects, so it serves every repository and never ends up in a commit:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://raw.githubusercontent.com/PeppeColi/peppec/v1/cli/peppec -o ~/.local/bin/peppec
chmod +x ~/.local/bin/peppec
```

If `~/.local/bin` is not in your `PATH`, call the script with its full path. `peppec update` replaces it with the current version. To try it without installing anything: `bash <(curl -fsSL https://raw.githubusercontent.com/PeppeColi/peppec/v1/cli/peppec) init`.

Then, inside a clone of your repository:

```bash
peppec init
```

What stays manual, because it needs your login or a secret only you can generate:

1. Before `init`: create the GitHub App, generate its private key and install it on the repository (Phase 2, steps 1–3); create the Telegram bot (step 6).
2. During `init`: paste the Claude token, your personal token and the bot token when asked. The values are read without echo and sent straight to GitHub.
3. After `init`: commit and push the files it wrote, install CodeRabbit (Phase 3), then run `peppec bot` and copy the folder it prepares to the bot's machine (Phase 6).

`init` also writes the PEPPEC section of `CLAUDE.md`, which tells the planning sessions on your computer how to write issues PEPPEC can build: see [Planning work for the agents](planning.md#producing-the-issues-with-a-planning-session).

`peppec doctor` checks the result at any time: labels, variables, secrets, workflows, configuration, the PEPPEC section of `CLAUDE.md`, branch protection, the expiry of the Claude token. With `--key <app.pem>` it also checks that the app is installed on the repository.

For unattended use, `peppec init --yes` never asks: it keeps what is set, takes the defaults and reads the secrets from the environment.

The rest of this guide describes every step in detail, and is the reference for doing them by hand.

Prerequisites:

- [ ] `git`, `gh` 2.94 or later (GitHub CLI, signed in with `gh auth login`) and `jq` on your computer. Older versions cannot create sub-issues from the command line (`gh issue create --parent`); check with `gh --version`
- [ ] Claude Code installed and signed in with your subscription
- [ ] A Telegram account
- [ ] An always-on machine with Docker and Docker Compose for the bot (a Raspberry Pi with a 64-bit system is enough)
- [ ] A repository whose default branch is `main`, with a project one of the [presets](../presets) can build

All `gh` commands run on your computer, signed in as `<USER>`.

## On an existing repository

PEPPEC can be installed on a project that already has code, history and habits. Check these before running `init`; the first three are blocking.

- [ ] **A preset fits the language** (`rust-v1`, `php-v1`). Another language needs a new preset: see [CONTRIBUTING.md](../CONTRIBUTING.md).
- [ ] **The default branch is `main`.** `init` stops otherwise; rename it under Settings → Branches.
- [ ] **The preset's checks pass on the code as it is.** For the agent "done" means "the checks pass", so they must start green, and a test suite that matters is what makes them meaningful. On a mature project a strict linter often fails at first: fix the warnings, or declare your own commands under `check:` in `.github/peppec.yml`, which replaces the preset's for CI and the agent alike.
- [ ] **Services the tests need** (a database, system packages, generated files) go in a small setup action of yours, named by `extra_setup` (see [Services and other project-specific setup](#services-and-other-project-specific-setup)).
- [ ] **Workflow files with the same names.** `init` writes `agent.yml`, `ci.yml` and `summary.yml`, and asks before overwriting a file that differs. The required check is `ci / ci` from PEPPEC's workflow: rename your own CI first (for example to `build.yml`) and keep both.
- [ ] **No open issue labelled `ready` that you do not want built.** The first run takes the oldest one. If `ready` already means something else to you, rename your label first.
- [ ] **Existing branch protection.** `init` leaves an existing branch ruleset alone and only tells you what it should require; check that it requires `ci / ci`.

Two planning sessions are worth doing before the first feature: see [Working on an existing codebase](planning.md#working-on-an-existing-codebase).

## Phase 1 — Repository settings and labels

1. Add the working folders of the workflows to `.gitignore`:

```bash
printf '.agent/\n_ctl/\n_preset/\n_extra/\n_base/\n' >> .gitignore
```

2. Protect `main`: **Settings → Rules → Rulesets → New branch ruleset**, target `main`, enable "Require a pull request before merging" (0 approvals) and "Block force pushes". Under **Bypass list** add the **Repository admin** role, so you can push the setup files straight to `main`. The required status check is added in Phase 5.
3. **Settings → Actions → General**: under "Approval for running fork pull request workflows" choose "Require approval for all external contributors".
4. **Settings → General → Pull Requests**: leave "Automatically delete head branches" off. The workflow removes the agent's branches itself after a merge; GitHub's setting would also delete a base branch such as `dev` each time you bring it to `main`.
5. Create the labels:

```bash
R=<USER>/<REPO>
while IFS='|' read -r name desc; do
  gh label create "$name" -R "$R" --description "$desc" --force
done <<'EOF'
ready|Ready to be picked up by the agents
size: S|Small issue, for the lightest model (Haiku by default)
size: M|Medium issue, the default (Sonnet by default)
size: L|Large issue, for the strongest model (Opus by default)
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
always on|New issues start at any hour, not only at night (control panel)
base missing|The base branch does not exist: queue stopped until it is back (control panel)
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

`peppec init` can do steps 1 and 2 for you: it opens GitHub with the settings below already filled in, you confirm, and it receives the App ID and the private key, which it saves in your home folder. Then it opens the page of step 3. By hand:

1. Create the app: **Settings → Developer settings → GitHub Apps → New GitHub App**.
   - Name: any free name; the name in the app's URL is your `<APP_SLUG>`.
   - Homepage URL: the repository URL.
   - Webhook: untick **Active**.
   - Repository permissions: Actions, Contents, Issues and Pull requests set to **Read and write**; Checks set to **Read-only**.
   - Where can this GitHub App be installed: **Only on this account**.
2. On the app page note the **App ID**, then under **Private keys** click **Generate a private key**: a `.pem` file downloads.
3. Install it: **Install App → your account → Only select repositories → `<REPO>`**.
4. Claude token: run `claude setup-token` and copy the token. It lasts one year: note the date.
5. Personal token: **Settings → Developer settings → Personal access tokens → Fine-grained tokens → Generate**, "Only select repositories" → `<REPO>`, with the permissions in the table. `peppec init` prints a link that fills in name, description, expiry and permissions.
   - This is a token of your own account: not the app's key, and not the token `gh` uses on your computer. The workflow uses it to push the agent's commits and open pull requests in your name.
   - Name it `peppec workflow`, adding the repository name if you create one token per repository, so its purpose is clear in GitHub's list and in the email GitHub sends before it expires.
   - Expiration: one year is a reasonable choice. When the token expires the queue stops until you replace it. Note the date.
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

CodeRabbit approves a pull request once its comments are resolved, and the workflow uses that approval as the "review passed" signal. Automatic reviews are switched off: the workflow asks for one review per commit, as soon as the checks are green. If CodeRabbit does not answer the request at all, for example because it was installed after the first pull request, the workflow asks again after 20 minutes. On public repositories with few stars CodeRabbit does not start on its own anyway, and this avoids spending the review allowance on commits that do not pass CI.

## Phase 4 — Control panel and variables

Pause and merge mode are labels on a "Control panel" issue, so you can see them on GitHub and the bot can change them. The other parameters are repository variables.

1. Create and pin the panel, and note its number:

```bash
R=<USER>/<REPO>
gh issue create -R "$R" --title "Control panel" \
  --body "Labels: paused = queue stopped; auto mode = automatic merge; always on = work at any hour. Do not close."
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
gh variable set LARGE_FROM_ROUND -R "$R" -b 3
gh variable set MAX_CI_ATTEMPTS -R "$R" -b 5
gh variable set MAX_ISSUE_MINUTES -R "$R" -b 120
gh variable set STALL_MINUTES -R "$R" -b 120
gh variable set QUOTA_RETRY_MINUTES -R "$R" -b 60
gh variable set SUMMARY_HOUR -R "$R" -b 9
gh variable set CLAUDE_TOKEN_EXPIRES -R "$R" -b "<one year after claude setup-token, YYYY-MM-DD>"
gh variable set AGENT_TOKEN_EXPIRES -R "$R" -b "<expiry date of the personal token, YYYY-MM-DD>"
```

| Variable | Meaning |
| --- | --- |
| `WORK_START_HOUR`, `WORK_END_HOUR` | Hours between which new issues are started, in `TZ_NAME`. The window may cross midnight. Ignored while the schedule is `always` |
| `MAX_ISSUE_MINUTES` | The agent's total working time per issue. Waits for quota, CI and CodeRabbit do not count |
| `STALL_MINUTES` | How long a pull request may wait for a CI result; a review may take twice as long |
| `LARGE_FROM_ROUND` | Review round from which the model of size L takes over |
| `SUMMARY_HOUR` | Hour of the daily summary, in `TZ_NAME` |
| `BASE_BRANCH` | Optional: the branch the agent starts from and its pull requests are merged into. `main` when not set. See [A base branch other than `main`](#a-base-branch-other-than-main) |
| `PEPPEC_BRANCHES` | Optional: the names of the agent's branches, and a feature branch for each specification. See [Feature branches](#feature-branches) |
| `PEPPEC_E2E_FEATURE`, `PEPPEC_E2E_ALL` | Optional, with feature branches: the end-to-end tests of one feature and of the whole project. See [End-to-end tests](#end-to-end-tests) |
| `CLAUDE_TOKEN_EXPIRES`, `AGENT_TOKEN_EXPIRES` | The summary warns you during the 30 days before each date. The second is optional: leave it out for a token that never expires |

## Phase 5 — Workflows and configuration

1. Copy the three workflows and the configuration from [`examples/`](../examples):

```bash
base=https://raw.githubusercontent.com/PeppeColi/peppec/v1/examples
mkdir -p .github/workflows
for f in agent ci summary; do curl -fsSL "$base/$f.yml" -o ".github/workflows/$f.yml"; done
curl -fsSL "$base/peppec.yml" -o .github/peppec.yml
```

2. In `.github/peppec.yml` choose the [preset](../presets) for your project. Each preset's README lists what it installs and checks; any default can be overridden.
3. If the tests need something the preset does not install, add your own setup action as described below.
4. In `summary.yml`, adjust the cron hours to your time zone as explained in the file.
5. Commit and push to `main` from your account. Check that the `ci` workflow passes.
6. Go back to the ruleset of Phase 1 and add **`ci / ci`** to "Require status checks to pass".

Workflow and configuration changes are always yours to make: the agent's token cannot touch workflows, and the agent's changes under `.github` are refused. The same goes for the files that steer the agent: `.claude`, `CLAUDE.md` and `AGENTS.md` (also in subdirectories), `docs/agents` and `docs/adr`. When a task needs them, the agent asks a question instead.

### Services and other project-specific setup

A preset is generic: it installs the language and the dependencies. A database for the tests, a system package or a file to generate belong to your project, in a small action of your own that runs right after the preset, both in CI and for the agent.

```yaml
# .github/actions/services/action.yml
runs:
  using: composite
  steps:
    - shell: bash
      run: docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=test postgres:16
    - shell: bash
      run: cp .env.testing.example .env.testing
```

```yaml
# .github/peppec.yml
preset: php-v1
extra_setup: .github/actions/services
```

The action must live under `.github/`, so the agent cannot change it. Like the rest of the configuration, it is read from the base branch.

### A base branch other than `main`

By default the agent's pull requests are merged into `main`. To collect them on another branch first, for example `dev`, and bring them to `main` yourself when a group of issues is complete and tested:

```bash
git push origin main:dev                        # create the branch, with the same files as main
gh variable set BASE_BRANCH -R "$R" -b dev
```

Then add `dev` to the target branches of the ruleset of Phase 1, and create a second branch ruleset for `dev` alone, with only "Restrict deletions" and an empty bypass list. `peppec init` asks for the branch, sets the variable and creates the second ruleset. On a private repository of a free plan rulesets are not available: `dev` works all the same, only without that second guard.

What changes:

- **Issues are closed by the workflow.** GitHub closes an issue by itself only when its pull request reaches the default branch. A closed issue therefore means "merged into `dev`", not "on `main`".
- **The configuration is read from `dev`.** `.github/peppec.yml` and your setup action travel with the code they check, and reach `main` together with it. `peppec doctor` warns when the configuration differs between the two branches.
- **The workflow files must be the same on both branches.** GitHub runs the scheduled and manual runs from the copy on `main`, and the runs started by a pull request (review submitted, pull request closed) from the copy on `dev`. A change to them, such as an [upgrade](#upgrading), goes to `main` first and is then merged into `dev`. `peppec doctor` reports a difference as a problem.
- **Bringing `dev` to `main` is yours to do**, with a pull request merged with a merge commit. A squash would leave the two branches with different histories, and the next pull request between them would conflict. A fix made directly on `main` must be merged back into `dev`. `dev` stays after the merge: GitHub does not delete merged branches here (Phase 1), on any plan. Do not press "Delete branch" on that pull request. The second ruleset makes the button fail; the first one does not, because admins bypass it. Where rulesets are not available and `dev` was deleted by mistake, "Restore branch" on the same pull request brings it back.
- **Without `dev` the queue stops.** If the branch is missing, nothing is started and you get one Telegram message; the queue goes on by itself when the branch is back (see [Merge modes](architecture.md#merge-modes)).

### Feature branches

By default every issue gets a branch `agent/issue-N`, based on the base branch. Set `PEPPEC_BRANCHES` to name the branches your way and to give each specification its own integration branch:

```bash
gh variable set PEPPEC_BRANCHES -R "$R" -b 'feature=feature/{spec}/dev'
```

The variable holds one `kind=template` per line; a kind left out takes its default:

| Kind | Default | Based on | What |
| --- | --- | --- | --- |
| `feature` | `feature/{spec}/dev` | the base branch | The integration branch of a specification |
| `work` | `feature/{spec}/parte-{n}` | its feature branch | A work unit of the specification |
| `hotfix` | `feature/{spec}/hotfix-{n}` | its feature branch | A problem reported with Report a problem |
| `sync` | `feature/{spec}/sync-{n}` | its feature branch | Resolving the conflicts between the base branch and the feature |
| `single` | `fix/{n}-{slug}` | the base branch | An issue without a specification |

`{spec}` is the number of the specification and its title in lowercase words joined by dashes (`78-stats`), `{n}` the number of the issue, `{slug}` its title the same way. Every template but `feature` must contain `{n}`; `feature` must contain `{spec}`. Never create a branch named like the beginning of a feature branch (`feature/78-stats` next to `feature/78-stats/dev`): git cannot hold both.

How it works:

- **The feature branch is created by the workflow** from the base branch, when the first work unit of the specification starts. The work units are merged into it, as they would be into the base branch.
- **Names are kept.** Each issue remembers its branch when it starts: renaming the issue or the specification, or changing the variable, never moves work already under way. Issues started before the variable keep `agent/issue-N`.
- **One feature is built at a time.** The work units of a feature already started come first; a finished feature waits for you while the agent starts the next one.
- **When the last work unit is merged** the workflow opens a pull request from the feature branch into the base branch, brings the base branch into the feature (see below) and sends the "ready to be tried" message with the link of the pull request. Try the feature on its branch, then merge that pull request yourself: the workflow never merges it. The merge closes the specification and removes the feature branch.
- **The feature follows the base branch only at the end.** While it is built the feature branch is left alone. When it is finished the workflow merges the base branch into it. If the two conflict, it opens a sync work unit, a sub-issue of the specification: the workflow makes the merge, the agent resolves the conflict markers, and its pull request is merged with a merge commit (in manual mode, merge it that way yourself: a squash would bring the conflict back). The "ready to be tried" message comes once that work unit is merged. If the base branch moves again while a finished feature waits for you, the workflow merges it in again and tells you, or opens a new sync work unit.
- **Setup.** `peppec init` asks whether you want feature branches (it sets `PEPPEC_BRANCHES` to `feature=feature/{spec}/dev`, which you can change afterwards) and the two end-to-end commands below. Where rulesets exist it creates a ruleset "feature branches" that forbids force pushes on them, and adds `ci / e2e_all` to the required checks of a ruleset it creates. `peppec doctor` checks the templates and warns when `ci / e2e_all` is not required on the base branch.
- **On the dashboard and in `/status`** every finished feature is listed under "Ready to try", with the link of its pull request; "Being checked" means the workflow is still bringing in the base branch or running its end-to-end tests.
- **A variable, not `.github/peppec.yml`:** a feature branch carries the configuration of the day it was created.

### End-to-end tests

With feature branches, two optional repository variables run end-to-end tests on the pull request of each feature into the base branch:

```bash
gh variable set PEPPEC_E2E_FEATURE -R "$R" -b 'npx playwright test --grep @spec-{spec}'
gh variable set PEPPEC_E2E_ALL -R "$R" -b 'npx playwright test'
```

- **`PEPPEC_E2E_FEATURE`**: the tests of one feature. `{spec}` becomes the number of its specification; how the tests are picked (a tag, a folder, a name) is up to your command. The agent is told the command, and writes the scenarios of the specification so that it picks them. The tests run once the feature is finished (CI job `ci / e2e_feature`); the "ready to be tried" message waits for them. If they fail, the workflow opens a work unit of size L with the end of the log; after two such work units it tells you and stops opening them.
- **`PEPPEC_E2E_ALL`**: the whole suite (CI job `ci / e2e_all`), on the same pull request. Add `ci / e2e_all` to the required checks of the ruleset of the base branch: a red suite then blocks your merge.
- A variable left out turns its level off. On every other pull request both jobs succeed without running anything, so requiring them blocks nothing else.
- The tests run after the setup of the preset and your `extra_setup`, with the feature's own configuration: services and browsers go in your setup action. They count towards nothing but their own job: give them the time they need in the workflow, not in `STALL_MINUTES`, which only bounds how long the workflow waits before telling you there is no result.

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

   `REPOS` lists the repositories the bot controls, as `owner/name#N` where `N` is the number of the control panel issue. To make the same bot follow more repositories, separate them with commas: they must be installed with the same app, Telegram bot and chat. After changing `.env`, run `docker compose up -d` again.

4. Send `/status` to the bot: it answers with mode, pause and queue.
5. Optional: the dashboard, a web page with the state of the queues and the same actions as the bot. In `.env` set `DASHBOARD_PASSWORD` to a long password and `DASHBOARD_PORT=8737`, run `docker compose up -d` again and open `http://<address of the machine>:8737` from a device in the same network. Do not expose that port to the internet: see [Dashboard](architecture.md#dashboard).
6. Optional: the Claude usage on the dashboard. Log in to Claude Code once inside the bot's container: `docker compose run --rm peppec-bot claude`, follow the link it prints, paste the code back, then leave with `/exit`. The login is kept in `~/peppec-bot/claude/`. Restart the bot with `docker compose up -d`.

The final layout:

```text
~/peppec-bot/
├── docker-compose.yml
├── .env
├── claude/         (optional: the Claude Code login, step 6)
└── data/
    ├── app.pem
    └── offset      (created by the bot)
```

## Phase 7 — End-to-end test

Test during the day, with dummy issues and the work window overridden.

- [ ] On `main`: CI green, ruleset active, bot answering `/status`
- [ ] Create an easy issue labelled `ready` and `size: M`
- [ ] Start it ignoring the window: `gh workflow run agent.yml -R <USER>/<REPO> -f force=true`
- [ ] An `agent/issue-N` branch and a pull request labelled `review 1` appear; CI runs; a "@coderabbitai review" comment appears when CI is green
- [ ] In manual mode you get "ready to merge": merge and check that the next issue starts right away
- [ ] Create a deliberately vague issue: a "Question on #N" reaches you on Telegram. It shows the answer the agent recommends with an Accept button. Press Accept, or reply, and check that the work resumes
- [ ] Create an issue that asks to change a protected file: you get a question, or the queue stops with the list of files
- [ ] Try `/pause`, `/unblock`, `/hint` and `/mode automatic`, then go back to `/mode manual`
- [ ] Run `summary.yml` manually from the Actions tab and check the message
- [ ] Close the test issues

If something gets stuck, look first at the log of the `decide` job: it always says which move it chose and why.

## Upgrading

The engine version is the ref after `@` in the three workflows, repeated in `engine_ref`. To upgrade, change both in each file. With a base branch other than `main`, merge `main` into it afterwards, so both branches run the same version. `v1` follows every compatible release; use a full version or a commit SHA if you prefer to upgrade deliberately.

The bot follows the same versions: `docker compose pull && docker compose up -d`, then `/version`.

From 1.6 the notifications start with the repository name, and a bot older than 1.6 does not accept replies to them: upgrade the bot together with the engine. A bot configured with `REPO` and `CONTROL_ISSUE` keeps working; `REPOS` replaces both.

## Maintenance

- **Claude token**: it lasts one year. Run `claude setup-token` again, then update the `CLAUDE_CODE_OAUTH_TOKEN` secret and the `CLAUDE_TOKEN_EXPIRES` variable.
- **Personal token**: regenerate it on GitHub before it expires, then update the `AGENT_TOKEN` secret and the `AGENT_TOKEN_EXPIRES` variable. Running `peppec init` again does both: answer yes when it asks whether to replace the token.
- **Scheduled workflows**: on public repositories GitHub disables them after 60 days without activity. Re-enable `agent` and `summary` from the Actions tab.
- **App permissions**: if a step fails with "Resource not accessible by integration", add the missing permission on the app's page and accept the change in the installation settings.
