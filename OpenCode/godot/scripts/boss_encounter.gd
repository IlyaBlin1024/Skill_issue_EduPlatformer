extends CharacterBody2D
class_name BossEncounter

const PROJECTILE_SCRIPT := preload("res://scripts/enemy_projectile.gd")
const PRODUCTION_ANIMATION_LOADER := preload("res://scripts/production_animation_loader.gd")
const SOLID_GEOMETRY_LAYER := 1
const ONE_WAY_GEOMETRY_LAYER := 2
const BOSS_SPRITE_CANVAS_SIZE := Vector2i(256, 256)
const BOSS_SPRITE_TARGET_HEIGHT := 154
const BOSS_SPRITE_MAX_WIDTH := 220
const BOSS_SPRITE_FOOT_MARGIN := 6
const BOSS_SPRITE_FOLDERS := {
	"threshold_warden": "01_threshold_warden",
	"logic_spider": "02_logic_spider",
	"assembly_golem": "03_assembly_golem",
	"archivist": "04_archivist",
	"system_admin": "05_system_admin",
}
const BOSS_SPRITE_ANIMATIONS := {
	"threshold_warden": {
		"idle": {"prefix": "idle", "fps": 6.0, "loop": true},
		"move": {"prefix": "move", "fps": 10.0, "loop": true},
		"telegraph": {"prefix": "telegraph", "fps": 10.0, "loop": false},
		"attack": {"prefix": "attack_threshold", "fps": 12.0, "loop": false},
		"hurt": {"prefix": "hurt", "fps": 10.0, "loop": false},
		"death": {"prefix": "death", "fps": 8.0, "loop": false},
	},
	"logic_spider": {
		"idle": {"prefix": "idle", "fps": 6.0, "loop": true},
		"move": {"prefix": "crawl", "fps": 10.0, "loop": true},
		"telegraph": {"prefix": "telegraph_branch", "fps": 10.0, "loop": false},
		"attack": {"prefix": "attack_branch", "fps": 12.0, "loop": false},
		"hurt": {"prefix": "hurt", "fps": 10.0, "loop": false},
		"death": {"prefix": "death", "fps": 8.0, "loop": false},
	},
	"assembly_golem": {
		"idle": {"prefix": "idle", "fps": 6.0, "loop": true},
		"move": {"prefix": "walk", "fps": 10.0, "loop": true},
		"telegraph": {"prefix": "telegraph_loop", "fps": 10.0, "loop": false},
		"attack": {"prefix": "attack_loop", "fps": 12.0, "loop": false},
		"hurt": {"prefix": "hurt", "fps": 10.0, "loop": false},
		"death": {"prefix": "death", "fps": 8.0, "loop": false},
	},
	"archivist": {
		"idle": {"prefix": "idle", "fps": 6.0, "loop": true},
		"move": {"prefix": "float", "fps": 8.0, "loop": true},
		"telegraph": {"prefix": "telegraph_function", "fps": 10.0, "loop": false},
		"attack": {"prefix": "attack_function", "fps": 12.0, "loop": false},
		"hurt": {"prefix": "hurt", "fps": 10.0, "loop": false},
		"death": {"prefix": "death", "fps": 8.0, "loop": false},
	},
	"system_admin": {
		"idle": {"prefix": "player_idle", "fps": 6.0, "loop": true},
		"move": {"prefix": "player_run", "fps": 10.0, "loop": true},
		"telegraph": {"prefix": "player_melee_combo_01", "fps": 10.0, "loop": false},
		"attack": {"prefix": "player_ranged_combo_03", "fps": 12.0, "loop": false},
		"teleport_dissolve": {"prefix": "player_death", "fps": 12.0, "loop": false},
		"teleport_materialize": {"prefix": "player_land", "fps": 12.0, "loop": false},
		"hurt": {"prefix": "player_hurt", "fps": 10.0, "loop": false},
		"death": {"prefix": "player_death", "fps": 8.0, "loop": false},
	},
}

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
var _base_move_speed := 220.0
var _base_jump_interval := 1.2
var _base_attack_interval := 0.95
var _base_reposition_interval := 1.1
var _base_melee_damage := 18
var _base_ranged_damage := 12
var _strategy_attack_budget := 6
var _strategy_pressure := 0
var _strategy_refresh_required := false
var _overdrive_level := 0
var _max_overdrive_level := 3
var _overdrive_tick_interval := 3.0
var _overdrive_tick_timer := 0.0
var _overdrive_move_multiplier := 1.14
var _overdrive_damage_multiplier := 1.18
var _overdrive_attack_speed_multiplier := 0.9
var _terminal_paused := false
var _resume_combat_after_pause := false
var _animation_tween: Tween = null
var _visual_base_position := Vector2.ZERO
var _visual_base_scale := Vector2.ONE
var _visual_base_rotation := 0.0
var _boss_brief := ""
var _mechanic_summary := ""
var _mechanic_type := "threshold_warden"
var _terminal_title := "Boss Terminal"
var _terminal_intro_status := "Write a clean tactic before the boss starts circling."
var _terminal_reprogram_status := "Adjust your tactic while the boss shifts the pattern."
var _terminal_success_text := "Tactic deployed."
var _terminal_failure_text := "Boss repelled the pattern."
var _start_feedback := "Threshold Warden starts circling the arena."
var _reposition_feedback := "Threshold Warden vaults to a new lane."
var _melee_feedback := "Threshold Warden crashes into you for %d damage."
var _ranged_feedback := "Threshold Warden fires across the arena."
var _projectile_feedback := "Boss projectile hits for %d damage."
var _dialogue := {
	"intro_boss": "",
	"intro_player": "",
	"rewrite_boss": "",
	"rewrite_player": "",
	"defeat_boss": "",
	"defeat_player": ""
}
var _threshold_health_steps: Array[float] = [0.75, 0.5, 0.25]
var _threshold_phase_index := 0
var _logic_branch_mode := "ranged"
var _logic_branch_interval := 2.6
var _logic_branch_timer := 0.0
var _loop_repeat_count_min := 2
var _loop_repeat_count_max := 3
var _loop_repeat_remaining := 0
var _loop_repeat_cooldown := 0.0
var _loop_repeat_kind := ""
var _routine_cycle_index := 0
var _system_phase_behaviors: Array[String] = ["threshold_warden", "logic_spider", "assembly_golem", "archivist"]
var _system_phase_labels: Array[String] = ["Variables Phase", "If / Else Phase", "Loops Phase", "Functions Phase"]
var _system_phase_index := 0
var _system_phase_interval := 6.0
var _system_phase_timer := 0.0
var _melee_telegraph_duration := 0.2
var _ranged_telegraph_duration := 0.28
var _attack_telegraph_timer := 0.0
var _pending_attack_kind := ""
var _pending_attack_vector := Vector2.ZERO
var _pending_projectile_count := 1
var _pending_spread_step := 0.0
var _pending_feedback_text := ""
var _pending_speed_scale := 1.0
var _pending_projectile_color := Color(0.960784, 0.537255, 0.34902, 1.0)
var _parry_stagger_timer := 0.0
var _parry_stagger_duration := 0.85
var _parry_damage := 26
var _teleport_phase := ""
var _teleport_timer := 0.0
var _teleport_target_x := 0.0
var _teleport_after_attack_kind := ""
var _teleport_after_attack_vector := Vector2.ZERO
var _teleport_indicator_root: Node2D = null
var _teleport_indicator_glow: Polygon2D = null
var _teleport_indicator_core: Polygon2D = null
var _sprite: AnimatedSprite2D = null
var _sprites_ready := false
var _sprite_boss_key := ""
var _sprite_base_position := Vector2.ZERO
var _current_visual_animation := ""


