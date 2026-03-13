extends CanvasLayer

signal interaction_resolved(success: bool, result: Dictionary)
signal terminal_closed

@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var status_label: Label = $Panel/Margin/VBox/Status
@onready var timer_label: Label = $Panel/Margin/VBox/TimerLabel
@onready var code_editor: TextEdit = $Panel/Margin/VBox/CodeEditor
@onready var run_button: Button = $Panel/Margin/VBox/Actions/RunButton
@onready var close_button: Button = $Panel/Margin/VBox/Actions/CloseButton

var _active_payload: Dictionary = {}
var _time_left := 0.0
var _request_in_flight := false
var _timer_enabled := true
var _interaction_type := "combat"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hide_terminal()
	run_button.pressed.connect(_on_run_pressed)
	close_button.pressed.connect(_on_close_pressed)
	CodeApiClient.combat_result_received.connect(_on_combat_result_received)
	CodeApiClient.request_failed.connect(_on_request_failed)


func open_terminal(payload: Dictionary) -> void:
	_active_payload = payload.duplicate(true)
	_interaction_type = String(payload.get("interaction_type", "combat"))
	_timer_enabled = bool(payload.get("timer_enabled", true))
	_time_left = float(payload.get("time_limit", 180))
	_request_in_flight = false
	code_editor.editable = true
	run_button.disabled = false
	close_button.disabled = false
	title_label.text = String(payload.get("title", "Combat Terminal"))
	code_editor.text = _default_snippet_for_interaction()
	status_label.text = String(payload.get("status_text", "Encounter ready."))
	timer_label.visible = _timer_enabled
	if _timer_enabled:
		timer_label.text = "Time: %d" % int(_time_left)
	panel.visible = true
	code_editor.grab_focus()


func hide_terminal() -> void:
	panel.visible = false


func _process(delta: float) -> void:
	if not panel.visible or _request_in_flight or not _timer_enabled:
		return

	_time_left = max(_time_left - delta, 0.0)
	timer_label.text = "Time: %d" % int(ceil(_time_left))
	if _time_left <= 0.0:
		status_label.text = "Time is up. The enemy strikes first."
		interaction_resolved.emit(false, {"interaction_type": _interaction_type, "attack_mode": String(_active_payload.get("attack_mode", "melee")), "success": false, "errors": ["time limit reached"], "damage_to_player": 25})
		hide_terminal()


func _on_run_pressed() -> void:
	if _request_in_flight:
		return

	_request_in_flight = true
	run_button.disabled = true
	status_label.text = "Checking code..."

	var payload := {
		"user_id": "anon_local",
		"level_theme": _active_payload.get("level_theme", "variables"),
		"difficulty": _active_payload.get("difficulty", "easy"),
		"code": code_editor.text,
		"time_taken_seconds": int(_active_payload.get("time_limit", 180) - _time_left),
	}
	CodeApiClient.validate_combat(payload)


func _on_close_pressed() -> void:
	status_label.text = "Encounter closed."
	hide_terminal()
	terminal_closed.emit()


func _on_combat_result_received(result: Dictionary) -> void:
	_request_in_flight = false
	run_button.disabled = false

	if result.get("success", false):
		code_editor.editable = false
		run_button.disabled = true
		close_button.disabled = true
		status_label.text = String(_active_payload.get("success_text", "Success."))
		var emitted_result: Dictionary = result.duplicate(true)
		emitted_result["interaction_type"] = _interaction_type
		emitted_result["attack_mode"] = String(_active_payload.get("attack_mode", "melee"))
		if _interaction_type == "altar":
			emitted_result["weapon_summary"] = _build_weapon_summary(code_editor.text)
		await get_tree().create_timer(1.2, true).timeout
		interaction_resolved.emit(true, emitted_result)
		hide_terminal()
		return

	var errors := PackedStringArray(result.get("errors", []))
	status_label.text = "%s: %s" % [String(_active_payload.get("failure_text", "Failed")), ", ".join(errors)]
	if _interaction_type == "chest" or _interaction_type == "altar":
		run_button.disabled = false
		return

	await get_tree().create_timer(1.2, true).timeout
	interaction_resolved.emit(false, {"interaction_type": _interaction_type, "attack_mode": String(_active_payload.get("attack_mode", "melee")), "success": false, "errors": result.get("errors", []), "damage_to_player": 20})
	hide_terminal()


func _on_request_failed(message: String) -> void:
	_request_in_flight = false
	run_button.disabled = false
	status_label.text = message


func _default_snippet_for_interaction() -> String:
	match _interaction_type:
		"altar":
			return "weapon_type = 'melee'\nweapon_damage = 15\nweapon_effect = 'fire'"
		_:
			return _default_snippet_for_theme(String(_active_payload.get("level_theme", "variables")))


func _build_weapon_summary(code: String) -> String:
	var lines := code.split("\n", false)
	var summary_parts: Array[String] = []
	for line in lines:
		var stripped := line.strip_edges()
		if stripped.is_empty():
			continue
		summary_parts.append(stripped)
		if summary_parts.size() == 2:
			break
	if summary_parts.is_empty():
		return "Forged a standard glitch blade."
	return "Forged weapon: %s" % ", ".join(summary_parts)


func _default_snippet_for_theme(theme: String) -> String:
	match theme:
		"conditions":
			return "if enemy_distance < 50:\n    attack = 'heavy'\nelse:\n    attack = 'light'"
		"loops":
			return "for step in range(3):\n    attack(step)"
		"functions":
			return "def combo():\n    return 'slash'\n\ncombo()"
		"integration":
			return "stamina = 3\nif stamina > 0:\n    for _i in range(stamina):\n        print('strike')"
		_:
			return "damage = 15\nspeed = 4"
