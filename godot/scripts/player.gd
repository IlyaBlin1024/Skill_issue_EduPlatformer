extends CharacterBody2D

class_name PlayerController

signal health_changed(current_health: int, max_health: int)
signal defeated
signal combat_action_requested(facing_direction: Vector2)

const SOLID_GEOMETRY_LAYER := 1
const ONE_WAY_GEOMETRY_LAYER := 2

@export var move_speed: float = 260.0
@export var jump_force: float = -380.0
@export var gravity: float = 1000.0
@export var wall_slide_speed: float = 120.0
@export var wall_jump_push: float = 220.0
@export var max_health: int = 100
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


func _ready() -> void:
	add_to_group("player")
	collision_mask = SOLID_GEOMETRY_LAYER | ONE_WAY_GEOMETRY_LAYER
	_spawn_position = global_position
	_body_base_position = body.position
	_slash_pivot_base_position = slash_pivot.position
	current_health = max_health
	_air_jumps_left = max_air_jumps
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	_update_drop_through(delta)
	_update_combat_lock(delta)
	_update_parry(delta)

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

	if Input.is_action_just_pressed("interact") and _combat_lock_timer <= 0.0:
		_begin_parry()

	if Input.is_action_just_pressed("attack_primary") and _combat_lock_timer <= 0.0:
		combat_action_requested.emit(_facing_direction)

	move_and_slide()


func apply_damage(amount: int) -> bool:
	current_health = max(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	_flash_damage()
	if current_health == 0:
		defeated.emit()
		return true
	return false


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
	body.color = Color(0.9, 1.0, 0.82, 1.0)
	var tween := create_tween()
	tween.tween_property(body, "scale", Vector2(1.08, 0.92), 0.08)
	tween.tween_property(body, "scale", Vector2.ONE, 0.12)


func is_parry_active() -> bool:
	return _parry_timer > 0.0


func try_parry(attack_direction: Vector2, source_enemy: EnemyEncounter = null) -> bool:
	if source_enemy != null and is_instance_valid(source_enemy) and not source_enemy.is_combat_unlocked():
		return false
	if not is_parry_active():
		return false
	_parry_timer = 0.0
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
	if projectile.source_enemy == null or not is_instance_valid(projectile.source_enemy):
		return false
	if not projectile.source_enemy.is_combat_unlocked():
		return false
	if not is_parry_active():
		return false
	var projectile_direction: Vector2 = projectile.direction
	var horizontal_direction: float = _facing_direction.x if not is_zero_approx(_facing_direction.x) else 1.0
	if not projectile_direction.is_zero_approx():
		horizontal_direction = -signf(projectile_direction.x) if not is_zero_approx(projectile_direction.x) else horizontal_direction
	if not projectile.reflect_to_source():
		return false
	_parry_timer = 0.0
	body.color = Color(0.74, 1.0, 0.84, 1.0)
	velocity = Vector2(horizontal_direction * 90.0, jump_force * 0.1)
	_play_projectile_parry_animation(horizontal_direction)
	return true


func _flash_damage() -> void:
	body.color = Color(1, 0.45, 0.45, 1)
	var tween := create_tween()
	tween.tween_property(body, "color", _base_color, 0.25)


func _play_attack_animation(step_name: String, horizontal_direction: float) -> void:
	if _combat_animation_tween != null and _combat_animation_tween.is_running():
		_combat_animation_tween.kill()
	_reset_attack_visual_state()
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
