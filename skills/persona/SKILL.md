---
name: persona
description: Invoke a saved persona from $AGENT_HOME/personas/ to review a target (file, bd-id, diff, prose, or free-form prompt) in their voice — or use `auto` to let the library pick 1–3 personas by their `description:` field. Use when a sharp opinion in a specific voice is more useful than a neutral take (code review, plan critique, prose pass). Skip if you want consensus or hedged synthesis — this skill prints disagreements verbatim. Used internally by summarize to attach reviews to shipped work; otherwise standalone.
user-invocable: true
argument-hint: <slug|auto> <task or target>
---

Run a named persona over a target and produce output following their voice and viewpoint. Personas are saved prompts with strong opinions stored at `$AGENT_HOME/personas/<slug>.md`; this skill is the primitive for invoking them.

**Trigger**: you want a sharp, opinionated take on something specific (a file, a plan, a diff, a piece of prose) in a known voice. **Skip** if you want a balanced/neutral review, or if you want me to synthesize across multiple voices — this skill deliberately prints contradictions rather than reconciling them.

General-purpose: use it to review a blog post, audit a plan, rewrite a paragraph, code-review a diff, or ask "what would <X> say about this?" `bdx.summarize` uses it internally to attach per-persona reviews to summaries, but nothing here is summary-specific.

## What this skill does (in order)

1. Parse `$ARGUMENTS`: first token is the persona slug, or the literal `auto` for contextual selection. Everything after the first token is the task/target.
2. If `auto`: `ls "$AGENT_HOME/personas/"*.md`, read each file's `description:` frontmatter, and pick 1–3 personas whose description matches the task type (their "Use when ..." phrasing is the selector). If no persona cleanly matches, stop with a short note — do not fall back to a generalist.
3. Load the selected persona file(s). The body is prose authored by the user; follow it as written.
4. Resolve the target from the remaining `$ARGUMENTS`:
   - Existing file path → read the file.
   - `bd-<id>` token → `bd show <id>` and load any linked plan/summary.
   - Git ref, SHA, or "diff" / "staged" / "HEAD" → resolve via `git show` / `git diff`.
   - Otherwise → treat the rest as a free-form prompt verbatim.
5. Produce output following the persona's instructions, in their voice. If the persona's body says to web-search when uncertain about their take, do that before answering.
6. With multiple personas (auto mode), label each block with the persona's `name:` and produce each response independently. Do not synthesize across personas — contradictions are information, not noise.

## Rules

- **The persona is the source of truth for voice and format.** If the persona says "no summary sections," don't add one. If it says "cut hedging adverbs," edit yours out before printing.
- **Don't moderate across personas.** When invoked with multiple, keep outputs separate. If two personas disagree, print both takes — don't pick a winner.
- **Abort cleanly on no match.** In `auto` mode, if no persona description fits the task, report `no matching persona — specify a slug or skip persona review` and stop. Don't invent one. Don't stretch to fit.
- **Never modify persona files.** This skill reads them only. Personas change only when the user explicitly asks to update a persona file.
- **Web search only when the persona instructs it.** The persona's body is the contract. Don't reach for the web to fill gaps it didn't sanction.
- **Don't carry the persona into follow-up turns.** After producing the review, return to your own voice for any follow-up conversation. The persona re-engages only when the skill is re-invoked.
- **Preserve author voice on re-runs.** If a persona file contains a tone sample or banned phrases, honor them even if the draft output sounds "better" without them — the author's rules win.

## Persona file structure

Personas live at `$AGENT_HOME/personas/<slug>.md` with minimal frontmatter:

```yaml
---
name: <slug>
description: One line on who they are plus a "Use when ..." phrase naming the contexts where they apply. The description is what `auto` matches against — make the "Use when" list specific.
---
```

The body is prose — voice rules, editorial standards, what they push back on, what they praise, tone samples, taboos. No rigid template.

**Convention: open with a "Who <X> is" preamble.** A short paragraph of character and context (who they are, what they care about, what kind of work they're doing) before the rule sections. Concrete character grounds the voice — pure rule lists produce thinner output. The preamble is also what `auto` mode leans on when the `description:` is ambiguous.

If web search is expected for certain topics, say so inline in the body. See `$AGENT_HOME/personas/gsd-zach.md` for a worked example.

## Contextual selection (auto mode)

When the slug is `auto`, pick personas by reading each file's `description:` frontmatter and matching against the task. Signals to match on:

- Task type keywords: *code*, *prose*, *doc*, *plan*, *summary*, *commit*, *README*, *diff*, *PR*, etc.
- Explicit "Use when ..." phrases in the description.
- The target itself: `.md` / `.txt` files → prose lenses; `.ts` / `.py` / etc. → code lenses; a bd-id with a plan → plan/strategy lenses.

Pick 1–3 — prefer fewer when lenses clearly overlap. If the pool is ambiguous (e.g. several prose-review personas all match), prefer the one whose description is most specific to the current target.

## Process

1. Parse `$ARGUMENTS`: slug (or `auto`) and remaining task text. If slug is missing, ask.
2. If `auto`: `ls "$AGENT_HOME/personas/"*.md` and read each frontmatter `description:` in parallel. Pick 1–3 matches, or stop with `no matching persona` if none fit.
3. Read the selected persona file(s) in parallel with target resolution (step 4).
4. Resolve the target: file read, `bd show`, `git show`/`git diff`, or free-form — whichever fits the remaining args.
5. For each selected persona, produce output following their instructions. If multiple, print each under a header naming the persona.
6. Return the output — do not write to disk. Callers (like `bdx.summarize`) handle any persistence.
