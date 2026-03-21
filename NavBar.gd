extends GridContainer

func _ready():
	$HomeButton.pressed.connect(func(): print("HOME PRESSED"))
