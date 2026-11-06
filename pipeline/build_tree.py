"""Build game/data/skill_tree.json from the authored node list and fixed board positions.
Unlock dependencies may change without moving the reviewed board. The radial/relax helpers
remain available for a future explicit layout review; normal generation never runs them.

    python pipeline/build_tree.py
"""
import json
import math
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "data", "skill_tree.json")

BRANCH = {"stall": -90, "auntie": -30, "box": 30, "fish": 90, "crew": 150, "version": -150}
RINGS = ["V3", "R1", "V3.1", "V3.2", "V4", "V4.1F", "V4.1-1017", "V4.1P"]
RING_COST = [60, 2500, 25000, 250000, 1500000, 5000000, 12000000, 25000000]   # first level of a plain node, by ring
GROWTH = {"eat": 2.0, "mat": 30.0, "vram": 6.0, "smallcup": 2.5, "vmatch": 2.5, "fetchfast": 2.5, "fetchgold": 2.5, "shorter": 2.5, "pro_full": 2.5, "godfeast": 2.5, "longctx": 2.5}   # per-node price growth (default 2.2, stalls 2.5)
STEP, LANE_PX, R0 = 195.0, 160.0, 0.9   # a tight radial start; relax() then pushes tickets apart
TICKET = (235.0, 165.0)                  # room one ticket needs (with its pin and yarn)
PULL = 0.001

