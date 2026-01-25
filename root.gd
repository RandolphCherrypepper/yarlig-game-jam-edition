# nothing more classic than a large monofile.

extends Node2D

@export var BaseElements : Node2D
@export var ViewPort : Node2D

signal kill_me_now_plz
signal use_level(Level)

#region RNG Engine
# modified from my code originally used in https://tallpear.itch.io/lil-guys-candy-run
class RNG:
	var game_seed
	# TODO merge with the enum m?
	enum rtype {PATH, ROOM, ITEM, MOB}
	func _init(_seed):
		game_seed = _seed
	func get_value(what: rtype, where: Vector2, level: int, additional: String = "") -> int:
		# too much granularity means moving an asset a few pixels in the editor will change
		# the results of procedural generation.
		# drop decimals off x,y location by converting to int.
		# divide to further reduce granularity, because pixel locations are after scaling.
		var int_location = where #Vector2i(where/8.)
		# hashing context will do some math for us.
		var ctx = HashingContext.new()
		# combine all the parts into a string as
		# seed|level(x,y)typenumber
		var input = str(game_seed) + "|" + str(level) + str(int_location) + str(what) + additional
		# md5 is the fastest of the options. generates a 128 bit long string/number.
		ctx.start(HashingContext.HASH_MD5)
		# convert string into UTF8 bytes and add to the hashing context
		ctx.update(input.to_utf8_buffer())
		# perform the hash and get some raw bytes
		var output_bytes = ctx.finish()
		# convert bytes into a 32-bit long integer.
		# that'll support up to a little over 4 million values/options.
		# run modulo on this by max options somewhere else.
		var output = output_bytes.decode_u32(0)
		return output
#endregion

#region Array data types
class Array2D:
	var data
	var n_rows
	var n_cols
	var default
	func _init(_n_rows: int, _n_cols: int, _default=0):
		# TODO make this sparse later. fill in values as they're read or written
		n_rows = _n_rows
		n_cols = _n_cols
		default = _default
		var rows = []
		for row_idx in range(0, n_rows):
			var cols = []
			for col_idx in range(0, n_cols):
				cols.append(default)
			rows.append(cols)
		data = rows
	func getv(r, c):
		return data[r][c]
	func setv(r, c, value):
		data[r][c] = value
	func shape() -> Vector2:
		return Vector2(len(data), len(data[0]))

class CenteredArray2D extends Array2D:
	var center
	func _init(_n_rows: int, _n_cols: int, _default=0):
		# treat n_rows and n_cols as being offset from (0,0) so (-n_rows,-n_cols) through (+n_rows, +n_cols)
		center = Vector2(_n_rows, _n_cols)
		_n_rows = _n_rows*2 + 1
		_n_cols = _n_cols*2 + 1
		super(_n_rows, _n_cols, _default)
	func getv(x, y):
		# map (x,y) values onto rows and columns such that (x,y) follows normal math graphing axes.
		# each x and y can be (-n_rows,-n_cols) through (+n_rows, +n_cols).
		# adjust it to positive values only.
		# swap x and y only on read but not on write.
		# invert only the -x values.
		#return super(y+center.y, -x+center.x) # TODO this in combo with setv changed cancel?
		return super(x+center.x, y+center.y)
	func setv(x, y, value):
		super(x+center.x, y+center.y, value)
	func rect() -> Rect2:
		# return a shape considering it as a full rectangle
		var parent_shape = shape()
		return Rect2(-center.x,-center.y,parent_shape.x,parent_shape.y)
	func debug():
		var dims = rect()
		var values = ""
		for r in range(dims.position.x, dims.position.x + dims.size.x):
			for c in range(dims.position.y, dims.position.y + dims.size.y):
				values += str(getv(r,c)) + " "
			values += "\n"
		print(values)
#endregion

const directions = {
	1: Vector2(1,0),
	2: Vector2(-1,0),
	4: Vector2(0,1),
	8: Vector2(0,-1),
}

