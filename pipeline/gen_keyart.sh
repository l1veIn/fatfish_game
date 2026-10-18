#!/usr/bin/env bash
# Key art for the whole canteen scene (run from repo root), used later as the style reference
# for every individual asset. Skips images that exist. Outputs art_src/keyart/<name>_0.png.
#   bash pipeline/gen_keyart.sh
# The 大肥鱼 reference is our generated chibi base (art_src/fatfish/base_0.png, CC BY-NC-SA 4.0
# derivative of 「溟月」/ ZipZipPipe's maid version). 梁阿姨 is an original octopus character.
set -u
OUT=art_src/keyart
mkdir -p "$OUT"

STYLE="Cute chibi anime game art, clean crisp lineart, soft cel shading, bright clear colours, cosy and funny mood, 16:9 game screen composition seen from the front, no text, no letters, no watermark, no UI."
FISH="the blue whale maid girl from the reference image (chibi, long wavy navy-to-sky-blue hair, whale-fin ears with a light-blue bow, white maid headdress, navy maid dress with white apron with a whale emblem, dark navy whale tail) - keep her design exactly as in the reference"
AUNTIE="a cute chubby purple-pink octopus dinner lady with a tall white chef's hat and a white apron, calm professional face, holding big metal ladles in several tentacles"
BOX="a square metal bento lunch box with compartments, seen in a three-quarter view from the front and above so the onigiri, dumplings and a chicken drumstick inside its compartments are clearly visible"

REFS="--image art_src/fatfish/base_0.png"
gen() {  # gen <name> <prompt>   (reference images come from $REFS)
  [ -f "$OUT/$1_0.png" ] && { echo "skip $1"; return; }
  python .agents/skills/65535/scripts/s65535.py image --model gpt-image-2 --resolution 2k --n 1 --size 16:9 \
    $REFS --out "$OUT" --name "$1" --prompt "$STYLE $2" 2>&1 | tail -1
}

gen keyart_a "An undersea school canteen: soft blue water light, bubbles and seaweed. Top third: a long wooden serving counter with a row of serving windows; behind it $AUNTIE, flinging onigiri rice balls, dumplings and a chicken drumstick over the counter in little arcs. Middle: the food flying through the water. Bottom centre: $BOX floating as if held by an unseen player, half full. Bottom right: a small wooden table where $FISH happily hugs another bento box and gobbles rice, cheeks stuffed, sparkles around her." &
gen keyart_b "Game screen of a cute catching game in an underwater cafeteria with tiled walls, warm lamps and drifting bubbles. Across the top a serving counter with windows; $AUNTIE leans over it, several tentacles each tossing food: onigiri, a bowl of rice, dumplings. Lower middle: $BOX catching the falling food. Lower right: a dining table with $FISH sitting behind it, eating from a full bento box with both hands, blissful face." &
wait

# In-game mockups ("实机图"): the greybox screenshot fixes the layout, key art A fixes the style.
REFS="--image art_src/keyart/layout_greybox.png --image art_src/keyart/keyart_a_0.png --image art_src/fatfish/base_0.png"
MOCK="Redraw the first reference image, a greybox screenshot of our 2D game, as the finished in-game screen in the art style of the second reference image. Keep the layout exactly: flat side-on 2D view, fixed camera, no perspective tricks. Top band: a long wooden serving counter across the screen with serving windows, and behind it, centred, $AUNTIE, its tentacles reaching to several windows with ladles; a few onigiri and dumplings arc over the counter. The big middle of the screen is open, calm and uncluttered (this is where the player catches food): a soft, darker, slightly blurred undersea canteen wall far behind with a few bubbles. Lower centre: $BOX, small, the size it has in the greybox. Bottom right: a wooden dining table with $FISH standing behind it, small like in the greybox. A dark floor strip along the bottom. Keep the top-left, top-right and bottom edge areas plain and darker so UI text can sit there later. Readable game art: clear silhouettes, foreground objects brighter than the background."
gen mock_a "$MOCK" &
gen mock_b "$MOCK Make the background a little more detailed (arched windows to the sea, lanterns) but still dim and out of focus so the food and the lunch box pop." &
wait

# Second round (2026-10-15): an ordinary canteen instead of undersea, and the lunch box as a
# standard square grid seen from a fixed 45° top-down angle. Layout from the new greybox, look
# from mockup B (characters, palette).
REFS="--image art_src/keyart/layout_greybox2.png --image art_src/keyart/mock_b_0.png --image art_src/fatfish/base_0.png"
BOX45="a square metal bento lunch box divided into a 3x3 grid of equal compartments, drawn from a fixed 45-degree top-down angle with no perspective distortion (orthographic), a few onigiri, dumplings and a chicken drumstick sitting in the compartments"
CANTEEN="Redraw the first reference image, a greybox screenshot of our 2D game, as the finished in-game screen, using the characters and the art style of the second reference image but moving the scene from underwater to an ordinary bright school/company canteen: cream tiled walls, a menu board, warm ceiling lights, stainless steel serving trays on the counter, no water, no bubbles, no fish, no seaweed. Keep the layout exactly: flat side-on 2D view, fixed camera. Top band: the long serving counter across the screen with serving windows, and behind it, centred, $AUNTIE, tentacles reaching to several windows with ladles, a few onigiri and dumplings arcing over the counter. The big middle of the screen is open and uncluttered (where the player catches food): the canteen wall far behind, softly out of focus and slightly darker. Lower centre: $BOX45, small like in the greybox. Bottom right: a canteen dining table with $FISH sitting behind it, small like in the greybox. A plain floor strip along the bottom. Keep the top-left, top-right and bottom edges plain so UI text can sit there later. No whale icons or logos anywhere except the small emblem on her apron."
gen mock_c "$CANTEEN" &
gen mock_d "$CANTEEN Slightly warmer, cosier evening light in the canteen." &
wait
echo KEYART_DONE
