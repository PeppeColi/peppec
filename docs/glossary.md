# Glossary

The words PEPPEC uses for its own parts and for the life of an issue, from the label `ready` to the merge. Use them in code, comments, documentation, issues and pull requests of this repository, and do not invent synonyms.

This glossary is PEPPEC's, not a host's. A host repository may have its own `GLOSSARY.md`: that file describes the domain of the host's application, and the agent reads it when it builds. Never copy these terms into it, and never mix the two: "app" in a host's glossary is likely the product being built, while here it is the GitHub App.

## Repositories and people

**Engine**
This repository: the reusable workflows, the scripts, the presets, the bot and the command line. Hosts call it at a moving tag (`v2`).
_Avoid_: framework, core

**Host**
A repository that uses PEPPEC: its issues are built, it calls the engine's workflows and holds the configuration, the variables and the secrets.
_Avoid_: client repo, target, project (alone)

**Owner**
The person whose GitHub account owns the host. Only the owner and the app give the agent instructions: issues and comments of anyone else are ignored.
_Avoid_: user (ambiguous with the users of the host's application), admin, maintainer

**App**
The owner's GitHub App, installed on the host. It applies labels, merges, writes the hidden markers and acts for the bot. Markers and comments are trusted only when the app wrote them.
_Avoid_: bot (the bot is a separate program that acts as the app), GitHub integration

**Agent**
Claude Code running in the `agent` job on a task. It writes code and replies to reviews; it never commits, pushes or comments: the workflow does.
_Avoid_: bot, worker, AI

**Bot**
The Telegram bot, a long-running program on a machine of the owner (a Raspberry Pi is enough). It forwards notifications and questions, takes commands and answers, serves the dashboard, and acts on GitHub as the app.
_Avoid_: agent, assistant

**Dashboard**
The web page the bot serves for a phone: the state of every host, and the same actions as the bot.
_Avoid_: UI, panel (the control panel is something else)

## Planning

**Specification**
A parent issue describing a whole feature: problem, solution, decisions, scenarios, out of scope. It never gets `ready`; its work units do. Its body reaches the agent as background, in `.agent/spec.md`.
_Avoid_: spec issue, epic, PRD (Pocock's skills write it; here it is the specification)

**Work unit**
An issue the agent builds in one pull request: labelled `ready`, usually a sub-issue of a specification. The smallest change that can be shown working by itself.
_Avoid_: slice, ticket, task (the task is what the agent receives), story

**Sync work unit**
A work unit the workflow opens when the base branch conflicts with a finished feature: the workflow makes the merge with the conflict markers, the agent resolves them.

**Hotfix work unit**
A work unit of size L the workflow opens when the end-to-end tests of a feature fail, with the end of the log. Report a problem opens work units of size S that are not hotfixes.

**Size**
The label `size: S` or `size: L` on a work unit, or no label for M. It picks the model.
_Avoid_: complexity, difficulty, priority

**Scenarios**
The behaviours of a specification in given/when/then form, under a heading named "Scenarios".

**Wayfinder map**
A planning map charted with the wayfinder skill on the owner's computer, with `wayfinder:` labels. It plans and never carries code: the queue skips its issues.

## The queue

**Queue**
The open issues labelled `ready`, oldest first, minus those blocked by an open issue. One is worked on at a time.
_Avoid_: backlog, pipeline

**`ready`**
The label that puts an issue in the queue. Pocock's triage role `ready-for-agent` maps to it.
_Avoid_: `ready-for-agent`, approved, todo

**Move**
The one thing a run of the workflow decides to do (start an issue, fix the checks, ask for a review, merge, block…), after reading the state back from GitHub. Each run makes at most one.
_Avoid_: step, action (an action is a GitHub Action)

**Task**
What the agent receives for a move: the issue, the owner's and the app's comments, the specification, the instructions. Written by the `prepare` job.
_Avoid_: prompt (the prompt is one part of it), job

**Control panel**
A pinned issue of the host whose labels hold the state of the whole queue: always one `merge:` and one `schedule:` label, and `paused`, `base missing`, `no preset` when they apply.
_Avoid_: settings issue, config, dashboard

**Pause**
The `paused` label on the control panel: no new issue starts; the one in progress goes on to its merge. Only Resume lifts it.
_Avoid_: stop, freeze

**Merge mode**
Manual (the owner merges the pull requests of the agent branches, label `merge: manual`, default) or automatic (the workflow merges them as the app once the review passes, label `merge: automatic`). Feature branches and the base branch are always merged by the owner.
_Avoid_: auto-merge (GitHub's own feature, not used)

**Schedule**
`always` (new issues start at any hour, label `schedule: always`, default) or `nightly` (new issues start only in the work window, label `schedule: nightly`).

**Ping**
The bot starting the agent workflow every `PING_MINUTES` on a repository with something to move, and the summary workflow once a day at `SUMMARY_HOUR`. GitHub's cron is not used.
_Avoid_: heartbeat, wake-up

**Work window**
The hours between `PEPPEC_WORK_START_HOUR` and `PEPPEC_WORK_END_HOUR` in which new issues start on the nightly schedule.

## Review and limits

**Checks**
The commands of the preset (or of `check` in `.github/peppec.yml`) that CI runs and the agent must make pass. "Done" means they pass.
_Avoid_: tests (only part of the checks), CI (CI runs the checks)

**Review round**
One pass of CodeRabbit's review and the agent's answer to it, counted by the `review N` labels and capped by `PEPPEC_MAX_REVIEW_ROUNDS`.
_Avoid_: iteration, attempt (an attempt is one try at making the checks pass, `ci N`)

**Carried approval**
CodeRabbit's previous approval standing for a new commit that holds nothing it reviews (a lockfile, a deleted file).

**Full review**
CodeRabbit reviewing the whole pull request again (`@coderabbitai full review`), asked once for a commit that got no verdict and has no approval to carry over.

**Question**
What the agent asks when an issue is unclear, with the answer it recommends. The issue gets `question open`; the owner replies or presses Accept.
_Avoid_: clarification, blocker

**Blocked**
An issue the queue stopped on: a limit passed, an agent error, a protected path changed. The owner presses Unblock, or Hint with a text. Not to be confused with GitHub's "blocked by" relationship, which only orders the queue.
_Avoid_: stuck, failed

**Hint**
A comment of the owner, through the bot or the dashboard, that unblocks an issue and is read by the agent at the next run.

**`needs human`**
The label that stops the queue on an issue and its pull request until the owner acts.

**Protected paths**
Files the agent may not change: the engine always protects `.github`, `.claude`, `CLAUDE.md`, `AGENTS.md`, `docs/agents`, `docs/adr`; the preset and the configuration add more. A change to them blocks the issue.

**Never commit**
Paths the workflow leaves out of every commit (dependencies, build output, caches), listed by the preset in `never_commit`.

**Marker**
A hidden comment `<!-- peppec:KEY=VALUE -->` written by the app, where the workflow keeps its state: minutes worked, branch of an issue, results already judged.
_Avoid_: tag, metadata

## Branches

**Base branch**
The branch work units are merged into: `main`, or the branch in `PEPPEC_BASE_BRANCH` (usually `dev`). The configuration is always read from it.
_Avoid_: default branch (GitHub's default branch may differ), target branch

**Feature branch**
With `PEPPEC_BRANCHES`, the integration branch of one specification: its work units are merged into it, and it reaches the base branch only through a pull request the owner merges.
_Avoid_: topic branch, epic branch

**Agent branch**
The branch of one issue: `agent/issue-N`, or a name from the `work`, `hotfix`, `sync` or `single` templates of `PEPPEC_BRANCHES`. The workflow merges and deletes only these.

**Ready to be tried**
A feature whose work units are all merged (and, with feature branches, whose base branch came in and end-to-end tests passed). The owner gets a message with Report a problem.
_Avoid_: done, released

**End-to-end tests**
Tests run only on the pull request of a feature: `PEPPEC_E2E_FEATURE` for the feature's own, `PEPPEC_E2E_ALL` for the whole suite.

## Setup

**Preset**
A directory of the engine with everything that depends on the language: setup action, checks, tools of the agent, protected paths. `none` is the placeholder for a language not chosen yet.
_Avoid_: template, stack, profile

**Extra setup**
A setup action of the host, named by `extra_setup`, run after the preset's for services and system packages.

**Configuration**
`.github/peppec.yml` of the host, read from the base branch: preset, options, checks, models.
_Avoid_: settings (the variables are separate)

## From Pocock's skills

Planning sessions use Matt Pocock's skills, whose names differ:

| Pocock | PEPPEC |
| --- | --- |
| PRD, spec | Specification |
| Slice, ticket, issue from `/to-tickets` | Work unit |
| `ready-for-agent` | `ready` |
| `GLOSSARY.md` of the repository | The host's domain glossary, not this file |
