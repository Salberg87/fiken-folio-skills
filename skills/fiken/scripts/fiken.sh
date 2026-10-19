#!/usr/bin/env bash
# fiken.sh — thin curl wrapper for the Fiken API (https://api.fiken.no/api/v2)
# Read freely. Writes create DRAFTS only. Posting a draft to the ledger
# (createPurchase) is gated behind --confirm AND requires explicit user OK.
#
# Auth: set FIKEN_API_TOKEN + FIKEN_COMPANY_SLUG in your environment, or put
# them in a file and point FIKEN_ENV at it (e.g. export FIKEN_ENV=~/.config/fiken/.env).
# The file should contain:
#   FIKEN_API_TOKEN=...
#   FIKEN_COMPANY_SLUG=your-company-as
set -euo pipefail

BASE="https://api.fiken.no/api/v2"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Optional env file: only loaded if FIKEN_ENV is set, the file exists, and the
# token isn't already in the environment. No personal default path.
if [ -z "${FIKEN_API_TOKEN:-}" ] && [ -n "${FIKEN_ENV:-}" ] && [ -f "$FIKEN_ENV" ]; then
  set -a; . "$FIKEN_ENV"; set +a
fi
case "${1:-}" in ""|-h|--help|help) ;; *)  # help works without credentials
  : "${FIKEN_API_TOKEN:?FIKEN_API_TOKEN not set — export it, or set FIKEN_ENV to a file that defines it}"
  : "${FIKEN_COMPANY_SLUG:?FIKEN_COMPANY_SLUG not set — export it, or set FIKEN_ENV to a file that defines it}" ;;
esac
: "${FIKEN_PAGE_SIZE:=1000}"   # lower only for testing pagination
C="$BASE/companies/${FIKEN_COMPANY_SLUG:-}"

_fmt() { if command -v jq >/dev/null 2>&1; then jq .; else cat; fi; }
_die() { echo "error: $*" >&2; exit 1; }
# curl with the token passed via a config on a file descriptor, so it never
# shows up in the process list (ps) the way a -H argument would.
_curl() { curl -K <(printf 'header = "Authorization: Bearer %s"\n' "$FIKEN_API_TOKEN") "$@"; }
_get() { _curl -fsS -H "Accept: application/json" "$1"; }

# Input checks. Values that land in a URL go through these, so an id like
# "../../x" can't walk the request onto another endpoint (curl collapses ../).
_num()  { [[ "$1" =~ ^[0-9]+$ ]] || _die "invalid id (numeric): $1"; }
_date() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || _die "invalid date (YYYY-MM-DD): $1"; }
_rawpath() { [[ "$1" =~ ^/[A-Za-z0-9/_=\&?:-]*$ ]] || _die "REFUSED: path must start with / and use plain characters only: $1"; }
_json() { # _json <@file.json | inline-json> -> validated body on stdout
  local arg="$1" data
  if [ "${arg:0:1}" = "@" ]; then data="$(cat "${arg:1}")"; else data="$arg"; fi
  printf '%s' "$data" | python3 -m json.tool >/dev/null || _die "invalid JSON body"
  printf '%s' "$data"
}

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

# Write helper: never swallows the error body, surfaces HTTP code and the
# Location header (Fiken returns the created resource URL there).
_write() { # _write <METHOD> <url> [extra curl args...]
  local m="$1" url="$2"; shift 2
  local hdr body code loc
  hdr=$(mktemp); body=$(mktemp)
  code=$(_curl -sS -X "$m" \
    -D "$hdr" -o "$body" -w '%{http_code}' "$@" "$url") || true
  loc=$(awk 'tolower($1)=="location:"{print $2}' "$hdr" | tr -d '\r')
  echo "HTTP $code${loc:+  ->  $loc}"
  [ -s "$body" ] && _fmt < "$body"
  rm -f "$hdr" "$body"
  case "$code" in 2*) return 0;; *) return 1;; esac
}

# client-side date filter on a `.date` field, inclusive range.
# (Fiken has NO date query params on purchases/sales/journalEntries — this
# is the only correct way to filter by date.)
_filter_dates() { # _filter_dates <start> <end>
  python3 -c "import json,sys;s,e=sys.argv[1],sys.argv[2];d=json.load(sys.stdin);d=[x for x in d if s<=x.get('date','')<=e] if s else d;print(json.dumps(d,ensure_ascii=False,indent=2))" "$1" "$2"
}

