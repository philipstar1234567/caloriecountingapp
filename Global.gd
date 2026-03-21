extends Node

var body_metrics: Dictionary = {
	"bmr": 0.0,
	"tdee": 0.0,
	"daily_goal": 0.0,
	"goal_weight": 0.0,
	"weight": 0.0
}

# ── Health conditions selected by user ──
var active_conditions: Array = []

# ── Kidney risk flag (set from SettingsPage) ──
var kidney_at_risk: bool = false

# ── Warning thresholds per condition ──
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

# ── Called by any script to get warnings for a food ──
func get_warnings(food: Dictionary) -> Array:
	var warnings = []
	var oxalate = food.get("oxalate_mg_per_100g", 0)

	# Kidney risk check (eGFR-based or known disease)
	if kidney_at_risk:
		if oxalate >= 50:
			warnings.append({
				"severity": "avoid",
				"message": "High oxalate — avoid due to kidney risk."
			})
		elif oxalate >= 10:
			warnings.append({
				"severity": "caution",
				"message": "Moderate oxalate — caution due to kidney risk."
			})

	# Other conditions
	for key in active_conditions:
		if not conditions_data.has(key): continue
		var c = conditions_data[key]
		if oxalate >= c["avoid"]:
			warnings.append({"severity": "avoid", "message": c["avoid_msg"]})
		elif oxalate >= c["caution"]:
			warnings.append({"severity": "caution", "message": c["caution_msg"]})

	return warnings

# ── Save profile (conditions + kidney risk) ──
func save_profile():
	var file = FileAccess.open("user://profile.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"conditions": active_conditions,
		"kidney_at_risk": kidney_at_risk
	}))
	file.close()

# ── Load profile on startup ──
func load_profile():
	if not FileAccess.file_exists("user://profile.json"): return
	var file = FileAccess.open("user://profile.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	active_conditions = data.get("conditions", [])
	kidney_at_risk = data.get("kidney_at_risk", false)

var points_history: Dictionary = {}  # key = "YYYY-MM-DD", value = points

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
		var date = Time.get_date_string_from_datetime_dict(
			Time.get_datetime_dict_from_unix_time(unix_day)
		)
		total += points_history.get(date, 0.0)
	return total

func get_points_alltime() -> float:
	var total = 0.0
	for val in points_history.values():
		total += val
	return total
