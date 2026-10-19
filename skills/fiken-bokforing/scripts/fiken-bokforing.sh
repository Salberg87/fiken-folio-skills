#!/usr/bin/env bash
# fiken-bokforing.sh — Bokføring in Fiken: post a draft to the ledger, plus a
# write escape hatch. Opt-in skill for the "Bokføring med godkjenning" Modus.
#
# There is no deterministic lock here. --confirm marks the command as booking so
# the agent tool can stop it (e.g. a Claude Code ask rule on "*--confirm*"); the
# agent can still type the flag itself. Install this skill only if you want the
# agent to book after you say yes. Otherwise post drafts in Fiken.
#
# Auth: FIKEN_WRITE_TOKEN + FIKEN_COMPANY_SLUG, or a file FIKEN_ENV points at.
set -euo pipefail

SKILL="fiken-bokforing"
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
_rawpath() { [[ "$1" =~ ^/[A-Za-z0-9/_=\&?:-]*$ ]] || _die "REFUSED: path must start with / and use plain characters only: $1"; }

_audit() { # _audit <METHOD> <path> <status> [location]
  ( umask 077; mkdir -p "$(dirname "$AUDIT_LOG")"
    printf '{"ts":"%s","skill":"%s","method":"%s","path":"%s","status":"%s","location":"%s"}\n' \
      "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$SKILL" "$1" "$2" "$3" "${4:-}" >> "$AUDIT_LOG"
  ) || echo "warning: could not write audit log $AUDIT_LOG" >&2
}

# One attempt only — a write is never retried automatically, so a timeout can't
# turn into a double booking. Logs the call and reads the result back.
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
  case "$loc" in "$BASE"/*)   # only follow a Location on the Fiken API — the token goes with it
    if _curl -fsS -o /dev/null -H "Accept: application/json" "$loc"; then echo "verified: $loc"
    else echo "warning: written, but could not read back $loc" >&2; fi ;;
  esac
}

usage() {
  cat <<'EOF'
fiken-bokforing — bokføring i Fiken (irreversibelt). Kun med brukerens ja.

  post-draft <draftId> --confirm         Bokfør kjøpskladd → faktisk kjøp
  raw <METHOD> <path> [json] --confirm   Escape hatch for skrivekall

Uten --confirm nektes alt. Flagget er ikke en lås: sørg for at agentverktøyet
spør deg før kommandoer med --confirm kjøres. Hvert kall logges.
EOF
}

cmd="${1:-}"; shift || true
case "$cmd" in
  post-draft)
    [ $# -ge 1 ] || _die "usage: post-draft <draftId> --confirm"
    id="$1"; shift; ok=""; _num "$id"
    while [ $# -gt 0 ]; do case "$1" in --confirm) ok=1;; esac; shift; done
    [ -n "$ok" ] || _die "REFUSED: post-draft bokfører kladd $id til regnskapet (irreversibelt). Bekreft med bruker, og legg til --confirm."
    _write POST "$C/purchases/drafts/$id/createPurchase" ;;

  raw)
    [ $# -ge 2 ] || _die "usage: raw <METHOD> <path> [json] --confirm"
    m="$1"; path="$2"; shift 2; data=""; ok=""
    while [ $# -gt 0 ]; do case "$1" in --confirm) ok=1;; *) data="$1";; esac; shift; done
    _rawpath "$path"
    [ -n "$ok" ] || _die "REFUSED: raw $m is a write — confirm with the user, then add --confirm."
    if [ -n "$data" ]; then _write "$m" "$BASE$path" -H "Content-Type: application/json" -d "$data"
    else _write "$m" "$BASE$path"; fi ;;

  ""|-h|--help|help) usage ;;
  *) _die "unknown command: $cmd (try: fiken-bokforing help)" ;;
esac
