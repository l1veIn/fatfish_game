"""Reproduce arithmetic and legal skill examples; never writes gameplay/save data.

Run the isolated Godot rule probe first, then python docs/build-archetypes-calculations.py.
Inputs: menu/tree JSON and engine-report.json; output lives in build/qa/player-build-analysis.
Cost examples exclude already-owned release tickets/review fees and do not predict scores.
"""
from pathlib import Path
import hashlib
import json
import math

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "build/qa/player-build-analysis"
tree = json.loads((ROOT / "game/data/skill_tree.json").read_text(encoding="utf8"))
nodes = {n["id"]: n for n in tree["nodes"]}
menu = json.loads((ROOT / "game/data/menu.json").read_text(encoding="utf8"))
engine = json.loads((OUT / "engine-report.json").read_text(encoding="utf8"))
assert engine["failures"] == 0
snapshot = json.loads((OUT / "save-snapshot.json").read_text(encoding="utf8"))


def price(levels):
    return sum(math.floor(nodes[k]["cost"] * nodes[k]["growth"] ** i)
               for k, lv in levels.items() for i in range(lv)
               if nodes[k].get("kind") != "ticket")


def legalize(desired):
    """Add one rank of a cheapest missing ANY parent. Never fabricates a closed stall."""
    levels = {"start": 1, **desired}
    while True:
        changed = False
        for k in list(levels):
            parents = nodes[k]["parents"]
            if parents and not any(levels.get(p, 0) > 0 for p in parents):
                levels[min(parents, key=lambda p: nodes[p]["cost"])] = 1
                changed = True
        if not changed:
            break
    for k, lv in levels.items():
        assert 0 < lv <= nodes[k]["max"] and nodes[k].get("ring", 0) <= 4
        assert not nodes[k]["parents"] or any(levels.get(p, 0) for p in nodes[k]["parents"])
    return levels


def stats(levels):
    out = {}
    for k, base in engine["base_stats"].items():
        val, mul = base, 1
        for node_id, lv in levels.items():
            e = nodes[node_id]["effects"].get(k, {})
            val += e.get("add", 0) * lv
            mul *= e.get("mul", 1) ** lv
        out[k] = val * mul
    return out


def available(st, banned):
    return {sid: [f["id"] for f in menu["foods"] if f.get("stall") == sid
                  and f["level"] <= st["stall_" + sid] and f["id"] not in banned]
            for sid in menu["stalls"] if st["stall_" + sid] > 0}


common = dict(eat=10, vram=2, mat=3, ocr=3, fill=1, conc=3, api=3,
              batch=2, peak=2, sft=4, dpo=2, lora=1, stream=3,
              ttft=2, mtp=4, lunch=3, rlhf=3, menu=4, moe=3)
