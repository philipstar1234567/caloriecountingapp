# DigestiveSimulatorPanel.gd
# ============================================================
# Attach this to the DigestiveSimulatorPanel node in FridgePage.tscn
# Requires DigestiveSimulator.gd to be at res://DigestiveSimulator.gd
#
# Node paths below match the tree described in the integration guide.
# Adjust @onready paths if you name nodes differently.
# ============================================================
extends Panel

# ── Node references (adjust paths to match your exact tree) ──────────────────
@onready var close_btn:          Button         = $VBoxContainer/TopBar/CloseBtn
@onready var lactose_toggle:     CheckButton    = $VBoxContainer/SensitivityRow/LactoseToggle
@onready var fructose_toggle:    CheckButton    = $VBoxContainer/SensitivityRow/FructoseToggle
@onready var gluten_toggle:      CheckButton    = $VBoxContainer/SensitivityRow/GlutenToggle
@onready var histamine_toggle:   CheckButton    = $VBoxContainer/SensitivityRow/HistamineToggle
@onready var search_bar:         LineEdit       = $VBoxContainer/ContentRow/LeftCol/SearchBar
@onready var food_list:          VBoxContainer  = $VBoxContainer/ContentRow/LeftCol/FoodScrollContainer/FoodList
@onready var selected_list:      VBoxContainer  = $VBoxContainer/ContentRow/RightCol/SelectedScrollContainer/SelectedList
@onready var clear_meal_btn:     Button         = $VBoxContainer/ContentRow/RightCol/ClearMealBtn
@onready var warnings_container: VBoxContainer  = $VBoxContainer/WarningsScroll/WarningsContainer

# ── Simulator instance ────────────────────────────────────────────────────────
var simulator: DigestiveSimulator

# ── State ─────────────────────────────────────────────────────────────────────
var _selected_food_ids: Array = []
var _all_food_ids: Array = []

# ── Severity colors matching your app's cyan palette ─────────────────────────
const SEVERITY_COLORS := {
	1: Color(0.95, 0.80, 0.10, 1.0),   # yellow  – mild
	2: Color(0.95, 0.45, 0.05, 1.0),   # orange  – moderate
	3: Color(0.80, 0.08, 0.08, 1.0),   # red     – severe
}
# Synergy warnings use a purple-tinted background to visually distinguish them
const SYNERGY_COLORS := {
	1: Color(0.45, 0.15, 0.75, 1.0),   # purple  – mild synergy
	2: Color(0.55, 0.05, 0.85, 1.0),   # violet  – moderate synergy
	3: Color(0.65, 0.00, 0.90, 1.0),   # deep violet – severe synergy
}
const OK_COLOR := Color(0.10, 0.72, 0.30, 1.0)
const WHITE         := Color.WHITE
const WHITE_80      := Color(1, 1, 1, 0.80)
const WHITE_65      := Color(1, 1, 1, 0.65)

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	# ── Load the simulator ──────────────────────────────────────────────────
	simulator = DigestiveSimulator.new()
	var ok := simulator.load_food_database("res://data/foods_compounds_EU.json")
	if not ok:
		push_error("DigestiveSimulatorPanel: Could not load food database.")
		return

	_all_food_ids = simulator.get_all_food_ids()
	_all_food_ids.sort_custom(func(a, b):
		return simulator.get_food_name(a) < simulator.get_food_name(b)
	)

	# ── Connect signals ─────────────────────────────────────────────────────
	close_btn.pressed.connect(_on_close)
	clear_meal_btn.pressed.connect(_on_clear_meal)
	search_bar.text_changed.connect(_on_search_changed)

	lactose_toggle.toggled.connect(func(on):
		simulator.user_lactose_intolerant = on; _run_analysis())
	fructose_toggle.toggled.connect(func(on):
		simulator.user_fructose_sensitive = on; _run_analysis())
	gluten_toggle.toggled.connect(func(on):
		simulator.user_gluten_sensitive = on; _run_analysis())
	histamine_toggle.toggled.connect(func(on):
		simulator.user_histamine_sensitive = on; _run_analysis())

	# ── Populate food list ──────────────────────────────────────────────────
	_populate_food_list(_all_food_ids)
	_configure_touch_controls()

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC — called from FridgePage.gd to open the panel
# ─────────────────────────────────────────────────────────────────────────────

