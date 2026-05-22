extends Node2D

signal terminal_step_finished
signal overlay_step_finished

const NEXT_SCENE_PATH := "res://scenes/main_menu.tscn"
const PROJECTILE_SCRIPT := preload("res://scripts/enemy_projectile.gd")
const TUTORIAL_ART_ROOT := "res://assets/production_art/levels/tutorial"

const ROOM_WIDTH := 1280.0
const ROOM_COUNT := 5
const FLOOR_TOP := 620.0
const FLOOR_HEIGHT := 100.0
const PLAYER_GROUND_Y := FLOOR_TOP - 24.0
const TUTORIAL_RANGED_PROJECTILE_SPEED := 520.0
const TUTORIAL_MELEE_DAMAGE := 140
const TUTORIAL_RANGED_DAMAGE := 140
const TUTORIAL_MELEE_RANGE := 210.0
const TUTORIAL_MELEE_PREFERRED_RANGE := 110.0
const TUTORIAL_RANGED_PREFERRED_RANGE := 250.0
const ROOM_FADE_OUT_DURATION := 0.5
const ROOM_FADE_IN_DURATION := 0.5
@onready var backdrop: ColorRect = $Backdrop
@onready var world: Node2D = $World
@onready var player: PlayerController = $Player
@onready var terminal = $CombatTerminal
@onready var hud: GameHud = $Hud
@onready var overlay: TutorialOverlay = $TutorialOverlay
@onready var fade_rect: ColorRect = $FadeLayer/FadeRect

var _fade_tween: Tween = null
var _melee_enemy: EnemyEncounter = null
var _ranged_enemy: EnemyEncounter = null
var _chest: ChestEncounter = null
var _altar: AltarEncounter = null
var _player_projectiles: Array[EnemyProjectile] = []
var _current_room := 0
var _current_combat_target: EnemyEncounter = null
var _terminal_result_ready := false
var _terminal_result_success := false
var _terminal_result_payload: Dictionary = {}
var _terminal_closed := false
var _melee_defeated := false
var _ranged_defeated := false
var _altar_complete := false
var _chest_complete := false
var _overlay_advance_requested := false
var _tutorial_background_texture: Texture2D = null
var _tutorial_ground_texture: Texture2D = null
var _tutorial_wall_texture: Texture2D = null
var _tutorial_platform_texture: Texture2D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_world()
	_connect_runtime_nodes()
	player.set_spawn_position(_room_spawn_position(0))
	player.set_camera_limits(0, 0, int(ROOM_WIDTH * ROOM_COUNT), 720)
	player.camera.make_current()
	hud.set_level_context("Tutorial")
	hud.set_boss_status("")
	hud.update_enemy_counter(0, 0)
	hud.set_room_context("Terminal Basics")
	hud.set_objective("Learn how the terminal opens combat options.")
	hud.set_lesson_progress("Room 1 / 5")
	hud.update_health(player.current_health, player.max_health)
	_configure_fade_layer()
	call_deferred("_run_tutorial")


func _input(event: InputEvent) -> void:
	if not overlay.visible:
		return
	if event.is_action_pressed("attack_primary") or event.is_action_pressed("jump") or _is_continue_key(event):
		_on_overlay_advanced()
		get_viewport().set_input_as_handled()


func _build_world() -> void:
	_load_tutorial_art()
	backdrop.offset_left = 0.0
	backdrop.offset_top = 0.0
	backdrop.offset_right = ROOM_WIDTH * ROOM_COUNT
	backdrop.offset_bottom = 720.0
	backdrop.color = Color(0.19, 0.2, 0.28, 1.0)
	if _tutorial_background_texture != null:
		_set_texture_overlay(backdrop, _tutorial_background_texture, false)
	for room_index in range(ROOM_COUNT):
		_build_room_shell(room_index)
	_build_terminal_room()
	_build_melee_room()
	_build_ranged_room()
	_build_chest_room()
	_build_altar_room()


func _build_room_shell(room_index: int) -> void:
	var room_start: float = room_index * ROOM_WIDTH
	var room_back := ColorRect.new()
	room_back.position = Vector2(room_start, 0.0)
	room_back.size = Vector2(ROOM_WIDTH, 720.0)
	room_back.color = Color(0.21 + room_index * 0.015, 0.22, 0.31 + room_index * 0.01, 1.0)
	world.add_child(room_back)
	if _tutorial_background_texture != null:
		_set_texture_overlay(room_back, _tutorial_background_texture, false)
	_add_floor(room_start)
	_add_wall(room_start + ROOM_WIDTH - 8.0)
	var header := Label.new()
	header.position = Vector2(room_start + 32.0, 36.0)
	header.text = _room_title(room_index)
	header.add_theme_font_size_override("font_size", 26)
	world.add_child(header)


func _build_terminal_room() -> void:
	var room_start: float = 0.0
	_add_one_way_platform(room_start + 720.0, 430.0, 260.0)
	_add_one_way_platform(room_start + 980.0, 300.0, 180.0)


