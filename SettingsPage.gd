extends Control

func _ready():
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/KnownDisease.toggled.connect(_on_known_disease_toggled)
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields/CalculateButton.pressed.connect(_on_calculate)
	$Panel/ScrollContainer/VBoxContainer/ResetButton.pressed.connect(_on_reset)
	
	# Load saved kidney settings
	load_kidney_settings()

func _on_known_disease_toggled(checked: bool):
	# Hide input fields if user already knows they have kidney disease
	$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields.visible = !checked
	if checked:
		_set_risk("⚠️ Kidney disease flagged. High oxalate foods will be marked.")
		Global.kidney_at_risk = true
		Global.save_profile()

func _on_calculate():
	var fields = $Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields
	var scr   = fields.get_node("CreatinineInput").value
	var age   = fields.get_node("AgeInput").value
	var is_female = fields.get_node("GenderOption").selected == 1  # 0=Male, 1=Female

	# CKD-EPI formula
	var kappa = 0.7 if is_female else 0.9
	var alpha = -0.329 if is_female else -0.411
	var sex_factor = 1.012 if is_female else 1.0

	var ratio = scr / kappa
	var egfr = 142.0 \
		* pow(min(ratio, 1.0), alpha) \
		* pow(max(ratio, 1.0), -1.200) \
		* pow(0.9938, age) \
		* sex_factor

	egfr = snapped(egfr, 0.1)

	# Show the result
	fields.get_node("eGFRLabel").text = "eGFR: " + str(egfr) + " mL/min/1.73m²"

	# Determine risk
	if egfr <= 60:
		_set_risk("⚠️ eGFR ≤ 60 — kidney function reduced. High oxalate foods will be marked.")
		Global.kidney_at_risk = true
	else:
		_set_risk("✅ eGFR > 60 — kidney function appears normal.")
		Global.kidney_at_risk = false

	save_kidney_settings(egfr)
	Global.save_profile()

func _set_risk(message: String):
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
	if data.has("egfr"):
		$Panel/ScrollContainer/VBoxContainer/KidneyCarePanel/VBoxContainer/InputFields/eGFRLabel.text = "eGFR: " + str(data["egfr"]) + " mL/min/1.73m²"

func _on_reset():
	if FileAccess.file_exists("user://intake.json"):
		DirAccess.remove_absolute("user://intake.json")
