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

4. **Collect the feature on a base branch.** With [a base branch other than `main`](setup.md#a-base-branch-other-than-main) the work units are merged into it, and `main` gets the feature only when it is complete. With [feature branches](setup.md#feature-branches) each specification gets its own branch first, and reaches the base branch through a pull request you merge after trying it.
5. **Try it when you are told.** When the last sub-issue is closed you get a Telegram message. Try the feature on the base branch (or on its feature branch); what does not work becomes a new sub-issue of the same specification, and you get the message again when those are closed too. The message has a **Report a problem** button (the dashboard has the same, under "Ready to try"): write what does not work in one sentence and the bot opens that sub-issue for you, labelled `ready` and `size: S`. The agent receives the specification with it, so it sees your scenarios. For another size, change the label on GitHub before the issue starts.
6. **Bring it to `main`** with a pull request merged with a merge commit, and close the specification. This merge is yours, always, in either merge mode: merging the base branch into `main` is how you declare that the feature passed its end-to-end test. PEPPEC never opens or merges that pull request.

To have the feature checked end to end by the machine as well, write the scenarios in the specification while planning, in given/when/then form, and make the last sub-issue "automate these scenarios", blocked by all the others. The agent then translates scenarios you wrote instead of inventing its own exam, and they run with the checks from then on.

Keep a feature to a handful of issues, and plan the next one after seeing the first built: issues written long before they run describe code that no longer exists.

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

Earlier versions of this page asked you to add an "Issues built by PEPPEC" section at the end of `docs/agents/issue-tracker.md`. The section in `CLAUDE.md` replaces it: delete it, so the two cannot disagree.
