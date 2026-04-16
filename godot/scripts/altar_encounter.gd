extends Area2D
class_name AltarEncounter

signal altar_started(altar: AltarEncounter, payload: Dictionary)
signal weapon_forged(altar: AltarEncounter, weapon_summary: String)

@export var level_theme: String = "variables"
@export var terminal_title: String = "Forge Terminal"
@export var terminal_status_text: String = "Write weapon setup code to forge a new blade."
@export var terminal_success_text: String = "Weapon forged."
@export var terminal_failure_text: String = "Forge rejected the pattern."
@export var terminal_starter_code: String = ""

@onready var visual: ColorRect = $Visual
@onready var label: Label = $Label

var _forged := false
var _triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_visual_state()


func configure(config: Dictionary) -> void:
	level_theme = String(config.get("level_theme", level_theme))
	terminal_title = String(config.get("terminal_title", terminal_title))
	terminal_status_text = String(config.get("terminal_status_text", terminal_status_text))
	terminal_success_text = String(config.get("terminal_success_text", terminal_success_text))
	terminal_failure_text = String(config.get("terminal_failure_text", terminal_failure_text))
	terminal_starter_code = String(config.get("terminal_starter_code", terminal_starter_code))
	var position_data: Array = config.get("position", [])
	if position_data.size() == 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	_apply_visual_state()


func _on_body_entered(body: Node) -> void:
	if _forged or _triggered:
		return
	if body is PlayerController:
		_triggered = true
		altar_started.emit(
			self,
			{
				"interaction_type": "altar",
				"level_theme": level_theme,
				"title": terminal_title,
				"status_text": terminal_status_text,
				"success_text": terminal_success_text,
				"failure_text": terminal_failure_text,
				"time_limit": 0,
				"timer_enabled": false,
				"starter_code": terminal_starter_code
			}
		)


func mark_forged(weapon_summary: String) -> void:
	if _forged:
		return
	_forged = true
	_triggered = true
	_apply_visual_state()
	weapon_forged.emit(self, weapon_summary)


func reset_interaction() -> void:
	if _forged:
		return
	_triggered = false


func is_forged() -> bool:
	return _forged


func _apply_visual_state() -> void:
	if _forged:
		visual.color = Color(0.423529, 0.776471, 0.858824, 1)
		label.text = "FORGED"
	else:
		visual.color = Color(0.364706, 0.627451, 0.847059, 1)
		label.text = "ALTAR"
