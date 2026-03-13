extends CharacterBody2D

class_name PlayerController

signal health_changed(current_health: int, max_health: int)
signal defeated

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

@onready var body: ColorRect = $Body
@onready var camera: Camera2D = $Camera2D

var current_health: int = 0
var _spawn_position: Vector2
var _base_color := Color(0.74, 0.82, 1, 1)
var _air_jumps_left: int = 0
var _drop_through_timer: float = 0.0


func _ready() -> void:
	add_to_group("player")
	collision_mask = SOLID_GEOMETRY_LAYER | ONE_WAY_GEOMETRY_LAYER
	_spawn_position = global_position
	current_health = max_health
	_air_jumps_left = max_air_jumps
	health_changed.emit(current_health, max_health)


func _physics_process(delta: float) -> void:
	_update_drop_through(delta)

	var direction: float = Input.get_axis("move_left", "move_right")

	if Input.is_action_just_pressed("move_down") and is_on_floor():
		_begin_drop_through()

	if is_on_floor():
		_air_jumps_left = max_air_jumps
	else:
		velocity.y += gravity * delta

	velocity.x = direction * move_speed

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

	move_and_slide()


func apply_damage(amount: int) -> bool:
	current_health = max(current_health - amount, 0)
	health_changed.emit(current_health, max_health)
	_flash_damage()
	if current_health == 0:
		defeated.emit()
		return true
	return false


func set_spawn_position(position: Vector2) -> void:
	_spawn_position = position
	global_position = position
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
	collision_mask = SOLID_GEOMETRY_LAYER | ONE_WAY_GEOMETRY_LAYER
	body.color = _base_color
	health_changed.emit(current_health, max_health)


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


func _flash_damage() -> void:
	body.color = Color(1, 0.45, 0.45, 1)
	var tween := create_tween()
	tween.tween_property(body, "color", _base_color, 0.25)