class Level:
	var rng
	var level_number
	var renderer
	var player_location: Vector2
	var board: CenteredArray2D
	var kill_me_now_plz
	var recursive_args = {}
	# always leave "STAIRS" at the start.
	# always leave "LAST" at the end to get the valid length of the enum
	# TODO merge with the enum rtype?
	enum m {STAIRS, DOWNSTAIRS, WALL, FLOOR, DOOR, LOOT, MOB, LAST}
	func _init(_kill_me_now_plz, _rng, _level, _renderer, start_location: Vector2):
		player_location = start_location
		rng = _rng
		renderer = _renderer
		kill_me_now_plz = _kill_me_now_plz
		# level alone makes the first level a bit too bleak.
		level_number = _level + 2
		board = CenteredArray2D.new(3*level_number, 3*level_number, m.WALL)
		#var bounds: Rect2 = board.rect()
		# Perform a random walk from the starting location.
		self.recursive_args['touched path'] = {}
		var n_path_tiles = recursive_build_path_dfs(0, 0, start_location, true)
		self.recursive_args.erase('touched path')
		self.recursive_args['touched room'] = {}
		recursive_build_rooms(start_location, n_path_tiles)
		self.recursive_args.erase('touched room')

	func loop_region(f: Callable, region: Rect2, interior=true, corners=true):
		# This function takes a function that is run over each (x,y) in the region.
		# interior=true means include full interior; otherwise only include perimeter.
		var x_start = region.position.x
		var x_stop = region.position.x+region.size.x
		if (x_stop-x_start) < 0:
			# the two values are not in increasing order. fix that.
			var x_tmp = x_start
			x_start = x_stop
			x_stop = x_tmp
		var y_start = region.position.y
		var y_stop = region.position.y+region.size.y
		if (y_stop-y_start) < 0:
			# the two values are not in increasing order. fix that.
			var y_tmp = y_start
			y_start = y_stop
			y_stop = y_tmp
		if interior:
			for x in range(x_start, x_stop):
				for y in range(y_start, y_stop):
					if not corners:
						# skip if (x,y) is a corner
						if x == x_start and y == y_start or \
						   x == x_start and y == y_stop-1 or \
						   x == x_stop-1 and y == y_start or \
						   x == x_stop-1 and y == y_stop-1:
							continue
					f.call(x,y)
		if not interior:
			for x in range(x_start, x_stop):
				for y in [y_start, y_stop-1]:
					if not corners:
						if x == x_start and y == y_start or \
						   x == x_start and y == y_stop-1 or \
						   x == x_stop-1 and y == y_start or \
						   x == x_stop-1 and y == y_stop-1:
							continue
					f.call(x,y)
			# the (x_start,y_start) etc 4 corners were already touched.
			# reduce the y range by one on each side to avoid where the x loop
			# already touched.
			for y in range(y_start+1, y_stop-1):
				for x in [x_start, x_stop-1]:
					if not corners:
						if x == x_start and y == y_start or \
						   x == x_start and y == y_stop-1 or \
						   x == x_stop-1 and y == y_start or \
						   x == x_stop-1 and y == y_stop-1:
							continue
					f.call(x,y)

	func set_region(region: Rect2, m_type: m, interior: bool, corners: bool):
		var set_region_callback = func(x,y):
			board.setv(x,y,m_type)
		loop_region(set_region_callback, region, interior, corners)

	func count_in_room(rule: Callable, region: Rect2, interior: bool):
		# need to keep an accumulator outside the function. keep it in the object.
		self.recursive_args['count'] = 0
		var set_region_callback = func(x,y):
			var this_type = board.getv(x, y)
			if rule.call(this_type):
				self.recursive_args['count'] += 1
		loop_region(set_region_callback, region, interior)

		# extract and remove the object's accumulator
		var count = self.recursive_args['count']
		self.recursive_args.erase('count')
		return count

	func count_non_walls(region: Rect2, interior: bool):
		var _count_non_walls = func(this_type):
			return this_type != m.WALL
		return count_in_room(_count_non_walls, region, interior)

	func count_stairs(region: Rect2, interior: bool):
		var _count_stairs = func(this_type):
			return this_type == m.STAIRS
		return count_in_room(_count_stairs, region, interior)

	func build_doors(region: Rect2):
		var test_sets = {
			"horizontal": [Vector2(-1,0), Vector2(1,0)],
			"vertical": [Vector2(0,-1), Vector2(0,1)],
		}

		for test_set_name in test_sets.keys():
			var test_set = test_sets[test_set_name]
			var set_region_callback = func(x,y):
				var bounds: Rect2 = board.rect()
				var paths = 0
				for check_direction in test_set:
					var check_point = Vector2(x,y) + check_direction
					if bounds.has_point(check_point):
						if board.getv(check_point.x, check_point.y) in [m.FLOOR, m.DOWNSTAIRS, m.STAIRS]:
							# a diagonal is not a wall, don't add a path here
							paths += 1
				if paths < 2:
					return
				# check for how many doors are cross wise
				paths = 0
				var cross_test_set = "horizontal"
				if test_set_name == "horizontal":
					cross_test_set = "vertical"
				for check_direction in test_sets[cross_test_set]:
					var check_point = Vector2(x,y) + check_direction
					if bounds.has_point(check_point):
						if board.getv(check_point.x, check_point.y) == m.DOOR:
							# a diagonal is not a wall, don't add a path here
							paths += 1
				if paths > 0:
					# there's an adjacent door, don't put one here.
					return
				board.setv(x, y, m.DOOR)
			loop_region(set_region_callback, region, false)

	func recursive_build_path_dfs(total_path_tiles, depth, location: Vector2, starting=false, run=0) -> int:
		# shrink the board so that paths never lead off the edge
		var bounds: Rect2 = board.rect().grow_individual(-1, -1, -1, -1)
		var shape = board.rect()
		var level_area = shape.size.x * shape.size.y
		# check full tiles drawn, stop drawing if enough are drawn.
		if total_path_tiles > level_area/5:
			print("hit max tiles ", level_area/5)
			return total_path_tiles
		# prevent too much nesting
		if depth == 32:
			return total_path_tiles
		# make sure this will not create a 2x2 region by testing each set of 3 points
		for test_set in [
			[Vector2(-1,0), Vector2(-1,-1), Vector2(0,-1)],
			[Vector2(1,0), Vector2(1,1), Vector2(0,1)],
			[Vector2(1,0), Vector2(1,-1), Vector2(0,-1)],
			[Vector2(-1,0), Vector2(-1,1), Vector2(0,1)],
		]:
			var test_points = 0
			for check_direction in test_set:
				var check_point = location + check_direction
				if bounds.has_point(check_point):
					if board.getv(check_point.x, check_point.y) != m.WALL:
						# a diagonal is not a wall, don't add a path here
						test_points += 1
			if test_points == 3:
				# this point does not pass the diagonals check. too many diagonals.
				return total_path_tiles
		# this point passes checks, mark it.
		if starting:
			board.setv(location.x, location.y, m.STAIRS)
		else:
			board.setv(location.x, location.y, m.FLOOR)
		total_path_tiles += 1
		# get a random value determinstically
		var rngv: int = rng.get_value(rng.rtype.PATH, location, level_number, str(run))
		# choose one or more directions from up to 4 choices
		var direction = rngv % 16
		while direction == 0:
			if rngv == 0:
				# could not generate a valid path. GIVE UP OMG DO NOT INFINITE LOOP PLZ
				kill_me_now_plz.emit()
			# remove the bits used above; avoids too many slow RNG calls
			@warning_ignore("integer_division")
			rngv = rngv / 16
			direction = rngv % 16
		for val_check in directions.keys():
			if (direction & val_check):
				var new_location = location + directions[val_check]
				if bounds.has_point(new_location):
					# don't keep hitting the same path.
					if new_location not in self.recursive_args['touched path']:
						# mark that the location will be checked.
						# avoid touching a location that already has a path. 
						if board.getv(new_location.x, new_location.y) == m.WALL:
							total_path_tiles = recursive_build_path_dfs(total_path_tiles, depth+1, new_location)
						self.recursive_args['touched path'][new_location] = true

		if starting == true:
			print("total_path_tiles ", total_path_tiles)
			print("desired min tiles ", 2*level_number**2)
		# check full tiles drawn, do another run of tiles if more are needed.
		if starting == true and total_path_tiles < 2*level_number**2:
			# perform another run from root
			total_path_tiles = recursive_build_path_dfs(total_path_tiles, depth+1, location, true, run+1)
		return total_path_tiles

	func room_is_okay(bounds: Rect2, starting_location: Vector2, potential_room: Rect2, consider_walls: bool) -> bool:
		var room_inside = potential_room.grow_individual(-1,-1,-1,-1)
		var room_outer = potential_room.grow_individual(1,1,1,1)
		if not bounds.encloses(room_outer):
			# room is not in the map.
			#print("out of map ", bounds)
			return false
		if potential_room.has_point(starting_location):
			# don't cover the starting location with a room. always hallway.
			#print("covers start")
			return false
		
		var path_tiles_in_room = count_non_walls(room_inside, true)
		if path_tiles_in_room > 0:
			# this room covers too much path
			#print("covers too much path")
			return false

		# ensure no room's corner will override a path. this tends to break the paths to be
		# unnavigable.
		var corners_pass_test = true
		for corner in [
			Vector2(potential_room.position),
			Vector2(potential_room.position+potential_room.size-Vector2(1,1)),
			Vector2(potential_room.position+Vector2(potential_room.size.x-1,0)),
			Vector2(potential_room.position+Vector2(0,potential_room.size.y-1)),
		]:
			if board.getv(corner.x, corner.y) != m.WALL:
				corners_pass_test = false
				break
		if not corners_pass_test:
			#print("touches a corner")
			return false

		var path_tiles_on_perimeter = count_non_walls(potential_room, false)
		if path_tiles_on_perimeter == 0 and consider_walls:
			#print("perimeter is all wall")
			return false

		if count_stairs(potential_room, true) > 0:
			# there are stairs in the room that will be overridden. abort
			#print("stairs in room")
			return false
		# TODO corner can block path ending completeness
		# OR ROOMS DON'T COVER ROOMS
		# valid room!
		#print("valid room ", potential_room)
		return true

	func recursive_build_rooms(starting_location: Vector2, n_path_tiles: int):
		# shrink the board so that paths never lead off the edge
		var bounds: Rect2 = board.rect().grow_individual(-1, -1, -1, -1)
		# get a random value determinstically
		var rngv: int = rng.get_value(rng.rtype.ROOM, starting_location, level_number)
		# decide how many rooms to attempt in this level.
		var n_rooms = rngv % (2*level_number)
		# modify max n_rooms based on how many paths exist.
		if (n_rooms*3) > n_path_tiles:
			print("reducing n rooms")
			@warning_ignore("integer_division")
			n_rooms = int(n_path_tiles/3)
		if n_rooms < 2:
			n_rooms = 2
		# decide how many exits in this level.
		const n_exits = 1
		var tot_rooms = 0
		var tot_exits = 0
		var attempts = 0
		var last_room_attempt = -1
		while tot_rooms < n_rooms and attempts < 1500:
			var room_rngv: int = rng.get_value(rng.rtype.ROOM, starting_location, level_number, ":" + str(attempts))
			attempts += 1
			var min_width = 4
			var min_height = 4
			@warning_ignore("integer_division")
			room_rngv = room_rngv / 256
			var position_x = room_rngv % int(bounds.size.x-min_width) + bounds.position.x
			@warning_ignore("integer_division")
			room_rngv = room_rngv / 256
			var position_y = room_rngv % int(bounds.size.y-min_height) + bounds.position.y
			@warning_ignore("integer_division")
			room_rngv = room_rngv / 256
			var width = min_width
			var height = min_height
			var potential_room = Rect2(position_x, position_y, width, height)
			if potential_room in self.recursive_args['touched room']:
				continue
			var good_room = null
			self.recursive_args['touched room'][potential_room] = true
			while room_is_okay(bounds, starting_location, potential_room, false):
				# this room might grow to meet demands.
				if room_is_okay(bounds, starting_location, potential_room, true):
					# this room meets all demands!
					good_room = potential_room
				# expand room
				width += 1
				height += 1
				potential_room = Rect2(position_x, position_y, width, height)
			if good_room == null:
				# room was never okay. try a new one.
				continue
			potential_room = good_room
			tot_rooms += 1
			last_room_attempt = attempts
			#set_region(room_inside, m.MOB, true, true)
			set_region(potential_room.grow_individual(-1,-1,-1,-1), m.FLOOR, true, true)
			#set_region(potential_room, m.LOOT, false, false)
			set_region(potential_room, m.WALL, false, false)
			build_doors(potential_room)
			if tot_exits < n_exits:
				# if this is the first valid room, drop an exit.
				tot_exits += drop_exit(potential_room)
		print("n_rooms ", n_rooms, " to tot_rooms ", tot_rooms, " at attempt ", last_room_attempt, " out of ", attempts, " attempts")

	func drop_exit(region: Rect2):
		# find a random tile in the room and drop an exit on it.
		var rngv: int = rng.get_value(rng.rtype.ROOM, region.position, level_number)
		print("position ", region.position)
		print("region ", region.size)
		var target = Vector2(0,0)
		var x_loc = (rngv % 16384) % int(region.size.x-2) + 1
		target.x = region.position.x + x_loc
		@warning_ignore("integer_division")
		rngv = rngv / 16384
		var y_loc = (rngv % 16384) % int(region.size.y-2) + 1
		target.y = region.position.y + y_loc
		print("within room diff ", x_loc, " ", y_loc)
		print("dropping a big ol exit all over the place ", target)
		board.setv(target.x, target.y, m.DOWNSTAIRS)
		return 1

	func move_player(change: Vector2):
		var potential_location = player_location + change
		#var potential_type = board.getv(potential_location.x, potential_location.y)
		# can player move?
		#if potential_type not in [m.FLOOR, m.DOOR, m.STAIRS]:
			# nope, player cannot move into this.
		#	return
		# update player location
		player_location = potential_location
		draw(false)

	func draw(swap=false):
		renderer.fill_viewport(self, swap)
		if swap:
			renderer.swap_viewport()

