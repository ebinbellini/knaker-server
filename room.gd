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


# The available undealed cards
var deck: Array = []
# The players in this room
var players: Array = []
# How many players are ready to play
var ready_count: int = 0
# Is the game started
var playing: bool = false
# Owner of the room
var owner_id: int = 0
# The pile on which players play their cards
var pile: Array = []
# Index of the player that has the turn
var has_turn: int = 0


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
			initialize_game()

	
func owner() -> int:
	return owner_id


func remove_player(pid: int):
	var index: int = find_player_index(pid)
	if index != 0:
		players.remove(index)

	# Close room if no players are left
	if len(players) == 0:
		queue_free()


func initialize_game():
	has_turn = 0
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
	# Tell all players what up-cards this player has
	# and how many hand and down cards he has
	for player in players:
		if player.id != p.id:
			server.rpc_id(player.id, "update_player_cards", p.id, len(p.hand), card_array_to_transferable(p.up), len(p.down))


func create_deck():
	deck = []

	# All colors of all values except knakers
	for color in [ Spade, Heart, Diamond, Clover ]:
		# 2 - 10, Kn 11, Q 12, K 13, A 14
		for value in range(2, 15):
			var card: Card = Card.new()
			card.color = color
			card.value = value
			deck.append(card)

	# All three knakers
	for knaker_color in [Spade, Clover, Heart]:
		var knak = Card.new()
		knak.value = Knaker
		knak.color = knaker_color
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


func player_has_card(player: Player, comp_card: Card) -> bool:
	# TODO allow mixing hand and up

	for card in player.hand:
		if card.value == comp_card.value and card.color == comp_card.color:
			return true

	if len(player.hand) == 0:
		# Player is allowed to place his up cards
		for card in player.up:
			if card.value == comp_card.value and card.color == comp_card.color:
				return true

		if len(player.up) == 0:
			# Player is allowed to place his down cards
			for card in player.down:
				if card.value == comp_card.value and card.color == comp_card.color:
					return true

	return false


func player_placed_cards(pid: int, transferables: Array):
	print("Någon som heter ", pid, " försöker lägga!")
	print(transferables)
	var cards = transferable_array_to_cards(remove_duplicates(transferables))
	print(cards)

	if len(cards) == 0:
		unruly_move(pid, "HTSMT0C")
		return

	if find_player_index(pid) != has_turn:
		unruly_move(pid, "INYTY")
		return

	var player: Player = find_player(pid)
	for card in cards:
		if not player_has_card(player, card):
			unruly_move(pid, "YMNPTCN")
			return

	# Send a duplicate of (cards) by using Array() construction in order to
	# allow are_these_cards_placeable to edit the array safely
	var placeable: bool = are_these_cards_placeable(Array(cards))
	if not placeable:
		if len(cards) == 1:
			unruly_move(pid, "YMNPTCH")
		else:
			unruly_move(pid, "YMNPTHCH")

	if placeable:
		accept_move(cards, transferables, pid)


func accept_move(cards: Array, transferables: Array, pid: int):
	# The move is allowed!!!
	for p in players:
		server.rpc_id(p.id, "cards_placed", transferables, pid)

	# Put the placed cards in the pile
	for card in cards:
		pile.append(card)

	var index: int = find_player_index(pid)
	remove_cards_from_player(index, cards)
	deal_new_cards_to_player(index)


func deal_new_cards_to_player(index):
	var p: Player = players[index]

	var dealt: bool = false
	# TODO GIVE NEW CARDS TO PLAYER IF THERE ARE ANY
	while len(deck) > 0 and len(players[index].hand) < 3:
		dealt = true
		players[index].hand.append(deck.pop_back())

	if dealt:
		var thand: Array = card_array_to_transferable(p.hand)
		var tup: Array = card_array_to_transferable(p.up)
		server.rpc_id(p.id, "update_my_cards", thand, tup, len(p.down))
		send_player_cards_update(p)


