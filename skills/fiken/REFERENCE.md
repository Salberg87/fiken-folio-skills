# Fiken API — Reference

Base URL: `https://api.fiken.no/api/v2` · Auth: `Authorization: Bearer $FIKEN_READ_TOKEN` (personal API token).
Company: `$FIKEN_COMPANY_SLUG`. Set both as environment variables, or put them in a file and point `$FIKEN_ENV` at it — `scripts/fiken.sh` auto-loads it.
Manage tokens: Fiken → Innstillinger → API. Full OpenAPI: `GET /api/v2/docs/swagger.yaml`.

**Money is in øre** (integer, 1/100 NOK): `22600` = 226,00 NOK. Applies to every amount field (`net`, `gross`, `vat`, `amount`, `balance`). The `costs`/`result` reports convert; raw JSON does not.
Dates: `YYYY-MM-DD`. Pagination: `?page=` (0-indexed) + `?pageSize=`; the response carries `fiken-api-page-count` / `fiken-api-result-count` headers. **The wrapper follows all pages automatically** (`_get_all`), so list commands always return the complete set. `$FIKEN_PAGE_SIZE` overrides page size (testing only).

## Endpoints

### Read

| Command           | Method · Path                                 | Notes                                                                  |
| ----------------- | --------------------------------------------- | ---------------------------------------------------------------------- |
| `whoami`          | GET `/user`                                   | name, email                                                            |
| `company`         | GET `/companies/{slug}`                       | org.nr, vatType, accountingStartDate                                   |
| `accounts`        | GET `/companies/{slug}/accounts`              | chart of accounts: `code`, `name`                                      |
| `balances <date>` | GET `/companies/{slug}/accountBalances?date=` | **`date` required** (400 without). Cumulative balance per account.     |
| `purchases s [e]` | GET `/companies/{slug}/purchases`             | filtered client-side on `.date` (the API has **no** date query params) |
| `sales s [e]`     | GET `/companies/{slug}/sales`                 | filtered client-side on `.date`                                        |
| `journal s [e]`   | GET `/companies/{slug}/journalEntries`        | bilag; filtered client-side on `.date`                                 |
| `invoices`        | GET `/companies/{slug}/invoices`              | outgoing invoices                                                      |
| `transactions`    | GET `/companies/{slug}/transactions`          | accounting transactions                                                |
| `contacts [q]`    | GET `/companies/{slug}/contacts`              | optional client-side name filter                                       |
| `products`        | GET `/companies/{slug}/products`              |                                                                        |
| `bank`            | GET `/companies/{slug}/bankAccounts`          |                                                                        |
| `inbox`           | GET `/companies/{slug}/inbox`                 | mottak — uploaded docs awaiting processing                             |
| `drafts`          | GET `/companies/{slug}/purchases/drafts`      | purchase drafts (kladd)                                                |
| `draft <id>`      | GET `/companies/{slug}/purchases/drafts/{id}` | single draft                                                           |
| `offer-drafts`    | GET `/companies/{slug}/offers/drafts`         | sales offer drafts (tilbud-kladd)                                      |
| `invoice-drafts`  | GET `/companies/{slug}/invoices/drafts`       | sales invoice drafts (faktura-kladd)                                   |

### Computed reports (`scripts/report.py`)

`costs <period>` and `result <period>` — period is `YYYY-MM`, `ytd`, or `YYYY-MM..YYYY-MM` — compute **movement = accountBalances(period end) − accountBalances(day before period start)** per account, bucketed by Norwegian standard class (cost rows show account names from the chart of accounts):

- **3xxx** = driftsinntekter (credit; report flips sign to positive revenue)
- **4–7xxx** = driftskostnader
- **8xxx** = finans / skatt / årsresultat

This is the **authoritative** cost figure — the purchases list misses anything booked as a bilag. For the first month of accounting the prev-month-end falls before `accountingStartDate`; `accountBalances` 400s there and the report treats prior balances as 0.

`raw GET <path>` is the escape hatch for anything not wrapped. Other methods are refused; writes live in `fiken-kladd` and `fiken-bokforing`.

## Schemas

**Purchase / draft line** (read) — `description`/`text`, `netPrice`/`net`, `vat`, `gross`, `account`/`incomeAccount`, `vatType`. Top-level: `date`, `kind` (`cash_purchase`|`supplier`), `paid`, `settled`, `payments[]`, `purchaseAttachments[]`.

**vatType values**

- Sales: `NONE, HIGH, MEDIUM, RAW_FISH, LOW, EXEMPT_IMPORT_EXPORT, EXEMPT, OUTSIDE, EXEMPT_REVERSE`
- Purchases: `NONE, HIGH, MEDIUM, RAW_FISH, LOW, HIGH_DIRECT, HIGH_BASIS, MEDIUM_DIRECT, MEDIUM_BASIS, NONE_IMPORT_BASIS, HIGH_FOREIGN_SERVICE_DEDUCTIBLE, HIGH_FOREIGN_SERVICE_NONDEDUCTIBLE, LOW_FOREIGN_SERVICE_DEDUCTIBLE, LOW_FOREIGN_SERVICE_NONDEDUCTIBLE, HIGH_PURCHASE_OF_EMISSIONSTRADING_OR_GOLD_DEDUCTIBLE, HIGH_PURCHASE_OF_EMISSIONSTRADING_OR_GOLD_NONDEDUCTIBLE`
- `HIGH` = 25 %, `MEDIUM` = 15 % (mat), `LOW` = 12 %, `NONE` = ingen mva.

## Gotchas

- **øre everywhere** — `net`/`gross`/`amount` are integers in øre. Convert before showing NOK.
- `accountBalances` **requires** `?date=` and is **cumulative** from `accountingStartDate`; a single month's figure is end − prev-end (what `costs`/`result` do).
- `purchases`/`sales`/`journalEntries`/`invoices` have **no date query params at all** (verified against the OpenAPI spec — unknown params are silently ignored). The wrapper filters on `.date` client-side; that is the only correct way.
- `incomeAccount` is the line account field even for purchases (cost account).
- If the company became VAT-registered partway through a year, purchase VAT from before registration is not deductible — sanity-check `vatType` on older docs.
