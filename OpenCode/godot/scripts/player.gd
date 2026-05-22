extends CharacterBody2D

class_name PlayerController

signal health_changed(current_health: int, max_health: int)
signal defeated
signal combat_action_requested(facing_direction: Vector2)

const SOLID_GEOMETRY_LAYER := 1
const ONE_WAY_GEOMETRY_LAYER := 2
const PLAYER_SPRITE_DIRS := [
	"res://assets/production_art/models/characters/player",
	"res://assets/production_art/characters/player/spritesheets",
]
const PLAYER_SPRITE_CANVAS_SIZE := Vector2i(160, 128)
const PLAYER_SPRITE_TARGET_HEIGHT := 84
const PLAYER_SPRITE_MAX_WIDTH := 118
const PLAYER_SPRITE_FOOT_MARGIN := 4
const PLAYER_SPRITE_ANIMATIONS := {
	"idle": {"prefix": "player_idle", "fps": 6.0, "loop": true},
	"run": {"prefix": "player_run", "fps": 12.0, "loop": true},
	"jump": {"prefix": "player_jump", "fps": 10.0, "loop": false, "target_height": 72},
	"fall": {"prefix": "player_fall", "fps": 8.0, "loop": true},
	"wall_slide": {"prefix": "player_slippage", "fps": 6.0, "loop": true},
	"land": {"prefix": "player_land", "fps": 10.0, "loop": false},
	"hurt": {"prefix": "player_hurt", "fps": 10.0, "loop": false},
	"death": {"prefix": "player_death", "fps": 8.0, "loop": false},
	"parry_shield": {"prefix": "player_parry_shield", "fps": 12.0, "loop": false},
	"melee_combo_01": {"prefix": "player_melee_combo_01", "fps": 13.0, "loop": false, "target_height": 92, "max_width": 148},
	"melee_combo_02": {"prefix": "player_melee_combo_02", "fps": 13.0, "loop": false, "target_height": 94, "max_width": 150},
	"melee_combo_03": {"prefix": "player_melee_combo_03", "fps": 12.0, "loop": false, "target_height": 100, "max_width": 152},
	"ranged_combo_01": {"prefix": "player_ranged_combo_01", "fps": 13.0, "loop": false},
	"ranged_combo_02": {"prefix": "player_ranged_combo_02", "fps": 13.0, "loop": false},
	"ranged_combo_03": {"prefix": "player_ranged_combo_03", "fps": 12.0, "loop": false, "target_height": 108, "max_width": 152},
}
const PLAYER_COMBAT_ANIMATION_ALIASES := {
	"melee_one": "melee_combo_01",
	"melee_two": "melee_combo_02",
	"melee_three": "melee_combo_03",
	"ranged_one": "ranged_combo_01",
	"ranged_two": "ranged_combo_02",
	"ranged_three": "ranged_combo_03",
}

@export var move_speed: float = 260.0
@export var jump_force: float = -380.0
@export var gravity: float = 1000.0
@export var wall_slide_speed: float = 120.0
@export var wall_jump_push: float = 220.0
@export var max_health: int = 300
@export var max_air_jumps: int = 1
@export var drop_through_duration: float = 0.2
@export var parry_window: float = 0.22
@export var parry_cooldown: float = 0.55

@onready var body: ColorRect = $Body
@onready var camera: Camera2D = $Camera2D
@onready var slash_pivot: Node2D = $SlashPivot
@onready var slash_visual: TextureRect = $SlashPivot/SlashVisual

var current_health: int = 0
var _spawn_position: Vector2
var _base_color := Color(0.74, 0.82, 1, 1)
var _body_base_position: Vector2 = Vector2.ZERO
var _slash_pivot_base_position: Vector2 = Vector2.ZERO
var _air_jumps_left: int = 0
var _drop_through_timer: float = 0.0
var _facing_direction: Vector2 = Vector2.RIGHT
var _combat_lock_timer: float = 0.0
var _combat_animation_tween: Tween = null
var _combat_move_velocity_x: float = 0.0
var _parry_timer: float = 0.0
var _parry_cooldown_timer: float = 0.0
var _terminal_locked := false
var _sprite: AnimatedSprite2D = null
var _sprites_ready := false
var _visual_lock_timer: float = 0.0
var _current_visual_animation := ""


