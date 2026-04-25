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
@onready var state_label: Label = $StateLabel

var _triggered := false
var _defeated := false
var _current_health := 0
var _base_color := Color(0.788235, 0.278431, 0.321569, 1)
var _player: PlayerController = null
var _player_nearby := false
var _player_visible := false
var _patrol_center_x := 0.0
var _patrol_distance := 120.0
var _patrol_min_x := -1000000.0
var _patrol_max_x := 1000000.0
var _patrol_speed := 72.0
var _chase_speed := 112.0
var _vision_range := 300.0
var _melee_range := 60.0
var _ranged_attack_range := 260.0
var _vertical_tolerance := 96.0
var _vision_enter_range_multiplier := 1.0
var _vision_exit_range_multiplier := 1.18
var _vision_enter_vertical_multiplier := 1.0
var _vision_exit_vertical_multiplier := 1.28
var _attack_cooldown := 0.0
var _attack_interval := 1.6
var _melee_damage := 10
var _ranged_damage := 8
var _projectile_speed := 310.0
var _move_direction := 1.0
var _active_projectiles: Array[EnemyProjectile] = []
var _attack_style: String = "mixed"
var _ranged_retreat_distance := 92.0
var _ranged_hold_distance := 156.0
var _vision_feedback_style := ""
var _interaction_hint_state := ""
var _terminal_title := ""
var _terminal_status_text := ""
var _terminal_success_text := ""
var _terminal_failure_text := ""
var _terminal_starter_code := ""
var _combat_unlocked := false
var _attack_telegraph_timer := 0.0
var _pending_attack_type := ""
var _stagger_timer := 0.0
var _telegraph_duration := 0.38
var _parry_stagger_duration := 0.85
var _parry_damage := 18
var _base_patrol_speed := 72.0
var _base_chase_speed := 112.0
var _base_attack_interval := 1.6
var _base_projectile_speed := 310.0
var _base_ranged_retreat_distance := 92.0
var _base_ranged_hold_distance := 156.0
var _base_telegraph_duration := 0.38
var _special_move_timer := 0.0
var _special_move_duration := 0.0
var _special_move_from := Vector2.ZERO
var _special_move_to := Vector2.ZERO
var _special_move_height := 0.0
var _parry_terminal_opened := false
var _visual_base_position := Vector2.ZERO
var _attack_animation_tween: Tween = null


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	_patrol_center_x = global_position.x
	_visual_base_position = visual.position
	_reset_stats()


