# Changelog

All notable changes to the PEPPEC engine are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the engine
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Hosts call the moving tag of their major
version (`v2`), which always points to its latest release. Versions up to 1.25.0 were rebuilt from the git
history when this file was created.

## [Unreleased]

## [2.18.1] - 2026-11-16

### Fixed

- A sync work unit opened by a run now starts in that same run, ahead of the other ready issues:
  GitHub's list of ready issues did not show it yet, so another work unit started first and the
  finished feature waited for it.

## [2.18.0] - 2026-11-16

### Added

- The smart queue: with feature branches, the planning session proposes the blockers between
  the new specification and the other open ones, from what each adds, and sets them once you
  approve its table (new part of the PEPPEC section of `CLAUDE.md`: run `peppec init` again). On
  the first round of a work unit the agent also receives the other open features, and when it
  needs code one of them adds it names it instead of writing it: the workflow blocks the
  specification's work units by it, pushes nothing and moves on to the next issue.

## [2.17.0] - 2026-11-16

### Added

- `peppec init` starts with "Use default values?". With yes it takes and shows the default of every
  question that has one (numeric parameters, time zone, base branch, commit name and email, feature
  branches, token expiry dates, `CLAUDE.md` section, label map, hook), and still asks the app on a
  first install, an unrecognised preset, the secrets, and every step that changes GitHub or
  overwrites something.

## [2.16.0] - 2026-11-16

### Added

- Each version tag publishes a GitHub release, with that version's section of this changelog as
  its notes.
- The ping: the bot starts the agent workflow every `PING_MINUTES` (15 by default) on each
  repository with something to move (an issue in progress that does not wait for you, or a ready
  issue no open issue blocks, the queue being neither paused nor without a preset) and no run in
  the meantime, and the summary workflow once a day from
  `SUMMARY_HOUR` (9 by default) in its time zone `TZ`. `peppec bot` asks for both and writes `TZ`.
- `peppec doctor` warns about a GitHub cron left in `agent.yml` or `summary.yml`, and about an
  `agent.yml` without the `ping` input.

### Changed

- GitHub's cron is not used any more: it ran the workflows hours late and the queue stood still.
  `examples/agent.yml` and `examples/summary.yml` have no `schedule`, and `agent.yml` passes the new
  `ping` input; run `peppec init` again, or copy them, then restart the bot with the new `.env`
  lines. The bot is now required on every host.
- A failure of the decide step rings only in the first quarter of an hour for runs started by the
  ping, instead of for scheduled runs.

### Removed

- The `PEPPEC_SUMMARY_HOUR` variable and the hour check of the summary: the summary is sent
  whenever its workflow runs, and the bot picks the hour.

## [2.15.0] - 2026-11-16

### Changed

- `peppec bot` prepares its folder in `~/peppec-bot` by default, outside any clone, instead of
  the current directory: the app's key and the bot token never sit inside a repository.
  `--out <dir>` still picks another folder.

### Fixed

- With feature branches, an issue blocked by a work unit of another specification no longer starts
  before that feature reaches the base branch: the workflow adds the specification as a blocker,
  with a comment on the issue.

## [2.14.0] - 2026-11-16

### Changed

- `docs/agents/e2e.md` carries a status line, "End-to-end tests per feature: on" or "off", that
  `peppec init` keeps in step with `PEPPEC_E2E_FEATURE`: the PEPPEC section of `CLAUDE.md` now
  follows that line, since planning sessions cannot read GitHub variables, and `peppec doctor`
  warns when the two disagree. Run `peppec init` to update the section and write the line.

- `peppec init` with `rust-v1` and no `Cargo.toml` offers to run `cargo init`, and the files it
  creates join the suggested commit; without cargo, or with `php-v1` and no `composer.json`, it
  warns that the first CI run will fail.

- `peppec bot` asks whether to turn on the dashboard: yes writes `DASHBOARD_PASSWORD` (generated)
  and `DASHBOARD_PORT` in `.env`, and the next steps give the address, the password and the
  optional Claude Code login for the Claude usage.

- `peppec doctor` and `peppec bot` find the app's private key where `peppec init` saved it
  (`~/<app>.private-key.pem`): doctor checks the app's installation without `--key`, and bot
  proposes that path. `--key` still picks another file.

