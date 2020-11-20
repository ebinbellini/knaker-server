extends Node

const PORT = 1840
const MAX_PLAYERS = 50

var room_res = preload("res://room.tscn")
onready var rooms = get_node("rooms")

var room_names = []
var names = {}
var pids = []


func _ready():
	set_network_peer()
	get_tree().connect("network_peer_connected", self, "peer_connected")


func set_network_peer():
	var peer = NetworkedMultiplayerENet.new()
	peer.create_server(PORT, MAX_PLAYERS)
	get_tree().network_peer = peer


func peer_connected(pid: int):
	print("någon anslöt ", pid)
	pids.append(pid)


remote func create_room(room_name):
	print("skapar rum ", room_name)
	var inst = room_res.instance()
	var l = len(room_name)
	if (l > 0 && l <= 30 && find_room(room_name) == null) && names[pid] != null:
		inst.name = room_name
		var sender = get_tree().get_rpc_sender_id()
		inst.call_deferred("set_owner", sender)
		inst.call_deferred("add_player", sender)
		rooms.call_deferred("add_child", inst)


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
	if room != null && names[pid] != null:
		room.add_player(pid)

		rpc_id(pid, "go_to_waiting_room")

		# Notify room members
		var players = room.players()
		for i in range(players):
			rpc_id(players[i], "update_player_data", len(players), )


func find_room(name: String) -> Node:
	var cc = rooms.get_child_count()
	for i in range(cc):
		var room = rooms.get_child(i)
		print(room)
		print(room.name)
		if (room.name == name):
			return room

	return null
	

remote func request_start_game(room_name):
	var pid = get_tree().get_rpc_sender_id()
	var room = find_room(room_name)
	if room != null:
		if pid == room.owner():
			start_game_for_room(room)


func start_game_for_room(room):
	print("STARTAR I RUM ", room)
	var players = room.players()
	for i in range(len(players)):
		var pid = players[i]
		print("BJUDER IN ", pid)
		rpc_id(pid, "start_game")


func set_user_name(name):
	var pid = get_tree().get_rpc_sender_id()
	names[pid] = name
	