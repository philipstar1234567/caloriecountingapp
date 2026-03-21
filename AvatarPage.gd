extends Control

func _ready():
	$Panel/VBoxContainer/HBoxContainer/ClosetButton.pressed.connect(_on_closet)
	$Panel/VBoxContainer/HBoxContainer/ShopButton.pressed.connect(_on_shop)
	$Panel/ClosetPanel.hide()

func _on_closet():
	$Panel/ClosetPanel.show()

func _on_shop():
	pass
	# Later: open shop panel
