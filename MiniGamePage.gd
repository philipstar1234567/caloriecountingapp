extends Control

signal close_requested

const TASTE_CATEGORIES = ["sweet", "sour", "salty", "bitter", "spicy", "bland"]

var current_game: int = 0
var score: int = 0
var all_foods: Array = []

func setup(foods: Array):
	all_foods = foods
	call_deferred("_build_game_select")

const SORT_CHALLENGES = [
	{
		"question": "Sort these by protein content (highest first):",
		"foods": [
			{"name":"Chicken breast","protein_g":31.0},
			{"name":"Lentils","protein_g":9.0},
			{"name":"Salmon","protein_g":25.0},
			{"name":"Egg","protein_g":13.0},
		],
		"sort_key": "protein_g",
		"sort_desc": true
	},
	{
		"question": "Sort by Vitamin C content (highest first):",
		"foods": [
			{"name":"Orange","protein_g":0,"vitamin_c_mg":53.0},
			{"name":"Broccoli","vitamin_c_mg":89.0},
			{"name":"Strawberry","vitamin_c_mg":59.0},
			{"name":"Apple","vitamin_c_mg":4.6},
		],
		"sort_key": "vitamin_c_mg",
		"sort_desc": true
	},
]

const GUESS_CHALLENGES = [
	{"food":"100g Avocado","calories":160,"range":40},
	{"food":"1 large Egg (60g)","calories":78,"range":25},
	{"food":"100g Brown rice (cooked)","calories":123,"range":30},
	{"food":"100g Salmon","calories":208,"range":40},
	{"food":"100g Almonds","calories":579,"range":60},
]

const MATCH_CHALLENGES = [
	{"nutrient":"Calcium",         "benefit":"Strong bones and teeth"},
	{"nutrient":"Vitamin D",       "benefit":"Calcium absorption and immune function"},
	{"nutrient":"Iron",            "benefit":"Oxygen transport in blood"},
	{"nutrient":"Vitamin C",       "benefit":"Immune defense and collagen synthesis"},
	{"nutrient":"Omega-3",         "benefit":"Brain function and heart health"},
	{"nutrient":"Magnesium",       "benefit":"Muscle function and energy production"},
	{"nutrient":"Vitamin B12",     "benefit":"Nerve function and red blood cell formation"},
	{"nutrient":"Zinc",            "benefit":"Wound healing and immune support"},
]

func _ready():
	pass

func _build_game_select():
	var vbox = $Panel/ScrollContainer/VBoxContainer
	for child in vbox.get_children(): child.queue_free()

	var title = Label.new()
	title.text = "🎮 Nutrition Mini-Games"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var sub = Label.new()
	sub.text = "Learn while you play! Completing games earns PY and counts toward your daily streak."
	sub.add_theme_font_size_override("font_size", 36)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(sub)

	vbox.add_child(HSeparator.new())

	_add_game_button(vbox, "🔢 Sorting Game",
		"Sort foods by their nutrient content",
		func(): _start_sort_game())
	_add_game_button(vbox, "🎯 Calorie Guesser",
		"Estimate how many calories are in a food",
		func(): _start_guess_game())
	_add_game_button(vbox, "🔗 Nutrient Match",
		"Match nutrients to their health benefits",
		func(): _start_match_game())
	_add_game_button(vbox, "🧺 Taste Test",
		"Drag foods into the correct taste basket",
		func(): _start_taste_test())

	var close_btn = Button.new()
	close_btn.text = "✕ Close"
	close_btn.flat = true
	close_btn.z_index = 30
	close_btn.add_theme_font_size_override("font_size", 36)
	close_btn.add_theme_color_override("font_color", Color(1.0,0.4,0.4))
	close_btn.pressed.connect(func(): close_requested.emit())
	vbox.add_child(close_btn)

func _add_game_button(vbox: VBoxContainer, name: String, desc: String, callback: Callable):
	var btn_panel = PanelContainer.new()
	btn_panel.custom_minimum_size = Vector2(0, 90)
	vbox.add_child(btn_panel)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	btn_panel.add_child(hbox)
	var text_col = VBoxContainer.new()
	text_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(text_col)
	var name_lbl = Label.new()
	name_lbl.text = name
	name_lbl.add_theme_font_size_override("font_size", 36)
	text_col.add_child(name_lbl)
	var desc_lbl = Label.new()
	desc_lbl.text = desc
	desc_lbl.add_theme_font_size_override("font_size", 36)
	desc_lbl.add_theme_color_override("font_color", Color(0.6,0.6,0.6))
	text_col.add_child(desc_lbl)
	var play_btn = Button.new()
	play_btn.text = "Play ▶"
	play_btn.custom_minimum_size = Vector2(80, 55)
	play_btn.add_theme_font_size_override("font_size", 36)
	play_btn.pressed.connect(callback)
	hbox.add_child(play_btn)

