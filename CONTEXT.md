# fiken-folio-skills

Agent skills that let an AI agent work with a Norwegian small business's accounting (Fiken) and business bank (Folio), with a hard line between what the agent may prepare and what only a human may commit.

## Language

**Bokføring**:
Any action that changes the ledger or a Folio event's completed status, directly or as a side effect.
_Avoid_: posting, booking (as loose synonyms for "any write")

**Forberedelse**:
Any write that leaves the ledger and every Folio event's completed status untouched: drafts, inbox uploads, attachments, notes.
_Avoid_: safe write, draft mode

**Kladd**:
A Fiken purchase, offer or invoice draft that exists in Fiken but is not in the ledger.
_Avoid_: draft booking, pending entry

**Modus**:
The level of access the human chooses for the agent: **Kun lesing**, **Forberedelse** or **Bokføring med godkjenning**.
_Avoid_: permission level, safety mode

**Kun lesing**:
The **Modus** where the agent can only read.

**Bokføring med godkjenning**:
The **Modus** where the agent may also do **Bokføring** after the human says yes; the only lock is the agent tool's own permission prompt.
_Avoid_: auto-booking, full access

## Relationships

- A Folio payment created through the API is a draft until a person signs it in Folio; the API has no way to sign, so the agent can prepare a payment but never send money
- The agent prepares; the human commits in the provider's own app (posts in Fiken, signs in Folio)
- Each **Modus** includes everything the one below it allows: **Kun lesing** < **Forberedelse** < **Bokføring med godkjenning**
- **Forberedelse** is the default **Modus**

- A **Kladd** becomes **Bokføring** only when a human posts it in Fiken
- Completing a Folio event is **Bokføring** when Folio's Fiken integration is on, because Folio then posts it to Fiken
- Folio completes an event by itself once it has a category and what that category requires; a category that doesn't require a receipt completes it on its own. Any write that leaves an event in that state counts as **Bokføring**

## Example dialogue

> **Dev:** "Can the agent attach the receipt and set the category on this Folio event?"
> **Domain expert:** "Attaching is **Forberedelse**. Setting the category on an event that already has a receipt can complete it, and that's **Bokføring**, so that part is mine. Same for a category like *Refusjon* that doesn't need a receipt at all."

## Flagged ambiguities

- "booking"/"posting" was used for every write, including drafts. Resolved: only **Bokføring** changes the ledger; drafts are **Forberedelse**.
