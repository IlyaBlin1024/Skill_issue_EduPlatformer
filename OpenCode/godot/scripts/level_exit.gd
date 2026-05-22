extends Area2D
class_name LevelExit

const PRODUCTION_ANIMATION_LOADER := preload("res://scripts/production_animation_loader.gd")
const EXIT_SPRITE_CANVAS_SIZE := Vector2i(128, 128)
const EXIT_SPRITE_DIRS := [
	"res://assets/production_art/interactables/exits/spritesheets",
]
const EXIT_SPRITE_ANIMATIONS := {
	"locked": {"prefix": "exit_locked", "fps": 6.0, "loop": true},
	"open": {"prefix": "exit_open", "fps": 8.0, "loop": true},
}

signal exit_entered

@onready var visual: ColorRect = $Visual
@onready var label: Label = $Label

var _unlocked := false
var _locked_text := "Locked"
var _ready_text := "Exit Ready"
var _sprite: AnimatedSprite2D = null
var _sprites_ready := false
var _current_visual_animation := ""


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	_setup_exit_sprite()
	set_unlocked(false)


func configure(config: Dictionary) -> void:
	var position_data: Array = config.get("position", [])
	if position_data.size() == 2:
		global_position = Vector2(float(position_data[0]), float(position_data[1]))
	_locked_text = String(config.get("locked_text", _locked_text))
	_ready_text = String(config.get("ready_text", _ready_text))
	set_unlocked(_unlocked)


func set_unlocked(value: bool) -> void:
	_unlocked = value
	if _unlocked:
		visual.color = Color(0.45, 0.8, 0.55, 1)
		label.text = _ready_text
		_play_exit_visual("open")
	else:
		visual.color = Color(0.32, 0.34, 0.4, 1)
		label.text = _locked_text
		_play_exit_visual("locked")


func _on_body_entered(body: Node) -> void:
	if not _unlocked:
		return
	if body is PlayerController:
		exit_entered.emit()


func _setup_exit_sprite() -> void:
	if visual == null:
		return
	var sprite_options := {
		"name": "ExitSprite",
		"canvas_size": EXIT_SPRITE_CANVAS_SIZE,
		"target_height": 118,
		"max_width": 118,
		"foot_margin": 4,
		"initial_animation": "locked",
	}
	_sprite = PRODUCTION_ANIMATION_LOADER.create_sprite(self, _sprite, visual, EXIT_SPRITE_DIRS, EXIT_SPRITE_ANIMATIONS, sprite_options)
	_sprites_ready = _sprite != null


func _play_exit_visual(animation_name: String) -> bool:
	if not _sprites_ready or _sprite == null or _sprite.sprite_frames == null:
		return false
	var resolved_animation := animation_name
	if not _sprite.sprite_frames.has_animation(resolved_animation):
		resolved_animation = "locked"
	if not _sprite.sprite_frames.has_animation(resolved_animation):
		return false
	if _current_visual_animation == resolved_animation and _sprite.is_playing():
		return true
	_current_visual_animation = resolved_animation
	_sprite.play(resolved_animation)
	return true
