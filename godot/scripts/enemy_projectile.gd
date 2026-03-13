extends Area2D

class_name EnemyProjectile

signal projectile_expired(projectile: EnemyProjectile)
signal target_hit(projectile: EnemyProjectile, target: Node, damage: int)

var speed: float = 320.0
var damage: int = 8
var direction := Vector2.LEFT
var max_travel_distance: float = 520.0
var target_kind: String = "player"

var _travelled_distance := 0.0
var _collision: CollisionShape2D
var _visual: ColorRect


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
	if _visual != null:
		_visual.color = projectile_color


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
	add_child(_visual)


func _on_body_entered(body: Node) -> void:
	if body is StaticBody2D:
		_expire()
		return
	if target_kind == "player" and body is PlayerController:
		target_hit.emit(self, body, damage)
		_expire()


func _on_area_entered(area: Area2D) -> void:
	if target_kind == "enemy" and area is EnemyEncounter:
		target_hit.emit(self, area, damage)
		_expire()


func _expire() -> void:
	projectile_expired.emit(self)
	queue_free()
