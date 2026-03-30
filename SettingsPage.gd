extends Control

const BASE  = "Panel/ScrollContainer/MarginContainer/VBoxContainer/"
const KIDNEY = BASE + "KidneyCarePanel/VBoxContainer/"
const BODY   = BASE + "BodyMetricsPanel/VBoxContainer/"
const GLYC   = BASE + "GlycemicPanel/VBoxContainer/"
const NAFLD  = BASE + "NAFLDPanel/VBoxContainer/"
const LIPID  = BASE + "LipidPanel/VBoxContainer/"
const THYR   = BASE + "ThyroidPanel/VBoxContainer/"
const OSTEO  = BASE + "OsteoPanel/VBoxContainer/"
const HEMO   = BASE + "HemoPanel/VBoxContainer/"
const WILS   = BASE + "WilsonPanel/VBoxContainer/"
const SULF   = BASE + "SulfurPanel/VBoxContainer/"
const CROHN  = BASE + "CrohnsPanel/VBoxContainer/"
const CELIAC = BASE + "CeliacPanel/VBoxContainer/"
const LACT   = BASE + "LactosePanel/VBoxContainer/"
const EPI    = BASE + "EPIPanel/VBoxContainer/"
const CHOLE  = BASE + "CholecystPanel/VBoxContainer/"

# ─────────────────────────────────────────
#  UNIT DEFINITIONS
#  Each entry: { "options": [...], "conversions": [...] }
#  conversions[i] = multiplier to convert option[i] → standard unit
#  standard unit is always options[0]
# ─────────────────────────────────────────
const UNITS = {
	"hba1c": {
		"options": ["% (NGSP)", "mmol/mol (IFCC)"],
		"multipliers": [1.0, 1.0]
	},
	"fpg": {
		"options": ["mg/dL", "mmol/L"],
		"multipliers": [1.0, 18.016]
	},
	"alt": {
		"options": ["IU/L", "U/L", "µkat/L"],
		"multipliers": [1.0, 1.0, 60.0]
	},
	"ast": {
		"options": ["IU/L", "U/L", "µkat/L"],
		"multipliers": [1.0, 1.0, 60.0]
	},
	"trigl": {
		"options": ["mg/dL", "mmol/L"],
		"multipliers": [1.0, 88.57]
	},
	"tchol": {
		"options": ["mg/dL", "mmol/L"],
		"multipliers": [1.0, 38.67]
	},
	"ldl": {
		"options": ["mg/dL", "mmol/L"],
		"multipliers": [1.0, 38.67]
	},
	"hdl": {
		"options": ["mg/dL", "mmol/L"],
		"multipliers": [1.0, 38.67]
	},
	"tsh": {
		"options": ["mIU/L", "µIU/mL"],
		"multipliers": [1.0, 1.0]
	},
	"ft4": {
		"options": ["ng/dL", "pmol/L"],
		"multipliers": [1.0, 0.07772]
	},
	"ctx": {
		"options": ["pg/mL", "ng/L", "µg/L"],
		"multipliers": [1.0, 1.0, 1000.0]
	},
	"p1np": {
		"options": ["µg/L", "ng/mL"],
		"multipliers": [1.0, 1.0]
	},
	"ferritin": {
		"options": ["µg/L", "ng/mL", "pmol/L"],
		"multipliers": [1.0, 1.0, 0.4451]
	},
	"tsat": {
		"options": ["%"],
		"multipliers": [1.0]
	},
	"cerul": {
		"options": ["mg/dL", "mg/L", "g/L"],
		"multipliers": [1.0, 0.1, 100.0]
	},
	"urine_cu": {
		"options": ["µg/day", "nmol/day"],
		"multipliers": [1.0, 0.06355]
	},
	"creatinine": {
		"options": ["mg/dL", "µmol/L"],
		"multipliers": [1.0, 0.01131]
	},
}

# Stores references to unit OptionButtons: { "field_key": OptionButton }
var _unit_buttons: Dictionary = {}

func _get_input(path: String, node_name: String) -> SpinBox:
	return get_node(path + "InputFields").find_child(node_name, true, false)