func _ready() -> void:
	floor_snap_length = 20.0
	collision_mask = SOLID_GEOMETRY_LAYER | ONE_WAY_GEOMETRY_LAYER
	_spawn_position = global_position
	_visual_base_position = visual.position
	_visual_base_scale = visual.scale
	_visual_base_rotation = visual.rotation
	_setup_boss_sprite()
	_ensure_teleport_indicator()
	_reset_state()
	_deactivate_visuals()


func _physics_process(delta: float) -> void:
	if not _active or _defeated:
		return

	_resolve_player_reference()

	if not _combat_enabled:
		velocity = Vector2.ZERO
		apply_floor_snap()
		_play_boss_visual("idle")
		move_and_slide()
		return
	if _terminal_paused:
		velocity = Vector2.ZERO
		apply_floor_snap()
		_play_boss_visual("idle")
		move_and_slide()
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
	if _loop_repeat_cooldown > 0.0:
		_loop_repeat_cooldown = maxf(_loop_repeat_cooldown - delta, 0.0)
	if _parry_stagger_timer > 0.0:
		_parry_stagger_timer = maxf(_parry_stagger_timer - delta, 0.0)
	if _strategy_refresh_required and _overdrive_level < _max_overdrive_level:
		_overdrive_tick_timer = maxf(_overdrive_tick_timer - delta, 0.0)
		if is_zero_approx(_overdrive_tick_timer):
			_raise_overdrive()
	_update_mechanic_runtime(delta)
	if _update_teleport_state(delta):
		move_and_slide()
		global_position.x = clampf(global_position.x, _arena_left, _arena_right)
		return
	if _update_attack_telegraph(delta):
		move_and_slide()
		global_position.x = clampf(global_position.x, _arena_left, _arena_right)
		return
	if _parry_stagger_timer > 0.0:
		velocity.x = move_toward(velocity.x, 0.0, _move_speed * delta * 5.0)
		move_and_slide()
		global_position.x = clampf(global_position.x, _arena_left, _arena_right)
		return

	if _has_target():
		if _reposition_timer <= 0.0:
			_choose_next_anchor()
			_reposition_timer = _reposition_interval
			_play_reposition_animation()

		var to_anchor_x: float = _target_anchor_x - global_position.x
		var anchor_direction: float = signf(to_anchor_x)
		if is_zero_approx(anchor_direction):
			velocity.x = move_toward(velocity.x, 0.0, _move_speed * delta * 4.0)
		else:
			velocity.x = anchor_direction * _move_speed
			_play_boss_visual("move")

		if is_on_floor() and _jump_timer <= 0.0 and absf(to_anchor_x) > 18.0:
			velocity.y = _jump_force
			_jump_timer = _jump_interval
			boss_feedback.emit(_reposition_feedback)

		_attempt_pattern_attack()
	else:
		velocity.x = move_toward(velocity.x, 0.0, _move_speed * delta * 2.0)
		_play_boss_visual("idle")

	move_and_slide()
	global_position.x = clampf(global_position.x, _arena_left, _arena_right)


func configure(config: Dictionary) -> void:
	boss_name = String(config.get("boss_name", boss_name))
	level_theme = String(config.get("level_theme", level_theme))
	difficulty = String(config.get("difficulty", difficulty))
	max_health = int(config.get("max_health", max_health))
	_mechanic_type = String(config.get("mechanic_type", _mechanic_type))
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
	_strategy_attack_budget = int(config.get("strategy_attack_budget", _strategy_attack_budget))
	_max_overdrive_level = int(config.get("max_overdrive_level", _max_overdrive_level))
	_overdrive_tick_interval = float(config.get("overdrive_tick_interval", _overdrive_tick_interval))
	_overdrive_move_multiplier = float(config.get("overdrive_move_multiplier", _overdrive_move_multiplier))
	_overdrive_damage_multiplier = float(config.get("overdrive_damage_multiplier", _overdrive_damage_multiplier))
	_overdrive_attack_speed_multiplier = float(config.get("overdrive_attack_speed_multiplier", _overdrive_attack_speed_multiplier))
	_boss_brief = String(config.get("boss_brief", _boss_brief))
	_mechanic_summary = String(config.get("mechanic_summary", _mechanic_summary))
	_logic_branch_interval = float(config.get("logic_branch_interval", _logic_branch_interval))
	_loop_repeat_count_min = int(config.get("loop_repeat_count_min", _loop_repeat_count_min))
	_loop_repeat_count_max = int(config.get("loop_repeat_count_max", _loop_repeat_count_max))
	_system_phase_interval = float(config.get("system_phase_interval", _system_phase_interval))
	var threshold_steps_variant: Variant = config.get("threshold_health_steps", _threshold_health_steps)
	if typeof(threshold_steps_variant) == TYPE_ARRAY:
		var parsed_thresholds: Array[float] = []
		for threshold_value in threshold_steps_variant:
			parsed_thresholds.append(float(threshold_value))
		if not parsed_thresholds.is_empty():
			_threshold_health_steps = parsed_thresholds
	var terminal_config_variant: Variant = config.get("terminal", {})
	if typeof(terminal_config_variant) == TYPE_DICTIONARY:
		var terminal_config: Dictionary = terminal_config_variant
		_terminal_title = String(terminal_config.get("title", _terminal_title))
		_terminal_intro_status = String(terminal_config.get("intro_status_text", _terminal_intro_status))
		_terminal_reprogram_status = String(terminal_config.get("reprogram_status_text", _terminal_reprogram_status))
		_terminal_success_text = String(terminal_config.get("success_text", _terminal_success_text))
		_terminal_failure_text = String(terminal_config.get("failure_text", _terminal_failure_text))
	var feedback_config_variant: Variant = config.get("feedback", {})
	if typeof(feedback_config_variant) == TYPE_DICTIONARY:
		var feedback_config: Dictionary = feedback_config_variant
		_start_feedback = String(feedback_config.get("start_battle", _start_feedback))
		_reposition_feedback = String(feedback_config.get("reposition", _reposition_feedback))
		_melee_feedback = String(feedback_config.get("melee_attack", _melee_feedback))
		_ranged_feedback = String(feedback_config.get("ranged_attack", _ranged_feedback))
		_projectile_feedback = String(feedback_config.get("projectile_hit", _projectile_feedback))
	var dialogue_config_variant: Variant = config.get("dialogue", {})
	if typeof(dialogue_config_variant) == TYPE_DICTIONARY:
		var dialogue_config: Dictionary = dialogue_config_variant
		for key in _dialogue.keys():
			_dialogue[key] = String(dialogue_config.get(key, _dialogue[key]))
	var color_variant: Variant = config.get("color", [])
	if typeof(color_variant) == TYPE_ARRAY:
		var color_array: Array = color_variant
		if color_array.size() >= 4:
			_base_color = Color(float(color_array[0]), float(color_array[1]), float(color_array[2]), float(color_array[3]))
	var anchor_points_variant = config.get("anchor_points", [])
	if typeof(anchor_points_variant) == TYPE_ARRAY:
		var parsed_anchors: Array[float] = []
		for value in anchor_points_variant:
			parsed_anchors.append(float(value))
		if parsed_anchors.size() >= 2:
			_anchor_points = parsed_anchors
	_capture_base_stats()
	_setup_boss_sprite()
	_reset_state()
	_deactivate_visuals()


