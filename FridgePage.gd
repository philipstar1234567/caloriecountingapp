extends Control

var shopping_page_titles: Dictionary = {}
var _shopping_undo_stack: Array = []  # max 10 snapshots
const UNDO_MAX = 10
var all_foods: Array = []
var fridge_foods: Array = []        # list of unique food dicts
var fridge_quantities: Dictionary = {} # food_id → count
var fridge_weights: Dictionary = {}   # food_id → {total_g, remaining_g}
var shopping_list: Array = []
var _long_press_active: bool = false
var fridge_overrides: Dictionary = {}
var checked_items: Dictionary = {}  # food_id → bool
var meal_items: Array = []
# Each entry: { "slot": Dictionary, "cook_method": String,
#               "cook_params": Dictionary, "weight_g": float,
#               "cooked_nutrients": Dictionary }
var meal_frequency: int = 1
var suggested_shopping: Array = []
# Each: { "food": Dictionary, "total_g": float }
var saved_meals: Array = []
# Each saved meal: {
#   "_mid": String,
#   "name": String,
#   "items": Array,         ← copy of meal_items at save time
#   "total_cooked_g": float,
#   "merged_nutrients": Dictionary  ← summed post-cook nutrients per 100g
# }
var editing_meal_mid: String = ""  # empty = new meal, set = editing existing
var _meal_tabs_built: bool = false

var meal_active_filters: Array = []
var meal_sort_ascending: bool = true
var meal_warning_filter: String = "all"
# ── Paging ──
var current_page: int = 0
const ITEMS_PER_PAGE: int = 18
const GRID_COLS: int = 3
var shopping_page: int = 0
const SHOPPING_ITEMS_PER_PAGE: int = 9

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

#Z index
const Z_INFO_BUBBLE    = 10
const Z_ACTION_POPUP   = 20
const Z_COOK_PARAMS    = 25   # shows above action popup
const Z_DETAILS_POPUP  = 15
const Z_LIMIT_WARNING  = 30   # highest — must be seen above everything

const NOTIFY_FIELDS = [
	{"key":"calories",    "label":"Calories",  "unit":"kcal"},
	{"key":"fat_g",       "label":"Fat",       "unit":"g"},
	{"key":"protein_g",   "label":"Protein",   "unit":"g"},
	{"key":"vitamin_b1_mg","label":"Vit B1",   "unit":"mg"},
	{"key":"vitamin_c_mg","label":"Vit C",     "unit":"mg"},
	{"key":"vitamin_e_mg","label":"Vit E",     "unit":"mg"},
	{"key":"potassium_mg","label":"Potassium", "unit":"mg"},
	{"key":"sodium_mg",   "label":"Salt",      "unit":"mg"},
]

const COOK_RETENTION = {
	"boil": {
		"calories":      1.00,
		"protein_g":     0.90,
		"carbs_g":       0.90,
		"fiber_g":       0.95,
		"fat_g":         1.00,
		"potassium_mg":  0.70,
		"manganese_mg":  0.80,
		"vitamin_a_mcg": 0.80,
		"vitamin_b1_mg": 0.60,
		"vitamin_b6_mg": 0.70,
		"vitamin_c_mg":  0.50,
		"vitamin_e_mg":  0.90,
		"vitamin_k1_mcg":0.90,
		# All others default to 0.85
	},
	"microwave": {
		"calories":      1.00,
		"protein_g":     1.00,
		"carbs_g":       1.00,
		"fiber_g":       1.00,
		"fat_g":         1.00,
		"potassium_mg":  1.00,
		"manganese_mg":  1.00,
		"vitamin_a_mcg": 0.95,
		"vitamin_b1_mg": 0.90,
		"vitamin_b6_mg": 0.95,
		"vitamin_c_mg":  0.85,
		"vitamin_e_mg":  1.00,
		"vitamin_k1_mcg":1.00,
	},
	"oven": {
		"calories":      1.00,
		"protein_g":     0.95,
		"carbs_g":       1.00,
		"fiber_g":       0.95,
		"fat_g":         1.00,
		"potassium_mg":  0.90,
		"manganese_mg":  0.90,
		"vitamin_a_mcg": 0.80,
		"vitamin_b1_mg": 0.70,
		"vitamin_b6_mg": 0.80,
		"vitamin_c_mg":  0.70,
		"vitamin_e_mg":  0.80,
		"vitamin_k1_mcg":0.90,
	},
	"pan": {
		"calories":      1.00,
		"protein_g":     0.95,
		"carbs_g":       1.00,
		"fiber_g":       0.90,
		"fat_g":         1.10,  # fat absorption from pan
		"potassium_mg":  0.85,
		"manganese_mg":  0.90,
		"vitamin_a_mcg": 0.75,
		"vitamin_b1_mg": 0.75,
		"vitamin_b6_mg": 0.85,
		"vitamin_c_mg":  0.65,
		"vitamin_e_mg":  0.60,
		"vitamin_k1_mcg":0.80,
	},
	"boil_water": {  # same as boil but called from the "boil" button
		"calories":      1.00,
		"protein_g":     0.90,
		"carbs_g":       0.90,
		"fiber_g":       0.95,
		"fat_g":         1.00,
		"potassium_mg":  0.70,
		"vitamin_c_mg":  0.50,
		"vitamin_b1_mg": 0.60,
		"vitamin_b6_mg": 0.70,
		"vitamin_e_mg":  0.90,
		"vitamin_k1_mcg":0.90,
	}
}

# Weight yield factors (cooked weight / raw weight)
const COOK_YIELD = {
	"boil":      1.05,  # fruits absorb slight moisture
	"microwave": 0.90,  # slight moisture loss
	"oven":      0.80,  # more moisture loss
	"pan":       0.85,
	"boil_water":1.05,
}

# Maps field key → { "unit": display string, "display_multiplier": float }
# display_multiplier converts the stored value to the display value
# For most fields it's 1.0 (show as-is)
# For fields stored in mcg that you want shown as mcg: 1.0
# This avoids any conversion — just shows the right label
const FIELD_UNITS: Dictionary = {
	# Macros — stored in g
	"calories":                {"unit": "kcal", "mult": 1.0},
	"protein_g":               {"unit": "g",    "mult": 1.0},
	"fat_g":                   {"unit": "g",    "mult": 1.0},
	"saturated_fat_g":         {"unit": "g",    "mult": 1.0},
	"monounsaturated_fat_g":   {"unit": "g",    "mult": 1.0},
	"polyunsaturated_fat_g":   {"unit": "g",    "mult": 1.0},
	"carbs_g":                 {"unit": "g",    "mult": 1.0},
	"sugar_g":                 {"unit": "g",    "mult": 1.0},
	"fiber_g":                 {"unit": "g",    "mult": 1.0},
	"lactose_g":               {"unit": "g",    "mult": 1.0},
	# Minerals — stored in mg
	"calcium_mg":              {"unit": "mg",   "mult": 1.0},
	"sodium_mg":               {"unit": "mg",   "mult": 1.0},
	"iron_mg":                 {"unit": "mg",   "mult": 1.0},
	"copper_mg":               {"unit": "mg",   "mult": 1.0},
	"magnesium_mg":            {"unit": "mg",   "mult": 1.0},
	"potassium_mg":            {"unit": "mg",   "mult": 1.0},
	"zinc_mg":                 {"unit": "mg",   "mult": 1.0},
	"phosphorus_mg":           {"unit": "mg",   "mult": 1.0},
	"manganese_mg":            {"unit": "mg",   "mult": 1.0},
	"sulfur_mg":               {"unit": "mg",   "mult": 1.0},
	"quercetin_mg":            {"unit": "mg",   "mult": 1.0},
	"anthocyanins_mg":         {"unit": "mg",   "mult": 1.0},
	"resveratrol_mg":          {"unit": "mg",   "mult": 1.0},
	"total_polyphenols_mg":    {"unit": "mg",   "mult": 1.0},
	# Trace minerals — stored in mcg
	"selenium_mcg":            {"unit": "mcg",  "mult": 1.0},
	"iodine_mcg":              {"unit": "mcg",  "mult": 1.0},
	"chromium_mcg":            {"unit": "mcg",  "mult": 1.0},
	"molybdenum_mcg":          {"unit": "mcg",  "mult": 1.0},
	# Vitamins — stored in mcg or mg depending on vitamin
	"vitamin_a_mcg":           {"unit": "mcg",  "mult": 1.0},
	"vitamin_b1_mg":           {"unit": "mg",   "mult": 1.0},
	"vitamin_b2_mg":           {"unit": "mg",   "mult": 1.0},
	"vitamin_b3_mg":           {"unit": "mg",   "mult": 1.0},
	"vitamin_b5_mg":           {"unit": "mg",   "mult": 1.0},
	"vitamin_b6_mg":           {"unit": "mg",   "mult": 1.0},
	"vitamin_b7_mcg":          {"unit": "mcg",  "mult": 1.0},
	"vitamin_b9_mcg":          {"unit": "mcg",  "mult": 1.0},
	"vitamin_b12_mcg":         {"unit": "mcg",  "mult": 1.0},
	"vitamin_c_mg":            {"unit": "mg",   "mult": 1.0},
	"vitamin_d_mcg":           {"unit": "mcg",  "mult": 1.0},
	"vitamin_e_mg":            {"unit": "mg",   "mult": 1.0},
	"vitamin_k1_mcg":          {"unit": "mcg",  "mult": 1.0},
	"vitamin_k2_mcg":          {"unit": "mcg",  "mult": 1.0},
	# Antioxidants — stored in mcg
	"beta_carotene_mcg":       {"unit": "mcg",  "mult": 1.0},
	"lycopene_mcg":            {"unit": "mcg",  "mult": 1.0},
	"lutein_zeaxanthin_mcg":   {"unit": "mcg",  "mult": 1.0},
	# Oxalate
	"oxalate_mg_per_100g":     {"unit": "mg",   "mult": 1.0},
	"soluble_fiber_pct":    {"unit": "%",  "mult": 1.0},
	"insoluble_fiber_pct":  {"unit": "%",  "mult": 1.0},
	"glycemic_index":       {"unit": "GI", "mult": 1.0},
	"resistant_starch_pct": {"unit": "%",  "mult": 1.0},
	"rapid_starch_pct":     {"unit": "%",  "mult": 1.0},
	"slow_starch_pct":      {"unit": "%",  "mult": 1.0},
}

# Fat absorption during frying (g per 100g raw)
const FRY_FAT_ABSORPTION_G = 6.0
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
	{"key":"soluble_fiber_pct",   "label":"Soluble Fiber %"},
	{"key":"insoluble_fiber_pct", "label":"Insoluble Fiber %"},
	{"key":"glycemic_index",      "label":"Glycemic Index"},
	{"key":"resistant_starch_pct","label":"Resistant Starch %"},
	{"key":"rapid_starch_pct",    "label":"Fast Starch %"},
	{"key":"slow_starch_pct",     "label":"Slow Starch %"},
]

func _ready():
	load_foods()
	load_fridge()
	load_shopping_list()
	load_saved_meals()
	$Panel/ShoppingListPanel/UndoBtn.pressed.connect(_undo_shopping)
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
	$Panel/MealPlannerPanel/VBoxContainer/FrequencyRow/SaveMealBtn.pressed.connect(_on_save_meal_pressed)
	$Panel/MealPlannerPanel/VBoxContainer/FrequencyRow/AddToShoppingBtn.pressed.connect(func():
		if meal_items.is_empty(): return
		add_suggested_to_shopping()
	)
	$Panel/TopBar/MealPlannerButton.pressed.connect(_on_meal_planner_pressed)
	$Panel/MealPlannerPanel/VBoxContainer/TopBarMP/MPCloseBtn.pressed.connect(func():
		# Clear any active editing
		meal_items.clear()
		editing_meal_mid = ""
		var banner = $Panel/MealPlannerPanel/EditingBanner
		banner.hide()
		banner.text = ""
		var name_edit = $Panel/MealPlannerPanel/VBoxContainer/FrequencyRow/SaveMealNameEdit
		name_edit.text = ""
		_refresh_meal_grid()
	# Close any open popups
		var ap = get_node_or_null("MealItemPopup")
		if ap: ap.queue_free()
		var ib = get_node_or_null("MealInfoBubble")
		if ib: ib.queue_free()
		var dp = get_node_or_null("MealDetailsPopup")
		if dp: dp.queue_free()
		$Panel/MealPlannerPanel.hide()
		$Panel/FridgeContainer.mouse_filter = Control.MOUSE_FILTER_PASS
	# Show NavBar again
		#get_tree().root.get_node("Main/NavBar").show()
	)
	var details_btn = $Panel/MealPlannerPanel/VBoxContainer/FrequencyRow/DetailsButton
	details_btn.button_down.connect(func():
		Global.any_button_pressed.emit() 
		_show_meal_details()
		)
	details_btn.button_up.connect(func():
		var existing = get_node_or_null("MealDetailsPopup")
		if existing and is_instance_valid(existing): existing.queue_free()
	)
	$Panel/MealPlannerPanel/VBoxContainer/FrequencyRow/FreqSpin.value_changed.connect(func(v):
		meal_frequency = int(v)
		_update_suggested_shopping()
	)
	$Panel/MealPlannerPanel/ClearPlateBtn.pressed.connect(_on_clear_plate)
	$Panel/MealPlannerPanel/EatPlateBtn.pressed.connect(func():
	# Create a temporary meal dict from current meal_items
		var temp_meal = {
			"name": "Current Meal",
			"items": meal_items.duplicate(true)
		}
		_eat_meal(temp_meal)
	)
	$Panel/MealPlannerPanel.hide()
	Global.any_button_pressed.connect(_on_any_button_pressed)
	_build_filter_buttons()
	_build_warning_filter_buttons()
	_connect_sort_buttons()

