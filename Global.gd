extends Node

signal any_button_pressed
signal py_awarded(amount: int, reason: String)
signal streak_milestone_reached(days: int)
signal quest_completed(quest: Dictionary)
signal badge_earned(badge: Dictionary)
signal item_equipped
signal food_discovered(food_id: String)

var _discovery_counter: int = 0
var _next_discovery_at: int = 0 

var discovered_foods: Array = []   

var consecutive_logging_days: int = 0

var last_report_date: String = ""

var py_earned_today: int = 0

var py_currency: int = 0
var today_quests: Array = []      # [{id, description, target, progress, completed, pts, gems}]
var completed_quest_ids: Array = []
var quest_date: String = ""
var gems: int = 0                 # accumulated gem currency

var earned_badges: Array = []   # list of badge ids

var base_kcal_goal: float = 0.0  # always the raw tdee-adjusted goal, never modified
var adjusted_kcal_goal: float = 0.0
# ── Body metrics (set from SettingsPage) ──
var body_metrics: Dictionary = {
	"bmr": 0.0,
	"tdee": 0.0,
	"daily_goal": 0.0,
	"goal_weight": 0.0,
	"weight": 0.0,
	"bmi_text": "BMI: —",
	"is_female": false,
	"adjusted_kcal_goal": 0.0
}

var use_fahrenheit: bool = false
# ── Kidney/oxalate conditions ──
var active_conditions: Array = []
var kidney_at_risk: bool = false

# ── Metabolic conditions (Tier 1) ──
var active_metabolic_conditions: Array = []
var known_diagnoses: Array = []  # only manually checked boxes
# Possible values:
# "glycemic-health", "nafld", "lipid-health",
# "thyroid-health", "osteoporosis",
# "hemochromatosis", "wilsons-disease"

var daily_water_liters: float = 2.5  # default, recalculated based on conditions

var hide_red_warnings: bool = false

var tooth_remove_staining: bool = false
var tooth_warn_staining: bool = false
#var tooth_staining_data: Dictionary = {}  # keyed by food id

var paro_remove: bool = false
var paro_warn: bool = false

var metabolic_risk_levels: Dictionary = {}
var conditions_data: Dictionary = {}

var daily_streak: int = 0
var last_streak_date: String = ""
var streak_freeze_count: int = 1  # starts with 1 free freeze
var _last_celebrated_milestone: int = 0

var ALL_BADGES = [
	 #── Streak badges ──
	{"id":"streak_3",    "name":"Spark 🔥",        "desc":"3-day streak",            "tier":"bronze", "check": func(g): return g.daily_streak >= 3},
	{"id":"streak_7",    "name":"Flame 🔥🔥",      "desc":"7-day streak",            "tier":"silver", "check": func(g): return g.daily_streak >= 7},
	{"id":"streak_30",   "name":"Inferno 🌋",       "desc":"30-day streak",           "tier":"gold",   "check": func(g): return g.daily_streak >= 30},
	{"id":"streak_100",  "name":"Solar ☀️",         "desc":"100-day streak",          "tier":"gold",   "check": func(g): return g.daily_streak >= 100},
	{"id":"streak_365",  "name":"Eternal ✨",        "desc":"365-day streak",          "tier":"gold",   "check": func(g): return g.daily_streak >= 365},
	# ── Water badges ──
	{"id":"hydro_7",     "name":"Hydration Hero 💧","desc":"Hit water goal 7 days in a row","tier":"silver","check": func(g): return g.daily_streak >= 7},
	# ── Nutrition badges ──
	{"id":"iron_chef",   "name":"Planner 🏆",       "desc":"Save 5 meals",            "tier":"bronze", "check": func(g): return true},  # checked externally
	{"id":"rainbow",     "name":"Rainbow Plate 🌈", "desc":"Eat 6 categories in one day","tier":"silver","check": func(g): return true},
	{"id":"bone_builder","name":"Bone Builder 🦴",  "desc":"30 days hitting Ca+VitD", "tier":"gold",   "check": func(g): return true},
	{"id":"brain_food",  "name":"Brain Food 🧠",    "desc":"7 days of Omega-3+B12",   "tier":"silver", "check": func(g): return true},
	# ── Condition badges ──
	{"id":"ox_warrior",  "name":"Oxalate Warrior 🌿","desc":"14 days under oxalate threshold","tier":"gold","check": func(g): return true},
	{"id":"data_driven", "name":"Data Driven 📊",   "desc":"Fill in all disease panels","tier":"bronze","check": func(g): return g.active_metabolic_conditions.size() >= 3},
	# ── Currency badges ──
	{"id":"py_100",      "name":"Earner 💰",        "desc":"Earn 100 PY",             "tier":"bronze", "check": func(g): return g.py_currency >= 100},
	{"id":"py_1000",     "name":"Wealthy 💎",       "desc":"Earn 1000 PY",            "tier":"gold",   "check": func(g): return g.py_currency >= 1000},
]

const FOODS_TO_AVOID_NOTES = {
	"epi": "⚠️ FAT MUST NOT BE RESTRICTED when using PERT (enzyme replacement therapy). Fat restriction worsens malnutrition and accelerates nutritional deficiency.",
	"post-cholecystectomy": "⚠️ In the first 3 months after gallbladder removal, keep fat under 13g per meal. Gradually liberalize to normal after 3 months.",
	"hemochromatosis": "⚠️ WITH MEALS: Use tea, coffee, dairy or eggs to inhibit iron absorption. Tannins and calcium compete with iron — use this to your advantage.",
	"crohns-disease": "⚠️ During FLARES: avoid raw vegetables, whole nuts and seeds, and high-fiber foods. During REMISSION: increase fiber to 30–48g/day.",
	"graves-disease": "⚠️ Soy can interfere with antithyroid medications. Separate by at least 4 hours from any medication dose.",
}

const FOODS_TO_AVOID = {
	"graves-disease": {
		"strict_avoid": [
			"Seaweed (all: kelp, nori, wakame, spirulina, kombu)",
			"Iodine supplements of any kind",
			"Iodized salt in excess",
			"High-iodine seafood in large amounts (oysters, shrimp)",
			"Excessive caffeine (>2 cups coffee/day)",
			"All alcohol",
			"Soy in excess if on antithyroid drugs",
		],
		"limit": [
			"Raw cruciferous vegetables (large amounts)",
			"Very high-fiber foods if diarrhea present",
			"Excessive refined sugar",
		]
	},
	"thyroid-health": {  # Hashimoto's
		"strict_avoid": [
			"Seaweed/kelp supplements (excess iodine worsens autoimmunity)",
			"Iodine supplements >300 mcg/day",
			"Ultra-processed foods",
			"Millet in large amounts (goitrogenic)",
			"Cassava in large amounts",
			"All alcohol",
		],
		"limit": [
			"Raw cruciferous vegetables in very large amounts",
			"Soy near levothyroxine dose (separate by 4 hours)",
			"High omega-6 oils (corn, soybean, sunflower) in excess",
			"Refined sugar and simple carbohydrates",
			"Selenium >400 mcg/day (selenosis risk)",
		]
	},
	"celiac-disease": {
		"strict_avoid": [
			"ALL wheat (durum, spelt, kamut, einkorn, emmer, farro)",
			"Barley — all forms",
			"Rye — all forms",
			"Triticale",
			"Conventional oats (cross-contamination; use certified GF oats only)",
			"Malt, malt vinegar, malt flavoring, brewer's yeast",
			"Regular beer, ale, lager, malt beverages",
			"Traditional soy sauce (wheat-based)",
			"Shared fryers / cooking surfaces with gluten foods",
		],
		"limit": [
			"GF processed products (often high sugar/fat; nutritionally inferior)",
			"Gluten-containing medications/supplements (check all labels)",
		]
	},
	"hemochromatosis": {
		"strict_avoid": [
			"Red meat in excess (beef, lamb, venison, pork) — highest heme iron",
			"Organ meats (liver, kidney, heart, blood pudding)",
			"Raw shellfish (Vibrio vulnificus risk; lethal with iron overload)",
			"Vitamin C supplements >250 mg",
			"Iron-containing multivitamins and supplements",
			"Cast iron cookware for acidic foods (tomatoes, citrus)",
			"Iron-fortified cereals and breads",
			"Excess alcohol (liver damage; enhances iron absorption)",
		],
		"inhibitors_to_use_with_meals": [
			"Tea (black or green) — reduces iron absorption 40–60%",
			"Coffee — chlorogenic acid reduces absorption",
			"Dairy/calcium with meals — competes with iron",
			"Whole grains and legumes (phytates bind iron)",
			"Eggs with iron-rich meals (phosvitin binds iron)",
		]
	},
	"crohns-disease": {
		"strict_avoid": [
			"Raw vegetables during flares (carrots, celery, corn, raw cruciferous)",
			"Whole nuts and seeds during flares",
			"Fried and fatty foods",
			"All alcohol (pro-inflammatory; increases permeability)",
			"Ultra-processed foods and emulsifiers (CMC, polysorbate-80)",
			"Red and processed meats",
			"Raw shellfish (infection risk during immunosuppression)",
		],
		"limit": [
			"Lactose if intolerant (25–40% of CD patients)",
			"Spicy foods",
			"Caffeinated beverages if diarrhea present",
			"High-FODMAP foods if IBS-CD overlap",
			"Oxalate-rich foods if ileal disease (kidney stone risk)",
			"Refined sugars (promote dysbiosis)",
		]
	},
	"nafld": {
		"strict_avoid": [
			"All alcohol (directly hepatotoxic; accelerates fibrosis)",
			"Added fructose and HFCS (sugary beverages, pastries)",
			"Trans fats (commercially baked goods, fried fast food)",
			"Ultra-processed foods",
			"Sugary beverages (even one soda/day increases NAFLD risk)",
		],
		"limit": [
			"Saturated fat (fatty meats, full-fat dairy)",
			"Red and processed meats (heme iron causes oxidative stress in liver)",
			"Refined carbohydrates",
			"Excess omega-6 oils (corn, soybean, sunflower)",
			"Large high-calorie meals in one sitting",
		]
	},
	"glycemic-health": {
		"strict_avoid": [
			"Sugary beverages (soda, fruit juice, energy drinks)",
			"Trans fats (commercial baked goods)",
			"Ultra-processed foods",
			"Heavy alcohol use",
		],
		"limit": [
			"High GI foods (white bread, white rice, instant oatmeal, potatoes)",
			"Added sugars (white sugar, honey, agave)",
			"Saturated fat in excess (worsens insulin resistance)",
			"Dried fruits in large amounts",
			"Refined white flour products",
		]
	},
	"lipid-health": {
		"strict_avoid": [
			"Trans fats — NO safe level (partially hydrogenated oils, stick margarine, fried fast food)",
			"Tropical oils in excess (coconut oil 93% SFA, palm kernel oil 82% SFA)",
		],
		"limit": [
			"Saturated fats (butter, lard, fatty meats, full-fat dairy)",
			"Refined carbohydrates (raise TG dramatically)",
			"Added sugars and fructose (elevate VLDL and TG)",
			"Alcohol (>1 drink F / >2 drinks M): dramatically elevates TG",
			"Processed meats (salami, hot dogs: high SFA + sodium)",
		]
	},
	"epi": {
		"strict_avoid": [
			"All alcohol (primary cause of chronic pancreatitis)",
			"Very high-fat single meals WITHOUT adequate PERT",
		],
		"limit": [
			"High-sugar foods (risk of pancreatogenic diabetes)",
			"Carbonated beverages (exacerbate bloating)",
			"Raw vegetables in large amounts (increase gas)",
			"Excessive caffeine",
		],
		"important_note": "FAT MUST NOT BE RESTRICTED when PERT is used. Fat restriction worsens malnutrition."
	},
	"post-cholecystectomy": {
		"strict_avoid": [
			"High-fat meals in early phase (>13 g fat/meal for first 3 months)",
			"Fried and deep-fried foods",
			"All alcohol (stimulates bile, worsens reflux)",
			"Trans fats",
		],
		"limit": [
			"Full-fat dairy",
			"Processed meats",
			"Cream-based sauces",
			"Carbonated beverages (if causing reflux)",
			"Caffeinated beverages (if reflux present)",
			"Chocolate",
			"Raw onions and garlic",
			"Tomato-based foods if reflux",
			"Spicy foods",
			"Mint (relaxes LES, worsens reflux)",
		]
	},
}

const BADGE_TIER_COLORS = {
	"bronze": Color(0.80, 0.50, 0.20),
	"silver": Color(0.75, 0.75, 0.80),
	"gold":   Color(1.00, 0.85, 0.00),
}

const LEAGUE_NAMES = ["🥉 Bronze", "🥈 Silver", "🥇 Gold", "💎 Diamond", "🏆 Legendary"]
const LEAGUE_THRESHOLDS = [0, 100, 500, 2000, 10000]  # all-time points to reach each

const SEASONS = [
	{
		"name":        "Nordic Health Challenge",
		"emoji":       "❄️",
		"months":      [12, 1, 2],
		"desc":        "Winter season — bonus points for eating traditional Nordic foods.",
		"bonus_foods": ["herring", "salmon", "rye", "blueberry", "lingonberry"],
		"bonus_field": "",
		"bonus_pts":   2
	},
	{
		"name":        "Spring Detox Season",
		"emoji":       "🌿",
		"months":      [3, 4, 5],
		"desc":        "Spring — bonus points for green vegetables and low-oxalate days.",
		"bonus_foods": [],
		"bonus_field": "vitamin_c_mg",
		"bonus_threshold": 100.0,
		"bonus_pts":   2
	},
	{
		"name":        "Hydration Championship",
		"emoji":       "💧",
		"months":      [6, 7, 8],
		"desc":        "Summer — doubled water points.",
		"bonus_foods": [],
		"bonus_field": "water_ml",
		"bonus_threshold": 3000.0,
		"bonus_pts":   2
	},
	{
		"name":        "Harvest Festival",
		"emoji":       "🍂",
		"months":      [9, 10, 11],
		"desc":        "Autumn — bonus points for root vegetables and high fiber.",
		"bonus_foods": ["carrot","beetroot","parsnip","sweet-potato","potato"],
		"bonus_field": "fiber_g",
		"bonus_threshold": 30.0,
		"bonus_pts":   2
	},
]

