#!/usr/bin/env python3
"""reconcile.py — plan-only reconciliation between Folio events and Fiken purchases.

Reads Folio events (from `folio events`) and existing Fiken purchases (from
`fiken purchases`), then for each uncompleted Folio card charge decides:

  - already_booked : a Fiken purchase already matches (date + amount) → skip
  - proposed       : no match → emit a Fiken purchase-DRAFT body to create
  - needs_review   : ambiguous (no vendor rule, odd currency, zero amount)

It NEVER calls any API and NEVER writes anything. Output is a plan (JSON +
a human table). Creating drafts, posting to the ledger, and marking Folio
events complete are all separate, gated steps done via the fiken/folio skills
after a human has reviewed this plan.

Usage:
  reconcile.py --events folio_events.json --purchases fiken_purchases.json \
               [--rules rules.json] [--card-account 1949] [--json]

  # typical pipeline:
  W=$(mktemp -d)
  bash folio.sh events 2026-05-01 2026-05-31 > "$W/ev.json"
  bash fiken.sh purchases 2026-05-01 2026-05-31 > "$W/pu.json"
  python3 reconcile.py --events "$W/ev.json" --purchases "$W/pu.json" --rules rules.json

Money: Folio amounts are strings in NOK ("438.00"); Fiken amounts are øre
(integers). This script normalises everything to øre for matching.
Stdlib only.
"""
import argparse, json, re, sys
from collections import defaultdict

DEFAULT_SAAS_ACCOUNT = "6553"   # IT-tjenester / programvare (abonnement)


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def to_ore(amount):
    """Folio NOK string/float -> absolute øre (int)."""
    try:
        return abs(int(round(float(str(amount).replace(",", ".")) * 100)))
    except (TypeError, ValueError):
        return None


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        die(f"cannot read {path}: {e}")


def events_list(data):
    """Accept either {"events":[...]} or a bare [...]"""
    if isinstance(data, dict):
        return data.get("events", [])
    return data or []


def event_date(ev):
    t = ev.get("time") or ev.get("date") or ""
    return t[:10]


def event_currency(ev):
    ca = ev.get("cardAuthorization") or {}
    if ca.get("currency"):
        return ca["currency"]
    txs = ev.get("transactions") or []
    desc = (txs[0].get("description", "") if txs else "") or ""
    m = re.search(r"\b([A-Z]{3})\b", desc)
    return m.group(1) if m else (ev.get("amount", {}) or {}).get("currency", "NOK")


def event_desc(ev):
    txs = ev.get("transactions") or []
    if txs and txs[0].get("description"):
        return txs[0]["description"]
    return ev.get("purpose") or ev.get("note") or ""


def booked_index(purchases, card_account=None):
    """(date, amount_øre) -> count, from existing Fiken purchase payments.
    If card_account is given, only payments on that account count."""
    idx = defaultdict(int)
    for p in purchases or []:
        date = p.get("date", "")
        pays = p.get("payments") or []
        if pays:
            for pay in pays:
                if card_account and str(pay.get("account", "")).split(":")[0] != str(card_account):
                    continue
                amt = pay.get("amount")
                if amt is not None:
                    idx[(date, abs(int(amt)))] += 1
        else:
            # No payment rows (e.g. supplier invoice) — fall back to line gross sum.
            tot = sum(abs(int(l.get("gross", 0) or 0)) for l in (p.get("lines") or []))
            if tot:
                idx[(date, tot)] += 1
    return idx


def classify(desc, rules):
    """desc -> (account, vendor_name) via first matching keyword rule."""
    up = desc.upper()
    for r in rules:
        if r.get("keyword", "").upper() in up:
            return r.get("account", DEFAULT_SAAS_ACCOUNT), r.get("name", "Ukjent")
    return None, None


