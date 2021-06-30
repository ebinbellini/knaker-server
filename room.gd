# Copyright (C) 2021 Ebin Bellini ebinbellini@airmail.cc

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

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
	var locked_up_indexes: Array
	var down: Array
	var ready: bool
	var	done_trading: bool
	var finished: bool


# The available undealed cards
var deck: Array = []
# The players in this room
var players: Array = []
# How many players are ready to play
var ready_count: int = 0
# How many players want to end the trading phase
var done_trading_ammount: int = 0
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
# Is the player placing only up cards
var placing_only_up_cards: bool = false
# The order in which players went out
var leaderboard = []
# The order in which players lost
var failed = []
# The players that want to play again
var want_to_play_again: Array = []
# Is this room visible to all players
var public: bool = false

# Is a game currently taking place
export var playing: bool = false


onready var server: Node = get_parent().get_parent()


func initialize_game():
	for p in players:
		p.ready = false
		p.done_trading = false
		p.locked_up_indexes = []
		p.finished = false

	ready_count = 0
	done_trading_ammount = 0

	# Give the turn to no-one
	turn_index = -1

	playing = true
	in_trading_phase = true

	create_deck()
	deal_cards()

	leaderboard = []
	failed = []
	want_to_play_again = []


func pid_of_player_with_worst_cards() -> int:
	var value: int = 3
	var found: bool = false
	var ammount: int = 1
	var candidates = players.duplicate(true)
	var to_remove: Array

	while true:
		to_remove = []
		found = false

		# Give up if we have gone too far
		if value == 16:
			return players[0].id

		for player in candidates:
			var count: int = 0
			for card in player.hand:
				if card.value == value:
					count +=1
					found = true

			if count < ammount:
				to_remove.append(player.id)

		if found:
			ammount += 1

			# Remove all candidates in to_remove
			for id in to_remove:
				for i in len(candidates):
					if candidates[i].id == id:
						candidates.remove(i)
						break

			# When there's only one player left we're done
			if len(candidates) == 1:
				return candidates[0].id
		else:
			# No one had a card with the value of the variable value
			# Try with a higher value
			value += 1
			ammount = 1

			# Skip special cards
			if [7, 10].has(value):
				value += 1

	# Silence errors
	return -1


func add_player(pid: int, name: String):
	var new_player = Player.new()
	new_player.id = pid
	new_player.name = name
	players.append(new_player)


func player_ids() -> Array:
	var ids: Array = []
	for i in range(player_count()):
		ids.append(players[i].id)
	return ids


func player_count() -> int:
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
			server.all_players_ready(self)


func set_done_trading(pid: int):
	var index: int = find_player_index(pid)
	if (!players[index].done_trading):
		players[index].done_trading = true
		done_trading_ammount += 1
		end_trading_phase_if_possible()


func players_done_trading() -> int:
	return done_trading_ammount


func end_trading_phase_if_possible():
	if not can_end_trading_phase():
		return

	# Give turn to the player with the worst cards
	var turn_pid: int = pid_of_player_with_worst_cards()
	turn_index = find_player_index(turn_pid)

	in_trading_phase = false
	server.trading_phase_ended(self)

	var pid: int = players[turn_index].id
	for p in players:
		server.rpc_id(p.id, "this_player_has_turn", pid)


func can_end_trading_phase() -> bool:
	# All players need to vote to begin
	if done_trading_ammount < player_count():
		return false

	# All players need three stacks in their up cards
	for player in players:
		if len(player.up) != 3:
			return false

	return true


func owner() -> int:
	return owner_id


func remove_player(pid: int):
	var index: int = find_player_index(pid)
	if index != -1:
		players.remove(index)
	else:
		return

	# Close room if no players are left
	if player_count() == 0:
		queue_free()

	if player_count() <= turn_index:
		turn_index -= 1

	# Tell players who has the turn
	for p in players:
		server.rpc_id(p.id, "this_player_has_turn", pid)

	# Tell all players that this player is finished
	for p in players:
		if (p.id != pid):
			server.rpc_id(p.id, "player_finished", pid, "LEFT")