- The `git add` that `peppec init` suggests also takes `docs/agents` when it holds files not yet
  in git, such as those written by `/setup-matt-pocock-skills`.

- The end-to-end questions of `peppec init` say "leave empty to skip" (they said "empty: none",
  which read like an invitation to type `none`), and a typed `none` is taken as empty.

- `peppec init` proposes feature branches by default on a first install. A repository already
  installed without them keeps no as the default.

## [2.13.0] - 2026-11-16

### Changed

- The branch names of a specification leave out a leading `Spec:` of its title:
  `feature/12-notes-cli-v1/dev` instead of `feature/12-spec-notes-cli-v1/dev`. A feature branch
  already created keeps its name, and its new work units follow it.

### Fixed

- `peppec init` no longer accepts a `PEPPEC_AGENT_TOKEN` that cannot reach a public repository:
  it checks the token with a real write (a blob tied to nothing) instead of the push permission
  GitHub reports, which is your role on the repository and is true for any token there.
- A pull request no longer waits forever when CodeRabbit answers the review request of a new commit
  with "Review finished" but no verdict, and its previous verdict asked for changes: the workflow
  asks once for a full review (`@coderabbitai full review`), which ends with a verdict.

## [2.12.0] - 2026-11-16

### Changed

- The branch of a work unit with feature branches is `feature/{spec}/unit-{n}` by default (it was
  `feature/{spec}/parte-{n}`). A work unit already in progress keeps the branch it started on, and
  branches with the old name are still recognised as the engine's.

## [2.11.0] - 2026-11-16

### Changed

- The PEPPEC section of `CLAUDE.md` and `docs/planning.md` ask planning sessions to check each work unit
  on the tracker (title, body, size, blockers) before adding `ready`, and to push the files they wrote
  to the base branch before the work units get `ready`.

## [2.10.0] - 2026-11-16

### Changed

- The PEPPEC section of `CLAUDE.md` and `docs/planning.md` tell planning sessions to add `ready` only
  after every blocker is set, oldest issue first, so that no work unit starts before its blockers
  exist; and, with feature branches, to block work that needs another feature by that specification,
  never by its work units. A work unit blocked by the last work unit of another feature could start
  from a base branch that did not have that feature yet. Hosts get the new section at their next
  `peppec init`.

## [2.9.0] - 2026-11-15

### Changed

- With a base branch other than `main`, the PEPPEC section of `CLAUDE.md` tells planning sessions to
  commit what they write (glossary, decision records, docs) to the base branch, never to `main`, and
  the "Next steps" of `peppec init` end with `git checkout <base branch>`. A wayfinder session had
  committed the glossary to `main`, where the agent, starting from `dev`, never sees it. Hosts get the
  new section at their next `peppec init`.

## [2.8.2] - 2026-11-15

### Fixed

- The folder `peppec bot` prepares inside a clone, with the app's key and the bot token, could end up in
  a commit. `peppec init` now adds `peppec-bot/` to `.gitignore`, and `peppec bot` adds its folder to
  `.git/info/exclude` when git does not ignore it yet.

## [2.8.1] - 2026-11-15

### Changed

- `peppec update` tells you when a new major version of the engine is out, with the command that moves
  to it; it still never moves by itself.
- `peppec --help` explains that `--key` is only for an app you already have, and shows the real default
  of `--ref` (it said `v1`, the default is `v2`).
- README and `docs/setup.md` put the setup of Matt Pocock's skills in a note before `peppec init`: where
  to type it, that the suggested answers are enough, and what `init` adds afterwards. They also say to
  run the `peppec` commands in a terminal, and how to move a copy of the script from `v1` to `v2`.

## [2.8.0] - 2026-11-15

### Changed

- The schedule is `always` by default: new issues start at any hour. `nightly` is now the choice.
- The merge mode and the schedule are always one label each on the control panel: `merge: manual` or
  `merge: automatic`, `schedule: always` or `schedule: nightly`. They replace `auto mode` and
  `always on`, and the missing label no longer means anything. With neither label of a pair the
  default applies and the workflow adds it back; with both, `manual` and `nightly` win, and
  `peppec doctor` and `/status` point it out. The bot adds the new label before removing the old one.
