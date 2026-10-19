---
name: fiken-bokforing
description: Post Fiken drafts to the ledger (bokføring) after the user explicitly says yes, plus a write escape hatch for the Fiken API. Opt-in; install only if you want the agent to book in Fiken. Use when the user asks to bokføre/post a specific Fiken draft and has confirmed it in this conversation.
---

# Fiken bokføring (opt-in)

Posting a draft turns it into a booked purchase. **That is irreversible** — booked entries can't be deleted, only corrected with a credit note in Fiken.

**The rule:** run a command from this skill only after the user has said yes to that exact draft in the same conversation. Show them the draft first (supplier, date, amount in NOK, account, VAT) using the `fiken` skill. Never post as part of a chain of other steps.

**What locks this, honestly:** nothing deterministic. Every command requires `--confirm`, but you can type that flag yourself. The real check is the user's agent tool asking before it runs a command containing `--confirm`. If the user hasn't set that up, recommend posting in Fiken instead.

**Setup:** same `FIKEN_WRITE_TOKEN` + `FIKEN_COMPANY_SLUG` as `fiken-kladd`.

```bash
F=~/.claude/skills/fiken-bokforing/scripts/fiken-bokforing.sh
bash "$F" post-draft <draftId> --confirm
bash "$F" raw <METHOD> <path> [json] --confirm   # any other write; GET is in the fiken skill
```

Every call is logged to `~/.local/state/fiken-folio-skills/audit.jsonl` and the result is read back. A post is never retried automatically: after a timeout or 5xx, check `fiken purchases` before trying again.

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Not affiliated with Fiken.
