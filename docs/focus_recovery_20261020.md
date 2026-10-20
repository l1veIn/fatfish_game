# 失焦后无法继续 · 2026-10-20

## 原因和修复

收到 `NOTIFICATION_APPLICATION_FOCUS_OUT` 后，`CanteenRun` 原先立即创建并添加暂停菜单。整棵场景树正在传播通知时，子节点列表被锁定，`add_child()` 会失败；随后执行的 `SceneTree.paused = true` 却仍然生效。玩家看到的是停住的游戏，没有可操作的恢复按钮。

玩家日志存在 `Parent node is busy setting up children, add_child() failed`。将原先单独调用 `_notification()` 的测试改为 `get_tree().root.propagate_notification(...)` 后，在修改生产代码前复现了相同错误，回溯指向 `CanteenRun.pause()`。

现在只在通知回调中排队一次暂停请求，通知传播结束后再创建菜单。菜单成功进入场景树后才暂停游戏；退出中的场景不再接受暂停请求。失焦后仍需玩家按 Esc 或选择“继续上班”恢复。

## 验收记录

- 旧版失败证据：`build/verification-20261020T062224Z/focus.log`。
- 最终 GPU 回归：`build/verification-20261020T063054Z/report.json`，报告 SHA-256 为 `ccbc7fdaa119715b2b7ee42b234d189f3926e9f72592f4a1f68c8c1ad1135777`。源码冻结前后相同，玩家存档、备份和设置未变。
- `focus-zh_CN`：真实树通知传播、同帧重复通知、24 次快速失焦/回焦、键盘恢复、暂停子菜单、关闭失焦暂停选项、暂停中退出、延迟暂停执行前退出，均通过。
- Windows 原生窗口操作：切到另一窗口再回来，Esc 恢复；最小化再还原，Enter 恢复。两次均记录暂停菜单有效且游戏计时重新推进。
- 第三次原生切换只完成失焦与暂停；Computer Use 因无法确认目标浏览器 URL 而停止，未声称第三次恢复通过。随后结束本轮专用测试进程。此限制不影响引擎内回归结果。

原生测试用隔离的 `qa_native_focus` 档案与一小时饭局夹具，仅用于恢复验证。脚本 `build/native_focus_probe.gd` SHA-256 为 `f25cb28015679002cc7b187e44b46f863840bfaf3ebd88fa08e4fbb46912a8fc`；日志 `build/native-focus-20261020.log` SHA-256 为 `c7684cd463a05303bd6e9daa49251ad13c3fb705f956b1d1e0a46338817109b1`。未直接操作截图软件，也不声称排除了所有驱动、系统或第三方覆盖层问题。