func _ready() -> void:
	add_to_group("player")
	collision_mask = SOLID_GEOMETRY_LAYER | ONE_WAY_GEOMETRY_LAYER
	floor_snap_length = 16.0
	_spawn_position = global_position
	_body_base_position = body.position
	_slash_pivot_base_position = slash_pivot.position
	current_health = max_health
	_air_jumps_left = max_air_jumps
	_setup_player_sprite()
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	if _terminal_locked:
		velocity = Vector2.ZERO
		apply_floor_snap()
		move_and_slide()
		_update_sprite_direction()
		_play_visual_animation("idle")
		return

	_update_drop_through(delta)
	_update_combat_lock(delta)
	_update_parry(delta)
	_update_visual_lock(delta)

	var direction: float = Input.get_axis("move_left", "move_right")
	if not is_zero_approx(direction):
		_facing_direction = Vector2(signf(direction), 0.0)

	if Input.is_action_just_pressed("move_down") and is_on_floor():
		_begin_drop_through()

	if is_on_floor():
		_air_jumps_left = max_air_jumps
	else:
		velocity.y += gravity * delta

	if _combat_lock_timer <= 0.0:
		velocity.x = direction * move_speed
	else:
		velocity.x = _combat_move_velocity_x

	if is_on_wall_only() and velocity.y > wall_slide_speed:
		velocity.y = wall_slide_speed

	if Input.is_action_just_pressed("jump"):
		if is_on_floor():
			velocity.y = jump_force
			_air_jumps_left = max_air_jumps
		elif is_on_wall_only():
			var wall_normal: Vector2 = get_wall_normal()
			velocity.y = jump_force
			velocity.x = wall_normal.x * wall_jump_push
			_air_jumps_left = max_air_jumps
		elif _air_jumps_left > 0:
			velocity.y = jump_force
			_air_jumps_left -= 1

	if Input.is_action_just_pressed("attack_primary"):
		combat_action_requested.emit(_facing_direction)

	move_and_slide()
	_update_movement_visual(direction)


func apply_damage(amount: int) -> bool:
	if amount > 0:
		GameState.log_event("player_damage_taken", {"amount": amount, "health_before": current_health, "health_after": max(current_health - amount, 0)})
	current_health = max(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	_flash_damage()
	if current_health == 0:
		GameState.log_event("player_died", {"max_health": max_health})
		defeated.emit()
		return true
	return false


func heal(amount: int) -> void:
	if amount <= 0:
		return
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health, max_health)


func restore_full_health() -> void:
	current_health = max_health
	health_changed.emit(current_health, max_health)


func set_spawn_position(spawn_position: Vector2) -> void:
	_spawn_position = spawn_position
	global_position = spawn_position
	velocity = Vector2.ZERO
	_air_jumps_left = max_air_jumps
	_drop_through_timer = 0.0
	collision_mask = SOLID_GEOMETRY_LAYER | ONE_WAY_GEOMETRY_LAYER


func set_camera_limits(left: int, top: int, right: int, bottom: int) -> void:
	camera.limit_left = left
	camera.limit_top = top
	camera.limit_right = right
	camera.limit_bottom = bottom


func respawn() -> void:
	global_position = _spawn_position
	velocity = Vector2.ZERO
	current_health = max_health
	_air_jumps_left = max_air_jumps
	_drop_through_timer = 0.0
	_combat_lock_timer = 0.0
	_combat_move_velocity_x = 0.0
	_parry_timer = 0.0
	_parry_cooldown_timer = 0.0
	collision_mask = SOLID_GEOMETRY_LAYER | ONE_WAY_GEOMETRY_LAYER
	body.color = _base_color
	_reset_attack_visual_state()
	_play_visual_animation("idle")
	health_changed.emit(current_health, max_health)


