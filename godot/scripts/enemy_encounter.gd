extends Area2D
class_name EnemyEncounter

const ENEMY_PROJECTILE_SCRIPT := preload("res://scripts/enemy_projectile.gd")

signal encounter_started(encounter: EnemyEncounter, payload: Dictionary)
signal encounter_defeated(encounter: EnemyEncounter)
signal world_attack_feedback(message: String)

@export var level_theme: String = "variables"
@export var difficulty: String = "easy"

@onready var visual: ColorRect = $Visual
@onready var hp_label: Label = $HpLabel

var _triggered := false
var _defeated := false
var _current_health := 0
var _base_color := Color(0.788235, 0.278431, 0.321569, 1)
var _player: PlayerController = null
var _player_nearby := false
var _player_visible := false
var _patrol_center_x := 0.0
var _patrol_distance := 120.0
var _patrol_speed := 72.0
var _chase_speed := 112.0
var _aggro_range := 300.0
var _melee_range := 60.0
var _ranged_range := 180.0
var _vertical_tolerance := 96.0
var _attack_cooldown := 0.0
var _attack_interval := 1.6
var _melee_damage := 10
var _ranged_damage := 8
var _projectile_speed := 310.0
var _move_direction := 1.0
var _active_projectiles: Array[EnemyProjectile] = []
var _attack_style: String = "mixed"


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_patrol_center_x = global_position.x
	_reset_stats()


func _physics_process(delta: float) -> void:
	if _defeated:
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown = max(_attack_cooldown - delta, 0.0)

	_resolve_player_reference()
	_update_visibility_state()

	if _triggered:
		return

	if _player_visible and Input.is_action_just_pressed("interact"):
		_start_code_encounter()
		return

	if not _player_visible:
		_patrol(delta)
		return

	var offset_to_player: Vector2 = _player_offset()
	var planar_distance: float = offset_to_player.length()
	var horizontal_distance: float = absf(offset_to_player.x)
	var vertical_distance: float = absf(offset_to_player.y)
	_face_player()

	if _attack_style != "ranged" and _can_use_melee(planar_distance, horizontal_distance, vertical_distance):
		_attempt_melee_attack()
		return

	if _attack_style != "melee" and _can_use_ranged(planar_distance, vertical_distance):
		_attempt_ranged_attack()
		_move_towards(_player.global_position.x, delta, _patrol_speed)
		return

	if vertical_distance <= _vertical_tolerance * 1.8 or planar_distance <= _aggro_range * 0.7:
		_move_towards(_player.global_position.x, delta, _chase_speed)
		return

	_patrol(delta)


func configure(config: Dictionary) -> void:
	level_theme = String(config.get("level_theme", level_theme))
	difficulty = String(config.get("difficulty", difficulty))
	var position_data: Array = config.get("position", [])
	if position_data.size() == 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
		_patrol_center_x = global_position.x
	var color_data: Array = config.get("color", [])
	if color_data.size() == 4:
		_base_color = Color(float(color_data[0]), float(color_data[1]), float(color_data[2]), float(color_data[3]))
	_patrol_distance = float(config.get("patrol_distance", _patrol_distance))
	_patrol_speed = float(config.get("patrol_speed", _patrol_speed))
	_chase_speed = float(config.get("chase_speed", _chase_speed))
	_aggro_range = float(config.get("aggro_range", _aggro_range))
	_melee_range = float(config.get("melee_range", _melee_range))
	_ranged_range = float(config.get("ranged_range", _ranged_range))
	_vertical_tolerance = float(config.get("vertical_tolerance", _vertical_tolerance))
	_attack_interval = float(config.get("attack_interval", _attack_interval))
	_melee_damage = int(config.get("melee_damage", _melee_damage))
	_ranged_damage = int(config.get("ranged_damage", _ranged_damage))
	_projectile_speed = float(config.get("projectile_speed", _projectile_speed))
	_attack_style = String(config.get("attack_style", _attack_style))
	_reset_stats()


