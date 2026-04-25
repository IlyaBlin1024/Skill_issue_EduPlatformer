extends Node

const SAVE_FILE := "user://codeknight_saves.json"
const SETTINGS_FILE := "user://codeknight_settings.json"
const ANALYTICS_FILE := "user://player_analytics.jsonl"
const MAX_SAVE_SLOTS := 5

const MAIN_MENU_SCENE := "res://scenes/main_menu.tscn"
const TUTORIAL_SCENE := "res://scenes/tutorial.tscn"
const LEVEL_SCENE := "res://scenes/main.tscn"
const BOSS_SCENE := "res://scenes/boss_room.tscn"

const LEVELS := [
	{"id": "level_01", "number": 1, "title": "Variables", "path": "res://data/levels/level_01.json"},
	{"id": "level_02", "number": 2, "title": "If / Else", "path": "res://data/levels/level_02.json"},
	{"id": "level_03", "number": 3, "title": "Loops", "path": "res://data/levels/level_03.json"},
	{"id": "level_04", "number": 4, "title": "Functions", "path": "res://data/levels/level_04.json"},
	{"id": "level_05", "number": 5, "title": "Integration", "path": "res://data/levels/level_05.json"}
]

var settings: Dictionary = {
	"volume": 0.85,
	"generation_mode": "ai",
	"difficulty": "normal",
	"hf_api_key": ""
}

var save_slots: Array[Dictionary] = []
var active_save_slot := 0
var pending_stage_type := ""
var pending_level_id := ""
var pending_level_path := ""
var session_id := ""
var _session_end_logged := false


func _ready() -> void:
	session_id = "%d_%d" % [Time.get_unix_time_from_system(), randi()]
	load_all()
	apply_settings()
	call_deferred("log_event", "session_start", {})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_PREDELETE:
		if not _session_end_logged:
			_session_end_logged = true
			log_event("session_end")


func load_all() -> void:
	_load_settings()
	_load_saves()


func get_levels() -> Array:
	return LEVELS.duplicate(true)


func get_level_by_id(level_id: String) -> Dictionary:
	for level_variant in LEVELS:
		var level_data: Dictionary = level_variant
		if String(level_data.get("id", "")) == level_id:
			return level_data.duplicate(true)
	return {}


func get_level_index(level_id: String) -> int:
	for index in range(LEVELS.size()):
		var level_data: Dictionary = LEVELS[index]
		if String(level_data.get("id", "")) == level_id:
			return index
	return -1


func quick_play() -> void:
	log_event("quick_play_requested")
	var slot: Dictionary = _active_save()
	if bool(slot.get("empty", true)):
		start_tutorial()
		return
	var current_stage: Dictionary = slot.get("current_stage", {"type": "tutorial", "level_id": ""})
	var stage_type := String(current_stage.get("type", "tutorial"))
	var level_id := String(current_stage.get("level_id", ""))
	if stage_type == "boss" and not level_id.is_empty():
		start_boss(level_id)
	elif stage_type == "level" and not level_id.is_empty():
		start_level(level_id)
	else:
		start_tutorial()


func start_tutorial() -> void:
	log_event("tutorial_started")
	pending_stage_type = "tutorial"
	pending_level_id = ""
	pending_level_path = ""
	_update_current_stage("tutorial", "")
	get_tree().paused = false
	get_tree().change_scene_to_file(TUTORIAL_SCENE)


func start_level(level_id: String) -> void:
	var level_data := get_level_by_id(level_id)
	if level_data.is_empty():
		return
	log_event("level_started", {"level_id": level_id})
	pending_stage_type = "level"
	pending_level_id = level_id
	pending_level_path = String(level_data.get("path", ""))
	_update_current_stage("level", level_id)
	get_tree().paused = false
	get_tree().change_scene_to_file(LEVEL_SCENE)


func start_boss(level_id: String) -> void:
	var level_data := get_level_by_id(level_id)
	if level_data.is_empty():
		return
	log_event("boss_started", {"level_id": level_id})
	pending_stage_type = "boss"
	pending_level_id = level_id
	pending_level_path = String(level_data.get("path", ""))
	_update_current_stage("boss", level_id)
	get_tree().paused = false
	get_tree().change_scene_to_file(BOSS_SCENE)


func go_to_main_menu() -> void:
	log_event("main_menu_opened")
	get_tree().paused = false
	pending_stage_type = ""
	pending_level_id = ""
	pending_level_path = ""
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)


func mark_tutorial_completed() -> void:
	log_event("tutorial_completed")
	var slot := _active_save()
	slot["empty"] = false
	slot["tutorial_completed"] = true
	slot["current_stage"] = {"type": "level", "level_id": "level_01"}
	_touch_slot(slot)
	_write_saves()


func mark_level_completed(level_id: String) -> void:
	log_event("level_completed", {"level_id": level_id})
	var slot := _active_save()
	slot["empty"] = false
	var levels: Dictionary = slot.get("levels_completed", {})
	levels[level_id] = true
	slot["levels_completed"] = levels
	slot["current_stage"] = {"type": "boss", "level_id": level_id}
	_touch_slot(slot)
	_write_saves()


