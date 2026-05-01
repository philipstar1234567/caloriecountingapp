extends Control

var today_totals: Dictionary = {}
var foods_eaten: Array = []
var water_ml: float = 0.0
var meal_history: Dictionary = {}

const GLASS_FULL_PATH  = "res://images/glass_full.png"
const GLASS_EMPTY_PATH = "res://images/glass_empty.png"
var glass_states: Array = []  # true = full, false = empty

func _ready():
	$Panel/ScrollContainer/VBoxContainer/StreakRow/WeeklyReportBtn.pressed.connect(func():
		_show_reflection_screen()
		# Mark as shown so it won't auto-show again today
		Global.mark_report_shown()
)
	$Panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	$Panel.clip_contents = true
	$Panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_init_today_totals()
	Global.load_currency()
	Global.load_quests()
	Global.get_personalized_quests()
	load_today()
	load_water()
	load_meal_history()
	Global.load_streak()
	refresh_display()
	Global.quest_completed.connect(func(_q): refresh_display())
	Global.py_awarded.connect(func(_a, _r): _refresh_streak_row())
	Global.streak_milestone_reached.connect(_on_streak_milestone)
	var sc = $Panel/ScrollContainer
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.clip_contents = true

	var vbox = $Panel/ScrollContainer/VBoxContainer
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	_check_weekly_reflection()


func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		load_meal_history()
		refresh_display()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		# Save current day to history even if nothing was logged
		_save_to_history()
		save_today()
		save_water()

func _init_today_totals():
	today_totals = {
		"calories":0.0,"protein_g":0.0,"fat_g":0.0,
		"saturated_fat_g":0.0,"monounsaturated_fat_g":0.0,"polyunsaturated_fat_g":0.0,
		"carbs_g":0.0,"fiber_g":0.0,"calcium_mg":0.0,"oxalate_mg":0.0,
		"sugar_g":0.0,"sodium_mg":0.0,"iron_mg":0.0,"copper_mg":0.0,"selenium_mcg":0.0,
		"vitamin_a_mcg":0.0,"vitamin_b1_mg":0.0,"vitamin_b2_mg":0.0,"vitamin_b3_mg":0.0,
		"vitamin_b5_mg":0.0,"vitamin_b6_mg":0.0,"vitamin_b7_mcg":0.0,"vitamin_b9_mcg":0.0,
		"vitamin_b12_mcg":0.0,"vitamin_c_mg":0.0,"vitamin_d_mcg":0.0,"vitamin_e_mg":0.0,
		"vitamin_k1_mcg":0.0,"vitamin_k2_mcg":0.0,
		"magnesium_mg":0.0,"potassium_mg":0.0,"zinc_mg":0.0,"phosphorus_mg":0.0,
		"manganese_mg":0.0,"chromium_mcg":0.0,"iodine_mcg":0.0,"molybdenum_mcg":0.0,
		"beta_carotene_mcg":0.0,"lycopene_mcg":0.0,"lutein_zeaxanthin_mcg":0.0,
		"quercetin_mg":0.0,"anthocyanins_mg":0.0,"resveratrol_mg":0.0,
		"total_polyphenols_mg":0.0
	}

# ─────────────────────────────────────────
#  LOG FOOD
# ─────────────────────────────────────────
func log_food(food: Dictionary):
	for key in today_totals.keys():
		var food_key = "oxalate_mg_per_100g" if key == "oxalate_mg" else key
		today_totals[key] += food.get(food_key, 0.0)
	foods_eaten.append(food.get("name", "Unknown"))

	# ── Strict avoid penalty ──
	var strict_conditions = Global._get_strict_avoid_conditions(food)
	if not strict_conditions.is_empty():
		var today = Time.get_date_string_from_system()
		var current_pts = Global.points_history.get(today, 0.0)
		Global.save_points(today, current_pts - float(strict_conditions.size()))
		_show_strict_avoid_penalty_toast(food, strict_conditions)

	Global.check_and_update_streak()
	save_today()
	_save_to_history()
	Global.check_badges()
	var totals_for_quests = today_totals.duplicate()
	totals_for_quests["water_ml"] = water_ml
	Global.check_quests(totals_for_quests)
	refresh_display()

func _show_strict_avoid_penalty_toast(food: Dictionary, conditions: Array):
	var existing = get_node_or_null("StrictAvoidToast")
	if existing: existing.queue_free()

	var panel = PanelContainer.new()
	panel.name = "StrictAvoidToast"
	panel.z_index = 60
	panel.set_anchor_and_offset(SIDE_LEFT,   0, 10)
	panel.set_anchor_and_offset(SIDE_RIGHT,  1, -10)
	panel.set_anchor_and_offset(SIDE_TOP,    0, 10)
	panel.set_anchor_and_offset(SIDE_BOTTOM, 0, 110)
	panel.modulate.a = 0.0

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "⛔ −" + str(conditions.size()) + " pt  Strict avoid eaten: " + food.get("name","")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	for c in conditions:
		var lbl = Label.new()
		lbl.text = "Strictly contraindicated for: " + c.replace("-"," ").capitalize()
		lbl.add_theme_font_size_override("font_size", 19)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.4))
		vbox.add_child(lbl)

	add_child(panel)
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(3.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): panel.queue_free())

# ─────────────────────────────────────────
#  WATER
# ─────────────────────────────────────────
func add_water(ml: float):
	water_ml += ml
	save_water()
	_refresh_water_card()

func reset_water():
	water_ml = 0.0
	glass_states = []
	save_water()
	_refresh_water_card()

# ─────────────────────────────────────────
#  REFRESH ALL
# ─────────────────────────────────────────
func refresh_display():
	_refresh_streak_row()
	_refresh_quests_card()
	_refresh_meal_history_card()
	if Global.simple_mode:
		_refresh_simple_kcal_card()
	else:
		_refresh_macro_card()
		_refresh_micro_card()
	_refresh_water_card()
	_refresh_tips_card()
	
	var macro_card = $Panel/ScrollContainer/VBoxContainer/MacroCard
	var micro_card = $Panel/ScrollContainer/VBoxContainer/MicroCard
	var simple_card = $Panel/ScrollContainer/VBoxContainer/SimpleKcalCard
	if macro_card:  macro_card.visible  = not Global.simple_mode
	if micro_card:  micro_card.visible  = not Global.simple_mode
	if simple_card: simple_card.visible = Global.simple_mode
	#_fix_labels_in($Panel/ScrollContainer/VBoxContainer)
	
func _refresh_simple_kcal_card():
	var card = $Panel/ScrollContainer/VBoxContainer/SimpleKcalCard
	if not card: return
	var vbox = card.get_node("VBoxContainer")
	for child in vbox.get_children(): child.queue_free()

	var daily_goal = Global.body_metrics.get("daily_goal", 0.0)
	var kcal       = today_totals.get("calories", 0.0)
	var remaining  = daily_goal - kcal

	var title = Label.new()
	title.text = "🔥 Calories Today"
	title.add_theme_font_size_override("font_size", 28)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var kcal_lbl = Label.new()
	kcal_lbl.text = str(snappedf(kcal, 0.1)) + " kcal"
	kcal_lbl.add_theme_font_size_override("font_size", 48)
	kcal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	kcal_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	vbox.add_child(kcal_lbl)

	if daily_goal > 0:
		var pct   = clamp(kcal / daily_goal, 0.0, 1.0)
		var fill  = int(pct * 10)
		var bar   = Label.new()
		bar.text  = "█".repeat(fill) + "░".repeat(10 - fill)
		bar.add_theme_font_size_override("font_size", 22)
		bar.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(bar)

		var goal_lbl = Label.new()
		var rem_str  = ("+" if remaining < 0 else "") + str(snappedf(abs(remaining),0.1))
		goal_lbl.text = "Goal: " + str(snappedf(daily_goal,0.1)) + " kcal  |  " + \
			("Over by " if remaining < 0 else "Remaining: ") + rem_str + " kcal"
		goal_lbl.add_theme_font_size_override("font_size", 22)
		goal_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if remaining < 0:
			goal_lbl.add_theme_color_override("font_color", Color(1.0,0.4,0.3))
		vbox.add_child(goal_lbl)
# ─────────────────────────────────────────
#  STREAK ROW (always visible at top)
# ─────────────────────────────────────────
func _refresh_streak_row():
	var row = $Panel/ScrollContainer/VBoxContainer/StreakRow
	if not row: return

	# Load level from LeaderboardPage if available, else from file
	var level = 0
	var lb = get_tree().root.get_node_or_null("Main/ContentArea/LeaderboardPage")
	if lb: level = lb.user_level
	else:
		if FileAccess.file_exists("user://level.json"):
			var f = FileAccess.open("user://level.json", FileAccess.READ)
			var d = JSON.parse_string(f.get_as_text())
			f.close()
			if d: level = d.get("level", 0)

	var level_lbl = row.get_node_or_null("LevelLabel")
	if level_lbl:
		level_lbl.text = "⚡ Lv." + str(level)

	var streak = Global.daily_streak
	var flame_color = Color.GRAY
	if streak >= 100: flame_color = Color(1.0, 0.85, 0.0)
	elif streak >= 30: flame_color = Color(1.0, 0.2, 0.1)
	elif streak >= 7:  flame_color = Color(1.0, 0.5, 0.0)

	var streak_lbl = row.get_node_or_null("StreakLabel")
	if streak_lbl:
		streak_lbl.text = "🔥 " + str(streak) + " days"
		streak_lbl.add_theme_color_override("font_color", flame_color)

	var freeze_lbl = row.get_node_or_null("FreezesLabel")
	if freeze_lbl:
		freeze_lbl.text = "🧊 ×" + str(Global.streak_freeze_count)

	var py_lbl = row.get_node_or_null("PYLabel")
	if py_lbl:
		py_lbl.text = "💰 " + str(Global.py_currency) + " PY"

