# Security

These skills give an AI agent access to live accounting and banking data, so the guardrails live in the scripts, not in the prompts. See [Safety model](README.md#safety-model).

## Reporting a vulnerability

If you find a way around the guardrails (moving money through Folio, posting to the Fiken ledger without `--confirm`, leaking credentials), please report it privately: use [GitHub's private vulnerability reporting](https://github.com/Salberg87/fiken-folio-skills/security/advisories/new) or email fredrik@pifre.no. Don't open a public issue for it.

You can expect an answer within a few working days.

## Credentials

- Keep `FIKEN_API_TOKEN` and `FOLIO_API_KEY` in your environment or in an env file outside the repo. `.env` files are ignored by git.
- Give the Folio API key read and bookkeeping access only. The script has no payment command and refuses payment endpoints through `raw`, and the key shouldn't have payment scope either.
- The scripts send credentials only to `api.fiken.no` and `api.folio.no`, and pass them to curl on a file descriptor so they don't appear in the process list.
- `FIKEN_ENV` / `FOLIO_ENV` files are sourced as shell. Only point them at files you control.
