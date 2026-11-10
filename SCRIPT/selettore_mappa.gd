class_name SelettoreMappa
extends Control
## Logica del selettore mappa (UI nella scena, nodo SelezioneMappa).
## P1 vota, P2 vota (ognuno col proprio dispositivo) -> estrazione tra i 2 voti.
## Se esce RANDOM -> una mappa a caso tra quelle in data/mappe.cfg.
## La mappa scelta resta in SelettoreMappa.corrente per la scena di gioco.

signal mappa_scelta(mappa: Dictionary)

# ───── CONFIGURAZIONE ─────
# Le mappe si definiscono in res://data/mappe.cfg
const CFG_PATH := "res://data/mappe.cfg"
const MAX_MAPPE := 7
const RITARDO_RISULTATO := 1.5
const COLORE_P1 := Color(1, 0.85, 0.2)
const COLORE_P2 := Color(0.4, 0.8, 1)
const TEMPO_TRA_MOVIMENTI := 0.18
# ──────────────────────────

const RANDOM_ID := -1

static var corrente: Dictionary = {}

var _mappe: Array = []


# Legge le mappe dal cfg (usata anche dal livello)
static func carica_mappe() -> Array:
	var cfg := ConfigFile.new()
	var out: Array = []
	if cfg.load(CFG_PATH) != OK:
		push_error("Impossibile leggere " + CFG_PATH)
		return out
	for sez in cfg.get_sections():
		out.append({
			"id": sez,
			"nome": cfg.get_value(sez, "nome", sez),
			"background_node": cfg.get_value(sez, "background_node", ""),
			"tilemap_node": cfg.get_value(sez, "tilemap_node", ""),
			"musica": cfg.get_value(sez, "musica", ""),
		})
	return out.slice(0, MAX_MAPPE)

@onready var _titolo: Label = $Titolo
@onready var _griglia: GridContainer = $Griglia
@onready var _cursore: ColorRect = $Cursore

var _opzioni: Array = []   # [{id, btn}] solo bottoni visibili
var _voti: Array[int] = []
var _cursor_index := 0
var _bloccato := false
var _ultimo_movimento := -999.0


func _ready() -> void:
	_mappe = carica_mappe()
	var bottoni := _griglia.get_children()
	for i in bottoni.size():
		var btn: Button = bottoni[i]
		if i < _mappe.size():
			btn.text = _mappe[i]["nome"]
			_opzioni.append({"id": i, "btn": btn})
		elif i == bottoni.size() - 1:
			_opzioni.append({"id": RANDOM_ID, "btn": btn})
		else:
			btn.hide()
			continue
		var idx := _opzioni.size() - 1
		btn.mouse_entered.connect(_hover.bind(idx))
		btn.pressed.connect(_click.bind(idx))
	visibility_changed.connect(func(): if visible: reset())


func reset() -> void:
	_voti.clear()
	_bloccato = false
	_cursor_index = 0
	for o in _opzioni:
		o.btn.modulate = Color.WHITE
	_titolo.text = "Player 1: scegli la mappa"
	_aggiorna_cursore.call_deferred()


func _unhandled_input(event: InputEvent) -> void:
	if not visible or _bloccato:
		return
	var ass: Dictionary = Controlli.i().assegnazioni.get(_voti.size(), {})
	if ass.is_empty():
		return
	if ass.tipo == "controller":
		_input_controller(event, ass.device)
	else:
		_input_tastiera(event, ass.mappa)


func _input_tastiera(event: InputEvent, _mappa: Dictionary) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var prefisso: String = "p1_" if _voti.size() == 0 else "p2_"
	if event.is_action_pressed(prefisso + "left"):
		_muovi(-1)
	elif event.is_action_pressed(prefisso + "right"):
		_muovi(1)
	elif event.is_action_pressed(prefisso + "attack"):
		_conferma()


func _input_controller(event: InputEvent, device: int) -> void:
	if event is InputEventJoypadButton and event.device == device and event.pressed:
		match event.button_index:
			JOY_BUTTON_DPAD_LEFT: _muovi(-1)
			JOY_BUTTON_DPAD_RIGHT: _muovi(1)
			JOY_BUTTON_A, JOY_BUTTON_X: _conferma()
	elif event is InputEventJoypadMotion and event.device == device and event.axis == JOY_AXIS_LEFT_X:
		if event.axis_value < -0.5:
			_muovi(-1)
		elif event.axis_value > 0.5:
			_muovi(1)


func _muovi(dir: int) -> void:
	var adesso := Time.get_ticks_msec() / 1000.0
	if adesso - _ultimo_movimento < TEMPO_TRA_MOVIMENTI:
		return
	_ultimo_movimento = adesso
	_cursor_index = (_cursor_index + dir + _opzioni.size()) % _opzioni.size()
	_aggiorna_cursore()


func _mouse_abilitato() -> bool:
	var ass: Dictionary = Controlli.i().assegnazioni.get(_voti.size(), {})
	return ass.get("tipo", "tastiera") == "tastiera"


func _hover(idx: int) -> void:
	if _bloccato or not _mouse_abilitato():
		return
	_cursor_index = idx
	_aggiorna_cursore()


func _click(idx: int) -> void:
	if _bloccato or not _mouse_abilitato():
		return
	_cursor_index = idx
	_aggiorna_cursore()
	_conferma()


func _aggiorna_cursore() -> void:
	var b: Button = _opzioni[_cursor_index].btn
	_cursore.global_position = b.global_position - Vector2(6, 6)
	_cursore.size = b.size + Vector2(12, 12)


func _conferma() -> void:
	var o: Dictionary = _opzioni[_cursor_index]
	_voti.append(o.id)
	o.btn.modulate = COLORE_P1 if _voti.size() == 1 else COLORE_P2
	if GameState.bot_enabled and _voti.size() == 1:
		var bot_vote: Dictionary = _opzioni.pick_random()
		_voti.append(int(bot_vote.id))
		bot_vote.btn.modulate = COLORE_P2
		_bloccato = true
		_concludi()
		return
	if _voti.size() < 2:
		_titolo.text = "Player 2: scegli la mappa"
		return
	_bloccato = true
	_concludi()


func _concludi() -> void:
	var scelto: int = _voti.pick_random()
	if scelto == RANDOM_ID:
		scelto = randi() % _mappe.size()
	var mappa: Dictionary = _mappe[scelto].duplicate()
	mappa["indice"] = scelto
	corrente = mappa
	if GameState.bot_enabled and _voti.size() >= 2:
		var bot_choice_name: String = "RANDOM"
		for option: Dictionary in _opzioni:
			if int(option.id) == _voti[1]:
				bot_choice_name = str(option.btn.text)
				break
		_titolo.text = "Bot vota: %s\nMappa estratta: %s" % [bot_choice_name, mappa["nome"]]
	else:
		_titolo.text = "Mappa estratta: %s" % mappa["nome"]
	await get_tree().create_timer(RITARDO_RISULTATO).timeout
	mappa_scelta.emit(mappa)