func _start_sort_game():
	var vbox = $Panel/ScrollContainer/VBoxContainer
	for child in vbox.get_children(): child.queue_free()
	randomize()
	var challenge = SORT_CHALLENGES[randi() % SORT_CHALLENGES.size()]
	var foods = challenge["foods"].duplicate()
	foods.shuffle()
	var sort_key = challenge["sort_key"]

	var q_lbl = Label.new()
	q_lbl.text = challenge["question"]
	q_lbl.add_theme_font_size_override("font_size", 36)
	q_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(q_lbl)

	var inst = Label.new()
	inst.text = "Tap foods in the correct order (best first):"
	inst.add_theme_font_size_override("font_size", 36)
	inst.add_theme_color_override("font_color", Color(0.6,0.6,0.6))
	vbox.add_child(inst)

	var order_lbl = Label.new()
	order_lbl.name = "OrderLabel"
	order_lbl.text = "Your order: (tap below)"
	order_lbl.add_theme_font_size_override("font_size", 36)
	vbox.add_child(order_lbl)

	var selected: Array = []
	var food_buttons: Array = []

	for food in foods:
		var btn = Button.new()
		btn.text = food["name"] + "  (" + str(food.get(sort_key,0)) + ")"
		btn.custom_minimum_size = Vector2(0, 60)
		btn.add_theme_font_size_override("font_size", 36)
		var captured_food = food
		btn.pressed.connect(func():
			if selected.has(captured_food): return
			selected.append(captured_food)
			btn.disabled = true
			btn.modulate = Color(0.5, 0.9, 0.5)
			order_lbl.text = "Your order: " + \
				", ".join(selected.map(func(f): return f["name"]))
			if selected.size() == foods.size():
				_check_sort_answer(vbox, selected, foods, sort_key,
					challenge.get("sort_desc", true))
		)
		vbox.add_child(btn)
		food_buttons.append(btn)

func _check_sort_answer(vbox: VBoxContainer, selected: Array, foods: Array,
		sort_key: String, descending: bool):
	var correct = foods.duplicate()
	correct.sort_custom(func(a,b):
		return a.get(sort_key,0) > b.get(sort_key,0) if descending \
			else a.get(sort_key,0) < b.get(sort_key,0)
	)
	var is_correct = true
	for i in range(selected.size()):
		if selected[i]["name"] != correct[i]["name"]:
			is_correct = false; break

	var result = Label.new()
	if is_correct:
		result.text = "✅ Correct! +20 PY"
		result.add_theme_color_override("font_color", Color(0.3,1.0,0.3))
		Global.award_py(20, "Sort game correct")
		Global.check_and_update_streak()
	else:
		result.text = "❌ Not quite. Correct: " + \
			", ".join(correct.map(func(f): return f["name"]))
		result.add_theme_color_override("font_color", Color(1.0,0.4,0.3))
	result.add_theme_font_size_override("font_size", 36)
	result.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(result)

	var next_btn = Button.new()
	next_btn.text = "← Back to Games"
	next_btn.custom_minimum_size = Vector2(0, 60)
	next_btn.add_theme_font_size_override("font_size", 36)
	next_btn.pressed.connect(func(): _build_game_select())
	vbox.add_child(next_btn)