#region Game Object Types
class GameObjectType:
	var collision: bool
	var shape: Array[String]
	var color: Array[String]
	func gframe(animation_frame: int):
		var max_frame = min(len(shape),len(color))
		var use_frame = animation_frame % max_frame
		var this_color = color[use_frame]
		var this_shape = shape[use_frame]
		if this_color != '' and this_shape != '':
			return '[color="#' + this_color + '"]' + this_shape + '[/color]'
		else:
			return false

class StairsType extends GameObjectType:
	var up_direction
	var all_shape
	var all_color
	func _init(_up_direction=true):
		up_direction = _up_direction
		collision = false
		all_shape = {
			true: ['<'] as Array[String],
			false: ['>']  as Array[String],
		}
		color = ['b0b080']
	func gframe(animation_frame: int):
		self.shape = all_shape[self.up_direction]
		return super(animation_frame)
class WallType extends GameObjectType:
	func _init():
		collision = true
		shape = ['#']
		color = ['c0a060']
class FloorType extends GameObjectType:
	func _init():
		collision = false
		shape = ['.']
		color = ['00cc00']
class DoorType extends GameObjectType:
	func _init():
		collision = false
		shape = ['+']
		color = ['cccc00']
class LootType extends GameObjectType:
	func _init():
		collision = false
		shape = ['?']
		color = ['999999']