# ─────────────────────────────────────────
#  SWIPE DETECTION
# ─────────────────────────────────────────
func _input(event: InputEvent):
	if get_node_or_null("ActionPopup"): return
	if get_node_or_null("InfoBubble"): return
	if get_node_or_null("MealItemPopup"): return
	if get_node_or_null("MealInfoBubble"): return
	# Only track input when shopping list is hidden
	if $Panel/ShoppingListPanel.visible: return
	if $Panel/MealPlannerPanel.visible: return

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

	_apply_tab_arrow_theme(tabs)
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
		
	if active_filters.has("soluble_fiber_pct"):
		filtered = filtered.filter(func(f):
			# Only show foods where soluble fiber is majority (>=50%)
			# AND food actually has fiber
			return f.get("fiber_g", 0.0) > 0.3 and f.get("soluble_fiber_pct", 0) >= 50
		)
	if active_filters.has("insoluble_fiber_pct"):
		filtered = filtered.filter(func(f):
			return f.get("fiber_g", 0.0) > 0.3 and f.get("insoluble_fiber_pct", 0) >= 50
		)
	if active_filters.has("resistant_starch_pct"):
		filtered = filtered.filter(func(f):
			return f.get("carbs_g", 0.0) > 1.0 and f.get("resistant_starch_pct", 0) >= 10
		)
	if active_filters.has("rapid_starch_pct"):
		filtered = filtered.filter(func(f):
			return f.get("carbs_g", 0.0) > 1.0 and f.get("rapid_starch_pct", 0) >= 50
		)
	if active_filters.has("slow_starch_pct"):
		filtered = filtered.filter(func(f):
			return f.get("carbs_g", 0.0) > 1.0 and f.get("slow_starch_pct", 0) >= 40
		)
		
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

	# ── Warning sort — must come BEFORE building rows ──
	if warning_filter != "all":
		filtered.sort_custom(func(a, b):
			var order = {"avoid":2, "caution":1, "safe":0}
			var sa = order.get(_get_food_severity(a), 0)
			var sb = order.get(_get_food_severity(b), 0)
			return sa < sb if sort_ascending else sa > sb
		)
		
	for food in filtered:
		vbox.add_child(make_browse_row(food))
		

# ── One row in the browse list ──
func make_browse_row(food: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 60)

	var severity = _get_food_severity(food)
	if severity != "safe":
		var badge = Label.new()
		badge.text = "⛔" if severity == "avoid" else "⚠️"
		badge.add_theme_font_size_override("font_size", 24)
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
		var val_vbox = VBoxContainer.new()  # ← VBox instead of inline text
		val_vbox.add_theme_constant_override("separation", 2)
		row.add_child(val_vbox)
		for key in active_filters:
			var val    = food.get(key, 0.0)
			var lbl_text = _get_filter_label(key) + ": " + _format_field_value(key, val)
			var val_lbl = Label.new()
			val_lbl.text = lbl_text
			val_lbl.add_theme_font_size_override("font_size", 30)
			val_vbox.add_child(val_lbl)
	else:
		var amount = Label.new()
		amount.text = str(food.get("oxalate_mg_per_100g",0)) + "mg ox"
		row.add_child(amount)

		var warnings = Global.get_warnings(food)
		if warnings.size() > 0:
			var info_btn = Button.new()
			info_btn.text = "ℹ️"
			info_btn.flat = true
			info_btn.custom_minimum_size = Vector2(44, 44)
			info_btn.add_theme_font_size_override("font_size", 22)
			info_btn.pressed.connect(func():
				Global.any_button_pressed.emit()
				_show_warning_detail_panel(food)
			)
			row.add_child(info_btn)

	var btn = Button.new()
	btn.text = "+ List"
	btn.pressed.connect(func(): add_to_shopping_list(food))
	row.add_child(btn)

	return row

func _generate_sid() -> String:
	return "s_" + str(Time.get_ticks_usec())

# ── Add food to shopping list ──
func add_to_shopping_list(food: Dictionary):
	_shopping_snapshot() 
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
	_shopping_snapshot()
	for entry in shopping_list:
		if entry["_sid"] == sid:
			entry["qty"] = entry.get("qty", 1) + 1
			break
	save_shopping_list()
	refresh_shopping_list()

func decrement_shopping_entry(sid: String):
	_shopping_snapshot()
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
	_shopping_snapshot()
	for entry in shopping_list:
		if entry["_sid"] == sid:
			entry["_checked"] = checked
		if checked:
			var qty = entry.get("qty", 1)
			add_to_fridge_multi(entry["food"], qty)
			entry["_fridge_qty_added"] = qty   # ← record how many we added
		else:
			# Reverse: remove from fridge what was added
			var qty_to_remove = entry.get("_fridge_qty_added", entry.get("qty", 1))
			_remove_from_fridge_by_food_id(entry["food"].get("id",""), qty_to_remove)
			entry["_fridge_qty_added"] = 0
	save_shopping_list()
	# Do NOT call refresh_shopping_list() here — 
	# we handle the visual change directly in the row

func _remove_from_fridge_by_food_id(fid: String, qty: int):
	var removed = 0
	var to_remove: Array = []

	# Find matching slots — prefer ones that are untouched (full, no override)
	for slot in fridge_foods:
		if removed >= qty: break
		if slot.get("id","") != fid: continue
		var iid       = slot.get("_iid","")
		var w         = fridge_weights.get(iid, {})
		var remaining = w.get("remaining_g", 0.0)
		var total     = w.get("total_g", 100.0)
		var count     = slot.get("_count", 1)
		var has_override = fridge_overrides.has(iid)

		# Only reverse slots that haven't been partially eaten or edited
		if has_override: continue
		if abs(remaining - total) > 0.5: continue  # partially eaten — skip

		if count > qty - removed:
			slot["_count"] = count - (qty - removed)
			removed = qty
		else:
			removed += count
			to_remove.append(iid)

	for iid in to_remove:
		fridge_foods = fridge_foods.filter(func(f): return f.get("_iid","") != iid)
		fridge_weights.erase(iid)
		fridge_overrides.erase(iid)

	if current_page >= _get_total_pages():
		current_page = max(0, _get_total_pages() - 1)
	save_fridge()
	build_fridge_ui()

func refresh_shopping_list():
	var paper_vbox = $Panel/ShoppingListPanel/VBoxContainer/ListPaperArea/PaperScrollContainer/PaperItemsVBox
	for child in paper_vbox.get_children():
		child.queue_free()

# ── Page title row ──
	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	paper_vbox.add_child(title_row)

	var prefix = Label.new()
	prefix.text = "Title: "
	prefix.add_theme_font_size_override("font_size", 69)
	prefix.add_theme_color_override("font_color", Color(0.4, 0.3, 0.2))
	title_row.add_child(prefix)

	var title_edit = LineEdit.new()
	title_edit.placeholder_text = "e.g. Mom's list, Tikka Masala recipe..."
	title_edit.text = shopping_page_titles.get(str(shopping_page), "")
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.add_theme_font_size_override("font_size", 59)
	var captured_page = shopping_page
	title_edit.text_changed.connect(func(new_text):
		shopping_page_titles[str(captured_page)] = new_text
		save_shopping_list()
	)
	title_row.add_child(title_edit)

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
		row.custom_minimum_size = Vector2(0, 110)
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
			var uncheck_btn = Button.new()
			uncheck_btn.text = "↩️"
			uncheck_btn.flat = true
			uncheck_btn.custom_minimum_size = Vector2(60, 60)
			uncheck_btn.add_theme_font_size_override("font_size", 70)
			uncheck_btn.tooltip_text = "Uncheck — I haven't bought this yet"
			var captured_sid = sid
			uncheck_btn.pressed.connect(func():
				check_shopping_entry(captured_sid, false)   # ← handles fridge reversal
				refresh_shopping_list()
			)
			row.add_child(uncheck_btn)
		else:
			# Unchecked — show CheckBox
			var cb = CheckBox.new()
			cb.text = display_text
			cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cb.add_theme_font_size_override("font_size", 70)
			if entry.get("_suggested", false):
				var suggested_g = entry.get("_suggested_g", 0.0)
				cb.text = display_text + " (" + str(snappedf(suggested_g, 0.1)) + "g)"
				cb.add_theme_color_override("font_color",         Color(0.7, 0.1, 0.1))
				cb.add_theme_color_override("font_color_hover",   Color(0.7, 0.1, 0.1))
				cb.add_theme_color_override("font_color_pressed", Color(0.7, 0.1, 0.1))
			else:
				cb.add_theme_color_override("font_color",         Color(0.08, 0.15, 0.35))
				cb.add_theme_color_override("font_color_hover",   Color(0.08, 0.15, 0.35))
				cb.add_theme_color_override("font_color_pressed", Color(0.08, 0.15, 0.35))
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
		"page": shopping_page,
		"titles": shopping_page_titles
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
	shopping_page_titles = data.get("titles", {})

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
	var throw = $Panel/ThrowBtn
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

# Empty warning
		if remaining <= 0.0:
			var warn_bg = ColorRect.new()
			warn_bg.color = Color(0.9, 0.3, 0.1, 0.92)
			warn_bg.size = Vector2(container.custom_minimum_size.x, 40)
			warn_bg.position = Vector2(0, container.custom_minimum_size.y - 40)
			container.add_child(warn_bg)

			var warn_lbl = Label.new()
			warn_lbl.text = "⚠️ 0 g\nleft"
			warn_lbl.add_theme_font_size_override("font_size", 40)
			warn_lbl.add_theme_color_override("font_color", Color.WHITE)
			warn_lbl.position = Vector2(4, container.custom_minimum_size.y - 40)
			warn_lbl.custom_minimum_size = Vector2(container.custom_minimum_size.x - 8, 40)
			container.add_child(warn_lbl)

	# Fill empty slots with invisible placeholders to keep grid shape
	var empty_slots = ITEMS_PER_PAGE - page_items.size()
	for i in range(empty_slots):
		var placeholder = Control.new()
		placeholder.custom_minimum_size = Vector2(110,110)
		fridge.add_child(placeholder)

	var throw_btn = Button.new()
	throw_btn.text = "🗑 Throw empty items out"
	throw_btn.add_theme_font_size_override("font_size", 26)
	throw_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	throw_btn.custom_minimum_size = Vector2(0, 60)
	throw_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	throw_btn.alignment = VERTICAL_ALIGNMENT_CENTER
	throw_btn.pressed.connect(func(): _throw_out_current_page())
	throw.add_child(throw_btn)

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

func _throw_out_current_page():
	var existing = get_node_or_null("ThrowOutConfirm")
	if existing: existing.queue_free()

	var backdrop = ColorRect.new()
	backdrop.name = "ThrowOutConfirm"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.6)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.z_index = 100
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_LEFT)
	panel.custom_minimum_size = Vector2(900, 350)
	backdrop.add_child(panel)
	panel.position.x += 130
	panel.position.y -= 150

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 80)
	panel.add_child(vbox)

	var msg = Label.new()
	msg.text = " Are you sure you want to throw\n out all the empty items on this page?"
	msg.add_theme_font_size_override("font_size", 48)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(msg)

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var yes_btn = Button.new()
	yes_btn.text = "Yes, throw out"
	yes_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	yes_btn.custom_minimum_size = Vector2(0, 130)
	yes_btn.add_theme_font_size_override("font_size", 48)
	yes_btn.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	yes_btn.pressed.connect(func():
		backdrop.queue_free()
		_do_throw_out_current_page()
	)
	btn_row.add_child(yes_btn)

	var no_btn = Button.new()
	no_btn.text = "No, keep them"
	no_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	no_btn.custom_minimum_size = Vector2(0, 130)
	no_btn.add_theme_font_size_override("font_size", 48)
	no_btn.pressed.connect(func(): backdrop.queue_free())
	btn_row.add_child(no_btn)

