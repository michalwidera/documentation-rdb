#!/usr/bin/env python3
"""
Migrates GitBook markdown files to mdBook format.
Modifies files in-place — use git diff to review, git checkout to revert.

What it does:
  1. Removes YAML frontmatter (--- ... ---)
  2. Converts {% hint %} callouts to blockquotes
  3. Converts {% tabs %} / {% tab %} panels to sequential sections
  4. Converts {% embed url="..." %} to markdown links
  5. Rewrites .gitbook/assets/ paths to assets/
  6. Renames .gitbook/assets/ directory to assets/

Math: $$ ... $$ is kept as-is. mdBook >= 0.4.35 with mathjax-support = true
handles $$ via pulldown-cmark's math extension (raw token, no escape processing).
Do NOT convert to \\[...\\] — the Markdown parser would corrupt \\{ \\} etc.
"""

import re
import shutil
from pathlib import Path


ROOT = Path(__file__).parent


def remove_frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return text
    end = text.find("\n---\n", 4)
    if end == -1:
        return text
    return text[end + 5:].lstrip("\n")


def convert_hints(text: str) -> str:
    PREFIXES = {
        "info":    "> **ℹ️ Info**",
        "warning": "> **⚠️ Ostrzeżenie**",
        "success": "> **✅ Uwaga**",
        "danger":  "> **🚨 Błąd**",
    }

    def replace(m: re.Match) -> str:
        style = m.group(1) or "info"
        content = m.group(2).strip()
        header = PREFIXES.get(style, "> **Uwaga**")
        lines = content.splitlines()
        quoted = "\n".join(("> " + line).rstrip() if line.strip() else ">" for line in lines)
        return f"{header}\n>\n{quoted}\n"

    pattern = r'\{%\s*hint\s+style="([^"]*)"[^%]*%\}(.*?)\{%\s*endhint\s*%\}'
    return re.sub(pattern, replace, text, flags=re.DOTALL)


def convert_tabs(text: str) -> str:
    def replace(m: re.Match) -> str:
        inner = m.group(1)
        # Split on {% tab title="..." %} — captures title as group
        parts = re.split(r'\{%\s*tab\s+title="([^"]*)"\s*%\}', inner)
        sections = []
        # parts[0] = content before first tab (usually whitespace)
        i = 1
        while i + 1 <= len(parts) - 1:
            title = parts[i]
            body = re.sub(r'\{%\s*endtab\s*%\}', "", parts[i + 1]).strip()
            sections.append(f"**{title}**\n\n{body}")
            i += 2
        return "\n\n---\n\n".join(sections) + "\n"

    pattern = r'\{%\s*tabs\s*%\}(.*?)\{%\s*endtabs\s*%\}'
    return re.sub(pattern, replace, text, flags=re.DOTALL)


def convert_embeds(text: str) -> str:
    pattern = r'\{%\s*embed\s+url="([^"]*)"\s*%\}'
    return re.sub(pattern, lambda m: f"[{m.group(1)}]({m.group(1)})", text)


def fix_asset_paths(text: str) -> str:
    # Covers both HTML src=".../.gitbook/assets/..." and markdown (...)
    return text.replace(".gitbook/assets/", "assets/")


def migrate_file(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    text = original
    text = remove_frontmatter(text)
    text = convert_hints(text)
    text = convert_tabs(text)
    text = convert_embeds(text)
    text = fix_asset_paths(text)
    if text != original:
        path.write_text(text, encoding="utf-8")
        return True
    return False


def rename_assets_dir() -> None:
    src = ROOT / ".gitbook" / "assets"
    dst = ROOT / "assets"
    if src.exists() and not dst.exists():
        shutil.copytree(src, dst)
        shutil.rmtree(ROOT / ".gitbook")
        print("  renamed: .gitbook/assets/ → assets/")
    elif dst.exists():
        print("  skip: assets/ already exists")
    else:
        print("  skip: .gitbook/assets/ not found")


def main() -> None:
    md_files = sorted(
        f for f in ROOT.rglob("*.md")
        if ".git" not in f.parts and f.name != "migrate_to_mdbook.py"
    )

    modified = 0
    for f in md_files:
        if migrate_file(f):
            print(f"  migrated: {f.relative_to(ROOT)}")
            modified += 1

    print(f"\nMarkdown: {modified}/{len(md_files)} files modified.")

    rename_assets_dir()
    print("\nDone. Review with: git diff")
    print("Revert with:       git checkout -- . && git clean -fd")


if __name__ == "__main__":
    main()