func _build_melee_room() -> void:
	var room_start: float = ROOM_WIDTH
	_add_one_way_platform(room_start + 310.0, 460.0, 220.0)
	_add_one_way_platform(room_start + 900.0, 350.0, 200.0)
	_melee_enemy = _create_enemy(
		Vector2(room_start + 640.0, PLAYER_GROUND_Y),
		{
			"level_theme": "variables",
			"difficulty": "easy",
			"attack_style": "melee",
			"color": [0.78, 0.34, 0.34, 1.0],
			"patrol_distance": 60.0,
			"patrol_min_x": room_start + 560.0,
			"patrol_max_x": room_start + 720.0,
			"attack_interval": 2.2,
			"telegraph_duration": 0.6,
			"terminal_title": "Melee Practice Terminal",
			"terminal_status_text": "Prepare the blade and then test a close-range strike."
		}
	)


func _build_ranged_room() -> void:
	var room_start: float = ROOM_WIDTH * 2.0
	_add_one_way_platform(room_start + 420.0, 460.0, 220.0)
	_add_one_way_platform(room_start + 980.0, 340.0, 240.0)
	_ranged_enemy = _create_enemy(
		Vector2(room_start + 780.0, PLAYER_GROUND_Y),
		{
			"level_theme": "variables",
			"difficulty": "easy",
			"attack_style": "ranged",
			"color": [0.76, 0.48, 0.25, 1.0],
			"patrol_distance": 70.0,
			"patrol_min_x": room_start + 720.0,
			"patrol_max_x": room_start + 860.0,
			"ranged_attack_range": 340.0,
			"attack_interval": 2.3,
			"telegraph_duration": 0.64,
			"terminal_title": "Ranged Practice Terminal",
			"terminal_status_text": "Tune the shot and then test a ranged strike."
		}
	)


func _build_chest_room() -> void:
	var room_start: float = ROOM_WIDTH * 3.0
	_add_one_way_platform(room_start + 500.0, 380.0, 220.0)
	_chest = _create_chest(Vector2(room_start + 710.0, PLAYER_GROUND_Y + 4.0))


func _build_altar_room() -> void:
	var room_start: float = ROOM_WIDTH * 4.0
	_add_one_way_platform(room_start + 420.0, 420.0, 200.0)
	_add_one_way_platform(room_start + 930.0, 300.0, 220.0)
	_altar = _create_altar(Vector2(room_start + 760.0, PLAYER_GROUND_Y + 4.0))


func _connect_runtime_nodes() -> void:
	terminal.interaction_resolved.connect(_on_terminal_interaction_resolved)
	terminal.terminal_closed.connect(_on_terminal_closed)
	overlay.advanced.connect(_on_overlay_advanced)
	player.health_changed.connect(_on_player_health_changed)
	player.defeated.connect(_on_player_defeated)
	player.combat_action_requested.connect(_on_player_combat_action_requested)
	_melee_enemy.encounter_defeated.connect(_on_enemy_defeated)
	_ranged_enemy.encounter_defeated.connect(_on_enemy_defeated)
	_melee_enemy.world_attack_feedback.connect(_on_world_feedback)
	_ranged_enemy.world_attack_feedback.connect(_on_world_feedback)
	_chest.chest_opened.connect(_on_chest_opened)
	_altar.weapon_forged.connect(_on_altar_forged)


func _configure_fade_layer() -> void:
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 1)


func _run_tutorial() -> void:
	_move_to_room(0, true)
	await _fade_from_black(0.5)
	await _run_terminal_room()
	await _transition_to_room(1, true)
	await _run_melee_room_sequence()
	await _transition_to_room(2, true)
	await _run_ranged_room_sequence()
	await _transition_to_room(3, true)
	await _run_chest_room_sequence()
	await _transition_to_room(4, true)
	await _run_altar_room_sequence()
	await _fade_to_black(0.5)
	GameState.mark_tutorial_completed()
	get_tree().change_scene_to_file(NEXT_SCENE_PATH)


func _run_terminal_room() -> void:
	_move_to_room(0, true)
	hud.set_room_context("Terminal Basics")
	hud.set_objective("See how tasks, hints and explanation work.")
	hud.set_lesson_progress("Room 1 / 5")
	hud.show_message("The tutorial starts with the terminal itself.", 1.8)
	var payload := _terminal_intro_payload()
	_open_terminal(payload)
	await terminal.task_loaded
	var targets: Dictionary = terminal.tutorial_get_targets()
	await _show_overlay_step("This header tells you what kind of coding task was generated.", targets["title"], "down", "top")
	await _show_overlay_step("Here you can see whether the task came from AI or from a safe tutorial preset.", targets["source"], "down", "top")
	await _show_overlay_step("The task text explains what values you should write and why they matter in combat.", targets["status"], "down", "top")
	await _show_overlay_step("This is the code area. On normal levels you write your own answer here.", targets["code"], "down", "center")
	await _show_overlay_step("Hint is optional. It can help, but you do not need to open it to continue.", targets["hint_button"], "up", "bottom")
	await _show_overlay_step("Explonation is optional too. It opens the short topic summary when you want extra help.", targets["explanation_button"], "up", "bottom")
	await _show_overlay_step("Run checks your code and unlocks the related gameplay effect.", targets["run_button"], "up", "bottom")
	await _show_overlay_step("Close also finishes this first orientation room. Run or Close both move the tutorial forward here.", targets["close_button"], "up", "bottom")
	await _wait_for_terminal_done()
	_release_terminal_control()