func deal_cards():
	for i in range(player_count()):
		var p: Player = players[i]

		# Reset
		p.hand = []
		p.up = []
		p.down = []
		p.locked_up_indexes = []

		# Hand
		for _j in range(3):
			var card: Card = deck.pop_back()
			p.hand.append(card)

		# Up
		for _j in range(3):
			var card: Card = deck.pop_back()
			p.up.append([card])

		# Down
		for _j in range(3):
			var card: Card = deck.pop_back()
			p.down.append(card)

		player_cards_changed(p)
	
	deck_ammount_changed()


func send_player_cards_update(p: Player):
	# Tell all players what up-cards this player has
	# and how many hand and down cards he has
	for player in players:
		if player.id != p.id:
			var tup: Array = []
			for stack in p.up:
				tup.append(card_array_to_transferable(stack))

			server.rpc_id(player.id, "update_player_cards", p.id, len(p.hand), tup, len(p.down))


func create_deck():
	deck = []

	# All colors of all values except knakers
	for color in [ Spade, Heart, Diamond, Clover ]:
		# 2 - 10, Kn 11, Q 12, K 13, A 14
		for value in range(2, 15):
			deck.append(create_card(value, color))

	# All three knakers
	for knaker_color in [Spade, Clover, Heart]:
		deck.append(create_card(Knaker, knaker_color))

	deck.shuffle()

	# DEBUG: deck = deck.slice(0, 11)


func create_card(value: int, color: int) -> Card:
	var card: Card = Card.new()
	card.value = value
	card.color = color
	return card


func card_to_transferable(card: Card) -> Array:
	return [card.value, card.color]


func card_array_to_transferable(card_array: Array) -> Array:
	var result: Array = []
	for card in card_array:
		result.append(card_to_transferable(card))
	return result


func transferable_to_card(transferable: Array) -> Card:
	return create_card(transferable[0], transferable[1])


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

	reset_placing_state()

	var placeable: bool = are_these_cards_placeable([placed_card])
	if not placeable:
		player.hand.append(placed_card)
		player_picks_up_cards(pid)
	else:
		var transferables: Array = [card_to_transferable(placed_card)]
		accept_move([placed_card], transferables, pid)
	

func player_has_cards(player: Player, cards: Array) -> bool:
	var selected_hand_cards: int = 0
	var selected_up_cards: int = 0

	for comp_card in cards:
		for card in player.hand:
			if are_cards_equal(card, comp_card):
				selected_hand_cards += 1

	var stack_index = -1
	if selected_hand_cards == len(player.hand):
		# Player is allowed to place his up cards
		for comp_card in cards:
			for si in len(player.up):
				var stack = player.up[si]
				for card in stack:
					if are_cards_equal(card, comp_card):
						# The player may only place cards from one stack
						if stack_index != -1 and stack_index != si:
							return false
						stack_index = si
						selected_up_cards += 1

	# If the player places one card in a stack, they have to place all
	if stack_index != -1:
		for comp_card in cards:
			var found = false

			for card in player.up[stack_index]:
				if are_cards_equal(card, comp_card):
					found = true

			if not found:
				return false

	# See if the player is placing only up cards
	placing_only_up_cards = (selected_hand_cards == 0)

	# See if the ammount of found cards is the same as the ammount that the player placed
	return selected_hand_cards + selected_up_cards == len(cards)
	

func reset_placing_state():
	placing_players_turn_again = false
	should_pile_flip = false
	placing_only_up_cards = false