# id, branch, d, lane, name, desc, max, ring, parents, effects, flags
# effects: {stat: add} or {stat: ("mul", x)}; flags: key (opens a way to score, x2.5 price)
N = [
    ("stall_main", "stall", 1, -1, "预训练语料·主食", "主食窗口升级，出新菜：饭团、白粥 → 炒饭 → 荷叶饭。", 3, "V3", ["start"], {"stall_main": 1}, ""),
    ("stall_wok", "stall", 1, 1, "预训练语料·炒菜", "开炒菜窗口：青菜、番茄炒蛋 → 土豆丝、红烧肉 → 宫保鸡丁。", 3, "V3", ["start"], {"stall_wok": 1}, ""),
    ("stall_dim", "stall", 2, 1.5, "预训练语料·面点", "开面点窗口：肉包、油条 → 豆浆、饺子 → 小笼包。", 3, "V3", ["stall_wok"], {"stall_dim": 1}, ""),
    ("stall_fry", "stall", 3, 1.5, "预训练语料·炸物", "开炸物窗口：鸡腿、薯条 → 冰可乐 → 炸鸡汉堡。", 3, "R1", ["stall_dim"], {"stall_fry": 1}, ""),
    ("stall_sweet", "stall", 4, 1.5, "多模态·甜品窗口", "开甜品窗口：布丁、奶茶 → 双皮奶 → 冰激凌。", 3, "V3.1", ["stall_fry"], {"stall_sweet": 1}, ""),
    ("menu", "stall", 2, 0, "System Prompt：今日菜单", "开饭前从菜单上划掉 1 道菜（在「今日菜单」里选），每级多划 1 道。被划掉的菜不再出，机会让给同窗口的其他菜。", 4, "V3", ["stall_wok"], {"menu_cut": 1}, ""),
    ("sft", "stall", 2, -1.5, "SFT 监督微调", "每道菜有几率是优质菜（×2，带银色扫光），每级 +8%。", 5, "V3", ["stall_main"], {"sft": 0.08}, ""),
    ("lora", "stall", 3, -0.5, "LoRA 微调", "菜单划得越短，剩下的菜越容易是优质菜：每划掉 1 道 +3%。", 1, "V3", ["menu", "sft"], {"lora": 0.03}, ""),
    ("dpo", "stall", 3, -1.5, "DPO 偏好优化", "优质菜有几率再升成金牌菜（×4，带金色辉光），每级 +20%。", 3, "R1", ["sft"], {"dpo": 0.2}, ""),
    ("fp32", "stall", 4, -1.5, "FP32 满精度", "金牌菜从 ×4 变成 ×5。", 1, "V3.2", ["dpo"], {"fp32": 1}, ""),
    ("moe", "stall", 2, -2.7, "MoE 激活专家", "开饭前多选 1 道招牌菜。", 3, "V3", ["stall_main"], {"sig_slots": 1}, ""),
    ("canteen_std", "stall", 2, 2.6, "食堂标配", "每个窗口出菜时，有几率顺手配一勺青菜，每级 +15%。", 3, "R1", ["stall_wok"], {"veg_std": 0.15}, ""),

    ("conc", "auntie", 1, 0, "并发请求", "梁阿姨多长一条触手，抛的菜更多（每个开着的窗口本来就有一条）。", 5, "V3", ["start"], {"tentacles": 1}, ""),
    ("lunch", "auntie", 1, -1.6, "中午吃什么", "每口有几率暴击 ×2：她先托腮想一下，再狠狠吃一大口。每级暴击率 +3%、暴击倍数 +0.1。", 5, "V3", ["start"], {"crit_chance": 0.03, "crit_mult": 0.1}, ""),
    ("api", "auntie", 2, -1, "API 价格打骨折", "阿姨抛菜更快，每级快 12%。", 5, "V3", ["conc"], {"throw_rate": ("mul", 1.12)}, ""),
    ("batch", "auntie", 3, -1.3, "Batch Size：多来一份", "每一勺有几率多抛 1 样，每级 +25%。", 3, "R1", ["api"], {"batch": 0.25}, ""),
    ("peak", "auntie", 2, -2.4, "推理高峰", "饭点里一阵一阵的高峰时段：出菜 ×2.5，稀有菜更常见。每级高峰多 3 秒。", 3, "R1", ["conc"], {"peaks": 1, "peak_time": 3}, ""),
    ("temp", "auntie", 2, 1, "Temperature 1.0", "菜进饭盒时，有几率变成同窗口、同类的高一级菜（青菜 → 土豆丝），已经最高级的就变成优质菜。变过的菜额外 ×1.5（带小火苗）。正在凑的套餐原料不会被变走。每级 +8%。", 5, "V3", ["conc"], {"temp": 0.08}, "key"),
    ("hot", "auntie", 3, 1, "高温采样", "被随机碰过的菜（变过的、幻觉出来的、暴击的）每级再 +0.25 倍。", 4, "R1", ["temp"], {"hot": 0.25}, ""),
    ("halluc", "auntie", 3, 2.1, "幻觉", "菜进饭盒时，有几率凭空多出一口同窗口的菜（不占格），每级 +8%。", 3, "R1", ["temp"], {"halluc": 0.08}, ""),
    ("regen", "auntie", 4, 0.6, "重新生成", "送上桌的饭盒有几率整盒重抽：每样散菜都换成高一级的菜。每级 +10%。", 2, "V4", ["hot"], {"regen": 0.1}, ""),
    ("emerge", "auntie", 4, 2.1, "涌现能力", "一盒里有 3 样被随机碰过的菜时，有几率凝成一份「涌现乱炖」（神级套餐）。", 1, "V4", ["halluc", "hodge"], {"emerge": 1}, ""),
    ("overfit", "auntie", 4, -0.4, "过拟合：看什么都像青菜", "顿悟以后，散菜进饭盒有 15% 几率变成青菜（算被随机碰过）。", 1, "V3.1", ["grok", "temp"], {"overfit": 1}, ""),

    ("vram", "box", 1, 0, "显存扩容", "饭盒 2×2 → 2×3 → 2×4，接菜范围一起变宽；每级还多一个饭盒。", 2, "V3", ["start"], {"box_n": 1, "basins": 1}, ""),
    ("ocr", "box", 1, -1.5, "光学压缩", "每盒饭 +20%（每级）。", 3, "V3", ["start"], {"box_bonus": 0.2}, ""),
    ("prompt", "box", 1, 1.5, "Prompt 模板", "小炒每级 +0.2 倍；装满同一道菜也能组成单品拼盘。", 5, "V3", ["stall_wok"], {"tier1": 1, "mono_bonus": 0.1}, ""),
    ("mat", "box", 2, 0, "饭盒材质", "铁 → 铜 → 银 → 金：整顿收入 ×1.5 / ×2 / ×3。", 3, "V3", ["vram"], {"material": 1}, ""),
    ("fill", "box", 2, -1.5, "上下文填满", "送出的饭盒一格都不空：这盒 +25%。", 1, "R1", ["ocr"], {"fill_bonus": 0.25}, ""),
    ("fewshot", "box", 2, 1.5, "Few-shot 示例", "二级套餐（3 样）更值钱：每级 +0.3 倍（乱炖也算二级）。", 5, "V3", ["prompt"], {"tier2": 1}, ""),
    ("inject", "box", 2, 2.8, "提示词注入", "合成套餐时，盒里的一样青菜被偷偷藏进去：不占格，算一份素，套餐也多算一样原料。", 1, "R1", ["prompt"], {"inject": 1}, ""),
    ("compress", "box", 3, 0, "上下文压缩", "套餐少占一格；送出有余量的套餐盒，给下一满盒存下加成。", 1, "R1", ["mat"], {"compress": 1, "cache_bonus": 0.15}, ""),
    ("agentwf", "box", 3, 1.5, "Agent 工作流", "三级大餐（4–5 样）更值钱：每级 +0.4 倍。", 5, "R1", ["fewshot"], {"tier3": 1}, ""),
    ("fuse3", "box", 3, -1.5, "模型融合", "盒里 3 份一样的菜融成 1 份高一品级的（普通 → 优质 → 金牌）。", 1, "V3.1", ["sft", "fill"], {"fuse3": 1}, ""),
    ("hodge", "box", 3, 2.8, "MoE 大杂烩", "饭盒装满、又没有「差一样就能凑齐」的套餐时，3 样不同窗口的散菜压成一份「乱炖」（二级套餐）。", 1, "V3.1", ["temp", "fewshot"], {"hodge": 1}, ""),
    ("cot", "box", 4, 0, "思维链", "盒里每发生一次连锁合成（套餐当原料再合成），这一盒 +30%，最多 3 次。", 1, "V3.1", ["compress"], {"cot": 0.3}, ""),
    ("rag", "box", 4, -1.2, "RAG 检索增强", "套餐里每样优质或金牌原料，每级 +2 价值（再乘套餐等级）。", 3, "V3.1", ["dpo", "agentwf"], {"rag": 2}, ""),
    ("agirec", "box", 4, 1.5, "AGI 菜谱", "首次学习后，图鉴公开所有套餐的完整配方，包括隐藏配方。「神级套餐」（6 样以上，或隐藏配方）更值钱，每级 +0.6 倍。", 5, "V3.2", ["agentwf"], {"tier4": 1}, ""),
    ("spec", "box", 5, 0.6, "投机解码", "每次合成有 20% 几率「猜下一样」：套餐差 1 样就直接补上，不然就变成一口零食。", 1, "V3.2", ["halluc", "cot"], {"spec": 0.2}, ""),

    ("eat", "fish", 1, 0, "猛炫", "她吃得更快，每级 +25%。", 12, "V3", ["start"], {"eat_rate": ("mul", 1.25)}, ""),
    ("stream", "fish", 2, -0.6, "流式输出", "越吃越香：这一顿吃过 40 口以后，每口越来越值钱（头顶有读数）。有上限，发布新版本会抬高。", 5, "V3", ["eat"], {"stream": 0.2}, "key"),
    ("ttft", "fish", 3, -1.1, "降低首 Token 延迟", "越吃越香开始得更早：第 40 口 → 30 口 → 20 口。", 2, "V3", ["stream"], {"ttft": 1}, ""),
    ("mtp", "fish", 3, 0, "MTP 多 Token 预测", "每吃一口，每级 +1 token。", 4, "V3", ["stream"], {"mtp": 1}, ""),
    ("busy", "fish", 1, 1.6, "服务器繁忙，请稍后再试", "她空着手等饭时越等越馋：下一盒饭跟着涨价（头顶有读数），等过一会儿就不怎么再涨了。每级更馋。", 5, "V3", ["start"], {"crave": 0.5}, "key"),
    ("queue", "fish", 2, 1.9, "排队中……", "馋得更快：同样等几秒，馋得更厉害。", 2, "R1", ["busy"], {"crave_tau": -1.25}, ""),
    ("multiturn", "fish", 3, 1.4, "多轮对话", "连续送出「至少 2 份二级以上套餐」的饭盒（盒边亮「连击✓」），每连一盒，之后的盒子更值钱。连击数有上限，发布新版本会抬高。", 4, "R1", ["busy", "fewshot"], {"combo": 0.05}, "key"),
    ("memory", "fish", 4, 0.9, "上下文记忆", "保留断连保护；连续送出单品拼盘时，换一道菜让下一盒更值钱。", 2, "V3.1", ["multiturn"], {"memory": 1, "rotation_bonus": 0.1}, ""),
    ("warm", "fish", 4, 2.1, "KV Cache 保温箱", "好吃的留到最后吃：桌子左边多一个保温箱。端着饭盒放进去，关门后她揭盖吃掉：×2，按馋到最高算。放进更好的一盒会把旧的换出来。", 1, "V3.1", ["multiturn"], {"warm": 1}, "key"),
    ("final", "fish", 5, 2.6, "Final Answer", "保温箱那一盒更值钱：×2 → ×3 → ×4 → ×5。", 3, "V3.1", ["warm"], {"final": 1}, ""),
    ("bon", "fish", 5, 1.5, "Best-of-N", "保温箱自动换成这一顿最值钱的那一盒。", 1, "V3.2", ["warm"], {"bon": 1}, ""),
    ("eos", "fish", 6, 2.6, "<EOS> 最后一个 token", "她把保温箱里最好吃的那一口留到最后：这一口再 ×3 → ×5 → ×8。", 3, "V3.1", ["final"], {"eos": 1}, ""),
    ("rlhf", "fish", 2, -1.9, "RLHF 人类偏好对齐", "吃得均衡时，整顿的加成上限更高（每级 +0.25）。", 4, "V3", ["eat"], {"balance_max": 0.25}, ""),
    ("constit", "fish", 3, -2.4, "宪法 AI·膳食宝塔", "均衡判定放宽：差一点也算吃得匀。", 1, "V3.2", ["rlhf"], {"constit": 1}, ""),
    ("grok", "fish", 4, -1.5, "顿悟（Grokking）", "她不再把青菜吐掉，而是皱着眉硬咽下去（一口不赚）。这一顿咽够 30 口后顿悟：「原来青菜这么好吃！」之后青菜每口都很值钱。", 1, "R1", ["stall_wok", "rlhf"], {"grok": 1}, "key"),
    ("warmup", "fish", 5, -2.2, "学习率预热", "顿悟得更快：要咽的青菜从 30 口降到 24 → 18 → 12 口。", 3, "R1", ["grok"], {"grok_need": -6}, ""),
    ("aftertaste", "fish", 5, -1, "回甘", "顿悟以后，每口青菜更值钱（每级 +2）。", 4, "V3.1", ["grok"], {"aftertaste": 2}, ""),
    ("drift", "fish", 6, -1.6, "向量漂移", "顿悟以后的青菜一半算素、一半算荤：吃得再多也不怕不均衡。", 1, "V3.2", ["aftertaste"], {"drift": 1}, ""),

    ("skills", "crew", 1, 0, "Skill：自动推送 / 自动回收", "自动给空盒、满盒回收可在开饭前分开开关。", 1, "V3", ["start"], {"auto_push": 1, "auto_return": 1}, ""),
    ("hire", "crew", 2, 0, "本地小模型：招募小助手", "每级增加一个出场名额，六位助手自由选，也可以休息。", 6, "V3", ["start"], {"helper": 1}, ""),
    ("orch", "crew", 3, -0.6, "多 Agent 编排", "助手每级跑速 +30%；有效完成不同职责，可给下一盒亲手送餐各存 +15% 接力。", 2, "R1", ["hire"], {"helper_speed": 0.3, "crew_relay": 0.15}, ""),
    ("fc", "crew", 3, 0.8, "Function Calling：点单", "可为每位助手指定套餐，优先接自己这盒缺的原料，做成就送。", 1, "R1", ["hire"], {"fc": 1}, ""),
    ("nutri", "crew", 4, -1.2, "营养师 Agent", "助手参考已经吃下和正在准备、配送的食物，补主荤素缺口。", 1, "V3.1", ["orch"], {"nutri": 1}, ""),
    ("clip", "crew", 5, -1.2, "梯度裁剪", "所有已吃完的饭盒都算：至少5盒时，最差20%补到平均收入。", 1, "V3.1", ["hire"], {"clip": 1}, ""),
    ("async", "crew", 4, 1.2, "异步调用", "需招募和服务器繁忙：玩家盒优先，助手不消耗馋；各组先进先出。", 1, "V3.2", ["hire", "busy"], {"async": 1}, "require_all"),
    ("sleep", "crew", 4, 0, "我去睡了", "全局收摊保险：所有未吃完的盒中食物按一半价值结算。", 1, "V3.2", ["hire"], {"sleep": 1}, ""),

    ("think", "version", 2, -0.4, "深度思考", "R1 的奖励：按住空格或右键，时间变慢，能看清每道菜落在哪。这里点一下，思考槽 +1 秒。", 1, "R1", ["ticket_r1"], {"think_time": 1}, "free"),
    ("diverge", "version", 3, -1.2, "发散思维", "思考时，饭盒能吸住大范围的菜（每级 +120 像素）。", 2, "R1", ["think"], {"diverge": 120}, ""),
    ("converge", "version", 3, -0.1, "收敛思维", "思考时，用不上的菜（包括青菜）直接穿过饭盒。和发散思维都点，就是「只吸需要的菜」。", 1, "R1", ["think"], {"converge": 1}, ""),
    ("critic", "version", 4, -0.6, "美食评鉴（刷榜）", "这一顿吃到的不同套餐，从第 5 种起，每多一种整顿 +4%。", 1, "V3.1", ["stall_dim"], {"critic": 0.04}, "key"),
    ("bench", "version", 5, -0.6, "Benchmark 全家桶", "每多一种套餐的加成，每级再 +2%。", 2, "V3.1", ["critic"], {"critic": 0.02}, ""),

    # V4.1 Flash: 小模型反超旗舰，还能看图
    ("vision", "version", 6, -1.0, "多模态：识图", "选一道想做的套餐，缺的原料所在窗口会亮起来。", 1, "V4.1F", ["ticket_flash"], {"vision": 1}, "free"),
    ("vfilter", "version", 6, -1.6, "视觉过滤", "选了识图目标后，用不上的菜直接穿过饭盒。", 1, "V4.1F", ["vision"], {"vision_filter": 1}, ""),
    ("vmatch", "version", 7, -1.0, "看图说话", "做成识图目标的那一盒更值钱，每级 +30%。", 3, "V4.1F", ["vision"], {"vmatch": 0.3}, ""),
    ("smallcup", "version", 6, -0.4, "小杯反超大杯", "只占一格的散菜更值钱，每级 +20%。", 3, "V4.1F", ["ticket_flash"], {"small_x": 0.2}, ""),

    # V4.1 Flash-1017: 任务更快、输出更短，开放搜索和抓取
    ("fetch", "version", 7, -0.2, "Fetch 跑腿", "每隔一会儿，助手把一道菜直接送到你饭盒上方。", 1, "V4.1-1017", ["ticket_1017"], {"fetch": 1}, "free"),
    ("fetchfast", "version", 8, -0.2, "Search 预查询", "跑腿更勤快，每级间隔少 2 秒。", 3, "V4.1-1017", ["fetch"], {"fetch_fast": 2}, ""),
    ("fetchgold", "version", 8, 0.4, "抓取加急", "跑腿送来的菜品级更高：优质 → 金牌。", 2, "V4.1-1017", ["fetch"], {"fetch_grade": 1}, ""),
    ("shorter", "version", 7, 0.4, "输出更短", "她吃得更快，每级 +20%。", 3, "V4.1-1017", ["ticket_1017"], {"eat_rate": ("mul", 1.2)}, ""),
    ("harness", "version", 9, -0.2, "Harness 升级", "每位上场的助手让跑腿间隔再少 1 秒。", 1, "V4.1-1017", ["fetchfast", "hire"], {"harness": 1}, "require_all"),

    # V4.1 Pro: 压轴
    ("pro_full", "version", 8, -1.0, "满血 Pro", "整顿收入 ×1.5，第 2 级 ×2。", 2, "V4.1P", ["ticket_pro"], {"pro_x": 0.5}, "key"),
    ("godfeast", "version", 8, -1.6, "神级宴席", "这一顿每吃过一种神级套餐，整顿收入每级 +15%。", 3, "V4.1P", ["ticket_pro"], {"godfeast": 0.15}, ""),
    ("longctx", "version", 9, -1.0, "超长上下文", "越吃越香和连击的上限再提高。", 2, "V4.1P", ["pro_full"], {"longctx": 1}, ""),
    ("waitlist", "version", 9, -1.6, "这周一定", "每没过一次当前评测，下次评测收入 +20%（最多 3 次）。", 1, "V4.1P", ["ticket_pro"], {"waitlist": 0.2}, ""),
]