func _run_melee_room_sequence() -> void:
	_move_to_room(1, true)
	hud.set_room_context("Melee Trial")
	hud.set_objective("Run the prepared melee code, then strike nearby with Q.")
	hud.set_lesson_progress("Room 2 / 5")
	hud.update_enemy_counter(1, 1)
	var payload := _melee_terminal_payload()
	_open_terminal(payload)
	await terminal.task_loaded
	var targets: Dictionary = terminal.tutorial_get_targets()
	await _show_overlay_step("This room is about close combat. The code is already filled in for you.", targets["code"], "down", "center")
	await _show_overlay_step("Hint and Explonation are available, but this room only requires Run.", targets["explanation_button"], "up", "bottom")
	await _show_overlay_step("Press Run to apply the melee setup. After that, move close and attack with Q.", targets["run_button"], "up", "bottom")
	await _wait_for_terminal_success(payload, "Press Run to apply the melee setup.")
	if not _terminal_result_success:
		hud.show_message("Tutorial accepted: melee code was skipped.", 1.4)
	_current_combat_target = _melee_enemy
	await _show_overlay_step("Now walk up to the sentinel and press Q. At close range the hit becomes a melee attack.", _melee_enemy, "down", "top")
	_melee_enemy.unlock_combat()
	player.set_terminal_locked(false)
	await _wait_for_melee_defeat()
	hud.update_enemy_counter(0, 1)


func _run_ranged_room_sequence() -> void:
	_move_to_room(2, true)
	hud.set_room_context("Ranged Trial")
	hud.set_objective("Run the prepared ranged code, then fire from distance with Q.")
	hud.set_lesson_progress("Room 3 / 5")
	hud.update_enemy_counter(1, 1)
	var payload := _ranged_terminal_payload()
	_open_terminal(payload)
	await terminal.task_loaded
	var targets: Dictionary = terminal.tutorial_get_targets()
	await _show_overlay_step("Here the setup is for a ranged hit. The prepared variables already show the pattern.", targets["code"], "down", "center")
	await _show_overlay_step("Hint and Explonation stay optional here too. You can skip them and press Run.", targets["hint_button"], "up", "bottom")
	await _show_overlay_step("Press Run, keep your distance, then attack with Q to fire a projectile.", targets["run_button"], "up", "bottom")
	await _wait_for_terminal_success(payload, "Press Run to apply the ranged setup.")
	if not _terminal_result_success:
		hud.show_message("Tutorial accepted: ranged code was skipped.", 1.4)
	_current_combat_target = _ranged_enemy
	await _show_overlay_step("Stay a bit farther away from this sentinel. Q should choose a ranged shot instead of a melee hit.", _ranged_enemy, "down", "top")
	_ranged_enemy.unlock_combat()
	player.set_terminal_locked(false)
	await _wait_for_ranged_defeat()
	hud.update_enemy_counter(0, 1)


func _run_chest_room_sequence() -> void:
	_move_to_room(3, true)
	hud.set_room_context("Chest Trial")
	hud.set_objective("Use code to open the chest.")
	hud.set_lesson_progress("Room 4 / 5")
	hud.update_enemy_counter(0, 0)
	var payload := _chest_terminal_payload()
	_open_terminal(payload)
	await terminal.task_loaded
	var targets: Dictionary = terminal.tutorial_get_targets()
	await _show_overlay_step("Chests use the same terminal, but the code now unlocks a reward instead of combat.", _chest, "down", "top")
	await _show_overlay_step("The tutorial fills in a small chest script. You still press Run yourself.", targets["code"], "down", "center")
	await _show_overlay_step("Optional help is still there if you want it. The required action is Run.", targets["explanation_button"], "up", "bottom")
	await _show_overlay_step("Run the prepared snippet to open the chest.", targets["run_button"], "up", "bottom")
	await _wait_for_terminal_success(payload, "Press Run to unlock the chest.")
	_chest.mark_opened()
	await _wait_for_chest_complete()


func _run_altar_room_sequence() -> void:
	_move_to_room(4, true)
	hud.set_room_context("Altar Trial")
	hud.set_objective("Forge the altar pattern. The tutorial ends here.")
	hud.set_lesson_progress("Room 5 / 5")
	hud.update_enemy_counter(0, 0)
	var payload := _altar_terminal_payload()
	_open_terminal(payload)
	await terminal.task_loaded
	var targets: Dictionary = terminal.tutorial_get_targets()
	await _show_overlay_step("Altars also use code, but here the variables shape weapon behavior directly.", _altar, "down", "top")
	await _show_overlay_step("The forge code is already filled in. Read it once, then apply it with Run.", targets["code"], "down", "center")
	await _show_overlay_step("Explonation can help if you want to reread the theme, but it is not required.", targets["explanation_button"], "up", "bottom")
	await _show_overlay_step("Press Run to forge the altar setup and finish the tutorial.", targets["run_button"], "up", "bottom")
	await _wait_for_terminal_success(payload, "Press Run to forge the altar setup.")
	_altar.mark_forged("Tutorial blade forged.")
	await _wait_for_altar_complete()


