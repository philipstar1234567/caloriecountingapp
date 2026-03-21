
extends Control

var current_page: Node = null

const PAGES = {
	"LeaderboardButton": "res://LeaderboardPage.tscn",
	"AvatarButton":      "res://AvatarPage.tscn",
	"HomeButton":        "res://HomePage.tscn",
	"FridgeButton":      "res://FridgePage.tscn",
	"SettingsButton":    "res://SettingsPage.tscn",
}

func _ready():
	print("Main _ready called")
	var navbar = $NavBar
	print("NavBar found: ", navbar)
	for button_name in PAGES.keys():
		var btn = navbar.get_node(button_name)
		print("Connecting button: ", button_name, " -> ", btn)
		var path = PAGES[button_name]
		btn.pressed.connect(func(): 
			print("Button pressed! Switching to: ", path)
			switch_to(path)
		)
	switch_to("res://HomePage.tscn")

func switch_to(scene_path: String):
	if current_page != null:
		current_page.queue_free()
		current_page = null
	
	# Wait one frame for queue_free to complete
	await get_tree().process_frame
	
	var new_page = load(scene_path).instantiate()
	$ContentArea.add_child(new_page)
	new_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	current_page = new_page