# ─────────────────────────────────────────
#  PANEL 1 — QUESTS CARD
# ─────────────────────────────────────────
func _refresh_quests_card():
	var card = $Panel/ScrollContainer/VBoxContainer/QuestsCard
	var vbox = card.get_node("VBoxContainer")
	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "✅ Daily Quests"
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	# Show first 3 quests
	var quests = Global.today_quests
	var shown  = min(3, quests.size())
	for i in range(shown):
		vbox.add_child(_make_quest_mini_row(quests[i]))

	if quests.size() > 3:
		var more_btn = Button.new()
		more_btn.text = "See all quests →"
		more_btn.flat = true
		more_btn.pressed.connect(func(): _open_quests_overlay())
		vbox.add_child(more_btn)

	# Make card clickable to open overlay
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_open_quests_overlay()
	)
	#_fix_labels_in($Panel/ScrollContainer/VBoxContainer/QuestsCard)

func _make_quest_mini_row(quest: Dictionary) -> HBoxContainer:
	var qid = quest.get("id","")
	var done = Global.completed_quest_ids.has(qid)
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var icon = Label.new()
	icon.text = "✅" if done else ("⭐" if quest.get("tier") == "bonus" else "◯")
	icon.add_theme_font_size_override("font_size", 48)
	row.add_child(icon)

	var desc = Label.new()
	desc.text = quest.get("desc","")
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.add_theme_font_size_override("font_size", 36)
	if done:
		desc.add_theme_color_override("font_color", Color(0.5,0.5,0.5))
	row.add_child(desc)

	var py = Label.new()
	py.text = "+" + str(quest.get("py",10)) + " PY"
	py.add_theme_font_size_override("font_size", 48)
	py.add_theme_color_override("font_color",
		Color(0.5,0.5,0.5) if done else Color(1.0,0.85,0.0))
	row.add_child(py)
	return row

func _open_quests_overlay():
	_show_overlay_panel(func(scroll_vbox):
		var title = Label.new()
		title.text = "📋 All Daily Quests"
		title.add_theme_font_size_override("font_size", 48)
		scroll_vbox.add_child(title)
		scroll_vbox.add_child(HSeparator.new())
		for quest in Global.today_quests:
			scroll_vbox.add_child(_make_quest_mini_row(quest))
	)

# ─────────────────────────────────────────
#  PANEL 2 — MEAL HISTORY CARD
# ─────────────────────────────────────────
func _refresh_meal_history_card():
	var card = $Panel/ScrollContainer/VBoxContainer/MealHistoryCard
	var vbox = card.get_node("VBoxContainer")
	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "🍽 Today's Meals"
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	var shown = min(3, foods_eaten.size())
	if shown == 0:
		var empty = Label.new()
		empty.text = "Nothing logged yet"
		empty.add_theme_color_override("font_color", Color(0.5,0.5,0.5))
		vbox.add_child(empty)

		var more = Button.new()
		more.text = "See full history →"
		more.flat = true
		more.pressed.connect(func(): _open_meal_history_overlay(Time.get_date_string_from_system()))
		vbox.add_child(more)
	else:
		for i in range(shown):
			var lbl = Label.new()
			lbl.text = "• " + foods_eaten[foods_eaten.size() - 1 - i]
			lbl.add_theme_font_size_override("font_size", 36)
			vbox.add_child(lbl)

		var more = Button.new()
		more.text = "See full history →"
		more.flat = true
		more.pressed.connect(func(): _open_meal_history_overlay(Time.get_date_string_from_system()))
		vbox.add_child(more)
		#_fix_labels_in($Panel/ScrollContainer/VBoxContainer/MealHistoryCard)

func _open_meal_history_overlay(_start_date: String):
	_show_overlay_panel(func(scroll_vbox):
		# Navigation state — use a RefCounted wrapper so lambdas share the reference
		var state = {"date": Time.get_date_string_from_system()}

		# Nav row
		var nav = HBoxContainer.new()
		nav.add_theme_constant_override("separation", 8)
		scroll_vbox.add_child(nav)

		var prev_btn = Button.new()
		prev_btn.text = "‹"
		prev_btn.add_theme_font_size_override("font_size", 36)
		prev_btn.custom_minimum_size = Vector2(60, 60)
		nav.add_child(prev_btn)

		# Date button — opens calendar popup
		var date_btn = Button.new()
		date_btn.text = state["date"]
		date_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		date_btn.add_theme_font_size_override("font_size", 36)
		nav.add_child(date_btn)

		var next_btn = Button.new()
		next_btn.text = "›"
		next_btn.add_theme_font_size_override("font_size", 36)
		next_btn.custom_minimum_size = Vector2(60, 60)
		nav.add_child(next_btn)

		scroll_vbox.add_child(HSeparator.new())

		var content_vbox = VBoxContainer.new()
		content_vbox.name = "ContentVBox"
		content_vbox.add_theme_constant_override("separation", 8)
		scroll_vbox.add_child(content_vbox)

		# Calendar popup (date picker)
		var calendar_panel: PanelContainer = null

		var _navigate = func(new_date: String):
			state["date"] = new_date
			date_btn.text = new_date
			for child in content_vbox.get_children():
				child.queue_free()
			_populate_history_content(content_vbox, new_date)

		prev_btn.pressed.connect(func():
			_navigate.call(_offset_date(state["date"], -1))
		)

		next_btn.pressed.connect(func():
			var today = Time.get_date_string_from_system()
			if state["date"] < today:
				_navigate.call(_offset_date(state["date"], 1))
		)

		date_btn.pressed.connect(func():
			if calendar_panel and is_instance_valid(calendar_panel):
				calendar_panel.queue_free()
				calendar_panel = null
				return
			calendar_panel = _make_calendar_popup(state["date"], func(picked: String):
				if calendar_panel and is_instance_valid(calendar_panel):
					calendar_panel.queue_free()
					calendar_panel = null
				_navigate.call(picked)
			)
			scroll_vbox.add_child(calendar_panel)
		)

		_populate_history_content(content_vbox, state["date"])
	)

func _make_calendar_popup(current_date: String, on_picked: Callable) -> PanelContainer:
	var panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var parts = current_date.split("-")
	var year  = int(parts[0])
	var month = int(parts[1])

	var header = HBoxContainer.new()
	vbox.add_child(header)

	var prev_mo = Button.new(); prev_mo.text = "‹"; header.add_child(prev_mo)
	var mo_lbl  = Label.new()
	mo_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mo_lbl.horizontal_alignment  = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(mo_lbl)
	var next_mo = Button.new(); next_mo.text = "›"; header.add_child(next_mo)

	var grid = GridContainer.new()
	grid.columns = 7
	vbox.add_child(grid)

	var state = {"year": year, "month": month}

	var _rebuild = func():
		mo_lbl.text = "%04d-%02d" % [state["year"], state["month"]]
		for child in grid.get_children(): child.queue_free()
		# Day headers
		for d in ["Mo","Tu","We","Th","Fr","Sa","Su"]:
			var h = Label.new(); h.text = d
			h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_theme_font_size_override("font_size", 36)
			grid.add_child(h)
		# Find first weekday of month
		var first_unix = Time.get_unix_time_from_datetime_dict({
			"year":state["year"],"month":state["month"],"day":1,
			"hour":12,"minute":0,"second":0
		})
		var first_dt  = Time.get_datetime_dict_from_unix_time(first_unix)
		var weekday   = first_dt.get("weekday", 1)  # 0=Sun,1=Mon,...
		var offset    = (weekday + 6) % 7            # Mon=0
		for i in range(offset):
			grid.add_child(Control.new())  # empty cells
		# Days in month
		var days_in_month = 31
		for test_day in range(28, 32):
			var test_unix = Time.get_unix_time_from_datetime_dict({
				"year":state["year"],"month":state["month"],"day":test_day,
				"hour":12,"minute":0,"second":0
			})
			var test_dt = Time.get_datetime_dict_from_unix_time(test_unix)
			if test_dt["month"] == state["month"]:
				days_in_month = test_day
		for day in range(1, days_in_month + 1):
			var day_str = "%04d-%02d-%02d" % [state["year"], state["month"], day]
			var day_btn = Button.new()
			day_btn.text = str(day)
			day_btn.custom_minimum_size = Vector2(40, 40)
			day_btn.add_theme_font_size_override("font_size", 36)
			# Highlight days that have history
			if meal_history.has(day_str) and not meal_history[day_str].get("foods",[]).is_empty():
				day_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
			var captured = day_str
			day_btn.pressed.connect(func(): on_picked.call(captured))
			grid.add_child(day_btn)

	var rebuild_ref = _rebuild  # keep reference
	_rebuild.call()

	prev_mo.pressed.connect(func():
		state["month"] -= 1
		if state["month"] < 1: state["month"] = 12; state["year"] -= 1
		rebuild_ref.call()
	)
	next_mo.pressed.connect(func():
		state["month"] += 1
		if state["month"] > 12: state["month"] = 1; state["year"] += 1
		rebuild_ref.call()
	)

	return panel

