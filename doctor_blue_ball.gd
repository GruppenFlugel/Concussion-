extends CharacterBody2D

const SPEED = 300.0
const HIDE_RANGE := 72.0
const HOUSE_BLOB := 12

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var hiding_in_house := false
var caught := false
var house_layer: TileMapLayer
var _e_held := false
var _outside_position := Vector2.ZERO
var _hide_cell_found := false


func _ready() -> void:
	add_to_group("player")
	sprite.texture = load("res://player.png")
	sprite.scale = Vector2(0.10, 0.10)
	house_layer = get_tree().current_scene.find_child("Houses and Props", true, false) as TileMapLayer


func _physics_process(_delta: float) -> void:
	if caught:
		velocity = Vector2.ZERO
		return

	var e_down := Input.is_physical_key_pressed(KEY_E)
	if e_down and not _e_held:
		_try_toggle_hide()
	_e_held = e_down

	if hiding_in_house:
		velocity = Vector2.ZERO
		return

	var direction := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		direction.x += 1.0
	if Input.is_physical_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		direction.y += 1.0
	velocity = direction.normalized() * SPEED
	move_and_slide()


func _try_toggle_hide() -> void:
	if house_layer == null:
		return

	if hiding_in_house:
		global_position = _outside_position
		hiding_in_house = false
		collision_shape.set_deferred("disabled", false)
		sprite.modulate.a = 1.0
		return

	var cell := _nearest_house_cell()
	if not _hide_cell_found:
		return

	_outside_position = global_position
	global_position = _house_center(cell)
	hiding_in_house = true
	collision_shape.set_deferred("disabled", true)
	sprite.modulate.a = 0.0


func _nearest_house_cell() -> Vector2i:
	var origin := house_layer.local_to_map(house_layer.to_local(global_position))
	var reach := ceili(HIDE_RANGE / _house_cell_size()) + 2
	var best := Vector2i.ZERO
	var best_distance := HIDE_RANGE
	_hide_cell_found = false
	for y in range(origin.y - reach, origin.y + reach + 1):
		for x in range(origin.x - reach, origin.x + reach + 1):
			var cell := Vector2i(x, y)
			if house_layer.get_cell_source_id(cell) == -1:
				continue
			var center := house_layer.to_global(house_layer.map_to_local(cell))
			var distance := global_position.distance_to(center)
			if distance <= best_distance:
				best_distance = distance
				best = cell
				_hide_cell_found = true
	return best


func _house_center(start: Vector2i) -> Vector2:
	var seen: Dictionary = {}
	var stack: Array[Vector2i] = [start]
	seen[start] = true
	var sum := Vector2.ZERO
	var count := 0
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		sum += house_layer.to_global(house_layer.map_to_local(cell))
		count += 1
		for offset: Vector2i in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + offset
			if seen.has(next):
				continue
			if absi(next.x - start.x) > HOUSE_BLOB or absi(next.y - start.y) > HOUSE_BLOB:
				continue
			if house_layer.get_cell_source_id(next) == -1:
				continue
			seen[next] = true
			stack.append(next)
	return sum / float(count)


func _house_cell_size() -> float:
	var tile := Vector2(house_layer.tile_set.tile_size) * house_layer.scale
	return maxf(minf(tile.x, tile.y), 1.0)
