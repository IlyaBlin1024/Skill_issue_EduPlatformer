extends CanvasLayer

signal interaction_resolved(success: bool, result: Dictionary)
signal terminal_closed
signal task_loaded
signal hint_loaded

@onready var explanation_backdrop: ColorRect = $ExplanationBackdrop
@onready var panel: PanelContainer = $Panel
@onready var title_label: Label = $Panel/Margin/VBox/Title
@onready var source_label: Label = $Panel/Margin/VBox/SourceLabel
@onready var status_scroll: ScrollContainer = $Panel/Margin/VBox/StatusScroll
@onready var status_label: RichTextLabel = $Panel/Margin/VBox/StatusScroll/Status
@onready var timer_label: Label = $Panel/Margin/VBox/TimerLabel
@onready var code_editor: TextEdit = $Panel/Margin/VBox/CodeEditor
@onready var hint_scroll: ScrollContainer = $Panel/Margin/VBox/HintScroll
@onready var hint_label: Label = $Panel/Margin/VBox/HintScroll/HintLabel
@onready var run_button: Button = $Panel/Margin/VBox/Actions/RunButton
@onready var hint_button: Button = $Panel/Margin/VBox/Actions/HintButton
@onready var explanation_button: Button = $Panel/Margin/VBox/Actions/ExplanationButton
@onready var close_button: Button = $Panel/Margin/VBox/Actions/CloseButton
@onready var help_panel: PanelContainer = $HelpPanel
@onready var help_close_button: Button = $HelpPanel/Margin/VBox/Header/HelpCloseButton
@onready var help_title_label: Label = $HelpPanel/Margin/VBox/Header/HelpTitle
@onready var help_theme_label: Label = $HelpPanel/Margin/VBox/ThemeLabel
@onready var help_scroll: ScrollContainer = $HelpPanel/Margin/VBox/Scroll
@onready var help_theme_body_label: RichTextLabel = $HelpPanel/Margin/VBox/Scroll/ScrollVBox/ThemeBody
@onready var help_language_label: Label = $HelpPanel/Margin/VBox/Scroll/ScrollVBox/LanguageLabel
@onready var help_rules_label: Label = $HelpPanel/Margin/VBox/Scroll/ScrollVBox/RulesLabel
@onready var help_example_label: RichTextLabel = $HelpPanel/Margin/VBox/Scroll/ScrollVBox/ExampleLabel
@onready var scroll_up_button: Button = $HelpPanel/Margin/VBox/ScrollButtons/ScrollUpButton
@onready var scroll_down_button: Button = $HelpPanel/Margin/VBox/ScrollButtons/ScrollDownButton

var _active_payload: Dictionary = {}
var _time_left := 0.0
var _request_in_flight := false
var _hint_request_in_flight := false
var _task_request_in_flight := false
var _timer_enabled := true
var _task_ready := false
var _task_generation_attempts := 0
var _interaction_type := "combat"
var _active_language := "python"
var _help_panel_open := false
var _timer_paused_by_help := false
var _hint_request_count := 0
var _explanation_open_count := 0
var _terminal_session_id := ""
var _terminal_open_tick_msec := 0
var _task_generation_start_tick_msec := 0
var _task_generation_seconds := 0.0
var _explanation_open_tick_msec := 0
var _explanation_read_seconds := 0.0
var _run_count := 0
var _terminal_success := false

const MAX_TASK_GENERATION_RETRIES := 2
const HIGHLIGHT_ALIASES := {
	"damage": ["damage", "attack damage", "attack power", "strike power", "hit power"],
	"speed": ["speed", "movement speed", "move speed", "dash speed", "mobility"],
	"guard_window": ["guard window", "parry window", "block timing", "deflect timing"],
	"hp": ["hp", "health", "integrity", "health pool"],
	"shield": ["shield", "barrier", "shield durability", "barrier strength"],
	"projectile_speed": ["projectile speed", "shot speed", "bolt speed", "volley speed"],
	"ranged_damage": ["ranged damage", "projectile damage", "shot damage", "volley damage"],
	"melee_damage": ["melee damage", "blade damage", "slash damage", "sword damage"],
	"recovery": ["recovery", "recovery timing", "cooldown"],
	"stamina": ["stamina", "energy", "energy reserve"],
}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	layer = 100
	hide_terminal()
	run_button.pressed.connect(_on_run_pressed)
	hint_button.pressed.connect(_on_hint_pressed)
	explanation_button.pressed.connect(_on_explanation_pressed)
	help_close_button.pressed.connect(_close_explanation_panel)
	close_button.pressed.connect(_on_close_pressed)
	scroll_up_button.pressed.connect(_on_explanation_scroll_up_pressed)
	scroll_down_button.pressed.connect(_on_explanation_scroll_down_pressed)
	CodeApiClient.validation_result_received.connect(_on_combat_result_received)
	CodeApiClient.hint_result_received.connect(_on_hint_result_received)
	CodeApiClient.task_result_received.connect(_on_task_result_received)
	CodeApiClient.request_failed.connect(_on_request_failed)