func activate_boss() -> void:
	if _defeated:
		return
	_active = true
	_combat_enabled = false
	_terminal_paused = false
	_resume_combat_after_pause = false
	visible = true
	global_position = _spawn_position
	velocity = Vector2.ZERO
	_target_anchor_x = global_position.x
	name_label.text = boss_name
	visual.color = _base_color
	collision_shape.disabled = false
	_hide_teleport_indicator()
	_update_hp_label()
	_play_boss_visual("idle")


func start_battle() -> void:
	if _defeated:
		return
	_terminal_paused = false
	_resume_combat_after_pause = false
	_combat_enabled = true
	_reposition_timer = 0.0
	_pattern_step = 0
	_system_phase_index = 0
	_system_phase_timer = _system_phase_interval
	_logic_branch_timer = _logic_branch_interval
	_play_battle_entry_animation()
	_play_boss_visual("move")
	boss_feedback.emit(_start_feedback)


func pause_for_terminal() -> void:
	if _defeated:
		return
	_resume_combat_after_pause = _combat_enabled
	_terminal_paused = true
	_combat_enabled = false
	velocity = Vector2.ZERO
	_attack_telegraph_timer = 0.0
	_pending_attack_kind = ""
	_teleport_phase = ""
	_teleport_timer = 0.0
	_clear_projectiles()
	_hide_teleport_indicator()
	_reset_visual_pose()
	_play_boss_visual("idle")


func resume_after_terminal(should_resume_combat: bool) -> void:
	if _defeated:
		return
	_terminal_paused = false
	_combat_enabled = should_resume_combat
	_resume_combat_after_pause = false
	velocity = Vector2.ZERO
	_hide_teleport_indicator()
	_reset_visual_pose()
	_play_boss_visual("idle" if not should_resume_combat else "move")