func _move_to_room(room_index: int, lock_player: bool) -> void:
	_current_room = room_index
	player.set_spawn_position(_room_spawn_position(room_index))
	player.global_position = _room_spawn_position(room_index)
	player.velocity = Vector2.ZERO
	player.camera.make_current()
	player.camera.reset_smoothing()
	player.set_terminal_locked(lock_player)


func _transition_to_room(room_index: int, lock_player: bool) -> void:
	overlay.hide_overlay()
	terminal.hide_terminal()
	_release_terminal_control()
	player.set_terminal_locked(true)
	await _fade_to_black(ROOM_FADE_OUT_DURATION)
	_current_combat_target = null
	_move_to_room(room_index, lock_player)
	await _wait_ui_refresh()
	await _fade_from_black(ROOM_FADE_IN_DURATION)


func _room_spawn_position(room_index: int) -> Vector2:
	var room_start: float = room_index * ROOM_WIDTH
	return Vector2(room_start + 240.0, PLAYER_GROUND_Y)


func _open_terminal(payload: Dictionary) -> void:
	_reset_terminal_wait_state()
	get_tree().paused = true
	hud.set_terminal_overlay_mode(true)
	player.set_terminal_locked(true)
	terminal.open_terminal(payload)


func _reset_terminal_wait_state() -> void:
	_terminal_result_ready = false
	_terminal_result_success = false
	_terminal_result_payload = {}
	_terminal_closed = false


func _wait_for_terminal_done() -> void:
	if _terminal_closed or _terminal_result_ready:
		return
	await terminal_step_finished


func _wait_for_terminal_success(payload: Dictionary, retry_text: String) -> void:
	while true:
		await _wait_for_terminal_done()
		_release_terminal_control()
		if _terminal_result_success:
			return
		hud.show_message("Finish this step with Run, then the tutorial continues.", 1.4)
		await _wait_ui_refresh()
		_open_terminal(payload)
		await terminal.task_loaded
		var targets: Dictionary = terminal.tutorial_get_targets()
		await _show_overlay_step(retry_text, targets["run_button"], "up", "bottom")


func _wait_ui_refresh() -> void:
	await get_tree().create_timer(0.05, true).timeout


func _wait_for_melee_defeat() -> void:
	if _melee_defeated:
		return
	await _melee_enemy.encounter_defeated


func _wait_for_ranged_defeat() -> void:
	if _ranged_defeated:
		return
	await _ranged_enemy.encounter_defeated


func _wait_for_chest_complete() -> void:
	if _chest_complete:
		return
	await _chest.chest_opened


func _wait_for_altar_complete() -> void:
	if _altar_complete:
		return
	await _altar.weapon_forged


func _release_terminal_control() -> void:
	get_tree().paused = false
	hud.set_terminal_overlay_mode(false)
	player.set_terminal_locked(false)


func _show_overlay_step(text: String, target: Variant, arrow_direction: String = "down", panel_anchor: String = "bottom") -> void:
	player.set_terminal_locked(true)
	_overlay_advance_requested = false
	overlay.show_step(text, target, arrow_direction, panel_anchor)
	if not _overlay_advance_requested:
		await overlay_step_finished
	overlay.hide_overlay()


func _is_continue_key(event: InputEvent) -> bool:
	if event is not InputEventKey:
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	return key_event.physical_keycode == Key.KEY_Q or key_event.physical_keycode == Key.KEY_SPACE


func _fade_from_black(duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 1)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", 0.0, duration)
	await _fade_tween.finished
	fade_rect.visible = false