- `peppec init` gives the labels fixed colors: red for those that stop the queue (`paused`,
  `base missing`, `no preset`), yellow for those that wait for you (`question open`, `needs human`),
  teal for the settings of the control panel. It used to let `gh` pick them at random.
- The control panel created by `peppec init` starts with `merge: manual` and `schedule: always`, and
  its body is a table of all its labels with a link to who merges what. Existing panels keep their
  body.
- The merge modes in `docs/architecture.md` are a table of who merges each kind of pull request.

## [2.7.0] - 2026-11-15

### Added

- A glossary of PEPPEC's terms, `docs/glossary.md`, for agents and contributors, kept apart from
  the domain glossary of a host. The PEPPEC section of `CLAUDE.md` written by `peppec init` points
  to it and says not to copy its terms into the host's `GLOSSARY.md`.

## [2.6.0] - 2026-11-15

### Added

- Browser notifications on the dashboard: with the page open, the messages that make Telegram ring
  also appear as notifications of the browser, turned on at the bottom of the home page. Every
  `notify` that rings also writes an annotation `peppec` in its job; the bot reads them every minute
  and serves the last 50 at `/api/events`, so the list follows `notify` and `notify_info` by itself.
  On the dashboard's plain HTTP, Chrome needs the flag "Insecure origins treated as secure" for its
  address: the page explains it.

## [2.5.0] - 2026-11-14

### Added

- The preset `none`, for a project whose language is not chosen yet: it installs nothing and its
  check is `true`, so CI passes. While a repository uses it the queue starts no agent work (no new
  issue, no fix round); merges and closures go on. The control panel gets the `no preset` label,
  shown by `/status` and the dashboard, and the ready issues wait: each run sends one Telegram
  message listing the ones not reported yet. `peppec init` proposes `none` when there is neither
  `Cargo.toml` nor `composer.json`, and `peppec doctor` warns about it.
- `peppec init --preset <name>` on a repository with another preset rewrites the `preset:` line of
  `.github/peppec.yml` after asking, and first lists the keys written for the old language and the
  issue in progress. docs/setup.md explains how to change preset.

## [2.4.0] - 2026-11-14

### Changed

- The workflows give `actions/create-github-app-token` the app's Client ID (`client-id`) in place of
  the deprecated `app-id`, read from the new variable `PEPPEC_APP_CLIENT_ID`. `peppec init` reads it
  from the app (when it creates the app or has its key) or asks for it; `peppec doctor` reports it
  missing and, with `--key`, checks it against the app. Hosts without the variable keep working: the
  workflows fall back to `PEPPEC_APP_ID`. `PEPPEC_APP_ID` stays, the Telegram bot still needs it.

## [2.3.1] - 2026-11-14

### Changed

- The workflows use the new major versions of the GitHub actions: `actions/checkout` v7,
  `actions/upload-artifact` v7, `actions/download-artifact` v8 (a download whose hash does not match
  now fails) and `actions/create-github-app-token` v3. They run on Node 24. Hosts change nothing.

## [2.3.0] - 2026-11-14

### Fixed

- In an empty repository, GitHub never started from an event the workflows that arrived with the
  first push: no CI, no agent schedule, and the queue stood still unnoticed. `peppec init` now
  pushes a starting commit without workflows first, to `main` and the base branch together (an
  empty commit, or the commits already in the clone when they hold no `.github/workflows`); the
  install commit follows as the second push.

### Added

- `peppec doctor` reports as a problem a repository where no workflow has ever started from an
  event within half an hour of the last push to `main`, with the remedy: a commit that adds a new
  workflow file, then removes it (changing an existing one is not enough).

## [2.2.0] - 2026-11-14

### Changed

- CI runs on the pushes to the base branch too, not only to `main`: each merge is checked where
  it lands, and the pull requests into the base branch get a fresh build cache. `peppec init`
  writes `main` and the base branch under `push: branches` in `ci.yml` (only `main` when it is
  the base branch). An installation upgrades by adding its base branch there by hand, or by
  running `peppec init` again.