func reset_encounter() -> void:
	if _defeated:
		return
	_triggered = false
	visual.color = _current_idle_color()


func apply_combat_result(result: Dictionary) -> bool:
	if _defeated:
		return true

	var damage: int = int(result.get("damage", 0))
	_current_health = max(_current_health - damage, 0)
	_update_hp_label()
	_flash_on_hit()

	if _current_health <= 0:
		mark_defeated()
		return true

	_triggered = false
	return false


func mark_defeated() -> void:
	if _defeated:
		return
	_defeated = true
	_triggered = true
	monitoring = false
	monitorable = false
	visible = false
	_clear_projectiles()
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		collision.disabled = true
	encounter_defeated.emit(self)


func is_defeated() -> bool:
	return _defeated


func _start_code_encounter() -> void:
	if _player == null:
		return
	var attack_mode: String = _current_attack_mode()
	_triggered = true
	encounter_started.emit(
		self,
		{
			"interaction_type": "combat",
			"title": "Combat Terminal",
			"status_text": _status_text_for_mode(attack_mode),
			"success_text": "Pattern accepted.",
			"failure_text": "Pattern rejected",
			"level_theme": level_theme,
			"difficulty": difficulty,
			"time_limit": _time_limit_for_difficulty(difficulty),
			"enemy_health": _current_health,
			"attack_mode": attack_mode,
		}
	)


func _resolve_player_reference() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_player = null
		return
	_player = players[0] as PlayerController


func _update_visibility_state() -> void:
	var was_visible: bool = _player_visible
	_player_visible = _has_world_target()
	if _player_visible and not was_visible:
		world_attack_feedback.emit("Sentry spots you %s. Press E for %s code." % [_vertical_hint_text(), _current_attack_mode()])
		visual.color = _current_idle_color()
	elif not _player_visible and was_visible:
		visual.color = _current_idle_color()


func _has_world_target() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var offset_to_player: Vector2 = _player_offset()
	var planar_distance: float = offset_to_player.length()
	var vertical_distance: float = absf(offset_to_player.y)
	if planar_distance > _aggro_range:
		return false
	return vertical_distance <= maxf(_vertical_tolerance * 2.0, _aggro_range * 0.7)


func _current_attack_mode() -> String:
	if _attack_style == "melee":
		return "melee"
	if _attack_style == "ranged":
		return "ranged"
	if _player == null or not is_instance_valid(_player):
		return "ranged"
	var offset_to_player: Vector2 = _player_offset()
	var planar_distance: float = offset_to_player.length()
	var horizontal_distance: float = absf(offset_to_player.x)
	var vertical_distance: float = absf(offset_to_player.y)
	if _can_use_melee(planar_distance, horizontal_distance, vertical_distance):
		return "melee"
	return "ranged"


func _status_text_for_mode(attack_mode: String) -> String:
	if attack_mode == "melee":
		return "Target is close. Write a melee strike script."
	return "Target is offset in the room. Write a ranged attack script."


func _player_offset() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.ZERO
	return _player.global_position - global_position


func _can_use_melee(planar_distance: float, horizontal_distance: float, vertical_distance: float) -> bool:
	return planar_distance <= _melee_range and horizontal_distance <= _melee_range and vertical_distance <= _melee_range * 0.75


func _can_use_ranged(planar_distance: float, vertical_distance: float) -> bool:
	return planar_distance <= _ranged_range and vertical_distance <= maxf(_vertical_tolerance, _ranged_range * 0.75)


func _patrol(delta: float) -> void:
	var left_limit: float = _patrol_center_x - _patrol_distance
	var right_limit: float = _patrol_center_x + _patrol_distance
	global_position.x += _move_direction * _patrol_speed * delta
	global_position.x = clampf(global_position.x, left_limit, right_limit)
	if is_equal_approx(global_position.x, left_limit):
		_move_direction = 1.0
	elif is_equal_approx(global_position.x, right_limit):
		_move_direction = -1.0