func _fade_to_black(duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	fade_rect.visible = true
	fade_rect.color = Color(0, 0, 0, 0)
	_fade_tween = create_tween()
	_fade_tween.tween_property(fade_rect, "color:a", 1.0, duration)
	await _fade_tween.finished


func _on_terminal_interaction_resolved(success: bool, result: Dictionary) -> void:
	_terminal_result_ready = true
	_terminal_result_success = success
	_terminal_result_payload = result.duplicate(true)
	_overlay_advance_requested = true
	overlay.hide_overlay()
	overlay_step_finished.emit()
	_release_terminal_control()
	terminal_step_finished.emit()


func _on_terminal_closed() -> void:
	_terminal_closed = true
	_overlay_advance_requested = true
	overlay.hide_overlay()
	overlay_step_finished.emit()
	_release_terminal_control()
	terminal_step_finished.emit()


func _on_overlay_advanced() -> void:
	_overlay_advance_requested = true
	overlay_step_finished.emit()


func _on_player_health_changed(current_health: int, max_health: int) -> void:
	hud.update_health(current_health, max_health)


func _on_player_defeated() -> void:
	player.restore_full_health()
	player.set_spawn_position(_room_spawn_position(_current_room))
	player.global_position = _room_spawn_position(_current_room)
	hud.show_message("Tutorial checkpoint restored.", 1.6)


func _on_player_combat_action_requested(facing_direction: Vector2) -> void:
	if _current_combat_target == null or not is_instance_valid(_current_combat_target):
		return
	if _current_combat_target.is_defeated() or not _current_combat_target.is_combat_unlocked():
		return
	var combo_mode := _choose_combo_mode(_current_combat_target)
	var step_name: String = "melee_one" if combo_mode == "melee" else "ranged_one"
	player.perform_combat_motion(step_name, facing_direction, _current_combat_target.global_position)
	if combo_mode == "melee":
		_apply_tutorial_melee_hit(_current_combat_target)
	else:
		_fire_tutorial_projectile(_current_combat_target)


func _apply_tutorial_melee_hit(target: EnemyEncounter) -> void:
	if target == null or not is_instance_valid(target):
		return
	if player.global_position.distance_to(target.global_position) > TUTORIAL_MELEE_RANGE:
		hud.show_message("Move closer before using a melee strike.", 1.2)
		return
	target.apply_combat_result({"damage": TUTORIAL_MELEE_DAMAGE})
	hud.show_message("Melee strike connected.", 1.0)


func _fire_tutorial_projectile(target: EnemyEncounter) -> void:
	if target == null or not is_instance_valid(target):
		return
	var projectile := PROJECTILE_SCRIPT.new() as EnemyProjectile
	if projectile == null:
		return
	var direction: Vector2 = (target.global_position - player.global_position).normalized()
	var start_position: Vector2 = player.global_position + direction * 24.0
	projectile.configure(start_position, direction, TUTORIAL_RANGED_DAMAGE, TUTORIAL_RANGED_PROJECTILE_SPEED, "enemy", Color(0.58, 0.85, 1.0, 1.0))
	projectile.target_hit.connect(_on_player_projectile_hit)
	projectile.projectile_expired.connect(_on_player_projectile_expired)
	world.add_child(projectile)
	_player_projectiles.append(projectile)
	hud.show_message("Ranged shot fired.", 1.0)


func _on_player_projectile_hit(projectile: EnemyProjectile, target: Node, damage: int) -> void:
	if target is EnemyEncounter:
		(target as EnemyEncounter).apply_combat_result({"damage": damage})
	_on_player_projectile_expired(projectile)


func _on_player_projectile_expired(projectile: EnemyProjectile) -> void:
	_player_projectiles.erase(projectile)


func _on_enemy_defeated(encounter: EnemyEncounter) -> void:
	if encounter == _melee_enemy:
		_melee_defeated = true
	elif encounter == _ranged_enemy:
		_ranged_defeated = true
	_current_combat_target = null


func _on_world_feedback(message: String) -> void:
	hud.show_message(message, 1.4)


func _on_chest_opened(_chest_node: ChestEncounter, reward_text: String) -> void:
	_chest_complete = true
	hud.show_message(reward_text, 1.6)


func _on_altar_forged(_altar_node: AltarEncounter, weapon_summary: String) -> void:
	_altar_complete = true
	hud.show_message(weapon_summary, 1.6)


func _choose_combo_mode(target: EnemyEncounter) -> String:
	if target == _melee_enemy:
		return "melee"
	if target == _ranged_enemy:
		return "ranged"
	var distance: float = player.global_position.distance_to(target.global_position)
	if distance <= TUTORIAL_MELEE_PREFERRED_RANGE:
		return "melee"
	if distance >= TUTORIAL_RANGED_PREFERRED_RANGE:
		return "ranged"
	var melee_gap: float = absf(distance - TUTORIAL_MELEE_PREFERRED_RANGE)
	var ranged_gap: float = absf(distance - TUTORIAL_RANGED_PREFERRED_RANGE)
	return "melee" if melee_gap <= ranged_gap else "ranged"


func _terminal_intro_payload() -> Dictionary:
	return {
		"interaction_type": "combat",
		"title": "Tutorial Terminal",
		"status_text": "This room explains how terminal tasks work.",
		"success_text": "Tutorial step complete.",
		"failure_text": "Not yet.",
		"time_limit": 0,
		"timer_enabled": false,
		"tutorial_mode": true,
		"level_theme": "variables",
		"encounter_name": "Tutorial Console",
		"encounter_style": "guided_intro",
		"tutorial_auto_code": "damage = 12\nspeed = 5\nguard_window = 0.4",
		"tutorial_force_success_code": "damage = 12\nspeed = 5\nguard_window = 0.4",
		"preset_task": {
			"title": "Terminal Orientation",
			"prompt": "Read the generated task and notice the important words: damage, speed and guard window. Later you will turn those words into code that changes combat.",
			"gameplay_effect": "Tutorial introduction only.",
			"generation_source": "tutorial",
			"generation_detail": "guided walkthrough",
			"keywords": ["damage", "speed", "guard window"],
			"validation_targets": ["damage", "speed", "guard_window"],
			"syntax_rules": ["Use short Python assignments.", "Keep names clear and readable."],
			"explanation_title": "Variables",
			"explanation_prompt": "Look for the stat words in the task. Those words usually tell you what variables are worth writing.",
			"explanation_body": "Variables store values. In this game they tune combat stats like damage, speed or guard timing. A short line such as damage = 12 is already enough to change behavior.",
			"explanation_rules": ["Use assignment with =.", "Pick readable names.", "One line can change one stat."],
			"example_code": "damage = 12\nspeed = 5\nguard_window = 0.4",
			"fallback_hints": ["Find the stat words in the text.", "Turn each stat word into one variable line."]
		},
		"tutorial_hint_override": [
			"Focus on the stat words written in the task text.",
			"Each important stat can become one assignment line.",
			"The explanation window gives the short theory for the current topic."
		]
	}


func _melee_terminal_payload() -> Dictionary:
	return {
		"interaction_type": "combat",
		"title": "Melee Practice Terminal",
		"status_text": "Prepare a short melee setup.",
		"success_text": "Melee setup accepted.",
		"failure_text": "The melee setup is not ready yet.",
		"time_limit": 0,
		"timer_enabled": false,
		"tutorial_mode": true,
		"level_theme": "variables",
		"encounter_name": "Blade Sentinel",
		"encounter_style": "melee",
		"tutorial_auto_code": "melee_damage = 14\nmelee_range = 120\nswing_speed = 3",
		"tutorial_force_success_code": "melee_damage = 14\nmelee_range = 120\nswing_speed = 3",
		"preset_task": {
			"title": "Melee Strike Setup",
			"prompt": "The Blade Sentinel fights up close. Set melee damage, melee range and swing speed so the knight is ready for a close strike.",
			"gameplay_effect": "Unlocks a melee test hit.",
			"generation_source": "tutorial",
			"generation_detail": "guided melee practice",
			"keywords": ["melee damage", "melee range", "swing speed"],
			"validation_targets": ["melee_damage", "melee_range", "swing_speed"],
			"syntax_rules": ["Use plain assignments only.", "Keep one stat per line."],
			"explanation_title": "Variables",
			"explanation_prompt": "The important words are the combat stats in the task sentence.",
			"explanation_body": "In melee tasks you often tune power, reach and rhythm. A variable like melee_damage changes how hard the hit lands, while swing_speed can describe how sharp or slow the motion feels.",
			"explanation_rules": ["Use readable stat names.", "Numbers can be integers.", "Short snippets are enough."],
			"example_code": "melee_damage = 12\nmelee_range = 110\nswing_speed = 2",
			"fallback_hints": ["Start with melee_damage.", "Then set range and speed."]
		}
	}


func _ranged_terminal_payload() -> Dictionary:
	return {
		"interaction_type": "combat",
		"title": "Ranged Practice Terminal",
		"status_text": "Prepare a short ranged setup.",
		"success_text": "Ranged setup accepted.",
		"failure_text": "The ranged setup is not ready yet.",
		"time_limit": 0,
		"timer_enabled": false,
		"tutorial_mode": true,
		"level_theme": "variables",
		"encounter_name": "Caster Sentinel",
		"encounter_style": "ranged",
		"tutorial_auto_code": "shot_damage = 10\nprojectile_speed = 340\nvolley_count = 1",
		"tutorial_force_success_code": "shot_damage = 10\nprojectile_speed = 340\nvolley_count = 1",
		"preset_task": {
			"title": "Ranged Shot Setup",
			"prompt": "The Caster Sentinel keeps distance. Set shot damage, projectile speed and volley count so the knight can fire safely from range.",
			"gameplay_effect": "Unlocks a ranged test hit.",
			"generation_source": "tutorial",
			"generation_detail": "guided ranged practice",
			"keywords": ["shot damage", "projectile speed", "volley count"],
			"validation_targets": ["shot_damage", "projectile_speed", "volley_count"],
			"syntax_rules": ["Use assignments only.", "Keep names related to the task words."],
			"explanation_title": "Variables",
			"explanation_prompt": "Read the stat words and map them to short variable names.",
			"explanation_body": "Ranged tasks still use the same idea: one variable stores one combat value. projectile_speed can make a shot travel faster, while shot_damage changes the impact if it lands.",
			"explanation_rules": ["Use one variable per line.", "Choose names that match the task text.", "Use simple numbers first."],
			"example_code": "shot_damage = 8\nprojectile_speed = 300\nvolley_count = 1",
			"fallback_hints": ["Damage controls impact.", "Projectile speed controls travel.", "Volley count controls how many shots are prepared."]
		}
	}


func _chest_terminal_payload() -> Dictionary:
	return {
		"interaction_type": "chest",
		"title": "Tutorial Chest Terminal",
		"status_text": "Open the chest with a simple reward pattern.",
		"success_text": "Chest unlocked.",
		"failure_text": "The chest remains sealed.",
		"time_limit": 0,
		"timer_enabled": false,
		"tutorial_mode": true,
		"level_theme": "variables",
		"encounter_name": "Archive Chest",
		"encounter_style": "reward_puzzle",
		"tutorial_auto_code": "reward_key = 1\nchest_unlock_time = 0",
		"tutorial_force_success_code": "reward_key = 1\nchest_unlock_time = 0",
		"preset_task": {
			"title": "Chest Unlock Setup",
			"prompt": "The chest needs a reward key and unlock time. Set both values so the archive chest opens immediately.",
			"gameplay_effect": "Opens the chest reward.",
			"generation_source": "tutorial",
			"generation_detail": "guided chest practice",
			"keywords": ["reward key", "unlock time"],
			"validation_targets": ["reward_key", "chest_unlock_time"],
			"syntax_rules": ["Keep the snippet short.", "Use assignment lines only."],
			"explanation_title": "Variables",
			"explanation_prompt": "Chest tasks still work the same way: read the requested stat words and store them in variables.",
			"explanation_body": "Outside combat, code can still affect the world. A chest can react to reward or timing variables the same way an enemy reacts to damage or speed values.",
			"explanation_rules": ["Use readable names.", "Use one line per requested value."],
			"example_code": "reward_key = 1\nchest_unlock_time = 1",
			"fallback_hints": ["One line should define the key.", "Another line should define the time."]
		}
	}


func _altar_terminal_payload() -> Dictionary:
	return {
		"interaction_type": "altar",
		"title": "Tutorial Forge Terminal",
		"status_text": "Forge a simple altar pattern.",
		"success_text": "Weapon forged.",
		"failure_text": "The forge rejects the pattern.",
		"time_limit": 0,
		"timer_enabled": false,
		"tutorial_mode": true,
		"level_theme": "variables",
		"encounter_name": "Forge Altar",
		"encounter_style": "weapon_forge",
		"tutorial_auto_code": "blade_power = 18\nguard_window = 0.4\naltar_charge = 2",
		"tutorial_force_success_code": "blade_power = 18\nguard_window = 0.4\naltar_charge = 2",
		"preset_task": {
			"title": "Altar Forge Setup",
			"prompt": "The altar shapes weapon behavior directly. Set blade power, guard window and altar charge so the forge can finish the pattern.",
			"gameplay_effect": "Forges the tutorial weapon setup.",
			"generation_source": "tutorial",
			"generation_detail": "guided altar practice",
			"keywords": ["blade power", "guard window", "altar charge"],
			"validation_targets": ["blade_power", "guard_window", "altar_charge"],
			"syntax_rules": ["Use short assignments.", "Keep names readable and tied to the forge text."],
			"explanation_title": "Variables",
			"explanation_prompt": "At the altar, the task words describe weapon stats instead of enemy stats.",
			"explanation_body": "The same variable skill now controls forging. blade_power can describe how strong the weapon becomes, while guard_window can describe how forgiving the defense timing will feel.",
			"explanation_rules": ["Use assignments only.", "Mirror the task wording in your variable names."],
			"example_code": "blade_power = 15\nguard_window = 0.3\naltar_charge = 1",
			"fallback_hints": ["Power affects the weapon.", "Guard window affects timing.", "Charge finishes the forge pattern."]
		}
	}


func _room_title(room_index: int) -> String:
	match room_index:
		0:
			return "Room 1: Terminal"
		1:
			return "Room 2: Melee"
		2:
			return "Room 3: Ranged"
		3:
			return "Room 4: Chest"
		_:
			return "Room 5: Altar"


func _add_floor(room_start: float) -> void:
	var floor_body := StaticBody2D.new()
	floor_body.collision_layer = 1
	floor_body.position = Vector2(room_start + ROOM_WIDTH * 0.5, FLOOR_TOP + FLOOR_HEIGHT * 0.5)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(ROOM_WIDTH, FLOOR_HEIGHT)
	collision.shape = shape
	floor_body.add_child(collision)
	var visual := ColorRect.new()
	visual.position = Vector2(-ROOM_WIDTH * 0.5, -FLOOR_HEIGHT * 0.5)
	visual.size = Vector2(ROOM_WIDTH, FLOOR_HEIGHT)
	visual.color = Color(0.28, 0.25, 0.39, 0.0)
	floor_body.add_child(visual)
	if _tutorial_ground_texture != null:
		_set_texture_overlay(visual, _tutorial_ground_texture, true)
	world.add_child(floor_body)


func _add_wall(x_position: float) -> void:
	var wall := StaticBody2D.new()
	wall.collision_layer = 1
	wall.position = Vector2(x_position, 300.0)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16.0, 620.0)
	collision.shape = shape
	wall.add_child(collision)
	var visual := ColorRect.new()
	visual.position = Vector2(-8.0, -310.0)
	visual.size = Vector2(16.0, 620.0)
	visual.color = Color(0.22, 0.2, 0.32, 0.0)
	wall.add_child(visual)
	if _tutorial_wall_texture != null:
		_set_texture_overlay(visual, _tutorial_wall_texture, true)
	world.add_child(wall)


