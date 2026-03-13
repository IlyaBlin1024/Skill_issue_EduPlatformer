extends CharacterBody2D
class_name BossEncounter

const PROJECTILE_SCRIPT := preload("res://scripts/enemy_projectile.gd")

signal boss_defeated
signal boss_feedback(message: String)

@export var boss_name: String = "Threshold Warden"
@export var level_theme: String = "variables"
@export var difficulty: String = "normal"
@export var max_health: int = 120

@onready var visual: ColorRect = $Visual
@onready var hp_label: Label = $HpLabel
@onready var name_label: Label = $NameLabel
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var _active := false
var _combat_enabled := false
var _defeated := false
var _current_health := 0
var _base_color := Color(0.607843, 0.270588, 0.682353, 1)
var _player: PlayerController = null
var _spawn_position := Vector2.ZERO
var _move_speed := 220.0
var _jump_force := -470.0
var _gravity := 1180.0
var _jump_interval := 1.2
var _jump_timer := 0.0
var _attack_interval := 0.95
var _attack_cooldown := 0.0
var _reposition_interval := 1.1
var _reposition_timer := 0.0
var _melee_range := 78.0
var _ranged_range := 420.0
var _vertical_tolerance := 280.0
var _melee_damage := 18
var _ranged_damage := 12
var _projectile_speed := 410.0
var _arena_left := 96.0
var _arena_right := 1824.0
var _anchor_points: Array[float] = [240.0, 520.0, 860.0, 1200.0, 1540.0, 1760.0]
var _target_anchor_x := 640.0
var _active_projectiles: Array[EnemyProjectile] = []
var _pattern_step: int = 0


func _ready() -> void:
	_spawn_position = global_position
	_reset_state()
	_deactivate_visuals()


func _physics_process(delta: float) -> void:
	if not _active or _defeated:
		return

	_resolve_player_reference()

	if not _combat_enabled:
		velocity = Vector2.ZERO
		return

	if not is_on_floor():
		velocity.y += _gravity * delta
	else:
		velocity.y = maxf(velocity.y, 0.0)

	if _jump_timer > 0.0:
		_jump_timer = maxf(_jump_timer - delta, 0.0)
	if _attack_cooldown > 0.0:
		_attack_cooldown = maxf(_attack_cooldown - delta, 0.0)
	if _reposition_timer > 0.0:
		_reposition_timer = maxf(_reposition_timer - delta, 0.0)

	if _has_target():
		if _reposition_timer <= 0.0:
			_choose_next_anchor()
			_reposition_timer = _reposition_interval

		var to_anchor_x: float = _target_anchor_x - global_position.x
		var anchor_direction: float = signf(to_anchor_x)
		if is_zero_approx(anchor_direction):
			velocity.x = move_toward(velocity.x, 0.0, _move_speed * delta * 4.0)
		else:
			velocity.x = anchor_direction * _move_speed

		if is_on_floor() and _jump_timer <= 0.0 and absf(to_anchor_x) > 18.0:
			velocity.y = _jump_force
			_jump_timer = _jump_interval
			boss_feedback.emit("Threshold Warden vaults to a new lane.")

		_attempt_pattern_attack()
	else:
		velocity.x = move_toward(velocity.x, 0.0, _move_speed * delta * 2.0)

	move_and_slide()
	global_position.x = clampf(global_position.x, _arena_left, _arena_right)