# ─────────────────────────────────────────
#  READY
# ─────────────────────────────────────────
func _ready():
	# Add unit selectors to all input fields
	_add_unit_selector(KIDNEY + "InputFields/CreatinineInput", "creatinine")
	_add_unit_selector(GLYC   + "InputFields/HbA1cInput",     "hba1c")
	_add_unit_selector(GLYC   + "InputFields/FPGInput",        "fpg")
	_add_unit_selector(NAFLD  + "InputFields/ALTInput",        "alt")
	_add_unit_selector(NAFLD  + "InputFields/ASTInput",        "ast")
	_add_unit_selector(NAFLD  + "InputFields/TriglInput",      "trigl")
	_add_unit_selector(LIPID  + "InputFields/TotalCholInput",  "tchol")
	_add_unit_selector(LIPID  + "InputFields/LDLInput",        "ldl")
	_add_unit_selector(LIPID  + "InputFields/HDLInput",        "hdl")
	_add_unit_selector(LIPID  + "InputFields/TriglInput",      "trigl")
	_add_unit_selector(THYR   + "InputFields/TSHInput",        "tsh")
	_add_unit_selector(THYR   + "InputFields/FT4Input",        "ft4")
	_add_unit_selector(OSTEO  + "InputFields/CTxInput",        "ctx")
	_add_unit_selector(OSTEO  + "InputFields/P1NPInput",       "p1np")
	_add_unit_selector(HEMO   + "InputFields/FerritinInput",   "ferritin")
	_add_unit_selector(HEMO   + "InputFields/TsatInput",       "tsat")
	_add_unit_selector(WILS   + "InputFields/CerulInput",      "cerul")
	_add_unit_selector(WILS   + "InputFields/UrineCuInput",    "urine_cu")
	
	# red warning
	get_node(BASE + "HideRedWarningsRow/HideRedCheck").toggled.connect(func(checked):
		Global.hide_red_warnings = checked
		Global.save_profile()
	)
	get_node(BASE + "HideRedWarningsRow/HideRedCheck").button_pressed = Global.hide_red_warnings

	# Kidney care
	get_node(KIDNEY + "KnownDisease").toggled.connect(_on_known_disease_toggled)
	get_node(KIDNEY + "InputFields/CalculateButton").pressed.connect(_on_calculate_egfr)

	# Body metrics
	get_node(BODY + "CalculateButton").pressed.connect(_on_calculate_metrics)

	# Metabolic checkboxes
	get_node(GLYC  + "KnownDiabetes").toggled.connect(func(c): _on_known_metabolic("glycemic-health", c, GLYC))
	get_node(NAFLD + "KnownNAFLD").toggled.connect(func(c):    _on_known_metabolic("nafld", c, NAFLD))
	get_node(LIPID + "KnownLipid").toggled.connect(func(c):    _on_known_metabolic("lipid-health", c, LIPID))
	get_node(THYR  + "KnownThyroid").toggled.connect(func(c):  _on_known_metabolic("thyroid-health", c, THYR))
	get_node(OSTEO + "KnownOsteo").toggled.connect(func(c):    _on_known_metabolic("osteoporosis", c, OSTEO))
	get_node(HEMO  + "KnownHemo").toggled.connect(func(c):     _on_known_metabolic("hemochromatosis", c, HEMO))
	get_node(WILS  + "KnownWilson").toggled.connect(func(c):   _on_known_metabolic("wilsons-disease", c, WILS))

	# Metabolic calculate buttons
	get_node(GLYC  + "InputFields/CalculateButton").pressed.connect(_on_calculate_glycemic)
	get_node(NAFLD + "InputFields/CalculateButton").pressed.connect(_on_calculate_nafld)
	get_node(LIPID + "InputFields/CalculateButton").pressed.connect(_on_calculate_lipid)
	get_node(THYR  + "InputFields/CalculateButton").pressed.connect(_on_calculate_thyroid)
	get_node(OSTEO + "InputFields/CalculateButton").pressed.connect(_on_calculate_osteo)
	get_node(HEMO  + "InputFields/CalculateButton").pressed.connect(_on_calculate_hemo)
	get_node(WILS  + "InputFields/CalculateButton").pressed.connect(_on_calculate_wilson)
	# GI conditions — checkbox only (no blood tests)
	get_node(SULF  + "KnownSulfur").toggled.connect(func(c):    _on_known_metabolic("sulfur-avoidance", c, SULF))
	get_node(CROHN + "KnownCrohns").toggled.connect(func(c):   _on_known_gi_crohns(c))
	get_node(CELIAC + "KnownCeliac").toggled.connect(func(c):  _on_known_metabolic("celiac-disease", c, CELIAC))
	get_node(LACT  + "KnownLactose").toggled.connect(func(c):  _on_known_metabolic("lactose-intolerance", c, LACT))
	get_node(EPI   + "KnownEPI").toggled.connect(func(c):      _on_known_gi_epi(c))
	get_node(CHOLE + "KnownCholecyst").toggled.connect(func(c):_on_known_metabolic("post-cholecystectomy", c, CHOLE))

	get_node(BASE + "ResetButton").pressed.connect(_on_reset)

	load_kidney_settings()
	load_body_metrics()
	load_metabolic_ui()

# ─────────────────────────────────────────
#  UNIT SELECTOR — adds OptionButton next to SpinBox
# ─────────────────────────────────────────
func _add_unit_selector(spinbox_path: String, field_key: String):
	var spinbox = get_node_or_null(spinbox_path)
	if not spinbox: return
	if not UNITS.has(field_key): return

	# Wrap SpinBox in HBoxContainer
	var parent = spinbox.get_parent()
	var idx    = spinbox.get_index()

	var hbox = HBoxContainer.new()
	hbox.name = spinbox.name + "Row"
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Remove spinbox from parent, put hbox in its place
	parent.remove_child(spinbox)
	parent.add_child(hbox)
	parent.move_child(hbox, idx)

	# Add spinbox back inside hbox
	spinbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spinbox)

	# Only add OptionButton if there are multiple units
	var unit_def = UNITS[field_key]
	var options  = unit_def["options"]
	if options.size() > 1:
		var opt = OptionButton.new()
		opt.name = field_key + "_unit"
		opt.custom_minimum_size = Vector2(120, 0)
		for o in options:
			opt.add_item(o)
		hbox.add_child(opt)
		_unit_buttons[field_key] = opt
	else:
		# Just show a label for single-unit fields
		var lbl = Label.new()
		lbl.text = options[0]
		hbox.add_child(lbl)

