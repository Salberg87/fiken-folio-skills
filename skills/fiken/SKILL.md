---
name: fiken
description: Read the Fiken accounting API (fiken.no) — costs/result reports, account balances, transactions, purchases, sales, invoices, contacts, drafts and the receipt inbox. Use when the user mentions Fiken, regnskap, kostnader/resultat/driftsresultat, kontoplan, bilag, kjøp/salg/faktura or mottak, or asks for accounting numbers. Read only; this skill cannot write anything.
---

# Fiken (read)

Norwegian accounting (regnskap). Base `https://api.fiken.no/api/v2`, bearer auth via `$FIKEN_READ_TOKEN` + `$FIKEN_COMPANY_SLUG`. All commands go through `scripts/fiken.sh`.

**This skill only reads.** It has no write commands, and `raw` refuses anything but GET. Drafts are in the `fiken-kladd` skill; posting to the ledger is in the opt-in `fiken-bokforing` skill. If the user asks for something those cover and they aren't installed, say so; don't write your own API calls.

**Setup (one-time):**

```bash
export FIKEN_READ_TOKEN=...            # personal API token (Rediger konto → API)
export FIKEN_COMPANY_SLUG=your-company-as
# or: export FIKEN_ENV=~/.config/fiken/.env   (a file defining the two vars)
```

Best practice: create the token as its own Fiken user with the role *Se regnskapet uten å kunne gjøre endringer*, so Fiken itself refuses writes made with it. See the repo README.

> **Amounts are in øre** — divide by 100 for NOK. The reporting commands already do this; raw JSON does not.

## Quick start

```bash
F=~/.claude/skills/fiken/scripts/fiken.sh

bash "$F" costs 2026-05        # driftskostnader for a month (GL movement, kl. 4-7)
bash "$F" costs ytd            # ... year to date
bash "$F" result 2026-01..2026-05   # revenue / costs / driftsresultat for a range
bash "$F" balances 2026-05-31  # balance per account on a date
bash "$F" help                 # all commands
```

Dates are `YYYY-MM-DD`; periods are `YYYY-MM`, `ytd`, or `YYYY-MM..YYYY-MM`. Output is JSON (via `jq` if present) except the `costs`/`result` reports, which print tables with account names. List commands follow Fiken's pagination automatically — results are always complete.

## Common workflows

**Monthly costs / result** — the authoritative way (general-ledger movement, not the purchases list):

```bash
bash "$F" costs 2026-05        # itemized cost accounts + sum
bash "$F" result 2026-05       # inntekter, kostnader, driftsresultat
```

These compute GL movement (`accountBalances` end − start) per account and bucket by class (3 = revenue, 4-7 = cost, 8 = finance/tax). Use this over `purchases` — the purchases list misses costs booked as bilag, and the API has no date filter on purchases (the wrapper filters client-side).

**Browse documents**

```bash
bash "$F" purchases 2026-05-01 2026-05-31   # kjøp (filtered client-side on date)
bash "$F" sales 2026-05-01 2026-05-31
bash "$F" journal 2026-05-01 2026-05-31     # bilag
bash "$F" invoices ; bash "$F" contacts <søk> ; bash "$F" bank ; bash "$F" inbox
bash "$F" drafts ; bash "$F" offer-drafts ; bash "$F" invoice-drafts
```

## Full reference

Endpoints, VAT types and gotchas: see [REFERENCE.md](REFERENCE.md).
For anything not wrapped: `bash "$F" raw GET /companies/$FIKEN_COMPANY_SLUG/...`.

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Not affiliated with Fiken.