func open_terminal(payload: Dictionary) -> void:
	_active_payload = payload.duplicate(true)
	_interaction_type = String(payload.get("interaction_type", "combat"))
	_timer_enabled = bool(payload.get("timer_enabled", true))
	_time_left = float(payload.get("time_limit", 180))
	_request_in_flight = false
	_hint_request_in_flight = false
	_task_request_in_flight = false
	_task_ready = false
	_task_generation_attempts = 0
	_hint_request_count = 0
	_explanation_open_count = 0
	_terminal_session_id = "%d_%d" % [Time.get_ticks_msec(), randi()]
	_terminal_open_tick_msec = Time.get_ticks_msec()
	_task_generation_start_tick_msec = 0
	_task_generation_seconds = 0.0
	_explanation_open_tick_msec = 0
	_explanation_read_seconds = 0.0
	_run_count = 0
	_terminal_success = false
	GameState.log_event("terminal_opened", _terminal_log_metadata())
	_active_language = "python"
	_help_panel_open = false
	_timer_paused_by_help = false
	code_editor.editable = not _help_panel_open
	run_button.disabled = false
	hint_button.disabled = false
	explanation_button.disabled = false
	close_button.disabled = true
	title_label.text = String(payload.get("title", "Combat Terminal"))
	source_label.text = "Source: loading..."
	code_editor.text = ""
	_set_rich_text(status_label, String(payload.get("status_text", "Encounter ready.")))
	hint_label.text = ""
	hint_label.visible = false
	hint_scroll.visible = false
	hint_button.visible = true
	explanation_backdrop.visible = false
	help_panel.visible = false
	explanation_button.text = "Explonation"
	help_scroll.scroll_vertical = 0
	status_scroll.scroll_vertical = 0
	hint_scroll.scroll_vertical = 0
	_update_help_panel()
	timer_label.visible = _timer_enabled
	if _timer_enabled:
		timer_label.text = "Time: %d" % int(_time_left)
	if get_parent() != null:
		get_parent().move_child(self, get_parent().get_child_count() - 1)
	panel.visible = true
	code_editor.grab_focus()
	_request_generated_task()


func hide_terminal() -> void:
	explanation_backdrop.visible = false
	panel.visible = false
	help_panel.visible = false
	_help_panel_open = false
	_timer_paused_by_help = false
	explanation_button.text = "Explonation"
	help_scroll.scroll_vertical = 0
	status_scroll.scroll_vertical = 0
	hint_scroll.scroll_vertical = 0


func is_terminal_open() -> bool:
	return panel.visible or help_panel.visible or explanation_backdrop.visible


func _process(delta: float) -> void:
	if not panel.visible or _request_in_flight or not _timer_enabled:
		return
	if _timer_paused_by_help or _task_request_in_flight or not _task_ready:
		return

	_time_left = max(_time_left - delta, 0.0)
	timer_label.text = "Time: %d" % int(ceil(_time_left))
	if _time_left <= 0.0:
		_set_rich_text(status_label, "Time is up. The enemy strikes first.")
		GameState.log_event("terminal_time_expired", _terminal_log_metadata({"run_count": _run_count}))
		interaction_resolved.emit(
			false,
			{
				"interaction_type": _interaction_type,
				"attack_mode": String(_active_payload.get("attack_mode", "melee")),
				"success": false,
				"errors": ["time limit reached"],
				"hints": ["The timer expired. Try a smaller valid snippet first."],
				"damage_to_player": 25,
				"suggested_difficulty": _fallback_suggested_difficulty(String(_active_payload.get("difficulty", "easy")))
			}
		)
		hide_terminal()


func _on_run_pressed() -> void:
	if _request_in_flight:
		return
	if _task_request_in_flight:
		_set_rich_text(status_label, "Task is still loading...")
		return

	_capture_explanation_read_time()
	_run_count += 1
	GameState.log_event("code_run_requested", _terminal_log_metadata({"code_length": code_editor.text.length()}))
	_request_in_flight = true
	run_button.disabled = true
	explanation_button.disabled = true
	_set_rich_text(status_label, "Checking code...")

	var tutorial_expected_code: String = String(_active_payload.get("tutorial_force_success_code", ""))
	if not tutorial_expected_code.is_empty():
		_resolve_tutorial_submission(tutorial_expected_code)
		return

	var stage: Dictionary = GameState.get_current_stage()
	var payload := {
		"user_id": "anon_local",
		"interaction_type": _interaction_type,
		"stage_type": String(stage.get("type", "")),
		"level_id": String(stage.get("level_id", "")),
		"level_theme": _active_payload.get("level_theme", "variables"),
		"difficulty": _active_payload.get("difficulty", "easy"),
		"language": _active_language,
		"encounter_name": _active_payload.get("encounter_name", ""),
		"encounter_style": _active_payload.get("encounter_style", ""),
		"gameplay_context": _active_payload.get("gameplay_context", _active_payload.get("status_text", "")),
		"structure_focus": _active_payload.get("structure_focus", ""),
		"boss_mechanic": _active_payload.get("boss_mechanic", ""),
		"task_prompt": _active_payload.get("generated_prompt", ""),
		"keywords": _active_payload.get("keywords", []),
		"syntax_rules": _active_payload.get("syntax_rules", []),
		"fallback_hints": _active_payload.get("fallback_hints", []),
		"validation_targets": _active_payload.get("validation_targets", []),
		"generation_source": _active_payload.get("generation_source", ""),
		"generation_detail": _active_payload.get("generation_detail", ""),
		"pattern_id": _active_payload.get("pattern_id", ""),
		"terminal_session_id": _terminal_session_id,
		"attempt_number": _run_count,
		"task_generation_seconds": _task_generation_seconds,
		"hint_used": _hint_request_count > 0,
		"explanation_used": _explanation_open_count > 0,
		"hint_request_count": _hint_request_count,
		"explanation_open_count": _explanation_open_count,
		"explanation_read_seconds": _explanation_read_seconds,
		"code": code_editor.text,
		"example_code": _active_payload.get("example_code", ""),
		"time_taken_seconds": int(_active_payload.get("time_limit", 180) - _time_left),
	}
	CodeApiClient.validate_interaction(payload)


