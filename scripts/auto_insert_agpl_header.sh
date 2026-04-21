#!/usr/bin/env bash
set -euo pipefail

HEADER_SNIPPET='Copyright (C) [2026] [Nikhil]'
FILETYPE_RECORD='.filetypes_in_use.tsv'

BLOCK_HEADER='/*
Copyright (C) [2026] [Nikhil]

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
*/
'

HASH_HEADER='# Copyright (C) [2026] [Nikhil]
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <https://www.gnu.org/licenses/>.
'

XML_HEADER='<!--
Copyright (C) [2026] [Nikhil]

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU Affero General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU Affero General Public License for more details.

You should have received a copy of the GNU Affero General Public License
along with this program. If not, see <https://www.gnu.org/licenses/>.
-->
'

get_header_for_file() {
  local file="$1"
  local style
  style="$(comment_style_for_file "$file")"

  case "$style" in
    block) printf '%s\n' "$BLOCK_HEADER" ;;
    hash) printf '%s\n' "$HASH_HEADER" ;;
    xml|html) printf '%s\n' "$XML_HEADER" ;;
    slash) printf '%s\n' "${BLOCK_HEADER//\/*/\/\/}" ;; # fallback to block-equivalent style
    sql) printf '%s\n' "${HASH_HEADER//# /-- }" ;;
    none) return 1 ;;
    unknown) return 1 ;;
    *) return 1 ;;
  esac
}

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
    Dockerfile|dockerfile) echo "hash"; return 0 ;;
    Makefile|makefile) echo "hash"; return 0 ;;
  esac

  case "$ext" in
    kt|kts|java|groovy|gradle|c|cc|cpp|cxx|h|hh|hpp|hxx|js|jsx|ts|tsx|go|rs|swift|dart|css|scss|less)
      echo "block"
      ;;
    py|sh|bash|zsh|fish|rb|pl|pm|ps1|properties|pro|md|txt|yml|yaml|toml|ini|conf|cfg|env|mk|tsv|csv)
      echo "hash"
      ;;
    xml|svg|xaml|plist|html|htm)
      echo "xml"
      ;;
    sql)
      echo "sql"
      ;;
    json|lock|png|jpg|jpeg|gif|webp|ico|pdf|jar|keystore|jks|dex|aar|so|ttf|otf|mp3|mp4|wav|zip|gz|7z|tar)
      echo "none"
      ;;
    *)
      if [[ -f "$file" ]] && awk 'NR==1 { exit ($0 ~ /^#!/ ? 0 : 1) }' "$file"; then
        echo "hash"
      else
        echo "unknown"
      fi
      ;;
  esac
}

update_filetype_record() {
  local tmp_file
  tmp_file="$(mktemp)"

  {
    printf 'extension\tcomment_style\tstatus\n'
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      local ext style status
      ext="$(file_extension "$file")"
      style="$(comment_style_for_file "$file")"
      case "$style" in
        unknown) status="needs_mapping" ;;
        none) status="non_commentable_or_binary" ;;
        *) status="supported" ;;
      esac
      printf '%s\t%s\t%s\n' "$ext" "$style" "$status"
    done < <(git ls-files)
  } | awk '!seen[$0]++' | awk 'NR==1{print;next}{print | "sort"}' > "$tmp_file"

  mv "$tmp_file" "$FILETYPE_RECORD"
  git add "$FILETYPE_RECORD"
}

insert_header_if_missing() {
  local file="$1"

  [[ -f "$file" ]] || return 0
  awk 'NR<=30 {print}' "$file" | grep -Fq "$HEADER_SNIPPET" && return 0

  local header
  if ! header="$(get_header_for_file "$file")"; then
    local style
    style="$(comment_style_for_file "$file")"
    if [[ "$style" == "unknown" ]]; then
      echo "Skipping unsupported new type (needs mapping): $file" >&2
    fi
    return 0
  fi

  local tmp_file
  tmp_file="$(mktemp)"

  if [[ "$file" == *.xml ]] && awk 'NR==1 { exit ($0 ~ /^<\?xml / ? 0 : 1) }' "$file"; then
    awk -v header="$header" '
      NR == 1 {
        print $0
        print header
        next
      }
      { print }
    ' "$file" > "$tmp_file"
  else
    {
      printf '%s\n' "$header"
      cat "$file"
    } > "$tmp_file"
  fi

  mv "$tmp_file" "$file"
  git add "$file"
  echo "Auto-inserted AGPL header: $file"
}

main() {
  update_filetype_record

  while IFS= read -r file; do
    insert_header_if_missing "$file"
  done < <(git diff --cached --name-only --diff-filter=A)
}

main "$@"
