#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
out="$repo/Tools/citizens/build/reference-sheets"
font=/System/Library/Fonts/Supplemental/Arial.ttf
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mkdir -p "$out"

make_sheet() {
  name=$1
  concept=$2
  crop=$3
  prefix=$4
  title=$5

  magick "$concept" -crop "$crop" +repage -resize '2048x430^' -gravity center -extent 2048x430 \
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
    -annotate +0+0 "$title — CANONICAL CROP + SHARED-RIG CONSTRUCTION ENVELOPE" \
    "$scratch/$name-title.png"
  magick "$scratch/$name-title.png" "$scratch/$name-concept.png" "$scratch/$name-views.png" -append \
    "$out/$name-construction-sheet.png"
}

make_sheet sunwoven \
  "$repo/Docs/Concepts/01-sunwoven-foundation-opening.png" \
  '575x195+440+780' slender 'FOUNDATION SUNWOVEN WEAVER'
make_sheet gravemark \
  "$repo/Docs/Concepts/05-gravemark-player-perspective.png" \
  '575x195+440+780' broad 'FOUNDATION GRAVEMARK MASON'

echo "Wrote reference sheets to $out"