func _start_guess_game():
	var vbox = $Panel/ScrollContainer/VBoxContainer
	for child in vbox.get_children(): child.queue_free()
	randomize()
	var challenge = GUESS_CHALLENGES[randi() % GUESS_CHALLENGES.size()]

	var q_lbl = Label.new()
	q_lbl.text = "🎯 How many calories in:"
	q_lbl.add_theme_font_size_override("font_size", 36)
	vbox.add_child(q_lbl)

	var food_lbl = Label.new()
	food_lbl.text = challenge["food"]
	food_lbl.add_theme_font_size_override("font_size", 36)
	food_lbl.add_theme_color_override("font_color", Color(1.0,0.85,0.2))
	food_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(food_lbl)

	var spin = SpinBox.new()
	spin.min_value = 0
	spin.max_value = 1000
	spin.step = 5
	spin.value = 100
	spin.custom_minimum_size = Vector2(0, 60)
	spin.add_theme_font_size_override("font_size", 36)
	vbox.add_child(spin)

	var submit_btn = Button.new()
	submit_btn.text = "Submit Guess"
	submit_btn.custom_minimum_size = Vector2(0, 60)
	submit_btn.add_theme_font_size_override("font_size", 36)
	submit_btn.pressed.connect(func():
		var guess    = spin.value
		var actual   = challenge["calories"]
		var range_v  = challenge["range"]
		var diff     = abs(guess - actual)
		var result   = Label.new()
		result.autowrap_mode = TextServer.AUTOWRAP_WORD
		if diff <= range_v * 0.3:
			result.text = "🎯 Spot on! " + str(actual) + " kcal  +25 PY"
			result.add_theme_color_override("font_color", Color(0.3,1.0,0.3))
			Global.award_py(25, "Calorie guess — perfect")
		elif diff <= range_v:
			result.text = "✅ Close! " + str(actual) + " kcal  +10 PY"
			result.add_theme_color_override("font_color", Color(0.6,0.9,0.4))
			Global.award_py(10, "Calorie guess — close")
		else:
			result.text = "❌ The answer was " + str(actual) + " kcal  (you guessed " + str(int(guess)) + ")"
			result.add_theme_color_override("font_color", Color(1.0,0.4,0.3))
		result.add_theme_font_size_override("font_size", 36)
		vbox.add_child(result)
		submit_btn.disabled = true
		var next_btn = Button.new()
		next_btn.text = "← Back to Games"
		next_btn.custom_minimum_size = Vector2(0,60)
		next_btn.add_theme_font_size_override("font_size",36)
		next_btn.pressed.connect(func(): _build_game_select())
		vbox.add_child(next_btn)
	)
	vbox.add_child(submit_btn)

func _start_match_game():
	var vbox = $Panel/ScrollContainer/VBoxContainer
	for child in vbox.get_children(): child.queue_free()
	randomize()

	var all_pairs = MATCH_CHALLENGES.duplicate()
	all_pairs.shuffle()
	var pairs = all_pairs.slice(0, 5)

	var title = Label.new()
	title.text = "🔗 Match each nutrient to its benefit:"
	title.add_theme_font_size_override("font_size", 36)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	var benefits = pairs.map(func(p): return p["benefit"])
	benefits.shuffle()

	# Use a shared Dictionary to track state across all lambdas
	var state = {"answered": 0, "correct": 0}

	for i in range(pairs.size()):
		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		vbox.add_child(row)

		var nut_lbl = Label.new()
		nut_lbl.text = pairs[i]["nutrient"]
		nut_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nut_lbl.add_theme_font_size_override("font_size", 36)
		row.add_child(nut_lbl)

		var opt_btn = OptionButton.new()
		for benefit in benefits:
			opt_btn.add_item(benefit)
		opt_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt_btn.add_theme_font_size_override("font_size", 36)
		row.add_child(opt_btn)

		var check_btn = Button.new()
		check_btn.text = "✓"
		check_btn.custom_minimum_size = Vector2(50, 50)
		row.add_child(check_btn)

		var correct_benefit = pairs[i]["benefit"]
		var captured_nut_lbl = nut_lbl
		var captured_opt = opt_btn
		var captured_check = check_btn
		var total = pairs.size()

		check_btn.pressed.connect(func():
			captured_check.disabled = true
			state["answered"] += 1
			if captured_opt.get_item_text(captured_opt.selected) == correct_benefit:
				state["correct"] += 1
				captured_nut_lbl.add_theme_color_override("font_color", Color(0.3,1.0,0.3))
			else:
				captured_nut_lbl.add_theme_color_override("font_color", Color(1.0,0.4,0.3))
				# Show correct answer
				var hint = Label.new()
				hint.text = "✓ " + correct_benefit
				hint.add_theme_font_size_override("font_size", 36)
				hint.add_theme_color_override("font_color", Color(0.5,0.8,0.5))
				hint.autowrap_mode = TextServer.AUTOWRAP_WORD
				captured_nut_lbl.get_parent().add_child(hint)

			if state["answered"] == total:
				_show_match_result(vbox, state["correct"], total)
		)

func _show_match_result(vbox: VBoxContainer, correct: int, total: int):
	var py_earned = correct * 6
	var result = Label.new()
	result.text = "Score: " + str(correct) + "/" + str(total) + \
		"  +" + str(py_earned) + " PY"
	result.add_theme_font_size_override("font_size", 36)
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_color_override("font_color",
		Color(0.3,1.0,0.3) if correct >= total / 2 else Color(1.0,0.6,0.3))
	vbox.add_child(result)
	Global.award_py(py_earned, "Match game")
	var btn = Button.new()
	btn.text = "← Back to Games"
	btn.custom_minimum_size = Vector2(0, 60)
	btn.add_theme_font_size_override("font_size", 36)
	btn.pressed.connect(func(): _build_game_select())
	vbox.add_child(btn)


