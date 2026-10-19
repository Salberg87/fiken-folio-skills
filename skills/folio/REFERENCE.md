# Folio API — Reference

Base URL: `https://api.folio.no/v2` · Auth: `Authorization: Bearer <key>` (global `apiKey` security scheme, HTTP bearer). The `folio` skill uses `$FOLIO_READ_KEY`; `folio-kladd` and `folio-bokforing` use `$FOLIO_WRITE_KEY`.
Create/manage keys at https://app.folio.no/til/api-tilgang. Companies can alternatively use an OAuth2 flow (separate `oauth2.html` spec) — not used here.

Dates: `YYYY-MM-DD`. Money fields are **strings** (e.g. `"1234.50"`) with a separate `currency`.

## Endpoints (in scope)

| Method | Path                                       | Params                                                                                  | Returns                        |
| ------ | ------------------------------------------ | --------------------------------------------------------------------------------------- | ------------------------------ |
| GET    | `/accounts`                                | —                                                                                       | `AccountsResponse`             |
| GET    | `/accounts/{accountNumber}/balance/{date}` | path: accountNumber, date                                                               | `AccountBalance`               |
| GET    | `/accounts/{accountNumber}/transactions`   | path: accountNumber · query: `startDate`(req), `endDate`                                | `TransactionResponse`          |
| GET    | `/transactions`                            | query: `startDate`(req), `endDate`, `includeMerchants`                                  | `TransactionResponse`          |
| GET    | `/transactions/{id}`                       | path: id                                                                                | `Transaction` (404 if none)    |
| GET    | `/events/{id}`                             | path: id                                                                                | `{event: Event}`               |
| GET    | `/events`                                  | query: `startDate`(req), `endDate`, `includeMerchants`, `includeAgents`, `includeCards` | `EventsResponse`               |
| PATCH  | `/events/{id}`                             | path: id · body: `PatchEvent`                                                           | 202 (400/403 on error)         |
| POST   | `/events/{id}/attachments`                 | path: id · headers: `Content-Type`, `Content-Disposition` · binary body                 | 200 `CreateAttachmentResponse` |
| POST   | `/events/{id}/complete`                    | path: id                                                                                | 2xx                            |
| DELETE | `/events/{id}/complete`                    | path: id                                                                                | 2xx (un-complete)              |
| GET    | `/attachments/{id}/{type}`                 | path: id(uuid), type                                                                    | binary (image/pdf)             |
| GET    | `/categories/{id}`                         | path: id                                                                                | `LedgerCategory`               |
| GET    | `/statement/{year}/{month}`                | path: year, month                                                                       | `application/pdf`              |
| GET    | `/statement`                               | query: `startDate`, `endDate`                                                           | `application/pdf`              |

Which skill wraps what: every GET is in `folio`. `PATCH /events/{id}` and `POST …/attachments` are in `folio-kladd` (guarded so an event is never left in a state where Folio completes it by itself) and in `folio-bokforing` (unguarded). `…/complete` is only in `folio-bokforing`.

`/attachments/{id}/{type}` — `type` ∈ `original | cropped | 128x128 | 256x256 | 512x512`.
`/events/{id}/attachments` — body is the raw file bytes; `Content-Type` must be `application/pdf`, `image/jpeg`, or `image/png`; set `Content-Disposition: attachment; filename="..."`.

### Out of scope (NOT wrapped — by design)

- `POST /payments`, `GET /payments`, `GET /payments/{id}`, `DELETE /payments/{id}`, and the same under `/salary`. A payment created through the API is a `Draft` until a person signs it in Folio; the API has no way to sign. `DELETE` can cancel a payment that is waiting, which is why writes to these paths are refused by `folio-bokforing`'s `raw` as well.
- `POST /integration/disable` (kills the API integration).

Use a key without payment access. If Folio offers a read-only key, use that for `FOLIO_READ_KEY`.

## Key schemas

**Account** — `accountNumber`, `name`, `type` (e.g. `Operational`, `Card`, `Earmarks`), `balance` (string), `balanceUpdatedAt`, `matchingTransactionsAt`, `completeTransactionsAt`.

**AccountBalance** — `incomingBalance`, `outgoingBalance` (strings).

**Transaction** — `id`, `eventId`, `paymentId`, `description`, `bookingDate`, `kid`, `creditorEventId`, `creditor{name,accountNumber}`, `debtor`, `transactionAmount{amount,currency}`, `currencyAmount{amount,currency}`, `cardAuthorization`, `attachments[]`, `purpose`, `note`, `participants`, `complete` (bool), `ledgerCategory{id,eTag}`.

**Event** — a bank event to be booked: `id`, `amount{amount,currency}`, `time`, `transactions[]`, `payment`, `cardAuthorization`, `attachments[]`, `purpose`, `note`, `participants`, `complete` (bool), `ledgerCategory{id,eTag}`.

**PatchEvent** (PATCH body) — any of: `purpose`, `note`, `participants`, `ledgerCategoryId`.

**LedgerCategory** — `title`, `accountName`, `accountNumber` (int), `isIncoming` (bool), `vatCode`, `vatRate`, `vatTitle`, and requirement flags: `requiresPurpose`, `requiresParticipants`, `requiresAttachment`, `requiresReview`. **Check these before completing an event.**

**Attachment** — `id`, `filename`, `mimeType`, `fileSize`, `extractedText` (OCR), `merchantId`, `orgNum`, `terminalId`, `uploadedByAgentId`, `averageColor`.

Wrapper responses: `AccountsResponse{accounts:[]}`, `EventsResponse{events:[], includes}`, and `TransactionResponse{transactions:{booked:[]}, includes}` — note transactions are nested under `transactions.booked`, **not** a top-level array.

## Gotchas

- `startDate` is **required** on `/transactions`, `/accounts/{n}/transactions`, and `/events`. Omitting it 4xx's.
- Transactions live at `.transactions.booked[]` (object → array), but events are a plain `.events[]` array — easy to confuse in `jq`.
- Amounts are strings — cast in `jq` (`(.transactionAmount.amount|tonumber)`) before arithmetic.
- PATCH returns **202 Accepted** (async) with no body; re-fetch the event to confirm.
- Completing an event whose category has `requires*` flags unmet will fail — set `purpose`/`participants`/attachment first.
- Statement and attachment-download endpoints return **binary**, not JSON — always write to a file (`-o`).
- `includeMerchants/Agents/Cards` enrich the response but make it larger; omit unless needed.