# ─────────────────────────────────────────
#  CONVERSION — converts entered value to standard unit
# ─────────────────────────────────────────
func _convert(value: float, field_key: String) -> float:
	if not UNITS.has(field_key): return value
	var unit_def = UNITS[field_key]

	# Special case: HbA1c mmol/mol → %
	if field_key == "hba1c":
		if _unit_buttons.has("hba1c") and _unit_buttons["hba1c"].selected == 1:
			# IFCC mmol/mol to NGSP %
			return (value / 10.929) + 2.15
		return value

	if not _unit_buttons.has(field_key): return value
	var selected = _unit_buttons[field_key].selected
	var multipliers = unit_def.get("multipliers", [1.0])
	if selected < multipliers.size():
		return value * multipliers[selected]
	return value

# ─────────────────────────────────────────
#  HELPER — known condition checkbox
# ─────────────────────────────────────────
func _on_known_metabolic(condition: String, checked: bool, path: String):
	# Some GI panels have no InputFields — check before accessing
	var input_node = get_node_or_null(path + "InputFields")
	if input_node:
		input_node.visible = !checked

	Global.set_metabolic_condition(condition, checked)
	Global.set_known_diagnosis(condition, checked)

	if checked:
		Global.set_metabolic_risk(condition, "confirmed")
		var msg = "⚠️ " + condition.replace("-"," ").capitalize() + " confirmed."
		# Add condition-specific guidance
		match condition:
			"sulfur-avoidance":
				msg = "✅ Sulfur avoidance active.\nHigh-sulfur foods (garlic, onion, eggs, cruciferous vegetables, meat) \nwill be flagged."
			"celiac-disease":
				msg = "⚠️ Celiac disease.\nAll gluten-containing foods will be flagged. Avoid wheat, rye, barley, spelt."
			"lactose-intolerance":
				msg = "⚠️ Lactose intolerance.\nHigh-lactose dairy will be flagged.\nHard cheeses and lactose-free products are safe."
			"post-cholecystectomy":
				msg = "⚠️ Post-cholecystectomy.\nHigh-fat foods flagged. Eat 5–6 small meals daily. Avoid fried/spicy foods."
		get_node(path + "ResultLabel").text = msg
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

func save_kidney_settings(egfr: float):
	var risk_text = get_node(KIDNEY + "RiskLabel").text
	var egfr_text = ""
	if egfr > 0:
		egfr_text = get_node(KIDNEY + "InputFields").find_child("eGFRLabel", true, false).text
	_save_metabolic_inputs("kidney", {
		"egfr": egfr,
		"at_risk": Global.kidney_at_risk,
		"known_disease": get_node(KIDNEY + "KnownDisease").button_pressed,
		"risk_text": risk_text,
		"egfr_text": egfr_text,
		"creatinine_unit": _unit_buttons["creatinine"].selected if _unit_buttons.has("creatinine") else 0
	})
	Global.save_profile()

