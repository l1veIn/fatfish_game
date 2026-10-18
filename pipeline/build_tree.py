"""Builds game/data/skill_tree.json from the node list below (the tree of docs/tree_model.md,
second draft of the design page). Positions follow the design page: six branches round the
centre, `d` steps out, `l` lanes sideways (an angle, so a branch keeps to its slice).

    python pipeline/build_tree.py
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "data", "skill_tree.json")

BRANCH = {"stall": -90, "auntie": -30, "box": 30, "fish": 90, "crew": 150, "version": -150}
RINGS = ["V3", "R1", "V3.1", "V3.2", "V4"]
RING_COST = [60, 2500, 25000, 250000, 1500000]   # first level of a plain node, by ring
GROWTH = {"eat": 2.0, "mat": 30.0, "vram": 6.0}   # per-node price growth (default 2.2, stalls 2.5)
STEP, LANE_PX, R0 = 195.0, 160.0, 0.9   # a tight radial start; relax() then pushes tickets apart
TICKET = (235.0, 165.0)                  # room one ticket needs (with its pin and yarn)
PULL = 0.001

# id, branch, d, lane, name, desc, max, ring, parents, effects, flags
# effects: {stat: add} or {stat: ("mul", x)}; flags: key (opens a way to score, x2.5 price)
N = [
    ("stall_main", "stall", 1, -1, "预训练语料·主食", "主食窗口升级，出新菜：饭团、白粥 → 炒饭 → 金饭团。", 3, "V3", ["start"], {"stall_main": 1}, ""),
    ("stall_wok", "stall", 1, 1, "预训练语料·炒菜", "开炒菜窗口：青菜、番茄炒蛋 → 土豆丝、红烧肉 → 宫保鸡丁。", 3, "V3", ["start"], {"stall_wok": 1}, ""),
    ("stall_dim", "stall", 2, 1.5, "预训练语料·面点", "开面点窗口：包子、油条 → 豆浆、饺子 → 小笼包。", 3, "V3", ["stall_wok"], {"stall_dim": 1}, ""),
    ("stall_fry", "stall", 3, 1.5, "预训练语料·炸物", "开炸物窗口：鸡腿、薯条 → 冰可乐 → 炸鸡汉堡。", 3, "R1", ["stall_dim"], {"stall_fry": 1}, ""),
    ("stall_sweet", "stall", 4, 1.5, "多模态·甜品窗口", "开甜品窗口：布丁、奶茶 → 双皮奶 → 冰激凌。", 3, "V3.1", ["stall_fry"], {"stall_sweet": 1}, ""),
    ("menu", "stall", 2, 0, "System Prompt：今日菜单", "开饭前从菜单上划掉 1 道菜（在「今日菜单」里选），每级多划 1 道。被划掉的菜不再出，机会让给同窗口的其他菜。", 4, "V3", ["stall_wok"], {"menu_cut": 1}, ""),
    ("sft", "stall", 2, -1.5, "SFT 监督微调", "每道菜有几率是优质菜（×2，带银圈），每级 +8%。", 5, "V3", ["stall_main"], {"sft": 0.08}, ""),
    ("lora", "stall", 3, -0.5, "LoRA 微调", "菜单划得越短，剩下的菜越容易是优质菜：每划掉 1 道 +3%。", 1, "V3", ["menu", "sft"], {"lora": 0.03}, ""),
    ("dpo", "stall", 3, -1.5, "DPO 偏好优化", "优质菜有几率再升成金牌菜（×4，带金圈），每级 +20%。", 3, "R1", ["sft"], {"dpo": 0.2}, ""),
    ("fp32", "stall", 4, -1.5, "FP32 满精度", "金牌菜从 ×4 变成 ×5。", 1, "V3.2", ["dpo"], {"fp32": 1}, ""),
    ("moe", "stall", 2, -2.7, "MoE 激活专家", "开饭前多选 1 道招牌菜。", 3, "V3", ["stall_main"], {"sig_slots": 1}, ""),
    ("canteen_std", "stall", 2, 2.6, "食堂标配", "每个窗口出菜时，有几率顺手配一勺青菜，每级 +15%。", 3, "R1", ["stall_wok"], {"veg_std": 0.15}, ""),

    ("conc", "auntie", 1, 0, "并发请求", "梁阿姨多长一条触手，抛的菜更多（每个开着的窗口本来就有一条）。", 5, "V3", ["start"], {"tentacles": 1}, ""),
    ("lunch", "auntie", 1, -1.6, "中午吃什么", "每口有几率暴击 ×2：她先托腮想一下，再狠狠吃一大口。每级暴击率 +3%、暴击倍数 +0.1。", 5, "V3", ["start"], {"crit_chance": 0.03, "crit_mult": 0.1}, ""),
    ("api", "auntie", 2, -1, "API 价格打骨折", "阿姨抛菜更快，每级快 12%。", 5, "V3", ["conc"], {"throw_rate": ("mul", 1.12)}, ""),
    ("batch", "auntie", 3, -1.3, "Batch Size ×2", "阿姨手不抖了：每一勺有几率多抛 1 样，每级 +25%。", 3, "R1", ["api"], {"batch": 0.25}, ""),
    ("peak", "auntie", 2, -2.4, "推理高峰", "饭点里一阵一阵的高峰时段：出菜 ×2.5，稀有菜更常见。每级高峰多 3 秒。", 3, "R1", ["conc"], {"peaks": 1, "peak_time": 3}, ""),
    ("temp", "auntie", 2, 1, "Temperature 1.0", "菜进饭盒时，有几率变成同窗口、同类的高一级菜（青菜 → 土豆丝），已经最高级的就变成优质菜。变过的菜额外 ×1.5（带小火苗）。正在凑的套餐原料不会被变走。每级 +8%。", 5, "V3", ["conc"], {"temp": 0.08}, "key"),
    ("hot", "auntie", 3, 1, "高温采样", "被随机碰过的菜（变过的、幻觉出来的、暴击的）每级再 +0.25 倍。", 4, "R1", ["temp"], {"hot": 0.25}, ""),
    ("halluc", "auntie", 3, 2.1, "幻觉", "菜进饭盒时，有几率凭空多出一口同窗口的菜（不占格），每级 +8%。", 3, "R1", ["temp"], {"halluc": 0.08}, ""),
    ("regen", "auntie", 4, 0.6, "重新生成", "送上桌的饭盒有几率整盒重抽：每样散菜都换成高一级的菜。每级 +10%。", 2, "V4", ["hot"], {"regen": 0.1}, ""),
    ("emerge", "auntie", 4, 2.1, "涌现能力", "一盒里有 3 样被随机碰过的菜时，有几率凝成一份「涌现乱炖」（神级套餐）。", 1, "V4", ["halluc", "hodge"], {"emerge": 1}, ""),
    ("overfit", "auntie", 4, -0.4, "过拟合：看什么都像青菜", "顿悟以后，散菜进饭盒有 15% 几率变成青菜（算被随机碰过）。", 1, "V3.1", ["grok", "temp"], {"overfit": 1}, ""),

    ("vram", "box", 1, 0, "显存扩容", "饭盒 2×2 → 2×3 → 2×4，接菜范围一起变宽；每级还多一个饭盒。", 2, "V3", ["start"], {"box_n": 1, "basins": 1}, ""),
    ("ocr", "box", 1, -1.5, "光学压缩", "每盒饭 +20%（每级）。", 3, "V3", ["start"], {"box_bonus": 0.2}, ""),
    ("prompt", "box", 1, 1.5, "Prompt 模板", "小炒（2 样合成）更值钱：每级 +0.2 倍。", 5, "V3", ["stall_wok"], {"tier1": 1}, ""),
    ("mat", "box", 2, 0, "饭盒材质", "铁 → 铜 → 银 → 金：整顿收入 ×1.5 / ×2 / ×3。", 3, "V3", ["vram"], {"material": 1}, ""),
    ("fill", "box", 2, -1.5, "上下文填满", "送出的饭盒一格都不空：这盒 +25%。", 1, "R1", ["ocr"], {"fill_bonus": 0.25}, ""),
    ("fewshot", "box", 2, 1.5, "Few-shot 示例", "二级套餐（3 样）更值钱：每级 +0.3 倍（乱炖也算二级）。", 5, "V3", ["prompt"], {"tier2": 1}, ""),
    ("inject", "box", 2, 2.8, "提示词注入", "合成套餐时，盒里的一样青菜被偷偷藏进去：不占格，算一份素，套餐也多算一样原料。", 1, "R1", ["prompt"], {"inject": 1}, ""),
    ("compress", "box", 3, 0, "上下文压缩", "套餐合成后再少占 1 格（最少 1 格）。", 1, "R1", ["mat"], {"compress": 1}, ""),
    ("agentwf", "box", 3, 1.5, "Agent 工作流", "三级大餐（4–5 样）更值钱：每级 +0.4 倍。", 5, "R1", ["fewshot"], {"tier3": 1}, ""),
    ("fuse3", "box", 3, -1.5, "模型融合", "盒里 3 份一样的菜融成 1 份高一品级的（普通 → 优质 → 金牌）。", 1, "V3.1", ["sft", "fill"], {"fuse3": 1}, ""),
    ("hodge", "box", 3, 2.8, "MoE 大杂烩", "饭盒装满、又没有「差一样就能凑齐」的套餐时，3 样不同窗口的散菜压成一份「乱炖」（二级套餐）。", 1, "V3.1", ["temp", "fewshot"], {"hodge": 1}, ""),
    ("cot", "box", 4, 0, "思维链", "盒里每发生一次连锁合成（套餐当原料再合成），这一盒 +30%，最多 3 次。", 1, "V3.1", ["compress"], {"cot": 0.3}, ""),
    ("rag", "box", 4, -1.2, "RAG 检索增强", "套餐里每样优质或金牌原料，每级 +2 价值（再乘套餐等级）。", 3, "V3.1", ["dpo", "agentwf"], {"rag": 2}, ""),
    ("agirec", "box", 4, 1.5, "AGI 菜谱", "神级套餐更值钱：每级 +0.6 倍。", 5, "V3.2", ["agentwf"], {"tier4": 1}, ""),
    ("spec", "box", 5, 0.6, "投机解码", "每次合成有 20% 几率「猜下一样」：套餐差 1 样就直接补上，不然就变成一口零食。", 1, "V3.2", ["halluc", "cot"], {"spec": 0.2}, ""),

    ("eat", "fish", 1, 0, "猛炫", "她吃得更快，每级 +25%。", 12, "V3", ["start"], {"eat_rate": ("mul", 1.25)}, ""),
    ("stream", "fish", 2, -0.6, "流式输出", "越吃越香：这一顿吃过 40 口以后，每口越来越值钱（头顶有读数）。有上限，发布新版本会抬高。", 5, "V3", ["eat"], {"stream": 0.2}, "key"),
    ("ttft", "fish", 3, -1.1, "降低首 Token 延迟", "越吃越香开始得更早：第 40 口 → 30 口 → 20 口。", 2, "V3", ["stream"], {"ttft": 1}, ""),
    ("mtp", "fish", 3, 0, "MTP 多 Token 预测", "每吃一口，每级 +1 token。", 4, "V3", ["stream"], {"mtp": 1}, ""),
    ("busy", "fish", 1, 1.6, "服务器繁忙，请稍后再试", "她空着手等饭时越等越馋：下一盒饭跟着涨价（头顶有读数），等过一会儿就不怎么再涨了。每级更馋。", 5, "V3", ["start"], {"crave": 0.5}, "key"),
    ("queue", "fish", 2, 1.9, "排队中……", "馋得更快：同样等几秒，馋得更厉害。", 2, "R1", ["busy"], {"crave_tau": -1.25}, ""),
    ("multiturn", "fish", 3, 1.4, "多轮对话", "连续送出「至少 2 份二级以上套餐」的饭盒（盒边亮「连击✓」），每连一盒，之后的盒子更值钱。连击数有上限，发布新版本会抬高。", 4, "R1", ["busy", "fewshot"], {"combo": 0.05}, "key"),
    ("memory", "fish", 4, 0.9, "上下文记忆", "1 级：连击断了只掉一半；2 级：每顿第一次断不算。", 2, "V3.1", ["multiturn"], {"memory": 1}, ""),
    ("warm", "fish", 4, 2.1, "KV Cache 保温箱", "好吃的留到最后吃：桌子左边多一个保温箱。端着饭盒放进去，关门后她揭盖吃掉：×2，按馋到最高算。放进更好的一盒会把旧的换出来。", 1, "V3.1", ["multiturn"], {"warm": 1}, "key"),
    ("final", "fish", 5, 2.6, "Final Answer", "保温箱那一盒更值钱：×2 → ×3 → ×4 → ×5。", 3, "V3.1", ["warm"], {"final": 1}, ""),
    ("bon", "fish", 5, 1.5, "Best-of-N", "保温箱自动换成这一顿最值钱的那一盒。", 1, "V3.2", ["warm"], {"bon": 1}, ""),
    ("rlhf", "fish", 2, -1.9, "RLHF 人类偏好对齐", "吃得均衡时，整顿的加成上限更高（每级 +0.25）。", 4, "V3", ["eat"], {"balance_max": 0.25}, ""),
    ("constit", "fish", 3, -2.4, "宪法 AI·膳食宝塔", "均衡判定放宽：差一点也算吃得匀。", 1, "V3.2", ["rlhf"], {"constit": 1}, ""),
    ("grok", "fish", 4, -1.5, "顿悟（Grokking）", "她不再把青菜吐掉，而是皱着眉硬咽下去（一口不赚）。这一顿咽够 30 口后顿悟：「原来青菜这么好吃！」之后青菜每口都很值钱。", 1, "R1", ["stall_wok", "rlhf"], {"grok": 1}, "key"),
    ("warmup", "fish", 5, -2.2, "学习率预热", "顿悟得更快：要咽的青菜从 30 口降到 24 → 18 → 12 口。", 3, "R1", ["grok"], {"grok_need": -6}, ""),
    ("aftertaste", "fish", 5, -1, "回甘", "顿悟以后，每口青菜更值钱（每级 +2）。", 4, "V3.1", ["grok"], {"aftertaste": 2}, ""),
    ("drift", "fish", 6, -1.6, "向量漂移", "顿悟以后的青菜一半算素、一半算荤：吃得再多也不怕不均衡。", 1, "V3.2", ["aftertaste"], {"drift": 1}, ""),

    ("skills", "crew", 1, 0, "Skill：自动推送 / 自动回收", "手空了，她给你丢一个空饭盒；饭盒装满，自己飞回桌上。", 1, "V3", ["start"], {"auto_push": 1, "auto_return": 1}, ""),
    ("hire", "crew", 2, 0, "本地小模型：招募小助手", "每级招一个小助手：问问、谱谱、小G、克劳、双子、格格，每人一个特长。她们自己接菜、送饭盒。", 6, "V3", ["skills"], {"helper": 1}, ""),
    ("orch", "crew", 3, -0.6, "多 Agent 编排", "小助手跑得更快（每级 +30%）。", 2, "R1", ["hire"], {"helper_speed": 0.3}, ""),
    ("fc", "crew", 3, 0.8, "Function Calling：点单", "小助手优先去接这一顿最值钱的套餐要的原料。", 1, "R1", ["hire"], {"fc": 1}, ""),
    ("nutri", "crew", 4, -1.2, "营养师 Agent", "小助手优先接这一顿缺的那一类（主 / 荤 / 素）。", 1, "V3.1", ["orch"], {"nutri": 1}, ""),
    ("clip", "crew", 5, -1.2, "梯度裁剪", "这一顿最差的那 20% 饭盒，按平均算。", 1, "V3.1", ["nutri"], {"clip": 1}, ""),
    ("async", "crew", 4, 1.2, "异步调用", "小助手的饭盒喂她的时候，她的馋不会清零。", 1, "V3.2", ["hire", "busy"], {"async": 1}, ""),
    ("sleep", "crew", 4, 0, "我去睡了", "关门后桌上没吃完的饭盒，她在梦里吃掉一半的价值。", 1, "V3.2", ["orch"], {"sleep": 1}, ""),

    ("think", "version", 2, -0.4, "深度思考", "R1 的奖励：按住空格或右键，时间变慢，能看清每道菜落在哪。这里点一下，思考槽 +1 秒。", 1, "R1", ["ticket_r1"], {"think_time": 1}, "free"),
    ("diverge", "version", 3, -1.2, "发散思维", "思考时，饭盒能吸住大范围的菜（每级 +120 像素）。", 2, "R1", ["think"], {"diverge": 120}, ""),
    ("converge", "version", 3, -0.1, "收敛思维", "思考时，用不上的菜（包括青菜）直接穿过饭盒。和发散思维都点，就是「只吸需要的菜」。", 1, "R1", ["think"], {"converge": 1}, ""),
    ("critic", "version", 4, -0.6, "美食评鉴（刷榜）", "这一顿吃到的不同套餐，从第 5 种起，每多一种整顿 +4%。", 1, "V3.1", ["stall_dim"], {"critic": 0.04}, "key"),
    ("bench", "version", 5, -0.6, "Benchmark 全家桶", "每多一种套餐的加成，每级再 +2%。", 2, "V3.1", ["critic"], {"critic": 0.02}, ""),
]

TICKETS = [
    ("ticket_r1", 1, 0.9, "申请发布 R1", "spring", 300, 0, ["start"], "评测：一顿赚到 2,000 就发布 R1。"),
    ("ticket_v31", 2, 1.1, "申请发布 V3.1", "hybrid", 6000, 1, ["ticket_r1"], "评测：一顿赚到 2 万就发布 V3.1。"),
    ("ticket_v32", 3, 1.2, "申请发布 V3.2", "ji", 40000, 2, ["ticket_v31"], "评测：一顿赚到 6 万就发布 V3.2。V3.1-Terminus 终于不再到处冒「极」字了。"),
    ("ticket_v4", 4, 1.2, "申请发布 V4", "v4", 250000, 3, ["ticket_v32"], "评测：一顿赚到 40 万就发布 V4。"),
    ("ticket_agi", 5, 1.2, "实现 AGI", "agi", 1200000, 4, ["ticket_v4"], "终极评测：一顿 200 万。目标是实现 AGI！但是也要先吃饱。"),
]

# What each node says on the board: written for the player (what happens when I click it, what
# will I see), not for us. Overrides the short design notes in N above.
DESC = {
    "stall_main": "主食窗口（柜台正中间）升级，菜单多一道菜：饭团和白粥 → 炒饭 → 金饭团。",
    "stall_wok": "开张炒菜窗口：番茄炒蛋和青菜。再升级会出土豆丝、红烧肉，最后是宫保鸡丁。小心：她不爱吃青菜。",
    "stall_dim": "开张面点窗口：包子和油条。再升级会出豆浆、饺子，最后是小笼包。",
    "stall_fry": "开张炸物窗口：鸡腿和薯条。再升级会出冰可乐，最后是炸鸡汉堡。",
    "stall_sweet": "开张甜品窗口：布丁和奶茶。再升级会出双皮奶，最后是冰激凌。",
    "menu": "解锁「今日菜单」按钮：开饭前划掉不想要的菜，它就不会再出，同窗口的其他菜出得更多。每级多划 1 道。",
    "sft": "抛下来的菜有几率是「优质菜」：带银圈，价值 ×2。每级几率 +8%。",
    "lora": "今日菜单里每划掉 1 道菜，剩下的菜是优质菜的几率 +3%。",
    "dpo": "优质菜有几率直接升成「金牌菜」：带金圈，价值 ×4。每级几率 +20%。",
    "fp32": "金牌菜的价值从 ×4 提到 ×5。",
    "moe": "解锁「招牌菜」按钮：开饭前选一道招牌菜，这一顿它有特别加成（比如越吃越值钱）。每级多选一道。",
    "canteen_std": "每个窗口抛菜时，有几率顺手多给一勺青菜（每级 +15%）。青菜能凑套餐、补素菜，也是「顿悟」的训练材料。",
    "conc": "梁阿姨多长一条触手：多一把勺子在抛菜，菜更多。",
    "lunch": "每一口有几率暴击：这口 ×2，她会先托腮想一下再狠狠咬下去。每级暴击几率 +3%、倍数 +0.1。",
    "api": "梁阿姨出菜更快，每级快 12%。",
    "batch": "每一勺有几率多抛一样菜，每级几率 +25%。",
    "peak": "饭点里隔一会儿来一阵「高峰」：出菜 ×2.5，稀有菜更常见。每级高峰多 3 秒。",
    "temp": "菜掉进饭盒时，有几率变成同窗口更高级的菜（比如青菜 → 土豆丝），最高级的就变成优质菜。变过的菜带小火苗，价值再 ×1.5。你正在凑的套餐原料不会被变走。每级几率 +8%。",
    "hot": "带小火苗的菜（被变过的、幻觉出来的、暴击的那口）每级再值钱 +0.25 倍。",
    "halluc": "菜掉进饭盒时，有几率凭空多出一口同窗口的菜，不占格子（饭盒角上显示 +1）。每级几率 +8%。",
    "regen": "送上桌的饭盒有几率整盒「重抽」：盒里每样散菜都换成更高级的菜。每级几率 +10%。",
    "emerge": "一盒里凑够 3 样带小火苗的菜时，有 25% 几率合成「涌现乱炖」：神级套餐，非常值钱。",
    "overfit": "（要先「顿悟」）掉进饭盒的散菜有 15% 几率变成青菜。开窍后的她最爱青菜。",
    "vram": "饭盒变宽一列（2×2 → 2×3 → 2×4），接菜范围也变宽；每级还多给你一个饭盒。",
    "ocr": "每一盒饭的收入 +20%（每级）。",
    "prompt": "「小炒」（2 样菜合成的套餐）更值钱，每级 +0.2 倍。",
    "mat": "换更好的饭盒：铁 → 铜 → 银 → 金，整顿收入 ×1.5 / ×2 / ×3。",
    "fill": "送出的饭盒一格都没空着，这盒收入 +25%。",
    "fewshot": "「二级套餐」（3 样菜合成）更值钱，每级 +0.3 倍。乱炖也算二级套餐。",
    "inject": "合成套餐时，盒里的一棵青菜会被偷偷藏进套餐：不占格子，她吃不出来，还算吃了一份素。",
    "compress": "合成出来的套餐少占 1 格（最少 1 格），一盒能装更多套餐。",
    "agentwf": "「三级大餐」（4–5 样菜合成）更值钱，每级 +0.4 倍。",
    "fuse3": "饭盒里有 3 份一模一样的菜时，会合成 1 份更高品级的（普通 → 优质 → 金牌），只占 1 格。",
    "hodge": "饭盒装满了又凑不出套餐时，3 样来自不同窗口的散菜会自动压成一份「乱炖」（二级套餐），腾出格子。",
    "cot": "套餐还能当原料，合成更大的套餐。一盒里每这样连着合成一次，这盒收入 +30%（最多 3 次）。",
    "rag": "套餐里每用到一样优质或金牌原料，这份套餐每级再值钱 +2（还会乘套餐倍率）。",
    "agirec": "「神级套餐」（6 样以上，或隐藏配方）更值钱，每级 +0.6 倍。",
    "spec": "每次合成套餐有 20% 几率「猜下一样」：如果盒里某个套餐只差 1 样，直接帮你补上；不然就送她一口零食。",
    "eat": "她吃得更快，每级 +25%。桌上的饭盒消化得越快，你越不用等空饭盒。",
    "stream": "越吃越香：这一顿她吃过 40 口以后，后面每一口越来越值钱（她头顶会显示现在 ×几）。有上限，发布新版本会抬高。每级涨得更快。",
    "ttft": "「越吃越香」开始得更早：第 40 口 → 第 30 口 → 第 20 口。",
    "mtp": "她每吃一口，额外 +1 token（每级）。吃得越多越划算。",
    "busy": "她手里没饭吃的时候会越等越馋：下一盒饭的收入跟着涨（头顶显示「馋 ×几」），等 10 秒左右就涨得差不多了。适合凑好一盒大的再送。每级更馋。",
    "queue": "馋得更快：同样等几秒，「馋」的倍数涨得更多。",
    "multiturn": "连着送出「至少有 2 份二级以上套餐」的饭盒，就能叠「连击」：每连一盒，之后的饭盒更值钱。手里的饭盒达标时会亮「连击✓」，送一盒不达标的就断。",
    "memory": "连击断了不再清零：1 级只掉一半；2 级每顿第一次断掉不算。",
    "warm": "桌子左边多一个保温箱：端着装好的饭盒碰一下就放进去。关门后她最后吃这盒，收入 ×2，而且按馋到最高算。放进更好的一盒，旧的会回到桌上。好吃的留到最后吃。",
    "final": "保温箱那一盒更值钱：×2 → ×3 → ×4 → ×5。",
    "bon": "保温箱会自动换成这一顿最值钱的那一盒，不用你自己放。",
    "rlhf": "她吃得越均衡（主食 : 荤 : 素 接近 4 : 3 : 3，看右上角的条），关门结算的加成越高。每级把最高加成提高 0.25 倍。",
    "constit": "均衡的判定放宽：差一点也算吃得很均衡。",
    "grok": "她不再把青菜吐掉，而是皱着眉硬咽下去（这几口不赚钱）。这一顿咽够 30 口，她会突然开窍：「原来青菜这么好吃！」之后每口青菜都值 6 token，嚼得飞快。",
    "warmup": "开窍得更快：要硬咽的青菜从 30 口降到 24 → 18 → 12 口。",
    "aftertaste": "开窍以后，每口青菜再值钱 +2（每级）。",
    "drift": "开窍以后，她吃的青菜一半算素、一半算荤：青菜吃得再多也不会不均衡。",
    "skills": "两个省事的自动技能：你手里空了，她会给你丢一个空饭盒；你的饭盒装满了，会自己飞回桌上。",
    "hire": "招一个小助手：她自带饭盒在地上跑来跑去接菜，接得差不多就送到桌上。每级多招一个（问问、谱谱、小G、克劳、双子、格格，各有一个小特长）。",
    "orch": "小助手跑得更快（每级 +30%）。",
    "fc": "小助手会优先去接「现在能做的最值钱套餐」要用的原料。",
    "nutri": "小助手会优先接这一顿吃得最少的那一类（主食、荤菜或素菜），帮她吃均衡。",
    "clip": "关门结算时，这一顿最差的那 20% 饭盒按平均水平算：收入更稳。",
    "async": "小助手送来的饭盒不会打断她的「馋」：吃完它们，她照样接着馋。",
    "sleep": "关门时桌上没吃完的饭盒，她会在梦里吃掉，算一半的收入。",
    "think": "R1 送你的能力：按住空格或右键，时间变慢，还能看到每道菜会落在哪儿。点这张票，思考时间多 1 秒。",
    "diverge": "思考（按住空格）的时候，饭盒会把附近的菜吸过来，每级吸得更远。",
    "converge": "思考的时候，用不上的菜（比如她不吃的青菜）会直接穿过饭盒。和「发散思维」都点，就是只吸你需要的菜。",
    "critic": "这一顿吃到的套餐种类越多越好：从第 5 种起，每多一种不同的套餐，整顿收入 +4%。",
    "bench": "「美食评鉴」每多一种套餐的加成，每级再 +2%。",
    "ticket_r1": "交门票，开始「发布 R1」的评测：这一顿赚到 2,000 token 就通过，解锁新的技能和「深度思考」。没过只是门票没了，随时再来。",
    "ticket_v31": "评测：一顿赚到 2 万 token 就发布 V3.1，解锁新技能、自动标出好菜的落点。",
    "ticket_v32": "评测：一顿赚到 6 万 token 就发布 V3.2，解锁新技能和更聪明的吸附。V3.1-Terminus 终于不再到处冒「极」字了。",
    "ticket_v4": "评测：一顿赚到 40 万 token 就发布 V4，解锁最后一批技能。",
    "ticket_agi": "终极评测：一顿赚到 200 万 token，大肥鱼就实现了 AGI。但是也要先吃饱。",
}


def pos(br, d, l):
    r = STEP * (d + R0)
    a = math.radians(BRANCH[br]) + l * LANE_PX / r
    return [math.cos(a) * r, math.sin(a) * r]


def relax(nodes):
    """Push overlapping tickets apart (the root stays put) while pulling each one a little towards
    its parents, so the board stays compact and the yarn short."""
    by = {n["id"]: n for n in nodes}
    for it in range(1500):
        moved = 0.0
        for i, a in enumerate(nodes):
            for b in nodes[i + 1:]:
                dx, dy = b["pos"][0] - a["pos"][0], b["pos"][1] - a["pos"][1]
                e = (dx / TICKET[0]) ** 2 + (dy / TICKET[1]) ** 2
                if e >= 1.0:
                    continue
                k = (1.0 - math.sqrt(e)) * 0.5 + 0.01
                if abs(dx) / TICKET[0] > abs(dy) / TICKET[1]:
                    push = (math.copysign(k * TICKET[0], dx or 1.0), 0.0)
                else:
                    push = (0.0, math.copysign(k * TICKET[1], dy or 1.0))
                for n, sgn in ((a, -1.0), (b, 1.0)):
                    if n["id"] != "start":
                        w = 1.0 if (a["id"] == "start" or b["id"] == "start") else 0.5
                        n["pos"][0] += sgn * push[0] * w
                        n["pos"][1] += sgn * push[1] * w
                moved += k
        for n in nodes:   # a gentle pull towards the parents
            ps = [by[p] for p in n["parents"] if p in by]
            if not ps or n["id"] == "start":
                continue
            px = sum(p["pos"][0] for p in ps) / len(ps)
            py = sum(p["pos"][1] for p in ps) / len(ps)
            n["pos"][0] += (px - n["pos"][0]) * PULL
            n["pos"][1] += (py - n["pos"][1]) * PULL
        if moved == 0.0 and it > 50:
            break
    for n in nodes:
        n["pos"] = [round(n["pos"][0]), round(n["pos"][1])]


nodes = [{"id": "start", "name": "先吃饭吧！", "desc": "目标是实现AGI！但是也要先吃饱。", "pos": [0, 0], "parents": [], "max": 1, "cost": 0, "growth": 1, "effects": {}}]
for (nid, br, d, l, name, desc, mx, ring, parents, eff, flags) in N:
    ri = RINGS.index(ring)
    cost = RING_COST[ri] * (1 + 0.35 * (d - 1))
    if "key" in flags:
        cost *= 2.5
    elif mx == 1:
        cost *= 1.5
    if "free" in flags:
        cost = 0
    growth = 1.0 if mx == 1 else GROWTH.get(nid, 4.0)
    effects = {}
    for k, v in eff.items():
        effects[k] = {"mul": v[1]} if isinstance(v, tuple) else {"add": v}
    n = {"id": nid, "name": name, "desc": DESC.get(nid, desc), "pos": pos(br, d, l), "parents": parents, "max": mx,
         "cost": int(round(cost, -1)) if cost >= 100 else int(cost), "growth": growth, "effects": effects}
    if ri:
        n["ring"] = ri
    if "key" in flags:
        n["key"] = True
    nodes.append(n)
for (nid, d, l, name, opens, cost, ri, parents, desc) in TICKETS:
    n = {"id": nid, "kind": "ticket", "opens": opens, "name": name, "desc": DESC.get(nid, desc), "pos": pos("version", d, l),
         "parents": parents, "max": 1, "cost": cost, "growth": 1, "effects": {}}
    if ri:
        n["ring"] = ri
    nodes.append(n)

relax(nodes)
left = sum(1 for i, a in enumerate(nodes) for b in nodes[i + 1:]
           if ((a["pos"][0] - b["pos"][0]) / TICKET[0]) ** 2 + ((a["pos"][1] - b["pos"][1]) / TICKET[1]) ** 2 < 0.8)
print("overlaps left:", left, "· extent:", max(max(abs(n["pos"][0]), abs(n["pos"][1])) for n in nodes))
doc = ("技能树数据，由 pipeline/build_tree.py 生成（别手改）。模型见 docs/tree_model.md。ring 是节点所属的版本环（0 = V3，1 = R1，2 = V3.1，3 = V3.2，4 = V4），"
       "版本发布前这一环不显示；kind=ticket 是门票节点，opens 是它开放的评测；key 是开一种新赚钱方式的节点。pos 是相对树中心的坐标（像素）；"
       "parents 里任意一个父节点买过，这个节点才会出现；cost = cost × growth^当前等级（token）；effects 每升一级叠加一次：add 加法，mul 乘法。可用属性见 game.gd 的 BASE。")
json.dump({"_doc": doc, "nodes": nodes}, open(OUT, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
print(len(nodes), "nodes ->", OUT)