func _on_hint_pressed() -> void:
	if _hint_request_in_flight or _request_in_flight:
		return
	if _task_request_in_flight:
		_set_rich_text(status_label, "Task is still loading...")
		return
	_hint_request_count += 1
	GameState.log_event("hint_requested", _terminal_log_metadata())
	_hint_request_in_flight = true
	hint_button.disabled = true
	explanation_button.disabled = true
	hint_label.visible = true
	hint_label.text = "Requesting hint..."
	var tutorial_hints_variant: Variant = _active_payload.get("tutorial_hint_override", null)
	var tutorial_hints: Array = tutorial_hints_variant if typeof(tutorial_hints_variant) == TYPE_ARRAY else []
	if not tutorial_hints.is_empty():
		_hint_request_in_flight = false
		hint_button.disabled = _help_panel_open
		explanation_button.disabled = false
		_show_hints(tutorial_hints)
		hint_loaded.emit()
		return
	if bool(_active_payload.get("tutorial_mode", false)):
		_hint_request_in_flight = false
		hint_button.disabled = _help_panel_open
		explanation_button.disabled = false
		_show_hints(_active_payload.get("fallback_hints", ["Read the task text and turn the requested stat words into assignments."]))
		hint_loaded.emit()
		return
	var payload := {
		"user_id": "anon_local",
		"interaction_type": _interaction_type,
		"level_theme": _active_payload.get("level_theme", "variables"),
		"difficulty": _active_payload.get("difficulty", "easy"),
		"language": _active_language,
		"encounter_name": _active_payload.get("encounter_name", ""),
		"encounter_style": _active_payload.get("encounter_style", ""),
		"gameplay_context": _active_payload.get("gameplay_context", _active_payload.get("status_text", "")),
		"structure_focus": _active_payload.get("structure_focus", ""),
		"boss_mechanic": _active_payload.get("boss_mechanic", ""),
		"task_prompt": _active_payload.get("generated_prompt", ""),
		"keywords": _active_payload.get("keywords", []),
		"validation_targets": _active_payload.get("validation_targets", []),
		"fallback_hints": _active_payload.get("fallback_hints", []),
		"code": code_editor.text,
	}
	CodeApiClient.request_hints(payload)


func _on_close_pressed() -> void:
	_capture_explanation_read_time()
	var close_event := "terminal_closed" if _terminal_success else "terminal_closed_without_success"
	GameState.log_event(close_event, _terminal_log_metadata({"run_count": _run_count}))
	_set_rich_text(status_label, "Encounter closed.")
	hide_terminal()
	terminal_closed.emit()


func _on_combat_result_received(result: Dictionary) -> void:
	_request_in_flight = false
	run_button.disabled = _help_panel_open
	explanation_button.disabled = false

	if result.get("success", false):
		_terminal_success = true
		GameState.log_event("code_validation_succeeded", _terminal_log_metadata({"attempt_id": String(result.get("attempt_id", "")), "attempt_number": _run_count}))
		code_editor.editable = false
		run_button.disabled = true
		close_button.disabled = true
		_set_rich_text(status_label, String(_active_payload.get("success_text", "Success.")))
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
	GameState.log_event("code_validation_failed", _terminal_log_metadata({"errors": result.get("errors", []), "attempt_id": String(result.get("attempt_id", "")), "attempt_number": _run_count}))
	_set_rich_text(status_label, "%s: %s" % [String(_active_payload.get("failure_text", "Failed")), ", ".join(errors)])
	_show_hints(result.get("hints", []))
	if _interaction_type == "chest" or _interaction_type == "altar":
		run_button.disabled = false
		return

	await get_tree().create_timer(1.2, true).timeout
	interaction_resolved.emit(
		false,
		{
			"interaction_type": _interaction_type,
			"attack_mode": String(_active_payload.get("attack_mode", "melee")),
			"success": false,
			"errors": result.get("errors", []),
			"hints": result.get("hints", []),
			"damage_to_player": 20,
			"suggested_difficulty": String(result.get("suggested_difficulty", _active_payload.get("difficulty", "easy"))),
			"attempt_id": String(result.get("attempt_id", ""))
		}
	)
	hide_terminal()


func _on_hint_result_received(result: Dictionary) -> void:
	_hint_request_in_flight = false
	hint_button.disabled = _help_panel_open
	explanation_button.disabled = false
	_show_hints(result.get("hints", []))
	hint_loaded.emit()


