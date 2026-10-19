---
name: folio-bokforing
description: Complete (bokføre) Folio bank events after the user explicitly says yes — mark events complete or undo it, set categories and receipts without the folio-kladd guards, plus a write escape hatch. Opt-in; install only if you want the agent to book in Folio. Never moves money.
---

# Folio bokføring (opt-in)

Completing an event marks it as booked. With Folio's Fiken integration on, it is also booked in Fiken, where booked entries can't be deleted.

**The rule:** run a command from this skill only after the user has said yes to that exact event in the same conversation. Show them the event first (date, amount, merchant, category, receipt) using the `folio` skill. Never complete events as part of a chain of other steps.

**What locks this, honestly:** nothing deterministic. Every command requires `--confirm`, but you can type that flag yourself. The real check is the user's agent tool asking before it runs a command containing `--confirm`. If the user hasn't set that up, recommend completing events in Folio instead.

**Money stays out of reach regardless:** `raw` refuses writes to `/payments`, `/salary` and `/integration`, and a payment created through Folio's API can't be sent without a person signing it in Folio.

```bash
F=~/.claude/skills/folio-bokforing/scripts/folio-bokforing.sh
bash "$F" complete <eventId> --confirm
bash "$F" uncomplete <eventId> --confirm
bash "$F" patch-event <eventId> --category <id> --confirm   # no kladd guards
bash "$F" attach <eventId> <file> --confirm                 # no kladd guards
bash "$F" raw <METHOD> <path> [json] --confirm
```

Setup: same `FOLIO_WRITE_KEY` as `folio-kladd`. Every call is logged to `~/.local/state/fiken-folio-skills/audit.jsonl`.

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Not affiliated with Folio.
