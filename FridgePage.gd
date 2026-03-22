extends Control

var all_foods: Array = []
var fridge_foods: Array = []
var shopping_list: Array = []
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

	var cat = tabs.get_tab_title(tabs.current_tab).to_lower()
	var search = $Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/TopBar2/SearchBar.text.to_lower()

	var filtered = all_foods.filter(func(f):
		var right_cat = f.get("category", "") == cat
		var matches = search.is_empty() or f.get("name", "").to_lower().contains(search)
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
	if shopping_list.any(func(f): return f["id"] == food["id"]):
		return
	shopping_list.append(food)
	refresh_shopping_list()

# ── Rebuild the shopping list checkboxes ──
func refresh_shopping_list():
	var container = $Panel/VBoxContainer/ShoppingListPanel/VBoxContainer/ShoppingListContainer
	for child in container.get_children():
		child.queue_free()

	for food in shopping_list:
		var row = HBoxContainer.new()

		var cb = CheckBox.new()
		cb.text = food.get("name", "")
		cb.add_theme_font_size_override("font_size", 28)
		cb.custom_minimum_size = Vector2(300, 60)
		cb.toggled.connect(func(checked):
			if checked:
				add_to_fridge(food)
		)
		row.add_child(cb)

		var warnings = Global.get_warnings(food)
		if warnings.size() > 0:
			var badge = Label.new()
			badge.text = "⛔" if warnings[0]["severity"] == "avoid" else "⚠️"
			badge.tooltip_text = warnings[0]["message"]
			row.add_child(badge)

		container.add_child(row)

# ── Add food to fridge ──
func add_to_fridge(food: Dictionary):
	if fridge_foods.any(func(f): return f["id"] == food["id"]):
		return
	fridge_foods.append(food)
	save_fridge()
	build_fridge_ui()

# ── Build the fridge grid ──
func build_fridge_ui():
	var fridge = $FridgeContainer
	fridge.add_theme_constant_override("h_separation", 40)
	fridge.add_theme_constant_override("v_separation", 40)
	for child in fridge.get_children():
		child.queue_free()
	
	var max_display = 18  # 3 columns × 8 rows
	var fridge_foods = fridge_foods.slice(max(0, fridge_foods.size() - max_display))

	for food in fridge_foods:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(200, 200)
		btn.tooltip_text = food.get("name", "")

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(100, 100)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path = "res://images/" + food.get("id", "") + ".png"
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		btn.add_child(icon)

		# Create a timer for long press detection
		var timer = Timer.new()
		timer.wait_time = 2.0
		timer.one_shot = true
		btn.add_child(timer)

		# Long press → nutritional info bubble
		timer.timeout.connect(func():
			_long_press_active = true
			_on_info_pressed(food)
		)

		# Handle press and release
		btn.gui_input.connect(func(event): _handle_fridge_input(event, food, btn, timer))

		fridge.add_child(btn)

# ── Handle short/long press on fridge food ──
func _handle_fridge_input(event: InputEvent, food: Dictionary, _btn: Button, timer: Timer):
	var is_press = false
	var is_release = false

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_press = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenTouch:
		is_press = event.pressed
		is_release = not event.pressed

	if is_press:
		_long_press_active = false
		timer.start()

	if is_release:
		if timer.time_left > 0:
			timer.stop()
			if not _long_press_active:
				# Short tap → eat
				_on_eat_pressed(food)

# ── Eat food ──
func _on_eat_pressed(food: Dictionary):
	fridge_foods = fridge_foods.filter(func(f): return f["id"] != food["id"])

	save_fridge()
	build_fridge_ui()

	# Log to HomePage
	var main = get_tree().root.get_node("Main")
	var home = main.get_node_or_null("ContentArea/HomePage")
	if home == null:
		_log_food_to_file(food)
	else:
		home.log_food(food)

# ── Show nutritional info bubble ──
func _on_info_pressed(food: Dictionary):
	var existing = get_node_or_null("InfoBubble")
	if existing:
		existing.queue_free()

	var bubble = PanelContainer.new()
	bubble.name = "InfoBubble"
	bubble.custom_minimum_size = Vector2(620, 400)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 20)
	bubble.add_child(vbox)

	var title = Label.new()
	title.text = food.get("name", "") + " (per 100g)"
	title.add_theme_font_size_override("font_size", 40)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	var separator = HSeparator.new()
	vbox.add_child(separator)

	var fields = [
		["Calories",      str(food.get("calories", 0)) + " kcal"],
		["Protein",       str(food.get("protein_g", 0)) + " g"],
		["Fat",           str(food.get("fat_g", 0)) + " g"],
		["  Saturated",   str(food.get("saturated_fat_g", 0)) + " g"],
		["  Mono",        str(food.get("monounsaturated_fat_g", 0)) + " g"],
		["  Poly",        str(food.get("polyunsaturated_fat_g", 0)) + " g"],
		["Carbs",         str(food.get("carbs_g", 0)) + " g"],
		["  Sugar",       str(food.get("sugar_g", 0)) + " g"],
		["Fiber",         str(food.get("fiber_g", 0)) + " g"],
		["Calcium",       str(food.get("calcium_mg", 0)) + " mg"],
		["Sodium",        str(food.get("sodium_mg", 0)) + " mg"],
		["Oxalates",      str(food.get("oxalate_mg_per_100g", 0)) + " mg"],
	]

	for pair in fields:
		var row = HBoxContainer.new()
		var key_lbl = Label.new()
		key_lbl.text = pair[0]
		key_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		key_lbl.add_theme_font_size_override("font_size", 40)

		var val_lbl = Label.new()
		val_lbl.text = pair[1]
		val_lbl.add_theme_font_size_override("font_size", 40)

		row.add_child(key_lbl)
		row.add_child(val_lbl)
		vbox.add_child(row)

	var close_btn = Button.new()
	close_btn.text = "✕ Close"
	close_btn.add_theme_font_size_override("font_size", 40)
	close_btn.custom_minimum_size = Vector2(0, 100)
	close_btn.pressed.connect(func(): bubble.queue_free())
	vbox.add_child(close_btn)

	bubble.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(bubble)

# ── Log food to file when HomePage is not loaded ──
func _log_food_to_file(food: Dictionary):
	var today = Time.get_date_string_from_system()
	var totals = {"calories":0.0,"protein_g":0.0,"fat_g":0.0,"carbs_g":0.0,"fiber_g":0.0,"calcium_mg":0.0,"oxalate_mg":0.0}
	var foods = []

	if FileAccess.file_exists("user://intake.json"):
		var read_file = FileAccess.open("user://intake.json", FileAccess.READ)
		var data = JSON.parse_string(read_file.get_as_text())
		read_file.close()
		if data and data.get("date", "") == today:
			totals = data.get("totals", totals)
			foods  = data.get("foods", [])

	totals["calories"]   += food.get("calories", 0)
	totals["protein_g"]  += food.get("protein_g", 0)
	totals["fat_g"]      += food.get("fat_g", 0)
	totals["carbs_g"]    += food.get("carbs_g", 0)
	totals["fiber_g"]    += food.get("fiber_g", 0)
	totals["calcium_mg"] += food.get("calcium_mg", 0)
	totals["oxalate_mg"] += food.get("oxalate_mg_per_100g", 0)
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
	file.store_string(JSON.stringify({"fridge": fridge_foods}))
	file.close()

func load_fridge():
	if not FileAccess.file_exists("user://fridge.json"): return
	var file = FileAccess.open("user://fridge.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data and data.has("fridge"):
		fridge_foods = data["fridge"]
		build_fridge_ui()