func _on_task_result_received(result: Dictionary) -> void:
	_task_request_in_flight = false
	_task_ready = true
	if _task_generation_start_tick_msec > 0:
		_task_generation_seconds = float(Time.get_ticks_msec() - _task_generation_start_tick_msec) / 1000.0
	if not panel.visible:
		return
	if String(result.get("interaction_type", "")) != _interaction_type:
		return
	GameState.log_event("task_loaded", _terminal_log_metadata({
		"source": String(result.get("generation_source", "")),
		"pattern_id": String(result.get("pattern_id", "")),
		"task_generation_seconds": _task_generation_seconds,
	}))
	var generated_title: String = String(result.get("title", "")).strip_edges()
	var generated_prompt: String = String(result.get("prompt", "")).strip_edges()
	var gameplay_effect: String = String(result.get("gameplay_effect", "")).strip_edges()
	var generation_source: String = String(result.get("generation_source", "fallback")).strip_edges().to_lower()
	var generation_detail: String = String(result.get("generation_detail", "")).strip_edges()
	var difficulty_text: String = String(result.get("difficulty", _active_payload.get("difficulty", "easy")))
	var syntax_rules_variant: Variant = result.get("syntax_rules", [])
	var syntax_rules: Array = syntax_rules_variant if typeof(syntax_rules_variant) == TYPE_ARRAY else []
	var example_code: String = String(result.get("example_code", "")).strip_edges()
	var result_keywords: Array[String] = _normalize_string_array(result.get("keywords", []))
	var result_targets: Array[String] = _normalize_string_array(result.get("validation_targets", []))
	_active_language = "python"
	if not generated_title.is_empty():
		title_label.text = generated_title
	source_label.text = _format_generation_source_label(generation_source, generation_detail)
	_active_payload["keywords"] = result_keywords
	_active_payload["validation_targets"] = result_targets
	var highlight_terms: Array[String] = _build_highlight_terms(result_keywords, result_targets)
	if not generated_prompt.is_empty():
		_set_rich_text(
			status_label,
			_render_keyword_text(generated_prompt, highlight_terms)
		)
	hint_label.visible = false
	hint_label.text = ""
	_active_payload["difficulty"] = difficulty_text
	_active_payload["generated_prompt"] = generated_prompt
	_active_payload["gameplay_effect"] = gameplay_effect
	_active_payload["generation_source"] = generation_source
	_active_payload["generation_detail"] = generation_detail
	_active_payload["syntax_rules"] = syntax_rules
	_active_payload["explanation_title"] = String(result.get("explanation_title", "")).strip_edges()
	_active_payload["explanation_body"] = String(result.get("explanation_body", "")).strip_edges()
	_active_payload["explanation_rules"] = result.get("explanation_rules", [])
	_active_payload["explanation_prompt"] = String(result.get("explanation_prompt", "")).strip_edges()
	_active_payload["example_code"] = example_code
	_active_payload["fallback_hints"] = result.get("fallback_hints", [])
	_active_payload["pattern_id"] = String(result.get("pattern_id", "")).strip_edges()
	_active_payload["language"] = _active_language
	_update_help_panel()
	code_editor.editable = not _help_panel_open
	var tutorial_auto_code: String = String(_active_payload.get("tutorial_auto_code", ""))
	if not tutorial_auto_code.is_empty():
		code_editor.text = tutorial_auto_code
	run_button.disabled = _help_panel_open
	hint_button.disabled = _help_panel_open
	explanation_button.disabled = false
	close_button.disabled = false
	task_loaded.emit()


func _show_hints(hints_variant: Variant) -> void:
	if typeof(hints_variant) != TYPE_ARRAY:
		hint_scroll.visible = false
		hint_label.visible = false
		hint_label.text = ""
		return
	var hints: Array = hints_variant
	if hints.is_empty():
		hint_scroll.visible = false
		hint_label.visible = false
		hint_label.text = ""
		return
	var rendered_hints: PackedStringArray = []
	for hint_variant in hints:
		rendered_hints.append("- %s" % String(hint_variant))
	hint_scroll.visible = true
	hint_label.visible = true
	hint_label.text = "Hints:\n%s" % "\n".join(rendered_hints)
	hint_scroll.scroll_vertical = 0


func _on_request_failed(message: String) -> void:
	GameState.log_event("backend_request_failed", _terminal_log_metadata({"message": message}))
	_request_in_flight = false
	_hint_request_in_flight = false
	var was_waiting_for_task: bool = _task_request_in_flight or not _task_ready
	_task_request_in_flight = false
	if was_waiting_for_task and panel.visible:
		if _task_generation_attempts < MAX_TASK_GENERATION_RETRIES:
			_set_rich_text(status_label, "%s Retrying..." % message)
			_request_generated_task()
			return
		_set_rich_text(status_label, "Backend generation is unavailable. Loading a local pattern...")
		call_deferred("_deliver_preset_task", _local_fallback_task(message))
		return
	run_button.disabled = _help_panel_open
	hint_button.disabled = _help_panel_open
	explanation_button.disabled = false
	_set_rich_text(status_label, message)


