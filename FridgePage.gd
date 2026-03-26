extends Control

var all_foods: Array = []
var fridge_foods: Array = []        # list of unique food dicts
var fridge_quantities: Dictionary = {} # food_id → count
var fridge_weights: Dictionary = {}   # food_id → {total_g, remaining_g}
var shopping_list: Array = []
var shopping_quantities: Dictionary = {} # food_id → count
var _long_press_active: bool = false

func _ready():
	load_foods()
	load_fridge()
	$Panel/VBoxContainer/TopBar/ListButton.pressed.connect(_on_list_pressed)
	$Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/TopBar2/CloseButton.pressed.connect(_on_close_list)
	$Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/TopBar2/SearchBar.text_changed.connect(func(_t): refresh_current_tab())
	$Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/TabContainer.tab_changed.connect(func(_i): refresh_current_tab())
	$Panel/VBoxContainer/ShoppingListPanel.hide()

# ── Load foods.json ──
func load_foods():
	var file = FileAccess.open("res://data/foods.json", FileAccess.READ)
	if file == null:
		print("ERROR: foods.json not found")
		return
	all_foods = JSON.parse_string(file.get_as_text())
	file.close()
	build_tabs()

# ── Build one tab per category ──
func build_tabs():
	var tabs = $Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/TabContainer
	for child in tabs.get_children():
		child.queue_free()

	var categories = []
	for food in all_foods:
		var cat = food.get("category", "other")
		if not categories.has(cat):
			categories.append(cat)

	for cat in categories:
		var scroll = ScrollContainer.new()
		scroll.name = cat.capitalize()
		var vbox = VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(vbox)
		tabs.add_child(scroll)

	refresh_current_tab()

# ── Rebuild food list for active tab + search ──
func refresh_current_tab():
	var tabs = $Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/TabContainer
	var scroll = tabs.get_current_tab_control()
	if not scroll: return
	var vbox = scroll.get_child(0)
	if not vbox: return

	for child in vbox.get_children():
		child.queue_free()

	var cat    = tabs.get_tab_title(tabs.current_tab).to_lower()
	var search = $Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/TopBar2/SearchBar.text.to_lower()

	var filtered = all_foods.filter(func(f):
		var right_cat = f.get("category", "") == cat
		var matches   = search.is_empty() or f.get("name", "").to_lower().contains(search)
		return right_cat and matches
	)

	for food in filtered:
		vbox.add_child(make_browse_row(food))

# ── One row in the browse list ──
func make_browse_row(food: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 60)

	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(50, 50)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var path = "res://images/" + food.get("id", "") + ".png"
	if ResourceLoader.exists(path):
		icon.texture = load(path)
	row.add_child(icon)

	var name_label = Label.new()
	name_label.text = food.get("name", "")
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var amount = Label.new()
	amount.text = str(food.get("oxalate_mg_per_100g", 0)) + "mg"
	row.add_child(amount)

	var warnings = Global.get_warnings(food)
	if warnings.size() > 0:
		var badge = Label.new()
		badge.text = "⛔" if warnings[0]["severity"] == "avoid" else "⚠️"
		badge.tooltip_text = warnings[0]["message"]
		row.add_child(badge)

	var btn = Button.new()
	btn.text = "+ List"
	btn.pressed.connect(func(): add_to_shopping_list(food))
	row.add_child(btn)

	return row

# ── Add food to shopping list ──
func add_to_shopping_list(food: Dictionary):
	var fid = food.get("id", "")
	if not shopping_list.any(func(f): return f["id"] == fid):
		shopping_list.append(food)
		shopping_quantities[fid] = 1
	else:
		shopping_quantities[fid] = shopping_quantities.get(fid, 1) + 1
	refresh_shopping_list()

# ── Remove one from shopping list ──
func remove_from_shopping_list(food: Dictionary):
	var fid = food.get("id", "")
	if not shopping_quantities.has(fid): return
	shopping_quantities[fid] -= 1
	if shopping_quantities[fid] <= 0:
		shopping_quantities.erase(fid)
		shopping_list = shopping_list.filter(func(f): return f["id"] != fid)
	refresh_shopping_list()