func configure(config: Dictionary) -> void:
	boss_name = String(config.get("boss_name", boss_name))
	level_theme = String(config.get("level_theme", level_theme))
	difficulty = String(config.get("difficulty", difficulty))
	max_health = int(config.get("max_health", max_health))
	var position_data: Array = config.get("position", [])
	if position_data.size() == 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
		_spawn_position = global_position
	_move_speed = float(config.get("move_speed", _move_speed))
	_jump_force = float(config.get("jump_force", _jump_force))
	_gravity = float(config.get("gravity", _gravity))
	_jump_interval = float(config.get("jump_interval", _jump_interval))
	_attack_interval = float(config.get("attack_interval", _attack_interval))
	_reposition_interval = float(config.get("reposition_interval", _reposition_interval))
	_melee_range = float(config.get("melee_range", _melee_range))
	_ranged_range = float(config.get("ranged_range", _ranged_range))
	_vertical_tolerance = float(config.get("vertical_tolerance", _vertical_tolerance))
	_melee_damage = int(config.get("melee_damage", _melee_damage))
	_ranged_damage = int(config.get("ranged_damage", _ranged_damage))
	_projectile_speed = float(config.get("projectile_speed", _projectile_speed))
	_arena_left = float(config.get("arena_left", _arena_left))
	_arena_right = float(config.get("arena_right", _arena_right))
	var anchor_points_variant = config.get("anchor_points", [])
	if typeof(anchor_points_variant) == TYPE_ARRAY:
		var parsed_anchors: Array[float] = []
		for value in anchor_points_variant:
			parsed_anchors.append(float(value))
		if parsed_anchors.size() >= 2:
			_anchor_points = parsed_anchors
	_reset_state()
	_deactivate_visuals()


func activate_boss() -> void:
	if _defeated:
		return
	_active = true
	_combat_enabled = false
	visible = true
	global_position = _spawn_position
	velocity = Vector2.ZERO
	_target_anchor_x = global_position.x
	name_label.text = boss_name
	visual.color = _base_color
	collision_shape.disabled = false
	_update_hp_label()


func start_battle() -> void:
	if _defeated:
		return
	_combat_enabled = true
	_reposition_timer = 0.0
	_pattern_step = 0
	boss_feedback.emit("Threshold Warden starts circling the arena.")


func build_terminal_payload(is_reprogramming: bool) -> Dictionary:
	var status_text := "Write a clean tactic before the Warden starts circling."
	if is_reprogramming:
		status_text = "Adjust your tactic while the Warden shifts lanes."
	return {
		"interaction_type": "boss",
		"level_theme": level_theme,
		"difficulty": difficulty,
		"title": "Boss Terminal",
		"status_text": status_text,
		"success_text": "Tactic deployed.",
		"failure_text": "Boss repelled the pattern.",
		"time_limit": _time_limit_for_difficulty(difficulty),
		"timer_enabled": true,
	}


func apply_combat_result(result: Dictionary) -> bool:
	if _defeated:
		return true
	var damage: int = int(result.get("damage", 0))
	_current_health = max(_current_health - damage, 0)
	_update_hp_label()
	_flash_on_hit()
	if _current_health <= 0:
		_defeated = true
		_active = false
		_combat_enabled = false
		_clear_projectiles()
		collision_shape.disabled = true
		visible = false
		boss_defeated.emit()
		return true
	return false


func reset_boss() -> void:
	_reset_state()
	_deactivate_visuals()


func is_defeated() -> bool:
	return _defeated


func is_active() -> bool:
	return _active and not _defeated


func _has_target() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	return absf(_player.global_position.y - global_position.y) <= _vertical_tolerance + 80.0


func _resolve_player_reference() -> void:
	if _player != null and is_instance_valid(_player):
		return
	var players := get_tree().get_nodes_in_group("player")
	if players.is_empty():
		_player = null
		return
	_player = players[0] as PlayerController


func _choose_next_anchor() -> void:
	if _player == null or _anchor_points.is_empty():
		return
	var player_x: float = _player.global_position.x
	var chosen_anchor: float = _anchor_points[0]
	var mode: int = _pattern_step % 3
	if mode == 0:
		var farthest_distance := -1.0
		for anchor in _anchor_points:
			var distance_to_player: float = absf(anchor - player_x)
			if distance_to_player > farthest_distance:
				farthest_distance = distance_to_player
				chosen_anchor = anchor
	elif mode == 1:
		var closest_distance := INF
		for anchor in _anchor_points:
			var distance_to_player: float = absf(anchor - player_x)
			if distance_to_player < closest_distance:
				closest_distance = distance_to_player
				chosen_anchor = anchor
	else:
		var center_index: int = clampi(_anchor_points.size() / 2, 0, _anchor_points.size() - 1)
		chosen_anchor = _anchor_points[center_index]
	if absf(chosen_anchor - global_position.x) < 24.0 and _anchor_points.size() > 1:
		chosen_anchor = _anchor_points[randi_range(0, _anchor_points.size() - 1)]
	_target_anchor_x = clampf(chosen_anchor, _arena_left, _arena_right)