func _physics_process(delta: float) -> void:
	if _defeated:
		return

	if _attack_cooldown > 0.0:
		_attack_cooldown = max(_attack_cooldown - delta, 0.0)
	if _special_move_timer > 0.0:
		_update_special_move(delta)
		return
	if _stagger_timer > 0.0:
		_stagger_timer = max(_stagger_timer - delta, 0.0)
		if is_zero_approx(_stagger_timer):
			visual.color = _current_idle_color()
			_update_state_label()
		return

	_resolve_player_reference()
	_update_visibility_state()

	if _triggered:
		return
	if _attack_telegraph_timer > 0.0:
		_attack_telegraph_timer = max(_attack_telegraph_timer - delta, 0.0)
		if is_zero_approx(_attack_telegraph_timer):
			_release_pending_attack()
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
		_begin_attack_telegraph("melee")
		return

	if _attack_style != "melee" and _can_use_ranged(planar_distance, vertical_distance):
		_begin_attack_telegraph("ranged")
		if _attack_style == "ranged":
			if horizontal_distance < _ranged_retreat_distance:
				if _can_use_hard_ranged_escape() and _try_special_reposition_away_from(_player.global_position.x):
					return
				_move_away_from(_player.global_position.x, delta, _chase_speed)
			elif horizontal_distance > _ranged_hold_distance:
				_move_towards(_player.global_position.x, delta, _patrol_speed)
		else:
			_move_towards(_player.global_position.x, delta, _patrol_speed)
		return

	if _attack_style == "ranged":
		if vertical_distance <= _vertical_tolerance * 1.3 and horizontal_distance < _ranged_retreat_distance:
			if _can_use_hard_ranged_escape() and _try_special_reposition_away_from(_player.global_position.x):
				return
			_move_away_from(_player.global_position.x, delta, _chase_speed)
			return
		if horizontal_distance > _ranged_hold_distance and horizontal_distance <= _ranged_attack_range * 1.15 and vertical_distance <= _vertical_tolerance * 1.6:
			_move_towards(_player.global_position.x, delta, _patrol_speed)
			return
		_patrol(delta)
		return

	if vertical_distance <= _vertical_tolerance * 1.8 or planar_distance <= _vision_range * 0.7:
		if _can_use_hard_melee_leap(horizontal_distance, vertical_distance) and _try_special_reposition_towards(_player.global_position.x):
			return
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
	_patrol_min_x = float(config.get("patrol_min_x", _patrol_center_x - _patrol_distance))
	_patrol_max_x = float(config.get("patrol_max_x", _patrol_center_x + _patrol_distance))
	if _patrol_min_x > _patrol_max_x:
		var swap_bound: float = _patrol_min_x
		_patrol_min_x = _patrol_max_x
		_patrol_max_x = swap_bound
	_patrol_center_x = (_patrol_min_x + _patrol_max_x) * 0.5
	_patrol_distance = maxf((_patrol_max_x - _patrol_min_x) * 0.5, 16.0)
	global_position.x = clampf(global_position.x, _patrol_min_x, _patrol_max_x)
	_patrol_speed = float(config.get("patrol_speed", _patrol_speed))
	_chase_speed = float(config.get("chase_speed", _chase_speed))
	_vision_range = float(config.get("vision_range", config.get("aggro_range", _vision_range)))
	_melee_range = float(config.get("melee_range", _melee_range))
	_ranged_attack_range = float(config.get("ranged_attack_range", config.get("ranged_range", _ranged_attack_range)))
	_vertical_tolerance = float(config.get("vertical_tolerance", _vertical_tolerance))
	_vision_enter_range_multiplier = float(config.get("vision_enter_range_multiplier", _vision_enter_range_multiplier))
	_vision_exit_range_multiplier = float(config.get("vision_exit_range_multiplier", _vision_exit_range_multiplier))
	_vision_enter_vertical_multiplier = float(config.get("vision_enter_vertical_multiplier", _vision_enter_vertical_multiplier))
	_vision_exit_vertical_multiplier = float(config.get("vision_exit_vertical_multiplier", _vision_exit_vertical_multiplier))
	_attack_interval = float(config.get("attack_interval", _attack_interval))
	_telegraph_duration = float(config.get("telegraph_duration", _telegraph_duration))
	_melee_damage = int(config.get("melee_damage", _melee_damage))
	_ranged_damage = int(config.get("ranged_damage", _ranged_damage))
	_projectile_speed = float(config.get("projectile_speed", _projectile_speed))
	_attack_style = String(config.get("attack_style", _attack_style))
	_ranged_retreat_distance = float(config.get("ranged_retreat_distance", _ranged_retreat_distance))
	_ranged_hold_distance = float(config.get("ranged_hold_distance", _ranged_hold_distance))
	_terminal_title = String(config.get("terminal_title", ""))
	_terminal_status_text = String(config.get("terminal_status_text", ""))
	_terminal_success_text = String(config.get("terminal_success_text", ""))
	_terminal_failure_text = String(config.get("terminal_failure_text", ""))
	_terminal_starter_code = String(config.get("terminal_starter_code", ""))
	_base_patrol_speed = _patrol_speed
	_base_chase_speed = _chase_speed
	_base_attack_interval = _attack_interval
	_base_projectile_speed = _projectile_speed
	_base_ranged_retreat_distance = _ranged_retreat_distance
	_base_ranged_hold_distance = _ranged_hold_distance
	_base_telegraph_duration = _telegraph_duration
	_reset_stats()


