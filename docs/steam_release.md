# 上架 Steam（免费）清单

> 2026-10-16 起草。Steam 的规则会变，提交前以 Steamworks 后台和 partner.steamgames.com 文档为准。
> 标 ✅ 的已经在游戏里做好；标 👤 的只能你本人做（账号、付款、授权、问卷）；标 🔧 的是还能继续做的开发工作。

## 1. 游戏里已经做好的（Steam 审核和玩家会看的基本功）

- ✅ **启动页**：食堂夜景 + 飘落的饭菜 + 大肥鱼待机（点她会叫一声、做个动作），Logo 掉落动画，按钮依次淡入；开始/继续上班、设置、鸣谢、退出；右下角版本号；底部署名行
- ✅ **设置**（标题、技能树、暂停菜单都能打开，存在 `settings.cfg`，和存档分开）
  - 声音：总音量 / 音乐 / 音效 / 配音四条音量（四条音频总线），切到后台时静音
  - 画面：全屏（F11、Alt+Enter 随时切换），垂直同步
  - 游戏：语言（简体中文 / English，第一次启动跟随系统语言），切到后台自动暂停
  - 存档：清除存档（要点两次确认）
- ✅ **暂停菜单**（Esc / P / 手柄 Start，或窗口失去焦点）：继续、设置、提前下班（结算已经吃下的）、回到标题。试炼中途离开算失败
- ✅ **手柄和键盘全流程**（Steam Deck 需要）：
  - 上班：左摇杆 / WASD / 方向键移动饭盒，A / E / 回车放下饭盒，B / RB / RT / 空格 / Shift 深度思考，Start / Esc 暂停
  - 技能树：方向键 / 摇杆在节点间移动，A 购买，Y / G 去打饭，Start / Esc 设置
  - 菜单：方向键选、A 确认、B 返回
