extends Node2D

const DEFAULT_LEVEL_CONFIG_PATH := "res://data/levels/level_01.json"
const PLAYER_RANGED_PROJECTILE_SPEED := 500.0
const PLAYER_MELEE_RANGE := 210.0
const PLAYER_MELEE_VERTICAL_TOLERANCE := 96.0
const PLAYER_TARGET_ACQUIRE_RANGE := 520.0
const PLAYER_MELEE_COMBO_DAMAGE := [28, 34, 42]
const PLAYER_RANGED_COMBO_DAMAGE := [16, 24, 36]
const PLAYER_MELEE_PREFERRED_RANGE := 110.0
const PLAYER_RANGED_PREFERRED_RANGE := 250.0
const PLAYER_COMBO_FOLLOWUP_DELAY := 0.25
const PLAYER_COMBO_FOLLOWUP_TOLERANCE := 0.25

const COMBAT_PROJECTILE_SCRIPT := preload("res://scripts/enemy_projectile.gd")
const LEVEL_LAYOUT_GENERATOR_SCRIPT := preload("res://scripts/level_layout_generator.gd")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const INVENTORY_MENU_SCENE := preload("res://scenes/ui/inventory_menu.tscn")

@onready var backdrop: ColorRect = $Backdrop
@onready var geometry_root: Node2D = $LevelGeometry
@onready var terminal: CanvasLayer = $CombatTerminal
@onready var player: PlayerController = $Player
@onready var hud: GameHud = $Hud
@onready var level_exit: LevelExit = $LevelExit
@onready var enemy_template_a: EnemyEncounter = $EnemyEncounterA
@onready var enemy_template_b: EnemyEncounter = $EnemyEncounterB
@onready var fade_rect: ColorRect = $FadeLayer/FadeRect

@export_file("*.json") var level_config_path: String = DEFAULT_LEVEL_CONFIG_PATH

var _enemy_templates: Array[EnemyEncounter] = []
var _encounters: Array[EnemyEncounter] = []
var _chests: Array[ChestEncounter] = []
var _altars: Array[AltarEncounter] = []
var _runtime_encounter_configs: Array = []
var _active_encounter: EnemyEncounter = null
var _active_chest: ChestEncounter = null
var _active_altar: AltarEncounter = null
var _player_projectiles: Array[EnemyProjectile] = []
var _player_damage_on_failure: int = 20
var _level_config: Dictionary = {}
var _generated_layout: Dictionary = {}
var _layout_generator: LevelLayoutGenerator = LEVEL_LAYOUT_GENERATOR_SCRIPT.new()
var _level_completed := false
var _player_combo_in_progress := false
var _player_combo_step: int = 0
var _player_combo_target: EnemyEncounter = null
var _player_combo_mode: String = ""
var _player_combo_window_open: float = 0.0
var _player_combo_window_close: float = 0.0
var _active_unlock_group: Array[EnemyEncounter] = []
var _room_descriptors: Array = []
var _current_room_key: String = ""
var _adaptive_difficulty_state: Dictionary = {}
var _respawn_in_progress := false
var _player_melee_damage_bonus := 0
var _player_ranged_damage_bonus := 0
var _player_failure_damage_reduction := 0
var _base_player_parry_window := 0.22
var _base_player_move_speed := 260.0
var _fade_tween: Tween = null
var _completion_fade_started := false
var _pause_menu: CanvasLayer = null
var _inventory_menu: CanvasLayer = null
var _messages := {
	"intro": "Level 1: clear the generated archive and reach the exit chamber.",
	"remaining": "Sentries remain in the archive.",
	"exit_unlocked": "Exit opened. Reach the marked chamber.",
	"level_complete": "Level 1 clear. Variables secured.",
	"encounter_cancelled": "Encounter cancelled.",
	"respawn": "Respawn complete.",
	"defeat": "Knight integrity lost. Respawning..."
}


func _ready() -> void:
	randomize()
	if not GameState.pending_level_path.is_empty():
		level_config_path = GameState.pending_level_path
	_enemy_templates = [enemy_template_a, enemy_template_b]
	_chests = [$ChestA, $ChestB]
	_altars = [$AltarA]
	_base_player_parry_window = player.parry_window
	_base_player_move_speed = player.move_speed
	_level_config = _load_level_config()
	_initialize_adaptive_difficulty()
	_prepare_runtime_level_state()
	hud.update_health(player.current_health, player.max_health)
	hud.set_boss_status("")
	level_exit.set_unlocked(false)
	_configure_fade_layer()
	_ensure_overlay_menus()
	call_deferred("_run_level_intro_fade")


func _process(_delta: float) -> void:
	_update_room_context()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return
		if key_event.keycode == KEY_ESCAPE:
			_toggle_pause_menu()
			get_viewport().set_input_as_handled()
		elif key_event.keycode == KEY_I:
			_toggle_inventory_menu()
			get_viewport().set_input_as_handled()


func _ensure_overlay_menus() -> void:
	if _pause_menu == null:
		_pause_menu = PAUSE_MENU_SCENE.instantiate() as CanvasLayer
		add_child(_pause_menu)
	if _inventory_menu == null:
		_inventory_menu = INVENTORY_MENU_SCENE.instantiate() as CanvasLayer
		add_child(_inventory_menu)


func _toggle_pause_menu() -> void:
	if get_tree().paused and (_pause_menu == null or not _pause_menu.visible):
		return
	if _pause_menu != null and _pause_menu.has_method("toggle_pause"):
		_pause_menu.call("toggle_pause")


func _toggle_inventory_menu() -> void:
	if get_tree().paused and (_inventory_menu == null or not _inventory_menu.visible):
		return
	if _inventory_menu != null and _inventory_menu.has_method("toggle_inventory"):
		_inventory_menu.call("toggle_inventory")


func _configure_fade_layer() -> void:
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 1)


func _run_level_intro_fade() -> void:
	await _fade_from_black(0.8)
	hud.show_message(_messages["intro"], 1.8)


func _fade_from_black(duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 1)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", 0.0, duration)
	await _fade_tween.finished
	fade_rect.visible = false


func _play_level_outro_fade() -> void:
	if _completion_fade_started:
		return
	_completion_fade_started = true
	await get_tree().create_timer(0.25).timeout
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 0)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", 1.0, 0.95)
	await _fade_tween.finished
	GameState.go_to_main_menu()


func _prepare_runtime_level_state() -> void:
	_reset_level_runtime_bonuses()
	_runtime_encounter_configs = _build_runtime_enemy_configs(_level_config)
	_ensure_enemy_pool(_runtime_encounter_configs.size())
	_level_config["encounters"] = _runtime_encounter_configs
	_generated_layout = _layout_generator.generate(geometry_root, backdrop, _level_config)
	_apply_level_config(_level_config)
	_apply_generated_layout(_generated_layout)
	_connect_static_nodes()
	_refresh_enemy_counter()


func _connect_static_nodes() -> void:
	for encounter in _encounters:
		if not encounter.encounter_started.is_connected(_on_encounter_started):
			encounter.encounter_started.connect(_on_encounter_started)
		if not encounter.encounter_defeated.is_connected(_on_encounter_defeated):
			encounter.encounter_defeated.connect(_on_encounter_defeated)
		if not encounter.world_attack_feedback.is_connected(_on_enemy_world_attack_feedback):
			encounter.world_attack_feedback.connect(_on_enemy_world_attack_feedback)
	for chest in _chests:
		if not chest.chest_started.is_connected(_on_chest_started):
			chest.chest_started.connect(_on_chest_started)
		if not chest.chest_opened.is_connected(_on_chest_opened):
			chest.chest_opened.connect(_on_chest_opened)
	for altar in _altars:
		if not altar.altar_started.is_connected(_on_altar_started):
			altar.altar_started.connect(_on_altar_started)
		if not altar.weapon_forged.is_connected(_on_weapon_forged):
			altar.weapon_forged.connect(_on_weapon_forged)
	if not terminal.interaction_resolved.is_connected(_on_interaction_resolved):
		terminal.interaction_resolved.connect(_on_interaction_resolved)
	if not terminal.terminal_closed.is_connected(_on_terminal_closed):
		terminal.terminal_closed.connect(_on_terminal_closed)
	if not player.health_changed.is_connected(_on_player_health_changed):
		player.health_changed.connect(_on_player_health_changed)
	if not player.defeated.is_connected(_on_player_defeated):
		player.defeated.connect(_on_player_defeated)
	if not player.combat_action_requested.is_connected(_on_player_combat_action_requested):
		player.combat_action_requested.connect(_on_player_combat_action_requested)
	if not level_exit.exit_entered.is_connected(_on_exit_entered):
		level_exit.exit_entered.connect(_on_exit_entered)


func _ensure_enemy_pool(count: int) -> void:
	var current_pool: Array[EnemyEncounter] = []
	for index in range(min(2, count)):
		var template_enemy: EnemyEncounter = _enemy_templates[index]
		template_enemy.visible = true
		current_pool.append(template_enemy)
	var next_index: int = current_pool.size()
	while next_index < count:
		var source_template: EnemyEncounter = _enemy_templates[next_index % _enemy_templates.size()]
		var clone := source_template.duplicate() as EnemyEncounter
		clone.name = _enemy_node_name_for_index(next_index)
		clone.global_position = Vector2(-2000.0 - float(next_index) * 40.0, -2000.0)
		add_child(clone)
		current_pool.append(clone)
		next_index += 1
	for child in get_children():
		if child is EnemyEncounter:
			var encounter_child: EnemyEncounter = child as EnemyEncounter
			if current_pool.has(encounter_child):
				continue
			if encounter_child in _enemy_templates:
				encounter_child.visible = false
				continue
			encounter_child.queue_free()
	_encounters = current_pool