var current_league_idx: int = 0
var league_weekly_pts: int  = 0
var league_week_start: String = ""
var a = get_sat_fat_limit_g()
var metabolic_warnings_data = {

	# ── Glycemic / T2DM ──────────────────────────────────────────────────
	"glycemic-health": {
		"label": "Glycemic Health",
		"field": "sugar_g",
		"avoid": 5.0,
		"avoid_msg": "High sugar. Not recommended for diabetes/prediabetes."
	},
	"glycemic-health-sat-fat": {
		"label": "Glycemic Health",
		"field": "saturated_fat_g",
		"avoid": get_sat_fat_limit_g()
		#"avoid_msg": "High saturated fat. Avoid — promotes insulin resistance."
	},

	# ── NAFLD / MASLD ─────────────────────────────────────────────────────
	"nafld": {
		"label": "NAFLD",
		"field": "sugar_g",
		"avoid": 7.0,
		"avoid_msg": "High sugar. Drives hepatic fat accumulation."
	},
	"nafld-fat": {
		"label": "NAFLD",
		"field": "saturated_fat_g",
		"avoid": get_sat_fat_limit_g()
	},
	"nafld-iron": {
		"label": "NAFLD",
		"field": "iron_mg",
		"caution": 4.0, "avoid": 8.0,
		"caution_msg": "Moderate iron — monitor ferritin; iron overload worsens NAFLD.",
		"avoid_msg": "High iron. Avoid supplements; excess iron worsens NASH."
	},

	# ── Lipid Health / Dyslipidemia ───────────────────────────────────────
	"lipid-health": {
		"label": "Lipid Health",
		"field": "saturated_fat_g",
		"avoid": get_sat_fat_limit_g()
		
	},
	"lipid-health-sugar": {
		"label": "Lipid Health (TG)",
		"field": "sugar_g",
		"caution": 5.0, "avoid": 10.0,
		"caution_msg": "Sugar raises triglycerides. Limit with dyslipidemia.",
		"avoid_msg": "High sugar. Significantly elevates triglycerides — avoid."
	},

	# ── Hemochromatosis ───────────────────────────────────────────────────
	"hemochromatosis": {
		"label": "Hemochromatosis",
		"field": "iron_mg",
		"caution": 3.0, "avoid": 6.0,
		"caution_msg": "Moderate iron content. Limit with iron overload.",
		"avoid_msg": "High iron. Avoid — worsens iron overload."
	},
	"hemochromatosis-vitamin_c": {
		# Note: This warns when vitamin_c is HIGH (supplements enhance iron absorption)
		# For food-based vitamin C this is less critical; mainly warn on very high values
		"label": "Hemochromatosis",
		"field": "vitamin_c_mg",
		"caution": 80.0, "avoid": 200.0,
		"caution_msg": "High vitamin C enhances iron absorption. Take between meals, not with iron-rich foods.",
		"avoid_msg": "Very high vitamin C. Significantly increases iron absorption — avoid supplements."
	},
	"hemochromatosis-sugar": {
		"label": "Hemochromatosis",
		"field": "sugar_g",
		"caution": 8.0, "avoid": 15.0,
		"caution_msg": "Sugar/fructose increases non-heme iron absorption. Limit with hemochromatosis.",
		"avoid_msg": "High sugar. Fructose promotes iron absorption — avoid with iron overload."
	},

	# ── Wilson's Disease ─────────────────────────────────────────────────
	"wilsons-disease": {
		"label": "Wilson's Disease",
		"field": "copper_mg",
		"caution": 0.3, "avoid": 0.5,
		"caution_msg": "Moderate copper. Limit with Wilson's disease.",
		"avoid_msg": "High copper. Avoid — toxic with Wilson's disease."
	},

	# ── Osteoporosis ─────────────────────────────────────────────────────
	"osteoporosis-sodium": {
		"label": "Osteoporosis",
		"field": "sodium_mg",
		"caution": 300.0, "avoid": 600.0,
		"caution_msg": "Moderate sodium — can increase calcium loss.",
		"avoid_msg": "High sodium. Avoid — significantly increases calcium loss."
	},

	# ── Sulfur Avoidance ─────────────────────────────────────────────────
	"sulfur-avoidance": {
		"label": "Sulfur Avoidance",
		"field": "sulfur_mg",
		"caution": 80.0, "avoid": 150.0,
		"caution_msg": "Moderate sulfur content — may cause gas/bloating.",
		"avoid_msg": "High sulfur food — avoid if sensitive to sulfur compounds."
	},

	# ── Crohn's Disease ───────────────────────────────────────────────────
	# IMPORTANT: fiber thresholds during FLARE only.
	# During remission fiber should be INCREASED. The app needs a flare/remission toggle.
	"crohns-disease-fiber": {
		"label": "Crohn's Disease (Flare)",
		"field": "fiber_g",
		"caution": 2.0, "avoid": 4.0,
		"caution_msg": "Moderate fiber — limit during active flares.",
		"avoid_msg": "High fiber — avoid during Crohn's flares or with strictures."
	},
	"crohns-disease-fat": {
		"label": "Crohn's Disease",
		"field": "fat_g",
		"caution": 15.0, "avoid": 25.0,
		"caution_msg": "Moderate fat — may worsen diarrhea in ileal Crohn's.",
		"avoid_msg": "High fat content — avoid during active Crohn's disease."
	},

	# ── Celiac Disease ───────────────────────────────────────────────────
	"celiac-disease": {
		"label": "Celiac Disease",
		"field": "contains_gluten",
		"caution": 0.5, "avoid": 0.5,
		"caution_msg": "Contains gluten — avoid with celiac disease.",
		"avoid_msg": "Contains gluten — strictly avoid with celiac disease."
	},

	# ── Lactose Intolerance ───────────────────────────────────────────────
	"lactose-intolerance": {
		"label": "Lactose Intolerance",
		"field": "lactose_g",
		"caution": 3.0, "avoid": 6.0,
		"caution_msg": "Contains lactose — may cause discomfort. Limit portion.",
		"avoid_msg": "High lactose content — avoid or use lactase enzyme."
	},

	# ── EPI (Pancreatic Exocrine Insufficiency) ───────────────────────────
	# NOTE: Per PDF Disease 8 guidelines, fat should NOT be restricted when PERT is used.
	# The warning below should only appear if the user has NOT confirmed PERT usage.
	# Consider adding a "pert_active" flag to Global to suppress this warning.
	"epi": {
		"label": "Pancreatic Insufficiency",
		"field": "fat_g",
		"caution": 10.0, "avoid": 20.0,
		"caution_msg": "Moderate fat — take PERT with this meal. Fat is essential; do not restrict.",
		"avoid_msg": "High fat content — ensure adequate PERT dosing. Fat should not be restricted."
	},

	# ── Post-Cholecystectomy ──────────────────────────────────────────────
	"post-cholecystectomy": {
		"label": "Post-Cholecystectomy",
		"field": "fat_g",
		"caution": 8.0, "avoid": 15.0,
		"caution_msg": "Moderate fat — eat small portions, chew slowly.",
		"avoid_msg": "High fat — may cause diarrhea post-cholecystectomy. Split into smaller meals."
	},
	"post-cholecystectomy-sat-fat": {
		"label": "Post-Cholecystectomy",
		"field": "saturated_fat_g",
		"avoid": get_sat_fat_limit_g()
		#"avoid_msg": "High saturated fat — significantly worsens fat malabsorption."
	},

	# ── Hashimoto's / Thyroid ─────────────────────────────────────────────
	"thyroid-health-iodine": {
		# Warn when iodine is VERY HIGH (excess worsens autoimmunity)
		"label": "Hashimoto's Thyroiditis",
		"field": "iodine_mcg",
		"caution": 200.0, "avoid": 400.0,
		"caution_msg": "Moderate iodine content. Stay within RDA (150 mcg/day); avoid excess with Hashimoto's.",
		"avoid_msg": "Very high iodine. Excess iodine worsens thyroid autoimmunity — avoid seaweed/kelp/supplements."
	},

	# ── Graves' Disease (NEW) ─────────────────────────────────────────────
	"graves-disease-iodine": {
		"label": "Graves' Disease",
		"field": "iodine_mcg",
		"caution": 100.0, "avoid": 150.0,
		"caution_msg": "Contains iodine. With Graves' disease, iodine directly stimulates hormone production.",
		"avoid_msg": "High iodine — STRICTLY AVOID with Graves' disease. Can trigger thyroid storm."
	},
	"graves-disease-caffeine": {
		# Would need caffeine_mg field in food data
		"label": "Graves' Disease",
		"field": "caffeine_mg",
		"caution": 50.0, "avoid": 100.0,
		"caution_msg": "Contains caffeine — may worsen tachycardia and anxiety with hyperthyroidism.",
		"avoid_msg": "High caffeine — exacerbates Graves' disease symptoms."
	},
}