# ── Rebuild the shopping list ──
func refresh_shopping_list():
	var container = $Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/ShoppingListContainer
	for child in container.get_children():
		child.queue_free()

	for food in shopping_list:
		var fid = food.get("id", "")
		var qty = shopping_quantities.get(fid, 1)

		var row = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 60)

		# Minus button
		var minus_btn = Button.new()
		minus_btn.text = "−"
		minus_btn.custom_minimum_size = Vector2(50, 50)
		minus_btn.pressed.connect(func(): remove_from_shopping_list(food))
		row.add_child(minus_btn)

		# Checkbox with quantity
		var cb = CheckBox.new()
		cb.text = food.get("name", "") + (" ×" + str(qty) if qty > 1 else "")
		cb.add_theme_font_size_override("font_size", 28)
		cb.custom_minimum_size = Vector2(260, 50)
		cb.toggled.connect(func(checked):
			if checked:
				add_to_fridge(food, qty)
		)
		row.add_child(cb)

		# Warning badge
		var warnings = Global.get_warnings(food)
		if warnings.size() > 0:
			var badge = Label.new()
			badge.text = "⛔" if warnings[0]["severity"] == "avoid" else "⚠️"
			badge.tooltip_text = warnings[0]["message"]
			row.add_child(badge)

		# Plus button
		var plus_btn = Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(50, 50)
		plus_btn.z_index = 100
		plus_btn.pressed.connect(func(): add_to_shopping_list(food))
		row.add_child(plus_btn)

		container.add_child(row)

# ── Add food to fridge (with quantity) ──
func add_to_fridge(food: Dictionary, qty: int = 1):
	var fid = food.get("id", "")
	if not fridge_foods.any(func(f): return f["id"] == fid):
		fridge_foods.append(food)
		fridge_quantities[fid] = qty
		fridge_weights[fid] = {"total_g": 100.0 * qty, "remaining_g": 100.0 * qty}
	else:
		fridge_quantities[fid] = fridge_quantities.get(fid, 0) + qty
		var w = fridge_weights.get(fid, {"total_g":100.0,"remaining_g":100.0})
		w["total_g"]     += 100.0 * qty
		w["remaining_g"] += 100.0 * qty
		fridge_weights[fid] = w
	save_fridge()
	build_fridge_ui()

# ── Remove one from fridge ──
#func remove_one_from_fridge(food: Dictionary):
	#var fid = food.get("id", "")
	#if not fridge_quantities.has(fid): return
	#fridge_quantities[fid] -= 1
	#if fridge_quantities[fid] <= 0:
		#fridge_quantities.erase(fid)
		#fridge_foods = fridge_foods.filter(func(f): return f["id"] != fid)
	#save_fridge()
	#build_fridge_ui()

# ── Build the fridge grid ──
func build_fridge_ui():
	var fridge = $FridgeContainer
	fridge.add_theme_constant_override("h_separation", 20)
	fridge.add_theme_constant_override("v_separation", 20)
	for child in fridge.get_children():
		child.queue_free()

	for food in fridge_foods:
		var fid = food.get("id", "")
		var qty = fridge_quantities.get(fid, 1)
		var w   = fridge_weights.get(fid,{"remaining_g":100.0})
		var remaining = w.get("remaining_g",100.0)

		# Outer container to stack badge over button
		var container = Control.new()
		container.custom_minimum_size = Vector2(220, 220)

		# Button
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(220, 220)
		btn.size = Vector2(220, 220)
		btn.position = Vector2(0, 0)
		btn.tooltip_text = food.get("name", "") + " (" + str(snappedf(remaining,0.1)) + "g left)"

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(90, 90)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path = "res://images/" + fid + ".png"
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		btn.add_child(icon)

		# Long press timer
		var timer = Timer.new()
		timer.wait_time = 1.4
		timer.one_shot = true
		btn.add_child(timer)

		timer.timeout.connect(func():
			_long_press_active = true
			_on_info_pressed(food)
		)

		btn.gui_input.connect(func(event): _handle_fridge_input(event, food, btn, timer))
		container.add_child(btn)

		# Count badge — only show if qty > 1
		if qty > 1:
			var badge = Label.new()
			badge.text = str(qty)
			badge.add_theme_font_size_override("font_size", 30)
			badge.add_theme_color_override("font_color", Color.WHITE)
			# Position badge top-right corner
			badge.position = Vector2(75, 2)
			badge.custom_minimum_size = Vector2(50, 50)
			# Add a dark background panel behind badge
			var badge_bg = ColorRect.new()
			badge_bg.color = Color(0.1, 0.1, 0.1, 0.85)
			badge_bg.size = Vector2(50, 50)
			badge_bg.position = Vector2(75, 2)
			container.add_child(badge_bg)
			container.add_child(badge)

		fridge.add_child(container)

