extends Node


enum { Spade, Heart, Diamond, Clover }
enum { Knight = 11, Queen, King, Ace, Knaker }


class Card:
	var color: int
	var value: int


class Player:
	var name: String
	var id: int
	var hand: Array
	var up: Array
	var down: Array
	var ready: bool


var deck: Array = []
var players: Array = []
var ready_count: int = 0
var playing: bool = false
var owner_id: int = 0


onready var server: Node = get_parent().get_parent()


func _ready():
	print("SÖRVER ÄR ", server)


func add_player(pid: int, name: String):
	print("adding player ", pid)
	var new_player = Player.new()
	new_player.id = pid
	new_player.name = name
	players.append(new_player)


func player_ids() -> Array:
	var ids: Array = []
	for i in range(len(players)):
		ids.append(players[i].id)
	return ids


func player_count():
	return len(players)


func set_room_owner(pid: int):
	owner_id = pid


func find_player_index(pid: int) -> int:
	for i in range(player_count()):
		var p = players[i]
		if pid == p.id:
			return i

	return 0


func find_player(pid: int) -> Player:
	return players[find_player_index(pid)]


func set_ready(pid: int):
	if (!find_player(pid).ready):
		find_player(pid).ready = true
		ready_count += 1
		if (ready_count == player_count()):
			initialize_game();

	
func owner() -> int:
	return owner_id


func remove_player(pid: int):
	var index: int = find_player_index(pid)
	if index != 0:
		players.remove(index)


func initialize_game():
	create_deck()
	deal_cards()


func deal_cards():
	for i in range(player_count()):
		var p = players[i]

		# Reset
		p.hand = []
		p.up = []
		p.down = []

		# Hand
		for _j in range(3):
			var card: Card = deck.pop_back()
			p.hand.append(card)

		# Up
		for _j in range(3):
			var card: Card = deck.pop_back()
			p.up.append(card)

		# Down
		for _j in range(3):
			var card: Card = deck.pop_back()
			p.down.append(card)

		# Send to player
		var thand = card_array_to_transferable(p.hand)
		var tup = card_array_to_transferable(p.up)
		server.rpc_id(p.id, "update_my_cards", thand, tup, len(p.down))

		# Send to other players
		send_player_cards_update(p)


func send_player_cards_update(p: Player):
	# Tell all players what hand and up-cards this player has
	# and how many down cards he has
	for player in players:
		if player.id != p.id:
			server.rpc_id(player.id, "update_player_cards", p.id, len(p.hand), card_array_to_transferable(p.up), len(p.down))


func create_deck():
	deck = []

	# All colors of all values
	for color in [ Spade, Heart, Diamond, Clover ]:
		# 2 - 10, Kn 11, Q 12, K 13, A 14
		for value in range(2, 15):
			var card: Card = Card.new()
			card.color = color
			card.value = value
			deck.append(card)

	var knak = Card.new()
	knak.value = Knaker
	knak.color = Spade
	deck.append(knak)
	deck.append(knak)

	knak.color = Heart
	deck.append(knak)

	deck.shuffle()


func card_to_transferable(card: Card) -> Array:
	return [card.value, card.color]
	

func card_array_to_transferable(card_array: Array) -> Array:
	var result: Array = []
	for card in card_array:
		result.append(card_to_transferable(card))
	return result


func transferable_to_card(transferable: Array) -> Card:
	var result = Card.new()
	result.value = transferable[0]
	result.color = transferable[1]
	return result


func transferable_array_to_cards(transferable_array: Array) -> Array:
	var result: Array = []
	for transferable in transferable_array:
		result.append(transferable_to_card(transferable))
	return result
