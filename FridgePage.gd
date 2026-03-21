extends Control

var all_foods: Array = []
var fridge_foods: Array = []
var shopping_list: Array = []

func build_fridge_ui2():
	print("build_fridge_ui called")

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

	# Warning badge
	var warnings = Global.get_warnings(food)
	if warnings.size() > 0:
		var badge = Label.new()
		badge.text = "⛔" if warnings[0]["severity"] == "avoid" else "⚠️"
		badge.tooltip_text = warnings[0]["message"]
		row.add_child(badge)

	# Add to shopping list button
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
		cb.add_theme_font_size_override("font_size", 32)
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
	var fridge = $Panel/VBoxContainer/FridgeContainer
	for child in fridge.get_children():
		child.queue_free()

	for food in fridge_foods:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(70, 70)
		btn.tooltip_text = food.get("name", "")

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(60, 60)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path = "res://images/" + food.get("id", "") + ".png"
		if ResourceLoader.exists(path):
			icon.texture = load(path)
		btn.add_child(icon)

		btn.pressed.connect(func(): open_food_popup(food))
		fridge.add_child(btn)

# ── Open eat/info popup ──
func open_food_popup(food: Dictionary):
	var popup = preload("res://FoodPopup.tscn").instantiate()
	add_child(popup)
	popup.setup(food)
	popup.eat_pressed.connect(_on_eat_pressed)
	popup.info_pressed.connect(_on_info_pressed)

func _on_eat_pressed(food: Dictionary):
	fridge_foods = fridge_foods.filter(func(f): return f["id"] != food["id"])
	save_fridge()
	build_fridge_ui()
	# Log to daily intake
	var intake = get_tree().root.get_node_or_null("Main/ContentArea/HomePage")
	if intake:
		intake.log_food(food)

func _on_info_pressed(food: Dictionary):
	var info = preload("res://NutritionalInfo.tscn").instantiate()
	add_child(info)
	info.setup(food)

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