func _start_taste_test():
	$Panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$Panel.anchor_right = 1.0  # stretch to right edge of parent

	$Panel/ScrollContainer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	$Panel/ScrollContainer.follow_focus = false  # already default, not the issue

# This is the fix:
	$Panel/ScrollContainer/VBoxContainer.custom_minimum_size.x = $Panel.size.x
	var btn_w = ($Panel.size.x - 40) / 3.0 
	var vbox = $Panel/ScrollContainer/VBoxContainer
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.custom_minimum_size = Vector2($Panel.size.x, 1000)
	for child in vbox.get_children(): child.queue_free()
	randomize()

	# Pick 6 random foods that have a taste field
	var foods_with_taste = all_foods.filter(func(f): return f.has("taste") and not f.get("taste","").is_empty())
	if foods_with_taste.size() < 6:
		var err = Label.new()
		err.text = "Not enough foods with taste data in foods.json"
		err.add_theme_font_size_override("font_size", 36)
		vbox.add_child(err)
		return
	foods_with_taste.shuffle()
	var chosen = foods_with_taste.slice(0, 6)

	var title = Label.new()
	title.text = "🧺 Taste Test — Drag each food to its correct basket!"
	title.add_theme_font_size_override("font_size", 36)
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(title)

	var inst = Label.new()
	inst.text = "Tap a food, then tap the correct basket."
	inst.add_theme_font_size_override("font_size", 36)
	inst.add_theme_color_override("font_color", Color(0.6,0.6,0.6))
	vbox.add_child(inst)

	vbox.add_child(HSeparator.new())

	# Track game state
	var state = {
		"selected_food": null,    # Dictionary of selected food or null
		"placed": {},             # { food_name: basket_name }
		"total": chosen.size(),
		"food_btns": {}           # { food_name: Button }
	}

	# Food buttons row
	var food_label = Label.new()
	food_label.text = "Foods:"
	food_label.add_theme_font_size_override("font_size", 36)
	vbox.add_child(food_label)

	var food_grid = GridContainer.new()
	food_grid.columns = 3
	food_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	food_grid.add_theme_constant_override("h_separation", 8)
	food_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(food_grid)

	for food in chosen:
		var food_name = food.get("name","")
		var food_btn = Button.new()
		food_btn.custom_minimum_size = Vector2(btn_w, 70)  # dynamic width, taller
		food_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		food_btn.text = food_name
		food_btn.custom_minimum_size = Vector2(110, 55)
		food_btn.add_theme_font_size_override("font_size", 36)
		food_btn.autowrap_mode = TextServer.AUTOWRAP_WORD
		state["food_btns"][food_name] = food_btn

		var captured_name = food_name
		var captured_food = food
		food_btn.pressed.connect(func():
			# Deselect if already placed
			if state["placed"].has(captured_name): return
			# Toggle selection
			if state["selected_food"] != null and state["selected_food"]["name"] == captured_name:
				state["selected_food"] = null
				food_btn.add_theme_color_override("font_color", Color.WHITE)
				return
			# Deselect previous
			if state["selected_food"] != null:
				var prev_btn = state["food_btns"].get(state["selected_food"]["name"])
				if prev_btn: prev_btn.add_theme_color_override("font_color", Color.WHITE)
			# Select this food
			state["selected_food"] = captured_food
			food_btn.add_theme_color_override("font_color", Color(1.0,0.85,0.0))
		)
		food_grid.add_child(food_btn)

	vbox.add_child(HSeparator.new())

	# Basket buttons
	var basket_label = Label.new()
	basket_label.text = "Baskets:"
	basket_label.add_theme_font_size_override("font_size", 36)
	vbox.add_child(basket_label)

	var basket_grid = GridContainer.new()
	basket_grid.columns = 3
	basket_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	basket_grid.add_theme_constant_override("h_separation", 8)
	basket_grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(basket_grid)

	const BASKET_EMOJIS = {
		"sweet":"🍬", "sour":"🍋", "salty":"🧂",
		"bitter":"🫖", "spicy":"🌶️", "bland":"🍚"
	}

	# Contents label per basket
	var basket_contents: Dictionary = {}   # { basket_name: Label }

	for category in TASTE_CATEGORIES:
		var basket_col = VBoxContainer.new()
		basket_col.add_theme_constant_override("separation", 4)
		basket_grid.add_child(basket_col)

		var basket_btn = Button.new()
		basket_btn.text = BASKET_EMOJIS.get(category,"🧺") + "\n" + category.capitalize()
		basket_btn.custom_minimum_size = Vector2(btn_w, 80)  # dynamic width
		basket_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		basket_btn.add_theme_font_size_override("font_size", 36)
		basket_col.add_child(basket_btn)

		var contents_lbl = Label.new()
		contents_lbl.text = ""
		contents_lbl.add_theme_font_size_override("font_size", 36)
		contents_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
		contents_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		basket_col.add_child(contents_lbl)
		basket_contents[category] = contents_lbl

		var captured_cat = category
		basket_btn.pressed.connect(func():
			if state["selected_food"] == null: return
			var food_name = state["selected_food"]["name"]

			# Place food in basket
			state["placed"][food_name] = captured_cat
			state["selected_food"] = null

			# Mark food button as placed
			var fb = state["food_btns"].get(food_name)
			if fb:
				fb.disabled = true
				fb.add_theme_color_override("font_color", Color(0.5,0.5,0.5))

			# Update basket contents label
			var placed_in_cat = state["placed"].keys().filter(
				func(n): return state["placed"][n] == captured_cat
			)
			basket_contents[captured_cat].text = "\n".join(placed_in_cat)

			# Check if all placed
			if state["placed"].size() == state["total"]:
				_check_taste_result(vbox, state["placed"], chosen)
		)

	vbox.add_child(HSeparator.new())

	# Result area (filled by _check_taste_result)
	var result_placeholder = Control.new()
	result_placeholder.name = "TasteResult"
	vbox.add_child(result_placeholder)

