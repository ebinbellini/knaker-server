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
# Is the game in the trading phase
var in_trading_phase: bool = false
# Owner of the room
var owner_id: int = 0
# The pile on which players play their cards
var pile: Array = []
# Index of the player that has the turn
var turn_index: int = 0
# Does the turn return to the placing player if placement is succesful
var placing_players_turn_again: bool = false
# Should the pile be flipped if placement is succesful
var should_pile_flip: bool = false


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

	return -1


func set_ready(pid: int):
	var index: int = find_player_index(pid)
	if (!players[index].ready):
		players[index].ready = true
		ready_count += 1
		if (ready_count == player_count()):
			initialize_game()


func owner() -> int:
	return owner_id


func remove_player(pid: int):
	var index: int = find_player_index(pid)
	if index != -1:
		players.remove(index)
	else:
		return

	if len(players) <= turn_index:
		turn_index -= 1

	# Close room if no players are left
	if len(players) == 0:
		queue_free()


func initialize_game():
	in_trading_phase = true
	turn_index = 0
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

		player_cards_changed(p)


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


func player_placed_down_card(pid: int):
	var index: int = find_player_index(pid)
	if index == -1:
		return
	var player: Player = players[index]

	if len(player.down) == 0:
		return

	var placed_card = player.down.pop_back()

	var placeable: bool = is_card_placeable(placed_card)
	if not placeable:
		player.hand.append(placed_card)
		pick_up_pile(player)
	else:
		var transferable: Array = card_to_transferable(placed_card)
		for p in players:
			server.rpc_id(p.id, "cards_placed", [transferable], pid)
		pile.append(placed_card)
	
	player_cards_changed(player)
	

func player_has_cards(player: Player, cards: Array):
	var selected_hand_cards: int = 0
	var selected_up_cards: int = 0

	for comp_card in cards:
		for card in player.hand:
			if card.value != comp_card.value or card.color != comp_card.color:
				return true
			selected_hand_cards += 1

	if selected_hand_cards == len(player.hand):
		# Player is allowed to place his up cards
		for comp_card in cards:
			for card in player.up:
				if card.value != comp_card.value or card.color != comp_card.color:
					return true
				selected_up_cards += 1

	return selected_hand_cards + selected_up_cards == len(cards)
	

func player_placed_cards(pid: int, transferables: Array):
	placing_players_turn_again = false
	should_pile_flip = false

	print(pid, " försöker att lägga ", transferables)
	var cards = transferable_array_to_cards(remove_duplicates(transferables))

	if len(cards) == 0:
		unruly_move(pid, "HTSMT0C")
		return

	if find_player_index(pid) != turn_index:
		unruly_move(pid, "INYTY")
		return

	var index: int = find_player_index(pid)
	if index == -1:
		unruly_move(pid, "AEHO")
		return
	var player: Player = players[index]

	if not player_has_cards(player, cards):
		unruly_move(pid, "YMNPTCN")
		return

	# Send a duplicate of cards in order to allow are_these_cards_placeable to
	# edit the array safely
	var placeable: bool = are_these_cards_placeable(cards.duplicate())
	if not placeable:
		if len(cards) == 1:
			unruly_move(pid, "YMNPTCH")
		else:
			unruly_move(pid, "YMNPTHCH")
	else:
		accept_move(cards, transferables, pid)


func player_cards_changed(player):
	var thand = card_array_to_transferable(player.hand)
	var tup = card_array_to_transferable(player.up)
	server.rpc_id(player.id, "update_my_cards", thand, tup, len(player.down))

	# Send to other players
	send_player_cards_update(player)


func pick_up_pile(player: Player):
	for card in pile:
		player.hand.append(card)

	empty_pile()


func accept_move(cards: Array, transferables: Array, pid: int):
	# The move is allowed!!
	for p in players:
		server.rpc_id(p.id, "cards_placed", transferables, pid)

	# Put the placed cards in the pile
	for card in cards:
		pile.append(card)

	var index: int = find_player_index(pid)
	remove_cards_from_player(index, cards)

	if should_pile_flip:
		empty_pile()
	elif not placing_players_turn_again:
		transfer_turn()

	
	deal_new_cards_to_player(index)