func _add_one_way_platform(x_position: float, y_position: float, width: float) -> void:
	var platform := StaticBody2D.new()
	platform.collision_layer = 2
	platform.position = Vector2(x_position, y_position)
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(width, 10.0)
	collision.position = Vector2(0.0, -3.0)
	collision.shape = shape
	collision.one_way_collision = true
	collision.one_way_collision_margin = 2.0
	platform.add_child(collision)
	var visual := ColorRect.new()
	visual.position = Vector2(-width * 0.5, -8.0)
	visual.size = Vector2(width, 16.0)
	visual.color = Color(0.42, 0.32, 0.53, 0.0)
	platform.add_child(visual)
	if _tutorial_platform_texture != null:
		_set_texture_overlay(visual, _tutorial_platform_texture, true)
	world.add_child(platform)


func _load_tutorial_art() -> void:
	_tutorial_background_texture = _load_texture("%s/backgrounds/background.png" % TUTORIAL_ART_ROOT)
	_tutorial_ground_texture = _load_texture("%s/tilesets/tileset_ground.png" % TUTORIAL_ART_ROOT)
	_tutorial_wall_texture = _load_texture("%s/tilesets/tileset_walls.png" % TUTORIAL_ART_ROOT)
	_tutorial_platform_texture = _load_texture("%s/platforms/platform_one_way.png" % TUTORIAL_ART_ROOT)