func build_terminal_payload(is_reprogramming: bool) -> Dictionary:
	var status_text := _terminal_intro_status
	if is_reprogramming:
		status_text = _terminal_reprogram_status
	return {
		"interaction_type": "boss",
		"level_theme": level_theme,
		"difficulty": difficulty,
		"title": _terminal_title,
		"status_text": status_text,
		"success_text": _terminal_success_text,
		"failure_text": _terminal_failure_text,
		"time_limit": _time_limit_for_difficulty(difficulty),
		"timer_enabled": true,
		"encounter_name": boss_name,
		"encounter_style": _mechanic_type,
		"gameplay_context": status_text,
		"structure_focus": _structure_focus_for_theme(is_reprogramming),
		"boss_mechanic": _mechanic_summary if not _mechanic_summary.is_empty() else _mechanic_type.replace("_", " "),
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
		_terminal_paused = false
		_attack_telegraph_timer = 0.0
		_pending_attack_kind = ""
		_teleport_phase = ""
		_teleport_timer = 0.0
		_clear_projectiles()
		_hide_teleport_indicator()
		collision_shape.disabled = true
		_reset_visual_pose()
		_play_boss_visual("death")
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


func is_strategy_refresh_required() -> bool:
	return _strategy_refresh_required


func refresh_strategy() -> void:
	_strategy_pressure = 0
	_strategy_refresh_required = false
	_overdrive_level = 0
	_overdrive_tick_timer = _overdrive_tick_interval
	_restore_base_combat_stats()


func apply_terminal_effects(effects: Dictionary) -> void:
	if effects.is_empty():
		return
	if effects.has("health_delta"):
		_current_health = maxi(_current_health + int(effects.get("health_delta", 0)), 1)
	if effects.has("move_speed_scale"):
		_move_speed = maxf(_move_speed * maxf(float(effects.get("move_speed_scale", 1.0)), 0.55), 90.0)
	if effects.has("attack_interval_scale"):
		_attack_interval = clampf(_attack_interval * maxf(float(effects.get("attack_interval_scale", 1.0)), 0.65), 0.35, 3.8)
		_reposition_interval = clampf(_reposition_interval * maxf(float(effects.get("attack_interval_scale", 1.0)), 0.75), 0.4, 4.5)
	if effects.has("damage_scale"):
		var damage_scale: float = maxf(float(effects.get("damage_scale", 1.0)), 0.5)
		_melee_damage = maxi(int(round(float(_melee_damage) * damage_scale)), 1)
		_ranged_damage = maxi(int(round(float(_ranged_damage) * damage_scale)), 1)
	_update_hp_label()


func register_player_attack() -> bool:
	if _defeated or not _combat_enabled:
		return false
	_strategy_pressure += 1
	if _strategy_pressure < _strategy_attack_budget:
		return false
	if not _strategy_refresh_required:
		_strategy_refresh_required = true
		_raise_overdrive()
		boss_feedback.emit("%s adapts. Rewrite your strategy before the arena runs hot." % boss_name)
		return true
	return false


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
	var behavior_key: String = _current_behavior_key()
	if behavior_key == "logic_spider":
		if _logic_branch_mode == "melee":
			var closest_distance := INF
			for anchor in _anchor_points:
				var distance_to_player: float = absf(anchor - player_x)
				if distance_to_player < closest_distance:
					closest_distance = distance_to_player
					chosen_anchor = anchor
		else:
			var farthest_distance := -1.0
			for anchor in _anchor_points:
				var distance_to_player: float = absf(anchor - player_x)
				if distance_to_player > farthest_distance:
					farthest_distance = distance_to_player
					chosen_anchor = anchor
	elif behavior_key == "assembly_golem":
		var loop_index: int = _pattern_step % _anchor_points.size()
		chosen_anchor = _anchor_points[loop_index]
	elif behavior_key == "archivist":
		var routine_anchor_index: int = (_routine_cycle_index * 2) % _anchor_points.size()
		chosen_anchor = _anchor_points[routine_anchor_index]
	else:
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
			var center_index: int = clampi(int(_anchor_points.size() / 2.0), 0, _anchor_points.size() - 1)
			chosen_anchor = _anchor_points[center_index]
	if absf(chosen_anchor - global_position.x) < 24.0 and _anchor_points.size() > 1:
		chosen_anchor = _anchor_points[randi_range(0, _anchor_points.size() - 1)]
	_target_anchor_x = clampf(chosen_anchor, _arena_left, _arena_right)


func _attempt_threshold_attack() -> void:
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


func _attempt_logic_spider_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector2 = _player.global_position - global_position
	var horizontal_distance: float = absf(to_player.x)
	var vertical_distance: float = absf(to_player.y)
	if _logic_branch_mode == "melee":
		if horizontal_distance <= _melee_range + 20.0 and vertical_distance <= _vertical_tolerance:
			if _attempt_melee_attack():
				_pattern_step += 1
	elif horizontal_distance <= _ranged_range and vertical_distance <= _vertical_tolerance + 54.0:
		if _attempt_spread_ranged_attack(to_player, 2, 0.08, "Logic Spider threads two false-logic bolts."):
			_pattern_step += 1


func _attempt_assembly_golem_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var to_player: Vector2 = _player.global_position - global_position
	if _loop_repeat_remaining > 0:
		if _loop_repeat_cooldown <= 0.0:
			_perform_loop_repeat_attack(to_player)
		return
	if _attack_cooldown > 0.0:
		return
	_loop_repeat_kind = "melee" if absf(to_player.x) <= _melee_range + 30.0 else "ranged"
	_loop_repeat_remaining = randi_range(_loop_repeat_count_min, _loop_repeat_count_max)
	boss_feedback.emit("Assembly Golem locks into a repeated %s sequence." % _loop_repeat_kind)
	_perform_loop_repeat_attack(to_player)


func _attempt_archivist_attack() -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if _attack_cooldown > 0.0:
		return
	var to_player: Vector2 = _player.global_position - global_position
	var routine_index: int = _routine_cycle_index % 3
	if routine_index == 0:
		if _attempt_spread_ranged_attack(to_player, 3, 0.1, "Archivist invokes summon_blades()."):
			_routine_cycle_index += 1
	elif routine_index == 1:
		if _attempt_dash_melee_attack(to_player, "Archivist executes seal_floor()."):
			_routine_cycle_index += 1
	else:
		if _attempt_shadow_burst(to_player):
			_routine_cycle_index += 1


func _attempt_system_admin_attack() -> void:
	match _current_behavior_key():
		"logic_spider":
			_attempt_logic_spider_attack()
		"assembly_golem":
			_attempt_assembly_golem_attack()
		"archivist":
			_attempt_archivist_attack()
		_:
			_attempt_threshold_attack()


func _perform_loop_repeat_attack(to_player: Vector2) -> void:
	if _loop_repeat_kind == "melee":
		if _attempt_melee_attack():
			_pattern_step += 1
	else:
		_attempt_spread_ranged_attack(to_player, 3, 0.08, "Assembly Golem repeats a shock-wave loop.")
		_pattern_step += 1
	_loop_repeat_remaining = maxi(_loop_repeat_remaining - 1, 0)
	_loop_repeat_cooldown = _attack_interval * 0.45
	_attack_cooldown = _attack_interval * 0.2


func _attempt_spread_ranged_attack(to_player: Vector2, projectile_count: int, spread_step: float, feedback_text: String) -> bool:
	return _start_attack_telegraph("ranged_spread", to_player, projectile_count, spread_step, feedback_text)


func _attempt_dash_melee_attack(to_player: Vector2, feedback_text: String) -> bool:
	var horizontal_distance: float = absf(to_player.x)
	var vertical_distance: float = absf(to_player.y)
	if horizontal_distance > _melee_range + 56.0 or vertical_distance > _vertical_tolerance + 22.0:
		return false
	return _start_attack_telegraph("dash_melee", to_player, 1, 0.0, feedback_text)


func _attempt_shadow_burst(to_player: Vector2) -> bool:
	if _attack_cooldown > 0.0 or _attack_telegraph_timer > 0.0 or not _teleport_phase.is_empty():
		return false
	_choose_next_anchor()
	_begin_teleport(_target_anchor_x, "shadow_burst", to_player)
	return true


func _spawn_projectile(travel_direction: Vector2, projectile_damage: int, speed_scale: float = 1.0, projectile_color: Color = Color(0.960784, 0.537255, 0.34902, 1.0)) -> void:
	var projectile := PROJECTILE_SCRIPT.new() as EnemyProjectile
	if projectile == null:
		return
	var spawn_direction: Vector2 = travel_direction
	if spawn_direction.is_zero_approx():
		spawn_direction = Vector2.RIGHT
	projectile.configure(global_position + spawn_direction * 26.0, spawn_direction, projectile_damage, _projectile_speed * speed_scale, "player", projectile_color)
	projectile.source_boss = self
	projectile.target_hit.connect(_on_projectile_target_hit)
	projectile.projectile_expired.connect(_on_projectile_expired)
	get_parent().add_child(projectile)
	_active_projectiles.append(projectile)


func can_accept_q_parry() -> bool:
	if _defeated or not _combat_enabled or _terminal_paused:
		return false
	if _attack_telegraph_timer > 0.0 and _can_parry_current_telegraph():
		return true
	if _has_reflectable_projectile_near_player():
		return true
	return false


func _can_parry_current_telegraph() -> bool:
	if _pending_attack_kind == "melee" or _pending_attack_kind == "dash_melee":
		return true
	if _pending_attack_kind.begins_with("ranged") or _pending_attack_kind == "shadow_burst":
		return _can_contact_parry_ranged_attack()
	return false


func _can_contact_parry_ranged_attack() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var offset_to_player: Vector2 = _player.global_position - global_position
	return absf(offset_to_player.x) <= _melee_range * 1.4 and absf(offset_to_player.y) <= _vertical_tolerance * 0.75


func _has_reflectable_projectile_near_player() -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	for projectile in _active_projectiles:
		if not is_instance_valid(projectile):
			continue
		if projectile.target_kind != "player":
			continue
		if projectile.global_position.distance_to(_player.global_position) <= 126.0:
			return true
	return false


func _start_attack_telegraph(kind: String, to_player: Vector2, projectile_count: int = 1, spread_step: float = 0.0, feedback_text: String = "", speed_scale: float = 1.0, projectile_color: Color = Color(0.960784, 0.537255, 0.34902, 1.0)) -> bool:
	if _attack_cooldown > 0.0 or _attack_telegraph_timer > 0.0 or not _teleport_phase.is_empty() or _parry_stagger_timer > 0.0:
		return false
	_pending_attack_kind = kind
	_pending_attack_vector = to_player
	_pending_projectile_count = maxi(projectile_count, 1)
	_pending_spread_step = spread_step
	_pending_feedback_text = feedback_text
	_pending_speed_scale = speed_scale
	_pending_projectile_color = projectile_color
	_attack_telegraph_timer = _melee_telegraph_duration if kind == "melee" or kind == "dash_melee" else _ranged_telegraph_duration
	velocity.x = 0.0
	_play_attack_telegraph_animation(kind, to_player)
	return true


func _update_attack_telegraph(delta: float) -> bool:
	if _attack_telegraph_timer <= 0.0:
		return false
	_attack_telegraph_timer = maxf(_attack_telegraph_timer - delta, 0.0)
	velocity.x = move_toward(velocity.x, 0.0, _move_speed * delta * 8.0)
	if _attack_telegraph_timer > 0.0:
		return true
	_execute_pending_attack()
	return true


func _execute_pending_attack() -> void:
	if _pending_attack_kind.is_empty():
		return
	var kind := _pending_attack_kind
	var to_player := _pending_attack_vector
	var projectile_count := _pending_projectile_count
	var spread_step := _pending_spread_step
	var feedback_text := _pending_feedback_text
	var speed_scale := _pending_speed_scale
	var projectile_color := _pending_projectile_color
	_pending_attack_kind = ""
	_pending_attack_vector = Vector2.ZERO
	_pending_projectile_count = 1
	_pending_spread_step = 0.0
	_pending_feedback_text = ""
	_pending_speed_scale = 1.0
	_pending_projectile_color = Color(0.960784, 0.537255, 0.34902, 1.0)
	match kind:
		"melee":
			_execute_melee_strike(_melee_damage, feedback_text)
		"dash_melee":
			_execute_dash_melee_strike(to_player, feedback_text)
		"ranged_single":
			_execute_ranged_burst(to_player, 1, 0.0, feedback_text, speed_scale, projectile_color)
		"shadow_burst":
			_execute_ranged_burst(to_player, projectile_count, spread_step, feedback_text, speed_scale, projectile_color)
		_:
			_execute_ranged_burst(to_player, projectile_count, spread_step, feedback_text, speed_scale, projectile_color)


func _execute_melee_strike(damage_value: int, feedback_text: String) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _player.try_parry(_player.global_position - global_position):
		_apply_parry_stagger()
		return true
	_attack_cooldown = _attack_interval
	_play_melee_attack_animation()
	_player.apply_damage(damage_value)
	boss_feedback.emit(feedback_text if not feedback_text.is_empty() else _melee_feedback % damage_value)
	return true


func _execute_dash_melee_strike(to_player: Vector2, feedback_text: String) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	var dash_direction := 1.0
	if not is_zero_approx(to_player.x):
		dash_direction = signf(to_player.x)
	global_position.x = clampf(global_position.x + dash_direction * 52.0, _arena_left, _arena_right)
	apply_floor_snap()
	return _execute_melee_strike(_melee_damage + 2, feedback_text)


func _execute_ranged_burst(to_player: Vector2, projectile_count: int, spread_step: float, feedback_text: String, speed_scale: float, projectile_color: Color) -> bool:
	if _player == null or not is_instance_valid(_player):
		return false
	if _can_contact_parry_ranged_attack() and _player.try_parry(_player.global_position - global_position):
		_apply_parry_stagger()
		return true
	_attack_cooldown = _attack_interval + 0.08
	_play_ranged_attack_animation(to_player)
	var safe_direction: Vector2 = to_player.normalized() if not to_player.is_zero_approx() else Vector2.RIGHT
	var safe_count := maxi(projectile_count, 1)
	var first_offset: float = -float(safe_count - 1) * 0.5 * spread_step
	for projectile_index in range(safe_count):
		var angle_offset: float = first_offset + float(projectile_index) * spread_step
		_spawn_projectile(safe_direction.rotated(angle_offset), _ranged_damage, speed_scale, projectile_color)
	boss_feedback.emit(feedback_text if not feedback_text.is_empty() else _ranged_feedback)
	return true


func _apply_parry_stagger() -> void:
	_parry_stagger_timer = _parry_stagger_duration
	_attack_cooldown = _parry_stagger_duration + 0.32
	velocity = Vector2.ZERO
	apply_combat_result({"damage": _parry_damage})
	GameState.log_event("boss_damage_dealt", {"amount": _parry_damage, "mode": "parry", "boss_name": boss_name})
	_play_parry_stagger_animation()
	boss_feedback.emit("%s is parried and staggered." % boss_name)


func _begin_teleport(target_x: float, followup_attack_kind: String = "", followup_vector: Vector2 = Vector2.ZERO) -> void:
	if _terminal_paused or _defeated:
		return
	_teleport_phase = "dissolve"
	_teleport_timer = 0.16
	_teleport_target_x = clampf(target_x, _arena_left, _arena_right)
	_teleport_after_attack_kind = followup_attack_kind
	_teleport_after_attack_vector = followup_vector
	velocity = Vector2.ZERO
	_show_teleport_indicator(_teleport_target_x)
	_play_boss_visual("teleport_dissolve")


func _update_teleport_state(delta: float) -> bool:
	if _teleport_phase.is_empty():
		return false
	velocity.x = 0.0
	_teleport_timer = maxf(_teleport_timer - delta, 0.0)
	if _teleport_phase == "dissolve":
		var dissolve_ratio := 1.0 - (_teleport_timer / 0.16 if 0.16 > 0.0 else 1.0)
		_apply_teleport_visuals(dissolve_ratio, false)
		if _teleport_timer <= 0.0:
			global_position.x = _teleport_target_x
			apply_floor_snap()
			_teleport_phase = "materialize"
			_teleport_timer = 0.18
			_play_boss_visual("teleport_materialize")
		return true
	var materialize_ratio := 1.0 - (_teleport_timer / 0.18 if 0.18 > 0.0 else 1.0)
	_apply_teleport_visuals(materialize_ratio, true)
	if _teleport_timer <= 0.0:
		_teleport_phase = ""
		_hide_teleport_indicator()
		_reset_visual_pose()
		if _teleport_after_attack_kind == "shadow_burst":
			var followup_vector := _teleport_after_attack_vector
			_teleport_after_attack_kind = ""
			_teleport_after_attack_vector = Vector2.ZERO
			_start_attack_telegraph("shadow_burst", followup_vector, 3, 0.12, "Archivist calls shadow_burst().", 1.04, Color(0.937255, 0.776471, 0.505882, 1.0))
		else:
			_teleport_after_attack_kind = ""
			_teleport_after_attack_vector = Vector2.ZERO
		return false
	return true


func _apply_teleport_visuals(progress: float, materializing: bool) -> void:
	var clamped_progress := clampf(progress, 0.0, 1.0)
	var alpha := clamped_progress if materializing else 1.0 - clamped_progress
	var scale_x := lerpf(1.0, 0.68, 1.0 - alpha)
	var scale_y := lerpf(1.0, 1.2, 1.0 - alpha)
	if _sprites_ready and _sprite != null:
		_sprite.scale = Vector2(scale_x, scale_y)
		_sprite.modulate = Color(1.0, 1.0, 1.0, alpha)
	else:
		visual.scale = Vector2(scale_x, scale_y)
		visual.modulate = Color(1.0, 1.0, 1.0, alpha)


func _ensure_teleport_indicator() -> void:
	if _teleport_indicator_root != null and is_instance_valid(_teleport_indicator_root):
		return
	_teleport_indicator_root = Node2D.new()
	_teleport_indicator_root.name = "TeleportIndicator"
	_teleport_indicator_root.visible = false
	_teleport_indicator_root.z_index = 20
	var glow := Polygon2D.new()
	glow.polygon = PackedVector2Array([Vector2(-42, 0), Vector2(0, -22), Vector2(42, 0), Vector2(0, 22)])
	glow.color = Color(0.996078, 0.858824, 0.478431, 0.16)
	var core := Polygon2D.new()
	core.polygon = PackedVector2Array([Vector2(-24, 0), Vector2(0, -12), Vector2(24, 0), Vector2(0, 12)])
	core.color = Color(1.0, 0.941176, 0.658824, 0.0)
	_teleport_indicator_root.add_child(glow)
	_teleport_indicator_root.add_child(core)
	if get_parent() != null:
		get_parent().call_deferred("add_child", _teleport_indicator_root)
	_teleport_indicator_glow = glow
	_teleport_indicator_core = core


func _show_teleport_indicator(target_x: float) -> void:
	_ensure_teleport_indicator()
	if _teleport_indicator_root == null or not is_instance_valid(_teleport_indicator_root):
		return
	_teleport_indicator_root.global_position = Vector2(target_x, global_position.y + _collision_half_height() - 8.0)
	_teleport_indicator_root.visible = true
	if _teleport_indicator_glow != null:
		_teleport_indicator_glow.color = Color(0.996078, 0.858824, 0.478431, 0.22)
	if _teleport_indicator_core != null:
		_teleport_indicator_core.color = Color(1.0, 0.941176, 0.658824, 0.94)


func _hide_teleport_indicator() -> void:
	if _teleport_indicator_root != null and is_instance_valid(_teleport_indicator_root):
		_teleport_indicator_root.visible = false


func _collision_half_height() -> float:
	if is_instance_valid(collision_shape) and collision_shape.shape is RectangleShape2D:
		return (collision_shape.shape as RectangleShape2D).size.y * 0.5
	return 75.0


func _current_behavior_key() -> String:
	if _mechanic_type == "system_admin" and not _system_phase_behaviors.is_empty():
		return _system_phase_behaviors[_system_phase_index % _system_phase_behaviors.size()]
	return _mechanic_type


func _update_mechanic_runtime(delta: float) -> void:
	if _current_behavior_key() == "threshold_warden":
		_update_threshold_phase()
	if _current_behavior_key() == "logic_spider":
		_logic_branch_timer = maxf(_logic_branch_timer - delta, 0.0)
		if is_zero_approx(_logic_branch_timer):
			_toggle_logic_branch_mode()
	if _mechanic_type == "system_admin":
		_system_phase_timer = maxf(_system_phase_timer - delta, 0.0)
		if is_zero_approx(_system_phase_timer):
			_rotate_system_phase()


func _update_threshold_phase() -> void:
	if _threshold_phase_index >= _threshold_health_steps.size():
		return
	var health_ratio: float = float(_current_health) / float(maxi(max_health, 1))
	var next_threshold: float = _threshold_health_steps[_threshold_phase_index]
	if health_ratio > next_threshold:
		return
	_threshold_phase_index += 1
	_move_speed += 16.0
	_melee_damage += 2
	_ranged_damage += 2
	_attack_interval = maxf(_attack_interval - 0.05, 0.42)
	_trigger_threshold_burst()
	boss_feedback.emit("%s rewrites a new threshold and accelerates." % boss_name)


func _toggle_logic_branch_mode() -> void:
	if not _teleport_phase.is_empty() or _attack_telegraph_timer > 0.0:
		_logic_branch_timer = 0.2
		return
	_logic_branch_mode = "melee" if _logic_branch_mode == "ranged" else "ranged"
	_logic_branch_timer = _logic_branch_interval
	_choose_next_anchor()
	_begin_teleport(_target_anchor_x)
	if _logic_branch_mode == "melee":
		_base_color = Color(0.701961, 0.964706, 0.756863, 1.0)
		visual.color = _base_color
		boss_feedback.emit("Logic Spider commits to the close branch.")
	else:
		_base_color = Color(0.615686, 0.741176, 1.0, 1.0)
		visual.color = _base_color
		boss_feedback.emit("Logic Spider retreats into the far branch.")


func _rotate_system_phase() -> void:
	if _system_phase_behaviors.is_empty():
		return
	_system_phase_index = (_system_phase_index + 1) % _system_phase_behaviors.size()
	_system_phase_timer = _system_phase_interval
	_pattern_step = 0
	_apply_system_phase_visuals()
	var phase_label := _system_phase_labels[_system_phase_index % _system_phase_labels.size()]
	boss_feedback.emit("System Admin rotates to %s." % phase_label)


func _trigger_threshold_burst() -> void:
	_spawn_projectile(Vector2.LEFT, _ranged_damage + 1, 1.05, Color(1.0, 0.803922, 0.501961, 1.0))
	_spawn_projectile(Vector2.RIGHT, _ranged_damage + 1, 1.05, Color(1.0, 0.803922, 0.501961, 1.0))


func _apply_system_phase_visuals() -> void:
	match _current_behavior_key():
		"logic_spider":
			_base_color = Color(0.552941, 0.835294, 0.678431, 1.0)
		"assembly_golem":
			_base_color = Color(0.847059, 0.627451, 0.341176, 1.0)
		"archivist":
			_base_color = Color(0.823529, 0.733333, 0.454902, 1.0)
		_:
			_base_color = Color(0.54902, 0.713725, 0.92549, 1.0)
	visual.color = _base_color


func _attempt_pattern_attack() -> void:
	match _current_behavior_key():
		"logic_spider":
			_attempt_logic_spider_attack()
		"assembly_golem":
			_attempt_assembly_golem_attack()
		"archivist":
			_attempt_archivist_attack()
		"system_admin":
			_attempt_system_admin_attack()
		_:
			_attempt_threshold_attack()


func _attempt_melee_attack() -> bool:
	if _player == null:
		return false
	return _start_attack_telegraph("melee", _player.global_position - global_position)


func _attempt_ranged_attack(to_player: Vector2) -> bool:
	return _start_attack_telegraph("ranged_single", to_player)


func _on_projectile_target_hit(_projectile: EnemyProjectile, target: Node, damage: int) -> void:
	if target is PlayerController:
		(target as PlayerController).apply_damage(damage)
		boss_feedback.emit(_projectile_feedback % damage)
	elif target == self:
		var defeated: bool = apply_combat_result({"damage": damage})
		if not defeated:
			boss_feedback.emit("%s takes %d reflected damage." % [boss_name, damage])


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
	_threshold_phase_index = 0
	_logic_branch_mode = "ranged"
	_logic_branch_timer = _logic_branch_interval
	_loop_repeat_remaining = 0
	_loop_repeat_cooldown = 0.0
	_loop_repeat_kind = ""
	_routine_cycle_index = 0
	_system_phase_index = 0
	_system_phase_timer = _system_phase_interval
	_attack_telegraph_timer = 0.0
	_pending_attack_kind = ""
	_pending_attack_vector = Vector2.ZERO
	_pending_projectile_count = 1
	_pending_spread_step = 0.0
	_pending_feedback_text = ""
	_pending_speed_scale = 1.0
	_pending_projectile_color = Color(0.960784, 0.537255, 0.34902, 1.0)
	_parry_stagger_timer = 0.0
	_teleport_phase = ""
	_teleport_timer = 0.0
	_teleport_target_x = 0.0
	_teleport_after_attack_kind = ""
	_teleport_after_attack_vector = Vector2.ZERO
	_strategy_pressure = 0
	_strategy_refresh_required = false
	_overdrive_level = 0
	_overdrive_tick_timer = _overdrive_tick_interval
	_restore_base_combat_stats()
	velocity = Vector2.ZERO
	_terminal_paused = false
	_resume_combat_after_pause = false
	name_label.text = boss_name
	_hide_teleport_indicator()
	_update_hp_label()


func _deactivate_visuals() -> void:
	visible = false
	velocity = Vector2.ZERO
	_clear_projectiles()
	_hide_teleport_indicator()
	_reset_visual_pose()
	collision_shape.disabled = true


func _clear_projectiles() -> void:
	for projectile in _active_projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_active_projectiles.clear()


func _flash_on_hit() -> void:
	_play_boss_visual("hurt")
	if _animation_tween != null and _animation_tween.is_running():
		_animation_tween.kill()
	visual.color = Color(1, 0.8, 0.45, 1)
	_animation_tween = create_tween()
	_animation_tween.tween_property(visual, "color", _base_color, 0.25)


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


func get_boss_brief() -> String:
	return _boss_brief


func _structure_focus_for_theme(is_reprogramming: bool) -> String:
	var prefix: String = "boss rewrite" if is_reprogramming else "boss opening plan"
	match level_theme:
		"variables":
			return "%s with stat assignments that tune timing, damage, or guard values" % prefix
		"conditions":
			return "%s with one readable branch for close or far responses" % prefix
		"loops":
			return "%s with one controlled repeated pattern" % prefix
		"functions":
			return "%s with one helper routine the player can reason about" % prefix
		_:
			return "%s with a compact mixed tactic that still stays readable" % prefix


func get_mechanic_summary() -> String:
	return _mechanic_summary


func get_dialogue_line(key: String) -> String:
	return String(_dialogue.get(key, ""))


func get_dialogue_texture() -> Texture2D:
	if not _sprites_ready or _sprite == null or _sprite.sprite_frames == null:
		return null
	for animation_name in ["idle", "move", "attack", "hurt"]:
		if _sprite.sprite_frames.has_animation(animation_name) and _sprite.sprite_frames.get_frame_count(animation_name) > 0:
			return _sprite.sprite_frames.get_frame_texture(animation_name, 0)
	return null


func _capture_base_stats() -> void:
	_base_move_speed = _move_speed
	_base_jump_interval = _jump_interval
	_base_attack_interval = _attack_interval
	_base_reposition_interval = _reposition_interval
	_base_melee_damage = _melee_damage
	_base_ranged_damage = _ranged_damage


func _restore_base_combat_stats() -> void:
	_move_speed = _base_move_speed
	_jump_interval = _base_jump_interval
	_attack_interval = _base_attack_interval
	_reposition_interval = _base_reposition_interval
	_melee_damage = _base_melee_damage
	_ranged_damage = _base_ranged_damage


func _raise_overdrive() -> void:
	_overdrive_level = mini(_overdrive_level + 1, _max_overdrive_level)
	_overdrive_tick_timer = _overdrive_tick_interval
	_restore_base_combat_stats()
	var speed_scale := pow(_overdrive_move_multiplier, _overdrive_level)
	var damage_scale := pow(_overdrive_damage_multiplier, _overdrive_level)
	var cadence_scale := pow(_overdrive_attack_speed_multiplier, _overdrive_level)
	_move_speed = _base_move_speed * speed_scale
	_reposition_interval = _base_reposition_interval * cadence_scale
	_jump_interval = _base_jump_interval * cadence_scale
	_attack_interval = _base_attack_interval * cadence_scale
	_melee_damage = maxi(int(round(float(_base_melee_damage) * damage_scale)), _base_melee_damage + _overdrive_level)
	_ranged_damage = maxi(int(round(float(_base_ranged_damage) * damage_scale)), _base_ranged_damage + _overdrive_level)
	if _strategy_refresh_required:
		boss_feedback.emit("%s enters overdrive level %d." % [boss_name, _overdrive_level])


func _play_attack_telegraph_animation(kind: String, to_player: Vector2) -> void:
	if _play_boss_visual("telegraph"):
		return
	if _animation_tween != null and _animation_tween.is_running():
		_animation_tween.kill()
	_reset_visual_pose()
	var attack_direction := 1.0
	if not is_zero_approx(to_player.x):
		attack_direction = signf(to_player.x)
	var telegraph_color := Color(1.0, 0.909804, 0.560784, 1.0)
	if kind == "melee" or kind == "dash_melee":
		telegraph_color = Color(1.0, 0.647059, 0.560784, 1.0)
	_animation_tween = create_tween()
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(-8.0 * attack_direction, -10.0), 0.08)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(0.94, 1.08), 0.08)
	_animation_tween.parallel().tween_property(visual, "rotation", -0.06 * attack_direction, 0.08)
	_animation_tween.parallel().tween_property(visual, "color", telegraph_color, 0.08)