- ✅ **音乐和音效**：4 首可无缝循环的 BGM（标题、上班、技能树、春节试炼），食堂环境音，37 个音效（接住、弹开、洒出、掉地、开炫、暴击、挑食、高峰、深度思考、服务器繁忙、宕机、通过 / 失败、版本升级、UI 悬停 / 点击等）。菜单打开时音乐自动压低
- ✅ **存档安全**：存档目录改成 ASCII 的 `%APPDATA%\FatFishFreeLunch\`（Steam 云存档好配置）；先写临时文件再改名，并保留上一份 `save.json.bak`，写一半断电也不会坏档；旧版本的存档自动迁移过来
- ✅ **图标、exe 信息、启动画面**：`icon.ico` 进 exe，文件版本 0.2.0，产品名中英文
- ✅ **英文界面**：全部 140 条文字（包括技能树的梗）都有英文，见 `game/data/i18n/en.json`
- ✅ **AI 内容声明**：鸣谢页写明哪些美术、音效、音乐用 AI 辅助生成

## 2. 只能你来做的 👤

### 2.1 账号和费用
- 注册 Steamworks 合作伙伴账号，完成身份验证、银行和税务信息（免费游戏也要填）
- 每个应用要交 **100 美元 Steam Direct 费用**。这笔钱要在游戏收入满 1000 美元后才退，免费游戏实际上拿不回来
- 「即将推出」商店页至少公开 **两周** 才能正式发布；商店页和游戏版本都要经过 Valve 审核（各需要几个工作日）

### 2.2 授权（最大的风险，建议先做）
Steam 要求你对游戏里所有内容拥有权利或得到许可。我们的角色是二创，所以：
1. **角色作者**：上善无形（原型「溟月」）、ZipZipPipe（女仆版），协议都是 CC BY-NC-SA 4.0。NC（非商业）允许免费发布，但仍然**强烈建议私信两位作者，拿到一句书面同意**（截图保存）：说明是免费、开源、不盈利、署名、上架 Steam。审核或日后有人投诉时，这就是凭证
2. **第三方动画**：✅ 已解决（2026-10-16）。大肥鱼改用我们自己生成的高清立绘 + 网格变形动画，tndmgzo7、PC2005-cloud、YunYueSama 三个仓库的动画已经不在游戏里了，不用再去问这几位作者
3. **不要开 Steam DRM**：CC BY-NC-SA 禁止对素材加技术限制措施，所以 Steamworks 里不要启用 Steam DRM 包装（DRM wrapper）。游戏保持开源
4. **ShareAlike（相同方式共享）**：我们的美术是二创衍生，所以也必须按 CC BY-NC-SA 发布（鸣谢页已写）
5. **商标**：商店标题、标签、宣传图里不要把 DeepSeek 的名字或 logo 当卖点；简介里写一句「粉丝作品，与 DeepSeek 官方无关」就够了
6. **梁阿姨**：原创章鱼角色，「梁」只是名字。商店文案也不要往真人身上靠（红线不变）

### 2.3 内容问卷
- **AI 生成内容披露**（Steam 内容调查问卷）：要如实勾选「预先生成的内容」：美术（gpt-image）、音效和音乐（ElevenLabs），并说明经过人工挑选和修整；我们**没有**运行时生成的 AI 内容
- ElevenLabs 现在是 Creator 套餐，允许商用（免费发布更没问题）。65535 中转的 gpt-image 生图条款请你确认一下
- 年龄和内容问卷：没有暴力、色情、赌博内容

### 2.4 商店页素材（尺寸以后台为准）
✅ 已做好，都在 `art_src/store/`，总览见 `art_src/store/_contact_sheet.jpg`。重新生成：`python pipeline/make_store_art.py`（只用现有素材，没有调用生图 API）。带文字的图都有中文（`_zh`）和英文（`_en`）两版：Steamworks 里先传中文版作为默认，再在「本地化」里给英语传 `_en` 版。

| 素材 | 尺寸 | 文件 | 备注 |
|---|---|---|---|
| Header capsule | 920×430 | `header_capsule_zh/en.png` | 左边 Logo，右边梁阿姨在柜台后抛饭、大肥鱼端着饭碗 |
| Small capsule | 462×174 | `small_capsule_zh/en.png` | 只有 Logo 和大肥鱼的脸，缩小也认得出 |
| Main capsule | 1232×706 | `main_capsule_zh/en.png` | 比 header 多一个装满的 3×3 饭盒 |
| Vertical capsule | 748×896 | `vertical_capsule_zh/en.png` | Logo 在上 |
| Library capsule | 600×900 | `library_capsule_zh/en.png` | 同上，窄一点 |
| Library hero | 3840×1240 | `library_hero.png` | 没有文字；角色在中间偏右，左边留给 Logo |
| Library logo | 1082×680 / 1240×445，透明 | `library_logo_zh/en.png` | 在后台把 Logo 放在 hero 的左下 |
| 截图 | 1920×1080 | `screenshots/zh_01…06.png`、`screenshots/en_01…05.png` | 自动测试实机截图（高峰、开炫、暴击、技能树、结算卡、标题）。中文 6 张，英文 5 张，英文那套传到「本地化截图」 |
| 预告片 | 推荐 30–60 秒 | — | 🔧 还没做，第一秒就要看到玩法 |

注意：
- **红线已检查**：图里没有 DeepSeek 的名字和 Logo；大肥鱼饭碗上的小鲸鱼已经在脚本里抹掉，只留围裙上的鲸鱼徽章；没有「官方」字样
- **胶囊图上只能有美术和游戏名**（Valve 规定），所以没写「免费」「粉丝作品」之类，这些写在简介里
- **截图里的大肥鱼动画**：上班画面里饭桌旁的动画和标题画面的待机动画是第三方素材（见 2.2 第 2 条）。如果哪段问不到授权、换成了我们自己的动画，要重新截图：`tools/godot/Godot_v4.7.2-stable_win64_console.exe --path game --resolution 1920x1080 -- --autotest --runs=10 --shots=<目录>`（英文再加 `--lang=en`，目录名以 `en` 结尾），然后 `python pipeline/make_store_art.py --shots <中文目录> --shots <英文目录>`，必要时改脚本里的 `SHOTS` 重新挑
- 截图里还没有试炼和 R1 以后的能力（自动测试 10 顿还到不了 R1）。现在可以用 `--trial=spring|hybrid|ji --runs=1 --shots=<目录>` 直接截某一场试炼（之前各环满级），建议补一两张试炼截图（「极字大清扫」的「极」最有辨识度）
- 现在的图都是用游戏里的素材拼的。想要更像「海报」的专门插画（比如大肥鱼抱着饭盒猛炫的特写），可以用 gpt-image-2.5 生成，约 0.04 美元一张，一般要试 5–10 张，**生成前会先问你**

### 2.5 商店文案草稿
- 中文短描述：在食堂接住章鱼梁阿姨抛来的饭团、鸡腿和饺子，端给大肥鱼猛炫，吃下去的变成 token。升级饭盒、技能树，带她从 V3 一路发布到 R1、V3.1、V3.2……免费粉丝作品。
- English short description: Catch the onigiri, drumsticks and dumplings that Auntie Liang the octopus flings across the canteen, and feed them to the Fatfish, who turns every bite into tokens. Grow your lunch box, climb the skill tree and ship her from V3 through R1 and V3.1 to V3.2. A free fan game.
- 标签建议：Casual、Incremental、Cute、Anime、Arcade、2D、Cartoony、Female Protagonist、Funny、Free to Play、Singleplayer、Short
- 语言：简体中文（界面、字幕），英语（界面、字幕）。没有配音的话就不要勾「完全音频」

## 3. 发布前还建议做的开发 🔧

1. **内容量（最重要）**：已经做到 V3.2（V3 → R1 → V3.1 → V3.2，三场试炼），机器人一路买完 V3.2 环大约要 65 顿，按真人每顿约 1 分钟（含逛树）估算约 1–1.2 小时，见 `core_design_v3.md` 第 6 节最后的自动测试数据。还缺**一个结局**（现在 V3.2 环买完后只剩「申请发布 V4：敬请期待（Next Week）」），建议发布前至少做一个简短的收尾演出，或者把 V4 门票做成结局入口。Steam 的「Demo」必须挂在一个本体游戏下面，所以我们应该直接发**完整的免费游戏**，而不是「试玩版」
2. **云存档**：不用接 SDK。在 Steamworks 里配 Auto-Cloud：Windows 根目录选 `WinAppDataRoaming`，子目录 `FatFishFreeLunch`，文件匹配 `save.json*`
3. **成就**（要接 GodotSteam，需要下载它的 GDExtension，**下载前我会先问你**）：例如「吃饱了！」第一次吃饱、「金饭碗」、「服务器繁忙」试炼零失败通过、「我不胖！」胃升满、「层层外包」、「wait… aha」等
4. **Steam Deck**：1280×800 是 16:10，现在会上下留黑边。可以改成 `expand` 让食堂背景铺满。字号在 7 寸屏上也要检查
5. **Linux 版**：要下载 Linux 导出模板（同样先问你）。不做的话 Deck 也能用 Proton 跑 Windows 版
6. **配音**：大肥鱼的几句招牌台词（`game/data/voice_lines.json`），设置里已经有配音音量
7. **预告片**（截图已做好，见 2.4）
8. **崩溃和反馈**：在鸣谢页或标题放一个反馈链接（GitHub Issues / B站）

## 4. 上传流程（到时候再细化）
1. Steamworks 新建应用，填商店页，提交「即将推出」审核
2. 用 SteamPipe（steamcmd + ContentBuilder 脚本）上传 `build/windows/`：一个 Windows depot，启动项 `FatFish.exe`
3. 配云存档，填价格「免费」，提交版本审核
4. 「即将推出」满两周后发布