func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return ResourceLoader.load(path) as Texture2D


func _set_texture_overlay(control: Control, texture: Texture2D, tile: bool) -> void:
	if texture == null:
		return
	control.clip_contents = true
	if control is ColorRect:
		var color_rect := control as ColorRect
		color_rect.color = Color(color_rect.color.r, color_rect.color.g, color_rect.color.b, 0.0)
	var texture_rect := control.get_node_or_null("ProductionTexture") as TextureRect
	if texture_rect == null:
		texture_rect = TextureRect.new()
		texture_rect.name = "ProductionTexture"
		texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		control.add_child(texture_rect)
	texture_rect.texture = texture
	texture_rect.position = Vector2.ZERO
	texture_rect.size = control.size
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.stretch_mode = TextureRect.STRETCH_TILE if tile else TextureRect.STRETCH_KEEP_ASPECT_COVERED
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _create_enemy(spawn_position: Vector2, config: Dictionary) -> EnemyEncounter:
	var enemy := EnemyEncounter.new()
	enemy.position = spawn_position
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(42.0, 72.0)
	collision.position = Vector2(0.0, -12.0)
	collision.shape = shape
	collision.name = "CollisionShape2D"
	enemy.add_child(collision)
	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.offset_left = -21.0
	visual.offset_top = -48.0
	visual.offset_right = 21.0
	visual.offset_bottom = 24.0
	visual.visible = false
	visual.color = Color(0, 0, 0, 0)
	visual.modulate = Color(1, 1, 1, 0)
	visual.self_modulate = Color(1, 1, 1, 0)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	enemy.add_child(visual)
	var hp_label := Label.new()
	hp_label.name = "HpLabel"
	hp_label.offset_left = -42.0
	hp_label.offset_top = -92.0
	hp_label.offset_right = 44.0
	hp_label.offset_bottom = -66.0
	hp_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy.add_child(hp_label)
	var state_label := Label.new()
	state_label.name = "StateLabel"
	state_label.visible = false
	state_label.offset_left = -58.0
	state_label.offset_top = -118.0
	state_label.offset_right = 60.0
	state_label.offset_bottom = -94.0
	state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	enemy.add_child(state_label)
	world.add_child(enemy)
	enemy.configure(config)
	return enemy


