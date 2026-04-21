#!/usr/bin/env bash
set -euo pipefail

HEADER_SNIPPET='Copyright (C) [2026] [Nikhil]'

file_extension() {
  local file="$1"
  local base
  base="$(basename "$file")"
  if [[ "$base" == *.* ]]; then
    printf '%s\n' "${base##*.}" | tr '[:upper:]' '[:lower:]'
  else
    printf '%s\n' "(none)"
  fi
}

comment_style_for_file() {
  local file="$1"
  local ext
  ext="$(file_extension "$file")"
  local base
  base="$(basename "$file")"

  case "$base" in
    Dockerfile|dockerfile|Makefile|makefile) echo "hash"; return 0 ;;
  esac

  case "$ext" in
    kt|kts|java|groovy|gradle|c|cc|cpp|cxx|h|hh|hpp|hxx|js|jsx|ts|tsx|go|rs|swift|dart|css|scss|less)
      echo "supported"
      ;;
    py|sh|bash|zsh|fish|rb|pl|pm|ps1|properties|pro|md|txt|yml|yaml|toml|ini|conf|cfg|env|mk|tsv|csv)
      echo "supported"
      ;;
    xml|svg|xaml|plist|html|htm|sql)
      echo "supported"
      ;;
    json|lock|png|jpg|jpeg|gif|webp|ico|pdf|jar|keystore|jks|dex|aar|so|ttf|otf|mp3|mp4|wav|zip|gz|7z|tar)
      echo "skip"
      ;;
    *)
      if [[ -f "$file" ]] && awk 'NR==1 { exit ($0 ~ /^#!/ ? 0 : 1) }' "$file"; then
        echo "supported"
      else
        echo "skip"
      fi
      ;;
  esac
}

check_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    return 0
  fi

  [[ "$(comment_style_for_file "$file")" == "supported" ]] || return 0

  if ! awk 'NR<=30 {print}' "$file" | grep -Fq "$HEADER_SNIPPET"; then
    echo "Missing AGPL header in: $file" >&2
    return 1
  fi
}

main() {
  local failed=0
  while IFS= read -r file; do
    if ! check_file "$file"; then
      failed=1
    fi
  done < <(git ls-files)

  if [[ "$failed" -ne 0 ]]; then
    echo "Commit blocked: add AGPL header to files above." >&2
    exit 1
  fi
}

main "$@"
