#!/usr/bin/env bash
# fiken.sh — read-only curl wrapper for the Fiken API (https://api.fiken.no/api/v2)
# This skill only reads. Drafts live in the fiken-kladd skill, posting to the
# ledger in fiken-bokforing. Code for writes is not in this file at all.
#
# Auth: set FIKEN_READ_TOKEN + FIKEN_COMPANY_SLUG in your environment, or put
# them in a file and point FIKEN_ENV at it (e.g. export FIKEN_ENV=~/.config/fiken/.env).
# Best: create the token as a Fiken user with "Se regnskapet uten å kunne gjøre
# endringer", so Fiken itself refuses writes made with it.
set -euo pipefail

BASE="https://api.fiken.no/api/v2"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Optional env file: only loaded if FIKEN_ENV is set, the file exists, and the
# token isn't already in the environment. No personal default path.
if [ -z "${FIKEN_READ_TOKEN:-}" ] && [ -n "${FIKEN_ENV:-}" ] && [ -f "$FIKEN_ENV" ]; then
  set -a; . "$FIKEN_ENV"; set +a
fi
case "${1:-}" in ""|-h|--help|help) ;; *)  # help works without credentials
  : "${FIKEN_READ_TOKEN:?FIKEN_READ_TOKEN not set — export it, or set FIKEN_ENV to a file that defines it}"
  : "${FIKEN_COMPANY_SLUG:?FIKEN_COMPANY_SLUG not set — export it, or set FIKEN_ENV to a file that defines it}" ;;
esac
export FIKEN_READ_TOKEN FIKEN_COMPANY_SLUG 2>/dev/null || true   # report.py reads them
: "${FIKEN_PAGE_SIZE:=1000}"   # lower only for testing pagination
C="$BASE/companies/${FIKEN_COMPANY_SLUG:-}"

_fmt() { if command -v jq >/dev/null 2>&1; then jq .; else cat; fi; }
_die() { echo "error: $*" >&2; exit 1; }
# curl with the token passed via a config on a file descriptor, so it never
# shows up in the process list (ps) the way a -H argument would.
_curl() { curl -K <(printf 'header = "Authorization: Bearer %s"\n' "$FIKEN_READ_TOKEN") "$@"; }
_get() { _curl -fsS -H "Accept: application/json" "$1"; }

# Input checks. Values that land in a URL go through these, so an id like
# "../../x" can't walk the request onto another endpoint (curl collapses ../).
_num()  { [[ "$1" =~ ^[0-9]+$ ]] || _die "invalid id (numeric): $1"; }
_date() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || _die "invalid date (YYYY-MM-DD): $1"; }
_rawpath() { [[ "$1" =~ ^/[A-Za-z0-9/_=\&?:-]*$ ]] || _die "REFUSED: path must start with / and use plain characters only: $1"; }

# GET a list endpoint, following fiken-api-page-count across all pages.
_get_all() { # _get_all <path-relative-to-BASE, may contain ?query>
  local path="$1" page=0 pc="" sep tmp
  tmp=$(mktemp -d)
  case "$path" in *\?*) sep='&';; *) sep='?';; esac
  while :; do
    _curl -fsS -D "$tmp/h" -H "Accept: application/json" \
      "$BASE$path${sep}pageSize=$FIKEN_PAGE_SIZE&page=$page" -o "$tmp/p$page.json"
    pc=$(awk 'tolower($1)=="fiken-api-page-count:"{print $2+0}' "$tmp/h")
    page=$((page+1))
    if [ -z "$pc" ] || [ "$page" -ge "$pc" ]; then break; fi
  done
  python3 -c '
import json, sys, glob, os
d = []
for f in sorted(glob.glob(os.path.join(sys.argv[1], "p*.json")),
                key=lambda x: int(os.path.basename(x)[1:-5])):
    d += json.load(open(f))
print(json.dumps(d, ensure_ascii=False))' "$tmp"
  rm -rf "$tmp"
}

# client-side date filter on a `.date` field, inclusive range.
# (Fiken has NO date query params on purchases/sales/journalEntries — this
# is the only correct way to filter by date.)
_filter_dates() { # _filter_dates <start> <end>
  python3 -c "import json,sys;s,e=sys.argv[1],sys.argv[2];d=json.load(sys.stdin);d=[x for x in d if s<=x.get('date','')<=e] if s else d;print(json.dumps(d,ensure_ascii=False,indent=2))" "$1" "$2"
}

