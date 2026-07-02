# The miolimOS agent system

miolimOS can be operated together with **autonomous agents** — long-running
assistants that read a work inbox, do tasks (write code, do research, draft
documents, …) and report back, all through the same API a human would use.
The reference agent is `miolim_builder`, which maintains miolimOS itself.

This document explains the architecture so you can run, restrict or build
your own agents. **The agent system is optional**; miolimOS runs fine
without any agents.

## The three pieces

1. **`AgentActor`** — an agent is just an `Actor` (like a human user) of
   type `AgentActor`, with an **API token** instead of a password. It has
   the same capability-based permissions as any actor, so it can only touch
   what it is allowed to.
2. **The Operations API** (`/api/v1/...`) — a token-authenticated REST API
   covering tasks, knowledge items, sources, topics, communications,
   awaitings, inbox items, comments, attachments, relations and research
   jobs, plus a **heartbeat** endpoint. This is the *only* surface an agent
   uses; there is no special "agent backdoor".
3. **A runner** — the process that actually thinks and acts. The reference
   runner is **[Claude Code](https://claude.com/claude-code) in a `tmux`
   session**, which miolimOS **pokes event-driven** — the moment there is
   work for the agent (a task published or assigned to it, a reply, an
   @-mention, or the manual *"Trigger inbox run"* button), not on a fixed
   schedule. But the runner is interchangeable: anything that can send HTTP
   requests with a bearer token can be an agent (a script, a different LLM
   harness, a webhook consumer).

## The inbox / heartbeat loop

Agents work on a simple polling protocol:

```
loop:
  POST /api/v1/heartbeat        # marks the agent "alive" (last_seen_at)
                                # and returns { pending_trigger, open_tasks, ... }
  if pending_trigger or open_tasks > 0:
      … claim work, do it, comment, mark done …
```

- `pending_trigger` is set when someone presses **"Trigger inbox run"** in
  the UI (or assigns the agent work). The heartbeat reports it *before*
  stamping `last_seen_at`, so a trigger is never lost.
- `GET /api/v1/heartbeat` returns the status of all agents (`last_seen_at`,
  pending triggers) — useful for the dashboard or an external watchdog cron
  that alerts you if an agent goes silent.

When work appears, miolimOS pokes the runner: it sends the inbox-check prompt
straight into the agent's tmux session (`tmux send-keys`) so the agent reacts
immediately, then runs one iteration of the loop and goes idle until the next
poke. **This is event-driven, not a periodic cron job** — the agent is woken
exactly when there is something to do (and a short debounce coalesces a burst
of triggers into a single run). miolimOS only needs to know *which* tmux
session and prompt belong to the agent; that mapping lives in a single
crontab line (see below) that is kept **commented out** — it is a registry
entry the app reads, never an active cron tick.

## Setting up an agent

Create an `AgentActor` under **Settings → Agents → New agent**. On the
agent's page miolimOS generates ready-to-paste setup commands for the
reference runner:

1. Write the agent's **workflow/memory file** (its standing instructions).
2. Add an index line so the runner discovers it.
3. *(Optional)* a **restricted permission block** — read/research only
   (e.g. for a researcher/auditor agent that must not write to the repo).
4. Start the **tmux session** (`cd <app root> && claude`).
5. Add the **crontab registry line** — a *commented-out* marker (it carries
   the `(id=<id>)` tag, tmux session and prompt that miolimOS reads to poke
   the agent). It is **not** an active cron tick; nothing is scheduled.

All paths in those commands are derived from the deployment (`Rails.root`,
the configured host), so they are correct for any installation — not just
the maintainer's machine.

## Permissions

When an agent is created it receives default capabilities
(`read`/`create`/`update`) on the core resource types
(`Task`, `KnowledgeItem`, `Source`, `Topic`, `Communication`, `Awaiting`,
`InboxItem`). `delete` is opt-in. For a read-only agent, grant only `read`
(and use the restricted runner permission block so it also cannot touch the
filesystem/git).

Tokens can be **rotated** from the agent's settings page (invalidates the old
token; running sessions must be restarted with the new one).

## Building your own runner

You do not need Claude Code or tmux. A minimal runner is:

```bash
TOKEN=…   # the agent's API token
BASE=https://your-host/api/v1
while true; do
  state=$(curl -s -X POST "$BASE/heartbeat" -H "Authorization: Bearer $TOKEN")
  # if state shows pending_trigger / open work: fetch tasks, act, comment, PATCH status
  sleep 60
done
```

Everything an agent can do is expressed as ordinary API calls — list/claim
tasks, post comments, create knowledge items, mark work done — so any
language or LLM harness can drive it.

## Security notes

- Agent tokens are full API credentials — treat them like passwords; rotate
  if leaked.
- Scope agents tightly with capabilities; prefer read-only agents where
  possible, plus the restricted filesystem/git permission block for the
  runner.
- The Operations API enforces the same per-resource authorization as the web
  UI; an agent cannot exceed its capabilities.