func _format_generation_source_label(generation_source: String, generation_detail: String) -> String:
	match generation_source:
		"ai":
			return "Source: AI Generated"
		"fallback":
			if generation_detail.is_empty():
				return "Source: Fallback Pattern"
			return "Source: Fallback Pattern (%s)" % generation_detail
		_:
			if generation_detail.is_empty():
				return "Source: %s" % generation_source.capitalize()
			return "Source: %s (%s)" % [generation_source.capitalize(), generation_detail]


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
func _fallback_suggested_difficulty(current_difficulty: String) -> String:
	match current_difficulty:
		"hard":
			return "normal"
		"normal":
			return "easy"
		_:
			return "easy"


func _request_generated_task() -> void:
	_task_generation_attempts += 1
	_task_generation_start_tick_msec = Time.get_ticks_msec()
	_task_request_in_flight = true
	_task_ready = false
	run_button.disabled = true
	hint_button.disabled = true
	explanation_button.disabled = true
	_set_rich_text(status_label, "Generating task...")
	GameState.log_event("task_generation_requested", _terminal_log_metadata({"attempt": _task_generation_attempts}))
	var preset_task_variant: Variant = _active_payload.get("preset_task", null)
	if typeof(preset_task_variant) == TYPE_DICTIONARY:
		call_deferred("_deliver_preset_task", (preset_task_variant as Dictionary).duplicate(true))
		return
	var payload := {
		"user_id": "anon_local",
		"interaction_type": _interaction_type,
		"level_theme": _active_payload.get("level_theme", "variables"),
		"language": _active_language,
		"encounter_name": _active_payload.get("encounter_name", ""),
		"encounter_style": _active_payload.get("encounter_style", ""),
		"gameplay_context": _active_payload.get("gameplay_context", _active_payload.get("status_text", "")),
		"structure_focus": _active_payload.get("structure_focus", ""),
		"boss_mechanic": _active_payload.get("boss_mechanic", ""),
		"tutorial_mode": bool(_active_payload.get("tutorial_mode", false)),
	}
	CodeApiClient.request_task(payload)


func tutorial_request_hint() -> void:
	_on_hint_pressed()


func tutorial_toggle_explanation() -> void:
	_on_explanation_pressed()


func tutorial_press_run() -> void:
	_on_run_pressed()


func tutorial_set_code_text(text: String) -> void:
	code_editor.text = text


func tutorial_get_targets() -> Dictionary:
	return {
		"title": title_label,
		"source": source_label,
		"status": status_label,
		"timer": timer_label,
		"code": code_editor,
		"hint_panel": hint_scroll,
		"hint_text": hint_label,
		"run_button": run_button,
		"hint_button": hint_button,
		"explanation_button": explanation_button,
		"close_button": close_button,
		"help_panel": help_panel,
		"help_body": help_theme_body_label,
		"help_rules": help_rules_label,
		"help_example": help_example_label,
	}


func _deliver_preset_task(preset_task: Dictionary) -> void:
	await get_tree().create_timer(0.45, true).timeout
	if not panel.visible:
		return
	var result: Dictionary = preset_task.duplicate(true)
	result["interaction_type"] = String(result.get("interaction_type", _interaction_type))
	result["level_theme"] = String(result.get("level_theme", _active_payload.get("level_theme", "variables")))
	result["difficulty"] = String(result.get("difficulty", _active_payload.get("difficulty", "easy")))
	result["language"] = String(result.get("language", _active_language))
	result["generation_source"] = String(result.get("generation_source", "tutorial"))
	result["generation_detail"] = String(result.get("generation_detail", "preset tutorial task"))
	_on_task_result_received(result)


