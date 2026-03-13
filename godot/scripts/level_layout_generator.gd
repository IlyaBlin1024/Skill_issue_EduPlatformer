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
const SURFACE_ENTITY_OFFSET := 24.0
const SURFACE_OBJECT_OFFSET := 26.0
const SIDE_DOOR_CLEARANCE := 60.0
const SURFACE_MARGIN := 22.0
const CONNECTION_OVERLAP := 18.0
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

	var generated: Dictionary = _build_room_graph(columns, rows, room_count, start_cell)
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
		var room_surfaces: Array = _build_room(geometry_root, room, room_width, room_height)
		room["room_surfaces"] = room_surfaces
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
			shaft_surfaces.append_array(_build_vertical_shaft(geometry_root, from_room, to_room, room_width, room_height))

	_apply_backdrop(backdrop, bounds)

	var start_room: Dictionary = room_map.get(_cell_key(start_cell), {})
	var start_surface: Dictionary = _pick_surface_from_room(start_room)
	var player_spawn: Vector2 = start_surface.get("position", Vector2(120.0, 540.0))

	var special_rooms: Dictionary = _pick_special_rooms(rooms, start_room)
	var chest_rooms: Array = special_rooms.get("chests", [])
	var altar_room: Dictionary = special_rooms.get("altar", {})
	var exit_room: Dictionary = special_rooms.get("exit", {})

	var encounter_positions: Dictionary = {}
	var encounter_surfaces: Array = []
	encounter_surfaces.append_array(_collect_surfaces(rooms, "room_surfaces"))
	encounter_surfaces.append_array(shaft_surfaces)
	encounter_surfaces.append_array(corridor_surfaces)
	_shuffle_array(encounter_surfaces)

	for encounter_config_variant in config.get("encounters", []):
		if typeof(encounter_config_variant) != TYPE_DICTIONARY:
			continue
		var encounter_config: Dictionary = encounter_config_variant
		var node_name: String = String(encounter_config.get("node_name", ""))
		if node_name.is_empty() or encounter_surfaces.is_empty():
			continue
		var chosen_surface: Dictionary = encounter_surfaces.pop_front()
		encounter_positions[node_name] = {
			"position": chosen_surface.get("position", Vector2.ZERO),
			"patrol_distance": chosen_surface.get("patrol_distance", 36.0)
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

	var exit_position: Vector2 = _pick_room_object_position(exit_room) if not exit_room.is_empty() else Vector2.ZERO

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
		"exit": exit_position
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
	return [{
		"position": Vector2(center.x, bottom_y - SURFACE_OBJECT_OFFSET),
		"kind": "room",
		"patrol_distance": maxf(surface_width * 0.5, 24.0)
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
	return [{
		"position": Vector2(start_x + corridor_length * 0.5, corridor_floor_y - SURFACE_ENTITY_OFFSET),
		"kind": "corridor",
		"patrol_distance": maxf(corridor_length * 0.5 - SURFACE_MARGIN, 24.0)
	}]


func _build_vertical_shaft(geometry_root: Node2D, room_a: Dictionary, room_b: Dictionary, room_width: float, room_height: float) -> Array:
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
	while approach_y > bottom_y + 30.0:
		var approach_x: float = shaft_center_x
		if approach_y < lower_floor_y - 110.0:
			approach_x = shaft_center_x + (-SHAFT_WIDTH * 0.24 if approach_toggle_left else SHAFT_WIDTH * 0.24)
			approach_toggle_left = not approach_toggle_left
		_add_shaft_platform(geometry_root, surfaces, approach_x, approach_y, SHAFT_APPROACH_PLATFORM_WIDTH)
		approach_y -= SHAFT_PLATFORM_STEP

	var entry_y: float = bottom_y - 42.0
	_add_shaft_platform(geometry_root, surfaces, shaft_center_x, entry_y, SHAFT_PLATFORM_WIDTH + 28.0)

	var current_y: float = entry_y - SHAFT_PLATFORM_STEP
	var toggle_left: bool = true
	while current_y > top_y + 44.0:
		var platform_x: float = shaft_center_x + (-SHAFT_WIDTH * 0.24 if toggle_left else SHAFT_WIDTH * 0.24)
		_add_shaft_platform(geometry_root, surfaces, platform_x, current_y, SHAFT_PLATFORM_WIDTH)
		current_y -= SHAFT_PLATFORM_STEP
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


func _add_horizontal_wall(geometry_root: Node2D, y: float, left_x: float, right_x: float, openings_variant: Variant, is_ceiling: bool) -> void:
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
		cursor = opening_right
	if right_x > cursor:
		_add_segment(geometry_root, Vector2((cursor + right_x) * 0.5, y), Vector2(right_x - cursor, FLOOR_THICKNESS), WALL_COLOR)


func _add_shaft_platform(geometry_root: Node2D, surfaces: Array, platform_x: float, platform_y: float, width: float) -> void:
	_add_segment(geometry_root, Vector2(platform_x, platform_y), Vector2(width, SHAFT_PLATFORM_HEIGHT), PLATFORM_COLOR, true)
	surfaces.append({
		"position": Vector2(platform_x, platform_y - SURFACE_ENTITY_OFFSET),
		"kind": "shaft",
		"patrol_distance": maxf(width * 0.5 - 16.0, 18.0)
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


func _pick_special_rooms(rooms: Array, start_room: Dictionary) -> Dictionary:
	var candidates: Array = []
	var endpoint_candidates: Array = []
	var start_center: Vector2 = start_room.get("center", Vector2.ZERO)
	for room_variant in rooms:
		if typeof(room_variant) != TYPE_DICTIONARY:
			continue
		var room: Dictionary = room_variant
		if room == start_room:
			continue
		candidates.append(room)
		if int(room.get("connection_count", 0)) <= 1:
			endpoint_candidates.append(room)
	var exit_pool: Array = endpoint_candidates if not endpoint_candidates.is_empty() else candidates.duplicate()
	exit_pool.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a.get("center", Vector2.ZERO) as Vector2).distance_squared_to(start_center) > (b.get("center", Vector2.ZERO) as Vector2).distance_squared_to(start_center)
	)
	var exit_room: Dictionary = {}
	if not exit_pool.is_empty():
		exit_room = exit_pool[0]
		candidates.erase(exit_room)
	_shuffle_array(candidates)
	var altar_room: Dictionary = {}
	if not candidates.is_empty():
		altar_room = candidates.pop_front()
	var chest_rooms: Array = []
	while not candidates.is_empty() and chest_rooms.size() < 2:
		chest_rooms.append(candidates.pop_front())
	return {"exit": exit_room, "altar": altar_room, "chests": chest_rooms}


func _pick_surface_from_room(room: Dictionary) -> Dictionary:
	var room_surfaces_variant: Variant = room.get("room_surfaces", [])
	if typeof(room_surfaces_variant) != TYPE_ARRAY or (room_surfaces_variant as Array).is_empty():
		return {"position": room.get("center", Vector2.ZERO), "patrol_distance": 32.0}
	return (room_surfaces_variant as Array)[0]


func _pick_room_object_position(room: Dictionary) -> Vector2:
	var room_surface: Dictionary = _pick_surface_from_room(room)
	var surface_position: Vector2 = room_surface.get("position", room.get("center", Vector2.ZERO))
	return Vector2(surface_position.x, surface_position.y)


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