func _play_parry_stagger_animation() -> void:
	if _play_boss_visual("hurt"):
		return
	if _animation_tween != null and _animation_tween.is_running():
		_animation_tween.kill()
	_reset_visual_pose()
	visual.color = Color(0.792157, 1.0, 0.854902, 1.0)
	_animation_tween = create_tween()
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(0.0, -12.0), 0.08)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(1.14, 0.84), 0.08)
	_animation_tween.parallel().tween_property(visual, "rotation", -0.08, 0.08)
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(0.0, 6.0), 0.16)
	_animation_tween.parallel().tween_property(visual, "rotation", 0.06, 0.16)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(0.92, 1.08), 0.16)
	_animation_tween.tween_property(visual, "position", _visual_base_position, 0.18)
	_animation_tween.parallel().tween_property(visual, "rotation", _visual_base_rotation, 0.18)
	_animation_tween.parallel().tween_property(visual, "scale", _visual_base_scale, 0.18)
	_animation_tween.parallel().tween_property(visual, "color", _base_color, 0.18)


func _play_reposition_animation() -> void:
	if _play_boss_visual("move"):
		return
	if _animation_tween != null and _animation_tween.is_running():
		_animation_tween.kill()
	_reset_visual_pose()
	visual.color = Color(0.819608, 0.631373, 0.941176, 1.0)
	_animation_tween = create_tween()
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(0.0, -14.0), 0.08)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(1.05, 0.92), 0.08)
	_animation_tween.tween_property(visual, "position", _visual_base_position, 0.14)
	_animation_tween.parallel().tween_property(visual, "scale", _visual_base_scale, 0.14)
	_animation_tween.parallel().tween_property(visual, "color", _base_color, 0.18)