func _local_fallback_task(detail: String) -> Dictionary:
	var theme: String = String(_active_payload.get("level_theme", "variables"))
	var encounter_name: String = String(_active_payload.get("encounter_name", "Training Target"))
	var interaction_label: String = _interaction_type.capitalize()
	var keywords: Array[String] = ["damage", "speed", "guard window"]
	var validation_targets: Array[String] = ["damage", "speed", "guard_window"]
	var prompt := "Assign clear values for damage, speed, and guard window so the knight is ready for %s." % encounter_name
	var example_code := "damage = 12\nspeed = 4\nguard_window = 2"
	var syntax_rules: Array[String] = ["Use assignments only.", "Keep one concept per line.", "Use readable variable names."]
	var explanation_title := "Variables"
	var explanation_body := "Variables store combat values. In this fallback task, each line should assign one useful gameplay stat."
	var explanation_prompt := "Read the stat words in the task, then write one assignment for each requested stat."
	var fallback_hints: Array[String] = [
		"Write one line for damage, one for speed, and one for guard window.",
		"Similar readable variable names are accepted if they clearly match the task.",
	]
	match theme:
		"conditions":
			keywords = ["if", "else", "enemy distance", "attack", "guard"]
			validation_targets = ["if", "else", "enemy_distance", "attack", "guard"]
			prompt = "Use if/else to choose attack when %s is open and guard otherwise." % encounter_name
			example_code = "if enemy_open:\n    action = 'attack'\nelse:\n    action = 'guard'"
			syntax_rules = ["Use one if/else branch.", "Put a useful action in each branch.", "Keep the branch short."]
			explanation_title = "If / Else"
			explanation_body = "Conditions choose between actions. The task asks you to connect a combat state to a safe response."
			explanation_prompt = "Find the state clue and the two possible actions, then translate them into one branch."
			fallback_hints = ["Start with if, then add else.", "Use readable action names connected to the task."]
		"loops":
			keywords = ["loop", "repeat", "range", "attack"]
			validation_targets = ["loop", "range", "attack"]
			prompt = "Write a short loop that repeats a safe attack pattern against %s." % encounter_name
			example_code = "for _ in range(3):\n    attack()"
			syntax_rules = ["Use one loop.", "Keep the loop body short.", "Make the repeat count clear."]
			explanation_title = "Loops"
			explanation_body = "Loops repeat one useful action with a clear stopping rule."
			explanation_prompt = "Find the repeated action and the repeat count, then turn them into one loop."
			fallback_hints = ["Use range for the repeat count.", "The body should contain one combat action."]
		"functions":
			keywords = ["def", "function", "call", "helper"]
			validation_targets = ["def", "call", "helper"]
			prompt = "Define and call one helper function for a safe response to %s." % encounter_name
			example_code = "def safe_response():\n    guard()\n\nsafe_response()"
			syntax_rules = ["Define one function with def.", "Call the function after defining it.", "Keep the helper focused."]
			explanation_title = "Functions"
			explanation_body = "Functions package a tactic into a reusable helper."
			explanation_prompt = "Name the reusable action, define it, then call it once."
			fallback_hints = ["Use def to define the helper.", "Do not forget to call the helper."]
		"integration":
			keywords = ["variable", "if", "loop", "tactic"]
			validation_targets = ["assignment", "if", "loop"]
			prompt = "Combine a stat setup with one tactical decision for %s." % encounter_name
			example_code = "damage = 12\nif enemy_open:\n    attack()"
			syntax_rules = ["Use at least two core constructs.", "Keep the snippet compact.", "Make each part support one tactic."]
			explanation_title = "Integration"
			explanation_body = "Integration combines earlier programming tools into one compact tactic."
			explanation_prompt = "Find the stat clue and the decision clue, then combine them without extra code."
			fallback_hints = ["Use one assignment first.", "Add one decision or repeated action that matches the task."]
	return {
		"interaction_type": _interaction_type,
		"level_theme": theme,
		"difficulty": String(_active_payload.get("difficulty", "easy")),
		"language": "python",
		"generation_source": "fallback",
		"generation_detail": "Local pattern after backend error: %s" % detail,
		"title": "%s: %s" % [interaction_label, encounter_name],
		"prompt": prompt,
		"gameplay_effect": "A correct local fallback snippet unlocks the current interaction.",
		"syntax_rules": syntax_rules,
		"explanation_title": explanation_title,
		"explanation_body": explanation_body,
		"explanation_rules": syntax_rules,
		"explanation_prompt": explanation_prompt,
		"keywords": keywords,
		"example_code": example_code,
		"adaptation_reason": "Local fallback is used only when generated tasks are unavailable.",
		"fallback_hints": fallback_hints,
		"validation_targets": validation_targets,
		"pattern_id": "local_%s_%s" % [theme, _interaction_type],
	}


func _resolve_tutorial_submission(expected_code: String) -> void:
	await get_tree().create_timer(0.2, true).timeout
	_request_in_flight = false
	run_button.disabled = _help_panel_open
	explanation_button.disabled = false
	if _normalize_tutorial_code(code_editor.text) != _normalize_tutorial_code(expected_code):
		GameState.log_event("tutorial_code_validation_failed", _terminal_log_metadata({"attempt_number": _run_count}))
		_set_rich_text(status_label, "%s: %s" % [String(_active_payload.get("failure_text", "Failed")), "tutorial code does not match yet"])
		_show_hints(_active_payload.get("tutorial_failure_hints", ["Use the auto-filled tutorial code as shown, then press Run."]))
		return
	_terminal_success = true
	GameState.log_event("tutorial_code_validation_succeeded", _terminal_log_metadata({"attempt_number": _run_count}))
	code_editor.editable = false
	run_button.disabled = true
	close_button.disabled = true
	_set_rich_text(status_label, String(_active_payload.get("success_text", "Success.")))
	var emitted_result: Dictionary = {
		"success": true,
		"interaction_type": _interaction_type,
		"damage": int(_active_payload.get("tutorial_damage", 0)),
		"errors": [],
		"hints": [],
		"suggested_difficulty": String(_active_payload.get("difficulty", "easy")),
		"resolved_effects": _active_payload.get("tutorial_resolved_effects", {}),
	}
	if _interaction_type == "altar":
		emitted_result["weapon_summary"] = _build_weapon_summary(code_editor.text)
	await get_tree().create_timer(1.0, true).timeout
	interaction_resolved.emit(true, emitted_result)
	hide_terminal()


func _normalize_tutorial_code(value: String) -> String:
	var normalized_parts: PackedStringArray = []
	for raw_line in value.split("\n", false):
		var line: String = raw_line.strip_edges().replace("\t", "").replace(" ", "")
		if not line.is_empty():
			normalized_parts.append(line)
	return "\n".join(normalized_parts)


