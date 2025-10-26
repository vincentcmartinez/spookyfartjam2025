extends CharacterBody2D

# ---------- Multiplayer? / Inputs ----------
@export var action_prefix: String = "p1_" # "p1_" or "p2_"
func action(name: String) -> String:
	return "%s%s" % [action_prefix, name]

# ---------- Tunables ----------
@export var max_speed: float = 200.0
@export var air_max_speed: float = 200.0
@export var accel: float = 1500.0
@export var air_accel: float = 1100.0
@export var deaccel: float = 1600.0

@export var gravity: float = ProjectSettings.get_setting("physics/2d/default_gravity")
@export var max_fall_speed: float = 1300.0

@export var jump_velocity: float = -420.0
@export var jump_buffer: float = 0.12
@export var coyote_time: float = 0.12
@export var jump_cut_multiplier: float = 0.45

@export var allow_double_jump: bool = true
@export var wall_slide_speed: float = 90.0
@export var wall_jump_push: float = 280.0
@export var wall_jump_up: float = 420.0

@export var dash_speed: float = 420.0
@export var dash_time: float = 0.14
@export var dash_cooldown: float = 0.45

# ---------- Aim/Item Use ----------
@export var aim_deadzone: float = 0.25
@export var aim_smooth: float = 20.0
@export var throw_speed: float = 650.0
@export var fire_cooldown: float = 0.25
@export var projectile_scene: PackedScene
@export var aim_pivot: NodePath

@onready var _aim_pivot: Node2D = get_node_or_null(aim_pivot)

# ---------- State ----------
var _coyote_left: float = 0.0
var _jump_buf_left: float = 0.0
var _can_double: bool = false

var _is_dashing: bool = false
var _dash_left: float = 0.0
var _dash_cd_left: float = 0.0

var aim_vector: Vector2 = Vector2.RIGHT
var _aim_display: Vector2 = Vector2.RIGHT
var _fire_cd_left: float = 0.0

# ---------- Sabotage / Possession ----------
var _frozen: bool = false
var _freeze_left: float = 0.0

var _invert_input: bool = false
var _wind: Vector2 = Vector2.ZERO
var _wind_left: float = 0.0

var _slippery: bool = false
var _accel_mult: float = 1.0
var _fric_mult: float = 1.0

var _possessed_device: int = -1
var _possess_left: float = 0.0

# ---------- Signals ----------
signal jumped

func _ready() -> void:
	_can_double = allow_double_jump

func _physics_process(delta: float) -> void:
	# Timers
	if is_on_floor():
		_coyote_left = coyote_time
		_can_double = allow_double_jump
	else:
		_coyote_left = max(_coyote_left - delta, 0.0)

	_jump_buf_left = max(_jump_buf_left - delta, 0.0)

	if _dash_cd_left > 0.0:
		_dash_cd_left -= delta
	if _is_dashing:
		_dash_left -= delta
		if _dash_left <= 0.0:
			_is_dashing = false

	if _freeze_left > 0.0:
		_freeze_left -= delta
		if _freeze_left <= 0.0:
			_frozen = false

	if _wind_left > 0.0:
		_wind_left -= delta
		if _wind_left <= 0.0:
			_wind = Vector2.ZERO

	if _possess_left > 0.0:
		_possess_left -= delta
		if _possess_left <= 0.0:
			_possessed_device = -1
			
	if _fire_cd_left > 0.0:
		_fire_cd_left -= delta

	# Input
	var dir_x: float = _get_move_input()
	if _frozen:
		dir_x = 0.0


		# --- read aim from right stick (or actions)
	var aim_in: Vector2 = _get_aim_input()
	var mag: float = aim_in.length()
	if mag >= aim_deadzone:
		aim_vector = aim_in / mag                 # normalize
	# Smooth for visuals/reticle
	var t: float = clamp(aim_smooth * delta, 0.0, 1.0)
	_aim_display = _aim_display.lerp(aim_vector, t)

	# --- rotate an optional pivot (arm/reticle)
	if _aim_pivot:
		_aim_pivot.rotation = atan2(_aim_display.y, _aim_display.x)
		
	# Horizontal move (skip while dashing)
	if not _is_dashing:
		var target: float = dir_x * (max_speed if is_on_floor() else air_max_speed)
		var a: float = (accel if is_on_floor() else air_accel) * _accel_mult
		var d: float = deaccel * _fric_mult
		if absf(target) > 0.001:
			velocity.x = move_toward(velocity.x, target, a * delta)
		else:
			velocity.x = move_toward(velocity.x, 0.0, d * delta)

	# Gravity
	if not is_on_floor():
		velocity.y = min(velocity.y + gravity * delta, max_fall_speed)

	# Wall slide
	var wall_n: float = _get_wall_normal_x()
	var pushing_into_wall: bool = (dir_x < -0.3 and wall_n > 0.7) or (dir_x > 0.3 and wall_n < -0.7)
	if not is_on_floor() and pushing_into_wall and velocity.y > wall_slide_speed:
		velocity.y = move_toward(velocity.y, wall_slide_speed, 2400.0 * delta)

	# Jumps (buffer/coyote/wall/double)
	if _jump_buf_left > 0.0 and not _frozen:
		var jumped: bool = false
		if _coyote_left > 0.0:
			velocity.y = jump_velocity
			jumped = true
		elif pushing_into_wall:
			var away: float = -signf(wall_n) # typed, avoids Variant
			velocity = Vector2(away * wall_jump_push, -wall_jump_up)
			jumped = true
		elif allow_double_jump and _can_double:
			velocity.y = jump_velocity
			_can_double = false
			jumped = true

		if jumped:
			_jump_buf_left = 0.0
			emit_signal("jumped")

	# Variable jump height
	if not _is_dashing and velocity.y < 0.0 and not Input.is_action_pressed(action("jump")):
		velocity.y += gravity * (1.0 - jump_cut_multiplier) * delta

	# Dash
	if not _is_dashing and _dash_cd_left <= 0.0 and not _frozen:
		if Input.is_action_just_pressed(action("dash")) and absf(dir_x) > 0.05:
			_is_dashing = true
			_dash_left = dash_time
			_dash_cd_left = dash_cooldown
			velocity.y = 0.0
			velocity.x = signf(dir_x) * dash_speed

	# Wind
	if _wind != Vector2.ZERO:
		velocity += _wind * delta

	move_and_slide()

	# Queue jump after movement so landings consume it
	if Input.is_action_just_pressed(action("jump")):
		_jump_buf_left = jump_buffer
		
	
	# Fire
	if Input.is_action_just_pressed(action("fire")) and _fire_cd_left <= 0.0 and not _frozen:
		_fire_cd_left = fire_cooldown
		_fire_projectile()

