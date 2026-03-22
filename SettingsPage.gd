extends Control

func _ready():
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/KnownDisease.toggled.connect(_on_known_disease_toggled)
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields/CalculateButton.pressed.connect(_on_calculate_egfr)
	$Panel/ScrollContainer/VBoxContainer/BodyMetricsPanel/VBoxContainer/CalculateButton.pressed.connect(_on_calculate_metrics)
	$Panel/ScrollContainer/VBoxContainer/ResetButton.pressed.connect(_on_reset)
	load_kidney_settings()
	load_body_metrics()

# ─────────────────────────────────────────
#  KIDNEY CARE
# ─────────────────────────────────────────
func _on_known_disease_toggled(checked: bool):
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields.visible = !checked
	if checked:
		_set_kidney_risk("⚠️ Kidney disease flagged. High oxalate foods will be marked.")
		Global.kidney_at_risk = true
	else:
		Global.kidney_at_risk = false
		_set_kidney_risk("")
	save_kidney_settings(0.0)
	Global.save_profile()

func _on_calculate_egfr():
	var fields = $Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields
	var scr       = fields.get_node("CreatinineInput").value
	var age       = fields.get_node("AgeInput").value
	var is_female = fields.get_node("GenderOption").selected == 1

	var kappa      = 0.7 if is_female else 0.9
	var alpha      = -0.329 if is_female else -0.411
	var sex_factor = 1.012 if is_female else 1.0

	var ratio = scr / kappa
	var egfr  = 142.0 \
		* pow(min(ratio, 1.0), alpha) \
		* pow(max(ratio, 1.0), -1.200) \
		* pow(0.9938, age) \
		* sex_factor
	egfr = snappedf(egfr, 0.1)

	fields.get_node("eGFRLabel").text = "eGFR: " + str(egfr) + " mL/min/1.73m²"

	if egfr <= 60:
		_set_kidney_risk("⚠️ eGFR ≤ 60 — kidney function reduced. High oxalate foods will be marked.")
		Global.kidney_at_risk = true
	else:
		_set_kidney_risk("✅ eGFR > 60 — kidney function appears normal.")
		Global.kidney_at_risk = false

	save_kidney_settings(egfr)
	Global.save_profile()

func _set_kidney_risk(message: String):
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/RiskLabel.text = message

func save_kidney_settings(egfr: float):
	var file = FileAccess.open("user://kidney.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"egfr": egfr,
		"at_risk": Global.kidney_at_risk,
		"known_disease": $Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/KnownDisease.button_pressed
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
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/KnownDisease.button_pressed = known
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields.visible = !known
	if data.has("egfr") and data["egfr"] > 0:
		$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields/eGFRLabel.text = "eGFR: " + str(data["egfr"]) + " mL/min/1.73m²"

# ─────────────────────────────────────────
#  BODY METRICS
# ─────────────────────────────────────────
func _on_calculate_metrics():
	var panel     = $Panel/ScrollContainer/VBoxContainer/BodyMetricsPanel/VBoxContainer
	var weight    = panel.get_node("WeightInput").value
	var height_cm = panel.get_node("HeightInput").value
	var age       = panel.get_node("AgeInput").value
	var activity  = panel.get_node("ActivityOption").selected
	var goal_w    = panel.get_node("GoalWeightInput").value
	var weeks     = panel.get_node("TimeIntervalInput").value
	var is_female = panel.get_node("GenderOption").selected == 1

	var height_m = height_cm / 100.0

	# BMI
	var bmi = weight / (height_m * height_m)
	bmi = snappedf(bmi, 0.1)
	var bmi_category = ""
	if bmi < 18.5:    bmi_category = "Underweight"
	elif bmi < 25.0:  bmi_category = "Normal"
	elif bmi < 30.0:  bmi_category = "Overweight"
	else:             bmi_category = "Obese"
	var bmi_text = "BMI: " + str(bmi) + " (" + bmi_category + ")"
	panel.get_node("BMIResult").text = bmi_text

	# BMR — Mifflin-St Jeor
	var bmr = 10.0 * weight + 6.25 * height_cm - 5.0 * age
	bmr += -161.0 if is_female else 5.0
	bmr = snappedf(bmr, 1.0)
	panel.get_node("BMRResult").text = "BMR: " + str(bmr) + " kcal/day"

	# TDEE
	var tdee_multiplier = [1.2, 1.55, 1.9][activity]
	var tdee = snappedf(bmr * tdee_multiplier, 1.0)
	panel.get_node("TDEEResult").text = "TDEE: " + str(tdee) + " kcal/day"

	# Daily goal
	var days = weeks * 7.0
	var kcal_adjustment = 7700.0 * (goal_w - weight) / days
	var daily_goal = snappedf(tdee + kcal_adjustment, 1.0)
	var direction = ""
	if goal_w < weight:       direction = "deficit to lose weight"
	elif goal_w > weight:     direction = "surplus to gain weight"
	else:                     direction = "maintenance"
	panel.get_node("GoalResult").text = "Daily goal: " + str(daily_goal) + " kcal (" + direction + ")"

	save_body_metrics(weight, height_cm, age, activity, goal_w, weeks, is_female, bmr, tdee, daily_goal, bmi_text)

func save_body_metrics(weight, height, age, activity, goal_w, weeks, is_female, bmr, tdee, daily_goal, bmi_text):
	var file = FileAccess.open("user://body_metrics.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"weight": weight,
		"height": height,
		"age": age,
		"activity": activity,
		"goal_weight": goal_w,
		"weeks": weeks,
		"is_female": is_female,
		"bmr": bmr,
		"tdee": tdee,
		"daily_goal": daily_goal,
		"bmi_text": bmi_text
	}))
	file.close()

	Global.body_metrics = {
		"bmr": bmr,
		"tdee": tdee,
		"daily_goal": daily_goal,
		"goal_weight": goal_w,
		"weight": weight,
		"bmi_text": bmi_text
	}

func load_body_metrics():
	if not FileAccess.file_exists("user://body_metrics.json"): return
	var file = FileAccess.open("user://body_metrics.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return

	var panel = $Panel/ScrollContainer/VBoxContainer/BodyMetricsPanel/VBoxContainer
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
		"bmr": data.get("bmr", 0.0),
		"tdee": data.get("tdee", 0.0),
		"daily_goal": data.get("daily_goal", 0.0),
		"goal_weight": data.get("goal_weight", 0.0),
		"weight": data.get("weight", 0.0),
		"bmi_text": data.get("bmi_text", "BMI: —")
	}

# ─────────────────────────────────────────
#  RESET
# ─────────────────────────────────────────
func _on_reset():
	if FileAccess.file_exists("user://intake.json"):
		DirAccess.remove_absolute("user://intake.json")
	print("Daily intake reset")
