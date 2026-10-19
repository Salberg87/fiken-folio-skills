#!/usr/bin/env bash
# folio.sh — thin curl wrapper for the Folio API (https://api.folio.no/v2)
# Read + bookkeeping only. No payment commands by design (and a read/bookkeeping
# API key has no payment scope anyway).
#
# Auth: export FOLIO_API_KEY=... in your environment. Optionally point
# FOLIO_ENV at a file that defines it (export FOLIO_ENV=~/.config/folio/.env).
set -euo pipefail

BASE="https://api.folio.no/v2"
if [ -z "${FOLIO_API_KEY:-}" ] && [ -n "${FOLIO_ENV:-}" ] && [ -f "$FOLIO_ENV" ]; then
  set -a; . "$FOLIO_ENV"; set +a
fi
case "${1:-}" in ""|-h|--help|help) ;; *)  # help works without credentials
  : "${FOLIO_API_KEY:?FOLIO_API_KEY not set — export it, or set FOLIO_ENV to a file that defines it}" ;;
esac

# Pretty-print JSON if jq is present and the input parses as a single value;
# else pass it through untouched, so a plain-text or malformed error body
# never turns into a jq parse error.
_fmt() {
  if command -v jq >/dev/null 2>&1; then
    local in out; in=$(cat)
    if out=$(printf '%s' "$in" | jq -e . 2>/dev/null); then
      printf '%s\n' "$out"
    else
      printf '%s\n' "$in"
    fi
  else cat; fi
}

_die() { echo "error: $*" >&2; exit 1; }

# curl with the API key passed via a config on a file descriptor, so the key
# never shows up in the process list (ps) the way a -H argument would.
_curl() { curl -K <(printf 'header = "Authorization: Bearer %s"\n' "$FOLIO_API_KEY") "$@"; }

_get() { # _get <path...>  -> JSON to stdout
  _curl -fsS -H "Accept: application/json" "$BASE$1"
}

# _write <curl args...> -> pretty body on stdout, "HTTP <code>" on stderr.
# Deliberately omits -f so 4xx/5xx bodies (which carry the API's error
# message) reach us instead of being swallowed.
_write() {
  local body rc=0 code
  body=$(mktemp) || _die "mktemp failed"
  code=$(_curl -sS -w '%{http_code}' -o "$body" "$@") || rc=$?
  if [ "$rc" -ne 0 ]; then rm -f "$body"; _die "curl failed (exit $rc)"; fi
  [ -s "$body" ] && _fmt < "$body"
  rm -f "$body"
  echo "HTTP $code" >&2
  case "$code" in 2*) return 0;; *) _die "request failed (HTTP $code)";; esac
}