func _play_melee_attack_animation() -> void:
	if _play_boss_visual("attack"):
		return
	if _animation_tween != null and _animation_tween.is_running():
		_animation_tween.kill()
	_reset_visual_pose()
	var attack_direction := 1.0
	if _player != null and is_instance_valid(_player):
		var offset_x: float = _player.global_position.x - global_position.x
		if not is_zero_approx(offset_x):
			attack_direction = signf(offset_x)
	visual.color = Color(1.0, 0.58, 0.58, 1.0)
	_animation_tween = create_tween()
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(-16.0 * attack_direction, -10.0), 0.08)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(0.88, 1.12), 0.08)
	_animation_tween.parallel().tween_property(visual, "rotation", -0.12 * attack_direction, 0.08)
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(26.0 * attack_direction, 2.0), 0.14)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(1.18, 0.86), 0.14)
	_animation_tween.parallel().tween_property(visual, "rotation", 0.2 * attack_direction, 0.14)
	_animation_tween.tween_property(visual, "position", _visual_base_position, 0.2)
	_animation_tween.parallel().tween_property(visual, "scale", _visual_base_scale, 0.2)
	_animation_tween.parallel().tween_property(visual, "rotation", _visual_base_rotation, 0.2)
	_animation_tween.parallel().tween_property(visual, "color", _base_color, 0.2)


