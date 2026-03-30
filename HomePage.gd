extends Control

var today_totals = {
	"calories": 0.0, "protein_g": 0.0, "fat_g": 0.0,
	"saturated_fat_g": 0.0, "monounsaturated_fat_g": 0.0, "polyunsaturated_fat_g": 0.0,
	"carbs_g": 0.0, "fiber_g": 0.0, "calcium_mg": 0.0, "oxalate_mg": 0.0,
	"sugar_g": 0.0, "sodium_mg": 0.0, "iron_mg": 0.0, "copper_mg": 0.0, "selenium_mcg": 0.0
}
var foods_eaten: Array = []
var water_ml: float = 0.0

func _ready():
	Global.load_points()
	load_today()
	load_water()
	refresh_display()
	_connect_water_buttons()
func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		refresh_display()


func _connect_water_buttons():
	$Panel/ScrollContainer/VBoxContainer/WaterButtonsRow/Water100Btn.pressed.connect(func(): add_water(100))
	$Panel/ScrollContainer/VBoxContainer/WaterButtonsRow/Water250Btn.pressed.connect(func(): add_water(250))
	$Panel/ScrollContainer/VBoxContainer/WaterButtonsRow/Water500Btn.pressed.connect(func(): add_water(500))
	$Panel/ScrollContainer/VBoxContainer/WaterButtonsRow/WaterResetBtn.pressed.connect(func(): reset_water())

# ── Add water ──
func add_water(ml: float):
	water_ml += ml
	save_water()
	refresh_water_display()

func reset_water():
	water_ml = 0.0
	save_water()
	refresh_water_display()


func log_food(food: Dictionary):
	today_totals["calories"]             += food.get("calories", 0)
	today_totals["protein_g"]            += food.get("protein_g", 0)
	today_totals["fat_g"]                += food.get("fat_g", 0)
	today_totals["saturated_fat_g"]      += food.get("saturated_fat_g", 0)
	today_totals["monounsaturated_fat_g"]+= food.get("monounsaturated_fat_g", 0)
	today_totals["polyunsaturated_fat_g"]+= food.get("polyunsaturated_fat_g", 0)
	today_totals["carbs_g"]              += food.get("carbs_g", 0)
	today_totals["fiber_g"]              += food.get("fiber_g", 0)
	today_totals["calcium_mg"]           += food.get("calcium_mg", 0)
	today_totals["oxalate_mg"]           += food.get("oxalate_mg_per_100g", 0)
	today_totals["sugar_g"]              += food.get("sugar_g", 0)
	today_totals["sodium_mg"]            += food.get("sodium_mg", 0)
	today_totals["iron_mg"]              += food.get("iron_mg", 0)
	today_totals["copper_mg"]            += food.get("copper_mg", 0)
	today_totals["selenium_mcg"]         += food.get("selenium_mcg", 0)
	foods_eaten.append(food.get("name", "Unknown"))
	save_today()
	refresh_display()

