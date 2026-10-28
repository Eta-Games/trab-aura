extends "res://SCRIPT/powers/knife_power.gd"
# Secondaria di Andrix: un tocco lancia i coltelli; tenere premuto carica la
# Madonnina, che parte al rilascio dopo la soglia.

var _madonna_texture: Texture2D
var _target: Player
var _projectile: Sprite2D
var _poison_cloud: Node2D
var _poison_area: Area2D
var _phase: String = ""
var _phase_left: float = 0.0
var _charging: bool = false
var _impact_position: Vector2 = Vector2.ZERO
var _flight_start: Vector2 = Vector2.ZERO
var _flight_end: Vector2 = Vector2.ZERO
var _flight_left: float = 0.0
var _flight_duration: float = 0.0
var _impact_power: String = ""
var _trail_texture: Texture2D
var _poison_left: float = 0.0
var _poison_tick_left: float = 0.0
var _poison_duration: float = 0.0
var _poison_elapsed: float = 0.0
var _poison_expand_duration: float = 0.45
var _poison_hold_duration: float = 0.0
var _rng := RandomNumberGenerator.new()


func default_params() -> Dictionary:
	var values: Dictionary = super.default_params()
	values.merge({
		"statue_sprite": "res://sprite/Player/Andrix/madonnina.png",
		"flight_time": 0.8,
		"flight_arc": 180.0,
		"projectile_size": 96.0,
		"hold_time": 0.5,
		"poison_duration": 4.0,
		"self_poison_duration": 6.5,
		"self_poison_radius": 128.0,
		"poison_expand_duration": 0.5,
		"poison_hold_duration": 4.0,
		"poison_tick_interval": 0.5,
		"poison_damage": 3,
		"poison_aura_drain": 30.0,
		"poison_radius": 150.0,
		"poison_particle_amount": 48,
		"impact_knife_count": 12,
		"knife_effect_time": 1.0,
		"madonna_stamina_min": 100.0,
		"madonna_stamina_cost": 100.0,
	}, true)
	return values


func _on_setup() -> void:
	super._on_setup()
	_rng.randomize()
	_madonna_texture = load(str(params["statue_sprite"]))
	_trail_texture = _make_trail_texture()
	if _madonna_texture == null:
		push_warning("Andrix: immagine della Madonnina non trovata: %s" % params["statue_sprite"])


func can_use() -> bool:
	if _madonna_texture == null or not _phase.is_empty() or not super.can_use():
		return false
	if player._secondary_hold_time >= charge_time():
		return _has_stamina(float(params["madonna_stamina_min"]))
	return true


func is_busy() -> bool:
	return super.is_busy() or _charging


func use() -> void:
	if _rng.randi_range(0, 1) == 0:
		super.use()
		return
	cooldown_left = float(params["cooldown"])
	_spend_stamina(float(params["stamina_cost"]))
	_cast_left = float(params["cast_time"])
	player.velocity.x = 0.0
	_impact_position = _get_player_feet_position()
	_spawn_poison_cloud(float(params["self_poison_duration"]), float(params["self_poison_radius"]))
	_phase = "self_poison"
	_phase_left = float(params["self_poison_duration"])


func has_charged_attack() -> bool:
	return true


func charge_time() -> float:
	return maxf(float(params["hold_time"]), 0.0)


func start_charge() -> bool:
	if not _has_stamina(float(params["madonna_stamina_min"])):
		return false
	_charging = true
	return true


func release_charge() -> void:
	if not _charging:
		return
	_charging = false
	_start_madonnina()


func on_player_hit() -> void:
	if _charging:
		_charging = false
		return
	super.on_player_hit()


func _start_madonnina() -> void:
	cooldown_left = float(params["cooldown"])
	_spend_stamina(float(params["madonna_stamina_cost"]))
	_target = _find_opponent()
	_impact_power = "poison" if _rng.randi_range(0, 1) == 0 else "knives"
	_flight_start = player.global_position + Vector2(0.0, -player.get_visual_height() * 0.35)
	_flight_end = _get_map_center_ground()
	_flight_duration = maxf(float(params["flight_time"]), 0.1)
	_flight_left = _flight_duration
	_create_projectile()
	_phase = "flight"
	_phase_left = _flight_duration


func _create_projectile() -> void:
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		scene_root = player.get_tree().root
	_projectile = Sprite2D.new()
	_projectile.name = "MadonninaProjectile"
	_projectile.texture = _madonna_texture
	_projectile.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_projectile.centered = true
	var max_dim: float = maxf(_madonna_texture.get_width(), _madonna_texture.get_height())
	_projectile.scale = Vector2.ONE * float(params["projectile_size"]) / maxf(max_dim, 1.0)
	_projectile.global_position = _flight_start
	scene_root.add_child(_projectile)


