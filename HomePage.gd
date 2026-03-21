extends Control

var today_totals = {
	"calories": 0.0, "protein_g": 0.0, "fat_g": 0.0,
	"carbs_g": 0.0, "fiber_g": 0.0, "calcium_mg": 0.0, "oxalate_mg": 0.0
}
var foods_eaten: Array = []

func _ready():
	Global.load_points()
	load_today()
	refresh_display()

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		refresh_display()

func log_food(food: Dictionary):
	today_totals["calories"]   += food.get("calories", 0)
	today_totals["protein_g"]  += food.get("protein_g", 0)
	today_totals["fat_g"]      += food.get("fat_g", 0)
	today_totals["carbs_g"]    += food.get("carbs_g", 0)
	today_totals["fiber_g"]    += food.get("fiber_g", 0)
	today_totals["calcium_mg"] += food.get("calcium_mg", 0)
	today_totals["oxalate_mg"] += food.get("oxalate_mg_per_100g", 0)
	foods_eaten.append(food.get("name", "Unknown"))
	save_today()
	refresh_display()

func refresh_display():
	var vbox = $Panel/ScrollContainer/VBoxContainer
	vbox.get_node("DateLabel").text = Time.get_date_string_from_system()

	# Totals
	var kcal = snappedf(today_totals["calories"], 0.1)
	vbox.get_node("CaloriesBar/CaloriesValue").text  = str(kcal) + " kcal"
	vbox.get_node("ProteinBar/ProteinValue").text    = str(snappedf(today_totals["protein_g"], 0.1)) + " g"
	vbox.get_node("FatBar/FatValue").text            = str(snappedf(today_totals["fat_g"], 0.1)) + " g"
	vbox.get_node("CarbsBar/CarbsValue").text        = str(snappedf(today_totals["carbs_g"], 0.1)) + " g"
	vbox.get_node("FiberBar/FiberValue").text        = str(snappedf(today_totals["fiber_g"], 0.1)) + " g"
	vbox.get_node("CalciumBar/CalciumValue").text    = str(snappedf(today_totals["calcium_mg"], 0.1)) + " mg"
	vbox.get_node("OxalatesBar/OxalatesValue").text  = str(snappedf(today_totals["oxalate_mg"], 0.1)) + " mg"

	# Calorie goal progress
	var daily_goal = Global.body_metrics.get("daily_goal", 0.0)
	var bmr        = Global.body_metrics.get("bmr", 0.0)
	if daily_goal > 0:
		var remaining = snappedf(daily_goal - kcal, 0.1)
		var sign = "+" if remaining > 0 else ""
		vbox.get_node("GoalLabel").text = "Goal: " + str(snappedf(daily_goal, 0)) + " kcal  |  Remaining: " + sign + str(remaining) + " kcal"
	else:
		vbox.get_node("GoalLabel").text = "Set your goal in Settings ⚙️"

	# Points calculation
	var points = calculate_points(kcal, daily_goal, bmr)
	vbox.get_node("PointsLabel").text = "⭐ Points today: " + str(snappedf(points, 0.1))

	# Save today's points to history
	var today = Time.get_date_string_from_system()
	Global.save_points(today, points)

	# Foods eaten list
	var list = vbox.get_node("FoodsEatenList")
	for child in list.get_children():
		child.queue_free()
	for name in foods_eaten:
		var lbl = Label.new()
		lbl.text = "• " + name
		list.add_child(lbl)

func calculate_points(daily_kcal: float, kcal_goal: float, bmr: float) -> float:
	if bmr == 0: return 0.0
	var goal_weight = Global.body_metrics.get("goal_weight", 0.0)
	var weight      = Global.body_metrics.get("weight", 0.0)
	if goal_weight == 0 or weight == 0: return 0.0

	var kcal_diff = kcal_goal - bmr

	if goal_weight < weight:
		if kcal_diff >= 0 and daily_kcal >= bmr:
			return 1.0 + kcal_diff / 500.0
	elif goal_weight > weight:
		if kcal_diff <= 0 and daily_kcal >= bmr:
			return 1.0 + (-kcal_diff) / 500.0
	return 0.0

func save_today():
	var file = FileAccess.open("user://intake.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"date": Time.get_date_string_from_system(),
		"totals": today_totals,
		"foods": foods_eaten
	}))
	file.close()

func load_today():
	if not FileAccess.file_exists("user://intake.json"): return
	var file = FileAccess.open("user://intake.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	if data.get("date", "") != Time.get_date_string_from_system(): return
	today_totals = data.get("totals", today_totals)
	foods_eaten  = data.get("foods", [])
