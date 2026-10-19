#!/usr/bin/env bash
# fiken-kladd.sh — Forberedelse in Fiken: drafts (kladd), inbox uploads and
# attachments. Nothing here changes the ledger. Posting a draft is Bokføring
# and lives in the fiken-bokforing skill; the code for it is not in this file.
#
# Auth: FIKEN_WRITE_TOKEN + FIKEN_COMPANY_SLUG in the environment, or in a file
# that FIKEN_ENV points at. Fiken has no draft-only role, so this token can
# technically post too; what keeps posting out of reach is that this skill has
# no command for it and the human posts in Fiken.
set -euo pipefail

SKILL="fiken-kladd"
BASE="https://api.fiken.no/api/v2"
if [ -z "${FIKEN_WRITE_TOKEN:-}" ] && [ -n "${FIKEN_ENV:-}" ] && [ -f "$FIKEN_ENV" ]; then
  set -a; . "$FIKEN_ENV"; set +a
fi
case "${1:-}" in ""|-h|--help|help) ;; *)  # help works without credentials
  : "${FIKEN_WRITE_TOKEN:?FIKEN_WRITE_TOKEN not set — export it, or set FIKEN_ENV to a file that defines it}"
  : "${FIKEN_COMPANY_SLUG:?FIKEN_COMPANY_SLUG not set — export it, or set FIKEN_ENV to a file that defines it}" ;;
esac
C="$BASE/companies/${FIKEN_COMPANY_SLUG:-}"
AUDIT_LOG="${FIKEN_FOLIO_AUDIT_LOG:-${XDG_STATE_HOME:-$HOME/.local/state}/fiken-folio-skills/audit.jsonl}"

_fmt() { if command -v jq >/dev/null 2>&1; then jq .; else cat; fi; }
_die() { echo "error: $*" >&2; exit 1; }
# curl with the token passed via a config on a file descriptor, so it never
# shows up in the process list (ps) the way a -H argument would.
_curl() { curl -K <(printf 'header = "Authorization: Bearer %s"\n' "$FIKEN_WRITE_TOKEN") "$@"; }
_num()  { [[ "$1" =~ ^[0-9]+$ ]] || _die "invalid id (numeric): $1"; }
_json() { # _json <@file.json | inline-json> -> validated body on stdout
  local arg="$1" data
  if [ "${arg:0:1}" = "@" ]; then data="$(cat "${arg:1}")"; else data="$arg"; fi
  printf '%s' "$data" | python3 -m json.tool >/dev/null || _die "invalid JSON body"
  printf '%s' "$data"
}

# One JSON line per write, appended in the same call as the write. For the
# human's own record; Fiken keeps its own history too.
_audit() { # _audit <METHOD> <path> <status> [location]
  ( umask 077; mkdir -p "$(dirname "$AUDIT_LOG")"
    printf '{"ts":"%s","skill":"%s","method":"%s","path":"%s","status":"%s","location":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SKILL" "$1" "$2" "$3" "${4:-}" >> "$AUDIT_LOG"
  ) || echo "warning: could not write audit log $AUDIT_LOG" >&2
}

# Write helper: one attempt only (a write is never retried automatically, so a
# timeout can't turn into a duplicate), never swallows the error body, logs the
# call, and reads the created resource back from Fiken.
_write() { # _write <METHOD> <url> [extra curl args...]
  local m="$1" url="$2"; shift 2
  local hdr body code loc
  hdr=$(mktemp); body=$(mktemp)
  code=$(_curl -sS -X "$m" -D "$hdr" -o "$body" -w '%{http_code}' "$@" "$url") || true
  code="${code:-000}"
  loc=$(awk 'tolower($1)=="location:"{print $2}' "$hdr" | tr -d '\r"\\')
  _audit "$m" "${url#"$BASE"}" "$code" "$loc"
  echo "HTTP $code${loc:+  ->  $loc}"
  [ -s "$body" ] && _fmt < "$body"
  rm -f "$hdr" "$body"
  case "$code" in 2*) ;; *) return 1;; esac
  # Only follow a Location on the Fiken API itself — the token goes with it.
  case "$loc" in "$BASE"/*)
    if _curl -fsS -o /dev/null -H "Accept: application/json" "$loc"; then echo "verified: $loc"
    else echo "warning: created, but could not read back $loc" >&2; fi ;;
  esac
}

usage() {
  cat <<'EOF'
fiken-kladd — forberedelse i Fiken. Lager kladder, endrer aldri regnskapet.

  inbox-upload <file> [desc]         Last kvittering opp til mottak
  draft-purchase <@file.json|json>   Opprett kjøpskladd (se REFERENCE for skjema)
  draft-offer <@file.json|json>      Opprett tilbud-kladd
  draft-invoice <@file.json|json>    Opprett faktura-kladd
  attach-draft <draftId> <file>      Legg kvittering på en kjøpskladd

Kladder bokføres av et menneske i Fiken. Hvert skrivekall logges til
$FIKEN_FOLIO_AUDIT_LOG (standard ~/.local/state/fiken-folio-skills/audit.jsonl).
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  inbox-upload)
    [ $# -ge 1 ] || _die "usage: inbox-upload <file> [description]"
    file="$1"; desc="${2:-Lastet opp via fiken-kladd}"; [ -f "$file" ] || _die "no such file: $file"
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

  ""|-h|--help|help) usage ;;
  *) _die "unknown command: $cmd (try: fiken-kladd help)" ;;
esac