func _build_runtime_enemy_configs(config: Dictionary) -> Array:
	var archetypes_variant: Variant = config.get("enemy_archetypes", [])
	var archetypes: Array = archetypes_variant if typeof(archetypes_variant) == TYPE_ARRAY else []
	if archetypes.is_empty():
		archetypes = [
			{"difficulty": "easy", "attack_style": "melee"},
			{"difficulty": "normal", "attack_style": "ranged"}
		]
	var count_min: int = int(config.get("enemy_count_min", 14))
	var count_max: int = int(config.get("enemy_count_max", 18))
	var encounter_count: int = randi_range(count_min, count_max)
	var encounter_configs: Array = []
	for index in range(encounter_count):
		var archetype: Dictionary = (archetypes[randi_range(0, archetypes.size() - 1)] as Dictionary).duplicate(true)
		archetype["node_name"] = _enemy_node_name_for_index(index)
		_apply_level_theme_encounter_lesson(archetype, index)
		encounter_configs.append(archetype)
	return encounter_configs


func _enemy_node_name_for_index(index: int) -> String:
	if index == 0:
		return "EnemyEncounterA"
	if index == 1:
		return "EnemyEncounterB"
	return "EnemyEncounter%02d" % [index + 1]


func _load_level_config() -> Dictionary:
	var resolved_path: String = level_config_path if not level_config_path.is_empty() else DEFAULT_LEVEL_CONFIG_PATH
	if not FileAccess.file_exists(resolved_path):
		push_warning("Level config missing: %s" % resolved_path)
		return {}
	var file := FileAccess.open(resolved_path, FileAccess.READ)
	if file == null:
		push_warning("Unable to open level config: %s" % resolved_path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Level config has invalid JSON payload: %s" % resolved_path)
		return {}
	return parsed


func _apply_level_config(config: Dictionary) -> void:
	if config.is_empty():
		return
	_messages["intro"] = String(config.get("intro_message", _messages["intro"]))
	_messages["remaining"] = String(config.get("encounter_remaining_message", _messages["remaining"]))
	_messages["exit_unlocked"] = String(config.get("exit_unlocked_message", _messages["exit_unlocked"]))
	_messages["level_complete"] = String(config.get("level_complete_message", _messages["level_complete"]))
	_messages["encounter_cancelled"] = String(config.get("encounter_cancelled_message", _messages["encounter_cancelled"]))
	_messages["respawn"] = String(config.get("respawn_message", _messages["respawn"]))
	_messages["defeat"] = String(config.get("defeat_message", _messages["defeat"]))
	_player_damage_on_failure = int(config.get("player_damage_on_failure", _player_damage_on_failure))
	hud.set_level_context(_level_context_text(config))
	hud.set_boss_status(_level_boss_teaser_text(config))
	_apply_encounter_configs(config.get("encounters", []))
	_apply_chest_configs(config.get("chests", []))
	_apply_altar_configs(config.get("altars", []))
	var exit_config_variant: Variant = config.get("exit", {})
	if typeof(exit_config_variant) == TYPE_DICTIONARY:
		var exit_config: Dictionary = (exit_config_variant as Dictionary).duplicate(true)
		if _generated_layout.has("exit"):
			var exit_spawn: Vector2 = _generated_layout.get("exit", Vector2.ZERO)
			exit_config["position"] = [exit_spawn.x, exit_spawn.y]
		level_exit.configure(exit_config)


func _apply_generated_layout(layout: Dictionary) -> void:
	var spawn_position: Vector2 = layout.get("player_spawn", player.global_position)
	_room_descriptors = layout.get("rooms", [])
	_current_room_key = ""
	player.set_spawn_position(spawn_position)
	player.respawn()
	var limits_variant: Variant = layout.get("camera_limits", {})
	if typeof(limits_variant) == TYPE_DICTIONARY:
		var limits: Dictionary = limits_variant
		player.set_camera_limits(
			int(limits.get("left", 0)),
			int(limits.get("top", 0)),
			int(limits.get("right", 2600)),
			int(limits.get("bottom", 720))
		)
	_update_room_context(true)
	_update_level_objective()


func _initialize_adaptive_difficulty() -> void:
	var defaults_variant: Variant = _level_config.get("adaptive_defaults", {})
	var defaults: Dictionary = defaults_variant if typeof(defaults_variant) == TYPE_DICTIONARY else {}
	_adaptive_difficulty_state = {
		"combat": _make_adaptive_entry(String(defaults.get("combat", _default_combat_difficulty())), 2, 2),
		"chest": _make_adaptive_entry(String(defaults.get("chest", "easy")), 2, 3),
		"altar": _make_adaptive_entry(String(defaults.get("altar", "easy")), 2, 3),
		"boss": _make_adaptive_entry(String(defaults.get("boss", "normal")), 2, 2)
	}


func _default_combat_difficulty() -> String:
	var archetypes_variant: Variant = _level_config.get("enemy_archetypes", [])
	if typeof(archetypes_variant) != TYPE_ARRAY or (archetypes_variant as Array).is_empty():
		return "easy"
	var first_archetype_variant: Variant = (archetypes_variant as Array)[0]
	if typeof(first_archetype_variant) != TYPE_DICTIONARY:
		return "easy"
	var first_archetype: Dictionary = first_archetype_variant
	return String(first_archetype.get("difficulty", "easy"))


func _level_context_text(config: Dictionary) -> String:
	var level_number: int = int(config.get("level_number", 1))
	var title: String = String(config.get("title", "Variables"))
	var concept_summary: String = String(config.get("concept_summary", ""))
	if concept_summary.is_empty():
		return "Level %d: %s" % [level_number, title]
	return "Level %d: %s  |  Focus: %s" % [level_number, title, concept_summary]


func _level_boss_teaser_text(config: Dictionary) -> String:
	var boss_variant: Variant = config.get("boss", {})
	if typeof(boss_variant) != TYPE_DICTIONARY:
		return ""
	var boss: Dictionary = boss_variant
	var boss_name: String = String(boss.get("boss_name", ""))
	if boss_name.is_empty():
		return ""
	var boss_brief: String = String(boss.get("boss_brief", ""))
	if boss_brief.is_empty():
		return "Area Boss: %s" % boss_name
	return "Area Boss: %s  |  %s" % [boss_name, boss_brief]


func _make_adaptive_entry(difficulty: String, success_threshold: int, failure_threshold: int) -> Dictionary:
	return {
		"difficulty": difficulty,
		"success_streak": 0,
		"failure_streak": 0,
		"success_threshold": success_threshold,
		"failure_threshold": failure_threshold
	}


func _reset_level_runtime_bonuses() -> void:
	_player_melee_damage_bonus = 0
	_player_ranged_damage_bonus = 0
	_player_failure_damage_reduction = 0
	player.parry_window = _base_player_parry_window
	player.move_speed = _base_player_move_speed


func _apply_encounter_configs(encounter_configs: Array) -> void:
	var generated_positions: Dictionary = _generated_layout.get("encounters", {})
	for encounter_config_variant in encounter_configs:
		if typeof(encounter_config_variant) != TYPE_DICTIONARY:
			continue
		var encounter_config: Dictionary = (encounter_config_variant as Dictionary).duplicate(true)
		var node_name := String(encounter_config.get("node_name", ""))
		if node_name.is_empty():
			continue
		var encounter := get_node_or_null(NodePath(node_name)) as EnemyEncounter
		if encounter == null:
			continue
		if generated_positions.has(node_name):
			var generated_data_variant: Variant = generated_positions.get(node_name, {})
			if typeof(generated_data_variant) == TYPE_DICTIONARY:
				var generated_data: Dictionary = generated_data_variant
				var spawn_point: Vector2 = generated_data.get("position", Vector2.ZERO)
				encounter_config["position"] = [spawn_point.x, spawn_point.y]
				encounter_config["patrol_distance"] = float(generated_data.get("patrol_distance", encounter_config.get("patrol_distance", 32.0)))
				encounter_config["patrol_min_x"] = float(generated_data.get("left_bound", spawn_point.x - float(encounter_config.get("patrol_distance", 32.0))))
				encounter_config["patrol_max_x"] = float(generated_data.get("right_bound", spawn_point.x + float(encounter_config.get("patrol_distance", 32.0))))
		encounter.configure(encounter_config)


func _apply_chest_configs(chest_configs: Array) -> void:
	var generated_positions: Dictionary = _generated_layout.get("chests", {})
	for chest_config_variant in chest_configs:
		if typeof(chest_config_variant) != TYPE_DICTIONARY:
			continue
		var chest_config: Dictionary = (chest_config_variant as Dictionary).duplicate(true)
		var node_name := String(chest_config.get("node_name", ""))
		if node_name.is_empty():
			continue
		var chest := get_node_or_null(NodePath(node_name)) as ChestEncounter
		if chest == null:
			continue
		if generated_positions.has(node_name):
			var chest_spawn: Vector2 = generated_positions.get(node_name, Vector2.ZERO)
			chest_config["position"] = [chest_spawn.x, chest_spawn.y]
		_apply_level_theme_chest_lesson(chest_config, node_name)
		chest.configure(chest_config)


func _apply_altar_configs(altar_configs: Array) -> void:
	var generated_positions: Dictionary = _generated_layout.get("altars", {})
	for altar_config_variant in altar_configs:
		if typeof(altar_config_variant) != TYPE_DICTIONARY:
			continue
		var altar_config: Dictionary = (altar_config_variant as Dictionary).duplicate(true)
		var node_name := String(altar_config.get("node_name", ""))
		if node_name.is_empty():
			continue
		var altar := get_node_or_null(NodePath(node_name)) as AltarEncounter
		if altar == null:
			continue
		if generated_positions.has(node_name):
			var altar_spawn: Vector2 = generated_positions.get(node_name, Vector2.ZERO)
			altar_config["position"] = [altar_spawn.x, altar_spawn.y]
		_apply_level_theme_altar_lesson(altar_config, node_name)
		altar.configure(altar_config)


func _apply_level_theme_encounter_lesson(encounter_config: Dictionary, index: int) -> void:
	var level_id: String = String(_level_config.get("id", ""))
	if level_id == "level_01":
		_apply_level_one_encounter_lesson(encounter_config, index)
	elif level_id == "level_02":
		_apply_level_two_encounter_lesson(encounter_config, index)
	elif level_id == "level_03":
		_apply_level_three_encounter_lesson(encounter_config, index)
	elif level_id == "level_04":
		_apply_level_four_encounter_lesson(encounter_config, index)
	elif level_id == "level_05":
		_apply_level_five_encounter_lesson(encounter_config, index)


func _apply_level_theme_chest_lesson(chest_config: Dictionary, node_name: String) -> void:
	var level_id: String = String(_level_config.get("id", ""))
	if level_id == "level_01":
		_apply_level_one_chest_lesson(chest_config, node_name)
	elif level_id == "level_02":
		_apply_level_two_chest_lesson(chest_config, node_name)
	elif level_id == "level_03":
		_apply_level_three_chest_lesson(chest_config, node_name)
	elif level_id == "level_04":
		_apply_level_four_chest_lesson(chest_config, node_name)
	elif level_id == "level_05":
		_apply_level_five_chest_lesson(chest_config, node_name)


func _apply_level_theme_altar_lesson(altar_config: Dictionary, node_name: String) -> void:
	var level_id: String = String(_level_config.get("id", ""))
	if level_id == "level_01":
		_apply_level_one_altar_lesson(altar_config, node_name)
	elif level_id == "level_02":
		_apply_level_two_altar_lesson(altar_config, node_name)
	elif level_id == "level_03":
		_apply_level_three_altar_lesson(altar_config, node_name)
	elif level_id == "level_04":
		_apply_level_four_altar_lesson(altar_config, node_name)
	elif level_id == "level_05":
		_apply_level_five_altar_lesson(altar_config, node_name)


func _apply_level_one_encounter_lesson(encounter_config: Dictionary, index: int) -> void:
	if String(_level_config.get("id", "")) != "level_01":
		return
	var attack_style: String = String(encounter_config.get("attack_style", "mixed"))
	var variable_sets: Array[Dictionary] = [
		{
			"title": "Variables: Blade Terminal",
			"status_text": "Declare combat values before the sentinel closes in.",
			"starter_code": "damage = 12\nspeed = 3",
			"success_text": "Variables locked. Blade pattern accepted.",
			"failure_text": "Variable setup failed"
		},
		{
			"title": "Variables: Caster Terminal",
			"status_text": "Set ranged variables to stabilize the shot.",
			"starter_code": "projectile_speed = 8\nrange_limit = 220",
			"success_text": "Variables locked. Ranged pattern accepted.",
			"failure_text": "Variable setup failed"
		},
		{
			"title": "Variables: Archive Terminal",
			"status_text": "Assign two values to complete the archive pattern.",
			"starter_code": "damage = 10\ncooldown = 2",
			"success_text": "Archive variables accepted.",
			"failure_text": "Archive pattern rejected"
		}
	]
	var lesson: Dictionary = variable_sets[index % variable_sets.size()]
	if attack_style == "melee":
		lesson = variable_sets[0]
	elif attack_style == "ranged":
		lesson = variable_sets[1]
	encounter_config["terminal_title"] = lesson.get("title", "Combat Terminal")
	encounter_config["terminal_status_text"] = lesson.get("status_text", "Declare variables.")
	encounter_config["terminal_starter_code"] = lesson.get("starter_code", "damage = 10\nspeed = 3")
	encounter_config["terminal_success_text"] = lesson.get("success_text", "Pattern accepted.")
	encounter_config["terminal_failure_text"] = lesson.get("failure_text", "Pattern rejected")


func _apply_level_one_chest_lesson(chest_config: Dictionary, node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_01":
		return
	if node_name == "ChestA":
		chest_config["terminal_title"] = "Variables: Cache Terminal"
		chest_config["terminal_status_text"] = "Assign cache variables to unlock the first supply chest."
		chest_config["terminal_starter_code"] = "hint_tokens = 1\ncache_slots = 2"
		chest_config["terminal_success_text"] = "Cache variables accepted."
		chest_config["terminal_failure_text"] = "Cache variables incomplete."
		return
	chest_config["terminal_title"] = "Variables: Recovery Cache"
	chest_config["terminal_status_text"] = "Set recovery values to stabilize the second chest."
	chest_config["terminal_starter_code"] = "shield = 5\nrecovery = 2"
	chest_config["terminal_success_text"] = "Recovery variables accepted."
	chest_config["terminal_failure_text"] = "Recovery variables incomplete."


func _apply_level_one_altar_lesson(altar_config: Dictionary, _node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_01":
		return
	altar_config["terminal_title"] = "Variables: Forge Terminal"
	altar_config["terminal_status_text"] = "Declare weapon variables to forge your archive blade."
	altar_config["terminal_starter_code"] = "weapon_type = 'melee'\nweapon_damage = 15\nweapon_speed = 4"
	altar_config["terminal_success_text"] = "Forge variables accepted."
	altar_config["terminal_failure_text"] = "Forge variables incomplete."


func _apply_level_two_encounter_lesson(encounter_config: Dictionary, index: int) -> void:
	if String(_level_config.get("id", "")) != "level_02":
		return
	var attack_style: String = String(encounter_config.get("attack_style", "mixed"))
	var condition_sets: Array[Dictionary] = [
		{
			"title": "If/Else: Blade Logic",
			"status_text": "Choose the close-range branch before the sentinel strikes.",
			"starter_code": "if enemy_distance < 60:\n    attack = 'heavy'\nelse:\n    attack = 'light'",
			"success_text": "Combat branch accepted.",
			"failure_text": "Combat branch rejected"
		},
		{
			"title": "If/Else: Caster Logic",
			"status_text": "Use a clear condition to decide when to fire from range.",
			"starter_code": "if energy > 2:\n    projectile = 'burst'\nelse:\n    projectile = 'pulse'",
			"success_text": "Ranged branch accepted.",
			"failure_text": "Ranged branch rejected"
		},
		{
			"title": "If/Else: Archive Logic",
			"status_text": "Write one readable branch that adapts to the encounter.",
			"starter_code": "if shield_active:\n    action = 'guard'\nelse:\n    action = 'dash'",
			"success_text": "Archive branch accepted.",
			"failure_text": "Archive branch rejected"
		}
	]
	var lesson: Dictionary = condition_sets[index % condition_sets.size()]
	if attack_style == "melee":
		lesson = condition_sets[0]
	elif attack_style == "ranged":
		lesson = condition_sets[1]
	encounter_config["terminal_title"] = lesson.get("title", "Combat Terminal")
	encounter_config["terminal_status_text"] = lesson.get("status_text", "Write an if/else branch.")
	encounter_config["terminal_starter_code"] = lesson.get("starter_code", "if ready:\n    attack = 'light'\nelse:\n    attack = 'wait'")
	encounter_config["terminal_success_text"] = lesson.get("success_text", "Pattern accepted.")
	encounter_config["terminal_failure_text"] = lesson.get("failure_text", "Pattern rejected")


func _apply_level_two_chest_lesson(chest_config: Dictionary, node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_02":
		return
	if node_name == "ChestA":
		chest_config["terminal_title"] = "If/Else: Cache Branch"
		chest_config["terminal_status_text"] = "Choose the correct cache action with one if/else branch."
		chest_config["terminal_starter_code"] = "if has_key:\n    chest_state = 'open'\nelse:\n    chest_state = 'locked'"
		chest_config["terminal_success_text"] = "Cache branch accepted."
		chest_config["terminal_failure_text"] = "Cache branch incomplete."
		return
	chest_config["terminal_title"] = "If/Else: Recovery Branch"
	chest_config["terminal_status_text"] = "Use one condition to decide the recovery behavior."
	chest_config["terminal_starter_code"] = "if health < 50:\n    recovery = 'potion'\nelse:\n    recovery = 'shield'"
	chest_config["terminal_success_text"] = "Recovery branch accepted."
	chest_config["terminal_failure_text"] = "Recovery branch incomplete."


func _apply_level_two_altar_lesson(altar_config: Dictionary, _node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_02":
		return
	altar_config["terminal_title"] = "If/Else: Forge Logic"
	altar_config["terminal_status_text"] = "Branch between two weapon modes before forging."
	altar_config["terminal_starter_code"] = "if enemy_distance < 70:\n    weapon_mode = 'melee'\nelse:\n    weapon_mode = 'ranged'"
	altar_config["terminal_success_text"] = "Forge branch accepted."
	altar_config["terminal_failure_text"] = "Forge branch incomplete."


func _apply_level_three_encounter_lesson(encounter_config: Dictionary, index: int) -> void:
	if String(_level_config.get("id", "")) != "level_03":
		return
	var attack_style: String = String(encounter_config.get("attack_style", "mixed"))
	var loop_sets: Array[Dictionary] = [
		{
			"title": "Loops: Blade Sequence",
			"status_text": "Use a loop to repeat a close-range action cleanly.",
			"starter_code": "for step in range(3):\n    strike_power = step + 1",
			"success_text": "Loop pattern accepted.",
			"failure_text": "Loop pattern rejected"
		},
		{
			"title": "Loops: Caster Sequence",
			"status_text": "Build a repeated ranged pattern with a loop.",
			"starter_code": "for pulse in range(2):\n    projectile_speed = 6 + pulse",
			"success_text": "Volley loop accepted.",
			"failure_text": "Volley loop rejected"
		},
		{
			"title": "Loops: Archive Cycle",
			"status_text": "Repeat the archive action without rewriting each step.",
			"starter_code": "count = 0\nwhile count < 3:\n    count += 1",
			"success_text": "Cycle accepted.",
			"failure_text": "Cycle rejected"
		}
	]
	var lesson: Dictionary = loop_sets[index % loop_sets.size()]
	if attack_style == "melee":
		lesson = loop_sets[0]
	elif attack_style == "ranged":
		lesson = loop_sets[1]
	encounter_config["terminal_title"] = lesson.get("title", "Combat Terminal")
	encounter_config["terminal_status_text"] = lesson.get("status_text", "Write a loop.")
	encounter_config["terminal_starter_code"] = lesson.get("starter_code", "for step in range(2):\n    damage = step")
	encounter_config["terminal_success_text"] = lesson.get("success_text", "Pattern accepted.")
	encounter_config["terminal_failure_text"] = lesson.get("failure_text", "Pattern rejected")


func _apply_level_three_chest_lesson(chest_config: Dictionary, node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_03":
		return
	if node_name == "ChestA":
		chest_config["terminal_title"] = "Loops: Cache Cycle"
		chest_config["terminal_status_text"] = "Repeat the cache fill action with a short loop."
		chest_config["terminal_starter_code"] = "for slot in range(2):\n    cache_slots = slot + 1"
		chest_config["terminal_success_text"] = "Cache cycle accepted."
		chest_config["terminal_failure_text"] = "Cache cycle incomplete."
		return
	chest_config["terminal_title"] = "Loops: Recovery Cycle"
	chest_config["terminal_status_text"] = "Use a loop to stack repeated recovery steps."
	chest_config["terminal_starter_code"] = "regen = 0\nwhile regen < 3:\n    regen += 1"
	chest_config["terminal_success_text"] = "Recovery cycle accepted."
	chest_config["terminal_failure_text"] = "Recovery cycle incomplete."


func _apply_level_three_altar_lesson(altar_config: Dictionary, _node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_03":
		return
	altar_config["terminal_title"] = "Loops: Forge Sequence"
	altar_config["terminal_status_text"] = "Use a loop to build a repeating forge pattern."
	altar_config["terminal_starter_code"] = "for layer in range(3):\n    weapon_charge = layer + 1"
	altar_config["terminal_success_text"] = "Forge sequence accepted."
	altar_config["terminal_failure_text"] = "Forge sequence incomplete."


func _apply_level_four_encounter_lesson(encounter_config: Dictionary, index: int) -> void:
	if String(_level_config.get("id", "")) != "level_04":
		return
	var attack_style: String = String(encounter_config.get("attack_style", "mixed"))
	var function_sets: Array[Dictionary] = [
		{
			"title": "Functions: Blade Routine",
			"status_text": "Wrap the strike logic inside a reusable function.",
			"starter_code": "def blade_combo(power):\n    result = power\n    return result",
			"success_text": "Blade routine accepted.",
			"failure_text": "Blade routine rejected"
		},
		{
			"title": "Functions: Caster Routine",
			"status_text": "Create a ranged helper function and return a result.",
			"starter_code": "def cast_burst(speed):\n    result = speed\n    return result",
			"success_text": "Caster routine accepted.",
			"failure_text": "Caster routine rejected"
		},
		{
			"title": "Functions: Archive Routine",
			"status_text": "Move the repeated archive action into one function.",
			"starter_code": "def archive_step(value):\n    return value + 1",
			"success_text": "Archive routine accepted.",
			"failure_text": "Archive routine rejected"
		}
	]
	var lesson: Dictionary = function_sets[index % function_sets.size()]
	if attack_style == "melee":
		lesson = function_sets[0]
	elif attack_style == "ranged":
		lesson = function_sets[1]
	encounter_config["terminal_title"] = lesson.get("title", "Combat Terminal")
	encounter_config["terminal_status_text"] = lesson.get("status_text", "Write a function.")
	encounter_config["terminal_starter_code"] = lesson.get("starter_code", "def action(value):\n    return value")
	encounter_config["terminal_success_text"] = lesson.get("success_text", "Pattern accepted.")
	encounter_config["terminal_failure_text"] = lesson.get("failure_text", "Pattern rejected")


func _apply_level_four_chest_lesson(chest_config: Dictionary, node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_04":
		return
	if node_name == "ChestA":
		chest_config["terminal_title"] = "Functions: Cache Helper"
		chest_config["terminal_status_text"] = "Write a helper function for the cache action."
		chest_config["terminal_starter_code"] = "def open_cache(key_count):\n    return key_count"
		chest_config["terminal_success_text"] = "Cache helper accepted."
		chest_config["terminal_failure_text"] = "Cache helper incomplete."
		return
	chest_config["terminal_title"] = "Functions: Recovery Helper"
	chest_config["terminal_status_text"] = "Define a recovery function and return the chosen value."
	chest_config["terminal_starter_code"] = "def recovery_step(points):\n    return points + 2"
	chest_config["terminal_success_text"] = "Recovery helper accepted."
	chest_config["terminal_failure_text"] = "Recovery helper incomplete."


func _apply_level_four_altar_lesson(altar_config: Dictionary, _node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_04":
		return
	altar_config["terminal_title"] = "Functions: Forge Helper"
	altar_config["terminal_status_text"] = "Create a forge function that returns the weapon output."
	altar_config["terminal_starter_code"] = "def forge_mode(base_damage):\n    return base_damage + 3"
	altar_config["terminal_success_text"] = "Forge helper accepted."
	altar_config["terminal_failure_text"] = "Forge helper incomplete."


func _apply_level_five_encounter_lesson(encounter_config: Dictionary, index: int) -> void:
	if String(_level_config.get("id", "")) != "level_05":
		return
	var attack_style: String = String(encounter_config.get("attack_style", "mixed"))
	var integration_sets: Array[Dictionary] = [
		{
			"title": "Integration: Blade System",
			"status_text": "Combine variables, conditions, loops and functions in one combat script.",
			"starter_code": "def blade_system(power):\n    total = 0\n    for step in range(2):\n        if power > step:\n            total += power\n    return total",
			"success_text": "Blade system accepted.",
			"failure_text": "Blade system rejected"
		},
		{
			"title": "Integration: Caster System",
			"status_text": "Use a full control script for the ranged pattern.",
			"starter_code": "def cast_system(energy):\n    total = 0\n    for pulse in range(3):\n        if energy > pulse:\n            total += 1\n    return total",
			"success_text": "Caster system accepted.",
			"failure_text": "Caster system rejected"
		},
		{
			"title": "Integration: Archive System",
			"status_text": "Write one readable script that combines all core ideas.",
			"starter_code": "def archive_system(level):\n    total = 0\n    while total < level:\n        total += 1\n    return total",
			"success_text": "Archive system accepted.",
			"failure_text": "Archive system rejected"
		}
	]
	var lesson: Dictionary = integration_sets[index % integration_sets.size()]
	if attack_style == "melee":
		lesson = integration_sets[0]
	elif attack_style == "ranged":
		lesson = integration_sets[1]
	encounter_config["terminal_title"] = lesson.get("title", "Combat Terminal")
	encounter_config["terminal_status_text"] = lesson.get("status_text", "Combine the core concepts.")
	encounter_config["terminal_starter_code"] = lesson.get("starter_code", "def system(value):\n    return value")
	encounter_config["terminal_success_text"] = lesson.get("success_text", "Pattern accepted.")
	encounter_config["terminal_failure_text"] = lesson.get("failure_text", "Pattern rejected")


func _apply_level_five_chest_lesson(chest_config: Dictionary, node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_05":
		return
	if node_name == "ChestA":
		chest_config["terminal_title"] = "Integration: Cache System"
		chest_config["terminal_status_text"] = "Use a complete mini-system to unlock the cache."
		chest_config["terminal_starter_code"] = "def cache_system(keys):\n    total = 0\n    for step in range(keys):\n        total += 1\n    return total"
		chest_config["terminal_success_text"] = "Cache system accepted."
		chest_config["terminal_failure_text"] = "Cache system incomplete."
		return
	chest_config["terminal_title"] = "Integration: Recovery System"
	chest_config["terminal_status_text"] = "Combine branching and repetition in the recovery script."
	chest_config["terminal_starter_code"] = "def recovery_system(points):\n    total = 0\n    while total < points:\n        total += 1\n    return total"
	chest_config["terminal_success_text"] = "Recovery system accepted."
	chest_config["terminal_failure_text"] = "Recovery system incomplete."


func _apply_level_five_altar_lesson(altar_config: Dictionary, _node_name: String) -> void:
	if String(_level_config.get("id", "")) != "level_05":
		return
	altar_config["terminal_title"] = "Integration: Forge System"
	altar_config["terminal_status_text"] = "Forge a final weapon with a complete multi-part script."
	altar_config["terminal_starter_code"] = "def forge_system(base_damage):\n    total = 0\n    for layer in range(2):\n        if base_damage > layer:\n            total += base_damage\n    return total"
	altar_config["terminal_success_text"] = "Forge system accepted."
	altar_config["terminal_failure_text"] = "Forge system incomplete."


func _refresh_enemy_counter() -> void:
	var total_enemies: int = _encounters.size()
	var remaining_enemies: int = 0
	for encounter in _encounters:
		if is_instance_valid(encounter) and not encounter.is_defeated():
			remaining_enemies += 1
	hud.update_enemy_counter(remaining_enemies, total_enemies)
	_update_level_objective()


func _update_room_context(force: bool = false) -> void:
	if player == null or _room_descriptors.is_empty():
		return
	var player_position: Vector2 = player.global_position
	var matched_room: Dictionary = {}
	for descriptor_variant in _room_descriptors:
		if typeof(descriptor_variant) != TYPE_DICTIONARY:
			continue
		var descriptor: Dictionary = descriptor_variant
		var rect_position: Vector2 = descriptor.get("rect_position", Vector2.ZERO)
		var rect_size: Vector2 = descriptor.get("rect_size", Vector2.ZERO)
		var rect := Rect2(rect_position, rect_size)
		if rect.has_point(player_position):
			matched_room = descriptor
			break
	if matched_room.is_empty():
		return
	var room_key: String = String(matched_room.get("key", ""))
	if not force and room_key == _current_room_key:
		return
	_current_room_key = room_key
	hud.set_room_context(String(matched_room.get("title", "")))
	_update_level_objective()


func _update_level_objective() -> void:
	if hud == null:
		return
	var level_id: String = String(_level_config.get("id", "level_01"))
	hud.set_lesson_progress(_lesson_progress_text(level_id))
	if _level_completed:
		hud.set_objective("Objective: Level clear.")
		return
	var remaining_enemies: int = 0
	for encounter in _encounters:
		if is_instance_valid(encounter) and not encounter.is_defeated():
			remaining_enemies += 1
	var room_role: String = _current_room_role()
	if remaining_enemies > 0:
		hud.set_objective(_active_objective_text(level_id, room_role, remaining_enemies))
		return
	hud.set_objective(_cleared_objective_text(level_id, room_role))


func _current_room_role() -> String:
	for descriptor_variant in _room_descriptors:
		if typeof(descriptor_variant) != TYPE_DICTIONARY:
			continue
		var descriptor: Dictionary = descriptor_variant
		if String(descriptor.get("key", "")) == _current_room_key:
			return String(descriptor.get("role", ""))
	return ""


func _active_objective_text(level_id: String, room_role: String, remaining_enemies: int) -> String:
	if level_id == "level_02":
		if room_role == "altar" and not _is_any_altar_forged():
			return "Objective: Set the forge branch, then clear the logic sentries."
		if room_role == "chest" and _opened_chest_count() < _chests.size():
			return "Objective: Solve this branch cache with if/else, then continue downward."
		if room_role == "exit":
			return "Objective: Decision gate is sealed. Resolve %d remaining logic sentries first." % remaining_enemies
		return "Objective: Resolve %d remaining logic sentries and practice branching." % remaining_enemies
	if level_id == "level_03":
		if room_role == "altar" and not _is_any_altar_forged():
			return "Objective: Build the forge sequence, then break the wave sentries."
		if room_role == "chest" and _opened_chest_count() < _chests.size():
			return "Objective: Solve this cycle cache with a loop, then continue through the conduit."
		if room_role == "exit":
			return "Objective: Conduit gate is sealed. Collapse %d remaining wave sentries first." % remaining_enemies
		return "Objective: Break %d remaining wave sentries and practice repeated actions." % remaining_enemies
	if level_id == "level_04":
		if room_role == "altar" and not _is_any_altar_forged():
			return "Objective: Assemble the forge helper, then clear the archivist sentries."
		if room_role == "chest" and _opened_chest_count() < _chests.size():
			return "Objective: Build this helper cache with a function, then continue the codex climb."
		if room_role == "exit":
			return "Objective: Function gate is sealed. Defeat %d remaining archivist sentries first." % remaining_enemies
		return "Objective: Defeat %d remaining function sentries and practice reusable routines." % remaining_enemies
	if level_id == "level_05":
		if room_role == "altar" and not _is_any_altar_forged():
			return "Objective: Complete the integration forge, then stabilize the system sentries."
		if room_role == "chest" and _opened_chest_count() < _chests.size():
			return "Objective: Solve this system cache with a full combined script, then continue the vault route."
		if room_role == "exit":
			return "Objective: System gate is sealed. Stabilize %d remaining sentries first." % remaining_enemies
		return "Objective: Stabilize %d remaining system sentries and combine all core concepts." % remaining_enemies
	if level_id == "level_01":
		if room_role == "altar" and not _is_any_altar_forged():
			return "Objective: Set weapon variables at the altar, then clear the archive sentries."
		if room_role == "chest":
			if _opened_chest_count() < _chests.size():
				return "Objective: Assign variables to unlock this cache, then continue the purge."
		if room_role == "exit":
			return "Objective: Exit is sealed. Clear %d remaining sentries first." % remaining_enemies
		return "Objective: Defeat %d remaining sentries and practice variable setup." % remaining_enemies
	match room_role:
		"altar":
			return "Objective: Claim the altar, then clear the archive sentries."
		"chest":
			return "Objective: Secure the cache, then continue the purge."
		"exit":
			return "Objective: Exit is sealed. Clear the sentries first."
		_:
			return "Objective: Defeat all sentries in Level 1."


func _cleared_objective_text(level_id: String, room_role: String) -> String:
	if level_id == "level_02":
		if _opened_chest_count() < _chests.size():
			return "Objective: Path is stable. Finish opening the remaining branch caches."
		if not _is_any_altar_forged():
			return "Objective: Path is stable. Visit the forge and lock in your branch weapon."
		if room_role == "exit":
			return "Objective: Reach the decision gate and leave the logic archive."
		return "Objective: Branching mastered here. Head to the decision gate."
	if level_id == "level_03":
		if _opened_chest_count() < _chests.size():
			return "Objective: The loop path is clear. Finish the remaining cycle caches."
		if not _is_any_altar_forged():
			return "Objective: The loop path is clear. Visit the forge and complete the weapon sequence."
		if room_role == "exit":
			return "Objective: Reach the conduit gate and leave the loop foundry."
		return "Objective: Loop control mastered here. Head to the conduit gate."
	if level_id == "level_04":
		if _opened_chest_count() < _chests.size():
			return "Objective: The function path is clear. Finish the remaining helper caches."
		if not _is_any_altar_forged():
			return "Objective: The function path is clear. Visit the forge and complete the weapon helper."
		if room_role == "exit":
			return "Objective: Reach the function gate and leave the codex archive."
		return "Objective: Function logic mastered here. Head to the function gate."
	if level_id == "level_05":
		if _opened_chest_count() < _chests.size():
			return "Objective: The system path is clear. Finish the remaining system caches."
		if not _is_any_altar_forged():
			return "Objective: The system path is clear. Visit the forge and complete the final weapon system."
		if room_role == "exit":
			return "Objective: Reach the system gate and complete the final exam."
		return "Objective: Integration mastered here. Head to the final gate."
	if level_id == "level_01":
		if _opened_chest_count() < _chests.size():
			return "Objective: Path is clear. Finish opening the remaining supply caches."
		if not _is_any_altar_forged():
			return "Objective: Path is clear. Visit the altar and forge your variable blade."
		if room_role == "exit":
			return "Objective: Reach the gate and leave the archive."
		return "Objective: Variables mastered here. Head to the exit chamber."
	match room_role:
		"exit":
			return "Objective: Reach the gate and leave the archive."
		_:
			return "Objective: Path is clear. Head to the exit chamber."


func _opened_chest_count() -> int:
	var opened_count: int = 0
	for chest in _chests:
		if is_instance_valid(chest) and chest.is_opened():
			opened_count += 1
	return opened_count


func _is_any_altar_forged() -> bool:
	for altar in _altars:
		if is_instance_valid(altar) and altar.is_forged():
			return true
	return false


func _are_all_enemies_defeated() -> bool:
	for encounter in _encounters:
		if is_instance_valid(encounter) and not encounter.is_defeated():
			return false
	return true


func _is_level_exit_ready() -> bool:
	var level_id: String = String(_level_config.get("id", "level_01"))
	if not _are_all_enemies_defeated():
		return false
	if level_id == "level_01":
		return _opened_chest_count() >= _chests.size() and _is_any_altar_forged()
	if level_id == "level_02":
		return _opened_chest_count() >= _chests.size() and _is_any_altar_forged()
	if level_id == "level_03":
		return _opened_chest_count() >= _chests.size() and _is_any_altar_forged()
	if level_id == "level_04":
		return _opened_chest_count() >= _chests.size() and _is_any_altar_forged()
	if level_id == "level_05":
		return _opened_chest_count() >= _chests.size() and _is_any_altar_forged()
	return true


func _refresh_exit_state() -> void:
	level_exit.set_unlocked(_is_level_exit_ready())


func _lesson_progress_text(level_id: String) -> String:
	if level_id == "level_01":
		var combat_done: String = "Done" if _are_all_enemies_defeated() else "In Progress"
		var chest_progress: String = "%d / %d" % [_opened_chest_count(), _chests.size()]
		var forge_progress: String = "Done" if _is_any_altar_forged() else "Pending"
		return "Variables Progress: Combat %s | Caches %s | Forge %s" % [combat_done, chest_progress, forge_progress]
	if level_id == "level_02":
		var combat_done_level_two: String = "Done" if _are_all_enemies_defeated() else "In Progress"
		var chest_progress_level_two: String = "%d / %d" % [_opened_chest_count(), _chests.size()]
		var forge_progress_level_two: String = "Done" if _is_any_altar_forged() else "Pending"
		return "If/Else Progress: Combat %s | Branch Caches %s | Forge %s" % [combat_done_level_two, chest_progress_level_two, forge_progress_level_two]
	if level_id == "level_03":
		var combat_done_level_three: String = "Done" if _are_all_enemies_defeated() else "In Progress"
		var chest_progress_level_three: String = "%d / %d" % [_opened_chest_count(), _chests.size()]
		var forge_progress_level_three: String = "Done" if _is_any_altar_forged() else "Pending"
		return "Loops Progress: Combat %s | Cycle Caches %s | Forge %s" % [combat_done_level_three, chest_progress_level_three, forge_progress_level_three]
	if level_id == "level_04":
		var combat_done_level_four: String = "Done" if _are_all_enemies_defeated() else "In Progress"
		var chest_progress_level_four: String = "%d / %d" % [_opened_chest_count(), _chests.size()]
		var forge_progress_level_four: String = "Done" if _is_any_altar_forged() else "Pending"
		return "Functions Progress: Combat %s | Helper Caches %s | Forge %s" % [combat_done_level_four, chest_progress_level_four, forge_progress_level_four]
	if level_id == "level_05":
		var combat_done_level_five: String = "Done" if _are_all_enemies_defeated() else "In Progress"
		var chest_progress_level_five: String = "%d / %d" % [_opened_chest_count(), _chests.size()]
		var forge_progress_level_five: String = "Done" if _is_any_altar_forged() else "Pending"
		return "Integration Progress: Combat %s | System Caches %s | Forge %s" % [combat_done_level_five, chest_progress_level_five, forge_progress_level_five]
	return ""


func _on_encounter_started(encounter: EnemyEncounter, payload: Dictionary) -> void:
	if _level_completed:
		return
	_active_encounter = encounter
	if _active_unlock_group.is_empty():
		_active_unlock_group = _build_unlock_group_for(encounter)
	_active_chest = null
	_active_altar = null
	var adaptive_payload: Dictionary = payload.duplicate(true)
	var combat_difficulty: String = _adaptive_difficulty("combat")
	encounter.set_runtime_difficulty(combat_difficulty, true)
	adaptive_payload["difficulty"] = combat_difficulty
	adaptive_payload["time_limit"] = _time_limit_for_difficulty(combat_difficulty)
	get_tree().paused = true
	hud.set_terminal_overlay_mode(true)
	terminal.open_terminal(adaptive_payload)


func _on_chest_started(chest: ChestEncounter, payload: Dictionary) -> void:
	if _level_completed:
		return
	_active_chest = chest
	_active_encounter = null
	_active_altar = null
	var adaptive_payload: Dictionary = payload.duplicate(true)
	adaptive_payload["difficulty"] = _adaptive_difficulty("chest")
	get_tree().paused = true
	hud.set_terminal_overlay_mode(true)
	terminal.open_terminal(adaptive_payload)


func _on_altar_started(altar: AltarEncounter, payload: Dictionary) -> void:
	if _level_completed:
		return
	_active_altar = altar
	_active_encounter = null
	_active_chest = null
	var adaptive_payload: Dictionary = payload.duplicate(true)
	adaptive_payload["difficulty"] = _adaptive_difficulty("altar")
	get_tree().paused = true
	hud.set_terminal_overlay_mode(true)
	terminal.open_terminal(adaptive_payload)


func _on_interaction_resolved(success: bool, result: Dictionary) -> void:
	get_tree().paused = false
	hud.set_terminal_overlay_mode(false)
	var interaction_type := String(result.get("interaction_type", "combat"))
	if interaction_type == "chest":
		_handle_chest_resolution(success, result)
		return
	if interaction_type == "altar":
		_handle_altar_resolution(success, result)
		return
	_handle_combat_resolution(success, result)


func _handle_combat_resolution(success: bool, result: Dictionary) -> void:
	if _active_encounter == null:
		return
	_apply_adaptive_result("combat", result)
	if success:
		_apply_runtime_solution_effects(result, _active_unlock_group if not _active_unlock_group.is_empty() else [_active_encounter])
		var unlocked_count: int = 0
		if not _active_unlock_group.is_empty():
			for encounter in _active_unlock_group:
				if is_instance_valid(encounter) and not encounter.is_defeated():
					encounter.unlock_combat()
					unlocked_count += 1
		else:
			_active_encounter.unlock_combat()
			unlocked_count = 1
		hud.show_message("Combat unlocked for %d sentinel(s). Press Q, then keep the combo within 0.5 seconds." % unlocked_count, 2.2)
		_show_runtime_effect_summary(result)
		_active_unlock_group.clear()
		_active_encounter = null
		return
	var damage_to_player: int = int(result.get("damage_to_player", _player_damage_on_failure))
	damage_to_player = maxi(damage_to_player - _player_failure_damage_reduction, 0)
	var player_defeated: bool = player.apply_damage(damage_to_player)
	hud.show_message("Code failed. You took %d damage." % damage_to_player, 1.4)
	if not player_defeated:
		_active_encounter.reset_encounter()
	_active_unlock_group.clear()
	_active_encounter = null


func _fire_player_ranged_projectile(encounter: EnemyEncounter, damage: int, angle_offset: float = 0.0) -> void:
	if encounter == null or encounter.is_defeated():
		return
	var projectile := COMBAT_PROJECTILE_SCRIPT.new() as EnemyProjectile
	if projectile == null:
		return
	var start_position := player.global_position + Vector2(0.0, -10.0)
	var target_vector: Vector2 = encounter.global_position - start_position
	if target_vector.is_zero_approx():
		target_vector = Vector2.RIGHT
	var projectile_direction: Vector2 = target_vector.normalized().rotated(angle_offset)
	projectile.configure(start_position, projectile_direction, damage, PLAYER_RANGED_PROJECTILE_SPEED, "enemy", Color(0.588235, 0.847059, 1.0, 1))
	projectile.target_hit.connect(_on_player_projectile_hit)
	projectile.projectile_expired.connect(_on_player_projectile_expired)
	add_child(projectile)
	_player_projectiles.append(projectile)


func _fire_player_ranged_volley(encounter: EnemyEncounter, total_damage: int, projectile_count: int) -> void:
	var safe_count: int = maxi(projectile_count, 1)
	var damage_per_projectile: int = maxi(int(ceil(float(total_damage) / float(safe_count))), 1)
	var spread_step: float = 0.08
	var first_offset: float = -float(safe_count - 1) * 0.5 * spread_step
	for index in range(safe_count):
		var angle_offset: float = first_offset + float(index) * spread_step
		_fire_player_ranged_projectile(encounter, damage_per_projectile, angle_offset)


func _on_player_combat_action_requested(facing_direction: Vector2) -> void:
	if _level_completed or _player_combo_in_progress or get_tree().paused:
		return
	if _should_use_q_for_parry():
		player.request_parry()
		return
	var unlock_group: Array[EnemyEncounter] = _find_visible_locked_encounters()
	if not unlock_group.is_empty():
		_active_unlock_group = unlock_group
		var encounter_to_unlock: EnemyEncounter = unlock_group[0]
		encounter_to_unlock.request_code_encounter()
		return
	var target: EnemyEncounter = _resolve_combo_target(facing_direction)
	if target == null:
		if _can_perform_free_combo():
			_execute_free_combo(facing_direction)
			return
		if not _is_waiting_for_combo_followup():
			_reset_player_combo_state()
			hud.show_message("Stand close to an unlocked enemy to attack.", 0.9)
		return
	_execute_player_combo(target, facing_direction)


func _should_use_q_for_parry() -> bool:
	for encounter in _encounters:
		if not is_instance_valid(encounter):
			continue
		if encounter.can_accept_q_parry():
			return true
	return false


func _find_player_combat_target(_facing_direction: Vector2) -> EnemyEncounter:
	var chosen_target: EnemyEncounter = null
	var chosen_distance: float = PLAYER_TARGET_ACQUIRE_RANGE
	for encounter in _encounters:
		if not is_instance_valid(encounter) or encounter.is_defeated() or not encounter.is_combat_unlocked():
			continue
		var offset: Vector2 = encounter.global_position - player.global_position
		var distance: float = offset.length()
		if distance > PLAYER_TARGET_ACQUIRE_RANGE:
			continue
		if chosen_target == null or distance < chosen_distance:
			chosen_target = encounter
			chosen_distance = distance
	return chosen_target


func _find_visible_locked_encounters() -> Array[EnemyEncounter]:
	var candidates: Array[EnemyEncounter] = []
	var chosen_distance: float = PLAYER_TARGET_ACQUIRE_RANGE
	var chosen_target: EnemyEncounter = null
	for encounter in _encounters:
		if not is_instance_valid(encounter) or encounter.is_defeated() or encounter.is_combat_unlocked():
			continue
		if not encounter.is_player_visible():
			continue
		candidates.append(encounter)
		var distance: float = player.global_position.distance_to(encounter.global_position)
		if distance > chosen_distance:
			continue
		chosen_target = encounter
		chosen_distance = distance
	if chosen_target == null:
		return []
	candidates.erase(chosen_target)
	candidates.push_front(chosen_target)
	return candidates


func _resolve_combo_target(facing_direction: Vector2) -> EnemyEncounter:
	var now_seconds: float = Time.get_ticks_msec() / 1000.0
	if _is_combo_target_valid(_player_combo_target) and now_seconds >= _player_combo_window_open and now_seconds <= _player_combo_window_close:
		return _player_combo_target
	if _is_combo_target_valid(_player_combo_target) and now_seconds < _player_combo_window_open:
		hud.show_message("Continue the combo a little later.", 0.8)
		return null
	_reset_player_combo_state()
	return _find_player_combat_target(facing_direction)


func _execute_player_combo(target: EnemyEncounter, facing_direction: Vector2) -> void:
	_player_combo_in_progress = true
	var action_direction: Vector2 = _combat_direction_to_target(target, facing_direction)
	if _player_combo_step == 0 or _player_combo_mode.is_empty():
		_player_combo_mode = _choose_combo_mode(target)
	match _player_combo_step:
		1:
			_apply_player_combo_step(target, _player_combo_mode, 1, action_direction)
		2:
			_apply_player_combo_step(target, _player_combo_mode, 2, action_direction)
			_reset_player_combo_state()
		_:
			_apply_player_combo_step(target, _player_combo_mode, 0, action_direction)
			_player_combo_target = target
			_player_combo_step = 1
			_set_player_combo_window()
	_player_combo_in_progress = false
	_refresh_enemy_counter()


func _execute_free_combo(facing_direction: Vector2) -> void:
	_player_combo_in_progress = true
	if _player_combo_step == 0 or _player_combo_mode.is_empty():
		var passive_target: EnemyEncounter = _find_nearest_unlocked_target_any()
		_player_combo_mode = _choose_combo_mode(passive_target) if passive_target != null else "melee"
	match _player_combo_step:
		1:
			_play_free_combo_step(_player_combo_mode, 1, facing_direction)
			_player_combo_step = 2
			_set_player_combo_window()
		2:
			_play_free_combo_step(_player_combo_mode, 2, facing_direction)
			_reset_player_combo_state()
		_:
			_play_free_combo_step(_player_combo_mode, 0, facing_direction)
			_player_combo_step = 1
			_set_player_combo_window()
	_player_combo_in_progress = false


func _apply_player_combo_step(target: EnemyEncounter, combo_mode: String, combo_index: int, facing_direction: Vector2) -> void:
	if not _is_combo_target_valid(target):
		return
	var motion_name: String = _motion_name_for_combo(combo_mode, combo_index)
	player.perform_combat_motion(motion_name, facing_direction, target.global_position)
	if combo_mode == "ranged":
		var ranged_damage: int = PLAYER_RANGED_COMBO_DAMAGE[min(combo_index, PLAYER_RANGED_COMBO_DAMAGE.size() - 1)] + _player_ranged_damage_bonus
		_fire_player_ranged_volley(target, ranged_damage, combo_index + 1)
		hud.show_message(_combo_step_message(combo_mode, combo_index), 0.8)
		if combo_index < 2:
			_player_combo_target = target
			_player_combo_step = combo_index + 1
			_set_player_combo_window()
		return
	if not _can_player_melee_target(target):
		hud.show_message("Target slipped out of melee range.", 0.8)
		return
	var melee_damage: int = PLAYER_MELEE_COMBO_DAMAGE[min(combo_index, PLAYER_MELEE_COMBO_DAMAGE.size() - 1)] + _player_melee_damage_bonus
	var defeated: bool = target.apply_combat_result({"damage": melee_damage})
	if defeated:
		_reset_player_combo_state()
		hud.show_message("Enemy defeated.", 1.0)
	else:
		hud.show_message(_combo_step_message(combo_mode, combo_index), 0.8)
		if combo_index < 2:
			_player_combo_target = target
			_player_combo_step = combo_index + 1
			_set_player_combo_window()


func _play_free_combo_step(combo_mode: String, combo_index: int, facing_direction: Vector2) -> void:
	player.perform_combat_motion(_motion_name_for_combo(combo_mode, combo_index), facing_direction)
	hud.show_message(_combo_step_message(combo_mode, combo_index), 0.8)


func _motion_name_for_combo(combo_mode: String, combo_index: int) -> String:
	if combo_mode == "ranged":
		match combo_index:
			1:
				return "ranged_two"
			2:
				return "ranged_three"
			_:
				return "ranged_one"
	match combo_index:
		1:
			return "melee_two"
		2:
			return "melee_three"
		_:
			return "melee_one"


func _combo_step_message(combo_mode: String, combo_index: int) -> String:
	if combo_mode == "ranged":
		match combo_index:
			1:
				return "Ranged combo: double volley fired."
			2:
				return "Ranged combo: triple volley fired."
			_:
				return "Ranged combo: opening shot fired."
	match combo_index:
		1:
			return "Melee combo: second strike landed."
		2:
			return "Melee combo: finisher landed."
		_:
			return "Melee combo: opening strike landed."


func _choose_combo_mode(target: EnemyEncounter) -> String:
	if not _is_combo_target_valid(target):
		return "melee"
	var distance: float = player.global_position.distance_to(target.global_position)
	if distance <= PLAYER_MELEE_PREFERRED_RANGE:
		return "melee"
	if distance >= PLAYER_RANGED_PREFERRED_RANGE:
		return "ranged"
	var melee_gap: float = absf(distance - PLAYER_MELEE_PREFERRED_RANGE)
	var ranged_gap: float = absf(distance - PLAYER_RANGED_PREFERRED_RANGE)
	return "ranged" if ranged_gap < melee_gap else "melee"


func _find_nearest_unlocked_target_any() -> EnemyEncounter:
	var chosen_target: EnemyEncounter = null
	var chosen_distance: float = PLAYER_TARGET_ACQUIRE_RANGE
	for encounter in _encounters:
		if not is_instance_valid(encounter) or encounter.is_defeated() or not encounter.is_combat_unlocked():
			continue
		var distance: float = player.global_position.distance_to(encounter.global_position)
		if distance > chosen_distance:
			continue
		chosen_target = encounter
		chosen_distance = distance
	return chosen_target


func _build_unlock_group_for(primary_encounter: EnemyEncounter) -> Array[EnemyEncounter]:
	var unlock_group: Array[EnemyEncounter] = []
	for encounter in _find_visible_locked_encounters():
		if is_instance_valid(encounter):
			unlock_group.append(encounter)
	if primary_encounter != null and is_instance_valid(primary_encounter) and not unlock_group.has(primary_encounter):
		unlock_group.push_front(primary_encounter)
	return unlock_group


func _is_combo_target_valid(target: EnemyEncounter) -> bool:
	return target != null and is_instance_valid(target) and not target.is_defeated() and target.is_combat_unlocked()


func _can_player_melee_target(target: EnemyEncounter) -> bool:
	if not _is_combo_target_valid(target):
		return false
	var offset: Vector2 = target.global_position - player.global_position
	if absf(offset.y) > PLAYER_MELEE_VERTICAL_TOLERANCE:
		return false
	if absf(offset.x) > PLAYER_MELEE_RANGE:
		return false
	return true


func _combat_direction_to_target(target: EnemyEncounter, fallback_direction: Vector2) -> Vector2:
	if _is_combo_target_valid(target):
		var offset_x: float = target.global_position.x - player.global_position.x
		if not is_zero_approx(offset_x):
			return Vector2(signf(offset_x), 0.0)
	return fallback_direction if not fallback_direction.is_zero_approx() else Vector2.RIGHT


func _is_waiting_for_combo_followup() -> bool:
	if not _is_combo_target_valid(_player_combo_target):
		return false
	var now_seconds: float = Time.get_ticks_msec() / 1000.0
	return now_seconds < _player_combo_window_open


func _can_perform_free_combo() -> bool:
	for encounter in _encounters:
		if not is_instance_valid(encounter) or encounter.is_defeated():
			continue
		if encounter.is_player_visible():
			return false
	return true


func _reset_player_combo_state() -> void:
	_player_combo_step = 0
	_player_combo_target = null
	_player_combo_mode = ""
	_player_combo_window_open = 0.0
	_player_combo_window_close = 0.0


func _set_player_combo_window() -> void:
	var now_seconds: float = Time.get_ticks_msec() / 1000.0
	_player_combo_window_open = now_seconds + PLAYER_COMBO_FOLLOWUP_DELAY - PLAYER_COMBO_FOLLOWUP_TOLERANCE
	_player_combo_window_close = now_seconds + PLAYER_COMBO_FOLLOWUP_DELAY + PLAYER_COMBO_FOLLOWUP_TOLERANCE


func _on_player_projectile_hit(projectile: EnemyProjectile, target: Node, damage: int) -> void:
	_player_projectiles.erase(projectile)
	if target is EnemyEncounter:
		var encounter := target as EnemyEncounter
		var defeated: bool = encounter.apply_combat_result({"damage": damage})
		if defeated:
			hud.show_message("Ranged hit confirmed. Enemy defeated.", 1.4)
		else:
			hud.show_message("Ranged hit confirmed.", 1.0)
		_refresh_enemy_counter()


func _on_player_projectile_expired(projectile: EnemyProjectile) -> void:
	_player_projectiles.erase(projectile)


func _clear_player_projectiles() -> void:
	for projectile in _player_projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_player_projectiles.clear()


func _handle_chest_resolution(success: bool, result: Dictionary) -> void:
	if _active_chest == null:
		return
	if success:
		_apply_adaptive_result("chest", result)
		_apply_runtime_solution_effects(result, [])
		_active_chest.mark_opened()
		_show_runtime_effect_summary(result)
	else:
		_active_chest.reset_interaction()
	_active_chest = null


func _handle_altar_resolution(success: bool, result: Dictionary) -> void:
	if _active_altar == null:
		return
	if success:
		_apply_adaptive_result("altar", result)
		_apply_runtime_solution_effects(result, [])
		_active_altar.mark_forged(String(result.get("weapon_summary", "Forged a standard glitch blade.")))
		_show_runtime_effect_summary(result)
	else:
		_active_altar.reset_interaction()
	_active_altar = null


func _apply_adaptive_result(interaction_type: String, result: Dictionary) -> void:
	var entry: Dictionary = _adaptive_entry(interaction_type)
	var success: bool = bool(result.get("success", true))
	var suggested: String = String(result.get("suggested_difficulty", _adaptive_difficulty(interaction_type)))
	var current_difficulty: String = String(entry.get("difficulty", suggested))
	var success_streak: int = int(entry.get("success_streak", 0))
	var failure_streak: int = int(entry.get("failure_streak", 0))
	if success:
		success_streak += 1
		failure_streak = 0
	else:
		failure_streak += 1
		success_streak = 0
	entry["success_streak"] = success_streak
	entry["failure_streak"] = failure_streak
	var success_threshold: int = int(entry.get("success_threshold", 2))
	var failure_threshold: int = int(entry.get("failure_threshold", 2))
	if success_streak >= success_threshold:
		suggested = _step_difficulty(current_difficulty, 1)
		entry["success_streak"] = 0
	elif failure_streak >= failure_threshold:
		suggested = _step_difficulty(current_difficulty, -1)
		entry["failure_streak"] = 0
	_adaptive_difficulty_state[interaction_type] = entry
	if suggested.is_empty():
		return
	_set_adaptive_difficulty(interaction_type, suggested)


func _set_adaptive_difficulty(interaction_type: String, value: String) -> void:
	var current_value: String = _adaptive_difficulty(interaction_type)
	if current_value == value:
		return
	var entry: Dictionary = _adaptive_entry(interaction_type)
	entry["difficulty"] = value
	_adaptive_difficulty_state[interaction_type] = entry
	if interaction_type == "combat":
		_sync_enemy_difficulties(value)
	hud.show_message("Adaptive %s difficulty -> %s" % [interaction_type, value.capitalize()], 1.4)


func _sync_enemy_difficulties(difficulty: String) -> void:
	for encounter in _encounters:
		if not is_instance_valid(encounter) or encounter.is_defeated() or encounter == _active_encounter:
			continue
		encounter.set_runtime_difficulty(difficulty, true)


func _adaptive_difficulty(interaction_type: String) -> String:
	var entry: Dictionary = _adaptive_entry(interaction_type)
	return String(entry.get("difficulty", "easy"))


func _adaptive_entry(interaction_type: String) -> Dictionary:
	var entry_variant: Variant = _adaptive_difficulty_state.get(interaction_type, {})
	if typeof(entry_variant) == TYPE_DICTIONARY:
		return entry_variant
	return _make_adaptive_entry("easy", 2, 2)


func _step_difficulty(current: String, direction: int) -> String:
	var order: Array[String] = ["easy", "normal", "hard"]
	var index: int = order.find(current)
	if index == -1:
		index = 0
	var next_index: int = clampi(index + direction, 0, order.size() - 1)
	return order[next_index]


func _time_limit_for_difficulty(value: String) -> int:
	match value:
		"hard":
			return 60
		"normal":
			return 120
		_:
			return 180


func _apply_runtime_solution_effects(result: Dictionary, target_encounters: Array) -> void:
	var runtime_effects_variant: Variant = result.get("resolved_effects", {})
	if typeof(runtime_effects_variant) != TYPE_DICTIONARY:
		return
	var runtime_effects: Dictionary = runtime_effects_variant
	var player_effects_variant: Variant = runtime_effects.get("player", {})
	var target_effects_variant: Variant = runtime_effects.get("target", {})
	var player_effects: Dictionary = player_effects_variant if typeof(player_effects_variant) == TYPE_DICTIONARY else {}
	var target_effects: Dictionary = target_effects_variant if typeof(target_effects_variant) == TYPE_DICTIONARY else {}

	if player_effects.has("heal_amount"):
		player.heal(int(player_effects.get("heal_amount", 0)))
	if player_effects.has("move_speed_bonus"):
		player.move_speed = maxf(player.move_speed, _base_player_move_speed + float(player_effects.get("move_speed_bonus", 0.0)))
	if player_effects.has("parry_window_bonus"):
		player.parry_window = maxf(player.parry_window, _base_player_parry_window + float(player_effects.get("parry_window_bonus", 0.0)))
	if player_effects.has("melee_damage_bonus"):
		_player_melee_damage_bonus = maxi(_player_melee_damage_bonus, int(player_effects.get("melee_damage_bonus", 0)))
	if player_effects.has("ranged_damage_bonus"):
		_player_ranged_damage_bonus = maxi(_player_ranged_damage_bonus, int(player_effects.get("ranged_damage_bonus", 0)))
	if player_effects.has("failure_damage_reduction"):
		_player_failure_damage_reduction = maxi(_player_failure_damage_reduction, int(player_effects.get("failure_damage_reduction", 0)))

	if target_effects.is_empty():
		return
	for encounter_variant in target_encounters:
		var encounter: EnemyEncounter = encounter_variant as EnemyEncounter
		if encounter == null or not is_instance_valid(encounter) or encounter.is_defeated():
			continue
		encounter.apply_terminal_effects(target_effects)


func _show_runtime_effect_summary(result: Dictionary) -> void:
	var runtime_effects_variant: Variant = result.get("resolved_effects", {})
	if typeof(runtime_effects_variant) != TYPE_DICTIONARY:
		return
	var runtime_effects: Dictionary = runtime_effects_variant
	var summary_variant: Variant = runtime_effects.get("summary", [])
	if typeof(summary_variant) != TYPE_ARRAY:
		return
	var summary_items: Array = summary_variant
	var lines: PackedStringArray = []
	for item_variant in summary_items:
		var item_text: String = String(item_variant).strip_edges()
		if not item_text.is_empty():
			lines.append(item_text)
	if lines.is_empty():
		return
	hud.show_message("Runtime effects: %s." % ", ".join(lines), 2.0)


func _on_terminal_closed() -> void:
	get_tree().paused = false
	hud.set_terminal_overlay_mode(false)
	if _active_encounter != null:
		_active_encounter.reset_encounter()
		_active_encounter = null
	_active_unlock_group.clear()
	if _active_chest != null:
		_active_chest.reset_interaction()
		_active_chest = null
	if _active_altar != null:
		_active_altar.reset_interaction()
		_active_altar = null
	_reset_player_combo_state()
	hud.show_message(_messages["encounter_cancelled"], 1.0)


func _on_player_health_changed(current_health: int, max_health: int) -> void:
	hud.update_health(current_health, max_health)


func _on_enemy_world_attack_feedback(message: String) -> void:
	if get_tree().paused or _level_completed:
		return
	hud.show_message(message, 0.9)


func _on_player_defeated() -> void:
	if _respawn_in_progress:
		return
	_respawn_in_progress = true
	get_tree().paused = false
	hud.set_terminal_overlay_mode(false)
	_level_completed = false
	_player_combo_in_progress = false
	_reset_player_combo_state()
	_active_unlock_group.clear()
	terminal.hide_terminal()
	_active_encounter = null
	_active_chest = null
	_active_altar = null
	hud.show_message(_messages["defeat"], 1.5)
	await get_tree().create_timer(1.5, true).timeout
	if not is_inside_tree():
		return
	player.respawn()
	_clear_player_projectiles()
	_prepare_runtime_level_state()
	_refresh_exit_state()
	hud.show_message(_messages["respawn"], 1.2)
	_completion_fade_started = false
	fade_rect.visible = false
	_respawn_in_progress = false


func _on_encounter_defeated(_encounter: EnemyEncounter) -> void:
	if _encounter == _player_combo_target:
		_reset_player_combo_state()
	_active_encounter = null
	_refresh_enemy_counter()
	var all_cleared: bool = _are_all_enemies_defeated()
	if all_cleared:
		_refresh_exit_state()
		if _is_level_exit_ready():
			hud.show_message(_messages["exit_unlocked"], 2.0)
		else:
			var level_id: String = String(_level_config.get("id", "level_01"))
			if level_id == "level_02":
				hud.show_message("Combat complete. Finish the If/Else branch caches and forge before the gate opens.", 2.4)
			elif level_id == "level_03":
				hud.show_message("Combat complete. Finish the loop caches and forge sequence before the conduit opens.", 2.4)
			elif level_id == "level_04":
				hud.show_message("Combat complete. Finish the helper caches and function forge before the gate opens.", 2.4)
			elif level_id == "level_05":
				hud.show_message("Combat complete. Finish the system caches and final forge before the system gate opens.", 2.5)
			else:
				hud.show_message("Combat complete. Finish the Variables caches and forge before the exit opens.", 2.3)
	else:
		var remaining_count: int = 0
		for encounter in _encounters:
			if not encounter.is_defeated():
				remaining_count += 1
		hud.show_message("%s Remaining: %d" % [_messages["remaining"], remaining_count], 1.4)


func _on_exit_entered() -> void:
	if _level_completed:
		return
	_level_completed = true
	level_exit.set_unlocked(false)
	GameState.mark_level_completed(String(_level_config.get("id", "level_01")))
	hud.show_message(_messages["level_complete"], 3.0)
	call_deferred("_play_level_outro_fade")


func _on_chest_opened(chest: ChestEncounter, reward_text: String) -> void:
	if _level_completed:
		return
	var reward_suffix: String = ""
	var level_id: String = String(_level_config.get("id", ""))
	if level_id == "level_01":
		if chest.name == "ChestA":
			player.restore_full_health()
			reward_suffix = " Integrity fully restored."
		elif chest.name == "ChestB":
			_player_failure_damage_reduction = max(_player_failure_damage_reduction, 8)
			reward_suffix = " Code failures now hurt less."
	elif level_id == "level_02":
		if chest.name == "ChestA":
			player.restore_full_health()
			reward_suffix = " Branch cache stabilized. Integrity restored."
		elif chest.name == "ChestB":
			player.parry_window = _base_player_parry_window + 0.08
			reward_suffix = " Branch timing improved. Parry window increased."
	elif level_id == "level_03":
		if chest.name == "ChestA":
			player.restore_full_health()
			reward_suffix = " Cycle cache stabilized. Integrity restored."
		elif chest.name == "ChestB":
			_player_ranged_damage_bonus = max(_player_ranged_damage_bonus, 8)
			reward_suffix = " Volley loop improved. Ranged combo damage increased."
	elif level_id == "level_04":
		if chest.name == "ChestA":
			player.restore_full_health()
			reward_suffix = " Helper cache stabilized. Integrity restored."
		elif chest.name == "ChestB":
			_player_failure_damage_reduction = max(_player_failure_damage_reduction, 12)
			reward_suffix = " Helper routines optimized. Code failures now hurt less."
	elif level_id == "level_05":
		if chest.name == "ChestA":
			player.restore_full_health()
			_player_failure_damage_reduction = max(_player_failure_damage_reduction, 14)
			reward_suffix = " System cache stabilized. Integrity restored and failures reduced."
		elif chest.name == "ChestB":
			_player_melee_damage_bonus = max(_player_melee_damage_bonus, 14)
			_player_ranged_damage_bonus = max(_player_ranged_damage_bonus, 14)
			reward_suffix = " Final system cache online. All combat output increased."
	var opened_count: int = _opened_chest_count()
	var progress_label: String = "Variables cache progress"
	if level_id == "level_02":
		progress_label = "Branch cache progress"
	elif level_id == "level_03":
		progress_label = "Cycle cache progress"
	elif level_id == "level_04":
		progress_label = "Helper cache progress"
	elif level_id == "level_05":
		progress_label = "System cache progress"
	GameState.add_inventory_hint("%s %s" % [progress_label, String(chest.name)], "%s%s" % [reward_text, reward_suffix])
	hud.show_message("%s%s %s: %d / %d." % [reward_text, reward_suffix, progress_label, opened_count, _chests.size()], 2.4)
	_refresh_exit_state()
	if _is_level_exit_ready():
		hud.show_message(_messages["exit_unlocked"], 2.0)
	_update_level_objective()


func _on_weapon_forged(_altar: AltarEncounter, weapon_summary: String) -> void:
	if _level_completed:
		return
	var level_id: String = String(_level_config.get("id", ""))
	if level_id == "level_01":
		_player_melee_damage_bonus = 8
		_player_ranged_damage_bonus = 6
		hud.show_message("%s Variable forge complete. Weapon power increased." % weapon_summary, 2.6)
	elif level_id == "level_02":
		_player_melee_damage_bonus = 6
		_player_ranged_damage_bonus = 10
		_player_failure_damage_reduction = max(_player_failure_damage_reduction, 10)
		hud.show_message("%s Branch forge complete. Weapon modes stabilized." % weapon_summary, 2.6)
	elif level_id == "level_03":
		_player_melee_damage_bonus = 10
		_player_ranged_damage_bonus = 10
		player.parry_window = _base_player_parry_window + 0.1
		hud.show_message("%s Loop forge complete. Combo sequence stabilized." % weapon_summary, 2.6)
	elif level_id == "level_04":
		_player_melee_damage_bonus = 12
		_player_ranged_damage_bonus = 12
		_player_failure_damage_reduction = max(_player_failure_damage_reduction, 14)
		hud.show_message("%s Function forge complete. Combat routines upgraded." % weapon_summary, 2.6)
	elif level_id == "level_05":
		_player_melee_damage_bonus = 18
		_player_ranged_damage_bonus = 18
		_player_failure_damage_reduction = max(_player_failure_damage_reduction, 16)
		player.parry_window = _base_player_parry_window + 0.12
		hud.show_message("%s Integration forge complete. Full combat system upgraded." % weapon_summary, 2.8)
	else:
		hud.show_message(weapon_summary, 2.2)
	_refresh_exit_state()
	if _is_level_exit_ready():
		hud.show_message(_messages["exit_unlocked"], 2.0)
	_update_level_objective()