func player_placed_cards(pid: int, transferables: Array):
	reset_placing_state()

	var index: int = find_player_index(pid)
	if index == -1:
		unruly_move(pid, "AEHO")
		return

	var player: Player = players[index]

	var cards: Array = transferable_array_to_cards(remove_duplicates(transferables))

	if len(cards) == 0:
		unruly_move(pid, "HTSMT0C")
		return

	if in_trading_phase:
		unruly_move(pid, "YMNPCDTP")
		return

	var valid_insertion: bool = is_valid_insertion(cards, pid)

	if find_player_index(pid) != turn_index and not valid_insertion:
		unruly_move(pid, "INYTY")
		return

	if not player_has_cards(player, cards):
		unruly_move(pid, "YMNPTCN")
		return

	# Send a duplicate of cards in order to allow are_these_cards_placeable to
	# edit the array safely
	var placeable: bool = are_these_cards_placeable(cards.duplicate())
	if not placeable and not valid_insertion:
		if placing_only_up_cards:
			remove_cards_from_player(index, cards)
			player.hand += cards
			player_picks_up_cards(pid)
		else:
			if len(cards) == 1:
				unruly_move(pid, "YMNPTCH")
			else:
				unruly_move(pid, "YMNPTHCH")
	else:
		accept_move(cards, transferables, pid)


func is_valid_insertion(cards: Array, pid: int) -> bool:
	# Is this a valid "instick" (insertion)

	# There has to be cards in the pile
	if len(pile) == 0:
		return false

	# Has to be homogenous
	if not is_homogenous(cards):
		return false

	# The player has to have the cards
	for card in cards:
		if not is_in_players_hand_cards(card, pid):
			return false

	# The placed cards have to have the same value as the pile top
	var top: Card = pile[len(pile)-1]
	return cards[0].value == top.value


func is_in_players_hand_cards(comp_card: Card, pid: int) -> bool:
	var player = players[find_player_index(pid)]
	for card in player.hand:
		if are_cards_equal(comp_card, card):
			return true

	return false


func player_cards_changed(player):
	var thand = card_array_to_transferable(player.hand)
	var tup = []
	for stack in player.up:
		tup.append(card_array_to_transferable(stack))

	server.rpc_id(player.id, "update_my_cards", thand, tup, len(player.down))

	# Send to other players
	send_player_cards_update(player)


func accept_move(cards: Array, transferables: Array, pid: int):
	# The move is allowed!!

	for p in players:
		server.rpc_id(p.id, "cards_placed", transferables, pid)

	# Put the placed cards in the pile
	for card in cards:
		pile.append(card)

	# Flip if a flippable quadruple is on the top of the pile
	# or if a ten is on top of the pile
	if is_top_flippable_quadruple() or pile[len(pile) - 1].value == 10:
		should_pile_flip = true

	# Player gets the turn again if a two was placed on top, optionally followed by sevens
	var fnsi: int = first_non_seven_index()
	if fnsi != -1 and pile[fnsi].value == 2:
		placing_players_turn_again = true

	var index: int = find_player_index(pid)
	remove_cards_from_player(index, cards)

	if should_pile_flip:
		empty_pile()
	# Don't transfer turn if this is an "instick" (insertion)
	elif not placing_players_turn_again and pid == players[turn_index].id:
		transfer_turn()

	var player = players[index]

	deal_new_cards_to_player(index)

	if is_player_finished(player):
		player.finished = true
		var successful: bool = did_finished_player_go_out_successfully()
		if successful:
			leaderboard.append(player)
		else:
			failed.append(player)

		var reason: String = "PRO"
		if not successful:
			reason = "UNLUCKY"

		# Tell all players that this player is finished
		for p in players:
			server.rpc_id(p.id, "player_finished", pid, reason)

		if should_game_end():
			end_game()

	player_cards_changed(player)

	should_pile_flip = false
	placing_players_turn_again = false


func should_game_end() -> bool:
	# How many players are finished?
	var done_count: int = 0
	for player in players:
		if not is_player_finished(player):
			done_count += 1

	# All but one player have to be finished
	return done_count >= player_count() - 1


func end_game():
	# The order in which to place the players names in the leaderboard
	var order = []

	# The first in leaderboard comes first in order
	for p in leaderboard:
		order.append(p.name)

	# The first in failed comes last in order
	failed.invert()
	for p in failed:
		order.append(p.name)

	for p in players:
		server.rpc_id(p.id, "go_to_leaderboard", order)


