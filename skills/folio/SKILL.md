---
name: folio
description: Query the Folio business-banking/accounting API (folio.no) — accounts, transactions, balances, bookkeeping events, receipts/attachments and statement PDFs. Use when the user mentions Folio, their Folio/bedriftskonto, or asks to pull transactions, check a balance, categorize/bokføre an event, upload a kvittering/receipt, or download a kontoutskrift/statement. Read + bookkeeping only — does NOT move money.
---

# Folio API

Norwegian business banking + bookkeeping. Base `https://api.folio.no/v2`, bearer auth via `$FOLIO_API_KEY`. All helper commands go through `scripts/folio.sh`.

**Setup (one-time):** export your API key, or put it in a file and point `FOLIO_ENV` at it. See the repo README for full instructions.

```bash
export FOLIO_API_KEY=...               # create at https://app.folio.no/til/api-tilgang
# or: export FOLIO_ENV=~/.config/folio/.env   (a file defining FOLIO_API_KEY)
```

**Scope:** read + bookkeeping only. There are deliberately **no payment commands** — a read/bookkeeping API key has no payment scope, and money movement is done manually in Folio.

## Quick start

```bash
F=~/.claude/skills/folio/scripts/folio.sh

bash "$F" accounts                            # list accounts
bash "$F" transactions 2026-01-01 2026-06-09  # transactions in range
bash "$F" help                                # all commands
```

Dates are `YYYY-MM-DD`. Output is JSON (piped through `jq` if available); statements/attachments download as files.

## Common workflows

**Pull transactions / reconcile**

```bash
bash "$F" transactions 2026-05-01 2026-05-31 --merchants
bash "$F" transactions 2026-05-01 2026-05-31 --account <accountNumber>   # one account
bash "$F" balance <accountNumber> 2026-05-31
```

**Bookkeeping an event** (events = bank events needing categorization/receipts)

1. List uncompleted events: `bash "$F" events 2026-05-01 2026-05-31`
2. Check what the target category requires (purpose? participants? attachment?):
   `bash "$F" category <ledgerCategoryId>`
3. Set fields: `bash "$F" patch-event <eventId> --purpose "Kundemøte" --participants "Navn" --category <ledgerCategoryId>`
4. Attach receipt: `bash "$F" attach <eventId> ~/Downloads/kvittering.pdf`
5. Mark done: `bash "$F" complete <eventId>` (undo: `uncomplete`)

> A `LedgerCategory` flags `requiresPurpose`, `requiresParticipants`, `requiresAttachment`, `requiresReview` and the VAT code/rate. Check these (step 2) before `complete`, or completion may be rejected.

**Sharp edges (learned in production):**

- **An event can complete itself.** Setting `--category` on an event that already has an attachment has triggered auto-completion with no `complete` call — and in other runs it didn't (possibly async). There's no reliable way to stage attachment + category without the event going live. Warn the user before categorizing an already-attached event if they wanted a manual review step.
- **With Folio's Fiken integration on, completing an event books it in Fiken** (the matching purchase shows up with a payment on the bank account). Don't also hand-build a Fiken purchase draft for the same card charge, or it's booked twice. Fiken drafts are still the right tool for things Folio never sees, like expenses paid with a private card (utlegg).
- **Refunds (incoming events) need an incoming category.** An expense category has `isIncoming: false`; a refund set to it showed `complete: true` but never synced to Fiken. Use a category with `isIncoming: true`. There is no list endpoint for categories — find ids on past events (`bash "$F" events <range> | jq '.events[].ledgerCategory'`) and inspect them with `bash "$F" category <id>`.

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

## Full reference

Endpoint list, query params, schemas and gotchas: see [REFERENCE.md](REFERENCE.md).
For anything not wrapped by the helper, use the escape hatch: `bash "$F" raw GET /some/path`. Writes through `raw` need `--confirm` (get the user's OK first), and payment/integration endpoints are refused no matter what.

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Not affiliated with Folio.
