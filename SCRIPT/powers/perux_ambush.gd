extends "res://SCRIPT/powers/fighter_power.gd"
# Perux svanisce nella nebbia, poi appare alle spalle dell'avversario.
# Se l'avversario si gira verso il punto di apparizione durante l'attesa,
# anticipa la mossa: la nebbia svanisce e Perux resta stordito.

var _target: Player
var _phase: String = ""
var _phase_left: float = 0.0
var _target_initial_facing: float = 1.0
var _spawn_side: float = -1.0
var _fog: CanvasLayer
var _sprite_was_visible: bool = true
var _remote_visual_active: bool = false
var _remote_sprite_was_visible: bool = true
var _remote_fog: CanvasLayer
var _last_remote_effect: String = ""
var _spawn_sfx: AudioStreamPlayer


func _on_setup() -> void:
	var spawn_sound: AudioStream = load("res://sound/Effects/perux_ambush_spawn.mp3") as AudioStream
	if spawn_sound == null:
		push_warning("Perux: suono di apparizione non trovato")
		return
	_spawn_sfx = AudioStreamPlayer.new()
	_spawn_sfx.name = "AmbushSpawnSound"
	_spawn_sfx.bus = "Master"
	_spawn_sfx.stream = spawn_sound
	add_child(_spawn_sfx)


func default_params() -> Dictionary:
	return {
		"cooldown": 18.0,
		"stamina_min": 75.0,
		"stamina_cost": 75.0,
		"windup": 2.0,
		"damage": 30,
		"teleport_offset": 72.0,
		"counter_stun": 1.0,
	}


func can_use() -> bool:
	return _find_opponent() != null and super.can_use()


func is_busy() -> bool:
	return not _phase.is_empty()


func use() -> void:
	_target = _find_opponent()
	if not is_instance_valid(_target):
		return

	super.use()
	player.velocity.x = 0.0
	player.is_blocking = false
	_target_initial_facing = _target.get_facing_dir()
	_spawn_side = -_target_initial_facing
	_phase_left = maxf(float(params["windup"]), 0.1)
	_phase = "windup"
	player.synced_power_effect = "perux_ambush_mist"
	_sprite_was_visible = player.current_sprite.visible
	if GameState.visual_effects:
		player.current_sprite.visible = false
	_fog = _spawn_mist(player.global_position)


func on_player_hit() -> void:
	if not is_busy():
		return
	_phase = ""
	_phase_left = 0.0
	player.synced_power_effect = ""
	_target = null
	_fade_mist(_fog, 0.2)
	_fog = null
	player.current_sprite.visible = _sprite_was_visible


func _update_power(delta: float) -> void:
	if _phase != "windup":
		return
	if not is_instance_valid(_target) or _target.is_dead or _target.current_health <= 0:
		_cancel_windup()
		return

	# Il lato di apparizione resta fissato all'inizio: il difensore deve girarsi
	# verso quel lato durante i due secondi di nebbia per interrompere l'attacco.
	var target_facing: float = _target.get_facing_dir()
	if target_facing == _spawn_side and target_facing != _target_initial_facing:
		_countered()
		return

	_phase_left = maxf(_phase_left - delta, 0.0)
	if _phase_left == 0.0:
		_strike()


func _strike() -> void:
	if not is_instance_valid(_target):
		_cancel_windup()
		return

	var destination := Vector2(
		_target.global_position.x + _spawn_side * float(params["teleport_offset"]),
		_target.global_position.y
	)
	_fade_mist(_fog, 0.35)
	_fog = null
	player.global_position = destination
	player.velocity = Vector2.ZERO
	player._set_facing(_spawn_side > 0.0)
	player.current_sprite.visible = _sprite_was_visible
	if player.current_sprite.sprite_frames != null and player.current_sprite.sprite_frames.has_animation("hit"):
		player.current_sprite.play("hit")
		player.synced_animation = "hit"
	_play_spawn_sound()
	_phase = ""
	_phase_left = 0.0
	_publish_spawn_event()

	_target.hurtbox.take_damage(int(params["damage"]), player)
	_target = null


