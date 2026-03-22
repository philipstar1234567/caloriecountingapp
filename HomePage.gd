extends Control

var today_totals = {
	"calories": 0.0, "protein_g": 0.0, "fat_g": 0.0,
	"saturated_fat_g": 0.0, "monounsaturated_fat_g": 0.0, "polyunsaturated_fat_g": 0.0,
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
	today_totals["saturated_fat_g"]       += food.get("saturated_fat_g", 0)
	today_totals["monounsaturated_fat_g"] += food.get("monounsaturated_fat_g", 0)
	today_totals["polyunsaturated_fat_g"] += food.get("polyunsaturated_fat_g", 0)
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
	var conditions = Global.active_metabolic_conditions  # new array in Global

	# Always show these
	vbox.get_node("CaloriesBar").visible = true
	vbox.get_node("ProteinBar").visible = true
	vbox.get_node("FatBar").visible = true
	vbox.get_node("CarbsBar").visible = true
	vbox.get_node("FiberBar").visible = true
	vbox.get_node("CalciumBar").visible = true
	vbox.get_node("OxalatesBar").visible = true
	vbox.get_node("GoalLabel").visible = true
	vbox.get_node("PointsLabel").visible = true

	# Only show if relevant condition active
	var has_glycemic = conditions.has("glycemic-health") or conditions.has("nafld")
	var has_lipid    = conditions.has("nafld") or conditions.has("lipid-health")
	var has_iron     = conditions.has("hemochromatosis")
	var has_copper   = conditions.has("wilsons-disease")
	var has_selenium = conditions.has("hashimotos")
	var has_sodium   = conditions.has("osteoporosis") or conditions.has("fabry")

	vbox.get_node("SugarBar").visible          = has_glycemic
	vbox.get_node("SaturatedFatBar").visible   = has_lipid
	vbox.get_node("MonoFatBar").visible        = has_lipid
	vbox.get_node("PolyFatBar").visible        = has_lipid
	vbox.get_node("IronBar").visible           = has_iron
	vbox.get_node("CopperBar").visible         = has_copper
	vbox.get_node("SeleniumBar").visible       = has_selenium
	vbox.get_node("SodiumBar").visible         = has_sodium

	# Totals
	var kcal = snappedf(today_totals["calories"], 0.1)
	vbox.get_node("CaloriesBar/CaloriesValue").text  = str(kcal) + " kcal"
	vbox.get_node("ProteinBar/ProteinValue").text    = str(snappedf(today_totals["protein_g"], 0.1)) + " g"
	vbox.get_node("FatBar/FatValue").text            = str(snappedf(today_totals["fat_g"], 0.1)) + " g"
	vbox.get_node("SaturatedFatBar/SaturatedFatValue").text = str(snappedf(today_totals["saturated_fat_g"], 0.1)) + " g"
	vbox.get_node("MonoFatBar/MonoFatValue").text           = str(snappedf(today_totals["monounsaturated_fat_g"], 0.1)) + " g"
	vbox.get_node("PolyFatBar/PolyFatValue").text           = str(snappedf(today_totals["polyunsaturated_fat_g"], 0.1)) + " g"
	vbox.get_node("CarbsBar/CarbsValue").text        = str(snappedf(today_totals["carbs_g"], 0.1)) + " g"
	vbox.get_node("FiberBar/FiberValue").text        = str(snappedf(today_totals["fiber_g"], 0.1)) + " g"
	vbox.get_node("CalciumBar/CalciumValue").text    = str(snappedf(today_totals["calcium_mg"], 0.1)) + " mg"
	vbox.get_node("OxalatesBar/OxalatesValue").text  = str(snappedf(today_totals["oxalate_mg"], 0.1)) + " mg"

	# Calorie goal progress
	var daily_goal = Global.body_metrics.get("daily_goal", 0.0)
	var bmr        = Global.body_metrics.get("bmr", 0.0)
	if daily_goal > 0:
		var remaining = snappedf(daily_goal - kcal, 0.1)
		var sign_str = "+" if remaining > 0 else ""
		vbox.get_node("GoalLabel").text = "Goal: " + str(snappedf(daily_goal, 0)) + " kcal  |  Remaining: " + sign_str + str(remaining) + " kcal"
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
	for food_name in foods_eaten:
		var lbl = Label.new()
		lbl.text = "• " + food_name
		list.add_child(lbl)

func calculate_points(daily_kcal: float, kcal_goal: float, bmr: float) -> float:
	if bmr == 0: return 0.0
	var goal_weight = Global.body_metrics.get("goal_weight", 0.0)
	var weight      = Global.body_metrics.get("weight", 0.0)
	if goal_weight == 0 or weight == 0: return 0.0

	if goal_weight > weight:
		# Gaining weight — reward eating at or over goal
		if daily_kcal >= kcal_goal:
			var extra_kcal = daily_kcal - kcal_goal
			var bonus = floor(extra_kcal / 500.0)
			return 1.0 + bonus

	elif goal_weight < weight:
		# Losing weight — reward staying at or under goal
		if daily_kcal <= kcal_goal and daily_kcal >= bmr:
			var saved_kcal = kcal_goal - daily_kcal
			var bonus = floor(saved_kcal / 500.0)
			return 1.0 + bonus

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
	# Merge saved values into today_totals instead of replacing entirely
	# This way new fields that didn't exist in old saves default to 0
	var saved = data.get("totals", {})
	for key in today_totals.keys():
		if saved.has(key):
			today_totals[key] = saved[key]
	foods_eaten = data.get("foods", [])