func perform_combat_motion(step_name: String, facing_direction: Vector2, target_position: Vector2 = Vector2.ZERO) -> void:
	var horizontal_direction: float = facing_direction.x if not is_zero_approx(facing_direction.x) else 1.0
	if not target_position.is_zero_approx():
		var target_offset_x: float = target_position.x - global_position.x
		if not is_zero_approx(target_offset_x):
			horizontal_direction = signf(target_offset_x)
			_facing_direction = Vector2(horizontal_direction, 0.0)
	_play_attack_animation(step_name, horizontal_direction)
	match step_name:
		"ranged_one":
			_combat_move_velocity_x = -horizontal_direction * 180.0
			velocity = Vector2(_combat_move_velocity_x, 0.0)
			_combat_lock_timer = 0.46
		"ranged_two":
			_combat_move_velocity_x = -horizontal_direction * 215.0
			velocity = Vector2(_combat_move_velocity_x, 0.0)
			_combat_lock_timer = 0.5
		"ranged_three":
			_combat_move_velocity_x = -horizontal_direction * 275.0
			velocity = Vector2(_combat_move_velocity_x, 0.0)
			_combat_lock_timer = 0.56
		"melee_one", "melee_two", "melee_three":
			var approach_direction: float = horizontal_direction
			if not target_position.is_zero_approx():
				var target_offset_x: float = target_position.x - global_position.x
				if not is_zero_approx(target_offset_x):
					approach_direction = signf(target_offset_x)
			var approach_speed: float = 192.0
			if not target_position.is_zero_approx():
				approach_speed = clampf(absf(target_position.x - global_position.x) * 1.65, 164.0, 262.0)
			if step_name == "melee_two":
				approach_speed *= 1.02
			elif step_name == "melee_three":
				approach_speed *= 1.1
			_combat_move_velocity_x = approach_direction * approach_speed
			var vertical_velocity: float = 0.0
			if step_name == "melee_one":
				vertical_velocity = jump_force * 0.16
			elif step_name == "melee_two":
				vertical_velocity = jump_force * 0.28
			elif step_name == "melee_three":
				vertical_velocity = jump_force * 0.72
			velocity = Vector2(_combat_move_velocity_x, vertical_velocity)
			_combat_lock_timer = 0.54 if step_name != "melee_three" else 0.72
		_:
			_combat_move_velocity_x = 0.0
			velocity = Vector2.ZERO
			_combat_lock_timer = 0.0


func _begin_drop_through() -> void:
	_drop_through_timer = drop_through_duration
	collision_mask = SOLID_GEOMETRY_LAYER
	global_position.y += 6.0
	velocity.y = maxf(velocity.y, 80.0)
	_air_jumps_left = max_air_jumps


func _update_drop_through(delta: float) -> void:
	if _drop_through_timer <= 0.0:
		return
	_drop_through_timer = maxf(_drop_through_timer - delta, 0.0)
	if is_zero_approx(_drop_through_timer):
		collision_mask = SOLID_GEOMETRY_LAYER | ONE_WAY_GEOMETRY_LAYER


func _update_combat_lock(delta: float) -> void:
	if _combat_lock_timer <= 0.0:
		return
	_combat_lock_timer = maxf(_combat_lock_timer - delta, 0.0)
	if is_zero_approx(_combat_lock_timer):
		_combat_move_velocity_x = 0.0


func _update_parry(delta: float) -> void:
	if _parry_timer > 0.0:
		_parry_timer = maxf(_parry_timer - delta, 0.0)
		if is_zero_approx(_parry_timer):
			body.color = _base_color
	if _parry_cooldown_timer > 0.0:
		_parry_cooldown_timer = maxf(_parry_cooldown_timer - delta, 0.0)


func _begin_parry() -> void:
	if _parry_timer > 0.0 or _parry_cooldown_timer > 0.0:
		return
	_parry_timer = parry_window
	_parry_cooldown_timer = parry_cooldown
	_play_temporary_visual_animation("parry_shield", parry_window + 0.08)
	body.color = Color(0.9, 1.0, 0.82, 1.0)
	var tween := create_tween()
	tween.tween_property(body, "scale", Vector2(1.08, 0.92), 0.08)
	tween.tween_property(body, "scale", Vector2.ONE, 0.12)


func request_parry() -> void:
	GameState.log_event("parry_requested", {"parry_window": parry_window, "cooldown": parry_cooldown})
	_begin_parry()


func set_terminal_locked(locked: bool) -> void:
	_terminal_locked = locked
	if not locked:
		return
	if _combat_animation_tween != null and _combat_animation_tween.is_running():
		_combat_animation_tween.kill()
	velocity = Vector2.ZERO
	_combat_move_velocity_x = 0.0
	_combat_lock_timer = 0.0
	_parry_timer = 0.0
	body.color = _base_color
	_reset_attack_visual_state()
	_play_visual_animation("idle")


func is_parry_active() -> bool:
	return _parry_timer > 0.0


func try_parry(attack_direction: Vector2, source_enemy: EnemyEncounter = null) -> bool:
	if source_enemy != null and is_instance_valid(source_enemy) and not source_enemy.is_combat_unlocked():
		return false
	if not is_parry_active():
		GameState.log_event("parry_failed", {"reason": "not_active", "source": "enemy" if source_enemy != null else "boss_or_unknown"})
		return false
	_parry_timer = 0.0
	GameState.log_event("parry_succeeded", {"source": "enemy" if source_enemy != null else "boss_or_unknown"})
	body.color = Color(0.74, 1.0, 0.84, 1.0)
	var horizontal_direction: float = _facing_direction.x if not is_zero_approx(_facing_direction.x) else 1.0
	if not attack_direction.is_zero_approx():
		horizontal_direction = -signf(attack_direction.x) if not is_zero_approx(attack_direction.x) else horizontal_direction
	velocity = Vector2(horizontal_direction * 120.0, jump_force * 0.18)
	_play_parry_success_animation(horizontal_direction)
	return true


