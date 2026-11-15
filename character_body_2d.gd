extends CharacterBody2D

@export var patrol_speed := 110.0
@export var chase_speed := 200.0
@export var sight_range := 380.0
@export var sight_angle_deg := 75.0
@export var lose_sight_time := 3.0
@export var patrol_wait_time := 2.0
@export var catch_distance := 28.0
@export var patrol_min_distance := 140.0
@export var patrol_max_distance := 520.0
@export_flags_2d_physics var sight_mask := 1

enum State { PATROL, CHASE }

var state := State.PATROL
var player: Node2D
var ground: TileMapLayer
var astar := AStar2D.new()
var walkable := {}
var cells: Array[Vector2i] = []
var facing := Vector2.DOWN
var lose_timer := 0.0
var wait_timer := 0.0
var stuck_timer := 0.0
var last_position := Vector2.ZERO
var path := PackedVector2Array()
var path_index := 0
var repath_timer := 0.0
var caught := false
var sprite: Sprite2D
var body_shape: CollisionShape2D
var death_anim: AnimatedSprite2D
var _origin := Vector2i.ZERO
var _stride := 1


func _ready() -> void:
	motion_mode = MOTION_MODE_FLOATING
	collision_layer = 2
	collision_mask = 3
	sprite = get_node_or_null("Sprite2D") as Sprite2D
	body_shape = get_node_or_null("CollisionShape2D") as CollisionShape2D
	player = get_tree().get_first_node_in_group("player") as Node2D
	var root := get_parent()
	ground = root.get_node("TileMapLayer") as TileMapLayer
	var trees := root.get_node("Trees and Bushes") as TileMapLayer
	var houses := root.get_node("Houses and Props") as TileMapLayer
	# Painted navigation only covers a corner of the map, so routes come from the ground grid.
	for layer in [ground, trees, houses]:
		layer.navigation_enabled = false
	_build_grid(trees, houses)
	_snap_onto_grid()
	last_position = _agent_position()
	_prepare_death_screen()
	_pick_patrol_point()
	print("AI ready cells=", cells.size(), " path=", path.size(), " pos=", _agent_position(), " player=", player)


func _physics_process(delta: float) -> void:
	if caught:
		velocity = Vector2.ZERO
		return
	if player == null:
		player = get_tree().get_first_node_in_group("player") as Node2D

	if state == State.PATROL and _can_see_player():
		_set_state(State.CHASE)

	match state:
		State.PATROL:
			_patrol(delta)
		State.CHASE:
			_chase(delta)

	_check_stuck(delta)
	_try_catch()


func _patrol(delta: float) -> void:
	if path_index >= path.size():
		wait_timer -= delta
		velocity = Vector2.ZERO
		move_and_slide()
		if wait_timer <= 0.0:
			_pick_patrol_point()
		return
	_follow_path(patrol_speed)


func _chase(delta: float) -> void:
	if player == null:
		_set_state(State.PATROL)
		return

	if _can_see_player():
		lose_timer = 0.0
		repath_timer -= delta
		if repath_timer <= 0.0:
			repath_timer = 0.3
			_set_path(_world_to_cell(player.global_position))
	else:
		lose_timer += delta
		if lose_timer >= lose_sight_time:
			_set_state(State.PATROL)
			return

	_follow_path(chase_speed)


func _follow_path(speed: float) -> void:
	_skip_reached_points()
	var here := _agent_position()
	if path_index >= path.size():
		if state == State.CHASE and _can_see_player():
			var fallback := player.global_position - here
			if fallback.length() > 1.0:
				_move_in_direction(fallback, speed)
				return
		velocity = Vector2.ZERO
		move_and_slide()
		return

	_move_in_direction(path[path_index] - here, speed)


