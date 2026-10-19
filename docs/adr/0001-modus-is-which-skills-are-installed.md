# Modus is chosen by which skills are installed, not by a setting

The agent's **Modus** (Kun lesing / Forberedelse / Bokføring med godkjenning) is decided by which skills the human installs. Code that does **Bokføring** lives only in a separate, opt-in skill. A config file or env var would sit in reach of the agent, which could flip it and unlock booking, so a setting would be a preference rather than a lock. Code that isn't on the machine can't be run through the skill.

Skills are split per system and per **Modus**: `fiken`/`folio` (read only), `fiken-kladd`/`folio-kladd` (**Forberedelse**), `fiken-bokforing`/`folio-bokforing` (**Bokføring**), plus `reconcile`. Many Fiken users don't bank with Folio, so the tiers must not cross systems.

## Considered Options

- **One skill with a mode setting (config/env).** Rejected: the agent can edit the setting.
- **`--confirm` flag on booking commands.** Rejected as a lock: the agent can type the flag itself.
- **OS-level approval (Touch ID, Secure Enclave, keychain ACL).** Prototyped and worked on macOS, but rejected: machine-specific, and generic system dialogs get approved on muscle memory.

## Consequences

- This does not stop an agent that holds a full-access token from writing its own HTTP call. Only the scope of the credential at Fiken/Folio stops that, and the README must say so.
- **Bokføring med godkjenning** has no deterministic lock; it relies on the agent tool's permission prompt.