func _create_chest(spawn_position: Vector2) -> ChestEncounter:
	var chest := ChestEncounter.new()
	chest.position = spawn_position
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(72.0, 54.0)
	collision.position = Vector2(0.0, -7.0)
	collision.shape = shape
	collision.name = "CollisionShape2D"
	chest.add_child(collision)
	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.offset_left = -28.0
	visual.offset_top = -24.0
	visual.offset_right = 28.0
	visual.offset_bottom = 20.0
	visual.visible = false
	visual.color = Color(0, 0, 0, 0)
	visual.modulate = Color(1, 1, 1, 0)
	visual.self_modulate = Color(1, 1, 1, 0)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chest.add_child(visual)
	var label := Label.new()
	label.name = "Label"
	label.visible = false
	label.offset_left = -36.0
	label.offset_top = -58.0
	label.offset_right = 38.0
	label.offset_bottom = -28.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chest.add_child(label)
	world.add_child(chest)
	return chest


func _create_altar(spawn_position: Vector2) -> AltarEncounter:
	var altar := AltarEncounter.new()
	altar.position = spawn_position
	var collision := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(84.0, 56.0)
	collision.position = Vector2(0.0, -6.0)
	collision.shape = shape
	collision.name = "CollisionShape2D"
	altar.add_child(collision)
	var visual := ColorRect.new()
	visual.name = "Visual"
	visual.offset_left = -34.0
	visual.offset_top = -26.0
	visual.offset_right = 34.0
	visual.offset_bottom = 22.0
	visual.visible = false
	visual.color = Color(0, 0, 0, 0)
	visual.modulate = Color(1, 1, 1, 0)
	visual.self_modulate = Color(1, 1, 1, 0)
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	altar.add_child(visual)
	var label := Label.new()
	label.name = "Label"
	label.visible = false
	label.offset_left = -42.0
	label.offset_top = -58.0
	label.offset_right = 44.0
	label.offset_bottom = -28.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	altar.add_child(label)
	world.add_child(altar)
	return altar