TICKETS = [
    ("ticket_r1", 1, 0.9, "申请发布 R1", "spring", 300, 0, ["start"], "评测：一顿赚到 2,000 就发布 R1。"),
    ("ticket_v31", 2, 1.1, "申请发布 V3.1", "hybrid", 6000, 1, ["ticket_r1"], "评测：一顿赚到 2 万就发布 V3.1。"),
    ("ticket_v32", 3, 1.2, "申请发布 V3.2", "ji", 40000, 2, ["ticket_v31"], "评测：一顿赚到 6 万就发布 V3.2。V3.1-Terminus 终于不再到处冒「极」字了。"),
    ("ticket_v4", 4, 1.2, "申请发布 V4", "v4", 250000, 3, ["ticket_v32"], "评测：一顿赚到 40 万就发布 V4。"),
    ("ticket_flash", 5, 1.2, "申请发布 V4.1 Flash", "flash", 10000000, 4, ["ticket_v4"], "评测：一顿赚到 3000 万就发布 V4.1 Flash。"),
    ("ticket_1017", 6, 1.2, "申请发布 V4.1 Flash-1017", "f1017", 25000000, 5, ["ticket_flash"], "评测：一顿赚到 5000 万就发布 V4.1 Flash-1017。"),
    ("ticket_pro", 7, 1.2, "申请发布 V4.1 Pro", "pro", 50000000, 6, ["ticket_1017"], "评测：一顿赚到 8000 万就发布 V4.1 Pro。"),
    ("ticket_agi", 8, 1.2, "实现 AGI", "agi", 100000000, 7, ["ticket_pro"], "终极评测：一顿 1.5 亿。目标是实现 AGI！但是也要先吃饱。"),
]

