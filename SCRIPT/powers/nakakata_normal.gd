extends "res://SCRIPT/powers/fighter_power.gd"

const SLIDE_ANIMATION: StringName = &"nakakata_secondary_slide"
const SLIDE_TEXTURE_PATH := "res://sprite/Player/Nakakata/Secondary/naka-slide.png"

var _busy: bool = false


func default_params() -> Dictionary:
	return {
		"cooldown": 5.0,
		"stamina_min": 40.0,
		"stamina_cost": 40.0,
		"damage": 40,
		"slow_duration": 10.0,
		"slow_multiplier": 0.5,
		"slide_duration": 1.0,
		"animation_fps": 25.0,
		"behind_margin": 12.0,
	}


func _on_setup() -> void:
	_setup_slide_animation()


func _setup_slide_animation() -> void:
	var frames: SpriteFrames = player.current_sprite.sprite_frames
	if frames == null or frames.has_animation(SLIDE_ANIMATION):
		return
	var sheet: Texture2D = load(SLIDE_TEXTURE_PATH) as Texture2D
	if sheet == null:
		push_warning("Nakakata: sprite sheet dello scivolamento non trovato: %s" % SLIDE_TEXTURE_PATH)
		return
	frames.add_animation(SLIDE_ANIMATION)
	frames.set_animation_loop(SLIDE_ANIMATION, false)
	frames.set_animation_speed(SLIDE_ANIMATION, float(params["animation_fps"]))
	for index in range(25):
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2((index % 5) * 256, int(index / 5) * 256, 256, 256)
		frames.add_frame(SLIDE_ANIMATION, atlas)


func can_use() -> bool:
	return not _busy and cooldown_left <= 0.0 \
		and _has_stamina(float(params["stamina_min"]))


func is_busy() -> bool:
	return _busy


func use() -> void:
	if not can_use() or not player.is_on_floor() or player.isAttacking:
		return
	var target: Player = _find_opponent()
	if target == null or not player.current_sprite.sprite_frames.has_animation(SLIDE_ANIMATION):
		return
	super.use()
	_busy = true
	_slide_behind(target)


func _slide_behind(target: Player) -> void:
	var back_direction: float = -target.get_facing_dir()
	var stand_off: float = _body_half_width(player) + _body_half_width(target) \
		+ float(params["behind_margin"])
	var start_x: float = player.global_position.x
	var saved_z_index: int = player.current_sprite.z_index
	player.current_sprite.z_index = target.current_sprite.z_index - 1
	player._set_facing((target.global_position.x + back_direction * stand_off) < start_x)
	player.current_sprite.play(SLIDE_ANIMATION)
	player.synced_animation = String(SLIDE_ANIMATION)

	var slide: Tween = player.get_tree().create_tween()
	slide.tween_method(
		_set_slide_progress.bind(start_x, target, back_direction, stand_off),
		0.0, 1.0, float(params["slide_duration"])
	).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	await slide.finished

	if is_instance_valid(target) and not target.is_dead and target.current_health > 0:
		# Allinea il punto finale alla posizione attuale del bersaglio se si è mosso.
		player.global_position.x = target.global_position.x + back_direction * stand_off
		player._set_facing(target.global_position.x < player.global_position.x)
		var was_blocking: bool = target.is_blocking
		target.is_blocking = false
		target.hurtbox.take_damage(int(params["damage"]), player)
		target.is_blocking = was_blocking
		if not target.is_dead:
			target.apply_slow(float(params["slow_duration"]), float(params["slow_multiplier"]))

	player.current_sprite.z_index = saved_z_index
	if is_instance_valid(player) and not player.is_dead:
		player.current_sprite.play("idle")
		player.synced_animation = "idle"
	_busy = false


func _set_slide_progress(progress: float, start_x: float, target: Player, back_direction: float, stand_off: float) -> void:
	if not is_instance_valid(player):
		return
	var target_x: float = target.global_position.x if is_instance_valid(target) else start_x
	var destination_x: float = target_x + back_direction * stand_off
	player.global_position.x = lerpf(start_x, destination_x, progress)


func _body_half_width(fighter: Player) -> float:
	var body_shape: CollisionShape2D = fighter.get_node_or_null("collision") as CollisionShape2D
	if body_shape != null and body_shape.shape != null:
		return body_shape.shape.get_rect().size.x * absf(body_shape.global_scale.x) * 0.5
	return 18.0


func _find_opponent() -> Player:
	var closest: Player = null
	var closest_distance: float = INF
	for candidate: Node in player.get_tree().get_nodes_in_group("players"):
		if candidate is Player and candidate != player and not candidate.is_dead and candidate.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(candidate.global_position)
			if distance < closest_distance:
				closest = candidate
				closest_distance = distance
	return closest