# Prefer actions; fall back to per-device axis when possessed
func _get_move_input() -> float:
	var x: float = 0.0
	if _possessed_device != -1:
		x = clamp(Input.get_joy_axis(_possessed_device, JOY_AXIS_LEFT_X), -1.0, 1.0)
	else:
		var a: float = Input.get_axis(action("left"), action("right"))
		var v: float = Input.get_vector(action("left"), action("right"), action("up"), action("down")).x
		x = a if absf(a) > absf(v) else v
	if _invert_input:
		x = -x
	return clamp(x, -1.0, 1.0)
	
# --- Right stick aim reader (typed) ---
func _get_aim_input() -> Vector2:
	# Right stick is Axis 2 (X), Axis 3 (Y) in Godot
	if _possessed_device != -1:
		var ax: float = clamp(Input.get_joy_axis(_possessed_device, JOY_AXIS_RIGHT_X), -1.0, 1.0)
		var ay: float = clamp(Input.get_joy_axis(_possessed_device, JOY_AXIS_RIGHT_Y), -1.0, 1.0)
		return Vector2(ax, ay)
	else:
		var ax: float = Input.get_axis(action("aim_left"), action("aim_right"))
		var ay: float = Input.get_axis(action("aim_up"), action("aim_down"))
		return Vector2(ax, ay)

func _get_wall_normal_x() -> float:
	if not is_on_wall():
		return 0.0
	for i in range(get_slide_collision_count()):
		var col: KinematicCollision2D = get_slide_collision(i)
		if col and absf(col.get_normal().x) > 0.7:
			return col.get_normal().x
	return 0.0
	
# --- Fire helper (works with Area2D or RigidBody2D projectiles) ---
func _fire_projectile() -> void:
	if projectile_scene == null:
		return

	var dir: Vector2 = aim_vector
	if dir.length_squared() < 0.0001:
		# Fallback to facing based on current velocity.x
		dir = Vector2(1.0 if velocity.x >= 0.0 else -1.0, 0.0)

	var projectile := projectile_scene.instantiate()
	var spawn_offset: float = 14.0
	projectile.global_position = global_position + dir * spawn_offset

	# Common patterns:
	if projectile.has_method("launch"):
		projectile.call("launch", dir, throw_speed, self)
	elif projectile is RigidBody2D:
		projectile.linear_velocity = dir * throw_speed
	elif "velocity" in projectile: # e.g., CharacterBody2D/Area2D with .velocity
		projectile.velocity = dir * throw_speed

	get_tree().current_scene.add_child(projectile)

# ---------- Sabotage ----------
func apply_wind(force: Vector2, duration: float = 1.0) -> void:
	_wind = force
	_wind_left = max(duration, 0.0)

func set_ice_slip(active: bool, accel_scale: float = 0.35, friction_scale: float = 0.2) -> void:
	_slippery = active
	if active:
		_accel_mult = accel_scale
		_fric_mult = friction_scale
	else:
		_accel_mult = 1.0
		_fric_mult = 1.0

func freeze(seconds: float) -> void:
	_frozen = true
	_freeze_left = max(seconds, 0.0)
	velocity = Vector2.ZERO

func invert_controls(active: bool) -> void:
	_invert_input = active

func begin_possession(device_id: int, seconds: float = 3.0) -> void:
	_possessed_device = device_id
	_possess_left = max(seconds, 0.0)

func clear_effects() -> void:
	_invert_input = false
	_wind = Vector2.ZERO
	_wind_left = 0.0
	_slippery = false
	_accel_mult = 1.0
	_fric_mult = 1.0
	_frozen = false
	_freeze_left = 0.0
	_possessed_device = -1
	_possess_left = 0.0