func did_finished_player_go_out_successfully() -> bool:
	# The player may not exit by flipping the pile
	if len(pile) == 0:
		return false

	# The player may not exit with a 2
	var fsn: int = first_non_seven_index()
	if fsn != -1 and pile[fsn].value == 2:
		return false

	return true


func is_player_finished(player: Player) -> bool:
	return len(player.hand) == 0 and len(player.down) == 0


func is_top_flippable_quadruple() -> bool:
	# TODO not flippable if a stair was placed to create the quadruple
	# Is a quadruple not consiting of 2, 7, or 10 on the top of the pile?
	if len(pile) < 4:
		return false

	var i = len(pile) - 1 
	var first: Card = pile[i]

	# A stair cannot contain 2, 7, or 10
	if first.value == 2 or first.value == 7 or first.value == 10:
		return false

	#  Check if the top four are non-homogenous 
	var end = i - 3
	while i > end:
		i -= 1
		if pile[i].value != first.value:
			return false

	return true


func transfer_turn():
	if in_trading_phase:
		return 

	turn_index += 1
	if turn_index >= player_count():
		turn_index = 0

	# This player is already done
	if players[turn_index].finished and not should_game_end():
		transfer_turn()

	var pid: int = players[turn_index].id
	for p in players:
		server.rpc_id(p.id, "this_player_has_turn", pid)


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
		deck_ammount_changed()


func deck_ammount_changed():
		for player in players:
			server.rpc_id(player.id, "deck_ammount_changed", len(deck))


func remove_cards_from_player(index, cards):
	var player: Player = players[index]

	for comp_card in cards:
		# Hand cards
		for i in len(player.hand):
			if are_cards_equal(comp_card, player.hand[i]):
				players[index].hand.remove(i)
				break

		# Up cards
		for i in len(player.up):
			for j in len(player.up[i]):
				if are_cards_equal(comp_card, player.up[i][j]):
					players[index].up[i].remove(j)
					break

		# Remove empty stacks from up cards
		var upi: int = 0
		while upi < len(player.up):
			while upi < len(player.up) and len(player.up[upi]) == 0:
				player.up.remove(upi)
			upi += 1

		# Down cards
		for i in len(player.down):
			if are_cards_equal(comp_card, player.down[i]):
				players[index].down.remove(i)
				break


func are_cards_equal(card1: Card, card2: Card) -> bool:
	return card1.value == card2.value and card1.color == card2.color 


func unruly_move(pid: int, reason: String):
	server.rpc_id(pid, "unruly_move", reason)


func are_these_cards_placeable(cards: Array) -> bool:
	# If a two has been placed then any card can be placed afterward
	var two_placed = false

	var fns: int = first_non_seven_index()
	if fns >= 0:
		two_placed = (pile[fns].value == 2)

	# Get rid of 2's and 7's
	var first_is_two: bool = cards[0].value == 2 and is_card_placeable(cards[0])
	var seven_after_two: bool = cards[0].value == 7 and two_placed
	if first_is_two or seven_after_two:
		two_placed = true
		# 2s and 7s allow other combinations after them
		# Remove 2s and 7s in order to allow inspection of other
		# structures
		while len(cards) > 0 and (cards[0].value == 2 or (cards[0].value == 7 and not is_legal_stair(cards))):
			cards.pop_front()

	# Only 2s and 7s were placed
	if len(cards) == 0:
		return true

	var is_first_placeable: bool = is_card_placeable(cards[0])

	# Only one card placed
	if len(cards) == 1:
		return is_first_placeable or two_placed

	# Mulitple cards were placed

	if is_legal_stair(cards):
		return is_first_placeable or two_placed

	var homogenous: bool = is_homogenous(cards)
	if homogenous and (is_first_placeable or two_placed or is_at_least_tripple_three_on_knaker(cards)):
		return true
	
	# No allowed structure was matched
	return false


