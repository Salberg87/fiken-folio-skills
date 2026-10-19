---
name: fiken
description: Query the Fiken accounting API (fiken.no) for your company — costs/result reports, account balances, transactions, purchases, sales, invoices, contacts, receipts/inbox. Use when the user mentions Fiken, regnskap, kostnader/result/driftsresultat, kontoplan, bilag, kjøp/salg/faktura, kvittering/mottak, or asks to pull accounting numbers. Read freely; writes create DRAFTS only — never posts to the ledger without explicit confirmation.
---

# Fiken API

Norwegian accounting (regnskap). Base `https://api.fiken.no/api/v2`, bearer auth via `$FIKEN_API_TOKEN` + `$FIKEN_COMPANY_SLUG`. All commands go through `scripts/fiken.sh`.

**Setup (one-time):** export your token and company slug, or put them in a file and point `FIKEN_ENV` at it. See the repo README for full instructions.

```bash
export FIKEN_API_TOKEN=...            # Fiken → Innstillinger → API
export FIKEN_COMPANY_SLUG=your-company-as
# or: export FIKEN_ENV=~/.config/fiken/.env   (a file defining the two vars)
```

**Scope (HARD RULE):** read freely. Writes create **drafts only** (kladd) or upload to the inbox/mottak. Posting a draft to the ledger (`post-draft` → `createPurchase`) is **bokføring** — irreversible. It is gated behind `--confirm` and you MUST get the user's explicit OK in the same message before running it. Same for any `raw` non-GET call.

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
```

**Upload a receipt to mottak** (staging, not booking):

```bash
bash "$F" inbox-upload ~/Downloads/kvittering.pdf "Batterier"
```

**Register a cost as a DRAFT** (kladd — review in Fiken, post manually or via `post-draft`):

```bash
# Line account goes in "incomeAccount" even for a purchase (Fiken quirk). Øre.
bash "$F" draft-purchase '{"cash":true,"paid":true,"currency":"NOK","invoiceIssueDate":"2026-05-26",
  "lines":[{"text":"Batterier","vatType":"HIGH","incomeAccount":"6560","net":10800,"gross":13500}]}'
bash "$F" attach-draft <draftId> ~/Downloads/kvittering.pdf
```

**Create a sales offer / invoice DRAFT** (kladd — review and send in Fiken). Sales lines use `unitPrice` + `quantity` in øre (not net/gross), and `type` + `daysUntilDueDate` are required on both:

```bash
# Tilbud-kladd
bash "$F" draft-offer '{"type":"offer","customerId":12345,"daysUntilDueDate":14,
  "lines":[{"description":"Nettsideredesign","unitPrice":2500000,"vatType":"HIGH","quantity":1,"incomeAccount":"3020"}]}'

# Faktura-kladd (also needs bankAccountNumber + cash)
bash "$F" draft-invoice '{"type":"invoice","customerId":12345,"daysUntilDueDate":14,
  "bankAccountNumber":"<your account number>","cash":false,
  "lines":[{"description":"Nettsideredesign","unitPrice":2500000,"vatType":"HIGH","quantity":1,"incomeAccount":"3020"}]}'
```

**Post a draft to the ledger** — bokføring, irreversible. Confirm with the user first, then:

```bash
bash "$F" post-draft <draftId> --confirm
```

## Sharp edges (learned in production)

- **Line `text`/`description` max 200 characters** — the API answers 400 on longer ones. Shorten before sending.
- **Booked entries can never be deleted** — DELETE on a booked purchase gives HTTP 405. Corrections are a credit note or reversing entry in the Fiken UI, not via the API.
- **`vatType` is validated per account** — e.g. `EXEMPT` is rejected on some balance accounts. On "ikke gyldig mva kode for kontoen", change vatType or account; check the account's VAT setup in Fiken instead of guessing variants.
- **The cost account goes in `incomeAccount` even for purchases** (repeated here because it surprises every time).
- **Amounts are øre everywhere** in raw JSON; only the report commands convert.
- **`type` + `daysUntilDueDate` are required** on both offer and invoice drafts.
- **Attachments on sales drafts**: `POST /companies/{slug}/offers/drafts/{draftId}/attachments`, multipart with `filename`, `comment`, `file`. Works on **drafts** only — the same path on a finished offer gives 404. Delete with the attachment's `uuid` field: `DELETE …/attachments/{uuid}` → 204.
- **`curl -F` text fields lose UTF-8** — `comment=Avtalevilkår` is stored as `AvtalevilkÃ¥r`. Leave æ/ø/å out of multipart text fields, or build the request in Python with explicit encoding. File contents are not affected.
- **Services bought from abroad** (SaaS etc.) are reverse charge (snudd avregning, mval. § 3-30), not an ordinary HIGH purchase. Ask before drafting these.
- **Deep links into the Fiken UI** use the draft's `uuid`, not the numeric `draftId`: purchase draft → `https://fiken.no/foretak/{slug}/handelsutkast/kjop/{uuid}`, sales draft → `…/handelsutkast/salg/{uuid}`.

## Full reference

Endpoints, schemas, the draft-purchase body, VAT types and gotchas: see [REFERENCE.md](REFERENCE.md).
For anything not wrapped: read escape hatch `bash "$F" raw GET /companies/$FIKEN_COMPANY_SLUG/...`; writes need `--confirm`.

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Not affiliated with Fiken.
