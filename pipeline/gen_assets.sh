#!/usr/bin/env bash
# First batch of in-game art (run from repo root). gpt-image-2.5 with a transparent background
# for every sprite, so nothing has to be keyed out; only the canteen wall is opaque.
# The look follows the approved in-game mockup art_src/keyart/mock_d_0.png.
#   bash pipeline/gen_assets.sh [stage]     stage: base | variants | all (default all)
# Outputs art_src/assets/<name>_0.png; skips names that already exist (delete one to redo it).
# 梁阿姨 is an original octopus character; 大肥鱼 is not in this batch.
set -u
OUT=art_src/assets
mkdir -p "$OUT"
MOCK="--image art_src/keyart/mock_d_0.png"
STYLE="Cute chibi anime game art matching the reference image: clean lineart with a slightly thick dark outline, soft cel shading, warm bright colours, no text, no letters, no watermark."
SPRITE="Single game sprite, centred, fully visible with a little margin, transparent background, no shadow on the ground, no other objects."
TOP45="seen from a fixed 45-degree top-down angle (orthographic, no perspective distortion)"

gen() {  # gen <name> <size> <background: transparent|opaque> <refs> <prompt>
  [ -f "$OUT/$1_0.png" ] && { echo "skip $1"; return; }
  local bg=""
  [ "$3" = "transparent" ] && bg="--background transparent"
  python .agents/skills/65535/scripts/s65535.py image --model gpt-image-2.5 --resolution 2k --n 1 --size "$2" \
    $bg $4 --out "$OUT" --name "$1" --prompt "$STYLE $5" 2>&1 | tail -1
}

stage=${1:-all}

if [ "$stage" = base ] || [ "$stage" = all ]; then
  # scene layers
  gen bg_wall 16:9 opaque "$MOCK" "Background layer only: the far wall of an ordinary warm school/company canteen in the evening, cream tiles, a menu board with pictures, pendant lights, a window to the kitchen, a few empty canteen tables and benches far away, softly out of focus. No counter in front, no characters, no food in the air. Keep the upper 30% and the middle calm and simple." &
  gen counter 16:9 transparent "$MOCK" "$SPRITE A long straight canteen serving counter seen straight from the front, filling the whole width: wooden front panel with eight evenly spaced cream name plates, a stainless steel top with a few trays of onigiri, dumplings and fried chicken. Only the counter, nothing behind it." &
  gen table 1:1 transparent "$MOCK" "$SPRITE A wooden canteen dining table seen from the front, slightly from above, simple and sturdy, empty top." &
  # 梁阿姨: the neutral pose first; the other expressions reference it
  gen auntie_normal 1:1 transparent "$MOCK" "$SPRITE The octopus dinner lady from the reference image: a cute chubby purple-pink octopus with a tall white chef's hat and a white apron with a small seashell emblem, calm friendly professional face, head and upper body only with short tentacle stubs at the sides (the long arms are drawn separately)." &
  # foods: 45-degree top-down item sprites, the test onigiri sets the look
  FOOD="--image art_src/assets/onigiri_ref.png $MOCK"
  gen food_bowl 1:1 transparent "$FOOD" "$SPRITE A small bowl of white rice $TOP45, white-and-blue rice bowl, matching the style of the onigiri reference." &
  wait
  gen food_leg 1:1 transparent "$FOOD" "$SPRITE A glazed fried chicken drumstick with a white bone end $TOP45, matching the style of the onigiri reference." &
  gen food_gold 1:1 transparent "$FOOD" "$SPRITE A shiny golden onigiri rice ball with a nori band and little sparkles $TOP45, a rare item, matching the style of the onigiri reference." &
  gen food_veg 1:1 transparent "$FOOD" "$SPRITE A single leaf of green bok choy (a vegetable the character hates) $TOP45, matching the style of the onigiri reference." &
  gen food_dump 1:1 transparent "$FOOD" "$SPRITE A single pleated Chinese jiaozi dumpling $TOP45, matching the style of the onigiri reference." &
  # tentacle pieces for the procedural arms
  gen tentacle 16:9 transparent "$MOCK" "$SPRITE One long straight horizontal octopus tentacle segment, purple-pink with suckers along the lower edge, same thickness from end to end, filling the width, to be used as a repeating texture." &
  gen ladle 1:1 transparent "$MOCK" "$SPRITE A big stainless steel serving ladle seen from the side, bowl at the left, handle to the right." &
  wait
