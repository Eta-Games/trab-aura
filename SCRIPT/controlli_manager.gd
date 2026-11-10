class_name Controlli
extends RefCounted
## NON è un Autoload: non va registrato da nessuna parte in Project Settings.
## È una classe normale con un'unica istanza condivisa, creata solo alla
## prima chiamata a Controlli.i() — quindi solo quando serve davvero
## (tipicamente quando si apre il pannello di selezione controlli).
##
## USO NEGLI SCRIPT (es. personaggio1.gd, level.gd):
##   var controlli := Controlli.i()     # crea l'istanza la prima volta,
##                                       # poi riusa sempre la stessa
##   var dx := controlli.direzione_orizzontale(player_id)
##   if controlli.premuto(player_id, "colpo_leggero"): ...
##
## Se in precedenza avevi aggiunto "Controlli" tra gli Autoload in
## Project Settings, RIMUOVILO: avere sia un Autoload sia una class_name
## con lo stesso nome manda in conflitto Godot e blocca l'avvio del progetto.

signal dispositivi_cambiati
signal configurazione_applicata(config: int)

enum Config { DOPPIO_CONTROLLER, TASTIERA_E_CONTROLLER, DOPPIA_TASTIERA }

# --- Schemi da tastiera ---------------------------------------------------
const SCHEMA_WASD := {
	"su": KEY_W, "giu": KEY_S, "sinistra": KEY_A, "destra": KEY_D,
	"colpo_leggero": KEY_J, "colpo_pesante": KEY_K,
	"speciale": KEY_L, "parata": KEY_SHIFT,
}

const SCHEMA_FRECCE := {
	"su": KEY_UP, "giu": KEY_DOWN, "sinistra": KEY_LEFT, "destra": KEY_RIGHT,
	"colpo_leggero": KEY_KP_1, "colpo_pesante": KEY_KP_2,
	"speciale": KEY_KP_3, "parata": KEY_KP_0,
}

# --- Mappa pulsanti controller (schema stile Xbox) ------------------------
const SCHEMA_CONTROLLER := {
	"colpo_leggero": JOY_BUTTON_A,
	"colpo_pesante": JOY_BUTTON_X,
	"speciale": JOY_BUTTON_Y,
	"parata": JOY_BUTTON_B,
}

static var _istanza: Controlli

# player_id (0 o 1) -> { "tipo": "tastiera" | "controller", "device": int, "mappa": Dictionary }
var assegnazioni: Dictionary = {}


## Punto d'ingresso: restituisce l'unica istanza, creandola (e avviandola)
## la prima volta che viene chiamata.
static func i() -> Controlli:
	if _istanza == null:
		_istanza = Controlli.new()
		_istanza._avvia()
	return _istanza


func _avvia() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	applica_configurazione(suggerisci_configurazione())


func _on_joy_connection_changed(_device: int, _connected: bool) -> void:
	dispositivi_cambiati.emit()


func numero_controller() -> int:
	return Input.get_connected_joypads().size()


## Configurazione consigliata in base ai device collegati in questo istante.
func suggerisci_configurazione() -> int:
	var n := numero_controller()
	if n >= 2:
		return Config.DOPPIO_CONTROLLER
	elif n == 1:
		return Config.TASTIERA_E_CONTROLLER
	else:
		return Config.DOPPIA_TASTIERA


## Testo pronto da mostrare nel pannello di selezione.
func descrizione_dispositivi() -> String:
	var n := numero_controller()
	match n:
		0:
			return "P1: A/D muove, Spazio salta, Shift corre, J attacca/conferma, K potere/blocco, E ricarica.\nP2: Frecce muovono, Su salta, KP0 corre, KP1 attacca/conferma, KP2 potere/blocco, KP Invio ricarica."
		1:
			return "P1: A/D muove, Spazio salta, Shift corre, J attacca/conferma, K potere/blocco, E ricarica. P2 usa il controller."
		_:
			return "Rilevati %d controller: potete giocare in doppio controller." % n