usage() {
  cat <<'EOF'
fiken — Fiken regnskaps-API, kun lesing.

  whoami                          Innlogget bruker
  company                         Selskapsinfo
  accounts                        Kontoplan (kode + navn)
  balances <YYYY-MM-DD>           Saldo per konto på en dato
  costs <periode>                 Driftskostnader (kl. 4-7), bevegelse i perioden
  result <periode>                Resultat: inntekter, kostnader, driftsresultat
        periode: YYYY-MM | ytd | YYYY-MM..YYYY-MM
  purchases <start> [end]         Kjøp, filtrert klient-side på dato (YYYY-MM-DD)
  sales <start> [end]             Salg, filtrert på dato
  invoices                        Utgående fakturaer
  journal <start> [end]           Bilag (journalEntries), filtrert på dato
  transactions                    Regnskapstransaksjoner
  contacts [søk]                  Kontakter (valgfri navne-filter)
  products                        Produkter
  bank                            Bankkontoer
  inbox                           Mottak (ubehandlede dokumenter)
  drafts                          Kjøpskladder (purchase drafts)
  draft <draftId>                 Én kjøpskladd
  offer-drafts                    Tilbud-kladder (sales offer drafts)
  invoice-drafts                  Faktura-kladder (sales invoice drafts)
  raw GET <path>                  Escape hatch, kun lesing

Beløp fra Fiken er i ØRE (÷100 = NOK). Datoer YYYY-MM-DD. Lister henter
alle sider automatisk (fiken-api-page-count).
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  whoami)  _get "$BASE/user" | _fmt ;;
  company) _get "$C" | _fmt ;;
  accounts) _get_all "/companies/$FIKEN_COMPANY_SLUG/accounts" | _fmt ;;

  balances)
    [ $# -ge 1 ] || _die "usage: balances <YYYY-MM-DD>"; _date "$1"
    _get_all "/companies/$FIKEN_COMPANY_SLUG/accountBalances?date=$1" | _fmt ;;

  costs)  [ $# -ge 1 ] || _die "usage: costs <YYYY-MM | ytd | YYYY-MM..YYYY-MM>";  python3 "$HERE/report.py" costs  "$1" ;;
  result) [ $# -ge 1 ] || _die "usage: result <YYYY-MM | ytd | YYYY-MM..YYYY-MM>"; python3 "$HERE/report.py" result "$1" ;;

  purchases)
    [ $# -ge 1 ] || _die "usage: purchases <start> [end]"
    _get_all "/companies/$FIKEN_COMPANY_SLUG/purchases" | _filter_dates "${1:-}" "${2:-9999-12-31}" ;;
  sales)
    [ $# -ge 1 ] || _die "usage: sales <start> [end]"
    _get_all "/companies/$FIKEN_COMPANY_SLUG/sales" | _filter_dates "${1:-}" "${2:-9999-12-31}" ;;
  journal)
    [ $# -ge 1 ] || _die "usage: journal <start> [end]"
    _get_all "/companies/$FIKEN_COMPANY_SLUG/journalEntries" | _filter_dates "${1:-}" "${2:-9999-12-31}" ;;

  invoices)     _get_all "/companies/$FIKEN_COMPANY_SLUG/invoices" | _fmt ;;
  transactions) _get_all "/companies/$FIKEN_COMPANY_SLUG/transactions" | _fmt ;;
  products)     _get_all "/companies/$FIKEN_COMPANY_SLUG/products" | _fmt ;;
  bank)         _get_all "/companies/$FIKEN_COMPANY_SLUG/bankAccounts" | _fmt ;;
  inbox)        _get_all "/companies/$FIKEN_COMPANY_SLUG/inbox" | _fmt ;;
  drafts)       _get_all "/companies/$FIKEN_COMPANY_SLUG/purchases/drafts" | _fmt ;;
  draft)        [ $# -ge 1 ] || _die "usage: draft <draftId>"; _num "$1"; _get "$C/purchases/drafts/$1" | _fmt ;;
  offer-drafts)   _get_all "/companies/$FIKEN_COMPANY_SLUG/offers/drafts" | _fmt ;;
  invoice-drafts) _get_all "/companies/$FIKEN_COMPANY_SLUG/invoices/drafts" | _fmt ;;

  contacts)
    if [ $# -ge 1 ]; then _get_all "/companies/$FIKEN_COMPANY_SLUG/contacts" | python3 -c "import json,sys;q=sys.argv[1].lower();print(json.dumps([c for c in json.load(sys.stdin) if q in (c.get('name','') or '').lower()],ensure_ascii=False,indent=2))" "$1"
    else _get_all "/companies/$FIKEN_COMPANY_SLUG/contacts" | _fmt; fi ;;

  raw)
    [ $# -ge 2 ] || _die "usage: raw GET <path>"
    [ "$1" = "GET" ] || _die "REFUSED: this skill only reads. Writes are in fiken-kladd / fiken-bokforing."
    _rawpath "$2"; _get "$BASE$2" | _fmt ;;

  ""|-h|--help|help) usage ;;
  *) _die "unknown command: $cmd (try: fiken help)" ;;
esac
