extends Control

var all_foods: Array = []
var fridge_foods: Array = []        # list of unique food dicts
var fridge_quantities: Dictionary = {} # food_id → count
var fridge_weights: Dictionary = {}   # food_id → {total_g, remaining_g}
var shopping_list: Array = []
var _long_press_active: bool = false
var fridge_overrides: Dictionary = {}
var checked_items: Dictionary = {}  # food_id → bool

# ── Paging ──
var current_page: int = 0
const ITEMS_PER_PAGE: int = 18
const GRID_COLS: int = 3
var shopping_page: int = 0
const SHOPPING_ITEMS_PER_PAGE: int = 10

# ── Swipe detection ──
var _swipe_threshold: float = 50.0
var _touch_start_x: float = 0.0
var _touch_start_y: float = 0.0
var _is_tracking: bool = false
var _drag_distance: float = 0.0

# ── Filter state ──
var active_filters: Array = []   # list of field keys
var sort_ascending: bool = true
var filter_buttons: Dictionary = {}  # field_key → Button
var warning_filter: String = "all"  # "all", "caution", "avoid", "none"

# ── All filterable nutrients with display labels ──
# Note: vitamin_k1 is intentionally excluded for safety
const FILTER_OPTIONS = [
	{"key":"vitamin_a_mcg",        "label":"Vit A"},
	{"key":"vitamin_b1_mg",        "label":"B1 (Thiamine)"},
	{"key":"vitamin_b2_mg",        "label":"B2 (Riboflavin)"},
	{"key":"vitamin_b3_mg",        "label":"B3 (Niacin)"},
	{"key":"vitamin_b5_mg",        "label":"B5"},
	{"key":"vitamin_b6_mg",        "label":"B6"},
	{"key":"vitamin_b7_mcg",       "label":"B7 (Biotin)"},
	{"key":"vitamin_b9_mcg",       "label":"B9 (Folate)"},
	{"key":"vitamin_b12_mcg",      "label":"B12 (Cobalamin)"},
	{"key":"vitamin_c_mg",         "label":"Vit C"},
	{"key":"vitamin_d_mcg",        "label":"Vit D"},
	{"key":"vitamin_e_mg",         "label":"Vit E"},
	{"key":"vitamin_k2_mcg",       "label":"Vit K2"},
	{"key":"calcium_mg",           "label":"Calcium"},
	{"key":"iron_mg",              "label":"Iron"},
	{"key":"magnesium_mg",         "label":"Magnesium"},
	{"key":"potassium_mg",         "label":"Potassium"},
	{"key":"zinc_mg",              "label":"Zinc"},
	{"key":"phosphorus_mg",        "label":"Phosphorus"},
	{"key":"selenium_mcg",         "label":"Selenium"},
	{"key":"iodine_mcg",           "label":"Iodine"},
	{"key":"copper_mg",            "label":"Copper"},
	{"key":"manganese_mg",         "label":"Manganese"},
	{"key":"chromium_mcg",         "label":"Chromium"},
	{"key":"molybdenum_mcg",       "label":"Molybdenum"},
	{"key":"beta_carotene_mcg",    "label":"Beta-carotene"},
	{"key":"lycopene_mcg",         "label":"Lycopene"},
	{"key":"lutein_zeaxanthin_mcg","label":"Lutein+Zeaxanthin"},
	{"key":"quercetin_mg",         "label":"Quercetin"},
	{"key":"anthocyanins_mg",      "label":"Anthocyanins"},
	{"key":"resveratrol_mg",       "label":"Resveratrol"},
	{"key":"total_polyphenols_mg", "label":"Polyphenols"},
	{"key":"fiber_g",              "label":"Fiber"},
	{"key":"protein_g",            "label":"Protein"},
	{"key":"calories",             "label":"Calories"},
]

func _ready():
	load_foods()
	load_fridge()
	load_shopping_list()
	$Panel/ShoppingListPanel/VBoxContainer/ListPaperArea/ShoppingNavRow/ShoppingPrevBtn.pressed.connect(func():
		if shopping_page > 0:
			shopping_page -= 1
			refresh_shopping_list()
	)
	$Panel/ShoppingListPanel/VBoxContainer/ListPaperArea/ShoppingNavRow/ShoppingNextBtn.pressed.connect(func():
		var total = _get_shopping_pages()
		if shopping_page < total - 1:
			shopping_page += 1
			refresh_shopping_list()
	)
	$Panel/ShoppingListPanel/VBoxContainer/ListPaperArea/ShoppingNavRow/RipPageBtn.pressed.connect(_rip_shopping_page)
	$Panel/TopBar/ListButton.pressed.connect(_on_list_pressed)
	$Panel/ShoppingListPanel/VBoxContainer/TopBar2/CloseButton.pressed.connect(_on_close_list)
	$Panel/ShoppingListPanel/VBoxContainer/TopBar2/SearchBar.text_changed.connect(func(_t): refresh_current_tab())
	$Panel/ShoppingListPanel/VBoxContainer/TabContainer.tab_changed.connect(func(_i): refresh_current_tab())
	$Panel/ShoppingListPanel.hide()
	_build_filter_buttons()
	_build_warning_filter_buttons()
	_connect_sort_buttons()

# ─────────────────────────────────────────
#  SWIPE DETECTION
# ─────────────────────────────────────────
func _input(event: InputEvent):
	# Only track input when shopping list is hidden
	if $Panel/ShoppingListPanel.visible: return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_touch_start_x = event.position.x
			_touch_start_y = event.position.y
			_drag_distance = 0.0
			_is_tracking = true
		else:
			if _is_tracking and _drag_distance > _swipe_threshold:
				var delta = event.position.x - _touch_start_x
				if delta < -_swipe_threshold:
					_next_page()
				elif delta > _swipe_threshold:
					_prev_page()
			_is_tracking = false

	elif event is InputEventMouseMotion and _is_tracking:
		_drag_distance = abs(event.position.x - _touch_start_x)

	elif event is InputEventScreenTouch:
		if event.pressed:
			_touch_start_x = event.position.x
			_touch_start_y = event.position.y
			_drag_distance = 0.0
			_is_tracking = true
		else:
			if _is_tracking and _drag_distance > _swipe_threshold:
				var delta = event.position.x - _touch_start_x
				if delta < -_swipe_threshold:
					_next_page()
				elif delta > _swipe_threshold:
					_prev_page()
			_is_tracking = false

	elif event is InputEventScreenDrag and _is_tracking:
		_drag_distance = abs(event.position.x - _touch_start_x)