func reset_encounter() -> void:
	if _defeated:
		return
	_triggered = false
	_attack_telegraph_timer = 0.0
	_pending_attack_type = ""
	_stagger_timer = 0.0
	_interaction_hint_state = ""
	visual.color = _current_idle_color()
	_update_state_label()


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


func set_runtime_difficulty(value: String, preserve_ratio: bool = true) -> void:
	var previous_max_health: int = maxi(_health_for_difficulty(difficulty), 1)
	var new_max_health: int = maxi(_health_for_difficulty(value), 1)
	difficulty = value
	_apply_difficulty_profile()
	if _defeated:
		return
	if preserve_ratio:
		var health_ratio: float = float(_current_health) / float(previous_max_health)
		_current_health = clampi(int(round(new_max_health * health_ratio)), 1, new_max_health)
	else:
		_current_health = new_max_health
	_update_hp_label()


func unlock_combat() -> void:
	if _defeated:
		return
	_combat_unlocked = true
	_parry_terminal_opened = true
	_triggered = false
	visual.color = _current_idle_color()
	_update_state_label()


func is_combat_unlocked() -> bool:
	return _combat_unlocked


func apply_terminal_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	if effects.has("health_delta"):
		_current_health = maxi(_current_health + int(effects.get("health_delta", 0)), 1)
	if effects.has("move_speed_scale"):
		var move_scale: float = maxf(float(effects.get("move_speed_scale", 1.0)), 0.55)
		_patrol_speed = maxf(_patrol_speed * move_scale, 24.0)
		_chase_speed = maxf(_chase_speed * move_scale, 32.0)
	if effects.has("attack_interval_scale"):
		_attack_interval = clampf(_attack_interval * maxf(float(effects.get("attack_interval_scale", 1.0)), 0.6), 0.35, 4.0)
	if effects.has("projectile_speed_scale"):
		_projectile_speed = maxf(_projectile_speed * maxf(float(effects.get("projectile_speed_scale", 1.0)), 0.55), 140.0)
	if effects.has("vision_range_delta"):
		_vision_range = maxf(_vision_range + float(effects.get("vision_range_delta", 0.0)), 120.0)
	_update_hp_label()


func is_player_visible() -> bool:
	return _player_visible


func can_open_code_terminal() -> bool:
	return not _defeated and not _triggered and not _combat_unlocked and _player_visible


func request_code_encounter() -> bool:
	if not can_open_code_terminal():
		if _combat_unlocked:
			_emit_interaction_feedback("Combat unlocked. Press Q near the sentinel to chain attacks.")
		elif _player_visible:
			_emit_interaction_feedback("Stay in view and press Q to unlock combat.")
		return false
	_start_code_encounter()
	return true


func mark_defeated() -> void:
	if _defeated:
		return
	_defeated = true
	_triggered = true
	_clear_projectiles()
	call_deferred("_finalize_defeated_state")
	encounter_defeated.emit(self)


func is_defeated() -> bool:
	return _defeated


