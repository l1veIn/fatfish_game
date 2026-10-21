# Toy 0.4.2 发布候选验收

更新：2026-10-21（北京时间）。状态：**候选包已上传，Toy 线上预览可运行；未发布、未提交审核，等待用户决定。真实云同步与物理手机仍未验收。**

## 候选与复现

- 当前实现提交：`f2114edf9a6b77460c6bffe94af6199ef9bd2af8`，分支 `codex/toy-release`，已推送远端；在 RC3 基础上加入触控布局编辑、半透明交互键、5 token 自动化、长按回滚与 App 容器修复。
- 前置作者链接修改：`f99bf7e`，已推送 `main`。
- ZIP：`build/toy-final-rc4/FatFish-0.4.2-toy-compressed.zip`。
- ZIP 字节数：48,012,892（48.01 MB，十进制）；当前 Toy 账号上限 50 MB。
- SHA-256：`fdcb34cb600af36cd8868c8682ad768a5001a6872f206819a6587b997087ea64`。
- 完整构建、输入和输出摘要：`build/toy-final-rc4/build-manifest.json`。
- 复现：`py -3 pipeline/build_toy.py --output build/toy-release-rebuild --max-zip-mb 50`。
- Web 本地预览：从 `build` 目录启动 HTTP 服务，访问 `/toy-final-rc4/web/index.html`。请勿直接用 `file://` 打开。

Godot 4.7.2 Compatibility、WebGL 2、单线程，不要求跨源隔离。资源路径相对入口，主资源包改用 Toy 允许的 `.data` 扩展名；代码许可、素材署名和字体许可随包保留。编辑器插件、测试和调试工具不进入发行包。

原有 `game/project.godot` 的 Godot MCP 编辑器配置及未跟踪的 `game/addons/` 属于既有本地改动，未纳入这次提交。

## 体积与画质

无损基线 ZIP 114,523,671 字节，当前候选减少约 58.08%。两者包含不同阶段的桥接和字体修改，此数字是版本总体对比，不是完全隔离的压缩 A/B 实验。

压缩仅修改构建副本的纹理导入配置，游戏原始 PNG 未被重绘或覆盖。123 张压缩纹理通过尺寸和透明通道逐像素检查，透明通道完全一致；最低可见 RGB PSNR 为 30.287 dB。小型食物、功能 UI、字体图集及两个敏感精灵保留无损。中英招牌、人物、徽章及标题的对照图已查看，未见影响识别的缺陷。

证据：`build/toy-final-rc1/qa/texture-quality.json`、`texture-comparison.jpg`。

压缩减少下载体积，不减少解码后的纹理内存。没有据此宣称手机帧率、内存或低端设备表现合格。

## RC4 触控设置、回滚与 App 容器

「设置 → 游戏 → 触控布局：位置与尺寸」可分别拖动原生摇杆、交互键与思考键，并调整 65%～160% 大小。布局保存到独立设置文件，提供取消及恢复默认；取消不会保存草稿。实际游戏复用这些位置、尺寸；接菜区域继续忽略触屏拖盒和触摸生成的鼠标事件。右侧按钮背景常态透明度为 32%，按下为 55%，文字保持清晰。

`skills` 节点仍在第一层，自动推送与自动回收一起改为 5 token。测试用仅有根节点及 5 token 的进度，经真实 GUI 购买并检查两项效果。回滚先打开说明框，只有连续按满 3 秒才执行；短按、双击、松手、移出按钮、失焦均不能触发或累计时长。

B 站 App 的全屏请求改为 SDK 就绪后自动发起，SDK 延迟到首次等待结束以后仍会重试初始化；并发初始化只注册一次监听。请求返回本身不算成功，以容器状态确认；未确认时提供「全屏」重试入口。订阅先于请求，旧的初始状态读取不能覆盖较新的横屏通知。画布按实际 iframe 的 100vw/100dvh 尺寸与安全区排版，不再用 SDK 可能滞后的竖屏宽高限制横屏画布。设置里的 Web 全屏开关接入 Toy 模式并显示实际确认状态。