# Input checks. Every value that lands in a URL goes through one of these, so
# an id like "../../payments/x" can't walk the request onto another endpoint
# (curl collapses ../ in paths).
_id()   { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || _die "invalid id: $1"; }
_date() { [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || _die "invalid date (YYYY-MM-DD): $1"; }

# raw paths: plain characters only, and no writes to money-movement or
# integration endpoints — regardless of what scope the API key has.
_rawpath() { # _rawpath <METHOD> <path>
  [[ "$2" =~ ^/[A-Za-z0-9/_=\&?-]*$ ]] || _die "REFUSED: path must start with / and use plain characters only: $2"
  [ "$1" = "GET" ] && return 0
  local p; p=$(printf '%s' "${2%%\?*}" | tr '[:upper:]' '[:lower:]' | tr -s '/')
  case "$p/" in */payments/*|*/integration/*)
    _die "REFUSED: $1 $2 — payment and integration endpoints are blocked in this wrapper";; esac
}

usage() {
  cat <<'EOF'
folio — Folio API helper (read + bookkeeping)

  accounts                                 List accounts (number, name, type, balance)
  balance <accountNumber> <YYYY-MM-DD>     Incoming/outgoing balance on a date
  transactions <start> [end] [opts]        Transactions in date range (YYYY-MM-DD)
        --account <n>                        ...for one account only
        --merchants                          include merchant info
  tx <id>                                  Single transaction by id
  events <start> [end] [opts]              Events (bookkeeping items) in date range
        --merchants --agents --cards         include extra info
  category <ledgerCategoryId>              Inspect a ledger category (vat, requirements)
  patch-event <eventId> [opts]            Update an event (bookkeeping fields)
        --purpose <t> --note <t> --participants <t> --category <ledgerCategoryId>
  complete <eventId>                       Mark event complete (bookført)
  uncomplete <eventId>                     Undo complete
  attach <eventId> <file.pdf|jpg|png>     Upload a receipt/attachment to an event
  download <attachmentId> <type> -o <f>   Download attachment
        type: original|cropped|128x128|256x256|512x512
  statement [YYYY MM | --range s e] -o f  Download account statement PDF
  raw GET <path>                          Escape hatch, read (e.g. raw GET /accounts)
  raw <METHOD> <path> [json] --confirm    Escape hatch, write (gated; payment and
                                           integration endpoints are always refused)

Dates are YYYY-MM-DD. All output is JSON unless a PDF/file is downloaded.
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  accounts) _get "/accounts" | _fmt ;;

  balance)
    [ $# -ge 2 ] || _die "usage: balance <accountNumber> <YYYY-MM-DD>"
    _id "$1"; _date "$2"
    _get "/accounts/$1/balance/$2" | _fmt ;;

  transactions)
    [ $# -ge 1 ] || _die "usage: transactions <start> [end] [--account n] [--merchants]"
    start="$1"; shift; end=""; acct=""; q=""
    while [ $# -gt 0 ]; do case "$1" in
      --account) acct="${2:-}"; _id "$acct"; shift 2;;
      --merchants) q="${q}&includeMerchants=true"; shift;;
      *) end="$1"; _date "$end"; shift;;
    esac; done
    _date "$start"
    qs="startDate=$start"; [ -n "$end" ] && qs="$qs&endDate=$end"; qs="$qs$q"
    if [ -n "$acct" ]; then _get "/accounts/$acct/transactions?$qs" | _fmt
    else _get "/transactions?$qs" | _fmt; fi ;;

  tx) [ $# -ge 1 ] || _die "usage: tx <id>"; _id "$1"; _get "/transactions/$1" | _fmt ;;

  events)
    [ $# -ge 1 ] || _die "usage: events <start> [end] [--merchants --agents --cards]"
    start="$1"; shift; end=""; q=""
    while [ $# -gt 0 ]; do case "$1" in
      --merchants) q="${q}&includeMerchants=true"; shift;;
      --agents) q="${q}&includeAgents=true"; shift;;
      --cards) q="${q}&includeCards=true"; shift;;
      *) end="$1"; _date "$end"; shift;;
    esac; done
    _date "$start"
    qs="startDate=$start"; [ -n "$end" ] && qs="$qs&endDate=$end"; qs="$qs$q"
    _get "/events?$qs" | _fmt ;;

  category) [ $# -ge 1 ] || _die "usage: category <id>"; _id "$1"; _get "/categories/$1" | _fmt ;;

  patch-event)
    [ $# -ge 1 ] || _die "usage: patch-event <eventId> [--purpose t --note t --participants t --category id]"
    id="$1"; shift; body="{}"; _id "$id"
    while [ $# -gt 0 ]; do case "$1" in
      --purpose) body=$(echo "$body" | jq --arg v "$2" '.purpose=$v'); shift 2;;
      --note) body=$(echo "$body" | jq --arg v "$2" '.note=$v'); shift 2;;
      --participants) body=$(echo "$body" | jq --arg v "$2" '.participants=$v'); shift 2;;
      --category) body=$(echo "$body" | jq --arg v "$2" '.ledgerCategoryId=$v'); shift 2;;
      *) _die "unknown arg: $1";;
    esac; done
    _write -X PATCH -H "Content-Type: application/json" -d "$body" "$BASE/events/$id" ;;

  complete) [ $# -ge 1 ] || _die "usage: complete <eventId>"; _id "$1"
    _write -X POST "$BASE/events/$1/complete" ;;
  uncomplete) [ $# -ge 1 ] || _die "usage: uncomplete <eventId>"; _id "$1"
    _write -X DELETE "$BASE/events/$1/complete" ;;

  attach)
    [ $# -ge 2 ] || _die "usage: attach <eventId> <file.pdf|jpg|png>"
    id="$1"; file="$2"; _id "$id"; [ -f "$file" ] || _die "no such file: $file"
    case "$file" in
      *.pdf) ct="application/pdf";; *.jpg|*.jpeg) ct="image/jpeg";; *.png) ct="image/png";;
      *) _die "unsupported type (pdf/jpg/png only): $file";;
    esac
    fn=$(basename "$file" | tr -d '"\r\n')
    _write -X POST -H "Content-Type: $ct" -H "Content-Disposition: attachment; filename=\"$fn\"" \
      --data-binary @"$file" "$BASE/events/$id/attachments" ;;

  download)
    [ $# -ge 4 ] || _die "usage: download <attachmentId> <type> -o <file>  (type: original|cropped|128x128|256x256|512x512)"
    aid="$1"; type="$2"; shift 2; out=""
    while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) shift;; esac; done
    [ -n "$out" ] || _die "missing -o <file>"
    _id "$aid"; case "$type" in original|cropped|128x128|256x256|512x512) ;; *) _die "invalid type: $type";; esac
    _curl -fsS "$BASE/attachments/$aid/$type" -o "$out"
    echo "saved $out" ;;

  statement)
    out=""; year=""; month=""; rstart=""; rend=""
    while [ $# -gt 0 ]; do case "$1" in
      -o) out="$2"; shift 2;;
      --range) rstart="$2"; rend="$3"; shift 3;;
      *) if [ -z "$year" ]; then year="$1"; else month="$1"; fi; shift;;
    esac; done
    [ -n "$out" ] || _die "missing -o <file.pdf>"
    if [ -n "$rstart" ]; then
      _date "$rstart"; _date "$rend"
      _curl -fsS "$BASE/statement?startDate=$rstart&endDate=$rend" -o "$out"
    else
      [ -n "$year" ] && [ -n "$month" ] || _die "usage: statement <YYYY> <MM> -o f  |  statement --range s e -o f"
      [[ "$year" =~ ^[0-9]{4}$ && "$month" =~ ^[0-9]{1,2}$ ]] || _die "invalid year/month: $year $month"
      _curl -fsS "$BASE/statement/$year/$month" -o "$out"
    fi
    echo "saved $out" ;;

  raw)
    [ $# -ge 2 ] || _die "usage: raw <METHOD> <path> [jsonBody] [--confirm]"
    m=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]'); path="$2"; shift 2; data=""; ok=""
    while [ $# -gt 0 ]; do case "$1" in --confirm) ok=1;; *) data="$1";; esac; shift; done
    _rawpath "$m" "$path"
    if [ "$m" = "GET" ]; then
      _get "$path" | _fmt
    else
      [ -n "$ok" ] || _die "REFUSED: raw $m is a write — add --confirm and confirm with the user first."
      if [ -n "$data" ]; then _write -X "$m" -H "Content-Type: application/json" -d "$data" "$BASE$path"
      else _write -X "$m" "$BASE$path"; fi
    fi ;;

  ""|-h|--help|help) usage ;;
  *) _die "unknown command: $cmd (try: folio help)" ;;
esac
