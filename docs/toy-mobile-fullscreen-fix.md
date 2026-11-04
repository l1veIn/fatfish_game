# Toy mobile canvas fill — 2026-10-21

The published screenshot had two independent margins: the Toy HTML shell subtracted all SDK/CSS safe-area insets from the entire game canvas, and Godot kept a 16:9 viewport inside the remaining wide phone rectangle.

The design resolution remains **1920×1080**. Project resolution, authored gameplay positions, collision rules, tray/character proportions and desktop resolution preferences are unchanged. Only Web runtime presentation enables Godot's expand aspect. A fixed-size authored stage is centered in the available viewport, with aspect-preserving scenery covering the extra background area. Canvas CSS now fills the entire iframe. Safe-area insets constrain touch controls rather than shrinking scenery.

The camera translation is included in native touch/mouse event conversion for the serving hand, finger buttons, skill-tree drag/pinch and the touch-layout editor. Fade layers, notices, background images and modal shades follow resizing. Saved control coordinates retain the existing normalized design space.

## Verification

- `build/qa/toy-fullscreen-baseline5/report.json`: 105 checks, zero failures, unchanged player files. Real viewport touch/drag, GUI clicks, keyboard and controller event paths at 16:9.
- `build/qa/toy-fullscreen-input6/report.json`: 113 checks, zero failures, unchanged player files. Expanded 1328×610 phone ratio (the user's 2656×1220 screenshot at half scale), explicit CSS safe-area fixture, runtime resize to 1280×720 and 1200×800, then back to 1328×610. Integral viewport rounding is permitted within one render pixel.
- Earlier failed fixtures/imports are retained separately. An initial new-script UID was absent before export; it is now present in the source tree and final source manifest. Hidden QA windows needed explicit `RenderingServer.force_draw()` to capture frames when occluded. The concurrent native input run failed four serving assertions; the sequential standard and wide runs passed. Focus changes are a possible cause, not a confirmed diagnosis. No production tap timing was relaxed.
- Final Web loader, cloud bridge and HTML checks: 32 Node tests passed. Packaging unit checks: 6 passed.
- `build/toy-final-rc11/qa/fullscreen-validation.json` binds the passing reports and all staged production script hashes to the final archive. Source/staging script hashes match.
- Chrome WebGL was checked at the phone ratio, including a local CSS-safe-area fixture. These are browser and GPU fixture checks, not a physical Bilibili App certification. Toy's native top-right menu/close capsule remains platform-owned.

## Candidate

- `build/toy-final-rc11/FatFish-0.4.2-toy-compressed.zip`
- Size: 48,089,676 bytes (under the account's 50,000,000-byte limit).
- SHA-256: `5fdc4bdbd45a8771b2c2a35e13cbff375b6e792be674df1c56fba87e7f400f0b`
- Content pack: `index-e55f83162731.data`; asset filenames remain content-addressed to avoid immutable-CDN cache reuse.
- Preview: https://www.bilibili.com/toy/preview/preview_NoJ3OeDX/index.html
- Existing published Toy: https://www.bilibili.com/toy/fatfish-free-lunch/index.html

The existing Windows ZIP was not rebuilt or replaced for this mobile display update.

Update submitted to the existing Toy at 18:03 CST. Publication verification is recorded in the candidate QA folder once review completes.

Review passed at 18:05 CST. The live HTML references `index-e55f83162731.data` (40,538,532 bytes), matches the candidate Godot configuration, and contains the new full-viewport canvas CSS. See `build/toy-final-rc11/qa/live-verification.json` and `toy-update-approved.png`.