func _get_map_center_ground() -> Vector2:
	var viewport: Viewport = player.get_viewport()
	var view_size: Vector2 = viewport.get_visible_rect().size
	var inverse_transform: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var map_center: Vector2 = inverse_transform * Vector2(view_size.x * 0.5, view_size.y * 0.5)
	var floor_y: float = player.global_position.y
	if is_instance_valid(_target):
		floor_y = maxf(floor_y, _target.global_position.y)
	return Vector2(map_center.x, floor_y)


func _find_opponent() -> Player:
	var closest: Player = null
	var closest_distance: float = INF
	for candidate in player.get_tree().get_nodes_in_group("players"):
		if candidate is Player and candidate != player and not candidate.is_dead and candidate.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(candidate.global_position)
			if distance < closest_distance:
				closest = candidate
				closest_distance = distance
	return closest


func _get_player_feet_position() -> Vector2:
	var body_collision := player.get_node_or_null("collision") as CollisionShape2D
	if body_collision != null and body_collision.shape != null:
		var bounds: Rect2 = body_collision.shape.get_rect()
		return body_collision.to_global(Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.end.y))
	return player.global_position + Vector2(0.0, player.get_visual_height() * 0.5)


func _update_power(delta: float) -> void:
	super._update_power(delta)
	_update_poison(delta)
	if _phase != "flight":
		if _phase_left > 0.0:
			_phase_left = maxf(_phase_left - delta, 0.0)
		if _phase_left == 0.0 and not _phase.is_empty():
			_clear_effects()
			_phase = ""
		return
	_flight_left = maxf(_flight_left - delta, 0.0)
	var progress: float = 1.0 - _flight_left / _flight_duration
	var next_position: Vector2 = _flight_start.lerp(_flight_end, progress)
	next_position.y -= sin(progress * PI) * float(params["flight_arc"])
	if is_instance_valid(_projectile):
		var to_position: Vector2 = next_position - _projectile.global_position
		if to_position.length_squared() > 0.0:
			var query := PhysicsRayQueryParameters2D.create(_projectile.global_position, next_position)
			query.collision_mask = 0x7fffffff
			query.exclude = [player.get_rid()]
			query.collide_with_areas = false
			var collision: Dictionary = player.get_world_2d().direct_space_state.intersect_ray(query)
			if not collision.is_empty():
				_spawn_trail_particles(_projectile.global_position)
				_impact_at(collision["position"])
				return
		_projectile.global_position = next_position
		_spawn_trail_particles(next_position)
	if _flight_left == 0.0:
		_impact_at(_flight_end)


func _impact_at(position: Vector2) -> void:
	_impact_position = position
	if is_instance_valid(_projectile):
		_projectile.queue_free()
	_projectile = null
	if _impact_power == "poison":
		_spawn_poison_cloud()
		_phase = "poison"
		_phase_left = float(params["poison_duration"])
	else:
		_throw_impact_rose()
		_phase = "knife_effect"
		_phase_left = float(params["knife_effect_time"])
	_impact_power = ""


func _make_trail_texture() -> Texture2D:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	for y in range(8):
		for x in range(8):
			var distance: float = Vector2(x - 3.5, y - 3.5).length()
			image.set_pixel(x, y, Color.WHITE if distance <= 2.8 else Color(1, 1, 1, 0))
	return ImageTexture.create_from_image(image)


func _spawn_trail_particles(position: Vector2) -> void:
	if not GameState.visual_effects:
		return
	var particle_color: Color = Color(0.48, 0.08, 0.78, 1.0) if _impact_power == "knives" else Color(0.28, 0.9, 0.12, 1.0)
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		scene_root = player.get_tree().root
	for i in range(2):
		var particle := Sprite2D.new()
		particle.name = "MadonninaTrailParticle"
		particle.texture = _trail_texture
		particle.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		particle.modulate = particle_color
		particle.global_position = position + Vector2(_rng.randf_range(-5.0, 5.0), _rng.randf_range(-5.0, 5.0))
		var size: float = _rng.randf_range(0.65, 1.15)
		particle.scale = Vector2.ONE * size
		scene_root.add_child(particle)
		var tween := particle.create_tween()
		tween.set_parallel(true)
		tween.tween_property(particle, "global_position", particle.global_position + Vector2(_rng.randf_range(-10.0, 10.0), _rng.randf_range(-14.0, 2.0)), 0.28)
		tween.tween_property(particle, "modulate:a", 0.0, 0.28)
		tween.tween_property(particle, "scale", particle.scale * 0.45, 0.28)
		tween.chain().tween_callback(particle.queue_free)


func _throw_impact_rose() -> void:
	var direction: float = player.get_facing_dir()
	if is_instance_valid(_target):
		var dx: float = _target.global_position.x - _impact_position.x
		if not is_zero_approx(dx):
			direction = signf(dx)
	var count: int = maxi(int(params["impact_knife_count"]), 1)
	for i in range(count):
		var angle: float = TAU * float(i) / float(count)
		_spawn_knife(_impact_position, direction, angle)