func _next_page():
	var total_pages = _get_total_pages()
	if current_page < total_pages - 1:
		current_page += 1
		build_fridge_ui()

func _prev_page():
	if current_page > 0:
		current_page -= 1
		build_fridge_ui()

func _get_total_pages() -> int:
	return max(1, int(ceil(float(fridge_foods.size()) / float(ITEMS_PER_PAGE))))
	
# ─────────────────────────────────────────
#  FILTER UI SETUP
# ─────────────────────────────────────────

func _build_filter_buttons():
	var row = $Panel/ShoppingListPanel/VBoxContainer/FilterPanel/VBoxContainer/FilterScrollH/FilterButtonsRow
	for child in row.get_children():
		child.queue_free()
	filter_buttons.clear()

	for opt in FILTER_OPTIONS:
		var btn = Button.new()
		btn.text = opt["label"]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 50)
		btn.add_theme_font_size_override("font_size", 40)
		btn.toggled.connect(func(pressed): _on_filter_toggled(opt["key"], pressed, btn))
		row.add_child(btn)
		filter_buttons[opt["key"]] = btn
		
func _build_warning_filter_buttons():
	var row = $Panel/ShoppingListPanel/VBoxContainer/FilterPanel/VBoxContainer/WarningFilterRow
	var options = [
		{"label":"All",    "key":"all"},
		{"label":"⚠️ Only", "key":"caution"},
		{"label":"⛔ Only", "key":"avoid"},
		{"label":"✅ Safe", "key":"none"},
	]
	for opt in options:
		var btn = Button.new()
		btn.text = opt["label"]
		btn.toggle_mode = true
		btn.button_pressed = opt["key"] == warning_filter
		btn.custom_minimum_size = Vector2(80, 45)
		btn.add_theme_font_size_override("font_size", 40)
		btn.pressed.connect(func():
			warning_filter = opt["key"]
			refresh_current_tab()
		)
		row.add_child(btn)

func _connect_sort_buttons():
	var sort_row = $Panel/ShoppingListPanel/VBoxContainer/FilterPanel/VBoxContainer/SortRow
	sort_row.get_node("SortAscBtn").pressed.connect(func():
		sort_ascending = true
		_update_sort_button_states()
		refresh_current_tab()
	)
	sort_row.get_node("SortDescBtn").pressed.connect(func():
		sort_ascending = false
		_update_sort_button_states()
		refresh_current_tab()
	)

func _update_sort_button_states():
	var sort_row = $Panel/ShoppingListPanel/VBoxContainer/FilterPanel/VBoxContainer/SortRow
	sort_row.get_node("SortAscBtn").button_pressed  = sort_ascending
	sort_row.get_node("SortDescBtn").button_pressed = not sort_ascending

func _on_filter_toggled(field_key: String, pressed: bool, btn: Button):
	if pressed:
		if not active_filters.has(field_key):
			active_filters.append(field_key)
		btn.modulate = Color(0.4, 0.9, 0.4)  # green when active
	else:
		active_filters.erase(field_key)
		btn.modulate = Color.WHITE
	_update_filter_label()
	refresh_current_tab()

func _update_filter_label():
	var lbl = $Panel/ShoppingListPanel/VBoxContainer/FilterPanel/VBoxContainer/ActiveFiltersLabel
	if active_filters.is_empty():
		lbl.text = "No filters active — showing all foods"
	elif active_filters.size() == 1:
		var label = _get_filter_label(active_filters[0])
		var dir = "↑ Ascending" if sort_ascending else "↓ Descending"
		lbl.text = "Filter: " + label + " | Sort: " + dir
	else:
		var labels = active_filters.map(func(k): return _get_filter_label(k))
		lbl.text = "Filters: " + ", ".join(labels) + " | Sort: by kcal"

func _get_filter_label(key: String) -> String:
	for opt in FILTER_OPTIONS:
		if opt["key"] == key:
			return opt["label"]
	return key


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
	var tabs = $Panel/ShoppingListPanel/VBoxContainer/TabContainer
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


func _get_food_severity(food: Dictionary) -> String:
	# Check Global warnings first (condition-aware)
	var warnings = Global.get_warnings(food)
	for w in warnings:
		if w["severity"] == "avoid":   return "avoid"
	for w in warnings:
		if w["severity"] == "caution": return "caution"
	
	# Fallback: oxalate-based severity even with no conditions
	var ox = food.get("oxalate_mg_per_100g", 0.0)
	if ox >= 50:  return "avoid"
	if ox >= 10:  return "caution"
	return "safe"
	
# ── Rebuild food list for active tab + search ──
func refresh_current_tab():
	var tabs = $Panel/ShoppingListPanel/VBoxContainer/TabContainer
	var scroll = tabs.get_current_tab_control()
	if not scroll: return
	var vbox = scroll.get_child(0)
	if not vbox: return

	for child in vbox.get_children():
		child.queue_free()

	var cat    = tabs.get_tab_title(tabs.current_tab).to_lower()
	var search = $Panel/ShoppingListPanel/VBoxContainer/TopBar2/SearchBar.text.to_lower()

	var filtered = all_foods.filter(func(f):
		var right_cat = f.get("category", "") == cat
		var matches   = search.is_empty() or f.get("name", "").to_lower().contains(search)
		return right_cat and matches
	)

	if not active_filters.is_empty():
		filtered = filtered.filter(func(f):
			for key in active_filters:
				if f.get(key, 0.0) <= 0:
					return false
			return true
		)

	if not active_filters.is_empty():
		var sort_key = "calories"  # default for multiple filters
		if active_filters.size() == 1:
			sort_key = active_filters[0]

		filtered.sort_custom(func(a, b):
			var va = a.get(sort_key, 0.0)
			var vb = b.get(sort_key, 0.0)
			return va < vb if sort_ascending else va > vb
		)

	for food in filtered:
		vbox.add_child(make_browse_row(food))
		
