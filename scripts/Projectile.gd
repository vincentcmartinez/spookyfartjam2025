extends Area2D

@export var speed: float = 650.0
@export var lifetime: float = 2.0
var _vel: Vector2 = Vector2.ZERO

func launch(dir: Vector2, initial_speed: float, _owner: Node) -> void:
	_vel = dir.normalized() * initial_speed
	add_to_group("projectile")

func _physics_process(delta: float) -> void:
	position += _vel * delta
	lifetime -= delta
	if lifetime <= 0.0:
		queue_free()