- `peppec doctor` checks the last CI run on the base branch instead of the default branch, and
  warns when `ci.yml` does not run on the pushes to the base branch.

## [2.1.0] - 2026-11-14

### Removed

- The bot no longer reads `REPO` and `CONTROL_ISSUE`, the settings of the single-repository bot:
  `REPOS` is the only way to name the repositories it follows. A bot that still has the old
  settings stops at start with "REPOS is empty".

### Fixed

- `bot/.env.example` lists `TELEGRAM_USER_IDS`, needed to command the bot from a group chat.
- `examples/peppec.yml` says the configuration is read from the base branch, not from `main`.
- The docs no longer carry notes about 1.x versions; the setup guide says that `init` creates
  the GitHub App with you; the architecture lists the hidden state the workflow keeps; the
  planning guide describes end-to-end tests with and without `PEPPEC_E2E_FEATURE` in two
  separate sections.

## [2.0.0] - 2026-11-14

### Changed

- **Breaking.** Every repository variable and secret used only by PEPPEC starts with `PEPPEC_`,
  so it cannot clash with those of other tools or of an organization: for example `AGENT_TOKEN`
  is now `PEPPEC_AGENT_TOKEN`, `BASE_BRANCH` is `PEPPEC_BASE_BRANCH`, `TELEGRAM_CHAT_ID` is
  `PEPPEC_TELEGRAM_CHAT_ID`. `CLAUDE_CODE_OAUTH_TOKEN` keeps its standard name. The secrets the
  reusable workflows take have the new names too.
- `peppec init` reads the new names from the environment (`PEPPEC_AGENT_TOKEN`,
  `PEPPEC_TELEGRAM_BOT_TOKEN`, `PEPPEC_TELEGRAM_CHAT_ID`), and so does `peppec bot`.
- The moving tag is `v2`: the workflows, `peppec`, its default `--ref` and the bot image `:2`.
  The bot's `.env` keeps its names.
- A 1.x installation does not move by itself: run `peppec init` of 2.0 on it, which asks again for
  the secrets and stores the new names, then delete the old variables and secrets.

## [1.32.0] - 2026-11-14

### Added

- A specification decides whether its feature needs new end-to-end tests, in a section named
  "End-to-end": `None` skips `ci / e2e_feature` (and its hotfixes) for that feature, a list of
  scenarios gets a work unit of size L that writes them; without the section they stay required.
  `ci / e2e_all` still runs on every feature pull request.
- `peppec init` creates a placeholder `docs/agents/e2e.md` (how the repository writes and runs its
  end-to-end tests); `peppec doctor` notes when it is missing.

## [1.31.0] - 2026-11-14

### Changed

- The pause stops only new issues: the issue in progress goes on to its merge (or "ready to
  merge"), and the sync and hotfix work units of a feature already built still start. To stop the
  issue in progress too, label it `needs human`.
- Only Resume lifts the pause: Unblock, Hint and the answers to a question leave it on, and their
  reply says so.

### Fixed

- A pull request merged by hand while the queue is paused is tidied up at once: its issue is closed
  and the "ready to be tried" message is sent, which was lost after a merge into the default branch.

## [1.30.1] - 2026-11-14

### Added

- The README lists every Telegram notification, what to do about it and whether it rings.

## [1.30.0] - 2026-11-14

### Changed

- Telegram rings only when you need to act: merges in automatic mode, quota retries, hotfix and
  sync work units opened by the queue, the base branch coming back, an answer to CodeRabbit and the
  trace of a dashboard action now arrive silently.
- The daily summary arrives silently, unless a token is about to expire, and is not sent on a day
  with nothing merged, blocked, asked or in queue.

## [1.29.2] - 2026-11-14

### Security

- The third-party actions of the engine's workflows are pinned to a commit, and Dependabot
  proposes their updates. The CI no longer keeps the checkout's token in the workspace.
- The bot obeys only you: in a private chat its owner, in a group chat the users listed in
  `TELEGRAM_USER_IDS`; a member of the chat can no longer command it.
- `peppec init` and `peppec doctor` explain what a private repository without branch protection
  means, and `doctor` warns when automatic merge is on there. The example `agent.yml` no longer
  asks for `id-token: write`, which nothing used.

### Added

- A "Security notes" section in docs/setup.md: public run logs, where your code goes, private
  repositories on a free plan.

## [1.29.1] - 2026-11-13

### Fixed

- The agent can run commands again (checks, tests): 1.29.0 turned on the sandbox of Claude Code
  for the agent's commands, but the runner lacked bubblewrap and socat, so every command was
  refused. The agent job now installs them before Claude runs.

## [1.29.0] - 2026-11-13

### Security

- The agent's work is split in three jobs: `prepare` (the app's token) writes the task, `agent`
  runs Claude with only the Claude token and the workflow's read-only token, and `publish`, on a
  fresh runner, applies the agent's changes as a patch, checks them and pushes. The code the agent
  runs (tests, build scripts, dependencies) could read your personal token and leave git hooks for
  the step that pushed; now it shares no runner with a token that can write. Protected paths are
  checked on the whole change, commits made by the agent's own code included.