func load_kidney_settings():
	if not FileAccess.file_exists("user://metabolic_inputs.json"): return
	var file = FileAccess.open("user://metabolic_inputs.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data or not data.has("kidney"): return
	var k = data["kidney"]
	Global.kidney_at_risk = k.get("at_risk", false)
	var known = k.get("known_disease", false)
	get_node(KIDNEY + "KnownDisease").button_pressed = known
	get_node(KIDNEY + "InputFields").visible = !known
	if k.has("risk_text") and k["risk_text"] != "":
		get_node(KIDNEY + "RiskLabel").text = k["risk_text"]
	if k.has("egfr_text") and k["egfr_text"] != "":
		get_node(KIDNEY + "InputFields").find_child("eGFRLabel", true, false).text = k["egfr_text"]
	if _unit_buttons.has("creatinine"):
		_unit_buttons["creatinine"].selected = k.get("creatinine_unit", 0)
		
func _on_calculate_egfr():
	var scr_raw   = _get_input(KIDNEY, "CreatinineInput").value
	var scr       = _convert(scr_raw, "creatinine")
	var age       = _get_input(KIDNEY, "AgeInput").value
	var is_female = Global.body_metrics.get("is_female", false)

	var kappa      = 0.7 if is_female else 0.9
	var alpha      = -0.329 if is_female else -0.411
	var sex_factor = 1.012 if is_female else 1.0
	var ratio      = scr / kappa
	var egfr       = 142.0 \
		* pow(min(ratio, 1.0), alpha) \
		* pow(max(ratio, 1.0), -1.200) \
		* pow(0.9938, age) \
		* sex_factor
	egfr = snappedf(egfr, 0.1)

	get_node(KIDNEY + "InputFields").find_child("eGFRLabel", true, false).text = "eGFR: " + str(egfr) + " mL/min/1.73m²"

	if egfr <= 60:
		get_node(KIDNEY + "RiskLabel").text = "⚠️ eGFR ≤ 60 — kidney function reduced."
		Global.kidney_at_risk = true
	else:
		get_node(KIDNEY + "RiskLabel").text = "✅ eGFR > 60 — kidney function normal."
		Global.kidney_at_risk = false

	save_kidney_settings(egfr)
	Global.save_profile()

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
	var adjusted_kcal_goal: float = 0.0

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

	var adj = Global.calculate_adjusted_kcal_goal()
	var adj_goal = adj.get("adjusted_goal", 0.0)
	var adj_notes = adj.get("adjustments", [])

	if adj_notes.size() > 0:
		var adj_text = "⚕️ Adjusted goal: " + str(adj_goal) + " kcal/day\n"
		for note in adj_notes:
			adj_text += "• " + note + "\n"
		panel.get_node("AdjustedGoalResult").text = adj_text
		panel.get_node("AdjustedGoalResult").visible = true
		# Update Global so HomePage uses the adjusted goal
		Global.body_metrics["daily_goal"] = adj_goal
		Global.body_metrics["adjusted_kcal_goal"] = adj_goal
	else:
		panel.get_node("AdjustedGoalResult").visible = false
		Global.body_metrics["adjusted_kcal_goal"] = daily_goal

	save_body_metrics(weight, height_cm, age, activity, goal_w, weeks, is_female, bmr, tdee, daily_goal, bmi_text)

func save_body_metrics(weight, height, age, activity, goal_w, weeks, is_female, bmr, tdee, daily_goal, bmi_text):
	var adj = Global.calculate_adjusted_kcal_goal()
	var adj_goal = adj.get("adjusted_goal", daily_goal)
	var adj_notes = adj.get("adjustments", [])
	var file = FileAccess.open("user://body_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"weight": weight, "height": height, "age": age,
		"activity": activity, "goal_weight": goal_w, "weeks": weeks,
		"is_female": is_female, "bmr": bmr, "tdee": tdee,
		"adjusted_goal": adj_goal,
		"adjustment_notes": adj_notes,
		"daily_goal": daily_goal, "bmi_text": bmi_text
	}))
	file.close()
	Global.body_metrics = {
		"bmr": bmr, "tdee": tdee,
		"daily_goal": adj_goal if adj_notes.size() > 0 else daily_goal,
		"goal_weight": goal_w, "weight": weight,
		"bmi_text": bmi_text, "is_female": is_female
	}
	Global.body_metrics["adjusted_kcal_goal"] = adj_goal

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

	if data.has("adjusted_goal") and data["adjusted_goal"] > 0:
		var adj_notes = data.get("adjustment_notes", [])
		if adj_notes.size() > 0:
			var adj_text = "⚕️ Adjusted goal: " + str(data["adjusted_goal"]) + " kcal/day\n"
			for note in adj_notes:
				adj_text += "• " + note + "\n"
			panel.get_node("AdjustedGoalResult").text = adj_text
			panel.get_node("AdjustedGoalResult").visible = true
		else:
			panel.get_node("AdjustedGoalResult").visible = false
	
	Global.body_metrics = {
		"bmr": data.get("bmr", 0.0), "tdee": data.get("tdee", 0.0),
		"daily_goal": data.get("adjusted_goal", data.get("daily_goal", 0.0)),
		"goal_weight": data.get("goal_weight", 0.0),
		"weight": data.get("weight", 0.0),
		"bmi_text": data.get("bmi_text", "BMI: —"),
		"is_female": data.get("is_female", false)
	}

	Global.body_metrics = {
		"bmr": data.get("bmr", 0.0), "tdee": data.get("tdee", 0.0),
		"daily_goal": data.get("daily_goal", 0.0),
		"goal_weight": data.get("goal_weight", 0.0),
		"weight": data.get("weight", 0.0),
		"bmi_text": data.get("bmi_text", "BMI: —"),
		"is_female": data.get("is_female", false)
	}

# ─────────────────────────────────────────
#  GLYCEMIC
# ─────────────────────────────────────────
func _on_calculate_glycemic():
	var hba1c      = _convert(_get_input(GLYC, "HbA1cInput").value, "hba1c")
	var fpg        = _convert(_get_input(GLYC, "FPGInput").value, "fpg")
	var result_lbl = get_node(GLYC + "ResultLabel")
	var risk = "normal"
	var msg  = ""

	if hba1c >= 6.5 or fpg >= 126:
		risk = "diabetes"
		msg  = "🔴 Diabetes range (HbA1c ≥ 6.5% or FPG ≥ 126 mg/dL). Consult your doctor."
	elif hba1c >= 5.7 or fpg >= 100:
		risk = "prediabetes"
		msg  = "🟡 Prediabetes range (HbA1c 5.7–6.4% or FPG 100–125 mg/dL). Reduce sugar."
	else:
		msg  = "✅ Glycemic values appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("glycemic-health", risk)
	if risk != "normal":
		Global.set_metabolic_condition("glycemic-health", true)
	_save_metabolic_inputs("glycemic", {
		"hba1c": _get_input(GLYC, "HbA1cInput").value,
		"fpg": _get_input(GLYC, "FPGInput").value,
		"hba1c_unit": _unit_buttons.get("hba1c", null).selected if _unit_buttons.has("hba1c") else 0,
		"fpg_unit": _unit_buttons.get("fpg", null).selected if _unit_buttons.has("fpg") else 0,
		"result": msg
	})