func remove_cards_from_player(index, cards):
	var player: Player = players[index]

	for comp_card in cards:
		for i in len(player.hand):
			if player.hand[i].value == comp_card.value and player.hand[i].color == comp_card.color:
				players[index].hand.remove(i)
				break

		for i in len(player.up):
			if player.up[i].value == comp_card.value and player.up[i].color == comp_card.color:
				players[index].up.remove(i)
				break

		for i in len(player.down):
			if player.down[i].value == comp_card.value and player.down[i].color == comp_card.color:
				players[index].down.remove(i)
				break


func unruly_move(pid: int, reason: String):
	server.rpc_id(pid, "unruly_move", reason)


func are_these_cards_placeable(cards: Array) -> bool:
	if len(cards) == 1:
		return is_card_placeable(cards[0])
	else:
		# Mulitple cards

		# If a two has been placed then any card can be placed afterward
		var two_placed = false

		# Get rid of 2's and 7's
		if (cards[0].value == 2):
			# Is placing a 2 allowed
			if is_card_placeable(cards[0]):
				two_placed = true
				# 2s and 7s allow other combinations after them
				# Remove 2s and 7s in order to allow inspection of other
				# structures
				while len(cards) != 0 and cards[0].value == 2 or (cards[0].value == 7 and not is_legal_stair(cards)):
					cards.pop_front()

		if len(cards) == 0:
			# TODO a two was placed and the player is allowed to play again
			return true

		var is_first_placeable: bool = is_card_placeable(cards[0])

		if is_legal_stair(cards):
			return is_first_placeable || two_placed

		if is_homogenous(cards):
			return is_first_placeable || two_placed || is_at_least_tripple_three_on_knaker(cards)
	
	return false


func is_at_least_tripple_three_on_knaker(cards: Array) -> bool:
	for i in range(0, len(cards)):
		var curr_val: int = cards[i].value
		if curr_val != 3:
			return false

	return not is_top_knaker_at_least_rank(4)


func is_homogenous(cards: Array) -> bool:
	# Are all cards in the array of the same value
	var prev_val: int = cards[0].value
	
	for i in range(1, len(cards)):
		var curr_val: int = cards[i].value
		if curr_val != prev_val:
			return false

	return true


func is_legal_stair(cards: Array) -> bool:
	var prev_val: int = cards[0].value

	# Ammount of unique values encountered
	var unique: int = 0

	for i in range(1, len(cards)):
		var curr_val: int = cards[i].value
		# Can either be same or one higher

		if curr_val == 10:
			return false

		var same: bool = curr_val == prev_val

		if not same:
			# This card has a value different from the one before
			unique += 1

			# Is this card one value higher than the previous
			var plus_one: bool = curr_val == prev_val + 1
			# Is this card one after a seven skip
			var seven_skip: bool = prev_val == 6 and curr_val == 8
			# Is this card a klätterknåker
			var climb: bool = prev_val == Knaker and curr_val

			# Check if gap is too large
			if not plus_one and not seven_skip and not climb:
				return false

		prev_val = curr_val

	# A stair has at least 3 unique values
	return unique >= 3

	
func is_card_placeable(card: Card) -> bool:
	if len(pile) == 0:
		return true

	var top: Card = pile[len(pile)-1]
	var tv: int = top.value
	match card.value:
		2:
			# TODO a two was placed and the player is allowed to play again
			return not is_top_knaker_at_least_rank(3)
		3:
			return top.value == 3 or (top.value == Knaker and not is_top_knaker_at_least_rank(2))
		7:
			return not is_top_knaker_at_least_rank(2)
		10:
			# TODO a ten was placed and the player is allowed to play again
			# also the pile is flipped
			return not is_top_knaker_at_least_rank(4)
		Knaker:
			# TODO check if frippelknåker
			return not tv == 3
		_:
			return card.value >= top.value


func is_top_knaker_at_least_rank(rank: int) -> bool:
	var pl: int = len(pile)
	if (pl < rank):
		return false

	# Check if the first (rank) cards are Knåker
	for i in range(0, rank):
		if pile[len(pile)-1-i].value != Knaker:
			return false

	return true


func remove_duplicates(list: Array) -> Array:
	var i: int = 0
	while i < len(list):
		var curr = list[i]
		var index: int = list.find_last(curr)
		if index != i:
			list.remove(index)
		i += 1
		
	return list