class MobType extends GameObjectType:
	func _init():
		collision = true
		shape = ['!']
		color = ['cc0000']
class LastType extends GameObjectType:
	func _init():
		collision = false
		shape = [' ']
		color = ['000000']

class PlayerType extends GameObjectType:
	var health
	func _init():
		health = 10
		collision = false
		shape = ['@','']
		color = ['cccc00','']
	func gframe(animation_frame: int):
		if animation_frame == 0:
			return '[color="#cccc00"][outline_size=1][outline_color="#ffffff"]@[/outline_color][/outline_size][/color]'
		else:
			return false
#endregion

#region Rendering code
class Renderer:
	var be_cr: ColorRect
	var be_dtfs: RichTextLabel
	var be_commands: RichTextLabel
	var be_help: RichTextLabel
	var vp_container: Node2D
	var text_shape: Vector2
	var text_center: Vector2
	var charmap: Dictionary
	var animation_frame: int
	var objmap: Dictionary

	func _init(_be_container, _vp_container, _ts, _tc):
		be_cr = _be_container.get_node_and_resource("ColorRect")[0]
		be_dtfs = _be_container.get_node_and_resource("DebugTestFontSize")[0]
		be_commands = _be_container.get_node_and_resource("Commands")[0]
		be_help = _be_container.get_node_and_resource("Help")[0]
		vp_container = _vp_container
		text_shape = _ts
		text_center = _tc
		animation_frame = 0

		# setup dictionary of displays.
		objmap = {
			Level.m.STAIRS: StairsType.new(),
			Level.m.DOWNSTAIRS: StairsType.new(false),
			Level.m.WALL: WallType.new(),
			Level.m.FLOOR: FloorType.new(),
			Level.m.DOOR: DoorType.new(),
			Level.m.LOOT: LootType.new(),
			Level.m.MOB: MobType.new(),
			Level.m.LAST: LastType.new(),
			'player': PlayerType.new()
		}

	func base_elements_default():
		be_cr.show()
		be_dtfs.hide()
		be_commands.show()
		be_help.hide()
		vp_container.show()

	func get_active_viewport() -> RichTextLabel:
		return vp_container.get_children()[animation_frame]

	func get_inactive_viewport() -> RichTextLabel:
		# if animation frame is 0, then 1-0=1. if frame is 1, then 1-1=0.
		return vp_container.get_children()[1-animation_frame]

	func fill_viewport(level: Level, inactive=true):
		base_elements_default()
		# determine which frame we're in.
		var board = level.board
		var dims: Rect2 = board.rect()

		# draw to the inactive_viewport by default
		var viewport
		if inactive:
			viewport = get_inactive_viewport()
		else:
			viewport = get_active_viewport()

		# align player's location as center. level center is always (0,0)
		var player_loc = level.player_location
		var delta = text_center - player_loc
		#text_shape

		# setup map/board/level text
		var map = "\n\n"

		# scan through the screen size. 2 empty rows on top, one empty row on bottom, so -3
		for r in range(0, text_shape.x-3):
			for c in range(0, text_shape.y):
				# convert screen coordinate to play coordinate.
				var cursor = Vector2(r,c) - delta
				if not dims.has_point(cursor):
					map += " "
				else:
					var next_char = ''
					var representation
					if cursor == player_loc and (animation_frame == 0 or not inactive):
						# only draw the character every even frame; unless the draw was force updated.
						# this allows whatever is under the character to be shown on the odd frames.
						representation = objmap['player'].gframe(animation_frame)
						if representation:
							next_char = representation
					representation = objmap[board.getv(cursor.x, cursor.y)].gframe(animation_frame)
					if representation and not next_char:
						# only use this second object if there isn't already a character queued to be added.
						next_char = representation
					map += next_char
			map += "\n"
		# Status line on bottom
		map += "Player location: " + str(player_loc)
		viewport.text = map

	func swap_viewport():
		var active_viewport = get_active_viewport()
		var inactive_viewport = get_inactive_viewport()
		# switch which is hidden and which is shown
		active_viewport.hide()
		inactive_viewport.show()
		# update which animation frame is active
		animation_frame = 1 - animation_frame
