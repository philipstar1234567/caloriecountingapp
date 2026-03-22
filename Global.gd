extends Node

# ── Body metrics (set from SettingsPage) ──
var body_metrics: Dictionary = {
	"bmr": 0.0,
	"tdee": 0.0,
	"daily_goal": 0.0,
	"goal_weight": 0.0,
	"weight": 0.0,
	"bmi_text": "BMI: —",
	"is_female": false
}

# ── Kidney/oxalate conditions ──
var active_conditions: Array = []
var kidney_at_risk: bool = false

# ── Metabolic conditions (Tier 1) ──
var active_metabolic_conditions: Array = []
# Possible values:
# "glycemic-health", "nafld", "lipid-health",
# "thyroid-health", "osteoporosis",
# "hemochromatosis", "wilsons-disease"

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
}

# ─────────────────────────────────────────
#  STARTUP
# ─────────────────────────────────────────
func _ready():
	load_profile()
	load_points()
	load_body_metrics_from_file()
	load_metabolic_conditions()

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
		# Some conditions have multiple checks (nafld checks both sugar and fat)
		var keys_to_check = [condition]
		if condition == "nafld":
			keys_to_check = ["nafld", "nafld-fat"]

		for wkey in keys_to_check:
			if not metabolic_warnings_data.has(wkey): continue
			var w = metabolic_warnings_data[wkey]
			var value = food.get(w["field"], 0.0)
			if value >= w["avoid"]:
				warnings.append({"severity": "avoid", "message": w["avoid_msg"]})
				break  # only one warning per condition
			elif value >= w["caution"]:
				warnings.append({"severity": "caution", "message": w["caution_msg"]})
				break

	return warnings

# ─────────────────────────────────────────
#  PROFILE (kidney + oxalate conditions)
# ─────────────────────────────────────────
func save_profile():
	var file = FileAccess.open("user://profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"conditions": active_conditions,
		"kidney_at_risk": kidney_at_risk
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

# ─────────────────────────────────────────
#  METABOLIC CONDITIONS
# ─────────────────────────────────────────
func save_metabolic_conditions():
	var file = FileAccess.open("user://metabolic.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"conditions": active_metabolic_conditions,
		"risk_levels": metabolic_risk_levels
	}))
	file.close()

func load_metabolic_conditions():
	if not FileAccess.file_exists("user://metabolic.json"): return
	var file = FileAccess.open("user://metabolic.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	active_metabolic_conditions = data.get("conditions", [])
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
