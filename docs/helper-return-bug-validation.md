# 一级补漏助手送餐后停滞修复（2026-10-21）

用户反馈：仅一级小助手、补漏模式，送完第一盒后不再工作，移动鼠标后偶尔恢复。

## 原因与修改

`_plan_crew()` 只把 1.6 秒内能赶到的落菜当作即时目标。助手刚从最右侧餐桌送完餐时离窗口很远，一级速度无法赶到。待命评分又允许留在当前位置，只附加 500 的固定成本；回到远处有用窗口的步行成本可能更高，于是一直原地待命。玩家鼠标改变保留接菜列时，候选位置会变化，可能偶然解除停滞。

现改为：先选择当前分工可接、有食物供应且未被玩家或其他助手占用的窗口位置；只有没有此类位置时，才选接菜区内部的安全待命位置。送餐、速度、技能等级、盒子预算和玩家接菜优先权保持原规则。

## 对照复现

新场景 `game/tests/helper_return_test.tscn`：只有 `start=1, hire=1`，基础速度、正常窗口出菜。通过 Godot Viewport 派发鼠标移动和左键事件拿起玩家饭盒，停在 `(1300,650)` 后不再移动；此后屏蔽意外桌面输入。以 1/120 秒小步长推进生产 `_process`，没有塞入食物、饭盒、助手位置，也没有自动玩家或技能强化。固定种子 `2026102101`，观察 45 秒世界时间；不是 FPS 或人类手感测试。

| 版本 | 实际接菜 | 实际送餐 | 第一盒后继续接菜 | 结果 |
|---|---:|---:|---:|---|
| 修改前 | 3 | 1 | 0 | 约 9.108 秒送完第一盒后停滞 |
| 修改后 | 13 | 4 | 10 | 送餐发生在约 9.108、22.458、31.233、43.625 秒 |
| 修改后 GPU 实际画面 | 13 | 4 | 10 | 与逻辑场景一致，保存送餐、返回接菜、最终帧 |

GPU：Godot 4.7.2、Windows、OpenGL Compatibility、RTX 4070 SUPER，1280×720 视口。已查看 `returned_to_catching.png` 和 `final.png`。

## 回归及证据

- 助手策略 **142 项通过**，新增送餐后重新领盒、远窗返回、鼠标不动、无窗口回退及玩家列避让。
- 六名助手完整 105 秒普通出菜回归通过：补漏 23 次、配餐 23 次、营养 20 次实际送餐，每位均有配送，预留饭盒最多 6 且不超预算。
- 修复了旧策略测试夹具缺少真实 `FishMealVisual` 实例的问题。该组件已经是生产吃饭流程的依赖；旧夹具会在结算测试中访问空对象。只补齐测试组件，没有改生产结算。
- 原生玩家 `save.json`、备份及 `settings.cfg` 前后 SHA256 一致。运行在去除 MCP 插件的隔离项目和 `FatFishHelperReturnQA` 用户目录中。
- 新场景纳入 `pipeline/validate_release.py` 的 `helper-return` 回归入口。

本机证据：

- `build/qa/helper-return-before-runtime/report.json`：修改前生产代码真实失败。
- `build/qa/helper-return-after-runtime/report.json`：修复后的同种子、同输入场景。
- `build/qa/helper-return-gpu/report.json` 及截图：真实渲染，固定小步长模拟。
- `build/qa/helper-return-six-helper/report.json`：六人协作回归。
- `build/qa/helper-return-after.log`：142 项策略检查。
- `build/qa/helper-return-verification.json`：被测生产/测试源码摘要、前后对照及玩家文件保护结果。

修改前和修改后使用不同暂存目录，未改写失败日志或旧报告。本轮没有更新 Toy 线上版本。

## 本地修复候选

`build/toy-final-rc8/FatFish-0.4.2-toy-compressed.zip`，48,085,234 字节，SHA256 `23e8cdde14052b87ac6b2af6113a45ebe327fb07f531bd7e9e962d0bb13db792`。包含本次助手修复及先前本地加载器异常处理修复；不包含尚未实现的手机全屏布局调整。

构建、字体与纹理检查通过，最终导出的 JS 加载器及桥接/外壳 31 项故障与正常路径检查通过。实际 GPU 场景最终封存前后，对整个工作区 game/ 和隔离项目（排除缓存、插件）的源集合分别计算摘要，均一致；生产助手代码与打包源摘要一致，玩家文件未改变。

最终封存目录为 `build/toy-final-rc8/qa/helper-return/`，其中 `source-receipt.json` 绑定完整前后源摘要、实际画面报告和 ZIP 摘要。最终 GPU 报告为 `helper-return-final-gpu/report.json`。候选尚未上传或更新线上。

后续：用户随后授权正式更新。相同游戏源的 RC9 增加构建时资源 URL 指纹后，已于 2026-10-21 审核通过并上线，同时完成 Windows x64 打包与实际运行。最终交付及线上核对见 [Toy 与 Windows 发布记录](toy-windows-2026-10-21-release.md)。
