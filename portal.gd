extends TileMapLayer

const WIN_RANGE = 48.0

var _won := false
var _player: Node2D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  
	print("PORTAL ready, painted tiles: ", get_used_cells().size())

func _process(_delta: float) -> void:
	if _won:
		if Input.is_action_just_pressed("ui_accept"):
			get_tree().paused = false
			get_tree().reload_current_scene()
		return
	if _player == null:
		_player = get_tree().get_first_node_in_group("player") as Node2D
		return
	if _player.get("caught"):
		return
	if _near_portal():
		_win()

func _near_portal() -> bool:
	var origin := local_to_map(to_local(_player.global_position))
	var tile := Vector2(tile_set.tile_size) * scale
	var reach := ceili(WIN_RANGE / maxf(minf(tile.x, tile.y), 1.0)) + 1
	for y in range(origin.y - reach, origin.y + reach + 1):
		for x in range(origin.x - reach, origin.x + reach + 1):
			var cell := Vector2i(x, y)
			if get_cell_source_id(cell) == -1:
				continue
			var center := to_global(map_to_local(cell))
			if _player.global_position.distance_to(center) <= WIN_RANGE:
				return true
	return false

func _win() -> void:
	_won = true
	var layer := CanvasLayer.new()
	var label := Label.new()
	label.text = "You win! Press Enter to restart."
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 48)
	layer.add_child(label)
	get_tree().current_scene.add_child(layer)
	get_tree().paused = true
