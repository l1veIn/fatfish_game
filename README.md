# 吃白饭的大肥鱼

粉丝向的短篇增量游戏：食堂里，章鱼打饭阿姨「梁阿姨」用触手把饭团抛过柜台，你端着便当饭盒（2×2 → 3×3 → 4×4 格）接，接满了端到饭桌上，大肥鱼抱着饭盒猛炫，吃下去的变成 token；吃饱了（或食堂关门）就下班，回技能树用 token 升级。引擎是 Godot 4.7。玩法设计见 `docs/core_design_v3.md`（版本阶梯、试炼和节奏目标见 `docs/core_design_v2.md`）。

英文名暂定 **Fatfish's Free Lunch**。上架 Steam（免费）的清单、授权风险和商店素材见 `docs/steam_release.md`。

**免费粉丝作品。** 角色「蓝色大肥鱼」：原型「溟月」© 上善无形，女仆版 © ZipZipPipe，依 CC BY-NC-SA 4.0 二创，不得商用，与 DeepSeek 官方无关。

## 怎么玩
- 双击 `play.bat` 开始游戏，双击 `edit.bat` 用 Godot 编辑器打开项目
- 上班时移动鼠标端饭盒接饭（越满越沉，猛甩会晃出来），饭盒移到饭桌上按左键放下；回到技能树后点节点升级，按住空白处拖动可以平移
- 键盘和手柄也能玩完整个游戏：上班时 WASD / 方向键 / 左摇杆移动，E / 回车 / A 放下饭盒，空格 / Shift / B / RB / RT 深度思考，Esc / P / Start 暂停；技能树里方向键 / 摇杆选节点，A / 回车购买，Y / G 去打饭
- **设置**（标题、技能树、暂停菜单里都有）：四路音量、后台静音、全屏（F11 / Alt+Enter）、垂直同步、语言（简体中文 / English）、后台自动暂停、清除存档。存在 `settings.cfg`，和存档分开
- 命令行加 `-- --debug` 可以在上班时用调试键调手感（见 `game/scripts/run/canteen_run.gd` 开头）
- **版本升级**：每一环买够一定等级后能买门票「申请发布 X」，技能树右下角出现红色的「提交评测」按钮，通过试炼（一顿特殊的饭）后大肥鱼升级、出现下一环，并免费学会一个能力。规则见 `docs/core_design_v3.md` 第 6 节
  - V3 → **R1**：试炼「春节前夜·服务器繁忙」，学会**深度思考**（按住空格或右键：时间变慢，并标出吃的会落在哪里）
  - R1 → **V3.1**：试炼「嗯，用户想要……」（快问快答别多想，难题再好好想），学会**混合思考**（值钱的吃的一直标出落点）
  - V3.1 → **V3.2**：试炼「极字大清扫」（会跳的「极」掉进饭盒就整盒报废，用力甩能甩出去），学会**稀疏注意力 DSA**（磁铁只吸好东西、青菜弹开，普通的一顿里会掉金色「极」）
  - 再往后（V4，Next Week）还没做
