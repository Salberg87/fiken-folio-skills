#!/usr/bin/env bash
# folio-kladd.sh — Forberedelse in Folio: purpose, note, participants, category
# and receipts on bank events, without completing them.
#
# Folio completes an event by itself as soon as it has a ledger category and
# whatever that category requires. For a category that doesn't require a receipt
# (fees, interest, many transfers), setting the category alone completes it.
# Completing is Bokføring, so this script keeps every event in the one state
# where Folio can't complete it: no category, or a category that requires a
# receipt and no receipt yet. It reads the event and the category from Folio
# before each write and refuses the write that would leave that state. That
# step, and `complete`, belong to the human in Folio or to folio-bokforing.
#
# No payment commands: Folio's API can only create payment drafts that a person
# must sign in Folio, and this skill doesn't even do that.
#
# Auth: FOLIO_WRITE_KEY in the environment, or in a file FOLIO_ENV points at.
# Use a key without payment access.
set -euo pipefail

SKILL="folio-kladd"
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
# curl with the API key passed via a config on a file descriptor, so the key
# never shows up in the process list (ps) the way a -H argument would.
_curl() { curl -K <(printf 'header = "Authorization: Bearer %s"\n' "$FOLIO_WRITE_KEY") "$@"; }
_id() { [[ "$1" =~ ^[A-Za-z0-9_-]+$ ]] || _die "invalid id: $1"; }

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

# Reads the event and prints "<complete> <attachments> <categoryId or ->".
_state() {
  _curl -fsS -H "Accept: application/json" "$BASE/events/$1" | python3 -c '
import json, sys
e = json.load(sys.stdin)
e = e.get("event", e)
c = (e.get("ledgerCategory") or {}).get("id") or "-"
print(str(bool(e.get("complete"))).lower(), len(e.get("attachments") or []), c)'
}

# Reads a ledger category and prints "true" if it requires a receipt.
_needs_receipt() {
  _curl -fsS -H "Accept: application/json" "$BASE/categories/$1" | python3 -c '
import json, sys
c = json.load(sys.stdin)
c = c.get("category", c)
print("true" if c.get("requiresAttachment") is True else "false")'
}

usage() {
  cat <<'EOF'
folio-kladd — forberedelse i Folio. Fullfører aldri en hendelse.

  patch-event <eventId> [opts]          Oppdater en hendelse
        --purpose <t> --note <t> --participants <t> --category <ledgerCategoryId>
  attach <eventId> <file.pdf|jpg|png>   Last opp kvittering til en hendelse

Folio fullfører en hendelse selv når den har kategori og det kategorien krever.
Derfor holder skriptet hver hendelse der Folio ikke kan fullføre den: uten
kategori, eller med en kategori som krever kvittering og ingen kvittering ennå.
Sperrer (lest fra Folio før hvert kall):
  - fullførte hendelser endres ikke
  - kategori settes bare hvis den krever kvittering og hendelsen ikke har en
  - vedlegg legges ikke på en hendelse som har kategori
  - formål/notat endres ikke på en hendelse som Folio kan fullføre
Det steget som gjør hendelsen komplett, er bokføring. Det gjør du i Folio.
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  patch-event)
    [ $# -ge 1 ] || _die "usage: patch-event <eventId> [--purpose t --note t --participants t --category id]"
    id="$1"; shift; body="{}"; cat=""; _id "$id"
    while [ $# -gt 0 ]; do case "$1" in
      --purpose) body=$(printf '%s' "$body" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["purpose"]=sys.argv[1];print(json.dumps(d))' "$2"); shift 2;;
      --note) body=$(printf '%s' "$body" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["note"]=sys.argv[1];print(json.dumps(d))' "$2"); shift 2;;
      --participants) body=$(printf '%s' "$body" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["participants"]=sys.argv[1];print(json.dumps(d))' "$2"); shift 2;;
      --category) cat="$2"; _id "$cat"; body=$(printf '%s' "$body" | python3 -c 'import json,sys;d=json.load(sys.stdin);d["ledgerCategoryId"]=sys.argv[1];print(json.dumps(d))' "$2"); shift 2;;
      *) _die "unknown arg: $1";;
    esac; done
    st=$(_state "$id") || _die "could not read event $id"; read -r complete natt curcat <<<"$st"
    [ "$complete" = "false" ] || _die "REFUSED: event $id is already complete (bokført). Change it in Folio."
    if [ -n "$cat" ]; then
      [ "$natt" -eq 0 ] || _die "REFUSED: event $id has a receipt; setting a category can complete it, and that is bokføring. Set the category in Folio."
      need=$(_needs_receipt "$cat") || _die "could not read category $cat"
      [ "$need" = "true" ] || _die "REFUSED: category $cat doesn't require a receipt, so Folio may complete event $id as soon as it is set. That is bokføring. Set it in Folio."
    elif [ "$curcat" != "-" ]; then
      need=$(_needs_receipt "$curcat") || _die "could not read category $curcat"
      if [ "$natt" -gt 0 ] || [ "$need" != "true" ]; then
        _die "REFUSED: event $id has a category and nothing else blocks completion; any change can complete it. Finish it in Folio."
      fi
    fi
    _write PATCH "/events/$id" -H "Content-Type: application/json" -d "$body" ;;

  attach)
    [ $# -ge 2 ] || _die "usage: attach <eventId> <file.pdf|jpg|png>"
    id="$1"; file="$2"; _id "$id"; [ -f "$file" ] || _die "no such file: $file"
    case "$file" in
      *.pdf) ct="application/pdf";; *.jpg|*.jpeg) ct="image/jpeg";; *.png) ct="image/png";;
      *) _die "unsupported type (pdf/jpg/png only): $file";;
    esac
    st=$(_state "$id") || _die "could not read event $id"; read -r complete natt curcat <<<"$st"
    [ "$complete" = "false" ] || _die "REFUSED: event $id is already complete (bokført). Change it in Folio."
    [ "$curcat" = "-" ] || _die "REFUSED: event $id has a category; adding the receipt can complete it, and that is bokføring. Attach it in Folio."
    fn=$(basename "$file" | tr -d '"\r\n')
    _write POST "/events/$id/attachments" -H "Content-Type: $ct" -H "Content-Disposition: attachment; filename=\"$fn\"" \
      --data-binary @"$file" ;;

  ""|-h|--help|help) usage ;;
  *) _die "unknown command: $cmd (try: folio-kladd help)" ;;
esac