func mark_boss_completed(level_id: String) -> void:
	log_event("boss_completed", {"level_id": level_id})
	var slot := _active_save()
	slot["empty"] = false
	var bosses: Dictionary = slot.get("bosses_completed", {})
	bosses[level_id] = true
	slot["bosses_completed"] = bosses
	var level_index := get_level_index(level_id)
	if level_index >= 0 and level_index + 1 < LEVELS.size():
		var next_level: Dictionary = LEVELS[level_index + 1]
		slot["current_stage"] = {"type": "level", "level_id": String(next_level.get("id", ""))}
	else:
		slot["current_stage"] = {"type": "complete", "level_id": level_id}
	_touch_slot(slot)
	_write_saves()


func save_current_game(stage_type: String = "", level_id: String = "") -> void:
	log_event("game_saved", {"stage_type": stage_type, "level_id": level_id})
	var slot := _active_save()
	slot["empty"] = false
	if not stage_type.is_empty():
		slot["current_stage"] = {"type": stage_type, "level_id": level_id}
	elif not pending_stage_type.is_empty():
		slot["current_stage"] = {"type": pending_stage_type, "level_id": pending_level_id}
	slot["settings_snapshot"] = settings.duplicate(true)
	_touch_slot(slot)
	_write_saves()


func select_save_slot(slot_index: int) -> void:
	active_save_slot = clampi(slot_index, 0, MAX_SAVE_SLOTS - 1)
	log_event("save_slot_selected", {"slot": active_save_slot})
	if save_slots[active_save_slot].get("empty", true):
		save_slots[active_save_slot] = _new_save_slot(active_save_slot, false)
	_write_saves()


func delete_save_slot(slot_index: int) -> void:
	if slot_index < 0 or slot_index >= MAX_SAVE_SLOTS:
		return
	log_event("save_slot_deleted", {"slot": slot_index})
	save_slots[slot_index] = _empty_save_slot(slot_index)
	if active_save_slot == slot_index:
		active_save_slot = _first_available_save_slot()
	_write_saves()


func get_save_slots() -> Array:
	_ensure_save_slots()
	return save_slots.duplicate(true)


func is_tutorial_completed() -> bool:
	return bool(_active_save().get("tutorial_completed", false))


func is_level_completed(level_id: String) -> bool:
	var levels: Dictionary = _active_save().get("levels_completed", {})
	return bool(levels.get(level_id, false))


func is_boss_completed(level_id: String) -> bool:
	var bosses: Dictionary = _active_save().get("bosses_completed", {})
	return bool(bosses.get(level_id, false))


func is_level_unlocked(level_index: int) -> bool:
	if level_index <= 0:
		return is_tutorial_completed()
	var previous_level: Dictionary = LEVELS[level_index - 1]
	return is_boss_completed(String(previous_level.get("id", "")))


func is_boss_unlocked(level_index: int) -> bool:
	if level_index < 0 or level_index >= LEVELS.size():
		return false
	var level_data: Dictionary = LEVELS[level_index]
	return is_level_completed(String(level_data.get("id", "")))


func get_progress_percent() -> int:
	var completed := 0
	if is_tutorial_completed():
		completed += 1
	for level_variant in LEVELS:
		var level_data: Dictionary = level_variant
		var level_id := String(level_data.get("id", ""))
		if is_level_completed(level_id):
			completed += 1
		if is_boss_completed(level_id):
			completed += 1
	return int(round(float(completed) / 11.0 * 100.0))


func get_inventory_items() -> Array:
	var slot := _active_save()
	var items: Array = slot.get("inventory", [])
	return items.duplicate(true)


func add_inventory_hint(title: String, description: String) -> void:
	log_event("inventory_hint_collected", {"title": title})
	var slot := _active_save()
	slot["empty"] = false
	var items: Array = slot.get("inventory", [])
	items.append({
		"title": title,
		"description": description,
		"found_at": Time.get_unix_time_from_system()
	})
	slot["inventory"] = items
	_touch_slot(slot)
	_write_saves()


func set_volume(value: float) -> void:
	settings["volume"] = clampf(value, 0.0, 1.0)
	log_event("settings_volume_changed", {"volume": settings["volume"]})
	apply_settings()
	_write_settings()


func set_generation_mode(mode: String) -> void:
	settings["generation_mode"] = mode if mode == "patterns" else "ai"
	log_event("settings_generation_mode_changed", {"mode": settings["generation_mode"]})
	_write_settings()


func set_difficulty(difficulty: String) -> void:
	if difficulty in ["easy", "normal", "hard"]:
		settings["difficulty"] = difficulty
		log_event("settings_difficulty_changed", {"difficulty": difficulty})
	_write_settings()


