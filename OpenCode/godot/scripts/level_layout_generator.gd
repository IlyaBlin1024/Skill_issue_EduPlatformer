extends RefCounted
class_name LevelLayoutGenerator

const ROOM_FILL_COLOR := Color(0.205882, 0.219608, 0.282353, 0.58)
const WALL_COLOR := Color(0.180392, 0.188235, 0.25098, 1)
const PLATFORM_COLOR := Color(0.223529, 0.243137, 0.317647, 1)
const BACKDROP_COLOR := Color(0.316, 0.332, 0.392, 1)

const FLOOR_THICKNESS := 28.0
const WALL_THICKNESS := 28.0
const SIDE_DOOR_HEIGHT := 170.0
const VERTICAL_DOOR_WIDTH := 170.0
const CORRIDOR_HEIGHT := 184.0
const SHAFT_WIDTH := 248.0
const SHAFT_PLATFORM_WIDTH := 148.0
const SHAFT_PLATFORM_HEIGHT := 18.0
const SHAFT_PLATFORM_STEP := 68.0
const SHAFT_APPROACH_PLATFORM_WIDTH := 164.0
const ENTRY_PLATFORM_WIDTH := 120.0
const SURFACE_OBJECT_OFFSET := 26.0
const SIDE_DOOR_CLEARANCE := 60.0
const SURFACE_MARGIN := 22.0
const CONNECTION_OVERLAP := 18.0
const SURFACE_SAFE_PADDING := 30.0
const ENEMY_HALF_HEIGHT := 24.0
const EXIT_HALF_HEIGHT := 60.0
const ENTITY_SURFACE_CLEARANCE := 1.0
const PLAYER_ENEMY_SPAWN_MIN_DISTANCE := 170.0
const MAX_LAYOUT_ATTEMPTS := 24
const PLAYER_DEFAULT_MOVE_SPEED := 260.0
const PLAYER_DEFAULT_JUMP_FORCE := 380.0
const PLAYER_DEFAULT_GRAVITY := 1000.0
const PLAYER_DEFAULT_AIR_JUMPS := 1
const DEFAULT_MIN_CRITICAL_PATH_ROOMS := 5
const SOLID_GEOMETRY_LAYER := 1
const ONE_WAY_GEOMETRY_LAYER := 2