func try_reflect_projectile(projectile: EnemyProjectile) -> bool:
	if projectile == null or not is_instance_valid(projectile):
		return false
	var can_reflect := false
	if projectile.source_enemy != null and is_instance_valid(projectile.source_enemy):
		can_reflect = projectile.source_enemy.is_combat_unlocked()
	elif projectile.source_boss != null and is_instance_valid(projectile.source_boss):
		can_reflect = projectile.source_boss.is_active()
	if not can_reflect:
		return false
	if not is_parry_active():
		GameState.log_event("parry_failed", {"reason": "projectile_not_active"})
		return false
	var projectile_direction: Vector2 = projectile.direction
	var horizontal_direction: float = _facing_direction.x if not is_zero_approx(_facing_direction.x) else 1.0
	if not projectile_direction.is_zero_approx():
		horizontal_direction = -signf(projectile_direction.x) if not is_zero_approx(projectile_direction.x) else horizontal_direction
	if not projectile.reflect_to_source():
		return false
	_parry_timer = 0.0
	GameState.log_event("projectile_reflected", {"damage": projectile.damage})
	body.color = Color(0.74, 1.0, 0.84, 1.0)
	velocity = Vector2(horizontal_direction * 90.0, jump_force * 0.1)
	_play_projectile_parry_animation(horizontal_direction)
	return true


func _setup_player_sprite() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "PlayerSprite"
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.z_index = 1
	add_child(_sprite)
	move_child(_sprite, 1)

	var frames := _build_player_sprite_frames()
	if frames == null:
		body.visible = true
		_sprite.queue_free()
		_sprite = null
		_sprites_ready = false
		return

	_sprite.sprite_frames = frames
	_sprite.position = _sprite_position_for_collision()
	_sprites_ready = true
	body.visible = false
	_play_visual_animation("idle")


func _build_player_sprite_frames() -> SpriteFrames:
	var source_dir := _find_player_sprite_dir()
	if source_dir.is_empty():
		return null

	var frames := SpriteFrames.new()
	if frames.has_animation("default"):
		frames.remove_animation("default")

	var loaded_animation_count := 0
	for animation_name in PLAYER_SPRITE_ANIMATIONS.keys():
		var animation_info: Dictionary = PLAYER_SPRITE_ANIMATIONS[animation_name]
		var frame_files := _find_animation_frame_files(source_dir, String(animation_info.get("prefix", "")))
		if frame_files.is_empty():
			continue

		frames.add_animation(animation_name)
		frames.set_animation_speed(animation_name, float(animation_info.get("fps", 8.0)))
		frames.set_animation_loop(animation_name, bool(animation_info.get("loop", false)))
		for file_name in frame_files:
			var texture := _load_normalized_player_texture("%s/%s" % [source_dir, file_name], animation_info)
			if texture != null:
				frames.add_frame(animation_name, texture)

		if frames.get_frame_count(animation_name) > 0:
			loaded_animation_count += 1
		else:
			frames.remove_animation(animation_name)

	return frames if loaded_animation_count > 0 else null


func _find_player_sprite_dir() -> String:
	for directory_path in PLAYER_SPRITE_DIRS:
		var dir := DirAccess.open(directory_path)
		if dir == null:
			continue
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while not file_name.is_empty():
			if not dir.current_is_dir() and _is_player_sprite_resource_file(file_name):
				dir.list_dir_end()
				return directory_path
			file_name = dir.get_next()
		dir.list_dir_end()
	return ""