# ─────────────────────────────────────────
#  NAFLD
# ─────────────────────────────────────────
func _on_calculate_nafld():
	var alt        = _convert(_get_input(NAFLD, "ALTInput").value, "alt")
	var ast        = _convert(_get_input(NAFLD, "ASTInput").value, "ast")
	var trigl      = _convert(_get_input(NAFLD, "TriglInput").value, "trigl")
	var is_female  = Global.body_metrics.get("is_female", false)
	var result_lbl = get_node(NAFLD + "ResultLabel")
	var alt_upper  = 30.0 if is_female else 63.0
	var risk = "normal"
	var msg  = ""

	if alt > alt_upper * 2 or ast > 60 or trigl > 150:
		risk = "elevated"
		msg  = "🔴 Elevated liver enzymes or triglycerides. Restrict sugar and saturated fat."
	elif alt > alt_upper or ast > 30 or trigl > 100:
		risk = "borderline"
		msg  = "🟡 Borderline liver values. Reduce sugar and fructose."
	else:
		msg  = "✅ Liver markers appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("nafld", risk)
	if risk != "normal":
		Global.set_metabolic_condition("nafld", true)
	_save_metabolic_inputs("nafld", {
		"alt": _get_input(NAFLD, "ALTInput").value,
		"ast": _get_input(NAFLD, "ASTInput").value,
		"trigl": _get_input(NAFLD, "TriglInput").value,
		"alt_unit": _unit_buttons.get("alt", null).selected if _unit_buttons.has("alt") else 0,
		"ast_unit": _unit_buttons.get("ast", null).selected if _unit_buttons.has("ast") else 0,
		"trigl_unit": _unit_buttons.get("trigl", null).selected if _unit_buttons.has("trigl") else 0,
		"result": msg
	})

# ─────────────────────────────────────────
#  LIPID
# ─────────────────────────────────────────
func _on_calculate_lipid():
	var tchol      = _convert(_get_input(LIPID, "TotalCholInput").value, "tchol")
	var ldl        = _convert(_get_input(LIPID, "LDLInput").value, "ldl")
	var hdl        = _convert(_get_input(LIPID, "HDLInput").value, "hdl")
	var trigl      = _convert(_get_input(LIPID, "TriglInput").value, "trigl")
	var is_female  = Global.body_metrics.get("is_female", false)
	var result_lbl = get_node(LIPID + "ResultLabel")

	if tchol == 0 and ldl == 0 and hdl == 0 and trigl == 0:
		result_lbl.text = "Enter your blood test values above."
		return

	var hdl_low = 50.0 if is_female else 40.0
	var abnormal_details  = []
	var borderline_details = []

	if tchol > 0:
		if tchol > 200:   abnormal_details.append("Total cholesterol > 200 mg/dL")
		elif tchol > 180: borderline_details.append("Total cholesterol borderline")
	if ldl > 0:
		if ldl > 130:     abnormal_details.append("LDL > 130 mg/dL")
		elif ldl > 110:   borderline_details.append("LDL borderline")
	if hdl > 0:
		if hdl < hdl_low: abnormal_details.append("HDL too low (< " + str(hdl_low) + " mg/dL)")
	if trigl > 0:
		if trigl > 150:   abnormal_details.append("Triglycerides > 150 mg/dL")
		elif trigl > 100: borderline_details.append("Triglycerides borderline")

	var risk = "normal"
	var msg  = ""

	if abnormal_details.size() >= 1:
		risk = "high"
		msg  = "🔴 Abnormal lipid levels:\n"
		for d in abnormal_details: msg += "• " + d + "\n"
		msg += "Reduce saturated fat, increase fiber and omega-3."
	elif borderline_details.size() >= 1:
		risk = "borderline"
		msg  = "🟡 Borderline lipid values:\n"
		for d in borderline_details: msg += "• " + d + "\n"
		msg += "Monitor saturated fat intake."
	else:
		msg  = "✅ Lipid levels appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("lipid-health", risk)
	if risk != "normal":
		Global.set_metabolic_condition("lipid-health", true)
	_save_metabolic_inputs("lipid", {
		"tchol": _get_input(LIPID, "TotalCholInput").value,
		"ldl": _get_input(LIPID, "LDLInput").value,
		"hdl": _get_input(LIPID, "HDLInput").value,
		"trigl": _get_input(LIPID, "TriglInput").value,
		"tchol_unit": _unit_buttons.get("tchol", null).selected if _unit_buttons.has("tchol") else 0,
		"ldl_unit": _unit_buttons.get("ldl", null).selected if _unit_buttons.has("ldl") else 0,
		"hdl_unit": _unit_buttons.get("hdl", null).selected if _unit_buttons.has("hdl") else 0,
		"trigl_unit": _unit_buttons.get("trigl", null).selected if _unit_buttons.has("trigl") else 0,
		"result": msg
	})