func _play_ranged_attack_animation(to_player: Vector2) -> void:
	if _play_boss_visual("attack"):
		return
	if _animation_tween != null and _animation_tween.is_running():
		_animation_tween.kill()
	_reset_visual_pose()
	var attack_direction := 1.0
	if not is_zero_approx(to_player.x):
		attack_direction = signf(to_player.x)
	visual.color = Color(1.0, 0.72, 0.5, 1.0)
	_animation_tween = create_tween()
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(-18.0 * attack_direction, -14.0), 0.09)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(0.92, 1.08), 0.09)
	_animation_tween.parallel().tween_property(visual, "rotation", -0.1 * attack_direction, 0.09)
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(12.0 * attack_direction, -10.0), 0.14)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(1.14, 0.9), 0.14)
	_animation_tween.parallel().tween_property(visual, "rotation", 0.12 * attack_direction, 0.14)
	_animation_tween.tween_property(visual, "position", _visual_base_position, 0.22)
	_animation_tween.parallel().tween_property(visual, "scale", _visual_base_scale, 0.22)
	_animation_tween.parallel().tween_property(visual, "rotation", _visual_base_rotation, 0.22)
	_animation_tween.parallel().tween_property(visual, "color", _base_color, 0.22)


func _play_battle_entry_animation() -> void:
	if _play_boss_visual("move"):
		return
	if _animation_tween != null and _animation_tween.is_running():
		_animation_tween.kill()
	_reset_visual_pose()
	visual.color = Color(0.862745, 0.690196, 0.968627, 1.0)
	_animation_tween = create_tween()
	_animation_tween.tween_property(visual, "position", _visual_base_position + Vector2(0.0, -18.0), 0.12)
	_animation_tween.parallel().tween_property(visual, "scale", Vector2(1.08, 0.92), 0.12)
	_animation_tween.tween_property(visual, "position", _visual_base_position, 0.16)
	_animation_tween.parallel().tween_property(visual, "scale", _visual_base_scale, 0.16)
	_animation_tween.parallel().tween_property(visual, "color", _base_color, 0.16)