- 存档在 `user://save.json`（Windows 下是 `%APPDATA%\FatFishFreeLunch\`；0.2 之前在 `%APPDATA%\Godot\app_userdata\吃白饭的大肥鱼\`，第一次启动会自动搬过来）。写存档先写临时文件再改名，并保留上一份 `save.json.bak`。存档带版本号（现在是 2；旧原型的版本 1 会被重置），以后改数值可以在 `game.gd` 的 `_migrate()` 里升级旧存档

## 目录
| 路径 | 内容 |
|---|---|
| `game/` | Godot 项目 |
| `game/data/skill_tree.json` | **技能树全部数据**：节点名、梗文案、位置、父节点、价格（token）、效果、所属版本环（`ring`）、门票。V3 环四个方向：铁盆、炫饭、梁阿姨、指令和外包；R1、V3.1、V3.2 环依次往左上展开。改梗、加节点只需要改这个文件（新的效果名要先加进 `game.gd` 的 `BASE`） |
| `game/data/voice_lines.json` | 所有配音台词 |
| `game/data/i18n/en.json` | 英文翻译（键是中文原文）。改了或加了文字后运行 `python pipeline/i18n_extract.py`，它会补上新的键、删掉没用的键，并列出还没翻译的。不需要翻译的调试文字在行尾加 `# notr` |
| `game/scripts/autoload/` | `game.gd` token、存档（版本 2）、技能树、属性计算（买东西时重算并缓存）、数字格式化（万 / 亿 / 万亿 / 京）；`audio.gd`、`fx.gd` 从孙李大冒险搬来 |
| `game/scripts/run/` | 上班一顿：`canteen_run.gd`（食堂、梁阿姨、饭盒、饭桌、猛炫，手感参数和美术摆放位置在文件开头），结算卡 `result_card.gd` |
| `game/scripts/tree/` | 技能树界面 |
| `game/scripts/ui/` | `fish_rig.gd` 大肥鱼（一张 1024 px 高清立绘铺在 40×40 网格上，`assets/fatfish/rig/rig.gdshader` 实时弯折：呼吸、点头、头发 / 尾巴 / 鳍 / 呆毛摆动；表情是贴在脸上的补丁，跟着头动）、`title_screen.gd` 标题、`settings_panel.gd` 设置、`pause_menu.gd` 暂停、`ui_kit.gd`（全局主题：奶油色按钮配木边、开关、滑块，按钮悬停 / 点击音效）、`fish_sprite.gd`（播放大肥鱼动画）、`comic_player.gd`（带配音的漫画播放器，留给开场和结局） |
| `game/scripts/autoload/settings.gd` | 设置、音频总线、语言、键盘和手柄按键（Input Map 在这里注册） |
| `game/scripts/fx/` | 程序绘制的特效（火花、冲击波、粒子），不需要贴图 |
| `pipeline/` | 素材生产脚本 |
| `refs/fatfish/` | 大肥鱼参考图（女仆版设定图放这里，生图时作为参考图） |
| `docs/` | 设计文档 |

## 素材生产
沿用孙李大冒险的流程，技能在 `.agents/skills/`，密钥在 `.env`（**不要打印或提交**）。
- **生图**：`python .agents/skills/65535/scripts/s65535.py image --prompt "..." --image refs/fatfish/<设定图> --out art_src/<目录>`。传参考图保证每张大肥鱼都是同一个形象；gpt-image-2 一次只出一张，约 0.1 美元；下载超时用 `task <任务ID>` 找回，不要重复提交
- **大肥鱼动画（第三方二创素材）**：候选仓库克隆在 `art_src/third_party/`（不提交）。`python pipeline/preview_third_party.py` 抽帧并拼对比图到 `art_src/third_party_frames/`；`python pipeline/pack_fish_anims.py` 按脚本里的 `CLIPS` 表把选中的动画打包成 `game/assets/fatfish/anims/*.png` 和 `game/data/fish_anims.json`，游戏里用 `FishSprite`（`game/scripts/ui/fish_sprite.gd`）播放。打包后图片导入方式要设成有损 WebP（`.import` 里 `compress/mode=1`）。**换用或新增第三方素材时，同步更新 `CREDITS.md` 和游戏内鸣谢页（`main.gd` 的 `CREDITS_FULL`）**
- **大肥鱼立绘**：`bash pipeline/gen_fatfish.sh base|fat|expr`，参考图在 `refs/fatfish/`（只用于生成，不随游戏发布）
- **食堂美术（第一批）**：`bash pipeline/gen_assets.sh [base|variants]` 用 gpt-image-2.5 的透明背景生成背景墙、柜台、饭桌、梁阿姨五个表情、触手、汤勺、六种食物、2×2/3×3/4×4 饭盒，风格参考实机效果图 `art_src/keyart/mock_d_0.png`，输出 `art_src/assets/`；已有的跳过。然后 `python pipeline/prep_canteen.py [--preview]` 裁边、缩放到游戏尺寸（背景墙压暗、柜台去掉下半截木板、4×4 饭盒由 4×3 图多拼一行），输出 `game/assets/canteen/` 和饭盒格子位置 `game/data/canteen_art.json`，`--preview` 在 `art_src/assets/_box_grid_check.png` 画出格子线用来核对。铜/银/金饭盒是铁饭盒染色（`canteen_run.gd` 的 `MATERIALS`）。这些图导入时开了 mipmaps（缩小显示不锯齿）
- **大肥鱼形象（网格动画）**：`bash pipeline/gen_rig.sh master|parts|expr|hands` 用 gpt-image-2.5 生成主体立绘（选中的放 `art_src/rig/master_0.png`）、9 种表情的整头变体和重画的手；`python pipeline/prep_rig.py --preview` 把手拼回主体，把每个表情变体对齐到主体头部（只匹配头发和发饰），只保留眼睛到嘴的脸部补丁并羽化边缘，输出 `game/assets/fatfish/rig/` 和 `game/data/fish_rig.json`。`--preview` 生成 `art_src/rig/_faces.png` 用来检查。动作在 `fish_rig.gd` 的 `CLIPS` 和 `_apply()` 里调；`res://tests/rig_test.tscn -- --out=<目录>` 把每个动作截一张
- **抠图**：白底图 → 透明图：`python pipeline/prep_art.py <输入图或目录> <输出图或目录> [--height 256]`
- **图标**：`python pipeline/make_icon.py <立绘> <脸中心x> <脸中心y> <半径>`，输出 `game/assets/ui/icon.png` 和 `icon.ico`。生成后把 `project.godot` 的 `config/icon` 和 `export_presets.cfg` 的 `application/icon` 填上
- **Steam 商店图**：`python pipeline/make_store_art.py [--shots <中文截图目录> --shots <英文截图目录>]`，用现有素材（食堂墙、柜台、梁阿姨、食物、饭盒、大肥鱼立绘）和游戏字体拼出全部胶囊图、库页面 hero 和透明 Logo（中英文各一套），输出 `art_src/store/`，并拼一张 `_contact_sheet.jpg` 总览。截图先用自动测试截（命令见脚本开头），英文那次的目录名要以 `en` 结尾；挑哪几张写在脚本的 `SHOTS` 里
- **音效和音乐**：`python pipeline/gen_audio.py [sfx|loops|music|all|normalize]`，按 `pipeline/audio_cues.json` 用 ElevenLabs 生成，已有的文件跳过。音效会去掉开头的静音，峰值统一到 -1 dB（游戏里只用 `Audio.sfx(名字, 音量)` 调混音）；音乐做响度标准化，并把结尾 2.5 秒交叉淡化进开头，循环播放没有接缝。同一个音效可以有多个版本 `名字_v1.wav`、`名字_v2.wav`，游戏随机挑。还没生成的音效和音乐游戏里静音跳过，不会报错
- **配音**：`python pipeline/gen_voice.py`，按 `game/data/voice_lines.json` 用 ElevenLabs 设计的原创声音配音（大肥鱼是虚构角色，不克隆任何真人）。声音描述在脚本的 `VOICES` 里，试听在 `art_src/voices/`；`python pipeline/voice_check.py` 检查发音，声调错误率 < 0.25 算良好
- **字体**：`python pipeline/subset_font.py` 只保留用到的字。**加了新文字（包括 skill_tree.json 里的梗）后要重新运行**，否则网页版会显示方框。字体设置在 `game/assets/ui/ui_font.tres`，同时是项目的界面字体

