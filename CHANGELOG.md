# Changelog

All notable changes to the PEPPEC engine are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the engine
follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html). Hosts call the moving tag `v1`,
which always points to the latest 1.x release. Versions up to 1.25.0 were rebuilt from the git
history when this file was created.

## [Unreleased]

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

[Unreleased]: https://github.com/PeppeColi/peppec/compare/v1.31.0...HEAD
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
