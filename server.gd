extends Node

const PORT = 1840
const MAX_PLAYERS = 50

var room_res = preload("res://room.tscn")
onready var rooms = get_node("rooms")

# All room names
var room_names = []
# All player ID:s (PID)
var pids = []
# PID -> Player name
var names = {}
# PID -> Room name
var player_room = {}


func _ready():
	randomize()
	set_network_peer()
	get_tree().connect("network_peer_connected", self, "peer_connected")
	get_tree().connect("network_peer_disconnected", self, "peer_disconnected")


func set_network_peer():
	var peer = WebSocketServer.new()
	peer.listen(PORT, PoolStringArray(["ludus"]), true)
	# TODO USE MAX_PLAYERS

	get_tree().network_peer = peer


func peer_connected(pid: int):
	print("någon anslöt ", pid)
	pids.append(pid)


func peer_disconnected(pid: int):
	print("någon lämnade =-=-= ", pid)
	pids.erase(pid)

	for i in range(rooms.get_child_count()):
		rooms.get_child(i).remove_player(pid)


remote func create_room(room_name):
	print("skapar rum ", room_name)
	var inst = room_res.instance()
	var pid = get_tree().get_rpc_sender_id()
	var l = len(room_name)
	if (l > 0 && l <= 30 && find_room(room_name) == null) && names[pid] != null:
		player_room[pid] = room_name

		inst.name = room_name
		inst.call_deferred("set_room_owner", pid)
		inst.call_deferred("add_player", pid, names[pid])
		rooms.call_deferred("add_child", inst)

		rpc_id(pid, "go_to_waiting_room")


remote func update_rooms():
	var cc = rooms.get_child_count()
	var rnames = []
	for i in range(cc):
		rnames.append(get_child(i).name)

	rset("room_names", rnames)


remote func join_room(room_name):
	var pid = get_tree().get_rpc_sender_id()
	var room = find_room(room_name)

	# TODO tell the user if they can't join and why

	if room != null and not room.playing and names[pid] != null and room.player_count() < 6:
		player_room[pid] = room_name

		room.add_player(pid, names[pid])

		rpc_id(pid, "go_to_waiting_room")

		# Send updated names to players
		update_player_names(room)


func update_player_names(room: Node):
	var rpids = room.player_ids()
	var rpnames = []
	rpnames.resize(len(rpids))
	for i in range(len(rpids)):
		var pid: int = rpids[i]
		rpnames[i] = [pid, names[pid]]

	for pid in rpids:
		rpc_id(pid, "update_player_names", rpnames)


func find_room(name: String) -> Node:
	var cc = rooms.get_child_count()
	for i in range(cc):
		var room = rooms.get_child(i)
		if (room.name == name):
			return room

	return null


func find_player_room(pid: int) -> Node:
	var room_name = player_room[pid]
	if room_name == null:
		return null

	return find_room(room_name)
	

remote func request_start_game():
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)
	if room != null and pid == room.owner(): # TODO and room.player_count() > 1:
			start_game_for_room(room)


func start_game_for_room(room: Node):
	for pid in room.player_ids():
		rpc_id(pid, "start_loading_game")


remote func ready_for_game():
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)
	if room != null:
		room.set_ready(pid)


func all_players_ready(room: Node):
	for id in room.player_ids():
		rpc_id(id, "all_players_ready")


remote func set_username(name: String):
	var pid = get_tree().get_rpc_sender_id()
	names[pid] = name
	

remote func place_cards(cards: Array):
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)
	if room != null:
		room.player_placed_cards(pid, cards)


remote func place_down_card():
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)
	if room != null:
		room.player_placed_down_card(pid)


remote func leave_game():
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)

	# TODO tell all players so they can update their UI
	if room != null:
		room.remove_player(pid)


remote func done_trading():
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)

	if room == null:
		return

	room.set_done_trading(pid)

	var ammount: int = room.players_done_trading()

	for id in room.player_ids():
		rpc_id(id, "update_done_trading_ammount", ammount)


func trading_phase_ended(room: Node):
	for id in room.player_ids():
		rpc_id(id, "start_playing_phase")


remote func place_card_on_opponent(card: Array, opponent_pid: int, stack_index: int):
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)

	if room != null:
		room.place_card_on_opponent(card, opponent_pid, pid, stack_index)


remote func pick_up_card(card: Array):
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)

	if room != null:
		room.pick_up_card(card, pid)


remote func put_down_card(card: Array, up_card_index: int):
	# TODO: Specify which card to place on, or -1 for new stack
	var pid = get_tree().get_rpc_sender_id()
	var room = find_player_room(pid)

	if room != null:
		room.put_down_card(card, pid, up_card_index)
