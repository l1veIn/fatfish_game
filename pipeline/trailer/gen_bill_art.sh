#!/usr/bin/env bash
# Illustrations for the cost + open-source video (2026-11-07), gpt-image-2.5, 16:9, opaque.
# Run from repo root:  bash pipeline/trailer/gen_bill_art.sh
# Outputs art_src/promo/<name>_0.png; skips names that exist (delete one to redo it).
# References are ONLY this project's own art; never refs/. No logos, no whale icons, no text.
set -u
OUT=art_src/promo
FISH="--image art_src/promo/refs/fish.png"
AUNTIE="--image art_src/promo/refs/auntie.png"
SCENE="--image art_src/store/library_hero.png"
LINEUP="--image art_src/promo/refs/crew_lineup.png"
STYLE="Cute chibi anime game illustration, exactly matching the art style of the reference images: clean lineart with a slightly thick dark outline, soft cel shading, warm bright colours, about 2.5-head-tall chibi proportions. 16:9 widescreen frame for a video, full-bleed background. No text, no letters, no numbers, no logos, no watermark, no UI."
GIRL="the blue whale maid girl from the reference images (very long wavy dark navy hair fading to sky blue at the tips, one curled ahoge, dark navy whale-fin ears, white frilly maid headdress, navy maid dress with white frilled apron, navy whale tail; keep her design exactly). She is deadpan: half-lidded eyes, tiny flat mouth, no smile"
OCTO="the cute chubby purple-pink octopus dinner lady from the reference image (white tall chef hat, white apron with a small seashell emblem; keep her design exactly)"

gen() {  # gen <name> <refs> <prompt>
  [ -f "$OUT/$1_0.png" ] && { echo "skip $1"; return; }
  python .agents/skills/65535/scripts/s65535.py image --model gpt-image-2.5 --resolution 2k --n 1 --size 16:9 \
    --quality high $2 --out "$OUT" --name "$1" --prompt "$STYLE $3" 2>&1 | tail -3
}

gen b1_receipt "$AUNTIE $FISH $SCENE" "In the warm golden-lit canteen, $OCTO wears tiny round reading glasses and holds up a ridiculously long paper receipt with two tentacles; the blank receipt paper unrolls down over the serving counter and piles up in loops on the floor. Other tentacles point at it accusingly while she laughs. In the lower right foreground, $GIRL sits at a wooden table calmly eating from a big iron basin with a spoon, ignoring the bill. The receipt paper is completely blank. Leave the left third of the frame simple enough for a caption." &
gen b2_context "$FISH $SCENE" "Comedy shot about eating a lot and producing very little. $GIRL sits on the right of a wooden canteen table behind a mountain of hundreds of empty rice bowls stacked to the ceiling, still eating with a spoon. On the left side of the table sits one tiny plate holding one single grain of rice, lit by a tiny spotlight, as if it is everything she produced. Warm evening canteen light. Very clear silhouette, funny contrast between the giant tower of bowls and the single grain." &
gen b3_redo "$AUNTIE $FISH $SCENE" "Comedy shot. A long wooden canteen table holds a row of rejected dishes and papers: a lunch tray, a drawing of a hand, a small speaker. A big red rubber stamp, held by one purple-pink octopus tentacle coming in from the top of the frame, slams down onto a blank cream ticket in the centre with a burst of ink droplets and impact lines. $GIRL peeks over the end of the table on the right holding her iron basin in front of her, deadpan. Warm light, strong diagonal composition, nothing written anywhere." &
wait
gen b4_open "$FISH $LINEUP $SCENE" "Warm celebratory scene. The canteen's big wooden doors stand wide open with sunlight pouring in. On a long table in the middle lies a huge open recipe book glowing softly with blank pages; six cute chibi helper girls from the lineup reference sheet (keep each design) lean over it reading and pointing, carrying copies of blank loose pages out through the door. $GIRL sits on the end of the table on the right swinging her legs, holding her iron basin, deadpan as always. Nothing written on any page. Leave the upper-left area simple for a caption." &
wait
ls -la "$OUT" | grep " b[0-9]_"

# Red line: no whale icons in the scenery. The first b2 take put a whale on every bowl.
FIX="Edit the reference image. Keep EVERYTHING exactly the same: the girl, her pose and face, the tower of bowls, the tiny plate with one grain of rice, the spotlight, composition, colours and lighting. Change only the decoration on the bowls: remove every whale symbol and replace it with a plain blue rim line and simple blue wave stripes. No whale shapes on any bowl or in the background; the only whale emblem allowed is the tiny one on the girl's apron. No text."
gen b2_context_fix "--image $OUT/b2_context_0.png" "$FIX"