func refresh_display():
	var vbox = $Panel/ScrollContainer/VBoxContainer
	var c    = Global.active_metabolic_conditions

	vbox.get_node("DateLabel").text = Time.get_date_string_from_system()

	# ── Macro goals ──
	var macro_goals = Global.get_macro_goals()
	var protein_goal = macro_goals.get("protein_g", 0.0)
	var fat_min      = macro_goals.get("fat_g_min", 0.0)
	var fat_max      = macro_goals.get("fat_g_max", 0.0)
	var carb_min     = macro_goals.get("carbs_g_min", 0.0)
	var carb_max     = macro_goals.get("carbs_g_max", 0.0)
	var fiber_goal   = macro_goals.get("fiber_g", 0.0)

	var p_val  = snappedf(today_totals["protein_g"], 0.1)
	var f_val  = snappedf(today_totals["fat_g"], 0.1)
	var c_val  = snappedf(today_totals["carbs_g"], 0.1)
	var fi_val = snappedf(today_totals["fiber_g"], 0.1)
	
	var protein_str = str(p_val) + " / " + str(protein_goal) + " g " + _goal_bar(p_val, protein_goal)
	var fat_str     = str(f_val) + " / " + str(fat_min) + "–" + str(fat_max) + " g"
	var carb_str    = str(c_val) + " / " + str(carb_min) + "–" + str(carb_max) + " g"
	var fiber_str   = str(fi_val) + " / " + str(fiber_goal) + " g " + _goal_bar(fi_val, fiber_goal)

	vbox.get_node("ProteinBar/ProteinValue").text = protein_str
	vbox.get_node("FatBar/FatValue").text         = fat_str
	vbox.get_node("CarbsBar/CarbsValue").text     = carb_str
	vbox.get_node("FiberBar/FiberValue").text     = fiber_str

	# ── Condition-specific visibility ──
	var has_glycemic  = c.has("glycemic-health") or c.has("nafld")
	var has_lipid     = c.has("nafld") or c.has("lipid-health")
	var has_iron      = c.has("hemochromatosis")
	var has_copper    = c.has("wilsons-disease")
	var has_selenium  = c.has("thyroid-health")
	var has_sodium    = c.has("osteoporosis") or c.has("wilsons-disease")

	vbox.get_node("SugarBar").visible        = has_glycemic
	vbox.get_node("SaturatedFatBar").visible = has_lipid
	vbox.get_node("MonoFatBar").visible      = has_lipid
	vbox.get_node("PolyFatBar").visible      = has_lipid
	vbox.get_node("IronBar").visible         = has_iron
	vbox.get_node("CopperBar").visible       = has_copper
	vbox.get_node("SeleniumBar").visible     = has_selenium
	vbox.get_node("SodiumBar").visible       = has_sodium

	# ── Condition-specific values ──
	if has_glycemic:
		vbox.get_node("SugarBar/SugarValue").text = str(snappedf(today_totals["sugar_g"], 0.1)) + " g"
	if has_lipid:
		vbox.get_node("SaturatedFatBar/SaturatedFatValue").text = str(snappedf(today_totals["saturated_fat_g"], 0.1)) + " g"
		vbox.get_node("MonoFatBar/MonoFatValue").text           = str(snappedf(today_totals["monounsaturated_fat_g"], 0.1)) + " g"
		vbox.get_node("PolyFatBar/PolyFatValue").text           = str(snappedf(today_totals["polyunsaturated_fat_g"], 0.1)) + " g"
	if has_iron:
		vbox.get_node("IronBar/IronValue").text = str(snappedf(today_totals["iron_mg"], 0.1)) + " mg"
	if has_copper:
		vbox.get_node("CopperBar/CopperValue").text = str(snappedf(today_totals["copper_mg"], 0.2)) + " mg"
	if has_selenium:
		vbox.get_node("SeleniumBar/SeleniumValue").text = str(snappedf(today_totals["selenium_mcg"], 0.1)) + " mcg"
	if has_sodium:
		vbox.get_node("SodiumBar/SodiumValue").text = str(snappedf(today_totals["sodium_mg"], 0.1)) + " mg"

	# ── Calorie goal ──
	var kcal       = snappedf(today_totals["calories"], 0.1)
	var daily_goal = Global.body_metrics.get("daily_goal", 0.0)
	var bmr        = Global.body_metrics.get("bmr", 0.0)
	if daily_goal > 0:
		var remaining = snappedf(daily_goal - kcal, 0.1)
		var sign_str = "+" if remaining > 0 else ""
		vbox.get_node("GoalLabel").text = "Goal: " + str(snappedf(daily_goal, 0)) + " kcal  |  Remaining: " + sign_str + str(remaining) + " kcal"
	else:
		vbox.get_node("GoalLabel").text = "Set your goal in Settings ⚙️"


	# ── Water display ──
	refresh_water_display()

	# ── Total points = kcal points + water points ──
	var kcal_points   = calculate_points(kcal, daily_goal, bmr)
	var water_goal_ml = Global.daily_water_liters * 1000.0
	var water_points  = calculate_water_points(water_ml, water_goal_ml)
	var micro_points  = 0.0  # reserved for future micronutrient scoring

	# ── Oxalate penalty (kidney patients only) ──
	var oxalate_penalty = 0.0
	if Global.kidney_at_risk:
		var oxalate_mg  = today_totals.get("oxalate_mg", 0.0)
		var calcium_mg  = today_totals.get("calcium_mg", 0.0)
		# Clinical threshold: >50mg oxalate per 100mg calcium = high risk
		# Daily safe limit: <100mg oxalate for CKD, or <200mg for kidney-at-risk without CKD
		var daily_ox_limit = 50.0  # mg/day for CKD
		var ox_to_ca_ratio = oxalate_mg / max(calcium_mg, 1.0)
		
		if oxalate_mg > daily_ox_limit:
			# -1 point per 50mg over limit
			var excess = oxalate_mg - daily_ox_limit
			oxalate_penalty -= floor(excess / 50.0)
		
		if ox_to_ca_ratio > 0.5:
			# Ratio too high — calcium not compensating oxalate
			# -1 additional point per 0.5 ratio over threshold
			var ratio_excess = ox_to_ca_ratio - 0.5
			oxalate_penalty -= floor(ratio_excess / 0.5)
		
		if oxalate_penalty < 0:
			vbox.get_node("OxalatePenaltyLabel").text = "⚠️ Oxalate penalty: " + str(snappedf(oxalate_penalty, 0.1)) + " pts (Ca ratio: " + str(snappedf(ox_to_ca_ratio, 2)) + ")"
			vbox.get_node("OxalatePenaltyLabel").visible = true
		else:
			vbox.get_node("OxalatePenaltyLabel").visible = false

	var total_points = kcal_points + water_points + micro_points + oxalate_penalty
	vbox.get_node("PointsLabel").text = "⭐ Points today: " + str(snappedf(total_points, 0.1))
	Global.save_points(Time.get_date_string_from_system(), total_points)

	# ── Foods eaten list ──
	var list = vbox.get_node("FoodsEatenList")
	for child in list.get_children():
		child.queue_free()
	for food_name in foods_eaten:
		var lbl = Label.new()
		lbl.text = "• " + food_name
		list.add_child(lbl)

