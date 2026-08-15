# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

This is an **mdBook documentation repository** for [RetractorDB](https://github.com/michalwidera/retractordb), an Edge Signal Processing Engine (ESPE) for real-time regular time series data. All content is written in **English**.

**Build system:** mdBook (not GitBook). Workflow: edit Markdown → commit → GitHub Actions builds and publishes to GitHub Pages.

**Live site:** `https://documentation.retractordb.com/` (custom domain, see `CNAME`) — this is the canonical rendered version. Always verify math and diagrams against this URL after pushing, not against VS Code preview (which doesn't render MathJax or Mermaid).

The table of contents is defined in [SUMMARY.md](SUMMARY.md). Images and assets live in [assets/](assets/).

## Build & Preview

```bash
# Install (once)
cargo install mdbook mdbook-mermaid

# Local preview
mdbook-mermaid install .   # copies mermaid.min.js + mermaid-init.js (gitignored)
mdbook serve               # http://localhost:3000 with live reload

# Build only
mdbook build               # output → book/
```

## Authoring Rules

- **Math:** use `\\[...\\]` for display math, `\\(...\\)` for inline. **Do NOT use `$$...$$`** — officially unsupported by mdBook (the docs say "The usual delimiters MathJax uses are not yet supported"). Inside `\\[...\\]` the Markdown parser still runs, so double-escape these characters:
  - `\{` → `\\{`, `\}` → `\\}` (e.g. `\left\\{`)
  - `\\` (array row separator) → `\\\\`
  - `\!` → `\\!`, `\#` → `\\#`, `\&` → `\\&`, `\%` → `\\%`
  - Alphabetic commands (`\frac`, `\left`, `\Delta`, etc.) need no extra escaping.
  - **Subscript after command:** write `\Delta_{a}` (no space before `_`), NOT `\Delta _{a}`. Space before `_` followed by `{` makes it a left-flanking emphasis opener; if a matching right-flanking `_` (e.g. `a_{`) appears later, Markdown consumes both as `<em>`, destroying the MathJax block. Rule: `_` must be immediately preceded by an alphanumeric character.
  - **No line may start with `:`** inside `\\[...\\]`: a line like `:= ...` is parsed as a definition list (`<dl>/<dt>/<dd>`), which splits the math across HTML elements and MathJax leaves it unrendered. Put `:=` at the end of the previous line instead.
- **Diagrams:** use standard ` ```mermaid ``` ` fenced blocks — rendered by `mdbook-mermaid` plugin.
- **Callouts:** use blockquotes with bold prefix: `> **ℹ️ Info**` / `> **⚠️ Warning**` / `> **✅ Note**`.
- **Images:** paths relative to each `.md` file pointing to `assets/` (e.g. `../assets/foo.png` from a subdirectory).
- No GitBook-specific shortcodes (hint/tabs/embed blocks), no YAML frontmatter. Never write a literal curly-brace-percent tag anywhere in this repo, even inside backticks or code fences — Jekyll's Liquid engine parses it before Markdown rendering and ignores code-span escaping, which breaks the GitHub Pages fallback build if the mdBook Actions workflow ever fails to run.

## AI Watermark Hygiene (Text)

No text committed here may carry AI provenance marks — invisible Unicode (zero-width characters, bidi controls, tag characters, variation selectors, private use) or space homoglyphs. **Images are out of scope: marks inside `assets/*.png`, `*.svg`, `*.jpg`, `*.gif` may stay.** The rule covers text only: `.md` (including `SUMMARY.md`), `book.toml`, `.css`, `.yml`, `.sh`, `.py` and commit messages.

Tool: `watermarks-remover` (default `~/github/watermarks-remover`), used through its local scripts — **do not start its Docker/HTTP service for this**. Layer A only (deterministic Unicode scrub); statistical Layer B rewriting is not part of this rule.

**Mandatory before every commit and before every push:**

```bash
WM="${WATERMARKS_REMOVER:-$HOME/github/watermarks-remover}/service/scripts"
TEXT='\.(md|toml|css|ya?ml|json|sh|py)$'

# 1. Check the staged text files (empty output = clean)
git diff --cached --name-only --diff-filter=ACM | grep -E "$TEXT" \
  | while read -r f; do python3 "$WM/inspect_text.py" --json "$f" >/dev/null 2>&1 || echo "WATERMARK: $f"; done

# 2. Report for a flagged file (which codepoints, where)
python3 "$WM/inspect_text.py" <file>

# 3. Clean it, then drop the backup the tool leaves behind
python3 "$WM/clean_text.py" <file> --in-place --stats && rm -f <file>.bak

# 4. Re-check, then re-stage
python3 "$WM/inspect_text.py" --json <file> >/dev/null && git add <file>
```

Substitute `git ls-files` for the staged-file listing to audit the whole tracked tree before a push. The commit message can be checked with `git log -1 --pretty=%B | python3 "$WM/inspect_text.py" -`.

**Known-good baseline — do not "fix" it.** The callout convention in *Authoring Rules* writes the information and warning symbols (`U+2139`, `U+26A0`) followed by `U+FE0F VARIATION SELECTOR-16`. The scanner reports that selector because those two symbols are text-default, not emoji-default. It is the documented convention, not a watermark. It currently occurs once or twice in about a dozen `.md` files and in `migrate_to_mdbook.py`; leave it alone. A `U+FE0F` in any other position, and every other reported codepoint, is a real finding.

**Scripts are code, not prose — zero tolerance, strict mode.** `migrate_to_mdbook.py` and the `.sh` files get checked immediately after every edit, not at commit time:

```bash
python3 "$WM/inspect_text.py" --aggressive --strip-emoji-glue <script>
```

The default check does not report Latin/Cyrillic confusables: `int value = 1;` whose `a` is a Cyrillic `U+0430` instead of ASCII `a` passes it. Such a character inside an identifier or a path cannot realistically be found by hand, so name a codepoint in prose and never paste the character itself. In `migrate_to_mdbook.py` the strict check also reports the two callout selectors described above — that pair is the accepted baseline; anything beyond it is a defect.

Further rules:

- **Never paste model, browser or chat output straight into a file.** Retype it, or clean it before it lands on disk.
- `--in-place` writes a `.bak` next to the file. Delete it; never commit it.
- Never point `clean_text.py` at binary input (images, `book/` output) and never use `--force-text` on it: it rewrites the bytes and destroys the file. Keep the extension filter above.
- `U+00A0` (no-break space) is reported as informational. Inside `\\[...\\]` math and Mermaid blocks, confirm it is not deliberate before replacing it.
- After cleaning, `git diff` must show no visible change — only invisible codepoints and, where confirmed, `U+00A0`. Math escaping and Mermaid blocks must come out byte-identical apart from those characters; if a diff touches anything else, revert and clean again.
- The check runs on Markdown sources, never on generated `book/` output.

## Collaboration Rules

**Commit and push are performed by the human only.** Claude shows the diff and waits for the human to review and decide. Never run `git commit` or `git push` autonomously.

## Key Config Files

| File | Purpose |
|------|---------|
| `book.toml` | mdBook config: title, language, MathJax, Mermaid, GitHub edit links |
| `SUMMARY.md` | Table of contents (mdBook format) |
| `.github/workflows/deploy.yml` | CI: installs mdBook + mdbook-mermaid, builds, deploys to GitHub Pages; also renders `book/retractordb.pdf` and `book/retractordb.epub` via Pandoc from the same preprocessed `SUMMARY.md`-ordered Markdown (skip both with a `[skippdf]` commit message tag, which restores the previous deployment's copies instead); copies `CNAME` into `book/` so the custom domain survives each deploy |
| `CNAME` | GitHub Pages custom domain (`documentation.retractordb.com`); must be copied into `book/` on every build — mdBook doesn't do this itself |
| `.gitignore` | Excludes `book/`, `mermaid.min.js`, `mermaid-init.js` |
| `migrate_to_mdbook.py` | One-time migration script (GitBook → mdBook); idempotent, safe to re-run |

## RetractorDB Architecture (Documentation Subject)

RetractorDB has three executables:

- **xretractor** — singleton main processor; compiles RQL queries, builds execution plans, manages shared memory for IPC
- **xqry** — multi-instance client; queries the running xretractor, sends data/commands, supports output formats: raw, Graphite, InfluxDB, Gnuplot
- **xtrdb** — binary artifact analysis tool with optional interactive mode

**Data flow:**
```
Input sources → xretractor (compile + execute) → shared memory → xqry clients
                       ↓
              Artifact files (binary/text) → xtrdb (analysis)
```

**Three stream types:**
- **Ephemerides** — volatile input streams that cannot be stored
- **Substrates** — intermediate computed streams
- **Artifacts** — materialized, persisted results

## Query Language (RQL)

RQL is based on **time-series algebra** (not relational algebra). Key commands:
- `DECLARE` — declares data sources and their types
- `SELECT` — defines transformation/aggregation over time windows
- `RULE` — defines alerting conditions

The compiler uses an ANTLR4-based parser. Query compilation involves symbol expansion, aliasing, `_` symbol processing, type unification, and dependency tree construction — each step documented in [query-compilation/](query-compilation/).

## Mathematical Foundations

The algebra underlying RQL is built on **Beatty sequences** and the **Fraenkel theorem** (non-homogeneous Beatty sequences). The sliding window mechanism (AGSE — Aggregation and Serialization) is the core execution primitive. This theory is documented in [mathematical-foundations/](mathematical-foundations/).
