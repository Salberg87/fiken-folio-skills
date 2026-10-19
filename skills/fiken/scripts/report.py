#!/usr/bin/env python3
"""Period reports for the Fiken API (costs / result), computed from the
general ledger: movement = accountBalances(period end) - accountBalances(day
before period start), per account. Norwegian standard chart: class 3 =
revenue, 4-7 = costs, 8 = finance/tax. Fiken amounts are in øre (÷100 = NOK).

Usage: report.py <mode: costs|result> <period>
       period: YYYY-MM | ytd | YYYY-MM..YYYY-MM
Env:   FIKEN_READ_TOKEN, FIKEN_COMPANY_SLUG
Stdlib only — no external deps.
"""
import os, sys, json, calendar, datetime, urllib.request, urllib.error

BASE = "https://api.fiken.no/api/v2"
TOKEN = os.environ.get("FIKEN_READ_TOKEN")
SLUG = os.environ.get("FIKEN_COMPANY_SLUG")


def die(msg):
    print(f"error: {msg}", file=sys.stderr)
    sys.exit(1)


def get_all(path, params=""):
    """Paginated GET -> merged list. Empty list on 400 (date before start)."""
    out, page = [], 0
    while True:
        url = f"{BASE}/companies/{SLUG}{path}?{params}&pageSize=1000&page={page}"
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
        try:
            with urllib.request.urlopen(req) as r:
                rows = json.load(r)
                pc = int(r.headers.get("fiken-api-page-count", 1) or 1)
        except urllib.error.HTTPError as e:
            if e.code == 400:
                return []
            die(f"HTTP {e.code} on {path}: {e.read().decode()[:200]}")
        out += rows
        page += 1
        if page >= pc:
            return out


def balances(date):
    """code -> balance (øre) as of `date`."""
    return {a["code"]: a.get("balance", 0) for a in get_all("/accountBalances", f"date={date}")}


def account_names():
    """code -> name from the chart of accounts (sub-account codes fall back
    to their parent, e.g. 1920:10001 -> 1920)."""
    return {a["code"]: a.get("name", "") for a in get_all("/accounts")}


def month_end(y, m):
    return f"{y:04d}-{m:02d}-{calendar.monthrange(y, m)[1]:02d}"


def parse_period(period):
    """-> (prev_end, end, label). prev_end = last day before the period."""
    if period == "ytd":
        today = datetime.date.today()
        start, end_ym = (today.year, 1), (today.year, today.month)
        label = f"ytd {today.year} (tom. {today:%Y-%m-%d})"
        end = f"{today:%Y-%m-%d}"
    elif ".." in period:
        a, b = period.split("..", 1)
        start = tuple(int(x) for x in a.split("-"))
        end_ym = tuple(int(x) for x in b.split("-"))
        label = f"{a}..{b}"
        end = month_end(*end_ym)
    else:
        y, m = (int(x) for x in period.split("-"))
        start, label, end = (y, m), period, month_end(y, m)
    py, pm = (start[0] - 1, 12) if start[1] == 1 else (start[0], start[1] - 1)
    return month_end(py, pm), end, label


def nok(ore):
    return f"{ore/100:,.0f}".replace(",", " ")


def cls(code):
    return code[:1]


def main():
    if len(sys.argv) != 3:
        die("usage: report.py <costs|result> <YYYY-MM | ytd | YYYY-MM..YYYY-MM>")
    mode, period = sys.argv[1], sys.argv[2]
    if not TOKEN or not SLUG:
        die("FIKEN_READ_TOKEN / FIKEN_COMPANY_SLUG not set")
    prev_end, end, label = parse_period(period)
    cur, prv = balances(end), balances(prev_end)
    if not cur and not prv:
        die(f"ingen kontosaldoer i perioden {label} — sjekk perioden (regnskap fra accountingStartDate)")
    mv = {c: cur.get(c, 0) - prv.get(c, 0) for c in set(cur) | set(prv)}
    names = account_names()

    def name(code):
        n = names.get(code) or names.get(code.split(":")[0], "")
        return n if len(n) <= 45 else n[:44] + "…"

    if mode == "costs":
        rows = sorted(((c, v) for c, v in mv.items() if cls(c) in "4567" and v),
                      key=lambda x: -x[1])
        print(f"Driftskostnader (klasse 4-7) — {label}  [{prev_end} → {end}]\n")
        if not rows:
            print("  Ingen bevegelse på kostnadskontoene i perioden.")
            return
        w = max(len(name(c)) for c, _ in rows)
        print(f"{'Konto':7} {'Navn':{w}} {'NOK':>12}")
        print("-" * (21 + w))
        tot = 0
        for c, v in rows:
            tot += v
            print(f"{c:7} {name(c):{w}} {nok(v):>12}")
        print("-" * (21 + w))
        print(f"{'SUM':7} {'':{w}} {nok(tot):>12}")

    elif mode == "result":
        rev = -sum(v for c, v in mv.items() if cls(c) == "3")   # revenue is credit (negative)
        cost = sum(v for c, v in mv.items() if cls(c) in "4567")
        fin = sum(v for c, v in mv.items() if cls(c) == "8")
        print(f"Resultat — {label}  [{prev_end} → {end}]\n")
        if not rev and not cost and not fin:
            print("  Ingen resultatbevegelse i perioden.")
            return
        print(f"  Driftsinntekter (kl. 3):   {nok(rev):>14}")
        print(f"  Driftskostnader (kl. 4-7): {nok(cost):>14}")
        print(f"  {'-'*40}")
        print(f"  Driftsresultat:            {nok(rev - cost):>14}")
        if fin:
            print(f"  Finans/skatt (kl. 8):      {nok(fin):>14}")
    else:
        die(f"unknown mode: {mode} (costs|result)")


if __name__ == "__main__":
    main()
