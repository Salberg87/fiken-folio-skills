# fiken-folio-skills

**Fiken and Folio skills for Claude Code and other AI agents. Let your agent read your Norwegian accounting and bank, draft bookings and reconcile, without ever being able to touch the money.**

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-SKILL.md-black)](https://agentskills.io)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-ready-d97757)](https://claude.com/claude-code)

Plug-and-play **Agent Skills** for [Claude Code](https://claude.com/claude-code) and other agents that read `SKILL.md`. A growing collection wrapping the tools Norwegian small businesses actually run on:

| Skill                             | What it does                                                                                                                                | Scope                                                                     |
| --------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| [**folio**](skills/folio)         | The [Folio](https://folio.no) business-banking API — accounts, transactions, balances, bookkeeping events, receipts, statement PDFs         | Read + bookkeeping only · **money movement is impossible**                |
| [**fiken**](skills/fiken)         | The [Fiken](https://fiken.no) accounting API — costs/result reports, balances, transactions, purchases, sales, invoices, contacts, receipts | Read freely · writes are **drafts only** · posting to the ledger is gated |
| [**reconcile**](skills/reconcile) | Match Folio card charges/events against Fiken and book the unmatched ones — offline planning, count-based dedup, VAT classification         | Plans offline · creates **drafts only** · booking + complete stay manual  |

Thin, auditable `curl` wrappers (bash + a little stdlib Python). No SDK, no daemon, no telemetry — you can read every line in a minute. The agent reads `SKILL.md`, runs one script, gets clean JSON or a formatted report.

## What you can ask

Once installed, just talk to your agent:

- *"What did we spend on software in Q3?"* (fiken `costs`)
- *"Show the result for September next to August."* (fiken `result`)
- *"Upload this receipt to the Fiken inbox."* (fiken `inbox-upload`)
- *"List last week's Folio card transactions with merchant names."* (folio `transactions --merchants`)
- *"Download the August account statement as PDF."* (folio `statement`)
- *"Reconcile September's Folio card charges against Fiken and draft what's missing."* (reconcile)

## Why this exists

- **Covers Folio, not just Fiken.** If you bank with Folio and want an AI agent to see your transactions and help with bookkeeping, the `folio` skill does exactly that — accounts, transactions, events, receipts, statements.
- **Safety is enforced in code, not asked for in a prompt.** Most AI-accounting tools wave a "⚠️ please confirm" comment at the model and hope. Here the guardrails are in the scripts: a payment is not a command that exists (and the escape hatch refuses payment endpoints), and posting to the ledger refuses to run without an explicit flag. A confused agent still can't move your money, and a booking always shows up as a deliberate, visible command.
- **Built for the regnskap reality, not just the API.** `costs` and `result` are computed from general-ledger movement (the authoritative figure), pagination is automatic, amounts are converted from øre — the things you'd otherwise get wrong.
- **Reconciliation that proposes, never commits.** The `reconcile` skill matches Folio charges to Fiken and drafts the bookings — but the matching is offline, the writes are drafts, and posting to the ledger or marking a bank event done stays a human decision. Automation up to the point where a mistake would cost you, and not one step further.

## Safety model

These skills touch live accounting and banking data, so the guardrails are baked into the scripts, not just the prompts:

- **Reads are free.** Anything that only fetches data runs without confirmation.
- **Folio cannot move money.** There is no payment command, the `raw` escape hatch refuses writes to `/payments` and `/integration`, and every id is validated so it can't be bent into another endpoint. Use an API key without payment scope as well, so there are two independent locks.
- **Fiken writes create drafts (kladd) only.** Posting a draft to the ledger (`bokføring`) is irreversible — it's gated behind an explicit `--confirm` flag enforced in the script _and_ the skill instructs the agent to get your OK first. No flag, no booking.
- **Every other write through `raw` needs `--confirm` too**, in both scripts.
- **The flag is a speed bump, not a lock.** An agent can type `--confirm`. The human check is your agent's permission prompt: in Claude Code, don't auto-approve Bash commands that contain `--confirm`, and you approve every booking yourself.
- **Credentials stay out of sight.** Tokens are passed to curl on a file descriptor, not as arguments, so they don't show up in `ps`. The scripts only talk to `api.fiken.no` and `api.folio.no`.

## Install

**Any agent, one command** (via the [`skills`](https://www.npmjs.com/package/skills) CLI):

```bash
npx skills add Salberg87/fiken-folio-skills            # pick skills interactively
npx skills add Salberg87/fiken-folio-skills -s '*' -g  # all skills, user-level
```

**Claude Code, manually:**

```bash
git clone https://github.com/Salberg87/fiken-folio-skills.git
cp -r fiken-folio-skills/skills/{fiken,folio,reconcile} ~/.claude/skills/
```

Each skill is a self-contained folder under `skills/`. For a single project instead, copy into `.claude/skills/` inside the project. `reconcile` uses the `fiken` and `folio` skills, so install all three if you want it.

## Setup

Each skill needs credentials in the environment. Export them in your shell, or keep them in a file and point an env var at it (the scripts auto-load it).

**Fiken** — personal API token from _Fiken → Innstillinger → API_:

```bash
export FIKEN_API_TOKEN=...
export FIKEN_COMPANY_SLUG=your-company-as
# or: cp skills/fiken/env.example ~/.config/fiken/.env && export FIKEN_ENV=~/.config/fiken/.env
```

**Folio** — API key from <https://app.folio.no/til/api-tilgang>:

```bash
export FOLIO_API_KEY=...
# or: cp skills/folio/env.example ~/.config/folio/.env && export FOLIO_ENV=~/.config/folio/.env
```

Requires `curl`, `python3`, and (optional, for pretty output) `jq`.

## Quick check

```bash
FIKEN_API_TOKEN=... FIKEN_COMPANY_SLUG=your-company-as \
  bash skills/fiken/scripts/fiken.sh whoami

FOLIO_API_KEY=... bash skills/folio/scripts/folio.sh accounts
```

Each script also has built-in help: `bash skills/fiken/scripts/fiken.sh help`.

## Author

Built by **Fredrik Skorge Salberg** — [Pifre AS](https://pifre.no), Oslo. Made because running a Norwegian AS shouldn't mean clicking through three dashboards to answer "what did I spend last month."

Not affiliated with or endorsed by Fiken or Folio. "Fiken" and "Folio" are the trademarks of their respective owners; these skills just call their public APIs.

## Status

Early, and in use for our own monthly bookkeeping at Pifre AS. Use at your own risk on your own accounting data, and read the scripts before you run writes. Issues and ideas for more Norwegian business skills (Tripletex, PowerOffice, Altinn, Brønnøysund) are welcome.

## På norsk

Agent-skills som lar Claude Code og andre AI-agenter jobbe med regnskapet i Fiken og bedriftskontoen i Folio. Agenten kan hente kostnader og resultat, se transaksjoner, laste opp kvitteringer, lage kjøpskladder og avstemme kortkjøp i Folio mot Fiken. Bokføring krever alltid din bekreftelse, og agenten har ingen mulighet til å flytte penger. Laget for små norske AS som vil bruke mindre tid på regnskap.

## License

[Apache License 2.0](LICENSE) — © 2026 Fredrik Skorge Salberg / Pifre AS. See [NOTICE](NOTICE).
