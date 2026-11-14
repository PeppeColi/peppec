# none

The placeholder preset, for a project whose language is not chosen yet. PEPPEC installs and its
workflows run, but the queue stays idle.

| | |
| --- | --- |
| Setup | Nothing |
| Checks | None: `true`, so CI passes and your own commits of plans and documents can merge |
| Agent | Never runs: the queue starts no issue and no fix round while the preset is `none` |

## Use it

```yaml
# .github/peppec.yml
preset: none
```

`peppec init` proposes it when the repository has neither `Cargo.toml` nor `composer.json`.

## What the queue does

- Issues labelled `ready` wait. Each run tells you once, on Telegram, about the ones not reported
  yet, in a single message.
- `/status` and the dashboard say that no preset is chosen.
- Merges, closures and messages that need no agent go on as usual.

## Choosing the language

Run `peppec init --preset <name>` (for example `rust-v1`): it rewrites the `preset:` line of
`.github/peppec.yml` after asking. Then the queue builds the ready issues with the new preset. The
project must pass the new preset's checks: the first issue can create the skeleton (for example
`cargo init`), see [docs/setup.md](../../docs/setup.md#changing-the-preset).
