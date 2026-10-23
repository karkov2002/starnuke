class_name StationDebugSection
extends VBoxContainer
## Section « station et radio » du panneau de debug (scripts/debug/debug_panel.gd) :
## - menu « Alerte » : niveau d'alerte de la station (couleur des luminaires intérieurs, Station.set_alert) ;
## - « Cargo » : sépare le vaisseau cargo de la station, ou le réamarre (Station.set_cargo_docked) ;
## - « Ouverture totale » / « Fermeture totale » : toutes les écoutilles ouvrables, porte extérieure du sas comprise
##   (Station.set_all_hatches_open : tests d'expulsion depuis n'importe quel module) ;
## - « Combinaison » : combinaison du sas portée ou rangée (Station.set_suit_worn), la case suit l'état réel ;
## - « Radio » : message radio d'essai du contrôle sol, avec deux réponses (RadioComms.post).

var _suit: CheckBox


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	var row := DebugUi.row(self)
	var alert := OptionButton.new()
	alert.focus_mode = Control.FOCUS_NONE
	for level in ["Alerte : aucune", "Alerte jaune", "Alerte orange", "Alerte rouge", "Plus de lumière"]:
		alert.add_item(level)
	alert.item_selected.connect(func(index: int) -> void:
		var station := _station()
		if station:
			station.set_alert(index as Station.Alert))
	row.add_child(alert)
	# Vaisseau cargo : séparation (recul de 10 m en 30 s) ou réamarrage.
	row.add_child(DebugUi.button("Cargo", func() -> void:
		var station := _station()
		if station:
			station.set_cargo_docked(not station.is_cargo_docked())))

	var hatches := DebugUi.row(self)
	for pair: Array in [["Ouverture totale", true], ["Fermeture totale", false]]:
		var open: bool = pair[1]
		var button := DebugUi.button(pair[0], func() -> void:
			var station := _station()
			if station:
				station.set_all_hatches_open(open))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hatches.add_child(button)
	_suit = CheckBox.new()
	_suit.text = "Combinaison"
	_suit.focus_mode = Control.FOCUS_NONE
	_suit.toggled.connect(func(on: bool) -> void:
		var station := _station()
		if station:
			station.set_suit_worn(on))
	hatches.add_child(_suit)
	hatches.add_child(DebugUi.button("Radio", func() -> void:
		var radio := get_tree().get_first_node_in_group(RadioComms.GROUP) as RadioComms
		if radio:
			radio.post({"from": "COMM_FROM_GROUND", "subject": "COMM_TEST_SUBJECT", "body": "COMM_TEST_BODY",
					"replies": ["COMM_TEST_REPLY_1", "COMM_TEST_REPLY_2"]})))


## La combinaison s'enfile aussi au clic dans le sas : la case suit l'état réel.
func _process(_delta: float) -> void:
	var station := _station()
	_suit.disabled = station == null
	if station:
		_suit.set_pressed_no_signal(station.is_suit_worn())


func _station() -> Station:
	return get_tree().get_first_node_in_group(Station.GROUP) as Station