## [1.28.1] - 2026-11-13

### Security

- The hidden markers that hold the queue's state (branch, time used, feature branch, review
  requests) are read only from comments written by the app, or by you for the review requests:
  on a public repository anyone can comment, and a marker written by someone else could send the
  agent's work straight to `main`. A remembered branch is used only when it is the agent's branch
  of that issue. Pull requests from forks are never taken for the agent's or a feature's, even
  with the same branch name, and the automatic merge happens only if the pull request still ends
  at the commit that was checked.

## [1.28.0] - 2026-11-13

### Added

- Existing projects: on a new installation `peppec init` lists the open issues already labelled
  `ready` and offers to remove the label; warns when `ready` existed with another description;
  offers to rename your own `ci.yml` to `build.yml` (the others to `<name>-own.yml`) and a default
  branch other than `main`. `peppec doctor` warns when the base branch requires approving or code
  owner reviews, when the last CI run on `main` failed, and when CI takes longer than
  `STALL_MINUTES`.
- Planning skills: `peppec skills` checks that the installed `mattpocock-skills` plugin still does
  what PEPPEC relies on (the `ready-for-agent` row of the label map, `/to-tickets` applying it,
  the `wayfinder:` labels). `peppec init` adds a SessionStart hook to `.claude/settings.json` that
  runs it when Claude Code starts and speaks only when something changed; `peppec doctor` shows
  it too. The queue sends one Telegram message for each open issue labelled `ready-for-agent`
  but not `ready`.

## [1.27.1] - 2026-11-13

### Fixed

- `peppec update` names the release it installed or found (for example `v1 (v1.27.0)`), and says
  that it compares only the script: "already up to date" after a release that changed only the
  workflows was correct, but looked like a stale copy.

## [1.27.0] - 2026-11-13

### Changed

- `dev` from day one: on a new installation `peppec init` proposes `dev` as the base branch,
  creates it at the commit of `main`, and prints one push that lands the install commit on both
  branches (in an empty repository that push creates them). An existing `dev` with commits `main`
  lacks gets a pull request from `main` instead. Installations already on `main` keep it.

## [1.26.0] - 2026-11-13

### Added

- A changelog for the engine, and one for the host: `peppec init` creates `CHANGELOG.md` when
  missing, the agent adds a line under "Unreleased" in each pull request, and `peppec doctor`
  checks the file.

### Changed

- Docs: `gh` 2.94 or later in the prerequisites; feature branches and end-to-end tests in the
  architecture page; notes for installing on an existing repository.

### Security

- The queue builds only `ready` issues written by the owner or the app. Any other `ready` issue
  loses the label, with one Telegram message: its body would reach the agent, and its author could
  edit it after you label it.

## [1.25.0] - 2026-11-13

### Added

- `peppec init` sets up feature branches, and the dashboard shows them.

## [1.24.0] - 2026-11-13

### Added

- End-to-end tests of a feature and of the whole project, run on their pull requests
  (`PEPPEC_E2E_FEATURE`, `PEPPEC_E2E_ALL`).

## [1.23.0] - 2026-11-13

### Added

- A finished feature gets the base branch merged in, and an agent resolves the conflicts.

## [1.22.0] - 2026-11-13

