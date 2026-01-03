# nothing more classic than a large monofile.

extends Node2D

@export var BaseElements : Node2D
@export var ViewPort : Node2D

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
	func getv(r, c):
		# row and column can be (-n_rows,-n_cols) through (+n_rows, +n_cols).
		# adjust it to positive values only.
		return super(r+center.x, c+center.y)
	func setv(r, c, value):
		super(r+center.x, c+center.y, value)
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

class Level:
	var rng
	var level_number
	var renderer
	var player_location: Vector2
	var board: CenteredArray2D
	# always leave "STAIRS" at the start.
	# always leave "LAST" at the end to get the valid length of the enum
	enum m {STAIRS, WALL, FLOOR, DOOR, LOOT, MOB, LAST}
	func _init(_rng, _level, _renderer):
		rng = _rng
		renderer = _renderer
		# level alone makes the first level a bit too bleak.
		level_number = _level + 1
		board = CenteredArray2D.new(3*level_number, 3*level_number)
		# for now, fill in the board with random values.
		var dims: Rect2 = board.rect()
		for r in range(dims.position.x, dims.position.x + dims.size.x):
			for c in range(dims.position.y, dims.position.y + dims.size.y):
				# TODO replace temporary fillin
				board.setv(r,c,randi_range(m.STAIRS+1, m.LAST-1))
		#board.debug()
	func set_player_location(loc: Vector2):
		player_location = loc
	func move_player(change: Vector2):
		player_location += change
		draw(false)
	func draw(swap=false):
		renderer.fill_viewport(self, swap)
		if swap:
			renderer.swap_viewport()

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
		charmap = {
			0: {
				Level.m.STAIRS: '[color="#333333"]>[/color]',
				Level.m.WALL: '[color="#666666"]#[/color]',
				Level.m.FLOOR: '[color="#999999"].[/color]',
				Level.m.DOOR: '[color="#cccc00"]#[/color]',
				Level.m.LOOT: '[color="#00cc00"]?[/color]',
				Level.m.MOB: '[color="#cc0000"]![/color]',
				Level.m.LAST: ' ', # acts as empty as well
				'player': '[color="#00cc00"]@[/color]'
			},
			1: {
				Level.m.STAIRS: '[color="#333333"]>[/color]',
				Level.m.WALL: '[color="#666666"]#[/color]',
				Level.m.FLOOR: '[color="#999999"].[/color]',
				Level.m.DOOR: '[color="#cccc00"]#[/color]',
				Level.m.LOOT: '[color="#00cc00"]?[/color]',
				Level.m.MOB: '[color="#cccc00"]![/color]',
				Level.m.LAST: ' ', # acts as empty as well
				'player': '[color="#00cc00"]@[/color]'
			},
		}
	
	func base_elements_default():
		be_cr.show()
		be_dtfs.hide()
		be_commands.show()
		be_help.hide()

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

		# scan through the screen size.
		for r in range(0, text_shape.x):
			for c in range(0, text_shape.y):
				# convert screen coordinate to play coordinate.
				var cursor = Vector2(r,c) - delta
				if not dims.has_point(cursor):
					map += " "
				else:
					#if (cursor + delta) == text_center:
					if cursor == player_loc and (animation_frame == 0 or not inactive):
						# only draw the character every even frame; unless the draw was force updated.
						# this allows whatever is under the character to be shown on the odd frames.
						map += charmap[animation_frame]['player']
					else:
						map += charmap[animation_frame][board.getv(cursor.x, cursor.y)]
			map += "\n"
		viewport.text = map

	func swap_viewport():
		var active_viewport = get_active_viewport()
		var inactive_viewport = get_inactive_viewport()
		# switch which is hidden and which is shown
		active_viewport.hide()
		inactive_viewport.show()
		# update which animation frame is active
		animation_frame = 1 - animation_frame

var my_rng
var tick
var renderer
var level
var last_render = 0
const animation_rate = 0.7
func _ready():
	renderer = Renderer.new(BaseElements, ViewPort, Vector2(25, 80), Vector2(11,40))
	# TODO add seed from user here
	my_rng = RNG.new(0)
	tick = 0
	var curr_level = 1
	level = Level.new(my_rng, curr_level, renderer)
	level.set_player_location(Vector2(0,0))
	level.draw(false)

func _process(delta):
	last_render += delta
	if last_render < animation_rate:
		# not time to update animation yet.
		return
	#level.draw(false)
	level.draw(true)
	last_render = 0

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_up"):
		level.move_player(Vector2(-1,0))
	if event.is_action_pressed("ui_down"):
		level.move_player(Vector2(1,0))
	if event.is_action_pressed("ui_left"):
		level.move_player(Vector2(0,-1))
	if event.is_action_pressed("ui_right"):
		level.move_player(Vector2(0,1))