func transfer_turn():
	turn_index += 1
	if turn_index >= len(players):
		turn_index = 0



func empty_pile():
	for player in players:
		server.rpc_id(player.id, "empty_pile")

	pile = []


func deal_new_cards_to_player(index):
	var p: Player = players[index]

	var dealt: bool = false

	while len(deck) > 0 and len(players[index].hand) < 3:
		dealt = true
		players[index].hand.append(deck.pop_back())

	if dealt:
		player_cards_changed(p)


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
		var two_placed = pile[first_non_seven_index()].value == 2

		# Get rid of 2's and 7's
		if (cards[0].value == 2):
			# Is placing a 2 allowed
			if is_card_placeable(cards[0]):
				two_placed = true
				# 2s and 7s allow other combinations after them
				# Remove 2s and 7s in order to allow inspection of other
				# structures
				while len(cards) > 0 and cards[0].value == 2 or (cards[0].value == 7 and not is_legal_stair(cards)):
					cards.pop_front()

		if len(cards) == 0:
			placing_players_turn_again = true
			return true

		var is_first_placeable: bool = is_card_placeable(cards[0])

		if is_legal_stair(cards):
			return is_first_placeable or two_placed

		var homogenous: int = homogenous_ammount(cards)
		if homogenous > 1 and (is_first_placeable or two_placed or is_at_least_tripple_three_on_knaker(cards)):
			if homogenous == 4:
				should_pile_flip = true
			return true
	
	return false


func is_at_least_tripple_three_on_knaker(cards: Array) -> bool:
	for i in range(0, len(cards)):
		var curr_val: int = cards[i].value
		if curr_val != 3:
			return false

	return not is_top_knaker_at_least_rank(4)


func homogenous_ammount(cards: Array) -> int:
	# How many cards in a row are of the same value
	var first_val: int = cards[0].value
	var i: int = 1;
	while i < len(cards):
		if cards[i].value != first_val:
			return i - 1
		i += 1

	return i


func is_legal_stair(cards: Array) -> bool:
	var prev_val: int = cards[0].value

	# Ammount of unique values encountered
	var unique: int = 0

	for i in range(1, len(cards)):
		var curr_val: int = cards[i].value

		if curr_val == 10:
			return false

		var same: bool = curr_val == prev_val

		if not same:
			# This card has a value different from the one before
			unique += 1

			# Is this card one value higher than the previous?
			var plus_one: bool = curr_val == prev_val + 1
			# Is this a seven skip?
			var seven_skip: bool = prev_val == 6 and curr_val == 8
			# Is this a klätterknåker (climbing knaker)?
			var climb: bool = prev_val == Knaker and curr_val == 3

			# Check if gap is too large
			if not (plus_one or seven_skip or climb):
				return false

		prev_val = curr_val

	# A stair has at least 3 unique values
	return unique >= 3

	
func is_card_placeable(card: Card) -> bool:
	if len(pile) == 0:
		return true


	# Use the value of the first card that isn't 7
	var top: Card = pile[first_non_seven_index()]

	var tv: int = top.value
	match card.value:
		2:
			placing_players_turn_again = true
			return not is_top_knaker_at_least_rank(3)
		3:
			return top.value == 3 or (top.value == Knaker and not is_top_knaker_at_least_rank(2))
		7:
			return not is_top_knaker_at_least_rank(2)
		10:
			should_pile_flip = true
			return not is_top_knaker_at_least_rank(4)
		Knaker:
			# TODO check if frippelknåker
			return not tv == 3
		_:
			return card.value >= top.value


func first_non_seven_index() -> int:
	# Find the index of the first card in the pile that isn't seven
	var i: int = len(pile)-1
	while pile[i].value == 7:
		i -= 1

	return i


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