# ── Handle short/long press ──
func _handle_fridge_input(event: InputEvent, food: Dictionary, _btn: Button, timer: Timer):
	var is_press   = false
	var is_release = false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_press   = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenTouch:
		is_press   = event.pressed
		is_release = not event.pressed

	if is_press:
		_long_press_active = false
		timer.start()

	if is_release:
		if timer.time_left > 0:
			timer.stop()
			if not _long_press_active:
				_open_action_popup(food)



# ─────────────────────────────────────────
#  ACTION POPUP — 8 buttons
# ─────────────────────────────────────────
func _open_action_popup(food: Dictionary):
	var existing = get_node_or_null("ActionPopup")
	if existing: existing.queue_free()

	var fid = food.get("id","")
	var w   = fridge_weights.get(fid, {"total_g":100.0,"remaining_g":100.0})
	var remaining_g = w.get("remaining_g", 100.0)
	var density = food.get("density_g_per_ml", 1.0)

	var popup = PanelContainer.new()
	popup.name = "ActionPopup"
	popup.custom_minimum_size = Vector2(350, 500)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	popup.add_child(vbox)

	# Title
	var title = Label.new()
	title.text = food.get("name","")
	title.add_theme_font_size_override("font_size", 26)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	# Remaining weight
	var weight_lbl = Label.new()
	weight_lbl.name = "WeightLabel"
	weight_lbl.text = "Remaining: " + str(snappedf(remaining_g, 0.1)) + " g"
	weight_lbl.add_theme_font_size_override("font_size", 22)
	vbox.add_child(weight_lbl)

	var sep = HSeparator.new()
	vbox.add_child(sep)

	# 8 action buttons in 2 columns
	var actions = [
		{"icon":"⚖️",  "label":"Modify\nWeight",   "key":"modify"},
		{"icon":"🍽️",  "label":"Eat\nWhole",        "key":"eat_whole"},
		{"icon":"🥄",  "label":"Tablespoon\n(15mL)", "key":"tablespoon"},
		{"icon":"🫖",  "label":"Teaspoon\n(5mL)",    "key":"teaspoon"},
		{"icon":"⚡",  "label":"By Gram",            "key":"gram"},
		{"icon":"💊",  "label":"By Milligram",       "key":"milligram"},
		{"icon":"🥛",  "label":"Glass\n(250mL)",     "key":"glass"},
		{"icon":"🗑️",  "label":"Throw\nOut",         "key":"throw_out"},
	]

	var grid = GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	for action in actions:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(155, 80)
		btn.text = action["icon"] + "\n" + action["label"]
		btn.pressed.connect(func(): _on_action_pressed(action["key"], food, popup, density, remaining_g))
		grid.add_child(btn)

	# Input area (hidden by default, shown for certain actions)
	var input_area = VBoxContainer.new()
	input_area.name = "InputArea"
	input_area.visible = false
	vbox.add_child(input_area)

	# Close button
	var close_btn = Button.new()
	close_btn.text = "✕ Close"
	close_btn.custom_minimum_size = Vector2(0,55)
	close_btn.add_theme_font_size_override("font_size",24)
	close_btn.pressed.connect(func(): popup.queue_free())
	vbox.add_child(close_btn)

	popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(popup)

