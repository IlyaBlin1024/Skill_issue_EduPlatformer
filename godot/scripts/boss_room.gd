extends Node2D

const LEVEL_CONFIG_PATH := "res://data/levels/level_01.json"
const BOSS_DAMAGE_ON_FAILURE := 35
const ROOM_WIDTH := 1920
const ROOM_HEIGHT := 1080

@onready var terminal: CanvasLayer = $CombatTerminal
@onready var player: PlayerController = $Player
@onready var hud: GameHud = $Hud
@onready var boss: BossEncounter = $BossEncounter
@onready var camera: Camera2D = $Player/Camera2D

var _boss_arena_spawn := Vector2(280, 820)
var _boss_fight_active := false
var _messages := {
	"intro": "Boss chamber reached. Reprogram and defeat the Threshold Warden.",
	"defeat": "Knight integrity lost. Respawning...",
	"respawn": "Respawn complete.",
	"boss_defeated": "Threshold Warden collapsed.",
	"level_complete": "Boss defeated. Variables secured."
}


func _ready() -> void:
	_apply_boss_config(_load_level_config())
	terminal.interaction_resolved.connect(_on_interaction_resolved)
	terminal.terminal_closed.connect(_on_terminal_closed)
	player.health_changed.connect(_on_player_health_changed)
	player.defeated.connect(_on_player_defeated)
	boss.boss_defeated.connect(_on_boss_defeated)
	boss.boss_feedback.connect(_on_boss_feedback)

	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ROOM_WIDTH
	camera.limit_bottom = ROOM_HEIGHT
	hud.update_health(player.current_health, player.max_health)
	hud.update_enemy_counter(1, 1)
	hud.set_boss_status("Planning opening tactic...")
	player.global_position = _boss_arena_spawn
	player.velocity = Vector2.ZERO
	boss.activate_boss()
	hud.show_message(_messages["intro"], 2.0)
	_open_boss_terminal(false)


func _process(_delta: float) -> void:
	if _boss_fight_active and not get_tree().paused and not boss.is_defeated():
		if Input.is_action_just_pressed("interact"):
			_open_boss_terminal(true)


func _load_level_config() -> Dictionary:
	if not FileAccess.file_exists(LEVEL_CONFIG_PATH):
		return {}
	var file := FileAccess.open(LEVEL_CONFIG_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _apply_boss_config(config: Dictionary) -> void:
	if config.is_empty():
		return
	_messages["intro"] = String(config.get("boss_intro_message", _messages["intro"]))
	_messages["boss_defeated"] = String(config.get("boss_defeated_message", _messages["boss_defeated"]))
	_messages["level_complete"] = String(config.get("level_complete_message", _messages["level_complete"]))
	_messages["defeat"] = String(config.get("defeat_message", _messages["defeat"]))
	_messages["respawn"] = String(config.get("respawn_message", _messages["respawn"]))
	var boss_config_variant: Variant = config.get("boss", {})
	if typeof(boss_config_variant) != TYPE_DICTIONARY:
		return
	var boss_config: Dictionary = boss_config_variant
	boss.configure(boss_config)
	var arena_spawn_data: Array = boss_config.get("arena_spawn", [])
	if arena_spawn_data.size() == 2:
		_boss_arena_spawn = Vector2(float(arena_spawn_data[0]), float(arena_spawn_data[1]))


func _on_interaction_resolved(success: bool, result: Dictionary) -> void:
	get_tree().paused = false
	if String(result.get("interaction_type", "")) != "boss":
		return
	_handle_boss_resolution(success, result)


func _handle_boss_resolution(success: bool, result: Dictionary) -> void:
	if success:
		var defeated: bool = boss.apply_combat_result(result)
		if not _boss_fight_active:
			_boss_fight_active = true
			boss.start_battle()
			hud.set_boss_status("Boss fight active. Press E to reprogram.")
		if defeated:
			hud.set_boss_status("Boss defeated.")
			hud.update_enemy_counter(0, 1)
			hud.show_message(_messages["boss_defeated"], 2.5)
		else:
			hud.set_boss_status("Boss fight active. Press E to reprogram.")
			hud.show_message("Boss core damaged. Press E to reprogram.", 1.6)
		return
	var damage_to_player: int = int(result.get("damage_to_player", BOSS_DAMAGE_ON_FAILURE))
	var player_defeated: bool = player.apply_damage(damage_to_player)
	if not _boss_fight_active:
		_boss_fight_active = true
		boss.start_battle()
	hud.show_message("Boss strike: %d damage." % damage_to_player, 1.8)
	if not player_defeated:
		hud.set_boss_status("Boss fight active. Press E to reprogram.")


func _open_boss_terminal(is_reprogramming: bool) -> void:
	if boss.is_defeated():
		return
	get_tree().paused = true
	if is_reprogramming:
		hud.set_boss_status("Reprogramming tactic...")
	else:
		hud.set_boss_status("Planning opening tactic...")
	terminal.open_terminal(boss.build_terminal_payload(is_reprogramming))


func _on_terminal_closed() -> void:
	get_tree().paused = false
	if not boss.is_defeated() and _boss_fight_active:
		hud.set_boss_status("Boss fight active. Press E to reprogram.")
		hud.show_message("Boss terminal closed. Press E to reopen.", 1.4)
		return
	if not boss.is_defeated():
		hud.set_boss_status("Planning opening tactic...")


func _on_player_health_changed(current_health: int, max_health: int) -> void:
	hud.update_health(current_health, max_health)


func _on_player_defeated() -> void:
	hud.show_message(_messages["defeat"], 1.5)
	await get_tree().create_timer(1.5).timeout
	player.respawn()
	player.global_position = _boss_arena_spawn
	player.velocity = Vector2.ZERO
	boss.reset_boss()
	boss.activate_boss()
	_boss_fight_active = false
	hud.update_enemy_counter(1, 1)
	hud.set_boss_status("Planning opening tactic...")
	hud.show_message(_messages["respawn"], 1.2)
	_open_boss_terminal(false)


func _on_boss_defeated() -> void:
	_boss_fight_active = false
	hud.set_boss_status("Boss defeated.")
	hud.update_enemy_counter(0, 1)
	hud.show_message(_messages["level_complete"], 3.0)


func _on_boss_feedback(message: String) -> void:
	if get_tree().paused:
		return
	hud.show_message(message, 1.0)
