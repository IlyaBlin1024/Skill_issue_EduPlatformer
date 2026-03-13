extends Area2D
class_name AltarEncounter

signal altar_started(altar: AltarEncounter, payload: Dictionary)
signal weapon_forged(altar: AltarEncounter, weapon_summary: String)

@export var level_theme: String = "variables"

@onready var visual: ColorRect = $Visual
@onready var label: Label = $Label

var _forged := false
var _triggered := false


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_apply_visual_state()


func configure(config: Dictionary) -> void:
	level_theme = String(config.get("level_theme", level_theme))
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
				"title": "Forge Terminal",
				"status_text": "Write weapon setup code to forge a new blade.",
				"success_text": "Weapon forged.",
				"failure_text": "Forge rejected the pattern.",
				"time_limit": 0,
				"timer_enabled": false,
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
