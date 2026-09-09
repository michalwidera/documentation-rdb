#!/usr/bin/env bash
# Generate an English-only PDF suitable for double-blind peer review.
# The source tree is never modified; all transformations happen in a temporary directory.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTPUT="$REPO_DIR/book/supplementary-documentation-anonymous.pdf"
OUTPUT="$DEFAULT_OUTPUT"

usage() {
  printf '%s\n' \
    "Usage: $(basename "$0") [OUTPUT.pdf]" \
    "" \
    "Builds an anonymized English PDF from the Markdown files listed in SUMMARY.md." \
    "The default output is:" \
    "  $DEFAULT_OUTPUT" \
    "" \
    "Missing dependencies can be installed interactively on Debian or Ubuntu." \
    "" \
    "The public project name is replaced with the value of" \
    "ANONYMOUS_PROJECT_NAME (default: System Under Review)."
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi
if [ "$#" -gt 1 ]; then
  usage >&2
  exit 2
fi
if [ "$#" -eq 1 ]; then
  OUTPUT="$1"
fi

ANONYMOUS_PROJECT_NAME="${ANONYMOUS_PROJECT_NAME:-System Under Review}"
if [ -z "$ANONYMOUS_PROJECT_NAME" ]; then
  echo "ANONYMOUS_PROJECT_NAME must not be empty." >&2
  exit 2
fi

required_tools=(convert pandoc pdfinfo pdftotext python3 rsvg-convert xelatex)
system_packages=(
  fonts-dejavu imagemagick librsvg2-bin pandoc poppler-utils python3
  texlive-latex-extra texlive-xetex
)

confirm_installation() {
  local reply
  if [ ! -t 0 ]; then
    return 1
  fi
  printf '%s [y/N] ' "$1" >&2
  read -r reply
  [[ "$reply" =~ ^[Yy]([Ee][Ss])?$ ]]
}

install_apt_packages() {
  local packages=("$@")
  local apt_command=()
  if ! command -v apt-get >/dev/null 2>&1; then
    echo "Automatic installation is supported only on Debian and Ubuntu." >&2
    return 1
  fi
  if [ "$(id -u)" -eq 0 ]; then
    apt_command=(apt-get)
  elif command -v sudo >/dev/null 2>&1; then
    apt_command=(sudo apt-get)
  else
    echo "sudo is required to install system packages." >&2
    return 1
  fi
  "${apt_command[@]}" update
  "${apt_command[@]}" install -y "${packages[@]}"
}

find_missing_tools() {
  missing_tools=()
  local tool
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing_tools+=("$tool")
    fi
  done
}

show_system_install_command() {
  cat >&2 <<'EOF'
On Debian/Ubuntu install the document toolchain with:
  sudo apt-get update
  sudo apt-get install fonts-dejavu imagemagick librsvg2-bin pandoc \
    poppler-utils python3 texlive-latex-extra texlive-xetex
EOF
}

find_missing_tools
if [ "${#missing_tools[@]}" -ne 0 ]; then
  printf 'Missing required tools: %s\n' "${missing_tools[*]}" >&2
  if confirm_installation "Install the required system packages now?"; then
    install_apt_packages "${system_packages[@]}" || exit 1
    find_missing_tools
  else
    show_system_install_command
    exit 1
  fi
fi
if [ "${#missing_tools[@]}" -ne 0 ]; then
  printf 'Tools still missing after installation: %s\n' "${missing_tools[*]}" >&2
  exit 1
fi

MERMAID_TOOL_DIR="${ANONYMOUS_PDF_TOOL_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/documentation-rdb-anonymous-pdf}"
MMDC_BIN=""

try_mmdc() {
  local candidate="$1"
  if [ -z "$candidate" ]; then
    return 1
  fi
  if [[ "$candidate" != */* ]]; then
    candidate="$(command -v "$candidate" 2>/dev/null || true)"
  fi
  if [ -z "$candidate" ] || [ ! -x "$candidate" ]; then
    return 1
  fi
  if command -v timeout >/dev/null 2>&1; then
    timeout 15s "$candidate" --version >/dev/null 2>&1 || return 1
  else
    "$candidate" --version >/dev/null 2>&1 || return 1
  fi
  MMDC_BIN="$candidate"
}

try_mmdc "${ANONYMOUS_PDF_MMDC:-}" \
  || try_mmdc "$MERMAID_TOOL_DIR/node_modules/.bin/mmdc" \
  || try_mmdc "mmdc" \
  || true

if [ -z "$MMDC_BIN" ]; then
    cat >&2 <<EOF
No working native Mermaid CLI was found.
The mmdc visible in PATH may be a Windows wrapper, which cannot run in this WSL environment.

The isolated installation uses this directory:
  $MERMAID_TOOL_DIR

Equivalent manual command:
  PUPPETEER_CACHE_DIR="$MERMAID_TOOL_DIR/puppeteer" \\
    corepack npm install --prefix "$MERMAID_TOOL_DIR" --no-save \\
    @mermaid-js/mermaid-cli@11.17.0
EOF

  if confirm_installation "Install the native Mermaid CLI and its Chromium runtime now?"; then
    node_packages=()
    command -v node >/dev/null 2>&1 || node_packages+=(nodejs)
    command -v corepack >/dev/null 2>&1 || node_packages+=(node-corepack)
    if [ "${#node_packages[@]}" -ne 0 ]; then
      install_apt_packages "${node_packages[@]}" || exit 1
    fi
    mkdir -p "$MERMAID_TOOL_DIR/puppeteer"
    if ! PUPPETEER_CACHE_DIR="$MERMAID_TOOL_DIR/puppeteer" \
      corepack npm install --prefix "$MERMAID_TOOL_DIR" --no-save \
      @mermaid-js/mermaid-cli@11.17.0; then
      echo "Mermaid CLI installation failed." >&2
      exit 1
    fi
    try_mmdc "$MERMAID_TOOL_DIR/node_modules/.bin/mmdc" || {
      echo "The installed Mermaid CLI could not be executed." >&2
      exit 1
    }
  else
    cat >&2 <<'EOF'
Installation declined. Install Mermaid CLI manually, then run the script again.
Alternatively set ANONYMOUS_PDF_MMDC=/absolute/path/to/mmdc.
EOF
    exit 1
  fi
fi

if [[ "$MMDC_BIN" == "$MERMAID_TOOL_DIR/"* ]]; then
  export PUPPETEER_CACHE_DIR="${PUPPETEER_CACHE_DIR:-$MERMAID_TOOL_DIR/puppeteer}"
fi

if [ ! -f "$REPO_DIR/SUMMARY.md" ] || [ ! -f "$REPO_DIR/assets/book-cover-anonymous.svg" ]; then
  echo "Run this script from a complete documentation-rdb checkout." >&2
  exit 1
fi

TEMP_DIR="$(mktemp -d "/tmp/anonymous-pdf.XXXXXXXX")"
cleanup() {
  rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT INT TERM

if [[ "$OUTPUT" != /* ]]; then
  OUTPUT="$REPO_DIR/$OUTPUT"
fi
mkdir -p "$(dirname "$OUTPUT")"

cat > "$TEMP_DIR/puppeteer.json" <<'EOF'
{"args":["--no-sandbox","--disable-setuid-sandbox"]}
EOF

rsvg-convert --format=pdf \
  --output="$TEMP_DIR/anonymous-cover.pdf" \
  "$REPO_DIR/assets/book-cover-anonymous.svg"

cat > "$TEMP_DIR/header.tex" <<'EOF'
\usepackage{caption}
\usepackage{float}
\floatplacement{figure}{H}
\usepackage{amssymb}
\usepackage{newunicodechar}
\usepackage{tcolorbox}
\usepackage{mdframed}
\usepackage{fvextra}
\usepackage{eso-pic}
\usepackage{titlesec}
\usepackage{tocloft}
\RecustomVerbatimEnvironment{Highlighting}{Verbatim}{commandchars=\\\{\},breaklines=true,breakanywhere=true}
\titlelabel{\thetitle.\quad}
\renewcommand{\cftchapaftersnum}{.}
\renewcommand{\cftsecaftersnum}{.}
\renewcommand{\cftchapleader}{\cftdotfill{\cftdotsep}}
\cftsetpnumwidth{2.5em}
\cftsetrmarg{3em}
\setlength{\cftchapnumwidth}{2.5em}
\setlength{\cftsecindent}{2.5em}
\setlength{\cftsecnumwidth}{3em}
\setlength{\cftsubsecindent}{5.5em}
\tcbuselibrary{breakable}
\captionsetup{labelformat=empty,labelsep=none}
\newtcolorbox{calloutNote}{breakable,colback=green!8,colframe=green!45!black,fonttitle=\bfseries,title={Note}}
\newtcolorbox{calloutInfo}{breakable,colback=cyan!6,colframe=cyan!55!black,fonttitle=\bfseries,title={Info}}
\newtcolorbox{calloutWarning}{breakable,colback=orange!10,colframe=orange!70!black,fonttitle=\bfseries,title={Warning}}
\newunicodechar{∎}{\ensuremath{\square}}
\newunicodechar{ℕ}{\ensuremath{\mathbb{N}}}
\newunicodechar{∖}{\ensuremath{\setminus}}
\newunicodechar{⚠}{Warning}
EOF

cat > "$TEMP_DIR/cover.tex" <<EOF
\thispagestyle{empty}
\AddToShipoutPictureBG*{%
  \AtPageLowerLeft{%
    \includegraphics[width=\paperwidth,height=\paperheight]{$TEMP_DIR/anonymous-cover.pdf}%
  }%
}
\null
\clearpage
EOF

cat > "$TEMP_DIR/fix_math.lua" <<'EOF'
function Math(elem)
  local value = elem.text
  value = value:gsub("\\\\([{}!,;:#&%%])", "\\%1")
  value = value:gsub("\\\\\\\\", "\\\\")
  return pandoc.Math(elem.mathtype, value)
end
EOF

cat > "$TEMP_DIR/codeblock.lua" <<'EOF'
local box = "[linewidth=0.5pt,linecolor=gray!50,backgroundcolor=gray!8," ..
            "innerleftmargin=8pt,innerrightmargin=8pt," ..
            "innertopmargin=5pt,innerbottommargin=5pt," ..
            "skipabove=6pt,skipbelow=4pt]"

function CodeBlock(element)
  if FORMAT:match("latex") then
    return {
      pandoc.RawBlock("latex", "\\begin{mdframed}" .. box),
      element,
      pandoc.RawBlock("latex", "\\end{mdframed}")
    }
  end
end

function Table(element)
  if not FORMAT:match("latex") or #element.head.rows == 0 then return end
  local first_cell = element.head.rows[1].cells[1]
  if not first_cell or pandoc.utils.stringify(first_cell.content) ~= "Test name" then return end
  for _, body in ipairs(element.bodies) do
    for _, row in ipairs(body.body) do
      if #row.cells >= 2 then
        row.cells[2].content:insert(1, pandoc.RawBlock("latex", "\\vspace*{\\baselineskip}"))
      end
    end
  end
  return element
end
EOF

cat > "$TEMP_DIR/table_breaks.lua" <<'EOF'
local function break_long_code(element)
  if not element.text:match("[._]") then return nil end
  local result = pandoc.List()
  local start = 1
  for index = 1, #element.text do
    local character = element.text:sub(index, index)
    if character == "." or character == "_" then
      result:insert(pandoc.Code(element.text:sub(start, index), element.attr))
      result:insert(pandoc.RawInline("latex", "\\allowbreak{}"))
      start = index + 1
    end
  end
  if start <= #element.text then
    result:insert(pandoc.Code(element.text:sub(start), element.attr))
  end
  return result
end

local function customize_table_layout(element)
  if #element.head.rows == 0 then return end
  local first_cell = element.head.rows[1].cells[1]
  if not first_cell then return end

  local first_heading = pandoc.utils.stringify(first_cell.content)
  local widths
  if #element.colspecs == 5 and first_heading == "Field" then
    widths = {0.23, 0.21, 0.19, 0.18, 0.19}
  elseif #element.colspecs == 3 and first_heading == "Written in SELECT" then
    widths = {0.31, 0.43, 0.26}
  elseif #element.colspecs == 3 and first_heading == "Unit" then
    widths = {0.30, 0.27, 0.43}
  elseif #element.colspecs == 3 and first_heading == "State" then
    widths = {0.25, 0.37, 0.38}
  elseif #element.colspecs == 2 and first_heading == "Option"
      and pandoc.utils.stringify(element):find("xqrywait", 1, true) then
    widths = {0.25, 0.75}
  else
    return
  end

  for index, width in ipairs(widths) do
    element.colspecs[index] = {element.colspecs[index][1], width}
  end

  local function pad_first_cell(row)
    local cell = row.cells[1]
    local block = cell and cell.content[1]
    if block and block.content then
      block.content:insert(1, pandoc.RawInline("latex", "\\setlength{\\leftskip}{0.5em}"))
    end
  end

  for _, row in ipairs(element.head.rows) do pad_first_cell(row) end
  for _, body in ipairs(element.bodies) do
    for _, row in ipairs(body.body) do pad_first_cell(row) end
  end
end

function Table(element)
  if not FORMAT:match("latex") then return nil end
  customize_table_layout(element)
  return element:walk({Code = break_long_code})
end
EOF

cat > "$TEMP_DIR/callouts.lua" <<'EOF'
local environments = {
  Note="calloutNote", Info="calloutInfo", Warning="calloutWarning",
  NOTE="calloutNote", Download="calloutInfo"
}

local function environment_for(text)
  for label, environment in pairs(environments) do
    if text:find(label, 1, true) then return environment end
  end
end

function BlockQuote(element)
  if #element.content == 0 then return element end
  local first = element.content[1]
  if first.t ~= "Para" or #first.content == 0 then return element end
  local heading = first.content[1]
  if heading.t ~= "Strong" then return element end
  local environment = environment_for(pandoc.utils.stringify(heading))
  if not environment then return element end

  local body = {}
  local remainder = {}
  for index = 2, #first.content do table.insert(remainder, first.content[index]) end
  while #remainder > 0 and remainder[1].t == "Space" do table.remove(remainder, 1) end
  if #remainder > 0 then table.insert(body, pandoc.Para(remainder)) end
  for index = 2, #element.content do table.insert(body, element.content[index]) end

  local result = {pandoc.RawBlock("latex", "\\begin{" .. environment .. "}")}
  for _, block in ipairs(body) do table.insert(result, block) end
  table.insert(result, pandoc.RawBlock("latex", "\\end{" .. environment .. "}"))
  return result
end
EOF

export ANON_REPO_DIR="$REPO_DIR"
export ANON_TEMP_DIR="$TEMP_DIR"
export ANON_PROJECT_NAME="$ANONYMOUS_PROJECT_NAME"
export ANON_MMDC_BIN="$MMDC_BIN"

python3 - <<'PYEOF'
import os
import re
import shutil
import subprocess
from pathlib import Path

repo = Path(os.environ["ANON_REPO_DIR"])
temporary = Path(os.environ["ANON_TEMP_DIR"])
project_name = os.environ["ANON_PROJECT_NAME"]
mmdc = os.environ["ANON_MMDC_BIN"]
mermaid_dir = temporary / "mermaid"
mermaid_dir.mkdir()
mermaid_counter = 0
mermaid_total = 0
current_document = ""
current_document_text = ""
asset_dir = temporary / "assets"
asset_dir.mkdir()
asset_counter = 0

sensitive_url = re.compile(
    r"https?://(?:www\.)?(?:"
    r"github\.com/michalwidera|"
    r"(?:documentation|dokumentacja)\.retractordb\.com|"
    r"retractordb\.com|"
    r"academia\.edu/1840563"
    r")[^\s)<]*",
    re.IGNORECASE,
)

def replace_project(match):
    value = match.group(0)
    if value.islower():
        return re.sub(r"\s+", "-", project_name.lower())
    if value.isupper():
        return project_name.upper()
    return project_name

def anonymize_prose(text):
    text = re.sub(r"\bI'm\b", "the authors are", text)
    text = re.sub(r"\bI've\b", "the authors have", text)
    text = re.sub(r"\bI'll\b", "the authors will", text)
    text = re.sub(r"\bI'd\b", "the authors would", text)
    text = re.sub(r"\bI\s+am\b", "the authors are", text)
    text = re.sub(r"\bI\s+was\b", "the authors were", text)
    text = re.sub(r"\bFor me\b", "For the authors", text)
    text = re.sub(r"\bmyself\b", "the authors", text, flags=re.IGNORECASE)
    text = re.sub(r"\bmy\b", "the authors'", text, flags=re.IGNORECASE)
    text = re.sub(r"\bme\b", "the authors", text, flags=re.IGNORECASE)
    text = re.sub(r"\bI\b(?!\s*(?:[/=]|has\s+rate\b))", "the authors", text)
    return text

def anonymize(text, path):
    if path == repo / "README.md":
        text = re.sub(
            r"(?ms)^The name combines two ideas\..*?(?=\n\n)",
            "[Project-name history omitted for double-blind review.]",
            text,
        )
    if path == repo / "appendices/README.md":
        text = re.sub(
            r"(?ms)^\*\*System Origin\*\*.*?(?=^\*\*Further Development Directions\*\*)",
            "",
            text,
        )

    for reference_number in (3, 10, 25):
        text = re.sub(
            rf"(?m)^{reference_number}\\\..*$",
            f"{reference_number}\\. Anonymous reference omitted for double-blind review.",
            text,
        )

    markdown_link = re.compile(r"\[([^\]]*)\]\((" + sensitive_url.pattern + r")\)", re.IGNORECASE)
    text = markdown_link.sub("source (link omitted for double-blind review)", text)
    text = sensitive_url.sub("[link omitted for double-blind review]", text)
    text = re.sub(
        r"\[((?:\\.|[^\\\]])*)\]\((?:\.\.?/)*[^)\s]+\.md(?:#[^)]*)?\)",
        lambda match: match.group(1),
        text,
    )
    text = re.sub(r"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b", "[email omitted]", text)
    text = re.sub(r"Micha(?:l|\u0142)\s+Widera", "Anonymous Author", text, flags=re.IGNORECASE)
    text = re.sub(r"\bM\.\s*Widera\b", "Anonymous Author", text)
    text = re.sub(r"@Muro\b", "@anonymous", text, flags=re.IGNORECASE)
    text = re.sub(r"\bmichal\b", "user", text, flags=re.IGNORECASE)
    text = re.sub(r"xretractor", "xengine", text, flags=re.IGNORECASE)
    text = re.sub(r"\bretractor\b", "engine", text, flags=re.IGNORECASE)
    text = re.sub(r"(?i)\bRetractorDB\b", replace_project, text)

    segments = re.split(r"(^```.*?^```\s*$)", text, flags=re.MULTILINE | re.DOTALL)
    for index in range(0, len(segments), 2):
        segments[index] = anonymize_prose(segments[index])
    return "".join(segments)

def render_mermaid(match):
    global mermaid_counter
    mermaid_counter += 1
    headings = re.findall(r"^#{1,6}\s+(.+)$", current_document_text[:match.start()], re.MULTILINE)
    section = re.sub(r"[*_`]", "", headings[-1]).strip() if headings else "untitled section"
    print(
        f"Rendering Mermaid chart {mermaid_counter}/{mermaid_total}: "
        f"{current_document} - {section}",
        flush=True,
    )
    source = mermaid_dir / f"diagram-{mermaid_counter}.mmd"
    image = mermaid_dir / f"diagram-{mermaid_counter}.png"
    content = match.group(1).strip()
    source.write_text(content, encoding="utf-8")
    subprocess.run(
        [mmdc, "-i", str(source), "-o", str(image), "-p", str(temporary / "puppeteer.json")],
        check=True,
        stdout=subprocess.DEVNULL,
    )
    subprocess.run(["convert", str(image), "-trim", "+repage", str(image)], check=True)
    pdf_width = re.search(r"^%%\s+pdf-width:\s*(\S+)", content, re.MULTILINE)
    if pdf_width:
        width = pdf_width.group(1)
    else:
        first_line = next(
            (line for line in content.splitlines() if not line.strip().startswith("%%")), ""
        ).lower().strip()
        width = "85%" if any(key in first_line for key in ("sequence", "timeline", " lr")) else "50%"
    return f"![Diagram]({image}){{width={width}}}\n"

def stage_asset(source):
    global asset_counter
    source_path = Path(source)
    if not source_path.is_file():
        return None
    asset_counter += 1
    destination = asset_dir / f"asset-{asset_counter}{source_path.suffix.lower()}"
    if source_path.suffix.lower() == ".svg":
        content = source_path.read_text(encoding="utf-8")
        content = sensitive_url.sub("", content)
        content = re.sub(r"\b[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}\b", "[email omitted]", content)
        content = re.sub(r"Micha(?:l|\u0142)\s+Widera", "Anonymous Author", content, flags=re.IGNORECASE)
        content = re.sub(r"\bM\.\s*Widera\b", "Anonymous Author", content)
        content = re.sub(r"@Muro\b", "@anonymous", content, flags=re.IGNORECASE)
        content = re.sub(r"\bmichal\b", "user", content, flags=re.IGNORECASE)
        content = re.sub(r"xretractor", "xengine", content, flags=re.IGNORECASE)
        content = re.sub(r"\bretractor\b", "engine", content, flags=re.IGNORECASE)
        content = re.sub(r"(?i)\bRetractorDB\b", replace_project, content)
        destination.write_text(content, encoding="utf-8")
    else:
        shutil.copyfile(source_path, destination)
    return str(destination)

def fix_figure(match, directory):
    source_match = re.search(r'src="([^"]+)"', match.group(0))
    if not source_match:
        return ""
    source = source_match.group(1)
    caption_match = re.search(r"<figcaption[^>]*>(.*?)</figcaption>", match.group(0), re.DOTALL)
    caption = re.sub(r"<[^>]+>", "", caption_match.group(1)).strip() if caption_match else ""
    if source.startswith(("http://", "https://", "/")):
        if source.startswith(("http://", "https://")):
            return f"*[{caption}]*\n" if caption else ""
    else:
        source = str((directory / source).resolve())
    if source.lower().endswith(".gif"):
        converted = temporary / (Path(source).stem + f"-{mermaid_counter}.png")
        subprocess.run(["convert", source + "[0]", str(converted)], check=True)
        source = str(converted)
    else:
        source = stage_asset(source)
    if not source:
        return f"*[{caption}]*\n" if caption else ""
    width_match = re.search(r'<img[^>]+width="([^"]+)"', match.group(0))
    width = f"{{width={width_match.group(1)}}}" if width_match else ""
    return f"![{caption}]({source}){width}\n"

def fix_markdown_image(match, directory):
    alt, source = match.group(1), match.group(2)
    if source.startswith(("http://", "https://")):
        return ""
    source_path = Path(source) if source.startswith("/") else directory / source
    staged = stage_asset(source_path.resolve())
    return f"![{alt}]({staged})" if staged else ""

def demote_headings(text, levels):
    if levels == 0:
        return text
    return re.sub(
        r"^(#+)( )",
        lambda match: "#" * min(len(match.group(1)) + levels, 6) + match.group(2),
        text,
        flags=re.MULTILINE,
    )

summary = (repo / "SUMMARY.md").read_text(encoding="utf-8")
entries = []
for line in summary.splitlines():
    match = re.match(r"^( *)\*.*\(([^)]+\.md)\)", line)
    if not match:
        continue
    relative_path = match.group(2)
    if relative_path.startswith("appendices/system-origin/"):
        continue
    path = repo / relative_path
    if path.is_file():
        entries.append((path, len(match.group(1)) // 2))

parts = []
for path, _ in entries:
    source_text = path.read_text(encoding="utf-8")
    source_text = re.sub(r'<div class="no-print">.*?</div>', "", source_text, flags=re.DOTALL)
    mermaid_total += len(re.findall(r"```mermaid\n.*?```", source_text, flags=re.DOTALL))

for path, level in entries:
    text = path.read_text(encoding="utf-8")
    text = re.sub(r'<div class="no-print">.*?</div>', "", text, flags=re.DOTALL)
    text = anonymize(text, path)
    text = text.replace("\u2714", "$\\checkmark$")
    current_document = str(path.relative_to(repo))
    current_document_text = text
    text = re.sub(r"```mermaid\n(.*?)```", render_mermaid, text, flags=re.DOTALL)
    text = re.sub(r"<figure>.*?</figure>", lambda match: fix_figure(match, path.parent), text, flags=re.DOTALL)
    text = re.sub(
        r"!\[([^\]]*)\]\(([^)\s]+)\)",
        lambda match: fix_markdown_image(match, path.parent),
        text,
    )
    parts.append(demote_headings(text, level))

combined = "\n\n".join(parts)
combined = re.sub(
    r"!\[Diagram\]\(([^)]+)\)(\{[^}]*\})?\n+_(Fig\.[^_\n]+)_",
    lambda match: f"![{match.group(3)}]({match.group(1)}){match.group(2) or ''}",
    combined,
)
(temporary / "combined.md").write_text(combined, encoding="utf-8")
PYEOF

forbidden='Michal|Widera|@Muro|\bretractor\b|xretractor|github\.com/michalwidera|retractordb\.com|documentation\.retractordb|dokumentacja\.retractordb|commit [0-9a-f]{7,}'
if LC_ALL=C rg -n -i "$forbidden" "$TEMP_DIR/combined.md"; then
  echo "Anonymization failed: identifying text remains in the prepared Markdown." >&2
  exit 1
fi

CANDIDATE_PDF="$TEMP_DIR/candidate.pdf"

pandoc "$TEMP_DIR/combined.md" \
  --from markdown+tex_math_double_backslash \
  --lua-filter "$TEMP_DIR/codeblock.lua" \
  --lua-filter "$TEMP_DIR/callouts.lua" \
  --lua-filter "$TEMP_DIR/fix_math.lua" \
  --lua-filter "$TEMP_DIR/table_breaks.lua" \
  --include-in-header="$TEMP_DIR/header.tex" \
  --include-before-body="$TEMP_DIR/cover.tex" \
  --pdf-engine=xelatex \
  --number-sections \
  --toc --toc-depth=2 \
  --top-level-division=chapter \
  --standalone \
  -V lang=en \
  -V papersize:a4 \
  -V geometry:margin=2.5cm \
  -V fontsize=11pt \
  -V documentclass=report \
  -V mainfont="DejaVu Serif" \
  -V monofont="DejaVu Sans Mono" \
  -V secnumdepth=1 \
  --metadata title-meta="$ANONYMOUS_PROJECT_NAME" \
  --metadata subject="Anonymous supplementary documentation" \
  --metadata author="" \
  --metadata date="" \
  --output "$CANDIDATE_PDF"

pdftotext "$CANDIDATE_PDF" "$TEMP_DIR/pdf-text.txt"
if LC_ALL=C rg -n -i "$forbidden" "$TEMP_DIR/pdf-text.txt"; then
  echo "Anonymization failed: identifying text remains in the generated PDF." >&2
  exit 1
fi

pdfinfo "$CANDIDATE_PDF" > "$TEMP_DIR/pdfinfo.txt"
if awk -F: '/^Author:/ {sub(/^[[:space:]]+/, "", $2); if ($2 != "") exit 1}' "$TEMP_DIR/pdfinfo.txt"; then
  :
else
  echo "Anonymization failed: PDF Author metadata is not empty." >&2
  exit 1
fi

if pdfinfo -url "$CANDIDATE_PDF" 2>/dev/null | LC_ALL=C rg -n -i "$forbidden"; then
  echo "Anonymization failed: an identifying URL remains in the PDF." >&2
  exit 1
fi

pages="$(awk '/^Pages:/ {print $2}' "$TEMP_DIR/pdfinfo.txt")"
size="$(du -h "$CANDIDATE_PDF" | awk '{print $1}')"
mv -- "$CANDIDATE_PDF" "$OUTPUT"
printf 'Created: %s\nPages: %s\nSize: %s\nAutomated anonymity checks: PASSED\n' \
  "$OUTPUT" "${pages:-unknown}" "$size"