func _populate_history_content(vbox: VBoxContainer, date_str: String):
	var today = Time.get_date_string_from_system()
	var foods_list: Array = []
	var kcal: float = 0.0

	if date_str == today:
		foods_list = foods_eaten
		kcal       = today_totals.get("calories", 0.0)
	elif meal_history.has(date_str):
		var h  = meal_history[date_str]
		foods_list = h.get("foods", [])
		kcal       = h.get("totals",{}).get("calories", 0.0)

	var kcal_lbl = Label.new()
	kcal_lbl.text = date_str + " — " + str(snappedf(kcal, 0.1)) + " kcal"
	kcal_lbl.add_theme_font_size_override("font_size", 36)
	kcal_lbl.add_theme_color_override("font_color",
		Color(0.3,1.0,0.3) if date_str == today else Color(0.7,0.7,0.7))
	vbox.add_child(kcal_lbl)

	if foods_list.is_empty():
		var empty = Label.new()
		empty.text = "No foods logged this day"
		empty.add_theme_color_override("font_color", Color(0.5,0.5,0.5))
		empty.add_theme_font_size_override("font_size", 36)
		vbox.add_child(empty)
		return

	for food_name in foods_list:
		var lbl = Label.new()
		lbl.text = "• " + food_name
		lbl.add_theme_font_size_override("font_size", 36)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(lbl)

func _offset_date(date_str: String, days: int) -> String:
	var parts = date_str.split("-")
	var dt = {"year":int(parts[0]),"month":int(parts[1]),"day":int(parts[2]),
			  "hour":12,"minute":0,"second":0}
	var unix = Time.get_unix_time_from_datetime_dict(dt) + days * 86400
	var nd   = Time.get_datetime_dict_from_unix_time(unix)
	return "%04d-%02d-%02d" % [nd.year, nd.month, nd.day]

# ─────────────────────────────────────────
#  PANEL 3 — MACRO CARD
# ─────────────────────────────────────────
func _refresh_macro_card():
	var card = $Panel/ScrollContainer/VBoxContainer/MacroCard
	var vbox = card.get_node("VBoxContainer")
	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "Macronutrients"
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	# Circle indicators row
	var macro_goals  = Global.get_macro_goals()
	var daily_goal   = Global.body_metrics.get("daily_goal", 2000.0)
	var circles_row  = HBoxContainer.new()
	circles_row.alignment = BoxContainer.ALIGNMENT_CENTER
	circles_row.add_theme_constant_override("separation", 16)
	vbox.add_child(circles_row)

	var macros = [
		{"key":"calories",    "label":"kcal", "goal":daily_goal},
		{"key":"protein_g",   "label":"P",    "goal":macro_goals.get("protein_g",50.0)},
		{"key":"fat_g",       "label":"Fat",  "goal":macro_goals.get("fat_g_max",70.0)},
		{"key":"carbs_g",     "label":"Carb", "goal":macro_goals.get("carbs_g_max",300.0)},
		{"key":"fiber_g",     "label":"Fibre","goal":macro_goals.get("fiber_g",25.0)},
	]

	for macro in macros:
		var val  = today_totals.get(macro["key"], 0.0)
		var goal = macro["goal"]
		var pct  = clamp(val / goal, 0.0, 1.2) if goal > 0 else 0.0
		var state = "green" if pct >= 0.9 else ("yellow" if pct >= 0.5 else "red")

		var col = VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		circles_row.add_child(col)

		# Circle image — you provide these 3 versions per macro
		var img = TextureRect.new()
		img.custom_minimum_size = Vector2(64, 64)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var img_path = "res://images/macro_" + macro["label"].to_lower() + "_" + state + ".png"
		if ResourceLoader.exists(img_path):
			img.texture = load(img_path)
		else:
			# Fallback colored rect if image not found
			var cr = ColorRect.new()
			cr.custom_minimum_size = Vector2(64, 64)
			cr.color = Color.GREEN if state == "green" else (Color.YELLOW if state == "yellow" else Color.RED)
			col.add_child(cr)
		col.add_child(img)

		#var lbl = Label.new()
		#lbl.text = macro["label"]
		#lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		#lbl.add_theme_font_size_override("font_size", 18)
		#col.add_child(lbl)

	# Click opens detail overlay
	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_open_macro_overlay()
	)
	#_fix_labels_in($Panel/ScrollContainer/VBoxContainer/MacroCard)

func _open_macro_overlay():
	_show_overlay_panel(func(scroll_vbox):
		var title = Label.new()
		title.text = "📊 Macronutrients — Today"
		title.add_theme_font_size_override("font_size", 48)
		scroll_vbox.add_child(title)
		scroll_vbox.add_child(HSeparator.new())

		var macro_goals = Global.get_macro_goals()
		var daily_goal  = Global.body_metrics.get("daily_goal", 2000.0)
		var bmr         = Global.body_metrics.get("bmr", 0.0)

		var entries = [
			{"label":"Calories",      "key":"calories",    "unit":"kcal","goal":daily_goal,                         "min":bmr},
			{"label":"Protein",       "key":"protein_g",   "unit":"g",  "goal":macro_goals.get("protein_g",50.0),  "min":0},
			{"label":"Fat",           "key":"fat_g",       "unit":"g",  "goal":macro_goals.get("fat_g_max",70.0),  "min":macro_goals.get("fat_g_min",44.0)},
			{"label":"  Saturated",   "key":"saturated_fat_g","unit":"g","goal":20.0,                              "min":0},
			{"label":"Carbohydrates", "key":"carbs_g",     "unit":"g",  "goal":macro_goals.get("carbs_g_max",300.0),"min":macro_goals.get("carbs_g_min",225.0)},
			{"label":"  Sugar",       "key":"sugar_g",     "unit":"g",  "goal":50.0,                              "min":0},
			{"label":"Fiber",         "key":"fiber_g",     "unit":"g",  "goal":macro_goals.get("fiber_g",25.0),   "min":0},
			{"label":"Calcium",       "key":"calcium_mg",  "unit":"mg", "goal":1000.0,                            "min":0},
			{"label":"Sodium",        "key":"sodium_mg",   "unit":"mg", "goal":2300.0,                            "min":0},
		]

		for e in entries:
			scroll_vbox.add_child(_make_progress_row(e))
	)

func _make_progress_row(entry: Dictionary) -> VBoxContainer:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)

	var row = HBoxContainer.new()
	col.add_child(row)

	var key_lbl = Label.new()
	key_lbl.text = entry["label"]
	key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	key_lbl.add_theme_font_size_override("font_size", 36)
	row.add_child(key_lbl)

	var val  = today_totals.get(entry["key"], 0.0)
	var goal = entry.get("goal", 0.0)
	var min_val = entry.get("min", 0.0)
	var pct  = clamp(val / goal, 0.0, 1.0) if goal > 0 else 0.0

	var val_lbl = Label.new()
	val_lbl.text = str(snappedf(val,0.1)) + " / " + str(snappedf(goal,0.1)) + " " + entry.get("unit","")
	val_lbl.add_theme_font_size_override("font_size", 36)
	if pct >= 1.0:
		val_lbl.add_theme_color_override("font_color", Color(0.3,1.0,0.3))
	elif pct >= 0.5:
		val_lbl.add_theme_color_override("font_color", Color(1.0,0.85,0.0))
	row.add_child(val_lbl)

	# Progress bar — blocks
	var filled = int(pct * 10)
	var bar_lbl = Label.new()
	bar_lbl.text = "█".repeat(filled) + "░".repeat(10 - filled)
	bar_lbl.add_theme_font_size_override("font_size", 36)
	col.add_child(bar_lbl)

	return col

# ─────────────────────────────────────────
#  PANEL 4 — MICRO CARD
# ─────────────────────────────────────────
const VITAMIN_FIELDS = [
	"vitamin_a_mcg","vitamin_d_mcg","vitamin_e_mg","vitamin_k2_mcg","vitamin_b1_mg","vitamin_b2_mg","vitamin_b3_mg",
	"vitamin_b5_mg","vitamin_b6_mg","vitamin_b7_mcg","vitamin_b9_mcg",
	"vitamin_b12_mcg","vitamin_c_mg"
]
const VITAMIN_LABELS = ["A","B1","B2","B3","B5","B6","B7","B9","B12","C","D","E","K2"]