func _spawn_poison_cloud(duration: float = -1.0, radius: float = -1.0) -> void:
	var is_self_poison: bool = duration > 0.0
	if duration <= 0.0:
		duration = float(params["poison_duration"])
	if radius <= 0.0:
		radius = float(params["poison_radius"])
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		scene_root = player.get_tree().root
	_poison_cloud = Node2D.new()
	_poison_cloud.name = "MadonninaPoisonCloud"
	_poison_cloud.global_position = _impact_position
	_poison_cloud.scale = Vector2.ONE * 0.06
	scene_root.add_child(_poison_cloud)
	var ground_offset := Vector2(0.0, -radius * 0.35)

	var particles := CPUParticles2D.new()
	particles.name = "PoisonParticles"
	particles.amount = int(params["poison_particle_amount"])
	particles.lifetime = 1.1
	particles.local_coords = true
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(radius * 0.65, 22.0)
	particles.direction = Vector2(0.0, -1.0)
	particles.spread = 22.0
	particles.gravity = Vector2(0.0, -5.0)
	particles.initial_velocity_min = 2.0
	particles.initial_velocity_max = 12.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 3.5
	particles.color = Color(0.48, 0.08, 0.78, 0.96)
	particles.texture = _make_soft_particle_texture()
	particles.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	particles.position = ground_offset
	_poison_cloud.add_child(particles)

	_poison_area = Area2D.new()
	_poison_area.name = "PoisonArea"
	_poison_area.collision_layer = player.current_hitbox.collision_layer
	_poison_area.collision_mask = player.current_hitbox.collision_mask
	_poison_area.monitoring = true
	_poison_cloud.add_child(_poison_area)
	var shape := CircleShape2D.new()
	shape.radius = radius
	var collision := CollisionShape2D.new()
	collision.shape = shape
	collision.position = ground_offset
	_poison_area.add_child(collision)
	_poison_left = duration
	_poison_duration = duration
	_poison_elapsed = 0.0
	_poison_expand_duration = minf(float(params["poison_expand_duration"]), duration * 0.5)
	_poison_hold_duration = 0.0 if is_self_poison else float(params["poison_hold_duration"])
	_poison_tick_left = float(params["poison_tick_interval"])


func _make_soft_particle_texture() -> Texture2D:
	var image := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in range(16):
		for x in range(16):
			var distance: float = Vector2(x - 7.5, y - 7.5).length()
			var alpha: float = 1.0 if distance <= 6.0 else (0.72 if distance <= 7.0 else 0.0)
			image.set_pixel(x, y, Color(1.0, 1.0, 1.0, alpha))
	return ImageTexture.create_from_image(image)


func _update_poison(delta: float) -> void:
	if _poison_left <= 0.0:
		return
	_poison_left = maxf(_poison_left - delta, 0.0)
	_poison_elapsed = minf(_poison_elapsed + delta, _poison_duration)
	var cloud_scale: float
	if _poison_elapsed < _poison_expand_duration:
		var expand: float = _poison_elapsed / maxf(_poison_expand_duration, 0.001)
		cloud_scale = lerpf(0.06, 1.0, _smooth_progress(expand))
	elif _poison_elapsed < _poison_expand_duration + _poison_hold_duration:
		cloud_scale = 1.0
	else:
		var shrink_duration: float = maxf(_poison_duration - _poison_expand_duration - _poison_hold_duration, 0.001)
		var shrink: float = (_poison_elapsed - _poison_expand_duration - _poison_hold_duration) / shrink_duration
		cloud_scale = lerpf(1.0, 0.06, _smooth_progress(shrink))
	if is_instance_valid(_poison_cloud):
		_poison_cloud.scale = Vector2.ONE * cloud_scale
	_poison_tick_left -= delta
	if _poison_tick_left <= 0.0 and is_instance_valid(_poison_area):
		_poison_tick_left = float(params["poison_tick_interval"])
		for area in _poison_area.get_overlapping_areas():
			if area is Hurtbox and area != player.hurtbox:
				var victim := area.get_parent() as Player
				if victim == null:
					continue
				victim.apply_poison_damage(int(params["poison_damage"]), player, float(params["poison_aura_drain"]))
	if _poison_left == 0.0:
		if is_instance_valid(_poison_cloud):
			_poison_cloud.queue_free()
		_poison_cloud = null
		_poison_area = null
		_poison_duration = 0.0
		_poison_elapsed = 0.0


func _smooth_progress(value: float) -> float:
	var clamped: float = clampf(value, 0.0, 1.0)
	return clamped * clamped * (3.0 - 2.0 * clamped)


func _clear_effects() -> void:
	if is_instance_valid(_projectile):
		_projectile.queue_free()
	if is_instance_valid(_poison_cloud):
		_poison_cloud.queue_free()
	_projectile = null
	_poison_cloud = null
	_poison_area = null
	_target = null