func _on_action_pressed(key: String, food: Dictionary, popup: PanelContainer, density: float, remaining_g: float):
	var fid = food.get("id","")

	match key:
		"eat_whole":
			_eat_portion(food, remaining_g, popup)

		"throw_out":
			_remove_food_from_fridge(fid)
			popup.queue_free()

		"modify":
			_show_input_area(popup, food, "modify", "New total weight (g):", 100, 10000, 1, density, remaining_g)

		"tablespoon":
			# 1 tbsp = 15mL
			var grams_per_tbsp = 15.0 * density
			_show_input_area(popup, food, "tablespoon", "How many tablespoons?", 1, 50, 1, density, remaining_g)

		"teaspoon":
			_show_input_area(popup, food, "teaspoon", "How many teaspoons?", 1, 50, 1, density, remaining_g)

		"gram":
			_show_input_area(popup, food, "gram", "How many grams?", 1, 2000, 1, density, remaining_g)

		"milligram":
			_show_input_area(popup, food, "milligram", "How many milligrams?", 100, 500000, 100, density, remaining_g)

		"glass":
			_show_input_area(popup, food, "glass", "How many glasses (250mL)?", 1, 10, 1, density, remaining_g)

func _show_input_area(popup: PanelContainer, food: Dictionary, action_key: String, prompt: String, min_val: float, max_val: float, step: float, density: float, remaining_g: float):
	var input_area = popup.find_child("InputArea", true, false)
	if not input_area: return

	# Clear previous
	for child in input_area.get_children():
		child.queue_free()
	input_area.visible = true

	var lbl = Label.new()
	lbl.text = prompt
	lbl.add_theme_font_size_override("font_size", 22)
	input_area.add_child(lbl)

	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.step = step
	spin.value = min_val
	spin.custom_minimum_size = Vector2(200, 50)
	input_area.add_child(spin)

	# Preview label
	var preview = Label.new()
	preview.name = "Preview"
	preview.add_theme_font_size_override("font_size", 20)
	input_area.add_child(preview)

	# Update preview on value change
	spin.value_changed.connect(func(val):
		var portion_g = _calc_portion_g(action_key, val, density)
		preview.text = "≈ " + str(snappedf(portion_g, 0.1)) + " g"
	)
	# Initial preview
	var initial_g = _calc_portion_g(action_key, min_val, density)
	preview.text = "≈ " + str(snappedf(initial_g, 0.1)) + " g"

	var confirm_btn = Button.new()
	confirm_btn.text = "✓ Confirm"
	confirm_btn.custom_minimum_size = Vector2(0, 55)
	confirm_btn.add_theme_font_size_override("font_size", 24)
	confirm_btn.pressed.connect(func():
		var val = spin.value
		if action_key == "modify":
			_modify_weight(food, val, popup)
		else:
			var portion_g = _calc_portion_g(action_key, val, density)
			_eat_portion(food, portion_g, popup)
	)
	input_area.add_child(confirm_btn)

func _calc_portion_g(action_key: String, value: float, density: float) -> float:
	match action_key:
		"tablespoon": return value * 15.0 * density
		"teaspoon":   return value * 5.0  * density
		"glass":      return value * 250.0 * density
		"gram":       return value
		"milligram":  return value / 1000.0
		_:            return value

