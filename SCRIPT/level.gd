extends Node

@onready var fine_partita = $FinePartita
@onready var label_timer: Label = $HUD/PannelloTimer/LabelTimer
@onready var pause_menu: CanvasLayer = $PauseMenu

const TEMPO_ROUND: float = 300.0

var partita_finita: bool = false
var _intro_running: bool = true
var _ambient_theme: String = "hell"
var tempo_rimasto: float = TEMPO_ROUND
var players_per_id: Dictionary = {}  # player_id -> Player


func _ready() -> void:
	_applica_mappa()
	_applica_controlli()

	# ascolta la morte di ogni player, indicizzandolo per player_id
	for p in get_tree().get_nodes_in_group("players"):
		if p is Player:
			players_per_id[p.player_id] = p
			p.died.connect(_on_player_died)

	_aggiorna_label_timer()
	$HUD.hide()
	for p in players_per_id.values():
		p.intro_locked = true
		p.velocity = Vector2.ZERO
	_setup_ambient_effects()
	call_deferred("_play_fight_intro")


func _unhandled_input(event: InputEvent) -> void:
	if partita_finita or _intro_running:
		return
	var pause_pressed: bool = false
	if event is InputEventKey:
		pause_pressed = event.pressed and not event.echo and event.keycode == KEY_ESCAPE
	elif event is InputEventJoypadButton:
		pause_pressed = event.pressed and event.button_index == JOY_BUTTON_START
	if pause_pressed:
		pause_menu.call("open_menu")
		get_viewport().set_input_as_handled()


# Tiene solo background/tilemap della mappa scelta (definite in data/mappe.cfg)
# e imposta la musica. Se il livello parte da solo (test) usa la prima mappa.
func _applica_mappa() -> void:
	var tutte := SelettoreMappa.carica_mappe()
	if tutte.is_empty():
		return
	var scelta: Dictionary = SelettoreMappa.corrente if not SelettoreMappa.corrente.is_empty() else tutte[0]
	_ambient_theme = str(scelta.id)
	for m in tutte:
		if m.id == scelta.id:
			continue
		for chiave in ["background_node", "tilemap_node"]:
			var n := get_node_or_null(NodePath(m[chiave]))
			if n:
				n.queue_free()
	if scelta.musica != "" and ResourceLoader.exists(scelta.musica):
		var player: AudioStreamPlayer = $AudioStreamPlayer
		player.stop()
		player.stream = load(scelta.musica)
		player.play()


# NUOVO: traduce la configurazione scelta nel pannello "Rilevazione controlli"
# nel device_id che player.gd si aspetta già (-1 = tastiera schema p1_*,
# -2 = tastiera schema p2_*, >=0 = indice del joypad), sovrascrivendo il
# valore fisso impostato in scena. Senza questo, ogni Player usava sempre
# lo stesso dispositivo indipendentemente da chi avesse scelto cosa in
# selezione — da qui i personaggi che risultavano scambiati in partita.
func _applica_controlli() -> void:
	var controlli := Controlli.i()
	print("[DEBUG] assegnazioni: ", controlli.assegnazioni)
	for p in get_tree().get_nodes_in_group("players"):
		if not (p is Player):
			continue
		var assegnazione: Dictionary = controlli.assegnazioni.get(p.player_id, {})
		if assegnazione.is_empty():
			continue
		if assegnazione.tipo == "controller":
			p.device_id = assegnazione.device
		else:
			# player_id 0 -> sempre schema tastiera "p1_*" (WASD)
			# player_id 1 -> sempre schema tastiera "p2_*" (Frecce)
			p.device_id = -1 if p.player_id == 0 else -2
		print("[DEBUG] ", p.name, " -> device_id finale=", p.device_id)