#endregion

var my_rng
var tick
var renderer
var level
var last_render = 0
var new_counter = 0
const animation_rate = 0.7
func new_game():
	last_render = 0
	new_counter += 1
	renderer = Renderer.new(BaseElements, ViewPort, Vector2(25, 80), Vector2(11,40))
	# TODO add seed from user here
	print("using seed ", new_counter)
	my_rng = RNG.new(new_counter)
	tick = 0
	var curr_level = 1
	var starting_location = Vector2(0,0)
	# set some new level
	use_level.emit(Level.new(kill_me_now_plz, my_rng, curr_level, renderer, starting_location))

func set_level(_level):
	level = _level
	level.draw(false)

func adjust_window_size_to_text():
	# the ViewPorts are sized based on the font size.
	# there will always be 80x25 characters in the ViewPorts.
	# the ViewPort size should define the entire window size.
	# ViewPort size is inaccessbile??????????????
	# Find desired max height from the vertical scrollbar
	var viewports = ViewPort.get_children()
	var scrollybars: VScrollBar = viewports[0].get_v_scroll_bar()
	var desired_height = scrollybars.max_value+5
	# determine width based on the scrollbar
	var desired_width = desired_height * 1.57
	# now we know the size we want our window to be.
	var desired_size = Vector2i(int(desired_width), int(desired_height))

	# Update the window size itself
	DisplayServer.window_set_size(desired_size)
	get_window().size = desired_size

	# Update all the container sizes
	for vp in viewports:
		vp.size = desired_size
	for thing in $"Base Elements".get_children():
		thing.size = desired_size