func _do_throw_out_current_page():
	var start = current_page * ITEMS_PER_PAGE
	var end   = min(start + ITEMS_PER_PAGE, fridge_foods.size())
	var page_items = fridge_foods.slice(start, end)
	for slot in page_items:
		var iid = slot.get("_iid","")
		var w   = fridge_weights.get(iid, {})
		if w.get("remaining_g", 1.0) <= 0.0:
			fridge_foods = fridge_foods.filter(func(f): return f.get("_iid","") != iid)
			fridge_weights.erase(iid)
			fridge_overrides.erase(iid)
	if current_page >= _get_total_pages():
		current_page = max(0, _get_total_pages() - 1)
	save_fridge()
	build_fridge_ui()

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
	# ── INFO POPUP with page toggle ──
	var info_popup = PanelContainer.new()
	info_popup.name = "InfoBubble"
	info_popup.set_anchor_and_offset(SIDE_LEFT,   0, 0)
	info_popup.set_anchor_and_offset(SIDE_RIGHT,  1, 0)
	info_popup.set_anchor_and_offset(SIDE_TOP,    0, 0)
	info_popup.set_anchor_and_offset(SIDE_BOTTOM, 0, 215 * (390.0/1170.0))
	info_popup.z_index = Z_INFO_BUBBLE

	var stack = VBoxContainer.new()
	info_popup.add_child(stack)

	# Page toggle row
	var toggle_row = HBoxContainer.new()
	stack.add_child(toggle_row)

	var per100_btn = Button.new()
	per100_btn.text = "Per 100g"
	per100_btn.flat = false
	per100_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_row.add_child(per100_btn)

	var total_btn = Button.new()
	total_btn.text = "Total (" + str(snappedf(remaining,0.1)) + "g)"
	total_btn.flat = true
	total_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_row.add_child(total_btn)

	# Content area — rebuilt on toggle
	var content_hbox = HBoxContainer.new()
	content_hbox.add_theme_constant_override("separation", 20)
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stack.add_child(content_hbox)

	var _show_page = func(per_100g: bool):
		per100_btn.flat = not per_100g
		total_btn.flat  = per_100g
		for child in content_hbox.get_children(): child.queue_free()

		var multiplier = 1.0 if per_100g else (remaining / 100.0)

		var left_col = VBoxContainer.new()
		left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_hbox.add_child(left_col)

		var food_title_lbl = Label.new()
		food_title_lbl.text = slot.get("name","") + \
			(" ✏️" if has_override else "") + \
			(" — per 100g" if per_100g else " — " + str(snappedf(remaining,0.1)) + "g total")
		food_title_lbl.add_theme_font_size_override("font_size", 35)
		food_title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		left_col.add_child(food_title_lbl)

		var fields_left = [
			["Calories", "calories",   "kcal"],
			["Protein",  "protein_g",  "g"],
			["Fat",      "fat_g",      "g"],
			["Sat.",     "saturated_fat_g","g"],
			["Carbs",    "carbs_g",    "g"],
			["Sugar",    "sugar_g",    "g"],
		]
		for pair in fields_left:
			var r = HBoxContainer.new()
			var k = Label.new(); k.text = pair[0]
			k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			k.add_theme_font_size_override("font_size", 30)
			var v = Label.new()
			v.text = str(snappedf(effective.get(pair[1],0.0) * multiplier, 0.1)) + " " + pair[2]
			v.add_theme_font_size_override("font_size", 30)
			r.add_child(k); r.add_child(v)
			left_col.add_child(r)

		var right_col = VBoxContainer.new()
		right_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content_hbox.add_child(right_col)

		var rem_lbl = Label.new()
		rem_lbl.text = str(snappedf(remaining,0.1)) + "g left"
		rem_lbl.add_theme_font_size_override("font_size", 35)
		right_col.add_child(rem_lbl)

		var fields_right = [
			["Fiber",   "fiber_g",        "g"],
			["Calcium", "calcium_mg",     "mg"],
			["Sodium",  "sodium_mg",      "mg"],
			["Vit C",   "vitamin_c_mg",   "mg"],
			["Vit D",   "vitamin_d_mcg",  "mcg"],
			["B12",     "vitamin_b12_mcg","mcg"],
		]
		for pair in fields_right:
			var r = HBoxContainer.new()
			var k = Label.new(); k.text = pair[0]
			k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			k.add_theme_font_size_override("font_size", 30)
			var v = Label.new()
			v.text = str(snappedf(effective.get(pair[1],0.0) * multiplier, 0.1)) + " " + pair[2]
			v.add_theme_font_size_override("font_size", 30)
			r.add_child(k); r.add_child(v)
			right_col.add_child(r)

	_show_page.call(true)   # default: per 100g
	per100_btn.pressed.connect(func(): _show_page.call(true))
	total_btn.pressed.connect(func(): _show_page.call(false))

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

	add_child(info_popup)
	info_popup.z_index = Z_INFO_BUBBLE
	
	var action_popup = PanelContainer.new()
	action_popup.name = "ActionPopup"
	action_popup.mouse_filter = Control.MOUSE_FILTER_STOP
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
	
	add_child(action_popup)

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
	action_popup.z_index = Z_ACTION_POPUP

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
		# Partially ate one unit from a group — split it off
		slot["_count"] = count - 1
		var new_iid  = _generate_iid()
		var new_slot = slot.duplicate()
		new_slot["_iid"]   = new_iid
		new_slot["_count"] = 1
		fridge_foods.append(new_slot)
		fridge_weights[new_iid] = {"total_g": remaining, "remaining_g": new_remaining}

	elif count > 1 and new_remaining <= 0.1:
		# Fully ate one unit from a group
		slot["_count"] = count - 1
		w["remaining_g"] = 0.0
		fridge_weights[iid] = w

	elif count == 1 and new_remaining > 0.1:
		# Single unit partially eaten
		w["remaining_g"] = new_remaining
		fridge_weights[iid] = w

	else:
		# Single unit fully eaten — show 0g warning, no removal
		w["remaining_g"] = 0.0
		fridge_weights[iid] = w

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
	var w   = fridge_weights.get(iid, {"total_g":100.0,"remaining_g":100.0})
	var old_remaining = w.get("remaining_g", 100.0)
	var old_total     = w.get("total_g", 100.0)

	# If food is at 0g, treat modify as a full restock to new weight
	if old_remaining <= 0.0:
		w["total_g"]     = new_total_g
		w["remaining_g"] = new_total_g
	else:
		# Scale remaining proportionally as before
		var ratio = old_remaining / old_total if old_total > 0 else 1.0
		w["total_g"]     = new_total_g
		w["remaining_g"] = snappedf(new_total_g * ratio, 0.1)

	fridge_weights[iid] = w
	save_fridge()
	build_fridge_ui()
	popup.queue_free()
	var ib = get_node_or_null("InfoBubble")
	if ib: ib.queue_free()
	_show_weight_notification(slot.get("name","Food"), old_total, new_total_g)
	popup.queue_free()

func _show_weight_notification(food_name: String, old_g: float, new_g: float):
	var existing = get_node_or_null("WeightNotification")
	if existing: existing.queue_free()

	var panel = PanelContainer.new()
	panel.name = "WeightNotification"
	panel.z_index = Z_LIMIT_WARNING
	panel.set_anchor_and_offset(SIDE_LEFT,  0, 10)
	panel.set_anchor_and_offset(SIDE_RIGHT, 1, -10)
	panel.set_anchor_and_offset(SIDE_TOP,   0, 10)
	panel.set_anchor_and_offset(SIDE_BOTTOM,0, 90)
	panel.modulate.a = 0.0

	var lbl = Label.new()
	lbl.text = "⚖️ " + food_name + ": " + str(snappedf(old_g,0.1)) + "g → " + str(snappedf(new_g,0.1)) + "g"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	panel.add_child(lbl)
	add_child(panel)

	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(4.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): panel.queue_free())

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
	_shopping_snapshot()
	var start = shopping_page * SHOPPING_ITEMS_PER_PAGE
	var end   = min(start + SHOPPING_ITEMS_PER_PAGE, shopping_list.size())
	shopping_list = shopping_list.slice(0, start) + shopping_list.slice(end)
	shopping_page = clamp(shopping_page, 0, max(0, _get_shopping_pages() - 1))
	save_shopping_list()
	refresh_shopping_list()

func _on_meal_planner_pressed():
	$Panel/MealPlannerPanel.show()
	$Panel/MealPlannerPanel.mouse_filter = Control.MOUSE_FILTER_STOP
	$Panel/FridgeContainer.mouse_filter  = Control.MOUSE_FILTER_IGNORE
	# Hide NavBar
	#get_tree().root.get_node("Main/NavBar").hide()

	if not _meal_tabs_built:
		_build_meal_tabs()
		_meal_tabs_built = true

	# Always default to Fruits tab on open
	var tabs = $Panel/MealPlannerPanel/VBoxContainer/TabContainer
	var fruits_idx = _get_fruits_tab_index()
	tabs.current_tab = fruits_idx
	_refresh_meal_tab()
	_refresh_my_meals_tab()
	_refresh_meal_grid()

func _get_fruits_tab_index() -> int:
	var tabs = $Panel/MealPlannerPanel/VBoxContainer/TabContainer
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i).to_lower() == "fruits":
			return i
	return 2  # fallback

func _build_meal_tabs():
	var tabs = $Panel/MealPlannerPanel/VBoxContainer/TabContainer
	for child in tabs.get_children():
		child.queue_free()

	# My Meals — always first
	var my_meals_scroll = ScrollContainer.new()
	my_meals_scroll.name = "My Meals"
	var my_meals_vbox = VBoxContainer.new()
	my_meals_vbox.name = "MyMealsVBox"
	my_meals_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	my_meals_scroll.add_child(my_meals_vbox)
	tabs.add_child(my_meals_scroll)

# Tab 1: From Fridge
	var fridge_scroll = ScrollContainer.new()
	fridge_scroll.name = "From Fridge"
	var fridge_vbox = VBoxContainer.new()
	fridge_vbox.name = "FromFridgeVBox"
	fridge_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fridge_scroll.add_child(fridge_vbox)
	tabs.add_child(fridge_scroll)

	# Food category tabs
	var categories = []
	for food in all_foods:
		var cat = food.get("category","other")
		if not categories.has(cat):
			categories.append(cat)

	for cat in categories:
		var scroll = ScrollContainer.new()
		scroll.name = cat.capitalize()
		var vbox = VBoxContainer.new()
		vbox.name = cat.capitalize() + "Vbox"
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(vbox)
		tabs.add_child(scroll)

	_apply_tab_arrow_theme(tabs)
	# Connect signal once
	tabs.tab_changed.connect(func(idx):
		Global.any_button_pressed.emit()
		_on_meal_tab_changed(idx)
	)
	_build_meal_filter_buttons()
	


func _build_meal_filter_buttons():
	var row = $Panel/MealPlannerPanel/VBoxContainer/FilterPanel/VBoxContainer/FilterScrollH/FilterButtonsRow
	if not row: return
	for child in row.get_children():
		child.queue_free()

	for opt in FILTER_OPTIONS:
		var btn = Button.new()
		btn.text = opt["label"]
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(0, 50)
		btn.add_theme_font_size_override("font_size", 40)
		btn.toggled.connect(func(pressed):
			Global.any_button_pressed.emit()
			_on_meal_filter_toggled(opt["key"], pressed, btn)
		)
		row.add_child(btn)

	# Sort buttons
	var sort_row = $Panel/MealPlannerPanel/VBoxContainer/FilterPanel/VBoxContainer/SortRow
	if sort_row:
		sort_row.get_node("SortAscBtn").pressed.connect(func():
			Global.any_button_pressed.emit()
			meal_sort_ascending = true
			_update_meal_filter_label()
			_refresh_meal_tab()
		)
		sort_row.get_node("SortDescBtn").pressed.connect(func():
			Global.any_button_pressed.emit()
			meal_sort_ascending = false
			_update_meal_filter_label()
			_refresh_meal_tab()
		)

	# Warning filter row
	var warn_row = $Panel/MealPlannerPanel/VBoxContainer/FilterPanel/VBoxContainer/WarningFilterRow
	if not warn_row: return
	for child in warn_row.get_children():
		child.queue_free()

	var warn_options = [
		{"label":"All",     "key":"all"},
		{"label":"⚠️ Only", "key":"caution"},
		{"label":"⛔ Only", "key":"avoid"},
		{"label":"✅ Safe", "key":"none"},
	]
	for opt in warn_options:
		var btn = Button.new()
		btn.text = opt["label"]
		btn.toggle_mode = true
		btn.button_pressed = (opt["key"] == meal_warning_filter)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 50)
		btn.add_theme_font_size_override("font_size", 35)
		var key = opt["key"]
		btn.toggled.connect(func(pressed):
			if pressed:
				Global.any_button_pressed.emit()
				meal_warning_filter = key
				_update_meal_filter_label()
				for child in warn_row.get_children():
					if child != btn: child.button_pressed = false
				_refresh_meal_tab()
		)
		warn_row.add_child(btn)

func _on_meal_tab_changed(idx: int):
	var tabs = $Panel/MealPlannerPanel/VBoxContainer/TabContainer
	var tab_name = tabs.get_tab_title(idx)
	match tab_name:
		"My Meals":    _refresh_my_meals_tab()
		"From Fridge": _refresh_from_fridge_tab()
		_:             _refresh_meal_tab()

func _refresh_meal_tab():
	var tabs = $Panel/MealPlannerPanel/VBoxContainer/TabContainer
	var scroll = tabs.get_current_tab_control()
	if not scroll: return
	if scroll.get_child_count() == 0: return
	var vbox = scroll.get_child(0)
	if not vbox: return
	for child in vbox.get_children():
		child.queue_free()

	var cat = tabs.get_tab_title(tabs.current_tab).to_lower().strip_edges()
	if cat == "my meals": return

	var search_text = ""
	var search_bar = $Panel/MealPlannerPanel/VBoxContainer/TopBarMP/MPSearchBar
	if search_bar: search_text = search_bar.text.to_lower()

	var filtered = all_foods.filter(func(f):
		if f.get("category","") != cat: return false
		if not search_text.is_empty() and not f.get("name","").to_lower().contains(search_text):
			return false
		return true
	)

	# Nutrient filters
	if not meal_active_filters.is_empty():
		filtered = filtered.filter(func(f):
			for key in meal_active_filters:
				if f.get(key, 0.0) <= 0: return false
			return true
		)

	# Warning filter
	if meal_warning_filter != "all":
		filtered = filtered.filter(func(f):
			var severity = _get_food_severity(f)
			match meal_warning_filter:
				"avoid":   return severity == "avoid"
				"caution": return severity == "caution"
				"none":    return severity == "safe"
			return true
		)

	# Sort
	if not meal_active_filters.is_empty():
		var sort_key = "calories" if meal_active_filters.size() > 1 else meal_active_filters[0]
		filtered.sort_custom(func(a, b):
			return a.get(sort_key,0.0) < b.get(sort_key,0.0) if meal_sort_ascending \
				else a.get(sort_key,0.0) > b.get(sort_key,0.0)
		)

	for food in filtered:
		vbox.add_child(_make_meal_browse_row(food))

func _refresh_my_meals_tab():
	var tabs = $Panel/MealPlannerPanel/VBoxContainer/TabContainer
	if tabs.get_tab_count() == 0: return
	var scroll = tabs.get_tab_control(0)
	if not scroll: return
	var vbox = scroll.find_child("MyMealsVBox", true, false)
	if not vbox: return
	for child in vbox.get_children():
		child.queue_free()
	if saved_meals.is_empty():
		var empty_lbl = Label.new()
		empty_lbl.text = "No saved meals yet.\nBuild a meal and tap 'Add to My Meals'."
		empty_lbl.add_theme_font_size_override("font_size", 40)
		empty_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		vbox.add_child(empty_lbl)
		return
	for meal in saved_meals:
		vbox.add_child(_make_saved_meal_row(meal))