examples = {
    "rotation_platters": {
        "name": "包子/鸡腿分餐轮换", "levels": {**common, "stall_dim":1,"stall_fry":1,
            "prompt":3,"multiturn":3,"memory":2,"moe":2},
        "bans":["youtiao","fries"], "signatures":["ball","congee"],
        "note":"One-cell buns and legs avoid the 2x3-bowl packing trap; at V3.1 memory unlocks rotation."},
    "warm_finale": {
        "name":"神级大餐保温收尾", "levels":{**common,"stall_main":1,"stall_dim":2,
            "stall_fry":1,"stall_sweet":3,"prompt":3,"fewshot":3,"agentwf":2,
            "agirec":1,"rag":1,"compress":1,"cot":1,"busy":5,"queue":2,
            "multiturn":1,"warm":1,"final":2,"eos":3},
        "bans":["ball","mantou","pudding","shuangpi"],
        "signatures":["congee","milktea","soymilk"],
        "note":"Deep recipe focus. No Best-of-N or Skills: reserve only chosen box and avoid forced full-box delivery."},
    "balanced_review": {
        "name":"均衡与菜谱评鉴", "levels":{**common,"stall_main":2,"stall_wok":2,
            "stall_dim":3,"stall_fry":2,"stall_sweet":1,"prompt":3,"fewshot":3,
            "agentwf":2,"compress":1,"cot":1,"critic":1,"bench":2,"constit":1,
            "rlhf":4,"grok":1,"warmup":3},
        "bans":["potato","pork","bun","fries"],
        "signatures":["congee","soymilk","milktea"],
        "note":"Bans preserve nine explicitly listed attainable recipes; collect recipes by eating, not merely crafting."},
    "helpers_salvage": {
        "name":"助手分工与收摊兜底", "levels":{**common,"stall_main":2,"stall_wok":2,
            "stall_dim":2,"stall_fry":2,"stall_sweet":1,"skills":1,"hire":5,
            "orch":2,"fc":1,"nutri":1,"clip":1,"async":1,"sleep":1,"busy":3,
            "queue":2,"compress":1,"prompt":2,"fewshot":2,"agentwf":1},
        "bans":["veg","egg","bowl","mantou"],
        "signatures":["congee","soymilk","milktea"],
        "note":"Keep potato and fries as edible vegetables; nutrition can prioritize them while avoiding pre-grok greens. Prioritizes comfort/catch coverage, not proven peak score."},
    "hot_mutation": {
        "name":"高温变菜与随机合成", "levels":{**common,"stall_wok":1,"stall_dim":2,
            "stall_fry":1,"stall_sweet":1,"temp":4,"hot":3,"halluc":2,"hodge":1,
            "prompt":2,"fewshot":3,"agentwf":2,"agirec":1,"compress":1,"rag":1},
        "bans":["veg","mantou","bowl","youtiao"],
        "signatures":["congee","soymilk","milktea"],
        "note":"Mutation can reach higher-level dishes without opening that stall level. No overfit/fuse/regen by default. Emergence is an expensive separate upgrade, not assumed."},
}
result = {"scope":"Arithmetic and legal purchase examples; no score forecast or proof of player execution", "examples":{}}
for key, data in examples.items():
    lv = legalize(data["levels"])
    st = stats(lv)
    pools = available(st, data["bans"])
    assert all(pools.values()), (key, "would empty a stall")
    raw = available(st, [])
    assert len(data["bans"]) <= st["menu_cut"]
    assert all(any(b in pool for pool in raw.values()) for b in data["bans"])
    assert len(data["signatures"]) <= st["sig_slots"]
    for sig in data["signatures"]:
        assert sig not in data["bans"] and any(sig in p for p in pools.values())
    result["examples"][key] = {**data,"levels":lv,"skill_cost_excluding_release_tickets":price(lv),
        "effective_stall_levels":{s:int(st["stall_"+s]) for s in menu["stalls"]},
        "food_pools":pools,"stats":st,
        "first_mechanic_ring":max(nodes[x].get("ring",0) for x in data["levels"])}

s = engine["snapshot"]["stats"]
p_good, p_gold = .43, .6
mean_grade = 1-p_good + p_good*(1-p_gold)*2 + p_good*p_gold*5
crit = 1 + s["crit_chance"]*(s["crit_mult"]-1)
stream = lambda n: min(6.5, 1+s["stream"]*math.log2(1+max(n-20,0)/20))
pool = 1+s["box_bonus"]+s["fill_bonus"]+s["mono_bonus"]
arm_counts = {"dim":2,"wok":2,"main":2,"fry":1,"sweet":1}
rates = {}
for peak in [False, True]:
    scoop_rates = {sid: count/(2.15/(menu["stalls"][sid]["speed"]*s["throw_rate"]*(2.5 if peak else 1))+.45)
                   for sid,count in arm_counts.items()}
    rates["peak" if peak else "normal"] = {"scoops_per_world_second":scoop_rates,
        "green_items_per_world_second":scoop_rates["wok"]*(2+s["batch"])+sum(scoop_rates.values())*s["veg_std"]}
