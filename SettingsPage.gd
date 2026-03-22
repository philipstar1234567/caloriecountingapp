extends Control

# ─────────────────────────────────────────
#  Shorthand paths
# ─────────────────────────────────────────
const BASE = "Panel/ScrollContainer/MarginContainer/VBoxContainer/"
const KIDNEY = BASE + "KidneyCarePanel/VBoxContainer/"
const BODY   = BASE + "BodyMetricsPanel/VBoxContainer/"
const GLYC   = BASE + "GlycemicPanel/VBoxContainer/"
const NAFLD  = BASE + "NAFLDPanel/VBoxContainer/"
const LIPID  = BASE + "LipidPanel/VBoxContainer/"
const THYR   = BASE + "ThyroidPanel/VBoxContainer/"
const OSTEO  = BASE + "OsteoPanel/VBoxContainer/"
const HEMO   = BASE + "HemoPanel/VBoxContainer/"
const WILS   = BASE + "WilsonPanel/VBoxContainer/"

func _ready():
	# Kidney care
	get_node(KIDNEY + "KnownDisease").toggled.connect(_on_known_disease_toggled)
	get_node(KIDNEY + "InputFields/CalculateButton").pressed.connect(_on_calculate_egfr)

	# Body metrics
	get_node(BODY + "CalculateButton").pressed.connect(_on_calculate_metrics)

	# Metabolic panels — checkboxes
	get_node(GLYC  + "KnownDiabetes").toggled.connect(func(c): _on_known_metabolic("glycemic-health", c, GLYC))
	get_node(NAFLD + "KnownNAFLD").toggled.connect(func(c):    _on_known_metabolic("nafld", c, NAFLD))
	get_node(LIPID + "KnownLipid").toggled.connect(func(c):    _on_known_metabolic("lipid-health", c, LIPID))
	get_node(THYR  + "KnownThyroid").toggled.connect(func(c):  _on_known_metabolic("thyroid-health", c, THYR))
	get_node(OSTEO + "KnownOsteo").toggled.connect(func(c):    _on_known_metabolic("osteoporosis", c, OSTEO))
	get_node(HEMO  + "KnownHemo").toggled.connect(func(c):     _on_known_metabolic("hemochromatosis", c, HEMO))
	get_node(WILS  + "KnownWilson").toggled.connect(func(c):   _on_known_metabolic("wilsons-disease", c, WILS))

	# Metabolic panels — calculate buttons
	get_node(GLYC  + "InputFields/CalculateButton").pressed.connect(_on_calculate_glycemic)
	get_node(NAFLD + "InputFields/CalculateButton").pressed.connect(_on_calculate_nafld)
	get_node(LIPID + "InputFields/CalculateButton").pressed.connect(_on_calculate_lipid)
	get_node(THYR  + "InputFields/CalculateButton").pressed.connect(_on_calculate_thyroid)
	get_node(OSTEO + "InputFields/CalculateButton").pressed.connect(_on_calculate_osteo)
	get_node(HEMO  + "InputFields/CalculateButton").pressed.connect(_on_calculate_hemo)
	get_node(WILS  + "InputFields/CalculateButton").pressed.connect(_on_calculate_wilson)

	# Reset
	get_node(BASE + "ResetButton").pressed.connect(_on_reset)

	load_kidney_settings()
	load_body_metrics()
	load_metabolic_ui()

# ─────────────────────────────────────────
#  HELPER — known condition checkbox
# ─────────────────────────────────────────
func _on_known_metabolic(condition: String, checked: bool, path: String):
	get_node(path + "InputFields").visible = !checked
	Global.set_metabolic_condition(condition, checked)
	if checked:
		Global.set_metabolic_risk(condition, "confirmed")
		get_node(path + "ResultLabel").text = "⚠️ " + condition.replace("-", " ").capitalize() + " confirmed."
	else:
		Global.set_metabolic_risk(condition, "normal")
		get_node(path + "ResultLabel").text = "—"