func _countered() -> void:
	_fade_mist(_fog, 0.15)
	_fog = null
	_phase = ""
	_phase_left = 0.0
	_publish_spawn_event()
	_target = null
	player.current_sprite.visible = _sprite_was_visible
	player.velocity = Vector2.ZERO
	player.is_blocking = false
	_play_spawn_sound()
	player.hurt_stun_left = maxf(player.hurt_stun_left, float(params["counter_stun"]))
	player.isHurt = true
	if player.current_sprite.sprite_frames != null and player.current_sprite.sprite_frames.has_animation("hit"):
		player.current_sprite.play("hit")
		player.synced_animation = "hit"


func _cancel_windup() -> void:
	_fade_mist(_fog, 0.2)
	_fog = null
	_phase = ""
	_phase_left = 0.0
	player.synced_power_effect = ""
	_target = null
	player.current_sprite.visible = _sprite_was_visible


func _play_spawn_sound() -> void:
	if is_instance_valid(_spawn_sfx) and _spawn_sfx.stream != null:
		_spawn_sfx.play()


func _publish_spawn_event() -> void:
	player.synced_power_effect = "perux_ambush_spawn"
	var timer: SceneTreeTimer = player.get_tree().create_timer(0.6)
	timer.timeout.connect(_clear_spawn_event)


func _clear_spawn_event() -> void:
	if is_instance_valid(player) and player.synced_power_effect == "perux_ambush_spawn":
		player.synced_power_effect = ""


func sync_remote_visual(effect: String) -> void:
	var active: bool = effect == "perux_ambush_mist"
	var spawned: bool = effect == "perux_ambush_spawn" and _last_remote_effect != effect
	if active and not _remote_visual_active:
		_remote_visual_active = true
		_remote_sprite_was_visible = player.current_sprite.visible
		if GameState.visual_effects:
			player.current_sprite.visible = false
			_remote_fog = _spawn_mist(player.global_position)
	if active:
		return
	if _remote_visual_active:
		_remote_visual_active = false
		player.current_sprite.visible = _remote_sprite_was_visible
		_fade_mist(_remote_fog, 0.15)
		_remote_fog = null
	if spawned:
		_play_spawn_sound()
	_last_remote_effect = effect


func _find_opponent() -> Player:
	var closest: Player
	var closest_distance: float = INF
	for candidate in player.get_parent().get_children():
		if candidate is Player and candidate != player and not candidate.is_dead and candidate.current_health > 0:
			var distance: float = player.global_position.distance_squared_to(candidate.global_position)
			if distance < closest_distance:
				closest = candidate
				closest_distance = distance
	return closest


func _spawn_mist(_position: Vector2, duration: float = -1.0) -> CanvasLayer:
	if not GameState.visual_effects:
		return null
	var mist := CanvasLayer.new()
	mist.name = "PeruxGlobalMist"
	mist.layer = 2
	var scene_root: Node = player.get_tree().current_scene
	if scene_root == null:
		scene_root = player.get_tree().root
	scene_root.add_child(mist)
	var overlay := ColorRect.new()
	overlay.name = "FogOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var material := ShaderMaterial.new()
	material.shader = load("res://SCRIPT/powers/perux_global_mist.gdshader") as Shader
	overlay.material = material
	overlay.modulate.a = 0.0
	mist.add_child(overlay)
	var enter_tween := overlay.create_tween()
	enter_tween.set_trans(Tween.TRANS_SINE)
	enter_tween.set_ease(Tween.EASE_OUT)
	enter_tween.tween_property(overlay, "modulate:a", 1.0, 0.65)
	mist.set_meta("fog_tween", enter_tween)

	if duration > 0.0:
		player.get_tree().create_timer(duration).timeout.connect(_fade_mist.bind(mist, 0.25))
	return mist


func _fade_mist(mist: CanvasLayer, linger: float) -> void:
	if not is_instance_valid(mist):
		return
	var overlay := mist.get_node_or_null("FogOverlay") as ColorRect
	if overlay == null:
		mist.queue_free()
		return
	var previous_tween := mist.get_meta("fog_tween", null) as Tween
	if previous_tween != null:
		previous_tween.kill()
	var tween := overlay.create_tween()
	tween.set_trans(Tween.TRANS_SINE)
	tween.set_ease(Tween.EASE_IN)
	tween.tween_property(overlay, "modulate:a", 0.0, maxf(linger, 0.01))
	tween.tween_callback(Callable(mist, "queue_free"))
	mist.set_meta("fog_tween", tween)
