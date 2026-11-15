extends CanvasLayer

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	hide()

func _unhandled_input(event):
	if visible and event.is_action_pressed("ui_accept"):
		get_tree().paused = false
		get_tree().reload_current_scene()
