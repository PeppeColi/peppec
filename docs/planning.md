# Planning work for the agents

PEPPEC builds one issue at a time. This page explains how to prepare a whole feature as a group of issues it can build in order, and how to produce those issues with a planning session on your computer.

## What an issue needs

- **The `ready` label.** Nothing else starts an issue.
- **A size.** `size: S` for a small, mechanical change, `size: L` for one that crosses several parts of the code or needs design judgement; no label means M. The size picks the model.
- **To stand on its own.** The agent sees the issue, your comments and, for a sub-issue, the body of its parent. It cannot open other issues or links. Write what the issue needs in the issue.
- **Behaviour, not files.** Describe what must work and the names or shapes that matter. Paths and line numbers are out of date after the first merge.
- **Acceptance criteria a check can fail.** The agent does not run the program: "done" means the check commands pass. A criterion nobody can turn into a test is not verified by anyone. The agent writes a failing test for each criterion before the code.
- **Where to test, when it matters.** Name the interface the tests should go through (a command, a public function, an HTTP endpoint), in the issue or in a "Testing decisions" section of the specification. Without it the agent tests through the public interface of the code it changes. If the repository has a `GLOSSARY.md`, the agent uses its terms.
- **What is out of scope**, under a heading named "Out of scope", so the agent does not build the neighbouring issue too. That section is copied into the pull request, so the reviewer does not ask for it either.

A good work unit, the issue the agent builds in one pull request, is the smallest change you could show working by itself. Smaller than that, the fixed cost of every issue (pull request, checks, review rounds) outweighs the work.

## A feature as a group of issues

1. **The specification is the parent issue.** Write it yourself: the problem, the solution, the decisions already taken, what is out of scope. It does not get the `ready` label. If it gets it by mistake once it has sub-issues, the queue skips it and tells you once on Telegram; a specification without sub-issues yet cannot be told apart from a work unit, and would be built in one run.
2. **Each work unit is a sub-issue** of the specification, labelled `ready` and with its size. The agent receives the specification as background and builds only its own work unit.
3. **Order comes from "blocked by".** Mark each issue as blocked by the ones it needs: an issue starts only when its blockers are closed. Create them all at once; the queue sorts itself out.

```bash
gh issue create --parent <SPEC> --label ready --label "size: S" --title "..." --body "..."
gh issue edit <ISSUE> --add-blocked-by <BLOCKER>
```

These options need `gh` 2.94 or later.

