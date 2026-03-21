extends Control

signal eat_pressed(food: Dictionary)
signal info_pressed(food: Dictionary)

var current_food: Dictionary = {}

func _ready():
	$PanelContainer/VBoxContainer/EatButton.pressed.connect(func():
		emit_signal("eat_pressed", current_food)
		queue_free()
	)
	$PanelContainer/VBoxContainer/InfoButton.pressed.connect(func():
		emit_signal("info_pressed", current_food)
	)
	$PanelContainer/VBoxContainer/CloseButton.pressed.connect(func():
		queue_free()
	)

func setup(food: Dictionary):
	current_food = food
	$PanelContainer/VBoxContainer/FoodName.text = food.get("name", "")
	$PanelContainer/VBoxContainer/OxalateLabel.text = "Oxalates: " + str(food.get("oxalate_mg_per_100g", 0)) + " mg per 100g"

	var path = "res://images/" + food.get("id", "") + ".png"
	if ResourceLoader.exists(path):
		$PanelContainer/VBoxContainer/FoodIcon.texture = load(path)

	# Show warning if any
	var warnings = Global.get_warnings(food)
	if warnings.size() > 0:
		var warn_label = Label.new()
		warn_label.text = ("⛔ " if warnings[0]["severity"] == "avoid" else "⚠️ ") + warnings[0]["message"]
		$PanelContainer/VBoxContainer.add_child(warn_label)
		$PanelContainer/VBoxContainer.move_child(warn_label, 3)