## Optionally pre-load foods already on the meal plate.
## Pass an Array of food IDs that are already selected in your MealPlanner.
func open(preloaded_food_ids: Array = []) -> void:
	visible = true
	if not preloaded_food_ids.is_empty():
		for fid in preloaded_food_ids:
			_add_food_to_meal(fid)
	_run_analysis()


# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE — food list population
# ─────────────────────────────────────────────────────────────────────────────

func _populate_food_list(food_ids: Array) -> void:
	# Clear existing buttons
	for child in food_list.get_children():
		child.queue_free()

	for food_id in food_ids:
		var btn := Button.new()
		btn.text = simulator.get_food_name(food_id)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(_on_food_btn_pressed.bind(food_id))
		food_list.add_child(btn)


func _on_search_changed(query: String) -> void:
	var q := query.to_lower().strip_edges()
	if q.is_empty():
		_populate_food_list(_all_food_ids)
		return

	var filtered := _all_food_ids.filter(func(fid: String) -> bool:
		return simulator.get_food_name(fid).to_lower().contains(q)
	)
	_populate_food_list(filtered)


# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE — meal management
# ─────────────────────────────────────────────────────────────────────────────

func _on_food_btn_pressed(food_id: String) -> void:
	if _selected_food_ids.has(food_id):
		return  # already added
	_add_food_to_meal(food_id)


func _add_food_to_meal(food_id: String) -> void:
	_selected_food_ids.append(food_id)

	# Build a row: food name label + remove button
	var row := HBoxContainer.new()
	row.name = "Row_" + food_id

	var lbl := Label.new()
	lbl.text = simulator.get_food_name(food_id)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var remove_btn := Button.new()
	remove_btn.text = "✕"
	remove_btn.flat = true
	remove_btn.pressed.connect(_on_remove_food.bind(food_id, row))

	row.add_child(lbl)
	row.add_child(remove_btn)
	selected_list.add_child(row)

	_run_analysis()


func _on_remove_food(food_id: String, row: HBoxContainer) -> void:
	_selected_food_ids.erase(food_id)
	row.queue_free()
	_run_analysis()


func _on_clear_meal() -> void:
	_selected_food_ids.clear()
	for child in selected_list.get_children():
		child.queue_free()
	_run_analysis()


# ─────────────────────────────────────────────────────────────────────────────
# PRIVATE — run simulation and render warnings
# ─────────────────────────────────────────────────────────────────────────────

func _run_analysis() -> void:
	for child in warnings_container.get_children():
		child.queue_free()
 
	if _selected_food_ids.is_empty():
		_add_placeholder("<- Add foods from the list to check your meal.")
		return
 
	var warnings: Array = simulator.analyze_meal(_selected_food_ids)
 
	if warnings.is_empty():
		_add_ok_banner()
		return
 
	# Separate synergy and regular warnings so synergy always shows at the top
	var synergy_warnings := warnings.filter(func(w): return w.get("is_synergy", false))
	var regular_warnings := warnings.filter(func(w): return not w.get("is_synergy", false))
 
	# Synergy section header (only if there are synergy warnings)
	if not synergy_warnings.is_empty():
		_add_section_header("⚡  Combination Warnings — these only occur from this specific meal combination")
		for w in synergy_warnings:
			_add_warning_card(w)
 
	# Regular warnings section header (only if there are also synergy warnings above)
	if not regular_warnings.is_empty() and not synergy_warnings.is_empty():
		_add_section_header("Individual Compound Warnings")
 
	for w in regular_warnings:
		_add_warning_card(w)