func calculate_water_recommendation() -> float:
	var is_female = body_metrics.get("is_female", false)
	var weight    = body_metrics.get("weight", 70.0)
	var egfr      = 0.0
	var c         = active_metabolic_conditions

	if FileAccess.file_exists("user://metabolic_inputs.json"):
		var file = FileAccess.open("user://metabolic_inputs.json", FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data and data.has("kidney"):
			egfr = data["kidney"].get("egfr", 0.0)

	var liters = 2.7 if is_female else 3.7  # baseline AI from NIH

	# ── CKD stage based on eGFR (KDIGO) ──────────────────────────────────
	if kidney_at_risk or egfr > 0:
		if egfr >= 90 or egfr == 0:
			liters = 2.5
		elif egfr >= 60:
			liters = 2.5
		elif egfr >= 30:
			liters = 2.0 if is_female else 3.0
		elif egfr >= 15:
			liters = 1.25
		else:
			liters = 1.0  # Stage 5 — strict restriction

	# ── Condition-specific recommendations ───────────────────────────────
	# Take the HIGHEST recommendation unless CKD restricts
	var recommendations: Array = []

	if c.has("graves-disease"):
		# Hypermetabolic state; significant fluid needs
		var risk = metabolic_risk_levels.get("graves-disease", "normal")
		if risk == "active":
			recommendations.append(5.0 if not is_female else 4.0)  # 3.5–5.0 L range
		else:
			recommendations.append(3.7 if not is_female else 3.0)

	if c.has("thyroid-health"):
		recommendations.append(3.7 if not is_female else 3.0)  # 2.5–3.7 L

	if c.has("crohns-disease"):
		var risk = metabolic_risk_levels.get("crohns-disease", "normal")
		if risk == "confirmed" or risk == "active":
			recommendations.append(4.25 if not is_female else 3.75)  # flare: 3.0–5.5 L
		else:
			recommendations.append(3.25 if not is_female else 2.85)  # remission

	if c.has("epi"):
		recommendations.append(3.75 if not is_female else 3.45)  # 3.0–4.5 L

	if c.has("celiac-disease"):
		recommendations.append(3.25 if not is_female else 2.9)   # 2.5–4.0 L

	if c.has("glycemic-health"):
		recommendations.append(3.7 if not is_female else 2.7)    # 2.5–3.7 L

	if c.has("nafld"):
		recommendations.append(1.75)  # 6–8 glasses = ~1.5–2 L

	if c.has("lipid-health"):
		recommendations.append(3.7 if not is_female else 2.7)

	if c.has("thyroid-health"):
		recommendations.append(3.1 if not is_female else 2.1)

	if c.has("osteoporosis"):
		recommendations.append(1.75)  # 6–8 glasses

	if c.has("post-cholecystectomy"):
		recommendations.append(3.0 if not is_female else 2.6)   # 2.5–3.5 L

	# Take the maximum unless CKD restricts
	if not recommendations.is_empty():
		var max_rec = recommendations.max()
		if not kidney_at_risk:
			liters = max(liters, max_rec)
		else:
			liters = min(liters, max_rec)  # CKD restricts

	return liters

func calculate_adjusted_kcal_goal() -> Dictionary:
	var base_goal = base_kcal_goal if base_kcal_goal > 0 else body_metrics.get("daily_goal", 0.0)
	var tdee      = body_metrics.get("tdee", 0.0)
	var bmr       = body_metrics.get("bmr", 0.0)
	var weight    = body_metrics.get("weight", 0.0)
	var bmi_text  = body_metrics.get("bmi_text", "")
	var is_female = body_metrics.get("is_female", false)

	if base_goal == 0 or bmr == 0:
		return {"adjusted_goal": 0.0, "adjustments": []}

	var adjusted  = base_goal
	var notes     = []
	var is_overweight = bmi_text.contains("Overweight") or bmi_text.contains("Obese")
	var is_obese      = bmi_text.contains("Obese")
	var is_underweight= bmi_text.contains("Underweight")
	var c = active_metabolic_conditions

	# ── NAFLD / MASLD (Disease 12) ────────────────────────────────────────
	if c.has("nafld"):
		if is_obese:
			adjusted -= 750.0
			notes.append("NAFLD (obese): −750 kcal/day (target ≥10% weight loss)")
		elif is_overweight:
			adjusted -= 500.0
			notes.append("NAFLD (overweight): −500 kcal/day (target 5–10% weight loss)")

	# ── T2DM / Glycemic Health (Disease 10) ──────────────────────────────
	if c.has("glycemic-health"):
		if is_obese:
			adjusted -= 625.0
			notes.append("T2DM (obese): −625 kcal/day; each 5% weight loss improves HbA1c")
		elif is_overweight:
			adjusted -= 500.0
			notes.append("T2DM (overweight): −500 kcal/day")

	# ── Lipid Health / Dyslipidemia (Disease 11) ─────────────────────────
	if c.has("lipid-health"):
		if is_obese:
			adjusted -= 625.0
			notes.append("Dyslipidemia (obese): −625 kcal/day; 5–10% loss: LDL↓10%, TG↓20–30%")
		elif is_overweight:
			adjusted -= 400.0
			notes.append("Dyslipidemia (overweight): −400 kcal/day")

	# ── Hashimoto's / Thyroid Health (Disease 2) ──────────────────────────
	if c.has("thyroid-health"):
		var thyroid_floor = bmr + 200.0
		if adjusted < thyroid_floor:
			adjusted = thyroid_floor
		notes.append("Thyroid: minimum " + str(snappedf(thyroid_floor, 0)) + " kcal (BMR+200)")
		# Subclinical: –5 to –10% vs TDEE; overt: –10 to –20% vs TDEE
		var risk = metabolic_risk_levels.get("thyroid-health", "normal")
		if risk == "hypothyroid" or risk == "hashimotos":
			var reduction = tdee * 0.15  # –15% as midpoint
			if adjusted > (base_goal - reduction):
				adjusted = max(base_goal - reduction, thyroid_floor)
				notes.append("Overt hypothyroid: −15% TDEE adjustment (reduced metabolic rate)")
		elif risk == "subclinical":
			var reduction = tdee * 0.075  # –7.5% as midpoint
			adjusted = max(base_goal - reduction, thyroid_floor)
			notes.append("Subclinical hypothyroid: −7.5% TDEE adjustment")

	# ── Graves' Disease (Disease 3) — NEW ────────────────────────────────
	if c.has("graves-disease"):
		var graves_risk = metabolic_risk_levels.get("graves-disease","normal")
		match graves_risk:
			"active":
				var extra = adjusted * 0.30 # +20-40% above TDEE — use +30% midpoint
				adjusted += extra
				notes.append("Graves' (active): +" + str(snappedf(extra,0)) + " kcal (hypermetabolism +30%)")
			"mild", "hyperthyroid-other":
				var extra = adjusted * 0.15
				adjusted += extra
				notes.append("Graves' (mild): +" + str(snappedf(extra,0)) + " kcal (+15% hypermetabolism)")
			"subclinical", "trab-positive-controlled":
				notes.append("Graves' (controlled): monitor kcal — no adjustment yet")

	# ── Osteoporosis ──────────────────────────────────────────────────────
	if c.has("osteoporosis"):
		if adjusted < bmr:
			adjusted = bmr
		notes.append("Osteoporosis: minimum BMR (" + str(snappedf(bmr, 0)) + " kcal)")

	# ── Hemochromatosis (Disease 9) ───────────────────────────────────────
	if c.has("hemochromatosis"):
		# No significant metabolic change; caloric needs = TDEE
		# Just ensure not below BMR
		if adjusted < bmr:
			adjusted = bmr
		# Note: no caloric adjustment noted in clinical PDF

	# ── Crohn's Disease (Disease 7) ───────────────────────────────────────
	if c.has("crohns-disease"):
		var risk = metabolic_risk_levels.get("crohns-disease", "normal")
		if risk == "confirmed" or risk == "active":
			# Active flare: +20–40% above TDEE midpoint = +30%
			var extra_kcal = tdee * 0.30
			adjusted += extra_kcal
			notes.append("Crohn's (active): +" + str(snappedf(extra_kcal, 0)) + " kcal (+30% TDEE; hyperinflammatory)")
		else:
			# Remission: = to +10% TDEE
			var extra_kcal = tdee * 0.05  # +5% midpoint
			adjusted += extra_kcal
			notes.append("Crohn's (remission): +" + str(snappedf(extra_kcal, 0)) + " kcal (+5% TDEE)")

	# ── Celiac Disease (Disease 6) — FIXED ───────────────────────────────
	# CRITICAL FIX: previous code SUBTRACTED 200 kcal which is WRONG.
	# Active CD requires MORE calories; stable GFD = TDEE.
	if c.has("celiac-disease"):
		var risk = metabolic_risk_levels.get("celiac-disease", "confirmed")
		if is_underweight:
			var extra_kcal = 600.0  # +400–800 midpoint
			adjusted += extra_kcal
			notes.append("Celiac (underweight): +" + str(extra_kcal) + " kcal; aggressive nutritional rehab")
		elif risk == "confirmed":
			# Newly diagnosed or active: +10–15% above TDEE
			var extra_kcal = tdee * 0.125
			adjusted += extra_kcal
			notes.append("Celiac (active/newly diagnosed): +" + str(snappedf(extra_kcal, 0)) + " kcal (+12.5% TDEE)")
		# Stable GFD >2 years: = TDEE (no adjustment)

	# ── Lactose Intolerance ───────────────────────────────────────────────
	if c.has("lactose-intolerance"):
		adjusted += 150.0
		notes.append("Lactose intolerance: +150 kcal dairy compensation")

	# ── EPI / Pancreatic Exocrine Insufficiency (Disease 8) ───────────────
	if c.has("epi"):
		# With PERT: 30–35 kcal/kg, +10–20% TDEE midpoint
		# Without PERT: +30–60% — user should indicate PERT status
		var epi_target = weight * 32.5  # 30–35 kcal/kg midpoint
		var pert_adjustment = tdee * 0.15  # +15% midpoint with PERT
		var epi_adjusted = max(epi_target, base_goal + pert_adjustment)
		adjusted = epi_adjusted
		notes.append("EPI: " + str(snappedf(adjusted, 0)) + " kcal (32.5 kcal/kg or +15% TDEE with PERT)")

	# ── Post-Cholecystectomy (Disease 1) ─────────────────────────────────
	if c.has("post-cholecystectomy"):
		if is_overweight:
			adjusted -= 200.0
			notes.append("Post-cholecystectomy: −200 kcal (weight management; raised obesity risk)")
		elif is_underweight:
			adjusted += 350.0
			notes.append("Post-cholecystectomy (underweight): +350 kcal; correct nutritional deficits")

	# ── Hard floor: never below BMR ───────────────────────────────────────
	if adjusted < bmr and bmr > 0:
		adjusted = bmr
		notes.append("⚠️ Floor enforced: goal cannot go below BMR (" + str(snappedf(bmr,0)) + " kcal) — this is your minimum safe intake")

	return {"adjusted_goal": snappedf(adjusted, 0.1), "adjustments": notes}

# ─────────────────────────────────────────
#  MICRONUTRIENT RDAs — sex-aware, condition-adjusted
#  Returns dict: { field_key: { "rda": float, "unit": String, "label": String } }
# ─────────────────────────────────────────
func get_micronutrient_rdas() -> Dictionary:
	var is_female = body_metrics.get("is_female", false)
	var age       = body_metrics.get("age", 35)  # NOTE: add "age" to body_metrics in save_body_metrics()
	var c         = active_metabolic_conditions

	# ── Determine age group ──
	# 0 = child (0-12), 1 = young (12-25), 2 = adult (25-45), 3 = middle (45-65), 4 = older (65+)
	var ag = 2  # default adult
	if   age < 12: ag = 0
	elif age < 25: ag = 1
	elif age < 45: ag = 2
	elif age < 65: ag = 3
	else:          ag = 4

	# ── Base RDAs — sex and age stratified (NIH DRI 2011–2023) ──
	# Format: [child, young, adult, middle, older]
	var vit_a_m   = [450.0, 900.0, 900.0, 900.0, 900.0]
	var vit_a_f   = [450.0, 700.0, 700.0, 700.0, 700.0]
	var vit_b1_m  = [0.7,   1.2,   1.2,   1.2,   1.2]
	var vit_b1_f  = [0.7,   1.0,   1.1,   1.1,   1.1]
	var vit_b2_m  = [0.7,   1.3,   1.3,   1.3,   1.3]
	var vit_b2_f  = [0.7,   1.0,   1.1,   1.1,   1.1]
	var vit_b3_m  = [9.0,   16.0,  16.0,  16.0,  16.0]
	var vit_b3_f  = [9.0,   14.0,  14.0,  14.0,  14.0]
	var vit_b5    = [3.0,   5.0,   5.0,   5.0,   5.0]
	var vit_b6_m  = [0.75,  1.3,   1.3,   1.7,   1.7]
	var vit_b6_f  = [0.75,  1.2,   1.3,   1.5,   1.5]
	var vit_b7    = [14.0,  27.5,  30.0,  30.0,  30.0]
	var vit_b9    = [225.0, 400.0, 400.0, 400.0, 400.0]
	var vit_b12_m = [1.35,  2.4,   2.4,   2.4,   2.4]
	var vit_b12_f = [1.35,  2.4,   2.4,   2.4,   2.4]
	var vit_c_m   = [30.0,  90.0,  90.0,  90.0,  90.0]
	var vit_c_f   = [30.0,  75.0,  75.0,  75.0,  75.0]
	var vit_d     = [15.0,  15.0,  15.0,  15.0,  20.0]
	var vit_e     = [8.5,   15.0,  15.0,  15.0,  15.0]
	var vit_k_m   = [45.0,  97.5,  120.0, 120.0, 120.0]
	var vit_k_f   = [45.0,  82.5,  90.0,  90.0,  90.0]
	var calcium_m = [1000.0,1300.0,1000.0,1000.0,1200.0]
	var calcium_f = [1000.0,1300.0,1000.0,1200.0,1200.0]
	var iron_m    = [8.5,   11.0,  8.0,   8.0,   8.0]
	var iron_f    = [8.5,   15.0,  18.0,  8.0,   8.0]
	var mag_m     = [160.0, 410.0, 420.0, 420.0, 420.0]
	var mag_f     = [160.0, 335.0, 315.0, 320.0, 320.0]
	var potassium_m = [2250.0,3200.0,3400.0,3400.0,3400.0]
	var potassium_f = [2150.0,2450.0,2600.0,2600.0,2600.0]
	var zinc_m    = [5.5,   11.0,  11.0,  11.0,  11.0]
	var zinc_f    = [5.5,   9.0,   8.0,   8.0,   8.0]
	var selenium  = [30.0,  55.0,  55.0,  55.0,  55.0]
	var iodine    = [105.0, 150.0, 150.0, 150.0, 150.0]
	var copper    = [520.0, 890.0, 900.0, 900.0, 900.0]
	var manganese_m = [1.7,  2.2,  2.3,  2.3,  2.3]
	var manganese_f = [1.4,  1.6,  1.8,  1.8,  1.8]
	var chromium_m  = [18.0, 35.0, 35.0, 35.0, 30.0]
	var chromium_f  = [16.0, 24.0, 25.0, 20.0, 20.0]

	var rdas: Dictionary = {
		"vitamin_a_mcg":        {"rda": vit_a_f[ag]   if is_female else vit_a_m[ag],   "unit":"mcg", "label":"Vitamin A"},
		"vitamin_b1_mg":        {"rda": vit_b1_f[ag]  if is_female else vit_b1_m[ag],  "unit":"mg",  "label":"Vitamin B1"},
		"vitamin_b2_mg":        {"rda": vit_b2_f[ag]  if is_female else vit_b2_m[ag],  "unit":"mg",  "label":"Vitamin B2"},
		"vitamin_b3_mg":        {"rda": vit_b3_f[ag]  if is_female else vit_b3_m[ag],  "unit":"mg",  "label":"Vitamin B3"},
		"vitamin_b5_mg":        {"rda": vit_b5[ag],                                    "unit":"mg",  "label":"Vitamin B5"},
		"vitamin_b6_mg":        {"rda": vit_b6_f[ag]  if is_female else vit_b6_m[ag],  "unit":"mg",  "label":"Vitamin B6"},
		"vitamin_b7_mcg":       {"rda": vit_b7[ag],                                    "unit":"mcg", "label":"Vitamin B7"},
		"vitamin_b9_mcg":       {"rda": vit_b9[ag],                                    "unit":"mcg", "label":"Folate (B9)"},
		"vitamin_b12_mcg":      {"rda": vit_b12_f[ag] if is_female else vit_b12_m[ag], "unit":"mcg", "label":"Vitamin B12"},
		"vitamin_c_mg":         {"rda": vit_c_f[ag]   if is_female else vit_c_m[ag],   "unit":"mg",  "label":"Vitamin C"},
		"vitamin_d_mcg":        {"rda": vit_d[ag],                                     "unit":"mcg", "label":"Vitamin D"},
		"vitamin_e_mg":         {"rda": vit_e[ag],                                     "unit":"mg",  "label":"Vitamin E"},
		"vitamin_k2_mcg":       {"rda": vit_k_f[ag]   if is_female else vit_k_m[ag],   "unit":"mcg", "label":"Vitamin K2"},
		"calcium_mg":           {"rda": calcium_f[ag]  if is_female else calcium_m[ag], "unit":"mg",  "label":"Calcium"},
		"iron_mg":              {"rda": iron_f[ag]     if is_female else iron_m[ag],    "unit":"mg",  "label":"Iron"},
		"magnesium_mg":         {"rda": mag_f[ag]      if is_female else mag_m[ag],     "unit":"mg",  "label":"Magnesium"},
		"potassium_mg":         {"rda": potassium_f[ag]if is_female else potassium_m[ag],"unit":"mg", "label":"Potassium"},
		"zinc_mg":              {"rda": zinc_f[ag]     if is_female else zinc_m[ag],    "unit":"mg",  "label":"Zinc"},
		"selenium_mcg":         {"rda": selenium[ag],                                   "unit":"mcg", "label":"Selenium"},
		"iodine_mcg":           {"rda": iodine[ag],                                     "unit":"mcg", "label":"Iodine"},
		"copper_mg":            {"rda": copper[ag] / 1000.0,                            "unit":"mg",  "label":"Copper"},
		"manganese_mg":         {"rda": manganese_f[ag]if is_female else manganese_m[ag],"unit":"mg", "label":"Manganese"},
		"chromium_mcg":         {"rda": chromium_f[ag] if is_female else chromium_m[ag],"unit":"mcg", "label":"Chromium"},
		# Antioxidants (therapeutic targets, no official RDA)
		"beta_carotene_mcg":    {"rda": 3000.0,  "unit":"mcg", "label":"Beta-carotene"},
		"lycopene_mcg":         {"rda": 8000.0,  "unit":"mcg", "label":"Lycopene"},
		"lutein_zeaxanthin_mcg":{"rda": 7000.0,  "unit":"mcg", "label":"Lutein+Zeaxanthin"},
		"quercetin_mg":         {"rda": 10.0,    "unit":"mg",  "label":"Quercetin"},
		"total_polyphenols_mg": {"rda": 650.0,   "unit":"mg",  "label":"Polyphenols"},
	}

	# ════════════════════════════════════════════════════════════════════
	# CONDITION-SPECIFIC ADJUSTMENTS
	# Source: Disease tables D1–D12 in clinical PDF reference
	# ════════════════════════════════════════════════════════════════════

	# ── NAFLD / MASLD (Disease 12) ────────────────────────────────────────
	if c.has("nafld"):
		rdas["vitamin_e_mg"]["rda"]         = 800.0   # AASLD rec for non-diabetic NASH; UL=1000
		rdas["vitamin_c_mg"]["rda"]         = 500.0   # antioxidant support
		rdas["vitamin_d_mcg"]["rda"]        = 50.0    # 2000 IU; target >75 nmol/L
		rdas["vitamin_b1_mg"]["rda"]       *= 1.5     # deficiency common in NAFLD
		rdas["vitamin_b2_mg"]["rda"]       *= 1.5
		rdas["vitamin_b3_mg"]["rda"]       *= 1.2
		rdas["vitamin_b6_mg"]["rda"]       *= 1.5
		rdas["vitamin_b12_mcg"]["rda"]      = 5.0     # low B12 linked to hepatosteatosis
		rdas["selenium_mcg"]["rda"]         = 150.0   # antioxidant; 100–200 mcg range
		rdas["zinc_mg"]["rda"]              = 18.0 if not is_female else 15.0
		rdas["magnesium_mg"]["rda"]         = 500.0   # deficiency promotes IR
		rdas["chromium_mcg"]["rda"]         = 300.0   # therapeutic; 200–600 mcg
		rdas["potassium_mg"]["rda"]         = 4000.0 if not is_female else 3750.0
		rdas["beta_carotene_mcg"]["rda"]    = 6000.0
		rdas["total_polyphenols_mg"]["rda"] = 1000.0

	# ── T2DM / Glycemic Health (Disease 10) ──────────────────────────────
	if c.has("glycemic-health"):
		rdas["vitamin_b1_mg"]["rda"]        = 2.0     # benfotiamine; neuropathy prevention
		rdas["vitamin_b6_mg"]["rda"]        = 1.7 if ag < 3 else 2.0  # insulin sensitivity
		rdas["vitamin_b9_mcg"]["rda"]       = 600.0   # reduces homocysteine risk in T2DM
		rdas["vitamin_b12_mcg"]["rda"]      = 5.0     # metformin depletes B12
		rdas["vitamin_d_mcg"]["rda"]        = 50.0    # 2000 IU; VD deficiency worsens IR
		rdas["vitamin_k2_mcg"]["rda"]       = 150.0   # MK-7 improves insulin sensitivity
		rdas["magnesium_mg"]["rda"]         = 500.0 if not is_female else 420.0
		rdas["potassium_mg"]["rda"]         = 3500.0 if is_female else 4700.0
		rdas["zinc_mg"]["rda"]              = 15.0 if not is_female else 13.0
		rdas["chromium_mcg"]["rda"]         = 400.0   # therapeutic 200–1000 mcg; picolinate form
		rdas["manganese_mg"]["rda"]         = 3.0     # critical for gluconeogenesis regulation
		rdas["selenium_mcg"]["rda"]         = 80.0
		rdas["quercetin_mg"]["rda"]         = 15.0

	# ── Lipid Health / Dyslipidemia (Disease 11) ─────────────────────────
	if c.has("lipid-health"):
		rdas["vitamin_b3_mg"]["rda"]        = 20.0    # niacin; therapeutic use under MD only
		rdas["vitamin_b9_mcg"]["rda"]       = 600.0   # reduces homocysteine (CVD risk)
		rdas["vitamin_b12_mcg"]["rda"]      = 4.0     # reduces homocysteine
		rdas["vitamin_c_mg"]["rda"]         = 600.0   # 200–1000 mg; reduces LDL oxidation
		rdas["vitamin_d_mcg"]["rda"]        = 37.5    # 1500 IU; deficiency linked to worse lipids
		rdas["vitamin_e_mg"]["rda"]         = 200.0   # antioxidant; prevents LDL oxidation
		rdas["vitamin_k2_mcg"]["rda"]       = 200.0 if not is_female else 150.0  # arterial calcification
		rdas["magnesium_mg"]["rda"]         = 460.0 if not is_female else 420.0
		rdas["selenium_mcg"]["rda"]         = 80.0
		rdas["chromium_mcg"]["rda"]         = 200.0
		rdas["potassium_mg"]["rda"]         = 4700.0 if not is_female else 3500.0
		rdas["lycopene_mcg"]["rda"]         = 10000.0  # cardioprotective
		rdas["quercetin_mg"]["rda"]         = 15.0
		rdas["total_polyphenols_mg"]["rda"] = 1000.0

	# ── Hashimoto's / Thyroid Health (Disease 2) ──────────────────────────
	if c.has("thyroid-health"):
		rdas["selenium_mcg"]["rda"]         = 150.0   # 100–200 mcg; L-selenomethionine; reduces TPOAb
		rdas["iodine_mcg"]["rda"]           = 150.0   # RDA ONLY; strict cap; avoid excess >300 mcg
		rdas["zinc_mg"]["rda"]              = 13.5 if not is_female else 11.5  # deficiency common in HT
		rdas["iron_mg"]["rda"]              = 10.0 if not is_female else 14.0  # impairs thyroid peroxidase
		rdas["magnesium_mg"]["rda"]         = 450.0 if not is_female else 400.0
		rdas["copper_mg"]["rda"]            = 1.2    # Cu:Zn ratio ~1:10 important
		rdas["vitamin_a_mcg"]["rda"]        = 1200.0 if not is_female else 950.0
		rdas["vitamin_b6_mg"]["rda"]        = 1.7 if ag < 3 else 2.0
		rdas["vitamin_b9_mcg"]["rda"]       = 500.0
		rdas["vitamin_b12_mcg"]["rda"]      = 3.0     # B12 deficiency common in autoimmune
		rdas["vitamin_c_mg"]["rda"]         = 150.0   # antioxidant; 200 mg in active disease
		rdas["vitamin_d_mcg"]["rda"]        = 56.0    # 2250 IU; target serum >75 nmol/L
		rdas["vitamin_e_mg"]["rda"]         = 18.5    # antioxidant
		rdas["vitamin_k2_mcg"]["rda"]       = 160.0 if not is_female else 135.0
		rdas["quercetin_mg"]["rda"]         = 750.0   # 500–1000 mg anti-inflammatory

	# ── Graves' Disease (Disease 3) — NEW ────────────────────────────────
	if c.has("graves-disease"):
		rdas["selenium_mcg"]["rda"]         = 200.0   # ETA Grade A for orbitopathy; 6 months
		rdas["iodine_mcg"]["rda"]           = 150.0   # absolute maximum; NO supplements
		rdas["calcium_mg"]["rda"]           = 1600.0 if not is_female else 1600.0  # bone resorption
		rdas["vitamin_d_mcg"]["rda"]        = 56.0    # 2250 IU; bone protection
		rdas["vitamin_k2_mcg"]["rda"]       = 185.0 if not is_female else 185.0  # bone; MK-7
		rdas["vitamin_b1_mg"]["rda"]        = 2.0     # increased need in hypermetabolic state
		rdas["vitamin_b2_mg"]["rda"]        = 2.0
		rdas["vitamin_b3_mg"]["rda"]        = 21.5 if not is_female else 18.5
		rdas["vitamin_b6_mg"]["rda"]        = 2.0 if ag < 3 else 2.5
		rdas["vitamin_b9_mcg"]["rda"]       = 600.0
		rdas["vitamin_b12_mcg"]["rda"]      = 3.7
		rdas["vitamin_c_mg"]["rda"]         = 200.0   # antioxidant; hypermetabolic state
		rdas["vitamin_e_mg"]["rda"]         = 20.0
		rdas["magnesium_mg"]["rda"]         = 525.0 if not is_female else 425.0
		rdas["zinc_mg"]["rda"]              = 15.0 if not is_female else 12.5
		rdas["potassium_mg"]["rda"]         = 4750.0 if not is_female else 3750.0  # high metabolic rate
		rdas["iron_mg"]["rda"]              = 12.5 if not is_female else 21.5

	# ── Osteoporosis ──────────────────────────────────────────────────────
	if c.has("osteoporosis"):
		rdas["vitamin_d_mcg"]["rda"]        = 20.0    # 800 IU minimum
		rdas["vitamin_k2_mcg"]["rda"]       = 190.0 if not is_female else 180.0  # MK-7 for bone
		rdas["calcium_mg"]["rda"]           = 1200.0  # critical; DEXA monitoring
		rdas["magnesium_mg"]["rda"]         = 460.0 if not is_female else 420.0
		rdas["vitamin_c_mg"]["rda"]         = 100.0   # collagen synthesis

	# ── Hemochromatosis (Disease 9) ───────────────────────────────────────
	if c.has("hemochromatosis"):
		rdas["vitamin_c_mg"]["rda"]         = 75.0    # LOWER limit; supplements enhance iron absorption
		rdas["calcium_mg"]["rda"]           = 1200.0  # with meals to inhibit iron absorption
		rdas["zinc_mg"]["rda"]              = 12.5 if not is_female else 10.5  # competes with iron
		rdas["selenium_mcg"]["rda"]         = 78.0    # 55–100 mcg
		rdas["copper_mg"]["rda"]            = 1.2     # monitor Cu:Zn balance
		rdas["vitamin_d_mcg"]["rda"]        = 28.5    # 1150 IU; phlebotomy phase
		rdas["vitamin_e_mg"]["rda"]         = 17.5
		rdas["vitamin_k2_mcg"]["rda"]       = 160.0 if not is_female else 135.0

	# ── Wilson's Disease ──────────────────────────────────────────────────
	if c.has("wilsons-disease"):
		rdas["zinc_mg"]["rda"]              = 32.5 if not is_female else 25.0  # pharmacological block

	# ── Crohn's Disease (Disease 7) ───────────────────────────────────────
	if c.has("crohns-disease"):
		rdas["vitamin_a_mcg"]["rda"]        = 1500.0 if not is_female else 1250.0
		rdas["vitamin_b1_mg"]["rda"]        = 2.25 if not is_female else 2.0
		rdas["vitamin_b2_mg"]["rda"]        = 2.25 if not is_female else 2.0
		rdas["vitamin_b6_mg"]["rda"]        = 2.25 if not is_female else 1.75
		rdas["vitamin_b9_mcg"]["rda"]       = 900.0   # MTX depletes folate
		rdas["vitamin_b12_mcg"]["rda"]      = 10.0    # terminal ileum disease; IM if resected
		rdas["vitamin_c_mg"]["rda"]         = 300.0   # antioxidant; 250–500 mg therapeutic
		rdas["vitamin_d_mcg"]["rda"]        = 87.5    # 3500 IU; target serum >80–100 nmol/L
		rdas["vitamin_e_mg"]["rda"]         = 22.5
		rdas["vitamin_k2_mcg"]["rda"]       = 250.0 if not is_female else 235.0  # MK-7; bone protection
		rdas["calcium_mg"]["rda"]           = 2000.0  # corticosteroid bone loss; DEXA
		rdas["iron_mg"]["rda"]              = 17.5 if not is_female else 30.0  # IV preferred in active IBD
		rdas["magnesium_mg"]["rda"]         = 575.0   # hypomagnesemia very common
		rdas["zinc_mg"]["rda"]              = 19.5 if not is_female else 17.0  # diarrheal losses
		rdas["selenium_mcg"]["rda"]         = 150.0   # antioxidant; severity associated
		rdas["copper_mg"]["rda"]            = 1.45    # 900–2000 mcg
		rdas["potassium_mg"]["rda"]         = 4500.0 if not is_female else 4000.0  # diarrheal losses
		rdas["iodine_mcg"]["rda"]           = 225.0   # 150–300 mcg

	# ── Celiac Disease (Disease 6) ────────────────────────────────────────
	if c.has("celiac-disease"):
		rdas["vitamin_a_mcg"]["rda"]        = 1500.0 if not is_female else 1250.0  # malabsorbed
		rdas["vitamin_b1_mg"]["rda"]        = 2.0    # GF grains not enriched
		rdas["vitamin_b2_mg"]["rda"]        = 2.0
		rdas["vitamin_b3_mg"]["rda"]       *= 1.5
		rdas["vitamin_b6_mg"]["rda"]        = 2.0
		rdas["vitamin_b9_mcg"]["rda"]       = 750.0   # severely malabsorbed
		rdas["vitamin_b12_mcg"]["rda"]      = 4.5     # ileal absorption impaired
		rdas["vitamin_c_mg"]["rda"]         = 170.0
		rdas["vitamin_d_mcg"]["rda"]        = 75.0    # 3000 IU; maintain >75 nmol/L
		rdas["vitamin_e_mg"]["rda"]         = 20.0    # fat-soluble; malabsorbed
		rdas["vitamin_k2_mcg"]["rda"]       = 225.0 if not is_female else 210.0  # fat-soluble; bone
		rdas["calcium_mg"]["rda"]           = 1650.0  # DEXA at diagnosis; high osteoporosis risk
		rdas["iron_mg"]["rda"]              = 15.0 if not is_female else 26.5   # anemia very common
		rdas["magnesium_mg"]["rda"]         = 550.0   # malabsorbed; glycinate preferred
		rdas["zinc_mg"]["rda"]              = 16.0 if not is_female else 14.0  # malabsorbed
		rdas["selenium_mcg"]["rda"]         = 110.0   # 70–150 mcg
		rdas["copper_mg"]["rda"]            = 1.5     # deficiency can cause myelopathy
		rdas["iodine_mcg"]["rda"]           = 225.0   # GF grains not iodized; supplement
		rdas["chromium_mcg"]["rda"]         = 40.0    # deficiency associated with CD
		rdas["manganese_mg"]["rda"]         = 3.25 if not is_female else 3.0

	# ── EPI / Pancreatic Exocrine Insufficiency (Disease 8) ───────────────
	if c.has("epi"):
		rdas["vitamin_a_mcg"]["rda"]        = 2250.0 if not is_female else 1850.0  # severely deficient
		rdas["vitamin_d_mcg"]["rda"]        = 112.5  # 4500 IU; very high need; PERT required
		rdas["vitamin_e_mg"]["rda"]         = 30.0   # 75% of untreated patients VE deficient
		rdas["vitamin_k2_mcg"]["rda"]       = 300.0  # fat-soluble; malabsorbed
		rdas["vitamin_b1_mg"]["rda"]       *= 1.75
		rdas["vitamin_b2_mg"]["rda"]       *= 1.75
		rdas["vitamin_b3_mg"]["rda"]       *= 1.75
		rdas["vitamin_b5_mg"]["rda"]       *= 1.75
		rdas["vitamin_b6_mg"]["rda"]       *= 1.75
		rdas["vitamin_b7_mcg"]["rda"]      *= 1.75
		rdas["vitamin_b9_mcg"]["rda"]       = 750.0
		rdas["vitamin_b12_mcg"]["rda"]      = 8.5
		rdas["vitamin_c_mg"]["rda"]         = 200.0
		rdas["calcium_mg"]["rda"]           = 2000.0  # 75% of PEI patients have osteoporosis
		rdas["iron_mg"]["rda"]              = 15.5 if not is_female else 26.5
		rdas["magnesium_mg"]["rda"]         = 575.0
		rdas["zinc_mg"]["rda"]              = 19.5 if not is_female else 17.0
		rdas["selenium_mcg"]["rda"]         = 150.0
		rdas["copper_mg"]["rda"]            = 1.6    # 1000–2200 mcg
		rdas["iodine_mcg"]["rda"]           = 225.0
		rdas["chromium_mcg"]["rda"]         = 47.5
		rdas["manganese_mg"]["rda"]         = 3.75 if not is_female else 3.4
		rdas["potassium_mg"]["rda"]         = 4500.0 if not is_female else 4100.0

	# ── Post-Cholecystectomy (Disease 1) ─────────────────────────────────
	if c.has("post-cholecystectomy"):
		rdas["vitamin_a_mcg"]["rda"]        = 1050.0 if not is_female else 850.0  # fat-soluble; monitor
		rdas["vitamin_d_mcg"]["rda"]        = 22.5   # 900 IU; monitor 25(OH)D
		rdas["vitamin_e_mg"]["rda"]         = 17.5   # fat-soluble; monitor serum E
		rdas["vitamin_k2_mcg"]["rda"]       = 160.0 if not is_female else 140.0  # monitor INR if on warfarin
		rdas["vitamin_b12_mcg"]["rda"]      = 3.2 if ag == 4 else 2.4  # 65+ absorption reduced
		rdas["calcium_mg"]["rda"]           = 1100.0 if not is_female else 1350.0
		rdas["magnesium_mg"]["rda"]         = 430.0 if not is_female else 345.0
		rdas["zinc_mg"]["rda"]              = 13.0 if not is_female else 10.0
		rdas["selenium_mcg"]["rda"]         = 77.5   # 55–100 mcg
		rdas["potassium_mg"]["rda"]         = 3700.0 if not is_female else 3200.0

	# ── Kidney at risk (CKD) ─────────────────────────────────────────────
	if kidney_at_risk:
		rdas["potassium_mg"]["rda"] = 2000.0   # restriction
		rdas["vitamin_c_mg"]["rda"] = 30.0     # large doses harmful in CKD

	# ── Lactose Intolerance ───────────────────────────────────────────────
	if c.has("lactose-intolerance"):
		rdas["calcium_mg"] = {"rda": 1200.0, "unit":"mg", "label":"Calcium"}

	return rdas


# ── Which micronutrients to show on HomePage ──
func get_visible_micronutrients() -> Array:
	var c = active_metabolic_conditions
	var visible = []

	# Always show core nutrients
	visible.append_array(["vitamin_a_mcg", "vitamin_c_mg", "vitamin_d_mcg", "vitamin_b12_mcg", "magnesium_mg"])

	# NAFLD
	if c.has("nafld") or c.has("thyroid-health") or c.has("osteoporosis"):
		if not visible.has("vitamin_e_mg"): visible.append("vitamin_e_mg")
	if c.has("nafld"):
		for f in ["beta_carotene_mcg", "total_polyphenols_mg", "selenium_mcg", "vitamin_b1_mg"]:
			if not visible.has(f): visible.append(f)

	# Osteoporosis
	if c.has("osteoporosis"):
		for f in ["vitamin_k2_mcg", "calcium_mg"]:
			if not visible.has(f): visible.append(f)

	# Glycemic / T2DM
	if c.has("glycemic-health") or c.has("lipid-health"):
		for f in ["vitamin_b6_mg", "vitamin_b9_mcg", "potassium_mg", "quercetin_mg", "chromium_mcg", "manganese_mg"]:
			if not visible.has(f): visible.append(f)

	# Lipid
	if c.has("lipid-health"):
		for f in ["lycopene_mcg", "total_polyphenols_mg", "vitamin_k2_mcg", "vitamin_c_mg"]:
			if not visible.has(f): visible.append(f)

	# Thyroid (Hashimoto's)
	if c.has("thyroid-health"):
		for f in ["selenium_mcg", "iodine_mcg", "zinc_mg", "copper_mg", "iron_mg"]:
			if not visible.has(f): visible.append(f)

	# Graves' disease — similar to thyroid but iodine is DANGER
	if c.has("graves-disease"):
		for f in ["selenium_mcg", "iodine_mcg", "calcium_mg", "vitamin_k2_mcg"]:
			if not visible.has(f): visible.append(f)

	# Hemochromatosis
	if c.has("hemochromatosis"):
		for f in ["iron_mg", "vitamin_c_mg", "calcium_mg", "zinc_mg"]:
			if not visible.has(f): visible.append(f)

	# Wilson's
	if c.has("wilsons-disease"):
		for f in ["copper_mg", "zinc_mg"]:
			if not visible.has(f): visible.append(f)

	# Crohn's
	if c.has("crohns-disease"):
		for f in ["vitamin_b12_mcg", "vitamin_d_mcg", "zinc_mg", "magnesium_mg", "selenium_mcg", "potassium_mg"]:
			if not visible.has(f): visible.append(f)

	# Celiac
	if c.has("celiac-disease"):
		for f in ["vitamin_b9_mcg", "vitamin_d_mcg", "zinc_mg", "iron_mg", "calcium_mg", "copper_mg", "iodine_mcg"]:
			if not visible.has(f): visible.append(f)

	# EPI
	if c.has("epi"):
		for f in ["vitamin_a_mcg", "vitamin_d_mcg", "vitamin_e_mg", "vitamin_k2_mcg", "selenium_mcg", "zinc_mg"]:
			if not visible.has(f): visible.append(f)

	# Post-cholecystectomy
	if c.has("post-cholecystectomy"):
		for f in ["vitamin_d_mcg", "vitamin_e_mg", "vitamin_k2_mcg", "vitamin_a_mcg"]:
			if not visible.has(f): visible.append(f)

	return visible


# ───────────────────────────────────────────
# SECTION K — BODY METRICS: Add age field
# In SettingsPage.gd save_body_metrics(), add age to the saved dict.
# In Global.gd load_body_metrics_from_file(), add age to body_metrics.
# ───────────────────────────────────────────

# In save_body_metrics() in SettingsPage.gd, add:
#   "age": age,
#
# In load_body_metrics_from_file() in Global.gd, add:
#   body_metrics["age"] = data.get("age", 35)
#
# Also update Global.body_metrics dict to include:
#   "age": 35


# ───────────────────────────────────────────
# SECTION L — GRAVES' DISEASE CALCULATOR
# Add to SettingsPage.gd
# ───────────────────────────────────────────

# New panel constant (add to SettingsPage.gd):
# const GRAVES  = BASE + "GravesPanel/VBoxContainer/"

# New condition registration:
# get_node(GRAVES + "KnownGraves").toggled.connect(func(c): _on_known_metabolic("graves-disease", c, GRAVES))
# get_node(GRAVES + "InputFields/CalculateButton").pressed.connect(_on_calculate_graves)

# Note: metabolic_risk_levels entry to add in Global.gd:
# "graves-disease": "normal",   # normal / mild / active / controlled


# ─────────────────────────────────────────
#  STARTUP
# ─────────────────────────────────────────
func _ready():
	load_streak()
	load_quests()
	load_profile()
	load_points()
	load_badges()
	load_currency()
	load_report_date()
	load_body_metrics_from_file()
	load_metabolic_conditions()
	# Create metabolic.json if it doesn't exist yet
	if not FileAccess.file_exists("user://metabolic.json"):
		save_metabolic_conditions()
	if Global.should_show_weekly_report():
		call_deferred("_show_weekly_report")
		Global.mark_report_shown()
	Global.load_ui_settings()
	#load_tooth_staining_data()
# ─────────────────────────────────────────
#  WARNINGS — called by FridgePage per food

# ───────────────────────────────────────────

func get_warnings(food: Dictionary) -> Array:
	var warnings = []
	var oxalate = food.get("oxalate_mg_per_100g", 0)

	# ── Kidney risk ────────────────────────────────────────────────────────
	if kidney_at_risk:
		if oxalate >= 50:
			warnings.append({"severity": "avoid", "message": "High oxalate — avoid due to kidney risk."})
		elif oxalate >= 10:
			warnings.append({"severity": "caution", "message": "Moderate oxalate — caution due to kidney risk."})

	# ── Oxalate conditions ────────────────────────────────────────────────
	for key in active_conditions:
		if not conditions_data.has(key): continue
		var c_data = conditions_data[key]
		if oxalate >= c_data["avoid"]:
			warnings.append({"severity": "avoid",   "message": c_data["avoid_msg"]})
		elif oxalate >= c_data["caution"]:
			warnings.append({"severity": "caution", "message": c_data["caution_msg"]})

	# ── Metabolic conditions (updated with new warnings) ──────────────────
	for condition in active_metabolic_conditions:
		# Build list of warning keys to check for this condition
		var keys_to_check: Array = []
		match condition:
			"nafld":
				keys_to_check = ["nafld", "nafld-fat", "nafld-iron"]
			"glycemic-health":
				keys_to_check = ["glycemic-health", "glycemic-health-sat-fat"]
			"lipid-health":
				keys_to_check = ["lipid-health", "lipid-health-sugar"]
			"hemochromatosis":
				keys_to_check = ["hemochromatosis", "hemochromatosis-vitamin_c", "hemochromatosis-sugar"]
			"crohns-disease":
				var risk = metabolic_risk_levels.get("crohns-disease", "normal")
				if risk == "active" or risk == "confirmed":
					keys_to_check = ["crohns-disease-fiber", "crohns-disease-fat"]
				else:
					keys_to_check = []  # remission: no fiber restriction warning
			"thyroid-health":
				keys_to_check = ["thyroid-health-iodine"]
			"graves-disease":
				keys_to_check = ["graves-disease-iodine"]
			"post-cholecystectomy":
				keys_to_check = ["post-cholecystectomy", "post-cholecystectomy-sat-fat"]
			_:
				keys_to_check = [condition]

		for wkey in keys_to_check:
			if not metabolic_warnings_data.has(wkey): continue
			var w     = metabolic_warnings_data[wkey]
			var field = w["field"]

			# Boolean field (gluten)
			if field == "contains_gluten":
				if food.get("contains_gluten", false):
					warnings.append({"severity":"avoid","message":w["avoid_msg"]})
				break

			var value = food.get(field, 0.0)
			if value >= w["avoid"]:
				if w.has("avoid_msg"):
					warnings.append({"severity":"avoid","message":w["avoid_msg"]})
				break
			elif w.has("caution") and value >= w["caution"]:
				if w.has("caution_msg"):
					warnings.append({"severity":"caution","message":w["caution_msg"]})
				break
			if Global.active_metabolic_conditions.has("graves-disease"):
				var cat = food.get("category","")
				var fid = food.get("id","")
				if cat == "vegetables" and fid in ["seaweed","wakame"]:
					warnings.append({"severity":"avoid","message":"Seaweed — avoid with Graves' disease (variable high iodine)."})
		# Tooth staining warnings
	for w in get_tooth_warnings(food):
		warnings.append(w)
	# Parodontosis warnings
	for pw in get_paro_warnings(food):
		warnings.append(pw)
	return warnings

# ─────────────────────────────────────────
#  PROFILE (kidney + oxalate conditions)
# ─────────────────────────────────────────
func save_profile():
	var file = FileAccess.open("user://profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"conditions": active_conditions,
		"kidney_at_risk": kidney_at_risk,
		"hide_red_warnings": hide_red_warnings,
		"use_fahrenheit":   use_fahrenheit,
		"tooth_remove_staining": tooth_remove_staining,
		"tooth_warn_staining":   tooth_warn_staining,
		"paro_remove": paro_remove,
		"paro_warn":   paro_warn,
	}))
	file.close()

