---
name: fiken-kladd
description: Prepare bookkeeping in Fiken (fiken.no) without touching the ledger — create purchase, offer and invoice drafts (kladd), upload receipts to the inbox (mottak) and attach receipts to drafts. Use when the user wants to register a cost, draft an invoice or offer, or upload a kvittering to Fiken. Never posts to the ledger; the user posts drafts in Fiken.
---

# Fiken kladd (prepare)

Creates **drafts** and inbox uploads in Fiken. Nothing here changes the ledger. All commands go through `scripts/fiken-kladd.sh`. Use the `fiken` skill to read (contacts, accounts, existing drafts).

**Bokføring is not in this skill.** There is no command to post a draft. When a draft is ready, tell the user to review and post it in Fiken (or, if they have installed the opt-in `fiken-bokforing` skill, ask them first). Don't write your own API call to post it.

**Setup (one-time):**

```bash
export FIKEN_WRITE_TOKEN=...           # a token from a Fiken user with full access
export FIKEN_COMPANY_SLUG=your-company-as
# or: export FIKEN_ENV=~/.config/fiken/.env
```

Every write is logged as a JSON line to `~/.local/state/fiken-folio-skills/audit.jsonl` (override with `FIKEN_FOLIO_AUDIT_LOG`), and the created draft is read back from Fiken. A write is never retried automatically: if a call times out or fails with 5xx, check `fiken drafts` before trying again, or you may create a duplicate.

## Workflows

```bash
F=~/.claude/skills/fiken-kladd/scripts/fiken-kladd.sh
```

**Upload a receipt to mottak** (staging, not booking):

```bash
bash "$F" inbox-upload ~/Downloads/kvittering.pdf "Batterier"
```

**Register a cost as a DRAFT** (kladd — the user reviews and posts it in Fiken):

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

Fiken's UI link to a draft uses its `uuid`: `https://fiken.no/foretak/{slug}/handelsutkast/kjop/{uuid}` (sales: `…/handelsutkast/salg/{uuid}`). Give the user that link so they can post it.

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

Draft schemas, VAT types and gotchas: see [REFERENCE.md](REFERENCE.md).

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Not affiliated with Fiken.