fi

if [ "$stage" = variants ] || [ "$stage" = all ]; then
  AUNTIE="--image art_src/assets/auntie_normal_0.png $MOCK"
  SAME="Exactly the same octopus character, outfit, colours and framing as the first reference image, only the expression and pose change."
  gen auntie_shaky 1:1 transparent "$AUNTIE" "$SPRITE $SAME Shaky hands: nervous sweat drops, wobbly worried smile, little tremble lines." &
  gen auntie_busy 1:1 transparent "$AUNTIE" "$SPRITE $SAME Peak hours: determined fired-up face, steam puffs around the head, rolled-up energy." &
  gen auntie_panic 1:1 transparent "$AUNTIE" "$SPRITE $SAME Server crash panic: swirly eyes, mouth wide open, the chef's hat askew." &
  gen auntie_happy 1:1 transparent "$AUNTIE" "$SPRITE $SAME Celebrating: eyes closed happily, big smile, little confetti and a sparkle." &
  # lunch boxes: empty iron boxes, regular square grids; copper/silver/gold are recoloured in code
  BOXREF="$MOCK"
  BOX="$SPRITE An empty square stainless steel bento lunch box $TOP45: the opening is a perfect square seen from above with the front wall visible below it, the inside divided into a perfectly regular grid of equal square compartments by thin metal dividers, a narrow even rim all round, side clasps."
  gen box_2 1:1 transparent "$BOXREF" "$BOX The grid is 2 by 2 compartments." &
  gen box_3 1:1 transparent "$BOXREF" "$BOX The grid is 3 by 3 compartments." &
  # (the first try came out 4 columns x 3 rows, so the count is spelled out and the 3x3 box is a reference)
  gen box_4 1:1 transparent "--image art_src/assets/box_3_0.png $MOCK" "$BOX The same box design as the first reference image but bigger, with exactly sixteen equal compartments: four rows and four columns, a square grid (count them: 4 x 4 = 16)." &
  wait
fi
echo ASSETS_DONE

