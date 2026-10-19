---
name: reconcile
description: Reconcile Folio card charges / bank events against Fiken and prepare the missing bookings as Fiken DRAFTS. Use when the user wants to reconcile, match bank transactions to accounting, find unbooked card charges, or do a monthly bookkeeping pass across Folio + Fiken. Plans first, creates drafts only — never posts to the ledger and never moves money.
---

# Reconcile (Folio ↔ Fiken)

A reconciliation workflow on top of the [`folio`](../folio), [`fiken`](../fiken) and [`fiken-kladd`](../fiken-kladd) skills. It matches uncompleted Folio events (card charges / bank events) against existing Fiken purchases, then proposes Fiken purchase **drafts** for the unmatched ones. The matching/classification is a pure, offline plan step (`scripts/reconcile.py`); the only writes are drafts through `fiken-kladd`.

**Requires:** the `folio`, `fiken` and `fiken-kladd` skills installed and configured (their env vars set). `python3`, and `jq` for convenience.

## The hard rule: this never books and never pays

The whole point of this skill vs. ad-hoc automation is that the dangerous steps are off the automated path:

- **`reconcile.py` only plans.** It makes no API calls and writes nothing — it reads two JSON files and prints a plan.
- **Writes create drafts (kladd) only**, via `fiken-kladd draft-purchase`. Drafts are reviewable and reversible.
- **Running it twice is safe**: pass `--drafts` and open drafts that already match are skipped.
- **Posting a draft to the ledger** is the user's step in Fiken. Don't chain it into this workflow, even if `fiken-bokforing` is installed.
- **Completing a Folio event** is likewise the user's step in Folio.
- **Money never moves** — none of the skills has a payment command.

So a full run produces: a reviewed plan → Fiken drafts → (human) posts drafts → (human) marks Folio events complete.

> ⚠️ **Folio's Fiken integration and this workflow don't mix.** If the integration is on, completing a Folio event books it in Fiken by itself. Creating a Fiken draft for the same charge *and* completing the event books it twice. With the integration on, book card charges by completing them in Folio (see the `folio` skill) and use this skill only to find what's missing. Ask the user which setup they have before step 4.

## Workflow

### 1. Set up classification rules (once)

```bash
cp ~/.claude/skills/reconcile/rules.example.json ~/.config/reconcile/rules.json
# edit: map charge-description keywords → Fiken cost account + vendor name.
# list physical-goods accounts under "goods_accounts" (import VAT = vatType NONE).
```

### 2. Pull the data (reads, safe)

```bash
FO=~/.claude/skills/folio/scripts/folio.sh
FI=~/.claude/skills/fiken/scripts/fiken.sh
FK=~/.claude/skills/fiken-kladd/scripts/fiken-kladd.sh

W=$(mktemp -d)   # private working dir — this is financial data, keep it out of shared /tmp files
bash "$FO" events 2026-05-01 2026-05-31 > "$W/events.json"
bash "$FI" purchases 2026-05-01 2026-05-31 > "$W/purchases.json"
bash "$FI" drafts > "$W/drafts.json"
```

### 3. Build the plan (offline, no writes)

```bash
R=~/.claude/skills/reconcile/scripts/reconcile.py
python3 "$R" --events "$W/events.json" --purchases "$W/purchases.json" --drafts "$W/drafts.json" \
  --rules ~/.config/reconcile/rules.json --card-account 1949
```

You get three buckets:

- **already_booked** — a Fiken purchase already matches `(date, amount)`; skipped (count-based dedup handles same-day, same-amount duplicates).
- **already_drafted** — an open Fiken draft already matches; skipped.
- **proposed** — no match; a draft is suggested with account + vatType.
- **needs_review** — no vendor rule matched, or amount is zero/odd; left for you to classify by hand.

`--card-account <code>` is the Fiken account the card is paid from (e.g. a `19xx` card account); used both to scope dedup and to fill the draft's payment line. Omit it to skip payment lines.

### 4. Review with the user, then create DRAFTS

Show the proposed table to the user. Only after they're happy, create the drafts (this is safe — drafts only):

```bash
python3 "$R" --events "$W/events.json" --purchases "$W/purchases.json" --drafts "$W/drafts.json" \
  --rules ~/.config/reconcile/rules.json --card-account 1949 --json > "$W/plan.json"

# create one draft per proposed entry:
jq -c '.[] | select(.status=="proposed") | .draft' "$W/plan.json" | while read -r d; do
  bash "$FK" draft-purchase "$d"
done
```

### 5. (Optional) attach receipts

If you have the receipt PDF (e.g. from email), attach it to the draft:

```bash
bash "$FK" attach-draft <draftId> ~/Downloads/receipt.pdf
```

### 6. Hand off to the user

Drafts now sit in Fiken. Give the user the list (with Fiken links, `https://fiken.no/foretak/{slug}/handelsutkast/kjop/{uuid}`) and tell them what's left:

- post each draft in Fiken after checking it
- complete the matching Folio events in Folio, or leave them, depending on whether their Folio–Fiken integration books them (see the warning above)

Don't post or complete anything from here.

## VAT logic

`reconcile.py` picks `vatType` from the charge currency and target account:

- **NOK** → `HIGH` (25 %); `net = gross / 1.25`.
- **Foreign + service account** → `HIGH_FOREIGN_SERVICE_DEDUCTIBLE` (reverse charge); `net = gross`, no VAT line.
- **Foreign + goods account** (in `goods_accounts`) → `NONE` (import VAT via customs); `net = gross`.

These are sensible defaults, not tax advice — check unusual charges, and verify `vatType` is valid for the account (Fiken rejects some combinations).

## Full reference

Plan schema, matching rules, edge cases: see [REFERENCE.md](REFERENCE.md).

---

Part of **[fiken-folio-skills](https://github.com/Salberg87/fiken-folio-skills)** by Fredrik Skorge Salberg ([Pifre AS](https://pifre.no)). Builds on the `fiken` and `folio` skills.