# ── Warning filter ──
	if warning_filter != "all" or Global.hide_red_warnings:
		filtered = filtered.filter(func(f):
			var severity = _get_food_severity(f)
			
			if Global.hide_red_warnings and severity == "avoid":
				return false
			
			match warning_filter:
				"avoid":   return severity == "avoid"
				"caution": return severity == "caution"
				"none":    return severity == "safe"
				_:         return true
		)
	
	# ── Warning sort ──
	if warning_filter != "all":
		filtered.sort_custom(func(a, b):
			var order = {"avoid":2, "caution":1, "safe":0}
			var sa = order.get(_get_food_severity(a), 0)
			var sb = order.get(_get_food_severity(b), 0)
			return sa < sb if sort_ascending else sa > sb
		)

# ── One row in the browse list ──
func make_browse_row(food: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 60)

	var severity = _get_food_severity(food)
	if severity == "avoid":
		var badge = Label.new()
		badge.text = "⛔"
		row.add_child(badge)
	elif severity == "caution":
		var badge = Label.new()
		badge.text = "⚠️"
		row.add_child(badge)

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

	if not active_filters.is_empty():
		var val_text = ""
		for key in active_filters:
			var val = food.get(key, 0.0)
			var label = _get_filter_label(key)
			val_text += label + ": " + str(snappedf(val, 0.1)) + " "
		var val_lbl = Label.new()
		val_lbl.text = val_text.strip_edges()
		val_lbl.add_theme_font_size_override("font_size", 40)
		row.add_child(val_lbl)
	else:
		var amount = Label.new()
		amount.text = str(food.get("oxalate_mg_per_100g",0)) + "mg ox"
		row.add_child(amount)

	var warnings = Global.get_warnings(food)
	if warnings.size() > 0:
		var badge = Label.new()
		badge.text = "⛔" if warnings[0]["severity"] == "avoid" else "⚠️"
		row.add_child(badge)

	var btn = Button.new()
	btn.text = "+ List"
	btn.pressed.connect(func(): add_to_shopping_list(food))
	row.add_child(btn)

	return row

func _generate_sid() -> String:
	return "s_" + str(Time.get_ticks_usec())

# ── Add food to shopping list ──
func add_to_shopping_list(food: Dictionary):
	# Always create a new entry — never merge with existing
	# (even same food gets its own entry if added again)
	var entry = {
		"_sid":     _generate_sid(),
		"food":     food,
		"qty":      1,
		"_checked": false
	}
	shopping_list.append(entry)
	save_shopping_list()
	refresh_shopping_list()

# ── Remove one from shopping list ──
func increment_shopping_entry(sid: String):
	for entry in shopping_list:
		if entry["_sid"] == sid:
			entry["qty"] = entry.get("qty", 1) + 1
			break
	save_shopping_list()
	refresh_shopping_list()

func decrement_shopping_entry(sid: String):
	for i in range(shopping_list.size()):
		if shopping_list[i]["_sid"] == sid:
			shopping_list[i]["qty"] -= 1
			if shopping_list[i]["qty"] <= 0:
				shopping_list.remove_at(i)
			break
	# Clamp page
	shopping_page = clamp(shopping_page, 0, max(0, _get_shopping_pages() - 1))
	save_shopping_list()
	refresh_shopping_list()

func check_shopping_entry(sid: String, checked: bool):
	for entry in shopping_list:
		if entry["_sid"] == sid:
			entry["_checked"] = checked
			if checked:
				# Move food to fridge when checked
				add_to_fridge_multi(entry["food"], entry.get("qty", 1))
			break
	save_shopping_list()
	# Do NOT call refresh_shopping_list() here — 
	# we handle the visual change directly in the row