# The menu (docs/menu_design.md, data/menu.json): 18 more dishes and 15 套餐, same look as the
# first foods (45° top-down item sprites, the onigiri sets the style).
#   bash pipeline/gen_assets.sh menu
if [ "$stage" = menu ]; then
  FOOD="--image art_src/assets/food_ball_0.png --image art_src/assets/food_leg_0.png"
  dish() { gen "food_$1" 1:1 transparent "$FOOD" "$SPRITE $2 $TOP45, a single cute chunky game food item in exactly the art style of the reference images, no plate unless stated, no text." & }
  dish mantou "A plain white fluffy Chinese steamed bun (mantou), round and soft."
  dish congee "A white porcelain bowl of plain white rice congee, smooth and creamy."
  dish friedrice "A small round heap of golden egg fried rice with peas, carrot bits and spring onion."
  dish egg "A small white dish of Chinese tomato and scrambled egg stir-fry, red tomato and yellow egg."
  dish potato "A small white dish of shredded potato stir-fry (golden thin potato strips) with a few red chili slices."
  dish pork "A small white dish of glossy Chinese red-braised pork belly cubes (hong shao rou)."
  wait
  dish kungpao "A small white dish of kung pao chicken: diced chicken, peanuts and red dried chilies."
  dish bun "A Chinese steamed meat bun (baozi) with pleated top."
  dish youtiao "A golden fried dough stick pair (youtiao)."
  dish soymilk "A clear glass cup of warm white soy milk."
  dish xlb "A small bamboo steamer with three soup dumplings (xiaolongbao)."
  dish fries "A red paper cup of golden french fries."
  wait
  dish cola "A tall paper cup of iced cola with a straw and a lid, plain red and white cup, no logo, no text."
  dish burger "A fried chicken burger with lettuce and a sesame bun, slightly wide (it takes two cells)."
  dish pudding "A wobbly caramel custard pudding with caramel on top."
  dish milktea "A clear plastic cup of bubble milk tea with tapioca pearls and a wide straw, no logo."
  dish shuangpi "A small white bowl of Cantonese double-skin milk custard (shuang pi nai), smooth and white."
  dish icecream "A waffle cone with two scoops of ice cream, strawberry and vanilla."
  wait
  SET="--image art_src/assets/food_bowl_0.png --image art_src/assets/food_leg_0.png"
  combo() { gen "food_set_$1" 1:1 transparent "$SET" "$SPRITE A cute compact set meal for a canteen game, $2, everything arranged together on ONE small round plate or tray $TOP45, appetizing, in exactly the art style of the reference images, no text." & }
  combo carb "a 'carb bomb': a bowl of white rice, a steamed bun and an onigiri piled together"
  combo congee_mantou "a bowl of white congee with a steamed bun beside it"
  combo egg_veg "tomato and scrambled egg with a side of green bok choy"
  combo two_one "red-braised pork, kung pao chicken and shredded potato, three small portions"
  combo breakfast "a glass of soy milk with a pair of golden youtiao"
  wait
  combo happy "a fried chicken burger, a cup of fries and an iced cola (plain cups, no logo)"
  combo tea "a caramel pudding and a bubble milk tea, afternoon tea"
  combo homestyle "a home-style meal: a bowl of rice, tomato and egg, and bok choy"
  combo porkrice "a rice bowl topped with red-braised pork and shredded potato"
  combo bento "an onigiri bento with a chicken drumstick and bok choy in a small bento tray"
  wait
  combo chicken_rice "golden fried rice with a fried chicken drumstick and an iced cola"
  combo dimsum "a breakfast stand set: soup dumplings in a bamboo steamer, a bowl of congee and a glass of soy milk"
  combo summer "a summer special: a fried chicken burger, iced cola and an ice cream cone"
  combo deep "a bowl of congee with an ice cream cone stuck in it, a funny odd pairing, a tiny thought bubble with three dots above it"
  combo full "a lavish feast tray with a little bit of everything: rice, tomato egg, bok choy, a burger, fries, cola, youtiao, soy milk, pudding and milk tea, sparkling gold edges, a crown on top"
  wait
fi