func set_hf_api_key(api_key: String) -> void:
	settings["hf_api_key"] = api_key.strip_edges()
	log_event("settings_hf_key_changed", {"has_key": not String(settings["hf_api_key"]).is_empty()})
	_write_settings()


func get_generation_mode() -> String:
	return String(settings.get("generation_mode", "ai"))


func get_initial_difficulty() -> String:
	return String(settings.get("difficulty", "normal"))


func get_hf_api_key() -> String:
	return String(settings.get("hf_api_key", ""))


func apply_settings() -> void:
	var volume := float(settings.get("volume", 0.85))
	AudioServer.set_bus_mute(0, volume <= 0.01)
	if volume > 0.01:
		AudioServer.set_bus_volume_db(0, linear_to_db(volume))


func reset_settings() -> void:
	settings = {
		"volume": 0.85,
		"generation_mode": "ai",
		"difficulty": "normal",
		"hf_api_key": ""
	}
	log_event("settings_reset")
	apply_settings()
	_write_settings()


func log_event(event_type: String, metadata: Dictionary = {}) -> void:
	if event_type.strip_edges().is_empty():
		return
	var timestamp := Time.get_unix_time_from_system()
	var slot := _active_save()
	var stage: Dictionary = slot.get("current_stage", {"type": pending_stage_type, "level_id": pending_level_id})
	var record := {
		"user_id": "anon_local",
		"session_id": session_id,
		"save_slot": active_save_slot,
		"event_type": event_type,
		"stage_type": String(stage.get("type", pending_stage_type)),
		"level_id": String(stage.get("level_id", pending_level_id)),
		"progress_percent": int(slot.get("progress_percent", 0)),
		"timestamp_unix": timestamp,
		"metadata": metadata,
	}
	_write_local_analytics(record)
	var api_client := get_node_or_null("/root/CodeApiClient")
	if api_client != null and api_client.has_method("send_log_event"):
		api_client.call("send_log_event", record)


func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_FILE):
		_write_settings()
		return
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		var parsed_settings: Dictionary = parsed
		settings.merge(parsed_settings, true)


func _load_saves() -> void:
	save_slots = []
	if FileAccess.file_exists(SAVE_FILE):
		var file := FileAccess.open(SAVE_FILE, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if typeof(parsed) == TYPE_DICTIONARY:
				var parsed_saves: Dictionary = parsed
				active_save_slot = int(parsed_saves.get("active_slot", 0))
				var raw_slots: Array = parsed_saves.get("slots", [])
				for slot_variant in raw_slots:
					if typeof(slot_variant) == TYPE_DICTIONARY:
						var loaded_slot: Dictionary = slot_variant
						save_slots.append(loaded_slot)
	_ensure_save_slots()
	active_save_slot = clampi(active_save_slot, 0, MAX_SAVE_SLOTS - 1)
	_write_saves()


func _ensure_save_slots() -> void:
	while save_slots.size() < MAX_SAVE_SLOTS:
		save_slots.append(_empty_save_slot(save_slots.size()))
	if save_slots.size() > MAX_SAVE_SLOTS:
		save_slots.resize(MAX_SAVE_SLOTS)
	for index in range(save_slots.size()):
		save_slots[index]["slot"] = index


func _first_available_save_slot() -> int:
	for index in range(save_slots.size()):
		if not bool(save_slots[index].get("empty", true)):
			return index
	return 0


func _active_save() -> Dictionary:
	_ensure_save_slots()
	return save_slots[active_save_slot]


func _update_current_stage(stage_type: String, level_id: String) -> void:
	var slot := _active_save()
	slot["empty"] = false
	slot["current_stage"] = {"type": stage_type, "level_id": level_id}
	_touch_slot(slot)
	_write_saves()


func _touch_slot(slot: Dictionary) -> void:
	slot["updated_at"] = Time.get_unix_time_from_system()
	slot["progress_percent"] = get_progress_percent()


func _write_settings() -> void:
	var file := FileAccess.open(SETTINGS_FILE, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(settings, "\t"))


func _write_saves() -> void:
	_ensure_save_slots()
	var file := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(JSON.stringify({
		"active_slot": active_save_slot,
		"slots": save_slots
	}, "\t"))


func _write_local_analytics(record: Dictionary) -> void:
	var file := FileAccess.open(ANALYTICS_FILE, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(ANALYTICS_FILE, FileAccess.WRITE)
	if file == null:
		return
	file.seek_end()
	file.store_line(JSON.stringify(record))


func _new_save_slot(slot_index: int, empty: bool) -> Dictionary:
	return {
		"slot": slot_index,
		"empty": empty,
		"tutorial_completed": false,
		"levels_completed": {},
		"bosses_completed": {},
		"inventory": [],
		"current_stage": {"type": "tutorial", "level_id": ""},
		"progress_percent": 0,
		"updated_at": Time.get_unix_time_from_system()
	}


func _empty_save_slot(slot_index: int) -> Dictionary:
	var slot := _new_save_slot(slot_index, true)
	slot["updated_at"] = 0
	return slot