# ─────────────────────────────────────────
#  KIDNEY CARE
# ─────────────────────────────────────────
func _on_known_disease_toggled(checked: bool):
	get_node(KIDNEY + "InputFields").visible = !checked
	Global.kidney_at_risk = checked
	if checked:
		get_node(KIDNEY + "RiskLabel").text = "⚠️ Kidney disease flagged."
	else:
		get_node(KIDNEY + "RiskLabel").text = ""
	save_kidney_settings(0.0)
	Global.save_profile()

func _on_calculate_egfr():
	var fields = get_node(KIDNEY + "InputFields")
	var scr       = fields.get_node("CreatinineInput").value
	var age       = fields.get_node("AgeInput").value
	var is_female = Global.body_metrics.get("is_female", false)

	var kappa      = 0.7 if is_female else 0.9
	var alpha      = -0.329 if is_female else -0.411
	var sex_factor = 1.012 if is_female else 1.0
	var ratio = scr / kappa
	var egfr = 142.0 \
		* pow(min(ratio, 1.0), alpha) \
		* pow(max(ratio, 1.0), -1.200) \
		* pow(0.9938, age) \
		* sex_factor
	egfr = snappedf(egfr, 0.1)
	fields.get_node("eGFRLabel").text = "eGFR: " + str(egfr) + " mL/min/1.73m²"

	if egfr <= 60:
		get_node(KIDNEY + "RiskLabel").text = "⚠️ eGFR ≤ 60 — kidney function reduced."
		Global.kidney_at_risk = true
	else:
		get_node(KIDNEY + "RiskLabel").text = "✅ eGFR > 60 — kidney function normal."
		Global.kidney_at_risk = false

	save_kidney_settings(egfr)
	Global.save_profile()

func save_kidney_settings(egfr: float):
	var file = FileAccess.open("user://kidney.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"egfr": egfr,
		"at_risk": Global.kidney_at_risk,
		"known_disease": get_node(KIDNEY + "KnownDisease").button_pressed
	}))
	file.close()

func load_kidney_settings():
	if not FileAccess.file_exists("user://kidney.json"): return
	var file = FileAccess.open("user://kidney.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	Global.kidney_at_risk = data.get("at_risk", false)
	var known = data.get("known_disease", false)
	get_node(KIDNEY + "KnownDisease").button_pressed = known
	get_node(KIDNEY + "InputFields").visible = !known
	if data.has("egfr") and data["egfr"] > 0:
		get_node(KIDNEY + "InputFields/eGFRLabel").text = "eGFR: " + str(data["egfr"]) + " mL/min/1.73m²"

# ─────────────────────────────────────────
#  BODY METRICS
# ─────────────────────────────────────────
func _on_calculate_metrics():
	var panel     = get_node(BODY)
	var weight    = panel.get_node("WeightInput").value
	var height_cm = panel.get_node("HeightInput").value
	var age       = panel.get_node("AgeInput").value
	var activity  = panel.get_node("ActivityOption").selected
	var goal_w    = panel.get_node("GoalWeightInput").value
	var weeks     = panel.get_node("TimeIntervalInput").value
	var is_female = panel.get_node("GenderOption").selected == 1
	var height_m  = height_cm / 100.0

	var bmi = weight / (height_m * height_m)
	bmi = snappedf(bmi, 0.1)
	var bmi_category = ""
	if bmi < 18.5:    bmi_category = "Underweight"
	elif bmi < 25.0:  bmi_category = "Normal"
	elif bmi < 30.0:  bmi_category = "Overweight"
	else:             bmi_category = "Obese"
	var bmi_text = "BMI: " + str(bmi) + " (" + bmi_category + ")"
	panel.get_node("BMIResult").text = bmi_text

	var bmr = 10.0 * weight + 6.25 * height_cm - 5.0 * age
	bmr += -161.0 if is_female else 5.0
	bmr = snappedf(bmr, 1.0)
	panel.get_node("BMRResult").text = "BMR: " + str(bmr) + " kcal/day"

	var tdee_multiplier = [1.2, 1.55, 1.9][activity]
	var tdee = snappedf(bmr * tdee_multiplier, 1.0)
	panel.get_node("TDEEResult").text = "TDEE: " + str(tdee) + " kcal/day"

	var days = weeks * 7.0
	var kcal_adjustment = 7700.0 * (goal_w - weight) / days
	var daily_goal = snappedf(tdee + kcal_adjustment, 1.0)
	var direction = ""
	if goal_w < weight:      direction = "deficit to lose weight"
	elif goal_w > weight:    direction = "surplus to gain weight"
	else:                    direction = "maintenance"
	panel.get_node("GoalResult").text = "Daily goal: " + str(daily_goal) + " kcal (" + direction + ")"

	save_body_metrics(weight, height_cm, age, activity, goal_w, weeks, is_female, bmr, tdee, daily_goal, bmi_text)

func save_body_metrics(weight, height, age, activity, goal_w, weeks, is_female, bmr, tdee, daily_goal, bmi_text):
	var bmi = weight / ((height / 100.0) * (height / 100.0))
	bmi = snappedf(bmi, 0.1)
	var bmi_category = ""
	if bmi < 18.5:    bmi_category = "Underweight"
	elif bmi < 25.0:  bmi_category = "Normal"
	elif bmi < 30.0:  bmi_category = "Overweight"
	else:             bmi_category = "Obese"

	var file = FileAccess.open("user://body_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"weight": weight, "height": height, "age": age,
		"activity": activity, "goal_weight": goal_w, "weeks": weeks,
		"is_female": is_female, "bmr": bmr, "tdee": tdee,
		"daily_goal": daily_goal,
		"bmi_text": "BMI: " + str(bmi) + " (" + bmi_category + ")"
	}))
	file.close()

	Global.body_metrics = {
		"bmr": bmr, "tdee": tdee, "daily_goal": daily_goal,
		"goal_weight": goal_w, "weight": weight,
		"bmi_text": bmi_text, "is_female": is_female
	}