# Round 3 (2026-10-17): five stalls with art per level and a shutter when closed, the sign plate
# their names are drawn on, the 保温箱, the 饭票软木板 for the skill tree, the 菜谱图鉴 page and the
# new 套餐 icons. Stall art is one section of the serving counter seen from the front; the main
# stall's level 1 sets the look for the rest. No text anywhere (the game writes the names).
#   bash pipeline/gen_assets.sh round3
if [ "$stage" = round3 ]; then
  STALL="$SPRITE One single section of a canteen serving counter seen straight from the front, about as wide as it is tall: a short counter front panel at the bottom, a stainless steel top with food trays behind a low glass sneeze guard, and a blank empty header board on top (no letters). Only this one section, nothing beside it, no people."
  gen stall_main_1 4:3 transparent "$MOCK" "$STALL A rice and staples section: a big rice cooker, trays of white rice and steamed buns, plain and simple, cream and wood colours."
  S1="--image art_src/assets/stall_main_1_0.png $MOCK"
  SAME="Same framing, size, viewpoint and art style as the first reference image."
  stall() { gen "stall_$1" 4:3 transparent "$S1" "$STALL $SAME $2" & }
  stall main_2 "A rice and staples section, upgraded: more trays (onigiri, congee pot, fried rice), a little steam, a red paper lantern."
  stall main_3 "A rice and staples section, deluxe: polished wood and brass trim, golden onigiri on a special plate, warm lights, two red lanterns."
  stall wok_1 "A stir-fry section: a wok on a small flame behind the glass, trays of bok choy and tomato egg, plain and simple."
  stall wok_2 "A stir-fry section, upgraded: two woks with bigger flames, trays of shredded potato and red-braised pork, steam."
  stall wok_3 "A stir-fry section, deluxe: a roaring wok fire, a tray of kung pao chicken, polished steel and red tiles, a red lantern."
  wait
  stall dim_1 "A dim sum and breakfast section: a stack of bamboo steamers, trays of baozi and youtiao, plain and simple."
  stall dim_2 "A dim sum section, upgraded: taller bamboo steamer stacks with steam, a soy milk urn, dumplings."
  stall dim_3 "A dim sum section, deluxe: many bamboo steamers puffing steam, soup dumplings on display, green tiles and a lantern."
  stall fry_1 "A fried food section: a deep fryer basket, trays of fried chicken drumsticks and fries, plain and simple."
  stall fry_2 "A fried food section, upgraded: two fryers, a cola dispenser (plain, no logo), more fried chicken."
  wait
  stall fry_3 "A fried food section, deluxe: shiny fryers, fried chicken burgers stacked, bright yellow and red trim, a lantern."
  stall sweet_1 "A dessert section: a small glass dessert fridge with puddings, a milk tea pitcher, pastel pink and mint colours, plain and simple."
  stall sweet_2 "A dessert section, upgraded: a bigger dessert fridge with double-skin milk custards, a bubble tea station with pearls."
  stall sweet_3 "A dessert section, deluxe: an ice cream freezer with cones on top, sparkling pastel lights, a pink lantern."
  wait
  shut() { gen "stall_$1_closed" 4:3 transparent "--image art_src/assets/stall_$1_1_0.png $MOCK" "$STALL $SAME The same section CLOSED: a rolled-down corrugated stainless steel roller shutter covers the whole food area down to the counter top, a blank cardboard sign (no letters) hangs on it with string, slightly dusty. $2" & }
  shut main "Cream and wood colours as the reference."
  shut wok "A hint of red tiles at the edges."
  shut dim "A hint of green tiles at the edges."
  shut fry "A hint of yellow trim at the edges."
  shut sweet "A hint of pastel pink at the edges."
  wait
  NOCHAR="No characters, no animals, no hands, nobody holding it: only the object."
  gen sign_plate 3:1 transparent "" "$SPRITE $NOCHAR A blank white plastic shop sign plate with a thin red border and rounded corners, slightly glossy, completely empty in the middle (no letters, no drawings), seen straight from the front." &
  gen warm_box 1:1 transparent "$MOCK" "$SPRITE A small stainless steel food warmer cabinet seen from the front, a glass door with a warm orange glow inside, an empty shelf, a little heat lamp on top, cute and chunky." &
  gen cork_bg 16:9 opaque "$MOCK" "A big cork notice board filling the whole picture, seen straight on, warm brown cork texture with a simple wooden frame at the edges, a few old pin holes, softly lit, nothing pinned on it, no paper, no text. Calm and even so things can be placed on top." &
  gen ticket 3:2 transparent "" "$SPRITE $NOCHAR A blank cream-coloured canteen meal ticket stub with a perforated tear-off edge on the right and a thin printed border, completely blank (no letters, no numbers), seen straight from the front, flat." &
  wait
  gen ticket_gold 3:2 transparent "--image art_src/assets/ticket_0.png" "$SPRITE $NOCHAR $SAME The same meal ticket in shiny gold paper with a faint sparkle, still completely blank (no letters, no numbers)." &
  gen stamp 1:1 transparent "" "$SPRITE $NOCHAR A round red ink rubber-stamp mark, slightly uneven and faded like real ink, a double ring with a simple rice bowl icon in the middle, no letters." &
  gen pin 1:1 transparent "$MOCK" "$SPRITE A single red push pin seen from the front and a little above, glossy round head." &
  gen recipe_page 16:9 opaque "$MOCK" "An open recipe notebook filling the whole picture, seen from straight above: two cream lined pages with a soft fold in the middle, a few small grease stains and a pencil doodle of a rice bowl in a corner, completely empty otherwise, no text." &
  wait
  SET="--image art_src/assets/food_bowl_0.png --image art_src/assets/food_leg_0.png --image art_src/assets/food_set_happy_0.png"
  combo() { gen "food_set_$1" 1:1 transparent "$SET" "$SPRITE A cute compact set meal for a canteen game, $2, everything arranged together on ONE small round plate or tray $TOP45, appetizing, in exactly the art style of the reference images, no text." & }
  combo deluxe_breakfast "a deluxe breakfast: soy milk with youtiao, soup dumplings in a bamboo steamer and a baozi"
  combo bucket "a family bucket: a paper bucket of fried chicken drumsticks with a burger, fries and cola beside it (plain, no logo)"
  combo dessert_bar "a dessert table: a pudding, a bubble milk tea, a double-skin milk custard and an ice cream cone"
  combo kungpao_rice "a set: kung pao chicken, red-braised pork and shredded potato with a bowl of white rice"
  wait
  combo family "a canteen family feast: rice, red-braised pork, soup dumplings, a chicken drumstick, a pudding and a steamed bun, little stars"
  combo stew "a messy mixed stew (luan dun) in a small clay pot, random bits of everything, a bit chaotic but tasty, a small flame mark"
  combo emerge_stew "a glowing mystic mixed stew in a golden clay pot with sparkles and swirls of light rising, a legendary dish"
  wait