func load_profile():
	if not FileAccess.file_exists("user://profile.json"): return
	var file = FileAccess.open("user://profile.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	active_conditions = data.get("conditions", [])
	kidney_at_risk = data.get("kidney_at_risk", false)
	hide_red_warnings   = data.get("hide_red_warnings", false)
	tooth_remove_staining = data.get("tooth_remove_staining", false)
	tooth_warn_staining   = data.get("tooth_warn_staining", false)
	use_fahrenheit      = data.get("use_fahrenheit", false)
	paro_remove = data.get("paro_remove", false)
	paro_warn   = data.get("paro_warn", false)
	

# ─────────────────────────────────────────
#  METABOLIC CONDITIONS
# ─────────────────────────────────────────
func save_metabolic_conditions():
	var file = FileAccess.open("user://metabolic.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"conditions": active_metabolic_conditions,
		"risk_levels": metabolic_risk_levels,
		"known_diagnoses": known_diagnoses
	}))
	file.close()

func load_metabolic_conditions():
	if not FileAccess.file_exists("user://metabolic.json"): return
	var file = FileAccess.open("user://metabolic.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	active_metabolic_conditions = data.get("conditions", [])
	known_diagnoses = data.get("known_diagnoses", [])
	var saved_risks = data.get("risk_levels", {})
	for key in saved_risks.keys():
		metabolic_risk_levels[key] = saved_risks[key]

func set_metabolic_condition(condition: String, active: bool):
	if active:
		if not active_metabolic_conditions.has(condition):
			active_metabolic_conditions.append(condition)
	else:
		active_metabolic_conditions.erase(condition)
	save_metabolic_conditions()

func set_metabolic_risk(condition: String, level: String):
	metabolic_risk_levels[condition] = level
	save_metabolic_conditions()

func set_known_diagnosis(condition: String, known: bool):
	if known:
		if not known_diagnoses.has(condition):
			known_diagnoses.append(condition)
	else:
		known_diagnoses.erase(condition)
	save_metabolic_conditions()
# ─────────────────────────────────────────
#  BODY METRICS
# ─────────────────────────────────────────
func load_body_metrics_from_file():
	if not FileAccess.file_exists("user://body_metrics.json"): return
	var file = FileAccess.open("user://body_metrics.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	body_metrics = {
		"bmr": data.get("bmr", 0.0),
		"tdee": data.get("tdee", 0.0),
		"daily_goal": data.get("daily_goal", 0.0),
		"goal_weight": data.get("goal_weight", 0.0),
		"weight": data.get("weight", 0.0),
		"bmi_text": data.get("bmi_text", "BMI: —"),
		"is_female": data.get("is_female", false),
		"age": data.get("age", 35)
	}
	body_metrics["adjusted_kcal_goal"] = data.get("adjusted_goal", data.get("daily_goal", 0.0))
# ─────────────────────────────────────────
#  POINTS
# ─────────────────────────────────────────
var points_history: Dictionary = {}

func save_points(date: String, points: float):
	points_history[date] = points
	var file = FileAccess.open("user://points.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(points_history))
	file.close()

func load_points():
	if not FileAccess.file_exists("user://points.json"): return
	var file = FileAccess.open("user://points.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data:
		points_history = data

func get_points_today() -> float:
	var today = Time.get_date_string_from_system()
	if points_history.is_empty():
		load_points()
	return points_history.get(today, 0.0)

func get_points_week() -> float:
	if points_history.is_empty(): load_points()
	var total    = 0.0
	var unix_now = Time.get_unix_time_from_system()
	var now_dt   = Time.get_datetime_dict_from_unix_time(unix_now)
	var weekday  = now_dt.get("weekday", 1)
	var days_since_monday = (weekday + 6) % 7
	for i in range(days_since_monday + 1):
		var unix_day = unix_now - (i * 86400)
		var dt       = Time.get_datetime_dict_from_unix_time(unix_day)
		var date_str = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]
		total += points_history.get(date_str, 0.0)
	return total

func get_points_alltime() -> float:
	if points_history.is_empty(): load_points()
	var total = 0.0
	for key in points_history.keys():
		if not key.begins_with("_"):
			total += points_history[key]
	return total

func get_macro_goals() -> Dictionary:
	var weight    = body_metrics.get("weight", 70.0)
	print("DEBUG macro_goals: weight=", weight, " kidney_at_risk=", kidney_at_risk, " conditions=", active_metabolic_conditions)
	var is_female = body_metrics.get("is_female", false)
	var bmi_text  = body_metrics.get("bmi_text", "")
	var daily_kcal = body_metrics.get("daily_goal", 2000.0)
	var is_overweight = bmi_text.contains("Overweight") or bmi_text.contains("Obese")
	var c = active_metabolic_conditions

	# ── Protein (g/day) ───────────────────────────────────────────────────
	var protein_g_per_kg = 0.8  # baseline RDA
	if is_overweight:                  protein_g_per_kg = 1.0
	if c.has("glycemic-health"):       protein_g_per_kg = max(protein_g_per_kg, 1.3)   # 1.2–1.5 high priority
	if c.has("nafld"):                 protein_g_per_kg = max(protein_g_per_kg, 1.35)
	if c.has("lipid-health"):          protein_g_per_kg = max(protein_g_per_kg, 1.0)
	if c.has("thyroid-health"):        protein_g_per_kg = max(protein_g_per_kg, 0.9)
	if c.has("graves-disease"):        protein_g_per_kg = max(protein_g_per_kg, 1.75)  # 1.5–2.0; catabolic
	if c.has("osteoporosis"):          protein_g_per_kg = max(protein_g_per_kg, 1.1)
	if c.has("hemochromatosis"):       protein_g_per_kg = max(protein_g_per_kg, 0.8)
	if c.has("crohns-disease"):
		var risk = metabolic_risk_levels.get("crohns-disease", "normal")
		if risk == "confirmed" or risk == "active":
			protein_g_per_kg = max(protein_g_per_kg, 1.75)  # flare: 1.5–2.0
		else:
			protein_g_per_kg = max(protein_g_per_kg, 1.35)  # remission: 1.2–1.5
	if c.has("celiac-disease"):        protein_g_per_kg = max(protein_g_per_kg, 1.35)  # active: 1.2–1.5
	if c.has("epi"):                   protein_g_per_kg = max(protein_g_per_kg, 1.35)
	if c.has("post-cholecystectomy"):  protein_g_per_kg = max(protein_g_per_kg, 0.9)
	if c.has("lactose-intolerance"):   protein_g_per_kg = max(protein_g_per_kg, 0.8)
	if kidney_at_risk:                 protein_g_per_kg = 0.6   # CKD: restrict

	var protein_goal = weight * protein_g_per_kg

	# ── Fat (g/day) ───────────────────────────────────────────────────────
	var fat_pct_min = 0.20
	var fat_pct_max = 0.35


	# EPI: fat MUST NOT BE RESTRICTED (different from all other conditions)
	if c.has("epi"):
		var fat_goal_g    = 40.0  # 30–50 g midpoint (NOT % kcal)
		var carb_pct_min  = 0.45
		var carb_pct_max  = 0.65
		var carb_min = (daily_kcal * carb_pct_min) / 4.0
		var carb_max = (daily_kcal * carb_pct_max) / 4.0
		var fiber_goal = 31.5   # normal fiber OK with PERT
		return {
			"protein_g":    snappedf(protein_goal, 0.1),
			"fat_g_min":    fat_goal_g,
			"fat_g_max":    fat_goal_g * 2.0,  # generous; fat NOT restricted
			"carbs_g_min":  snappedf(carb_min, 0.1),
			"carbs_g_max":  snappedf(carb_max, 0.1),
			"fiber_g":      fiber_goal,
			"fat_note":     "Fat must NOT be restricted with PERT. Use MCT oil if needed."
		}

	if c.has("nafld"):
		fat_pct_min = 0.15; fat_pct_max = 0.30
	if c.has("lipid-health"):
		fat_pct_min = 0.15; fat_pct_max = 0.28  # stricter: <7% SFA emphasis
	if c.has("glycemic-health"):
		fat_pct_min = 0.20; fat_pct_max = 0.35  # MUFA emphasis
	if c.has("post-cholecystectomy"):
		fat_pct_max = 0.25  # impaired fat digestion
	if c.has("graves-disease"):
		fat_pct_min = 0.25; fat_pct_max = 0.38  # higher need in hypermetabolic state

	# Post-cholecystectomy early phase: stricter fat per meal
	var fat_min_g = snappedf((daily_kcal * fat_pct_min) / 9.0, 0.1)
	var fat_max_g = snappedf((daily_kcal * fat_pct_max) / 9.0, 0.1)

	# ── Carbohydrates (g/day) ─────────────────────────────────────────────
	var carb_pct_min = 0.45
	var carb_pct_max = 0.65

	if c.has("glycemic-health"):
		carb_pct_min = 0.40; carb_pct_max = 0.45  # strict carb control; max 45–60 g/meal
	if c.has("nafld"):
		carb_pct_min = 0.40; carb_pct_max = 0.50  # limit fructose
	if c.has("lipid-health"):
		carb_pct_min = 0.40; carb_pct_max = 0.55  # restrict for TG management
	if c.has("graves-disease"):
		carb_pct_min = 0.45; carb_pct_max = 0.60  # high caloric need

	var carb_min_g = snappedf((daily_kcal * carb_pct_min) / 4.0, 0.1)
	var carb_max_g = snappedf((daily_kcal * carb_pct_max) / 4.0, 0.1)

	# ── Fiber (g/day) ─────────────────────────────────────────────────────
	var fiber_g = 25.0 if is_female else 38.0  # baseline IOM

	if c.has("glycemic-health"):  fiber_g = snappedf(daily_kcal / 1000.0 * 14.0, 0.1)  # 14 g/1000 kcal
	if c.has("nafld"):            fiber_g = 34.0   # prebiotic fiber beneficial
	if c.has("lipid-health"):     fiber_g = 42.5   # 10–15 g/day SOLUBLE fiber priority; 35–50 total
	if c.has("osteoporosis"):     fiber_g = 31.5
	if c.has("hemochromatosis"):  fiber_g = 34.0   # phytate fiber inhibits iron absorption
	if c.has("celiac-disease"):   fiber_g = 34.0   # GFD typically low fiber; emphasize GF sources
	if c.has("crohns-disease"):
		var risk = metabolic_risk_levels.get("crohns-disease", "normal")
		if risk == "confirmed" or risk == "active":
			fiber_g = 8.0    # flare: <10 g; soluble only
		else:
			fiber_g = 39.0   # remission: 30–48 g; high
	if c.has("thyroid-health"):   fiber_g = 37.5   # 35–45 g; anti-inflammatory
	if c.has("graves-disease"):   fiber_g = 42.5   # 35–55 g
	if c.has("post-cholecystectomy"):
		fiber_g = 25.0  # late phase; early phase use soluble only (12–15 g)
	if c.has("epi"):              fiber_g = 31.5
	if kidney_at_risk:            fiber_g = 25.0

	return {
		"protein_g":    snappedf(protein_goal, 0.1),
		"fat_g_min":    fat_min_g,
		"fat_g_max":    fat_max_g,
		"carbs_g_min":  carb_min_g,
		"carbs_g_max":  carb_max_g,
		"fiber_g":      fiber_g,
		"sat_fat_g_max": get_sat_fat_limit_g()
	}

func get_sat_fat_limit_g() -> float:
	var kcal = adjusted_kcal_goal if adjusted_kcal_goal > 0 else body_metrics.get("daily_goal", 2000.0)
	var pct  = 0.10
	if active_metabolic_conditions.has("nafld"):               pct = 0.07
	if active_metabolic_conditions.has("glycemic-health"):     pct = 0.07
	if active_metabolic_conditions.has("post-cholecystectomy"):pct = 0.07
	if active_metabolic_conditions.has("lipid-health"):        pct = 0.06
	return (pct * kcal) / 9.0

func get_sat_fat_threshold_grams_for_food(sat_fat_per_100g: float, already_eaten_sat_fat_g: float) -> float:
	# Returns: how many grams of this food can be eaten before hitting the daily sat fat limit
	# Returns -1 if food has no sat fat (no warning needed)
	if sat_fat_per_100g <= 0.0: return -1.0
	var budget = get_sat_fat_limit_g() - already_eaten_sat_fat_g
	if budget <= 0.0: return 0.0   # already exceeded — any amount warns
	# Exact math: solve x * sat_fat_per_100g / 100 = budget
	return (budget * 100.0) / sat_fat_per_100g

func get_condition_clinical_notes() -> Dictionary:
	var notes: Dictionary = {}
	var c = active_metabolic_conditions
 
	if c.has("graves-disease"):
		notes["graves-disease"] = [
			"⚡ Hypermetabolic: caloric needs significantly increased (+20–40%).",
			"🚫 Strictly avoid ALL iodine sources: seaweed, kelp, iodine supplements.",
			"🦴 Bone protection critical: calcium 1200–2000 mg/day + Vitamin K2 (MK-7).",
			"💊 Selenium 200 mcg/day recommended by ETA for orbitopathy (Grade A).",
			"💧 High fluid needs: 3.5–5.0 L/day in active disease.",
			"🥩 High protein essential (1.5–2.0 g/kg): hyperthyroidism is catabolic.",
		]
 
	if c.has("thyroid-health"):
		notes["thyroid-health"] = [
			"🌊 Selenium 100–200 mcg/day: RCT evidence for TPO antibody reduction.",
			"🧂 Iodine: RDA only (150 mcg/day). Strictly avoid excess >300 mcg.",
			"🚫 Avoid: seaweed/kelp, iodine supplements, large amounts of raw cruciferous vegetables.",
			"💊 Consider myo-inositol 2000–4000 mg/day combined with selenium (RCT evidence).",
			"☀️ Vitamin D target: serum >75 nmol/L. Supplement 1500–3000 IU/day.",
			"🐟 Omega-3 EPA+DHA 2.0–4.0 g/day: reduces thyroid inflammation.",
		]
 
	if c.has("nafld"):
		notes["nafld"] = [
			"☕ Coffee 2–4 cups/day (unsweetened): strong hepatoprotective evidence.",
			"🚫 Strictly avoid: fructose/HFCS, sugary beverages, alcohol (accelerates fibrosis).",
			"💊 Vitamin E 800 mg/day (AASLD recommendation for non-diabetic NASH).",
			"🐟 Omega-3 EPA+DHA 2–4 g/day: reduces liver fat by ~20%.",
			"⚖️ Weight loss target: ≥5% reduces steatosis; ≥10% reverses fibrosis.",
		]
 
	if c.has("glycemic-health"):
		notes["glycemic-health"] = [
			"💊 If on metformin: check B12 annually; supplement 500–1000 mcg if depleted.",
			"🫒 MUFA as primary fat: extra virgin olive oil 2–4 tbsp/day.",
			"🌾 Max 45–60 g carbohydrate per meal; low glycemic index foods.",
			"🐟 Omega-3 EPA+DHA 2000–4000 mg/day: reduces cardiovascular risk.",
			"🔬 Chromium picolinate 400–1000 mcg/day may improve insulin sensitivity.",
		]
 
	if c.has("lipid-health"):
		notes["lipid-health"] = [
			"🌿 Plant sterols/stanols 2–3 g/day: reduces LDL 5–15%.",
			"💊 If on statins: CoQ10 100–300 mg/day may reduce myopathy.",
			"🐟 Omega-3 EPA+DHA 3–6 g/day: reduces triglycerides 25–35%.",
			"🌾 Soluble fiber 10–15 g/day (beta-glucan, psyllium, pectin): reduces LDL.",
			"🚫 Trans fats: completely eliminate. Raise LDL, lower HDL — no safe level.",
			"🫒 Replace saturated fat with PUFA/MUFA: every 1% SFA → PUFA reduces LDL ~2 mg/dL.",
		]
 
	if c.has("hemochromatosis"):
		notes["hemochromatosis"] = [
			"🚫 Avoid ALL vitamin C supplements >250 mg (enhances iron absorption).",
			"🍵 Drink tea or coffee WITH meals: tannins reduce iron absorption 40–60%.",
			"🥛 Dairy with meals: calcium competes with iron absorption.",
			"🚫 Avoid red/organ meats: highest heme iron (25% absorption vs 2–8% non-heme).",
			"🚫 Avoid iron-fortified foods and iron-containing multivitamins.",
			"🥃 Alcohol strictly limited: enhances iron absorption + liver damage risk.",
		]
 
	if c.has("crohns-disease"):
		var risk = metabolic_risk_levels.get("crohns-disease", "normal")
		notes["crohns-disease"] = [
			"💉 B12: monthly IM injections if terminal ileum resected.",
			"💉 Iron: IV iron preferred in active IBD (ECCO recommendation).",
			"☀️ Vitamin D target: serum >80–100 nmol/L (3000–6000 IU/day).",
			"🐟 Omega-3 EPA+DHA 2000–4000 mg/day: anti-inflammatory.",
			("🌿 Fiber during FLARE: limit to 5–12 g/day (soluble only)." if (risk == "active" or risk == "confirmed") else "🌿 Fiber during REMISSION: 30–48 g/day recommended."),
			"🥗 Mediterranean diet recommended (AGA 2024 guidelines).",
		]
 
	if c.has("celiac-disease"):
		notes["celiac-disease"] = [
			"🌾 STRICTLY gluten-free for life: wheat, barley, rye, conventional oats.",
			"⚠️ GF grains not iodized or enriched: supplement B vitamins, iodine, iron.",
			"🦴 DEXA scan at diagnosis: high osteoporosis risk from malabsorption.",
			"🔬 Copper deficiency can cause myelopathy: monitor serum copper.",
			"☀️ Vitamin D 2000–4000 IU/day; maintain serum >75 nmol/L.",
			"📋 Monitor: iron, folate, B12, vitamin D, calcium, zinc, copper, selenium every 6–12 months.",
		]
 
	if c.has("epi"):
		notes["epi"] = [
			"💊 PERT (Pancreatic Enzyme Replacement Therapy): 40,000–50,000 LU lipase per main meal.",
			"🥑 DO NOT restrict fat — fat restriction worsens malnutrition. Use healthy fats.",
			"🧈 MCT oil 15–30 g/day if PERT inadequate: absorbed without lipase.",
			"☀️ Fat-soluble vitamins A, D, E, K all severely depleted — supplement aggressively.",
			"🩺 Vitamin D 3000–8000 IU/day; 75% of PEI patients have insufficient PERT.",
		]
 
	if c.has("post-cholecystectomy"):
		notes["post-cholecystectomy"] = [
			"🍽️ 5–6 small meals per day: bile flows continuously without gallbladder.",
			"Early phase (0–3 months): fat <13 g/meal; soluble fiber only.",
			"Late phase (3+ months): gradually liberalize to 20–35 g fat/meal.",
			"🔬 Monitor fat-soluble vitamins A, D, E, K: malabsorption risk.",
			"📊 Monitor INR if on warfarin (Vitamin K2 supplementation).",
			"⚠️ Long-term risk: increased BMI and metabolic syndrome.",
		]
 
	return notes

func check_and_update_streak():
	var today     = Time.get_date_string_from_system()
	var yesterday = _get_yesterday_string()

	print("STREAK CHECK: today=", today, " last=", last_streak_date,
		" streak=", daily_streak)

	if last_streak_date == today:
		print("STREAK: already logged today, no change")
		return

	if last_streak_date == yesterday:
		daily_streak += 1
		print("STREAK: consecutive day! new streak=", daily_streak)
	elif last_streak_date == "":
		daily_streak = 1
		print("STREAK: first ever log, streak=1")
	elif _days_between(last_streak_date, today) == 2:
		if streak_freeze_count > 0:
			streak_freeze_count -= 1
			daily_streak += 1

			print("STREAK: freeze used! streak=", daily_streak)
		else:
			daily_streak = 1
			consecutive_logging_days = 0
			print("STREAK: missed a day, reset to 1")
	else:
		daily_streak = 1

		print("STREAK: long absence, reset to 1")

	# Milestone check
	var milestones = [3, 7, 14, 30, 60, 100, 200, 365]
	for m in milestones:
		if daily_streak == m and _last_celebrated_milestone < m:
			_last_celebrated_milestone = m
			streak_milestone_reached.emit(m)
			award_py(m * 5, "Streak milestone " + str(m) + " days")

	last_streak_date = today
	consecutive_logging_days = max(consecutive_logging_days, daily_streak)
	save_streak()
	print("STREAK: saved. streak=", daily_streak, " last_date=", last_streak_date)

func save_streak():
	var file = FileAccess.open("user://streak.json", FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify({
		"daily_streak":              daily_streak,
		"last_streak_date":          last_streak_date,
		"streak_freeze_count":       streak_freeze_count,
		"last_celebrated_milestone": _last_celebrated_milestone,
		"consecutive_logging_days":   consecutive_logging_days
	}))
	file.close()

func load_streak():
	if not FileAccess.file_exists("user://streak.json"): return
	var file = FileAccess.open("user://streak.json", FileAccess.READ)
	if file == null: return
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data or not data is Dictionary: return
	daily_streak              = data.get("daily_streak", 0)
	last_streak_date          = data.get("last_streak_date", "")
	streak_freeze_count       = data.get("streak_freeze_count", 1)
	_last_celebrated_milestone = data.get("last_celebrated_milestone", 0)
	consecutive_logging_days  = data.get("consecutive_logging_days", 0)

func _get_yesterday_string() -> String:
	var unix = Time.get_unix_time_from_system() - 86400
	var dt   = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]

func _days_between(date_a: String, date_b: String) -> int:
	# Parse both strings and compute difference in days
	var a = date_a.split("-")
	var b = date_b.split("-")
	var unix_a = Time.get_unix_time_from_datetime_dict({
		"year":int(a[0]),"month":int(a[1]),"day":int(a[2]),
		"hour":12,"minute":0,"second":0
	})
	var unix_b = Time.get_unix_time_from_datetime_dict({
		"year":int(b[0]),"month":int(b[1]),"day":int(b[2]),
		"hour":12,"minute":0,"second":0
	})
	return int(abs(unix_b - unix_a) / 86400)
	


func award_py(amount: int, reason: String = ""):
	py_currency     += amount
	py_earned_today += amount   # ← track today's earnings
	save_currency()
	py_awarded.emit(amount, reason)

func save_currency():
	var file = FileAccess.open("user://currency.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"py":                     py_currency,
		"py_earned_today":        py_earned_today,
		"last_streak_milestone":  _last_celebrated_milestone
	}))
	file.close()