func generate(geometry_root: Node2D, backdrop: ColorRect, config: Dictionary) -> Dictionary:
	_clear_geometry(geometry_root)
	var settings_variant: Variant = config.get("generation", {})
	var settings: Dictionary = settings_variant if typeof(settings_variant) == TYPE_DICTIONARY else {}

	var room_count_min: int = int(settings.get("room_count_min", 7))
	var room_count_max: int = int(settings.get("room_count_max", 8))
	var room_count: int = randi_range(room_count_min, room_count_max)
	var columns: int = int(settings.get("columns", 3))
	var rows: int = int(settings.get("rows", 4))
	var room_width: float = float(settings.get("room_width", 420.0))
	var room_height: float = float(settings.get("room_height", 280.0))
	var spacing_x: float = float(settings.get("spacing_x", 640.0))
	var spacing_y: float = float(settings.get("spacing_y", 420.0))
	var origin_x: float = float(settings.get("origin_x", 340.0))
	var origin_y: float = float(settings.get("origin_y", 560.0))
	var start_cell: Vector2i = Vector2i(0, rows - 1)
	var shaft_platform_step: float = _effective_shaft_platform_step(settings)
	var generated: Dictionary = _build_validated_room_graph(columns, rows, room_count, start_cell, settings, shaft_platform_step)
	var rooms: Array = generated.get("rooms", [])
	var connections: Array = generated.get("connections", [])

	var room_map: Dictionary = {}
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var cell: Vector2i = room.get("cell", Vector2i.ZERO)
		var center: Vector2 = Vector2(origin_x + float(cell.x) * spacing_x, origin_y - float((rows - 1) - cell.y) * spacing_y)
		room["center"] = center
		room["room_width"] = room_width
		room["room_height"] = room_height
		room["room_surfaces"] = []
		room["openings"] = {"left": [], "right": [], "top": [], "bottom": []}
		room["connection_count"] = 0
		room_map[_cell_key(cell)] = room

	for connection_variant in connections:
		if typeof(connection_variant) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = connection_variant
		var from_cell: Vector2i = connection.get("from", Vector2i.ZERO)
		var to_cell: Vector2i = connection.get("to", Vector2i.ZERO)
		var from_room: Dictionary = room_map.get(_cell_key(from_cell), {})
		var to_room: Dictionary = room_map.get(_cell_key(to_cell), {})
		if from_room.is_empty() or to_room.is_empty():
			continue
		if from_cell.y == to_cell.y:
			_register_horizontal_connection(from_room, to_room)
		else:
			_register_vertical_connection(from_room, to_room)

	var shaft_surfaces: Array = []
	var corridor_surfaces: Array = []
	var bounds: Rect2 = Rect2(Vector2(origin_x - room_width, origin_y - float(rows) * spacing_y - room_height), Vector2(columns * spacing_x + room_width, rows * spacing_y + room_height * 2.0))

	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var built_room_surfaces: Array = _build_room(geometry_root, room, room_width, room_height)
		room["room_surfaces"] = built_room_surfaces
		bounds = _expand_bounds_with_room(bounds, room.get("center", Vector2.ZERO), room_width, room_height)

	for connection_variant in connections:
		if typeof(connection_variant) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = connection_variant
		var from_cell: Vector2i = connection.get("from", Vector2i.ZERO)
		var to_cell: Vector2i = connection.get("to", Vector2i.ZERO)
		var from_room: Dictionary = room_map.get(_cell_key(from_cell), {})
		var to_room: Dictionary = room_map.get(_cell_key(to_cell), {})
		if from_room.is_empty() or to_room.is_empty():
			continue
		if from_cell.y == to_cell.y:
			corridor_surfaces.append_array(_build_corridor(geometry_root, from_room, to_room, room_width))
		else:
			shaft_surfaces.append_array(_build_vertical_shaft(geometry_root, from_room, to_room, room_width, room_height, shaft_platform_step))

	_apply_backdrop(backdrop, bounds)

	var start_room: Dictionary = room_map.get(_cell_key(start_cell), {})
	var start_surface: Dictionary = _pick_surface_from_room(start_room)
	var player_spawn: Vector2 = start_surface.get("position", Vector2(120.0, 540.0))

	var special_rooms: Dictionary = _pick_special_rooms(rooms, connections, start_room)
	var chest_rooms: Array = special_rooms.get("chests", [])
	var altar_room: Dictionary = special_rooms.get("altar", {})
	var exit_room: Dictionary = special_rooms.get("exit", {})
	var critical_path: Array = special_rooms.get("critical_path", [])
	var room_roles: Dictionary = _build_room_role_map(rooms, start_room, exit_room, altar_room, chest_rooms, critical_path)

	var encounter_positions: Dictionary = {}
	var room_surfaces: Array = _collect_surfaces(rooms, "room_surfaces")
	var prioritized_surfaces: Dictionary = _partition_enemy_surfaces(room_surfaces, corridor_surfaces, shaft_surfaces, room_roles)
	var primary_surfaces: Array = prioritized_surfaces.get("preferred", [])
	primary_surfaces = _filter_surfaces_far_from_player(primary_surfaces, player_spawn)
	_shuffle_array(primary_surfaces)
	var secondary_surfaces: Array = prioritized_surfaces.get("fallback", [])
	secondary_surfaces = _filter_surfaces_far_from_player(secondary_surfaces, player_spawn)
	_shuffle_array(secondary_surfaces)
	var reusable_surfaces: Array = []
	reusable_surfaces.append_array(primary_surfaces)
	reusable_surfaces.append_array(secondary_surfaces)
	if reusable_surfaces.is_empty():
		reusable_surfaces = _collect_surfaces(rooms, "room_surfaces")
	if reusable_surfaces.is_empty() and not start_room.is_empty():
		reusable_surfaces.append(_pick_surface_from_room(start_room))

	for encounter_config_variant in config.get("encounters", []):
		if typeof(encounter_config_variant) != TYPE_DICTIONARY:
			continue
		var encounter_config: Dictionary = encounter_config_variant
		var node_name: String = String(encounter_config.get("node_name", ""))
		if node_name.is_empty() or reusable_surfaces.is_empty():
			continue
		var chosen_surface: Dictionary = {}
		if not primary_surfaces.is_empty():
			chosen_surface = primary_surfaces.pop_front()
		elif not secondary_surfaces.is_empty():
			chosen_surface = secondary_surfaces.pop_front()
		else:
			var attempts: int = min(reusable_surfaces.size(), 12)
			while attempts > 0:
				var candidate_surface: Dictionary = reusable_surfaces[randi_range(0, reusable_surfaces.size() - 1)] as Dictionary
				var candidate_position: Vector2 = candidate_surface.get("enemy_position", candidate_surface.get("position", Vector2.ZERO))
				if candidate_position.distance_to(player_spawn) >= PLAYER_ENEMY_SPAWN_MIN_DISTANCE:
					chosen_surface = candidate_surface
					break
				attempts -= 1
			if chosen_surface.is_empty():
				chosen_surface = reusable_surfaces[randi_range(0, reusable_surfaces.size() - 1)]
		encounter_positions[node_name] = {
			"position": chosen_surface.get("enemy_position", chosen_surface.get("position", Vector2.ZERO)),
			"patrol_distance": chosen_surface.get("patrol_distance", 36.0),
			"left_bound": chosen_surface.get("left_bound", chosen_surface.get("position", Vector2.ZERO).x - 48.0),
			"right_bound": chosen_surface.get("right_bound", chosen_surface.get("position", Vector2.ZERO).x + 48.0)
		}

	var chest_positions: Dictionary = {}
	var chest_configs: Array = config.get("chests", [])
	for index in range(min(chest_configs.size(), chest_rooms.size())):
		var chest_config: Dictionary = chest_configs[index]
		var node_name: String = String(chest_config.get("node_name", ""))
		if node_name.is_empty():
			continue
		chest_positions[node_name] = _pick_room_object_position(chest_rooms[index])

	var altar_positions: Dictionary = {}
	for altar_config_variant in config.get("altars", []):
		if typeof(altar_config_variant) != TYPE_DICTIONARY:
			continue
		var altar_config: Dictionary = altar_config_variant
		var node_name: String = String(altar_config.get("node_name", ""))
		if node_name.is_empty() or altar_room.is_empty():
			continue
		altar_positions[node_name] = _pick_room_object_position(altar_room)

	var exit_position: Vector2 = _pick_exit_position(exit_room) if not exit_room.is_empty() else Vector2.ZERO
	var room_descriptors: Array = _build_room_descriptors(rooms, room_roles, config)

	return {
		"player_spawn": player_spawn,
		"camera_limits": {
			"left": int(floor(bounds.position.x - 160.0)),
			"top": int(floor(bounds.position.y - 160.0)),
			"right": int(ceil(bounds.end.x + 160.0)),
			"bottom": int(ceil(bounds.end.y + 160.0))
		},
		"encounters": encounter_positions,
		"chests": chest_positions,
		"altars": altar_positions,
		"exit": exit_position,
		"critical_path": critical_path,
		"rooms": room_descriptors
	}


func _build_room_graph(columns: int, rows: int, room_count: int, start_cell: Vector2i) -> Dictionary:
	var rooms: Array = []
	var connections: Array = []
	var visited: Dictionary = {}
	var frontier: Array = [start_cell]
	visited[_cell_key(start_cell)] = true
	rooms.append({"cell": start_cell})

	while rooms.size() < room_count:
		var candidates: Array = []
		for frontier_cell in frontier:
			for neighbor in _neighbors(frontier_cell, columns, rows):
				var key: String = _cell_key(neighbor)
				if visited.has(key):
					continue
				candidates.append({"from": frontier_cell, "to": neighbor})
		if candidates.is_empty():
			break
		candidates.shuffle()
		var chosen: Dictionary = candidates[0]
		var next_cell: Vector2i = chosen.get("to", start_cell)
		visited[_cell_key(next_cell)] = true
		frontier.append(next_cell)
		rooms.append({"cell": next_cell})
		connections.append({"from": chosen.get("from", start_cell), "to": next_cell})

	return {"rooms": rooms, "connections": connections}