func _make_cinematic_overlay() -> Dictionary:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var top := ColorRect.new()
	top.color = Color.BLACK
	top.anchor_right = 1.0
	top.offset_top = -96.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(top)
	var bottom := ColorRect.new()
	bottom.color = Color.BLACK
	bottom.anchor_right = 1.0
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	bottom.offset_bottom = 96.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(bottom)
	var title := Label.new()
	title.anchor_left = 0.08
	title.anchor_right = 0.92
	title.anchor_top = 0.43
	title.anchor_bottom = 0.62
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", load("res://font/kreaturekombatcond.ttf"))
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.35))
	title.modulate.a = 0.0
	layer.add_child(title)
	return {"layer": layer, "top": top, "bottom": bottom, "title": title}

func _play_fight_intro() -> void:
	if not players_per_id.has(0) or not players_per_id.has(1):
		for p in players_per_id.values():
			p.intro_locked = false
		_intro_running = false
		$HUD.show()
		return
	var camera := get_viewport().get_camera_2d()
	var ui := _make_cinematic_overlay()
	var top: ColorRect = ui.top
	var bottom: ColorRect = ui.bottom
	var title: Label = ui.title
	var bars := create_tween()
	bars.set_parallel(true)
	bars.tween_property(top, "offset_top", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	bars.tween_property(top, "offset_bottom", 96.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	bars.tween_property(bottom, "offset_top", -96.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	bars.tween_property(bottom, "offset_bottom", 0.0, 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	await bars.finished
	for id in [0, 1]:
		var fighter: Player = players_per_id[id]
		fighter.play_intro_pose()
		if camera and camera.has_method("set_cinematic_focus"):
			camera.set_cinematic_focus(fighter, fighter.intro_zoom(), fighter.intro_focus_offset())
		title.text = fighter.intro_display_name()
		title.scale = Vector2(0.86, 0.86)
		title.modulate.a = 0.0
		var enter := create_tween()
		enter.set_parallel(true)
		enter.tween_property(title, "modulate:a", 1.0, 0.25)
		enter.tween_property(title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		await enter.finished
		await get_tree().create_timer(fighter.intro_duration()).timeout
		var leave := create_tween()
		leave.tween_property(title, "modulate:a", 0.0, 0.2)
		await leave.finished
	title.text = "FIGHT!"
	title.scale = Vector2(0.65, 0.65)
	var start := create_tween()
	start.set_parallel(true)
	start.tween_property(title, "modulate:a", 1.0, 0.18)
	start.tween_property(title, "scale", Vector2(1.15, 1.15), 0.34).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await start.finished
	await get_tree().create_timer(0.5).timeout
	var fade := create_tween()
	fade.set_parallel(true)
	fade.tween_property(top, "modulate:a", 0.0, 0.4)
	fade.tween_property(bottom, "modulate:a", 0.0, 0.4)
	fade.tween_property(title, "modulate:a", 0.0, 0.4)
	await fade.finished
	ui.layer.queue_free()
	if camera and camera.has_method("clear_cinematic_focus"):
		camera.clear_cinematic_focus()
	$HUD.show()
	for p in players_per_id.values():
		p.intro_locked = false
		p.current_sprite.play("idle")
		p.synced_animation = "idle"
	_intro_running = false

func _setup_ambient_effects() -> void:
	if not GameState.visual_effects:
		return
	var embers := _ambient_theme == "hell"
	var p := CPUParticles2D.new()
	p.name = "AmbientEmbers" if embers else "AmbientDust"
	p.amount = 34
	p.lifetime = 4.2
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(610.0, 280.0)
	p.direction = Vector2(0.0, -1.0)
	p.spread = 32.0 if embers else 90.0
	p.initial_velocity_min = 8.0
	p.initial_velocity_max = 24.0 if embers else 14.0
	p.gravity = Vector2(0.0, -4.0 if embers else 1.0)
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.8
	p.color = Color(1.0, 0.38, 0.08, 0.45) if embers else Color(0.84, 0.9, 1.0, 0.25)
	p.position = Vector2(0.0, -80.0)
	p.z_index = 5
	add_child(p)
	p.emitting = true
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = grad

func _show_ko(winner_id: int) -> void:
	Engine.time_scale = 0.42
	var camera := get_viewport().get_camera_2d()
	if camera and camera.has_method("set_cinematic_focus") and players_per_id.has(winner_id):
		camera.set_cinematic_focus(players_per_id[winner_id], 1.55)
	if GameState.visual_effects and camera and camera.has_method("shake"):
		camera.shake(10.0, 0.3)
	var layer := CanvasLayer.new()
	layer.layer = 31
	add_child(layer)
	var label := Label.new()
	label.text = "K.O."
	label.anchor_left = 0.1
	label.anchor_right = 0.9
	label.anchor_top = 0.35
	label.anchor_bottom = 0.65
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", load("res://font/kreaturekombatcond.ttf"))
	label.add_theme_font_size_override("font_size", 148)
	label.add_theme_color_override("font_color", Color(1.0, 0.18, 0.08))
	label.scale = Vector2(1.7, 1.7)
	label.modulate.a = 0.0
	layer.add_child(label)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 1.0, 0.18)
	await tween.finished
	await get_tree().create_timer(0.55).timeout
	var fade := create_tween()
	fade.tween_property(label, "modulate:a", 0.0, 0.22)
	await fade.finished
	layer.queue_free()
	if camera and camera.has_method("clear_cinematic_focus"):
		camera.clear_cinematic_focus()
	Engine.time_scale = 1.0
func _process(delta: float) -> void:
	if partita_finita or _intro_running:
		return

	tempo_rimasto = maxf(tempo_rimasto - delta, 0.0)
	_aggiorna_label_timer()

	if tempo_rimasto <= 0.0:
		_on_tempo_scaduto()


func _aggiorna_label_timer() -> void:
	if label_timer:
		label_timer.text = str(int(ceil(tempo_rimasto)))


func _on_player_died(morto: Player) -> void:
	if partita_finita:
		return  # se muoiono insieme, conta solo il primo
	# NUOVO: in rete la decisione la prende solo l'host, poi la manda a
	# entrambi via RPC (_mostra_fine); in locale (nessun peer) invariato
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	partita_finita = true

	# con due player, il vincitore è l'altro
	var vincitore: int = 1 if morto.player_id == 0 else 0
	var match_finito: bool = GameState.register_round_win(vincitore)
	if multiplayer.has_multiplayer_peer():
		_mostra_fine.rpc(vincitore, match_finito)
	else:
		fine_partita.mostra(vincitore, match_finito)


func _on_tempo_scaduto() -> void:
	if partita_finita:
		return
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		return
	partita_finita = true

	# tempo scaduto: vince chi ha più salute rimasta; a parità è pareggio
	if not players_per_id.has(0) or not players_per_id.has(1):
		return

	var salute_p0: int = players_per_id[0].current_health
	var salute_p1: int = players_per_id[1].current_health

	if salute_p0 == salute_p1:
		if multiplayer.has_multiplayer_peer():
			_mostra_pareggio.rpc()
		else:
			fine_partita.mostra_pareggio()
	else:
		var vincitore: int = 0 if salute_p0 > salute_p1 else 1
		var match_finito: bool = GameState.register_round_win(vincitore)
		if multiplayer.has_multiplayer_peer():
			_mostra_fine.rpc(vincitore, match_finito)
		else:
			fine_partita.mostra(vincitore, match_finito)


# NUOVO: chiamate dall'host a entrambi (call_local incluso) così la
# schermata di fine round appare uguale su entrambi i PC
@rpc("authority", "call_local", "reliable")
func _mostra_fine(vincitore: int, match_finito: bool) -> void:
	partita_finita = true
	await _show_ko(vincitore)
	fine_partita.mostra(vincitore, match_finito)


@rpc("authority", "call_local", "reliable")
func _mostra_pareggio() -> void:
	partita_finita = true
	fine_partita.mostra_pareggio()