- 中英各 73 项通过、0 失败，960×540 GPU 运行；涵盖全部三个控件的位置与大小编辑、保存重载、取消、非法配置边界、游戏内应用、触控及桌面输入切换、3 秒回滚与 5 token 购买。存档与用户设置原文件的前后摘要未变。
- 桌面输入 260 项、存档回归 41 项通过。后者的损坏备份和未来版本告警来自显式测试夹具。
- JS 平台桥接 18 项通过，包含 SDK 晚到、初始化去重及旧容器状态竞态。
- Chrome 实际 iframe 几何测试通过：模拟 SDK 在进入后到达，容器从 390×844 改为 844×390，旧 SDK 仍报告竖屏宽高，画布正确按左右 44、底部 21 安全区展开到约 756×369。该测试使用模拟 SDK 和假引擎，仅验证真实 CSS 尺寸及桥接顺序，不代表真实 B 站 App 或 Godot 手机渲染。
- 触控报告所列游戏源码、翻译与字体摘要和 RC4 构建输入一致；测试脚本单独比对，项目配置由隔离构建处理。构建再次通过 50 MB、文件后缀、888 个所需汉字覆盖及 123 张纹理尺寸/透明通道检查。

证据在 `build/toy-final-rc4/qa/`：中英 `touch-*/report.json` 与截图、桌面/存档/JS 日志、`container-fixture/browser-result.json`、`container-fixture/browser.jpg` 和源码摘要。浏览器容器测量使用小于 1 CSS px 的误差范围，兼容缩放产生的亚像素尺寸。

RC4 已通过 Toy 上传校验，线上完成标题、设置、游戏标签、触控布局编辑器及取消返回检查；现有进度仍为第 5 顿、大肥鱼 V3、20 token，未保存任何设置更改。控制台仅 B 站 reporter 的 spmId 告警，未捕获游戏错误。`qa/release-evidence.json` 绑定 ZIP、源码、日志与截图摘要，`toy-ready-unpublished.jpg` 记录当前草稿及未点击的发布按钮。

**B 站 App 真机的黑框变化仍待用户用 RC4 预览确认。** 修复的是丢失的沉浸请求与过期视口限制；游戏保留 16:9 比例，宽屏设备可能仍有比例留边。此轮没有重测音频输出，RC2 修复保留；实际云同步仍未验收。正式发布未点击。

## RC3 内置摇杆与底部引导