func _build_validated_room_graph(columns: int, rows: int, room_count: int, start_cell: Vector2i, settings: Dictionary, shaft_platform_step: float) -> Dictionary:
	var attempt: int = 0
	var min_critical_path_rooms: int = max(2, int(settings.get("min_critical_path_rooms", DEFAULT_MIN_CRITICAL_PATH_ROOMS)))
	while attempt < MAX_LAYOUT_ATTEMPTS:
		var generated: Dictionary = _build_room_graph(columns, rows, room_count, start_cell)
		if _is_graph_traversable(generated, start_cell) and _is_graph_gameplay_traversable(generated, settings, shaft_platform_step) and _has_sufficient_critical_path(generated, start_cell, min_critical_path_rooms):
			return generated
		attempt += 1
	return _build_room_graph(columns, rows, room_count, start_cell)


func _is_graph_traversable(generated: Dictionary, start_cell: Vector2i) -> bool:
	var rooms: Array = generated.get("rooms", [])
	var connections: Array = generated.get("connections", [])
	if rooms.is_empty():
		return false
	var room_keys: Dictionary = {}
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var cell: Vector2i = room.get("cell", Vector2i.ZERO)
		room_keys[_cell_key(cell)] = true
	var start_key: String = _cell_key(start_cell)
	if not room_keys.has(start_key):
		return false
	var adjacency: Dictionary = {}
	for key_variant in room_keys.keys():
		var key: String = String(key_variant)
		adjacency[key] = []
	for connection_variant in connections:
		if typeof(connection_variant) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = connection_variant
		var from_cell: Vector2i = connection.get("from", Vector2i.ZERO)
		var to_cell: Vector2i = connection.get("to", Vector2i.ZERO)
		var from_key: String = _cell_key(from_cell)
		var to_key: String = _cell_key(to_cell)
		if not room_keys.has(from_key) or not room_keys.has(to_key):
			continue
		(adjacency[from_key] as Array).append(to_key)
		(adjacency[to_key] as Array).append(from_key)
	var visited: Dictionary = {}
	var stack: Array[String] = [start_key]
	while not stack.is_empty():
		var current: String = stack.pop_back()
		if visited.has(current):
			continue
		visited[current] = true
		var neighbors: Array = adjacency.get(current, [])
		for neighbor_variant in neighbors:
			var neighbor: String = String(neighbor_variant)
			if not visited.has(neighbor):
				stack.append(neighbor)
	if visited.size() != room_keys.size():
		return false
	for key_variant in room_keys.keys():
		var node_key: String = String(key_variant)
		var degree: int = (adjacency.get(node_key, []) as Array).size()
		if room_keys.size() > 1 and degree == 0:
			return false
	return true


func _is_graph_gameplay_traversable(generated: Dictionary, settings: Dictionary, shaft_platform_step: float) -> bool:
	var connections: Array = generated.get("connections", [])
	var has_vertical_connection: bool = false
	for connection_variant in connections:
		if typeof(connection_variant) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = connection_variant
		var from_cell: Vector2i = connection.get("from", Vector2i.ZERO)
		var to_cell: Vector2i = connection.get("to", Vector2i.ZERO)
		if from_cell.y != to_cell.y:
			has_vertical_connection = true
			break
	if not has_vertical_connection:
		return true

	var jump_force: float = absf(float(settings.get("player_jump_force", PLAYER_DEFAULT_JUMP_FORCE)))
	var gravity: float = maxf(float(settings.get("player_gravity", PLAYER_DEFAULT_GRAVITY)), 1.0)
	var move_speed: float = maxf(float(settings.get("player_move_speed", PLAYER_DEFAULT_MOVE_SPEED)), 1.0)
	var air_jumps: int = max(0, int(settings.get("player_air_jumps", PLAYER_DEFAULT_AIR_JUMPS)))
	var jump_segments: float = float(air_jumps + 1)
	var max_vertical_reach: float = (jump_force * jump_force / (2.0 * gravity)) * jump_segments
	var max_air_time: float = (2.0 * jump_force / gravity) * jump_segments
	var max_horizontal_reach: float = move_speed * max_air_time

	var required_vertical_step: float = maxf(76.0, shaft_platform_step + 44.0)
	var required_horizontal_step: float = SHAFT_WIDTH * 0.48 + 12.0
	if max_vertical_reach < required_vertical_step:
		return false
	if max_horizontal_reach < required_horizontal_step:
		return false
	return true


func _has_sufficient_critical_path(generated: Dictionary, start_cell: Vector2i, min_critical_path_rooms: int) -> bool:
	var rooms: Array = generated.get("rooms", [])
	var connections: Array = generated.get("connections", [])
	if rooms.is_empty():
		return false
	var adjacency: Dictionary = _build_room_adjacency(rooms, connections)
	var start_key: String = _cell_key(start_cell)
	var distance_map: Dictionary = _build_distance_map(adjacency, start_key)
	if distance_map.is_empty():
		return false
	var max_distance: int = 0
	for distance_variant in distance_map.values():
		max_distance = max(max_distance, int(distance_variant))
	return max_distance + 1 >= min_critical_path_rooms


func _neighbors(cell: Vector2i, columns: int, rows: int) -> Array:
	var neighbors: Array = []
	for delta in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var next: Vector2i = cell + delta
		if next.x < 0 or next.x >= columns:
			continue
		if next.y < 0 or next.y >= rows:
			continue
		neighbors.append(next)
	return neighbors


func _register_horizontal_connection(room_a: Dictionary, room_b: Dictionary) -> void:
	var left_room: Dictionary = room_a if (room_a.get("center", Vector2.ZERO) as Vector2).x < (room_b.get("center", Vector2.ZERO) as Vector2).x else room_b
	var right_room: Dictionary = room_b if left_room == room_a else room_a
	var left_openings: Dictionary = left_room.get("openings", {})
	var right_openings: Dictionary = right_room.get("openings", {})
	left_openings["right"].append(_side_door_center_y(left_room))
	right_openings["left"].append(_side_door_center_y(right_room))
	left_room["connection_count"] = int(left_room.get("connection_count", 0)) + 1
	right_room["connection_count"] = int(right_room.get("connection_count", 0)) + 1