func _check_taste_result(vbox: VBoxContainer, placed: Dictionary, chosen: Array):
	var result_node = vbox.get_node_or_null("TasteResult")
	if result_node: result_node.queue_free()

	var correct = 0
	for food in chosen:
		var food_name   = food.get("name","")
		var correct_cat = food.get("taste","").to_lower().strip_edges()
		var chosen_cat  = placed.get(food_name,"").to_lower().strip_edges()
		if chosen_cat == correct_cat:
			correct += 1

	var result_col = VBoxContainer.new()
	result_col.add_theme_constant_override("separation", 10)
	vbox.add_child(result_col)

	# Show each food with correct/wrong indicator
	for food in chosen:
		var food_name   = food.get("name","")
		var correct_cat = food.get("taste","").to_lower().strip_edges()
		var chosen_cat  = placed.get(food_name,"").to_lower().strip_edges()
		var is_right    = chosen_cat == correct_cat

		var row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		result_col.add_child(row)

		var icon = Label.new()
		icon.text = "✅" if is_right else "❌"
		icon.add_theme_font_size_override("font_size", 36)
		row.add_child(icon)

		var info = Label.new()
		if is_right:
			info.text = food_name + " → " + correct_cat
		else:
			info.text = food_name + " → you said: " + chosen_cat + "  (correct: " + correct_cat + ")"
		info.add_theme_font_size_override("font_size", 36)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.autowrap_mode = TextServer.AUTOWRAP_WORD
		info.add_theme_color_override("font_color",
			Color(0.3,1.0,0.3) if is_right else Color(1.0,0.4,0.3))
		row.add_child(info)

	result_col.add_child(HSeparator.new())

	var score_lbl = Label.new()
	var py_earned = 0
	if correct == chosen.size():
		score_lbl.text = "🎉 Perfect! All correct! +30 PY"
		score_lbl.add_theme_color_override("font_color", Color(0.3,1.0,0.3))
		py_earned = 30
	elif correct >= 4:
		score_lbl.text = "👍 " + str(correct) + "/6 correct! +15 PY"
		score_lbl.add_theme_color_override("font_color", Color(0.6,0.9,0.4))
		py_earned = 15
	elif correct >= 2:
		score_lbl.text = "🙂 " + str(correct) + "/6 correct! +5 PY"
		score_lbl.add_theme_color_override("font_color", Color(1.0,0.7,0.2))
		py_earned = 5
	else:
		score_lbl.text = "❌ " + str(correct) + "/6 correct. Keep practising!"
		score_lbl.add_theme_color_override("font_color", Color(1.0,0.4,0.3))

	score_lbl.add_theme_font_size_override("font_size", 36)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_col.add_child(score_lbl)

	if py_earned > 0:
		Global.award_py(py_earned, "Taste test game")

	var back_btn = Button.new()
	back_btn.text = "← Back to Games"
	back_btn.custom_minimum_size = Vector2(0, 60)
	back_btn.add_theme_font_size_override("font_size", 36)
	back_btn.pressed.connect(func(): _build_game_select())
	result_col.add_child(back_btn)
