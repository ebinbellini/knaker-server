extends Object

var playing = false
var player_ids = []
var player_names = []
var owner_id = 0

enum { Spade, Heart, Diamond, Clover }
enum { Kn = 11, Q, K, A, Knk }

var card_values = []
var card_colors = []

func add_player(pid):
	print("adding player ", pid)
	player_ids.append(pid)


func players():
	return player_ids


func player_count():
	return len(player_ids)


func set_owner(pid):
	owner_id = pid

func owner():
	return owner_id