func _make_saved_meal_row(meal: Dictionary) -> VBoxContainer:
	var card = VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)

	var panel = PanelContainer.new()
	var inner = VBoxContainer.new()
	inner.add_theme_constant_override("separation", 6)
	panel.add_child(inner)
	card.add_child(panel)

	# Name + total weight
	var name_lbl = Label.new()
	name_lbl.text = meal.get("name","Meal") + \
		"  ·  " + str(meal.get("total_cooked_g",0.0)) + "g total"
	name_lbl.add_theme_font_size_override("font_size", 40)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner.add_child(name_lbl)

	# Ingredient summary
	var items = meal.get("items",[])
	var ingredients_text = ""
	for entry in items:
		var method_icons = {
			"raw":"🥗","boil":"💧","microwave":"📡",
			"oven":"🔥","pan":"🍳","boil_water":"♨️"
		}
		var icon      = method_icons.get(entry.get("cook_method","raw"),"🥗")
		var raw_g     = entry.get("weight_g", 100.0)
		var method    = entry.get("cook_method","raw")
		var yf        = COOK_YIELD.get(method, 1.0)
		var cooked_g  = snappedf(raw_g * yf, 0.1)
		var food_name = entry.get("food",{}).get("name","?")
		
		if method == "raw":
			ingredients_text += icon + " " + food_name + " " + str(raw_g) + "g  "
		else:
			ingredients_text += icon + " " + food_name + \
				" " + str(raw_g) + "g→" + str(cooked_g) + "g  "
	var ing_lbl = Label.new()
	ing_lbl.text = ingredients_text.strip_edges()
	ing_lbl.add_theme_font_size_override("font_size", 40)
	ing_lbl.add_theme_color_override("font_color", Color(0.6,0.6,0.6))
	ing_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	inner.add_child(ing_lbl)

	# Key nutrients summary
	var merged = meal.get("merged_nutrients",{})
	var nutrients_lbl = Label.new()
	nutrients_lbl.text = str(snappedf(merged.get("calories",0),0.1)) + " kcal  |  " + \
		"P: " + str(snappedf(merged.get("protein_g",0),0.1)) + "g  |  " + \
		"F: " + str(snappedf(merged.get("fat_g",0),0.1)) + "g  |  " + \
		"C: " + str(snappedf(merged.get("carbs_g",0),0.1)) + "g  (per 100g)"
	nutrients_lbl.add_theme_font_size_override("font_size", 40)
	inner.add_child(nutrients_lbl)

	# Buttons row
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 40)
	inner.add_child(btn_row)

	# + Fridge button
	var fridge_btn = Button.new()
	fridge_btn.text = "🧊 + Fridge"
	fridge_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fridge_btn.custom_minimum_size = Vector2(0, 55)
	fridge_btn.add_theme_font_size_override("font_size", 40)
	fridge_btn.pressed.connect(func(): _add_meal_to_fridge(meal))
	btn_row.add_child(fridge_btn)

	# Eat button — only show if meal has source fridge items
	var has_fridge_sources = meal.get("items",[]).any(func(e): return e.has("_source_iid"))
	if has_fridge_sources:
		var eat_btn = Button.new()
		eat_btn.text = "🍽 Eat"
		eat_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eat_btn.custom_minimum_size = Vector2(0, 55)
		eat_btn.add_theme_font_size_override("font_size", 40)
		eat_btn.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
		eat_btn.pressed.connect(func(): _eat_meal(meal))
		btn_row.add_child(eat_btn)

	# Edit button
	var edit_btn = Button.new()
	edit_btn.text = "✏️ Edit"
	edit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit_btn.custom_minimum_size = Vector2(0, 55)
	edit_btn.add_theme_font_size_override("font_size", 40)
	edit_btn.pressed.connect(func():
		Global.any_button_pressed.emit()
		_edit_saved_meal(meal)
	)
	btn_row.add_child(edit_btn)

	# Delete button
	var del_btn = Button.new()
	del_btn.text = "🗑"
	del_btn.custom_minimum_size = Vector2(55, 55)
	del_btn.add_theme_font_size_override("font_size", 40)
	del_btn.add_theme_color_override("font_color", Color(0.9,0.3,0.3))
	del_btn.pressed.connect(func(): _delete_saved_meal(meal.get("_mid","")))
	btn_row.add_child(del_btn)

	# Separator
	card.add_child(HSeparator.new())
	return card

func _make_meal_browse_row(food: Dictionary) -> HBoxContainer:
	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 60)
	row.add_theme_constant_override("separation", 8)

	# Icon — same as shopping list
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(50, 50)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var path = "res://images/" + food.get("id","") + ".png"
	if ResourceLoader.exists(path): icon.texture = load(path)
	row.add_child(icon)

	var name_lbl = Label.new()
	name_lbl.text = food.get("name","")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	# Show active filter values
	if not meal_active_filters.is_empty():
		var val_vbox = VBoxContainer.new()
		val_vbox.add_theme_constant_override("separation", 2)
		row.add_child(val_vbox)
		for key in meal_active_filters:
			var val    = food.get(key, 0.0)
			var lbl_text = _get_filter_label(key) + ": " + _format_field_value(key, val)
			var val_lbl = Label.new()
			val_lbl.text = lbl_text
			val_lbl.add_theme_font_size_override("font_size", 30)
			val_vbox.add_child(val_lbl)
	else:
		var ox_lbl = Label.new()
		ox_lbl.text = str(food.get("oxalate_mg_per_100g",0)) + "mg ox"
		row.add_child(ox_lbl)

	# Warning badge
	var severity = _get_food_severity(food)
	if severity != "safe":
		var badge = Label.new()
		badge.text = "⛔" if severity == "avoid" else "⚠️"
		badge.add_theme_font_size_override("font_size", 36)
		row.add_child(badge)

		var warnings = Global.get_warnings(food)
		if warnings.size() > 0:
			var info_btn = Button.new()
			info_btn.text = "ℹ️"
			info_btn.flat = true
			info_btn.custom_minimum_size = Vector2(44, 44)
			info_btn.add_theme_font_size_override("font_size", 36)
			info_btn.pressed.connect(func():
				Global.any_button_pressed.emit()
				_show_warning_detail_panel(food)
			)
			row.add_child(info_btn)

	var add_btn = Button.new()
	add_btn.text = "+ Meal"
	add_btn.pressed.connect(func():
		Global.any_button_pressed.emit()
		_add_to_meal(food))
	row.add_child(add_btn)
	return row

func _add_to_meal(food: Dictionary):
	if meal_items.size() >= 12:
		_show_limit_warning()
		return
	var entry = {
		"food":             food.duplicate(),
		"cook_method":      "raw",
		"cook_params":      {},
		"weight_g":         100.0,
		"cooked_nutrients": food.duplicate()
	}
	meal_items.append(entry)
	_refresh_meal_grid()
	_update_suggested_shopping()

func _show_limit_warning():
	var existing = get_node_or_null("LimitWarning")
	if existing: existing.queue_free()

	var lbl = Label.new()
	lbl.text = "⚠️ Max 12 items"
	lbl.add_theme_font_size_override("font_size", 40)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER

	var panel = PanelContainer.new()
	panel.name = "LimitWarning"
	panel.custom_minimum_size = Vector2(280, 100)
	panel.modulate.a = 0.0
	panel.add_child(lbl)
	add_child(panel)
	panel.z_index = Z_LIMIT_WARNING
	# Center it after adding to scene tree
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position.y += 100

	# Fade in then fade out using a tween
	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.4)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func():
		if is_instance_valid(panel): panel.queue_free()
	)
	
func _refresh_meal_grid():
	var grid = $Panel/MealPlannerPanel/VBoxContainer/MealArea/MealGridContainer
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 60)
	grid.add_theme_constant_override("v_separation", 40)
	for child in grid.get_children():
		child.queue_free()
	var page_size = 12  # 3 cols × 4 rows
	var start = 0       # add paging later if needed
	var end   = min(start + page_size, meal_items.size())
	
	for i in range(meal_items.size()):
		var entry = meal_items[i]
		var food  = entry["food"]

		var container = Control.new()
		container.custom_minimum_size = Vector2(200, 200)

		var btn = Button.new()
		btn.custom_minimum_size = Vector2(200, 200)
		btn.size = Vector2(200, 200)
		btn.position = Vector2(0, 0)
		btn.tooltip_text = food.get("name","") + "\n" + \
			entry.get("cook_method","raw") + "\n" + \
			str(entry.get("weight_g",100.0)) + "g"

		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(200,200)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path = "res://images/" + food.get("id","") + ".png"
		if ResourceLoader.exists(path): icon.texture = load(path)
		btn.add_child(icon)

		# Cook method badge
		if entry.get("cook_method","raw") != "raw":
			var method_icons = {
				"boil":"💧","microwave":"📡","oven":"🔥",
				"pan":"🍳","boil_water":"♨️"
			}
			var cook_lbl = Label.new()
			cook_lbl.text = method_icons.get(entry["cook_method"],"🍳")
			cook_lbl.add_theme_font_size_override("font_size", 40)
			cook_lbl.position = Vector2(2, 2)
			container.add_child(cook_lbl)

		var timer = Timer.new()
		timer.wait_time = 1.4
		timer.one_shot  = true
		btn.add_child(timer)

		var idx = i
		timer.timeout.connect(func():
			_long_press_active = true
			_open_meal_dual_popup(entry, idx, btn)
		)
		btn.gui_input.connect(func(event):
			_handle_meal_input(event, entry, idx, timer)
		)
		container.add_child(btn)
		grid.add_child(container)

func _handle_meal_input(event: InputEvent, entry: Dictionary, idx: int, timer: Timer):
	var is_press   = false
	var is_release = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_press   = event.pressed
		is_release = not event.pressed
	elif event is InputEventScreenTouch:
		is_press   = event.pressed
		is_release = not event.pressed

	if is_press:
		# Close any existing meal popups immediately
		var existing_action = get_node_or_null("MealItemPopup")
		if existing_action: existing_action.queue_free()
		var existing_info = get_node_or_null("MealInfoBubble")
		if existing_info: existing_info.queue_free()
		_long_press_active = false
		timer.start()

	if is_release:
		timer.stop()

