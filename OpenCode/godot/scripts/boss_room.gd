extends Node2D

const PLAYER_RANGED_PROJECTILE_SPEED := 500.0
const PLAYER_MELEE_RANGE := 210.0
const PLAYER_MELEE_VERTICAL_TOLERANCE := 96.0
const PLAYER_MELEE_COMBO_DAMAGE := [28, 34, 42]
const PLAYER_RANGED_COMBO_DAMAGE := [16, 24, 36]
const PLAYER_MELEE_PREFERRED_RANGE := 110.0
const PLAYER_RANGED_PREFERRED_RANGE := 250.0
const PLAYER_COMBO_FOLLOWUP_DELAY := 0.25
const PLAYER_COMBO_FOLLOWUP_TOLERANCE := 0.25
const BOSS_DAMAGE_ON_FAILURE := 35
const ROOM_WIDTH := 1920
const ROOM_HEIGHT := 1080
const FLOOR_TOP_Y := 984.0
const PLAYER_HALF_HEIGHT := 24.0
const BOSS_HALF_HEIGHT := 75.0
const COMBAT_PROJECTILE_SCRIPT := preload("res://scripts/enemy_projectile.gd")
const PAUSE_MENU_SCENE := preload("res://scenes/ui/pause_menu.tscn")
const INVENTORY_MENU_SCENE := preload("res://scenes/ui/inventory_menu.tscn")

signal dialogue_sequence_finished

@export_file("*.json") var level_config_path := "res://data/levels/level_01.json"

@onready var terminal: CanvasLayer = $CombatTerminal
@onready var player: PlayerController = $Player
@onready var hud: GameHud = $Hud
@onready var boss: BossEncounter = $BossEncounter
@onready var backdrop: ColorRect = $Backdrop
@onready var mist_band: ColorRect = $MistBand
@onready var floor_visual: ColorRect = $Floor/Visual
@onready var ceiling_visual: ColorRect = $Ceiling/Visual
@onready var left_wall_visual: ColorRect = $LeftWall/Visual
@onready var right_wall_visual: ColorRect = $RightWall/Visual
@onready var platform_a_shape: CollisionShape2D = $PlatformA/CollisionShape2D
@onready var platform_a_visual: ColorRect = $PlatformA/Visual
@onready var platform_b_shape: CollisionShape2D = $PlatformB/CollisionShape2D
@onready var platform_b_visual: ColorRect = $PlatformB/Visual
@onready var platform_c_shape: CollisionShape2D = $PlatformC/CollisionShape2D
@onready var platform_c_visual: ColorRect = $PlatformC/Visual
@onready var platform_d_shape: CollisionShape2D = $PlatformD/CollisionShape2D
@onready var platform_d_visual: ColorRect = $PlatformD/Visual
@onready var platform_e_shape: CollisionShape2D = $PlatformE/CollisionShape2D
@onready var platform_e_visual: ColorRect = $PlatformE/Visual
@onready var player_collision_shape: CollisionShape2D = $Player/CollisionShape2D
@onready var boss_collision_shape: CollisionShape2D = $BossEncounter/CollisionShape2D
@onready var camera: Camera2D = $Player/Camera2D
@onready var cutscene_camera: Camera2D = $CutsceneCamera
@onready var dialogue_box: BossDialogueBox = $BossDialogueBox
@onready var legacy_dialogue_layer: CanvasLayer = $DialogueLayer
@onready var dialogue_panel: PanelContainer = $DialogueLayer/Panel
@onready var dialogue_name_label: Label = $DialogueLayer/Panel/NamePlate/NameLabel
@onready var dialogue_body_label: Label = $DialogueLayer/Panel/Margin/VBox/BodyLabel
@onready var dialogue_prompt_label: Label = $DialogueLayer/Panel/Margin/VBox/Actions/PromptLabel
@onready var dialogue_next_button: Button = $DialogueLayer/Panel/Margin/VBox/Actions/NextButton
@onready var dialogue_portrait: ColorRect = $DialogueLayer/Panel/PortraitFrame/PortraitMargin/Portrait
@onready var fade_rect: ColorRect = $FadeLayer/FadeRect

