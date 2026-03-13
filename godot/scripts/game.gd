extends Node2D

const LEVEL_CONFIG_PATH := "res://data/levels/level_01.json"
const PLAYER_RANGED_PROJECTILE_SPEED := 420.0

const COMBAT_PROJECTILE_SCRIPT := preload("res://scripts/enemy_projectile.gd")
const LEVEL_LAYOUT_GENERATOR_SCRIPT := preload("res://scripts/level_layout_generator.gd")

@onready var backdrop: ColorRect = $Backdrop
@onready var geometry_root: Node2D = $LevelGeometry
@onready var terminal: CanvasLayer = $CombatTerminal
@onready var player: PlayerController = $Player
@onready var hud: GameHud = $Hud
@onready var level_exit: LevelExit = $LevelExit
@onready var enemy_template_a: EnemyEncounter = $EnemyEncounterA
@onready var enemy_template_b: EnemyEncounter = $EnemyEncounterB

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
	_enemy_templates = [enemy_template_a, enemy_template_b]
	_chests = [$ChestA, $ChestB]
	_altars = [$AltarA]
	_level_config = _load_level_config()
	_prepare_runtime_level_state()
	hud.update_health(player.current_health, player.max_health)
	hud.set_boss_status("")
	hud.show_message(_messages["intro"], 1.8)
	level_exit.set_unlocked(false)


func _prepare_runtime_level_state() -> void:
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
		encounter_configs.append(archetype)
	return encounter_configs


func _enemy_node_name_for_index(index: int) -> String:
	if index == 0:
		return "EnemyEncounterA"
	if index == 1:
		return "EnemyEncounterB"
	return "EnemyEncounter%02d" % [index + 1]


func _load_level_config() -> Dictionary:
	if not FileAccess.file_exists(LEVEL_CONFIG_PATH):
		push_warning("Level config missing: %s" % LEVEL_CONFIG_PATH)
		return {}
	var file := FileAccess.open(LEVEL_CONFIG_PATH, FileAccess.READ)
	if file == null:
		push_warning("Unable to open level config: %s" % LEVEL_CONFIG_PATH)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Level config has invalid JSON payload: %s" % LEVEL_CONFIG_PATH)
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
		altar.configure(altar_config)


func _refresh_enemy_counter() -> void:
	var total_enemies: int = _encounters.size()
	var remaining_enemies: int = 0
	for encounter in _encounters:
		if is_instance_valid(encounter) and not encounter.is_defeated():
			remaining_enemies += 1
	hud.update_enemy_counter(remaining_enemies, total_enemies)


func _on_encounter_started(encounter: EnemyEncounter, payload: Dictionary) -> void:
	if _level_completed:
		return
	_active_encounter = encounter
	_active_chest = null
	_active_altar = null
	get_tree().paused = true
	terminal.open_terminal(payload)


func _on_chest_started(chest: ChestEncounter, payload: Dictionary) -> void:
	if _level_completed:
		return
	_active_chest = chest
	_active_encounter = null
	_active_altar = null
	get_tree().paused = true
	terminal.open_terminal(payload)


func _on_altar_started(altar: AltarEncounter, payload: Dictionary) -> void:
	if _level_completed:
		return
	_active_altar = altar
	_active_encounter = null
	_active_chest = null
	get_tree().paused = true
	terminal.open_terminal(payload)


func _on_interaction_resolved(success: bool, result: Dictionary) -> void:
	get_tree().paused = false
	var interaction_type := String(result.get("interaction_type", "combat"))
	if interaction_type == "chest":
		_handle_chest_resolution(success)
		return
	if interaction_type == "altar":
		_handle_altar_resolution(success, result)
		return
	_handle_combat_resolution(success, result)