# ─────────────────────────────────────────
#  EAT PORTION — scales nutrients by grams eaten
# ─────────────────────────────────────────
func _eat_portion(food: Dictionary, portion_g: float, popup: PanelContainer):
	var fid = food.get("id","")
	var w   = fridge_weights.get(fid, {"total_g":100.0,"remaining_g":100.0})
	var remaining = w.get("remaining_g", 100.0)

	# Cap portion at remaining
	portion_g = min(portion_g, remaining)
	if portion_g <= 0:
		popup.queue_free()
		return

	# Scale a food dict to the portion
	var scaled = food.duplicate()
	var ratio = portion_g / 100.0
	var scalable_fields = [
		"calories","protein_g","fat_g","carbs_g","fiber_g","calcium_mg",
		"saturated_fat_g","monounsaturated_fat_g","polyunsaturated_fat_g",
		"sugar_g","sodium_mg","iron_mg","copper_mg","selenium_mcg",
		"vitamin_a_mcg","vitamin_b1_mg","vitamin_b2_mg","vitamin_b3_mg",
		"vitamin_b5_mg","vitamin_b6_mg","vitamin_b7_mcg","vitamin_b9_mcg",
		"vitamin_b12_mcg","vitamin_c_mg","vitamin_d_mcg","vitamin_e_mg",
		"vitamin_k1_mcg","vitamin_k2_mcg","magnesium_mg","potassium_mg",
		"zinc_mg","phosphorus_mg","manganese_mg","chromium_mcg",
		"iodine_mcg","molybdenum_mcg","beta_carotene_mcg","lycopene_mcg",
		"lutein_zeaxanthin_mcg","quercetin_mg","anthocyanins_mg",
		"resveratrol_mg","total_polyphenols_mg","oxalate_mg_per_100g"
	]
	for field in scalable_fields:
		if scaled.has(field):
			scaled[field] = scaled[field] * ratio

	# Update remaining weight
	remaining -= portion_g
	w["remaining_g"] = remaining
	fridge_weights[fid] = w

	# Remove from fridge if empty
	if remaining <= 0.1:
		_remove_food_from_fridge(fid)
	else:
		# Update quantity display (rough: 1 qty per 100g)
		fridge_quantities[fid] = max(1, int(ceil(remaining / 100.0)))
		save_fridge()
		build_fridge_ui()

	popup.queue_free()

	# Log scaled nutrients to HomePage
	var main = get_tree().root.get_node("Main")
	var home = main.get_node_or_null("ContentArea/HomePage")
	if home == null:
		_log_food_to_file(scaled)
	else:
		home.log_food(scaled)

# ─────────────────────────────────────────
#  MODIFY WEIGHT — change total package weight
# ─────────────────────────────────────────
func _modify_weight(food: Dictionary, new_total_g: float, popup: PanelContainer):
	var fid = food.get("id","")
	var w   = fridge_weights.get(fid, {"total_g":100.0,"remaining_g":100.0})
	var old_total    = w.get("total_g", 100.0)
	var old_remaining = w.get("remaining_g", 100.0)

	# Scale remaining proportionally
	var ratio = old_remaining / old_total if old_total > 0 else 1.0
	w["total_g"]     = new_total_g
	w["remaining_g"] = new_total_g * ratio
	fridge_weights[fid] = w
	fridge_quantities[fid] = max(1, int(ceil(w["remaining_g"] / 100.0)))

	save_fridge()
	build_fridge_ui()
	popup.queue_free()

# ─────────────────────────────────────────
#  REMOVE FOOD FROM FRIDGE
# ─────────────────────────────────────────
func _remove_food_from_fridge(fid: String):
	fridge_foods = fridge_foods.filter(func(f): return f["id"] != fid)
	fridge_quantities.erase(fid)
	fridge_weights.erase(fid)
	save_fridge()
	build_fridge_ui()

# ── Show nutritional info bubble ──
func _on_info_pressed(food: Dictionary):
	var existing = get_node_or_null("InfoBubble")
	if existing:
		existing.queue_free()

	var bubble = PanelContainer.new()
	bubble.name = "InfoBubble"
	bubble.custom_minimum_size = Vector2(340, 400)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 40)
	bubble.add_child(vbox)

	var title = Label.new()
	title.text = food.get("name", "") + " (per 100g)"
	title.add_theme_font_size_override("font_size", 50)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	var separator = HSeparator.new()
	separator.add_theme_constant_override("h_separation", 30)
	separator.add_theme_constant_override("v_separation", 30)
	vbox.add_child(separator)

	var fields = [
		["Calories",     str(food.get("calories", 0)) + " kcal"],
		["Protein",      str(food.get("protein_g", 0)) + " g"],
		["Fat",          str(food.get("fat_g", 0)) + " g"],
		["  Saturated",  str(food.get("saturated_fat_g", 0)) + " g"],
		["  Mono",       str(food.get("monounsaturated_fat_g", 0)) + " g"],
		["  Poly",       str(food.get("polyunsaturated_fat_g", 0)) + " g"],
		["Carbs",        str(food.get("carbs_g", 0)) + " g"],
		["  Sugar",      str(food.get("sugar_g", 0)) + " g"],
		["Fiber",        str(food.get("fiber_g", 0)) + " g"],
	]

	for pair in fields:
		var row = HBoxContainer.new()
		var key_lbl = Label.new()
		key_lbl.text = pair[0]
		key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_lbl.add_theme_font_size_override("font_size", 26)
		var val_lbl = Label.new()
		val_lbl.text = pair[1]
		val_lbl.add_theme_font_size_override("font_size", 26)
		row.add_child(key_lbl)
		row.add_child(val_lbl)
		vbox.add_child(row)

	var close_btn = Button.new()
	close_btn.text = "✕ Close"
	close_btn.add_theme_font_size_override("font_size", 28)
	close_btn.custom_minimum_size = Vector2(0, 60)
	close_btn.pressed.connect(func(): bubble.queue_free())
	vbox.add_child(close_btn)

	bubble.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(bubble)

