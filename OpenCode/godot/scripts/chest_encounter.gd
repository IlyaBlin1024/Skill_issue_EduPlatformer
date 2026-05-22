extends Area2D
class_name ChestEncounter

const PRODUCTION_ANIMATION_LOADER := preload("res://scripts/production_animation_loader.gd")
const CHEST_SPRITE_CANVAS_SIZE := Vector2i(128, 128)
const CHEST_SPRITE_ANIMATIONS := {
	"idle": {"prefix": "chest_idle", "fps": 6.0, "loop": true},
	"open": {"prefix": "chest_open", "fps": 10.0, "loop": false},
	"locked": {"prefix": "chest_locked", "fps": 6.0, "loop": true},
}
const CHEST_SPRITE_DIRS := [
	"res://assets/production_art/models/interactables/chests",
]

signal chest_started(chest: ChestEncounter, payload: Dictionary)
signal chest_opened(chest: ChestEncounter, reward_text: String)

@export var level_theme: String = "variables"
@export var reward_text: String = "Recovered a syntax shard."
@export var terminal_title: String = "Hack Terminal"
@export var terminal_status_text: String = "Solve the chest script to unlock the reward."
@export var terminal_success_text: String = "Chest unlocked."
@export var terminal_failure_text: String = "Chest remains sealed."
@export var terminal_starter_code: String = ""

@onready var visual: ColorRect = $Visual
@onready var label: Label = $Label

var _opened := false
var _triggered := false
var _base_color := Color(0.847059, 0.666667, 0.27451, 1)
var _sprite: AnimatedSprite2D = null
var _sprites_ready := false
var _current_visual_animation := ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_setup_chest_sprite()
	_apply_visual_state()


func configure(config: Dictionary) -> void:
	level_theme = String(config.get("level_theme", level_theme))
	reward_text = String(config.get("reward_text", reward_text))
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
	if _opened or _triggered:
		return
	if body is PlayerController:
		_triggered = true
		chest_started.emit(
			self,
			{
				"interaction_type": "chest",
				"level_theme": level_theme,
				"title": terminal_title,
				"status_text": terminal_status_text,
				"success_text": terminal_success_text,
				"failure_text": terminal_failure_text,
				"time_limit": 0,
				"timer_enabled": false,
				"encounter_name": "Archive Chest",
				"encounter_style": "reward_puzzle",
				"gameplay_context": reward_text,
				"structure_focus": _structure_focus_for_theme(),
				"boss_mechanic": "",
				"starter_code": terminal_starter_code
			}
		)


func mark_opened() -> void:
	if _opened:
		return
	_opened = true
	_triggered = true
	_apply_visual_state()
	chest_opened.emit(self, reward_text)


func reset_interaction() -> void:
	if _opened:
		return
	_triggered = false


func is_opened() -> bool:
	return _opened


func _apply_visual_state() -> void:
	if _opened:
		visual.color = Color(0.470588, 0.776471, 0.501961, 1)
		label.text = "OPEN"
		_play_chest_visual("open")
	else:
		visual.color = _base_color
		label.text = "CHEST"
		_play_chest_visual("idle")


func _structure_focus_for_theme() -> String:
	match level_theme:
		"variables":
			return "two short assignments for a reward-related stat setup"
		"conditions":
			return "one branch that decides how the cache unlocks"
		"loops":
			return "one short repeated unlock pattern"
		"functions":
			return "one helper function that groups the unlock logic"
		_:
			return "one compact mixed snippet for the chest reward logic"


func _setup_chest_sprite() -> void:
	if visual == null:
		return
	var fallback_visual := visual
	var sprite_options := {
		"name": "ChestSprite",
		"canvas_size": CHEST_SPRITE_CANVAS_SIZE,
		"target_height": 88,
		"max_width": 112,
		"foot_margin": 8,
		"initial_animation": "idle",
		"hide_fallback_on_missing": true,
	}
	_sprite = PRODUCTION_ANIMATION_LOADER.create_sprite(self, _sprite, fallback_visual, CHEST_SPRITE_DIRS, CHEST_SPRITE_ANIMATIONS, sprite_options)
	_sprites_ready = _sprite != null
	_remove_legacy_visual_node(fallback_visual)
	label.visible = false
	if _sprites_ready:
		_play_chest_visual("idle")


func _play_chest_visual(animation_name: String) -> bool:
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