# ─────────────────────────────────────────
#  THYROID
# ─────────────────────────────────────────
func _on_calculate_thyroid():
	var tsh        = _convert(_get_input(THYR, "TSHInput").value, "tsh")
	var ft4        = _convert(_get_input(THYR, "FT4Input").value, "ft4")
	var tpo_pos    = get_node(THYR + "InputFields").find_child("TPOPositive", true, false).button_pressed
	var result_lbl = get_node(THYR + "ResultLabel")
	var risk = "normal"
	var msg  = ""

	if tsh > 5.0 and ft4 < 0.7:
		risk = "hypothyroid"
		msg  = "🔴 Hypothyroidism detected (TSH > 5.0, FT4 < 0.7 ng/dL). \nConsult your doctor."
	elif tsh > 5.0:
		risk = "subclinical"
		msg  = "🟡 Subclinical hypothyroidism (elevated TSH). \nMonitor closely."
	elif tsh < 0.4:
		risk = "hyperthyroid"
		msg  = "🟡 Possible hyperthyroidism (TSH < 0.4). \nConsult your doctor."
	else:
		msg  = "✅ Thyroid values appear normal."

	if tpo_pos:
		risk = "hashimotos"
		msg += "\n⚠️ TPO antibodies positive \n— Hashimoto's thyroiditis likely."
		Global.set_metabolic_condition("thyroid-health", true)

	result_lbl.text = msg
	Global.set_metabolic_risk("thyroid-health", risk)
	if risk != "normal":
		Global.set_metabolic_condition("thyroid-health", true)
	_save_metabolic_inputs("thyroid", {
		"tsh": _get_input(THYR, "TSHInput").value,
		"ft4": _get_input(THYR, "FT4Input").value,
		"tpo": tpo_pos,
		"tsh_unit": _unit_buttons.get("tsh", null).selected if _unit_buttons.has("tsh") else 0,
		"ft4_unit": _unit_buttons.get("ft4", null).selected if _unit_buttons.has("ft4") else 0,
		"result": msg
	})

# ─────────────────────────────────────────
#  OSTEOPOROSIS
# ─────────────────────────────────────────
func _on_calculate_osteo():
	var ctx        = _convert(_get_input(OSTEO, "CTxInput").value, "ctx")
	var p1np       = _convert(_get_input(OSTEO, "P1NPInput").value, "p1np")
	var is_female  = Global.body_metrics.get("is_female", false)
	var result_lbl = get_node(OSTEO + "ResultLabel")
	var ctx_high    = 1000.0 if is_female else 800.0
	var ctx_caution = 600.0  if is_female else 500.0
	var risk = "normal"
	var msg  = ""

	if ctx > ctx_high or p1np > 75:
		risk = "high-turnover"
		msg  = "🔴 High bone turnover — significant bone loss likely. Increase calcium and vitamin D."
	elif ctx > ctx_caution or p1np > 50:
		risk = "borderline"
		msg  = "🟡 Borderline bone turnover. Ensure calcium (1000–1200 mg/day) and vitamin D."
	else:
		msg  = "✅ Bone turnover markers appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("osteoporosis", risk)
	if risk != "normal":
		Global.set_metabolic_condition("osteoporosis", true)
	_save_metabolic_inputs("osteo", {
		"ctx": _get_input(OSTEO, "CTxInput").value,
		"p1np": _get_input(OSTEO, "P1NPInput").value,
		"ctx_unit": _unit_buttons.get("ctx", null).selected if _unit_buttons.has("ctx") else 0,
		"p1np_unit": _unit_buttons.get("p1np", null).selected if _unit_buttons.has("p1np") else 0,
		"result": msg
	})

# ─────────────────────────────────────────
#  HEMOCHROMATOSIS
# ─────────────────────────────────────────
func _on_calculate_hemo():
	var tsat       = _convert(_get_input(HEMO, "TsatInput").value, "tsat")
	var ferritin   = _convert(_get_input(HEMO, "FerritinInput").value, "ferritin")
	var is_female  = Global.body_metrics.get("is_female", false)
	var result_lbl = get_node(HEMO + "ResultLabel")
	var ferritin_high = 200.0 if is_female else 300.0
	var risk = "normal"
	var msg  = ""

	if tsat > 45 or ferritin > ferritin_high:
		risk = "overload"
		msg  = "🔴 Iron overload markers elevated. \nAvoid iron-rich foods and vitamin C supplements."
	elif tsat > 35 or ferritin > (ferritin_high * 0.7):
		risk = "borderline"
		msg  = "🟡 Borderline iron levels. \nMonitor iron-rich food intake."
	else:
		msg  = "✅ Iron levels appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("hemochromatosis", risk)
	if risk != "normal":
		Global.set_metabolic_condition("hemochromatosis", true)
	_save_metabolic_inputs("hemo", {
		"tsat": _get_input(HEMO, "TsatInput").value,
		"ferritin": _get_input(HEMO, "FerritinInput").value,
		"ferritin_unit": _unit_buttons.get("ferritin", null).selected if _unit_buttons.has("ferritin") else 0,
		"result": msg
	})

