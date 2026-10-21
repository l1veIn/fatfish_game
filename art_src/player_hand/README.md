# 玩家之手素材

2026-10-21，使用内置 `image_gen`（imagegen 技能）生成，非 CLI/API 回退。用于替换程序绘制的手臂。正式素材：`game/assets/canteen/player_hand.png`；保留生成的透明通道，没有用脚本重画、抠图或拉伸图片文件。

参考为项目的 `game/assets/canteen/box_2.png` 与 RC5 GPU 游戏截图 `build/toy-final-rc5b/qa/touch-zh/player_hand_food.png`。饭盒是透视参照，未重绘。先生成掌心向上、托住近侧右角的手与蓝袖，再清理背景，最后按用户反馈延长袖子，供运行时裁显，避免拉伸。

最终输出：`exec-28a8cc82-b210-4489-b925-059f68706969.png`。前两轮输出：`exec-3af1d679-d754-4efe-b068-b0f8b5008db1.png`、`exec-6d7da745-2ded-479c-a2da-21330f837355.png`。原始生成文件留在本机 Codex generated_images 目录；游戏只依赖仓库内的正式 PNG。

## 最后一轮提示词（以上一轮手臂为编辑输入）

> Use case: precise-object-edit. Production game sprite revision of the reference. Preserve this exact beautiful anime hand gripping an invisible cafeteria tray, the palm-up supporting pose, fingers, cream cuff, warm skin shading, blue sleeve and elevated camera perspective. The forearm goes diagonally DOWN RIGHT at approximately 45 degrees, the invisible tray is upper left. Change ONLY the extent of the blue sleeve: extend it far toward lower right into a long, naturally cylindrical nearly constant-width sleeve, approximately SIX hand lengths from fingertips to sleeve end. The sleeve must not be a widening cone: after the cuff its two edges run parallel, with sparse soft longitudinal folds. No bent elbow, no tapering needle, no flared opening. Entire long arm fits diagonally in a square image with transparent margin. Make the hand large enough to read; the hand occupies roughly the upper-left one sixth of the diagonal. This will be cropped at different points along the sleeve in the game, without ever stretching the drawing. Fully opaque illustration with clean antialiased outline and actual transparent alpha background. Absolutely no glow, shadow or haze outside silhouette, no tray, no extra hand, no text.

## 运行时握持

`game/scripts/ui/player_hand.gd` 固定绘制比例和角度，饭盒遮住掌心与托底的手指；同一张图的拇指区域单独盖到饭盒近侧右角的外沿。食物格不随手臂变形。手臂距离及边缘调整只改变袖子裁切位置，不改变图片坐标到屏幕坐标的比例，不随触点扭曲或翻转。短距离保留完整手腕。
