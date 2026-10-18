# 鸣谢与素材来源

《吃白饭的大肥鱼》是免费、开源、非商用的粉丝作品，与 DeepSeek 官方无关。

- **代码**：本项目自己写的代码使用 MIT 许可（另有说明的除外）
- **美术、音频等素材**：因为上游角色和素材都是非商用授权，本项目的素材统一按 **CC BY-NC-SA 4.0** 发布，不得用于商业用途

## 角色
| 内容 | 作者 | 授权 |
|---|---|---|
| 原型角色「溟月」 | 上善无形（B 站 space.bilibili.com/4456176） | CC BY-NC-SA 4.0 |
| 女仆版「蓝色大肥鱼」 | ZipZipPipe（B 站 space.bilibili.com/4168597） | CC BY-NC-SA 4.0 |

## 第三方素材（0.3 起已不随游戏发布）
2026-10-16 起大肥鱼改用自己生成的高清立绘 + 网格变形动画（`pipeline/gen_rig.sh`、`pipeline/prep_rig.py`、`game/scripts/ui/fish_rig.gd`），下面三个仓库的动画已从游戏里移除，文件留在 `art_src/legacy/game_fatfish/` 备查。曾经用过的版本和授权如下：
放进游戏时，在这里写清用了哪些动画、做了哪些修改（裁切、缩放、重新打包都算修改）。

| 项目 | 版本 | 作者 | 素材授权（以原仓库为准） | 署名要求 |
|---|---|---|---|---|
| [PC2005-cloud/dsh-pet](https://github.com/PC2005-cloud/dsh-pet) | `7f507e2`（2026-10-14） | PC2005-cloud | 代码 MIT；动画、提示词、源视频允许开源使用，**禁止商用** | 在介绍、展示、分发衍生作品的任何地方附原作者 GitHub 地址 |
| [tndmgzo7/blue-fat-fish-desktop-pet](https://github.com/tndmgzo7/blue-fat-fish-desktop-pet) | `b909bd7`（2026-10-04） | tndmgzo7 | 美术见 `LICENSE-ART`：**CC BY-NC-SA 4.0** | 署名、附授权链接、注明修改 |
| [YunYueSama/codex-deepseek-pet](https://github.com/YunYueSama/codex-deepseek-pet) | `7661c8b`（2026-09-23） | YunYueSama | 大肥鱼项目署名许可 1.0（见 `ASSET_LICENSE.md`）；社区参考图不在授权范围内，不使用 | 注明作者和仓库地址，保留完整许可，注明修改 |

## 字体
- Noto Sans SC，SIL Open Font License（`game/assets/ui/OFL.txt`）
- 站酷快乐体（ZCOOL KuaiLe），SIL Open Font License（`game/assets/ui/OFL_ZCOOLKuaiLe.txt`）

## 生成素材
- 大肥鱼立绘：65535（gpt-image-2）按社区参考图生成，属于上述角色的二创，CC BY-NC-SA 4.0。参考图只用于生成，不随游戏分发
- 大肥鱼游戏内形象（0.3 起）：65535（gpt-image-2.5，透明背景）生成主体立绘 `art_src/rig/master_c_0.png`，手部和 9 种表情分别重画后对齐拼回（`pipeline/prep_rig.py`），CC BY-NC-SA 4.0
- 食堂场景、梁阿姨（原创角色）、食物、饭盒、触手、汤勺：65535（gpt-image-2.5，透明背景）生成，再人工挑选、裁切、拼接（4×4 饭盒由 4×3 图拼出），CC BY-NC-SA 4.0
- 音效、音乐（4 首 BGM 做了首尾交叉淡化以无缝循环）、环境音、配音：ElevenLabs（Creator 套餐，允许商用）生成，配音为原创设计的声音，不克隆任何真人
- 上架 Steam 时要在内容问卷里披露以上 AI 生成内容（见 `docs/steam_release.md`）；游戏内鸣谢页也写了
- 坐姿大肥鱼（上班画面）和铁盆：65535（gpt-image-2.5）按主体立绘生成，CC BY-NC-SA 4.0
- 外包小助手（问问、谱谱、小G、克劳、双子、格格）：原创 Q 版角色，65535（gpt-image-2.5）只按我们自己的大肥鱼主体图定画风生成，只借用各家 AI 的配色印象，不含任何商标、logo；昵称是粉丝向的称呼，与各公司无关