# ─────────────────────────────────────────
#  WILSON'S DISEASE
# ─────────────────────────────────────────
func _on_calculate_wilson():
	var cerul      = _convert(_get_input(WILS, "CerulInput").value, "cerul")
	var urine_cu   = _convert(_get_input(WILS, "UrineCuInput").value, "urine_cu")
	var result_lbl = get_node(WILS + "ResultLabel")
	var risk = "normal"
	var msg  = ""

	if cerul < 20 and urine_cu > 100:
		risk = "likely"
		msg  = "🔴 Ceruloplasmin low + urinary copper elevated — Wilson's likely. Avoid copper-rich foods."
	elif cerul < 20 or urine_cu > 40:
		risk = "suspicious"
		msg  = "🟡 Suspicious copper markers. Limit shellfish, nuts and organ meats."
	else:
		msg  = "✅ Copper markers appear normal."

	result_lbl.text = msg
	Global.set_metabolic_risk("wilsons-disease", risk)
	if risk != "normal":
		Global.set_metabolic_condition("wilsons-disease", true)
	_save_metabolic_inputs("wilson", {
		"cerul": _get_input(WILS, "CerulInput").value,
		"urine_cu": _get_input(WILS, "UrineCuInput").value,
		"cerul_unit": _unit_buttons.get("cerul", null).selected if _unit_buttons.has("cerul") else 0,
		"urine_cu_unit": _unit_buttons.get("urine_cu", null).selected if _unit_buttons.has("urine_cu") else 0,
		"result": msg
	})
# ─────────────────────────────────────────
#  GI CONDITIONS
# ─────────────────────────────────────────
func _on_known_gi_crohns(checked: bool):
	Global.set_metabolic_condition("crohns-disease", checked)
	Global.set_known_diagnosis("crohns-disease", checked)
	if checked:
		Global.set_metabolic_risk("crohns-disease", "confirmed")
		var is_female = Global.body_metrics.get("is_female", false)
		var weight    = Global.body_metrics.get("weight", 70.0)
		var extra_kcal = snappedf(weight * 2.9 + 600.0, 0.0)
		get_node(CROHN + "ResultLabel").text = (
			"⚠️ Crohn's disease active.\n" +
			"• REE increased — need ~+" + str(extra_kcal) + " kcal/day extra\n" +
			"• High protein: 1.2–1.5 g/kg/day\n" +
			"• Low fiber during flares\n" +
			"• Small frequent meals recommended"
		)
	else:
		Global.set_metabolic_risk("crohns-disease", "normal")
		get_node(CROHN + "ResultLabel").text = "—"
	Global.save_metabolic_conditions()

func _on_known_gi_epi(checked: bool):
	Global.set_metabolic_condition("epi", checked)
	Global.set_known_diagnosis("epi", checked)
	if checked:
		Global.set_metabolic_risk("epi", "confirmed")
		var weight   = Global.body_metrics.get("weight", 70.0)
		var epi_kcal = snappedf(weight * 32.5, 0.0)
		get_node(EPI + "ResultLabel").text = (
			"⚠️ Pancreatic insufficiency.\n" +
			"• Target: 30–35 kcal/kg = ~" + str(epi_kcal) + " kcal/day\n" +
			"• Take PERT with every meal and snack\n" +
			"• High protein: 1.2–1.5 g/kg/day\n" +
			"• Monitor fat intake — watch for steatorrhea"
		)
	else:
		Global.set_metabolic_risk("epi", "normal")
		get_node(EPI + "ResultLabel").text = "—"
	Global.save_metabolic_conditions()