func _open_meal_dual_popup(entry: Dictionary, idx: int, pressed_btn: Button):
	# Clean up existing
	var existing_action = get_node_or_null("MealItemPopup")
	if existing_action: existing_action.queue_free()
	var existing_info = get_node_or_null("MealInfoBubble")
	if existing_info: existing_info.queue_free()

	var food      = entry["food"]
	var effective = entry.get("cooked_nutrients", food)
	var method    = entry.get("cook_method","raw")
	var weight_g  = entry.get("weight_g", 100.0)

	# ── NUTRITIONAL INFO — fixed strip at top ──
	var info_popup = PanelContainer.new()
	info_popup.name = "MealInfoBubble"
	info_popup.set_anchor_and_offset(SIDE_LEFT,   0, 0)
	info_popup.set_anchor_and_offset(SIDE_RIGHT,  1, 0)
	info_popup.set_anchor_and_offset(SIDE_TOP,    0, 0)
	info_popup.set_anchor_and_offset(SIDE_BOTTOM, 0, 600 * (390.0/1170.0))

	var info_hbox = HBoxContainer.new()
	info_hbox.add_theme_constant_override("separation", 20)
	info_popup.add_child(info_hbox)

	var method_display = {
		"raw":"Raw","boil":"Boiled","microwave":"Microwaved",
		"oven":"Oven-roasted","pan":"Pan-fried","boil_water":"Boiled"
	}

	# Left column
	var left_col = VBoxContainer.new()
	left_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_hbox.add_child(left_col)

	var food_title = Label.new()
	food_title.text = food.get("name","") + \
		"  [" + method_display.get(method,"Raw") + "  " + str(weight_g) + "g]"
	food_title.add_theme_font_size_override("font_size", 40)
	food_title.autowrap_mode = TextServer.AUTOWRAP_WORD
	left_col.add_child(food_title)

	var fields_left = [
		["Calories", str(snappedf(effective.get("calories",0),0.1)) + " kcal"],
		["Protein",  str(snappedf(effective.get("protein_g",0),0.1)) + " g"],
		["Fat",      str(snappedf(effective.get("fat_g",0),0.1)) + " g"],
		["Carbs",    str(snappedf(effective.get("carbs_g",0),0.1)) + " g"],
		["Sugar",    str(snappedf(effective.get("sugar_g",0),0.1)) + " g"],
	]
	for pair in fields_left:
		var row = HBoxContainer.new()
		var k = Label.new()
		k.text = pair[0]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_font_size_override("font_size", 40)
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

	var fields_right = [
		["Fiber",    str(snappedf(effective.get("fiber_g",0),0.1)) + " g"],
		["Calcium",  str(snappedf(effective.get("calcium_mg",0),0.1)) + " mg"],
		["Sodium",   str(snappedf(effective.get("sodium_mg",0),0.1)) + " mg"],
		["Vit C",    str(snappedf(effective.get("vitamin_c_mg",0),0.1)) + " mg"],
		["Vit D",    str(snappedf(effective.get("vitamin_d_mcg",0),0.1)) + " mcg"],
		["Vit E",    str(snappedf(effective.get("vitamin_e_mg",0),0.1)) + " mg"],
		["B12",      str(snappedf(effective.get("vitamin_b12_mcg",0),0.1)) + " mcg"],
	]
	for pair in fields_right:
		var row = HBoxContainer.new()
		var k = Label.new()
		k.text = pair[0]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_font_size_override("font_size", 40)
		var v = Label.new()
		v.text = pair[1]
		v.add_theme_font_size_override("font_size", 35)
		row.add_child(k)
		row.add_child(v)
		right_col.add_child(row)

	add_child(info_popup)
	info_popup.z_index = Z_INFO_BUBBLE
	
	# ── ACTION POPUP — positioned above pressed button ──
	var btn_rect     = pressed_btn.get_global_rect()
	var viewport     = get_viewport_rect().size
	var popup_width  = min(370.0, viewport.x - 20.0)  # never wider than screen
	var popup_height = 260.0
	var margin       = 8.0  # minimum distance from screen edge

	# X: center on button then shift slightly left, clamp to screen
	#var popup_x = btn_rect.position.x + btn_rect.size.x / 2.0 - popup_width / 2.0
	var popup_x = btn_rect.size.x / 2.0 - popup_width / 2.0
	popup_x = 192.0                                          # ← shift left here
	#popup_x = clamp(popup_x, margin, viewport.x - popup_width - margin)

	# Y: above button, push down if not enough room above info strip
	var info_bottom = 215.0 * (390.0 / 1170.0)
	var popup_y = btn_rect.position.y - popup_height - 1.0
	popup_y = 1225.0
	#if popup_y < info_bottom + margin:
		#popup_y = btn_rect.position.y + btn_rect.size.y + 1.0
	popup_y = clamp(popup_y, info_bottom + margin, viewport.y - popup_height - margin)

	var action_popup = PanelContainer.new()
	action_popup.name = "MealItemPopup"
	action_popup.custom_minimum_size = Vector2(popup_width, 0)
	action_popup.position = Vector2(popup_x, popup_y)
	
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	action_popup.add_child(vbox)

	var title_row = HBoxContainer.new()
	title_row.add_theme_constant_override("separation", 8)
	vbox.add_child(title_row)

	var title = Label.new()
	title.text = food.get("name","") + "  —  " + \
		method_display.get(method,"Raw") + "  ·  " + str(weight_g) + "g"
	title.add_theme_font_size_override("font_size", 40)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title_row.add_child(title)

	# 4×2 grid — 8 buttons including Close
	var actions = [
		{"icon":"🗑️", "label":"",         "key":"remove"},
		{"icon":"⚖️", "label":"Edit g",          "key":"edit_g"},
		{"icon":"📡", "label":"Micro\nwave",       "key":"microwave"},
		{"icon":"🔥", "label":"Oven",            "key":"oven"},
		{"icon":"🍳", "label":"Pan",             "key":"pan"},
		{"icon":"♨️", "label":"Boil",            "key":"boil"},
		{"icon":"📝", "label":"Edit\nVal","key":"edit_raw"},
		{"icon":"✕",  "label":"Close",           "key":"close"},
	]

	var grid = GridContainer.new()
	grid.columns = 8
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	for action in actions:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(82, 68)
		btn.text = action["icon"] + "\n" + action["label"]
		btn.add_theme_font_size_override("font_size", 35)

		if action["key"] == "close":
			btn.add_theme_color_override("font_color", Color(1.0,0.4,0.4))
			btn.pressed.connect(func():
				action_popup.queue_free()
				var ib = get_node_or_null("MealInfoBubble")
				if ib: ib.queue_free()
			)
		elif action["key"] == "remove":
			btn.add_theme_color_override("font_color", Color(1.0,0.4,0.4))
			btn.pressed.connect(func():
				meal_items.remove_at(idx)
				_refresh_meal_grid()
				_update_suggested_shopping()
				action_popup.queue_free()
				var ib = get_node_or_null("MealInfoBubble")
				if ib: ib.queue_free()
			)
		elif action["key"] == "edit_g":
			btn.pressed.connect(func():
				_show_meal_weight_editor(action_popup, entry, idx)
			)
		elif action["key"] == "edit_raw":
			btn.pressed.connect(func():
				_show_meal_edit_raw(action_popup, entry, idx)
			)
		else:
			btn.pressed.connect(func():
				_on_meal_action(action["key"], entry, idx,
					entry.get("weight_g",100.0), action_popup)
			)
		grid.add_child(btn)

	var params_area = VBoxContainer.new()
	params_area.name = "CookParamsArea"
	params_area.visible = false
	vbox.add_child(params_area)

	add_child(action_popup)
	action_popup.z_index = Z_ACTION_POPUP

func _show_meal_weight_editor(popup: PanelContainer, entry: Dictionary, idx: int):
	var params_area = popup.find_child("CookParamsArea", true, false)
	if not params_area: return
	for child in params_area.get_children():
		child.queue_free()
	params_area.visible = true

	var lbl = Label.new()
	lbl.text = "Weight (g):"
	lbl.add_theme_font_size_override("font_size", 40)
	params_area.add_child(lbl)

	var spin = SpinBox.new()
	spin.min_value = 1
	spin.max_value = 5000
	spin.step = 1
	spin.value = entry.get("weight_g", 100.0)
	spin.custom_minimum_size = Vector2(180, 50)
	params_area.add_child(spin)

	var confirm = Button.new()
	confirm.text = "✓ Apply"
	confirm.custom_minimum_size = Vector2(0, 50)
	confirm.add_theme_font_size_override("font_size", 40)
	confirm.pressed.connect(func():
		entry["weight_g"] = spin.value
		_apply_cook_to_entry(entry, entry.get("cook_method","raw"), entry.get("cook_params",{}))
		_refresh_meal_grid()
		_update_suggested_shopping()
		popup.queue_free()
	)
	params_area.add_child(confirm)


func _on_meal_action(key: String, entry: Dictionary, idx: int, weight_g: float, popup: PanelContainer):
	entry["weight_g"] = weight_g

	match key:
		"remove":
			meal_items.remove_at(idx)
			_refresh_meal_grid()
			_update_suggested_shopping()
			popup.queue_free()

		"edit_g":
			_apply_cook_to_entry(entry, "raw", {})
			_refresh_meal_grid()
			popup.queue_free()

		"microwave":
			_show_cook_params(popup, entry, idx, "microwave")

		"oven":
			_show_cook_params(popup, entry, idx, "oven")

		"pan":
			_show_cook_params(popup, entry, idx, "pan")

		"boil":
			# Boil is always 100°C, no extra params needed
			_apply_cook_to_entry(entry, "boil", {"temperature": 100})
			_refresh_meal_grid()
			_update_suggested_shopping()
			popup.queue_free()
			var ib = get_node_or_null("MealInfoBubble")
			if ib: ib.queue_free()

func _show_cook_params(popup: PanelContainer, entry: Dictionary, idx: int, method: String):
	var params_area = popup.find_child("CookParamsArea", true, false)
	if not params_area: return
	for child in params_area.get_children():
		child.queue_free()
	params_area.visible = true

	if method == "microwave":
		var power_row = HBoxContainer.new()
		var plbl = Label.new()
		plbl.text = "Power:"
		plbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		power_row.add_child(plbl)
		var power_opt = OptionButton.new()
		var powers = [100, 200, 300, 450, 600, 700, 800, 1000, 1200]
		for p in powers:
			power_opt.add_item(str(p) + "W")
		power_opt.selected = 4  # default 600W
		power_opt.custom_minimum_size = Vector2(120, 45)
		power_row.add_child(power_opt)
		params_area.add_child(power_row)

		var time_row = HBoxContainer.new()
		var tlbl = Label.new()
		tlbl.text = "Time (min):"
		tlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		time_row.add_child(tlbl)
		var tspin = SpinBox.new()
		tspin.min_value = 0.5
		tspin.max_value = 30
		tspin.step = 0.5
		tspin.value = 3.0
		tspin.custom_minimum_size = Vector2(100, 45)
		time_row.add_child(tspin)
		params_area.add_child(time_row)

		var confirm = Button.new()
		confirm.text = "✓ Apply"
		confirm.custom_minimum_size = Vector2(0, 50)
		confirm.add_theme_font_size_override("font_size", 40)
		confirm.pressed.connect(func():
			var power_vals = [100, 200, 300, 450, 600, 700, 800, 1000, 1200]
			_apply_cook_to_entry(entry, "microwave", {
				"power_w": power_vals[power_opt.selected],
				"time_min": tspin.value
			})
			_refresh_meal_grid()
			_update_suggested_shopping()
			popup.queue_free()
			var ib = get_node_or_null("MealInfoBubble")
			if ib: ib.queue_free()
		)
		params_area.add_child(confirm)

		
	elif method == "oven":
		var temp_row = HBoxContainer.new()
		var tlbl = Label.new()
		tlbl.text = "Temperature:"
		tlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		temp_row.add_child(tlbl)
		var temp_opt = OptionButton.new()
		var temps_c = [50, 100, 150, 200, 220, 250, 275, 300]
		for t in temps_c:
			if Global.use_fahrenheit:
				var f = int(t * 9.0 / 5.0 + 32)
				temp_opt.add_item(str(f) + "°F")
			else:
				temp_opt.add_item(str(t) + "°C")
		temp_opt.selected = 3  # default 200°C
		temp_opt.custom_minimum_size = Vector2(130, 45)
		temp_row.add_child(temp_opt)
		params_area.add_child(temp_row)

		var time_row = HBoxContainer.new()
		var timelbl = Label.new()
		timelbl.text = "Time (min):"
		timelbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		time_row.add_child(timelbl)
		var tspin = SpinBox.new()
		tspin.min_value = 5
		tspin.max_value = 180
		tspin.step = 5
		tspin.value = 20
		tspin.custom_minimum_size = Vector2(100, 45)
		time_row.add_child(tspin)
		params_area.add_child(time_row)

		var confirm = Button.new()
		confirm.text = "✓ Apply"
		confirm.custom_minimum_size = Vector2(0, 50)
		confirm.add_theme_font_size_override("font_size", 40)
		confirm.pressed.connect(func():
			var temps_c2 = [50, 100, 150, 200, 220, 250, 275, 300]
			_apply_cook_to_entry(entry, "oven", {
				"temp_c": temps_c2[temp_opt.selected],
				"time_min": tspin.value
			})
			_refresh_meal_grid()
			_update_suggested_shopping()
			popup.queue_free()
			var ib = get_node_or_null("MealInfoBubble")
			if ib: ib.queue_free()
		)
		params_area.add_child(confirm)
		
		
	elif method == "pan":
		var temp_row = HBoxContainer.new()
		var tlbl = Label.new()
		tlbl.text = "Temperature:"
		tlbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		temp_row.add_child(tlbl)
		var temp_opt = OptionButton.new()
		var temps_c = [100, 150, 180, 200, 220]
		for t in temps_c:
			if Global.use_fahrenheit:
				temp_opt.add_item(str(int(t * 9.0/5.0+32)) + "°F")
			else:
				temp_opt.add_item(str(t) + "°C")
		temp_opt.selected = 2  # default 180°C
		temp_opt.custom_minimum_size = Vector2(130, 45)
		temp_row.add_child(temp_opt)
		params_area.add_child(temp_row)

		var time_row = HBoxContainer.new()
		var timelbl = Label.new()
		timelbl.text = "Time (min):"
		timelbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		time_row.add_child(timelbl)
		var tspin = SpinBox.new()
		tspin.min_value = 1
		tspin.max_value = 60
		tspin.step = 1
		tspin.value = 10
		tspin.custom_minimum_size = Vector2(100, 45)
		time_row.add_child(tspin)
		params_area.add_child(time_row)

		var confirm = Button.new()
		confirm.text = "✓ Apply"
		confirm.custom_minimum_size = Vector2(0, 50)
		confirm.add_theme_font_size_override("font_size", 40)
		confirm.pressed.connect(func():
			var temps2 = [100, 150, 180, 200, 220]
			_apply_cook_to_entry(entry, "pan", {
				"temp_c": temps2[temp_opt.selected],
				"time_min": tspin.value
			})
			_refresh_meal_grid()
			_update_suggested_shopping()
			popup.queue_free()
			var ib = get_node_or_null("MealInfoBubble")
			if ib: ib.queue_free()
		)
		params_area.add_child(confirm)



func _apply_cook_to_entry(entry: Dictionary, method: String, params: Dictionary):
	entry["cook_method"] = method
	entry["cook_params"] = params

	if method == "raw":
		entry["cooked_nutrients"] = entry["food"].duplicate()
		return

	var before = entry.get("cooked_nutrients", entry["food"]).duplicate()

	var raw    = entry["food"]
	var weight = entry.get("weight_g", 100.0)
	var rf     = COOK_RETENTION.get(method, {})
	var yf     = COOK_YIELD.get(method, 1.0)

	var cooked_weight = weight * yf

	var cooked = {}
	var all_nutrient_keys = [
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
		"resveratrol_mg","total_polyphenols_mg"
	]

	for key in all_nutrient_keys:
		if not raw.has(key): continue
		var raw_val = raw[key] * (weight / 100.0)
		var factor  = rf.get(key, 0.85)  # default 0.85 for unspecified nutrients
		var cooked_val = raw_val * factor
		# Convert back to per-100g of cooked weight
		cooked[key] = snappedf(cooked_val / (cooked_weight / 100.0), 0.01)

	# Copy non-nutrient fields
	for key in raw.keys():
		if not cooked.has(key):
			cooked[key] = raw[key]

	cooked["_cooked_weight_g"] = snappedf(cooked_weight, 0.1)
	entry["cooked_nutrients"] = cooked
	entry["cooked_nutrients"] = cooked
	_show_cook_change_notification(before, cooked)

func _update_suggested_shopping():
	suggested_shopping.clear()
	for entry in meal_items:
		var food   = entry["food"]
		var weight = entry.get("weight_g", 100.0)
		var total  = weight * meal_frequency
		var found  = false
		for s in suggested_shopping:
			if s["food"].get("id","") == food.get("id",""):
				s["total_g"] += total
				found = true
				break
		if not found:
			suggested_shopping.append({"food": food, "total_g": total})

func add_suggested_to_shopping():
	for suggestion in suggested_shopping:
		# Add as a special red-ink entry
		var entry = {
			"_sid":     _generate_sid(),
			"food":     suggestion["food"],
			"qty":      1,
			"_checked": false,
			"_suggested": true,   # flag for red ink
			"_suggested_g": suggestion["total_g"]
		}
		shopping_list.append(entry)
	save_shopping_list()
	refresh_shopping_list()