var did_size_adjustment = false
func initial_size_adjust():
	if did_size_adjustment:
		return
	var viewport: RichTextLabel = ViewPort.get_children()[0]
	var scrollybars: VScrollBar = viewport.get_v_scroll_bar()
	if scrollybars.max_value == 100 and scrollybars.page == 0:
		# NOT INITIALIZED YET
		return
	# perform initial adjustment for real.
	adjust_window_size_to_text()
	# mark it done
	did_size_adjustment = true

func _ready():
	kill_me_now_plz.connect(quit)
	use_level.connect(set_level)
	new_game()

func _process(delta):
	last_render += delta
	if last_render < animation_rate:
		# not time to update animation yet.
		return
	level.draw(true)
	last_render = 0
	# TODO find a way to run this after ready but just once and not process
	initial_size_adjust()

func quit():
	get_tree().quit()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		# user is trying to close the window. quit the game.
		kill_me_now_plz.emit()

func zoom(mooz=false):
	if not did_size_adjustment:
		return
	var shared_theme = ViewPort.get_children()[0].theme
	if mooz:
		shared_theme.default_font_size -= 1
	else:
		shared_theme.default_font_size += 1
	did_size_adjustment = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		level.move_player(Vector2(-1,0))
	if event.is_action_pressed("ui_down"):
		level.move_player(Vector2(1,0))
	if event.is_action_pressed("ui_left"):
		level.move_player(Vector2(0,-1))
	if event.is_action_pressed("ui_right"):
		level.move_player(Vector2(0,1))
	if event.is_action_pressed("ui_quit"):
		kill_me_now_plz.emit()
	if event.is_action_pressed("ui_new"):
		new_game()
	if event.is_action_pressed("ui_ENHANCE"):
		zoom()
	if event.is_action_pressed("ui_DEHANCE"):
		zoom(true)