func _register_vertical_connection(room_a: Dictionary, room_b: Dictionary) -> void:
	var lower_room: Dictionary = room_a
	var upper_room: Dictionary = room_b
	if (room_a.get("center", Vector2.ZERO) as Vector2).y < (room_b.get("center", Vector2.ZERO) as Vector2).y:
		lower_room = room_b
		upper_room = room_a
	var lower_center: Vector2 = lower_room.get("center", Vector2.ZERO)
	var upper_center: Vector2 = upper_room.get("center", Vector2.ZERO)
	var opening_x: float = lerpf(lower_center.x, upper_center.x, 0.5)
	opening_x = clampf(opening_x, lower_center.x - float(lower_room.get("room_width", 420.0)) * 0.25, lower_center.x + float(lower_room.get("room_width", 420.0)) * 0.25)
	var lower_openings: Dictionary = lower_room.get("openings", {})
	var upper_openings: Dictionary = upper_room.get("openings", {})
	lower_openings["top"].append(opening_x)
	upper_openings["bottom"].append(opening_x)
	lower_room["shaft_x"] = opening_x
	upper_room["shaft_x"] = opening_x
	lower_room["connection_count"] = int(lower_room.get("connection_count", 0)) + 1
	upper_room["connection_count"] = int(upper_room.get("connection_count", 0)) + 1


func _build_room(geometry_root: Node2D, room: Dictionary, room_width: float, room_height: float) -> Array:
	var center: Vector2 = room.get("center", Vector2.ZERO)
	var openings: Dictionary = room.get("openings", {})
	var room_key: String = _cell_key(room.get("cell", Vector2i.ZERO))
	var left_x: float = center.x - room_width * 0.5
	var right_x: float = center.x + room_width * 0.5
	var top_y: float = center.y - room_height * 0.5
	var bottom_y: float = center.y + room_height * 0.5
	_add_fill(geometry_root, Rect2(Vector2(left_x, top_y), Vector2(room_width, room_height)), ROOM_FILL_COLOR)
	_add_horizontal_wall(geometry_root, top_y, left_x, right_x, openings.get("top", []), true)
	_add_horizontal_wall(geometry_root, bottom_y, left_x, right_x, openings.get("bottom", []), false)
	_add_vertical_wall(geometry_root, left_x, top_y, bottom_y, openings.get("left", []))
	_add_vertical_wall(geometry_root, right_x, top_y, bottom_y, openings.get("right", []))
	var surface_width: float = room_width - WALL_THICKNESS * 2.0 - SURFACE_MARGIN * 2.0
	var surface_left_x: float = center.x - surface_width * 0.5 + SURFACE_SAFE_PADDING
	var surface_right_x: float = center.x + surface_width * 0.5 - SURFACE_SAFE_PADDING
	var floor_top_y: float = bottom_y - FLOOR_THICKNESS * 0.5
	return [{
		"position": Vector2(center.x, bottom_y - SURFACE_OBJECT_OFFSET),
		"enemy_position": Vector2(center.x, _enemy_center_y_from_surface(bottom_y, FLOOR_THICKNESS * 0.5)),
		"kind": "room",
		"room_key": room_key,
		"patrol_distance": maxf(surface_width * 0.5 - SURFACE_SAFE_PADDING, 24.0),
		"left_bound": minf(surface_left_x, surface_right_x),
		"right_bound": maxf(surface_left_x, surface_right_x),
		"floor_top_y": floor_top_y
	}]


func _build_corridor(geometry_root: Node2D, room_a: Dictionary, room_b: Dictionary, room_width: float) -> Array:
	var center_a: Vector2 = room_a.get("center", Vector2.ZERO)
	var center_b: Vector2 = room_b.get("center", Vector2.ZERO)
	var left_room: Dictionary = room_a if center_a.x < center_b.x else room_b
	var right_room: Dictionary = room_b if left_room == room_a else room_a
	var left_center: Vector2 = left_room.get("center", Vector2.ZERO)
	var right_center: Vector2 = right_room.get("center", Vector2.ZERO)
	var start_x: float = left_center.x + room_width * 0.5 - WALL_THICKNESS - CONNECTION_OVERLAP
	var end_x: float = right_center.x - room_width * 0.5 + WALL_THICKNESS + CONNECTION_OVERLAP
	var corridor_length: float = maxf(end_x - start_x, 120.0)
	var corridor_floor_y: float = _room_floor_y(left_room)
	_add_fill(geometry_root, Rect2(Vector2(start_x, corridor_floor_y - CORRIDOR_HEIGHT + FLOOR_THICKNESS * 0.5), Vector2(corridor_length, CORRIDOR_HEIGHT)), ROOM_FILL_COLOR)
	_add_segment(geometry_root, Vector2(start_x + corridor_length * 0.5, corridor_floor_y - CORRIDOR_HEIGHT + FLOOR_THICKNESS), Vector2(corridor_length, FLOOR_THICKNESS), WALL_COLOR)
	_add_segment(geometry_root, Vector2(start_x + corridor_length * 0.5, corridor_floor_y), Vector2(corridor_length, FLOOR_THICKNESS), PLATFORM_COLOR)
	# Bridge lips at room-prolet joins to keep floor continuity readable and walkable.
	_add_segment(geometry_root, Vector2(start_x + ENTRY_PLATFORM_WIDTH * 0.5, corridor_floor_y), Vector2(ENTRY_PLATFORM_WIDTH, FLOOR_THICKNESS), PLATFORM_COLOR)
	_add_segment(geometry_root, Vector2(end_x - ENTRY_PLATFORM_WIDTH * 0.5, corridor_floor_y), Vector2(ENTRY_PLATFORM_WIDTH, FLOOR_THICKNESS), PLATFORM_COLOR)
	var patrol_half: float = maxf(corridor_length * 0.5 - SURFACE_MARGIN - SURFACE_SAFE_PADDING, 24.0)
	return [{
		"position": Vector2(start_x + corridor_length * 0.5, corridor_floor_y - SURFACE_OBJECT_OFFSET),
		"enemy_position": Vector2(start_x + corridor_length * 0.5, _enemy_center_y_from_surface(corridor_floor_y, FLOOR_THICKNESS * 0.5)),
		"kind": "corridor",
		"patrol_distance": patrol_half,
		"left_bound": start_x + SURFACE_MARGIN + SURFACE_SAFE_PADDING,
		"right_bound": end_x - SURFACE_MARGIN - SURFACE_SAFE_PADDING,
		"floor_top_y": corridor_floor_y - FLOOR_THICKNESS * 0.5
	}]


