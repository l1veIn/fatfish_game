# Toy 0.4.2 发布候选验收

更新：2026-10-21（北京时间）。状态：**候选包已上传，Toy 线上预览可运行；未发布、未提交审核，等待用户决定。真实云同步与物理手机仍未验收。**

## 候选与复现

- 实现提交：`28b4ed1f4e63f69d1cc0e2c1bcbe7b425480ae7b`，分支 `codex/toy-release`，已推送远端。
- 前置作者链接修改：`f99bf7e`，已推送 `main`。
- ZIP：`build/toy-final-rc1/FatFish-0.4.2-toy-compressed.zip`。
- ZIP 字节数：47,995,706（48.00 MB，十进制）；当前 Toy 账号上限 50 MB。
- SHA-256：`542f77efff9e89d1e99b58379d355550dceecebad8f92936c12ea723b4cddafc`。
- 完整构建、输入和输出摘要：`build/toy-final-rc1/build-manifest.json`。
- 复现：`py -3 pipeline/build_toy.py --output build/toy-release-rebuild --max-zip-mb 50`。
- Web 本地预览：从 `build` 目录启动 HTTP 服务，访问 `/toy-final-rc1/web/index.html`。请勿直接用 `file://` 打开。

Godot 4.7.2 Compatibility、WebGL 2、单线程，不要求跨源隔离。资源路径相对入口，主资源包改用 Toy 允许的 `.data` 扩展名；代码许可、素材署名和字体许可随包保留。编辑器插件、测试和调试工具不进入发行包。

原有 `game/project.godot` 的 Godot MCP 编辑器配置及未跟踪的 `game/addons/` 属于既有本地改动，未纳入这次提交。

## 体积与画质

无损基线 ZIP 114,523,671 字节，当前候选减少约 58.09%。两者包含不同阶段的桥接和字体修改，此数字是版本总体对比，不是完全隔离的压缩 A/B 实验。

压缩仅修改构建副本的纹理导入配置，游戏原始 PNG 未被重绘或覆盖。123 张压缩纹理通过尺寸和透明通道逐像素检查，透明通道完全一致；最低可见 RGB PSNR 为 30.287 dB。小型食物、功能 UI、字体图集及两个敏感精灵保留无损。中英招牌、人物、徽章及标题的对照图已查看，未见影响识别的缺陷。

证据：`build/toy-final-rc1/qa/texture-quality.json`、`texture-comparison.jpg`。

压缩减少下载体积，不减少解码后的纹理内存。没有据此宣称手机帧率、内存或低端设备表现合格。

## 验证结果

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

- 当前发布表单的预览：https://www.bilibili.com/toy/preview/preview_5fQDiQbe/index.html
- 完整流程验收先在 `preview_2GHUBKQX` 完成；同一 ZIP 重新上传后刷新了旧 DNS 错误的内嵌预览，生成当前链接。两次候选 ZIP 的 SHA-256 相同，当前链接另行确认启动并保留第 2 顿、8 token。最终发布表单截图为 `toy-ready-unpublished.jpg`，独立预览截图为 `toy-final-preview.jpg`。
- 名称：吃白饭的大肥鱼。
- 拟用页面地址：`fatfish-free-lunch`；尚未发布，不承诺已占用此地址。
- 分类：游戏。
- 封面：`art_src/store/toy_cover_zh.png`，4:3，基于原有宣传图由 imagegen 扩展构图；与原图不是逐像素相同。
- 图标：`game/assets/ui/icon.png`。
- 当前表单为“链接访问”、深色主题，未参加活动，未启用访客水印。

Toy 上传校验已通过并生成上述预览。此前 `www.bilibilitoy.com` 无法解析的问题已修复：OpenClash 的加密 DNS 上游使用 `#proxy`，但没有对应代理组或网卡，内核返回 `no such device`。备份后将 DNS 引用改为现有代理组并热加载；路由器、Windows DNS 与 Chrome 实际加载均恢复。没有重启路由器，代理节点选择保持不变。修复记录在本地 `build/toy-final-rc1/qa/network-repair.json`，凭据及路由器配置不进入仓库。

真实 Toy 预览中已确认标题、美术、作者文字、开始游戏、引导拿盘、接菜、送饭计分（8 token）、暂停与设置、倒计时自然结束结账及返回技能树可用。刷新后恢复第 2 顿、8 token，作者链接实际打开正确的 B 站空间。云读取失败时明确提示保存在本机，未阻止游戏。证据为 `toy-online-title.jpg`、`toy-online-delivery.jpg`、`toy-online-settings.jpg`、`toy-online-settlement.jpg`、`toy-online-tree.jpg`、`toy-online-reload.jpg`；日志为 `toy-online-console.json`，其中仅捕获翻译扩展及 B 站 reporter 的无关告警，未捕获游戏运行错误。

云存档仍为未验证：预览页面的内联脚本没有注入正式 Toy ID；检查官方公开的 [toy-host.js](https://s1.hdslb.com/bfs/seed/toy/app/sdk/toy-host.js) 后确认其存储分支先校验该 ID，无有效 ID 会报 `toy id not available on host`。这与当前失败相符，但本轮未捕获 SDK 的具体错误对象，不能据此宣称正式发布后的云同步已通过。官方 [toy-sdk.js](https://s1.hdslb.com/bfs/seed/toy/app/sdk/toy-sdk.js) 的云存储参数与当前接入一致。两份公开脚本的检查副本保存在本地 QA 目录。

物理手机/B 站 App 的横屏、安全区、触控、音频和保存到相册尚未实测。上述限制不以桌面运行或模拟测试代替。

正式发布或提交审核必须等待用户决定。本轮未点击“发布”。
