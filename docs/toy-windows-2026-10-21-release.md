# Toy 更新及 Windows 版（2026-10-21）

用户授权：“更新Toy，顺便打包个windows版本”。本轮按此授权更新已有 Toy，不创建另一个作品。

## 交付范围

包含一级补漏助手送餐后停滞修复、Web 下载/初始化错误传递、加载停滞重试入口和避免提前显示云读取提示。手机全屏留白调整尚未实现，不包含在本轮包中。

## Toy

- 入口：https://www.bilibili.com/toy/fatfish-free-lunch/index.html
- Toy ID：`46363714781184`，保持名称、slug、封面、图标、分类、深色主题和公开状态。
- 已于北京时间 **2026-10-21 17:34** 通过现有作品的“更新”表单提交；**17:39 复核已通过审核并上线**，公开发布记录更新时间显示 17:37，“审核中”标记消失，更新/管理按钮恢复。
- 最终 ZIP：`build/toy-final-rc9/FatFish-0.4.2-toy-compressed.zip`，48,085,426 字节，SHA256 `ed0bd7a634bceba2cf73fb383093e4f2da45d70d89fb96851b42a7f4301a23ce`。
- 最终预览：https://www.bilibili.com/toy/preview/preview_nBFfvf9f/index.html 。先前 RC8 上传预览未发布，最终提交的是 RC9。
- RC9 与已验证 RC8 的原始游戏源集合摘要一致，仅增加构建时的资源 URL 指纹：引擎 `index-d74647eb333c`、游戏数据 `index-5c5853a0be8d.data`、桥接 `toy_bridge-00d77429a14c.js`。静态资源原先返回一年 immutable 缓存，指纹文件名使新旧版本资源 URL 不重用；后续只改游戏数据时可以继续复用相同引擎 URL。
- 6 项构建打包检查、31 项桥接/加载器/外壳检查通过，完整构建、字体与纹理检查通过。最终指纹资源在 Chrome 本地真实加载并进入标题画面，音频 worklet 请求均返回 200。
- `build/toy-final-rc9/qa/toy-update-submitted.jpg` 保存提交回执；`local-title.jpg` 保存最终 Web 包本地启动画面；`cross-platform-receipt.json` 绑定两端源及产物摘要。
- `toy-update-approved.jpg` 保存审核通过后的公开记录。正式入口读取的引擎前缀、数据文件名、文件尺寸、桥接及加载器引用全部与 RC9 一致；实际下载的线上 JS 经 HTTP gzip 解码后 SHA256 与最终包完全一致，结果在 `published-config-verification.json` 和 `published-script-decoded-verification.json`。原始压缩传输体的直接摘要比较不能代表代码不一致，相应初步诊断仍保留。
- 正式页实际加载完成，点击“进入饭堂”后显示标题和既有进度；未开始新一局或重置进度。`toy-live-updated.jpg` 保存正式运行画面，`toy-live-console.json` 仅有 B 站 reporter 的 spmId 警告，无启动错误。

## Windows x64

- ZIP：`build/candidate-0.4.2-20261021T092608Z/FatFish-0.4.2-windows.zip`，142,050,731 字节，SHA256 `b97121a1207de6dcb558f98842947193b539d27e525e63b33dd1f78ddfb35616`。
- 解压后运行 `FatFish.exe`；原始美术使用桌面无损导入，单文件内嵌 PCK，另附 README、鸣谢和许可证。
- EXE：216,945,664 字节，SHA256 `685a1a4500eacb5bc89269af11d0750ad84cee2e9b5c8e2747fd54521387b747`。文件与产品版本均为 `0.4.2.0`，构建时从游戏版本同步，不再沿用导出预设的旧版本。
- 打包副本排除编辑器 MCP 插件、测试和调试工具；工作区编辑器配置保留。
- Windows 与 Toy 比较 933 个原始游戏源文件，除各平台项目/导出配置外一致。
- 实际运行打包 EXE：Godot 4.7.2、Vulkan Forward+、RTX 4070 SUPER、1280×720。隔离存档自动完成一顿饭、进入技能树并正常退出，退出码 0，未出现脚本/引擎错误。标题、设置、图鉴、暂停、游戏、结算和技能树截图均生成，已查看标题及游戏画面。
- 本轮验证复用已完成的 142 项助手策略、45 秒一级助手静止鼠标对照、六人 105 秒协作回归；没有声称重新运行全部历史发行测试，也不作为硬件性能或人类手感认证。
- `smoke-report-20261021T092803Z.json` 绑定打包源码、EXE 与验证源集合；原生玩家存档、备份及设置在运行前后完全相同。

## 尚未处理

手机画布安全区/超宽屏留白，以及软路由针对 Toy 域名的 DNS 策略，未在本轮改动。
