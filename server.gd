extends Node

const PORT = 1840
const MAX_PLAYERS = 50

var room_res = preload("res://room.tscn")
onready var rooms = get_node("rooms")

var room_names = []
var names = {}
var pids = []


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
	print(pid, " joined room ", room_name)
	var room = find_room(room_name)

	# TODO tell the user if they can't join and why

	if room != null && names[pid] != null && room.player_count() < 6:
		room.add_player(pid, names[pid])

		rpc_id(pid, "go_to_waiting_room")

		# Send updated names to players
		update_player_names(room)


func update_player_names(room: Node):
	print("UPDATERAR SPELARNAMNEN")
	var rpids = room.player_ids()
	print("RPIDS = ", rpids)
	var rpnames = []
	rpnames.resize(len(rpids))
	for i in range(len(rpids)):
		var pid = rpids[i]
		print("PID = ", rpids)
		rpnames[i] = [pid, names[pid]]

	print(rpnames)

	for pid in rpids:
		print("SKICKAR NAMN TILL ", pid)
		rpc_id(pid, "update_player_names", rpnames)


func find_room(name: String) -> Node:
	var cc = rooms.get_child_count()
	for i in range(cc):
		var room = rooms.get_child(i)
		if (room.name == name):
			return room

	return null
	

remote func request_start_game(room_name):
	var pid = get_tree().get_rpc_sender_id()
	var room = find_room(room_name)
	if room != null:
		if pid == room.owner(): # TODO and room.player_count() > 1:
			start_game_for_room(room)


func start_game_for_room(room):
	print("STARTAR I RUM ", room)
	for pid in room.player_ids():
		print("BJUDER IN ", pid)
		rpc_id(pid, "start_loading_game")


remote func ready_for_game(room_name):
	var pid = get_tree().get_rpc_sender_id()
	print(pid, " är redo att spela")
	var room = find_room(room_name)
	room.set_ready(pid)


remote func set_username(name):
	var pid = get_tree().get_rpc_sender_id()
	names[pid] = name
	

remote func place_cards(room_name: String, cards: Array):
	var pid = get_tree().get_rpc_sender_id()
	var room = find_room(room_name)
	if room:
		room.player_placed_cards(pid, cards)