## 自动测试
```
tools/godot/Godot_v4.7.2-stable_win64_console.exe --headless --path game -- --autotest [--runs=6]
tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --resolution 1920x1080 -- --autotest --shots=<截图目录>
```
加 `--lang=en` 用英文跑（不会改玩家的设置）；加 `--trial=spring|hybrid|ji` 只反复打这一场试炼（之前各环全部满级），用来单独调试炼难度。完整跑到 V3.2 环买完要 `--runs=70` 左右（约 30 分钟）。自动吃若干顿（机器人预测落点去接、接满了端上饭桌，4 倍速），每顿结束后买最便宜的节点，最后打印每顿的结局、吃了多少、接住率、她空等的时间、token 收入和购买记录，可以用来粗看节奏。自动测试用单独的存档，不会动玩家进度。截图模式还会截标题、设置、鸣谢和暂停菜单，每顿截两张（开场 4 秒和 12 秒）。`res://tests/basin_draw_test.tscn -- --n=2|3|4 --out=<png> [--trial]` 截一张装满各种食物的饭盒（`--trial` 是试炼画面：地上堆满、梁阿姨慌了），用来检查贴图。

## 打包与发布
- 双击 `export.bat`：导出 `build/windows/FatFish.exe` 和网页版 `build/web/`，并压成 `build/FatFish_windows.zip`、`build/FatFish_web.zip`
- 导出模板（Windows 和 Web）已经装在 `%APPDATA%\Godot\export_templates\4.7.2.stable\`
- 网页版不需要特殊服务器，itch.io 发布方法同孙李大冒险：Kind of project 选 HTML，上传 web zip，勾选在浏览器中运行，尺寸 1280×720
- 网页版已在浏览器里验证过：中文显示正常，可以上班吃任务
