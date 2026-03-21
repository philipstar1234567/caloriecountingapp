extends Control

func _ready():
	$PanelContainer/VBoxContainer/CloseButton.pressed.connect(func():
		queue_free()
	)

func setup(food: Dictionary):
	$PanelContainer/VBoxContainer/FoodTitle.text = food.get("name", "") + " — per 100g"

	var grid = $PanelContainer/VBoxContainer/Grid
	for child in grid.get_children():
		child.queue_free()

	var fields = [
		["Calories",  str(food.get("calories", 0)) + " kcal"],
		["Protein",   str(food.get("protein_g", 0)) + " g"],
		["Fat",       str(food.get("fat_g", 0)) + " g"],
		["Carbs",     str(food.get("carbs_g", 0)) + " g"],
		["Fiber",     str(food.get("fiber_g", 0)) + " g"],
		["Calcium",   str(food.get("calcium_mg", 0)) + " mg"],
		["Oxalates",  str(food.get("oxalate_mg_per_100g", 0)) + " mg"],
	]

	for pair in fields:
		var key_label = Label.new()
		key_label.text = pair[0]
		grid.add_child(key_label)

		var val_label = Label.new()
		val_label.text = pair[1]
		grid.add_child(val_label)