func refresh_shopping_list():
	var paper_vbox = $Panel/ShoppingListPanel/VBoxContainer/ListPaperArea/PaperScrollContainer/PaperItemsVBox
	for child in paper_vbox.get_children():
		child.queue_free()

	# Page slice
	var start = shopping_page * SHOPPING_ITEMS_PER_PAGE
	var end   = min(start + SHOPPING_ITEMS_PER_PAGE, shopping_list.size())
	var page_items = shopping_list.slice(start, end)

	for entry in page_items:
		var sid      = entry.get("_sid", "")
		var food     = entry.get("food", {})
		var qty      = entry.get("qty", 1)
		var checked  = entry.get("_checked", false)

		var row = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 52)
		row.add_theme_constant_override("separation", 8)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		paper_vbox.add_child(row)

		# ── Minus button ──
		var minus_btn = Button.new()
		minus_btn.text = "−"
		minus_btn.custom_minimum_size = Vector2(60, 106)
		minus_btn.add_theme_font_size_override("font_size", 40)
		minus_btn.disabled = checked  # can't modify checked items
		minus_btn.pressed.connect(func(): decrement_shopping_entry(sid))
		row.add_child(minus_btn)

		# ── Main content — either RichTextLabel (checked) or CheckBox (unchecked) ──
		var food_name    = food.get("name", "")
		var display_text = food_name + (" ×" + str(qty) if qty > 1 else "")
		var severity     = _get_food_severity(food)
		if severity == "avoid":
			display_text += " ⛔"
		elif severity == "caution":
			display_text += " ⚠️"

		if checked:
			# Permanently strikethrough — use RichTextLabel, no checkbox
			var rtl = RichTextLabel.new()
			rtl.bbcode_enabled = true
			rtl.fit_content = true
			rtl.text = "[s][color=#50507a]" + display_text + "[/color][/s]"
			rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			rtl.custom_minimum_size = Vector2(0, 44)
			rtl.add_theme_font_size_override("normal_font_size", 70)
			rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(rtl)
		else:
			# Unchecked — show CheckBox
			var cb = CheckBox.new()
			cb.text = display_text
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cb.add_theme_font_size_override("font_size", 70)
			cb.add_theme_color_override("font_color",         Color(0.08, 0.15, 0.35))
			cb.add_theme_color_override("font_color_hover",   Color(0.08, 0.15, 0.35))
			cb.add_theme_color_override("font_color_pressed",  Color(0.08, 0.15, 0.35))
			# IMPORTANT: capture sid in local var for lambda
			var captured_sid = sid
			cb.toggled.connect(func(is_checked):
				if is_checked:
					check_shopping_entry(captured_sid, true)
					# Replace this row's checkbox with strikethrough immediately
					# without rebuilding the whole list
					var parent = cb.get_parent()
					var idx    = cb.get_index()
					cb.queue_free()
					var rtl2 = RichTextLabel.new()
					rtl2.bbcode_enabled = true
					rtl2.fit_content = true
					rtl2.text = "[s][color=#50507a]" + display_text + "[/color][/s]"
					rtl2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					rtl2.custom_minimum_size = Vector2(0, 44)
					rtl2.add_theme_font_size_override("normal_font_size", 70)
					rtl2.mouse_filter = Control.MOUSE_FILTER_IGNORE
					parent.add_child(rtl2)
					parent.move_child(rtl2, idx)
					# Also disable the minus button in this row
					if parent.get_child_count() > 0:
						var mb = parent.get_child(0)
						if mb is Button: mb.disabled = true
			)
			row.add_child(cb)

		# ── Plus button ──
		var plus_btn = Button.new()
		plus_btn.text = "+"
		plus_btn.custom_minimum_size = Vector2(60, 106)
		plus_btn.add_theme_font_size_override("font_size", 40)
		plus_btn.disabled = checked  # can't add more to checked items
		var captured_sid2 = sid
		plus_btn.pressed.connect(func(): increment_shopping_entry(captured_sid2))
		row.add_child(plus_btn)

	_build_shopping_dots()

func _apply_strikethrough(cb: CheckBox, original_text: String):
	# Replace checkbox label with a RichTextLabel showing strikethrough
	var parent = cb.get_parent()
	if not parent:
		return
	var idx    = cb.get_index()
	var rtl = RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.text = "[s][color=#50507a]" + original_text + "[/color][/s]"
	rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rtl.custom_minimum_size = Vector2(0, 44)
	rtl.add_theme_font_size_override("normal_font_size", 70)
	rtl.fit_content = true
	parent.remove_child(cb)
	cb.queue_free()
	parent.add_child(rtl)
	parent.move_child(rtl, idx)

func _build_shopping_dots():
	var dots = $Panel/ShoppingListPanel/VBoxContainer/ListPaperArea/ShoppingPageDots
	if not dots: return
	for child in dots.get_children():
		child.queue_free()
	var total = _get_shopping_pages()
	if total <= 1: return
	for i in range(total):
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(12,12)
		dot.color = Color.WHITE if i == shopping_page else Color(0.5,0.5,0.5,0.7)
		dots.add_child(dot)
		

func save_shopping_list():
	var file = FileAccess.open("user://shopping.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"list": shopping_list,
		"page": shopping_page
	}))
	file.close()