func load_body_metrics():
	if not FileAccess.file_exists("user://body_metrics.json"): return
	var file = FileAccess.open("user://body_metrics.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return

	var panel = get_node(BODY)
	panel.get_node("WeightInput").value       = data.get("weight", 70)
	panel.get_node("HeightInput").value       = data.get("height", 170)
	panel.get_node("AgeInput").value          = data.get("age", 30)
	panel.get_node("ActivityOption").selected = data.get("activity", 0)
	panel.get_node("GoalWeightInput").value   = data.get("goal_weight", 70)
	panel.get_node("TimeIntervalInput").value = data.get("weeks", 12)
	panel.get_node("GenderOption").selected   = 1 if data.get("is_female", false) else 0

	if data.has("bmi_text"):
		panel.get_node("BMIResult").text = data["bmi_text"]
	if data.has("bmr"):
		panel.get_node("BMRResult").text  = "BMR: " + str(data["bmr"]) + " kcal/day"
		panel.get_node("TDEEResult").text = "TDEE: " + str(data["tdee"]) + " kcal/day"
		panel.get_node("GoalResult").text = "Daily goal: " + str(data["daily_goal"]) + " kcal"

	Global.body_metrics = {
		"bmr": data.get("bmr", 0.0), "tdee": data.get("tdee", 0.0),
		"daily_goal": data.get("daily_goal", 0.0),
		"goal_weight": data.get("goal_weight", 0.0),
		"weight": data.get("weight", 0.0),
		"bmi_text": data.get("bmi_text", "BMI: —"),
		"is_female": data.get("is_female", false)
	}

# ─────────────────────────────────────────
#  GLYCEMIC HEALTH
# ─────────────────────────────────────────
func _on_calculate_glycemic():
	var fields    = get_node(GLYC + "InputFields")
	var hba1c     = fields.get_node("HbA1cInput").value
	var fpg       = fields.get_node("FPGInput").value
	var result_lbl = get_node(GLYC + "ResultLabel")

	var risk = "normal"
	var msg = ""

	if hba1c >= 6.5 or fpg >= 126:
		risk = "diabetes"
		msg = "🔴 Diabetes range detected (HbA1c ≥ 6.5% or FPG ≥ 126 mg/dL). Consult your doctor."
	elif hba1c >= 5.7 or fpg >= 100:
		risk = "prediabetes"
		msg = "🟡 Prediabetes range (HbA1c 5.7–6.4% or FPG 100–125 mg/dL). Reduce sugar intake."
	else:
		msg = "✅ Glycemic values appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("glycemic-health", risk)
	if risk != "normal":
		Global.set_metabolic_condition("glycemic-health", true)
	_save_metabolic_inputs("glycemic", {"hba1c": hba1c, "fpg": fpg})

# ─────────────────────────────────────────
#  NAFLD
# ─────────────────────────────────────────
func _on_calculate_nafld():
	var fields     = get_node(NAFLD + "InputFields")
	var alt        = fields.get_node("ALTInput").value
	var ast        = fields.get_node("ASTInput").value
	var trigl      = fields.get_node("TriglInput").value
	var is_female  = Global.body_metrics.get("is_female", false)
	var result_lbl = get_node(NAFLD + "ResultLabel")

	# Sex-specific ALT thresholds
	var alt_upper = 30.0 if is_female else 63.0

	var risk = "normal"
	var msg = ""

	if alt > alt_upper * 2 or ast > 60 or trigl > 150:
		risk = "elevated"
		msg = "🔴 Elevated liver enzymes or triglycerides — NAFLD likely. Restrict sugar and saturated fat."
	elif alt > alt_upper or ast > 30 or trigl > 100:
		risk = "borderline"
		msg = "🟡 Borderline liver values. Monitor diet — reduce sugar and fructose."
	else:
		msg = "✅ Liver markers appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("nafld", risk)
	if risk != "normal":
		Global.set_metabolic_condition("nafld", true)
	_save_metabolic_inputs("nafld", {"alt": alt, "ast": ast, "trigl": trigl})

# ─────────────────────────────────────────
#  LIPID HEALTH
# ─────────────────────────────────────────
func _on_calculate_lipid():
	var fields     = get_node(LIPID + "InputFields")
	var tchol      = fields.get_node("TotalCholInput").value
	var ldl        = fields.get_node("LDLInput").value
	var hdl        = fields.get_node("HDLInput").value
	var trigl      = fields.get_node("TriglInput").value
	var is_female  = Global.body_metrics.get("is_female", false)
	var result_lbl = get_node(LIPID + "ResultLabel")

	# Sex-specific HDL thresholds
	var hdl_low = 50.0 if is_female else 40.0

	var risk = "normal"
	var msg = ""

	if tchol > 200 or ldl > 130 or hdl < hdl_low or trigl > 150:
		risk = "high"
		msg = "🔴 Abnormal lipid levels detected. Reduce saturated fat, increase fiber and omega-3."
	elif tchol > 180 or ldl > 110 or trigl > 100:
		risk = "borderline"
		msg = "🟡 Borderline lipid values. Monitor saturated fat intake."
	else:
		msg = "✅ Lipid levels appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("lipid-health", risk)
	if risk != "normal":
		Global.set_metabolic_condition("lipid-health", true)
	_save_metabolic_inputs("lipid", {"tchol": tchol, "ldl": ldl, "hdl": hdl, "trigl": trigl})

# ─────────────────────────────────────────
#  THYROID HEALTH
# ─────────────────────────────────────────
func _on_calculate_thyroid():
	var fields     = get_node(THYR + "InputFields")
	var tsh        = fields.get_node("TSHInput").value
	var ft4        = fields.get_node("FT4Input").value
	var tpo_pos    = fields.get_node("TPOPositive").button_pressed
	var result_lbl = get_node(THYR + "ResultLabel")

	var risk = "normal"
	var msg = ""

	if tsh > 5.0 and ft4 < 0.7:
		risk = "hypothyroid"
		msg = "🔴 Hypothyroidism detected (TSH > 5.0, FT4 < 0.7). Consult your doctor."
	elif tsh > 5.0:
		risk = "subclinical"
		msg = "🟡 Subclinical hypothyroidism (elevated TSH). Monitor closely."
	elif tsh < 0.4:
		risk = "hyperthyroid"
		msg = "🟡 Possible hyperthyroidism (TSH < 0.4). Consult your doctor."
	else:
		msg = "✅ Thyroid values appear normal."

	if tpo_pos:
		risk = "hashimotos"
		msg += "\n⚠️ TPO antibodies positive — Hashimoto's thyroiditis likely."
		Global.set_metabolic_condition("thyroid-health", true)

	result_lbl.text = msg
	Global.set_metabolic_risk("thyroid-health", risk)
	if risk != "normal":
		Global.set_metabolic_condition("thyroid-health", true)
	_save_metabolic_inputs("thyroid", {"tsh": tsh, "ft4": ft4, "tpo": tpo_pos})

# ─────────────────────────────────────────
#  OSTEOPOROSIS
# ─────────────────────────────────────────
func _on_calculate_osteo():
	var fields     = get_node(OSTEO + "InputFields")
	var ctx        = fields.get_node("CTxInput").value
	var p1np       = fields.get_node("P1NPInput").value
	var is_female  = Global.body_metrics.get("is_female", false)
	var result_lbl = get_node(OSTEO + "ResultLabel")

	# CTx reference: premenopausal F < 600, postmenopausal > 1000 = high
	var ctx_high = 1000.0 if is_female else 800.0
	var ctx_caution = 600.0 if is_female else 500.0

	var risk = "normal"
	var msg = ""

	if ctx > ctx_high or p1np > 75:
		risk = "high-turnover"
		msg = "🔴 High bone turnover markers — significant bone loss likely. Increase calcium and vitamin D."
	elif ctx > ctx_caution or p1np > 50:
		risk = "borderline"
		msg = "🟡 Borderline bone turnover. Ensure adequate calcium (1000–1200 mg/day) and vitamin D."
	else:
		msg = "✅ Bone turnover markers appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("osteoporosis", risk)
	if risk != "normal":
		Global.set_metabolic_condition("osteoporosis", true)
	_save_metabolic_inputs("osteo", {"ctx": ctx, "p1np": p1np})

# ─────────────────────────────────────────
#  HEMOCHROMATOSIS
# ─────────────────────────────────────────
func _on_calculate_hemo():
	var fields     = get_node(HEMO + "InputFields")
	var tsat       = fields.get_node("TsatInput").value
	var ferritin   = fields.get_node("FerritinInput").value
	var is_female  = Global.body_metrics.get("is_female", false)
	var result_lbl = get_node(HEMO + "ResultLabel")

	# Sex-specific ferritin thresholds
	var ferritin_high = 200.0 if is_female else 300.0

	var risk = "normal"
	var msg = ""

	if tsat > 45 or ferritin > ferritin_high:
		risk = "overload"
		msg = "🔴 Iron overload markers elevated. Avoid iron-rich foods and vitamin C supplements."
	elif tsat > 35 or ferritin > (ferritin_high * 0.7):
		risk = "borderline"
		msg = "🟡 Borderline iron levels. Monitor iron-rich food intake."
	else:
		msg = "✅ Iron levels appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("hemochromatosis", risk)
	if risk != "normal":
		Global.set_metabolic_condition("hemochromatosis", true)
	_save_metabolic_inputs("hemo", {"tsat": tsat, "ferritin": ferritin})

# ─────────────────────────────────────────
#  WILSON'S DISEASE
# ─────────────────────────────────────────
func _on_calculate_wilson():
	var fields     = get_node(WILS + "InputFields")
	var cerul      = fields.get_node("CerulInput").value
	var urine_cu   = fields.get_node("UrineCuInput").value
	var result_lbl = get_node(WILS + "ResultLabel")

	var risk = "normal"
	var msg = ""

	if cerul < 20 and urine_cu > 100:
		risk = "likely"
		msg = "🔴 Both ceruloplasmin low and urinary copper elevated — Wilson's disease likely. Avoid copper-rich foods."
	elif cerul < 20 or urine_cu > 40:
		risk = "suspicious"
		msg = "🟡 Suspicious copper markers. Limit copper-rich foods (shellfish, nuts, organ meats)."
	else:
		msg = "✅ Copper markers appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("wilsons-disease", risk)
	if risk != "normal":
		Global.set_metabolic_condition("wilsons-disease", true)
	_save_metabolic_inputs("wilson", {"cerul": cerul, "urine_cu": urine_cu})

# ─────────────────────────────────────────
#  SAVE/LOAD METABOLIC INPUTS
# ─────────────────────────────────────────
func _save_metabolic_inputs(key: String, values: Dictionary):
	var all = {}
	if FileAccess.file_exists("user://metabolic_inputs.json"):
		var read_file = FileAccess.open("user://metabolic_inputs.json", FileAccess.READ)
		var parsed = JSON.parse_string(read_file.get_as_text())
		read_file.close()
		if parsed:
			all = parsed
	all[key] = values
	var file = FileAccess.open("user://metabolic_inputs.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(all))
	file.close()

func load_metabolic_ui():
	if not FileAccess.file_exists("user://metabolic_inputs.json"): return
	var file = FileAccess.open("user://metabolic_inputs.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return

	# Restore input values
	if data.has("glycemic"):
		get_node(GLYC + "InputFields/HbA1cInput").value = data["glycemic"].get("hba1c", 5.0)
		get_node(GLYC + "InputFields/FPGInput").value   = data["glycemic"].get("fpg", 90)
	if data.has("nafld"):
		get_node(NAFLD + "InputFields/ALTInput").value  = data["nafld"].get("alt", 20)
		get_node(NAFLD + "InputFields/ASTInput").value  = data["nafld"].get("ast", 20)
		get_node(NAFLD + "InputFields/TriglInput").value = data["nafld"].get("trigl", 100)
	if data.has("lipid"):
		get_node(LIPID + "InputFields/TotalCholInput").value = data["lipid"].get("tchol", 150)
		get_node(LIPID + "InputFields/LDLInput").value       = data["lipid"].get("ldl", 100)
		get_node(LIPID + "InputFields/HDLInput").value       = data["lipid"].get("hdl", 60)
		get_node(LIPID + "InputFields/TriglInput").value     = data["lipid"].get("trigl", 100)
	if data.has("thyroid"):
		get_node(THYR + "InputFields/TSHInput").value      = data["thyroid"].get("tsh", 2.0)
		get_node(THYR + "InputFields/FT4Input").value      = data["thyroid"].get("ft4", 1.2)
		get_node(THYR + "InputFields/TPOPositive").button_pressed = data["thyroid"].get("tpo", false)
	if data.has("osteo"):
		get_node(OSTEO + "InputFields/CTxInput").value  = data["osteo"].get("ctx", 300)
		get_node(OSTEO + "InputFields/P1NPInput").value = data["osteo"].get("p1np", 40)
	if data.has("hemo"):
		get_node(HEMO + "InputFields/TsatInput").value     = data["hemo"].get("tsat", 30)
		get_node(HEMO + "InputFields/FerritinInput").value = data["hemo"].get("ferritin", 100)
	if data.has("wilson"):
		get_node(WILS + "InputFields/CerulInput").value    = data["wilson"].get("cerul", 25)
		get_node(WILS + "InputFields/UrineCuInput").value  = data["wilson"].get("urine_cu", 20)

	# Restore known condition checkboxes
	var conditions = Global.active_metabolic_conditions
	_restore_checkbox(GLYC,  "KnownDiabetes", "glycemic-health", conditions)
	_restore_checkbox(NAFLD, "KnownNAFLD",    "nafld",           conditions)
	_restore_checkbox(LIPID, "KnownLipid",    "lipid-health",    conditions)
	_restore_checkbox(THYR,  "KnownThyroid",  "thyroid-health",  conditions)
	_restore_checkbox(OSTEO, "KnownOsteo",    "osteoporosis",    conditions)
	_restore_checkbox(HEMO,  "KnownHemo",     "hemochromatosis", conditions)
	_restore_checkbox(WILS,  "KnownWilson",   "wilsons-disease", conditions)

func _restore_checkbox(path: String, node_name: String, condition: String, conditions: Array):
	var is_active = conditions.has(condition)
	get_node(path + node_name).button_pressed = is_active
	get_node(path + "InputFields").visible = !is_active

# ─────────────────────────────────────────
#  RESET
# ─────────────────────────────────────────
func _on_reset():
	if FileAccess.file_exists("user://intake.json"):
		DirAccess.remove_absolute("user://intake.json")
	print("Daily intake reset")