var _boss_arena_spawn := Vector2(280.0, 960.0)
var _boss_fight_active := false
var _rewrite_dialogue_shown := false
var _victory_dialogue_shown := false
var _player_combo_in_progress := false
var _player_combo_step := 0
var _player_combo_mode := ""
var _player_combo_window_open := 0.0
var _player_combo_window_close := 0.0
var _player_projectiles: Array[EnemyProjectile] = []
var _dialogue_active := false
var _dialogue_entries: Array[Dictionary] = []
var _dialogue_index := -1
var _terminal_reopen_lock_until := 0
var _player_dialogue_color := Color(0.701961, 0.768627, 0.980392, 1.0)
var _boss_dialogue_color := Color(0.796078, 0.54902, 0.894118, 1.0)
var _intro_terminal_offer_open := false
var _runtime_dialogue_body: RichTextLabel = null
var _fade_tween: Tween = null
var _outro_fade_started := false
var _level_id := "level_01"
var _pause_menu: CanvasLayer = null
var _inventory_menu: CanvasLayer = null
var _base_player_move_speed := 260.0
var _base_player_parry_window := 0.22
var _player_melee_damage_bonus := 0
var _player_ranged_damage_bonus := 0
var _player_failure_damage_reduction := 0
var _messages := {
	"intro": "Boss chamber reached. Reprogram and defeat the Threshold Warden.",
	"defeat": "Knight integrity lost. Respawning...",
	"respawn": "Respawn complete.",
	"boss_defeated": "Threshold Warden collapsed.",
	"level_complete": "Boss defeated. Variables secured."
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if not GameState.pending_level_path.is_empty():
		level_config_path = GameState.pending_level_path
	_apply_boss_config(_load_level_config())
	_hide_legacy_dialogue_layer()
	dialogue_box.hide_box()
	dialogue_box.visible = false
	terminal.hide_terminal()
	_configure_dialogue_layer()
	_ensure_runtime_dialogue_body()
	_configure_fade_layer()
	_ensure_overlay_menus()

	terminal.interaction_resolved.connect(_on_interaction_resolved)
	terminal.terminal_closed.connect(_on_terminal_closed)
	dialogue_box.next_pressed.connect(_advance_dialogue)
	player.health_changed.connect(_on_player_health_changed)
	player.defeated.connect(_on_player_defeated)
	player.combat_action_requested.connect(_on_player_combat_action_requested)
	boss.boss_defeated.connect(_on_boss_defeated)
	boss.boss_feedback.connect(_on_boss_feedback)

	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = ROOM_WIDTH
	camera.limit_bottom = ROOM_HEIGHT
	cutscene_camera.limit_left = 0
	cutscene_camera.limit_top = 0
	cutscene_camera.limit_right = ROOM_WIDTH
	cutscene_camera.limit_bottom = ROOM_HEIGHT

	hud.set_room_context("")
	hud.set_objective("")
	hud.set_lesson_progress("")
	_base_player_move_speed = player.move_speed
	_base_player_parry_window = player.parry_window
	hud.update_health(player.current_health, player.max_health)
	hud.update_enemy_counter(1, 1)
	hud.set_boss_status(_opening_status_text())

	boss.activate_boss()
	_snap_combatants_to_floor()
	call_deferred("_run_boss_room_intro_sequence")


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_ESCAPE and not _dialogue_active and not terminal.visible:
				_toggle_pause_menu()
				get_viewport().set_input_as_handled()
				return
			if key_event.keycode == KEY_I and not _dialogue_active and not terminal.visible:
				_toggle_inventory_menu()
				get_viewport().set_input_as_handled()
				return
	if not _dialogue_active:
		return
	if event.is_action_pressed("attack_primary") or event.is_action_pressed("jump") or event.is_action_pressed("interact"):
		get_viewport().set_input_as_handled()
		_advance_dialogue()


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


func _load_level_config() -> Dictionary:
	if not FileAccess.file_exists(level_config_path):
		return {}
	var file := FileAccess.open(level_config_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed


func _apply_boss_config(config: Dictionary) -> void:
	if config.is_empty():
		return
	_level_id = String(config.get("id", _level_id))
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
	_apply_boss_environment(boss_config)
	var arena_spawn_data: Array = boss_config.get("arena_spawn", [])
	if arena_spawn_data.size() == 2:
		_boss_arena_spawn = Vector2(float(arena_spawn_data[0]), float(arena_spawn_data[1]))


func _apply_boss_environment(boss_config: Dictionary) -> void:
	var environment_variant: Variant = boss_config.get("environment", {})
	if typeof(environment_variant) != TYPE_DICTIONARY:
		_apply_boss_arena_layout(boss_config, {})
		return
	var environment_config: Dictionary = environment_variant
	backdrop.color = _color_from_variant(environment_config.get("backdrop_color", []), backdrop.color)
	mist_band.color = _color_from_variant(environment_config.get("mist_color", []), mist_band.color)
	floor_visual.color = _color_from_variant(environment_config.get("floor_color", []), floor_visual.color)
	ceiling_visual.color = _color_from_variant(environment_config.get("ceiling_color", []), ceiling_visual.color)
	left_wall_visual.color = _color_from_variant(environment_config.get("wall_color", []), left_wall_visual.color)
	right_wall_visual.color = left_wall_visual.color
	var platform_color: Color = _color_from_variant(environment_config.get("platform_color", []), platform_a_visual.color)
	platform_a_visual.color = platform_color
	platform_b_visual.color = platform_color
	platform_c_visual.color = platform_color
	platform_d_visual.color = platform_color
	platform_e_visual.color = platform_color
	_apply_boss_arena_layout(boss_config, environment_config)


func _color_from_variant(color_variant: Variant, fallback: Color) -> Color:
	if typeof(color_variant) != TYPE_ARRAY:
		return fallback
	var color_array: Array = color_variant
	if color_array.size() < 4:
		return fallback
	return Color(float(color_array[0]), float(color_array[1]), float(color_array[2]), float(color_array[3]))


func _apply_boss_arena_layout(boss_config: Dictionary, _environment_config: Dictionary) -> void:
	var layout_variant: Variant = boss_config.get("arena_layout", {})
	var layout_config: Dictionary = {}
	if typeof(layout_variant) == TYPE_DICTIONARY:
		layout_config = layout_variant
	if layout_config.is_empty():
		layout_config = _default_arena_layout_for_mechanic(String(boss_config.get("mechanic_type", "threshold_warden")))
	var mist_top: float = float(layout_config.get("mist_top", mist_band.offset_top))
	var mist_bottom: float = float(layout_config.get("mist_bottom", mist_band.offset_bottom))
	mist_band.offset_top = mist_top
	mist_band.offset_bottom = mist_bottom
	var mist_alpha: float = float(layout_config.get("mist_alpha", mist_band.color.a))
	mist_band.color = Color(mist_band.color.r, mist_band.color.g, mist_band.color.b, mist_alpha)
	var platform_entries_variant: Variant = layout_config.get("platforms", [])
	if typeof(platform_entries_variant) != TYPE_ARRAY:
		return
	var platform_entries: Array = platform_entries_variant
	var shapes: Array[CollisionShape2D] = [platform_a_shape, platform_b_shape, platform_c_shape, platform_d_shape, platform_e_shape]
	var visuals: Array[ColorRect] = [platform_a_visual, platform_b_visual, platform_c_visual, platform_d_visual, platform_e_visual]
	for index in range(min(platform_entries.size(), shapes.size())):
		var entry_variant: Variant = platform_entries[index]
		if typeof(entry_variant) != TYPE_DICTIONARY:
			continue
		_apply_platform_entry(shapes[index], visuals[index], entry_variant as Dictionary)


func _apply_platform_entry(shape_node: CollisionShape2D, visual_node: ColorRect, entry: Dictionary) -> void:
	var is_visible: bool = bool(entry.get("visible", true))
	shape_node.disabled = not is_visible
	visual_node.visible = is_visible
	if not is_visible:
		return
	var platform_width: float = float(entry.get("width", 220.0))
	var platform_height: float = float(entry.get("height", 28.0))
	var platform_x: float = float(entry.get("x", 960.0))
	var platform_y: float = float(entry.get("y", 640.0))
	if shape_node.shape is RectangleShape2D:
		(shape_node.shape as RectangleShape2D).size = Vector2(platform_width, platform_height)
	shape_node.position = Vector2(platform_x, platform_y)
	visual_node.offset_left = platform_x - platform_width * 0.5
	visual_node.offset_top = platform_y - platform_height * 0.5
	visual_node.offset_right = platform_x + platform_width * 0.5
	visual_node.offset_bottom = platform_y + platform_height * 0.5


func _default_arena_layout_for_mechanic(mechanic_type: String) -> Dictionary:
	match mechanic_type:
		"logic_spider":
			return {
				"mist_top": 120.0,
				"mist_bottom": 910.0,
				"mist_alpha": 0.18,
				"platforms": [
					{"x": 280.0, "y": 860.0, "width": 220.0},
					{"x": 560.0, "y": 620.0, "width": 170.0},
					{"x": 960.0, "y": 710.0, "width": 290.0},
					{"x": 1360.0, "y": 620.0, "width": 170.0},
					{"x": 1640.0, "y": 860.0, "width": 220.0}
				]
			}
		"assembly_golem":
			return {
				"mist_top": 154.0,
				"mist_bottom": 928.0,
				"mist_alpha": 0.16,
				"platforms": [
					{"x": 250.0, "y": 892.0, "width": 210.0},
					{"x": 560.0, "y": 760.0, "width": 180.0},
					{"x": 960.0, "y": 640.0, "width": 220.0},
					{"x": 1360.0, "y": 760.0, "width": 180.0},
					{"x": 1670.0, "y": 892.0, "width": 210.0}
				]
			}
		"archivist":
			return {
				"mist_top": 110.0,
				"mist_bottom": 900.0,
				"mist_alpha": 0.12,
				"platforms": [
					{"x": 300.0, "y": 850.0, "width": 250.0},
					{"x": 680.0, "y": 640.0, "width": 230.0},
					{"x": 960.0, "y": 500.0, "width": 320.0},
					{"x": 1240.0, "y": 640.0, "width": 230.0},
					{"x": 1620.0, "y": 850.0, "width": 250.0}
				]
			}
		"system_admin":
			return {
				"mist_top": 96.0,
				"mist_bottom": 930.0,
				"mist_alpha": 0.17,
				"platforms": [
					{"x": 250.0, "y": 880.0, "width": 210.0},
					{"x": 620.0, "y": 690.0, "width": 210.0},
					{"x": 960.0, "y": 520.0, "width": 260.0},
					{"x": 1300.0, "y": 690.0, "width": 210.0},
					{"x": 1670.0, "y": 880.0, "width": 210.0}
				]
			}
		_:
			return {
				"mist_top": 138.0,
				"mist_bottom": 930.0,
				"mist_alpha": 0.14,
				"platforms": [
					{"x": 300.0, "y": 848.0, "width": 230.0},
					{"x": 630.0, "y": 720.0, "width": 210.0},
					{"x": 960.0, "y": 582.0, "width": 260.0},
					{"x": 1290.0, "y": 720.0, "width": 210.0},
					{"x": 1620.0, "y": 848.0, "width": 230.0}
				]
			}


func _hide_legacy_dialogue_layer() -> void:
	if is_instance_valid(legacy_dialogue_layer):
		legacy_dialogue_layer.visible = false


func _configure_dialogue_layer() -> void:
	if is_instance_valid(legacy_dialogue_layer):
		legacy_dialogue_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		legacy_dialogue_layer.visible = false


func _ensure_runtime_dialogue_body() -> void:
	_runtime_dialogue_body = null


func _configure_fade_layer() -> void:
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 1)


func _run_boss_room_intro_sequence() -> void:
	await _fade_from_black(0.8)
	_start_intro_cutscene()


func _on_interaction_resolved(success: bool, result: Dictionary) -> void:
	get_tree().paused = false
	hud.set_terminal_overlay_mode(false)
	if String(result.get("interaction_type", "")) != "boss":
		return
	_handle_boss_resolution(success, result)


func _handle_boss_resolution(success: bool, result: Dictionary) -> void:
	player.set_terminal_locked(false)
	if success:
		_apply_runtime_solution_effects(result)
		boss.refresh_strategy()
		if _boss_fight_active:
			boss.resume_after_terminal(true)
			hud.set_boss_status(_active_status_text())
			hud.show_message("Strategy updated. Press Q to keep attacking.", 1.2)
		else:
			_intro_terminal_offer_open = false
			boss.resume_after_terminal(false)
			hud.set_boss_status("Tactic ready. Press Q to engage.")
			hud.show_message("Tactic deployed. Press Q to start the fight.", 1.3)
		return

	var damage_to_player: int = int(result.get("damage_to_player", BOSS_DAMAGE_ON_FAILURE))
	damage_to_player = maxi(damage_to_player - _player_failure_damage_reduction, 0)
	var player_defeated: bool = player.apply_damage(damage_to_player)
	if _boss_fight_active:
		boss.resume_after_terminal(true)
	else:
		_intro_terminal_offer_open = false
		boss.resume_after_terminal(false)
	if not player_defeated:
		if _boss_fight_active:
			hud.set_boss_status(_active_status_text())
			hud.show_message("Boss strike: %d damage." % damage_to_player, 1.4)
		else:
			hud.set_boss_status("No tactic locked. Press Q to engage.")
			hud.show_message("You can still fight without a tactic, but it will be harsher.", 1.6)
	if _boss_fight_active and not _rewrite_dialogue_shown and not boss.is_defeated():
		_rewrite_dialogue_shown = true
		_play_dialogue_sequence(["rewrite_boss", "rewrite_player"])


func _open_boss_terminal(is_reprogramming: bool) -> void:
	if boss.is_defeated() or _dialogue_active:
		return
	get_tree().paused = true
	hud.set_terminal_overlay_mode(true)
	_reset_player_combo_state()
	player.set_terminal_locked(true)
	player.velocity = Vector2.ZERO
	_clear_player_projectiles()
	boss.pause_for_terminal()
	hud.show_message("", 0.0)
	hud.set_boss_status("")
	if not is_reprogramming:
		_intro_terminal_offer_open = true
	terminal.open_terminal(boss.build_terminal_payload(is_reprogramming))


func _on_terminal_closed() -> void:
	get_tree().paused = false
	hud.set_terminal_overlay_mode(false)
	_reset_player_combo_state()
	player.set_terminal_locked(false)
	_terminal_reopen_lock_until = Time.get_ticks_msec() + 250

	if boss.is_defeated():
		return

	if _boss_fight_active:
		boss.resume_after_terminal(true)
	else:
		_intro_terminal_offer_open = false
		boss.resume_after_terminal(false)
		hud.set_boss_status("Press Q to engage or reopen strategy later.")
		hud.show_message("Fight not started. Press Q when you are ready.", 1.4)

	if _boss_fight_active:
		hud.set_boss_status(_active_status_text())
		hud.show_message("", 0.0)


func _on_player_health_changed(current_health: int, max_health: int) -> void:
	hud.update_health(current_health, max_health)


func _on_player_defeated() -> void:
	get_tree().paused = false
	hud.set_terminal_overlay_mode(false)
	player.set_terminal_locked(false)
	hud.show_message(_messages["defeat"], 1.5)
	await get_tree().create_timer(1.5).timeout
	player.respawn()
	_reset_runtime_solution_effects()
	player.velocity = Vector2.ZERO
	_clear_player_projectiles()
	terminal.hide_terminal()
	_hide_runtime_dialogue()
	boss.reset_boss()
	boss.activate_boss()
	_snap_combatants_to_floor()
	_boss_fight_active = false
	_rewrite_dialogue_shown = false
	_victory_dialogue_shown = false
	_dialogue_active = false
	_intro_terminal_offer_open = false
	_outro_fade_started = false
	hud.update_enemy_counter(1, 1)
	hud.set_boss_status(_opening_status_text())
	call_deferred("_run_boss_room_intro_sequence")


func _on_boss_defeated() -> void:
	get_tree().paused = false
	terminal.hide_terminal()
	_boss_fight_active = false
	_clear_player_projectiles()
	_reset_player_combo_state()
	GameState.mark_boss_completed(_level_id)
	hud.set_boss_status("Boss defeated.")
	hud.update_enemy_counter(0, 1)
	hud.show_message(_messages["level_complete"], 3.0)
	if not _victory_dialogue_shown:
		_victory_dialogue_shown = true
		_play_dialogue_sequence(["defeat_boss", "defeat_player"])


func _on_boss_feedback(message: String) -> void:
	if get_tree().paused or _dialogue_active:
		return
	hud.show_message(message, 1.0)


func _opening_status_text() -> String:
	var mechanic_summary: String = boss.get_mechanic_summary()
	if mechanic_summary.is_empty():
		return "Planning opening tactic..."
	return "Planning tactic: %s" % mechanic_summary


func _active_status_text() -> String:
	var boss_brief: String = boss.get_boss_brief()
	if boss_brief.is_empty():
		if boss.is_strategy_refresh_required():
			return "Boss overdrive active. Press Q to reprogram."
		return "Boss fight active. Attack with Q."
	if boss.is_strategy_refresh_required():
		return "%s Strategy stale. Press Q to rewrite." % boss_brief
	return "%s Attack with Q." % boss_brief


func _on_player_combat_action_requested(facing_direction: Vector2) -> void:
	if get_tree().paused or _dialogue_active or boss.is_defeated() or _player_combo_in_progress:
		return
	if Time.get_ticks_msec() < _terminal_reopen_lock_until:
		return
	if _should_use_q_for_boss_parry():
		player.request_parry()
		return
	if boss.is_strategy_refresh_required():
		_open_boss_terminal(true)
		return
	if not _boss_fight_active:
		_intro_terminal_offer_open = false
		_boss_fight_active = true
		boss.start_battle()
		hud.set_boss_status(_active_status_text())
	var now_seconds: float = Time.get_ticks_msec() / 1000.0
	if _player_combo_step > 0 and now_seconds < _player_combo_window_open:
		hud.show_message("Continue the combo a little later.", 0.8)
		return
	if _player_combo_step > 0 and now_seconds > _player_combo_window_close:
		_reset_player_combo_state()
	var target_direction: Vector2 = _combat_direction_to_boss(facing_direction)
	_execute_player_combo(target_direction)


func _execute_player_combo(facing_direction: Vector2) -> void:
	_player_combo_in_progress = true
	if _player_combo_step == 0 or _player_combo_mode.is_empty():
		_player_combo_mode = _choose_combo_mode()
	match _player_combo_step:
		1:
			_apply_player_combo_step(_player_combo_mode, 1, facing_direction)
		2:
			_apply_player_combo_step(_player_combo_mode, 2, facing_direction)
			_reset_player_combo_state()
		_:
			_apply_player_combo_step(_player_combo_mode, 0, facing_direction)
			_player_combo_step = 1
			_set_player_combo_window()
	_player_combo_in_progress = false


func _apply_player_combo_step(combo_mode: String, combo_index: int, facing_direction: Vector2) -> void:
	var motion_name: String = _motion_name_for_combo(combo_mode, combo_index)
	player.perform_combat_motion(motion_name, facing_direction, boss.global_position)
	if combo_mode == "ranged":
		var ranged_damage: int = PLAYER_RANGED_COMBO_DAMAGE[min(combo_index, PLAYER_RANGED_COMBO_DAMAGE.size() - 1)] + _player_ranged_damage_bonus
		_fire_player_ranged_volley(ranged_damage, combo_index + 1)
		hud.show_message(_combo_step_message(combo_mode, combo_index), 0.8)
	else:
		if not _can_player_melee_boss():
			hud.show_message("Boss slipped out of melee range.", 0.8)
			_reset_player_combo_state()
			return
		var melee_damage: int = PLAYER_MELEE_COMBO_DAMAGE[min(combo_index, PLAYER_MELEE_COMBO_DAMAGE.size() - 1)] + _player_melee_damage_bonus
		var defeated: bool = boss.apply_combat_result({"damage": melee_damage})
		hud.show_message(_combo_step_message(combo_mode, combo_index), 0.8)
		if defeated:
			_reset_player_combo_state()
			return
	_register_strategy_pressure()
	if combo_index < 2 and not boss.is_strategy_refresh_required():
		_player_combo_step = combo_index + 1
		_set_player_combo_window()
	else:
		_reset_player_combo_state()


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
				return "Boss combo: double volley fired."
			2:
				return "Boss combo: triple volley fired."
			_:
				return "Boss combo: opening shot fired."
	match combo_index:
		1:
			return "Boss combo: second strike landed."
		2:
			return "Boss combo: finisher landed."
		_:
			return "Boss combo: opening strike landed."


func _choose_combo_mode() -> String:
	var distance: float = player.global_position.distance_to(boss.global_position)
	if distance <= PLAYER_MELEE_PREFERRED_RANGE:
		return "melee"
	if distance >= PLAYER_RANGED_PREFERRED_RANGE:
		return "ranged"
	var melee_gap: float = absf(distance - PLAYER_MELEE_PREFERRED_RANGE)
	var ranged_gap: float = absf(distance - PLAYER_RANGED_PREFERRED_RANGE)
	return "ranged" if ranged_gap < melee_gap else "melee"


func _can_player_melee_boss() -> bool:
	if boss.is_defeated():
		return false
	var offset: Vector2 = boss.global_position - player.global_position
	if absf(offset.y) > PLAYER_MELEE_VERTICAL_TOLERANCE:
		return false
	if absf(offset.x) > PLAYER_MELEE_RANGE:
		return false
	return true


func _combat_direction_to_boss(fallback_direction: Vector2) -> Vector2:
	var offset_x: float = boss.global_position.x - player.global_position.x
	if not is_zero_approx(offset_x):
		return Vector2(signf(offset_x), 0.0)
	return fallback_direction if not fallback_direction.is_zero_approx() else Vector2.RIGHT


func _fire_player_ranged_volley(total_damage: int, projectile_count: int) -> void:
	var safe_count: int = maxi(projectile_count, 1)
	var damage_per_projectile: int = maxi(int(ceil(float(total_damage) / float(safe_count))), 1)
	var spread_step: float = 0.08
	var first_offset: float = -float(safe_count - 1) * 0.5 * spread_step
	for index in range(safe_count):
		var angle_offset: float = first_offset + float(index) * spread_step
		_fire_player_ranged_projectile(damage_per_projectile, angle_offset)


func _fire_player_ranged_projectile(damage: int, angle_offset: float = 0.0) -> void:
	if boss.is_defeated():
		return
	var projectile := COMBAT_PROJECTILE_SCRIPT.new() as EnemyProjectile
	if projectile == null:
		return
	var start_position := player.global_position + Vector2(0.0, -10.0)
	var target_vector: Vector2 = boss.global_position - start_position
	if target_vector.is_zero_approx():
		target_vector = Vector2.RIGHT
	var projectile_direction: Vector2 = target_vector.normalized().rotated(angle_offset)
	projectile.configure(start_position, projectile_direction, damage, PLAYER_RANGED_PROJECTILE_SPEED, "enemy", Color(0.588235, 0.847059, 1.0, 1.0))
	projectile.target_hit.connect(_on_player_projectile_hit)
	projectile.projectile_expired.connect(_on_player_projectile_expired)
	add_child(projectile)
	_player_projectiles.append(projectile)


func _on_player_projectile_hit(projectile: EnemyProjectile, target: Node, damage: int) -> void:
	_player_projectiles.erase(projectile)
	if target is BossEncounter:
		var defeated: bool = (target as BossEncounter).apply_combat_result({"damage": damage})
		hud.show_message("Ranged hit confirmed.", 0.9)
		if defeated:
			_reset_player_combo_state()


func _on_player_projectile_expired(projectile: EnemyProjectile) -> void:
	_player_projectiles.erase(projectile)


func _clear_player_projectiles() -> void:
	for projectile in _player_projectiles:
		if is_instance_valid(projectile):
			projectile.queue_free()
	_player_projectiles.clear()


func _register_strategy_pressure() -> void:
	if boss.register_player_attack():
		_reset_player_combo_state()
		hud.set_boss_status(_active_status_text())
		hud.show_message("Strategy stale. Press Q to rewrite before the boss accelerates.", 1.6)
	else:
		hud.set_boss_status(_active_status_text())


func _reset_player_combo_state() -> void:
	_player_combo_step = 0
	_player_combo_mode = ""
	_player_combo_window_open = 0.0
	_player_combo_window_close = 0.0


func _apply_runtime_solution_effects(result: Dictionary) -> void:
	var runtime_effects_variant: Variant = result.get("resolved_effects", {})
	if typeof(runtime_effects_variant) != TYPE_DICTIONARY:
		return
	var runtime_effects: Dictionary = runtime_effects_variant
	var player_effects_variant: Variant = runtime_effects.get("player", {})
	var boss_effects_variant: Variant = runtime_effects.get("target", {})
	var player_effects: Dictionary = player_effects_variant if typeof(player_effects_variant) == TYPE_DICTIONARY else {}
	var boss_effects: Dictionary = boss_effects_variant if typeof(boss_effects_variant) == TYPE_DICTIONARY else {}
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
	if typeof(boss_effects_variant) == TYPE_DICTIONARY and not boss_effects.is_empty():
		boss.apply_terminal_effects(boss_effects)
	_show_runtime_effect_summary(runtime_effects)


func _show_runtime_effect_summary(runtime_effects: Dictionary) -> void:
	var summary_variant: Variant = runtime_effects.get("summary", [])
	if typeof(summary_variant) != TYPE_ARRAY:
		return
	var summary_items: Array = summary_variant
	var parts: PackedStringArray = []
	for item_variant in summary_items:
		var item_text: String = String(item_variant).strip_edges()
		if not item_text.is_empty():
			parts.append(item_text)
	if parts.is_empty():
		return
	hud.show_message("Runtime effects: %s." % ", ".join(parts), 2.0)


func _reset_runtime_solution_effects() -> void:
	player.move_speed = _base_player_move_speed
	player.parry_window = _base_player_parry_window
	_player_melee_damage_bonus = 0
	_player_ranged_damage_bonus = 0
	_player_failure_damage_reduction = 0


func _set_player_combo_window() -> void:
	var now_seconds: float = Time.get_ticks_msec() / 1000.0
	_player_combo_window_open = now_seconds + PLAYER_COMBO_FOLLOWUP_DELAY - PLAYER_COMBO_FOLLOWUP_TOLERANCE
	_player_combo_window_close = now_seconds + PLAYER_COMBO_FOLLOWUP_DELAY + PLAYER_COMBO_FOLLOWUP_TOLERANCE


func _start_intro_cutscene() -> void:
	terminal.hide_terminal()
	_intro_terminal_offer_open = false
	_play_dialogue_sequence(["intro_boss", "intro_player"])


func _play_dialogue_sequence(keys: Array[String]) -> void:
	_dialogue_entries.clear()
	for key in keys:
		var line: String = boss.get_dialogue_line(key)
		if line.is_empty():
			continue
		var speaker := "Skill Issue"
		var focus_target: Node2D = player
		if key.ends_with("_boss"):
			speaker = boss.boss_name
			focus_target = boss
		_dialogue_entries.append(
			{
				"speaker": speaker,
				"text": line,
				"focus_target": focus_target
			}
		)
	if _dialogue_entries.is_empty():
		_dialogue_entries = [
			{
				"speaker": boss.boss_name,
				"text": "State your tactic.",
				"focus_target": boss
			},
			{
				"speaker": "Skill Issue",
				"text": "Then watch it change.",
				"focus_target": player
			}
		]
	_begin_dialogue_mode()
	_dialogue_index = -1
	_advance_dialogue()


func _begin_dialogue_mode() -> void:
	_dialogue_active = true
	terminal.hide_terminal()
	get_tree().paused = false
	_reset_player_combo_state()
	player.set_terminal_locked(true)
	player.velocity = Vector2.ZERO
	boss.pause_for_terminal()
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	cutscene_camera.enabled = true
	cutscene_camera.make_current()
	dialogue_box.visible = true


func _advance_dialogue() -> void:
	if not _dialogue_active:
		return
	_dialogue_index += 1
	if _dialogue_index >= _dialogue_entries.size():
		_end_dialogue_mode()
		return
	var entry: Dictionary = _dialogue_entries[_dialogue_index]
	var speaker: String = String(entry.get("speaker", ""))
	var text: String = String(entry.get("text", "")).strip_edges()
	if text.is_empty():
		text = "..."
	_show_runtime_dialogue_line(speaker, text, _portrait_color_for_entry(entry))
	_focus_cutscene_camera(entry.get("focus_target", player) as Node2D)


func _end_dialogue_mode() -> void:
	_dialogue_active = false
	_dialogue_entries.clear()
	_dialogue_index = -1
	_hide_runtime_dialogue()
	player.set_terminal_locked(false)
	player.set_process_input(true)
	player.set_process_unhandled_input(true)
	camera.make_current()
	cutscene_camera.enabled = false
	_snap_combatants_to_floor()
	if boss.is_defeated():
		hud.set_boss_status("Boss defeated.")
		if not _outro_fade_started:
			_outro_fade_started = true
			call_deferred("_play_room_outro_fade")
	else:
		boss.resume_after_terminal(false)
		_boss_fight_active = false
		_intro_terminal_offer_open = true
		hud.set_boss_status(_opening_status_text())
		_open_boss_terminal(false)
	dialogue_sequence_finished.emit()


func _focus_cutscene_camera(target: Node2D) -> void:
	if target == null or not is_instance_valid(target):
		return
	var target_position := target.global_position
	target_position += Vector2(0.0, -120.0 if target == player else -150.0)
	var tween := create_tween()
	tween.tween_property(cutscene_camera, "global_position", target_position, 0.28)


func _portrait_color_for_entry(entry: Dictionary) -> Color:
	var focus_target := entry.get("focus_target", player) as Node2D
	return _boss_dialogue_color if focus_target == boss else _player_dialogue_color


func _show_runtime_dialogue_line(speaker: String, text: String, portrait_color: Color) -> void:
	dialogue_box.show_line(speaker, text, portrait_color)


func _hide_runtime_dialogue() -> void:
	dialogue_box.hide_box()


func _should_use_q_for_boss_parry() -> bool:
	return boss.can_accept_q_parry()


func _snap_combatants_to_floor() -> void:
	var player_half_height := PLAYER_HALF_HEIGHT
	if is_instance_valid(player_collision_shape) and player_collision_shape.shape is RectangleShape2D:
		player_half_height = (player_collision_shape.shape as RectangleShape2D).size.y * 0.5
	var boss_half_height := BOSS_HALF_HEIGHT
	if is_instance_valid(boss_collision_shape) and boss_collision_shape.shape is RectangleShape2D:
		boss_half_height = (boss_collision_shape.shape as RectangleShape2D).size.y * 0.5
	player.global_position = Vector2(_boss_arena_spawn.x, FLOOR_TOP_Y - player_half_height - 2.0)
	boss.global_position = Vector2(boss.global_position.x, FLOOR_TOP_Y - boss_half_height - 2.0)
	player.velocity = Vector2.ZERO
	boss.velocity = Vector2.ZERO
	player.apply_floor_snap()
	boss.apply_floor_snap()


func _fade_from_black(duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 1)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", 0.0, duration)
	await _fade_tween.finished
	fade_rect.visible = false


func _play_room_outro_fade() -> void:
	await get_tree().create_timer(0.25).timeout
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 0)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", 1.0, 0.95)
	await _fade_tween.finished
	GameState.go_to_main_menu()