func _refresh_micro_card():
	var card = $Panel/ScrollContainer/VBoxContainer/MicroCard
	var vbox = card.get_node("VBoxContainer")
	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "Micronutrients"
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	var rdas = Global.get_micronutrient_rdas()

	# VITAMIN_FIELDS order: A, B1, B2, B3, B5, B6, B7, B9, B12, C, D, E, K2
	# VITAMIN_LABELS order: A, B1, B2, B3, B5, B6, B7, B9, B12, C, D, E, K2
	# Water soluble: B1,B2,B3,B5,B6,B7,B9,B12,C → indices 1–9
	# Fat soluble:   A, D, E, K2               → indices 0, 10, 11, 12

	var water_soluble_indices = [1, 2, 3, 4, 5, 6, 7, 8, 9]   # B1–C
	var fat_soluble_indices   = [0, 10, 11, 12]                 # A, D, E, K2

	# ── Row 1: Water-soluble ──
	var ws_row = HBoxContainer.new()
	ws_row.alignment = BoxContainer.ALIGNMENT_CENTER
	ws_row.add_theme_constant_override("separation", 8)
	vbox.add_child(ws_row)

	for i in water_soluble_indices:
		var field = VITAMIN_FIELDS[i]
		var label = VITAMIN_LABELS[i]
		if not rdas.has(field): continue
		var rda   = rdas[field]["rda"]
		var val   = today_totals.get(field, 0.0)
		var pct   = clamp(val / rda, 0.0, 1.2) if rda > 0 else 0.0
		var state = "green" if pct >= 1.0 else ("yellow" if pct >= 0.5 else "red")

		var col = VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		ws_row.add_child(col)

		var img = TextureRect.new()
		img.custom_minimum_size = Vector2(120, 120)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var img_path = "res://images/vit_" + label.to_lower() + "_" + state + ".png"
		if ResourceLoader.exists(img_path):
			img.texture = load(img_path)
		else:
			var cr = ColorRect.new()
			cr.custom_minimum_size = Vector2(120, 120)
			cr.color = Color.GREEN if state == "green" else (Color.YELLOW if state == "yellow" else Color.RED)
			col.add_child(cr)
		col.add_child(img)

	var ws_label = Label.new()
	ws_label.text = "water soluble"
	ws_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ws_label.add_theme_font_size_override("font_size", 28)
	ws_label.add_theme_color_override("font_color", Color(0.5, 0.7, 1.0))
	vbox.add_child(ws_label)

	# ── Row 2: Fat-soluble ──
	var fs_row = HBoxContainer.new()
	fs_row.alignment = BoxContainer.ALIGNMENT_CENTER
	fs_row.add_theme_constant_override("separation", 8)
	vbox.add_child(fs_row)

	for i in fat_soluble_indices:
		var field = VITAMIN_FIELDS[i]
		var label = VITAMIN_LABELS[i]
		if not rdas.has(field): continue
		var rda   = rdas[field]["rda"]
		var val   = today_totals.get(field, 0.0)
		var pct   = clamp(val / rda, 0.0, 1.2) if rda > 0 else 0.0
		var state = "green" if pct >= 1.0 else ("yellow" if pct >= 0.5 else "red")

		var col = VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		fs_row.add_child(col)

		var img = TextureRect.new()
		img.custom_minimum_size = Vector2(120, 120)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var img_path = "res://images/vit_" + label.to_lower() + "_" + state + ".png"
		if ResourceLoader.exists(img_path):
			img.texture = load(img_path)
		else:
			var cr = ColorRect.new()
			cr.custom_minimum_size = Vector2(120, 120)
			cr.color = Color.GREEN if state == "green" else (Color.YELLOW if state == "yellow" else Color.RED)
			col.add_child(cr)
		col.add_child(img)

	var fs_label = Label.new()
	fs_label.text = "fat soluble"
	fs_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fs_label.add_theme_font_size_override("font_size", 28)
	fs_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.5))
	vbox.add_child(fs_label)

	card.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_open_micro_overlay()
	)
	#_fix_labels_in($Panel/ScrollContainer/VBoxContainer/MicroCard)

func _open_micro_overlay():
	_show_overlay_panel(func(scroll_vbox):
		var title = Label.new()
		title.text = "🔬 Micronutrients — Today"
		title.add_theme_font_size_override("font_size", 36)
		scroll_vbox.add_child(title)
		scroll_vbox.add_child(HSeparator.new())

		var rdas    = Global.get_micronutrient_rdas()
		var visible = Global.get_visible_micronutrients()

		# VITAMINS
		var vit_title = Label.new()
		vit_title.text = "Vitamins"
		vit_title.add_theme_font_size_override("font_size", 36)
		vit_title.add_theme_color_override("font_color", Color(0.6,0.9,0.4))
		scroll_vbox.add_child(vit_title)
		for field in VITAMIN_FIELDS:
			if rdas.has(field):
				scroll_vbox.add_child(_make_progress_row({
					"label": rdas[field]["label"],
					"key":   field,
					"unit":  rdas[field]["unit"],
					"goal":  rdas[field]["rda"],
					"min":   0
				}))

		scroll_vbox.add_child(HSeparator.new())

		# MINERALS
		var min_title = Label.new()
		min_title.text = "Minerals"
		min_title.add_theme_font_size_override("font_size", 36)
		min_title.add_theme_color_override("font_color", Color(0.4,0.8,0.9))
		scroll_vbox.add_child(min_title)
		var mineral_fields = ["magnesium_mg","potassium_mg","zinc_mg","iodine_mcg","selenium_mcg","calcium_mg","iron_mg","copper_mg"]
		for field in mineral_fields:
			if rdas.has(field):
				scroll_vbox.add_child(_make_progress_row({
					"label": rdas[field]["label"],
					"key":   field,
					"unit":  rdas[field]["unit"],
					"goal":  rdas[field]["rda"],
					"min":   0
				}))

		scroll_vbox.add_child(HSeparator.new())

		# ANTIOXIDANTS
		var aox_title = Label.new()
		aox_title.text = "Antioxidants"
		aox_title.add_theme_font_size_override("font_size", 36)
		aox_title.add_theme_color_override("font_color", Color(0.9,0.5,0.9))
		scroll_vbox.add_child(aox_title)
		var aox_fields = ["beta_carotene_mcg","lycopene_mcg","quercetin_mg","anthocyanins_mg","total_polyphenols_mg"]
		for field in aox_fields:
			if rdas.has(field):
				scroll_vbox.add_child(_make_progress_row({
					"label": rdas[field]["label"],
					"key":   field,
					"unit":  rdas[field]["unit"],
					"goal":  rdas[field]["rda"],
					"min":   0
				}))
	)