func _reset_visual_pose() -> void:
	visual.position = _visual_base_position
	visual.scale = _visual_base_scale
	visual.rotation = _visual_base_rotation
	visual.modulate = Color(1, 1, 1, 1)
	visual.color = _base_color
	if _sprites_ready and _sprite != null:
		_sprite.position = _sprite_base_position
		_sprite.scale = Vector2.ONE
		_sprite.rotation = 0.0
		_apply_boss_sprite_style()


func _setup_boss_sprite() -> void:
	if visual == null:
		return
	var fallback_visual := visual
	var boss_key := _boss_sprite_key()
	if _sprites_ready and _sprite != null and is_instance_valid(_sprite) and _sprite_boss_key == boss_key:
		_remove_legacy_visual_node(fallback_visual)
		_purge_duplicate_boss_visuals(_sprite)
		_apply_boss_sprite_style()
		_play_boss_visual("idle")
		return
	_current_visual_animation = ""
	var sprite_options := {
		"name": "BossSprite",
		"canvas_size": BOSS_SPRITE_CANVAS_SIZE,
		"target_height": BOSS_SPRITE_TARGET_HEIGHT,
		"max_width": BOSS_SPRITE_MAX_WIDTH,
		"foot_margin": BOSS_SPRITE_FOOT_MARGIN,
		"initial_animation": "idle",
		"hide_fallback_on_missing": true,
	}
	_sprite = PRODUCTION_ANIMATION_LOADER.create_sprite(
		self,
		_sprite,
		fallback_visual,
		_boss_sprite_dirs(boss_key),
		BOSS_SPRITE_ANIMATIONS.get(boss_key, {}),
		sprite_options
	)
	_sprites_ready = _sprite != null
	_sprite_boss_key = boss_key if _sprites_ready else ""
	_remove_legacy_visual_node(fallback_visual)
	_purge_duplicate_boss_visuals(_sprite)
	if _sprites_ready:
		_sprite_base_position = _sprite.position
		_apply_boss_sprite_style()
		_play_boss_visual("idle")


func _boss_sprite_key() -> String:
	if _mechanic_type == "system_admin":
		return "system_admin"
	if BOSS_SPRITE_FOLDERS.has(_mechanic_type):
		return _mechanic_type
	return "threshold_warden"


func _boss_sprite_dirs(boss_key: String) -> Array:
	if boss_key == "system_admin":
		return [
			"res://assets/production_art/models/characters/player",
		]
	var folder := String(BOSS_SPRITE_FOLDERS.get(boss_key, BOSS_SPRITE_FOLDERS["threshold_warden"]))
	return [
		"res://assets/production_art/models/bosses/%s" % folder,
	]


func _apply_boss_sprite_style() -> void:
	if _sprite == null or not is_instance_valid(_sprite):
		return
	if _boss_sprite_key() == "system_admin":
		_sprite.modulate = Color(0.78, 0.48, 1.0, 0.96)
		_sprite.skew = -0.06
	else:
		_sprite.modulate = Color(1, 1, 1, 1)
		_sprite.skew = 0.0


func _play_boss_visual(animation_name: String) -> bool:
	if not _sprites_ready or _sprite == null or _sprite.sprite_frames == null:
		return false
	_update_boss_sprite_direction()
	var resolved_animation := animation_name
	if not _sprite.sprite_frames.has_animation(resolved_animation):
		if resolved_animation.begins_with("teleport_") and _sprite.sprite_frames.has_animation("move"):
			resolved_animation = "move"
		else:
			resolved_animation = "idle"
	if not _sprite.sprite_frames.has_animation(resolved_animation):
		return false
	if _current_visual_animation == resolved_animation and _sprite.is_playing():
		return true
	_current_visual_animation = resolved_animation
	_sprite.play(resolved_animation)
	return true


func _update_boss_sprite_direction() -> void:
	if not _sprites_ready or _sprite == null:
		return
	if absf(velocity.x) > 1.0:
		_sprite.flip_h = velocity.x < 0.0
	elif _player != null and is_instance_valid(_player):
		var offset_x := _player.global_position.x - global_position.x
		if not is_zero_approx(offset_x):
			_sprite.flip_h = offset_x < 0.0


func _remove_legacy_visual_node(fallback_visual: ColorRect) -> void:
	if fallback_visual == null:
		return
	_hide_legacy_canvas_item(fallback_visual)
	if fallback_visual.name == "HiddenLegacyVisual":
		visual = fallback_visual
		if fallback_visual.get_parent() == null:
			add_child(fallback_visual)
		return
	var dummy := get_node_or_null("HiddenLegacyVisual") as ColorRect
	if dummy == null:
		dummy = ColorRect.new()
		dummy.name = "HiddenLegacyVisual"
		add_child(dummy)
	dummy.position = fallback_visual.position
	dummy.size = fallback_visual.size
	dummy.visible = false
	dummy.modulate = Color(1, 1, 1, 0)
	dummy.self_modulate = Color(1, 1, 1, 0)
	dummy.color = Color(0, 0, 0, 0)
	dummy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual = dummy
	if fallback_visual.get_parent() == self and is_instance_valid(fallback_visual):
		remove_child(fallback_visual)
		fallback_visual.free()


func _purge_duplicate_boss_visuals(keep_sprite: AnimatedSprite2D) -> void:
	for child in get_children():
		if child == keep_sprite:
			continue
		if child is AnimatedSprite2D and String(child.name) == "BossSprite":
			remove_child(child)
			child.free()
		elif child is ColorRect and String(child.name) != "HiddenLegacyVisual":
			_hide_legacy_canvas_item(child as CanvasItem)
			remove_child(child)
			child.free()


func _hide_legacy_canvas_item(item: CanvasItem) -> void:
	if item == null:
		return
	item.visible = false
	item.modulate = Color(1, 1, 1, 0)
	item.self_modulate = Color(1, 1, 1, 0)
	if item is ColorRect:
		(item as ColorRect).color = Color(0, 0, 0, 0)
	if item is Control:
		(item as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in item.get_children():
		if child is CanvasItem:
			_hide_legacy_canvas_item(child as CanvasItem)