func _find_animation_frame_files(directory_path: String, prefix: String) -> Array[String]:
	var result: Array[String] = []
	var seen: Dictionary = {}
	var dir := DirAccess.open(directory_path)
	if dir == null:
		return result

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		if not dir.current_is_dir() and _is_animation_frame(file_name, prefix):
			var resource_name := _resource_file_name(file_name)
			if not seen.has(resource_name):
				seen[resource_name] = true
				result.append(resource_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(_sort_frame_files)
	return result


func _is_animation_frame(file_name: String, prefix: String) -> bool:
	var lower_name := _resource_file_name(file_name).to_lower()
	var lower_prefix := prefix.to_lower()
	if not lower_name.ends_with(".png"):
		return false
	var base_name := lower_name.get_basename()
	return base_name == lower_prefix or base_name.begins_with(lower_prefix + "_")


func _is_player_sprite_resource_file(file_name: String) -> bool:
	var lower_name := file_name.to_lower()
	return lower_name.ends_with(".png") or lower_name.ends_with(".png.import")


func _resource_file_name(file_name: String) -> String:
	return file_name.trim_suffix(".import")


func _sort_frame_files(a: String, b: String) -> bool:
	var animation_a := _frame_group_name(a)
	var animation_b := _frame_group_name(b)
	if animation_a == animation_b:
		var frame_a := _extract_frame_number(a)
		var frame_b := _extract_frame_number(b)
		if frame_a == frame_b:
			return a < b
		return frame_a < frame_b
	return animation_a < animation_b


func _frame_group_name(file_name: String) -> String:
	var base_name := file_name.get_basename()
	var end_index := base_name.length() - 1
	while end_index >= 0 and base_name.substr(end_index, 1).is_valid_int():
		end_index -= 1
	if end_index >= 0 and base_name.substr(end_index, 1) == "_":
		end_index -= 1
	return base_name.substr(0, end_index + 1)


func _extract_frame_number(file_name: String) -> int:
	var base_name := file_name.get_basename()
	var digits := ""
	for index in range(base_name.length() - 1, -1, -1):
		var character := base_name.substr(index, 1)
		if character.is_valid_int():
			digits = character + digits
		elif not digits.is_empty():
			break
	return int(digits) if not digits.is_empty() else 0


func _load_normalized_player_texture(path: String, animation_info: Dictionary) -> Texture2D:
	var source_texture := ResourceLoader.load(path) as Texture2D
	if source_texture == null:
		return null
	var source_image := source_texture.get_image()
	if source_image == null:
		return source_texture
	if source_image.get_format() != Image.FORMAT_RGBA8:
		source_image.convert(Image.FORMAT_RGBA8)

	var used_rect: Rect2i = source_image.get_used_rect()
	if used_rect.size.x <= 0 or used_rect.size.y <= 0:
		return null

	var cropped_image: Image = source_image.get_region(used_rect)
	var target_height: int = int(animation_info.get("target_height", PLAYER_SPRITE_TARGET_HEIGHT))
	var max_width: int = int(animation_info.get("max_width", PLAYER_SPRITE_MAX_WIDTH))
	var foot_margin: int = int(animation_info.get("foot_margin", PLAYER_SPRITE_FOOT_MARGIN))
	var scale_factor: float = float(target_height) / float(cropped_image.get_height())
	var scaled_width: int = maxi(1, int(round(cropped_image.get_width() * scale_factor)))
	var scaled_height: int = target_height
	if scaled_width > max_width:
		scale_factor = float(max_width) / float(cropped_image.get_width())
		scaled_width = max_width
		scaled_height = maxi(1, int(round(cropped_image.get_height() * scale_factor)))
	cropped_image.resize(scaled_width, scaled_height, Image.INTERPOLATE_NEAREST)

	var output_image: Image = Image.create_empty(PLAYER_SPRITE_CANVAS_SIZE.x, PLAYER_SPRITE_CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	output_image.fill(Color(0, 0, 0, 0))
	var paste_position := Vector2i(
		int(round((PLAYER_SPRITE_CANVAS_SIZE.x - scaled_width) * 0.5)),
		PLAYER_SPRITE_CANVAS_SIZE.y - foot_margin - scaled_height
	)
	output_image.blit_rect(cropped_image, Rect2i(Vector2i.ZERO, Vector2i(scaled_width, scaled_height)), paste_position)
	return ImageTexture.create_from_image(output_image)


func _sprite_position_for_collision() -> Vector2:
	var collision_shape: Shape2D = $CollisionShape2D.shape
	var collision_half_height := 24.0
	if collision_shape is RectangleShape2D:
		collision_half_height = (collision_shape as RectangleShape2D).size.y * 0.5
	return Vector2(0.0, collision_half_height - (PLAYER_SPRITE_CANVAS_SIZE.y * 0.5 - PLAYER_SPRITE_FOOT_MARGIN))


func _update_visual_lock(delta: float) -> void:
	if _visual_lock_timer <= 0.0:
		return
	_visual_lock_timer = maxf(_visual_lock_timer - delta, 0.0)


func _update_sprite_direction() -> void:
	if not _sprites_ready or _sprite == null:
		return
	if not is_zero_approx(_facing_direction.x):
		_sprite.flip_h = _facing_direction.x < 0.0


func _update_movement_visual(direction: float) -> void:
	if not _sprites_ready:
		return
	_update_sprite_direction()
	if _visual_lock_timer > 0.0:
		return
	if current_health <= 0:
		_play_visual_animation("death")
	elif not is_on_floor() and is_on_wall_only() and velocity.y >= 0.0:
		_update_wall_slide_visual_direction()
		if not _play_visual_animation("wall_slide"):
			_play_visual_animation("fall")
	elif not is_on_floor():
		_play_visual_animation("jump" if velocity.y < 0.0 else "fall")
	elif absf(direction) > 0.05:
		_play_visual_animation("run")
	else:
		_play_visual_animation("idle")


func _update_wall_slide_visual_direction() -> void:
	var wall_normal := get_wall_normal()
	if not is_zero_approx(wall_normal.x):
		_facing_direction = Vector2(signf(wall_normal.x), 0.0)
	_update_sprite_direction()


func _play_temporary_visual_animation(animation_name: String, duration: float) -> void:
	if _play_visual_animation(animation_name):
		_visual_lock_timer = maxf(_visual_lock_timer, duration)


func _play_visual_animation(animation_name: String) -> bool:
	if not _sprites_ready or _sprite == null or _sprite.sprite_frames == null:
		return false
	if not _sprite.sprite_frames.has_animation(animation_name):
		return false
	if _current_visual_animation == animation_name and _sprite.is_playing():
		return true
	_current_visual_animation = animation_name
	_sprite.play(animation_name)
	return true


func _combat_visual_animation_for_step(step_name: String) -> String:
	return String(PLAYER_COMBAT_ANIMATION_ALIASES.get(step_name, "melee_combo_01"))


func _visual_duration_for_combat_step(step_name: String) -> float:
	match step_name:
		"ranged_one":
			return 0.46
		"ranged_two":
			return 0.5
		"ranged_three":
			return 0.56
		"melee_three":
			return 0.72
		"melee_one", "melee_two":
			return 0.54
		_:
			return 0.36


func _flash_damage() -> void:
	if current_health <= 0:
		_play_temporary_visual_animation("death", 1.2)
	else:
		_play_temporary_visual_animation("hurt", 0.28)
	body.color = Color(1, 0.45, 0.45, 1)
	var tween := create_tween()
	tween.tween_property(body, "color", _base_color, 0.25)


func _play_attack_animation(step_name: String, horizontal_direction: float) -> void:
	if _combat_animation_tween != null and _combat_animation_tween.is_running():
		_combat_animation_tween.kill()
	_reset_attack_visual_state()
	_play_temporary_visual_animation(_combat_visual_animation_for_step(step_name), _visual_duration_for_combat_step(step_name))
	if _sprites_ready:
		return
	slash_visual.visible = true
	slash_pivot.scale.x = horizontal_direction
	match step_name:
		"ranged_one":
			_play_ranged_shot_animation(horizontal_direction, 0)
		"ranged_two":
			_play_ranged_shot_animation(horizontal_direction, 1)
		"ranged_three":
			_play_ranged_shot_animation(horizontal_direction, 2)
		"melee_two":
			_play_melee_combo_animation(horizontal_direction, 1)
		"melee_three":
			_play_melee_combo_animation(horizontal_direction, 2)
		_:
			_play_melee_combo_animation(horizontal_direction, 0)


func _play_melee_combo_animation(horizontal_direction: float, combo_index: int) -> void:
	var slash_color: Color = Color(1.0, 0.93, 0.76, 0.96)
	var start_rotation: float = -1.1 * horizontal_direction
	var end_rotation: float = 0.72 * horizontal_direction
	var windup_position := Vector2(6.0 * horizontal_direction, -8.0)
	var finish_position := Vector2(16.0 * horizontal_direction, -6.0)
	var finish_body_position := Vector2(10.0 * horizontal_direction, 0.0)
	if combo_index == 1:
		slash_color = Color(1.0, 0.82, 0.68, 0.98)
		start_rotation = -0.25 * horizontal_direction
		end_rotation = 1.12 * horizontal_direction
		windup_position = Vector2(4.0 * horizontal_direction, -4.0)
		finish_position = Vector2(18.0 * horizontal_direction, -12.0)
		finish_body_position = Vector2(14.0 * horizontal_direction, 0.0)
	elif combo_index == 2:
		slash_color = Color(1.0, 0.95, 0.7, 1.0)
		start_rotation = -1.35 * horizontal_direction
		end_rotation = 0.88 * horizontal_direction
		windup_position = Vector2(8.0 * horizontal_direction, -18.0)
		finish_position = Vector2(24.0 * horizontal_direction, -28.0)
		finish_body_position = Vector2(18.0 * horizontal_direction, -24.0)
	slash_pivot.position = windup_position
	slash_pivot.rotation = start_rotation
	_combat_animation_tween = create_tween()
	_combat_animation_tween.tween_property(body, "position", Vector2(-4.0 * horizontal_direction, -2.0), 0.11)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2(0.96, 1.04), 0.11)
	_combat_animation_tween.parallel().tween_property(body, "rotation", -0.08 * horizontal_direction, 0.11)
	_combat_animation_tween.parallel().tween_property(slash_visual, "self_modulate", slash_color, 0.07)
	_combat_animation_tween.parallel().tween_property(slash_visual, "scale", Vector2(1.05, 1.0), 0.11)
	_combat_animation_tween.tween_property(body, "position", finish_body_position, 0.22)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2(1.12, 0.9), 0.22)
	_combat_animation_tween.parallel().tween_property(body, "rotation", 0.16 * horizontal_direction, 0.22)
	_combat_animation_tween.parallel().tween_property(slash_pivot, "position", finish_position, 0.22)
	_combat_animation_tween.parallel().tween_property(slash_pivot, "rotation", end_rotation, 0.22)
	_combat_animation_tween.parallel().tween_property(slash_visual, "scale", Vector2(1.34, 1.16), 0.22)
	_combat_animation_tween.tween_property(body, "position", Vector2.ZERO, 0.22)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2.ONE, 0.22)
	_combat_animation_tween.parallel().tween_property(body, "rotation", 0.0, 0.22)
	_combat_animation_tween.parallel().tween_property(slash_visual, "self_modulate", Color(1, 1, 1, 0), 0.2)
	_combat_animation_tween.finished.connect(_hide_slash_after_animation, CONNECT_ONE_SHOT)


