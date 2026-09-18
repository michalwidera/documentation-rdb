#!/usr/bin/env bash
# Regenerate xretractor plan listings and Graphviz figures used by the English book.
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
book_dir=$(cd -- "$script_dir/.." && pwd)
workspace_dir=$(cd -- "$book_dir/.." && pwd)

debug_build=$workspace_dir/retractordb/build/Debug

# Bring xretractor in a build directory up to date before drawing with it: a stale binary
# silently produces figures from an older src/ tree.
refresh() {
  local build_dir=$1
  if ! command -v ninja >/dev/null; then
    echo "Ninja is required to refresh xretractor in $build_dir." >&2
    exit 2
  fi
  echo "Refreshing xretractor in $build_dir" >&2
  ninja -C "$build_dir" xretractor >&2
}

if [[ -n ${XRETRACTOR:-} ]]; then
  xretractor=$XRETRACTOR
elif [[ -f "$debug_build/build.ninja" ]]; then
  refresh "$debug_build"
  xretractor=$debug_build/src/retractor/xretractor
else
  xretractor=$(command -v xretractor || true)
fi

if [[ -z ${xretractor:-} || ! -x $xretractor ]]; then
  echo "Set XRETRACTOR to a current xretractor executable." >&2
  exit 2
fi

if ! command -v dot >/dev/null; then
  echo "Graphviz 'dot' is required." >&2
  exit 2
fi

mkdir -p "$script_dir/out"

listing() {
  local name=$1
  "$xretractor" -c "$script_dir/$name.rql" >"$script_dir/out/$name.txt"
}

picture() {
  local source=$1
  local target=$2
  local format=$3
  shift 3
  local options=("$@")
  if [[ $format == svg ]]; then
    options+=(-p)
  fi
  local dot_file
  dot_file=$(mktemp)
  trap 'rm -f "$dot_file"' RETURN
  "$xretractor" -c -d "${options[@]}" "$script_dir/$source.rql" >"$dot_file"
  dot "-T$format" "$dot_file" -o "$book_dir/assets/$target.$format"
  rm -f "$dot_file"
  trap - RETURN
}

listing plan-basic
listing alias
listing compile-flow
listing debug
listing wildcard
listing underscore
listing substrate-hash
listing substrate-hash-plus
listing substrate-shift
"$xretractor" -c -w 1:3 "$script_dir/sum-sequence.rql" >"$script_dir/out/sum-sequence.txt"

picture plan-basic graf_plan_zapytania svg -f -t -s
picture runtime-plan graf_plan_zapytania_2 svg -f -t -s
picture dag-1 dependencja_efemeryda_artefakt svg
picture dag-2 dependencja_efemerydy_artefakty svg
picture dag-3 dependencja_efemerydy_artefakty_artefakty svg
picture dag-4 dependencja_z_substratem svg
picture dedup dedup_po svg
# The plan before deduplication is drawn by hand: xretractor cannot show it (see dedup_przed.dot).
dot -Tsvg "$script_dir/dedup_przed.dot" -o "$book_dir/assets/dedup_przed.svg"
picture absorb-auto absorb_bez_mysum svg
picture absorb-named absorb_z_mysum svg
picture filter zaleznosc_strumieni_filtr_sygnalowy svg

echo "Regenerated plan listings in regen/out and figures in assets/."
