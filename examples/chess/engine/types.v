module engine

pub const board_cells = 8
pub const search_depth = 5
pub const quiescence_depth = 8
pub const checkmate_score = 1000000
pub const white_color = 1
pub const black_color = -1
pub const pawn = 1
pub const knight = 2
pub const bishop = 3
pub const rook = 4
pub const queen = 5
pub const king = 6
pub const no_square = -1

const pawn_pst = [
	[0, 0, 0, 0, 0, 0, 0, 0],
	[50, 50, 50, 50, 50, 50, 50, 50],
	[10, 10, 20, 30, 30, 20, 10, 10],
	[5, 5, 10, 25, 25, 10, 5, 5],
	[0, 0, 0, 20, 20, 0, 0, 0],
	[5, -5, -10, 0, 0, -10, -5, 5],
	[5, 10, 10, -20, -20, 10, 10, 5],
	[0, 0, 0, 0, 0, 0, 0, 0],
]

const knight_pst = [
	[-50, -40, -30, -30, -30, -30, -40, -50],
	[-40, -20, 0, 0, 0, 0, -20, -40],
	[-30, 0, 10, 15, 15, 10, 0, -30],
	[-30, 5, 15, 20, 20, 15, 5, -30],
	[-30, 0, 15, 20, 20, 15, 0, -30],
	[-30, 5, 10, 15, 15, 10, 5, -30],
	[-40, -20, 0, 5, 5, 0, -20, -40],
	[-50, -40, -30, -30, -30, -30, -40, -50],
]

const bishop_pst = [
	[-20, -10, -10, -10, -10, -10, -10, -20],
	[-10, 0, 0, 0, 0, 0, 0, -10],
	[-10, 0, 5, 10, 10, 5, 0, -10],
	[-10, 5, 5, 10, 10, 5, 5, -10],
	[-10, 0, 10, 10, 10, 10, 0, -10],
	[-10, 10, 10, 10, 10, 10, 10, -10],
	[-10, 5, 0, 0, 0, 0, 5, -10],
	[-20, -10, -10, -10, -10, -10, -10, -20],
]

const rook_pst = [
	[0, 0, 0, 0, 0, 0, 0, 0],
	[5, 10, 10, 10, 10, 10, 10, 5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[-5, 0, 0, 0, 0, 0, 0, -5],
	[0, 0, 0, 5, 5, 0, 0, 0],
]

const queen_pst = [
	[-20, -10, -10, -5, -5, -10, -10, -20],
	[-10, 0, 0, 0, 0, 0, 0, -10],
	[-10, 0, 5, 5, 5, 5, 0, -10],
	[-5, 0, 5, 5, 5, 5, 0, -5],
	[0, 0, 5, 5, 5, 5, 0, -5],
	[-10, 5, 5, 5, 5, 5, 0, -10],
	[-10, 0, 5, 0, 0, 0, 0, -10],
	[-20, -10, -10, -5, -5, -10, -10, -20],
]

const king_pst_middle = [
	[-30, -40, -40, -50, -50, -40, -40, -30],
	[-30, -40, -40, -50, -50, -40, -40, -30],
	[-30, -40, -40, -50, -50, -40, -40, -30],
	[-30, -40, -40, -50, -50, -40, -40, -30],
	[-20, -30, -30, -40, -40, -30, -30, -20],
	[-10, -20, -20, -20, -20, -20, -20, -10],
	[20, 20, 0, 0, 0, 0, 20, 20],
	[20, 30, 10, 0, 0, 10, 30, 20],
]

const king_pst_end = [
	[-50, -40, -30, -20, -20, -30, -40, -50],
	[-30, -20, -10, 0, 0, -10, -20, -30],
	[-30, -10, 20, 30, 30, 20, -10, -30],
	[-30, -10, 30, 40, 40, 30, -10, -30],
	[-30, -10, 30, 40, 40, 30, -10, -30],
	[-30, -10, 20, 30, 30, 20, -10, -30],
	[-30, -30, 0, 0, 0, 0, -30, -30],
	[-50, -30, -30, -30, -30, -30, -30, -50],
]

const knight_offsets = [
	Pos{1, 2},
	Pos{2, 1},
	Pos{2, -1},
	Pos{1, -2},
	Pos{-1, -2},
	Pos{-2, -1},
	Pos{-2, 1},
	Pos{-1, 2},
]!

const king_offsets = [
	Pos{1, 1},
	Pos{1, 0},
	Pos{1, -1},
	Pos{0, 1},
	Pos{0, -1},
	Pos{-1, 1},
	Pos{-1, 0},
	Pos{-1, -1},
]!

const bishop_dirs = [Pos{1, 1}, Pos{1, -1}, Pos{-1, 1}, Pos{-1, -1}]!
const rook_dirs = [Pos{1, 0}, Pos{-1, 0}, Pos{0, 1}, Pos{0, -1}]!

pub struct Pos {
pub:
	x int
	y int
}

pub struct Move {
pub:
	from_x    int
	from_y    int
	to_x      int
	to_y      int
	promotion int
pub mut:
	score         int
	is_en_passant bool
	is_castle     bool
}

@[heap]
pub struct Position {
pub mut:
	board           [8][8]int
	white_to_move   bool
	white_kingside  bool
	white_queenside bool
	black_kingside  bool
	black_queenside bool
	en_passant_x    int
	en_passant_y    int
	halfmove_clock  int
	fullmove_number int
}

pub struct Engine {
pub mut:
	position_counts map[string]int
	killer_moves    [2][64]int
	history         [2][64][64]int
	move_history    []Move
	fullmove_number int = 1
}

pub struct SearchResult {
pub:
	best_move Move
	score     int
}

pub fn (mut e Engine) reset() {
	e.position_counts = map[string]int{}
	e.move_history = []
	e.fullmove_number = 1
	e.killer_moves = [2][64]int{}
	e.history = [2][64][64]int{}
}

pub fn piece_color(piece int) int {
	if piece > 0 {
		return white_color
	}
	if piece < 0 {
		return black_color
	}
	return 0
}

pub fn piece_kind(piece int) int {
	return if piece < 0 { -piece } else { piece }
}

pub fn piece_value(kind int) int {
	return match kind {
		pawn { 100 }
		knight { 320 }
		bishop { 330 }
		rook { 500 }
		queen { 900 }
		king { 20000 }
		else { 0 }
	}
}

fn inside(x int, y int) bool {
	return x >= 0 && x < board_cells && y >= 0 && y < board_cells
}

fn iabs(v int) int {
	return if v < 0 { -v } else { v }
}
