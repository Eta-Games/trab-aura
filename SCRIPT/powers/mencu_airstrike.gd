extends "res://SCRIPT/powers/fighter_power.gd"
## Deathlift del Mencu: sequenza cinematografica, salto e detonazione nucleare.

const AUDIO_PATH := "res://sound/Effects/nuke-bomb.mp3"
const JUMP_ANIMATION := &"deathlift_jump"
const INTRO_TEXT := "DEATHLIFT DEL MENCU!"
const HIT_TEXT := "ESPLOSIONE NUCLEARE!"

var _busy := false
var _audio: AudioStreamPlayer
var _overlay: CanvasLayer


func default_params() -> Dictionary:
	return {
		"cooldown": 9999.0,
		"health_ratio_max": 0.10,
		"aura_ratio_required": 1.0,
		"damage": 100,
		"flash_seconds": 0.22,
		"text_seconds": 1.4,
		"jump_height": 520.0,
		"jump_seconds": 0.8,
		"hover_seconds": 0.35,
		"blast_radius": 420.0,
		"cinematic_zoom": 0.9,
		"impact_zoom": 1.3,
		"audio": AUDIO_PATH,
	}


func _on_setup() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "DeadliftAudio"
	_audio.stream = load(str(params.get("audio", AUDIO_PATH))) as AudioStream
	add_child(_audio)
	_overlay = CanvasLayer.new()
	_overlay.name = "DeadliftOverlay"
	_overlay.layer = 10
	add_child(_overlay)
	_setup_jump_animation()


func can_use() -> bool:
	if player == null or _busy or player.max_health <= 0:
		return false
	var under_limit: bool = float(player.current_health) / float(player.max_health) < float(params["health_ratio_max"])
	var aura_full: bool = player.max_stamina > 0.0 and player.current_stamina >= player.max_stamina * float(params["aura_ratio_required"])
	return under_limit and aura_full and cooldown_left <= 0.0


func is_busy() -> bool:
	return _busy


func is_deadlift() -> bool:
	return true


func use() -> void:
	var target: Player = _find_opponent()
	if target == null or not can_use():
		return
	super.use()
	_spend_stamina(player.current_stamina)
	_busy = true
	_run_deathlift(target)


func _run_deathlift(target: Player) -> void:
	var scene: Node = player.get_tree().current_scene
	if scene == null:
		_busy = false
		return

	var camera: Camera2D = player.get_viewport().get_camera_2d()
	var saved_offset: Vector2 = camera.offset if camera != null else Vector2.ZERO
	var camera_anchor: Node2D = Node2D.new()
	camera_anchor.name = "MencuDeathliftCameraAnchor"
	# Punto medio fissato a terra prima del salto: non segue l'altezza del Mencu.
	camera_anchor.global_position = (player.global_position + target.global_position) * 0.5
	scene.add_child(camera_anchor)
	_show_letterbox(true)
	_lock_fighters(target)
	_face_each_other(target)
	if camera != null and camera.has_method("set_cinematic_focus"):
		camera.call("set_cinematic_focus", camera_anchor, float(params["cinematic_zoom"]), Vector2(0.0, -30.0))
	_show_text(INTRO_TEXT, 1.1)
	if _audio != null and _audio.stream != null:
		_audio.play()
	else:
		await player.get_tree().create_timer(0.35).timeout

	var launch_from: Vector2 = player.global_position
	var peak: Vector2 = launch_from + Vector2(0.0, -float(params["jump_height"]))
	if player.current_sprite.sprite_frames != null and player.current_sprite.sprite_frames.has_animation(JUMP_ANIMATION):
		player.current_sprite.play(JUMP_ANIMATION)
		player.synced_animation = JUMP_ANIMATION
	var rise: Tween = player.get_tree().create_tween()
	rise.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	rise.tween_property(player, "global_position", peak, float(params["jump_seconds"]) * 0.5)
	await rise.finished
	if not is_instance_valid(player) or not is_instance_valid(target):
		_finish(camera, saved_offset, camera_anchor, target)
		return
	await player.get_tree().create_timer(float(params["hover_seconds"])).timeout
	var fall: Tween = player.get_tree().create_tween()
	fall.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	fall.tween_property(player, "global_position", launch_from, float(params["jump_seconds"]) * 0.5)
	await fall.finished
	if not is_instance_valid(player) or not is_instance_valid(target):
		_finish(camera, saved_offset, camera_anchor, target)
		return
	player.current_sprite.play("idle")
	player.synced_animation = "idle"

	if camera != null and is_instance_valid(camera) and camera.has_method("set_cinematic_focus"):
		camera.call("set_cinematic_focus", camera_anchor, float(params["impact_zoom"]), Vector2(0.0, -70.0))
	var impact_position: Vector2 = _get_feet_position(player)
	_spawn_nuclear_blast(scene, impact_position, float(params["blast_radius"]))
	if camera != null and is_instance_valid(camera) and camera.has_method("shake"):
		camera.call("shake", 18.0, 0.45)
	_show_flash()
	_show_text(HIT_TEXT, float(params["text_seconds"]))
	# Come per Nakakata, il Deathlift ignora la guardia e applica il danno all'impatto.
	target.is_blocking = false
	target.combat_locked = false
	if _get_feet_position(target).distance_to(impact_position) <= float(params["blast_radius"]):
		target.hurtbox.take_damage(int(params["damage"]), player)
	await player.get_tree().create_timer(float(params["text_seconds"])).timeout
	_finish(camera, saved_offset, camera_anchor, target)


