# 铁盆大肥鱼 · 2026-10-20

用户要求：开场黑屏 Logo 和游戏图标统一为“头上扣铁盆、面无表情的大肥鱼”。保留原角色和游戏风格。

- 生成方式：Codex 内置 `image_gen`，真实透明背景，2026-10-20；未调用外部付费服务。
- 原图：`basin_deadpan_master.png`。参考原有 `game/assets/ui/icon.png`（替换前）和 `game/assets/portraits/release/fish_thinker.png`，只参考本项目角色身份。
- 交付：`game/assets/ui/icon.png`（512×512）、`icon.ico`（16/24/32/48/64/128/256 七种尺寸）。现有 boot_splash/image、config/icon、config/windows_native_icon 自动使用这套图；标题页艺术字不变。
- 机械转码：`python pipeline/pack_brand_icon.py art_src/brand/basin_deadpan_master.png`。只缩放及编码，保留生成的 alpha，不抠图、不重画。原尺寸预览在 `build/qa/brand-icon/native-sizes.png`。

## 实际生成提示词

Use case: logo-brand. Create one production-ready transparent square game icon / boot-splash mascot. The two reference images define the SAME blue-haired Fatfish maid character; preserve her distinctive dark-to-cyan blue hair, round chibi face, blue eyes, navy-and-white maid outfit and expressive hand-drawn anime illustration style. New composition: front-facing centered head and a tiny amount of shoulders, wearing a large ordinary stainless-steel cafeteria washbasin UPSIDE DOWN on her head like a silly helmet. The basin is silver grey, broad rolled rim sitting over her bangs, softly brushed metal and one clear restrained highlight. Critical expression: absolutely deadpan, half-lidded blue eyes, flat relaxed eyebrows, tiny straight horizontal mouth, no smile, no angry/scowling emotion, no blushing, no tears. The comedy comes ONLY from her blank expression and the upside-down metal basin. Hair should make a clean compact silhouette, recognizable at 32px. Very large face and basin occupying 90% of square with a safe transparent margin; simplified bold outer contours and large clear features suitable for a desktop icon. No hands, no book, no food, no lightbulb, no extra objects, no lettering, no badge/medallion border, no watermarks, no background, no shadow plate. Actual transparent alpha. Keep the familiar game's blue character palette and painted anime style; do not redesign the character.