func is_at_least_tripple_three_on_knaker(cards: Array) -> bool:
	for i in range(0, len(cards)):
		var curr_val: int = cards[i].value
		if curr_val != 3:
			return false

	return is_top_knaker_at_least_rank(3) and not is_top_knaker_at_least_rank(4)


func is_homogenous(cards: Array) -> bool:
	# Are all cards in of the same value
	var first_val: int = cards[0].value

	for card in cards:
		if card.value != first_val:
			return false

	return true


func is_legal_stair(cards: Array) -> bool:
	var prev_val: int = cards[0].value

	# Ammount of unique values encountered
	var unique: int = 1

	# Check all cards, including the first
	for i in range(0, len(cards)):
		var curr_val: int = cards[i].value

		if curr_val == 10 or curr_val == 2:
			return false

		var same: bool = curr_val == prev_val

		if not same:
			# This card has a value different from the one before
			unique += 1

			# Is this card one value higher than the previous?
			var plus_one: bool = curr_val == prev_val + 1
			# Is this stair skipping a seven?
			var seven_skip: bool = prev_val == 6 and curr_val == 8
			# Is this stair skipping a ten?
			var ten_skip: bool = prev_val == 9 and curr_val == Knight
			# Is this a klätterknåker (climbing knaker)?
			var climb: bool = prev_val == Knaker and curr_val == 3

			# Check if gap is too large
			if not (plus_one or seven_skip or ten_skip or climb):
				return false

		prev_val = curr_val

	# A stair has at least 3 unique values
	return unique >= 3

	
func is_card_placeable(card: Card) -> bool:
	if len(pile) == 0:
		return true

	# Use the value of the first card that isn't 7
	var fns: int = first_non_seven_index()
	var top: Card
	if fns >= 0:
		top = pile[fns]
	else:
		top = create_card(1, 0)

	var tv: int = top.value
	
	match card.value:
		2:
			return not is_top_knaker_at_least_rank(3)
		3:
			return tv == 3 or (tv == Knaker and not is_top_knaker_at_least_rank(3))
		7:
			return not is_top_knaker_at_least_rank(2)
		10:
			return not is_top_knaker_at_least_rank(4)
		Knaker:
			# TODO check if frippelknåker
			return tv != 3
		_:
			return card.value >= top.value


func first_non_seven_index() -> int:
	# Find the index of the first card in the pile that isn't seven
	# Returns -1 if the pile consists of only sevens
	var i: int = len(pile)-1
	while i >= 0 and pile[i].value == 7:
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


func player_takes_chance(pid: int):
	var index = find_player_index(pid)
	if index == -1 or index != turn_index or len(deck) == 0:
		return

	reset_placing_state()

	var player = players[index]
	var placed_card: Card = deck.pop_back()
	deck_ammount_changed()

	if are_these_cards_placeable([placed_card]):
		var transferable: Array = [card_to_transferable(placed_card)]
		accept_move([placed_card], transferable, pid)
	else:
		player.hand.append(placed_card)
		player_picks_up_cards(pid)


func player_picks_up_cards(pid: int):
	var index = find_player_index(pid)

	if index == -1 or index != turn_index:
		return

	var player = players[index]
	player.hand += pile
	empty_pile()

	player_cards_changed(player)
	transfer_turn()


