extends "res://SCRIPT/powers/perux_ambush.gd"
# Tocco breve: mantiene l'imboscata di Perucx.
# Carica e rilascio: un cappellino attraversa la visuale e lascia cadere
# palline da tennis lungo il percorso.

var _charging: bool = false
var _sweep_active: bool = false
var _sweep_hat: Sprite2D
var _sweep_direction: float = 1.0
var _sweep_speed: float = 0.0
var _sweep_target_x: float = 0.0
var _sweep_y: float = 0.0
var _drop_timer: float = 0.0
var _ball_texture: Texture2D
var _balls: Array[Dictionary] = []


func default_params() -> Dictionary:
	var values: Dictionary = super.default_params()
	values.merge({
		"cooldown": 5.0,
		"charge_time": 1.0,
		"ball_sprite": "res://sprite/Player/Perucx/Secondary/tennis_ball.png",
		"hat_sprite": "res://sprite/Player/Perucx/Secondary/perucx_cap.png",
		"ball_damage": 18,
		"hat_travel_time": 3.0,
		"hat_height_ratio": 0.22,
		"hat_size_ratio": 0.38,
		"drop_interval": 0.3,
		"ball_fall_speed": 100.0,
		"ball_gravity": 850.0,
		"ball_size_ratio": 0.28,
		"ball_lifetime": 3.0,

	}, true)
	return values


func _on_setup() -> void:
	super._on_setup()
	_ball_texture = load(str(params["ball_sprite"])) as Texture2D
	if _ball_texture == null:
		push_warning("Perucx: pallina non trovata: %s" % params["ball_sprite"])



func has_charged_attack() -> bool:
	return true


func charge_time() -> float:
	return float(params["charge_time"])


func is_busy() -> bool:
	return _charging or _sweep_active or super.is_busy()


func start_charge() -> bool:
	if _ball_texture == null or not _has_stamina(player.max_stamina):
		return false
	_charging = true
	player.velocity.x = 0.0
	player.is_blocking = false
	return true


func update_charge(_delta: float) -> void:
	player.velocity.x = 0.0


func release_charge() -> void:
	if not _charging:
		return
	_charging = false
	_spend_stamina(player.max_stamina)
	cooldown_left = float(params["cooldown"])
	player.velocity.x = 0.0
	_start_hat_sweep()


func on_player_hit() -> void:
	if _charging:
		_charging = false
		super.on_player_hit()
		return
	super.on_player_hit()


func _update_power(delta: float) -> void:
	super._update_power(delta)
	_update_sweep(delta)
	_update_falling_balls(delta)


func _start_hat_sweep() -> void:
	var hat_texture: Texture2D = load(str(params["hat_sprite"])) as Texture2D
	if hat_texture == null:
		push_warning("Perucx: cappellino non trovato: %s" % params["hat_sprite"])
		return
	var viewport: Viewport = player.get_viewport()
	var view_size: Vector2 = viewport.get_visible_rect().size
	var screen_to_world: Transform2D = viewport.get_canvas_transform().affine_inverse()
	var direction: float = player.get_facing_dir()
	var y_on_screen: float = view_size.y * float(params["hat_height_ratio"])
	var left_point: Vector2 = screen_to_world * Vector2(0.0, y_on_screen)
	var right_point: Vector2 = screen_to_world * Vector2(view_size.x, y_on_screen)
	_sweep_direction = 1.0 if direction >= 0.0 else -1.0
	_sweep_hat = Sprite2D.new()
	_sweep_hat.name = "PerucxSweepingCap"
	_sweep_hat.texture = hat_texture
	_sweep_hat.z_index = 5
	var hat_height: float = player.get_visual_height() * float(params["hat_size_ratio"])
	_sweep_hat.scale = Vector2.ONE * (hat_height / hat_texture.get_size().y)
	_sweep_hat.flip_h = _sweep_direction < 0.0
	var half_hat_width: float = hat_texture.get_size().x * _sweep_hat.scale.x * 0.5
	var start_point: Vector2 = left_point if _sweep_direction > 0.0 else right_point
	var end_point: Vector2 = right_point if _sweep_direction > 0.0 else left_point
	start_point.x -= _sweep_direction * half_hat_width
	end_point.x += _sweep_direction * half_hat_width
	_sweep_target_x = end_point.x
	_sweep_y = start_point.y
	_sweep_speed = absf(end_point.x - start_point.x) / maxf(float(params["hat_travel_time"]), 0.1)
	_sweep_active = true
	_drop_timer = float(params["drop_interval"])
	player.get_parent().add_child(_sweep_hat)
	_sweep_hat.global_position = start_point