项目的 Godot 4.7.2 已提供原生 [VirtualJoystick](https://docs.godotengine.org/en/stable/classes/class_virtualjoystick.html)，该控件在 [Godot 4.7](https://godotengine.org/releases/4.7/) 引入。本次直接实例化引擎控件，以 `move_left/right/up/down` 接入现有 InputMap，和实体手柄走同一个 `Input.get_vector` 及饭盒移动逻辑；没有自写摇杆绘制、触摸向量或摇杆插件。用户提供的 Toy SDK 能力文档没有摇杆接口，导出 Android APK 本身也不会自动生成系统摇杆界面；控件仍需放置在游戏的触控界面里。本轮未导出或验收 APK。

触控布局为左摇杆、右侧大「交互」键和较小的「按住思考」键；大键复用原先的拿盒、送饭、放回及保温箱路径，不能远程送饭。接菜区域不再响应手指拖盒。引导固定在底部，中间留出说明区域，两侧留给操作；饭盒活动下边界相应上移，引导及完成提示均不再跟随饭盒跳动。帮助和中英提示已同步更新，字体已重新裁集。

4.7.2 的原生摇杆没有公开 reset 方法，且失焦不会自动清除内部触点。本项目在暂停、失焦或离开场景时释放动作，必要时在通知遍历结束后重建该引擎控件，防止旧手指在恢复游戏后重新带动饭盒。

- 中英触控各 55 项通过、0 失败，960×540 GPU 运行：包括真实 ScreenTouch/ScreenDrag 经 Viewport/GUI 派发、两指移动与思考、触点取消、控件外松手、暂停、失焦恢复、取盒接菜送饭、桌面输入切换及用户存档不变。
- 桌面输入回归 260 项通过；键盘及模拟手柄事件，不等同于实物手柄测试。
- 桌面引导及原有技能树呈现测试 1,348 项通过；检查固定底部引导与饭盒不重叠。采用显式状态夹具，非完整人工通关。
- 两轮触控报告内的游戏脚本、翻译和字体摘要与 RC3 构建副本一致；项目配置由隔离构建去除编辑器插件、设置 Web 渲染。测试场景不进入 ZIP。
- RC3 构建重新通过 50 MB 上限、文件后缀、888 个所需汉字覆盖及 123 张纹理尺寸/透明通道检查。

报告、日志与已查看的中英引导截图保存在 `build/toy-final-rc3/qa/`，其中 `touch-zh1/report.json` 与 `touch-en1/report.json` 记录运行前后源码摘要。浏览器线上检查和上传证据也存放于该目录。触控测试是引擎事件注入，尚不能证明物理手机、浏览器触摸转换、人体工学或手机性能通过。

RC3 的 Toy 上传已通过，独立线上预览完成引擎启动、标题与设置开关检查。标题保留用户现有的第 5 顿饭、大肥鱼 V3、20 token；未重置存档或修改设置。控制台仅捕获 B 站 reporter 的 spmId 告警，未捕获游戏错误。`qa/release-evidence.json` 绑定上传包与运行截图摘要；正式发布未点击。本轮没有重新测量音频输出，RC2 修复保留。

## RC2 音频修复与封面

RC1 触发了 Godot Web Sample 音频总线动态追加缺陷：[godotengine/godot#119026](https://github.com/godotengine/godot/issues/119026)。4.7.2 导出模板的 `Bus.addAt(-1)` 会错误移动总线，导致 Master 的输出连接丢失。Settings 和 Audio 改为增加 `AudioServer.bus_count` 后命名总线，保留原有名称、路由与音量。两次构建的游戏源文件摘要仅这两个脚本不同；音频素材没有被删除或重新压缩。

在同一 Chrome、同一存档和音量下做了浏览器输出对照：两者均通过真实游戏点击让 AudioContext 进入 running；RC1 的输出采样峰值始终为 0，RC2 持续输出非零信号，记录的最大峰值为 0.224151、38 次非零采样。测量的是进入浏览器音频输出节点的 PCM，不代表对物理扬声器的听觉验收。首次进入后仍需点击游戏画面或游戏按钮，才能满足浏览器音频手势要求。

测量工具 `pipeline/prepare_web_audio_probe.py` 为导出物创建独立副本，提前挂载 `web_audio_probe.js`，只在已有输出节点旁挂分析器，不主动播放、恢复或解除静音；发行 ZIP 不包含该工具。源文件和探针摘要保存在 `build/qa/web-audio-before-source.json`、`web-audio-after-source.json`。原始结果及截图为 `build/qa/web-audio-before-result.json`、`web-audio-before.jpg` 和 `build/toy-final-rc2/qa/web-audio-after-result.json`、`web-audio-after.jpg`。

RC2 另运行隔离副本中的 `audio_mix_test.tscn`：23 项通过、0 失败；headless 环境下的听觉混音项明确跳过，Web 实际输出由上述浏览器对照覆盖。日志：`build/toy-final-rc2/qa/audio-mix.log`。构建体积、字体覆盖和纹理检查重新通过；下方其他玩法回归属于 RC1，未声称全部重跑。

封面角色已按用户要求换为双手端空盆、面无表情的版本，保留标题与饭堂构图，已上传到 Toy 草稿。源图为 `art_src/store/toy_cover_zh.png`。

RC2 已通过 Toy 上传校验，线上预览启动及设置入口可用，并保留用户后续试玩得到的第 3 顿、20 token。该预览没有附加测量探针，音频输出数值来自相同 RC2 导出文件的本地浏览器副本；没有宣称录制或听取线上扬声器输出。线上截图、日志与绑定包摘要的证据汇总在 `build/toy-final-rc2/qa/`。正式发布按钮未点击。

## RC1 验证结果（仍适用的回归基线）

| 项目 | 结果与边界 |
| --- | --- |
| 打包检查 | `py -3 pipeline/test_build_toy.py`，4 项通过；最终构建的 50 MB、后缀和字体覆盖检查通过 |
| JS 平台桥接 | `node --test pipeline/tests/test_toy_bridge.js`，15 项通过；使用 SDK 模拟对象，覆盖限额、损坏、超时、分片写失败、冲突和恢复确认 |
| Godot 云存档边界 | `toy_save_test.tscn` 通过；覆盖有效恢复、本地备份、损坏/未来版本拒绝与测试存档隔离 |
| 存档回归 | `release_state_test.tscn`，41 项通过 |
| 触控 | 中英两轮各 44 项通过，960×540 GPU 运行；注入真实 Godot ScreenTouch/Drag 事件，未使用物理手机 |
| 桌面输入 | `input_access_test.tscn`，260 项通过；键盘及模拟手柄事件，不等同于实物手柄测试 |
| 结局与保存入口 | `ending_flow_test.tscn` 通过；状态夹具和真实 GUI 事件，非人工全流程通关 |
| 最终 ZIP 的 Chrome 运行 | 正常启动、作者文字完整、拿饭盒、接菜、送饭获 6 token、暂停、设置、恢复游戏、正常倒计时结束结账及返回技能树均实测 |
| 作者链接 | 标题点击后打开 `https://space.bilibili.com/2501012`，账号名“夸夸家族族长”正确 |
| 本地 SDK 降级 | 云读取超时后仍可游戏，明确提示进度保存在本机；未将此当成 Toy 云同步通过 |
| 浏览器本地持久化 | 完成第一顿后刷新，标题正确恢复“第 2 顿饭 · 大肥鱼 V3 · 6 token”，继续入口可用 |

自动化报告：`build/qa/toy-touch-final-zh/report.json`、`toy-touch-final-en/report.json`、`toy-touch-desktop-regression02/report.json`、`toy-ending-final/report.json`。这些报告记录各自源码摘要；触控报告先于最终字体补全，最终字体和浏览器路径由 RC1 构建及浏览器复查覆盖。

浏览器截图位于 `build/toy-final-rc1/qa/`：`browser-delivery.jpg`、`browser-settings.jpg`、`browser-settlement.jpg`、`browser-tree.jpg`、`browser-reload-persistence.jpg`、`toy-uploaded-unpublished.jpg`。浏览器视口覆盖请求未可靠改变实际页面尺寸（本地 2125×841，线上本轮 2656×995），因此不计为窄屏浏览器验收；960×540 结果来自 Godot 触控测试。`browser-console.json` 保存最终包的启动日志，实测期间未捕获到错误或警告；没有进行实际音频输出录制或听觉验收。

## Toy 预览及发布资料

- 当前 RC4 发布表单预览：https://www.bilibili.com/toy/preview/preview_pqnld0Bu/index.html

- RC3 历史预览：https://www.bilibili.com/toy/preview/preview_o7QvaLNs/index.html
- RC2 历史预览：https://www.bilibili.com/toy/preview/preview_uquvmFbj/index.html
- RC1 完整流程验收先在 `preview_2GHUBKQX` 完成；同一 ZIP 重新上传后生成 `preview_5fQDiQbe`，刷新了旧 DNS 错误的内嵌预览。RC1 两次 ZIP 的 SHA-256 相同，后者另行确认启动并保留第 2 顿、8 token。RC1 发布表单截图为其 QA 目录中的 `toy-ready-unpublished.jpg`，独立预览截图为 `toy-final-preview.jpg`。
- 名称：吃白饭的大肥鱼。
- 拟用页面地址：`fatfish-free-lunch`；尚未发布，不承诺已占用此地址。
- 分类：游戏。
- 封面：`art_src/store/toy_cover_zh.png`，4:3，由 imagegen 编辑为端盆、面无表情的角色；与原图不是逐像素相同。
- 图标：`game/assets/ui/icon.png`。
- 本次接续时表单已选中“所有人可见”、深色主题，未参加活动，未启用访客水印；更新包时没有修改这些选项。正式发布仍须等待用户决定。

Toy 上传校验已通过并生成上述预览。此前 `www.bilibilitoy.com` 无法解析的问题已修复：OpenClash 的加密 DNS 上游使用 `#proxy`，但没有对应代理组或网卡，内核返回 `no such device`。备份后将 DNS 引用改为现有代理组并热加载；路由器、Windows DNS 与 Chrome 实际加载均恢复。没有重启路由器，代理节点选择保持不变。修复记录在本地 `build/toy-final-rc1/qa/network-repair.json`，凭据及路由器配置不进入仓库。

真实 Toy 预览中已确认标题、美术、作者文字、开始游戏、引导拿盘、接菜、送饭计分（8 token）、暂停与设置、倒计时自然结束结账及返回技能树可用。刷新后恢复第 2 顿、8 token，作者链接实际打开正确的 B 站空间。云读取失败时明确提示保存在本机，未阻止游戏。证据为 `toy-online-title.jpg`、`toy-online-delivery.jpg`、`toy-online-settings.jpg`、`toy-online-settlement.jpg`、`toy-online-tree.jpg`、`toy-online-reload.jpg`；日志为 `toy-online-console.json`，其中仅捕获翻译扩展及 B 站 reporter 的无关告警，未捕获游戏运行错误。

云存档仍为未验证：预览页面的内联脚本没有注入正式 Toy ID；检查官方公开的 [toy-host.js](https://s1.hdslb.com/bfs/seed/toy/app/sdk/toy-host.js) 后确认其存储分支先校验该 ID，无有效 ID 会报 `toy id not available on host`。这与当前失败相符，但本轮未捕获 SDK 的具体错误对象，不能据此宣称正式发布后的云同步已通过。官方 [toy-sdk.js](https://s1.hdslb.com/bfs/seed/toy/app/sdk/toy-sdk.js) 的云存储参数与当前接入一致。两份公开脚本的检查副本保存在本地 QA 目录。

物理手机/B 站 App 的横屏、安全区、触控、音频和保存到相册尚未实测。上述限制不以桌面运行或模拟测试代替。

正式发布或提交审核必须等待用户决定。本轮未点击“发布”。