func _add_section_header(text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warnings_container.add_child(lbl)
 
	# Thin separator line
	var sep := HSeparator.new()
	warnings_container.add_child(sep)

func _add_placeholder(msg: String) -> void:
	var lbl := Label.new()
	lbl.text = msg
	lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warnings_container.add_child(lbl)


func _add_ok_banner() -> void:
	var lbl := Label.new()
	lbl.text = "✅  No significant digestive concerns for this meal combination."
	lbl.add_theme_color_override("font_color", OK_COLOR)
	lbl.add_theme_font_size_override("font_size", 36)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	warnings_container.add_child(lbl)


func _add_warning_card(warning: Dictionary) -> void:
	var is_synergy: bool = warning.get("is_synergy", false)
	# Outer panel with colored background
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var color_map := SYNERGY_COLORS if is_synergy else SEVERITY_COLORS
	style.bg_color = color_map.get(warning["severity"], Color.GRAY)
	style.set_corner_radius_all(8)
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	# Synergy cards get a bright border to stand out further
	if is_synergy:
		style.border_color = Color(1.0, 0.85, 1.0, 0.6)
		style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)

	# Header: icon + outcome label + severity # ---- Row 1: badge(s) + title + severity ---------------------------------
	var header_row := HBoxContainer.new()
	header_row.add_theme_constant_override("separation", 8)
 
	# "⚡ Combination" badge for synergy warnings
	if is_synergy:
		var badge := Label.new()
		badge.text = "⚡ COMBINATION"
		badge.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
		badge.add_theme_font_size_override("font_size", 36)
		header_row.add_child(badge)
 
	var icon_lbl := Label.new()
	icon_lbl.text = warning["icon"]
	icon_lbl.add_theme_font_size_override("font_size", 36)
	header_row.add_child(icon_lbl)
 
	var title_lbl := Label.new()
	title_lbl.text = warning.get("title", warning["outcome"].replace("_", " "))
	title_lbl.add_theme_color_override("font_color", WHITE)
	title_lbl.add_theme_font_size_override("font_size", 36)
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header_row.add_child(title_lbl)
 
	var sev_lbl := Label.new()
	sev_lbl.text = warning["severity_label"].to_upper()
	sev_lbl.add_theme_color_override("font_color", WHITE_80)
	sev_lbl.add_theme_font_size_override("font_size", 36)
	header_row.add_child(sev_lbl)
 
	vbox.add_child(header_row)
 
	# ---- Row 2: Mechanism (what is happening) --------------------------------
	var mech_lbl := Label.new()
	mech_lbl.text = warning.get("mechanism", "")
	mech_lbl.add_theme_color_override("font_color", WHITE)
	mech_lbl.add_theme_font_size_override("font_size", 36)
	mech_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(mech_lbl)
 
	# ---- Row 3: Consequence (what you will feel) -----------------------------
	var cons_lbl := Label.new()
	cons_lbl.text = "What you will feel:  " + warning.get("consequence", "")
	cons_lbl.add_theme_color_override("font_color", WHITE_80)
	cons_lbl.add_theme_font_size_override("font_size", 36)
	cons_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(cons_lbl)

	# Chemical compounds responsible
	var chem := Label.new()
	chem.text = "⚗️  " + warning["chemical_cause"]
	chem.add_theme_color_override("font_color", Color(1, 1, 1, 0.80))
	chem.add_theme_font_size_override("font_size", 36)
	chem.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(chem)

	# Foods involved
	if not warning["foods_involved"].is_empty():
		var names := (warning["foods_involved"] as Array).map(
			func(fid): return simulator.get_food_name(fid)
		)
		var foods_lbl := Label.new()
		foods_lbl.text = "🍽️  " + ", ".join(names)
		foods_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.70))
		foods_lbl.add_theme_font_size_override("font_size", 36)
		foods_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(foods_lbl)

	panel.add_child(vbox)
	warnings_container.add_child(panel)

func _configure_touch_controls(node: Node = self):
	for child in node.get_children():
		if child is ScrollContainer:
			child.scroll_deadzone = 4
			child.mouse_filter = Control.MOUSE_FILTER_STOP
		if child is SpinBox:
			child.mouse_filter = Control.MOUSE_FILTER_PASS
			child.get_line_edit().mouse_filter = Control.MOUSE_FILTER_PASS
			for spinbox_child in child.get_children():
				if spinbox_child is BaseButton:
					spinbox_child.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
		elif child is OptionButton:
			child.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			child.mouse_filter = Control.MOUSE_FILTER_PASS
		elif child is CheckBox:
			child.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			child.mouse_filter = Control.MOUSE_FILTER_PASS
		elif child is BaseButton:
			child.action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
			child.mouse_filter = Control.MOUSE_FILTER_PASS
		_configure_touch_controls(child)

# ─────────────────────────────────────────────────────────────────────────────
func _on_close() -> void:
	visible = false
