#!/usr/bin/env bash
# Illustrations for the promo video (2026-10-21), gpt-image-2.5, 16:9, opaque.
# Run from repo root:  bash pipeline/trailer/gen_promo_art.sh
# Outputs art_src/promo/<name>_0.png; skips names that exist (delete one to redo it).
# References are ONLY this project's own art (rig masters, crew, 梁阿姨, store hero); never refs/.
# Red lines: no logos, no whale icons in the scenery, no text, original characters only.
set -u
OUT=art_src/promo
mkdir -p "$OUT"
FISH="--image art_src/rig/master_c_0.png --image art_src/rig/stand_basin_a_0.png"
SCENE="--image art_src/store/library_hero.png"
AUNTIE="--image game/assets/canteen/auntie_happy.png"
CREW="--image art_src/rig/crew_wen_0.png --image art_src/rig/crew_pu_0.png --image art_src/rig/crew_g_0.png --image art_src/rig/crew_ke_0.png --image art_src/rig/crew_ge_0.png --image art_src/rig/crew_zi_0.png"
STYLE="Cute chibi anime game illustration, exactly matching the art style of the reference images: clean lineart with a slightly thick dark outline, soft cel shading, warm bright colours, about 2.5-head-tall chibi proportions. 16:9 widescreen frame for a video, full-bleed background. No text, no letters, no numbers, no logos, no watermark, no UI."
# the request fails (HTML error) with many full-size refs: the crew go as one small lineup sheet
LINEUP="--image art_src/promo/refs/crew_lineup.png"
GIRL="the blue whale maid girl from the reference images (very long wavy dark navy hair fading to sky blue at the tips, one curled ahoge, dark navy whale-fin ears, white frilly maid headdress, navy maid dress with white frilled apron with a tiny whale emblem, navy whale tail; keep her design exactly)"

gen() {  # gen <name> <refs> <prompt>
  [ -f "$OUT/$1_0.png" ] && { echo "skip $1"; return; }
  python .agents/skills/65535/scripts/s65535.py image --model gpt-image-2.5 --resolution 2k --n 1 --size 16:9 \
    --quality high $2 --out "$OUT" --name "$1" --prompt "$STYLE $3" 2>&1 | tail -4
}

gen p1_hungry "$FISH $SCENE" "Late at night in an empty dark school canteen. $GIRL sits alone at a wooden canteen table on the RIGHT third of the frame, in front of an old chunky computer monitor whose screen shows only a big empty loading bar with a tiny sliver of progress (no characters on the screen). The cool blue glow of the monitor lights her face. She holds her big empty stainless-steel iron basin in her lap. Expression: completely deadpan, half-lidded eyes, tiny flat mouth, emotionless (she is a stoic, blank-faced character). A small cartoon rumble squiggle beside her tummy shows she is hungry. The LEFT half of the frame is calm dark canteen background (empty tables, a dark serving counter far away, moonlight from windows) with space for a title." &
gen p2_auntie "$AUNTIE $SCENE" "Lunch rush in the warm, golden-lit canteen. The cute chubby purple-pink octopus dinner lady from the first reference image (white tall chef hat, white apron with a small seashell emblem) stands behind a long stainless-steel serving counter full of trays of food, laughing heartily with eyes closed, and flings many dishes high into the air with all eight tentacles at once: onigiri rice balls, glazed fried chicken drumsticks, dumplings, steaming bowls of white rice, one shining golden onigiri, all arcing through the air with motion lines and steam puffs. Energetic, joyful, centred composition, camera slightly low." &
gen p3_catch "$FISH $SCENE" "Dynamic action shot in the warm canteen: $GIRL leaps sideways through the air, holding a square stainless-steel bento lunch box with a 2-by-3 grid of compartments up with both hands to catch food that rains down from above (onigiri, fried chicken drumsticks, dumplings, a golden onigiri). Her face stays deadpan and focused (half-lidded serious eyes, small flat mouth) which is the joke. Long hair and tail flowing, speed lines, the canteen counter blurred in the background." &
wait
gen p4_crew "$LINEUP --image art_src/promo/refs/fish.png" "Six cute chibi helper girls from the first reference image, a lineup sheet, left to right (pale-blue haired girl in light blue, black-haired cat-eared girl in a black maid outfit, white-haired girl with small dragon wings and tail, orange-haired girl in an orange maid outfit, blonde twin-tail girl in red-and-black gothic dress with little bat wings, blue-purple haired cat-eared girl in a purple maid outfit; keep each design) sprint in a lively line across the canteen floor from left to right, each holding a stainless-steel lunch box heaped with food above her head, cheerful determined faces, dust puffs and motion lines. On the far right, $GIRL sits at a wooden table waiting with a spoon in her hand and a napkin tucked in, deadpan face." &
gen p5_full "--image art_src/rig/lie_a_0.png --image art_src/rig/master_c_0.png $SCENE" "After a huge meal: $GIRL lies flat on her back across a wooden canteen table, round full tummy, eyes peacefully closed, a tiny satisfied deadpan mouth, a small sleep bubble at her nose. Around her: towers of empty stacked bowls and plates and empty steel lunch boxes, her iron basin tipped over on the table. Warm orange evening light through the canteen windows, calm and cosy. Wide shot, she is centred slightly right." &
gen p6_agi "--image art_src/promo/refs/fish.png --image art_src/promo/refs/auntie.png $LINEUP" "Grand finale key art. $GIRL stands on top of a wooden canteen table at the centre-right, and for the very first time she smiles a big, bright, happy open-mouthed smile with sparkling eyes, raising a glowing golden bowl of rice high over her head with both hands. Radiant golden light rays burst from the bowl, sparkles and confetti everywhere. Behind the serving counter the cute purple-pink octopus dinner lady cheers with all her tentacles, and the six chibi helper girls from the lineup reference sheet cheer and jump around the table. Warm festive canteen. Keep the upper-left quarter of the frame simple (light rays and softly blurred canteen) so a title can sit there." &
wait
ls -la "$OUT"

# Red line: no whale icons in the scenery. The first p4/p6 takes put whales on banners, bunting and the
# chalkboard, so they are edited (same picture, only the decorations change).
FIX="Edit the reference image. Keep EVERYTHING exactly the same: every character, pose, face, the composition, colours, lighting and framing. Change only the background decorations: remove every whale symbol from banners, flags, bunting, signs and the chalkboard and replace it with plain decoration (blank cream or blue banners, simple stripes, small food doodles like a rice bowl or an onigiri on the chalkboard). No whale shapes anywhere in the background; the only whale emblem allowed is the tiny one on the blue-haired main girl's apron. No text."
gen p4_crew_fix "--image $OUT/p4_crew_0.png" "$FIX" &
gen p6_agi_fix "--image $OUT/p6_agi_0.png" "$FIX" &
wait
