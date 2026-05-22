extends Area2D
class_name AltarEncounter

const PRODUCTION_ANIMATION_LOADER := preload("res://scripts/production_animation_loader.gd")
const ALTAR_SPRITE_CANVAS_SIZE := Vector2i(128, 128)
const ALTAR_SPRITE_ANIMATIONS := {
	"idle": {"prefix": "altar_idle", "fps": 6.0, "loop": true},
	"activate": {"prefix": "altar_activate", "fps": 10.0, "loop": false},
	"complete": {"prefix": "altar_complete", "fps": 8.0, "loop": true},
}
const ALTAR_SPRITE_DIRS := [
	"res://assets/production_art/models/interactables/altars",
]

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
var _sprite: AnimatedSprite2D = null
var _sprites_ready := false
var _current_visual_animation := ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_setup_altar_sprite()
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
				"encounter_name": "Forge Altar",
				"encounter_style": "weapon_forge",
				"gameplay_context": "The code defines weapon behavior that changes combat directly.",
				"structure_focus": _structure_focus_for_theme(),
				"boss_mechanic": "",
				"starter_code": terminal_starter_code
			}
		)


func mark_forged(weapon_summary: String) -> void:
	if _forged:
		return
	_play_altar_visual("activate")
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
		_play_altar_visual("complete")
	else:
		visual.color = Color(0.364706, 0.627451, 0.847059, 1)
		label.text = "ALTAR"
		_play_altar_visual("idle")


func _structure_focus_for_theme() -> String:
	match level_theme:
		"variables":
			return "clear weapon-stat assignments"
		"conditions":
			return "a branch that chooses one weapon behavior or another"
		"loops":
			return "a short repeated forge pattern"
		"functions":
			return "a helper function that wraps forge behavior"
		_:
			return "a compact multi-part forge tactic"


func _setup_altar_sprite() -> void:
	if visual == null:
		return
	var fallback_visual := visual
	var sprite_options := {
		"name": "AltarSprite",
		"canvas_size": ALTAR_SPRITE_CANVAS_SIZE,
		"target_height": 96,
		"max_width": 116,
		"foot_margin": 8,
		"initial_animation": "idle",
		"hide_fallback_on_missing": true,
	}
	_sprite = PRODUCTION_ANIMATION_LOADER.create_sprite(self, _sprite, fallback_visual, ALTAR_SPRITE_DIRS, ALTAR_SPRITE_ANIMATIONS, sprite_options)
	_sprites_ready = _sprite != null
	_remove_legacy_visual_node(fallback_visual)
	label.visible = false
	if _sprites_ready:
		_play_altar_visual("idle")


func _play_altar_visual(animation_name: String) -> bool:
	if not _sprites_ready or _sprite == null or _sprite.sprite_frames == null:
		return false
	var resolved_animation := animation_name
	if not _sprite.sprite_frames.has_animation(resolved_animation):
		resolved_animation = "idle"
	if not _sprite.sprite_frames.has_animation(resolved_animation):
		return false
	if _current_visual_animation == resolved_animation and _sprite.is_playing():
		return true
	_current_visual_animation = resolved_animation
	_sprite.play(resolved_animation)
	return true


func _remove_legacy_visual_node(fallback_visual: ColorRect) -> void:
	if fallback_visual == null:
		return
	var dummy := ColorRect.new()
	dummy.name = "HiddenLegacyVisual"
	dummy.position = fallback_visual.position
	dummy.size = fallback_visual.size
	dummy.visible = false
	dummy.modulate = Color(1, 1, 1, 0)
	dummy.self_modulate = Color(1, 1, 1, 0)
	dummy.color = Color(0, 0, 0, 0)
	dummy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual = dummy
	if fallback_visual.get_parent() == self and is_instance_valid(fallback_visual):
		remove_child(fallback_visual)
		fallback_visual.free()