func load_currency():
	if not FileAccess.file_exists("user://currency.json"): return
	var file = FileAccess.open("user://currency.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	py_currency              = data.get("py", 0)
	py_earned_today          = data.get("py_earned_today", 0)
	_last_celebrated_milestone = data.get("last_streak_milestone", 0)


func generate_daily_quests():
	var today = Time.get_date_string_from_system()
	# Use date as seed so quests are deterministic for a given day
	seed(today.hash())
	var all_quests = _get_all_quest_definitions()
	all_quests.shuffle()
	today_quests = all_quests.slice(0, 3)

func _get_all_quest_definitions() -> Array:
	return [
		{"id":"water_2l",   "desc":"Drink 2L of water",           "field":"water_ml",     "target":2000, "pts":2, "gems":5},
		{"id":"vit_d",      "desc":"Eat a food with Vitamin D",   "field":"vitamin_d_mcg","target":5,    "pts":1, "gems":3},
		{"id":"fiber",      "desc":"Hit your fiber goal",         "field":"fiber_g",      "target":-1,   "pts":1, "gems":3},
		{"id":"lycopene",   "desc":"Eat a lycopene-rich food",    "field":"lycopene_mcg", "target":1000, "pts":1, "gems":3},
		{"id":"vegetables", "desc":"Eat 3 different vegetables",  "field":"veg_count",    "target":3,    "pts":2, "gems":5},
		{"id":"kcal_goal",  "desc":"Stay within 10% of kcal goal","field":"kcal_ratio",   "target":1,    "pts":3, "gems":8},
		{"id":"5_micros",   "desc":"Hit 5 micronutrient RDAs",    "field":"micro_count",  "target":5,    "pts":5, "gems":15},
		{"id":"streak",     "desc":"Maintain your streak",        "field":"streak",       "target":1,    "pts":1, "gems":10},
		{"id":"shopping",   "desc":"Add 5 items to shopping list","field":"shop_count",   "target":5,    "pts":1, "gems":2},
		{"id":"meal_plan",  "desc":"Plan a meal",                 "field":"meal_planned", "target":1,    "pts":2, "gems":5},
	]
	
func get_personalized_quests() -> Array:
	var today = Time.get_date_string_from_system()
	if quest_date == today and not today_quests.is_empty():
		# Quests already built for today — just ensure check callables are present
		if today_quests[0].has("check"):
			return today_quests
		# Rebuild callables if missing (e.g. after load)
		var full_pool = _build_quest_pool()
		for i in range(today_quests.size()):
			var qid = today_quests[i].get("id","")
			for pq in full_pool:
				if pq.get("id","") == qid:
					today_quests[i]["check"] = pq["check"]
					break
		return today_quests

	quest_date = today
	# DO NOT clear completed_quest_ids here — they were loaded from disk
	# Only clear if it's genuinely a new day
	if quest_date != today:
		completed_quest_ids.clear()

	seed(today.hash() + daily_streak)
	var pool = _build_quest_pool()
	pool.shuffle()
	var core_quests  = pool.filter(func(q): return q.get("tier") == "core")
	var bonus_quests = pool.filter(func(q): return q.get("tier") == "bonus")
	today_quests = core_quests.slice(0, 3) + bonus_quests.slice(0, 2)
	save_quests()
	return today_quests

func _build_quest_pool() -> Array:
	var c   = active_metabolic_conditions
	var bm  = body_metrics
	var is_female = bm.get("is_female", false)
	var weight    = bm.get("weight", 70.0)
	var water_goal_ml = daily_water_liters * 1000.0
	var pool: Array = []

	# ── UNIVERSAL CORE QUESTS (everyone gets these in pool) ──
	pool.append({
		"id": "streak_maintain",
		"desc": "Log at least one meal today",
		"tier": "core", "py": 10,
		"check": func(totals): return totals.get("calories", 0.0) > 50
	})
	pool.append({
		"id": "water_goal",
		"desc": "Reach your daily water goal (" + str(snappedf(daily_water_liters,1)) + "L)",
		"tier": "core", "py": 10,
		"check": func(totals): return totals.get("water_ml", 0.0) >= water_goal_ml
	})
	pool.append({
		"id": "kcal_goal",
		"desc": "Stay within 15% of your calorie goal",
		"tier": "core", "py": 10,
		"check": func(totals):
			var goal = bm.get("daily_goal", 0.0)
			if goal <= 0: return false
			var kcal = totals.get("calories", 0.0)
			return kcal >= goal * 0.85 and kcal <= goal * 1.15
	})
	pool.append({
		"id": "fiber_goal",
		"desc": "Hit your fiber goal",
		"tier": "core", "py": 10,
		"check": func(totals):
			var goal = 25.0 if is_female else 38.0
			return totals.get("fiber_g", 0.0) >= goal
	})
	pool.append({
		"id": "protein_goal",
		"desc": "Hit your protein goal (" + str(snappedf(weight * 0.8, 0)) + "g)",
		"tier": "core", "py": 10,
		"check": func(totals):
			return totals.get("protein_g", 0.0) >= weight * 0.8
	})
	pool.append({
		"id": "vit_c",
		"desc": "Eat a food rich in Vitamin C",
		"tier": "core", "py": 10,
		"check": func(totals): return totals.get("vitamin_c_mg", 0.0) >= 30.0
	})
	pool.append({
		"id": "eat_3_categories",
		"desc": "Eat foods from 3 different categories",
		"tier": "core", "py": 10,
		"check": func(totals): return totals.get("_category_count", 0) >= 3
	})

	# ── CONDITION-SPECIFIC CORE QUESTS ──
	if kidney_at_risk:
		pool.append({
			"id": "kidney_oxalate",
			"desc": "Keep daily oxalates under 50mg",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("oxalate_mg", 0.0) < 50.0
		})
		pool.append({
			"id": "kidney_water",
			"desc": "Drink 2.5L+ of water today",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("water_ml", 0.0) >= 2500.0
		})

	if c.has("glycemic-health"):
		pool.append({
			"id": "glycemic_sugar",
			"desc": "Keep added sugar under 25g",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("sugar_g", 0.0) < 25.0
		})
		pool.append({
			"id": "glycemic_fiber",
			"desc": "Eat 14g fiber per 1000 kcal",
			"tier": "core", "py": 10,
			"check": func(totals):
				var kcal = totals.get("calories", 1.0)
				var fiber = totals.get("fiber_g", 0.0)
				return fiber >= (kcal / 1000.0) * 14.0
		})

	if c.has("nafld"):
		pool.append({
			"id": "nafld_no_alcohol",
			"desc": "Avoid all alcohol today",
			"tier": "core", "py": 10,
			"check": func(totals): return true  # trust-based — no alcohol field
		})
		pool.append({
			"id": "nafld_sat_fat",
			"desc": "Keep saturated fat under 10g",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("saturated_fat_g", 0.0) < 10.0
		})

	if c.has("lipid-health"):
		pool.append({
			"id": "lipid_fiber",
			"desc": "Eat 30g+ of fiber (heart-protective)",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("fiber_g", 0.0) >= 30.0
		})

	if c.has("osteoporosis"):
		pool.append({
			"id": "osteo_calcium",
			"desc": "Hit 1200mg of calcium today",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("calcium_mg", 0.0) >= 1200.0
		})
		pool.append({
			"id": "osteo_vit_d",
			"desc": "Eat a food with Vitamin D",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("vitamin_d_mcg", 0.0) >= 5.0
		})

	if c.has("thyroid-health") or c.has("graves-disease"):
		pool.append({
			"id": "thyroid_selenium",
			"desc": "Eat a selenium-rich food",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("selenium_mcg", 0.0) >= 30.0
		})

	if c.has("crohns-disease"):
		pool.append({
			"id": "crohns_small_meals",
			"desc": "Log 4+ separate meals/snacks today",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("_meal_count", 0) >= 4
		})

	if c.has("epi"):
		pool.append({
			"id": "epi_kcal",
			"desc": "Hit 32.5 kcal/kg target (" + str(snappedf(weight * 32.5, 0)) + " kcal)",
			"tier": "core", "py": 10,
			"check": func(totals):
				return totals.get("calories", 0.0) >= weight * 30.0
		})

	if c.has("hemochromatosis"):
		pool.append({
			"id": "hemo_no_vit_c",
			"desc": "Keep Vitamin C under 75mg today",
			"tier": "core", "py": 10,
			"check": func(totals): return totals.get("vitamin_c_mg", 0.0) <= 75.0
		})

	# ── BONUS QUESTS (optional, 30 PY) ──
	pool.append({
		"id": "bonus_vit_d",
		"desc": "Hit your full Vitamin D RDA",
		"tier": "bonus", "py": 30,
		"check": func(totals): return totals.get("vitamin_d_mcg", 0.0) >= 15.0
	})
	pool.append({
		"id": "bonus_rainbow",
		"desc": "Eat 5+ different food categories",
		"tier": "bonus", "py": 30,
		"check": func(totals): return totals.get("_category_count", 0) >= 5
	})
	pool.append({
		"id": "bonus_polyphenols",
		"desc": "Eat 500mg+ of polyphenols",
		"tier": "bonus", "py": 30,
		"check": func(totals): return totals.get("total_polyphenols_mg", 0.0) >= 500.0
	})
	pool.append({
		"id": "bonus_lycopene",
		"desc": "Eat a lycopene-rich food (tomato, watermelon)",
		"tier": "bonus", "py": 30,
		"check": func(totals): return totals.get("lycopene_mcg", 0.0) >= 2000.0
	})
	pool.append({
		"id": "bonus_b12",
		"desc": "Hit your Vitamin B12 RDA",
		"tier": "bonus", "py": 30,
		"check": func(totals): return totals.get("vitamin_b12_mcg", 0.0) >= 2.4
	})
	pool.append({
		"id": "bonus_magnesium",
		"desc": "Hit your magnesium goal",
		"tier": "bonus", "py": 30,
		"check": func(totals):
			var goal = 310.0 if is_female else 400.0
			return totals.get("magnesium_mg", 0.0) >= goal
	})
	pool.append({
		"id": "bonus_water_extra",
		"desc": "Drink 500mL beyond your water goal",
		"tier": "bonus", "py": 30,
		"check": func(totals): return totals.get("water_ml", 0.0) >= water_goal_ml + 500.0
	})

	# ── CONDITION-SPECIFIC BONUS QUESTS ──
	if c.has("nafld"):
		pool.append({
			"id": "bonus_nafld_vit_e",
			"desc": "Eat 15mg+ Vitamin E today (NAFLD support)",
			"tier": "bonus", "py": 30,
			"check": func(totals): return totals.get("vitamin_e_mg", 0.0) >= 15.0
		})

	if c.has("glycemic-health"):
		pool.append({
			"id": "bonus_glycemic_quercetin",
			"desc": "Eat quercetin-rich foods (10mg+)",
			"tier": "bonus", "py": 30,
			"check": func(totals): return totals.get("quercetin_mg", 0.0) >= 10.0
		})

	if c.has("lipid-health"):
		pool.append({
			"id": "bonus_lipid_lycopene",
			"desc": "Eat 8000mcg+ lycopene (cardioprotective)",
			"tier": "bonus", "py": 30,
			"check": func(totals): return totals.get("lycopene_mcg", 0.0) >= 8000.0
		})

	if c.has("osteoporosis"):
		pool.append({
			"id": "bonus_osteo_k2",
			"desc": "Eat a food with Vitamin K2",
			"tier": "bonus", "py": 30,
			"check": func(totals): return totals.get("vitamin_k2_mcg", 0.0) >= 10.0
		})

	return pool

func check_quests(today_totals: Dictionary):
	for quest in today_quests:
		var qid = quest.get("id","")
		if completed_quest_ids.has(qid): continue
		var check_fn = quest.get("check", null)
		if not check_fn is Callable: continue
		if check_fn.call(today_totals):
			completed_quest_ids.append(qid)
			var py = quest.get("py", 10)
			award_py(py, quest.get("desc",""))
			quest_completed.emit(quest)
	save_quests()

func save_quests():
	var saveable = today_quests.map(func(q): return {
		"id":   q.get("id",""),
		"desc": q.get("desc",""),
		"tier": q.get("tier","core"),
		"py":   q.get("py", 10)
		# deliberately omit "check"
	})
	var file = FileAccess.open("user://quests.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"date": quest_date,
		"quests": today_quests,
		"completed": completed_quest_ids
	}))
	file.close()