func _build_vertical_shaft(geometry_root: Node2D, room_a: Dictionary, room_b: Dictionary, _room_width: float, room_height: float, shaft_platform_step: float) -> Array:
	var lower_room: Dictionary = room_a
	var upper_room: Dictionary = room_b
	if (room_a.get("center", Vector2.ZERO) as Vector2).y < (room_b.get("center", Vector2.ZERO) as Vector2).y:
		lower_room = room_b
		upper_room = room_a
	var shaft_center_x: float = float(lower_room.get("shaft_x", lower_room.get("center", Vector2.ZERO).x))
	var lower_top_y: float = _room_ceiling_y(lower_room)
	var lower_floor_y: float = _room_floor_y(lower_room)
	var upper_bottom_y: float = _room_floor_y(upper_room)
	var top_y: float = upper_bottom_y - FLOOR_THICKNESS + CONNECTION_OVERLAP
	var bottom_y: float = lower_top_y + FLOOR_THICKNESS - CONNECTION_OVERLAP
	if bottom_y < top_y:
		var swap: float = bottom_y
		bottom_y = top_y
		top_y = swap
	var height: float = maxf(bottom_y - top_y, room_height)
	_add_fill(geometry_root, Rect2(Vector2(shaft_center_x - SHAFT_WIDTH * 0.5, top_y), Vector2(SHAFT_WIDTH, height)), Color(0.196078, 0.207843, 0.270588, 0.62))
	_add_segment(geometry_root, Vector2(shaft_center_x - SHAFT_WIDTH * 0.5, top_y + height * 0.5), Vector2(WALL_THICKNESS, height), WALL_COLOR)
	_add_segment(geometry_root, Vector2(shaft_center_x + SHAFT_WIDTH * 0.5, top_y + height * 0.5), Vector2(WALL_THICKNESS, height), WALL_COLOR)

	var surfaces: Array = []
	var approach_y: float = lower_floor_y - 76.0
	var approach_toggle_left: bool = false
	# Keep the entry opening clean: do not place an extra step directly under the opening platform.
	while approach_y > bottom_y + shaft_platform_step + 24.0:
		var approach_x: float = shaft_center_x
		if approach_y < lower_floor_y - 110.0:
			approach_x = shaft_center_x + (-SHAFT_WIDTH * 0.24 if approach_toggle_left else SHAFT_WIDTH * 0.24)
			approach_toggle_left = not approach_toggle_left
		_add_shaft_platform(geometry_root, surfaces, approach_x, approach_y, SHAFT_APPROACH_PLATFORM_WIDTH)
		approach_y -= shaft_platform_step

	var current_y: float = bottom_y - shaft_platform_step
	var toggle_left: bool = true
	while current_y > top_y + 44.0:
		var platform_x: float = shaft_center_x + (-SHAFT_WIDTH * 0.24 if toggle_left else SHAFT_WIDTH * 0.24)
		_add_shaft_platform(geometry_root, surfaces, platform_x, current_y, SHAFT_PLATFORM_WIDTH)
		current_y -= shaft_platform_step
		toggle_left = not toggle_left
	return surfaces


func _add_vertical_wall(geometry_root: Node2D, x: float, top_y: float, bottom_y: float, openings_variant: Variant) -> void:
	if typeof(openings_variant) != TYPE_ARRAY or (openings_variant as Array).is_empty():
		_add_segment(geometry_root, Vector2(x, (top_y + bottom_y) * 0.5), Vector2(WALL_THICKNESS, bottom_y - top_y), WALL_COLOR)
		return
	var openings: Array = (openings_variant as Array).duplicate()
	openings.sort()
	var cursor: float = top_y
	for opening_center_variant in openings:
		var opening_center: float = float(opening_center_variant)
		var opening_top: float = opening_center - SIDE_DOOR_HEIGHT * 0.5
		var opening_bottom: float = opening_center + SIDE_DOOR_HEIGHT * 0.5
		if opening_top > cursor:
			_add_segment(geometry_root, Vector2(x, (cursor + opening_top) * 0.5), Vector2(WALL_THICKNESS, opening_top - cursor), WALL_COLOR)
		cursor = opening_bottom
	if bottom_y > cursor:
		_add_segment(geometry_root, Vector2(x, (cursor + bottom_y) * 0.5), Vector2(WALL_THICKNESS, bottom_y - cursor), WALL_COLOR)


func _add_horizontal_wall(geometry_root: Node2D, y: float, left_x: float, right_x: float, openings_variant: Variant, _is_ceiling: bool) -> void:
	if typeof(openings_variant) != TYPE_ARRAY or (openings_variant as Array).is_empty():
		_add_segment(geometry_root, Vector2((left_x + right_x) * 0.5, y), Vector2(right_x - left_x, FLOOR_THICKNESS), WALL_COLOR)
		return
	var openings: Array = (openings_variant as Array).duplicate()
	openings.sort()
	var cursor: float = left_x
	for opening_center_variant in openings:
		var opening_center: float = float(opening_center_variant)
		var opening_left: float = opening_center - VERTICAL_DOOR_WIDTH * 0.5
		var opening_right: float = opening_center + VERTICAL_DOOR_WIDTH * 0.5
		if opening_left > cursor:
			_add_segment(geometry_root, Vector2((cursor + opening_left) * 0.5, y), Vector2(opening_left - cursor, FLOOR_THICKNESS), WALL_COLOR)
		var opening_platform_y: float = y
		_add_segment(
			geometry_root,
			Vector2(opening_center, opening_platform_y),
			Vector2(VERTICAL_DOOR_WIDTH, SHAFT_PLATFORM_HEIGHT),
			PLATFORM_COLOR,
			true
		)
		cursor = opening_right
	if right_x > cursor:
		_add_segment(geometry_root, Vector2((cursor + right_x) * 0.5, y), Vector2(right_x - cursor, FLOOR_THICKNESS), WALL_COLOR)


