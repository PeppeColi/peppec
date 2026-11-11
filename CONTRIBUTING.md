# Contributing

Presets for new languages and toolchains are the most useful contribution. This page explains what a preset is and the rules it must follow.

## Why the rules are strict

A preset runs inside other people's repositories, in the same job that later uses their GitHub tokens. A preset that does more than prepare the environment, or that depends on something that can change after the review, puts every adopter at risk. The rules below exist for that reason, and most of them are checked automatically on every pull request.

## Anatomy of a preset

```text
presets/<name>-v<N>/
├── action.yml     # composite action: toolchain, dependencies, cache; declares the "options" input
├── preset.yml     # defaults used by CI and by the agent
├── README.md      # what it installs, what it checks, its limits
└── fixture/       # minimal project the preset is tested on
```

`preset.yml` fields:

| Field | Meaning |
| --- | --- |
| `description` | One line describing the kind of project; it goes in the agent's prompt |
| `check` | The commands that must all pass. CI runs them as they are; the agent runs them before finishing |
| `notes` | Optional extra rules for the agent, one per line of the prompt |
| `allowed_tools` | Tools the agent may use besides reading and editing files |
| `disallowed_tools` | Exceptions to the above: at least running and publishing the project |
| `protected_paths` | Files that define how the code is checked. The agent's changes to them are refused |
| `never_commit` | Paths the workflow never commits, even if the project's `.gitignore` misses them: installed dependencies, build output, caches |

`action.yml` must declare an `options` input: it receives, as a JSON string, the `options` mapping of the host's configuration. Read it through an environment variable, never by writing `${{ inputs.options }}` inside a script. Document the options in the README.

Use [`presets/rust-v1`](presets/rust-v1) and [`presets/php-v1`](presets/php-v1) as models.

## Rules

1. **Pin every action to a full commit SHA**, with the version in a comment. Tags can be moved after the review; a SHA cannot.
2. **Only prepare the environment.** No downloads piped to a shell, no network calls other than package registries, no background processes, no reads outside the project, no writes to `.github/`, `_ctl/`, `_preset/` or `.agent/`. No obfuscated commands.
3. **The check must be real.** It runs formatting, linting, build and tests, and fails when any of them fails. No `|| true`.
4. **Give the agent only the tools of the language.** No bare `Bash`, no shells, `curl`, `git`, `gh` or `docker`.
5. **Protect what defines the checks**: linter and formatter configuration, and the file where the check command is defined if it is a script of the project.
6. **Detect, do not multiply.** Read versions and package managers from the project's own files (`.nvmrc`, `composer.json`, lockfiles) instead of creating one preset per combination.
7. **Keep the fixture minimal**: a few lines of code and one test, no install scripts, no unusual dependencies.
8. **One preset per pull request**, touching only its own directory.
9. **Never break a published version.** `<name>-v1` keeps working as it is; an incompatible change is a new `<name>-v2` directory.

## Test it locally

`scripts/lint-presets.sh` checks rules 1, 3 and 4, the layout and the `options` input. It needs `yq` and `jq`:

```bash
bash scripts/lint-presets.sh
```

The `presets` workflow runs the same script on your pull request, then runs your setup and your check commands on your fixture.

## What the review looks at

The automatic checks leave two things to a human: reading the shell commands of `action.yml`, and judging whether the check commands are serious. Updates to an existing preset get the same attention as a new one, especially when a pinned SHA changes.

What a preset cannot guarantee is the behaviour of the dependencies a project installs: that stays with whoever adopts it.

## Other changes

Changes to the workflows, the scripts or the bot are welcome too. Open an issue first to discuss them: they affect every installation.