func _update_help_panel() -> void:
	var explanation_title: String = String(_active_payload.get("explanation_title", "")).strip_edges()
	var explanation_body: String = String(_active_payload.get("explanation_body", "")).strip_edges()
	var explanation_prompt: String = String(_active_payload.get("explanation_prompt", "")).strip_edges()
	var explanation_rules_variant: Variant = _active_payload.get("explanation_rules", [])
	var explanation_rules: Array = explanation_rules_variant if typeof(explanation_rules_variant) == TYPE_ARRAY else []
	var highlight_terms: Array[String] = _get_highlight_terms()
	help_title_label.text = "Theme Explonation"
	var theme_prefix: String = "Boss Theme" if _interaction_type == "boss" else "Theme"
	help_theme_label.text = "%s: %s" % [theme_prefix, explanation_title if not explanation_title.is_empty() else "Loading theme..."]
	var body_text: String = explanation_body
	if not explanation_prompt.is_empty():
		body_text = "How to read the task:\n%s\n\n%s" % [explanation_prompt, body_text]
	if body_text.is_empty():
		body_text = "Explanation is loading for this encounter."
	_set_rich_text(help_theme_body_label, _render_keyword_text(body_text, highlight_terms))
	help_language_label.visible = false
	help_language_label.text = ""
	var rules_text: PackedStringArray = []
	if not explanation_rules.is_empty():
		rules_text.append("Quick rules:")
	var selected_rules: Array = explanation_rules
	for rule_variant in selected_rules:
		rules_text.append("- %s" % String(rule_variant))
	help_rules_label.text = "\n".join(rules_text)
	var example_code: String = String(_active_payload.get("example_code", "")).strip_edges()
	if example_code.is_empty():
		_set_rich_text(help_example_label, "")
	else:
		var example_header: String = "Example:"
		var rendered_example: String = "%s\n\n%s\n\nYou cannot submit this exact example as your final answer." % [
			example_header,
			example_code
		]
		_set_rich_text(help_example_label, _render_keyword_text(rendered_example, highlight_terms))
	help_scroll.scroll_vertical = 0


func _on_explanation_pressed() -> void:
	_help_panel_open = not _help_panel_open
	if _help_panel_open:
		_explanation_open_count += 1
		_explanation_open_tick_msec = Time.get_ticks_msec()
	else:
		_capture_explanation_read_time()
	GameState.log_event("explanation_opened" if _help_panel_open else "explanation_closed", _terminal_log_metadata())
	explanation_backdrop.visible = _help_panel_open
	panel.visible = not _help_panel_open
	help_panel.visible = _help_panel_open
	_timer_paused_by_help = _help_panel_open and _timer_enabled
	code_editor.editable = not _help_panel_open
	run_button.disabled = _help_panel_open or _request_in_flight or _task_request_in_flight
	hint_button.disabled = _help_panel_open or _hint_request_in_flight or _request_in_flight or _task_request_in_flight
	explanation_button.text = "Hide Explonation" if _help_panel_open else "Explonation"
	if _help_panel_open:
		help_scroll.scroll_vertical = 0


func _close_explanation_panel() -> void:
	_capture_explanation_read_time()
	_help_panel_open = false
	_timer_paused_by_help = false
	explanation_backdrop.visible = false
	panel.visible = true
	help_panel.visible = false
	code_editor.editable = true
	run_button.disabled = _request_in_flight or _task_request_in_flight
	hint_button.disabled = _hint_request_in_flight or _request_in_flight or _task_request_in_flight
	explanation_button.text = "Explonation"


func _capture_explanation_read_time() -> void:
	if _explanation_open_tick_msec <= 0:
		return
	_explanation_read_seconds += float(Time.get_ticks_msec() - _explanation_open_tick_msec) / 1000.0
	_explanation_open_tick_msec = 0


func _on_explanation_scroll_up_pressed() -> void:
	help_scroll.scroll_vertical = maxi(help_scroll.scroll_vertical - 120, 0)


func _on_explanation_scroll_down_pressed() -> void:
	help_scroll.scroll_vertical += 120


func _set_rich_text(label: RichTextLabel, text: String) -> void:
	label.clear()
	if text.is_empty():
		return
	label.append_text(text)


func _normalize_string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return result
	for entry in value:
		var text: String = String(entry).strip_edges()
		if not text.is_empty():
			result.append(text)
	return result