func _add_shaft_platform(geometry_root: Node2D, surfaces: Array, platform_x: float, platform_y: float, width: float) -> void:
	_add_segment(geometry_root, Vector2(platform_x, platform_y), Vector2(width, SHAFT_PLATFORM_HEIGHT), PLATFORM_COLOR, true)
	var patrol_half: float = maxf(width * 0.5 - 16.0 - SURFACE_SAFE_PADDING, 18.0)
	surfaces.append({
		"position": Vector2(platform_x, platform_y - SURFACE_OBJECT_OFFSET),
		"enemy_position": Vector2(platform_x, _enemy_center_y_from_surface(platform_y, SHAFT_PLATFORM_HEIGHT * 0.5)),
		"kind": "shaft",
		"patrol_distance": patrol_half,
		"left_bound": platform_x - width * 0.5 + 16.0 + SURFACE_SAFE_PADDING,
		"right_bound": platform_x + width * 0.5 - 16.0 - SURFACE_SAFE_PADDING,
		"floor_top_y": platform_y - SHAFT_PLATFORM_HEIGHT * 0.5
	})


func _add_segment(geometry_root: Node2D, center: Vector2, size: Vector2, color: Color, one_way: bool = false) -> void:
	var body := StaticBody2D.new()
	body.position = center
	body.add_to_group("level_geometry")
	body.collision_layer = ONE_WAY_GEOMETRY_LAYER if one_way else SOLID_GEOMETRY_LAYER
	body.collision_mask = 0
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = size
	collision.shape = shape
	if one_way:
		collision.one_way_collision = true
		collision.one_way_collision_margin = 2.0
	body.add_child(collision)
	var visual := ColorRect.new()
	visual.color = color
	visual.position = -size * 0.5
	visual.size = size
	body.add_child(visual)
	geometry_root.add_child(body)


func _add_fill(geometry_root: Node2D, rect: Rect2, color: Color) -> void:
	var fill := ColorRect.new()
	fill.position = rect.position
	fill.size = rect.size
	fill.color = color
	geometry_root.add_child(fill)


func _apply_backdrop(backdrop: ColorRect, bounds: Rect2) -> void:
	backdrop.color = BACKDROP_COLOR
	backdrop.position = bounds.position - Vector2(220.0, 220.0)
	backdrop.size = bounds.size + Vector2(440.0, 440.0)


func _expand_bounds_with_room(bounds: Rect2, center: Vector2, room_width: float, room_height: float) -> Rect2:
	var room_rect := Rect2(center - Vector2(room_width * 0.5, room_height * 0.5), Vector2(room_width, room_height))
	return bounds.merge(room_rect)


func _pick_special_rooms(rooms: Array, connections: Array, start_room: Dictionary) -> Dictionary:
	var candidates: Array = []
	var endpoint_candidates: Array = []
	var start_center: Vector2 = start_room.get("center", Vector2.ZERO)
	var rooms_by_key: Dictionary = {}
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_key: String = _cell_key(room.get("cell", Vector2i.ZERO))
		rooms_by_key[room_key] = room
		if room == start_room:
			continue
		candidates.append(room)
		if int(room.get("connection_count", 0)) <= 1:
			endpoint_candidates.append(room)
	var start_key: String = _cell_key(start_room.get("cell", Vector2i.ZERO))
	var adjacency: Dictionary = _build_room_adjacency(rooms, connections)
	var distance_map: Dictionary = _build_distance_map(adjacency, start_key)
	var exit_pool: Array = endpoint_candidates if not endpoint_candidates.is_empty() else candidates.duplicate()
	exit_pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_key: String = _cell_key(a.get("cell", Vector2i.ZERO))
		var b_key: String = _cell_key(b.get("cell", Vector2i.ZERO))
		var a_distance: int = int(distance_map.get(a_key, 0))
		var b_distance: int = int(distance_map.get(b_key, 0))
		if a_distance == b_distance:
			return (a.get("center", Vector2.ZERO) as Vector2).distance_squared_to(start_center) > (b.get("center", Vector2.ZERO) as Vector2).distance_squared_to(start_center)
		return a_distance > b_distance
	)
	var exit_room: Dictionary = {}
	if not exit_pool.is_empty():
		exit_room = exit_pool[0]
		candidates.erase(exit_room)
	var critical_path: Array = []
	if not exit_room.is_empty():
		var exit_key: String = _cell_key(exit_room.get("cell", Vector2i.ZERO))
		var path_keys: Array = _build_path_between(adjacency, start_key, exit_key)
		for path_key_variant in path_keys:
			var path_key: String = String(path_key_variant)
			if rooms_by_key.has(path_key):
				critical_path.append(rooms_by_key[path_key])
	var path_room_keys: Dictionary = {}
	for room_variant in critical_path:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var path_room: Dictionary = room_variant
		path_room_keys[_cell_key(path_room.get("cell", Vector2i.ZERO))] = true
	var off_path_candidates: Array = []
	var on_path_candidates: Array = []
	for candidate_variant in candidates:
		if typeof(candidate_variant) != TYPE_DICTIONARY:
			continue
		var candidate_room: Dictionary = candidate_variant
		var candidate_key: String = _cell_key(candidate_room.get("cell", Vector2i.ZERO))
		if path_room_keys.has(candidate_key):
			on_path_candidates.append(candidate_room)
		else:
			off_path_candidates.append(candidate_room)
	_shuffle_array(off_path_candidates)
	_shuffle_array(on_path_candidates)
	var ordered_candidates: Array = []
	ordered_candidates.append_array(off_path_candidates)
	ordered_candidates.append_array(on_path_candidates)
	var altar_room: Dictionary = {}
	if not ordered_candidates.is_empty():
		altar_room = ordered_candidates.pop_front()
	var chest_rooms: Array = []
	while not ordered_candidates.is_empty() and chest_rooms.size() < 2:
		chest_rooms.append(ordered_candidates.pop_front())
	return {"exit": exit_room, "altar": altar_room, "chests": chest_rooms, "critical_path": critical_path}