func _lock_fighters(target: Player) -> void:
	for fighter: Player in [player, target]:
		if is_instance_valid(fighter):
			fighter.combat_locked = true
			fighter.velocity = Vector2.ZERO
			fighter.is_blocking = false


func _face_each_other(target: Player) -> void:
	player._set_facing(target.global_position.x < player.global_position.x)
	target._set_facing(player.global_position.x < target.global_position.x)
	player.current_sprite.play("idle")
	player.synced_animation = "idle"
	target.current_sprite.play("idle")
	target.synced_animation = "idle"


func _setup_jump_animation() -> void:
	var frames: SpriteFrames = player.current_sprite.sprite_frames
	if frames == null or frames.has_animation(JUMP_ANIMATION):
		return
	var sheet: Texture2D = load("res://sprite/Player/IlMencu/mega_jump.png") as Texture2D
	if sheet == null:
		push_warning("Deathlift Mencu: spritesheet del salto non trovato")
		return
	frames.add_animation(JUMP_ANIMATION)
	frames.set_animation_loop(JUMP_ANIMATION, false)
	frames.set_animation_speed(JUMP_ANIMATION, 16.0)
	for frame_index in range(15):
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2((frame_index % 5) * 256, (frame_index / 5) * 256, 256, 256)
		frames.add_frame(JUMP_ANIMATION, atlas)


func _show_letterbox(show_bars: bool) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	for child in _overlay.get_children():
		if child.name == "CinemaTop" or child.name == "CinemaBottom":
			child.queue_free()
	if not show_bars:
		return
	var viewport_height: float = player.get_viewport_rect().size.y
	for is_top in [true, false]:
		var bar: ColorRect = ColorRect.new()
		bar.name = "CinemaTop" if is_top else "CinemaBottom"
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.offset_bottom = 62.0 if is_top else 0.0
		bar.anchor_top = 0.0 if is_top else 1.0
		bar.anchor_bottom = 0.0 if is_top else 1.0
		bar.offset_top = 0.0 if is_top else -62.0
		_overlay.add_child(bar)
		var tween: Tween = bar.create_tween()
		tween.tween_property(bar, "size:y", minf(viewport_height * 0.11, 78.0), 0.25)


func _show_text(message: String, duration: float) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var label: Label = Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 44)
	label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.55))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1))
	label.add_theme_constant_override("outline_size", 10)
	_overlay.add_child(label)
	get_tree().create_timer(duration).timeout.connect(label.queue_free)