func load_shopping_list():
	if not FileAccess.file_exists("user://shopping.json"): return
	var file = FileAccess.open("user://shopping.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if not data: return
	shopping_list = data.get("list", [])
	shopping_page = data.get("page", 0)

# ── Add food to fridge (with quantity) ──
func _generate_iid() -> String:
	return str(Time.get_ticks_usec())

func add_to_fridge_multi(food: Dictionary, qty: int):
	for i in range(qty):
		add_to_fridge(food)

func add_to_fridge(food: Dictionary):
	var fid = food.get("id","")
	
	# Look for an existing slot with same food id AND same remaining weight (within 0.5g tolerance)
	# that hasn't been edited
	for slot in fridge_foods:
		if slot.get("id","") != fid: continue
		var iid = slot.get("_iid","")
		if fridge_overrides.has(iid): continue  # edited slots don't merge
		var w = fridge_weights.get(iid, {})
		var remaining = w.get("remaining_g", 0.0)
		var total     = w.get("total_g", 0.0)
		# Same food, same total weight per unit (100g default), not partially eaten
		if abs(total - remaining) < 0.5 and abs(total - 100.0) < 0.5:
			# Merge: increment count on this slot
			var count: int = slot.get("_count", 1) + 1
			slot["_count"] = count
			save_fridge()
			build_fridge_ui()
			return
	
	# No matching slot — create new
	var iid  = _generate_iid()
	var slot = food.duplicate()
	slot["_iid"]   = iid
	slot["_count"] = 1
	fridge_foods.append(slot)
	fridge_weights[iid] = {"total_g": 100.0, "remaining_g": 100.0}
	if current_page >= _get_total_pages():
		current_page = _get_total_pages() - 1
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
	var fridge = $Panel/FridgeContainer
	fridge.add_theme_constant_override("h_separation", 40)
	fridge.add_theme_constant_override("v_separation", 20)
	for child in fridge.get_children():
		child.queue_free()


	# Clamp page
	current_page = clamp(current_page, 0, max(0, _get_total_pages() - 1))
	
	# Get current page items
	var start = current_page * ITEMS_PER_PAGE
	var end   = min(start + ITEMS_PER_PAGE, fridge_foods.size())
	var page_items = fridge_foods.slice(start, end)

	for slot in page_items:
		var iid       = slot.get("_iid","")
		var w         = fridge_weights.get(iid, {"remaining_g":100.0})
		var remaining = w.get("remaining_g",100.0)
		var has_override = fridge_overrides.has(iid)

		# Outer container to stack badge over button
		var container = Control.new()
		container.custom_minimum_size = Vector2(210, 210)

		# Button
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(210, 210)
		btn.size = Vector2(210, 210)
		btn.position = Vector2(0, 0)
		var count = slot.get("_count", 1)
		btn.tooltip_text = slot.get("name","") + "\n" + str(snappedf(remaining, 0.1)) + "g × " + str(count)

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(90,90)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path = "res://images/" + slot.get("id","") + ".png"
		if ResourceLoader.exists(path): icon.texture = load(path)
		btn.add_child(icon)
		# Long press timer
		var timer = Timer.new()
		timer.wait_time = 1.2
		timer.one_shot = true
		btn.add_child(timer)

		timer.timeout.connect(func():
			_long_press_active = true
			_open_dual_popup(slot, btn)
	)

		btn.gui_input.connect(func(event): _handle_fridge_input(event, slot, btn, timer))
		container.add_child(btn)

# Count badge
		if count > 1:
			var badge_bg = ColorRect.new()
			badge_bg.color = Color(0.1, 0.1, 0.1, 0.9)
			badge_bg.size = Vector2(55, 55)
			badge_bg.position = Vector2(container.custom_minimum_size.x - 38, 2)
			container.add_child(badge_bg)
			var badge = Label.new()
			badge.text = str(int(count))
			badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			badge.add_theme_font_size_override("font_size", 40)
			badge.add_theme_color_override("font_color", Color.WHITE)
			badge.position = Vector2(container.custom_minimum_size.x - 38, 2)
			badge.custom_minimum_size = Vector2(55, 55)
			container.add_child(badge)
			
			
		# Count badge — only show if qty > 1
		#if qty > 1:
			#var badge = Label.new()
			#badge.text = str(qty)
			#badge.add_theme_font_size_override("font_size", 30)
			#badge.add_theme_color_override("font_color", Color.WHITE)
			# Position badge top-right corner
			#badge.position = Vector2(75, 2)
			#badge.custom_minimum_size = Vector2(50, 50)
			# Add a dark background panel behind badge
			#var badge_bg = ColorRect.new()
			#badge_bg.color = Color(0.1, 0.1, 0.1, 0.85)
			#badge_bg.size = Vector2(50, 50)
			#badge_bg.position = Vector2(75, 2)
			#container.add_child(badge_bg)
			#container.add_child(badge)

		#fridge.add_child(container)
		
# Edit override indicator
		if has_override:
			var edit_dot = ColorRect.new()
			edit_dot.color = Color(0.2, 0.6, 1.0, 0.9)
			edit_dot.size = Vector2(14, 14)
			edit_dot.position = Vector2(2, 2)
			container.add_child(edit_dot)

		fridge.add_child(container)

	# Fill empty slots with invisible placeholders to keep grid shape
	var empty_slots = ITEMS_PER_PAGE - page_items.size()
	for i in range(empty_slots):
		var placeholder = Control.new()
		placeholder.custom_minimum_size = Vector2(110,110)
		fridge.add_child(placeholder)

	# Build dot indicators
	_build_page_dots()

func _build_page_dots():
	var dots_container = $Panel/PageDots
	if not dots_container: return
	for child in dots_container.get_children():
		child.queue_free()

	var total = _get_total_pages()
	if total <= 1: return

	for i in range(total):
		var dot = ColorRect.new()
		dot.custom_minimum_size = Vector2(14, 14)
		if i == current_page:
			dot.color = Color.WHITE
		else:
			dot.color = Color(0.5, 0.5, 0.5, 0.7)
		dots_container.add_child(dot)


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
		# Close any existing popups immediately when pressing a new food
		var existing_action = get_node_or_null("ActionPopup")
		if existing_action: existing_action.queue_free()
		var existing_info = get_node_or_null("InfoBubble")
		if existing_info: existing_info.queue_free()
		_long_press_active = false
		timer.start()

	if is_release:
		timer.stop()



# ─────────────────────────────────────────
#  ACTION POPUP — 9 buttons
# ─────────────────────────────────────────

func _open_dual_popup(slot: Dictionary, pressed_btn: Button):
	# Clean up any existing popups
	var existing_action = get_node_or_null("ActionPopup")
	if existing_action: existing_action.queue_free()
	var existing_info = get_node_or_null("InfoBubble")
	if existing_info: existing_info.queue_free()

	var iid       = slot.get("_iid","")
	var w         = fridge_weights.get(iid, {"remaining_g":100.0})
	var remaining = w.get("remaining_g", 100.0)
	var density   = slot.get("density_g_per_ml", 1.0)
	var effective = _get_effective_slot(slot)
	var has_override = fridge_overrides.has(iid)

	# ── NUTRITIONAL INFO POPUP ──
	# Fixed position: x=0..1170, y=0..215 (in your 390x844 display = scale 0.333)
	# In display coords: x=0..390, y=0..72
	var info_popup = PanelContainer.new()
	info_popup.name = "InfoBubble"
	# Position at top of screen
	info_popup.set_anchor_and_offset(SIDE_LEFT,   0, 0)
	info_popup.set_anchor_and_offset(SIDE_RIGHT,  1, 0)
	info_popup.set_anchor_and_offset(SIDE_TOP,    0, 0)
	info_popup.set_anchor_and_offset(SIDE_BOTTOM, 0, 215 * (390.0/1170.0))
	# 215/1170 * 390 ≈ 72px in display space

	var info_hbox = HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 20)
	info_popup.add_child(info_hbox)

	# Left column
	var left_col = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_hbox.add_child(left_col)

	var food_title = Label.new()
	food_title.text = slot.get("name","") + (" ✏️" if has_override else "")
	food_title.add_theme_font_size_override("font_size", 40)
	food_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	left_col.add_child(food_title)

	var fields_left = [
		["  Calories",    str(snappedf(effective.get("calories",0),0.1)) + " kcal"],
		["  Protein",     str(snappedf(effective.get("protein_g",0),0.1)) + " g"],
		["  Fat",         str(snappedf(effective.get("fat_g",0),0.1)) + " g"],
		["  Sat.",      str(snappedf(effective.get("saturated_fat_g",0),0.1)) + " g"],
		["  Carbs",       str(snappedf(effective.get("carbs_g",0),0.1)) + " g"],
		["  Sugar",     str(snappedf(effective.get("sugar_g",0),0.1)) + " g"],
	]
	for pair in fields_left:
		var row = HBoxContainer.new()
		var k = Label.new()
		k.text = pair[0]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_font_size_override("font_size", 35)
		var v = Label.new()
		v.text = pair[1]
		v.add_theme_font_size_override("font_size", 35)
		row.add_child(k)
		row.add_child(v)
		left_col.add_child(row)

	# Right column
	var right_col = VBoxContainer.new()
	right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_hbox.add_child(right_col)

	var remaining_lbl = Label.new()
	remaining_lbl.text = str(snappedf(remaining,0.1)) + "g left"
	remaining_lbl.add_theme_font_size_override("font_size", 40)
	right_col.add_child(remaining_lbl)

	var fields_right = [
		["Fiber",    str(snappedf(effective.get("fiber_g",0),0.1)) + " g"],
		["Calcium",  str(snappedf(effective.get("calcium_mg",0),0.1)) + " mg"],
		["Sodium",   str(snappedf(effective.get("sodium_mg",0),0.1)) + " mg"],
		["Vit C",    str(snappedf(effective.get("vitamin_c_mg",0),0.1)) + " mg"],
		["Vit D",    str(snappedf(effective.get("vitamin_d_mcg",0),0.1)) + " mcg"],
		["B12",      str(snappedf(effective.get("vitamin_b12_mcg",0),0.1)) + " mcg"],
	]
	for pair in fields_right:
		var row = HBoxContainer.new()
		var k = Label.new()
		k.text = pair[0]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_font_size_override("font_size", 35)
		var v = Label.new()
		v.text = pair[1]
		v.add_theme_font_size_override("font_size", 35)
		row.add_child(k)
		row.add_child(v)
		right_col.add_child(row)

	add_child(info_popup)

	# ── ACTION POPUP ──
	# Position ABOVE the pressed button
	var btn_global_pos = pressed_btn.get_global_rect()
	var popup_width  = 1010.0
	var popup_height = 395.0

	# X: center on button, clamp to screen edges
	var popup_x = btn_global_pos.position.x + btn_global_pos.size.x / 2.0 - popup_width / 2.0
	popup_x = clamp(popup_x, 0, get_viewport_rect().size.x - popup_width)

	# Y: above the button with 10px gap, clamp so it doesn't go off screen top
	var popup_y = btn_global_pos.position.y - popup_height - 70
	# If it would go above the nutritional info panel (72px), push it below button instead
	var info_panel_bottom = 150.0 * (390.0 / 1170.0)
	if popup_y < info_panel_bottom + 2.0:
		popup_y = btn_global_pos.position.y + btn_global_pos.size.y + 5.0

	var action_popup = PanelContainer.new()
	action_popup.name = "ActionPopup"
	action_popup.custom_minimum_size = Vector2(popup_width, 0)
	action_popup.position = Vector2(popup_x, popup_y)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	action_popup.add_child(vbox)

	var title = Label.new()
	title.text = slot.get("name","")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 35)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	var actions = [
		# Row 1
		{"icon":"⚖️", "label":"Modify\nWeight",    "key":"modify"},
		{"icon":"🍽️", "label":"Eat\nWhole",         "key":"eat_whole"},
		{"icon":"🥄", "label":"Tablespoon\n(15mL)", "key":"tablespoon"},
		{"icon":"🫖", "label":"Teaspoon\n(5mL)",    "key":"teaspoon"},
		{"icon":"⚡", "label":"By Gram",            "key":"gram"},
		# Row 2
		{"icon":"💊", "label":"By\nMilligram",      "key":"milligram"},
		{"icon":"🥛", "label":"Glass\n(250mL)",     "key":"glass"},
		{"icon":"✕",  "label":"Close",              "key":"close"},
		{"icon":"✏️", "label":"Edit\nNutrition",    "key":"edit_nutrition"},
		{"icon":"🗑️", "label":"Throw\nOut",         "key":"throw_out"},
	]

	var grid = GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 13)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	for action in actions:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(191, 191)
		btn.text = action["icon"] + "\n" + action["label"]
		btn.add_theme_font_size_override("font_size", 30)
		if action["key"] == "close":
			# Style close differently so it stands out
			btn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			btn.pressed.connect(func():
				action_popup.queue_free()
				var ib = get_node_or_null("InfoBubble")
				if ib: ib.queue_free()
			)
		else:
			btn.pressed.connect(func(): _on_action_pressed(action["key"], slot, action_popup, density, remaining))
		grid.add_child(btn)

	var input_area = VBoxContainer.new()
	input_area.name = "InputArea"
	input_area.visible = false
	vbox.add_child(input_area)

	add_child(action_popup)
	

