# Planning work for the agents

PEPPEC builds one issue at a time. This page explains how to prepare a whole feature as a group of issues it can build in order, and how to produce those issues with a planning session on your computer.

## What an issue needs

- **The `ready` label.** Nothing else starts an issue.
- **A size.** `size: S` for a small, mechanical change, `size: L` for one that crosses several parts of the code or needs design judgement; no label means M. The size picks the model.
- **To stand on its own.** The agent sees the issue, your comments and, for a sub-issue, the body of its parent. It cannot open other issues or links. Write what the issue needs in the issue.
- **Behaviour, not files.** Describe what must work and the names or shapes that matter. Paths and line numbers are out of date after the first merge.
- **Acceptance criteria a check can fail.** The agent does not run the program: "done" means the check commands pass. A criterion nobody can turn into a test is not verified by anyone.
- **What is out of scope**, under a heading named "Out of scope", so the agent does not build the neighbouring issue too. That section is copied into the pull request, so the reviewer does not ask for it either.

A good slice is the smallest change you could show working by itself. Smaller than that, the fixed cost of every issue (pull request, checks, review rounds) outweighs the work.

## A feature as a group of issues

1. **The specification is the parent issue.** Write it yourself: the problem, the solution, the decisions already taken, what is out of scope. It does not get the `ready` label.
2. **Each slice is a sub-issue** of the specification, labelled `ready` and with its size. The agent receives the specification as background and builds only its own slice.
3. **Order comes from "blocked by".** Mark each issue as blocked by the ones it needs: an issue starts only when its blockers are closed. Create them all at once; the queue sorts itself out.

```bash
gh issue create --parent <SPEC> --label ready --label "size: S" --title "..." --body "..."
gh issue edit <ISSUE> --add-blocked-by <BLOCKER>
```

4. **Collect the feature on a base branch.** With [a base branch other than `main`](setup.md#a-base-branch-other-than-main) the slices are merged into it, and `main` gets the feature only when it is complete.
5. **Try it when you are told.** When the last sub-issue is closed you get a Telegram message. Try the feature on the base branch; what does not work becomes a new sub-issue of the same specification, and you get the message again when those are closed too.
6. **Bring it to `main`** with a pull request merged with a merge commit, and close the specification.

To have the feature checked end to end by the machine as well, write the scenarios in the specification while planning, in given/when/then form, and make the last sub-issue "automate these scenarios", blocked by all the others. The agent then translates scenarios you wrote instead of inventing its own exam, and they run with the checks from then on.

Keep a feature to a handful of issues, and plan the next one after seeing the first built: issues written long before they run describe code that no longer exists.

## Producing the issues with a planning session

Any way of creating issues works. One that fits well is the set of skills in [mattpocock/skills](https://github.com/mattpocock/skills), run in Claude Code on your computer:

| Step | Skill | Result |
| --- | --- | --- |
| Decide | `/grill-with-docs`, or `/wayfinder` when the work does not fit in one session | The decisions, taken with you |
| Write down | `/to-spec` | The specification, as an issue |
| Slice | `/to-tickets` | The sub-issues, with their "blocked by" links |
| Build | PEPPEC, in place of `/implement` | One pull request per issue |

Their setup skill writes `docs/agents/issue-tracker.md` and `docs/agents/triage-labels.md` in your repository, and the other skills read them every time. Two edits make them produce issues PEPPEC accepts.

In `docs/agents/triage-labels.md`, map the label for work an agent can take to `ready`:

```markdown
| `ready-for-agent`          | `ready`              | Fully specified, ready for an AFK agent  |
```

At the end of `docs/agents/issue-tracker.md`, add:

```markdown
## Issues built by PEPPEC

Issues labelled `ready` are built by an agent that sees only the issue itself, the owner's
comments on it and the body of its parent issue. When you create one:

- Make it a sub-issue of the specification and set its blockers with the native
  "blocked by" relationship, never as text in the body.
- Give it a size label: `size: S` for a small, mechanical change, `size: L` for one that
  crosses several parts of the code or needs design judgement, no size label otherwise.
- Write it so that it stands on its own: do not point to other issues, files of this
  session or links for anything the agent needs.
- Every acceptance criterion must be something an automated test can fail: the agent
  cannot run the program.
- End with an "Out of scope" section.
- Do not label the specification itself `ready`.
```

The wording of those two files belongs to that project and may change: check them after running its setup skill.