func _highlight_keywords_with_bbcode(text: String, keywords: Array) -> String:
	var normalized_keywords: Array[String] = _normalize_string_array(keywords)
	if normalized_keywords.is_empty() or text.is_empty():
		return text
	var expanded_terms: Array[String] = []
	for keyword in normalized_keywords:
		for variant in _keyword_variants(keyword):
			if not expanded_terms.has(variant):
				expanded_terms.append(variant)
	expanded_terms.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	var spans: Array[Dictionary] = []
	for keyword in expanded_terms:
		var regex := RegEx.new()
		var pattern: String = "(?i)(?<![A-Za-z0-9_])%s(?![A-Za-z0-9_])" % _escape_regex(keyword)
		if regex.compile(pattern) != OK:
			continue
		var matches: Array = regex.search_all(text)
		for match_variant in matches:
			var match: RegExMatch = match_variant
			var start_index: int = match.get_start()
			var end_index: int = match.get_end()
			var overlaps_existing := false
			for existing_span_variant in spans:
				var existing_span: Dictionary = existing_span_variant
				var existing_start: int = int(existing_span.get("start", 0))
				var existing_end: int = int(existing_span.get("end", 0))
				if start_index < existing_end and end_index > existing_start:
					overlaps_existing = true
					break
			if overlaps_existing:
				continue
			spans.append(
				{
					"start": start_index,
					"end": end_index,
					"text": match.get_string(),
				}
			)
	if spans.is_empty():
		return text
	spans.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.get("start", 0)) < int(b.get("start", 0)))
	var rendered := ""
	var cursor := 0
	for span_variant in spans:
		var span: Dictionary = span_variant
		var start_index: int = int(span.get("start", 0))
		var end_index: int = int(span.get("end", 0))
		if start_index > cursor:
			rendered += _escape_bbcode(text.substr(cursor, start_index - cursor))
		rendered += "[b]%s[/b]" % _escape_bbcode(String(span.get("text", "")))
		cursor = end_index
	if cursor < text.length():
		rendered += _escape_bbcode(text.substr(cursor))
	return rendered


func _render_keyword_text(text: String, keywords: Array[String]) -> String:
	if _interaction_type == "boss":
		return _escape_bbcode(text)
	return _highlight_keywords_with_bbcode(text, keywords)


func _get_highlight_terms() -> Array[String]:
	return _build_highlight_terms(
		_normalize_string_array(_active_payload.get("keywords", [])),
		_normalize_string_array(_active_payload.get("validation_targets", []))
	)


func _build_highlight_terms(keywords: Array[String], targets: Array[String]) -> Array[String]:
	var terms: Array[String] = []
	for key in keywords:
		_append_unique_highlight_variants(terms, key)
	for target in targets:
		_append_unique_highlight_variants(terms, target)
	return terms


func _append_unique_highlight_variants(terms: Array[String], value: String) -> void:
	var text: String = value.strip_edges()
	if text.is_empty():
		return
	if not terms.has(text):
		terms.append(text)
	var normalized_key: String = text.to_lower().replace(" ", "_")
	if HIGHLIGHT_ALIASES.has(normalized_key):
		for alias_variant in HIGHLIGHT_ALIASES[normalized_key]:
			var alias_text: String = String(alias_variant).strip_edges()
			if not alias_text.is_empty() and not terms.has(alias_text):
				terms.append(alias_text)


func _keyword_variants(keyword: String) -> Array[String]:
	var variants: Array[String] = []
	var raw_keyword: String = keyword.strip_edges()
	if raw_keyword.is_empty():
		return variants
	if not variants.has(raw_keyword):
		variants.append(raw_keyword)
	var cleaned: String = raw_keyword.replace("_", " ").replace("-", " ")
	if cleaned.is_empty():
		return variants
	if not variants.has(cleaned):
		variants.append(cleaned)
	var parts: PackedStringArray = cleaned.split(" ", false)
	for part in parts:
		var token: String = part.strip_edges()
		if token.length() < 3:
			continue
		if not variants.has(token):
			variants.append(token)
		if token.ends_with("s") and token.length() > 4:
			var singular: String = token.left(token.length() - 1)
			if not variants.has(singular):
				variants.append(singular)
		elif token.length() > 4:
			var plural: String = "%ss" % token
			if not variants.has(plural):
				variants.append(plural)
		if token.ends_with("ing") and token.length() > 5:
			var stem: String = token.left(token.length() - 3)
			if not variants.has(stem):
				variants.append(stem)
	return variants


func _escape_regex(value: String) -> String:
	var escaped: String = value
	for special in ["\\", ".", "^", "$", "*", "+", "?", "(", ")", "[", "]", "{", "}", "|"]:
		escaped = escaped.replace(special, "\\" + special)
	return escaped


func _escape_bbcode(value: String) -> String:
	return value.replace("[", "\\[").replace("]", "\\]")


func _terminal_log_metadata(extra: Dictionary = {}) -> Dictionary:
	var stage: Dictionary = GameState.get_current_stage()
	var metadata := {
		"terminal_session_id": _terminal_session_id,
		"interaction_type": _interaction_type,
		"stage_type": String(stage.get("type", "")),
		"level_id": String(stage.get("level_id", "")),
		"level_theme": String(_active_payload.get("level_theme", "")),
		"difficulty": String(_active_payload.get("difficulty", "")),
		"encounter_name": String(_active_payload.get("encounter_name", "")),
		"generation_source": String(_active_payload.get("generation_source", "")),
		"generation_detail": String(_active_payload.get("generation_detail", "")),
		"pattern_id": String(_active_payload.get("pattern_id", "")),
		"time_left": int(_time_left),
		"elapsed_since_terminal_seconds": float(Time.get_ticks_msec() - _terminal_open_tick_msec) / 1000.0 if _terminal_open_tick_msec > 0 else 0.0,
		"run_count": _run_count,
		"hint_request_count": _hint_request_count,
		"explanation_open_count": _explanation_open_count,
		"explanation_read_seconds": _explanation_read_seconds,
		"task_generation_seconds": _task_generation_seconds,
	}
	metadata.merge(extra, true)
	return metadata
