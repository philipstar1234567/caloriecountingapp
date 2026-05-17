extends Control

var all_foods: Array = []

signal close_requested

func _ready():
	Global.load_discoveries()
	Global.food_discovered.connect(func(_id): refresh_display())
	refresh_display()

func _notification(what):
	if what == NOTIFICATION_VISIBILITY_CHANGED and visible:
		refresh_display()

func refresh_display():
	var vbox = $Panel/ScrollContainer/VBoxContainer
	for child in vbox.get_children(): child.queue_free()

	if all_foods.is_empty():
		var fridge = get_tree().root.get_node_or_null("Main/ContentArea/FridgePage")
		if fridge: all_foods = fridge.all_foods
	if all_foods.is_empty(): return

	var title = Label.new()
	title.text = "📖 Food Encyclopedia"
	title.add_theme_font_size_override("font_size", 48)
	vbox.add_child(title)

	var count_lbl = Label.new()
	count_lbl.text = str(Global.discovered_foods.size()) + " / " + \
		str(all_foods.size()) + " foods discovered"
	count_lbl.add_theme_font_size_override("font_size", 36)
	count_lbl.add_theme_color_override("font_color", Color(0.6,0.6,0.6))
	vbox.add_child(count_lbl)

	# Progress bar
	var pct    = float(Global.discovered_foods.size()) / float(max(all_foods.size(),1))
	var filled = int(pct * 20)
	var bar    = Label.new()
	bar.text   = "█".repeat(filled) + "░".repeat(20 - filled)
	bar.add_theme_font_size_override("font_size", 36)
	vbox.add_child(bar)

	vbox.add_child(HSeparator.new())

	# Show discovered foods
	for food in all_foods:
		var fid  = food.get("id","")
		var known = Global.discovered_foods.has(fid)
		var entry_panel = PanelContainer.new()
		var ev = HBoxContainer.new()
		ev.add_theme_constant_override("separation", 12)
		entry_panel.add_child(ev)
		vbox.add_child(entry_panel)

		# Icon
		var icon = TextureRect.new()
		icon.custom_minimum_size = Vector2(60, 60)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var path = "res://images/" + fid + ".png"
		if known and ResourceLoader.exists(path):
			icon.texture = load(path)
		else:
			icon.modulate = Color(0.2,0.2,0.2)
		ev.add_child(icon)

		var text_col = VBoxContainer.new()
		text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ev.add_child(text_col)

		var name_lbl = Label.new()
		name_lbl.text = food.get("name","?") if known else "???"
		name_lbl.add_theme_font_size_override("font_size", 36)
		if not known:
			name_lbl.add_theme_color_override("font_color", Color(0.3,0.3,0.3))
		text_col.add_child(name_lbl)

		if known:
			var fact_lbl = Label.new()
			fact_lbl.text = _get_food_fact(food)
			fact_lbl.add_theme_font_size_override("font_size", 36)
			fact_lbl.add_theme_color_override("font_color", Color(0.6,0.6,0.6))
			fact_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
			text_col.add_child(fact_lbl)

			var cat_lbl = Label.new()
			cat_lbl.text = food.get("category","").capitalize()
			cat_lbl.add_theme_font_size_override("font_size", 36)
			cat_lbl.add_theme_color_override("font_color", Color(0.4,0.7,0.4))
			text_col.add_child(cat_lbl)
		else:
			var hint_lbl = Label.new()
			hint_lbl.text = "Log this food to discover it!"
			hint_lbl.add_theme_font_size_override("font_size", 36)
			hint_lbl.add_theme_color_override("font_color", Color(0.3,0.3,0.3))
			text_col.add_child(hint_lbl)

func _get_food_fact(food: Dictionary) -> String:
	# Generate an interesting fact from the food's data
	var top_field = ""
	var top_val   = 0.0
	var facts: Dictionary = {
		"vitamin_c_mg":   str(snappedf(food.get("vitamin_c_mg",0),0.1)) + "mg Vitamin C per 100g",
		"protein_g":      str(snappedf(food.get("protein_g",0),0.1)) + "g protein per 100g",
		"iron_mg":        str(snappedf(food.get("iron_mg",0),0.1)) + "mg iron per 100g",
		"calcium_mg":     str(snappedf(food.get("calcium_mg",0),0.1)) + "mg calcium per 100g",
		"vitamin_d_mcg":  str(snappedf(food.get("vitamin_d_mcg",0),0.1)) + "mcg Vitamin D per 100g",
		"lycopene_mcg":   str(snappedf(food.get("lycopene_mcg",0),0.1)) + "mcg lycopene per 100g",
		"fiber_g":        str(snappedf(food.get("fiber_g",0),0.1)) + "g fiber per 100g",
	}
	for key in facts.keys():
		if food.get(key,0.0) > top_val:
			top_val = food.get(key,0.0)
			top_field = key
	if top_field.is_empty(): return food.get("category","").capitalize()
	return "Rich in " + facts.get(top_field,"")
	
func setup(foods: Array):
	all_foods = foods
	Global.load_discoveries()
	call_deferred("refresh_display")
