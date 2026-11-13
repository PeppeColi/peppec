<!-- Copy into CLAUDE.md at the root of the host repository: `peppec init` adds it and keeps it current -->
<!-- peppec:start · written by peppec init: change it in the engine (examples/claude-md-section.md), not here -->
## Issues built by PEPPEC

This repository is built by PEPPEC: an agent takes the issues labelled `ready`, one at a time,
and opens a pull request for each. It sees only the issue, the owner's comments on it and the
body of its parent issue, and it cannot run the program: "done" means the project's checks pass.
The triage role `ready-for-agent` is the label `ready`.

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
- Never label the specification itself `ready`: only its sub-issues get it.

### Issues for the agent

When you create an issue labelled `ready`:

- Make it a sub-issue of the specification and set its blockers with the native "blocked by"
  relationship, never as text in the body.
- Give it a size label: `size: S` for a small, mechanical change, `size: L` for one that crosses
  several parts of the code or needs design judgement, no size label otherwise.
- Write it so that it stands on its own: do not point to other issues, files of this session or
  links for anything the agent needs.
- Every acceptance criterion must be something an automated test can fail.
- End with an "Out of scope" section.
<!-- peppec:end -->