func _handle_combat_resolution(success: bool, result: Dictionary) -> void:
	if _active_encounter == null:
		return
	if success:
		var attack_mode: String = String(result.get("attack_mode", "melee"))
		if attack_mode == "ranged":
			_fire_player_ranged_projectile(_active_encounter, int(result.get("damage", 0)))
			hud.show_message("Ranged script deployed.", 1.2)
		else:
			var defeated: bool = _active_encounter.apply_combat_result(result)
			if defeated:
				hud.show_message("Enemy defeated.", 1.2)
			else:
				hud.show_message("Hit confirmed. Enemy HP reduced.", 1.0)
		_active_encounter = null
		_refresh_enemy_counter()
		return
	var damage_to_player: int = int(result.get("damage_to_player", _player_damage_on_failure))
	var player_defeated: bool = player.apply_damage(damage_to_player)
	hud.show_message("Code failed. You took %d damage." % damage_to_player, 1.4)
	if not player_defeated:
		_active_encounter.reset_encounter()
	_active_encounter = null


func _fire_player_ranged_projectile(encounter: EnemyEncounter, damage: int) -> void:
	if encounter == null or encounter.is_defeated():
		return
	var projectile := COMBAT_PROJECTILE_SCRIPT.new() as EnemyProjectile
	if projectile == null:
		return
	var start_position := player.global_position + Vector2(0.0, -10.0)
	var target_vector: Vector2 = encounter.global_position - start_position
	if target_vector.is_zero_approx():
		target_vector = Vector2.RIGHT
	projectile.configure(start_position, target_vector.normalized(), damage, PLAYER_RANGED_PROJECTILE_SPEED, "enemy", Color(0.588235, 0.847059, 1.0, 1))
	projectile.target_hit.connect(_on_player_projectile_hit)
	projectile.projectile_expired.connect(_on_player_projectile_expired)
	add_child(projectile)
	_player_projectiles.append(projectile)


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


func _handle_chest_resolution(success: bool) -> void:
	if _active_chest == null:
		return
	if success:
		_active_chest.mark_opened()
	else:
		_active_chest.reset_interaction()
	_active_chest = null


func _handle_altar_resolution(success: bool, result: Dictionary) -> void:
	if _active_altar == null:
		return
	if success:
		_active_altar.mark_forged(String(result.get("weapon_summary", "Forged a standard glitch blade.")))
	else:
		_active_altar.reset_interaction()
	_active_altar = null


func _on_terminal_closed() -> void:
	get_tree().paused = false
	if _active_encounter != null:
		_active_encounter.reset_encounter()
		_active_encounter = null
	if _active_chest != null:
		_active_chest.reset_interaction()
		_active_chest = null
	if _active_altar != null:
		_active_altar.reset_interaction()
		_active_altar = null
	hud.show_message(_messages["encounter_cancelled"], 1.0)


func _on_player_health_changed(current_health: int, max_health: int) -> void:
	hud.update_health(current_health, max_health)


func _on_enemy_world_attack_feedback(message: String) -> void:
	if get_tree().paused or _level_completed:
		return
	hud.show_message(message, 0.9)


func _on_player_defeated() -> void:
	_level_completed = false
	hud.show_message(_messages["defeat"], 1.5)
	await get_tree().create_timer(1.5).timeout
	player.respawn()
	_clear_player_projectiles()
	_prepare_runtime_level_state()
	_active_encounter = null
	_active_chest = null
	_active_altar = null
	level_exit.set_unlocked(false)
	hud.show_message(_messages["respawn"], 1.2)


func _on_encounter_defeated(_encounter: EnemyEncounter) -> void:
	_active_encounter = null
	_refresh_enemy_counter()
	var all_cleared := true
	for encounter in _encounters:
		if not encounter.is_defeated():
			all_cleared = false
			break
	if all_cleared:
		level_exit.set_unlocked(true)
		hud.show_message(_messages["exit_unlocked"], 2.0)
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
	hud.show_message(_messages["level_complete"], 3.0)


func _on_chest_opened(_chest: ChestEncounter, reward_text: String) -> void:
	if _level_completed:
		return
	hud.show_message(reward_text, 2.0)


func _on_weapon_forged(_altar: AltarEncounter, weapon_summary: String) -> void:
	if _level_completed:
		return
	hud.show_message(weapon_summary, 2.2)
