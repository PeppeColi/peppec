<!-- Copy into CLAUDE.md at the root of the host repository: `peppec init` adds it and keeps it current -->
<!-- peppec:start · written by peppec init: change it in the engine (examples/claude-md-section.md), not here -->
## Issues built by PEPPEC

This repository is built by PEPPEC: an agent takes the issues labelled `ready`, one at a time,
and opens a pull request for each. It sees only the issue, the owner's comments on it and the
body of its parent issue, and it cannot run the program: "done" means the project's checks pass.
The triage role `ready-for-agent` is the label `ready`.
The queue builds only issues written by the owner or the app: never put `ready` on an issue
someone else wrote. Write a new issue with what should be built, and label that one.
Terms such as work unit, specification, `ready` and size are PEPPEC's, defined in
https://github.com/PeppeColi/peppec/blob/v2/docs/glossary.md. Never add them to this
repository's GLOSSARY.md: that file is the domain of this application.

### Where planning commits go

When the repository has a base branch other than `main` (the `PEPPEC_BASE_BRANCH` variable,
usually `dev`), commit and push what a planning session writes (GLOSSARY.md, decision records,
files under `docs/`) to that branch, never to `main`. The agent starts from the base branch, and
`main` gets everything from it with the owner's release pull request. If the clone is on `main`,
switch to the base branch before the first commit. Push these files before the work units get
`ready`: the agent sees only what is on the base branch.

### Wayfinder maps

When you chart a wayfinder map, write these constraints in its Notes, so that every session on
the map reads them:

- The map plans; it never carries execution. No production code in wayfinder sessions: PEPPEC
  builds the code later, one issue at a time.
- The destination is a specification for `/to-spec`, with its scenarios in given/when/then form.
- Every behaviour the map decides must be checkable by an automated test: PEPPEC's agent cannot
  run the program.
- No issue of the map ever gets the `ready` label.

### Specifications

- Include the scenarios, in given/when/then form, under a heading named "Scenarios".
- If the repository has end-to-end tests per feature (the `PEPPEC_E2E_FEATURE` variable), add a
  section named "End-to-end" that decides whether this feature needs new end-to-end tests. The
  unit tests of its work units may be enough: then write `None: unit tests cover it.` and why,
  in one line. Otherwise list the scenarios the end-to-end tests must cover. Without the section
  the tests are required. How this repository writes and runs them is in
  `docs/agents/e2e.md`.
- Never label the specification itself `ready`: only its work units get it.

### Work units

A work unit is an issue the agent builds in one pull request: a sub-issue of a specification,
labelled `ready`. When you create one:

- Set its blockers with the native "blocked by" relationship, never as text in the body.
- Create all the work units first and set every blocker. Then check each one on the tracker
  (title, body, size label, blockers) and only then add `ready`, from the oldest issue to the
  newest: a work unit labelled before its blockers are set can start too early.
- When it needs the code of another specification that is not on the base branch yet (it is
  still on that specification's feature branch, `PEPPEC_BRANCHES`), block it by that
  specification, never by its work units: the specification is closed only when its feature
  reaches the base branch.
- Give it a size label: `size: S` for a small, mechanical change, `size: L` for one that crosses
  several parts of the code or needs design judgement, no size label otherwise.
- Write it so that it stands on its own: do not point to other issues, files of this session or
  links for anything the agent needs.
- Every acceptance criterion must be something an automated test can fail.
- End with an "Out of scope" section.

When the specification lists end-to-end scenarios, add one more work unit, `size: L`, blocked
by all the others: "Write the end-to-end tests of #N", where N is the specification. Tag or name
each test with N, so that the command in `PEPPEC_E2E_FEATURE` selects them.
<!-- peppec:end -->
