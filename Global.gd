extends Node

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

signal any_button_pressed

func calculate_water_recommendation() -> float:
	var is_female = body_metrics.get("is_female", false)
	var weight    = body_metrics.get("weight", 70.0)
	var egfr      = 0.0

	# Check for saved eGFR
	if FileAccess.file_exists("user://metabolic_inputs.json"):
		var file = FileAccess.open("user://metabolic_inputs.json", FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data and data.has("kidney"):
			egfr = data["kidney"].get("egfr", 0.0)

	var liters = 2.5  # baseline

	# CKD stage based on eGFR
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

	# Metabolic conditions override baseline
	for condition in active_metabolic_conditions:
		var rec = 0.0
		match condition:
			"glycemic-health":
				rec = 2.7 if is_female else 3.5
			"nafld":
				rec = 1.75  # 6-8 glasses
			"lipid-health":
				rec = 2.7 if is_female else 3.7
			"thyroid-health":
				rec = 2.1 if is_female else 3.1
			"osteoporosis":
				rec = 1.75  # 6-8 glasses
			"hemochromatosis":
				rec = 2.5
			"wilsons-disease":
				rec = 2.0

		# Take highest recommendation unless CKD restricts
		if not kidney_at_risk and rec > liters:
			liters = rec

	daily_water_liters = liters
	return liters

func calculate_adjusted_kcal_goal() -> Dictionary:
	# CRITICAL: always start from the raw base, never from already-adjusted value
	var base_goal = base_kcal_goal if base_kcal_goal > 0 else body_metrics.get("daily_goal", 0.0)
	var bmr       = body_metrics.get("bmr", 0.0)
	var weight    = body_metrics.get("weight", 0.0)
	var bmi_text  = body_metrics.get("bmi_text", "")
	var is_female = body_metrics.get("is_female", false)

	if base_goal == 0 or bmr == 0:
		return {"adjusted_goal": 0.0, "adjustments": []}

	var adjusted = base_goal  # start fresh every time
	var notes    = []
	var is_overweight = bmi_text.contains("Overweight") or bmi_text.contains("Obese")

	for condition in active_metabolic_conditions:
		match condition:
			"nafld":
				if is_overweight:
					adjusted -= 750.0
					notes.append("NAFLD: −750 kcal/day")
			"glycemic-health":
				if is_overweight:
					adjusted -= 500.0
					notes.append("Glycemic health: −500 kcal/day")
			"lipid-health":
				if is_overweight:
					adjusted -= 300.0
					notes.append("Lipid health: −300 kcal/day")
			"thyroid-health":
				# Hypothyroidism — protect metabolism, floor at BMR+200
				var thyroid_floor = bmr + 200.0
				if adjusted < thyroid_floor:
					adjusted = thyroid_floor
				notes.append("Thyroid: minimum " + str(snappedf(thyroid_floor, 0)) + " kcal (BMR+200)")
			"osteoporosis":
				if adjusted < bmr:
					adjusted = bmr
				notes.append("Osteoporosis: minimum BMR (" + str(snappedf(bmr, 0)) + " kcal)")
			"crohns-disease":
				var extra = weight * 2.9 + 600.0
				adjusted += extra
				notes.append("Crohn's: +" + str(snappedf(extra, 0)) + " kcal hypermetabolism")
			"celiac-disease":
				if is_overweight:
					adjusted -= 200.0
					notes.append("Celiac: −200 kcal GFD weight management")
			"lactose-intolerance":
				adjusted += 150.0
				notes.append("Lactose intolerance: +150 kcal dairy compensation")
			"epi":
				var epi_target = weight * 32.5
				if epi_target > adjusted:
					adjusted = epi_target
				notes.append("EPI: " + str(snappedf(adjusted, 0)) + " kcal (32.5 kcal/kg with PERT)")
			"post-cholecystectomy":
				if is_overweight:
					adjusted -= 200.0
					notes.append("Post-cholecystectomy: −200 kcal")

	# Hard floor: never below BMR
	if adjusted < bmr and bmr > 0:
		adjusted = bmr
		notes.append("Floor: BMR minimum (" + str(snappedf(bmr, 0)) + " kcal)")

	return {"adjusted_goal": snappedf(adjusted, 1.0), "adjustments": notes}
	

# ── Metabolic condition risk levels ──
# Set by SettingsPage calculators, read by HomePage + FridgePage
var metabolic_risk_levels: Dictionary = {
	"glycemic-health": "normal",   # normal / prediabetes / diabetes
	"nafld": "normal",             # normal / borderline / elevated
	"lipid-health": "normal",      # normal / borderline / high
	"thyroid-health": "normal",    # normal / subclinical / hypothyroid / hashimotos
	"osteoporosis": "normal",      # normal / borderline / high-turnover
	"hemochromatosis": "normal",   # normal / borderline / overload
	"wilsons-disease": "normal",   # normal / suspicious / likely
	"sulfur-avoidance": "confirmed",   # checkbox only, no calculator
	"crohns-disease": "normal",
	"celiac-disease": "confirmed",     # checkbox only
	"lactose-intolerance": "confirmed",# checkbox only
	"epi": "normal",
	"post-cholecystectomy": "confirmed",# checkbox only
}

# ── Oxalate/kidney warning thresholds ──
var conditions_data = {
	"kidney_stones": {
		"label": "Kidney Stones",
		"caution": 10, "avoid": 50,
		"caution_msg": "Moderate oxalate. Limit if prone to kidney stones.",
		"avoid_msg": "High oxalate. Avoid — increases kidney stone risk."
	},
	"hyperoxaluria": {
		"label": "Hyperoxaluria",
		"caution": 5, "avoid": 20,
		"caution_msg": "Contains oxalates. Use caution.",
		"avoid_msg": "High oxalate. Not recommended."
	},
	"gout": {
		"label": "Gout",
		"caution": 50, "avoid": 100,
		"caution_msg": "Monitor intake for gout.",
		"avoid_msg": "Avoid if managing gout."
	}
}

# ── Metabolic warning thresholds per condition ──
var metabolic_warnings_data = {
	"glycemic-health": {
		"label": "Glycemic Health",
		"field": "sugar_g",
		"caution": 5.0, "avoid": 10.0,
		"caution_msg": "Moderate sugar content. Watch portion size.",
		"avoid_msg": "High sugar. Not recommended for diabetes/prediabetes."
	},
	"nafld": {
		"label": "NAFLD",
		"field": "sugar_g",
		"caution": 5.0, "avoid": 10.0,
		"caution_msg": "Contains sugar — limit for liver health.",
		"avoid_msg": "High sugar. Drives hepatic fat accumulation."
	},
	"nafld-fat": {
		"label": "NAFLD",
		"field": "saturated_fat_g",
		"caution": 3.0, "avoid": 6.0,
		"caution_msg": "Moderate saturated fat — limit for liver health.",
		"avoid_msg": "High saturated fat. Avoid with NAFLD."
	},
	"lipid-health": {
		"label": "Lipid Health",
		"field": "saturated_fat_g",
		"caution": 3.0, "avoid": 5.0,
		"caution_msg": "Moderate saturated fat. Limit for cholesterol management.",
		"avoid_msg": "High saturated fat. Avoid — raises LDL cholesterol."
	},
	"hemochromatosis": {
		"label": "Hemochromatosis",
		"field": "iron_mg",
		"caution": 3.0, "avoid": 6.0,
		"caution_msg": "Moderate iron content. Limit with iron overload.",
		"avoid_msg": "High iron. Avoid — worsens iron overload."
	},
	"wilsons-disease": {
		"label": "Wilson's Disease",
		"field": "copper_mg",
		"caution": 0.3, "avoid": 0.5,
		"caution_msg": "Moderate copper. Limit with Wilson's disease.",
		"avoid_msg": "High copper. Avoid — toxic with Wilson's disease."
	},
	"osteoporosis-sodium": {
		"label": "Osteoporosis",
		"field": "sodium_mg",
		"caution": 300.0, "avoid": 600.0,
		"caution_msg": "Moderate sodium — can increase calcium loss.",
		"avoid_msg": "High sodium. Avoid — significantly increases calcium loss."
	},
		"sulfur-avoidance": {
		"label": "Sulfur Avoidance",
		"field": "sulfur_mg",
		"caution": 80.0, "avoid": 150.0,
		"caution_msg": "Moderate sulfur content — may cause gas/bloating.",
		"avoid_msg": "High sulfur food — avoid if sensitive to sulfur compounds."
	},
	"crohns-disease-fiber": {
		"label": "Crohn's Disease",
		"field": "fiber_g",
		"caution": 2.0, "avoid": 4.0,
		"caution_msg": "Moderate fiber — limit during active flares.",
		"avoid_msg": "High fiber — avoid during Crohn's flares or with strictures."
	},
	"celiac-disease": {
		"label": "Celiac Disease",
		"field": "contains_gluten",
		"caution": 0.5, "avoid": 0.5,
		"caution_msg": "Contains gluten — avoid with celiac disease.",
		"avoid_msg": "Contains gluten — strictly avoid with celiac disease."
},
	"lactose-intolerance": {
		"label": "Lactose Intolerance",
		"field": "lactose_g",
		"caution": 3.0, "avoid": 6.0,
		"caution_msg": "Contains lactose — may cause discomfort. Limit portion.",
		"avoid_msg": "High lactose content — avoid or use lactase enzyme."
	},
	"epi": {
		"label": "Pancreatic Insufficiency",
		"field": "fat_g",
		"caution": 10.0, "avoid": 20.0,
		"caution_msg": "Moderate fat — take PERT with this meal.",
		"avoid_msg": "High fat content — ensure adequate PERT dosing."
	},
	"post-cholecystectomy": {
		"label": "Post-Cholecystectomy",
		"field": "fat_g",
		"caution": 8.0, "avoid": 15.0,
		"caution_msg": "Moderate fat — eat small portions, chew slowly.",
		"avoid_msg": "High fat — may cause diarrhea post-cholecystectomy. Avoid or split into smaller meals."
	},
}

# ─────────────────────────────────────────
#  MICRONUTRIENT RDAs — sex-aware, condition-adjusted
#  Returns dict: { field_key: { "rda": float, "unit": String, "label": String } }
# ─────────────────────────────────────────
func get_micronutrient_rdas() -> Dictionary:
	var is_female = body_metrics.get("is_female", false)
	var c = active_metabolic_conditions

	# Base RDAs (healthy adult, EFSA/NIH reference)
	var rdas = {
		# Vitamins
		"vitamin_a_mcg":   {"rda": 700.0 if is_female else 900.0,  "unit":"mcg", "label":"Vitamin A"},
		"vitamin_c_mg":    {"rda": 75.0  if is_female else 90.0,   "unit":"mg",  "label":"Vitamin C"},
		"vitamin_d_mcg":   {"rda": 15.0,                           "unit":"mcg", "label":"Vitamin D"},
		"vitamin_e_mg":    {"rda": 15.0,                           "unit":"mg",  "label":"Vitamin E"},
		"vitamin_k2_mcg":  {"rda": 90.0  if is_female else 120.0,  "unit":"mcg", "label":"Vitamin K2"},
		"vitamin_b6_mg":   {"rda": 1.3,                            "unit":"mg",  "label":"Vitamin B6"},
		"vitamin_b9_mcg":  {"rda": 400.0,                          "unit":"mcg", "label":"Folate (B9)"},
		"vitamin_b12_mcg": {"rda": 2.4,                            "unit":"mcg", "label":"Vitamin B12"},
		# Minerals
		"magnesium_mg":    {"rda": 310.0 if is_female else 400.0,  "unit":"mg",  "label":"Magnesium"},
		"potassium_mg":    {"rda": 2600.0 if is_female else 3400.0,"unit":"mg",  "label":"Potassium"},
		"zinc_mg":         {"rda": 8.0   if is_female else 11.0,   "unit":"mg",  "label":"Zinc"},
		"iodine_mcg":      {"rda": 150.0,                          "unit":"mcg", "label":"Iodine"},
		# Antioxidants (no official RDA — using therapeutic targets)
		"beta_carotene_mcg":    {"rda": 3000.0,  "unit":"mcg", "label":"Beta-carotene"},
		"lycopene_mcg":         {"rda": 8000.0,  "unit":"mcg", "label":"Lycopene"},
		"quercetin_mg":         {"rda": 10.0,    "unit":"mg",  "label":"Quercetin"},
		"total_polyphenols_mg": {"rda": 650.0,   "unit":"mg",  "label":"Polyphenols"},
	}

	# ── Condition-specific adjustments ──
	if c.has("nafld"):
		rdas["vitamin_e_mg"]["rda"]         = 800.0  # therapeutic dose for NASH
		rdas["vitamin_c_mg"]["rda"]         = 500.0  # antioxidant support
		rdas["beta_carotene_mcg"]["rda"]    = 6000.0
		rdas["total_polyphenols_mg"]["rda"] = 1000.0

	if c.has("glycemic-health"):
		rdas["vitamin_b6_mg"]["rda"]  = 1.7   # improves insulin sensitivity
		rdas["vitamin_b9_mcg"]["rda"] = 600.0 # reduces homocysteine risk in diabetics
		rdas["magnesium_mg"]["rda"]   = 420.0 if is_female else 500.0  # magnesium deficiency common in T2DM
		rdas["potassium_mg"]["rda"]   = 3500.0 if is_female else 4700.0
		rdas["quercetin_mg"]["rda"]   = 15.0

	if c.has("lipid-health"):
		rdas["potassium_mg"]["rda"]         = 3500.0 if is_female else 4700.0
		rdas["vitamin_b6_mg"]["rda"]        = 1.7
		rdas["vitamin_b9_mcg"]["rda"]       = 600.0
		rdas["lycopene_mcg"]["rda"]         = 10000.0  # cardioprotective
		rdas["quercetin_mg"]["rda"]         = 15.0
		rdas["total_polyphenols_mg"]["rda"] = 1000.0

	if c.has("thyroid-health"):
		rdas["iodine_mcg"]["rda"]    = 150.0   # careful — not too high
		rdas["selenium_mcg"]         = {"rda": 200.0, "unit":"mcg", "label":"Selenium"}
		rdas["zinc_mg"]["rda"]       = 10.0 if is_female else 15.0
		rdas["vitamin_d_mcg"]["rda"] = 25.0   # higher for autoimmune support

	if c.has("osteoporosis"):
		rdas["vitamin_d_mcg"]["rda"]  = 20.0
		rdas["vitamin_k2_mcg"]["rda"] = 180.0 if is_female else 200.0  # MK-7 for bone
		rdas["magnesium_mg"]["rda"]   = 420.0 if is_female else 500.0
		rdas["vitamin_c_mg"]["rda"]   = 100.0  # collagen synthesis

# Hemochromatosis — cap vitamin C (enhances iron absorption)
	if c.has("hemochromatosis"):
		rdas["vitamin_c_mg"]["rda"]    = 75.0    # lower limit
		rdas["calcium_mg"]             = {"rda":1200.0, "unit":"mg", "label":"Calcium"}
		
	if c.has("wilsons-disease"):
		# Copper and zinc already tracked
		rdas["zinc_mg"]["rda"] = 25.0 if is_female else 40.0  # pharmacological zinc blocks copper
		
# Crohn's
	if c.has("crohns-disease"):
		rdas["vitamin_b12_mcg"]["rda"] = 1000.0  # therapeutic
		rdas["vitamin_b9_mcg"]["rda"]  = 800.0
		rdas["vitamin_d_mcg"]["rda"]   = 37.5    # 25-50 mid
		rdas["calcium_mg"]             = {"rda":1350.0, "unit":"mg", "label":"Calcium"}
		rdas["zinc_mg"]["rda"]         = 32.5     # 25-40 mid
		rdas["magnesium_mg"]["rda"]    = 400.0

	# Celiac
	if c.has("celiac-disease"):
		rdas["vitamin_d_mcg"]["rda"]   = 37.5
		rdas["vitamin_b9_mcg"]["rda"]  = 600.0
		rdas["calcium_mg"]             = {"rda":1350.0, "unit":"mg", "label":"Calcium"}
		rdas["zinc_mg"]["rda"]         = 32.5

	# EPI
	if c.has("epi"):
		rdas["vitamin_a_mcg"]["rda"]   = 1500.0
		rdas["vitamin_d_mcg"]["rda"]   = 37.5
		rdas["vitamin_e_mg"]["rda"]    = 250.0   # 100-400 IU converted to mg
		rdas["vitamin_k1_mcg"]         = {"rda":1000.0, "unit":"mcg", "label":"Vitamin K1"}

	# Lactose intolerance — calcium from non-dairy sources
	if c.has("lactose-intolerance"):
		rdas["calcium_mg"]             = {"rda":1200.0, "unit":"mg", "label":"Calcium"}

	if kidney_at_risk:
		# CKD — restrict potassium and phosphorus
		rdas["potassium_mg"]["rda"] = 2000.0  # restriction
		rdas.erase("vitamin_c_mg")  # large doses harmful in CKD

	return rdas

# ── Which micronutrients to show on HomePage ──
func get_visible_micronutrients() -> Array:
	var c = active_metabolic_conditions
	var visible = []

	# Always show
	visible.append_array(["vitamin_a_mcg","vitamin_c_mg","vitamin_d_mcg","vitamin_b12_mcg","magnesium_mg"])

	# Condition-specific
	if c.has("nafld") or c.has("thyroid-health") or c.has("osteoporosis"):
		if not visible.has("vitamin_e_mg"): visible.append("vitamin_e_mg")
	if c.has("osteoporosis"):
		if not visible.has("vitamin_k2_mcg"): visible.append("vitamin_k2_mcg")
	if c.has("glycemic-health") or c.has("lipid-health"):
		for f in ["vitamin_b6_mg","vitamin_b9_mcg","potassium_mg","quercetin_mg"]:
			if not visible.has(f): visible.append(f)
	if c.has("thyroid-health"):
		for f in ["iodine_mcg","zinc_mg"]:
			if not visible.has(f): visible.append(f)
	if c.has("nafld"):
		for f in ["beta_carotene_mcg","total_polyphenols_mg"]:
			if not visible.has(f): visible.append(f)
	if c.has("lipid-health"):
		for f in ["lycopene_mcg","total_polyphenols_mg"]:
			if not visible.has(f): visible.append(f)
	if c.has("crohns-disease"):
		for f in ["vitamin_b12_mcg","vitamin_d_mcg","zinc_mg","magnesium_mg"]:
			if not visible.has(f): visible.append(f)
	if c.has("celiac-disease"):
		for f in ["vitamin_b9_mcg","vitamin_d_mcg","zinc_mg","iron_mg"]:
			if not visible.has(f): visible.append(f)
	if c.has("epi"):
		for f in ["vitamin_a_mcg","vitamin_d_mcg","vitamin_e_mg","vitamin_k2_mcg"]:
			if not visible.has(f): visible.append(f)
	if c.has("post-cholecystectomy"):
		for f in ["vitamin_d_mcg","vitamin_k2_mcg"]:
			if not visible.has(f): visible.append(f)

	return visible


# ─────────────────────────────────────────
#  STARTUP
# ─────────────────────────────────────────
func _ready():
	load_profile()
	load_points()
	load_body_metrics_from_file()
	load_metabolic_conditions()
	# Create metabolic.json if it doesn't exist yet
	if not FileAccess.file_exists("user://metabolic.json"):
		save_metabolic_conditions()

# ─────────────────────────────────────────
#  WARNINGS — called by FridgePage per food
# ─────────────────────────────────────────
func get_warnings(food: Dictionary) -> Array:
	var warnings = []
	var oxalate = food.get("oxalate_mg_per_100g", 0)

	# Kidney risk (eGFR or known disease)
	if kidney_at_risk:
		if oxalate >= 50:
			warnings.append({"severity": "avoid", "message": "High oxalate — avoid due to kidney risk."})
		elif oxalate >= 10:
			warnings.append({"severity": "caution", "message": "Moderate oxalate — caution due to kidney risk."})

	# Oxalate conditions
	for key in active_conditions:
		if not conditions_data.has(key): continue
		var c = conditions_data[key]
		if oxalate >= c["avoid"]:
			warnings.append({"severity": "avoid", "message": c["avoid_msg"]})
		elif oxalate >= c["caution"]:
			warnings.append({"severity": "caution", "message": c["caution_msg"]})

	# Metabolic conditions
	for condition in active_metabolic_conditions:
		var keys_to_check = [condition]
		if condition == "nafld":
			keys_to_check = ["nafld","nafld-fat"]
		if condition == "crohns-disease":
			keys_to_check = ["crohns-disease-fiber"]

		for wkey in keys_to_check:
			if not metabolic_warnings_data.has(wkey): continue
			var w = metabolic_warnings_data[wkey]
			var field = w["field"]

			# Special case: boolean field (gluten)
			if field == "contains_gluten":
				if food.get("contains_gluten", false):
					warnings.append({"severity":"avoid","message":w["avoid_msg"]})
				break

			var value = food.get(field, 0.0)
			if value >= w["avoid"]:
				warnings.append({"severity":"avoid","message":w["avoid_msg"]})
				break
			elif value >= w["caution"]:
				warnings.append({"severity":"caution","message":w["caution_msg"]})
				break

	return warnings

# ─────────────────────────────────────────
#  PROFILE (kidney + oxalate conditions)
# ─────────────────────────────────────────
func save_profile():
	var file = FileAccess.open("user://profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"conditions": active_conditions,
		"kidney_at_risk": kidney_at_risk,
		"hide_red_warnings": hide_red_warnings
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
		"is_female": data.get("is_female", false)
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
	return points_history.get(today, 0.0)

func get_points_week() -> float:
	var total = 0.0
	var unix_now = Time.get_unix_time_from_system()
	for i in range(7):
		var unix_day = unix_now - (i * 86400)
		var datetime = Time.get_datetime_dict_from_unix_time(unix_day)
		var date = "%04d-%02d-%02d" % [datetime.year, datetime.month, datetime.day]
		total += points_history.get(date, 0.0)
	return total

func get_points_alltime() -> float:
	var total = 0.0
	for val in points_history.values():
		total += val
	return total

func get_macro_goals() -> Dictionary:
	var weight    = body_metrics.get("weight", 70.0)
	var is_female = body_metrics.get("is_female", false)
	var bmi_text  = body_metrics.get("bmi_text", "")
	var daily_kcal = body_metrics.get("daily_goal", 2000.0)
	var is_overweight = bmi_text.contains("Overweight") or bmi_text.contains("Obese")
	var c = active_metabolic_conditions

	# ── Protein (g/day) ──
	var protein_g_per_kg = 0.8
	if is_overweight: protein_g_per_kg = 1.0
	if c.has("crohns-disease"):         protein_g_per_kg = 1.35  # 1.2-1.5 mid
	if c.has("celiac-disease"):         protein_g_per_kg = 0.9
	if c.has("glycemic-health"):        protein_g_per_kg = 1.1
	if c.has("epi"):                    protein_g_per_kg = 1.1
	if c.has("osteoporosis"):           protein_g_per_kg = 1.1
	if c.has("thyroid-health"):         protein_g_per_kg = 0.9
	if c.has("lipid-health"):           protein_g_per_kg = 1.0
	if c.has("hemochromatosis"):        protein_g_per_kg = 0.8
	if c.has("post-cholecystectomy"):   protein_g_per_kg = 0.8
	if c.has("lactose-intolerance"):    protein_g_per_kg = 0.8
	if kidney_at_risk:                  protein_g_per_kg = 0.6  # CKD stage 3
	var protein_goal = weight * protein_g_per_kg

	# ── Fat (g/day from % of kcal) ──
	var fat_pct_min = 0.20
	var fat_pct_max = 0.35
	if c.has("nafld"):
		fat_pct_min = 0.15; fat_pct_max = 0.30
	if c.has("post-cholecystectomy"):
		fat_pct_max = 0.25
	if c.has("epi"):
		# EPI uses absolute grams, not percentage
		var fat_goal_g = 40.0  # 30-50g midpoint
		# fat macro handled separately
		var fat_goal = fat_goal_g
		var fat_min  = fat_goal_g
		var fat_max  = fat_goal_g
		var carb_pct_min = 0.45; var carb_pct_max = 0.65
		var carb_min = (daily_kcal * carb_pct_min) / 4.0
		var carb_max = (daily_kcal * carb_pct_max) / 4.0
		var fiber_goal = 31.5 if is_female else 31.5
		return {
			"protein_g":  snappedf(protein_goal, 0.1),
			"fat_g_min":  fat_min, "fat_g_max": fat_max,
			"carbs_g_min":snappedf(carb_min, 0.1), "carbs_g_max": snappedf(carb_max, 0.1),
			"fiber_g":    fiber_goal
		}
	var fat_min_g = snappedf((daily_kcal * fat_pct_min) / 9.0, 0.1)
	var fat_max_g = snappedf((daily_kcal * fat_pct_max) / 9.0, 0.1)

	# ── Carbs (g/day) ──
	var carb_pct_min = 0.45
	var carb_pct_max = 0.65
	if c.has("glycemic-health"):
		carb_pct_min = 0.40; carb_pct_max = 0.45
	if c.has("nafld"):
		carb_pct_min = 0.40; carb_pct_max = 0.50
	var carb_min_g = snappedf((daily_kcal * carb_pct_min) / 4.0, 0.1)
	var carb_max_g = snappedf((daily_kcal * carb_pct_max) / 4.0, 0.1)

	# ── Fiber (g/day) ──
	var fiber_g = 25.0 if is_female else 38.0
	if c.has("crohns-disease"): fiber_g = 8.0   # <10 during flare
	if c.has("glycemic-health"):
		fiber_g = snappedf(daily_kcal / 1000.0 * 14.0, 0.1)  # 14g per 1000kcal
	if c.has("nafld"):         fiber_g = 34.0
	if c.has("lipid-health"):  fiber_g = 34.0
	if c.has("osteoporosis"):  fiber_g = 31.5
	if c.has("hemochromatosis"): fiber_g = 34.0
	if c.has("celiac-disease"):  fiber_g = 31.5
	if kidney_at_risk:           fiber_g = 25.0

	return {
		"protein_g":   snappedf(protein_goal, 0.1),
		"fat_g_min":   fat_min_g,
		"fat_g_max":   fat_max_g,
		"carbs_g_min": carb_min_g,
		"carbs_g_max": carb_max_g,
		"fiber_g":     fiber_g
	}