result["green_math"] = {"normal_probability":1-p_good,"silver_probability":p_good*(1-p_gold),
    "gold_probability":p_good*p_gold,"mean_grade_mult_before_fusion":mean_grade,
    "mean_green_item_before_fusion":14*mean_grade,"with_mtp":14*mean_grade+4,
    "crit_expected_multiplier":crit,"pool":pool,"max_chain_snapshot":2.2,
    "eat_units_per_world_second":s["eat_rate"],
    "stream_multipliers":{str(n):stream(n) for n in [20,100,200,600,1000]},
    "stream_6_5_required_paid_bites":math.ceil(20+20*(2**(5.5/s["stream"])-1)),
    "gold_green_bite_at_200_expected_crit_no_crave_no_meal":(70+4)*stream(200)*pool*2.2*3*crit,
    "mean_green_bite_at_200_pre_fusion_expected_crit_no_crave_no_meal":(14*mean_grade+4)*stream(200)*pool*2.2*3*crit,
    "supply_renewal_approximation":rates,
    "approx_green_thrown_49_normal_56_peak_world_seconds":49*rates["normal"]["green_items_per_world_second"]+56*rates["peak"]["green_items_per_world_second"],
    "supply_caveat":"Steady renewal approximation. Ignores initial timer, phase crossing, frame quantization, MAX_ITEMS and miss/spill/crew; thrown is not caught or eaten.",
    "current_skill_cost_excluding_release_tickets":price({k:int(v) for k,v in snapshot["levels"].items()})}

def balance(cats, maximum=2.75, exponent=1.5, drinks=0):
    total=sum(cats)
    score=max(0,min(1,1-sum(abs(a/total-b) for a,b in zip(cats,[.4,.3,.3]))/1.2))
    return 1+(maximum-1)*score**exponent+min(.5,drinks*.04)

result["balance_math"]={"all_green_without_drift":balance([0,0,100]),
    "all_green_with_drift":balance([0,50,50]), "40_starch_60_drift_greens":balance([40,30,30]),
    "balanced_plus_13_signature_drinks":balance([40,30,30],drinks=13),
    "review_5_8_9_12_types_bench2":{str(n):1+.08*max(n-4,0) for n in [5,8,9,12]},
    "balanced_review9_max_rlhf4_plus_drinks":3.5*1.4}
result["mutation_math"]={"assumed_good":.32+.03*4,"assumed_gold_conditional":.4,
    "temp4_proc_probability":.32,"halluc2_probability":.16,
    "hot3_multiplier":2.25,"egg_to_pork_same_quality_expected_value_mult_no_protection":(.68*3+.32*5*2.25)/3,
    "pudding_to_shuangpi_same_quality_expected_value_mult_no_protection":(.68*3+.32*4*2.25)/3,
    "emergence_additional_cost":nodes["emerge"]["cost"],
    "emergence_qualifying_check_probability":.25,
    "emergence_3_5_8_qualifying_checks_probability":{str(n):1-.75**n for n in [3,5,8]},
    "caveat":"Eligible-temperature branch only; closest-recipe protection may suppress transformation. Emergence checks are not guaranteed every catch; hot items may already merge."}
result["hashes"]={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [
    ROOT/"docs/build-archetypes-calculations.py",ROOT/"game/data/menu.json",ROOT/"game/data/skill_tree.json",
    OUT/"save-snapshot.json",OUT/"engine-report.json"]}
output=OUT/"arithmetic-report.json"
output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+"\n",encoding="utf8")
print("BUILD_ARCHETYPES_ARITHMETIC PASS; five legal alternate examples plus player snapshot")
for key,d in result["examples"].items():
    print(key, d["skill_cost_excluding_release_tickets"],d["effective_stall_levels"])
print(json.dumps(result["green_math"],ensure_ascii=True,indent=2))
