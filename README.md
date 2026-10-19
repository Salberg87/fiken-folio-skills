# fiken-folio-skills

**Fiken and Folio skills for Claude Code and other AI agents. Let your agent read your Norwegian accounting and bank, prepare drafts and reconcile, while posting and paying stay with you.**

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](LICENSE)
[![Agent Skills](https://img.shields.io/badge/Agent%20Skills-SKILL.md-black)](https://agentskills.io)
[![Claude Code](https://img.shields.io/badge/Claude%20Code-ready-d97757)](https://claude.com/claude-code)

Plug-and-play **Agent Skills** for [Claude Code](https://claude.com/claude-code) and other agents that read `SKILL.md`, for the tools Norwegian small businesses run on. You choose how far the agent may go by choosing which skills to install:

| Skill | What it does | Modus |
| --- | --- | --- |
| [**fiken**](skills/fiken) | Read [Fiken](https://fiken.no): costs/result reports, balances, purchases, sales, invoices, contacts, drafts, inbox | Read only |
| [**folio**](skills/folio) | Read [Folio](https://folio.no): accounts, balances, transactions, bookkeeping events, receipts, statement PDFs | Read only |
| [**fiken-kladd**](skills/fiken-kladd) | Create purchase, offer and invoice drafts; upload receipts; add contacts, projects and time entries | Prepare |
| [**folio-kladd**](skills/folio-kladd) | Add purpose, note, receipt or a receipt-requiring category to bank events, without ever completing them | Prepare |
| [**reconcile**](skills/reconcile) | Match Folio card charges against Fiken and draft what's missing; safe to run twice | Prepare |
| [**fiken-bokforing**](skills/fiken-bokforing) | Post drafts to the ledger after you say yes | Book (opt-in) |
| [**folio-bokforing**](skills/folio-bokforing) | Complete bank events after you say yes | Book (opt-in) |

Thin, auditable `curl` wrappers (bash + a little stdlib Python). No SDK, no daemon, no telemetry — you can read every line in a minute.

## What you can ask

- *"What did we spend on software in Q3?"* (fiken `costs`)
- *"Show the result for September next to August."* (fiken `result`)
- *"List last week's Folio card transactions with merchant names."* (folio `transactions --merchants`)
- *"Upload this receipt to the Fiken inbox."* (fiken-kladd `inbox-upload`)
- *"Categorize September's software subscriptions in Folio."* (folio-kladd `patch-event`)
- *"Reconcile September's Folio card charges against Fiken and draft what's missing."* (reconcile)

## Why this exists

- **Covers Folio, not just Fiken.** If you bank with Folio, the agent can see transactions and help with the bookkeeping on them.
- **Built for the regnskap reality, not just the API.** `costs` and `result` come from general-ledger movement (the authoritative figure), pagination is automatic, amounts are converted from øre, and the sharp edges we hit in production are written into the skills.
- **The line between preparing and booking is drawn in code and at the provider**, not in a prompt. Most AI-accounting tools ask the model to "please confirm". Here the prepare skills simply can't book.

## Security model

Accounting and banking data needs a lock that doesn't depend on the agent behaving. These skills use three layers, and none of them is a prompt:

1. **The agent prepares, you commit — in the provider's own app.** Posting a draft in Fiken and completing an event in Folio are yours. Folio already works this way for money: a payment created through its API is a draft until a person signs it in Folio, and the API has no way to sign.
2. **The code for committing isn't there unless you install it.** `fiken` and `folio` have no write commands at all; `fiken-kladd` and `folio-kladd` can't post or complete. A config flag could be flipped by the agent; code that isn't on disk can't be run. Check it yourself: `grep -rn "createPurchase\|/complete" skills/*-kladd/scripts skills/fiken/scripts skills/folio/scripts` finds nothing.
3. **The agent gets its own, least-privileged identity.** Each tier reads its own variable (`*_READ_*` vs `*_WRITE_*`), so the read skills can run on a key the provider itself limits.

What enforces what:

| Risk | Stopped by | Holds even if the agent misbehaves? |
| --- | --- | --- |
| Moving money from Folio | Folio: API payments are drafts until a person signs. The skills also refuse `/payments`, `/salary` and `/integration`. | Yes |
| Writes with the read skills | Fiken: a token from a user with *Se regnskapet uten å kunne gjøre endringer*. Folio: a read-only key, if your plan offers one. | Yes, with those credentials |
| Posting in Fiken / completing in Folio from the prepare skills | No command for it; `fiken-kladd`'s `raw` only writes to an allow-list (contacts, projects, time entries, drafts, inbox); `folio-kladd` reads each event and category first and refuses any write that would let Folio complete the event by itself | Against an agent that follows the skill, yes. An agent holding a full-access token could write its own HTTP call; Fiken has no draft-only role. |
| Booking with the opt-in skills | Your agent tool's permission prompt. The commands require `--confirm`, but an agent can type that. | Only if your agent tool asks you. In Claude Code, don't auto-approve commands containing `--confirm`, and don't run bypass mode against your books. |

Also: tokens are passed to curl on a file descriptor, never as arguments, so they don't show up in `ps`; every id that goes into a URL is validated; every write is logged to `~/.local/state/fiken-folio-skills/audit.jsonl` and never retried automatically, so a timeout can't become a duplicate.

## Install

Pick your level (via the [`skills`](https://www.npmjs.com/package/skills) CLI; add `-g` for user-level):

```bash
# Read only
npx skills add Salberg87/fiken-folio-skills -s fiken folio

# Prepare (recommended): read + drafts + reconcile
npx skills add Salberg87/fiken-folio-skills -s fiken folio fiken-kladd folio-kladd reconcile

# Book with approval (opt-in): everything
npx skills add Salberg87/fiken-folio-skills -s '*'
```

Only use Fiken? Leave out the `folio*` skills and `reconcile`. Manual install: copy the folders you want from `skills/` into `~/.claude/skills/`.

## Setup

**Fiken** — personal API tokens are created under *Rediger konto → API*. Fiken's API module costs 99 kr/month per company.

```bash
export FIKEN_COMPANY_SLUG=your-company-as
export FIKEN_READ_TOKEN=...    # for fiken. Best: from a user with "Se regnskapet uten å kunne gjøre endringer"
export FIKEN_WRITE_TOKEN=...   # for fiken-kladd / fiken-bokforing: a user with full access
# or put them in a file: export FIKEN_ENV=~/.config/fiken/.env
```

**Folio** — keys at <https://app.folio.no/til/api-tilgang>:

```bash
export FOLIO_READ_KEY=...      # for folio: read access only if offered
export FOLIO_WRITE_KEY=...     # for folio-kladd / folio-bokforing: no payment access
# or: export FOLIO_ENV=~/.config/folio/.env
```

Only have one key? You can use the same value for both variables; then the tiers are separated by which skills you installed, not by the provider. Requires `curl`, `python3`, and (optional, for pretty output) `jq`.

## Quick check

```bash
bash skills/fiken/scripts/fiken.sh whoami
bash skills/folio/scripts/folio.sh accounts
bash skills/fiken-kladd/scripts/fiken-kladd.sh help
```

## Author

Built by **Fredrik Skorge Salberg** — [Pifre AS](https://pifre.no), Oslo. Made because running a Norwegian AS shouldn't mean clicking through three dashboards to answer "what did I spend last month."

Not affiliated with or endorsed by Fiken or Folio. "Fiken" and "Folio" are the trademarks of their respective owners; these skills just call their public APIs.

## Status

Early, and in use for our own monthly bookkeeping at Pifre AS. Use at your own risk on your own accounting data, and read the scripts before you run writes. Issues and ideas for more Norwegian business skills (Tripletex, PowerOffice, Altinn, Brønnøysund) are welcome.

## På norsk

Agent-skills som lar Claude Code og andre AI-agenter jobbe med regnskapet i Fiken og bedriftskontoen i Folio. Du velger selv hvor langt agenten får gå ved å velge hvilke skills du installerer: bare lesing, forberedelse (kladder, kvitteringer, kategorier og avstemming), eller bokføring etter at du har sagt ja. Bokføring og signering skjer ellers hos deg i Fiken og Folio, og agenten kan ikke flytte penger. Laget for små norske AS som vil bruke mindre tid på regnskap.

## License

[Apache License 2.0](LICENSE) — © 2026 Fredrik Skorge Salberg / Pifre AS. See [NOTICE](NOTICE).
