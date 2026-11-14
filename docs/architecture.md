# Architecture

## Goal

Claude Code agents resolve the issues of a GitHub repository, one at a time, oldest first. Each issue becomes a pull request, goes through automated checks and a CodeRabbit review, then is merged manually or automatically.

Two repositories are involved:

- the **engine**, this repository, with the workflows, the scripts, the presets and the bot;
- the **host**, your repository, where the issues live and the agents work. It calls the engine's workflows and holds the configuration, the secrets and the variables.

## Components

| Component | Runs on | Role |
| --- | --- | --- |
| Reusable workflows | GitHub Actions, in the host | Orchestrate the queue, triggers, limits and notifications |
| Claude Code (`claude-code-action`) | GitHub Actions | Writes the code and addresses reviews |
| CodeRabbit | GitHub App | Reviews the pull requests |
| A GitHub App of yours | Installed on the host | Applies labels, merges, keeps the hidden counters; one-hour tokens generated on demand |
| Telegram bot | Any always-on machine, long polling | Forwards notifications and questions, receives commands and answers; acts on GitHub as the app |
| Your GitHub account | — | Owns the host and authors the agent's commits and pull requests |

The bot uses long polling, so it needs no public address and no open ports. Notifications are sent from GitHub Actions, so they arrive even if the bot is down.