func _move_towards(target_x: float, delta: float, speed: float) -> void:
	var direction: float = signf(target_x - global_position.x)
	if is_zero_approx(direction):
		return
	_move_direction = direction
	var left_limit: float = _patrol_center_x - _patrol_distance
	var right_limit: float = _patrol_center_x + _patrol_distance
	global_position.x = clampf(global_position.x + direction * speed * delta, left_limit, right_limit)


func _face_player() -> void:
	if _player == null:
		return
	var delta_x: float = _player.global_position.x - global_position.x
	if not is_zero_approx(delta_x):
		_move_direction = signf(delta_x)


func _attempt_melee_attack() -> void:
	if _attack_cooldown > 0.0 or _player == null:
		return
	_attack_cooldown = _attack_interval
	_player.apply_damage(_melee_damage)
	world_attack_feedback.emit("Enemy slash hits for %d damage." % _melee_damage)
	visual.color = Color(1, 0.52, 0.52, 1)
	var tween := create_tween()
	tween.tween_property(visual, "color", _current_idle_color(), 0.2)


func _attempt_ranged_attack() -> void:
	if _attack_cooldown > 0.0 or _player == null:
		return
	_attack_cooldown = _attack_interval + 0.4
	var projectile := ENEMY_PROJECTILE_SCRIPT.new() as EnemyProjectile
	if projectile == null:
		return
	var projectile_direction: Vector2 = _player_offset().normalized()
	projectile.configure(global_position + projectile_direction * 18.0, projectile_direction, _ranged_damage, _projectile_speed, "player")
	projectile.target_hit.connect(_on_projectile_target_hit)
	projectile.projectile_expired.connect(_on_projectile_expired)
	get_parent().add_child(projectile)
	_active_projectiles.append(projectile)
	world_attack_feedback.emit("Enemy sentinel fires a ranged shot.")


func _on_projectile_target_hit(_projectile: EnemyProjectile, target: Node, damage: int) -> void:
	if target is PlayerController:
		(target as PlayerController).apply_damage(damage)
		world_attack_feedback.emit("Projectile hit for %d damage." % damage)


func _on_projectile_expired(projectile: EnemyProjectile) -> void:
	_active_projectiles.erase(projectile)


func _on_body_entered(body: Node) -> void:
	if body is PlayerController:
		_player = body as PlayerController
		_player_nearby = true
		visual.color = _current_idle_color()


func _on_body_exited(body: Node) -> void:
	if body is PlayerController:
		_player_nearby = false
		visual.color = _current_idle_color()


func _current_idle_color() -> Color:
	if _player_visible and not _triggered:
		return _base_color.lightened(0.24)
	if _player_nearby and not _triggered:
		return _base_color.lightened(0.12)
	return _base_color


func _flash_on_hit() -> void:
	visual.color = Color(1, 0.76, 0.45, 1)
	var tween := create_tween()
	tween.tween_property(visual, "color", _current_idle_color(), 0.25)


func _reset_stats() -> void:
	_triggered = false
	_defeated = false
	_player_nearby = false
	_player_visible = false
	_current_health = _health_for_difficulty(difficulty)
	_attack_cooldown = 0.0
	_move_direction = -1.0
	visible = true
	monitoring = true
	monitorable = true
	_clear_projectiles()
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		collision.disabled = false
	visual.color = _base_color
	_update_hp_label()


func _clear_projectiles() -> void:
	for projectile in _active_projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_active_projectiles.clear()


func _update_hp_label() -> void:
	hp_label.text = "HP %d" % _current_health


func _vertical_hint_text() -> String:
	if _player == null or not is_instance_valid(_player):
		return "ahead"
	var delta_y: float = _player.global_position.y - global_position.y
	if delta_y < -28.0:
		return "above"
	if delta_y > 28.0:
		return "below"
	return "ahead"


func _health_for_difficulty(value: String) -> int:
	match value:
		"hard":
			return 200
		"normal":
			return 150
		_:
			return 100


func _time_limit_for_difficulty(value: String) -> int:
	match value:
		"hard":
			return 60
		"normal":
			return 120
		_:
			return 180