func _goal_bar(value: float, goal: float) -> String:
	if goal <= 0: return ""
	var pct  = clamp(value / goal, 0.0, 1.0)
	var fill = int(pct * 5)
	return "█".repeat(fill) + "░".repeat(5 - fill)
	

func refresh_water_display():
	var vbox = $Panel/ScrollContainer/VBoxContainer
	var water_goal_l  = Global.calculate_water_recommendation()
	var water_goal_ml = water_goal_l * 1000.0
	var water_l       = snappedf(water_ml / 1000.0, 2)
	var goal_l        = snappedf(water_goal_l, 1)

	vbox.get_node("WaterGoalLabel").text = "Goal: " + str(goal_l) + " L/day"

	var pct = clamp(water_ml / water_goal_ml, 0.0, 1.0)
	var bar_text = str(water_l) + " / " + str(goal_l) + " L"
	# Add a simple visual fill indicator using blocks
	var filled = int(pct * 10)
	var bar = "█".repeat(filled) + "░".repeat(10 - filled)
	vbox.get_node("WaterBar/WaterProgress").text = bar_text + "\n" + bar

	var w_pts = calculate_water_points(water_ml, water_goal_ml)
	vbox.get_node("WaterBar/WaterPoints").text = "💧 +" + str(snappedf(w_pts, 0.1)) + " pts"

func calculate_water_points(current_ml: float, goal_ml: float) -> float:
	if goal_ml <= 0: return 0.0
	# 1 point for reaching goal, +1 per extra 500mL beyond goal
	if current_ml >= goal_ml:
		var extra = current_ml - goal_ml
		return 1.0 + floor(extra / 500.0)
	return 0.0

func calculate_points(daily_kcal: float, kcal_goal: float, bmr: float) -> float:
	if bmr == 0: return 0.0
	var goal_weight = Global.body_metrics.get("goal_weight", 0.0)
	var weight      = Global.body_metrics.get("weight", 0.0)
	if goal_weight == 0 or weight == 0: return 0.0

	if goal_weight > weight:
		if daily_kcal >= kcal_goal:
			return 1.0 + floor((daily_kcal - kcal_goal) / 500.0)
	elif goal_weight < weight:
		if daily_kcal <= kcal_goal and daily_kcal >= bmr:
			return 1.0 + floor((kcal_goal - daily_kcal) / 500.0)
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
	var saved = data.get("totals", {})
	for key in today_totals.keys():
		if saved.has(key):
			today_totals[key] = saved[key]
	foods_eaten = data.get("foods", [])

func save_water():
	var file = FileAccess.open("user://water.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"date": Time.get_date_string_from_system(),
		"water_ml": water_ml
	}))
	file.close()

func load_water():
	if not FileAccess.file_exists("user://water.json"): return
	var file = FileAccess.open("user://water.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	# Only load if saved today
	if data.get("date","") != Time.get_date_string_from_system(): return
	water_ml = data.get("water_ml", 0.0)