# What each node says on the board: written for the player (what happens when I click it, what
# will I see), not for us. Overrides the short design notes in N above.
DESC = {
    "stall_main": "主食窗口（柜台正中间）升级，菜单多一道菜：饭团和白粥 → 炒饭 → 荷叶饭。",
    "stall_wok": "开张炒菜窗口：番茄炒蛋和青菜。再升级会出土豆丝、红烧肉，最后是宫保鸡丁。小心：她不爱吃青菜。",
    "stall_dim": "开张面点窗口：肉包和油条。再升级会出豆浆、饺子，最后是小笼包。",
    "stall_fry": "开张炸物窗口：鸡腿和薯条。再升级会出冰可乐，最后是炸鸡汉堡。",
    "stall_sweet": "开张甜品窗口：布丁和奶茶。再升级会出双皮奶，最后是冰激凌。",
    "menu": "解锁「今日菜单」按钮：开饭前划掉不想要的菜，它就不会再出，同窗口的其他菜出得更多。每级多划 1 道；每个已开档口至少保留一道菜。",
    "sft": "抛下来的菜有几率是「优质菜」：带银色扫光，价值 ×2。每级几率 +8%。",
    "lora": "今日菜单里每划掉 1 道菜，剩下的菜是优质菜的几率 +3%。",
    "dpo": "优质菜有几率直接升成「金牌菜」：带金色辉光，价值 ×4。每级几率 +20%。",
    "fp32": "金牌菜的价值从 ×4 提到 ×5。",
    "moe": "解锁「招牌菜」按钮：开饭前选一道招牌菜，这一顿它有特别加成（比如越吃越值钱）。每级多选一道。",
    "canteen_std": "每个窗口抛菜时，有几率顺手多给一勺青菜（每级 +15%）。青菜能凑套餐、补素菜，也是「顿悟」的训练材料。",
    "conc": "梁阿姨多长一条触手：多一把勺子在抛菜，菜更多。",
    "lunch": "每一口有几率暴击：这口 ×2，她会先托腮想一下再狠狠咬下去。每级暴击几率 +3%、倍数 +0.1。",
    "api": "梁阿姨出菜更快，每级快 12%。",
    "batch": "每一勺有几率多抛一样菜，每级几率 +25%。",
    "peak": "饭点里隔一会儿来一阵「高峰」：出菜 ×2.5，稀有菜更常见。每级高峰多 3 秒。",
    "temp": "菜入盒时有几率变成同窗口、同类的高一级菜；最高级或放不下时改为升品级。变过的菜带火苗，价值再 ×1.5。正在凑的原料不变，顿悟后青菜只升品级。每级几率 +8%；可在「自动化」暂停，下顿生效。",
    "hot": "带小火苗的菜（被变过的、幻觉出来的、暴击的那口）每级再值钱 +0.25 倍。",
    "halluc": "菜掉进饭盒时，有几率凭空多出一口同窗口的菜，不占格子（饭盒角上显示 +1）。每级几率 +8%。",
    "regen": "亲手送上桌的饭盒有几率整盒「重抽」：散菜换成更高级的菜，放不下时原菜升品质并加热；每级几率 +10%。可在「自动化」暂停，下顿生效。",
    "emerge": "一盒里凑够 3 样带小火苗的菜时，有 25% 几率合成「涌现乱炖」：神级套餐，非常值钱。",
    "overfit": "顿悟以后，入盒散菜有 15% 几率变成高温青菜。可在「自动化」暂停，下顿生效，避免打乱其它套餐。",
    "vram": "饭盒变宽一列（2×2 → 2×3 → 2×4），接菜范围也变宽；每级还多给你一个饭盒。",
    "ocr": "每一盒饭的收入 +20%（每级）。",
    "prompt": "小炒套餐每级 +0.2 倍。亲手送出装满同一道散菜的饭盒（至少两份），就是「单品拼盘」：整盒每级 +10%，还能接上连击。品级不同也行，幻觉不算；拼盘不增加图鉴配方。",
    "mat": "换更好的饭盒：铁 → 铜 → 银 → 金，整顿收入 ×1.5 / ×2 / ×3。材质只提高收入；吸菜来自思考中的「发散思维」。",
    "fill": "送出的饭盒一格都没空着，这盒收入 +25%。",
    "fewshot": "「二级套餐」（3 样菜合成）更值钱，每级 +0.3 倍。乱炖也算二级套餐。",
    "inject": "合成套餐时，盒里的一棵青菜会被偷偷藏进套餐：不占格子，她吃不出来，还算吃了一份素。",
    "compress": "套餐少占 1 格（最少 1 格）。亲手送出含套餐、空着至少两格的盒，存一份缓存：下一亲手满盒 +15%，只存一份。搭配上下文记忆，单品拼盘后首次存入空缓存，还能保留换菜接力与连击。",
    "agentwf": "「三级大餐」（4–5 样菜合成）更值钱，每级 +0.4 倍。",
    "fuse3": "3 份菜名、品级和火苗相同的散菜融成 1 份高一品级的菜，腾出两份的位置（普通 → 优质 → 金牌）。会减少口数；可在「自动化」暂停，下顿生效。",
    "hodge": "饭盒装满，又没有只差一样的套餐时，3 样来自不同窗口的散菜自动压成一份「乱炖」（二级套餐），腾出格子。",
    "cot": "套餐还能当原料，合成更大的套餐。一盒里每这样连着合成一次，这盒收入 +30%（最多 3 次）。",
    "rag": "套餐里每用到一样优质或金牌原料，这份套餐每级再值钱 +2（还会乘套餐倍率）。",
    "agirec": "首次学习后，图鉴公开所有套餐的完整配方，包括隐藏配方。「神级套餐」（6 样以上，或隐藏配方）更值钱，每级 +0.6 倍。",
    "spec": "每次合成套餐有 20% 几率「猜下一样」：如果盒里某个套餐只差 1 样，直接帮你补上；不然就送她一口零食。",
    "eat": "她吃得更快，每级 +25%。桌上的饭盒消化得越快，你越不用等空饭盒。",
    "stream": "越吃越香：这一顿她吃过 40 口以后，后面每一口越来越值钱（她头顶会显示现在 ×几）。有上限，发布新版本会抬高。每级涨得更快。",
    "ttft": "「越吃越香」开始得更早：第 40 口 → 第 30 口 → 第 20 口。",
    "mtp": "她每吃一口，额外 +1 token（每级）。吃得越多越划算。",
    "busy": "她手里没饭吃的时候会越等越馋：下一盒饭的收入跟着涨（头顶显示「馋 ×几」），等 10 秒左右就涨得差不多了。适合凑好一盒大的再送。每级更馋。",
    "queue": "馋得更快：同样等几秒，「馋」的倍数涨得更多。",
    "multiturn": "连着送出「至少两份二级以上套餐」或已学会的「单品拼盘」，就能叠连击，让之后的饭盒更值钱。达标会亮「连击✓」；送出不达标的饭盒会断连。",
    "memory": "连击断了，1 级只掉一半，2 级每顿第一次不算。两盒单品拼盘换菜，后一盒每级再 +10%。中间可用一盒套餐首次存入空缓存来保留接力与连击；其它普通盒会中断换菜。",
    "warm": "桌子左边多一个保温箱：端着装好的饭盒碰一下就放进去。关门后她最后吃这盒，收入 ×2，而且按馋到最高算。放进更好的一盒，旧的会回到桌上。好吃的留到最后吃。",
    "final": "保温箱那一盒更值钱：×2 → ×3 → ×4 → ×5。",
    "bon": "自动保留整盒价值最高的饭盒；不单独比较 EOS 最后一口。可在「自动化」暂停自动选盒，下顿生效，改为手动留盒。",
    "eos": "她会把保温箱里最好吃的那一口留到最后吃：关门结账时，这一口单独再 ×3 → ×5 → ×8。往保温箱里塞一份大套餐，就能稳稳控住最后一口。",
    "rlhf": "她吃得越均衡（主食 : 荤 : 素 接近 4 : 3 : 3，看右上角的条），关门结算的加成越高。每级把最高加成提高 0.25 倍。",
    "constit": "均衡的判定放宽：差一点也算吃得很均衡。",
    "grok": "她不再把青菜吐掉，而是皱着眉硬咽下去（这几口不赚钱）。这一顿咽够 30 口，她会突然开窍：「原来青菜这么好吃！」之后每口青菜都值 6 token，嚼得飞快。",
    "warmup": "开窍得更快：要硬咽的青菜从 30 口降到 24 → 18 → 12 口。",
    "aftertaste": "开窍以后，每口青菜再值钱 +2（每级）。",
    "drift": "开窍以后，她吃的青菜一半算素、一半算荤，更容易凑齐荤素；仍然需要主食才能吃得均衡。",
    "skills": "手空了自动给你空饭盒；装满了自动送回桌上。两项可在「自动化」分别开关，下顿生效，方便手动留菜、装套餐或放保温箱。",
    "hire": "每级增加一个出场名额。从问问、谱谱、小G、克劳、双子、格格中自由选人，也可以休息。开饭前在「自动化」安排职责；她们自带饭盒，不占你的空盒。",
    "orch": "每级助手跑速 +30%。补漏、指定配餐、补营养各完成一次有效配送，可各存一份接力（同类不叠）。下一盒亲手送出的非空饭，每份加成 +15% / +30%，用后清空。",
    "fc": "解锁「指定配餐」职责：每位助手可选一道菜单能做、饭盒装得下的套餐，补自己盒里缺的原料，做成就送。配餐盒保护原料，不随机改菜。禁菜或退技能使目标失效时，回到补漏。",
    "nutri": "解锁「补营养」职责：按主食 : 荤 : 素 = 4 : 3 : 3 补缺。一起考虑已吃、待吃、在途和正在收集的菜，减少大家重复补同一类。",
    "clip": "全局保险：至少吃完 5 盒时，收入最差的 20% 饭盒补到平均水平。玩家和助手已吃完的饭盒都计入，不要求营养师职责。",
    "async": "需同时学会招募和服务器繁忙。玩家饭盒优先吃，各组内先进先出；助手饭盒不消耗也不享受馋值，吃助手饭不会凭空增加馋。",
    "sleep": "全局收摊保险：桌上、正在吃、配送在途、你手里和助手盒里的剩菜，按一半价值结算，再计入整顿加成；不带流式和整盒奖励。不要求编排或营养师职责。",
    "think": "R1 送你的能力：按住空格、右键或手柄 B，菜落得更慢。结束后冷却 1 秒，松开后才能再次开始。点这张票，思考时间多 1 秒。",
    "diverge": "思考（按住空格）的时候，饭盒会把附近的菜吸过来，每级吸得更远。",
    "converge": "思考的时候，用不上的菜（比如她不吃的青菜）会直接穿过饭盒。和「发散思维」都点，就是只吸你需要的菜。",
    "critic": "这一顿吃到的套餐种类越多越好：从第 5 种起，每多一种不同的套餐，整顿收入 +4%。",
    "bench": "「美食评鉴」每多一种套餐的加成，每级再 +2%。",
    "ticket_r1": "交门票，开始「发布 R1」的评测：这一顿赚到 2,000 token 就通过，解锁新的技能和「深度思考」。没过只是门票没了，随时再来。",
    "ticket_v31": "评测：一顿赚到 2 万 token 就发布 V3.1，解锁新技能、自动标出好菜的落点。",
    "ticket_v32": "评测：一顿赚到 6 万 token 就发布 V3.2，解锁新技能。未学「顿悟」时，饭盒会避开青菜。V3.1-Terminus 终于不再到处冒「极」字了。",
    "ticket_v4": "评测：一顿赚到 40 万 token 就发布 V4，解锁新技能。",
    "ticket_flash": "评测：一顿赚到 3000 万 token 就发布 V4.1 Flash。小杯反超大杯，还学会了看图：解锁「识图」和新技能。",
    "ticket_1017": "评测：一顿赚到 5000 万 token 就发布 V4.1 Flash-1017。干活更快、话更短，解锁「Fetch 跑腿」和新技能。",
    "ticket_pro": "评测：一顿赚到 8000 万 token 就发布 V4.1 Pro。现实里它还没发布，这里你先替她发了。解锁最后一批技能。",
    "ticket_agi": "终极评测：一顿赚到 1.5 亿 token，大肥鱼就实现了 AGI。但是也要先吃饱。",
    "vision": "V4.1 Flash 送你的能力：开饭前在顶部「识图」按钮选一道想做的套餐。开饭时，缺的原料所在窗口会亮起来，饭盒旁边显示还差什么。这里点一下就学会。",
    "vfilter": "选了识图目标后，用不上的菜直接穿过饭盒，再也不会接错。这盒做成以后恢复正常接菜。想多接杂菜时，把目标设成「不指定」就行。",
    "vmatch": "做成识图目标的那一盒，收入每级 +30%。",
    "smallcup": "只占一格的散菜更值钱，每级 +20%。青菜、鸡腿、奶茶都算；两格的大菜和套餐不算。",
    "fetch": "V4.1 Flash-1017 送你的能力：每 12 秒，助手把一道菜直接送到你饭盒上方，接住就行。选了识图目标时优先送还缺的原料，否则从开着的窗口随便挑一道。这里点一下就学会。",
    "fetchfast": "跑腿更勤快：间隔每级少 2 秒。",
    "fetchgold": "跑腿送来的菜品级更高：第 1 级是优质菜，第 2 级是金牌菜。",
    "shorter": "输出更短，她吃得更快，每级 +20%。",
    "harness": "需要学会招募和 Search 预查询。这一顿每有一位助手上场，跑腿间隔再少 1 秒（最短 3 秒）。",
    "pro_full": "整顿收入 ×1.5，第 2 级 ×2。在所有结算之前生效，评测也算。",
    "godfeast": "这一顿每吃过一种不同的神级套餐，整顿收入每级 +15%。深度思考套餐、满血版、食堂全家福和涌现乱炖都算。",
    "longctx": "越吃越香的上限每级 +1 倍，连击的上限每级 +2 盒。",
    "waitlist": "每没过一次当前评测，下次评测的收入 +20%，最多算 3 次。过了以后这个版本的次数就用不上了。",
}