def vat_for(currency, account, goods_accounts):
    """Return (vatType, net_ore_fn) given currency + target account.
    - NOK: domestic 25% (HIGH), net = gross/1.25
    - foreign + goods account: NONE (import VAT via customs), net = gross
    - foreign + service account: reverse charge deductible, net = gross
    """
    if currency == "NOK":
        return "HIGH", lambda g: int(round(g / 1.25))
    if str(account) in goods_accounts:
        return "NONE", lambda g: g
    return "HIGH_FOREIGN_SERVICE_DEDUCTIBLE", lambda g: g


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--events", required=True)
    ap.add_argument("--purchases", required=True)
    ap.add_argument("--rules", help="JSON: {\"vendors\":[{keyword,account,name}], \"goods_accounts\":[...]}")
    ap.add_argument("--card-account", help="Fiken account code charges are paid from (e.g. 1949). Used for dedup + draft payment.")
    ap.add_argument("--json", action="store_true", help="emit the full plan as JSON")
    args = ap.parse_args()

    events = events_list(load(args.events))
    purchases = load(args.purchases)
    rules_doc = load(args.rules) if args.rules else {}
    vendors = rules_doc.get("vendors", []) if isinstance(rules_doc, dict) else rules_doc
    goods_accounts = set(str(a) for a in (rules_doc.get("goods_accounts", []) if isinstance(rules_doc, dict) else []))

    booked = booked_index(purchases, args.card_account)
    plan = []

    for ev in events:
        if ev.get("complete"):
            continue
        date = event_date(ev)
        ore = to_ore((ev.get("amount", {}) or {}).get("amount"))
        currency = event_currency(ev)
        desc = event_desc(ev)
        entry = {
            "eventId": ev.get("id"),
            "date": date,
            "amount_ore": ore,
            "amount_nok": None if ore is None else round(ore / 100, 2),
            "currency": currency,
            "description": desc,
        }

        if not ore:
            entry.update(status="needs_review", reason="zero or unparseable amount")
            plan.append(entry); continue

        key = (date, ore)
        if booked.get(key, 0) > 0:
            booked[key] -= 1  # consume one match
            entry.update(status="already_booked", reason=f"matches a Fiken purchase on {date} for {entry['amount_nok']}")
            plan.append(entry); continue

        account, vendor = classify(desc, vendors)
        if account is None:
            entry.update(status="needs_review", reason="no vendor rule matched — classify manually")
            plan.append(entry); continue

        vat_type, net_fn = vat_for(currency, account, goods_accounts)
        gross = ore
        net = net_fn(gross)
        line = {"text": vendor, "vatType": vat_type, "incomeAccount": account, "net": net, "gross": gross}
        # A card charge is already paid, so the truthful draft is cash+paid WITH a
        # payment line on the card account. Fiken rejects cash/paid without a payment
        # ("Payment missing when registered as cash or paid"). If no card account is
        # known, fall back to an unpaid supplier-style draft (no payment required) —
        # the user settles the payment account in Fiken.
        if args.card_account:
            draft = {"cash": True, "paid": True, "currency": "NOK",
                     "invoiceIssueDate": date, "lines": [line],
                     "payments": [{"date": date, "account": str(args.card_account), "amount": gross}]}
        else:
            draft = {"cash": False, "paid": False, "currency": "NOK",
                     "invoiceIssueDate": date, "lines": [line]}
        entry.update(status="proposed", vendor=vendor, account=account,
                     vatType=vat_type, draft=draft)
        plan.append(entry)

    if args.json:
        print(json.dumps(plan, ensure_ascii=False, indent=2))
        return

    # Human summary
    by = defaultdict(list)
    for e in plan:
        by[e["status"]].append(e)
    n = len(plan)
    print(f"Reconciliation plan — {n} uncompleted Folio event(s)\n")
    print(f"  already_booked : {len(by['already_booked'])}")
    print(f"  proposed       : {len(by['proposed'])}  (drafts to create — review below)")
    print(f"  needs_review   : {len(by['needs_review'])}\n")

    if by["proposed"]:
        print("PROPOSED DRAFTS (nothing is created until you run draft-purchase):")
        w = max((len(e.get("vendor") or "") for e in by["proposed"]), default=6)
        print(f"  {'date':10} {'NOK':>10}  {'cur':3} {'acct':5} {'vendor':{w}} vatType")
        print("  " + "-" * (38 + w))
        for e in by["proposed"]:
            print(f"  {e['date']:10} {e['amount_nok']:>10.2f}  {e['currency']:3} "
                  f"{e['account']:5} {(e.get('vendor') or ''):{w}} {e['vatType']}")
        print()

    if by["needs_review"]:
        print("NEEDS REVIEW (skipped — decide manually):")
        for e in by["needs_review"]:
            print(f"  {e['date']}  {e['amount_nok']}  {e['currency']}  — {e['reason']}")
            print(f"      {e['description'][:80]}")
        print()

    print("Next: review the proposed drafts. To create them (DRAFTS only, safe):")
    print("  python3 reconcile.py ... --json  > plan.json")
    print("  # then for each proposed entry: bash fiken.sh draft-purchase '<entry.draft>'")
    print("Booking drafts to the ledger and marking Folio events complete are")
    print("separate, gated steps — never done by this script.")


if __name__ == "__main__":
    main()