func _build_room_role_map(rooms: Array, start_room: Dictionary, exit_room: Dictionary, altar_room: Dictionary, chest_rooms: Array, critical_path: Array) -> Dictionary:
	var roles: Dictionary = {}
	var chest_keys: Dictionary = {}
	for chest_variant in chest_rooms:
		if typeof(chest_variant) != TYPE_DICTIONARY:
			continue
		var chest_room: Dictionary = chest_variant
		chest_keys[_cell_key(chest_room.get("cell", Vector2i.ZERO))] = true
	var critical_path_keys: Dictionary = {}
	for path_variant in critical_path:
		if typeof(path_variant) != TYPE_DICTIONARY:
			continue
		var path_room: Dictionary = path_variant
		critical_path_keys[_cell_key(path_room.get("cell", Vector2i.ZERO))] = true
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_key: String = _cell_key(room.get("cell", Vector2i.ZERO))
		var role: String = "branch"
		if room_key == _cell_key(start_room.get("cell", Vector2i.ZERO)):
			role = "entry"
		elif room_key == _cell_key(exit_room.get("cell", Vector2i.ZERO)):
			role = "exit"
		elif room_key == _cell_key(altar_room.get("cell", Vector2i.ZERO)):
			role = "altar"
		elif chest_keys.has(room_key):
			role = "chest"
		elif critical_path_keys.has(room_key):
			role = "route"
		roles[room_key] = role
	return roles


func _build_room_descriptors(rooms: Array, room_roles: Dictionary, config: Dictionary) -> Array:
	var descriptors: Array = []
	var level_title: String = String(config.get("title", "Variables"))

	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_key: String = _cell_key(room.get("cell", Vector2i.ZERO))
		var role: String = String(room_roles.get(room_key, "branch"))
		var center: Vector2 = room.get("center", Vector2.ZERO)
		var room_width: float = float(room.get("room_width", 420.0))
		var room_height: float = float(room.get("room_height", 280.0))
		var rect := Rect2(
			Vector2(center.x - room_width * 0.5, center.y - room_height * 0.5),
			Vector2(room_width, room_height)
		)
		descriptors.append({
			"key": room_key,
			"role": role,
			"title": _room_title_for_role(role, level_title),
			"rect_position": rect.position,
			"rect_size": rect.size
		})
	return descriptors


func _partition_enemy_surfaces(room_surfaces: Array, corridor_surfaces: Array, shaft_surfaces: Array, room_roles: Dictionary) -> Dictionary:
	var preferred: Array = []
	var fallback: Array = []
	for surface_variant in room_surfaces:
		if typeof(surface_variant) != TYPE_DICTIONARY:
			continue
		var surface: Dictionary = surface_variant
		var room_key: String = String(surface.get("room_key", ""))
		var role: String = String(room_roles.get(room_key, "branch"))
		match role:
			"entry", "exit", "altar", "chest":
				fallback.append(surface)
			_:
				preferred.append(surface)
	preferred.append_array(corridor_surfaces)
	preferred.append_array(shaft_surfaces)
	return {"preferred": preferred, "fallback": fallback}


func _room_title_for_role(role: String, level_title: String) -> String:
	var is_conditions: bool = level_title.to_lower() == "if/else"
	var is_loops: bool = level_title.to_lower() == "loops"
	var is_functions: bool = level_title.to_lower() == "functions"
	var is_integration: bool = level_title.to_lower() == "integration"
	if is_conditions:
		match role:
			"entry":
				return "Logic Entry"
			"exit":
				return "Decision Gate"
			"altar":
				return "Branch Forge"
			"chest":
				return "Logic Cache"
			"route":
				return "Condition Route"
			_:
				return "Side Branch"
	if is_loops:
		match role:
			"entry":
				return "Loop Intake"
			"exit":
				return "Conduit Gate"
			"altar":
				return "Cycle Forge"
			"chest":
				return "Wave Cache"
			"route":
				return "Loop Route"
			_:
				return "Cycle Branch"
	if is_functions:
		match role:
			"entry":
				return "Codex Entry"
			"exit":
				return "Function Gate"
			"altar":
				return "Helper Forge"
			"chest":
				return "Routine Cache"
			"route":
				return "Function Route"
			_:
				return "Helper Branch"
	if is_integration:
		match role:
			"entry":
				return "System Entry"
			"exit":
				return "System Gate"
			"altar":
				return "Integration Forge"
			"chest":
				return "System Cache"
			"route":
				return "Integration Route"
			_:
				return "System Branch"
	match role:
		"entry":
			return "Entry Chamber"
		"exit":
			return "Exit Chamber"
		"altar":
			return "Weapon Altar"
		"chest":
			return "Supply Cache"
		"route":
			return "Archive Route"
		_:
			return "Side Archive"


func _build_room_adjacency(rooms: Array, connections: Array) -> Dictionary:
	var adjacency: Dictionary = {}
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var room_key: String = _cell_key(room.get("cell", Vector2i.ZERO))
		adjacency[room_key] = []
	for connection_variant in connections:
		if typeof(connection_variant) != TYPE_DICTIONARY:
			continue
		var connection: Dictionary = connection_variant
		var from_key: String = _cell_key(connection.get("from", Vector2i.ZERO))
		var to_key: String = _cell_key(connection.get("to", Vector2i.ZERO))
		if not adjacency.has(from_key) or not adjacency.has(to_key):
			continue
		(adjacency[from_key] as Array).append(to_key)
		(adjacency[to_key] as Array).append(from_key)
	return adjacency


func _build_distance_map(adjacency: Dictionary, start_key: String) -> Dictionary:
	var distances: Dictionary = {}
	if not adjacency.has(start_key):
		return distances
	var queue: Array[String] = [start_key]
	distances[start_key] = 0
	var index: int = 0
	while index < queue.size():
		var current: String = queue[index]
		index += 1
		var current_distance: int = int(distances.get(current, 0))
		var neighbors: Array = adjacency.get(current, [])
		for neighbor_variant in neighbors:
			var neighbor: String = String(neighbor_variant)
			if distances.has(neighbor):
				continue
			distances[neighbor] = current_distance + 1
			queue.append(neighbor)
	return distances


