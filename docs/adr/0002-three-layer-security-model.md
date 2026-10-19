# Three-layer security model: provider commits, code absent, least-privilege identity

Following zero-trust thinking (treat the agent as possibly compromised, e.g. by a prompt injected through a receipt or bank text), the skills rely on three layers and none on the model's judgement. (1) The human commits in the provider's own app: posting in Fiken, completing and signing in Folio. Folio already enforces this for money, since API payments stay drafts until a person signs. (2) Code that commits isn't installed unless the human opts in (ADR 0001). (3) The agent gets its own least-privilege credentials per tier (`*_READ_*` / `*_WRITE_*`), so the provider can enforce read-only where it supports it.

## Consequences

- A Fiken user with *Se regnskapet uten å kunne gjøre endringer* is the recommended source of `FIKEN_READ_TOKEN`. Not yet verified that Fiken's API honours that role for personal tokens.
- Fiken has no draft-only role and Fiken OAuth has no scopes, so the prepare tier can't be enforced by Fiken. The README says so.
- `folio-kladd` enforces a rule in code instead: an event may only be left with no category, or with a receipt-requiring category and no receipt. Pifre's 2026 data showed every event with a category that doesn't require a receipt (40 of 40) had been completed, so a category alone can book.
- Writes are logged locally and never retried automatically; `reconcile` skips matches against open drafts, so re-runs don't duplicate.