usage() {
  cat <<'EOF'
fiken — Fiken regnskaps-API helper.  Lesing fritt · skriving KUN som kladd.

READ
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

WRITE — KLADD (trygt, ingen bokføring)
  inbox-upload <file> [desc]      Last kvittering opp til mottak
  draft-purchase <@file.json|json>  Opprett kjøpskladd (se REFERENCE for skjema)
  draft-offer <@file.json|json>     Opprett tilbud-kladd (se REFERENCE for skjema)
  draft-invoice <@file.json|json>   Opprett faktura-kladd (se REFERENCE for skjema)
  attach-draft <draftId> <file>   Legg kvittering på en kjøpskladd

WRITE — BOKFØRING (irreversibelt i regnskap — krever --confirm + din OK)
  post-draft <draftId> --confirm  Bokfør kladd → faktisk kjøp

  raw GET <path>                  Escape hatch (lesing)
  raw <METHOD> <path> [json] --confirm   Escape hatch (skriving, gated)

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

  # ---- WRITE: drafts (safe) ----
  inbox-upload)
    [ $# -ge 1 ] || _die "usage: inbox-upload <file> [description]"
    file="$1"; desc="${2:-Lastet opp via fiken-skill}"; [ -f "$file" ] || _die "no such file: $file"
    fn=$(basename "$file")
    # --form-string: a description starting with @ or < must not read a local file
    _write POST "$C/inbox" -F "file=@$file" --form-string "filename=$fn" --form-string "name=$fn" --form-string "description=$desc" ;;

  draft-purchase)
    [ $# -ge 1 ] || _die "usage: draft-purchase <@file.json | inline-json>"
    data=$(_json "$1")
    _write POST "$C/purchases/drafts" -H "Content-Type: application/json" -d "$data" ;;

  draft-offer)
    [ $# -ge 1 ] || _die "usage: draft-offer <@file.json | inline-json>"
    data=$(_json "$1")
    _write POST "$C/offers/drafts" -H "Content-Type: application/json" -d "$data" ;;

  draft-invoice)
    [ $# -ge 1 ] || _die "usage: draft-invoice <@file.json | inline-json>"
    data=$(_json "$1")
    _write POST "$C/invoices/drafts" -H "Content-Type: application/json" -d "$data" ;;

  attach-draft)
    [ $# -ge 2 ] || _die "usage: attach-draft <draftId> <file>"
    id="$1"; file="$2"; _num "$id"; [ -f "$file" ] || _die "no such file: $file"
    fn=$(basename "$file")
    _write POST "$C/purchases/drafts/$id/attachments" -F "file=@$file" --form-string "filename=$fn" ;;

  # ---- WRITE: posting to ledger (GATED) ----
  post-draft)
    [ $# -ge 1 ] || _die "usage: post-draft <draftId> --confirm"
    id="$1"; shift; ok=""; _num "$id"
    while [ $# -gt 0 ]; do case "$1" in --confirm) ok=1;; esac; shift; done
    [ -n "$ok" ] || _die "REFUSED: post-draft bokfører kladd $id til regnskapet (irreversibelt). Legg til --confirm OG bekreft med bruker først."
    _write POST "$C/purchases/drafts/$id/createPurchase" ;;

  raw)
    [ $# -ge 2 ] || _die "usage: raw <METHOD> <path> [json] [--confirm]"
    m="$1"; path="$2"; shift 2; data=""; ok=""
    while [ $# -gt 0 ]; do case "$1" in --confirm) ok=1;; *) data="$1";; esac; shift; done
    _rawpath "$path"
    if [ "$m" = "GET" ]; then
      _get "$BASE$path" | _fmt
    else
      [ -n "$ok" ] || _die "REFUSED: raw $m is a write — add --confirm and confirm with user first."
      if [ -n "$data" ]; then _write "$m" "$BASE$path" -H "Content-Type: application/json" -d "$data"
      else _write "$m" "$BASE$path"; fi
    fi ;;

  ""|-h|--help|help) usage ;;
  *) _die "unknown command: $cmd (try: fiken help)" ;;
esac