func _move_in_direction(direction: Vector2, speed: float) -> void:
	if direction.length() < 1.0:
		velocity = Vector2.ZERO
	else:
		direction = direction.normalized()
		facing = direction
		velocity = direction * speed
		if sprite and absf(direction.x) > 0.1:
			sprite.flip_h = direction.x < 0.0
	move_and_slide()


func _check_stuck(delta: float) -> void:
	if caught or path_index >= path.size():
		stuck_timer = 0.0
		last_position = _agent_position()
		return

	var here := _agent_position()
	if here.distance_to(last_position) < 1.0:
		stuck_timer += delta
		if stuck_timer >= 0.8:
			stuck_timer = 0.0
			if state == State.PATROL:
				_pick_patrol_point()
			elif _can_see_player():
				_set_path(_world_to_cell(player.global_position))
			else:
				_set_state(State.PATROL)
	else:
		stuck_timer = 0.0
		last_position = here


func _pick_patrol_point() -> void:
	var start := _nearest_walkable(_world_to_cell(_agent_position()))
	if not _is_valid_cell(start) or cells.is_empty():
		wait_timer = 0.25
		return

	var here := _agent_position()
	var nearby: Array[Vector2i] = []
	var fallback: Array[Vector2i] = []
	for cell in cells:
		var distance := _cell_center(cell).distance_to(here)
		if distance >= patrol_min_distance and distance <= patrol_max_distance:
			nearby.append(cell)
		elif distance > 48.0:
			fallback.append(cell)

	var pool := nearby if not nearby.is_empty() else fallback
	path = PackedVector2Array()
	path_index = 0
	if pool.is_empty():
		wait_timer = 0.25
		return

	for _attempt in 12:
		var goal: Vector2i = pool[randi() % pool.size()]
		path = astar.get_point_path(_id(start), _id(goal))
		if path.size() > 1:
			break
		path = PackedVector2Array()

	path_index = 0
	_skip_reached_points()
	wait_timer = patrol_wait_time if path.size() > path_index else 0.25


func _set_path(goal: Vector2i) -> void:
	var start := _nearest_walkable(_world_to_cell(_agent_position()))
	goal = _nearest_walkable(goal)
	path = PackedVector2Array()
	path_index = 0
	if not _is_valid_cell(start) or not _is_valid_cell(goal):
		return
	path = astar.get_point_path(_id(start), _id(goal))
	_skip_reached_points()


func _set_state(new_state: State) -> void:
	state = new_state
	lose_timer = 0.0
	stuck_timer = 0.0
	repath_timer = 0.0
	if new_state == State.PATROL:
		_pick_patrol_point()
	elif player != null:
		_set_path(_world_to_cell(player.global_position))


func _can_see_player() -> bool:
	if player == null or _is_player_hidden() or player.get("caught") == true:
		return false

	var to_player := player.global_position - _agent_position()
	var distance := to_player.length()
	if distance > sight_range or distance < 0.01:
		return false
	if absf(facing.angle_to(to_player)) > deg_to_rad(sight_angle_deg):
		return false
	return _has_clear_sight()


func _has_clear_sight() -> bool:
	var query := PhysicsRayQueryParameters2D.create(_agent_position(), player.global_position, sight_mask)
	query.exclude = [get_rid()]
	if player is CollisionObject2D:
		query.exclude.append((player as CollisionObject2D).get_rid())
	var hit := get_world_2d().direct_space_state.intersect_ray(query)
	return hit.is_empty()


func _is_player_hidden() -> bool:
	return player != null and player.get("hiding_in_house") == true


func _try_catch() -> void:
	if caught or player == null or _is_player_hidden() or player.get("caught") == true:
		return
	if _agent_position().distance_to(player.global_position) > catch_distance:
		return
	if not _has_clear_sight():
		return
	_catch_player()


func _catch_player() -> void:
	caught = true
	velocity = Vector2.ZERO
	player.set("caught", true)
	state = State.PATROL
	path = PackedVector2Array()
	if death_anim == null:
		return
	var viewport_size := get_viewport().get_visible_rect().size
	death_anim.position = viewport_size * 0.5
	death_anim.visible = true
	death_anim.frame = 0
	death_anim.play("default")
	get_tree().paused = true