func _show_flash() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var flash: ColorRect = ColorRect.new()
	flash.color = Color.WHITE
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(flash)
	var tween: Tween = flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, float(params["flash_seconds"]))
	tween.tween_callback(flash.queue_free)


func _get_feet_position(fighter: Player) -> Vector2:
	var collision: CollisionShape2D = fighter.get_node_or_null("collision") as CollisionShape2D
	if collision == null or collision.shape == null:
		return fighter.global_position
	var half_height: float = collision.shape.get_rect().size.y * absf(collision.global_scale.y) * 0.5
	return Vector2(collision.global_position.x, collision.global_position.y + half_height)


func _spawn_nuclear_blast(scene: Node, center: Vector2, blast_radius: float) -> void:
	_spawn_shockwave(scene, center, blast_radius)
	var mushroom: Node2D = Node2D.new()
	mushroom.name = "MencuNuclearBlast"
	mushroom.global_position = center
	scene.add_child(mushroom)
	var stem: Polygon2D = Polygon2D.new()
	stem.color = Color(1.0, 0.72, 0.22, 0.92)
	stem.polygon = PackedVector2Array([Vector2(-34, 0), Vector2(34, 0), Vector2(76, -300), Vector2(-76, -300)])
	mushroom.add_child(stem)
	var cap: Polygon2D = Polygon2D.new()
	cap.color = Color(1.0, 0.48, 0.12, 0.95)
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(32):
		var angle: float = TAU * float(i) / 32.0
		points.append(Vector2(cos(angle) * 175.0, -340.0 + sin(angle) * 115.0))
	cap.polygon = points
	mushroom.add_child(cap)
	var tween: Tween = mushroom.create_tween()
	tween.set_parallel(true)
	tween.tween_property(mushroom, "scale", Vector2(2.3, 2.3), 1.0)
	tween.tween_property(mushroom, "modulate:a", 0.0, 1.25).set_delay(0.25)
	tween.chain().tween_callback(mushroom.queue_free)


func _spawn_shockwave(scene: Node, center: Vector2, blast_radius: float) -> void:
	# Il bordo arriva esattamente al limite usato dal controllo dei danni.
	var wave: Node2D = Node2D.new()
	wave.name = "MencuNuclearShockwave"
	wave.global_position = center
	scene.add_child(wave)
	for style in [
		{"width": 22.0, "color": Color(1.0, 0.42, 0.08, 0.38)},
		{"width": 9.0, "color": Color(1.0, 0.94, 0.62, 0.98)},
	]:
		var ring: Line2D = Line2D.new()
		ring.width = float(style["width"])
		ring.default_color = style["color"]
		ring.closed = true
		ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ring.end_cap_mode = Line2D.LINE_CAP_ROUND
		for i in range(65):
			var angle: float = TAU * float(i) / 64.0
			ring.add_point(Vector2(cos(angle), sin(angle)))
		wave.add_child(ring)
	var tween: Tween = wave.create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "scale", Vector2(blast_radius, blast_radius), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(wave, "modulate:a", 0.0, 0.65).set_delay(0.2)
	tween.chain().tween_callback(wave.queue_free)


func _find_opponent() -> Player:
	var closest: Player = null
	var closest_distance: float = INF
	# I due combattenti sono fratelli nella scena di gioco; non sono nel gruppo "players".
	for candidate: Node in player.get_parent().get_children():
		if candidate is Player and candidate != player and not candidate.is_dead and candidate.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(candidate.global_position)
			if distance < closest_distance:
				closest = candidate
				closest_distance = distance
	return closest


func _finish(camera: Camera2D, saved_offset: Vector2, camera_anchor: Node2D, target: Player) -> void:
	if camera != null and is_instance_valid(camera):
		camera.clear_cinematic_focus()
		camera.offset = saved_offset
	if is_instance_valid(camera_anchor):
		camera_anchor.queue_free()
	_show_letterbox(false)
	for fighter: Player in [player, target]:
		if is_instance_valid(fighter) and not fighter.is_dead:
			fighter.combat_locked = false
	_busy = false