func _on_action_pressed(key: String, slot: Dictionary, popup: PanelContainer, density: float, remaining_g: float):
	var iid = slot.get("_iid","")
	match key:
		"eat_whole":      _eat_portion(slot, remaining_g, popup)
		"throw_out":
			_remove_slot(iid)
			popup.queue_free()
		"modify":
			_show_input_area(popup, slot, "modify", "New total weight (g):", 1, 10000, 1, density, remaining_g)
		"tablespoon":
			_show_input_area(popup, slot, "tablespoon", "How many tablespoons?", 1, 50, 1, density, remaining_g)
		"teaspoon":
			_show_input_area(popup, slot, "teaspoon", "How many teaspoons?", 1, 50, 1, density, remaining_g)
		"gram":
			_show_input_area(popup, slot, "gram", "How many grams?", 1, 2000, 1, density, remaining_g)
		"milligram":
			_show_input_area(popup, slot, "milligram", "How many milligrams?", 100, 500000, 100, density, remaining_g)
		"glass":
			_show_input_area(popup, slot, "glass", "How many glasses (250mL)?", 1, 10, 1, density, remaining_g)
		"edit_nutrition":
			_show_edit_nutrition(popup, slot)
			
# ─────────────────────────────────────────
#  EDIT NUTRITIONAL CONTENT
# ─────────────────────────────────────────