func _build_path_between(adjacency: Dictionary, start_key: String, end_key: String) -> Array:
	if not adjacency.has(start_key) or not adjacency.has(end_key):
		return []
	var came_from: Dictionary = {start_key: ""}
	var queue: Array[String] = [start_key]
	var index: int = 0
	while index < queue.size():
		var current: String = queue[index]
		index += 1
		if current == end_key:
			break
		var neighbors: Array = adjacency.get(current, [])
		for neighbor_variant in neighbors:
			var neighbor: String = String(neighbor_variant)
			if came_from.has(neighbor):
				continue
			came_from[neighbor] = current
			queue.append(neighbor)
	if not came_from.has(end_key):
		return []
	var path: Array = []
	var cursor: String = end_key
	while not cursor.is_empty():
		path.push_front(cursor)
		cursor = String(came_from.get(cursor, ""))
	return path


func _pick_surface_from_room(room: Dictionary) -> Dictionary:
	var room_surfaces_variant: Variant = room.get("room_surfaces", [])
	if typeof(room_surfaces_variant) != TYPE_ARRAY or (room_surfaces_variant as Array).is_empty():
		return {"position": room.get("center", Vector2.ZERO), "patrol_distance": 32.0}
	return (room_surfaces_variant as Array)[0]


func _pick_room_object_position(room: Dictionary) -> Vector2:
	var room_surface: Dictionary = _pick_surface_from_room(room)
	var surface_position: Vector2 = room_surface.get("position", room.get("center", Vector2.ZERO))
	return Vector2(surface_position.x, surface_position.y)


func _pick_exit_position(room: Dictionary) -> Vector2:
	if room.is_empty():
		return Vector2.ZERO
	var room_surface: Dictionary = _pick_surface_from_room(room)
	var room_center: Vector2 = room.get("center", Vector2.ZERO)
	var room_width: float = float(room.get("room_width", 420.0))
	var left_limit: float = room_center.x - room_width * 0.5 + WALL_THICKNESS + 52.0
	var right_limit: float = room_center.x + room_width * 0.5 - WALL_THICKNESS - 52.0
	if room_surface.has("left_bound"):
		left_limit = maxf(left_limit, float(room_surface.get("left_bound", left_limit)))
	if room_surface.has("right_bound"):
		right_limit = minf(right_limit, float(room_surface.get("right_bound", right_limit)))
	if left_limit > right_limit:
		var center_limit: float = (left_limit + right_limit) * 0.5
		left_limit = center_limit
		right_limit = center_limit
	var candidate_xs: Array[float] = [
		room_center.x - room_width * 0.22,
		room_center.x,
		room_center.x + room_width * 0.22
	]
	var chosen_x: float = room_center.x
	var chosen_score: float = -1.0
	var opening_xs: Array = []
	var openings: Dictionary = room.get("openings", {})
	opening_xs.append_array(openings.get("top", []))
	opening_xs.append_array(openings.get("bottom", []))
	for candidate_variant in candidate_xs:
		var candidate_x: float = clampf(float(candidate_variant), left_limit, right_limit)
		var min_clearance: float = 1000000.0
		for opening_variant in opening_xs:
			min_clearance = minf(min_clearance, absf(candidate_x - float(opening_variant)))
		if opening_xs.is_empty():
			min_clearance = 1000000.0
		if min_clearance > chosen_score:
			chosen_score = min_clearance
			chosen_x = candidate_x
	var floor_top_y: float = float(room_surface.get("floor_top_y", _room_floor_y(room) - FLOOR_THICKNESS * 0.5))
	return Vector2(chosen_x, floor_top_y - EXIT_HALF_HEIGHT)


func _enemy_center_y_from_surface(surface_center_y: float, surface_half_thickness: float) -> float:
	return surface_center_y - surface_half_thickness - ENEMY_HALF_HEIGHT - ENTITY_SURFACE_CLEARANCE


func _effective_shaft_platform_step(settings: Dictionary) -> float:
	var jump_force: float = absf(float(settings.get("player_jump_force", PLAYER_DEFAULT_JUMP_FORCE)))
	var gravity: float = maxf(float(settings.get("player_gravity", PLAYER_DEFAULT_GRAVITY)), 1.0)
	var air_jumps: int = max(0, int(settings.get("player_air_jumps", PLAYER_DEFAULT_AIR_JUMPS)))
	var jump_segments: float = float(air_jumps + 1)
	var max_vertical_reach: float = (jump_force * jump_force / (2.0 * gravity)) * jump_segments
	var safe_step: float = maxf(40.0, floor(max_vertical_reach * 0.58))
	return minf(SHAFT_PLATFORM_STEP, safe_step)


func _filter_surfaces_far_from_player(surfaces: Array, player_spawn: Vector2) -> Array:
	var filtered: Array = []
	for surface_variant in surfaces:
		if typeof(surface_variant) != TYPE_DICTIONARY:
			continue
		var surface: Dictionary = surface_variant
		var spawn_position: Vector2 = surface.get("enemy_position", surface.get("position", Vector2.ZERO))
		if spawn_position.distance_to(player_spawn) < PLAYER_ENEMY_SPAWN_MIN_DISTANCE:
			continue
		filtered.append(surface)
	return filtered


func _collect_surfaces(rooms: Array, key: String) -> Array:
	var collected: Array = []
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		var surfaces_variant: Variant = room.get(key, [])
		if typeof(surfaces_variant) != TYPE_ARRAY:
			continue
		collected.append_array(surfaces_variant as Array)
	return collected


func _clear_geometry(geometry_root: Node2D) -> void:
	for child in geometry_root.get_children():
		child.queue_free()


func _shuffle_array(values: Array) -> void:
	for index in range(values.size() - 1, 0, -1):
		var swap_index: int = randi_range(0, index)
		var temp: Variant = values[index]
		values[index] = values[swap_index]
		values[swap_index] = temp


func _room_floor_y(room: Dictionary) -> float:
	var center: Vector2 = room.get("center", Vector2.ZERO)
	var room_height: float = float(room.get("room_height", 280.0))
	return center.y + room_height * 0.5


func _room_ceiling_y(room: Dictionary) -> float:
	var center: Vector2 = room.get("center", Vector2.ZERO)
	var room_height: float = float(room.get("room_height", 280.0))
	return center.y - room_height * 0.5


func _side_door_center_y(room: Dictionary) -> float:
	return _room_floor_y(room) - SIDE_DOOR_CLEARANCE


func _cell_key(cell: Vector2i) -> String:
	return "%d:%d" % [cell.x, cell.y]
