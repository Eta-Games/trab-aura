class_name MencuMineProjectile
extends Node2D

var _direction: Vector2 = Vector2.RIGHT
var _owner_player: Player
var _target: Player
var _damage: int = 35
var _speed: float = 520.0
var _lifetime: float = 1.5
var _age: float = 0.0
var _hit_radius: float = 12.0


func setup(texture: Texture2D, origin: Vector2, direction: Vector2, power, target: Player) -> void:
	global_position = origin
	_direction = direction.normalized()
	_owner_player = power.player
	_target = target
	_damage = int(power.params["projectile_damage"])
	_speed = float(power.params["projectile_speed"])
	_lifetime = float(power.params["projectile_lifetime"])
	_hit_radius = maxf(float(power.params["projectile_hit_radius"]), 1.0)
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.scale = Vector2.ONE * float(power.params["projectile_scale"])
	sprite.rotation = _direction.angle()
	add_child(sprite)


func _process(delta: float) -> void:
	_age += delta
	global_position += _direction * _speed * delta
	if is_instance_valid(_target) and not _target.is_dead and _target.current_health > 0 and _overlaps_target():
		_target.hurtbox.take_damage(_damage, _owner_player)
		queue_free()
		return
	if _age >= _lifetime:
		queue_free()


func _overlaps_target() -> bool:
	var shape_node: CollisionShape2D = _target.get_node_or_null("Hurtbox/CollisionShape2D") as CollisionShape2D
	if shape_node != null and shape_node.shape is RectangleShape2D:
		var rect_shape: RectangleShape2D = shape_node.shape as RectangleShape2D
		var local_position: Vector2 = shape_node.to_local(global_position)
		var scale: Vector2 = shape_node.global_scale.abs()
		var margin_x: float = _hit_radius / maxf(scale.x, 0.001)
		var margin_y: float = _hit_radius / maxf(scale.y, 0.001)
		return absf(local_position.x) <= rect_shape.size.x * 0.5 + margin_x \
			and absf(local_position.y) <= rect_shape.size.y * 0.5 + margin_y
	return global_position.distance_to(_target.hurtbox.global_position) <= 64.0 + _hit_radius
