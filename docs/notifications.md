# Notifications

Every message starts with the repository it comes from, as in `[owner/name]`. Only the messages that need you make the phone ring (🔔); the others arrive silently (🔕), without sound or vibration, and stay in the chat as a trace. With the [dashboard](architecture.md#dashboard) open in a browser, the 🔔 messages can also appear as browser notifications.

| Message | What to do | Sound |
| --- | --- | --- |
| Queue stopped on #N (no CI result, checks still failing, no CodeRabbit review, review not passed, time budget used up, branch not valid) | Fix it, then press Unblock or Hint | 🔔 |
| The agent is blocked on #N (agent error, no changes, protected files changed, conflict markers left, changes not applicable) | Press Unblock or Hint | 🔔 |
| #N needs another feature, but names none of the open ones, or its feature branch already holds work ([smart queue](architecture.md#smart-queue)) | Add the blocker or bring that code in, then press Unblock | 🔔 |
| Claude token rejected | Run `claude setup-token` and update the secret | 🔔 |
| Question on #N | Reply, or press Accept for the recommended answer | 🔔 |
| PR #N is ready to merge (manual mode), with "only minor findings left after N review rounds" when the last round passed on [minor findings](architecture.md#checks-review-and-limits) | Merge it | 🔔 |
| The feature of #N is ready to be tried | Try it, merge it, or press Report a problem | 🔔 |
| The base branch does not exist | Create it again | 🔔 |
| #N has `ready-for-agent` but not `ready` | Run `peppec doctor`, then label it `ready` | 🔔 |
| #N has `ready` but is not a work unit | Move `ready` to its sub-issues | 🔔 |
| #N has `ready` but was not written by you (the label is removed) | Copy what you want built into an issue of your own | 🔔 |
| The end-to-end tests still fail after the hotfixes, or gave no result | Fix them by hand, or press Report a problem | 🔔 |
| The base branch could not be brought into a feature | Merge it by hand | 🔔 |
| The decide step failed | Open the run | 🔔 |
| Daily summary with a token about to expire | Renew the token | 🔔 |
| Merged PR #N (automatic mode), with "only minor findings left after N review rounds" when the last round passed on minor findings | Nothing | 🔕 |
| Claude quota exhausted: will retry automatically | Nothing | 🔕 |
| The agent changed nothing and answered CodeRabbit | Nothing | 🔕 |
| #N waits for #M, whose code it needs (smart queue): the queue goes on | Nothing | 🔕 |
| The base branch is back: the queue goes on | Nothing | 🔕 |
| The end-to-end tests failed: #M will fix them | Nothing | 🔕 |
| The base branch and a feature conflict: #M will resolve it | Nothing | 🔕 |
| The base branch changed and is merged into a feature | Try its latest version, if you are trying it | 🔕 |
| Dashboard: … (the trace of what you did on the dashboard) | Nothing | 🔕 |
| Daily summary | Read it; not sent on a day with nothing merged, blocked, asked or in queue | 🔕 |

The bot's answers to your commands (`/status`, `/pause`, …) are normal messages.
