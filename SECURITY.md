# Security

These skills give an AI agent access to live accounting and banking data, so the locks sit in the code and at the provider, not in the prompts. See [Security model](README.md#security-model).

## Reporting a vulnerability

If you find a way around the guardrails, please report it privately: use [GitHub's private vulnerability reporting](https://github.com/Salberg87/fiken-folio-skills/security/advisories/new) or email fredrik@pifre.no. Don't open a public issue for it. Examples of what counts:

- moving or cancelling money through Folio
- posting to the Fiken ledger or completing a Folio event with `fiken`, `folio`, `fiken-kladd` or `folio-kladd`
- getting `folio-kladd` to leave an event with both a receipt and a category
- leaking credentials

You can expect an answer within a few working days.

## Credentials

- Give the agent its own credentials, not yours. For Fiken, a separate user with *Se regnskapet uten å kunne gjøre endringer* for `FIKEN_READ_TOKEN`; for Folio, a read-only key for `FOLIO_READ_KEY` if your plan offers one.
- `FOLIO_WRITE_KEY` should never have payment access.
- Keep tokens in your environment or in an env file outside the repo. `.env` files are ignored by git. `FIKEN_ENV` / `FOLIO_ENV` files are sourced as shell, so only point them at files you control.
- Fiken personal tokens never expire. Revoke and replace them now and then, and right away if one may have leaked.
- The scripts send credentials only to `api.fiken.no` and `api.folio.no`, and pass them to curl on a file descriptor so they don't appear in the process list.

## What the skills can't protect against

An agent that holds a full-access Fiken token can write its own HTTP call, whatever these scripts allow. Fiken has no draft-only role, so for the prepare tier the line holds against an agent that uses the skills, not against one that works around them. Keep the agent tool's own permission checks on.
