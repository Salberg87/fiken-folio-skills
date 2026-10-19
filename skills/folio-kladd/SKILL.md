---
name: folio-kladd
description: Prepare bookkeeping on Folio (folio.no) bank events without completing them — set purpose, note, participants and ledger category, and upload receipts (kvittering). Use when the user wants to categorize a Folio transaction, add a receipt or note to it, or prepare a month's Folio events. Never completes (bokfører) an event and never moves money.
---

# Folio kladd (prepare)

Fills in Folio events so the user can complete them in Folio. Uses `scripts/folio-kladd.sh` and `$FOLIO_WRITE_KEY` (a key without payment access). Read events with the `folio` skill.

**Why some writes are refused.** Folio completes an event by itself once it has both a receipt and a ledger category (and whatever else the category requires). With Folio's Fiken integration on, that books it in Fiken. Completing is **bokføring**, so the script reads the event first and refuses:

- any change to a completed event
- a category on an event that has a receipt
- a receipt on an event that has a category
- any change to an event that already has both

So per event, do **one** of: category (+ purpose/note), *or* receipt (+ purpose/note). The step that joins them is the user's, in Folio. When refused, tell the user what's left to do in Folio; don't work around it.

**Setup (one-time):**

```bash
export FOLIO_WRITE_KEY=...               # https://app.folio.no/til/api-tilgang, no payment access
# or: export FOLIO_ENV=~/.config/folio/.env
```

Every write is logged to `~/.local/state/fiken-folio-skills/audit.jsonl` (override with `FIKEN_FOLIO_AUDIT_LOG`) and is never retried automatically.

## Workflow

```bash
F=~/.claude/skills/folio-kladd/scripts/folio-kladd.sh
R=~/.claude/skills/folio/scripts/folio.sh

bash "$R" events 2026-05-01 2026-05-31                 # find events with complete:false
bash "$R" category <ledgerCategoryId>                  # what does the category require?
bash "$F" patch-event <eventId> --purpose "Kundemøte" --participants "Navn" --category <ledgerCategoryId>
bash "$F" attach <eventId> ~/Downloads/kvittering.pdf  # only on events without a category
```

**Sharp edges (learned in production):**

- **With Folio's Fiken integration on, a completed event is booked in Fiken.** Don't also make a Fiken purchase draft for the same card charge, or it's booked twice. Fiken drafts are for things Folio never sees, like expenses paid with a private card (utlegg).
- **Refunds (incoming events) need an incoming category.** An expense category has `isIncoming: false`; a refund set to it showed `complete: true` but never synced to Fiken. Use a category with `isIncoming: true`. There is no list endpoint for categories — find ids on past events (`bash "$R" events <range> | jq '.events[].ledgerCategory'`) and inspect them with `bash "$R" category <id>`.

Full API reference: `REFERENCE.md` in the `folio` skill.

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Not affiliated with Folio.