# Fields the user can edit, with display labels and units
const EDITABLE_FIELDS = [
	{"key":"calories",        "label":"Calories",       "unit":"kcal", "step":0.1,  "max":2000},
	{"key":"protein_g",       "label":"Protein",        "unit":"g",    "step":0.1,  "max":100},
	{"key":"fat_g",           "label":"Fat",            "unit":"g",    "step":0.1,  "max":100},
	{"key":"saturated_fat_g", "label":"Saturated Fat",  "unit":"g",    "step":0.1,  "max":100},
	{"key":"carbs_g",         "label":"Carbs",          "unit":"g",    "step":0.1,  "max":100},
	{"key":"sugar_g",         "label":"Sugar",          "unit":"g",    "step":0.1,  "max":100},
	{"key":"fiber_g",         "label":"Fiber",          "unit":"g",    "step":0.1,  "max":50},
	{"key":"calcium_mg",      "label":"Calcium",        "unit":"mg",   "step":1,    "max":2000},
	{"key":"sodium_mg",       "label":"Sodium",         "unit":"mg",   "step":1,    "max":5000},
	{"key":"iron_mg",         "label":"Iron",           "unit":"mg",   "step":0.1,  "max":50},
	{"key":"vitamin_c_mg",    "label":"Vitamin C",      "unit":"mg",   "step":0.1,  "max":500},
	{"key":"vitamin_d_mcg",   "label":"Vitamin D",      "unit":"mcg",  "step":0.1,  "max":100},
	{"key":"vitamin_b12_mcg", "label":"Vitamin B12",    "unit":"mcg",  "step":0.01, "max":100},
]

func _show_edit_nutrition(popup: PanelContainer, slot: Dictionary):
	var input_area = popup.find_child("InputArea", true, false)
	if not input_area: return
	for child in input_area.get_children():
		child.queue_free()
	input_area.visible = true

	var iid = slot.get("_iid","")
	var existing_overrides = fridge_overrides.get(iid, {})

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 350)
	input_area.add_child(scroll)

	var fields_vbox = VBoxContainer.new()
	fields_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(fields_vbox)

	# Title
	var title = Label.new()
	title.text = "Edit nutritional values (per 100g)"
	title.add_theme_font_size_override("font_size", 40)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	fields_vbox.add_child(title)

	fields_vbox.add_child(HSeparator.new())

	# Track spinboxes for save
	var spinboxes: Dictionary = {}

	for field_def in EDITABLE_FIELDS:
		var key   = field_def["key"]
		var lbl   = field_def["label"]
		var unit  = field_def["unit"]
		var step  = field_def["step"]
		var max_v = field_def["max"]

		# Current value — use override if exists, else json value
		var current_val = existing_overrides.get(key, slot.get(key, 0.0))
		var default_val = slot.get(key, 0.0)
		var is_overridden = existing_overrides.has(key)

		var row = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 55)
		fields_vbox.add_child(row)

		var row_lbl = Label.new()
		row_lbl.text = lbl + " (" + unit + ")"
		row_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row_lbl.add_theme_font_size_override("font_size", 40)
		if is_overridden:
			row_lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		row.add_child(row_lbl)

		var spin = SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = max_v
		spin.step = step
		spin.value = current_val
		spin.custom_minimum_size = Vector2(140, 50)
		spin.add_theme_font_size_override("font_size", 40)
		row.add_child(spin)
		spinboxes[key] = spin

		# Default hint
		var default_lbl = Label.new()
		default_lbl.text = "(" + str(snappedf(default_val, 0.01)) + ")"
		default_lbl.add_theme_font_size_override("font_size", 40)
		default_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(default_lbl)

	fields_vbox.add_child(HSeparator.new())

	# Buttons row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 10)
	fields_vbox.add_child(btn_row)

	# Save button
	var save_btn = Button.new()
	save_btn.text = "💾 Save"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.custom_minimum_size = Vector2(0, 55)
	save_btn.add_theme_font_size_override("font_size", 40)
	save_btn.pressed.connect(func():
		# Save only fields that differ from json defaults
		var overrides = {}
		for field_def in EDITABLE_FIELDS:
			var key       = field_def["key"]
			var spin      = spinboxes[key]
			var json_val  = slot.get(key, 0.0)
			var new_val   = spin.value
			# Save if different from json (tolerance: 0.001)
			if abs(new_val - json_val) > 0.001:
				overrides[key] = new_val
		if overrides.is_empty():
			fridge_overrides.erase(iid)
		else:
			fridge_overrides[iid] = overrides
		save_fridge()
		build_fridge_ui()
		popup.queue_free()
	)
	btn_row.add_child(save_btn)

	# Reset button
	var reset_btn = Button.new()
	reset_btn.text = "↺ Reset"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.custom_minimum_size = Vector2(0, 55)
	reset_btn.add_theme_font_size_override("font_size", 40)
	reset_btn.pressed.connect(func():
		fridge_overrides.erase(iid)
		save_fridge()
		build_fridge_ui()
		popup.queue_free()
	)
	btn_row.add_child(reset_btn)

# ─────────────────────────────────────────
#  HELPER — get effective food values (overrides applied)
# ─────────────────────────────────────────
func _get_effective_slot(slot: Dictionary) -> Dictionary:
	var iid = slot.get("_iid","")
	var overrides = fridge_overrides.get(iid, {})
	if overrides.is_empty(): return slot
	var effective = slot.duplicate()
	for key in overrides.keys():
		effective[key] = overrides[key]
	return effective