func _start_code_encounter() -> void:
	if _player == null:
		return
	var attack_mode: String = _current_attack_mode()
	_triggered = true
	_update_state_label()
	encounter_started.emit(
		self,
		{
			"interaction_type": "combat",
			"title": _terminal_title if not _terminal_title.is_empty() else "%s Terminal" % _style_display_name(),
			"status_text": _terminal_status_text if not _terminal_status_text.is_empty() else _status_text_for_mode(attack_mode),
			"success_text": _terminal_success_text if not _terminal_success_text.is_empty() else "Pattern accepted. Combat unlocked.",
			"failure_text": _terminal_failure_text if not _terminal_failure_text.is_empty() else "Pattern rejected",
			"level_theme": level_theme,
			"difficulty": difficulty,
			"time_limit": _time_limit_for_difficulty(difficulty),
			"enemy_health": _current_health,
			"attack_mode": attack_mode,
			"encounter_name": _style_display_name(),
			"encounter_style": _attack_style,
			"gameplay_context": _status_text_for_mode(attack_mode),
			"structure_focus": _structure_focus_for_theme(attack_mode),
			"boss_mechanic": "",
			"starter_code": _terminal_starter_code
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
		var visibility_signature: String = "%s:%s:%s" % [_style_display_name(), _current_attack_mode(), str(_combat_unlocked)]
		if _vision_feedback_style != visibility_signature:
			if _combat_unlocked:
				world_attack_feedback.emit("%s spots you %s. Combat is unlocked, press Q to attack." % [_style_display_name(), _vertical_hint_text()])
			else:
				world_attack_feedback.emit("%s spots you %s. Press Q to unlock combat." % [_style_display_name(), _vertical_hint_text()])
			_vision_feedback_style = visibility_signature
		visual.color = _current_idle_color()
	elif not _player_visible and was_visible:
		_vision_feedback_style = ""
		visual.color = _current_idle_color()
	_update_state_label()


func _has_world_target() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var offset_to_player: Vector2 = _player_offset()
	var planar_distance: float = offset_to_player.length()
	var horizontal_distance: float = absf(offset_to_player.x)
	var vertical_distance: float = absf(offset_to_player.y)
	var range_multiplier: float = _vision_exit_range_multiplier if _player_visible else _vision_enter_range_multiplier
	var vertical_multiplier: float = _vision_exit_vertical_multiplier if _player_visible else _vision_enter_vertical_multiplier
	var allowed_range: float = _vision_range * range_multiplier
	var allowed_vertical: float = maxf(_vertical_tolerance * vertical_multiplier, allowed_range * 0.55)
	if planar_distance > allowed_range:
		return false
	if vertical_distance > allowed_vertical:
		return false
	# Prevent enemies from acquiring targets through huge floor separation unless horizontally committed.
	if vertical_distance > _vertical_tolerance * 1.35 and horizontal_distance > _melee_range * 1.8:
		return false
	return true


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
		return "%s is in striking range. Write a melee strike script." % _style_display_name()
	return "%s is keeping distance. Write a ranged attack script." % _style_display_name()


func _structure_focus_for_theme(attack_mode: String) -> String:
	match level_theme:
		"variables":
			return "two or three short assignments that tune %s combat values" % attack_mode
		"conditions":
			return "one readable if/else branch for the current %s exchange" % attack_mode
		"loops":
			return "one short repeat pattern for %s pressure" % attack_mode
		"functions":
			return "one small helper function for the current %s action" % attack_mode
		_:
			return "one compact mixed tactic that fits the current %s exchange" % attack_mode


func _player_offset() -> Vector2:
	if _player == null or not is_instance_valid(_player):
		return Vector2.ZERO
	return _player.global_position - global_position


func _can_use_melee(planar_distance: float, horizontal_distance: float, vertical_distance: float) -> bool:
	return planar_distance <= _melee_range and horizontal_distance <= _melee_range and vertical_distance <= _melee_range * 0.75


func _can_use_ranged(planar_distance: float, vertical_distance: float) -> bool:
	return planar_distance <= _ranged_attack_range and vertical_distance <= maxf(_vertical_tolerance, _ranged_attack_range * 0.75)


func _patrol(delta: float) -> void:
	var left_limit: float = _patrol_center_x - _patrol_distance
	var right_limit: float = _patrol_center_x + _patrol_distance
	left_limit = maxf(left_limit, _patrol_min_x)
	right_limit = minf(right_limit, _patrol_max_x)
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
	left_limit = maxf(left_limit, _patrol_min_x)
	right_limit = minf(right_limit, _patrol_max_x)
	global_position.x = clampf(global_position.x + direction * speed * delta, left_limit, right_limit)


func _move_away_from(target_x: float, delta: float, speed: float) -> void:
	var direction: float = signf(global_position.x - target_x)
	if is_zero_approx(direction):
		direction = _move_direction if not is_zero_approx(_move_direction) else 1.0
	_move_direction = direction
	var left_limit: float = maxf(_patrol_center_x - _patrol_distance, _patrol_min_x)
	var right_limit: float = minf(_patrol_center_x + _patrol_distance, _patrol_max_x)
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
	_play_attack_animation("melee")
	var parried: bool = _player.try_parry(_player.global_position - global_position, self)
	if parried:
		_handle_parried()
		return
	_player.apply_damage(_melee_damage)
	world_attack_feedback.emit("%s slash hits for %d damage." % [_style_display_name(), _melee_damage])
	visual.color = Color(1, 0.52, 0.52, 1)
	var tween := create_tween()
	tween.tween_property(visual, "color", _current_idle_color(), 0.2)


func _attempt_ranged_attack() -> void:
	if _attack_cooldown > 0.0 or _player == null:
		return
	_attack_cooldown = _attack_interval + 0.4
	_play_attack_animation("ranged")
	if _can_contact_parry_ranged_attack():
		var parried: bool = _player.try_parry(_player.global_position - global_position, self)
		if parried:
			_handle_parried()
			return
	var projectile := ENEMY_PROJECTILE_SCRIPT.new() as EnemyProjectile
	if projectile == null:
		return
	var projectile_direction: Vector2 = _player_offset().normalized()
	projectile.configure(global_position + projectile_direction * 18.0, projectile_direction, _ranged_damage, _projectile_speed, "player")
	projectile.source_enemy = self
	projectile.target_hit.connect(_on_projectile_target_hit)
	projectile.projectile_expired.connect(_on_projectile_expired)
	get_parent().add_child(projectile)
	_active_projectiles.append(projectile)
	world_attack_feedback.emit("%s fires a ranged shot." % _style_display_name())


func _on_projectile_target_hit(_projectile: EnemyProjectile, target: Node, damage: int) -> void:
	if target is PlayerController:
		(target as PlayerController).apply_damage(damage)
		world_attack_feedback.emit("Projectile hit for %d damage." % damage)
	elif target is EnemyEncounter:
		var target_encounter := target as EnemyEncounter
		var defeated: bool = target_encounter.apply_combat_result({"damage": damage})
		if defeated:
			world_attack_feedback.emit("Reflected shot defeated %s." % target_encounter._style_display_name())
		else:
			world_attack_feedback.emit("Reflected shot hit %s for %d damage." % [target_encounter._style_display_name(), damage])


func _on_projectile_expired(projectile: EnemyProjectile) -> void:
	_active_projectiles.erase(projectile)


func _on_body_entered(body: Node) -> void:
	if body is PlayerController:
		_player = body as PlayerController
		_player_nearby = true
		visual.color = _current_idle_color()
		_update_state_label()


func _on_body_exited(body: Node) -> void:
	if body is PlayerController:
		_player_nearby = false
		_interaction_hint_state = ""
		visual.color = _current_idle_color()
		_update_state_label()


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
	_combat_unlocked = false
	_parry_terminal_opened = false
	_attack_telegraph_timer = 0.0
	_pending_attack_type = ""
	_stagger_timer = 0.0
	_special_move_timer = 0.0
	_special_move_duration = 0.0
	_player_nearby = false
	_player_visible = false
	_current_health = _health_for_difficulty(difficulty)
	_attack_cooldown = 0.0
	_move_direction = -1.0
	_vision_feedback_style = ""
	_interaction_hint_state = ""
	_apply_difficulty_profile()
	visible = true
	monitoring = true
	monitorable = true
	_clear_projectiles()
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		collision.disabled = false
	visual.color = _base_color
	visual.position = _visual_base_position
	visual.scale = Vector2.ONE
	visual.rotation = 0.0
	_update_hp_label()
	_update_state_label()


func _finalize_defeated_state() -> void:
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	set_deferred("visible", false)
	var collision := get_node_or_null("CollisionShape2D") as CollisionShape2D
	if collision:
		collision.set_deferred("disabled", true)


func _clear_projectiles() -> void:
	for projectile in _active_projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_active_projectiles.clear()


func _update_hp_label() -> void:
	hp_label.text = "HP %d" % _current_health


func _update_state_label() -> void:
	if _defeated:
		state_label.visible = false
		return
	var next_state: String = ""
	if _stagger_timer > 0.0:
		next_state = "STAGGERED"
	elif _attack_telegraph_timer > 0.0 and _can_parry_current_telegraph():
		next_state = "PARRY"
	if _player_visible and _combat_unlocked and not _triggered:
		if next_state.is_empty():
			next_state = "COMBAT OPEN"
	elif _player_visible and not _triggered:
		var mode: String = _current_attack_mode()
		if not next_state.is_empty():
			pass
		elif _attack_style == "melee" and mode != "melee":
			next_state = "OUT OF RANGE"
		elif mode == "melee":
			next_state = "MELEE READY"
		else:
			next_state = "RANGED READY"
	elif _player_nearby and not _triggered:
		next_state = "ALERT"
	state_label.text = next_state
	state_label.visible = not next_state.is_empty()


func _emit_interaction_feedback(message: String) -> void:
	if _interaction_hint_state == message:
		return
	_interaction_hint_state = message
	world_attack_feedback.emit(message)


func _begin_attack_telegraph(attack_type: String) -> void:
	if _attack_cooldown > 0.0 or _player == null or _attack_telegraph_timer > 0.0 or _stagger_timer > 0.0:
		return
	_pending_attack_type = attack_type
	_attack_telegraph_timer = _telegraph_duration
	visual.color = Color(1.0, 0.92, 0.5, 1.0)
	_play_telegraph_animation(attack_type)
	_update_state_label()


func _release_pending_attack() -> void:
	var pending_type: String = _pending_attack_type
	_pending_attack_type = ""
	visual.color = _current_idle_color()
	_update_state_label()
	if pending_type == "melee":
		_attempt_melee_attack()
	elif pending_type == "ranged":
		_attempt_ranged_attack()


func _handle_parried() -> void:
	_attack_telegraph_timer = 0.0
	_pending_attack_type = ""
	_stagger_timer = _parry_stagger_duration
	_attack_cooldown = _parry_stagger_duration + 0.4
	apply_combat_result({"damage": _parry_damage})
	visual.color = Color(0.76, 1.0, 0.78, 1.0)
	_play_stagger_animation()
	_update_state_label()


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


func _style_display_name() -> String:
	match _attack_style:
		"melee":
			return "Blade Sentinel"
		"ranged":
			return "Caster Sentinel"
		_:
			return "Code Sentinel"


func can_accept_q_parry() -> bool:
	if _defeated or not _combat_unlocked:
		return false
	if _attack_telegraph_timer > 0.0 and _can_parry_current_telegraph():
		return true
	if _has_reflectable_projectile_near_player():
		return true
	return false


func _can_contact_parry_ranged_attack() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if not _combat_unlocked:
		return false
	var offset_to_player: Vector2 = _player_offset()
	return absf(offset_to_player.x) <= _melee_range * 1.35 and absf(offset_to_player.y) <= _vertical_tolerance * 0.7


func _can_parry_current_telegraph() -> bool:
	if _pending_attack_type == "melee":
		return _combat_unlocked
	if _pending_attack_type == "ranged":
		return _can_contact_parry_ranged_attack()
	return false


func _has_reflectable_projectile_near_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	for projectile in _active_projectiles:
		if not is_instance_valid(projectile):
			continue
		if projectile.target_kind != "player":
			continue
		if projectile.global_position.distance_to(_player.global_position) <= 118.0:
			return true
	return false


func _difficulty_rank() -> int:
	match difficulty:
		"hard":
			return 2
		"normal":
			return 1
		_:
			return 0


func _apply_difficulty_profile() -> void:
	_patrol_speed = _base_patrol_speed
	_chase_speed = _base_chase_speed
	_attack_interval = _base_attack_interval
	_projectile_speed = _base_projectile_speed
	_ranged_retreat_distance = _base_ranged_retreat_distance
	_ranged_hold_distance = _base_ranged_hold_distance
	_telegraph_duration = _base_telegraph_duration
	var rank: int = _difficulty_rank()
	if _attack_style == "ranged":
		if rank >= 1:
			_attack_interval *= 0.76
			_projectile_speed *= 1.08
		if rank >= 2:
			_attack_interval *= 0.88
			_projectile_speed *= 1.08
			_chase_speed *= 1.12
			_ranged_retreat_distance += 28.0
			_ranged_hold_distance += 24.0
			_telegraph_duration *= 0.92
	elif _attack_style == "melee":
		if rank >= 1:
			_attack_interval *= 0.78
			_chase_speed *= 1.08
		if rank >= 2:
			_attack_interval *= 0.9
			_chase_speed *= 1.18
			_telegraph_duration *= 0.9


func _can_use_hard_ranged_escape() -> bool:
	return _attack_style == "ranged" and _difficulty_rank() >= 2 and _special_move_timer <= 0.0 and _attack_cooldown <= _attack_interval * 0.3


func _can_use_hard_melee_leap(horizontal_distance: float, vertical_distance: float) -> bool:
	return _attack_style == "melee" and _difficulty_rank() >= 2 and _special_move_timer <= 0.0 and _attack_cooldown <= _attack_interval * 0.35 and horizontal_distance > _melee_range * 1.1 and horizontal_distance < _melee_range * 3.2 and vertical_distance <= _vertical_tolerance * 1.4


func _try_special_reposition_away_from(target_x: float) -> bool:
	var direction: float = signf(global_position.x - target_x)
	if is_zero_approx(direction):
		direction = -_move_direction if not is_zero_approx(_move_direction) else -1.0
	var distance: float = clampf(_ranged_hold_distance + 42.0, 120.0, 188.0)
	return _start_special_move(direction, distance, 0.34, 18.0)


func _try_special_reposition_towards(target_x: float) -> bool:
	var direction: float = signf(target_x - global_position.x)
	if is_zero_approx(direction):
		return false
	var distance: float = clampf(absf(target_x - global_position.x) * 0.72, 96.0, 176.0)
	return _start_special_move(direction, distance, 0.28, 30.0)


func _start_special_move(direction: float, distance: float, duration: float, height: float) -> bool:
	var left_limit: float = maxf(_patrol_center_x - _patrol_distance, _patrol_min_x)
	var right_limit: float = minf(_patrol_center_x + _patrol_distance, _patrol_max_x)
	var destination_x: float = clampf(global_position.x + direction * distance, left_limit, right_limit)
	if absf(destination_x - global_position.x) < 18.0:
		return false
	_special_move_from = global_position
	_special_move_to = Vector2(destination_x, global_position.y)
	_special_move_duration = duration
	_special_move_timer = duration
	_special_move_height = height
	_move_direction = direction
	_play_mobility_animation(direction)
	return true


func _update_special_move(delta: float) -> void:
	if _special_move_timer <= 0.0 or _special_move_duration <= 0.0:
		return
	_special_move_timer = maxf(_special_move_timer - delta, 0.0)
	var progress: float = 1.0 - (_special_move_timer / _special_move_duration)
	global_position.x = lerpf(_special_move_from.x, _special_move_to.x, progress)
	global_position.y = lerpf(_special_move_from.y, _special_move_to.y, progress) - sin(progress * PI) * _special_move_height
	if is_zero_approx(_special_move_timer):
		global_position = _special_move_to


func _play_telegraph_animation(attack_type: String) -> void:
	_kill_attack_tween()
	visual.position = _visual_base_position
	var telegraph_color: Color = Color(1.0, 0.92, 0.5, 1.0) if attack_type == "melee" else Color(0.98, 0.84, 0.48, 1.0)
	_attack_animation_tween = create_tween()
	_attack_animation_tween.tween_property(visual, "scale", Vector2(1.08, 0.92), _telegraph_duration * 0.4)
	_attack_animation_tween.parallel().tween_property(visual, "color", telegraph_color, _telegraph_duration * 0.4)
	_attack_animation_tween.tween_property(visual, "scale", Vector2.ONE, _telegraph_duration * 0.6)
	_attack_animation_tween.parallel().tween_property(visual, "position", _visual_base_position + Vector2(-10.0 * _move_direction, 0.0), _telegraph_duration * 0.6)


func _play_attack_animation(attack_type: String) -> void:
	_kill_attack_tween()
	visual.position = _visual_base_position
	visual.rotation = 0.0
	_attack_animation_tween = create_tween()
	if attack_type == "melee":
		_attack_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(12.0 * _move_direction, -6.0), 0.08)
		_attack_animation_tween.parallel().tween_property(visual, "rotation", 0.14 * _move_direction, 0.08)
		_attack_animation_tween.parallel().tween_property(visual, "scale", Vector2(1.08, 0.92), 0.08)
		_attack_animation_tween.tween_property(visual, "position", _visual_base_position, 0.12)
	else:
		_attack_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(-14.0 * _move_direction, 0.0), 0.07)
		_attack_animation_tween.parallel().tween_property(visual, "scale", Vector2(0.9, 1.06), 0.07)
		_attack_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(10.0 * _move_direction, -2.0), 0.07)
		_attack_animation_tween.parallel().tween_property(visual, "color", Color(1.0, 0.8, 0.62, 1.0), 0.05)
		_attack_animation_tween.tween_property(visual, "position", _visual_base_position, 0.14)
	_attack_animation_tween.parallel().tween_property(visual, "rotation", 0.0, 0.14)
	_attack_animation_tween.parallel().tween_property(visual, "scale", Vector2.ONE, 0.14)
	_attack_animation_tween.parallel().tween_property(visual, "color", _current_idle_color(), 0.14)


