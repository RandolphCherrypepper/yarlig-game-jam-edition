extends Node2D

# modified from my code originally used in https://tallpear.itch.io/lil-guys-candy-run
class RNG:
	var game_seed
	enum rtype {MAP, ITEM, NPC}
	func _init(_seed):
		game_seed = _seed
	func get_value(what: rtype, where: Vector2, level: int) -> int:
		# too much granularity means moving an asset a few pixels in the editor will change
		# the results of procedural generation.
		# drop decimals off x,y location by converting to int.
		# divide to further reduce granularity, because pixel locations are after scaling.
		var int_location = Vector2i(where/8.)
		# hashing context will do some math for us.
		var ctx = HashingContext.new()
		# combine all the parts into a string as
		# seed|level(x,y)typenumber
		var input = str(game_seed) + "|" + str(level) + str(int_location) + str(what)
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
	func len():
		return [len(data), len(data[0])]

class Level:
	var rng
	var level_number
	var board: Array2D
	# always leave "UNSET" at the start to indicate an initialization value
	# always leave "LENGTH" at the end to get the valid length of the enum
	enum m {UNSET, WALL, PATH, ROOM, STAIRS, LOOT, MOB, LENGTH}
	func _init(_rng, _level):
		rng = _rng
		level_number = _level
		board = Array2D.new(3**level_number, 3**level_number)

var my_rng
var tick

func _ready():
	# TODO add seed from user here
	my_rng = RNG.new(0)
	tick = 0
	var curr_level = 1
	var level = Level.new(my_rng, curr_level)