# ─────────────────────────────────────────
#  PANEL 5 — WATER CARD
# ─────────────────────────────────────────
func _refresh_water_card():
	var card = $Panel/ScrollContainer/VBoxContainer/WaterCard
	var vbox = card.get_node("VBoxContainer")
	for child in vbox.get_children():
		child.queue_free()

	# ── Calculate goals ──
	var water_goal_l  = Global.calculate_water_recommendation()
	var water_goal_ml = water_goal_l * 1000.0   # e.g. 3000.0 for 3L
	var glass_ml      = 250.0                    # one glass = exactly 250mL
	var total_glasses = int(ceil(water_goal_ml / glass_ml))  # e.g. 12 for 3L
	var water_l       = snappedf(water_ml / 1000.0, 0.01)
	var goal_l        = snappedf(water_goal_l, 0.1)

	# ── Title ──
	var title = Label.new()
	title.text = "💧 Water  " + str(water_l) + " / " + str(goal_l) + " L"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# ── How many glasses has the user drunk? ──
	# Each glass is exactly 250mL, water_ml is the running total
	var glasses_drunk = int(water_ml / glass_ml)
	# glasses_drunk = 4 means the user drank 1000mL (4 × 250mL = 1L)

	# ── Sync glass_states array to match glasses_drunk ──
	if glass_states.size() != total_glasses:
		glass_states.resize(total_glasses)
		for i in range(total_glasses):
			glass_states[i] = false  # false = full (not yet drunk)

	for i in range(total_glasses):
		glass_states[i] = (i < glasses_drunk)
	# glass_states[0..3] = true (drunk) after 4 glasses
	# glass_states[4..11] = false (still full) for a 12-glass goal

	# ── Load textures ──
	var full_tex  = load(GLASS_FULL_PATH)  if ResourceLoader.exists(GLASS_FULL_PATH)  else null
	var empty_tex = load(GLASS_EMPTY_PATH) if ResourceLoader.exists(GLASS_EMPTY_PATH) else null

	# ── Build glass buttons row ──
	var glasses_row = HFlowContainer.new()
	glasses_row.alignment = BoxContainer.ALIGNMENT_CENTER
	glasses_row.add_theme_constant_override("h_separation", 8)
	glasses_row.add_theme_constant_override("v_separation", 8)
	vbox.add_child(glasses_row)

	for i in range(total_glasses):
		var is_drunk = glass_states[i]  # true = user already drank this glass

		var glass_btn = Button.new()
		glass_btn.flat = true
		glass_btn.custom_minimum_size = Vector2(96, 96)

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(96, 96)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE  # let button handle input

		if is_drunk and empty_tex:
			icon.texture = empty_tex   # drunk glass = empty image
		elif not is_drunk and full_tex:
			icon.texture = full_tex    # not yet drunk = full image
		else:
			# Fallback colored rect
			var cr = ColorRect.new()
			cr.custom_minimum_size = Vector2(96, 96)
			cr.color = Color(0.3, 0.3, 0.9, 0.5) if not is_drunk else Color(0.6, 0.6, 0.9, 0.2)
			cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			glass_btn.add_child(cr)

		glass_btn.add_child(icon)

		# Pressing glass i sets water to (i+1) × 250mL
		# Pressing an already-drunk glass undoes it (sets water back to i × 250mL)
		var idx = i
		glass_btn.pressed.connect(func():
			if glass_states[idx]:
				# Already drunk — undo: set water back to this glass not being drunk
				water_ml = idx * glass_ml
			else:
				# Not yet drunk — drink up to and including this glass
				water_ml = (idx + 1) * glass_ml
			water_ml = clamp(water_ml, 0.0, water_goal_ml + glass_ml * 4)
			save_water()
			_refresh_water_card()
			var totals_q = today_totals.duplicate()
			totals_q["water_ml"] = water_ml
			Global.check_quests(totals_q)
		)

		glasses_row.add_child(glass_btn)

	# ── Bonus glass (beyond goal) ──
	var bonus_tex_path = "res://images/glass_bonus.png"
	var bonus_btn = Button.new()
	bonus_btn.flat = true
	bonus_btn.custom_minimum_size = Vector2(96, 96)
	bonus_btn.tooltip_text = "Log an extra glass beyond your goal (+250mL)"

	var bonus_icon = TextureRect.new()
	bonus_icon.custom_minimum_size = Vector2(96, 96)
	bonus_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	bonus_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ResourceLoader.exists(bonus_tex_path):
		bonus_icon.texture = load(bonus_tex_path)
	else:
		var cr2 = ColorRect.new()
		cr2.custom_minimum_size = Vector2(96, 96)
		cr2.color = Color(0.2, 0.6, 1.0, 0.5)
		cr2.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bonus_btn.add_child(cr2)
	bonus_btn.add_child(bonus_icon)

	bonus_btn.pressed.connect(func():
		water_ml += glass_ml
		save_water()
		_refresh_water_card()
		var totals_q = today_totals.duplicate()
		totals_q["water_ml"] = water_ml
		Global.check_quests(totals_q)
	)
	glasses_row.add_child(bonus_btn)

	# ── Points preview ──
	var lower_goal_ml = water_goal_ml * 0.85  # quest target = 85% of goal
	var w_pts = 0.0
	if water_ml >= water_goal_ml:
		w_pts = 2.0
	elif water_ml >= lower_goal_ml:
		w_pts = 2.0 * (water_ml / water_goal_ml)

	var pts_lbl = Label.new()
	pts_lbl.text = "💧 " + str(snappedf(w_pts, 1)) + " / 2 pts"
	pts_lbl.add_theme_font_size_override("font_size", 36)
	pts_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(pts_lbl)

	# ── Water intoxication warning ──
	var water_max_ml = water_goal_ml * 1.15
	if water_ml >= water_max_ml:
		var warn_vbox = VBoxContainer.new()
		warn_vbox.name = "WaterWarning"
		vbox.add_child(warn_vbox)

		var warn_lbl = Label.new()
		warn_lbl.text = "⚠️ You reached the daily recommended water intake."
		warn_lbl.add_theme_font_size_override("font_size", 36)
		warn_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		warn_lbl.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
		warn_vbox.add_child(warn_lbl)

		var wi_row = HBoxContainer.new()
		warn_vbox.add_child(wi_row)

		var prefix = Label.new()
		prefix.text = "Going further can cause "
		prefix.add_theme_font_size_override("font_size", 36)
		wi_row.add_child(prefix)


		var wi_btn = Button.new()
		wi_btn.text = "Water Intoxication"
		wi_btn.flat = true
		wi_btn.add_theme_font_size_override("font_size", 36)
		wi_btn.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		wi_btn.pressed.connect(_show_water_intoxication_info)
		wi_row.add_child(wi_btn)
		
		#Global.save_points(Time.get_date_string_from_system(), total_points)
		#_fix_labels_in($Panel/ScrollContainer/VBoxContainer/WaterCard)

func _show_water_intoxication_info():
	_show_overlay_panel(func(scroll_vbox):
		var title = Label.new()
		title.text = "💧 Water Intoxication (Hyponatremia)"
		title.add_theme_font_size_override("font_size", 36)
		title.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD
		scroll_vbox.add_child(title)
		scroll_vbox.add_child(HSeparator.new())

		var info_text = [
			"Excess water dilutes the sodium and potassium in your blood.",
			"",
			"🧠 Cerebral Edema — brain swelling, headaches, confusion, seizures",
			"❤️ Heart arrhythmias",
			"💪 Muscle cramping",
			"",
			"Your kidneys can only process approximately 1 litre of water per hour.",
			"Never exceed 1L per hour.",
		]
		for line in info_text:
			var lbl = Label.new()
			lbl.text = line
			lbl.add_theme_font_size_override("font_size", 36)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			if line.begins_with("🧠") or line.begins_with("❤️") or line.begins_with("💪"):
				lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			scroll_vbox.add_child(lbl)
	)

func _refresh_tips_card():
	var card = $Panel/ScrollContainer/VBoxContainer/TipsCard
	var vbox = card.get_node("VBoxContainer")
	for child in vbox.get_children():
		child.queue_free()

	var title = Label.new()
	title.text = "💡 Tips for You"
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	var tips = _get_personalized_tips()
	if tips.is_empty(): return
	# Show first 2 tips on card, rest in overlay
	var today_seed = Time.get_date_string_from_system().hash()
	var idx1 = today_seed % tips.size()
	var idx2 = (today_seed + 7) % tips.size()   # +7 offset to avoid same tip twice
	if idx2 == idx1: idx2 = (idx2 + 1) % tips.size()

	for idx in [idx1, idx2]:
		var lbl = Label.new()
		lbl.text = "• " + tips[idx]
		lbl.add_theme_font_size_override("font_size", 36)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(lbl)

	var more = Button.new()
	more.text = "See all tips →"
	more.flat = true
	more.pressed.connect(func(): _open_tips_overlay())
	vbox.add_child(more)
	
	#_fix_labels_in($Panel/ScrollContainer/VBoxContainer/TipsCard)

func _open_tips_overlay():
	var tips = _get_personalized_tips()
	_show_overlay_panel(func(scroll_vbox):
		var title = Label.new()
		title.text = "💡 Personalized Tips"
		title.add_theme_font_size_override("font_size", 36)
		scroll_vbox.add_child(title)
		scroll_vbox.add_child(HSeparator.new())
		for tip in tips:
			var lbl = Label.new()
			lbl.text = "• " + tip
			lbl.add_theme_font_size_override("font_size", 36)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			scroll_vbox.add_child(lbl)
	)