## Applica una configurazione.
## giocatore_su_tastiera (0 o 1) conta solo per TASTIERA_E_CONTROLLER e
## decide chi resta alla tastiera.
func applica_configurazione(config: int, giocatore_su_tastiera: int = 0) -> void:
	match config:
		Config.DOPPIO_CONTROLLER:
			_assegna_controller(0, 0)
			_assegna_controller(1, 1)
		Config.TASTIERA_E_CONTROLLER:
			if giocatore_su_tastiera == 0:
				_assegna_tastiera(0, SCHEMA_WASD)
				_assegna_controller(1, 0)
			else:
				_assegna_controller(0, 0)
				_assegna_tastiera(1, SCHEMA_WASD)
		Config.DOPPIA_TASTIERA:
			_assegna_tastiera(0, SCHEMA_WASD)
			_assegna_tastiera(1, SCHEMA_FRECCE)
	configurazione_applicata.emit(config)


func _assegna_tastiera(player_id: int, schema: Dictionary) -> void:
	assegnazioni[player_id] = {"tipo": "tastiera", "device": -1, "mappa": schema}


func _assegna_controller(player_id: int, device: int) -> void:
	assegnazioni[player_id] = {"tipo": "controller", "device": device, "mappa": SCHEMA_CONTROLLER}


## In una partita contro il bot, assegna il dispositivo scelto al giocatore umano.
func imposta_giocatore_contro_bot(usa_controller: bool) -> void:
	if usa_controller and not Input.get_connected_joypads().is_empty():
		_assegna_controller(0, Input.get_connected_joypads()[0])
	else:
		_assegna_tastiera(0, SCHEMA_WASD)


# --- API da usare negli script dei personaggi -----------------------------

func premuto(player_id: int, azione: String) -> bool:
	var cfg: Dictionary = assegnazioni.get(player_id, {})
	if cfg.is_empty():
		return false
	if cfg.tipo == "tastiera":
		return Input.is_key_pressed(cfg.mappa[azione])
	else:
		return Input.is_joy_button_pressed(cfg.device, cfg.mappa[azione])


## Da -1 (sinistra) a 1 (destra). Con controller usa prima il D-pad, poi lo stick.
func direzione_orizzontale(player_id: int) -> float:
	var cfg: Dictionary = assegnazioni.get(player_id, {})
	if cfg.is_empty():
		return 0.0
	if cfg.tipo == "tastiera":
		return float(Input.is_key_pressed(cfg.mappa["destra"])) - float(Input.is_key_pressed(cfg.mappa["sinistra"]))
	var sinistra := Input.is_joy_button_pressed(cfg.device, JOY_BUTTON_DPAD_LEFT)
	var destra := Input.is_joy_button_pressed(cfg.device, JOY_BUTTON_DPAD_RIGHT)
	if sinistra or destra:
		return float(destra) - float(sinistra)
	var asse := Input.get_joy_axis(cfg.device, JOY_AXIS_LEFT_X)
	return asse if abs(asse) > 0.2 else 0.0


func direzione_verticale(player_id: int) -> float:
	var cfg: Dictionary = assegnazioni.get(player_id, {})
	if cfg.is_empty():
		return 0.0
	if cfg.tipo == "tastiera":
		return float(Input.is_key_pressed(cfg.mappa["giu"])) - float(Input.is_key_pressed(cfg.mappa["su"]))
	var su := Input.is_joy_button_pressed(cfg.device, JOY_BUTTON_DPAD_UP)
	var giu := Input.is_joy_button_pressed(cfg.device, JOY_BUTTON_DPAD_DOWN)
	if su or giu:
		return float(giu) - float(su)
	var asse := Input.get_joy_axis(cfg.device, JOY_AXIS_LEFT_Y)
	return asse if abs(asse) > 0.2 else 0.0