func _play_stagger_animation() -> void:
	_kill_attack_tween()
	visual.position = _visual_base_position
	_attack_animation_tween = create_tween()
	_attack_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(-8.0 * _move_direction, -3.0), 0.08)
	_attack_animation_tween.parallel().tween_property(visual, "rotation", -0.16 * _move_direction, 0.08)
	_attack_animation_tween.parallel().tween_property(visual, "scale", Vector2(1.12, 0.88), 0.08)
	_attack_animation_tween.tween_property(visual, "position", _visual_base_position, 0.18)
	_attack_animation_tween.parallel().tween_property(visual, "rotation", 0.0, 0.18)
	_attack_animation_tween.parallel().tween_property(visual, "scale", Vector2.ONE, 0.18)


func _play_mobility_animation(direction: float) -> void:
	_kill_attack_tween()
	visual.position = _visual_base_position
	_attack_animation_tween = create_tween()
	_attack_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(-8.0 * direction, -4.0), 0.08)
	_attack_animation_tween.parallel().tween_property(visual, "scale", Vector2(0.92, 1.06), 0.08)
	_attack_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(8.0 * direction, -8.0), 0.12)
	_attack_animation_tween.parallel().tween_property(visual, "scale", Vector2(1.04, 0.94), 0.12)
	_attack_animation_tween.tween_property(visual, "position", _visual_base_position, 0.12)
	_attack_animation_tween.parallel().tween_property(visual, "scale", Vector2.ONE, 0.12)


func _kill_attack_tween() -> void:
	if _attack_animation_tween != null and _attack_animation_tween.is_running():
		_attack_animation_tween.kill()