func _show_meal_details():
	var existing = get_node_or_null("MealDetailsPopup")
	if existing: existing.queue_free()
	if meal_items.is_empty(): return

	var popup = PanelContainer.new()
	popup.name = "MealDetailsPopup"
	popup.set_anchor_and_offset(SIDE_LEFT,   0, 10)
	popup.set_anchor_and_offset(SIDE_RIGHT,  1, -10)
	popup.set_anchor_and_offset(SIDE_TOP,    0, 10)
	popup.set_anchor_and_offset(SIDE_BOTTOM, 1, -10)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	#vbox.size_flags_vertical = 2000.0
	scroll.add_child(vbox)
	popup.add_child(scroll)

	# Title
	#var title = Label.new()
	#title.text = "📊 Meal — " + str(meal_frequency) + "×/week"
	#title.add_theme_font_size_override("font_size", 40)
	#vbox.add_child(title)

	var total_g = _get_total_cooked_weight()
	var weight_lbl = Label.new()
	weight_lbl.text = "Total cooked weight: " + str(total_g) + "g"
	weight_lbl.add_theme_font_size_override("font_size", 40)
	vbox.add_child(weight_lbl)

	vbox.add_child(HSeparator.new())

	# Get merged nutrients (totals for whole meal, per 100g)
	var merged = _merge_meal_nutrients()

	# ── Macros ──
	var macro_title = Label.new()
	macro_title.text = "Macronutrients (per 100g of meal)"
	macro_title.add_theme_font_size_override("font_size",40)
	macro_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.4))
	vbox.add_child(macro_title)

	var macro_fields = [
		["Calories",       "calories",              "kcal"],
		["Protein",        "protein_g",             "g"],
		["Fat",            "fat_g",                 "g"],
		["  Saturated",    "saturated_fat_g",       "g"],
		["  Mono",         "monounsaturated_fat_g", "g"],
		["  Poly",         "polyunsaturated_fat_g", "g"],
		["Carbohydrates",  "carbs_g",               "g"],
		["  Sugar",        "sugar_g",               "g"],
		["Fiber",          "fiber_g",               "g"],
	]

	_add_detail_rows(vbox, merged, macro_fields)

	vbox.add_child(HSeparator.new())

	# ── Minerals ──
	var min_title = Label.new()
	min_title.text = "Minerals"
	min_title.add_theme_font_size_override("font_size", 40)
	min_title.add_theme_color_override("font_color", Color(0.4, 0.8, 0.8))
	vbox.add_child(min_title)

	var mineral_fields = [
		["Calcium",    "calcium_mg",    "mg"],
		["Sodium",     "sodium_mg",     "mg"],
		["Iron",       "iron_mg",       "mg"],
		["Magnesium",  "magnesium_mg",  "mg"],
		["Potassium",  "potassium_mg",  "mg"],
		["Zinc",       "zinc_mg",       "mg"],
		["Phosphorus", "phosphorus_mg", "mg"],
		["Copper",     "copper_mg",     "mg"],
		["Selenium",   "selenium_mcg",  "mcg"],
		["Iodine",     "iodine_mcg",    "mcg"],
		["Manganese",  "manganese_mg",  "mg"],
	]
	_add_detail_rows(vbox, merged, mineral_fields)

	vbox.add_child(HSeparator.new())

	# ── Vitamins ──
	var vit_title = Label.new()
	vit_title.text = "Vitamins"
	vit_title.add_theme_font_size_override("font_size", 40)
	vit_title.add_theme_color_override("font_color", Color(0.6, 0.8, 0.4))
	vbox.add_child(vit_title)

	var vitamin_fields = [
		["Vitamin A",   "vitamin_a_mcg",  "mcg"],
		["Vitamin B1",  "vitamin_b1_mg",  "mg"],
		["Vitamin B2",  "vitamin_b2_mg",  "mg"],
		["Vitamin B3",  "vitamin_b3_mg",  "mg"],
		["Vitamin B5",  "vitamin_b5_mg",  "mg"],
		["Vitamin B6",  "vitamin_b6_mg",  "mg"],
		["Vitamin B7",  "vitamin_b7_mcg", "mcg"],
		["Folate B9",   "vitamin_b9_mcg", "mcg"],
		["Vitamin B12", "vitamin_b12_mcg","mcg"],
		["Vitamin C",   "vitamin_c_mg",   "mg"],
		["Vitamin D",   "vitamin_d_mcg",  "mcg"],
		["Vitamin E",   "vitamin_e_mg",   "mg"],
		["Vitamin K1",  "vitamin_k1_mcg", "mcg"],
		["Vitamin K2",  "vitamin_k2_mcg", "mcg"],
	]

	_add_detail_rows(vbox, merged, vitamin_fields)

	vbox.add_child(HSeparator.new())

	# ── Antioxidants ──
	var aox_title = Label.new()
	aox_title.text = "Antioxidants"
	aox_title.add_theme_font_size_override("font_size", 40)
	aox_title.add_theme_color_override("font_color", Color(0.8, 0.5, 0.8))
	vbox.add_child(aox_title)

	var aox_fields = [
		["Beta-carotene",    "beta_carotene_mcg",     "mcg"],
		["Lycopene",         "lycopene_mcg",           "mcg"],
		["Lutein+Zeaxanthin","lutein_zeaxanthin_mcg",  "mcg"],
		["Quercetin",        "quercetin_mg",           "mg"],
		["Anthocyanins",     "anthocyanins_mg",        "mg"],
		["Resveratrol",      "resveratrol_mg",         "mg"],
		["Polyphenols",      "total_polyphenols_mg",   "mg"],
	]
	_add_detail_rows(vbox, merged, aox_fields)

	vbox.add_child(HSeparator.new())

	# ── Suggested shopping ──
	#var sug_title = Label.new()
	#sug_title.text = "Shopping list for " + str(meal_frequency) + " meals/week:"
	#sug_title.add_theme_font_size_override("font_size", 30)
	#vbox.add_child(sug_title)

	#for s in suggested_shopping:
		#var s_lbl = Label.new()
		#s_lbl.text = "• " + s["food"].get("name","") + \
			#": " + str(snappedf(s["total_g"],0.1)) + "g"
		#s_lbl.add_theme_font_size_override("font_size", 30)
		#vbox.add_child(s_lbl)

	#var add_btn = Button.new()
	#add_btn.text = "➕ Add to Shopping List"
	#add_btn.custom_minimum_size = Vector2(0, 55)
	#add_btn.add_theme_font_size_override("font_size", 30)
	#add_btn.pressed.connect(func():
		#add_suggested_to_shopping()
		#var d = get_node_or_null("MealDetailsPopup")
		#if d: d.queue_free()
	#)
	#vbox.add_child(add_btn)

	add_child(popup)
	popup.z_index = Z_DETAILS_POPUP

func save_saved_meals():
	var file = FileAccess.open("user://saved_meals.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(saved_meals))
	file.close()

func load_saved_meals():
	if not FileAccess.file_exists("user://saved_meals.json"): return
	var file = FileAccess.open("user://saved_meals.json", FileAccess.READ)
	var data = JSON.parse_string(file.get_as_text())
	file.close()
	if data and data is Array:
		saved_meals = data

func _merge_meal_nutrients() -> Dictionary:
	var nutrient_keys = [
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
		"resveratrol_mg","total_polyphenols_mg","oxalate_mg_per_100g",
		"sulfur_mg","lactose_g"
	]

	# Total cooked weight of all ingredients
	var total_cooked_weight = 0.0
	for entry in meal_items:
		var method = entry.get("cook_method","raw")
		var weight = entry.get("weight_g", 100.0)
		var yf     = COOK_YIELD.get(method, 1.0)
		total_cooked_weight += weight * yf

	if total_cooked_weight <= 0:
		return {}

	# Sum all nutrients in absolute amounts (not per 100g)
	var totals: Dictionary = {}
	for key in nutrient_keys:
		totals[key] = 0.0

	for entry in meal_items:
		var cooked = entry.get("cooked_nutrients", entry.get("food",{}))
		var method = entry.get("cook_method","raw")
		var weight = entry.get("weight_g", 100.0)
		var yf     = COOK_YIELD.get(method, 1.0)
		var cooked_weight = weight * yf
		for key in nutrient_keys:
			if cooked.has(key):
				# cooked nutrients are per 100g of cooked food
				totals[key] += cooked[key] * (cooked_weight / 100.0)

	# Convert back to per 100g of total meal
	var merged: Dictionary = {}
	for key in nutrient_keys:
		merged[key] = snappedf(totals[key] / (total_cooked_weight / 100.0), 0.01)

	merged["_total_cooked_weight_g"] = snappedf(total_cooked_weight, 0.1)
	return merged

func _get_total_cooked_weight() -> float:
	var total = 0.0
	for entry in meal_items:
		var method = entry.get("cook_method","raw")
		var weight = entry.get("weight_g", 100.0)
		total += weight * COOK_YIELD.get(method, 1.0)
	return snappedf(total, 0.1)

func _on_save_meal_pressed():
	if meal_items.is_empty():
		return

	var banner = $Panel/MealPlannerPanel/EditingBanner
	banner.hide()
	banner.text = ""

	var name_edit = $Panel/MealPlannerPanel/VBoxContainer/FrequencyRow/SaveMealNameEdit
	var meal_name = name_edit.text.strip_edges()
	if meal_name.is_empty():
		meal_name = "My Meal " + str(saved_meals.size() + 1)

	var merged      = _merge_meal_nutrients()
	var total_g     = _get_total_cooked_weight()

	if editing_meal_mid != "":
		# Overwrite existing meal
		for i in range(saved_meals.size()):
			if saved_meals[i].get("_mid","") == editing_meal_mid:
				saved_meals[i] = {
					"_mid":             editing_meal_mid,
					"name":             meal_name,
					"items":            meal_items.duplicate(true),
					"total_cooked_g":   total_g,
					"merged_nutrients": merged
				}
				break
		editing_meal_mid = ""
	else:
		# New meal
		var mid = "meal_" + str(Time.get_ticks_usec())
		saved_meals.append({
			"_mid":             mid,
			"name":             meal_name,
			"items":            meal_items.duplicate(true),
			"total_cooked_g":   total_g,
			"merged_nutrients": merged
		})

	save_saved_meals()
	name_edit.text = ""
	meal_items.clear()
	editing_meal_mid = ""
	_refresh_meal_grid()
	_refresh_my_meals_tab()

func _add_meal_to_fridge(meal: Dictionary):
	var merged   = meal.get("merged_nutrients",{})
	var total_g  = meal.get("total_cooked_g", 100.0)
	var meal_name = meal.get("name","My Meal")

	# Build a food-like dict from merged nutrients
	var food_entry = merged.duplicate()
	food_entry["id"]       = "meal_" + meal.get("_mid","0")
	food_entry["name"]     = meal_name
	food_entry["category"] = "meals"
	food_entry["level"]    = "low"  # no oxalate level concern for composite meal
	food_entry["density_g_per_ml"]  = 1.0
	food_entry["contains_gluten"]   = _meal_contains_gluten(meal)
	food_entry["oxalate_mg_per_100g"] = merged.get("oxalate_mg_per_100g",0.0)

	# Add as a fridge slot with the actual total cooked weight
	var iid  = _generate_iid()
	var slot = food_entry.duplicate()
	slot["_iid"]   = iid
	slot["_count"] = 1
	fridge_foods.append(slot)
	fridge_weights[iid] = {
		"total_g":     total_g,
		"remaining_g": total_g
	}

	if current_page >= _get_total_pages():
		current_page = _get_total_pages() - 1
	save_fridge()
	build_fridge_ui()

func _meal_contains_gluten(meal: Dictionary) -> bool:
	for entry in meal.get("items",[]):
		if entry.get("food",{}).get("contains_gluten", false):
			return true
	return false
	
func _edit_saved_meal(meal: Dictionary):
	editing_meal_mid = meal.get("_mid","")
	meal_items.clear()
	meal_items = meal.get("items",[]).duplicate(true)

	var name_edit = $Panel/MealPlannerPanel/VBoxContainer/FrequencyRow/SaveMealNameEdit
	name_edit.text = meal.get("name","")

	_refresh_meal_grid()
	_update_suggested_shopping()

	# Remove any existing banner first
	#var old_banner = $Panel/MealPlannerPanel/VBoxContainer.get_node_or_null("EditingBanner")
	#if old_banner: old_banner.queue_free()

	var banner = $Panel/MealPlannerPanel/EditingBanner
	banner.text = "✏️ Editing: " + meal.get("name","") + " — save when done"
	banner.show()
	banner.add_theme_font_size_override("font_size", 40)
	banner.add_theme_color_override("font_color", Color(0.3, 0.7, 1.0))
	banner.autowrap_mode = TextServer.AUTOWRAP_WORD

	#var mp_vbox = $Panel/MealPlannerPanel/VBoxContainer
	#mp_vbox.add_child(banner)
	#mp_vbox.move_child(banner, 0)

func _delete_saved_meal(mid: String):
	saved_meals = saved_meals.filter(func(m): return m.get("_mid","") != mid)
	save_saved_meals()
	_refresh_my_meals_tab()

func _show_meal_edit_raw(popup: PanelContainer, entry: Dictionary, idx: int):
	var params_area = popup.find_child("CookParamsArea", true, false)
	if not params_area: return
	for child in params_area.get_children():
		child.queue_free()
	params_area.visible = true

	var scroll = ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	params_area.add_child(scroll)

	var fields_vbox = VBoxContainer.new()
	fields_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(fields_vbox)

	var header = Label.new()
	header.text = "Edit raw values (per 100g)"
	header.add_theme_font_size_override("font_size", 40)
	fields_vbox.add_child(header)
	fields_vbox.add_child(HSeparator.new())

	var food = entry["food"]
	var spinboxes: Dictionary = {}

	for field_def in EDITABLE_FIELDS:
		var key   = field_def["key"]
		var row   = HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 50)
		fields_vbox.add_child(row)

		var lbl = Label.new()
		lbl.text = field_def["label"] + " (" + field_def["unit"] + ")"
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 40)
		row.add_child(lbl)

		var spin = SpinBox.new()
		spin.min_value = 0.0
		spin.max_value = field_def["max"]
		spin.step      = field_def["step"]
		spin.value     = food.get(key, 0.0)
		spin.custom_minimum_size = Vector2(130, 45)
		row.add_child(spin)
		spinboxes[key] = spin

		# Show json default in grey
		var def_lbl = Label.new()
		def_lbl.text = "(" + str(snappedf(food.get(key,0.0),0.01)) + ")"
		def_lbl.add_theme_font_size_override("font_size", 40)
		def_lbl.add_theme_color_override("font_color", Color(0.5,0.5,0.5))
		row.add_child(def_lbl)

	fields_vbox.add_child(HSeparator.new())

	var btn_row = HBoxContainer.new()
	fields_vbox.add_child(btn_row)

	var save_btn = Button.new()
	save_btn.text = "💾 Save"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.custom_minimum_size = Vector2(0, 50)
	save_btn.add_theme_font_size_override("font_size", 40)
	save_btn.pressed.connect(func():
		# Apply raw overrides directly to the food dict in this entry
		for field_def in EDITABLE_FIELDS:
			var key = field_def["key"]
			entry["food"][key] = spinboxes[key].value
		# Reapply cooking with updated raw values
		_apply_cook_to_entry(entry, entry.get("cook_method","raw"), entry.get("cook_params",{}))
		_refresh_meal_grid()
		_update_suggested_shopping()
		popup.queue_free()
	)
	btn_row.add_child(save_btn)

	var reset_btn = Button.new()
	reset_btn.text = "↺ Reset"
	reset_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reset_btn.custom_minimum_size = Vector2(0, 50)
	reset_btn.add_theme_font_size_override("font_size", 40)
	reset_btn.pressed.connect(func():
		# Find the original food in all_foods and restore
		var fid = entry["food"].get("id","")
		for f in all_foods:
			if f.get("id","") == fid:
				entry["food"] = f.duplicate()
				break
		_apply_cook_to_entry(entry, entry.get("cook_method","raw"), entry.get("cook_params",{}))
		_refresh_meal_grid()
		popup.queue_free()
	)
	btn_row.add_child(reset_btn)

