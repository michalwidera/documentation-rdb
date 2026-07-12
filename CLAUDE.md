# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repository Is

This is an **mdBook documentation repository** for [RetractorDB](https://github.com/michalwidera/retractordb), an Edge Signal Processing Engine (ESPE) for real-time regular time series data. All content is written in **English**.

**Build system:** mdBook (not GitBook). Workflow: edit Markdown → commit → GitHub Actions builds and publishes to GitHub Pages.

**Live site:** `https://michalwidera.github.io/documentation-rdb/` — this is the canonical rendered version. Always verify math and diagrams against this URL after pushing, not against VS Code preview (which doesn't render MathJax or Mermaid).

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
- **Diagrams:** use standard ` ```mermaid ``` ` fenced blocks — rendered by `mdbook-mermaid` plugin.
- **Callouts:** use blockquotes with bold prefix: `> **ℹ️ Info**` / `> **⚠️ Warning**` / `> **✅ Note**`.
- **Images:** paths relative to each `.md` file pointing to `assets/` (e.g. `../assets/foo.png` from a subdirectory).
- No GitBook-specific shortcodes (hint/tabs/embed blocks), no YAML frontmatter. Never write a literal curly-brace-percent tag anywhere in this repo, even inside backticks or code fences — Jekyll's Liquid engine parses it before Markdown rendering and ignores code-span escaping, which breaks the GitHub Pages fallback build if the mdBook Actions workflow ever fails to run.

## Collaboration Rules

**Commit and push are performed by the human only.** Claude shows the diff and waits for the human to review and decide. Never run `git commit` or `git push` autonomously.

## Key Config Files

| File | Purpose |
|------|---------|
| `book.toml` | mdBook config: title, language, MathJax, Mermaid, GitHub edit links |
| `SUMMARY.md` | Table of contents (mdBook format) |
| `.github/workflows/deploy.yml` | CI: installs mdBook + mdbook-mermaid, builds, deploys to GitHub Pages |
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
