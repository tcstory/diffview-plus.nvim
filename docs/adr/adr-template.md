# ADR Template

Copy this file and rename it `adr-NNN-<slug>.md`.  
Fill in each section; delete the guidance text in parentheses.

---

# ADR-NNN: (Title — describe the decision in ≤ 10 words)

| Field       | Value                    |
|-------------|--------------------------|
| **Date**    | YYYY-MM-DD               |
| **Phase**   | (0 – 10)                 |
| **Status**  | Proposed / Accepted / Superseded by ADR-NNN |

---

## Context

(1–3 paragraphs. What problem prompted this decision? What Neovim API or
plugin subsystem is involved? Link to `:help` tags where relevant.)

## Decision

(State the decision clearly. Quote the chosen API or code structure. If the
decision is "do not use X", say so explicitly.)

### Neovim API references

| API / help tag | Stable in | Notes |
|----------------|-----------|-------|
| `:h vim.system()` | 0.10 | ... |

## Alternatives considered

(List at least one alternative and why it was rejected.)

| Alternative | Reason rejected |
|-------------|-----------------|
| ... | ... |

## Consequences

**Positive:**
- (What gets better.)

**Negative / trade-offs:**
- (What gets harder or breaks.)

**Files changed:** (comma-separated list of modules touched by this decision.)

---

## Developer note

(Short prose — 1–3 paragraphs — written after the implementation is complete.
Describe the actual module boundary, data flow, resource lifecycle, and a
one-command runnable example that verifies the change.)