func _get_personalized_tips() -> Array:
	var tips: Array = []
	var c         = Global.active_metabolic_conditions
	var bm        = Global.body_metrics
	var goal_w    = bm.get("goal_weight", 0.0)
	var weight    = bm.get("weight", 0.0)
	var is_female = bm.get("is_female", false)
	var trying_to_lose   = goal_w > 0 and goal_w < weight
	var trying_to_gain   = goal_w > 0 and goal_w > weight
	var trying_to_maintain = goal_w > 0 and abs(goal_w - weight) < 1.0

	# ── Weight loss tips ──
	if trying_to_lose:
		tips.append("Prioritise resistant starch and slow-digesting starch — they keep you full longer and reduce fat absorption.")
		tips.append("Eat soluble fiber (oats, legumes, chicory) with fatty meals — it binds dietary fat and slows absorption.")
		tips.append("Insoluble fiber is great for decreasing absorption time in the intestines — include it daily.")
		tips.append("Fasting triggers fat burning and gives your pancreas a break — consider a 12h overnight fast.")
		tips.append("Eat a lot of protein — it has the highest thermic effect and preserves muscle during weight loss.")
		tips.append("Eating protein and fat before carbohydrates in the same meal reduces your glucose spike significantly.")
		tips.append("Slow-digesting starch before bed can suppress growth hormone — avoid it if fat loss is your goal.")

	# ── Weight gain tips ──
	if trying_to_gain:
		tips.append("Prioritise rapidly digestible starch for post-workout meals — it refills glycogen fast.")
		tips.append("Avoid eating large amounts of soluble fiber in the same meal as healthy fats — it limits caloric absorption.")
		tips.append("If you eat soluble fiber, do it at least 5 hours away from a fatty meal.")
		tips.append("Insoluble fiber in the same meal as fats is fine — it doesn't limit fat absorption significantly.")
		tips.append("It's more effective to eat smaller meals often than one big meal — 5-6 small meals maximise nutrient uptake.")
		tips.append("Eating before bed is acceptable for gaining weight — prioritise slow-digesting starch and protein.")
		tips.append("Liquid calories (shakes, smoothies) are efficient for caloric surplus without feeling overfull.")

	# ── Maintenance tips ──
	if trying_to_maintain:
		tips.append("Vary your fiber sources — mix soluble (oats, legumes) and insoluble (vegetables, wholegrains) daily.")
		tips.append("Resistant starch feeds beneficial gut bacteria — include cooked and cooled potatoes, green bananas, legumes.")
		tips.append("Consistent meal timing helps regulate hunger hormones — aim for meals at similar times each day.")

	# ── Condition-specific tips ──
	if c.has("glycemic-health"):
		tips.append("Choose low-GI foods — barley (GI 28), legumes (GI 28-35), and pasta (GI 45) over white rice (GI 73).")
		tips.append("Vinegar or lemon juice with a meal can reduce the glycemic response by up to 20%.")
		tips.append("Walking for 10 minutes after meals significantly reduces post-meal blood glucose.")
		tips.append("Soluble fiber slows glucose absorption — eat oats or legumes at every meal if possible.")

	if c.has("nafld"):
		tips.append("Avoid all fructose-sweetened beverages — even one per day significantly accelerates NAFLD progression.")
		tips.append("Vitamin E-rich foods (almonds, avocado, sunflower seeds) have Grade A evidence for NAFLD support.")
		tips.append("Coffee (2-3 cups/day unsweetened) is associated with slower liver fibrosis progression.")
		tips.append("The Mediterranean diet has the strongest evidence base for reversing NAFLD — prioritise olive oil, fish, vegetables.")

	if c.has("osteoporosis"):
		tips.append("Take calcium and Vitamin D together — Vitamin D is essential for calcium absorption.")
		tips.append("Vitamin K2 (MK-7 form, in fermented foods) directs calcium into bones rather than arteries.")
		tips.append("Excess sodium increases urinary calcium loss — keep sodium under 2000mg/day.")
		tips.append("Weight-bearing exercise is as important as nutrition for bone density.")

	if c.has("thyroid-health"):
		tips.append("Selenium (Brazil nuts, seafood) is essential for T4→T3 conversion — aim for 100-200 mcg daily.")
		tips.append("Cooking cruciferous vegetables deactivates goitrogenic compounds — raw amounts are fine in moderation.")
		tips.append("Iodine requirements are strict — avoid seaweed supplements but maintain dietary iodine from dairy and fish.")
		tips.append("Take levothyroxine 30-60 minutes before breakfast, separate from calcium and iron by 4 hours.")

	if c.has("crohns-disease"):
		tips.append("During flares, choose easily digestible foods — white rice, cooked carrots, skinless chicken, banana.")
		tips.append("Omega-3 fatty acids (salmon, mackerel) have anti-inflammatory properties relevant to Crohn's.")
		tips.append("Small, frequent meals reduce bowel stress — aim for 5-6 small meals instead of 3 large ones.")
		tips.append("Turmeric (curcumin) has some evidence for reducing Crohn's inflammation — add to cooked foods.")

	if c.has("lipid-health"):
		tips.append("Beta-glucan in oats (3g/day) can reduce LDL cholesterol by 5-10% — eat oatmeal daily.")
		tips.append("Viscous soluble fiber (psyllium, legumes) binds bile acids and forces the liver to use cholesterol.")
		tips.append("Plant sterols (2g/day) block cholesterol absorption — found in fortified foods or supplements.")
		tips.append("Lycopene-rich foods (tomatoes, watermelon) are associated with lower LDL oxidation.")

	if Global.kidney_at_risk:
		tips.append("Calcium consumed WITH oxalate-rich meals binds oxalate in the gut — preventing kidney stone formation.")
		tips.append("Stay well hydrated — dilute urine protects the kidneys. Your goal today is " + str(snappedf(Global.daily_water_liters,1)) + "L.")
		tips.append("Cooking oxalate-rich vegetables and discarding the water reduces oxalate content by up to 50%.")

	if c.has("hemochromatosis"):
		tips.append("Drink tea or coffee with iron-rich meals — tannins reduce iron absorption by 40-60%.")
		tips.append("Dairy or calcium supplements with meals compete with iron absorption — use this to your advantage.")
		tips.append("Avoid vitamin C supplements — even 250mg significantly enhances iron absorption.")

	if c.has("epi"):
		tips.append("Always take PERT (enzyme replacement) at the start of every meal and snack — timing is critical.")
		tips.append("Do not restrict fat when using PERT adequately — fat provides essential calories and fat-soluble vitamins.")
		tips.append("Fat-soluble vitamins A, D, E, K require adequate PERT to be absorbed — monitor your levels regularly.")

	if c.has("graves-disease"):
		tips.append("Strictly avoid all seaweed and iodine supplements — iodine can trigger thyroid storm in active Graves'.")
		tips.append("Selenium 200 mcg/day has Grade A evidence (ETA) for reducing Graves' orbitopathy severity.")
		tips.append("Caffeine amplifies hyperthyroid symptoms — limit to 1 cup of coffee per day during active phase.")

	# Universal tips always included
	if tips.size() < 5:
		tips.append_array([
			"Eating a diverse diet with 30+ different plant foods per week optimises gut microbiome diversity.",
			"Chewing food thoroughly (20-30 chews per bite) improves digestion and reduces portion size naturally.",
			"Hydration status significantly affects appetite regulation — drink a glass of water before each meal.",
		])

	return tips
# ─────────────────────────────────────────
#  SHARED OVERLAY HELPER
# ─────────────────────────────────────────
func _show_overlay_panel(populate_fn: Callable):
	var existing = get_node_or_null("OverlayBackdrop")
	if existing: existing.queue_free()

	var canvas = CanvasLayer.new()
	canvas.name = "OverlayBackdrop"
	add_child(canvas)

	var backdrop = ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	canvas.add_child(backdrop)

	var _close = func():
		if is_instance_valid(canvas):
			canvas.queue_free()

	# Only close on a real left mouse click (not scroll wheel, not touch momentum)
	backdrop.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_LEFT:
			_close.call()
		elif event is InputEventScreenTouch and event.pressed:
			_close.call()
	)
	var viewport    = get_viewport_rect().size
	var panel_width = viewport.x - 40.0
	# Panel anchored on all four sides so it never grows beyond the viewport
	var panel = PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP  # blocks clicks — no gui_input needed
	panel.set_anchor_and_offset(SIDE_LEFT,  0, viewport.x / 2.0 - panel_width / 2.0)
	panel.set_anchor_and_offset(SIDE_RIGHT, 0, viewport.x / 2.0 + panel_width / 2.0)
	panel.set_anchor_and_offset(SIDE_TOP,    0,  80)
  # ← cap the bottom
	backdrop.add_child(panel)

	# DO NOT connect panel.gui_input — MOUSE_FILTER_STOP already swallows events

	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
# ← fill the panel height
	panel.add_child(scroll)

	var scroll_vbox = VBoxContainer.new()
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(scroll_vbox)

	populate_fn.call(scroll_vbox)

	var close_hint = Label.new()
	close_hint.text = "Tap outside to close"  # updated hint wording
	close_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close_hint.add_theme_font_size_override("font_size", 36)
	close_hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	scroll_vbox.add_child(close_hint)

	# ── Clamp panel height after layout ──
	scroll_vbox.queue_sort()
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(canvas):
		var viewport_h  = get_viewport_rect().size.y
		var max_h       = viewport_h * 0.67 # 80px top + 80px bottom breathing room
		var content_h   = scroll_vbox.size.y + 20.0
		var clamped_h   = min(content_h, max_h)
		scroll.custom_minimum_size = Vector2(0, clamped_h)


# ─────────────────────────────────────────
#  SAVE / LOAD
# ─────────────────────────────────────────
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
	if data.get("date","") != Time.get_date_string_from_system():
		var old_date = data.get("date", "")
		if old_date != "":
			# Load meal history from disk
			var history: Dictionary = {}
			if FileAccess.file_exists("user://meal_history.json"):
				var hfile = FileAccess.open("user://meal_history.json", FileAccess.READ)
				var hdata = JSON.parse_string(hfile.get_as_text())
				hfile.close()
				if hdata: history = hdata

			# Only write if there's actually something to save
			var old_foods = data.get("foods", [])
			var old_totals = data.get("totals", {})
			if not old_foods.is_empty() or old_totals.get("calories", 0.0) > 0:
				history[old_date] = {
					"totals": old_totals,
					"foods":  old_foods
				}
				var wfile = FileAccess.open("user://meal_history.json", FileAccess.WRITE)
				wfile.store_string(JSON.stringify(history))
				wfile.close()
		return
	var saved = data.get("totals",{})
	for key in today_totals.keys():
		if saved.has(key): today_totals[key] = saved[key]
	foods_eaten = data.get("foods",[])

func save_water():
	var file = FileAccess.open("user://water.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"date": Time.get_date_string_from_system(),
		"water_ml": water_ml,
		"glass_states": glass_states
	}))
	file.close()

