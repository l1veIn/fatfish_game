#!/usr/bin/env bash
# 大肥鱼 as a layered rig (like a Live2D-lite paper doll), generated with 65535 gpt-image-2.5
# on a transparent background. Run from repo root.
#   bash pipeline/gen_rig.sh master     # 3 candidate master figures (pick one, rename to master_0.png)
# Later stages (parts, expressions) reference art_src/rig/master_0.png.
# Outputs art_src/rig/<name>_0.png; skips names that exist (delete one to redo it).
# The character is 「溟月」(上善无形) / maid version (ZipZipPipe), CC BY-NC-SA 4.0: the results
# are derivative works under the same licence. No company logos anywhere: the apron has her own
# small whale emblem only.
set -u
OUT=art_src/rig
mkdir -p "$OUT"
REFS="--image art_src/fatfish/base_0.png"
for f in refs/fatfish/*.jpg; do REFS="$REFS --image $f"; done

STYLE="High quality cute chibi anime character art for a 2D game rig, about 2.5 heads tall, clean crisp lineart with consistent line weight, soft cel shading with gentle highlights, bright clear colors, no text, no watermark, no shadow on the ground, transparent background."
DESC="the blue whale maid girl from the reference images: very long wavy dark navy-blue hair fading to bright sky-blue at the tips, a single curled ahoge, big round blue eyes, dark navy whale-fin ears with pale undersides on both sides of her head, a light-blue ribbon bow on one fin, white frilly maid headdress, navy maid dress with white frilled blouse front, black neck bow with a small blue gem, puffy long sleeves with white frilled cuffs, white frilled apron with a small cute navy whale emblem (no other logo), gold ribbon bows and gold vine embroidery on the skirt hem, white tights, navy Mary-Jane shoes, and a dark navy whale tail behind her"
# a pose that splits cleanly into parts: arms away from the body, hair behind the body
POSE="Full body, standing straight and facing the viewer (front view, symmetrical), centred, both arms hanging relaxed slightly away from the body so the arms do not overlap the torso, open hands, the long hair falls behind her body and shoulders (not over the arms), the whale tail sticks out to her left side behind her, gentle closed-mouth smile, eyes open looking at the viewer, head level."

gen() {  # gen <name> <refs> <prompt>
  [ -f "$OUT/$1_0.png" ] && { echo "skip $1"; return; }
  python .agents/skills/65535/scripts/s65535.py image --model gpt-image-2.5 --resolution 2k --n 1 --size 1:1 \
    --background transparent --quality high $2 --out "$OUT" --name "$1" --prompt "$STYLE $3" 2>&1 | tail -1
}

case "${1:-}" in
master)
  gen master_a "$REFS" "Character sheet pose of $DESC. $POSE" &
  gen master_b "$REFS" "Character sheet pose of $DESC. $POSE Slightly rounder, softer chibi proportions." &
  gen master_c "$REFS" "Character sheet pose of $DESC. $POSE Very polished modern gacha-game chibi rendering, rich hair shading." &
  wait
  ;;
parts)
  # layers that are partly hidden in the master (the rest is cut from master_0.png by
  # pipeline/prep_rig.py); each keeps the master's canvas framing so it can be aligned
  M="--image $OUT/master_0.png"
  LAYER="Paper-doll layer for a 2D game rig, drawn from the reference image of this exact character, in exactly the same art style, size and position on the same square canvas as in the reference."
  gen hair_back "$M" "$LAYER Draw ONLY her long back hair mass: remove the head, face, front hair, fins, headdress, body, arms, legs and tail, and paint in completely the part of the hair that was hidden behind her head and body, so it is one complete wavy hair shape." &
  gen tail "$M" "$LAYER Draw ONLY her dark navy whale tail, complete, including the base that was hidden behind her skirt and hair; nothing else." &
  ARMS="$LAYER Draw ONLY her two arms (puffy navy maid sleeves with gold embroidery, white frilled cuffs, small hands), cut off at the shoulders, nothing else, same arm size as in the reference."
  gen arms_hold "$M" "$ARMS The two arms are bent, both hands together in front of her belly holding a small white-and-blue bowl of white rice." &
  gen arms_mouth "$M" "$ARMS The arms are bent upwards, both hands raised to her mouth holding a white onigiri rice ball with nori, about to take a bite." &
  wait
  gen arms_up "$M" "$ARMS Both arms raised high above the shoulders in a happy cheer, hands open." &
  gen arms_fists "$M" "$ARMS Both arms bent with small clenched fists held in front of her chest, a determined protesting pose." &
  wait
  ;;
expr)
  # whole-head variants: prep_rig.py aligns each to the master head and keeps only the eyes and
  # mouth, so the hair never changes between expressions
  H="--image $OUT/ref_head.png"
  SAME="Redraw exactly this character's head from the reference image, identical framing, size, position, angle, hair, fins and headdress, same art style; only the facial expression changes, transparent background."
  gen ex_blink "$H" "$SAME Both eyes gently closed (a relaxed blink, curved lash lines), same calm closed-mouth smile." &
  gen ex_happy "$H" "$SAME Very happy: eyes closed in upside-down U shapes (^ ^), big open smiling mouth, a little extra blush." &
  gen ex_chew "$H" "$SAME Chewing a big mouthful: cheeks puffed out round like a hamster, mouth closed, eyes squeezed shut happily." &
  wait
  gen ex_open "$H" "$SAME Eyes wide open and sparkling, mouth wide open in an eager 'aaah' about to take a bite." &
  gen ex_puppy "$H" "$SAME Pleading puppy eyes: big watery sparkling eyes with tears at the corners, small wobbly frown, begging for food." &
  gen ex_pout "$H" "$SAME Indignant pout: eyebrows angled down, eyes narrowed, cheeks slightly puffed, small pouting mouth, as if saying 'I'm not fat!'." &
  wait
  gen ex_surprised "$H" "$SAME Surprised: eyes very round with small pupils, small round open 'o' mouth." &
  gen ex_sleepy "$H" "$SAME Full and sleepy: half-closed content eyes, small satisfied smile, soft blush." &
  gen ex_think "$H" "$SAME Thinking hard: eyes looking up and to the side, mouth a small flat line, one eyebrow raised." &
  wait
  ;;
*)
  echo "usage: bash pipeline/gen_rig.sh master|parts|expr"
  ;;
esac
# hands: the master's hands came out with too few, splayed fingers. Each hand crop
# (ref_handL/R.png = master crops, see prep_rig.py HAND_CROPS) is redrawn and pasted back.
if [ "${1:-}" = hands ]; then
  for side in L R; do
    for v in 1 2; do
      gen hand${side}${v} "--image $OUT/ref_hand${side}.png" "Redraw exactly this crop of the character from the reference image, identical framing, size and position, same sleeve cuff, hair and colours, transparent where the reference is empty. Only fix the hand: a small cute chibi hand with correct anatomy, exactly five fingers (four fingers held loosely together and a thumb), relaxed and slightly curled, palm turned toward the body, soft simple shapes like in polished chibi game art." &
    done
  done
  wait
fi
# seated at the canteen table (the shift's rig): upper body from the waist up, holding her own
# iron basin (铁盆), front view, same character as master_0.png
if [ "${1:-}" = seated ]; then
  M="--image $OUT/master_0.png"
  SEAT="Exactly this character from the reference image (same face, hair, fins, headdress, maid outfit, art style and colours), now drawn from the waist up as if sitting behind a canteen table (the table itself is NOT drawn, the image simply ends at her waist with a clean straight cut), front view, symmetrical, centred, head level, gentle closed-mouth smile, eyes open."
  gen seat_a "$M" "$SEAT She holds a big empty round stainless-steel basin (a plain iron wash-basin style bowl, no pattern, no logo) in both hands in front of her chest, elbows bent, the basin rim at chin height so her face is fully visible above it." &
  gen seat_b "$M" "$SEAT She holds a big empty round stainless-steel basin (a plain iron wash-basin style bowl, no pattern, no logo) in both hands in front of her tummy, the basin tilted slightly toward the viewer, her face fully visible." &
  gen basin "--image $OUT/master_0.png" "Single game prop sprite, centred, transparent background, no shadow, no text: a big plain round stainless-steel basin (iron wash-basin style bowl, slightly worn, cute and chunky, matching the art style of the reference), seen from the front and a little above so a bit of the inside shows. No character." &
  gen basin_flip "--image $OUT/master_0.png" "Single game prop sprite, centred, transparent background, no shadow, no text: the same big plain round stainless-steel basin turned upside down (like a helmet), seen from the front, matching the art style of the reference. No character." &
  wait
fi
# seated rig: expression variants of seat_0's head, pose variants of the whole seated figure
if [ "${1:-}" = seat_more ]; then
  H="--image $OUT/ref_seat_head.png"
  SAME="Redraw exactly this character's head from the reference image, identical framing, size, position, angle, hair, fins and headdress, same art style; only the facial expression changes, transparent background."
  run() { gen "$@" & }
  run sx_blink "$H" "$SAME Both eyes gently closed (a relaxed blink), same calm closed-mouth smile."
  run sx_happy "$H" "$SAME Very happy: eyes closed in upside-down U shapes (^ ^), big open smiling mouth, extra blush."
  run sx_chew "$H" "$SAME Chewing a big mouthful: cheeks puffed out round like a hamster, mouth closed, eyes squeezed shut happily."
  run sx_open "$H" "$SAME Eyes wide open and sparkling, mouth wide open in an eager 'aaah' about to take a bite."
  wait
  run sx_puppy "$H" "$SAME Pleading puppy eyes: big watery sparkling eyes with tears at the corners, small wobbly frown."
  run sx_pout "$H" "$SAME Indignant pout: eyebrows angled down, eyes narrowed, cheeks puffed, small pouting mouth."
  run sx_surprised "$H" "$SAME Surprised: eyes very round with small pupils, small round open 'o' mouth."
  run sx_sleepy "$H" "$SAME Full and sleepy: half-closed content eyes, small satisfied smile, soft blush."
  wait
  run sx_think "$H" "$SAME Thinking hard: eyes looking up and to the side, mouth a small flat line."
  run sx_star "$H" "$SAME Delighted: sparkling star-shaped highlights in her wide eyes, open happy mouth, drooling a tiny bit."
  S="--image $OUT/seat_0.png"
  POSE="Redraw exactly this character from the reference image, identical framing, size, position, hair, outfit and art style, transparent background, drawn from the waist up with the same clean cut at the waist; only her arms, hands, the iron basin and her expression change:"
  run sp_eat_lift "$S" "$POSE she raises the iron basin, now heaped with white rice, up to her chin with both hands, mouth wide open about to take a big bite, eyes sparkling."
  run sp_eat_scoop "$S" "$POSE her left hand holds the basin heaped with white rice at her chest, her right hand holds a big metal spoon full of rice at her mouth, cheeks puffed, chewing happily with eyes closed."
  wait
  run sp_bang_up "$S" "$POSE her left hand holds the empty basin at her tummy, her right hand is raised high holding a metal spoon, about to bang the basin; impatient pouting face."
  run sp_bang_down "$S" "$POSE her left hand holds the empty basin at her tummy, her right hand with a metal spoon strikes the rim of the basin (little clang motion lines); impatient pouting face, eyes squeezed."
  run sp_sulk "$S" "$POSE the empty basin is worn upside down on her head like a helmet over her headdress, her arms are crossed over her chest, cheeks puffed, pouting, looking away to the side."
  run sp_cheer "$S" "$POSE both arms raised high holding the empty basin above her head, eyes closed in a big happy smile."
  wait
  run sp_full "$S" "$POSE she leans back a little with both hands patting her round full tummy, the empty basin resting low in front of her, content sleepy smile, blush."
  run sp_think "$S" "$POSE her left hand holds the basin low in front of her, her right index finger on her chin, thinking, eyes looking up."
  wait
fi
# 外包 helpers: ORIGINAL super-deformed chibis (not copies of anyone's design), each with one
# palette and one generic motif, both hands raised as if carrying a box overhead (the box is
# drawn by the game). No logos, no letters, no emblems.
if [ "${1:-}" = crew ]; then
  CREW="High quality super-deformed chibi anime girl for a 2D game, about 2 heads tall, round and cute, clean lineart, soft cel shading, same art style as the reference image, full body, front view, standing, both arms raised above her head with open hands as if carrying something overhead (nothing in her hands), cheerful face, transparent background, no shadow. No logos, no letters, no emblems, no symbols on the clothes."
  R="--image $OUT/master_0.png"
  gen crew_wen "$R" "$CREW Long light-blue and lilac hair in a side braid, a small navy cap, a white-and-blue Chinese-style dress with a little folding fan tucked in her sash." &
  gen crew_pu "$R" "$CREW Long straight black hair, black cat ears, a black-and-white gothic dress, a small book tucked under one arm strap." &
  gen crew_g "$R" "$CREW Fluffy white hair, small white dragon horns and tiny dragon wings and tail, a simple white dress, lavender eyes." &
  gen crew_ke "$R" "$CREW Long orange hair, warm cream-and-orange dress with a dark sash, a small book hanging from her belt, calm gentle smile." &
  wait
  gen crew_zi "$R" "$CREW Wavy blue-to-purple gradient hair, purple cat ears, a sparkly purple-and-white outfit with little star sparkles around her." &
  gen crew_ge "$R" "$CREW Blonde twin tails, tiny bat wings, a black-and-red gothic dress, a mischievous fang smile." &
  wait
fi
# v2 (2026-10-16, user feedback): deadpan beats sweet smiles, and the iron basin is BIG — worn
# upside down it sits deep, rim at the eyebrows, much wider than her head. Older versions are in
# art_src/rig/old/.
DEADPAN="a deadpan, expressionless face: big round eyes with a blank empty stare, upper eyelids a little lowered, a tiny flat mouth (no smile)"
if [ "${1:-}" = deadpan ]; then
  H="--image $OUT/ref_seat_head.png"
  SAME="Redraw exactly this character's head from the reference image, identical framing, size, position, angle, hair, fins and headdress, same art style; only the facial expression changes, transparent background."
  gen sx_blank "$H" "$SAME $DEADPAN, looking straight at the viewer." &
  gen sx_jitome "$H" "$SAME Unimpressed half-lidded flat stare (jitome), eyelids lowered halfway, tiny flat mouth, totally deadpan." &
  gen sx_stuffed "$H" "$SAME Cheeks stuffed round with food like a hamster, mouth closed, but the eyes stay blank and deadpan, staring straight ahead." &
  gen sx_o "$H" "$SAME Blank stare with a tiny round open 'o' mouth, deadpan." &
  wait
  gen sx_tear "$H" "$SAME $DEADPAN, with one small tear welling in the corner of an eye, quietly sad." &
  S="--image $OUT/seat_0.png"
  POSE="Redraw exactly this character from the reference image, identical framing, size, position, hair, outfit and art style, transparent background, drawn from the waist up with the same clean cut at the waist; only her arms, hands, the iron basin and her expression change:"
  gen sp_sulk "$S" "$POSE the big iron basin is worn upside down on her head like an oversized helmet: it sits deep, its rim resting just above her eyebrows and covering her headdress and the top of her hair, the basin much wider than her head; her arms hang down at her sides; $DEADPAN, staring straight ahead. Keep the whole basin inside the picture." &
  gen sp_eat_lift "$S" "$POSE she raises the iron basin, heaped with white rice, up to her chin with both hands, mouth open in a small 'aaa', eyes blank and deadpan." &
  gen sp_eat_scoop "$S" "$POSE her left hand holds the basin heaped with white rice at her chest, her right hand holds a big metal spoon full of rice at her mouth, cheeks stuffed round, eyes blank and deadpan." &
  wait
  gen sp_bang_up "$S" "$POSE her left hand holds the empty basin at her tummy, her right hand is raised holding a metal spoon, about to bang the basin; $DEADPAN." &
  gen sp_bang_down "$S" "$POSE her left hand holds the empty basin at her tummy, her right hand with a metal spoon strikes the rim of the basin (small clang motion lines); $DEADPAN." &
  wait
fi
if [ "${1:-}" = crew2 ]; then
  for c in wen pu g ke zi ge; do
    gen crew_$c "--image $OUT/old/crew_${c}_0.png" "Redraw exactly this chibi character from the reference image, same design, outfit, colours, pose (both arms raised above her head, hands open, nothing in them), size and art style, transparent background, no logos or symbols; only the face changes to $DEADPAN — like an emotionless little food-serving machine." &
    [ $c = pu ] && wait
    [ $c = ke ] && wait
  done
  wait
fi
# helpers asleep while there is no empty box to take: each sleeps differently, so a row of
# sleepers stays readable (standing / curled up / lying / sitting)
if [ "${1:-}" = crew_sleep ]; then
  SLEEP="Redraw exactly this chibi character from the reference image (same design, outfit, colours, size and art style), transparent background, no logos, fast asleep with a deadpan sleepy face, a small 'z' optional is NOT drawn (the game adds it):"
  gen crew_wen_sleep "--image $OUT/crew_wen_0.png" "$SLEEP standing upright asleep, arms hanging down, head tilted, a snot bubble at her nose." &
  gen crew_pu_sleep "--image $OUT/crew_pu_0.png" "$SLEEP curled up lying on the floor like a sleeping cat, seen from the front, low and wide." &
  gen crew_g_sleep "--image $OUT/crew_g_0.png" "$SLEEP lying flat on her tummy on the floor, cheek on her folded arms, little dragon tail up, seen from the front, low and wide." &
  wait
  gen crew_ke_sleep "--image $OUT/crew_ke_0.png" "$SLEEP sitting on the floor with her knees up, hugging her book, head nodding forward." &
  gen crew_zi_sleep "--image $OUT/crew_zi_0.png" "$SLEEP lying on her back sprawled like a starfish on the floor, seen from the front, low and wide." &
  gen crew_ge_sleep "--image $OUT/crew_ge_0.png" "$SLEEP standing asleep with her head drooped forward and arms dangling, little bat wings folded." &
  wait
fi

# Round 3 (2026-10-17): 顿悟 faces for the seated head (forcing greens down, then getting it), and
# two more poses per helper: running sideways with a box overhead, and a jumping cheer (a 套餐 made).
#   bash pipeline/gen_rig.sh round3
if [ "${1:-}" = round3 ]; then
  H="--image $OUT/ref_seat_head.png"
  SAME="Redraw exactly this character's head from the reference image, identical framing, size, position, angle, hair, fins and headdress, same art style; only the facial expression changes, transparent background."
  gen sx_grimace "$H" "$SAME Forcing down a vegetable she hates: eyes squeezed shut, face scrunched, cheeks a little green-tinged, lips pressed tight with a tiny bok choy leaf poking out, still deadpan at heart." &
  gen sx_grok "$H" "$SAME Sudden enlightenment: eyes wide open with bright sparkling star highlights, a small amazed open mouth, a little shine around her head, as if realising vegetables are delicious." &
  RUN="Redraw exactly this chibi character from the reference image (same design, outfit, colours, size and art style), transparent background, no logos, no letters:"
  for c in wen pu g ke zi ge; do
    gen "crew_${c}_run" "--image $OUT/crew_${c}_0.png" "$RUN running to the right in side view, mid-stride with one foot off the ground, both arms raised above her head with open hands as if carrying something overhead (nothing in her hands), determined deadpan face." &
    gen "crew_${c}_cheer" "--image $OUT/crew_${c}_0.png" "$RUN jumping up in a happy cheer, front view, one fist raised high, the other arm out, feet off the ground, a small proud smile." &
    [ "$c" = g ] && wait
  done
  wait
fi
# 2026-10-18 deadpan pass (user: early 大肥鱼 is emotionally flat, 木讷): the end-of-shift "吃饱躺平"
# (lying on her back on the canteen table; also the result card) and two title-screen cursors.
#   bash pipeline/gen_rig.sh lie
if [ "${1:-}" = lie ]; then
  S="--image $OUT/seat_0.png --image $OUT/master_0.png"
  LIE="Exactly this character from the reference images (same face, hair, fins, headdress, maid outfit, whale tail, art style and colours), full body, lying flat on her back after a huge meal, seen from the front and a little above, horizontal composition filling the width: her head on the left, the long blue hair spread out under her, arms flopped out to the sides, her tummy round and full under the apron, legs stretched out to the right, the whale tail resting by her feet. Eyes peacefully closed, small flat closed mouth, completely content but expressionless (no grin), a small 'z' sleep bubble is NOT drawn. An empty round stainless-steel basin lies tipped over on its side next to her hand. No table, no floor, no shadow, transparent background, no text."
  gen lie_a "$S" "$LIE" &
  gen lie_b "$S" "$LIE A slightly rounder, softer chibi pose, one hand resting on her round tummy." &
  gen cursor_hand "--image $OUT/master_0.png" "Single small game UI icon, centred, transparent background, no text, no shadow: a cute chibi cartoon open hand (palm facing down, fingers together, soft skin tone, thick dark outline) as if about to pat someone's head, seen from above at a slight angle, simple and readable at 64 pixels, matching the art style of the reference." &
  gen cursor_spoon "--image $OUT/master_0.png" "Single small game UI icon, centred, transparent background, no text, no shadow: a cute cartoon stainless-steel soup spoon held diagonally, bowl of the spoon at the top-left and handle to the bottom-right, thick dark outline, simple and readable at 64 pixels, matching the art style of the reference." &
  wait
fi
