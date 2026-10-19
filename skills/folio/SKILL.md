---
name: folio
description: Read the Folio business-bank API (folio.no) — accounts, balances, transactions, bookkeeping events, ledger categories, receipts and statement PDFs. Use when the user mentions Folio or their bedriftskonto, or asks to pull transactions, check a balance, look at events that need bookkeeping, or download a kontoutskrift. Read only; cannot write, book or move money.
---

# Folio (read)

Norwegian business banking. Base `https://api.folio.no/v2`, bearer auth via `$FOLIO_READ_KEY`. All commands go through `scripts/folio.sh`.

**This skill only reads.** Notes, categories and receipts on events are in the `folio-kladd` skill; completing events is in the opt-in `folio-bokforing` skill. Money is never moved by any of them: Folio's API can only create payment drafts that a person must sign in Folio, and these skills don't even do that.

**Setup (one-time):**

```bash
export FOLIO_READ_KEY=...               # create at https://app.folio.no/til/api-tilgang
# or: export FOLIO_ENV=~/.config/folio/.env   (a file defining FOLIO_READ_KEY)
```

Use a key with read access only if Folio offers one, otherwise a key without payment access.

## Quick start

```bash
F=~/.claude/skills/folio/scripts/folio.sh

bash "$F" accounts                            # list accounts
bash "$F" transactions 2026-01-01 2026-06-09  # transactions in range
bash "$F" events 2026-05-01 2026-05-31        # events, incl. which still need bookkeeping
bash "$F" event <eventId>                     # one event: complete? receipts? category?
bash "$F" help                                # all commands
```

Dates are `YYYY-MM-DD`. Output is JSON (piped through `jq` if available); statements/attachments download as files.

## Common workflows

**Transactions and balances**

```bash
bash "$F" transactions 2026-05-01 2026-05-31 --merchants
bash "$F" transactions 2026-05-01 2026-05-31 --account <accountNumber>   # one account
bash "$F" balance <accountNumber> 2026-05-31
```

**What needs bookkeeping** — an event with `complete: false`. A `LedgerCategory` (`bash "$F" category <id>`) flags `requiresPurpose`, `requiresParticipants`, `requiresAttachment`, `requiresReview` and the VAT code. There is no list endpoint for categories — find ids on past events (`bash "$F" events <range> | jq '.events[].ledgerCategory'`).

**Statement PDF** (e.g. for regnskap)

```bash
bash "$F" statement 2026 05 -o ~/Downloads/folio-2026-05.pdf
bash "$F" statement --range 2026-01-01 2026-03-31 -o ~/Downloads/folio-q1.pdf
```

**Export to CSV** — pull JSON, shape with `jq`:

```bash
bash "$F" transactions 2026-01-01 2026-06-09 \
  | jq -r '.transactions.booked[] | [.bookingDate, .description, .transactionAmount.amount, .transactionAmount.currency] | @csv'
```

**Export to CSV** — pull JSON, shape with `jq`:

```bash
bash "$F" transactions 2026-01-01 2026-06-09 \
  | jq -r '.transactions.booked[] | [.bookingDate, .description, .transactionAmount.amount, .transactionAmount.currency] | @csv'
```

## Full reference

Endpoints, schemas and gotchas: see [REFERENCE.md](REFERENCE.md). For anything not wrapped: `bash "$F" raw GET /some/path`.

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Not affiliated with Folio.