func _on_meal_filter_toggled(field_key: String, pressed: bool, btn: Button):
	if pressed:
		if not meal_active_filters.has(field_key):
			meal_active_filters.append(field_key)
		btn.modulate = Color(0.4, 0.9, 0.4)
	else:
		meal_active_filters.erase(field_key)
		btn.modulate = Color.WHITE
	_update_meal_filter_label()
	_refresh_meal_tab()

func _add_detail_rows(vbox: VBoxContainer, merged: Dictionary, fields: Array):
	for cf in fields:
		var val = merged.get(cf[1], 0.0)
		if val <= 0.0: continue  # skip zero values to save space
		var row = HBoxContainer.new()
		var k = Label.new()
		k.text = cf[0]
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		k.add_theme_font_size_override("font_size", 37)
		var v = Label.new()
		v.text = str(snappedf(val, 0.01)) + " " + cf[2]
		v.add_theme_font_size_override("font_size", 37)
		row.add_child(k)
		row.add_child(v)
		vbox.add_child(row)

func _apply_tab_arrow_theme(tabs: TabContainer):
	var left_tex  = load("res://images/tab_arrow_left.png")
	var right_tex = load("res://images/tab_arrow_right.png")
	if left_tex:
		tabs.add_theme_icon_override("decrement",           left_tex)
		tabs.add_theme_icon_override("decrement_highlight", left_tex)
	if right_tex:
		tabs.add_theme_icon_override("increment",           right_tex)
		tabs.add_theme_icon_override("increment_highlight", right_tex)

func _on_clear_plate():
	meal_items.clear()
	editing_meal_mid = ""
	var banner = $Panel/MealPlannerPanel/EditingBanner
	banner.hide()
	banner.text = ""
	var name_edit = $Panel/MealPlannerPanel/VBoxContainer/FrequencyRow/SaveMealNameEdit
	name_edit.text = ""
	_refresh_meal_grid()
	_update_suggested_shopping()

func _update_meal_filter_label():
	var lbl = $Panel/MealPlannerPanel/VBoxContainer/FilterPanel/VBoxContainer/ActiveFiltersLabel
	if not lbl: return
	var dir = "↑ Asc" if meal_sort_ascending else "↓ Desc"
	if meal_active_filters.is_empty() and meal_warning_filter == "all":
		lbl.text = "No filters active"
	elif meal_active_filters.size() == 1 and meal_warning_filter == "all":
		lbl.text = "Filter: " + _get_filter_label(meal_active_filters[0]) + " | Sort: " + dir
	elif not meal_active_filters.is_empty():
		var labels = meal_active_filters.map(func(k): return _get_filter_label(k))
		lbl.text = "Filters: " + ", ".join(labels) + " | Sort: " + dir
	elif meal_warning_filter != "all":
		lbl.text = "Warning filter: " + meal_warning_filter + " | Sort: " + dir

func _on_any_button_pressed():
	# Close meal popups if they exist
	var ap = get_node_or_null("MealItemPopup")
	if ap: ap.queue_free()
	var ib = get_node_or_null("MealInfoBubble")
	if ib: ib.queue_free()

func _refresh_from_fridge_tab():
	var tabs = $Panel/MealPlannerPanel/VBoxContainer/TabContainer
	# Find the From Fridge tab
	var fridge_vbox: VBoxContainer = null
	for i in range(tabs.get_tab_count()):
		if tabs.get_tab_title(i) == "From Fridge":
			var scroll = tabs.get_tab_control(i)
			if scroll and scroll.get_child_count() > 0:
				fridge_vbox = scroll.get_child(0)
			break
	if not fridge_vbox: return
	for child in fridge_vbox.get_children():
		child.queue_free()

	if fridge_foods.is_empty():
		var empty = Label.new()
		empty.text = "Your fridge is empty.\nAdd foods from the Shopping List first."
		empty.add_theme_font_size_override("font_size", 22)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD
		fridge_vbox.add_child(empty)
		return

	for slot in fridge_foods:
		fridge_vbox.add_child(_make_from_fridge_row(slot))

func _make_from_fridge_row(slot: Dictionary) -> HBoxContainer:
	var iid       = slot.get("_iid","")
	var w         = fridge_weights.get(iid, {"remaining_g":100.0})
	var remaining = w.get("remaining_g", 100.0)
	var count     = slot.get("_count", 1)

	var row = HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 60)
	row.add_theme_constant_override("separation", 8)

	# Icon
	var icon = TextureRect.new()
	icon.custom_minimum_size = Vector2(50, 50)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var path = "res://images/" + slot.get("id","") + ".png"
	if ResourceLoader.exists(path): icon.texture = load(path)
	row.add_child(icon)

	# Name + remaining
	var name_lbl = Label.new()
	name_lbl.text = slot.get("name","") + \
		"\n" + str(snappedf(remaining, 0.1)) + "g" + \
		(" ×" + str(count) if count > 1 else "") + " remaining"
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.add_theme_font_size_override("font_size", 22)
	row.add_child(name_lbl)

	# 0g warning
	if remaining <= 0.0:
		var warn = Label.new()
		warn.text = "⚠️ 0g"
		warn.add_theme_color_override("font_color", Color(1.0, 0.4, 0.1))
		row.add_child(warn)

	# + Meal button opens portion selector popup
	var add_btn = Button.new()
	add_btn.text = "+ Meal"
	add_btn.custom_minimum_size = Vector2(90, 50)
	add_btn.add_theme_font_size_override("font_size", 22)
	add_btn.pressed.connect(func():
		Global.any_button_pressed.emit()
		_open_from_fridge_portion_popup(slot)
	)
	row.add_child(add_btn)
	return row

func _open_from_fridge_portion_popup(slot: Dictionary):
	var existing = get_node_or_null("FridgePortionPopup")
	if existing: existing.queue_free()
	var existing_action = get_node_or_null("MealItemPopup")
	if existing_action: existing_action.queue_free()
	var existing_info = get_node_or_null("MealInfoBubble")
	if existing_info: existing_info.queue_free()

	var iid       = slot.get("_iid","")
	var w         = fridge_weights.get(iid, {"remaining_g":100.0})
	var remaining = w.get("remaining_g", 100.0)
	var density   = slot.get("density_g_per_ml", 1.0)

	var popup = PanelContainer.new()
	popup.name = "FridgePortionPopup"
	popup.z_index = Z_ACTION_POPUP
	popup.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	popup.custom_minimum_size = Vector2(360, 0)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	popup.add_child(vbox)

	var title = Label.new()
	title.text = slot.get("name","") + "  ·  " + str(snappedf(remaining,0.1)) + "g remaining"
	title.add_theme_font_size_override("font_size", 22)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	var portion_actions = [
		{"icon":"🍽️", "label":"Whole\n(" + str(snappedf(remaining,0.1)) + "g)", "key":"whole"},
		{"icon":"🥄", "label":"Tablespoon\n(15mL)",  "key":"tablespoon"},
		{"icon":"🫖", "label":"Teaspoon\n(5mL)",     "key":"teaspoon"},
		{"icon":"⚡", "label":"By Gram",             "key":"gram"},
		{"icon":"💊", "label":"By\nMilligram",       "key":"milligram"},
		{"icon":"🥛", "label":"Glass\n(250mL)",      "key":"glass"},
		{"icon":"✕",  "label":"Close",               "key":"close"},
	]

	var grid = GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	vbox.add_child(grid)

	for action in portion_actions:
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(82, 70)
		btn.text = action["icon"] + "\n" + action["label"]
		btn.add_theme_font_size_override("font_size", 17)
		if action["key"] == "close":
			btn.add_theme_color_override("font_color", Color(1.0,0.4,0.4))
			btn.pressed.connect(func(): popup.queue_free())
		elif action["key"] == "whole":
			btn.pressed.connect(func():
				_add_fridge_slot_to_meal(slot, remaining)
				popup.queue_free()
			)
		else:
			btn.pressed.connect(func():
				_show_fridge_portion_input(popup, vbox, slot, action["key"], density, remaining)
			)
		grid.add_child(btn)

	var input_area = VBoxContainer.new()
	input_area.name = "PortionInputArea"
	vbox.add_child(input_area)

	add_child(popup)

func _show_fridge_portion_input(popup: PanelContainer, vbox: VBoxContainer, slot: Dictionary, action_key: String, density: float, remaining: float):
	var input_area = vbox.get_node_or_null("PortionInputArea")
	if not input_area: return
	for child in input_area.get_children():
		child.queue_free()

	var prompts = {
		"tablespoon": ["How many tablespoons?", 1, 50, 1],
		"teaspoon":   ["How many teaspoons?",   1, 50, 1],
		"gram":       ["How many grams?",        1, 2000, 1],
		"milligram":  ["How many milligrams?",   100, 500000, 100],
		"glass":      ["How many glasses?",      1, 10, 1],
	}
	var p = prompts.get(action_key, ["Amount:", 1, 1000, 1])

	var lbl = Label.new()
	lbl.text = p[0]
	lbl.add_theme_font_size_override("font_size", 22)
	input_area.add_child(lbl)

	var spin = SpinBox.new()
	spin.min_value = p[1]
	spin.max_value = p[2]
	spin.step      = p[3]
	spin.value     = p[1]
	spin.custom_minimum_size = Vector2(180, 50)
	input_area.add_child(spin)

	var preview = Label.new()
	preview.add_theme_font_size_override("font_size", 20)
	var initial_g = _calc_portion_g(action_key, p[1], density)
	preview.text = "≈ " + str(snappedf(initial_g, 0.1)) + " g"
	input_area.add_child(preview)

	spin.value_changed.connect(func(val):
		preview.text = "≈ " + str(snappedf(_calc_portion_g(action_key, val, density), 0.1)) + " g"
	)

	var confirm = Button.new()
	confirm.text = "✓ Add to Plate"
	confirm.custom_minimum_size = Vector2(0, 55)
	confirm.add_theme_font_size_override("font_size", 22)
	confirm.pressed.connect(func():
		var portion_g = _calc_portion_g(action_key, spin.value, density)
		portion_g = min(portion_g, remaining)
		_add_fridge_slot_to_meal(slot, portion_g)
		popup.queue_free()
	)
	input_area.add_child(confirm)