func _play_ranged_shot_animation(horizontal_direction: float, combo_index: int) -> void:
	var slash_color: Color = Color(0.66, 0.87, 1.0, 0.9)
	var step_offset: float = 0.0
	if combo_index == 1:
		step_offset = 6.0
		slash_color = Color(0.56, 0.82, 1.0, 0.94)
	elif combo_index == 2:
		step_offset = 12.0
		slash_color = Color(0.84, 0.96, 1.0, 0.98)
	slash_pivot.position = Vector2(16.0 * horizontal_direction, -10.0)
	slash_pivot.rotation = 0.02 * horizontal_direction
	_combat_animation_tween = create_tween()
	_combat_animation_tween.tween_property(body, "position", Vector2(8.0 * horizontal_direction, 0.0), 0.08)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2(1.02, 0.98), 0.08)
	_combat_animation_tween.parallel().tween_property(body, "rotation", 0.04 * horizontal_direction, 0.08)
	_combat_animation_tween.tween_property(body, "position", Vector2(-(12.0 + step_offset) * horizontal_direction, 0.0), 0.12)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2(0.9, 1.04), 0.12)
	_combat_animation_tween.parallel().tween_property(body, "rotation", -0.08 * horizontal_direction, 0.12)
	_combat_animation_tween.parallel().tween_property(slash_visual, "self_modulate", slash_color, 0.05)
	_combat_animation_tween.parallel().tween_property(slash_visual, "scale", Vector2(1.4 + combo_index * 0.14, 0.62), 0.12)
	_combat_animation_tween.parallel().tween_property(slash_pivot, "position", Vector2((50.0 + step_offset) * horizontal_direction, -12.0), 0.14)
	_combat_animation_tween.parallel().tween_property(slash_pivot, "rotation", 0.0, 0.14)
	_combat_animation_tween.tween_property(body, "position", Vector2.ZERO, 0.2)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2.ONE, 0.2)
	_combat_animation_tween.parallel().tween_property(body, "rotation", 0.0, 0.2)
	_combat_animation_tween.parallel().tween_property(slash_visual, "self_modulate", Color(1, 1, 1, 0), 0.18)
	_combat_animation_tween.finished.connect(_hide_slash_after_animation, CONNECT_ONE_SHOT)