func _prepare_death_screen() -> void:
	var death_screen := preload("res://deathscreen.tscn").instantiate() as CanvasLayer
	death_screen.process_mode = Node.PROCESS_MODE_ALWAYS
	death_anim = death_screen.get_node("AnimatedSprite2D") as AnimatedSprite2D
	death_anim.process_mode = Node.PROCESS_MODE_ALWAYS
	death_anim.visible = false
	death_anim.stop()
	death_screen.layer = 100
	get_tree().root.add_child.call_deferred(death_screen)


func _build_grid(trees: TileMapLayer, houses: TileMapLayer) -> void:
	var blocked := {}
	for cell in trees.get_used_cells():
		var tile := trees.get_cell_tile_data(cell)
		if tile == null or tile.get_collision_polygons_count(0) == 0:
			continue
		blocked[_world_to_cell(trees.to_global(trees.map_to_local(cell)))] = true

	var house_tile := Vector2(houses.tile_set.tile_size) * houses.scale
	for cell in houses.get_used_cells():
		var center := houses.to_global(houses.map_to_local(cell))
		var rect := Rect2(center - house_tile * 0.5, house_tile)
		var min_cell := _world_to_cell(rect.position)
		var max_cell := _world_to_cell(rect.end)
		for y in range(min_cell.y, max_cell.y + 1):
			for x in range(min_cell.x, max_cell.x + 1):
				blocked[Vector2i(x, y)] = true

	var used := ground.get_used_rect()
	_origin = used.position
	_stride = maxi(used.size.x, 1) + 2
	for cell in ground.get_used_cells():
		if blocked.has(cell):
			continue
		walkable[cell] = true
		cells.append(cell)
		astar.add_point(_id(cell), _cell_center(cell))

	var directions: Array[Vector2i] = [
		Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP,
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
	]
	for cell in cells:
		for direction in directions:
			var next: Vector2i = cell + direction
			if not walkable.has(next):
				continue
			if direction.x != 0 and direction.y != 0:
				if not walkable.has(cell + Vector2i(direction.x, 0)) or not walkable.has(cell + Vector2i(0, direction.y)):
					continue
			var from_id := _id(cell)
			var to_id := _id(next)
			if not astar.are_points_connected(from_id, to_id):
				astar.connect_points(from_id, to_id)


func _snap_onto_grid() -> void:
	var here := _world_to_cell(_agent_position())
	if walkable.has(here):
		return
	var nearest := _nearest_walkable(here)
	if not _is_valid_cell(nearest):
		return
	global_position += _cell_center(nearest) - _agent_position()


func _skip_reached_points() -> void:
	var here := _agent_position()
	while path_index < path.size() and here.distance_to(path[path_index]) < 10.0:
		path_index += 1


func _agent_position() -> Vector2:
	if body_shape:
		return body_shape.global_position
	return global_position


func _world_to_cell(world: Vector2) -> Vector2i:
	return ground.local_to_map(ground.to_local(world))


func _cell_center(cell: Vector2i) -> Vector2:
	return ground.to_global(ground.map_to_local(cell))


func _id(cell: Vector2i) -> int:
	return (cell.x - _origin.x) + (cell.y - _origin.y) * _stride


func _is_valid_cell(cell: Vector2i) -> bool:
	return walkable.has(cell)


func _nearest_walkable(cell: Vector2i) -> Vector2i:
	if walkable.has(cell):
		return cell
	for radius in range(1, 24):
		for y in range(-radius, radius + 1):
			for x in range(-radius, radius + 1):
				if maxi(absi(x), absi(y)) != radius:
					continue
				var next := cell + Vector2i(x, y)
				if walkable.has(next):
					return next
	return Vector2i(1_000_000, 0)
