# 交接：继续打磨《吃白饭的大肥鱼》（2026-10-18）

目标：把游戏打磨到 Steam 精品级。先读这一页，再看 `docs/polish_roadmap.md`。

## 游戏现在是什么样

- **类型**：短篇增量游戏，Godot 4.7.2（`tools/godot/Godot_v4.7.2-stable_win64_console.exe`），一局 1–1.5 小时。
- **一顿饭的循环**：梁阿姨在一整条柜台后面抛菜（5 个窗口，主食在中间），玩家端饭盒接菜，凑齐自动合成套餐，送到桌上给大肥鱼吃。关门后结算，回技能树升级。
- **计分模型**「三联饭票」：口 → 盒 → 顿，见 `docs/tree_model.md`（第 9、10 节是定稿和实现记录）。四种吃法：暴食、美食家、食堂常客、吃菜邪修（顿悟）。
- **技能树**：74 个节点，由 `pipeline/build_tree.py` 生成（别手改 `skill_tree.json`）。界面是饭票软木板。
- **HUD**：设计语言见 `docs/hud_design.md`，包括五个固定区域、三级文字、红点和新功能卡。
- **声音**：
  - 大肥鱼和梁阿姨各有一个固定的 ElevenLabs 设计嗓音，由 `pipeline/gen_voice.py` 生成，嗓音 id 在 `art_src/voice/voices.json`。
  - 大肥鱼只用语气声，不说台词，人设是「臭屁小女孩」。
  - 所有触发点见 `docs/sound_list.md`（编号 1–53），混音规则也在那里。
  - 混音和音乐层在 `game/scripts/autoload/audio.gd`（顶部有总线图）。音乐层由 `pipeline/make_music_layers.py` 从上班音乐的节拍拼出来；示范音频由 `pipeline/render_sound_demos.py` 渲染。
  - 测试：`game/tests/audio_mix_test.tscn`（不加 `--headless` 才能测到真实出声）。
- **人设（用户 2026-10-18 定）**：前期的大肥鱼木讷、情感迟钝，不笑；表情随版本解锁（`Game.emotion()`：V3.1 以前 0 木讷、V3.2 偶尔闭眼小笑、V4 起完整表情，标题页换成站着微笑的立绘）。上班画面基本不变，只在吃到好东西时流露一下。
  - 标题页和技能树（V4 以前）：站着抱铁盆的全身像（`rig_basin`，`gen_rig.sh stand_basin` + `prep_rig.build_basin`，对齐在原立绘的画布上），鼠标移到头上变小手，摸头会慢慢不耐烦，最后把盆扣头上，鼠标变勺子，点击是敲盆声；放着不管盆会拿下来。
  - 吃饱关门：她滑到桌子后面，躺平图落到桌上（`fatfish/lie_full.png`，结算卡也用）。截图测试：`game/tests/deadpan_test.tscn`（要加 `-- --autotest`，用测试存档）。
- **特效和结账（2026-10-18 打磨）**：
  - Demo 时期的画圈、画方块特效都换成了 `gen_assets.sh polish` 生成的图：品级光晕、合成爆光、热气、星星、托盘、箭头、铜锁。
  - 九宫格和光晕工具在 `UiKit.nine()` / `glow()` / `vignette()`。
  - 食物品级不画圈（用户定的方案 D）：只改光，食物图不变。
    - 优质：冷白斜向扫光，偶尔一颗小星。
    - 金牌：贴轮廓的暖金辉光，会呼吸，加更快的扫光和轮流闪的金星。
    - 装进饭盒后只保留扫光。
    - 辉光和扫光帧由 `prep_canteen.food_rims()` 离线烘到 `canteen/rim/`、`canteen/sheen/`；`fx_silver` / `fx_gold` 不再用于食物。
  - 关门结账是饭票小票，见 `docs/settlement_design.md`。
  - 截图测试：`polish_test`、`checkout_test`、`crew_spread_test`（都在 `game/tests/`，加 `-- --autotest --out=<dir>`）。
- **节奏（机器人实测）**：第 13 顿发布 R1，21 顿 V3.1，25 顿 V3.2，31 顿 V4，35 顿 AGI。

## 和用户合作的方式（重要）

- **分工**：用户是作者兼玩家。数值和系统由我拍板，用户只从玩家角度反馈好不好玩、设定对不对味、名字好不好笑。给用户看的东西要写成「玩起来是什么样」，不放公式。
- **批注网页**：用户喜欢可批注的网页（db 存批注，事后用 ArtifactData 读回）。
  - 技能树设计页：https://claude.ai/artifact/HzHWGDhgTkuUKWzAWkvFjL
  - 声音清单页：https://claude.ai/artifact/V3A5j8PbbBJSfzvsRPzCfw
  - 声音收尾试听页（接菜声、音乐层、混音）：https://claude.ai/artifact/3A5BxfgCmpDdTUzrqyBZVu
  - 关门结账演示页（新结算流程、最后一口天赋、字体建议）：https://claude.ai/artifact/QHGeAJBy6BASwyw8FH7jqH ，设计见 `docs/settlement_design.md`、`docs/font_plan.md`，等用户批注后再实现。

  改完要在批注里写一条 `reply`（「已改：……」）。