func _update_sweep(delta: float) -> void:
	if not _sweep_active or not is_instance_valid(_sweep_hat):
		return
	_sweep_hat.global_position.x += _sweep_direction * _sweep_speed * delta
	_sweep_hat.global_position.y = _sweep_y
	_drop_timer -= delta
	while _drop_timer <= 0.0:
		_drop_ball(_sweep_hat.global_position)
		_drop_timer += maxf(float(params["drop_interval"]), 0.05)
	var reached_end: bool = _sweep_hat.global_position.x >= _sweep_target_x if _sweep_direction > 0.0 else _sweep_hat.global_position.x <= _sweep_target_x
	if reached_end:
		_sweep_active = false
		_sweep_hat.queue_free()
		_sweep_hat = null


func _drop_ball(origin: Vector2) -> void:
	if _ball_texture == null:
		return
	var ball = Area2D.new()
	ball.name = "PerucxFallingTennisBall"
	ball.set_script(load("res://SCRIPT/punch_hitbox_trab.gd"))
	ball.collision_layer = player.current_hitbox.collision_layer
	ball.collision_mask = player.current_hitbox.collision_mask
	ball.damage = int(params["ball_damage"])
	ball.source = player
	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = _ball_texture
	var ball_scale: float = player.get_visual_height() * float(params["ball_size_ratio"]) / _ball_texture.get_size().y
	sprite.scale = Vector2.ONE * ball_scale
	ball.add_child(sprite)
	var shape := CircleShape2D.new()
	shape.radius = maxf(_ball_texture.get_size().x, _ball_texture.get_size().y) * ball_scale * 0.42
	var collision := CollisionShape2D.new()
	collision.shape = shape
	ball.add_child(collision)
	player.get_parent().add_child(ball)
	ball.global_position = origin + Vector2(0.0, player.get_visual_height() * 0.16)
	ball.area_entered.connect(_on_ball_area_entered.bind(ball))
	_balls.append({"node": ball, "fall_speed": float(params["ball_fall_speed"]), "age": 0.0})


func _on_ball_area_entered(area: Area2D, ball: Area2D) -> void:
	if area is Hurtbox:
		_remove_ball(ball)


func _update_falling_balls(delta: float) -> void:
	var viewport: Viewport = player.get_viewport()
	var world_bottom: float = (viewport.get_canvas_transform().affine_inverse() * viewport.get_visible_rect().size).y
	for entry in _balls.duplicate():
		var ball: Area2D = entry["node"] as Area2D
		if not is_instance_valid(ball):
			_balls.erase(entry)
			continue
		var fall_speed: float = float(entry["fall_speed"]) + float(params["ball_gravity"]) * delta
		entry["fall_speed"] = fall_speed
		entry["age"] = float(entry["age"]) + delta
		ball.global_position.y += fall_speed * delta
		if ball.global_position.y > world_bottom + 100.0 or float(entry["age"]) >= float(params["ball_lifetime"]):
			_remove_ball(ball)


func _remove_ball(ball: Area2D) -> void:
	for entry in _balls:
		if entry["node"] == ball:
			_balls.erase(entry)
			break
	if is_instance_valid(ball):
		ball.queue_free()
