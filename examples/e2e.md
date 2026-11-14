<!-- Copy to docs/agents/e2e.md in the host repository: `peppec init` creates it when missing, then it is yours -->
# End-to-end tests

How this repository writes and runs its end-to-end tests. Planning sessions read it when a
specification decides whether a feature needs new ones (the "End-to-end" section, see the PEPPEC
section of CLAUDE.md); the agent reads it when a work unit writes them.

When they run: on the pull request of a finished feature into the base branch. The tests of the
feature (`PEPPEC_E2E_FEATURE`, skipped when its specification says `None`) and the whole suite
(`PEPPEC_E2E_ALL`). Not on the pull request into `main`.

## Kind

To be decided: none, command line, HTTP API, browser.

## Tool

To be decided.

## How the tests of one feature are selected

To be decided: a tag, a folder or a name with the number of the specification.

## How the application is started for them

To be decided.