func _show_input_area(popup: PanelContainer, food: Dictionary, action_key: String, prompt: String, min_val: float, max_val: float, step: float, density: float, remaining_g: float):
	var input_area = popup.find_child("InputArea", true, false)
	if not input_area: return

	# Clear previous
	for child in input_area.get_children():
		child.queue_free()
	input_area.visible = true

	var lbl = Label.new()
	lbl.text = prompt
	lbl.add_theme_font_size_override("font_size", 40)
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
	preview.add_theme_font_size_override("font_size", 40)
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
	confirm_btn.add_theme_font_size_override("font_size", 40)
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
func _eat_portion(slot: Dictionary, portion_g: float, popup: PanelContainer):
	var iid       = slot.get("_iid","")
	var w         = fridge_weights.get(iid, {"total_g":100.0,"remaining_g":100.0})
	var remaining = w.get("remaining_g", 100.0)
	var total     = w.get("total_g", 100.0)
	var count     = slot.get("_count", 1)

	portion_g = min(portion_g, remaining)
	if portion_g <= 0:
		popup.queue_free()
		return

	var effective = _get_effective_slot(slot)
	var scaled    = effective.duplicate()
	var ratio     = portion_g / 100.0
	var scalable  = [
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
	for field in scalable:
		if scaled.has(field):
			scaled[field] = scaled[field] * ratio

	var new_remaining = remaining - portion_g

	if count > 1 and new_remaining > 0.1:
		# Split: reduce count on original, create new partial slot
		slot["_count"] = count - 1
		# w stays the same for the grouped slot (still full units)
		
		# Create the partial slot
		var new_iid  = _generate_iid()
		var new_slot = slot.duplicate()
		new_slot["_iid"]   = new_iid
		new_slot["_count"] = 1
		fridge_foods.append(new_slot)
		fridge_weights[new_iid] = {"total_g": remaining, "remaining_g": new_remaining}
		
	elif count == 1 and new_remaining > 0.1:
		# Single unit partially eaten
		w["remaining_g"] = new_remaining
		fridge_weights[iid] = w
		
	elif new_remaining <= 0.1 and count > 1:
		# Ate a full unit from the group
		slot["_count"] = count - 1
		
	else:
		# Last unit fully eaten
		_remove_slot(iid)

	save_fridge()
	build_fridge_ui()
	popup.queue_free()

	var main = get_tree().root.get_node("Main")
	var home = main.get_node_or_null("ContentArea/HomePage")
	if home == null:
		_log_food_to_file(scaled)
	else:
		home.log_food(scaled)

func _modify_weight(slot: Dictionary, new_total_g: float, popup: PanelContainer):
	var iid = slot.get("_iid","")
	var w   = fridge_weights.get(iid,{"total_g":100.0,"remaining_g":100.0})
	var ratio = w.get("remaining_g",100.0) / w.get("total_g",100.0) if w.get("total_g",100.0) > 0 else 1.0
	w["total_g"]     = new_total_g
	w["remaining_g"] = new_total_g * ratio
	fridge_weights[iid] = w
	save_fridge()
	build_fridge_ui()
	popup.queue_free()

func _remove_slot(iid: String):
	fridge_foods = fridge_foods.filter(func(f): return f.get("_iid","") != iid)
	fridge_weights.erase(iid)
	fridge_overrides.erase(iid)
	# Clamp page
	if current_page >= _get_total_pages():
		current_page = max(0, _get_total_pages() - 1)
	save_fridge()
	build_fridge_ui()

# ── Show nutritional info bubble ──


# ── Log food to file when HomePage not loaded ──
func _log_food_to_file(food: Dictionary):
	var today  = Time.get_date_string_from_system()
	var totals = {
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
		"quercetin_mg":0.0,"anthocyanins_mg":0.0,"resveratrol_mg":0.0,"total_polyphenols_mg":0.0
	}
	var foods = []

	if FileAccess.file_exists("user://intake.json"):
		var read_file = FileAccess.open("user://intake.json", FileAccess.READ)
		var data = JSON.parse_string(read_file.get_as_text())
		read_file.close()
		if data and data.get("date","") == today:
			var saved = data.get("totals", totals)
			for key in totals.keys():
				if saved.has(key): totals[key] = saved[key]
			foods = data.get("foods",[])

	for key in totals.keys():
		var food_key = "oxalate_mg_per_100g" if key == "oxalate_mg" else key
		totals[key] += food.get(food_key, 0.0)
	foods.append(food.get("name","Unknown"))

	var file = FileAccess.open("user://intake.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({"date": today, "totals": totals, "foods": foods}))
	file.close()

# ── Open/close shopping list ──
func _on_list_pressed():
	$Panel/ShoppingListPanel.show()
	$Panel/ShoppingListPanel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Also disable fridge buttons while list is open
	$Panel/FridgeContainer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	refresh_shopping_list()

func _on_close_list():
	$Panel/ShoppingListPanel.hide()
	$Panel/ShoppingListPanel.mouse_filter = Control.MOUSE_FILTER_STOP
	# Re-enable fridge buttons
	$Panel/FridgeContainer.mouse_filter = Control.MOUSE_FILTER_PASS


# ── Save/load fridge ──
func save_fridge():
	var file = FileAccess.open("user://fridge.json", FileAccess.WRITE)
	file.store_string(JSON.stringify({
		"fridge": fridge_foods,
		"weights":   fridge_weights,
		"overrides": fridge_overrides
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
		# Migrate old saves without _iid
		for slot in fridge_foods:
			if not slot.has("_iid"):
				slot["_iid"] = _generate_iid()
	if data.has("weights"):   fridge_weights   = data["weights"]
	if data.has("overrides"): fridge_overrides = data["overrides"]
	build_fridge_ui()

func _get_shopping_pages() -> int:
	return max(1, int(ceil(float(shopping_list.size()) / float(SHOPPING_ITEMS_PER_PAGE))))

func _rip_shopping_page():
	var start = shopping_page * SHOPPING_ITEMS_PER_PAGE
	var end   = min(start + SHOPPING_ITEMS_PER_PAGE, shopping_list.size())
	shopping_list = shopping_list.slice(0, start) + shopping_list.slice(end)
	shopping_page = clamp(shopping_page, 0, max(0, _get_shopping_pages() - 1))
	save_shopping_list()
	refresh_shopping_list()