# ─────────────────────────────────────────
#  SAVE / LOAD METABOLIC INPUTS
# ─────────────────────────────────────────
func _save_metabolic_inputs(key: String, values: Dictionary):
	var all = {}
	if FileAccess.file_exists("user://metabolic_inputs.json"):
		var read_file = FileAccess.open("user://metabolic_inputs.json", FileAccess.READ)
		var parsed = JSON.parse_string(read_file.get_as_text())
		read_file.close()
		if parsed: all = parsed
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
	var tpo_node = get_node(THYR + "InputFields").find_child("TPOPositive", true, false)

	if data.has("glycemic"):
		get_node(GLYC + "InputFields/HbA1cInputRow/HbA1cInput").value = data["glycemic"].get("hba1c", 5.0)
		get_node(GLYC + "InputFields/FPGInputRow/FPGInput").value   = data["glycemic"].get("fpg", 90)
		get_node(GLYC + "ResultLabel").text             = data["glycemic"].get("result", "—")
		if _unit_buttons.has("hba1c"):
			_unit_buttons["hba1c"].selected = data["glycemic"].get("hba1c_unit", 0)
		if _unit_buttons.has("fpg"):
			_unit_buttons["fpg"].selected = data["glycemic"].get("fpg_unit", 0)

	if data.has("nafld"):
		get_node(NAFLD + "InputFields/ALTInputRow/ALTInput").value   = data["nafld"].get("alt", 20)
		get_node(NAFLD + "InputFields/ASTInputRow/ASTInput").value   = data["nafld"].get("ast", 20)
		get_node(NAFLD + "InputFields/TriglInputRow/TriglInput").value = data["nafld"].get("trigl", 100)
		get_node(NAFLD + "ResultLabel").text             = data["nafld"].get("result", "—")
		if _unit_buttons.has("alt"):   _unit_buttons["alt"].selected   = data["nafld"].get("alt_unit", 0)
		if _unit_buttons.has("ast"):   _unit_buttons["ast"].selected   = data["nafld"].get("ast_unit", 0)

	if data.has("lipid"):
		get_node(LIPID + "InputFields/TotalCholInputRow/TotalCholInput").value = data["lipid"].get("tchol", 150)
		get_node(LIPID + "InputFields/LDLInputRow/LDLInput").value       = data["lipid"].get("ldl", 100)
		get_node(LIPID + "InputFields/HDLInputRow/HDLInput").value       = data["lipid"].get("hdl", 60)
		get_node(LIPID + "InputFields/TriglInputRow/TriglInput").value     = data["lipid"].get("trigl", 100)
		get_node(LIPID + "ResultLabel").text                 = data["lipid"].get("result", "—")
		if _unit_buttons.has("tchol"): _unit_buttons["tchol"].selected = data["lipid"].get("tchol_unit", 0)
		if _unit_buttons.has("ldl"):   _unit_buttons["ldl"].selected   = data["lipid"].get("ldl_unit", 0)
		if _unit_buttons.has("hdl"):   _unit_buttons["hdl"].selected   = data["lipid"].get("hdl_unit", 0)

	if data.has("thyroid"):
		get_node(THYR + "InputFields/TSHInputRow/TSHInput").value            = data["thyroid"].get("tsh", 2.0)
		get_node(THYR + "InputFields/FT4InputRow/FT4Input").value            = data["thyroid"].get("ft4", 1.2)
		get_node(THYR + "ResultLabel").text                      = data["thyroid"].get("result", "—")
		if _unit_buttons.has("tsh"): _unit_buttons["tsh"].selected = data["thyroid"].get("tsh_unit", 0)
		if _unit_buttons.has("ft4"): _unit_buttons["ft4"].selected = data["thyroid"].get("ft4_unit", 0)
		if tpo_node: tpo_node.button_pressed = data["thyroid"].get("tpo", false)

	if data.has("osteo"):
		get_node(OSTEO + "InputFields/CTxInputRow/CTxInput").value  = data["osteo"].get("ctx", 300)
		get_node(OSTEO + "InputFields/P1NPInputRow/P1NPInput").value = data["osteo"].get("p1np", 40)
		get_node(OSTEO + "ResultLabel").text            = data["osteo"].get("result", "—")
		if _unit_buttons.has("ctx"):  _unit_buttons["ctx"].selected  = data["osteo"].get("ctx_unit", 0)
		if _unit_buttons.has("p1np"): _unit_buttons["p1np"].selected = data["osteo"].get("p1np_unit", 0)

	if data.has("hemo"):
		get_node(HEMO + "InputFields/TsatInputRow/TsatInput").value     = data["hemo"].get("tsat", 30)
		get_node(HEMO + "InputFields/FerritinInputRow/FerritinInput").value = data["hemo"].get("ferritin", 100)
		get_node(HEMO + "ResultLabel").text                = data["hemo"].get("result", "—")
		if _unit_buttons.has("ferritin"): _unit_buttons["ferritin"].selected = data["hemo"].get("ferritin_unit", 0)

	if data.has("wilson"):
		get_node(WILS + "InputFields/CerulInputRow/CerulInput").value   = data["wilson"].get("cerul", 25)
		get_node(WILS + "InputFields/UrineCuInputRow/UrineCuInput").value = data["wilson"].get("urine_cu", 20)
		get_node(WILS + "ResultLabel").text               = data["wilson"].get("result", "—")
		if _unit_buttons.has("cerul"):    _unit_buttons["cerul"].selected    = data["wilson"].get("cerul_unit", 0)
		if _unit_buttons.has("urine_cu"): _unit_buttons["urine_cu"].selected = data["wilson"].get("urine_cu_unit", 0)

	# Restore checkboxes
	_restore_checkbox(GLYC,  "KnownDiabetes", "glycemic-health", [])
	_restore_checkbox(NAFLD, "KnownNAFLD",    "nafld",           [])
	_restore_checkbox(LIPID, "KnownLipid",    "lipid-health",    [])
	_restore_checkbox(THYR,  "KnownThyroid",  "thyroid-health",  [])
	_restore_checkbox(OSTEO, "KnownOsteo",    "osteoporosis",    [])
	_restore_checkbox(HEMO,  "KnownHemo",     "hemochromatosis", [])
	_restore_checkbox(WILS,  "KnownWilson",   "wilsons-disease", [])
	# GI conditions (checkbox only, no inputs)
	_restore_gi_checkbox(SULF,   "KnownSulfur",    "sulfur-avoidance")
	_restore_gi_checkbox(CROHN,  "KnownCrohns",    "crohns-disease")
	_restore_gi_checkbox(CELIAC, "KnownCeliac",    "celiac-disease")
	_restore_gi_checkbox(LACT,   "KnownLactose",   "lactose-intolerance")
	_restore_gi_checkbox(EPI,    "KnownEPI",       "epi")
	_restore_gi_checkbox(CHOLE,  "KnownCholecyst", "post-cholecystectomy")

func _restore_gi_checkbox(path: String, node_name: String, condition: String):
	var is_known = Global.known_diagnoses.has(condition)
	get_node(path + node_name).button_pressed = is_known

func _restore_checkbox(path: String, node_name: String, condition: String, _conditions: Array):
	var is_known = Global.known_diagnoses.has(condition)
	get_node(path + node_name).button_pressed = is_known
	get_node(path + "InputFields").visible = !is_known

# ─────────────────────────────────────────
#  RESET
# ─────────────────────────────────────────
func _on_reset():
	if FileAccess.file_exists("user://intake.json"):
		DirAccess.remove_absolute("user://intake.json")
	print("Daily intake reset")
