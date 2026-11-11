extends "res://SCRIPT/powers/fighter_power.gd"
## Deathlift di Perux: carica il colpo e scatena un'onda sonora crescente.

const AUDIO_PATH := "res://sound/Effects/perux_ambush_spawn.mp3"
const CHARGE_ANIMATION := &"deathlift_charge"
const CHARGE_SHEET := "res://sprite/Player/Perucx/perux-attack.png"
const CHARGE_TEXT := "PERUX STA CARICANDO..."
const HIT_TEXT := "ONDA SONORA!"

var _busy := false
var _audio: AudioStreamPlayer
var _overlay: CanvasLayer


func default_params() -> Dictionary:
	return {
		"cooldown": 9999.0,
		"health_ratio_max": 0.10,
		"aura_ratio_required": 1.0,
		"damage": 6,
		"dot_interval": 1.0,
		"dot_damage_start": 1,
		"dot_damage_ramp": 1,
		"dot_ticks": 8,
		"flash_seconds": 0.24,
		"text_seconds": 1.2,
		"animation_fps": 12.0,
		"cinematic_zoom": 2.1,
		"audio": AUDIO_PATH,
	}


func _on_setup() -> void:
	_audio = AudioStreamPlayer.new()
	_audio.name = "DeathliftAudio"
	_audio.stream = load(str(params.get("audio", AUDIO_PATH))) as AudioStream
	add_child(_audio)
	_overlay = CanvasLayer.new()
	_overlay.name = "DeathliftOverlay"
	_overlay.layer = 10
	add_child(_overlay)
	_setup_charge_animation()


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
	var camera_anchor := Node2D.new()
	camera_anchor.name = "PeruxDeathliftCameraAnchor"
	camera_anchor.global_position = (player.global_position + target.global_position) * 0.5
	scene.add_child(camera_anchor)
	_lock_fighters(target)
	_face_each_other(target)
	_show_letterbox(true)
	_show_text(CHARGE_TEXT, 1.5)
	if camera != null and camera.has_method("set_cinematic_focus"):
		camera.call("set_cinematic_focus", camera_anchor, float(params["cinematic_zoom"]), Vector2(0.0, -28.0))

	player.current_sprite.play(CHARGE_ANIMATION)
	player.synced_animation = CHARGE_ANIMATION
	await player.current_sprite.animation_finished
	if not is_instance_valid(player) or not is_instance_valid(target):
		_finish(camera, saved_offset, camera_anchor, target)
		return

	player.current_sprite.play("idle")
	player.synced_animation = "idle"
	_show_letterbox(false)
	_show_text(HIT_TEXT, float(params["text_seconds"]))
	if _audio != null and _audio.stream != null:
		_audio.play()
	var impact: Vector2 = target.global_position + Vector2(0.0, -target.get_visual_height() * 0.46)
	_spawn_sound_wave(scene, player.global_position + Vector2(0.0, -player.get_visual_height() * 0.48), impact)
	await player.get_tree().create_timer(0.38).timeout
	if not is_instance_valid(player) or not is_instance_valid(target):
		_finish(camera, saved_offset, camera_anchor, target)
		return

	if camera != null and is_instance_valid(camera) and camera.has_method("shake"):
		camera.call("shake", 12.0, 0.32)
	_show_flash()
	var was_blocking: bool = target.is_blocking
	target.is_blocking = false
	target.combat_locked = false
	target.hurtbox.take_damage(int(params["damage"]), player)
	if not target.is_dead:
		target.combat_locked = true
		target.is_blocking = was_blocking
	_unlock_fighters([player, target])
	_apply_ramping_dot(target)
	_finish(camera, saved_offset, camera_anchor, target)


func _setup_charge_animation() -> void:
	var frames: SpriteFrames = player.current_sprite.sprite_frames
	if frames == null:
		return
	var texture: Texture2D = load(CHARGE_SHEET) as Texture2D
	if texture == null:
		push_warning("Deathlift Perux: foglio animazione non trovato")
		return
	if frames.has_animation(CHARGE_ANIMATION):
		frames.remove_animation(CHARGE_ANIMATION)
	frames.add_animation(CHARGE_ANIMATION)
	frames.set_animation_loop(CHARGE_ANIMATION, false)
	frames.set_animation_speed(CHARGE_ANIMATION, maxf(float(params["animation_fps"]), 1.0))
	for frame_index in range(25):
		var atlas := AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2((frame_index % 5) * 256, (frame_index / 5) * 256, 256, 256)
		frames.add_frame(CHARGE_ANIMATION, atlas)


func _lock_fighters(target: Player) -> void:
	for fighter: Player in [player, target]:
		if is_instance_valid(fighter):
			fighter.combat_locked = true
			fighter.velocity = Vector2.ZERO
			fighter.is_blocking = false


func _face_each_other(target: Player) -> void:
	player._set_facing(target.global_position.x < player.global_position.x)
	target._set_facing(player.global_position.x < target.global_position.x)
	target.current_sprite.play("idle")
	target.synced_animation = "idle"