func _add_fridge_slot_to_meal(slot: Dictionary, portion_g: float):
	if meal_items.size() >= 12:
		_show_limit_warning()
		return

	# Scale nutrients to portion_g
	var scaled = slot.duplicate()
	var ratio  = portion_g / 100.0
	var scalable = [
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

	# Store the _iid so Eat button knows which fridge slot to subtract from
	var entry = {
		"food":             scaled,
		"_source_iid":      slot.get("_iid",""),   # link back to fridge slot
		"_source_portion_g":portion_g,
		"cook_method":      "raw",
		"cook_params":      {},
		"weight_g":         portion_g,
		"cooked_nutrients": scaled.duplicate()
	}
	meal_items.append(entry)
	_refresh_meal_grid()
	_update_suggested_shopping()
	# Refresh From Fridge tab so remaining shows correctly
	_refresh_from_fridge_tab()
	
func _eat_meal(meal: Dictionary):
	var items = meal.get("items", meal_items)

	# Check if any fridge-sourced items are at 0g
	var zero_g_foods: Array = []
	for entry in items:
		var source_iid = entry.get("_source_iid","")
		if source_iid == "": continue
		var fw = fridge_weights.get(source_iid, {})
		if fw.get("remaining_g", 1.0) <= 0.0:
			zero_g_foods.append(entry.get("food",{}).get("name","Unknown"))

	if not zero_g_foods.is_empty():
		_show_zero_g_warning(zero_g_foods, meal)
		return

	_do_eat_meal(meal)

func _do_eat_meal(meal: Dictionary):
	var items = meal.get("items", meal_items)

	# ── Determine display name ──
	# If eating from current plate while editing a saved meal, use that meal's name
	var display_name = meal.get("name", "Current Meal")
	if display_name == "Current Meal" and editing_meal_mid != "":
		for sm in saved_meals:
			if sm.get("_mid","") == editing_meal_mid:
				display_name = sm.get("name","Current Meal")
				break

	# Build ingredient summary for the log
	var ingredient_parts: Array = []
	for entry in items:
		var food_name = entry.get("food",{}).get("name","?")
		var method    = entry.get("cook_method","raw")
		var weight    = entry.get("weight_g", 100.0)
		var yf        = COOK_YIELD.get(method, 1.0)
		var cooked_w  = snappedf(weight * yf, 0.1)
		if method == "raw":
			ingredient_parts.append(food_name + " " + str(weight) + "g")
		else:
			ingredient_parts.append(food_name + " " + str(cooked_w) + "g")

	var log_name = display_name
	if not ingredient_parts.is_empty():
		log_name += " (" + ", ".join(ingredient_parts) + ")"

	var nutrient_keys = [
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

	var total_nutrients: Dictionary = {}
	for k in nutrient_keys:
		total_nutrients[k] = 0.0

	for entry in items:
		var cooked   = entry.get("cooked_nutrients", entry.get("food",{}))
		var method   = entry.get("cook_method","raw")
		var weight   = entry.get("weight_g", 100.0)
		var yf       = COOK_YIELD.get(method, 1.0)
		var cooked_w = weight * yf
		var ratio    = cooked_w / 100.0

		for k in nutrient_keys:
			total_nutrients[k] += cooked.get(k, 0.0) * ratio

		# Subtract from fridge if this item came from the From Fridge tab
		var source_iid     = entry.get("_source_iid","")
		var source_portion = entry.get("_source_portion_g", weight)

		if source_iid != "":
			var fw = fridge_weights.get(source_iid, {})
			if not fw.is_empty():
				var new_remaining = fw.get("remaining_g", 0.0) - source_portion
				fw["remaining_g"] = max(new_remaining, 0.0)
				fridge_weights[source_iid] = fw

				# If a unit in a group is fully consumed, decrement count
				# and restore remaining to full unit weight for next unit
				if fw["remaining_g"] <= 0.0:
					for slot in fridge_foods:
						if slot.get("_iid","") == source_iid:
							var count = slot.get("_count", 1)
							if count > 1:
								slot["_count"] = count - 1
								fw["remaining_g"] = fw.get("total_g", 100.0)
								fridge_weights[source_iid] = fw
							break

	save_fridge()
	build_fridge_ui()

	# Build a combined food dict and log to HomePage
	var meal_food = total_nutrients.duplicate()
	meal_food["name"] = meal.get("name", "Meal")
	meal_food["id"]   = "meal_eaten"

	var main = get_tree().root.get_node("Main")
	var home = main.get_node_or_null("ContentArea/HomePage")
	if home == null:
		_log_food_to_file(meal_food)
	else:
		home.log_food(meal_food)

	# Clear the plate if eating from the current unsaved plate
	if items == meal_items:
		meal_items.clear()
		editing_meal_mid = ""
		var banner = $Panel/MealPlannerPanel/EditingBanner
		banner.hide()
		banner.text = ""
		_refresh_meal_grid()

	_refresh_from_fridge_tab()

	# Confirmation toast
	_show_eat_confirmation()

func _show_eat_confirmation():
	var existing = get_node_or_null("EatConfirmation")
	if existing: existing.queue_free()

	var panel = PanelContainer.new()
	panel.name = "EatConfirmation"
	panel.z_index = Z_LIMIT_WARNING
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.custom_minimum_size = Vector2(300, 80)
	panel.modulate.a = 0.0

	var lbl = Label.new()
	lbl.text = "✅ Meal logged to today's intake!"
	lbl.add_theme_font_size_override("font_size", 24)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(lbl)
	add_child(panel)

	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(1.5)
	tween.tween_property(panel, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): panel.queue_free())

func _process(_delta: float) -> void:
	var action_popup = get_node_or_null("ActionPopup")
	var info_bubble  = get_node_or_null("InfoBubble")
	if info_bubble and not action_popup:
		info_bubble.queue_free()

func _show_zero_g_warning(food_names: Array, meal: Dictionary):
	var existing = get_node_or_null("ZeroGWarning")
	if existing: existing.queue_free()

	var panel = PanelContainer.new()
	panel.name = "ZeroGWarning"
	panel.z_index = Z_LIMIT_WARNING
	panel.set_anchor_and_offset(SIDE_LEFT,   0, 20)
	panel.set_anchor_and_offset(SIDE_RIGHT,  1, -20)
	panel.set_anchor_and_offset(SIDE_TOP,    0.3, 950)
	panel.set_anchor_and_offset(SIDE_BOTTOM, 0.7, -150)
	
	#STYLEEE
	var style = StyleBoxTexture.new()
	style.texture = load("res://images/warning-panel.png")
	panel.add_theme_stylebox_override("panel", style)
	
	var btn_texture = load("res://images/your_button_texture.png")



	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "⚠️ Out of stock in fridge"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var names_joined = ", ".join(food_names)
	var msg = Label.new()
	msg.text = "Aren't you out of " + names_joined + "? " + \
		"They are on 0g in your app Fridge.\n\n" + \
		"Please adjust their weight in the fridge before eating this meal."
	msg.add_theme_font_size_override("font_size", 40)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(msg)

	vbox.add_child(HSeparator.new())

	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 12)
	vbox.add_child(btn_row)

	var ok_btn = Button.new()
	ok_btn.text = "Ok!"
	ok_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ok_btn.custom_minimum_size = Vector2(0, 55)
	ok_btn.add_theme_font_size_override("font_size", 41)
	ok_btn.pressed.connect(func(): panel.queue_free())
	btn_row.add_child(ok_btn)
#STYLEEE
	var ok_style = StyleBoxTexture.new()
	ok_style.texture = load("res://images/ok_button.png")
	ok_btn.add_theme_stylebox_override("normal",  ok_style)
	ok_btn.add_theme_stylebox_override("hover",   ok_style)
	ok_btn.add_theme_stylebox_override("pressed", ok_style)
	btn_row.add_child(ok_btn)


	var adjust_btn = Button.new()
	adjust_btn.text = "Adjust now\nwith meal's values\nand eat!"
	adjust_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	adjust_btn.custom_minimum_size = Vector2(0, 55)
	adjust_btn.add_theme_font_size_override("font_size", 41)
	adjust_btn.add_theme_color_override("font_color", Color(0.2, 0.9, 0.4))
	adjust_btn.pressed.connect(func():
		panel.queue_free()
		_adjust_zero_g_and_eat(meal)
	)
	btn_row.add_child(adjust_btn)
#STYLEEE
	var adjust_style = StyleBoxTexture.new()
	adjust_style.texture = load("res://images/adjust_button.png")
	adjust_btn.add_theme_stylebox_override("normal",  adjust_style)
	adjust_btn.add_theme_stylebox_override("hover",   adjust_style)
	adjust_btn.add_theme_stylebox_override("pressed", adjust_style)
	btn_row.add_child(adjust_btn)

	add_child(panel)

func _adjust_zero_g_and_eat(meal: Dictionary):
	var items = meal.get("items", meal_items)
	# Set all 0g fridge items back to their meal portion weight
	# so _do_eat_meal can subtract correctly
	for entry in items:
		var source_iid     = entry.get("_source_iid","")
		var source_portion = entry.get("_source_portion_g", entry.get("weight_g", 100.0))
		if source_iid == "":
			continue
		var fw = fridge_weights.get(source_iid, {})
		if fw.get("remaining_g", 1.0) <= 0.0:
			fw["remaining_g"] = source_portion
			fw["total_g"]     = source_portion
			fridge_weights[source_iid] = fw
	save_fridge()
	_do_eat_meal(meal)

func _format_field_value(key: String, value: float) -> String:
	if FIELD_UNITS.has(key):
		var info = FIELD_UNITS[key]
		var display_val = snappedf(value * info["mult"], 0.01)
		return str(display_val) + " " + info["unit"]
	return str(snappedf(value, 0.01))

func _show_warning_detail_panel(food: Dictionary):
	var existing = get_node_or_null("WarningDetailOverlay")
	if existing: existing.queue_free()

	var warnings = Global.get_warnings(food)
	if warnings.is_empty(): return

	# Disable ALL input on ShoppingListPanel while warning is shown
	var shopping_panel = $Panel/ShoppingListPanel
	shopping_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_set_children_mouse_filter(shopping_panel, Control.MOUSE_FILTER_IGNORE)

	# ── Full-screen backdrop — MOUSE_FILTER_STOP blocks everything below ──
	var backdrop = ColorRect.new()
	backdrop.name = "WarningDetailOverlay"
	backdrop.color = Color(0.0, 0.0, 0.0, 0.55)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.z_index = 4000                            # ← high z-index
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP # ← blocks ALL clicks below

	var _close = func():
		backdrop.queue_free()
		# Re-enable input on ShoppingListPanel
		shopping_panel.mouse_filter = Control.MOUSE_FILTER_STOP
		_set_children_mouse_filter(shopping_panel, Control.MOUSE_FILTER_PASS)
	# Close on any press anywhere on the backdrop
	backdrop.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed:
			_close.call()
		elif event is InputEventScreenTouch and event.pressed:
			_close.call()
	)
	add_child(backdrop)

	# ── Warning panel — centered, fixed width ──
	var panel = PanelContainer.new()
	panel.z_index = 301000
	panel.mouse_filter = Control.MOUSE_FILTER_STOP    # ← panel itself also blocks

	# Center it: anchor to center, then offset by half the panel size
	var panel_width  = 360.0
	var viewport     = get_viewport_rect().size
	panel.set_anchor_and_offset(SIDE_LEFT,   0, viewport.x / 2.0 - panel_width / 2.0)
	panel.set_anchor_and_offset(SIDE_RIGHT,  0, viewport.x / 2.0 + panel_width / 2.0)
	panel.set_anchor_and_offset(SIDE_TOP,    0, 100)   # 100px from top
	panel.set_anchor_and_offset(SIDE_BOTTOM, 1, -100)  # 100px from bottom
	backdrop.add_child(panel)

	var scroll = ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title = Label.new()
	title.text = "⚠️ Warnings for " + food.get("name","")
	title.add_theme_font_size_override("font_size", 36)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())

	for w in warnings:
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var icon = Label.new()
		icon.text = "⛔" if w["severity"] == "avoid" else "⚠️"
		icon.add_theme_font_size_override("font_size", 36)
		row.add_child(icon)

		var msg = Label.new()
		msg.text = w["message"]
		msg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		msg.add_theme_font_size_override("font_size", 36)
		msg.autowrap_mode = TextServer.AUTOWRAP_WORD
		row.add_child(msg)

	vbox.add_child(HSeparator.new())

	var hint = Label.new()
	hint.text = "Tap anywhere to close"
	hint.add_theme_font_size_override("font_size", 36)
	hint.add_theme_color_override("font_color", Color(0.5,0.5,0.5))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hint)

func _set_children_mouse_filter(node: Node, filter: int):
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = filter
		_set_children_mouse_filter(child, filter)

func _shopping_snapshot():
	_shopping_undo_stack.append(shopping_list.duplicate(true))
	if _shopping_undo_stack.size() > UNDO_MAX:
		_shopping_undo_stack.pop_front()

func _undo_shopping():
	if _shopping_undo_stack.is_empty(): return
	shopping_list = _shopping_undo_stack.pop_back()
	shopping_page = clamp(shopping_page, 0, max(0, _get_shopping_pages() - 1))
	save_shopping_list()
	refresh_shopping_list()

func _show_cook_change_notification(before: Dictionary, after: Dictionary):
	var existing = get_node_or_null("CookNotification")
	if existing: existing.queue_free()

	var lines: Array = []
	for f in NOTIFY_FIELDS:
		var key = f["key"]
		var b   = snappedf(before.get(key, 0.0), 0.1)
		var a   = snappedf(after.get(key, 0.0), 0.1)
		if abs(b - a) > 0.05:
			var arrow = "↓" if a < b else "↑"
			lines.append(f["label"] + ": " + str(b) + " " + arrow + " " + str(a) + " " + f["unit"])

	if lines.is_empty(): return

	var panel = PanelContainer.new()
	panel.name = "CookNotification"
	panel.z_index = Z_LIMIT_WARNING
	panel.set_anchor_and_offset(SIDE_LEFT,  0, 10)
	panel.set_anchor_and_offset(SIDE_RIGHT, 1, -10)
	panel.set_anchor_and_offset(SIDE_TOP,   0, 10)
	panel.set_anchor_and_offset(SIDE_BOTTOM,0, 10 + 40 + lines.size() * 36)
	panel.modulate.a = 0.0

	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	var title = Label.new()
	title.text = "🍳 Cooking changes:"
	title.add_theme_font_size_override("font_size", 22)
	vbox.add_child(title)

	for line in lines:
		var lbl = Label.new()
		lbl.text = line
		lbl.add_theme_font_size_override("font_size", 20)
		vbox.add_child(lbl)

	add_child(panel)

	var tween = create_tween()
	tween.tween_property(panel, "modulate:a", 1.0, 0.3)
	tween.tween_interval(4.0)
	tween.tween_property(panel, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func(): panel.queue_free())
