# Fiken API — Reference (drafts)

Base URL: `https://api.fiken.no/api/v2` · Auth: `Authorization: Bearer $FIKEN_WRITE_TOKEN` · Company: `$FIKEN_COMPANY_SLUG` (or a file `$FIKEN_ENV` points at).

**Money is in øre** (integer, 1/100 NOK): `22600` = 226,00 NOK.

## Endpoints

### Drafts and inbox (no ledger change)

| Command                      | Method · Path                                              | Body                                                 |
| ---------------------------- | ---------------------------------------------------------- | ---------------------------------------------------- |
| `inbox-upload <file> [desc]` | POST `/companies/{slug}/inbox`                             | multipart: `file`, `filename`, `name`, `description` |
| `draft-purchase <json>`      | POST `/companies/{slug}/purchases/drafts`                  | JSON `draftRequest` (below)                          |
| `draft-offer <json>`         | POST `/companies/{slug}/offers/drafts`                     | JSON `salesDraftRequest` (below)                     |
| `draft-invoice <json>`       | POST `/companies/{slug}/invoices/drafts`                   | JSON `salesDraftRequest` (below)                     |
| `attach-draft <id> <file>`   | POST `/companies/{slug}/purchases/drafts/{id}/attachments` | multipart: `file`, `filename`                        |

### raw (allow-listed)

`raw GET <path>` reads anything. `raw <POST|PUT|PATCH> <path> [json]` only reaches, under `/companies/{slug}`:

| Path | Notes |
| --- | --- |
| `/contacts`, `/contacts/{id}` | customers and suppliers |
| `/contacts/{id}/contactPerson`, `…/contactPerson/{id}` | |
| `/projects`, `/projects/{id}` | `POST` needs `startDate`, `number`, `name` |
| `/activities`, `/activities/{id}` | `POST` needs `name` |
| `/timeEntries`, `/timeEntries/{id}` | |
| `/{purchases,offers,invoices}/drafts`, `…/drafts/{id}`, `…/drafts/{id}/attachments` | |
| `/inbox` | |

No query strings, no `DELETE`, no `create*` actions. The list is a regex in `scripts/fiken-kladd.sh` (`RAW_WRITE_ALLOW`).

## Schemas

**draftRequest** (POST purchases/drafts) — required: `cash` (bool), `paid` (bool), `lines` (array). Optional: `invoiceIssueDate`, `dueDate`, `invoiceNumber`, `contactId` (int), `projectId` (int), `currency`, `kid`, `payments[]`.

**draftLineRequest** — required: `text`, `vatType`, `incomeAccount`, `net` (øre), `gross` (øre). Optional: `projectId`.

> ⚠️ For a **purchase** draft the cost account still goes in the field literally named `incomeAccount` (Fiken quirk). E.g. `"incomeAccount":"6560"` for forbruksmateriell.

**salesDraftRequest** (POST offers/drafts + invoices/drafts) — required: `type` (`"offer"` | `"invoice"`), `customerId` (int), `daysUntilDueDate` (int), `lines` (array). Invoice drafts also require `bankAccountNumber` (string) and `cash` (bool). Other `type` values exist (`cash_invoice`, `credit_note`, …) but only offer/invoice are wrapped.

**salesDraftLine** — `description`, `unitPrice` (**øre, net per unit**), `vatType`, `quantity` (int), `incomeAccount` (e.g. `"3020"` salgsinntekt). Optional: `discount`.

> ⚠️ Sales draft lines use `unitPrice` + `quantity` — **not** `net`/`gross` like purchase lines. And `type` + `daysUntilDueDate` are required on **both** offers and invoices (an offer draft 400s without them too).

> **Line discount** — `"discount": 50` = **integer percent** off. Put the list price in `unitPrice` (øre) and the percent in `discount`; Fiken computes net = `unitPrice × quantity × (1 − discount/100)`. On **read**, Fiken normalizes: `unitPrice`/`net` come back as the post-discount value and `discount` as a **fraction** (`0.5`). So: write percent (50), read fraction (0.5) — don't round-trip the read value straight back in.

**payment** — required: `date`, `account` (e.g. `"1920:10001"`), `amount` (øre). Optional: `amountInNok`, `currency`, `fee`.

**vatType values**

- Sales: `NONE, HIGH, MEDIUM, RAW_FISH, LOW, EXEMPT_IMPORT_EXPORT, EXEMPT, OUTSIDE, EXEMPT_REVERSE`
- Purchases: `NONE, HIGH, MEDIUM, RAW_FISH, LOW, HIGH_DIRECT, HIGH_BASIS, MEDIUM_DIRECT, MEDIUM_BASIS, NONE_IMPORT_BASIS, HIGH_FOREIGN_SERVICE_DEDUCTIBLE, HIGH_FOREIGN_SERVICE_NONDEDUCTIBLE, LOW_FOREIGN_SERVICE_DEDUCTIBLE, LOW_FOREIGN_SERVICE_NONDEDUCTIBLE, HIGH_PURCHASE_OF_EMISSIONSTRADING_OR_GOLD_DEDUCTIBLE, HIGH_PURCHASE_OF_EMISSIONSTRADING_OR_GOLD_NONDEDUCTIBLE`
- `HIGH` = 25 %, `MEDIUM` = 15 % (mat), `LOW` = 12 %, `NONE` = ingen mva.

## Gotchas

- **øre everywhere** — `net`/`gross`/`amount`/`unitPrice` are integers in øre.
- `incomeAccount` is the line account field even for purchases (cost account).
- Write commands surface the HTTP code, the error body (e.g. `Missing field: 'paid'`), and the `Location` header with the created resource URL (draftId). The script then reads that URL back to confirm the draft exists.
- `inbox` upload (mottak) is **staging**, not booking.
- Writes are never retried automatically. Fiken allows one request at a time and about 4 per second; after a timeout, check what exists before sending again.
- `projects`/`activities`/`timeEntries` endpoints worked on our plan, but are not wrapped. If you get **402**, the feature isn't on your Fiken plan.
- If the company became VAT-registered partway through a year, purchase VAT from before registration is not deductible — sanity-check `vatType` on older docs.