# One-line ticket effects. Keep the AI names and full explanations above; these answer
# what a purchase does while the player scans the board, without prescribing a build.
SUMMARY = {
    "start": "接菜喂饭赚收益",
    "stall_main": "主食档口加新菜",
    "stall_wok": "解锁炒菜档口",
    "stall_dim": "解锁面点档口",
    "stall_fry": "解锁炸物档口",
    "stall_sweet": "解锁甜品档口",
    "menu": "划掉不想要的菜",
    "sft": "提高优质菜几率",
    "lora": "精简菜单升品质",
    "dpo": "优质菜可升金牌",
    "fp32": "金牌菜价值提高",
    "moe": "开饭前选招牌菜",
    "canteen_std": "出菜额外配青菜",
    "conc": "增加抛菜触手",
    "lunch": "提高每口暴击",
    "api": "加快出菜速度",
    "batch": "一勺可多一份菜",
    "peak": "延长出菜高峰",
    "temp": "入盒随机升级菜",
    "hot": "火苗菜价值提高",
    "halluc": "入盒可额外加菜",
    "regen": "送餐可整盒升菜",
    "emerge": "火苗菜可成乱炖",
    "overfit": "顿悟后可变青菜",
    "vram": "饭盒变宽且变多",
    "ocr": "提高每盒收入",
    "prompt": "同菜满盒成拼盘",
    "mat": "提高整顿收入",
    "fill": "满盒送餐有加成",
    "fewshot": "二级套餐更值钱",
    "inject": "合成偷偷藏青菜",
    "compress": "套餐省格存缓存",
    "agentwf": "三级大餐更值钱",
    "fuse3": "三份同菜升品质",
    "hodge": "杂菜可合成乱炖",
    "cot": "连锁合成有加成",
    "rag": "好原料提升套餐",
    "agirec": "公开全部配方",
    "spec": "合成可补缺原料",
    "eat": "加快吃饭速度",
    "stream": "吃得越多越值钱",
    "ttft": "提前越吃越香",
    "mtp": "每口额外赚收益",
    "busy": "等饭越久越馋",
    "queue": "等待更快涨馋",
    "multiturn": "连击提升收益",
    "memory": "护连击换菜加成",
    "warm": "留一盒收摊再吃",
    "final": "保温盒收入提高",
    "bon": "自动留最贵盒",
    "eos": "最后一口有加成",
    "rlhf": "提高均衡上限",
    "constit": "放宽均衡判定",
    "grok": "吃青菜可顿悟",
    "warmup": "减少顿悟菜数",
    "aftertaste": "顿悟青菜更值钱",
    "drift": "顿悟青菜算荤素",
    "skills": "自动拿盒和送饭",
    "hire": "增加助手名额",
    "orch": "助手提速加接力",
    "fc": "指定助手凑套餐",
    "nutri": "助手补齐营养",
    "clip": "垫高低收入饭盒",
    "async": "玩家饭盒优先吃",
    "sleep": "收摊剩菜折半算",
    "think": "延长慢放思考",
    "diverge": "思考时吸附接菜",
    "converge": "思考时筛掉余菜",
    "critic": "套餐种类加成",
    "bench": "提高种类加成",
    "vision": "选套餐点亮窗口",
    "vfilter": "用不上的菜穿过",
    "vmatch": "做成目标有加成",
    "smallcup": "一格散菜更值钱",
    "fetch": "助手定时送菜",
    "fetchfast": "跑腿间隔变短",
    "fetchgold": "跑腿送好菜",
    "shorter": "加快吃饭速度",
    "harness": "助手加快跑腿",
    "pro_full": "整顿收入翻倍",
    "godfeast": "神级种类加成",
    "longctx": "提高成长上限",
    "waitlist": "没过评测有补偿",
    "ticket_flash": "挑战Flash评测",
    "ticket_1017": "挑战1017评测",
    "ticket_pro": "挑战Pro评测",
    "ticket_r1": "挑战R1评测",
    "ticket_v31": "挑战V3.1评测",
    "ticket_v32": "挑战V3.2评测",
    "ticket_v4": "挑战V4评测",
    "ticket_agi": "挑战最终评测",
}