func _play_parry_success_animation(horizontal_direction: float) -> void:
	if _combat_animation_tween != null and _combat_animation_tween.is_running():
		_combat_animation_tween.kill()
	_reset_attack_visual_state()
	if _sprites_ready:
		_play_temporary_visual_animation("parry_shield", 0.34)
		return
	slash_visual.visible = true
	slash_pivot.scale.x = horizontal_direction
	slash_pivot.position = Vector2(8.0 * horizontal_direction, -6.0)
	slash_pivot.rotation = -0.8 * horizontal_direction
	slash_visual.self_modulate = Color(0.72, 1.0, 0.88, 0.95)
	_combat_animation_tween = create_tween()
	_combat_animation_tween.tween_property(body, "position", Vector2(-6.0 * horizontal_direction, -4.0), 0.07)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2(0.92, 1.06), 0.07)
	_combat_animation_tween.parallel().tween_property(body, "rotation", -0.1 * horizontal_direction, 0.07)
	_combat_animation_tween.parallel().tween_property(slash_visual, "scale", Vector2(1.18, 0.86), 0.07)
	_combat_animation_tween.tween_property(body, "position", Vector2(10.0 * horizontal_direction, -2.0), 0.09)
	_combat_animation_tween.parallel().tween_property(body, "rotation", 0.12 * horizontal_direction, 0.09)
	_combat_animation_tween.parallel().tween_property(slash_pivot, "rotation", 0.72 * horizontal_direction, 0.09)
	_combat_animation_tween.parallel().tween_property(slash_pivot, "position", Vector2(22.0 * horizontal_direction, -12.0), 0.09)
	_combat_animation_tween.parallel().tween_property(slash_visual, "scale", Vector2(1.46, 1.04), 0.09)
	_combat_animation_tween.tween_property(body, "position", Vector2.ZERO, 0.16)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2.ONE, 0.16)
	_combat_animation_tween.parallel().tween_property(body, "rotation", 0.0, 0.16)
	_combat_animation_tween.parallel().tween_property(slash_visual, "self_modulate", Color(1, 1, 1, 0), 0.14)
	_combat_animation_tween.finished.connect(_hide_slash_after_animation, CONNECT_ONE_SHOT)