func load_quests():
	if not FileAccess.file_exists("user://quests.json"): return
	var file = FileAccess.open("user://quests.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	var today = Time.get_date_string_from_system()
	if data.get("date","") != today: return  # stale — regenerate
	quest_date          = data.get("date","")
	completed_quest_ids = data.get("completed",[])

	# Rebuild the full quest objects with their check callables
	# by matching saved ids against the full pool
	var saved_ids = data.get("quests",[]).map(func(q): return q.get("id",""))
	var full_pool = _build_quest_pool()
	today_quests  = full_pool.filter(func(q): return saved_ids.has(q.get("id","")))


func get_current_league() -> Dictionary:
	var all_time = get_points_alltime()
	var idx = 0
	for i in range(LEAGUE_THRESHOLDS.size()):
		if all_time >= LEAGUE_THRESHOLDS[i]:
			idx = i
	current_league_idx = idx
	return {
		"index": idx,
		"name":  LEAGUE_NAMES[idx],
		"pts_to_next": LEAGUE_THRESHOLDS[min(idx+1, LEAGUE_THRESHOLDS.size()-1)] - int(all_time),
		"progress_pct": _league_progress_pct(idx, int(all_time))
	}

func _league_progress_pct(idx: int, all_time: int) -> float:
	if idx >= LEAGUE_THRESHOLDS.size() - 1: return 1.0
	var lo = LEAGUE_THRESHOLDS[idx]
	var hi = LEAGUE_THRESHOLDS[idx + 1]
	return clamp(float(all_time - lo) / float(hi - lo), 0.0, 1.0)

func get_current_season() -> Dictionary:
	var month = Time.get_datetime_dict_from_system().get("month", 1)
	for season in SEASONS:
		if season["months"].has(month):
			return season
	return SEASONS[0]

func get_season_bonus_pts(today_totals: Dictionary, foods_eaten: Array) -> int:
	var season = get_current_season()
	var bonus  = 0
	# Bonus for specific foods eaten
	if not season["bonus_foods"].is_empty():
		for fid in season["bonus_foods"]:
			for fname in foods_eaten:
				if fname.to_lower().contains(fid):
					bonus += season["bonus_pts"]
					break
	# Bonus for field threshold
	if season.has("bonus_field") and season["bonus_field"] != "":
		var field = season["bonus_field"]
		var threshold = season.get("bonus_threshold", 0.0)
		if today_totals.get(field, 0.0) >= threshold:
			bonus += season["bonus_pts"]
	return bonus

func check_badges():
	for badge in ALL_BADGES:
		var bid = badge["id"]
		if earned_badges.has(bid): continue
		var check_fn = badge.get("check", null)
		if check_fn == null: continue
		if not check_fn.call(self): continue
		earned_badges.append(bid)
		save_badges()
		badge_earned.emit(badge)

func award_badge(bid: String):
	if earned_badges.has(bid): return
	for badge in ALL_BADGES:
		if badge["id"] == bid:
			earned_badges.append(bid)  # ← this was also missing in the original
			save_badges()
			badge_earned.emit(badge)
			return

func save_badges():
	var file = FileAccess.open("user://badges.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"badges": earned_badges}))
	file.close()

func load_badges():
	if not FileAccess.file_exists("user://badges.json"): return
	var file = FileAccess.open("user://badges.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data: earned_badges = data.get("badges",[])

func should_show_weekly_report() -> bool:
	var dt      = Time.get_datetime_dict_from_system()
	var weekday = dt.get("weekday", 0)  # 0=Sun, 1=Mon
	var today   = Time.get_date_string_from_system()
	# Show on Monday if not shown yet today
	return weekday == 1 and last_report_date != today

func mark_report_shown():
	last_report_date = Time.get_date_string_from_system()
	var file = FileAccess.open("user://report_date.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"date": last_report_date}))
	file.close()

func load_report_date():
	if not FileAccess.file_exists("user://report_date.json"): return
	var file = FileAccess.open("user://report_date.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data: last_report_date = data.get("date","")

var simple_mode: bool = false
var accessibility_large_font: bool = false

func save_ui_settings():
	var file = FileAccess.open("user://ui_settings.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"simple_mode":   simple_mode,
		"large_font":    accessibility_large_font
	}))
	file.close()

func load_ui_settings():
	if not FileAccess.file_exists("user://ui_settings.json"): return
	var file = FileAccess.open("user://ui_settings.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	simple_mode              = data.get("simple_mode", false)
	accessibility_large_font = data.get("large_font", false)

func get_strict_avoid_conditions(food: Dictionary) -> Array:
	var food_name = food.get("name","").to_lower()
	var food_id   = food.get("id","").to_lower()
	var cat       = food.get("category","").to_lower()
	var result: Array = []

	# Build keyword → food matching
	# Each entry in strict_avoid is a descriptive string — we match keywords
	var STRICT_KEYWORD_MAP = {
		"graves-disease": [
			{"keywords":["seaweed","kelp","nori","wakame","spirulina","kombu"], "ids":["seaweed","wakame","kelp"]},
			{"keywords":["oyster","shrimp"], "ids":["oyster","shrimp","scampi"]},
		],
		"thyroid-health": [
			{"keywords":["seaweed","kelp","nori","wakame"], "ids":["seaweed","wakame","kelp"]},
			{"keywords":["millet"], "ids":["millet"]},
			{"keywords":["cassava"], "ids":["cassava"]},
		],
		"celiac-disease": [
			{"keywords":["wheat","spelt","rye","barley","oat"], "ids":["rye","spelt","oatmeal","oats","barley","khorasan-wheat"]},
		],
		"hemochromatosis": [
			{"keywords":["beef","lamb","venison","pork","liver","kidney","blood","organ"],
			 "ids":["ground-beef","beef-steak","lamb","veal","pork-tenderloin","pork-shoulder","pork-chop","bacon","reindeer","elk"]},
			{"keywords":["shellfish","oyster","shrimp","lobster","crab"],
			 "ids":["shrimp","lobster","crab","scampi"]},
		],
		"crohns-disease": [
			{"keywords":["raw vegetable","fried","processed meat","shellfish"],
			 "ids":["bacon","sausage","meatballs","shrimp","lobster","crab","scampi"]},
		],
		"nafld": [
			{"keywords":["sugary","soda","juice","fructose","trans fat","ultra-processed"], "ids":[]},
		],
		"epi": [
			{"keywords":["alcohol"], "ids":[]},
		],
		"post-cholecystectomy": [
			{"keywords":["fried","trans fat"], "ids":[]},
		],
	}

	for condition in active_metabolic_conditions:
		if not STRICT_KEYWORD_MAP.has(condition): continue
		for entry in STRICT_KEYWORD_MAP[condition]:
			# Check by food id first (most reliable)
			for sid in entry["ids"]:
				if food_id == sid or food_id.begins_with(sid):
					if not result.has(condition):
						result.append(condition)
					break
			if result.has(condition): break
			# Check by name keywords
			for keyword in entry["keywords"]:
				if food_name.contains(keyword):
					if not result.has(condition):
						result.append(condition)
					break
			if result.has(condition): break

	# Special: celiac — use contains_gluten field (most reliable)
	if active_metabolic_conditions.has("celiac-disease"):
		if food.get("contains_gluten", false):
			if not result.has("celiac-disease"):
				result.append("celiac-disease")

	return result

# In Global.gd — add this function:
func calculate_today_points(today_totals: Dictionary, water_ml: float) -> float:
	var kcal       = today_totals.get("calories", 0.0)
	var daily_goal = body_metrics.get("daily_goal", 0.0)
	var bmr        = body_metrics.get("bmr", 0.0)
	var goal_weight = body_metrics.get("goal_weight", 0.0)
	var weight      = body_metrics.get("weight", 0.0)

	# ── Kcal points ──
	var kcal_pts = 0.0
	if bmr > 0 and daily_goal > 0 and goal_weight > 0 and weight > 0:
		if goal_weight > weight:
			if kcal >= daily_goal:
				kcal_pts = 1.0 + floor((kcal - daily_goal) / 500.0)
		elif goal_weight < weight:
			if kcal <= daily_goal and kcal >= bmr:
				kcal_pts = 1.0 + floor((daily_goal - kcal) / 500.0)
		else:
			if abs(kcal - daily_goal) <= daily_goal * 0.1:
				kcal_pts = 1.0

	# ── Water points ──
	var water_goal_ml = daily_water_liters * 1000.0
	var water_pts = 0.0
	if water_goal_ml > 0 and water_ml >= water_goal_ml:
		water_pts = 1.0 + floor((water_ml - water_goal_ml) / 500.0)

	# ── Strict avoid penalty (loaded from today's log) ──
	var penalty = points_history.get("_penalty_" + Time.get_date_string_from_system(), 0.0)

	# ── Oxalate penalty ──
	var oxalate_penalty = 0.0
	if kidney_at_risk:
		var ox = today_totals.get("oxalate_mg", 0.0)
		var ca = today_totals.get("calcium_mg", 0.0)
		if ox > 50.0:
			oxalate_penalty -= floor((ox - 50.0) / 50.0)
		var ratio = ox / max(ca, 1.0)
		if ratio > 0.5:
			oxalate_penalty -= floor((ratio - 0.5) / 0.5)

	return kcal_pts + water_pts + penalty + oxalate_penalty

func calculate_and_save_points(today_totals: Dictionary, water_ml_val: float, foods_eaten: Array = []):
	var today      = Time.get_date_string_from_system()
	var daily_goal = body_metrics.get("daily_goal", 0.0)
	var bmr        = body_metrics.get("bmr", 0.0)
	var goal_w     = body_metrics.get("goal_weight", 0.0)
	var weight     = body_metrics.get("weight", 0.0)
	var kcal       = today_totals.get("calories", 0.0)

	var pts = 0.0

	# ── Kcal points: 1 pt for being within goal, +1 per 500 in right direction ──
	if daily_goal > 0 and bmr > 0:
		if goal_w > weight:          # gaining
			if kcal >= daily_goal:
				pts += 1.0 + floor((kcal - daily_goal) / 500.0)
		elif goal_w < weight:        # losing
			if kcal >= bmr and kcal <= daily_goal:
				pts += 1.0 + floor((daily_goal - kcal) / 500.0)
		else:                        # maintenance
			if kcal >= daily_goal * 0.85 and kcal <= daily_goal * 1.15:
				pts += 1.0

	# ── Water points: 1 pt at goal, +1 per extra 500mL ──
	var water_goal_ml = daily_water_liters * 1000.0
	var water_max_ml  = water_goal_ml * 1.15
	if water_goal_ml > 0 and water_ml_val >= water_goal_ml:
		var effective_ml = min(water_ml_val, water_max_ml)
		pts += 1.0 + floor((effective_ml - water_goal_ml) / 500.0)

	# ── Oxalate penalty ──
	if kidney_at_risk:
		var ox = today_totals.get("oxalate_mg", 0.0)
		var ca = today_totals.get("calcium_mg", 1.0)
		if ox > 50.0:
			pts -= floor((ox - 50.0) / 50.0)
		var ratio = ox / max(ca, 1.0)
		if ratio > 0.5:
			pts -= floor((ratio - 0.5) / 0.5)
	
	# Saturated fat penalty
	var eaten_sat_fat = today_totals.get("saturated_fat_g", 0.0)
	var sat_fat_limit = get_sat_fat_limit_g()
	if sat_fat_limit > 0 and eaten_sat_fat > sat_fat_limit:
		pts -= 1.0
		
	# ── Strict avoid penalty (accumulated separately in points_history["_penalty"]) ──
	var penalty = points_history.get("_penalty_" + today, 0.0)
	pts += penalty

	pts += float(get_season_bonus_pts(today_totals, foods_eaten))
	save_points(today, pts)

func get_tooth_warnings(food: Dictionary) -> Array:
	if not tooth_warn_staining: return []
	var severity = food.get("severity", -1)
	if severity <= 0: return []
	var notes      = food.get("notes", "")
	var mechanisms = food.get("mechanisms", [])
	var sev_label  = ""
	match severity:
		0: sev_label = "Transient only (removed by brushing)"
		1: sev_label = "Mild staining ★"
		2: sev_label = "Moderate staining ★★"
		3: sev_label = "Strong staining ★★★"
	var msg = "🦷 Tooth staining — severity: " + sev_label
	if notes != "":
		msg += "\n" + notes
	if mechanisms.size() > 0:
		msg += "\nMechanism: " + ", ".join(mechanisms)
	return [{"severity": "caution", "message": msg}]

func get_paro_warnings(food: Dictionary) -> Array:
	if not paro_warn: return []
	var safe = food.get("safe for parodontosis check", "yes")
	if safe == "yes": return []
	return [{"severity": "caution", "message": "🦷 This food feeds bacteria / fungi that worsen Parodontosis."}]

func discover_food(food_id: String):
	if not discovered_foods.has(food_id):
		discovered_foods.append(food_id)
		save_discoveries()
		food_discovered.emit(food_id)
		
func save_discoveries():
	var file = FileAccess.open("user://discoveries.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"discovered": discovered_foods}))
	file.close()

func load_discoveries():
	if not FileAccess.file_exists("user://discoveries.json"): return
	var file = FileAccess.open("user://discoveries.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data: discovered_foods = data.get("discovered",[])

func _roll_next_discovery():
	randomize()
	_next_discovery_at = _discovery_counter + (randi() % 8 + 3)  # 3-10 logs

func should_trigger_discovery() -> bool:
	_discovery_counter += 1
	if _next_discovery_at == 0: _roll_next_discovery()
	if _discovery_counter >= _next_discovery_at:
		_roll_next_discovery()
		return true
	return false

const NUTRITIONAL_DISCOVERIES = [
	{"fact":"Broccoli contains more Vitamin C per gram than oranges!", "field":"vitamin_c_mg", "emoji":"🥦"},
	{"fact":"Salmon's omega-3 fatty acids are most bioavailable when eaten at room temperature.", "field":"fat_g", "emoji":"🐟"},
	{"fact":"Lentils have more protein per gram than beef — and no saturated fat!", "field":"protein_g", "emoji":"🫘"},
	{"fact":"Cooking tomatoes increases lycopene availability by 300%!", "field":"lycopene_mcg", "emoji":"🍅"},
	{"fact":"Spinach is richer in iron when eaten with vitamin C — try lemon juice!", "field":"iron_mg", "emoji":"🥬"},
	{"fact":"Eggs contain all 9 essential amino acids — a complete protein.", "field":"protein_g", "emoji":"🥚"},
	{"fact":"Dark berries have 4x more antioxidants than light-coloured fruits.", "field":"anthocyanins_mg", "emoji":"🫐"},
	{"fact":"Almonds are the highest nut source of Vitamin E — bone and skin health.", "field":"vitamin_e_mg", "emoji":"🌰"},
	{"fact":"Fermented foods feed gut bacteria that regulate serotonin production.", "field":"lactose_g", "emoji":"🧫"},
	{"fact":"Magnesium from green vegetables is better absorbed than from supplements.", "field":"magnesium_mg", "emoji":"🌿"},
]

func get_discovery_for_food(food: Dictionary) -> Dictionary:
	# Find a discovery fact relevant to the food's highest nutrient
	var best_key = ""
	var best_val = 0.0
	for key in ["protein_g","vitamin_c_mg","iron_mg","lycopene_mcg","vitamin_e_mg","magnesium_mg"]:
		if food.get(key,0.0) > best_val:
			best_val = food.get(key,0.0)
			best_key = key
	for discovery in NUTRITIONAL_DISCOVERIES:
		if discovery["field"] == best_key:
			return discovery
	# Fallback: random discovery
	return NUTRITIONAL_DISCOVERIES[randi() % NUTRITIONAL_DISCOVERIES.size()]