func _spawn_sound_wave(scene: Node, start: Vector2, finish: Vector2) -> void:
	var wave := Node2D.new()
	wave.name = "PeruxSoundWave"
	wave.global_position = start
	scene.add_child(wave)
	for style: Dictionary in [
		{"radius": 20.0, "width": 10.0, "color": Color(0.55, 0.94, 1.0, 0.95)},
		{"radius": 38.0, "width": 7.0, "color": Color(0.75, 0.83, 1.0, 0.8)},
		{"radius": 58.0, "width": 4.0, "color": Color(1.0, 0.96, 0.72, 0.72)},
	]:
		var ring := Line2D.new()
		ring.width = float(style["width"])
		ring.default_color = style["color"]
		ring.closed = true
		ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
		ring.end_cap_mode = Line2D.LINE_CAP_ROUND
		for point_index in range(33):
			var angle: float = TAU * float(point_index) / 32.0
			ring.add_point(Vector2(cos(angle), sin(angle)) * float(style["radius"]))
		wave.add_child(ring)
	var tween := wave.create_tween()
	tween.set_parallel(true)
	tween.tween_property(wave, "global_position", finish, 0.38).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(wave, "scale", Vector2(1.8, 1.8), 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(wave, "modulate:a", 0.0, 0.42).set_delay(0.28)
	tween.chain().tween_callback(wave.queue_free)


func _apply_ramping_dot(target: Player) -> void:
	var interval: float = maxf(float(params["dot_interval"]), 0.1)
	var base_damage: int = int(params["dot_damage_start"])
	var ramp: int = int(params["dot_damage_ramp"])
	var ticks: int = maxi(int(params["dot_ticks"]), 0)
	for tick in range(ticks):
		await player.get_tree().create_timer(interval).timeout
		if not is_instance_valid(player) or not is_instance_valid(target) or target.is_dead:
			return
		target.hurtbox.take_damage(base_damage + tick * ramp, player)
		_spawn_status_pulse(target, float(tick + 1) / float(maxi(ticks, 1)))


func _spawn_status_pulse(target: Player, intensity: float) -> void:
	var pulse := Node2D.new()
	pulse.name = "PeruxSonicPulse"
	pulse.position = Vector2(0.0, -target.get_visual_height() * 0.48)
	target.add_child(pulse)
	var ring := Line2D.new()
	ring.width = 3.0 + intensity * 3.0
	ring.default_color = Color(0.42, 0.9, 1.0, 0.9)
	ring.closed = true
	for point_index in range(33):
		var angle: float = TAU * float(point_index) / 32.0
		ring.add_point(Vector2(cos(angle), sin(angle)) * 26.0)
	pulse.add_child(ring)
	var tween := pulse.create_tween()
	tween.set_parallel(true)
	tween.tween_property(pulse, "scale", Vector2(2.0 + intensity, 2.0 + intensity), 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(pulse, "modulate:a", 0.0, 0.42)
	tween.chain().tween_callback(pulse.queue_free)


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
		var bar := ColorRect.new()
		bar.name = "CinemaTop" if is_top else "CinemaBottom"
		bar.color = Color.BLACK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_right = 1.0
		bar.anchor_top = 0.0 if is_top else 1.0
		bar.anchor_bottom = bar.anchor_top
		bar.offset_bottom = 62.0 if is_top else 0.0
		bar.offset_top = 0.0 if is_top else -62.0
		_overlay.add_child(bar)
		var tween := bar.create_tween()
		tween.tween_property(bar, "size:y", minf(viewport_height * 0.11, 78.0), 0.25)


func _show_text(message: String, duration: float) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 34 if message == HIT_TEXT else 42)
	label.add_theme_color_override("font_color", Color(0.72, 0.96, 1.0) if message == HIT_TEXT else Color(1.0, 0.94, 0.55))
	label.add_theme_color_override("font_outline_color", Color(0.03, 0.04, 0.13))
	label.add_theme_constant_override("outline_size", 9)
	_overlay.add_child(label)
	get_tree().create_timer(duration).timeout.connect(label.queue_free)


func _show_flash() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var flash := ColorRect.new()
	flash.color = Color(0.75, 0.95, 1.0, 0.9)
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, float(params["flash_seconds"]))
	tween.tween_callback(flash.queue_free)


func _unlock_fighters(fighters: Array) -> void:
	for fighter in fighters:
		if is_instance_valid(fighter) and not fighter.is_dead:
			fighter.combat_locked = false
	_busy = false


func _finish(camera: Camera2D, saved_offset: Vector2, camera_anchor: Node2D, target: Player) -> void:
	if camera != null and is_instance_valid(camera):
		if camera.has_method("clear_cinematic_focus"):
			camera.call("clear_cinematic_focus")
		camera.offset = saved_offset
	_unlock_fighters([player, target])
	_show_letterbox(false)
	if _overlay != null and is_instance_valid(_overlay):
		for child in _overlay.get_children():
			child.queue_free()
	if is_instance_valid(camera_anchor):
		camera_anchor.queue_free()
	_busy = false


func _find_opponent() -> Player:
	var closest: Player = null
	var closest_distance: float = INF
	for candidate: Node in player.get_parent().get_children():
		if candidate is Player and candidate != player and not candidate.is_dead and candidate.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(candidate.global_position)
			if distance < closest_distance:
				closest = candidate
				closest_distance = distance
	return closest