func place_card_on_opponent(placing_card: Array, placing_on_pid: int, placing_pid: int, stack_index: int):
	# Only allowed during the trading phase
	if not in_trading_phase:
		return

	# Check if players exist and find their indexes
	var index: int = find_player_index(placing_on_pid)
	if index == -1:
		return

	var placing_index: int = find_player_index(placing_pid)
	if placing_index == -1:
		return

	var placed_on_player = players[index]
	var placing_player = players[placing_index]
	var placing: Card = transferable_to_card(placing_card)

	# See if the card is in the placing player's hand cards
	var placed_card_index: int = -1
	# Was the card found in the player's hand
	var in_hand: bool = false
	for i in len(placing_player.hand):
		if are_cards_equal(placing_player.hand[i], placing):
			in_hand = true
			placed_card_index = i

	if not in_hand:
		# See if the card is in the placing player's up cards
		for i in len(placing_player.hand):
			if are_cards_equal(placing_player.hand[i], placing):
				placed_card_index = i

	# Return if the placing player doesn't have the card
	if placed_card_index == -1:
		return

	# Return if the chosen index is invalid
	if stack_index >= len(placed_on_player.up):
		return

	# Find a card of the same value that the placed card can be placed on
	var top_card = placed_on_player.up[stack_index][0]
	if placing.value == top_card.value:
		if in_hand:
			placing_player.hand.remove(placed_card_index)
		else:
			placing_player.up.remove(placed_card_index)

		placed_on_player.up[stack_index].append(placing)
		placed_on_player.locked_up_indexes.append(stack_index)
		# TODO make it possible to play an animation of the card flying to the opponent
		player_cards_changed(placed_on_player)
		player_cards_changed(placing_player)
		deal_new_cards_to_player(placing_index)


func pick_up_card(card: Array, pid: int):
	# Only allowed during the trading phase
	if not in_trading_phase:
		return

	var index: int = find_player_index(pid)
	if index == -1:
		return
	var player = players[index]

	var tcard: Card = transferable_to_card(card)
	var to_remove: Array = []
	for i in len(player.up):
		# Can not pick up cards from locked stacks
		if not player.locked_up_indexes.has(i):
			for j in len(player.up[i]):
				var up_card = player.up[i][j]
				if are_cards_equal(tcard, up_card):
					player.hand.append(up_card)
					to_remove.append([i, j])

	for dual_index in to_remove:
		var si = dual_index[0]
		player.up[si].remove(dual_index[1])
		if len(player.up[si]) == 0:
			player.up.remove(si)

			# Update locked stacks
			for i in len(player.locked_up_indexes):
				var val: int = player.locked_up_indexes[i]
				if val > si:
					player.locked_up_indexes[i] -= 1


	player_cards_changed(player)
	transfer_turn()


func put_down_card(card: Array, pid: int, up_card_index: int):
	# Only allowed during the trading phase
	if not in_trading_phase:
		return

	var index: int = find_player_index(pid)
	if index == -1:
		return

	var player = players[index]

	# Find the card being placed
	var tcard: Card = transferable_to_card(card)
	var to_place_index: int = -1
	for i in len(player.hand):
		var hand_card = player.hand[i]
		if are_cards_equal(tcard, hand_card):
			to_place_index = i
			break

	# Return if the card couldn't be found
	if to_place_index == -1:
		return

	# Figure out where to place it
	var placed: bool = false
	
	if up_card_index < 0:
		if len(player.up) < 3:
			# Place in a new stack
			player.up.append([player.hand[to_place_index]])
			placed = true
	elif up_card_index < len(player.up):
		# Place in specified stack at index up_card_index
		var top: Card = player.up[up_card_index][0]
		if top.value == card[0]:
			player.up[up_card_index].append(player.hand[to_place_index])
			placed = true

	if placed:
		# Move the card
		player.hand.remove(to_place_index)
		deal_new_cards_to_player(index)
		player_cards_changed(player)

		# It might have become possible to end the trading phase
		end_trading_phase_if_possible()


func leaderboard_want_to_play_again(pid: int):
	for id in want_to_play_again:
		# Already voted
		if id == pid:
			return

	# This player has not already voted		
	want_to_play_again.append(pid)

	var ammount = len(want_to_play_again)

	for p in players:
		server.rpc_id(p.id, "update_players_who_want_to_play_again", ammount)

	# If all players want to play again
	if ammount == len(players):
		# Play again
		restart_game()


func restart_game():
	for p in players:
		server.rpc_id(p.id, "restart_game")

	initialize_game()