- **花钱前先问**：生成图片、声音前先报数量和大概费用。下载东西也要先问。
- **用户会注意细节**：比如指出过食堂留样柜里的东西不能吃，所以设定细节要先核实。
- **交流用中文**。

## 红线（绝对不碰）

- **商标和官方**：不用 DeepSeek 官方 logo，不像官方出品，场景里不出现鲸鱼图标（只有她围裙上的小鲸鱼）。
- **敏感题材**：不碰「正统之争」，不娘化真人（包括梁文锋）。
- **角色**：
  - 梁阿姨是原创章鱼，「梁」只是名字。
  - 6 个外包小助手是原创 Q 版角色，只用昵称，不用商标。
- **「极」**：不进玩法，只在 V3.2 门票文字里提一句。
- **第三方素材**：`refs/ai_girl/` 是第三方未授权的图，不喂给生成器。
- **授权**：角色是 CC BY-NC-SA 4.0 二创（原型「溟月」：上善无形；女仆版：ZipZipPipe）。游戏免费、非商用。致谢写在 `CREDITS.md` 和 `game/scripts/main.gd`。
- **密钥**：`.env` 里有 API key，永远不要打印。

## 下一步（按 roadmap）

1. **声音（第 1 组）**：混音、音乐层、接菜声分类已做完（2026-10-18），等用户在试听页批注。还剩可选的「梁阿姨的声音再多几句」。
2. **手感（第 2 组）**：顿帧、轻微震屏、粒子（合成冒蒸汽、金牌拖尾）。都要在设置里能关。
3. **新手体验（第 3 组）**：第一顿只教「拿饭盒、接菜送桌」，用 HUD 的提示卡。
4. **内容（第 4 组）**：AGI 结局动画（现在通关什么都没有）、成就、图鉴奖励。
5. **Steam 必备（第 5 组）**：
   - 成就和云存档；
   - 手柄可用（Steam Deck）；
   - 显示设置；
   - 无障碍：减少动态效果、色盲友好、字号；
   - 商店页素材。
6. **已有任务卡**：英文翻译，`en.json` 还有 200 多条没翻。

## 常用命令和坑

- **Git**（2026-10-18 起）：私有仓库 GitHub `l1veIn/fatfish_game`，分支 `main`。
  - 图片、音频、字体、视频走 Git LFS（规则在 `.gitattributes`），免费额度 10 GB，现在用了约 1 GB。
  - 不进仓库的：`.env`（密钥）、`build/`、`tools/`（Godot 本体）、`art_src/third_party/` 和 `third_party_frames/`（第三方，`CREDITS.md` 记着版本，可以重新 clone）、`refs/`（别人的画，只放本地）。
  - Godot 的 `.import` 文件要提交（里面是导入设置），`game/.godot/` 不提交。
  - 生成的图和声音花了钱，生成完就提交，别只放在本地。

- **跑机器人**：在 `game/` 目录下运行

  ```
  ../tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path . -- --autotest --runs=N
  ```

  - 加 `--shots=<dir>` 并去掉 `--headless`、加 `--resolution 1920x1080`，会存截图。
  - 45 顿大约要 10–15 分钟，放后台跑。
  - 输出里有中文，过滤时用 `grep -a`。
- **两个 Godot 不能同时跑 autotest**：它们共用 `user://autotest_save.json`。
- **新增图片或声音以后**：先 `--headless --import` 一次，再跑。
- **声音的坑**：
  - 接菜声（catch*）和套餐「叮」（combo*）按响度对齐，不是按峰值，见 `gen_audio.py` 的 `LEVEL_LUFS`；同一类变体以前能差 9dB。
  - `perc_*` 是拼音乐层用的鼓点采样，只留在 `art_src/audio_raw/sfx/`，不进游戏。
  - 换了上班或评测音乐，要重跑 `make_music_layers.py`，层必须和原曲一样长。
  - headless 模式下 Godot 不混音，总线电平永远是 -200dB。
  - 退出时有声音在播会报 leaked instances（Godot 停声音是异步的），无害。
- **GDScript 的坑**：`var x := Dictionary 里的值` 会报「无法推断类型」，写成 `var x: float = ...`。
- **补丁脚本的坑**：在 Bash heredoc 里用 Python 写补丁时，反斜杠会被吃掉（`\n` 和正则反向引用都会坏）。复杂补丁先用 Write 写成 `.py` 文件再运行。
- **生图**（`pipeline/gen_assets.sh <stage>`，gpt-image-2.5）：
  - 场景参考图 `mock_d_0.png` 会把角色带进画面，纯道具不要带这张参考图。
  - 画面里不要文字，文字由代码绘制。
- **图片入库**：`pipeline/prep_canteen.py`（场景、道具、UI）、`pipeline/prep_rig.py --seat`（她的表情、小助手）。
- **字体**：加了新的中文文本后要重跑 `pipeline/subset_font.py`。两个字体：Noto Sans SC（正文）、站酷快乐体（数字和标题），都是 SIL OFL。
- **ElevenLabs**：
  - 不能设计儿童嗓音，要写成「成年声优演一个小女孩角色」。
  - 嗓音设计的示例文本至少 100 个字符。
  - 短声音由 `gen_voice.py` 的 MAXLEN 截短。
- **存档**：`Game.seen_buttons` 记录红点和新功能卡有没有出现过、点过。