func _play_projectile_parry_animation(horizontal_direction: float) -> void:
	if _combat_animation_tween != null and _combat_animation_tween.is_running():
		_combat_animation_tween.kill()
	_reset_attack_visual_state()
	if _sprites_ready:
		_play_temporary_visual_animation("parry_shield", 0.34)
		return
	slash_visual.visible = true
	slash_pivot.scale.x = horizontal_direction
	slash_pivot.position = Vector2(12.0 * horizontal_direction, -4.0)
	slash_pivot.rotation = 0.0
	slash_visual.self_modulate = Color(0.72, 1.0, 0.92, 0.98)
	_combat_animation_tween = create_tween()
	_combat_animation_tween.tween_property(body, "position", Vector2(-6.0 * horizontal_direction, -2.0), 0.06)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2(0.9, 1.08), 0.06)
	_combat_animation_tween.parallel().tween_property(slash_visual, "scale", Vector2(0.92, 1.42), 0.06)
	_combat_animation_tween.parallel().tween_property(slash_pivot, "rotation", 0.22 * horizontal_direction, 0.06)
	_combat_animation_tween.tween_property(body, "position", Vector2(8.0 * horizontal_direction, -1.0), 0.08)
	_combat_animation_tween.parallel().tween_property(body, "rotation", 0.08 * horizontal_direction, 0.08)
	_combat_animation_tween.parallel().tween_property(slash_pivot, "position", Vector2(24.0 * horizontal_direction, -6.0), 0.08)
	_combat_animation_tween.parallel().tween_property(slash_visual, "scale", Vector2(1.18, 1.8), 0.08)
	_combat_animation_tween.tween_property(body, "position", Vector2.ZERO, 0.16)
	_combat_animation_tween.parallel().tween_property(body, "scale", Vector2.ONE, 0.16)
	_combat_animation_tween.parallel().tween_property(body, "rotation", 0.0, 0.16)
	_combat_animation_tween.parallel().tween_property(slash_visual, "self_modulate", Color(1, 1, 1, 0), 0.14)
	_combat_animation_tween.finished.connect(_hide_slash_after_animation, CONNECT_ONE_SHOT)


func _hide_slash_after_animation() -> void:
	_reset_attack_visual_state()


func _reset_attack_visual_state() -> void:
	slash_visual.visible = false
	slash_visual.self_modulate = Color(1, 1, 1, 0)
	slash_visual.scale = Vector2(0.2, 0.2)
	body.position = _body_base_position
	body.scale = Vector2.ONE
	body.rotation = 0.0
	slash_pivot.position = _slash_pivot_base_position
	slash_pivot.rotation = 0.0
