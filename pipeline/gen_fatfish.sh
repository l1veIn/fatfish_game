#!/usr/bin/env bash
# 大肥鱼 character art via 65535 gpt-image-2 (run from repo root). Skips images that exist.
#   bash pipeline/gen_fatfish.sh base       # 1 locked base sheet from refs/fatfish/* (check it first!)
#   bash pipeline/gen_fatfish.sh fat        # fatness stages fat1-3, each referencing the base
#   bash pipeline/gen_fatfish.sh expr       # extra expressions (most are covered by the tndmgzo7 clips)
# Outputs art_src/fatfish/<name>_0.png on white; then:
#   python pipeline/prep_art.py art_src/fatfish game/assets/fatfish --height 512
# The character is 「溟月」(上善无形) / maid version (ZipZipPipe), CC BY-NC-SA 4.0: the results
# are derivative works under the same licence.
set -u
OUT=art_src/fatfish
mkdir -p "$OUT"

# In-game style: chibi so the fatness gag and expressions read at small sizes.
STYLE="Cute chibi anime character illustration, about 2.5 heads tall, clean crisp lineart, soft cel shading, bright clear colors, full character visible and centered, plain pure white background, no text, no watermark, no ground shadow."
DESC="the blue whale maid girl from the reference images: very long wavy dark navy-blue hair fading to bright sky-blue at the tips, a single curled ahoge, big round blue eyes, dark navy whale-fin ears with pale undersides on both sides of her head, a light-blue ribbon bow on the right fin, white frilly maid headdress, navy maid dress with white frilled blouse front, dark corset band with gold buttons, black neck bow with a small blue gem, puffy long sleeves with white frilled cuffs, white frilled apron with a small cute navy whale emblem, gold ribbon bows and gold vine embroidery on the skirt hem, white tights, navy Mary-Jane shoes, and a dark navy whale tail behind her"

REFS=""
for f in $(ls refs/fatfish/* 2>/dev/null | sort); do
  case "$f" in *.png|*.jpg|*.jpeg|*.webp|*.PNG|*.JPG|*.JPEG|*.WEBP) REFS="$REFS --image $f" ;; esac
done
[ -z "$REFS" ] && { echo "put the reference images into refs/fatfish/ first"; exit 1; }

gen() {  # gen <name> <refs> <prompt>
  [ -f "$OUT/$1_0.png" ] && { echo "skip $1"; return; }
  python .agents/skills/65535/scripts/s65535.py image --model gpt-image-2 --resolution 2k --n 1 --size 1:1 \
    $2 --out "$OUT" --name "$1" --prompt "$STYLE $3" 2>&1 | tail -1
}

case "${1:-}" in
base)
  gen base "$REFS" "Character design of $DESC, standing in a relaxed pose facing the viewer at a slight three-quarter angle, sleepy content smile, hands holding a small bowl of white rice in front of her belly."
  ;;
fat|expr)
  [ -f "$OUT/base_0.png" ] || { echo "generate and approve the base first"; exit 1; }
  B="--image $OUT/base_0.png $REFS"
  SAME="Exactly the same character, outfit, colours and art style as the first reference image."
  ;;&
fat)
  # fatness stages: she visibly gets rounder as the player upgrades (same pose and framing as the base)
  gen fat1 "$B" "$SAME Same pose as the first reference image, slightly chubbier: rounder cheeks and a small round belly pushing the maid apron forward, happy."
  gen fat2 "$B" "$SAME Same pose as the first reference image, clearly plump: very round body like a soft dumpling, puffy cheeks, the maid dress stretched round, still cute, satisfied smile."
  gen fat3 "$B" "$SAME Same pose as the first reference image, comically fat: an almost perfectly round ball-shaped body like a big blue fish ball, tiny arms and feet poking out, maid apron like a little bib, blissful closed-eye smile, a grain of rice on her cheek."
  ;;
expr)
  # expressions (base fatness, same framing)
  gen chew "$B" "$SAME Same pose, cheeks stuffed full of rice like a hamster, chewing happily, chopsticks in one hand, rice bowl in the other."
  gen think "$B" "$SAME Same pose, dazed daydreaming, looking up with a finger on her chin, a small thought cloud above her head with a bowl of rice in it, drool at the corner of her mouth."
  gen frenzy "$B" "$SAME Dynamic pose, wild comic frenzy: swirly spiral eyes, gritted teeth grin, both hands shovelling rice into her mouth at high speed with speed lines, steam puffing from her head."
  gen lunch "$B" "$SAME Cheerfully waving goodbye with one hand while walking away to lunch, holding an empty rice bowl and chopsticks in the other hand, carefree happy face."
  gen sleep "$B" "$SAME Curled up asleep on a big pillow, snot bubble from her nose, a laptop beside her showing a progress bar, peaceful."
  gen shock "$B" "$SAME Same pose, shocked surprised face with big round eyes and open mouth, sweat drop, startled with the rice bowl tipping over."
  ;;
*)
  sed -n 2,7p "$0"
  ;;
esac
