extends Area2D

class_name EnemyProjectile

const PLAYER_PROJECTILE_TEXTURE := "res://assets/production_art/effects/projectiles/player_shot_trail.png"
const ENEMY_PROJECTILE_TEXTURE := "res://assets/production_art/effects/projectiles/enemy_shot_trail.png"
const REFLECTED_PROJECTILE_TEXTURE := "res://assets/production_art/characters/enemies/shared_projectiles/reflected_projectile.png"

signal projectile_expired(projectile: EnemyProjectile)
signal target_hit(projectile: EnemyProjectile, target: Node, damage: int)

var speed: float = 320.0
var damage: int = 8
var direction := Vector2.LEFT
var max_travel_distance: float = 520.0
var target_kind: String = "player"
var source_enemy: EnemyEncounter = null
var source_boss: BossEncounter = null

var _travelled_distance := 0.0
var _collision: CollisionShape2D
var _visual: ColorRect
var _sprite: Sprite2D
var _projectile_color := Color(0.992157, 0.709804, 0.34902, 1)
var _is_reflected := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_monitor_setup()
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)


func configure(start_position: Vector2, travel_direction: Vector2, projectile_damage: int, projectile_speed: float, desired_target_kind: String, projectile_color: Color = Color(0.992157, 0.709804, 0.34902, 1)) -> void:
	global_position = start_position
	direction = travel_direction.normalized()
	damage = projectile_damage
	speed = projectile_speed
	target_kind = desired_target_kind
	_projectile_color = projectile_color
	if _visual != null:
		_visual.color = projectile_color
	_update_projectile_sprite()


func _physics_process(delta: float) -> void:
	var motion: Vector2 = direction * speed * delta
	global_position += motion
	_travelled_distance += motion.length()
	if _travelled_distance >= max_travel_distance:
		_expire()


func _monitor_setup() -> void:
	_collision = CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = 8.0
	_collision.shape = shape
	add_child(_collision)

	_visual = ColorRect.new()
	_visual.offset_left = -6.0
	_visual.offset_top = -6.0
	_visual.offset_right = 6.0
	_visual.offset_bottom = 6.0
	_visual.color = Color(0.992157, 0.709804, 0.34902, 1)
	_visual.visible = false
	_visual.modulate = Color(1, 1, 1, 0)
	_visual.self_modulate = Color(1, 1, 1, 0)
	add_child(_visual)
	_setup_projectile_sprite()


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D:
		_expire()
		return
	if target_kind == "player" and body is PlayerController:
		if (body as PlayerController).try_reflect_projectile(self):
			return
		target_hit.emit(self, body, damage)
		_expire()
		return
	if target_kind == "enemy" and body is BossEncounter:
		target_hit.emit(self, body, damage)
		_expire()


func _on_area_entered(area: Area2D) -> void:
	if target_kind == "enemy" and area is EnemyEncounter:
		target_hit.emit(self, area, damage)
		_expire()


func _expire() -> void:
	projectile_expired.emit(self)
	queue_free()


func reflect_to_source() -> bool:
	var reflected_direction := Vector2.ZERO
	if source_enemy != null and is_instance_valid(source_enemy) and not source_enemy.is_defeated():
		reflected_direction = source_enemy.global_position - global_position
	elif source_boss != null and is_instance_valid(source_boss) and not source_boss.is_defeated():
		reflected_direction = source_boss.global_position - global_position
	else:
		return false
	if reflected_direction.is_zero_approx():
		reflected_direction = Vector2.RIGHT
	direction = reflected_direction.normalized()
	target_kind = "enemy"
	speed *= 1.15
	damage = maxi(int(round(float(damage) * 1.15)), damage + 1)
	_travelled_distance = 0.0
	_is_reflected = true
	if _visual != null:
		_visual.color = Color(0.72, 1.0, 0.88, 1.0)
		_visual.visible = false
	_update_projectile_sprite()
	return true


func _setup_projectile_sprite() -> void:
	_sprite = Sprite2D.new()
	_sprite.name = "ProjectileSprite"
	_sprite.centered = true
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.scale = Vector2(0.42, 0.42)
	add_child(_sprite)
	_update_projectile_sprite()
	if _sprite.texture != null:
		_visual.visible = false


func _update_projectile_sprite() -> void:
	if _sprite == null:
		return
	var texture_path := _projectile_texture_path()
	if ResourceLoader.exists(texture_path):
		_sprite.texture = ResourceLoader.load(texture_path) as Texture2D
		_sprite.rotation = direction.angle()
		_sprite.modulate = Color(1, 1, 1, 1)
		if _visual != null:
			_visual.visible = false
	else:
		_sprite.texture = null
		if _visual != null:
			_visual.visible = false


func _projectile_texture_path() -> String:
	if _is_reflected:
		return REFLECTED_PROJECTILE_TEXTURE
	if target_kind == "enemy":
		return PLAYER_PROJECTILE_TEXTURE
	return ENEMY_PROJECTILE_TEXTURE
