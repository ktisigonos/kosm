#!/usr/bin/env sh
set -eu

out="${1:-doc/generated/zig}"
ver="$(zig version)"
case "$ver" in *dev*) path=master ;; *) path="$ver" ;; esac

mkdir -p "$out"
rm -f "$out"/*.md

curl -fsSL "https://ziglang.org/documentation/$path/" \
  | pandoc -f html -t gfm-raw_html --wrap=none \
  | awk -v out="$out" '
      /^## / {
        n++
        t = tolower(substr($0, 4))
        gsub(/[^a-z0-9]+/, "-", t)
        sub(/-$/, "", t)
        f = sprintf("%s/%02d-%s.md", out, n, t)
      }
      f { print > f }
    '

ls "$out" | wc -l