fi

# Round 3b (user: five separate booths don't feel like a canteen): one continuous counter with
# empty food pans (the game fills them with each window's dishes) and a shutter piece that
# covers one window's pans when it is closed.
#   bash pipeline/gen_assets.sh counter2
if [ "$stage" = counter2 ]; then
  gen counter_long 3:1 transparent "$MOCK" "$SPRITE No characters, no people, no text. A long continuous Chinese school canteen serving counter seen straight from the front, filling the whole width edge to edge: a stainless steel top with ONE long straight row of fifteen identical rectangular stainless steel food pans in five groups of three (the groups separated by thin steel posts), all pans EMPTY and clean, seen slightly from above so the inside of each pan shows; a raised glass sneeze guard shelf high above the pans so the pans stay fully visible; a few warm lamps hanging over it; a cream tiled front panel with wooden trim below. Busy-looking but tidy, warm light."
  gen counter_shutter 3:2 transparent "--image art_src/assets/counter_long_0.png" "$SPRITE No characters, no people, no text. A short section of rolled-down corrugated stainless steel roller shutter, a wide rectangle seen straight from the front, slightly dusty, with a blank cardboard sign hanging on a string (no letters), matching the metal and lighting of the reference counter."
fi

# HUD kit (docs/hud_design.md): 12 icons and 6 blank UI pieces in the game's look. No text, no
# characters (the scene mockup is left out on purpose: it pulls characters in).
#   bash pipeline/gen_assets.sh hud
if [ "$stage" = hud ]; then
  ST="--image art_src/assets/food_bowl_0.png"
  ICON="$SPRITE No characters, no people, no text, no letters, no numbers. A single small game UI icon, bold and readable at small size, chunky cartoon shape with a thick dark outline, in exactly the art style of the reference image:"
  icon() { gen "icon_$1" 1:1 transparent "$ST" "$ICON $2" & }
  icon token "a shiny gold coin with a tiny embossed rice bowl in the middle."
  icon flame "a small lively orange and yellow flame."
  icon drool "a single glossy blue drool droplet next to a small silver spoon."
  icon chain "two linked red chain links."
  icon leaf "a fresh green bok choy leaf with a little sparkle."
  icon crown "a small gold crown with three red gems."
  wait
  icon clock "a round cream canteen wall clock with a red rim and two hands, tick marks only."
  icon box "a tiny stainless steel lunch box with a lid."
  icon dice "a red cube die with white dots."
  icon shield "a small sturdy blue shield with a white rim."
  icon bolt "a bright yellow lightning bolt."
  icon bell "a small brass hand bell, ringing, with motion lines."
  wait
  UI="$SPRITE No characters, no people, no text, no letters, no numbers, completely blank in the middle so text can go on it, seen straight from the front, flat, in the art style of the reference image:"
  gen ui_badge 2:1 transparent "$ST" "$UI a small white enamel badge plate with a cobalt blue rim and rounded corners, glossy, like an old enamel sign." &
  gen ui_bubble 3:2 transparent "$ST" "$UI a white comic speech bubble with a thick dark outline and a short pointed tail at the bottom left." &
  gen ui_chalkboard 3:2 transparent "$ST" "$UI a small dark green chalkboard with a simple wooden frame and faint chalk smudges." &
  gen ui_paper 1:1 transparent "$ST" "$UI a square piece of cream meal-ticket paper with a thin brown printed border and a perforated top edge." &
  wait
  gen ui_banner 4:1 transparent "$ST" "$UI a wide red ribbon banner with folded tails at both ends, slightly worn like a stamp print." &
  gen ui_tray 3:1 transparent "$ST" "$UI an empty light-colored cafeteria food tray seen from straight above, divided into three equal compartments side by side." &
  wait
