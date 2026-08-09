#!/bin/sh
# Issue #24 — Sunwoven production construction sheet: canonical crop +
# production turnaround views (front/side/rear/threequarter).
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out="$repo/Tools/citizens/build/reference-sheets"
font=/System/Library/Fonts/Supplemental/Arial.ttf
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$out"

name=sunwoven-production
crop_manifest="$repo/Tools/citizens/manifest/sunwoven-canonical-crop.json"
concept="$repo/$(jq -r '.source' "$crop_manifest")"
crop_geometry=$(jq -r '.crop_px | "\(.width)x\(.height)+\(.x)+\(.y)"' "$crop_manifest")
prefix=sunwoven
title='FOUNDATION SUNWOVEN WEAVER — CANONICAL FOUNDATION CELL'

magick "$concept" -crop "$crop_geometry" +repage -resize '2048x430^' -gravity center -extent 2048x430 \
  "$scratch/$name-concept.png"
for view in front side rear threequarter; do
  input="$repo/Tools/citizens/build/renders/turnaround-$prefix-$view.png"
  output="$scratch/$name-$view.png"
  magick "$input" -resize '512x930^' -gravity center -extent 512x930 \
    -font "$font" -gravity north -fill '#f5e7c2' -stroke '#111827' -strokewidth 2 -pointsize 34 \
    -annotate +0+22 "$(printf '%s' "$view" | tr '[:lower:]' '[:upper:]')" "$output"
done
magick \
  "$scratch/$name-front.png" "$scratch/$name-side.png" \
  "$scratch/$name-rear.png" "$scratch/$name-threequarter.png" \
  +append "$scratch/$name-views.png"
magick -size 2048x96 xc:'#111827' -font "$font" -gravity center -fill '#f5e7c2' -pointsize 30 \
  -annotate +0+0 "$title — SHARED-RIG PRODUCTION ENVELOPE" \
  "$scratch/$name-title.png"
magick "$scratch/$name-title.png" "$scratch/$name-concept.png" "$scratch/$name-views.png" -append \
  "$out/$name-construction-sheet.png"

echo "Wrote $out/$name-construction-sheet.png"