### Added

- Configurable branch names, and a feature branch per specification.

## [1.21.0] - 2026-11-13

### Added

- The agent's questions come with a recommended answer and an Accept button.

## [1.20.1] - 2026-11-13

### Changed

- Prompt rules for where to test and for the terms of `GLOSSARY.md`.

## [1.20.0] - 2026-11-13

### Security

- The files that steer the agent (`.claude`, `CLAUDE.md`, `AGENTS.md`, `docs/agents`,
  `docs/adr`) are always protected.

## [1.19.1] - 2026-11-13

### Changed

- The issues the agent builds are called work units, not slices.

## [1.19.0] - 2026-11-13

### Added

- The queue skips `ready` issues that are not work units (specifications, wayfinder issues).

## [1.18.0] - 2026-11-13

### Added

- `peppec init` writes a PEPPEC section in `CLAUDE.md` for planning sessions.

## [1.17.2] - 2026-11-13

### Added

- The gh extension `gh peppec` is documented; `peppec update` does nothing under it.

## [1.17.1] - 2026-11-13

### Fixed

- A repository the bot cannot read no longer hides the others.

## [1.17.0] - 2026-11-12

### Fixed

- Without its base branch the queue stops and tells you once.

## [1.16.1] - 2026-11-12

### Fixed

- The agent starts again on private repositories.

## [1.16.0] - 2026-11-12

### Fixed

- The base branch is never deleted; the workflow removes only its own branches.

## [1.15.0] - 2026-11-12

### Added

- Report a problem on a feature ready to be tried, from Telegram and the dashboard.

## [1.14.2] - 2026-11-12

### Changed

- Docs: merging the base branch into `main` is always the owner's.

### Fixed

- The Claude usage reuses a recent reading and honours `Retry-After`.

## [1.14.1] - 2026-11-12

### Fixed

- Telegram messages drop Markdown backticks.

## [1.14.0] - 2026-11-12

### Added

- The dashboard shows the Claude usage.

## [1.13.3] - 2026-11-12

### Added

- The agent answers the review findings it leaves unchanged.

### Fixed

- Notifications log why Telegram did not deliver a message.

## [1.13.2] - 2026-11-12

### Fixed

- `peppec init` adds a ruleset that keeps the base branch.
- `peppec doctor` warns when the base branch would be deleted on merge.

## [1.13.1] - 2026-11-12

### Fixed

- `peppec doctor` reports a missing base branch once.

## [1.13.0] - 2026-11-12

### Added

- The pull request carries the issue's out-of-scope section.
- Docs: how to plan a feature as a group of issues.

## [1.12.0] - 2026-11-12

### Added

- `ready` issues blocked by an open issue are skipped.
- The agent receives the specification of the parent issue.
- A message when the last sub-issue of a feature is closed.

### Fixed

- With a base branch, the workflow files must match on both branches.

## [1.11.0] - 2026-11-12

### Added

- Configurable base branch for the agent's pull requests.

### Fixed

- The issue just closed is not picked again.

## [1.10.2] - 2026-11-11

### Fixed

- A review request CodeRabbit never answered is repeated.

## [1.10.1] - 2026-11-11

### Fixed

- Rough edges of the dashboard: loading text, feedback on buttons, Markdown questions, refresh.

## [1.10.0] - 2026-11-11

### Added

- A phone dashboard served by the bot.

## [1.9.0] - 2026-11-11

### Added

- Buttons and a command menu on the Telegram bot.

## [1.8.0] - 2026-11-11

### Added

- An always-on schedule, switched from Telegram.

### Changed

- Issue sizes (`size: S`, `size: L`) pick the model, and the models are configurable. They replace
  the complexity labels.

## [1.7.0] - 2026-11-11

### Added

- `peppec init` creates the GitHub App in the browser.

## [1.6.1] - 2026-11-11

### Fixed

- The agent reads the answers and hints sent from Telegram.

## [1.6.0] - 2026-11-11

### Added

- One Telegram bot for several repositories.

## [1.5.0] - 2026-11-11

### Added

- Expiry warning for the personal token.

### Changed

- Clearer installer messages.

## [1.4.0] - 2026-11-11