# ── Log food to file when HomePage not loaded ──
func _log_food_to_file(food: Dictionary):
	var today  = Time.get_date_string_from_system()
	var totals = {
		"calories":0.0,"protein_g":0.0,"fat_g":0.0,
		"saturated_fat_g":0.0,"monounsaturated_fat_g":0.0,"polyunsaturated_fat_g":0.0,
		"carbs_g":0.0,"fiber_g":0.0,"calcium_mg":0.0,"oxalate_mg":0.0,
		"sugar_g":0.0,"sodium_mg":0.0,"iron_mg":0.0,"copper_mg":0.0,"selenium_mcg":0.0
	}
	var foods = []

	if FileAccess.file_exists("user://intake.json"):
		var read_file = FileAccess.open("user://intake.json", FileAccess.READ)
		var data = JSON.parse_string(read_file.get_as_text())
		read_file.close()
		if data and data.get("date", "") == today:
			totals = data.get("totals", totals)
			foods  = data.get("foods", [])

	totals["calories"]             += food.get("calories", 0)
	totals["protein_g"]            += food.get("protein_g", 0)
	totals["fat_g"]                += food.get("fat_g", 0)
	totals["saturated_fat_g"]      += food.get("saturated_fat_g", 0)
	totals["monounsaturated_fat_g"]+= food.get("monounsaturated_fat_g", 0)
	totals["polyunsaturated_fat_g"]+= food.get("polyunsaturated_fat_g", 0)
	totals["carbs_g"]              += food.get("carbs_g", 0)
	totals["fiber_g"]              += food.get("fiber_g", 0)
	totals["calcium_mg"]           += food.get("calcium_mg", 0)
	totals["oxalate_mg"]           += food.get("oxalate_mg_per_100g", 0)
	totals["sugar_g"]              += food.get("sugar_g", 0)
	totals["sodium_mg"]            += food.get("sodium_mg", 0)
	totals["iron_mg"]              += food.get("iron_mg", 0)
	totals["copper_mg"]            += food.get("copper_mg", 0)
	totals["selenium_mcg"]         += food.get("selenium_mcg", 0)
	foods.append(food.get("name", "Unknown"))

	var file = FileAccess.open("user://intake.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"date": today, "totals": totals, "foods": foods}))
	file.close()

# ── Open/close shopping list ──
func _on_list_pressed():
	$Panel/VBoxContainer/ShoppingListPanel.show()

func _on_close_list():
	$Panel/VBoxContainer/ShoppingListPanel.hide()

# ── Save/load fridge ──
func save_fridge():
	var file = FileAccess.open("user://fridge.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"fridge": fridge_foods,
		"quantities": fridge_quantities,
		"weights": fridge_weights
	}))
	file.close()

func load_fridge():
	if not FileAccess.file_exists("user://fridge.json"): return
	var file = FileAccess.open("user://fridge.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	if data.has("fridge"):
		fridge_foods = data["fridge"]
	if data.has("quantities"):
		fridge_quantities = data["quantities"]
	if data.has("weights"):
		fridge_weights = data["weights"]
	else:
		# Migrate old saves — give everything qty 1
		for food in fridge_foods:
			var fid = food.get("id","")
			var qty = fridge_quantities.get(fid,1)
			fridge_weights[fid] = {"total_g": 100.0 * qty, "remaining_g": 100.0 * qty}
	build_fridge_ui()