func _attempt_melee_attack() -> bool:
	if _attack_cooldown > 0.0 or _player == null:
		return false
	_attack_cooldown = _attack_interval
	_player.apply_damage(_melee_damage)
	boss_feedback.emit("Threshold Warden crashes into you for %d damage." % _melee_damage)
	visual.color = Color(1, 0.55, 0.55, 1)
	var tween := create_tween()
	tween.tween_property(visual, "color", _base_color, 0.18)
	return true


func _attempt_ranged_attack(to_player: Vector2) -> bool:
	if _attack_cooldown > 0.0:
		return false
	_attack_cooldown = _attack_interval + 0.15
	var projectile := PROJECTILE_SCRIPT.new() as EnemyProjectile
	if projectile == null:
		return false
	var travel_direction: Vector2 = to_player.normalized()
	projectile.configure(global_position + travel_direction * 26.0, travel_direction, _ranged_damage, _projectile_speed, "player", Color(0.960784, 0.537255, 0.34902, 1))
	projectile.target_hit.connect(_on_projectile_target_hit)
	projectile.projectile_expired.connect(_on_projectile_expired)
	get_parent().add_child(projectile)
	_active_projectiles.append(projectile)
	boss_feedback.emit("Threshold Warden fires across the arena.")
	return true


func _attempt_pattern_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector2 = _player.global_position - global_position
	var horizontal_distance: float = absf(to_player.x)
	var vertical_distance: float = absf(to_player.y)
	var mode: int = _pattern_step % 3
	if mode == 0:
		if horizontal_distance <= _ranged_range and vertical_distance <= _vertical_tolerance + 40.0:
			if _attempt_ranged_attack(to_player):
				_pattern_step += 1
		return
	if mode == 1:
		if horizontal_distance <= _melee_range and vertical_distance <= _vertical_tolerance:
			if _attempt_melee_attack():
				_pattern_step += 1
		elif horizontal_distance <= _ranged_range * 0.7 and vertical_distance <= _vertical_tolerance + 24.0:
			_attempt_ranged_attack(to_player)
		return
	if horizontal_distance <= _ranged_range and vertical_distance <= _vertical_tolerance + 40.0:
		if _attempt_ranged_attack(to_player):
			_pattern_step += 1


func _on_projectile_target_hit(_projectile: EnemyProjectile, target: Node, damage: int) -> void:
	if target is PlayerController:
		(target as PlayerController).apply_damage(damage)
		boss_feedback.emit("Boss projectile hits for %d damage." % damage)


func _on_projectile_expired(projectile: EnemyProjectile) -> void:
	_active_projectiles.erase(projectile)


func _reset_state() -> void:
	_active = false
	_combat_enabled = false
	_defeated = false
	_current_health = max_health
	_jump_timer = 0.0
	_attack_cooldown = 0.0
	_reposition_timer = 0.0
	_target_anchor_x = _spawn_position.x
	_pattern_step = 0
	velocity = Vector2.ZERO
	name_label.text = boss_name
	_update_hp_label()


func _deactivate_visuals() -> void:
	visible = false
	velocity = Vector2.ZERO
	_clear_projectiles()
	collision_shape.disabled = true


func _clear_projectiles() -> void:
	for projectile in _active_projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_active_projectiles.clear()


func _flash_on_hit() -> void:
	visual.color = Color(1, 0.8, 0.45, 1)
	var tween := create_tween()
	tween.tween_property(visual, "color", _base_color, 0.25)


func _update_hp_label() -> void:
	hp_label.text = "Boss HP %d" % _current_health


func _time_limit_for_difficulty(value: String) -> int:
	match value:
		"hard":
			return 75
		"normal":
			return 105
		_:
			return 150