fi

# 2026-10-18 polish pass (user: replace the demo-era "cheap" effects): effect sprites, table trays,
# a hand-drawn arrow and a padlock for the skill tree. Plain props: no scene reference (it pulls
# characters in); the table art keeps the style.
#   bash pipeline/gen_assets.sh polish
if [ "$stage" = polish ]; then
  T="--image art_src/assets/table_0.png"
  FX="Single game visual-effect sprite for a cute 2D anime canteen game, centred, transparent background, soft glowing edges that fade out, no objects, no characters, no text:"
  gen fx_silver 1:1 transparent "" "$FX a delicate silvery-white shimmer halo: a soft ring of pale silver light with three or four small crisp four-pointed star glints around it, empty in the middle." &
  gen fx_gold 1:1 transparent "" "$FX a warm golden glow halo: a soft round aura of golden light with sparkling gold four-pointed stars and tiny glitter dots around it, empty in the middle." &
  gen fx_burst 1:1 transparent "" "$FX a cheerful cartoon celebration burst: a ring of chunky cream-white and golden comic action rays radiating out, with a few round puffs of white steam between them, empty in the middle." &
  wait
  gen fx_steam 1:1 transparent "" "$FX a single cute cartoon puff of white steam rising from hot food, soft round curly cloud shape with a gentle wavy tail at the bottom, a light outline." &
  gen fx_star 1:1 transparent "" "$FX a single bright four-pointed sparkle star, golden yellow with a white hot centre and a thin dark outline, crisp, like a twinkle in an anime." &
  gen tray_empty 3:2 transparent "$T" "$SPRITE A low wooden serving tray (a plain shallow box tray with short sides) seen from the front and a little above, empty, made to hold a stack of lunch boxes, matching the table's wood and art style, no text." &
  wait
  gen tray_full 3:2 transparent "$T" "$SPRITE A red plastic canteen serving tray seen from the front and a little above, empty, slightly glossy, with a small cream ticket clip on its front edge (blank), matching the art style of the reference, no text." &
  gen ui_arrow 3:2 transparent "" "$SPRITE A short chunky hand-drawn arrow pointing to the right, cream white with a thick dark brown outline, slightly wobbly like chalk on a menu board, no text." &
  gen icon_lock 1:1 transparent "" "$SPRITE A small cute brass padlock, chunky and rounded, with a keyhole, thick dark outline, soft cel shading, game UI icon, no text." &
  wait
fi