4. **Collect the feature on a base branch.** With [the base branch `dev`](setup.md#the-base-branch-dev) the work units are merged into it, and `main` gets the feature only when it is complete. With [feature branches](setup.md#feature-branches) each specification gets its own branch first, and reaches the base branch through a pull request you merge after trying it.
5. **Try it when you are told.** When the last sub-issue is closed you get a Telegram message. Try the feature on the base branch (or on its feature branch); what does not work becomes a new sub-issue of the same specification, and you get the message again when those are closed too. The message has a **Report a problem** button (the dashboard has the same, under "Ready to try"): write what does not work in one sentence and the bot opens that sub-issue for you, labelled `ready` and `size: S`. The agent receives the specification with it, so it sees your scenarios. For another size, change the label on GitHub before the issue starts.
6. **Bring it to `main`** with a pull request merged with a merge commit, and close the specification (with feature branches, merging the feature's pull request into the base branch closes it for you; `main` still gets the base branch from you). This merge is yours, always, in either merge mode: merging the base branch into `main` is how you declare that the feature passed its end-to-end test. PEPPEC never opens or merges that pull request.

Keep a feature to a handful of issues, and plan the next one after seeing the first built: issues written long before they run describe code that no longer exists.

## End-to-end tests

Every specification carries its scenarios, in given/when/then form, under a heading named "Scenarios": the PEPPEC section of `CLAUDE.md` asks for them. How they become tests depends on whether the repository runs end-to-end tests per feature.

### Without end-to-end tests per feature

This is the case when `PEPPEC_E2E_FEATURE` is not set, with or without feature branches.

- **Nothing runs them by itself.** The scenarios are what you try by hand when you are told the feature is ready.
- **To have them checked by the machine**, ask `/to-tickets` for one more sub-issue, "Automate the scenarios of #N", blocked by all the others. Nothing adds it for you.
- **The agent translates your scenarios** instead of inventing its own exam.
- **They become part of the checks.** The check commands run them on every pull request from then on, so they must be tests those commands run, and fast enough for CI.

### With end-to-end tests per feature

This is the case with [feature branches](setup.md#feature-branches) and `PEPPEC_E2E_FEATURE` set (see [End-to-end tests](setup.md#end-to-end-tests)). The tests run on the pull request of each finished feature into the base branch, not on every pull request.

- **The specification decides** whether the feature needs new ones, in a section named "End-to-end".
- **`None: unit tests cover it.`**, with the reason in one line: `ci / e2e_feature` is skipped for that feature.
- **Or the scenarios to cover:** `/to-tickets` adds the work unit that writes them, `size: L`, blocked by the others. Each test is tagged or named with the number of the specification, so the command in `PEPPEC_E2E_FEATURE` selects it.
- **Without the section they are required**, so a forgotten decision costs a hotfix rather than a gap.
- **`ci / e2e_all` runs either way**: a feature with no new tests can still break old ones.
- **`docs/agents/e2e.md`** says how this repository writes and runs them.

## Working on an existing codebase

Two sessions produce no issues but make every later one better. Run them on the base branch, and bring what they write (glossary, decision records) there too.

- **A glossary.** `/grill-with-docs` pointed at the repository compares what you say with the code, points out contradictions, and writes `GLOSSARY.md` term by term. Specifications and work units then use those words, and the agent is told to use them too.
- **A picture of the architecture.** `/improve-codebase-architecture` reads the commit history, looks at the code that changes most, and reports the shallow modules worth deepening, without touching the code. On an existing project it shows where tests have no good place to hook in, before an agent is asked to work there.

Then pick the way into the queue by the kind of work; every way ends with issues labelled `ready`:

| You have | Way | Tried with PEPPEC |
| --- | --- | --- |
| A feature that can be decided in one session | `/grill-with-docs` → `/to-spec` → `/to-tickets` | yes |
| A backlog of issues written by others | `/triage`, then a new issue of yours for each one to build: the queue builds only issues written by you or the app | no |
| A hard bug | the `diagnosing-bugs` skill | no |
| A large, unclear change: a rewrite, a migration, a new subsystem | `/wayfinder` → `/to-spec` → `/to-tickets` | no |
| Technical debt, refactoring | `/improve-codebase-architecture`, then the first way | no |

On existing code, prefer the test points that already exist when `/to-spec` asks for them, and let `/to-tickets` put any preparatory refactoring first.

## Producing the issues with a planning session

Any way of creating issues works. One that fits well is the set of skills in [mattpocock/skills](https://github.com/mattpocock/skills), run in Claude Code on your computer:

| Step | Skill | Result |
| --- | --- | --- |
| Decide | `/grill-with-docs`, or `/wayfinder` when the work does not fit in one session | The decisions, taken with you |
| Write down | `/to-spec` | The specification, as an issue |
| Split into work units | `/to-tickets` | The sub-issues, with their "blocked by" links |
| Build | PEPPEC, in place of `/implement` | One pull request per issue |

Two things make them produce issues PEPPEC accepts, and `peppec init` sets up both. Run their setup skill (`/setup-matt-pocock-skills`) first, then `init`; `peppec doctor` tells you when either is missing or out of date.

**A PEPPEC section in `CLAUDE.md`.** Every session on your computer reads `CLAUDE.md`, so the rules reach the planning skills without you repeating them: what an issue for the agent needs, scenarios in every specification, no `ready` label on the specification. It also tells `/wayfinder` what to write in the Notes of every map it charts: the map plans and never writes production code, its destination is a specification with given/when/then scenarios, every behaviour it decides must be checkable by a test, none of its issues gets `ready`. The queue skips any issue with a `wayfinder:` label even if it has `ready`, and a cleared map never shows under "Ready to try". Without those Notes a map can drift into building the feature itself, and PEPPEC would then build it a second time.

The section sits between a `<!-- peppec:start` line and a `<!-- peppec:end -->` line, outside the "Agent skills" block the setup skill rewrites, so running that skill again does not remove it. `init` adds it at the end of the file, creates the file if there is none (importing `AGENTS.md` when that is the file you have), and replaces the section when the engine's version changes, leaving the rest of the file alone. Do not edit it: your next `init` puts the engine's text back. To set it up by hand, copy [`examples/claude-md-section.md`](../examples/claude-md-section.md), without its first line, at the end of your `CLAUDE.md`.

**The `ready` label in `docs/agents/triage-labels.md`.** The skills apply the label written in this file for work an agent can take. `init` maps it to `ready`; by hand, change the row to:

```markdown
| `ready-for-agent`          | `ready`              | Fully specified, ready for an AFK agent  |
```

### When the skills change

The skills come as a Claude Code plugin, `mattpocock-skills`. Installed from the official marketplace it updates by itself, and the new version loads the next time Claude Code starts. PEPPEC relies on three of its behaviours: the `ready-for-agent` row of the label map, `/to-tickets` applying that label, and the `wayfinder:` labels. Three checks tell you when an update changes one of them:

- **When a session starts.** `init` adds a SessionStart hook to `.claude/settings.json` that runs `peppec skills --hook` (or `gh peppec skills --hook`). It says nothing while all is well; otherwise the session opens with a message such as "PEPPEC: mattpocock-skills 1.4.0 changed what PEPPEC relies on: /to-tickets no longer applies ready-for-agent…", before you write any issue. It needs `peppec` or the gh extension on your computer.
- **In the queue.** At every run the workflow looks for open issues labelled `ready-for-agent` but not `ready`, and sends one Telegram message for each: they would never be built.
- **In `peppec doctor`** and `peppec skills`, which show the installed version and the same checks.

If you prefer to change version only on purpose, install the plugin from its own marketplace pinned to a release, where automatic updates are off by default: `/plugin marketplace add mattpocock/skills#v1.3.2`, then install `mattpocock-skills` from it, and uninstall the copy from the official marketplace (the skills have the same names). To upgrade, add the marketplace again with the new tag, run `/setup-matt-pocock-skills`, then `peppec init`.