func load_water():
	if not FileAccess.file_exists("user://water.json"): return
	var file = FileAccess.open("user://water.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	if data.get("date","") != Time.get_date_string_from_system(): return
	water_ml     = data.get("water_ml", 0.0)
	glass_states = data.get("glass_states",[])

func _save_to_history():
	if foods_eaten.is_empty() and today_totals.get("calories", 0.0) <= 0:
		return   # ← nothing logged today, don't overwrite yesterday's real data

	# Load from disk first to merge, but preserve today's live data
	var today = Time.get_date_string_from_system()
	if not FileAccess.file_exists("user://meal_history.json"):
		meal_history = {}
	else:
		var file = FileAccess.open("user://meal_history.json", FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data: meal_history = data

	# Always write today from live memory, not from disk
	meal_history[today] = {
		"totals": today_totals.duplicate(),
		"foods":  foods_eaten.duplicate()
	}

	var file = FileAccess.open("user://meal_history.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(meal_history))
	file.close()

func load_meal_history():
	if not FileAccess.file_exists("user://meal_history.json"): return
	var file = FileAccess.open("user://meal_history.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data: meal_history = data
	# Merge today's live data so history is always current
	var today = Time.get_date_string_from_system()
	meal_history[today] = {
		"totals": today_totals.duplicate(),
		"foods":  foods_eaten.duplicate()
	}

func _goal_bar(value: float, goal: float) -> String:
	if goal <= 0: return ""
	var pct  = clamp(value / goal, 0.0, 1.0)
	var fill = int(pct * 10)
	return "█".repeat(fill) + "░".repeat(10 - fill)

func _on_badge_earned(badge: Dictionary):
	_show_badge_popup(badge)

func _show_badge_popup(badge: Dictionary):
	var existing = get_node_or_null("BadgePopup")
	if existing: existing.queue_free()

	var panel = PanelContainer.new()
	panel.name = "BadgePopup"
	panel.z_index = 60
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(320, 220)
	panel.modulate.a = 0.0

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var sparkle = Label.new()
	sparkle.text = "✨ Badge Unlocked! ✨"
	sparkle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sparkle.add_theme_font_size_override("font_size", 48)
	vbox.add_child(sparkle)

	var name_lbl = Label.new()
	name_lbl.text = badge["name"]
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 36)
	name_lbl.add_theme_color_override("font_color",
		Global.BADGE_TIER_COLORS.get(badge.get("tier","bronze"), Color.WHITE))
	vbox.add_child(name_lbl)

	var desc_lbl = Label.new()
	desc_lbl.text = badge["desc"]
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.add_theme_font_size_override("font_size", 36)
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(desc_lbl)

	var tier_lbl = Label.new()
	tier_lbl.text = badge.get("tier","bronze").capitalize() + " Badge"
	tier_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tier_lbl.add_theme_font_size_override("font_size", 36)
	tier_lbl.add_theme_color_override("font_color",
		Global.BADGE_TIER_COLORS.get(badge.get("tier","bronze"), Color.WHITE))
	vbox.add_child(tier_lbl)

	add_child(panel)

	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.4)
	tween.tween_property(panel, "scale",      Vector2(1.1,1.1), 0.2)
	tween.tween_property(panel, "scale",      Vector2(1.0,1.0), 0.1)
	tween.tween_interval(2.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): panel.queue_free())

func _show_weekly_report():
	_show_overlay_panel(func(scroll_vbox):
		# Header
		var now    = Time.get_datetime_dict_from_system()
		var week_n = int(Time.get_unix_time_from_system() / 604800)

		var title = Label.new()
		title.text = "📊 Weekly Health Report — Week " + str(week_n % 52)
		title.add_theme_font_size_override("font_size", 36)
		title.autowrap_mode = TextServer.AUTOWRAP_WORD
		scroll_vbox.add_child(title)
		scroll_vbox.add_child(HSeparator.new())

		# Streak + League
		var league = Global.get_current_league()
		_add_report_row(scroll_vbox, "🔥 Streak",   str(Global.daily_streak) + " days")
		_add_report_row(scroll_vbox, "🧊 Freezes",  str(Global.streak_freeze_count) + " remaining")
		_add_report_row(scroll_vbox, "🏆 League",   league["name"])
		_add_report_row(scroll_vbox, "⭐ Pts earned this week", str(snappedf(Global.get_points_week(),0)))
		_add_report_row(scroll_vbox, "💰 PY balance", str(Global.py_currency) + " PY")
		scroll_vbox.add_child(HSeparator.new())

		# Nutrition averages this week
		var week_avg = _get_week_averages()
		var rdas     = Global.get_micronutrient_rdas()
		var macro_goals = Global.get_macro_goals()

		var nutr_title = Label.new()
		nutr_title.text = "📈 Nutrition averages (daily)"
		nutr_title.add_theme_font_size_override("font_size", 36)
		nutr_title.add_theme_color_override("font_color", Color(0.7,0.9,0.4))
		scroll_vbox.add_child(nutr_title)

		var daily_goal = Global.body_metrics.get("daily_goal", 2000.0)
		_add_report_progress(scroll_vbox, "Calories",
			week_avg.get("calories",0), daily_goal, "kcal")
		_add_report_progress(scroll_vbox, "Protein",
			week_avg.get("protein_g",0), macro_goals.get("protein_g",50), "g")
		_add_report_progress(scroll_vbox, "Fiber",
			week_avg.get("fiber_g",0), macro_goals.get("fiber_g",25), "g")
		_add_report_progress(scroll_vbox, "Water",
			week_avg.get("water_ml",0)/1000.0, Global.daily_water_liters, "L")

		scroll_vbox.add_child(HSeparator.new())

		# Top nutrients met + missed
		var nutr2_title = Label.new()
		nutr2_title.text = "🔬 Micronutrients"
		nutr2_title.add_theme_font_size_override("font_size", 36)
		nutr2_title.add_theme_color_override("font_color", Color(0.4,0.8,0.9))
		scroll_vbox.add_child(nutr2_title)

		var met: Array = []
		var missed: Array = []
		for field in rdas.keys():
			var rda = rdas[field]["rda"]
			var avg = week_avg.get(field, 0.0)
			if rda <= 0: continue
			if avg >= rda:
				met.append(rdas[field]["label"])
			else:
				missed.append(rdas[field]["label"] + " (" + str(int(avg/rda*100)) + "%)")

		var met_lbl = Label.new()
		met_lbl.text = "✅ Goals met: " + (", ".join(met) if not met.is_empty() else "None")
		met_lbl.add_theme_font_size_override("font_size", 36)
		met_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		met_lbl.add_theme_color_override("font_color", Color(0.3,0.9,0.3))
		scroll_vbox.add_child(met_lbl)

		var miss_lbl = Label.new()
		miss_lbl.text = "❌ Needs work: " + (", ".join(missed.slice(0,6)) if not missed.is_empty() else "None!")
		miss_lbl.add_theme_font_size_override("font_size", 36)
		miss_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		miss_lbl.add_theme_color_override("font_color", Color(1.0,0.5,0.3))
		scroll_vbox.add_child(miss_lbl)

		scroll_vbox.add_child(HSeparator.new())

		# Badges earned this week
		var badge_title = Label.new()
		badge_title.text = "🏅 Badges"
		badge_title.add_theme_font_size_override("font_size", 36)
		scroll_vbox.add_child(badge_title)

		var badge_lbl = Label.new()
		badge_lbl.text = str(Global.earned_badges.size()) + " total badges earned"
		badge_lbl.add_theme_font_size_override("font_size", 36)
		scroll_vbox.add_child(badge_lbl)

		scroll_vbox.add_child(HSeparator.new())

		# Seasonal bonus
		var season = Global.get_current_season()
		var seas_title = Label.new()
		seas_title.text = season["emoji"] + " Season: " + season["name"]
		seas_title.add_theme_font_size_override("font_size", 36)
		seas_title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		scroll_vbox.add_child(seas_title)

		var seas_desc = Label.new()
		seas_desc.text = season["desc"]
		seas_desc.add_theme_font_size_override("font_size", 36)
		seas_desc.autowrap_mode = TextServer.AUTOWRAP_WORD
		scroll_vbox.add_child(seas_desc)
	)

func _add_report_row(vbox: VBoxContainer, label: String, value: String):
	var row = HBoxContainer.new()
	vbox.add_child(row)
	var k = Label.new(); k.text = label
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", 36)
	row.add_child(k)
	var v = Label.new(); v.text = value
	v.add_theme_font_size_override("font_size", 36)
	row.add_child(v)

func _add_report_progress(vbox: VBoxContainer, label: String, val: float, goal: float, unit: String):
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	vbox.add_child(col)

	var row = HBoxContainer.new()
	col.add_child(row)

	var k = Label.new(); k.text = label
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	k.add_theme_font_size_override("font_size", 36)
	row.add_child(k)

	var pct = clamp(val/goal, 0.0, 1.0) if goal > 0 else 0.0
	var v   = Label.new()
	v.text = str(snappedf(val,0.1)) + " / " + str(snappedf(goal,0.1)) + " " + unit
	v.add_theme_font_size_override("font_size", 36)
	if pct >= 1.0:
		v.add_theme_color_override("font_color", Color(0.3,0.9,0.3))
	elif pct >= 0.6:
		v.add_theme_color_override("font_color", Color(1.0,0.85,0.0))
	else:
		v.add_theme_color_override("font_color", Color(1.0,0.4,0.3))
	row.add_child(v)

	var bar = Label.new()
	var filled = int(pct * 10)
	bar.text = "█".repeat(filled) + "░".repeat(10 - filled)
	bar.add_theme_font_size_override("font_size", 36)
	col.add_child(bar)

func _get_week_averages() -> Dictionary:
	var totals: Dictionary = {}
	var days_found = 0
	var unix_now   = Time.get_unix_time_from_system()

	for i in range(7):
		var unix_day = unix_now - (i * 86400)
		var dt       = Time.get_datetime_dict_from_unix_time(unix_day)
		var date_str = "%04d-%02d-%02d" % [dt.year, dt.month, dt.day]

		var day_data: Dictionary = {}
		if date_str == Time.get_date_string_from_system():
			day_data = today_totals
		elif meal_history.has(date_str):
			day_data = meal_history[date_str].get("totals", {})
		else:
			continue

		days_found += 1
		for key in day_data.keys():
			if not totals.has(key): totals[key] = 0.0
			totals[key] += day_data[key]

	if days_found == 0: return {}
	for key in totals.keys():
		totals[key] = totals[key] / days_found
	return totals

func _on_streak_milestone(days: int):
	var milestone_names = {
		3: "Spark 🔥", 7: "Flame 🔥🔥", 14: "Blaze 🌋",
		30: "Inferno 🌋", 60: "Solar ☀️", 100: "Legendary 🏆",
		200: "Mythic 💫", 365: "Eternal ✨"
	}
	var name = milestone_names.get(days, str(days) + " days")
	_show_milestone_popup(name, days)

func _show_milestone_popup(name: String, days: int):
	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(320, 200)
	panel.modulate.a = 0.0

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "🎉 Streak Milestone!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title)

	var streak_lbl = Label.new()
	streak_lbl.text = str(days) + " Days — " + name
	streak_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	streak_lbl.add_theme_font_size_override("font_size", 36)
	streak_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	vbox.add_child(streak_lbl)

	var reward_lbl = Label.new()
	reward_lbl.text = "+ " + str(days * 5) + " PY 💰"
	reward_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reward_lbl.add_theme_font_size_override("font_size", 36)
	reward_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	vbox.add_child(reward_lbl)

	add_child(panel)
	Global.py_currency += days * 5
	Global.save_currency()

	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.4)
	tween.tween_interval(2.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): panel.queue_free())

