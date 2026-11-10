extends "res://SCRIPT/powers/fighter_power.gd"
## Suprema Deadlift di Nakata: audio cinematografico, pugno caricato e fascio energetico.

const AUDIO_PATH := "res://sound/Effects/deadlift_nakata.mp3"
const HIT_TEXT := "COLPO DEL DRAGO DELLA LUNA NASCENTE INFUOCATO ROTANTE!"
const CHARGE_ANIMATION := &"deadlift_charge"

var _busy := false
var _sequence_id := 0
var _locked_players: Array[Player] = []
var _audio: AudioStreamPlayer
var _overlay: CanvasLayer


func default_params() -> Dictionary:
	return {
		"cooldown": 9999.0,
		"health_ratio_max": 0.10,
		"aura_ratio_required": 1.0,
		"damage": 90,
		"flash_seconds": 0.22,
		"text_seconds": 1.4,
		"animation_fps": 10.0,
		"animation_start_frame": 5,
		"animation_frames": 15,
		"beam_seconds": 0.55,
		"cinematic_zoom": 2.25,
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
	var target := _find_opponent()
	if target == null or not can_use():
		return
	super.use()
	_spend_stamina(player.current_stamina)
	_busy = true
	_sequence_id += 1
	var current_sequence := _sequence_id
	_lock_fighters(target)
	_face_each_other(target)
	_show_letterbox(true)
	var camera: Camera2D = player.get_viewport().get_camera_2d()
	if camera != null and camera.has_method("set_cinematic_focus"):
		camera.call("set_cinematic_focus", player, float(params["cinematic_zoom"]), Vector2(0.0, -28.0))
	if _audio != null and _audio.stream != null:
		_audio.play()
		await _audio.finished
	else:
		await player.get_tree().create_timer(1.0).timeout
	_show_letterbox(false)
	if camera != null and is_instance_valid(camera) and camera.has_method("clear_cinematic_focus"):
		camera.call("clear_cinematic_focus")
	if current_sequence != _sequence_id or not is_instance_valid(target):
		_unlock_fighters()
		_busy = false
		return
	# Il foglio di Nakata si anima lentamente mentre carica il pugno.
	player.current_sprite.play(CHARGE_ANIMATION)
	player.synced_animation = CHARGE_ANIMATION
	await player.current_sprite.animation_finished
	if current_sequence != _sequence_id or not is_instance_valid(target):
		_unlock_fighters()
		_busy = false
		return
	player.current_sprite.play("idle")
	player.synced_animation = "idle"
	await _spawn_energy_beam(target)
	if current_sequence != _sequence_id or not is_instance_valid(target):
		_unlock_fighters()
		_busy = false
		return
	if camera != null and is_instance_valid(camera) and camera.has_method("shake"):
		camera.call("shake", 22.0, 0.55)
	_show_flash()
	_show_text(HIT_TEXT, float(params["text_seconds"]))
	# Il colpo della suprema non può essere ridotto dalla guardia.
	var was_blocking := target.is_blocking
	target.is_blocking = false
	target.combat_locked = false
	target.hurtbox.take_damage(int(params["damage"]), player)
	target.is_blocking = was_blocking
	if not target.is_dead:
		target.combat_locked = true
	await player.get_tree().create_timer(float(params["text_seconds"])).timeout
	if current_sequence == _sequence_id:
		_unlock_fighters()
		_busy = false


func _lock_fighters(target: Player) -> void:
	_locked_players.clear()
	for fighter in [player, target]:
		if is_instance_valid(fighter):
			fighter.combat_locked = true
			fighter.velocity = Vector2.ZERO
			fighter.is_blocking = false
			_locked_players.append(fighter)


func _unlock_fighters() -> void:
	for fighter in _locked_players:
		if is_instance_valid(fighter) and not fighter.is_dead:
			fighter.combat_locked = false
	_locked_players.clear()


func _face_each_other(target: Player) -> void:
	player._set_facing(target.global_position.x < player.global_position.x)
	target._set_facing(player.global_position.x < target.global_position.x)
	player.current_sprite.play("idle")
	player.synced_animation = "idle"
	target.current_sprite.play("idle")
	target.synced_animation = "idle"


func _setup_charge_animation() -> void:
	var frames: SpriteFrames = player.current_sprite.sprite_frames
	if frames == null:
		return
	var texture: Texture2D = load("res://sprite/Player/Nakakata/punc/nakakata-punch.png") as Texture2D
	if texture == null:
		push_warning("Deadlift: foglio animazione del pugno di Nakata non trovato")
		return
	if frames.has_animation(CHARGE_ANIMATION):
		frames.remove_animation(CHARGE_ANIMATION)
	frames.add_animation(CHARGE_ANIMATION)
	frames.set_animation_loop(CHARGE_ANIMATION, false)
	frames.set_animation_speed(CHARGE_ANIMATION, maxf(float(params["animation_fps"]), 1.0))
	var first_frame: int = int(params["animation_start_frame"])
	for frame_offset in range(int(params["animation_frames"])):
		var frame_index: int = first_frame + frame_offset
		if frame_index >= 25:
			break
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = texture
		atlas.region = Rect2((frame_index % 5) * 256, (frame_index / 5) * 256, 256, 256)
		frames.add_frame(CHARGE_ANIMATION, atlas)


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
		bar.offset_bottom = 62.0 if is_top else 0.0
		bar.anchor_top = 0.0 if is_top else 1.0
		bar.anchor_bottom = 0.0 if is_top else 1.0
		bar.offset_top = 0.0 if is_top else -62.0
		_overlay.add_child(bar)
		var tween := bar.create_tween()
		tween.tween_property(bar, "size:y", minf(viewport_height * 0.11, 78.0), 0.25)


func _spawn_energy_beam(target: Player) -> void:
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		return
	var direction: float = -1.0 if player.current_sprite.flip_h else 1.0
	var start: Vector2 = player.current_sprite.global_position + Vector2(65.0 * direction, -50.0)
	var finish: Vector2 = target.global_position + Vector2(-direction * 30.0, -42.0)
	var beam_root: Node2D = Node2D.new()
	beam_root.name = "NakataDragonEnergy"
	scene_root.add_child(beam_root)
	var beam_styles: Array[Dictionary] = [
		{"width": 104.0, "color": Color(1.0, 0.24, 0.025, 0.32)},
		{"width": 72.0, "color": Color(1.0, 0.48, 0.035, 0.64)},
		{"width": 46.0, "color": Color(1.0, 0.82, 0.12, 0.88)},
		{"width": 24.0, "color": Color(1.0, 0.98, 0.72, 1.0)},
		{"width": 9.0, "color": Color(1.0, 1.0, 1.0, 1.0)},
	]
	for style: Dictionary in beam_styles:
		var beam: Line2D = Line2D.new()
		beam.width = float(style["width"])
		beam.default_color = style["color"]
		beam.begin_cap_mode = Line2D.LINE_CAP_ROUND
		beam.end_cap_mode = Line2D.LINE_CAP_ROUND
		beam.add_point(start)
		beam.add_point(start)
		beam_root.add_child(beam)
		var tween: Tween = beam.create_tween()
		tween.tween_method(_set_beam_progress.bind(beam, start, finish), 0.0, 1.0, 0.2)
		tween.tween_interval(float(params["beam_seconds"]))
		tween.tween_property(beam, "modulate:a", 0.0, 0.35)
		tween.tween_callback(beam.queue_free)
	_spawn_energy_arcs(beam_root, start, finish)
	_spawn_impact_burst(scene_root, finish)
	var cleanup: Tween = beam_root.create_tween()
	cleanup.tween_interval(float(params["beam_seconds"]) + 0.8)
	cleanup.tween_callback(beam_root.queue_free)
	await player.get_tree().create_timer(0.2).timeout


func _set_beam_progress(progress: float, beam: Line2D, start: Vector2, finish: Vector2) -> void:
	if is_instance_valid(beam):
		beam.set_point_position(1, start.lerp(finish, progress))


func _spawn_energy_arcs(parent: Node2D, start: Vector2, finish: Vector2) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	for arc_index in range(5):
		var arc: Line2D = Line2D.new()
		arc.width = 5.0 if arc_index % 2 == 0 else 3.0
		arc.default_color = Color(0.5, 0.88, 1.0, 0.95) if arc_index % 2 == 0 else Color(1.0, 0.94, 0.62, 0.95)
		arc.begin_cap_mode = Line2D.LINE_CAP_ROUND
		arc.end_cap_mode = Line2D.LINE_CAP_ROUND
		var side: float = -1.0 if arc_index % 2 == 0 else 1.0
		for point_index in range(9):
			var progress: float = float(point_index) / 8.0
			var base: Vector2 = start.lerp(finish, progress)
			var envelope: float = sin(progress * PI) * 30.0
			var jitter: float = rng.randf_range(-envelope, envelope)
			arc.add_point(base + Vector2(0.0, side * envelope + jitter))
		parent.add_child(arc)
		var tween: Tween = arc.create_tween()
		tween.tween_interval(0.2 + rng.randf_range(0.0, 0.12))
		tween.tween_property(arc, "modulate:a", 0.0, 0.28)
		tween.tween_callback(arc.queue_free)


func _spawn_impact_burst(scene_root: Node, center: Vector2) -> void:
	var burst: Node2D = Node2D.new()
	burst.name = "NakataDragonImpact"
	burst.global_position = center
	scene_root.add_child(burst)
	var rays: Polygon2D = Polygon2D.new()
	rays.color = Color(1.0, 0.62, 0.08, 0.96)
	var ray_points: PackedVector2Array = PackedVector2Array()
	for i in range(48):
		var angle: float = TAU * float(i) / 48.0
		var radius: float = 115.0 if i % 2 == 0 else 54.0
		ray_points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	rays.polygon = ray_points
	burst.add_child(rays)
	var core: Polygon2D = Polygon2D.new()
	core.color = Color(1.0, 0.98, 0.82, 1.0)
	var core_points: PackedVector2Array = PackedVector2Array()
	for i in range(32):
		var angle: float = TAU * float(i) / 32.0
		core_points.append(Vector2(cos(angle) * 38.0, sin(angle) * 38.0))
	core.polygon = core_points
	burst.add_child(core)
	var ring: Line2D = Line2D.new()
	ring.width = 12.0
	ring.default_color = Color(1.0, 0.94, 0.55, 1.0)
	ring.closed = true
	for i in range(49):
		var angle: float = TAU * float(i) / 48.0
		ring.add_point(Vector2(cos(angle), sin(angle)))
	burst.add_child(ring)
	var tween: Tween = burst.create_tween()
	tween.set_parallel(true)
	tween.tween_property(burst, "scale", Vector2(2.8, 2.8), 0.42).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.2)
	tween.tween_property(burst, "modulate:a", 0.0, 0.5).set_delay(0.32)
	tween.chain().tween_callback(burst.queue_free)


func _show_text(message: String, duration: float) -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	label.add_theme_font_size_override("font_size", 34 if message == HIT_TEXT else 44)
	label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.55))
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1))
	label.add_theme_constant_override("outline_size", 10)
	_overlay.add_child(label)
	get_tree().create_timer(duration).timeout.connect(label.queue_free)


func _show_flash() -> void:
	if _overlay == null or not is_instance_valid(_overlay):
		return
	var flash := ColorRect.new()
	flash.color = Color.WHITE
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(flash)
	var tween := flash.create_tween()
	tween.tween_property(flash, "modulate:a", 0.0, float(params["flash_seconds"]))
	tween.tween_callback(flash.queue_free)


func _find_opponent() -> Player:
	var closest: Player = null
	var closest_distance := INF
	for node in player.get_parent().get_children():
		if node is Player and node != player and not node.is_dead and node.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(node.global_position)
			if distance < closest_distance:
				closest = node
				closest_distance = distance
	return closest
