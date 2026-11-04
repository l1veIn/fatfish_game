# Toy 技能树与配方显示更新（2026-11-04）

状态：代码已提交并推送；Toy 更新于北京时间约 **18:49** 提交，发布记录显示 **18:50** 更新并恢复管理按钮，审核已通过。正式入口引用的新内容包与候选一致。更新动态已于 **19:10** 发布并打开详情核对。

## 本轮内容

- 技能树保留暖色软木板、红绳和饭票美术；关键解锁增加金色饭票与星标，版本门票另作标记，选中技能时突出直接前置与后续连线。
- 每张已揭晓的技能票增加一句效果说明；标题、短效果、等级和进度使用统一安全区，票根留给标记与印章。中英长标题按实际字号换行、省略，选中扩大纸面时文字位置保持稳定；未揭晓便签不显示名称或效果。
- 首次学习「AGI 菜谱」后，图鉴公开全部 20 道套餐的完整配方，包含 3 道隐藏配方及嵌套子套餐。配方公开与实际制作分别保存；制作次数、收藏成就及隐藏助手订单仍按真实发现判断。已公开配方在退款、重启后保留，兼容既有存档。

## 源码与产物

- 源码提交：`a2409d815fb477cdbbe6ebf237d2ce213e041af7`，已推送 `origin/codex/toy-release`。
- 构建来自干净的已提交 worktree；验证了 937 个原始源文件，源文件、Web 输出及 ZIP 成员均与构建清单一致。
- ZIP：`build/toy-tree-readability-20261104/FatFish-0.4.2-toy-compressed.zip`。
- 大小：**48,102,265 字节**，低于账号的 50,000,000 字节上限。
- SHA-256：`443701ce25b37c28f9cd33d44f415bfd10c91022f183d330235a139b0cbed97d`。
- 内容包：`index-8f6112b1248a.data`，继续使用内容指纹资源名以避免旧 CDN 缓存复用。
- 构建清单与产物核对：`build/toy-tree-readability-20261104/build-manifest.json`、`qa/release-build-verification.json`。

## 验证与范围

- 发布前定向回归：助手策略 **142 项、0 失败**；配方公开 **31 项、0 失败**；技能树、收藏及助手送餐后恢复回归通过。报告位于 `build/qa/toy-tree-publish-20261104/`。
- 超宽比例中文触控最终独立复跑 **113 项、0 失败**，报告为 `build/qa/toy-tree-publish-20261104/touch-wide-zh-final/report.json`。首轮与浏览器并发检查有 2 项失败，失败报告保留；独立复跑通过，尚不能确定焦点变化是唯一原因。
- 技能票安全区的中英文、不同尺寸和缩放检查及真实 GPU 截图保存在 `build/qa/tree-readability-padding/`；这些是显式状态和输入夹具，不是完整人工通关。
- 最终导出加载器故障注入 **8 项、0 失败**；901 个所需汉字无缺字。124 张压缩纹理的尺寸和透明通道保持一致，最低可见 RGB PSNR 为 30.287 dB。
- 首次构建的引导导入进程非零退出，构建守卫拒绝该轮；原过程未保留数字退出码，不推断具体值。随后隔离重试的导入、导出及纹理解码均退出 0，生产源码未修改。两轮记录保留在产物验证文件中。
- Toy 上传预览真实完成引擎启动、标题及技能树检查。原有进度为第 8 顿、V3、758 token；未购买技能、开始新一顿或修改设置。预览资源名与最终构建清单相符。
- 没有据本轮自动化或桌面预览宣称物理手机、正式云同步、扬声器输出或完整人类游玩验收通过。

## Toy 更新与动态

- 更新既有作品，Toy ID：`46363714781184`；沿用原名称、slug 和页面资料。
- 正式入口：[吃白饭的大肥鱼](https://www.bilibili.com/toy/fatfish-free-lunch/index.html)。正式页面的内容包为 `index-8f6112b1248a.data`，引擎 `index-d74647eb333c.js`、桥接 `toy_bridge-00d77429a14c.js`，均与候选清单对应。未选择本机/云端冲突存档，未覆盖云端进度。
- 本轮预览：[技能树与配方更新预览](https://www.bilibili.com/toy/preview/author_GWULHvUK/index.html)。
- 上传和运行证据：`build/toy-tree-readability-20261104/qa/uploaded-preview-verification.json`、`toy-preview-title.jpg`、`toy-preview-tree-confirmed.jpg`、`toy-update-submitted.jpg`、`toy-update-review-state.jpg`。
- 上线核对：`qa/toy-update-approved.jpg`、`qa/published-verification.json`。正式资源引用已核对；标题及技能树的真实运行检查来自同包上传预览。
- 更新动态：[《吃白饭的大肥鱼》更新啦](https://t.bilibili.com/1266810143092244504)，平台显示北京时间 **19:10**。内容包含三项技能树呈现更新、AGI 菜谱公开配方规则及原游戏入口。发布前平台要求确认《动态使用规范》，用户明确同意后点击“确认并发送”；已打开动态详情核对正文仅一份、入口正确。
- 动态证据：`qa/dynamic-draft.txt`、`qa/dynamic-rules-confirmation.jpg`、`qa/dynamic-published-confirmed.jpg`、`qa/dynamic-published.json`。

本轮未替换 Windows 发行包，也未改动本机编辑器插件和旧宣传片临时文件。