#func _fix_labels_in(node: Node):
	#for child in node.get_children():
		#if child is Label:
			#child.autowrap_mode = TextServer.AUTOWRAP_WORD
			#child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		#elif child is RichTextLabel:
			#child.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			#child.fit_content = true
		#_fix_labels_in(child)

func _check_weekly_reflection():
	var dt      = Time.get_datetime_dict_from_system()
	var weekday = dt.get("weekday", 0)   # 0=Sun
	var today   = Time.get_date_string_from_system()

	if weekday != 0: return   # Only Sunday
	if Global.last_report_date == today: return

	call_deferred("_show_reflection_screen")

func _show_reflection_screen():
	# This function has NO weekday check — it works any day
	# The Monday auto-trigger is handled by _check_weekly_reflection()
	var week_avg = _get_week_averages()
	# If no data at all, show a placeholder
	if week_avg.is_empty():
		_show_overlay_panel(func(scroll_vbox):
			var lbl = Label.new()
			lbl.text = "📊 No meal history yet this week.\nStart logging meals to see your weekly insights!"
			lbl.add_theme_font_size_override("font_size", 24)
			lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			scroll_vbox.add_child(lbl)
		)
		return

	Global.mark_report_shown()
	_save_weekly_report(week_avg)
	
func _save_weekly_report(week_avg: Dictionary):
	var reports: Array = []
	if FileAccess.file_exists("user://weekly_reports.json"):
		var file = FileAccess.open("user://weekly_reports.json", FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data and data is Array: reports = data

	var today   = Time.get_date_string_from_system()
	var summary = {
		"week_label":    "Week of " + today,
		"avg_kcal":      snappedf(week_avg.get("calories",0), 0.1),
		"avg_protein":   snappedf(week_avg.get("protein_g",0), 0.1),
		"avg_fiber":     snappedf(week_avg.get("fiber_g",0), 0.1),
		"streak":        Global.daily_streak,
		"pts_week":      snappedf(Global.get_points_week(), 0.1),
		"py_currency":   Global.py_currency,
		"achievement":   _get_week_achievement(),
		"pattern":       _detect_pattern(week_avg),
		"suggestion":    _get_next_week_suggestion(),
	}

	# Don't add duplicate for same week
	var already = reports.any(func(r): return r.get("week_label","") == summary["week_label"])
	if not already:
		reports.append(summary)
		# Keep last 52 weeks
		if reports.size() > 52:
			reports = reports.slice(reports.size() - 52)
		var file = FileAccess.open("user://weekly_reports.json", FileAccess.WRITE)
		file.store_string(JSON.stringify(reports))
		file.close()

	_show_overlay_panel(func(scroll_vbox):
		var title = Label.new()
		title.text = "🌅 Sunday Reflection"
		title.add_theme_font_size_override("font_size", 50)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		scroll_vbox.add_child(title)
		scroll_vbox.add_child(HSeparator.new())

		# Pattern noticed
		var pattern = _detect_pattern(week_avg)
		if not pattern.is_empty():
			var pattern_panel = PanelContainer.new()
			var pv = VBoxContainer.new()
			pattern_panel.add_child(pv)
			scroll_vbox.add_child(pattern_panel)
			var p_title = Label.new()
			p_title.text = "🔍 Pattern noticed:"
			p_title.add_theme_font_size_override("font_size", 36)
			p_title.add_theme_color_override("font_color", Color(0.7,0.7,1.0))
			pv.add_child(p_title)
			var p_lbl = Label.new()
			p_lbl.text = pattern
			p_lbl.add_theme_font_size_override("font_size", 36)
			p_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			pv.add_child(p_lbl)

		scroll_vbox.add_child(HSeparator.new())

		# Achievement to celebrate
		var achievement = _get_week_achievement()
		var ach_panel = PanelContainer.new()
		var av = VBoxContainer.new()
		ach_panel.add_child(av)
		scroll_vbox.add_child(ach_panel)
		var a_title = Label.new()
		a_title.text = "🎉 This week's win:"
		a_title.add_theme_font_size_override("font_size", 36)
		a_title.add_theme_color_override("font_color", Color(0.3,1.0,0.3))
		av.add_child(a_title)
		var a_lbl = Label.new()
		a_lbl.text = achievement
		a_lbl.add_theme_font_size_override("font_size", 36)
		a_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		av.add_child(a_lbl)

		scroll_vbox.add_child(HSeparator.new())

		# Next week suggestion — framed as avatar journey
		var suggestion = _get_next_week_suggestion()
		var sug_panel = PanelContainer.new()
		var sv = VBoxContainer.new()
		sug_panel.add_child(sv)
		scroll_vbox.add_child(sug_panel)
		var s_title = Label.new()
		s_title.text = "🗺️ Next week's adventure:"
		s_title.add_theme_font_size_override("font_size", 36)
		s_title.add_theme_color_override("font_color", Color(1.0,0.85,0.2))
		sv.add_child(s_title)
		var s_lbl = Label.new()
		s_lbl.text = suggestion
		s_lbl.add_theme_font_size_override("font_size", 36)
		s_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		sv.add_child(s_lbl)
	)

func _detect_pattern(week_avg: Dictionary) -> String:
	var sodium   = week_avg.get("sodium_mg", 0.0)
	var sugar    = week_avg.get("sugar_g", 0.0)
	var protein  = week_avg.get("protein_g", 0.0)
	var macro_goals = Global.get_macro_goals()

	if sodium > 2500:
		return "Your sodium intake has been above the recommended limit this week. " + \
			"Try reducing processed foods and adding fresh herbs instead of salt."
	if sugar > 40:
		return "Your sugar intake was elevated this week. " + \
			"Swapping sugary snacks for fruit or nuts may help you feel more energetic."
	if protein < macro_goals.get("protein_g",50.0) * 0.7:
		return "Protein was below your goal most days this week. " + \
			"Adding eggs, legumes or fish to each meal could help."
	return "You showed consistent nutritional variety this week — keep exploring new foods!"

func _get_week_achievement() -> String:
	var rdas        = Global.get_micronutrient_rdas()
	var week_avg    = _get_week_averages()
	var met_rdas    = 0
	for field in rdas.keys():
		if week_avg.get(field,0.0) >= rdas[field]["rda"]:
			met_rdas += 1
	if Global.daily_streak >= 7:
		return "🔥 You maintained a " + str(Global.daily_streak) + "-day streak — outstanding consistency!"
	if met_rdas >= 10:
		return "💊 You hit " + str(met_rdas) + " micronutrient goals on average — excellent nutrition!"
	return "📝 You logged food every day you could — building a healthy habit!"

func _get_next_week_suggestion() -> String:
	var c = Global.active_metabolic_conditions
	if c.has("osteoporosis"):
		return "Your avatar is heading toward the mountain region — " + \
			"where mountain folk are known for their bone strength. " + \
			"Try adding more dairy, leafy greens or salmon this week for calcium and Vitamin D."
	if c.has("glycemic-health"):
		return "Your avatar discovers a Mediterranean coastal village " + \
			"where locals eat low-GI foods and walk after meals. " + \
			"Try barley, legumes or whole rye bread this week."
	return "Your avatar reaches a new region famous for vibrant markets and colorful produce. " + \
		"Challenge yourself to eat from 5 different food categories every day this week."