### Added

- `peppec update`; the command line is installed outside the projects.

## [1.3.0] - 2026-11-11

### Added

- Command line to install and check PEPPEC on a repository (`peppec init`, `peppec doctor`).

## [1.2.1] - 2026-11-11

### Fixed

- The previous approval is kept when path filters exclude every file.

## [1.2.0] - 2026-11-11

### Added

- Paths a preset never commits.

### Fixed

- The previous approval is kept when CodeRabbit has nothing to review.

## [1.1.1] - 2026-11-11

### Fixed

- No failure when the host ignores the workflow's working folders.

## [1.1.0] - 2026-11-11

### Added

- The `php-v1` preset, preset options and extra setup.

## [1.0.0] - 2026-11-11

### Added

- First release: reusable workflows, the `rust-v1` preset, the Telegram bot, notifications also
  written to the job log.

[Unreleased]: https://github.com/PeppeColi/peppec/compare/v2.18.1...HEAD
[2.18.1]: https://github.com/PeppeColi/peppec/compare/v2.18.0...v2.18.1
[2.18.0]: https://github.com/PeppeColi/peppec/compare/v2.17.0...v2.18.0
[2.17.0]: https://github.com/PeppeColi/peppec/compare/v2.16.0...v2.17.0
[2.16.0]: https://github.com/PeppeColi/peppec/compare/v2.15.0...v2.16.0
[2.15.0]: https://github.com/PeppeColi/peppec/compare/v2.14.0...v2.15.0
[2.14.0]: https://github.com/PeppeColi/peppec/compare/v2.13.0...v2.14.0
[2.13.0]: https://github.com/PeppeColi/peppec/compare/v2.12.0...v2.13.0
[2.12.0]: https://github.com/PeppeColi/peppec/compare/v2.11.0...v2.12.0
[2.11.0]: https://github.com/PeppeColi/peppec/compare/v2.10.0...v2.11.0
[2.10.0]: https://github.com/PeppeColi/peppec/compare/v2.9.0...v2.10.0
[2.9.0]: https://github.com/PeppeColi/peppec/compare/v2.8.2...v2.9.0
[2.8.2]: https://github.com/PeppeColi/peppec/compare/v2.8.1...v2.8.2
[2.8.1]: https://github.com/PeppeColi/peppec/compare/v2.8.0...v2.8.1
[2.8.0]: https://github.com/PeppeColi/peppec/compare/v2.7.0...v2.8.0
[2.7.0]: https://github.com/PeppeColi/peppec/compare/v2.6.0...v2.7.0
[2.6.0]: https://github.com/PeppeColi/peppec/compare/v2.5.0...v2.6.0
[2.5.0]: https://github.com/PeppeColi/peppec/compare/v2.4.0...v2.5.0
[2.4.0]: https://github.com/PeppeColi/peppec/compare/v2.3.1...v2.4.0
[2.3.1]: https://github.com/PeppeColi/peppec/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/PeppeColi/peppec/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/PeppeColi/peppec/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/PeppeColi/peppec/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/PeppeColi/peppec/compare/v1.32.0...v2.0.0
[1.32.0]: https://github.com/PeppeColi/peppec/compare/v1.31.0...v1.32.0
[1.31.0]: https://github.com/PeppeColi/peppec/compare/v1.30.1...v1.31.0
[1.30.1]: https://github.com/PeppeColi/peppec/compare/v1.30.0...v1.30.1
[1.30.0]: https://github.com/PeppeColi/peppec/compare/v1.29.2...v1.30.0
[1.29.2]: https://github.com/PeppeColi/peppec/compare/v1.29.1...v1.29.2
[1.29.1]: https://github.com/PeppeColi/peppec/compare/v1.29.0...v1.29.1
[1.29.0]: https://github.com/PeppeColi/peppec/compare/v1.28.1...v1.29.0
[1.28.1]: https://github.com/PeppeColi/peppec/compare/v1.28.0...v1.28.1
[1.28.0]: https://github.com/PeppeColi/peppec/compare/v1.27.1...v1.28.0
[1.27.1]: https://github.com/PeppeColi/peppec/compare/v1.27.0...v1.27.1
[1.27.0]: https://github.com/PeppeColi/peppec/compare/v1.26.0...v1.27.0
[1.26.0]: https://github.com/PeppeColi/peppec/compare/v1.25.0...v1.26.0
[1.25.0]: https://github.com/PeppeColi/peppec/compare/v1.24.0...v1.25.0
[1.24.0]: https://github.com/PeppeColi/peppec/compare/v1.23.0...v1.24.0
[1.23.0]: https://github.com/PeppeColi/peppec/compare/v1.22.0...v1.23.0
[1.22.0]: https://github.com/PeppeColi/peppec/compare/v1.21.0...v1.22.0
[1.21.0]: https://github.com/PeppeColi/peppec/compare/v1.20.1...v1.21.0
[1.20.1]: https://github.com/PeppeColi/peppec/compare/v1.20.0...v1.20.1
[1.20.0]: https://github.com/PeppeColi/peppec/compare/v1.19.1...v1.20.0
[1.19.1]: https://github.com/PeppeColi/peppec/compare/v1.19.0...v1.19.1
[1.19.0]: https://github.com/PeppeColi/peppec/compare/v1.18.0...v1.19.0
[1.18.0]: https://github.com/PeppeColi/peppec/compare/v1.17.2...v1.18.0
[1.17.2]: https://github.com/PeppeColi/peppec/compare/v1.17.1...v1.17.2
[1.17.1]: https://github.com/PeppeColi/peppec/compare/v1.17.0...v1.17.1
[1.17.0]: https://github.com/PeppeColi/peppec/compare/v1.16.1...v1.17.0
[1.16.1]: https://github.com/PeppeColi/peppec/compare/v1.16.0...v1.16.1
[1.16.0]: https://github.com/PeppeColi/peppec/compare/v1.15.0...v1.16.0
[1.15.0]: https://github.com/PeppeColi/peppec/compare/v1.14.2...v1.15.0
[1.14.2]: https://github.com/PeppeColi/peppec/compare/v1.14.1...v1.14.2
[1.14.1]: https://github.com/PeppeColi/peppec/compare/v1.14.0...v1.14.1
[1.14.0]: https://github.com/PeppeColi/peppec/compare/v1.13.3...v1.14.0
[1.13.3]: https://github.com/PeppeColi/peppec/compare/v1.13.2...v1.13.3
[1.13.2]: https://github.com/PeppeColi/peppec/compare/v1.13.1...v1.13.2
[1.13.1]: https://github.com/PeppeColi/peppec/compare/v1.13.0...v1.13.1
[1.13.0]: https://github.com/PeppeColi/peppec/compare/v1.12.0...v1.13.0
[1.12.0]: https://github.com/PeppeColi/peppec/compare/v1.11.0...v1.12.0
[1.11.0]: https://github.com/PeppeColi/peppec/compare/v1.10.2...v1.11.0
[1.10.2]: https://github.com/PeppeColi/peppec/compare/v1.10.1...v1.10.2
[1.10.1]: https://github.com/PeppeColi/peppec/compare/v1.10.0...v1.10.1
[1.10.0]: https://github.com/PeppeColi/peppec/compare/v1.9.0...v1.10.0
[1.9.0]: https://github.com/PeppeColi/peppec/compare/v1.8.0...v1.9.0
[1.8.0]: https://github.com/PeppeColi/peppec/compare/v1.7.0...v1.8.0
[1.7.0]: https://github.com/PeppeColi/peppec/compare/v1.6.1...v1.7.0
[1.6.1]: https://github.com/PeppeColi/peppec/compare/v1.6.0...v1.6.1
[1.6.0]: https://github.com/PeppeColi/peppec/compare/v1.5.0...v1.6.0
[1.5.0]: https://github.com/PeppeColi/peppec/compare/v1.4.0...v1.5.0
[1.4.0]: https://github.com/PeppeColi/peppec/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/PeppeColi/peppec/compare/v1.2.1...v1.3.0
[1.2.1]: https://github.com/PeppeColi/peppec/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/PeppeColi/peppec/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/PeppeColi/peppec/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/PeppeColi/peppec/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/PeppeColi/peppec/releases/tag/v1.0.0
