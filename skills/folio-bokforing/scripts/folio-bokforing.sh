#!/usr/bin/env bash
# folio-bokforing.sh — Bokføring in Folio: complete events (with Folio's Fiken
# integration on, that books them in Fiken), set categories and attach receipts
# without the folio-kladd guards, plus a write escape hatch. Opt-in skill for
# the "Bokføring med godkjenning" Modus.
#
# There is no deterministic lock here. --confirm marks the command as booking so
# the agent tool can stop it (e.g. a Claude Code ask rule on "*--confirm*"); the
# agent can still type the flag itself.
#
# Money is out of reach regardless: writes to /payments, /salary and
# /integration are refused, and Folio's API can only create payment drafts that
# a person must sign in Folio anyway.
#
# Auth: FOLIO_WRITE_KEY in the environment, or in a file FOLIO_ENV points at.
set -euo pipefail

SKILL="folio-bokforing"
BASE="https://api.folio.no/v2"
if [ -z "${FOLIO_WRITE_KEY:-}" ] && [ -n "${FOLIO_ENV:-}" ] && [ -f "$FOLIO_ENV" ]; then
  set -a; . "$FOLIO_ENV"; set +a
fi
case "${1:-}" in ""|-h|--help|help) ;; *)  # help works without credentials
  : "${FOLIO_WRITE_KEY:?FOLIO_WRITE_KEY not set — export it, or set FOLIO_ENV to a file that defines it}" ;;
esac
AUDIT_LOG="${FIKEN_FOLIO_AUDIT_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/fiken-folio-skills/audit.jsonl}"

_fmt() {
  if command -v jq >/dev/null 2>&1; then
    local in out; in=$(cat)
    if out=$(printf '%s' "$in" | jq -e . 2>/dev/null); then printf '%s\n' "$out"; else printf '%s\n' "$in"; fi
  else cat; fi
}
_die() { echo "error: $*" >&2; exit 1; }
_curl() { curl -K <(printf 'header = "Authorization: Bearer %s"\n' "$FOLIO_WRITE_KEY") "$@"; }
_id() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || _die "invalid id: $1"; }

# raw paths: plain characters only, and never money movement or integration.
_rawpath() { # _rawpath <path>
  [[ "$1" =~ ^/[A-Za-z0-9/_=\&?-]*$ ]] || _die "REFUSED: path must start with / and use plain characters only: $1"
  local p; p=$(printf '%s' "${1%%\?*}" | tr '[:upper:]' '[:lower:]' | tr -s '/')
  case "$p/" in */payments/*|*/salary/*|*/integration/*)
    _die "REFUSED: $1 — payment, salary and integration endpoints are blocked";; esac
}

_audit() { # _audit <METHOD> <path> <status>
  ( umask 077; mkdir -p "$(dirname "$AUDIT_LOG")"
    printf '{"ts":"%s","skill":"%s","method":"%s","path":"%s","status":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SKILL" "$1" "$2" "$3" >> "$AUDIT_LOG"
  ) || echo "warning: could not write audit log $AUDIT_LOG" >&2
}

# _write <METHOD> <path> [curl args...] — one attempt, error body shown, logged.
_write() {
  local m="$1" path="$2"; shift 2
  local body code
  body=$(mktemp)
  code=$(_curl -sS -X "$m" -w '%{http_code}' -o "$body" "$@" "$BASE$path") || true
  code="${code:-000}"
  _audit "$m" "$path" "$code"
  [ -s "$body" ] && _fmt < "$body"
  rm -f "$body"
  echo "HTTP $code" >&2
  case "$code" in 2*) return 0;; *) _die "request failed (HTTP $code)";; esac
}

_confirmed() { for a in "$@"; do [ "$a" = "--confirm" ] && return 0; done; return 1; }

usage() {
  cat <<'EOF'
folio-bokforing — bokføring i Folio. Kun med brukerens ja, og alltid --confirm.

  complete <eventId> --confirm                 Fullfør hendelse (bokfører i Fiken via integrasjonen)
  uncomplete <eventId> --confirm               Angre fullføring
  patch-event <eventId> [opts] --confirm       Oppdater uten kladd-sperrene
        --purpose <t> --note <t> --participants <t> --category <ledgerCategoryId>
  attach <eventId> <file> --confirm            Last opp kvittering uten kladd-sperrene
  raw <METHOD> <path> [json] --confirm         Escape hatch (aldri /payments, /salary, /integration)

Flagget er ikke en lås: sørg for at agentverktøyet spør deg før kommandoer
med --confirm kjøres. Hvert kall logges.
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in ""|-h|--help|help) ;; *)
  _confirmed "$@" || _die "REFUSED: $cmd is bokføring. Confirm with the user, then add --confirm." ;;
esac
case "$cmd" in
  complete)   [ $# -ge 1 ] || _die "usage: complete <eventId> --confirm"; _id "$1"; _write POST "/events/$1/complete" ;;
  uncomplete) [ $# -ge 1 ] || _die "usage: uncomplete <eventId> --confirm"; _id "$1"; _write DELETE "/events/$1/complete" ;;

  patch-event)
    [ $# -ge 1 ] || _die "usage: patch-event <eventId> [opts] --confirm"
    id="$1"; shift; body="{}"; _id "$id"
    while [ $# -gt 0 ]; do case "$1" in
      --purpose) body=$(printf '%s' "$body" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["purpose"]=sys.argv[1];print(json.dumps(d))' "$2"); shift 2;;
      --note) body=$(printf '%s' "$body" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["note"]=sys.argv[1];print(json.dumps(d))' "$2"); shift 2;;
      --participants) body=$(printf '%s' "$body" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["participants"]=sys.argv[1];print(json.dumps(d))' "$2"); shift 2;;
      --category) _id "$2"; body=$(printf '%s' "$body" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["ledgerCategoryId"]=sys.argv[1];print(json.dumps(d))' "$2"); shift 2;;
      --confirm) shift;;
      *) _die "unknown arg: $1";;
    esac; done
    _write PATCH "/events/$id" -H "Content-Type: application/json" -d "$body" ;;

  attach)
    [ $# -ge 2 ] || _die "usage: attach <eventId> <file.pdf|jpg|png> --confirm"
    id="$1"; file="$2"; _id "$id"; [ -f "$file" ] || _die "no such file: $file"
    case "$file" in
      *.pdf) ct="application/pdf";; *.jpg|*.jpeg) ct="image/jpeg";; *.png) ct="image/png";;
      *) _die "unsupported type (pdf/jpg/png only): $file";;
    esac
    fn=$(basename "$file" | tr -d '"\r\n')
    _write POST "/events/$id/attachments" -H "Content-Type: $ct" -H "Content-Disposition: attachment; filename=\"$fn\"" \
      --data-binary @"$file" ;;

  raw)
    [ $# -ge 2 ] || _die "usage: raw <METHOD> <path> [json] --confirm"
    m=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]'); path="$2"; shift 2; data=""
    while [ $# -gt 0 ]; do case "$1" in --confirm) ;; *) data="$1";; esac; shift; done
    _rawpath "$path"
    if [ -n "$data" ]; then _write "$m" "$path" -H "Content-Type: application/json" -d "$data"
    else _write "$m" "$path"; fi ;;

  ""|-h|--help|help) usage ;;
  *) _die "unknown command: $cmd (try: folio-bokforing help)" ;;
esac