# Reviewed 0.4.0 board (04d8ffa). Layout is authored independently of purchase dependencies:
# changing a prerequisite must not move the entire map. Never read generated JSON as input.
# A new node needs an explicit reviewed position here; no silent automatic rearrangement.
BOARD_POSITIONS = {
    'start': [0, 0],
    'stall_main': [-129, -286],
    'stall_wok': [360, -360],
    'stall_dim': [416, -520],
    'stall_fry': [338, -677],
    'stall_sweet': [286, -838],
    'menu': [-43, -454],
    'sft': [-270, -417],
    'lora': [-111, -611],
    'dpo': [-343, -575],
    'fp32': [-311, -740],
    'moe': [-365, -226],
    'canteen_std': [650, -537],
    'conc': [278, -205],
    'lunch': [102, -322],
    'api': [593, -377],
    'batch': [874, -590],
    'peak': [190, -475],
    'temp': [511, -223],
    'hot': [769, -267],
    'halluc': [689, -113],
    'regen': [828, -428],
    'emerge': [933, 166],
    'overfit': [921, 0],
    'vram': [226, -44],
    'ocr': [50, -161],
    'prompt': [241, 121],
    'mat': [474, 105],
    'fill': [461, -60],
    'fewshot': [253, 286],
    'inject': [180, 444],
    'compress': [486, 269],
    'agentwf': [414, 428],
    'fuse3': [698, 52],
    'hodge': [247, 597],
    'cot': [662, 381],
    'rag': [709, 219],
    'agirec': [711, 543],
    'spec': [888, 328],
    'eat': [14, 163],
    'stream': [-204, 367],
    'ttft': [18, 563],
    'mtp': [-214, 531],
    'busy': [-215, 202],
    'queue': [-428, 273],
    'multiturn': [-415, 438],
    'memory': [-254, 695],
    'warm': [-450, 603],
    'final': [-511, 790],
    'bon': [-296, 858],
    'eos': [-469, 985],
    'rlhf': [25, 326],
    'constit': [483, 586],
    'grok': [222, 761],
    'warmup': [355, 899],
    'aftertaste': [120, 910],
    'drift': [155, 1074],
    'skills': [-229, 38],
    'hire': [-443, 107],
    'orch': [-663, 275],
    'fc': [-679, 110],
    'nutri': [-652, 440],
    'clip': [-699, 603],
    'async': [-879, 206],
    'sleep': [-868, 373],
    'think': [-416, -64],
    'diverge': [-653, -53],
    'converge': [-602, -215],
    'critic': [-728, -355],
    'bench': [-958, -391],
    'ticket_r1': [-180, -125],
    'ticket_v31': [-492, -364],
    'ticket_v32': [-624, -502],
    'ticket_v4': [-584, -665],
    'ticket_flash': [-817, -688],
    'ticket_1017': [-1052, -716],
    'ticket_pro': [-1288, -744],
    'ticket_agi': [-1524, -772],
    'vision': [-817, -858],
    'vfilter': [-1052, -886],
    'vmatch': [-817, -1028],
    'smallcup': [-582, -838],
    'fetch': [-1062, -546],
    'fetchfast': [-1298, -574],
    'fetchgold': [-1196, -394],
    'shorter': [-1534, -602],
    'harness': [-1432, -424],
    'pro_full': [-1288, -914],
    'godfeast': [-1524, -942],
    'longctx': [-1288, -1084],
    'waitlist': [-1524, -1112],
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
    if nid == "skills":
        cost = 5   # Preserve the reviewed low-cost first automation unlock.
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
    if "require_all" in flags:
        n["require_all"] = True
    nodes.append(n)
for (nid, d, l, name, opens, cost, ri, parents, desc) in TICKETS:
    n = {"id": nid, "kind": "ticket", "opens": opens, "name": name, "desc": DESC.get(nid, desc), "pos": pos("version", d, l),
         "parents": parents, "max": 1, "cost": cost, "growth": 1, "effects": {}}
    if ri:
        n["ring"] = ri
    nodes.append(n)

if {n["id"] for n in nodes} != set(BOARD_POSITIONS):
    raise ValueError("Node IDs changed: review BOARD_POSITIONS explicitly before generation")
if {n["id"] for n in nodes} != set(SUMMARY):
    raise ValueError("Node IDs changed: author a short ticket effect for every node")
for n in nodes:
    n["pos"] = list(BOARD_POSITIONS[n["id"]])
    n["summary"] = SUMMARY[n["id"]]
left = sum(1 for i, a in enumerate(nodes) for b in nodes[i + 1:]
           if ((a["pos"][0] - b["pos"][0]) / TICKET[0]) ** 2 + ((a["pos"][1] - b["pos"][1]) / TICKET[1]) ** 2 < 0.8)
print("overlaps left:", left, "· extent:", max(max(abs(n["pos"][0]), abs(n["pos"][1])) for n in nodes))
doc = ("技能树数据，由 pipeline/build_tree.py 生成（别手改）。模型见 docs/tree_model.md。ring 是节点所属的版本环（0 = V3，1 = R1，2 = V3.1，3 = V3.2，4 = V4，5 = V4.1 Flash，6 = V4.1 Flash-1017，7 = V4.1 Pro），"
       "版本发布前这一环不显示；kind=ticket 是门票节点，opens 是它开放的评测；key 是开一种新赚钱方式的节点。pos 是相对树中心的坐标（像素）；"
       "parents 默认任意一个父节点买过即可；require_all 为 true 时须全部买过。位置独立于前置关系，固定在生成器 BOARD_POSITIONS；"
       "cost = cost × growth^当前等级（token）；effects 每升一级叠加一次：add 加法，mul 乘法。可用属性见 game.gd 的 BASE。")
json.dump({"_doc": doc, "nodes": nodes}, open(OUT, "w", encoding="utf-8", newline="\n"), ensure_ascii=False, indent=1)
print(len(nodes), "nodes ->", OUT)