Only the notifications that need your action make the phone ring: a stopped queue or a blocked issue, a question, a pull request ready to merge (manual mode), a feature ready to be tried, a missing base branch, a wrong label, end-to-end tests the hotfixes could not fix, a token about to expire. The others arrive silently, without sound or vibration: a merge in automatic mode, a quota retry, a hotfix or sync work unit opened by the queue, the base branch back, the agent answering CodeRabbit, the trace of a dashboard action. The daily summary is silent too, unless a token is about to expire, and it is not sent on a day with nothing merged, blocked, asked or in queue. The full list is in the [README](../README.md#notifications).

## Issue flow

```mermaid
flowchart TD
    A[Oldest ready issue that no open issue blocks] --> B[Agent implements it on its own branch]
    B --> Q{Unclear?}
    Q -- yes --> W[Question on Telegram, waits for your reply]
    W --> B
    Q -- no --> P[Workflow commits, pushes and opens the pull request]
    P --> C{CI green?}
    C -- no --> F[Agent fixes the checks]
    F --> C
    C -- yes --> R[Workflow asks CodeRabbit for a review]
    R --> D{Approved?}
    D -- no --> G[Agent addresses the review]
    G --> C
    D -- yes --> M[Merge, manual or automatic]
    M --> A
```

The queue is the open issues labelled `ready`, oldest first. An issue that another open issue blocks (GitHub's "blocked by" relationship, in the sidebar of the issue or with `gh issue edit <N> --add-blocked-by <M>`) is skipped until the blocking issue is closed, so a group of issues can be queued at once and still be built in order. An issue that is not a work unit is skipped for good, with one Telegram message: a specification (it has sub-issues) or a wayfinder map or ticket (a `wayfinder:` label), labelled `ready` by mistake. The daily summary says how many issues are waiting this way: a blocking issue that is not labelled `ready` holds them indefinitely.

An issue can be a sub-issue of a larger one that holds the specification of a whole feature. The agent then receives the body of the parent too, in `.agent/spec.md`, as background: it builds only what its own issue asks. When the repository has a `CHANGELOG.md`, the agent adds one line for its change under "Unreleased", in the same pull request, so you review it with the code. The "Out of scope" section of the issue, when there is one, is copied into the pull request, so that the reviewer does not ask for work that belongs to another issue. When the last sub-issue of a parent is closed you get a Telegram message: the whole feature is merged and can be tried. With [feature branches](#feature-branches) that message comes at the end of a few more steps, described below. Its Report a problem button turns one sentence of yours into a new sub-issue of the parent, `ready` and `size: S`; the bot adds the labels only after linking it, so the agent never starts it without the specification.

### Feature branches

With `PEPPEC_BRANCHES` set, each specification gets its own branch, created from the base branch when its first work unit starts. Its work units are merged into it; the base branch gets the feature only through a pull request you merge.

```mermaid
flowchart TD
    U[Last work unit merged into the feature branch] --> O[Workflow opens the pull request feature to base branch]
    O --> S{Base branch merges in cleanly?}
    S -- no --> Y[Sync work unit: the agent resolves the conflict markers]
    Y --> S
    S -- yes --> E{End-to-end tests of the feature pass?}
    E -- no --> H[Hotfix work unit, size L, with the log]
    H --> S
    E -- yes --> T[Ready to be tried: Telegram and dashboard]
    T --> M[You merge the pull request: the specification is closed, the branch removed]
```

- **One feature is built at a time.** Work units of a feature already started come first, and a sync work unit before anything else. A finished feature waits for you while the next one is built.
- **Names are remembered.** Each issue keeps the branch it started on (a hidden marker on the issue); the feature branch is remembered on the specification. Markers are read only from the app's comments, and a remembered branch is used only if it is the agent's branch of that issue: anyone can comment on a public repository. The engine recognises its own branches by the templates of `PEPPEC_BRANCHES`, which must name the issue number: a template that does not is refused.
- **The base branch comes in only at the end.** GitHub's merge API brings it into the feature branch. On a conflict the workflow opens a sync work unit, makes the merge itself with the conflict markers in place, and the agent resolves them; markers left behind are never pushed, and the pull request is merged with a merge commit. If the base branch moves while a finished feature waits, it is brought in again.
- **End-to-end tests run on the feature's pull request.** CI runs `PEPPEC_E2E_FEATURE` (`ci / e2e_feature`) and `PEPPEC_E2E_ALL` (`ci / e2e_all`) only there; elsewhere both succeed without running. A failing `e2e_feature` opens a hotfix work unit of size L; after two of them you are told instead. `e2e_all` is meant to be required on the base branch, so a red suite blocks your merge.

A single workflow wakes up every 15 minutes and on every relevant event: CI finished, review submitted, pull request closed, bot command. Each time it reads the state back from GitHub and picks exactly one move, so it can restart at any point. Only one run executes at a time.

## Presets and configuration

Everything that depends on the language lives in a preset, a directory of the engine:

| File | Content |
| --- | --- |
| `action.yml` | A composite action that installs the toolchain and the dependencies |
| `preset.yml` | Defaults: project description, check commands, notes for the agent, allowed and disallowed tools, protected paths |
| `fixture/` | A minimal project used to test the preset |

The host chooses a preset in `.github/peppec.yml` and can override any default:

```yaml
preset: rust-v1
check: |
  cargo fmt --all -- --check
  cargo test --all-features
```

Two more keys cover what a preset cannot know: `options` passes values to the preset (a language version, extensions), and `extra_setup` names a setup action of the host, run after the preset's, for services and system packages.

CI and the agent use the same definition: CI runs the setup and the check commands, and the agent's prompt tells it to run the same commands until they pass.

The configuration is always read from the base branch: `main`, or the branch named by the `BASE_BRANCH` variable. Pull requests from the agent's branches (`agent/issue-N`, or the names of `PEPPEC_BRANCHES`) are checked with the configuration of the branch they go into, so the agent cannot weaken its own checks.

## Model selection

The model depends on the size label of the issue. The models are set in `.github/peppec.yml`:

```yaml
models:
  s: haiku
  m: sonnet
  l: opus
```

These are the defaults. A value is a model alias or a full model ID; you can set one size and leave the others.

- **size: S** → the `s` model. Keep it for mechanical changes: a lighter model that needs more review rounds saves nothing.
- **size: M**, or no size label → the `m` model.
- **size: L** → the `l` model from the start.

If the review still fails, the `l` model takes over from the round set in `LARGE_FROM_ROUND`, whatever the size.

## Checks, review and limits

A pull request reaches CodeRabbit only after CI passes. The review passes when CodeRabbit approves the latest commit. When a new commit contains nothing CodeRabbit reviews, such as a lockfile or a deleted file, it gives no new verdict and only replies that the review is finished or that every file was excluded by its path filters: the previous approval then stands. CodeRabbit answers every review request with a comment: a request that gets no answer at all (CodeRabbit not installed yet, or unavailable) is repeated after 20 minutes, up to three requests per commit.

The agent does not have to agree with every finding. When it leaves one unchanged on purpose, for example because another issue of the feature covers it, it writes its reasons and the workflow posts them as a reply in the thread of that finding. CodeRabbit weighs the reply and approves when convinced. If it has not approved after 20 minutes, the next round starts and the agent reads CodeRabbit's answers. A round in which the agent neither changes the code nor replies stops the queue with `needs human`.

| Limit | Variable | Past the limit |
| --- | --- | --- |
| Attempts to make the checks pass, per review round | `MAX_CI_ATTEMPTS` | Queue stops, Telegram notification |
| Review rounds, tracked with the `review N` labels | `MAX_REVIEW_ROUNDS` | `needs human` label, queue stops, Telegram notification |
| Agent working time per issue, summed over all runs | `MAX_ISSUE_MINUTES` | Queue stops, Telegram notification |
| Wait for a CI result, from the latest commit | `STALL_MINUTES` | Queue stops |
| Wait for a CodeRabbit review, from the latest commit | twice `STALL_MINUTES` | Queue stops |

Waits for quota, CI and CodeRabbit do not count as working time. Counters move only after a successful push or a reply to the review: if a run is interrupted, the same move is repeated without spending a round.

## Schedule and quota

Agents start new issues only inside the work window (`WORK_START_HOUR`–`WORK_END_HOUR`). An issue already in progress is always finished. In manual mode, merging a pull request starts the next issue right away, at any hour.

The schedule is `nightly` by default. With `/schedule always` (the `always on` label on the control panel) new issues start at any hour and the work window is ignored. During the day the agents draw on the same Claude quota you use yourself: that is why nightly is the default. Pausing works in both schedules.

When the Claude quota runs out, the issue gets the `awaiting quota` label, you get a notification, and the workflow retries after `QUOTA_RETRY_MINUTES`.

## Merge modes

| Mode | Who merges | Effect on the queue |
| --- | --- | --- |
| Manual (default) | You, with the Merge button | The queue waits for your merge |
| Automatic | The workflow, as the app, as soon as the review passes | The queue runs on its own through the work window |

Pull requests are merged into the base branch: `main`, or the branch named by the `BASE_BRANCH` variable. GitHub closes an issue by itself only when its pull request reaches the default branch, so with another base branch the workflow closes it: right after an automatic merge, and at its next run after a merge done by hand. An issue you reopen after a merge is worked on again.

If the base branch does not exist, the whole queue stops: no issue is started, continued or blocked. You get one Telegram message with the command that creates the branch again, and the control panel gets the `base missing` label. At the first run that finds the branch, the label goes, you are told, and the queue goes on from where it was. A pull request that was open when the branch disappeared was closed by GitHub: the agent's branch is still there, and the workflow opens a new pull request from it.

The workflow merges only the pull requests of its own branches (`agent/issue-N`, or the work, hotfix, sync and single names of [`PEPPEC_BRANCHES`](setup.md#feature-branches)), and removes such a branch once its pull request is merged: right after an automatic merge, and at the run started by a merge done by hand. GitHub's own "Automatically delete head branches" stays off, because it would also delete the base branch each time it is brought to `main`; the only other branch the workflow deletes is a feature branch, once you have merged it into the base branch. A feature branch is never merged by the workflow. With a base branch other than `main`, the merge of the base branch into `main` is never automatic, whatever the mode: it is the owner's statement that the whole feature passed its end-to-end test (see [Planning a feature](planning.md)). With feature branches the machine runs the end-to-end tests first ([Feature branches](#feature-branches)); the last word is still yours, through the merge of each feature and of the base branch.

## Telegram bot

The bot answers only your chat and acts on GitHub as the app.

There is little to type. `/status` answers with one message per repository, and under each one the buttons that change it: pause or resume the queue, switch the merge mode and the schedule, unblock the issue in progress or give it a hint. The notifications about a blocked issue carry the Unblock and Hint buttons too. A Hint button asks for the text: write it as the reply the bot opens for you. The message about a feature ready to be tried carries a Report a problem button, which works the same way. Typing `/` shows the list of the commands.

The commands still work when typed in full:

| Command | Effect |
| --- | --- |
| `/status [repo]` | Mode, schedule, pause, current issue with labels, issues in queue, and the buttons |
| `/pause [repo]` | Stops the whole queue |
| `/unblock [repo] [n]` | Clears pause and blocks, resets the issue's time budget and counters, restarts |
| `/hint [repo] <n> <text>` | Comments the hint on the issue, unblocks it and restarts; without the text, the bot asks for it |
| `/mode [repo] manual` or `/mode [repo] automatic` | Switches the merge mode |
| `/schedule [repo] nightly` or `/schedule [repo] always` | Switches between the work window and working at any hour |
| `/version` | The bot's version |
| Reply to a "Question on #N" message | Posts the reply on the issue and restarts the work |
| Accept button under a "Question on #N" message | Posts the answer the agent recommends as yours and restarts the work |

One bot can follow several repositories, as long as they share the app, the Telegram bot and the chat. Every notification starts with the repository it comes from, as in `[owner/name] Question on #12:`, and a reply goes to that repository.

With one repository, `repo` is never needed. With several:

- `repo` is the name of the repository, or `owner/name` if two of them have the same name;
- `/status` and `/pause` without a repository apply to all of them;
- the other commands need the repository, unless you send them as a reply to a notification: `/unblock` in reply to a "Queue stopped" message acts on the repository of that message. A command that misses the repository or the value is answered with the buttons.

The Resume button only lifts the pause; `/unblock` and the Unblock button also clear the blocks of the issue and reset its time budget. The buttons on the notifications need a bot of version 1.9 or later.

## Dashboard

The bot can also serve a web page, meant for a phone: the state of every repository at a glance, and the same actions as the bot. It is off unless `DASHBOARD_PASSWORD` is set in the bot's `.env`.

- The home page only shows: what is waiting for you (blocked issues, open questions, pull requests ready to merge in manual mode), the features ready to be tried (open specifications whose sub-issues are all closed) and one line per repository. Nothing on it acts.
- Touching a line opens its page, where the buttons are: Unblock and Give a hint on a blocked issue, the answer to a question (Accept for the recommended answer, or your own), Report a problem on a feature ready to be tried, the merge mode, the schedule and the pause of a repository.
- Every action taken from the dashboard is also reported in the Telegram chat.

- Optionally, the home page also shows the usage of your Claude subscription: the current session, the weekly limit and any limit per model, each with when it resets. It is read from Anthropic when the page opens and when you press "Refresh usage", never on a timer. A reading less than a minute old is shown again instead of asking Anthropic, and when Anthropic answers `429 Too Many Requests` the bot asks nothing more until its `Retry-After` has passed (a minute without one), showing the last reading with a note. It needs Claude Code logged in inside the bot's container (see [setup](setup.md)); without that login the section is hidden. The usage comes from the endpoint behind Claude Code's `/usage`, which Anthropic does not document: if it changes, the section shows an error and the rest of the page keeps working. The token from `claude setup-token` cannot read it, so this is a separate login. When its access token has expired, the bot runs `claude -p ok --model haiku` once to renew it, which costs a tiny Haiku request. The limits are those of your whole account, your own sessions included.

The page asks for the password once and keeps it in the browser. The state is read from GitHub at most every 20 seconds and the page asks for it every 30; the Refresh button reads it again at once. Nothing is stored on the bot's machine.

The dashboard speaks plain HTTP and can act on your repositories: keep it inside your own network, and reach it from outside through a VPN such as Tailscale or WireGuard. Never forward its port from the internet. Without `DASHBOARD_PORT` in `.env`, it answers only on the bot's machine itself.

## Labels

| Label | Where | Set by | Meaning |
| --- | --- | --- | --- |
| `ready` | Issue | You | The issue can be picked up |
| `size: S` / `M` / `L` | Issue | You | Chooses the model |
| `in progress` | Issue | Workflow | Issue being worked on |
| `question open` | Issue | Workflow | Waiting for your answer |
| `awaiting quota` | Issue | Workflow | Resumes when the quota is back |
| `review 1`, `2`, `3` | Pull request | Workflow | Current review round |
| `ci 1`–`5` | Pull request | Workflow | Attempts to make the checks pass |
| `ready to merge` | Pull request | Workflow | Review passed, waiting for you |
| `needs human` | Issue and pull request | Workflow | Limits exceeded, queue stopped |
| `paused` / `auto mode` / `always on` | Control panel issue | Bot | Global pause, merge mode and schedule |
| `base missing` | Control panel issue | Workflow | The base branch does not exist: queue stopped until it is back |

Two hidden counters are kept as comments (`<!-- peppec:KEY=VALUE -->`): the minutes worked on an issue and the commit a review was requested for.

## Security

On a public repository anyone can open issues and comment. These rules stop a stranger, and the agent itself, from steering the system.

- **Who gives instructions.** Agents work only on issues labelled `ready`, and only you and the app can apply labels. The queue builds only issues written by your account or by the app: the body of an issue goes to the agent as it is, and its author can still edit it after you label it. A `ready` issue written by anyone else loses the label, and you get one Telegram message; copy what you want built into an issue of your own. The task contains only the comments written by your account and by the app. When the issue is a sub-issue, the body of its parent is added as background, only if your account wrote the parent.
- **Who can command the bot.** Only your Telegram chat, and in it only you (the owner of the private chat, or the users in `TELEGRAM_USER_IDS` for a group).
- **Three jobs, one with the tokens.** The agent's work runs in three jobs on separate runners. `prepare` labels the issue and writes the task with the app's token. `agent` runs Claude with the Claude token and the workflow's read-only token only, and with `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` on; the code Claude runs (tests, build scripts, dependencies) can read nothing that writes to GitHub. Its result is a patch, uploaded as data. `publish`, on a fresh runner where no code of the repository has run, builds again the commit the agent started from (it must match the tree recorded before Claude ran), applies the patch, checks it, and only then commits and pushes with your token. The Telegram token and the app's key never reach the agent job.
- **The agent never commits.** The workflow commits and pushes, after checking what changed: the whole change since the commit the agent started from, so a commit made by the agent's own code is checked too. Dependencies, build output and caches listed by the preset are left out even when the project's `.gitignore` misses them. Changes to protected paths are refused and the issue is labelled `needs human`. The engine always protects `.github` and the files that steer the agent: `.claude`, `CLAUDE.md` and `AGENTS.md` (also in subdirectories), `docs/agents` and `docs/adr`. An agent PR can be merged automatically without anyone reading it, so the agent must not be able to rewrite its own rules. The preset and the configuration add their own paths.
- **Engine and configuration out of reach.** The scripts and the presets come from the engine repository at a fixed ref; the configuration comes from the base branch. Your token has no permission on workflows.
- **Forks.** Pull requests from forks never receive secrets, and the orchestrator ignores them.
- **Third-party actions pinned.** Every action the engine's workflows use is pinned to a commit, so a moved tag cannot change the code that sees your secrets; Dependabot proposes the updates as pull requests.

One limit to know: the tools the agent may run (`cargo`, `npm`, …) execute code from the repository with the runner's rights, sudo included. That code can still read the Claude token from memory and spend your quota, and it can write what the agent job uploads; it cannot push, comment or merge.
