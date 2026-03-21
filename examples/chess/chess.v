module main

import gg
import os.asset
import rand

const board_cells = 8
const tile_size = 80
const board_padding = 18
const panel_width = 360
const top_height = 0
const window_width = board_padding * 2 + tile_size * board_cells + panel_width
const window_height = board_padding * 2 + tile_size * board_cells
const search_depth = 2
const checkmate_score = 1000000
const white_color = 1
const black_color = -1
const pawn = 1
const knight = 2
const bishop = 3
const rook = 4
const queen = 5
const king = 6
const no_square = -1

struct Pos {
	x int
	y int
}

struct Move {
	from_x        int
	from_y        int
	to_x          int
	to_y          int
	promotion     int
	score         int
	is_en_passant bool
	is_castle     bool
}

struct Position {
mut:
	board           [8][8]int
	white_to_move   bool = true
	white_kingside  bool = true
	white_queenside bool = true
	black_kingside  bool = true
	black_queenside bool = true
	en_passant_x    int  = no_square
	en_passant_y    int  = no_square
	halfmove_clock  int
	fullmove_number int = 1
}

@[heap]
struct Game {
mut:
	ctx                &gg.Context = unsafe { nil }
	pos                Position
	selected_x         int = no_square
	selected_y         int = no_square
	legal_moves        []Move
	hover_moves        []Move
	pending_promotions []Move
	status             string = 'White to move'
	game_over          bool
	images             map[int]int
	position_counts    map[string]int
}

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

const piece_files = {
	1:  'Chess_plt45.png'
	2:  'Chess_nlt45.png'
	3:  'Chess_blt45.png'
	4:  'Chess_rlt45.png'
	5:  'Chess_qlt45.png'
	6:  'Chess_klt45.png'
	-1: 'Chess_pdt45.png'
	-2: 'Chess_ndt45.png'
	-3: 'Chess_bdt45.png'
	-4: 'Chess_rdt45.png'
	-5: 'Chess_qdt45.png'
	-6: 'Chess_kdt45.png'
}

fn main() {
	mut game := &Game{}
	game.reset()
	game.ctx = gg.new_context(
		width:        window_width
		height:       window_height
		window_title: 'V Chess'
		bg_color:     gg.rgb(24, 26, 29)
		user_data:    game
		init_fn:      game.init
		frame_fn:     game.draw
		event_fn:     on_event
		font_path:    asset.get_path('../assets', 'fonts/RobotoMono-Regular.ttf')
	)
	game.ctx.run()
}

fn (mut g Game) init() {
	for piece, name in piece_files {
		g.images[piece] = g.ctx.create_image(asset.get_path('/', name)) or { panic(err) }.id
	}
}

fn (mut g Game) reset() {
	g.pos = Position{
		board: [
			[-rook, -knight, -bishop, -queen, -king, -bishop, -knight, -rook]!,
			[-pawn, -pawn, -pawn, -pawn, -pawn, -pawn, -pawn, -pawn]!,
			[0, 0, 0, 0, 0, 0, 0, 0]!,
			[0, 0, 0, 0, 0, 0, 0, 0]!,
			[0, 0, 0, 0, 0, 0, 0, 0]!,
			[0, 0, 0, 0, 0, 0, 0, 0]!,
			[pawn, pawn, pawn, pawn, pawn, pawn, pawn, pawn]!,
			[rook, knight, bishop, queen, king, bishop, knight, rook]!,
		]!
	}
	g.selected_x = no_square
	g.selected_y = no_square
	g.hover_moves = []Move{}
	g.pending_promotions = []Move{}
	g.game_over = false
	g.position_counts = map[string]int{}
	g.record_position()
	g.update_status()
}

fn on_event(e &gg.Event, mut g Game) {
	match e.typ {
		.key_down {
			match e.key_code {
				.escape {
					g.ctx.quit()
				}
				.r {
					if g.pending_promotions.len > 0 {
						g.try_promotion_shortcut(rook)
					} else {
						g.reset()
					}
				}
				.q {
					g.try_promotion_shortcut(queen)
				}
				.b {
					g.try_promotion_shortcut(bishop)
				}
				.n {
					g.try_promotion_shortcut(knight)
				}
				else {}
			}
		}
		.mouse_down {
			if e.mouse_button == .left {
				g.handle_click(int(e.mouse_x), int(e.mouse_y))
			}
		}
		else {}
	}
}

fn (mut g Game) try_promotion_shortcut(kind int) {
	if g.pending_promotions.len == 0 {
		return
	}
	for mv in g.pending_promotions {
		if mv.promotion == kind {
			g.commit_player_move(mv)
			return
		}
	}
}

fn (mut g Game) handle_click(mouse_x int, mouse_y int) {
	if g.pending_promotions.len > 0 {
		g.handle_promotion_click(mouse_x, mouse_y)
		return
	}
	if g.game_over || !g.pos.white_to_move {
		return
	}
	x, y, ok := board_square_from_mouse(mouse_x, mouse_y)
	if !ok {
		g.clear_selection()
		return
	}
	mut matching := []Move{}
	for mv in g.hover_moves {
		if mv.to_x == x && mv.to_y == y {
			matching << mv
		}
	}
	if matching.len == 1 {
		g.commit_player_move(matching[0])
		return
	}
	if matching.len > 1 {
		g.pending_promotions = matching
		return
	}
	piece := g.pos.board[y][x]
	if piece_color(piece) == white_color {
		if g.selected_x == x && g.selected_y == y {
			g.clear_selection()
		} else {
			g.selected_x = x
			g.selected_y = y
			g.hover_moves = g.moves_from_square(x, y, white_color)
		}
		return
	}
	g.clear_selection()
}

fn (mut g Game) handle_promotion_click(mouse_x int, mouse_y int) {
	for i, mv in g.pending_promotions {
		x, y, w, h := promotion_rect(i)
		if mouse_x >= x && mouse_x < x + w && mouse_y >= y && mouse_y < y + h {
			g.commit_player_move(mv)
			return
		}
	}
}

fn promotion_rect(index int) (int, int, int, int) {
	width := 88
	height := 88
	spacing := 10
	total := 4 * width + 3 * spacing
	start_x := board_padding + (tile_size * board_cells - total) / 2
	y := top_height + board_padding + tile_size * 3
	return start_x + index * (width + spacing), y, width, height
}

fn (mut g Game) clear_selection() {
	g.selected_x = no_square
	g.selected_y = no_square
	g.hover_moves = []Move{}
	g.pending_promotions = []Move{}
}

fn board_square_from_mouse(mouse_x int, mouse_y int) (int, int, bool) {
	board_x := mouse_x - board_padding
	board_y := mouse_y - top_height - board_padding
	if board_x < 0 || board_y < 0 {
		return 0, 0, false
	}
	x := board_x / tile_size
	y := board_y / tile_size
	if !inside(x, y) {
		return 0, 0, false
	}
	return x, y, true
}

fn (mut g Game) commit_player_move(mv Move) {
	g.apply_move(mut g.pos, mv)
	g.clear_selection()
	g.record_position()
	g.update_status()
	if !g.game_over {
		g.make_ai_move()
	}
}

fn (mut g Game) make_ai_move() {
	moves := g.legal_moves_for(g.pos, black_color)
	if moves.len == 0 {
		g.update_status()
		return
	}
	mut best_score := -checkmate_score
	mut candidates := []Move{}
	for mv in moves {
		mut next := g.copy_position(g.pos)
		g.apply_move(mut next, mv)
		score := g.search(next, white_color, search_depth - 1, -checkmate_score, checkmate_score)
		if score > best_score {
			best_score = score
			candidates = [mv]
			continue
		}
		if score >= best_score - 35 {
			candidates << mv
		}
	}
	chosen := candidates[rand.intn(candidates.len) or { 0 }]
	g.apply_move(mut g.pos, chosen)
	g.record_position()
	g.update_status()
}

fn (g &Game) search(pos Position, side int, depth int, alpha0 int, beta0 int) int {
	if pos.halfmove_clock >= 100 || is_insufficient_material(pos) {
		return 0
	}
	mut alpha := alpha0
	mut beta := beta0
	moves := g.legal_moves_for(pos, side)
	if moves.len == 0 {
		if g.is_in_check(pos, side) {
			return if side == black_color {
				-checkmate_score - depth
			} else {
				checkmate_score + depth
			}
		}
		return 0
	}
	if depth == 0 {
		return g.evaluate(pos, moves.len, side)
	}
	if side == black_color {
		mut best := -checkmate_score
		for mv in moves {
			mut next := g.copy_position(pos)
			g.apply_move(mut next, mv)
			score := g.search(next, white_color, depth - 1, alpha, beta)
			if score > best {
				best = score
			}
			if best > alpha {
				alpha = best
			}
			if alpha >= beta {
				break
			}
		}
		return best
	}
	mut best := checkmate_score
	for mv in moves {
		mut next := g.copy_position(pos)
		g.apply_move(mut next, mv)
		score := g.search(next, black_color, depth - 1, alpha, beta)
		if score < best {
			best = score
		}
		if best < beta {
			beta = best
		}
		if alpha >= beta {
			break
		}
	}
	return best
}

fn (g &Game) evaluate(pos Position, mobility int, side int) int {
	mut score := 0
	for y in 0 .. board_cells {
		for x in 0 .. board_cells {
			piece := pos.board[y][x]
			if piece == 0 {
				continue
			}
			color := piece_color(piece)
			kind := piece_kind(piece)
			mut value := piece_value(kind)
			center := 6 - iabs(3 - x) - iabs(3 - y)
			match kind {
				pawn {
					value += if color == black_color { y * 6 } else { (7 - y) * 6 }
				}
				knight, bishop {
					value += center * 8
				}
				rook {
					value += center * 3
				}
				queen {
					value += center * 2
				}
				king {
					value -= center * 4
				}
				else {}
			}
			score += if color == black_color { value } else { -value }
		}
	}
	score += mobility * if side == black_color { 2 } else { -2 }
	if g.is_in_check(pos, white_color) {
		score += 25
	}
	if g.is_in_check(pos, black_color) {
		score -= 25
	}
	return score + (rand.intn(7) or { 0 }) - 3
}

fn (g &Game) moves_from_square(x int, y int, side int) []Move {
	return g.legal_moves_for(g.pos, side).filter(it.from_x == x && it.from_y == y)
}

fn (g &Game) legal_moves_for(pos Position, side int) []Move {
	mut legal := []Move{}
	for mv in g.pseudo_moves_for(pos, side) {
		mut next := g.copy_position(pos)
		g.apply_move(mut next, mv)
		if !g.is_in_check(next, side) {
			legal << mv
		}
	}
	return legal
}

fn (g &Game) pseudo_moves_for(pos Position, side int) []Move {
	mut moves := []Move{}
	for y in 0 .. board_cells {
		for x in 0 .. board_cells {
			piece := pos.board[y][x]
			if piece == 0 || piece_color(piece) != side {
				continue
			}
			match piece_kind(piece) {
				pawn {
					g.add_pawn_moves(pos, side, x, y, mut moves)
				}
				knight {
					g.add_knight_moves(pos, side, x, y, mut moves)
				}
				bishop {
					g.add_sliding_moves(pos, side, x, y, bishop_dirs, mut moves)
				}
				rook {
					g.add_sliding_moves(pos, side, x, y, rook_dirs, mut moves)
				}
				queen {
					g.add_sliding_moves(pos, side, x, y, bishop_dirs, mut moves)
					g.add_sliding_moves(pos, side, x, y, rook_dirs, mut moves)
				}
				king {
					g.add_king_moves(pos, side, x, y, mut moves)
				}
				else {}
			}
		}
	}
	return moves
}

fn (g &Game) add_pawn_moves(pos Position, side int, x int, y int, mut moves []Move) {
	step := if side == white_color { -1 } else { 1 }
	start_row := if side == white_color { 6 } else { 1 }
	promo_row := if side == white_color { 0 } else { 7 }
	one_y := y + step
	if inside(x, one_y) && pos.board[one_y][x] == 0 {
		g.add_pawn_move_or_promotions(side, x, y, x, one_y, 0, false, mut moves)
		two_y := y + step * 2
		if y == start_row && pos.board[two_y][x] == 0 {
			moves << Move{
				from_x: x
				from_y: y
				to_x:   x
				to_y:   two_y
			}
		}
	}
	for dx in [-1, 1] {
		nx := x + dx
		ny := y + step
		if !inside(nx, ny) {
			continue
		}
		target := pos.board[ny][nx]
		if target != 0 && piece_color(target) == -side {
			g.add_pawn_move_or_promotions(side, x, y, nx, ny, piece_value(piece_kind(target)),
				false, mut moves)
			continue
		}
		if pos.en_passant_x == nx && pos.en_passant_y == ny {
			moves << Move{
				from_x:        x
				from_y:        y
				to_x:          nx
				to_y:          ny
				is_en_passant: true
				score:         105
			}
		}
	}
	if one_y == promo_row {
		_ := true
	}
}

fn (g &Game) add_pawn_move_or_promotions(side int, from_x int, from_y int, to_x int, to_y int, score int, is_en_passant bool, mut moves []Move) {
	promo_row := if side == white_color { 0 } else { 7 }
	if to_y != promo_row {
		moves << Move{
			from_x:        from_x
			from_y:        from_y
			to_x:          to_x
			to_y:          to_y
			is_en_passant: is_en_passant
			score:         score
		}
		return
	}
	for kind in [queen, rook, bishop, knight] {
		moves << Move{
			from_x:        from_x
			from_y:        from_y
			to_x:          to_x
			to_y:          to_y
			promotion:     kind
			is_en_passant: is_en_passant
			score:         score + if kind == queen { 700 } else { 350 }
		}
	}
}

fn (g &Game) add_knight_moves(pos Position, side int, x int, y int, mut moves []Move) {
	for offset in knight_offsets {
		nx := x + offset.x
		ny := y + offset.y
		if !inside(nx, ny) {
			continue
		}
		target := pos.board[ny][nx]
		if target == 0 || piece_color(target) == -side {
			moves << Move{
				from_x: x
				from_y: y
				to_x:   nx
				to_y:   ny
				score:  if target == 0 { 0 } else { piece_value(piece_kind(target)) }
			}
		}
	}
}

fn (g &Game) add_sliding_moves(pos Position, side int, x int, y int, dirs [4]Pos, mut moves []Move) {
	for dir in dirs {
		mut nx := x + dir.x
		mut ny := y + dir.y
		for inside(nx, ny) {
			target := pos.board[ny][nx]
			if target == 0 {
				moves << Move{
					from_x: x
					from_y: y
					to_x:   nx
					to_y:   ny
				}
			} else {
				if piece_color(target) == -side {
					moves << Move{
						from_x: x
						from_y: y
						to_x:   nx
						to_y:   ny
						score:  piece_value(piece_kind(target))
					}
				}
				break
			}
			nx += dir.x
			ny += dir.y
		}
	}
}

fn (g &Game) add_king_moves(pos Position, side int, x int, y int, mut moves []Move) {
	for offset in king_offsets {
		nx := x + offset.x
		ny := y + offset.y
		if !inside(nx, ny) {
			continue
		}
		target := pos.board[ny][nx]
		if target == 0 || piece_color(target) == -side {
			moves << Move{
				from_x: x
				from_y: y
				to_x:   nx
				to_y:   ny
				score:  if target == 0 { 0 } else { piece_value(piece_kind(target)) }
			}
		}
	}
	if g.is_in_check(pos, side) {
		return
	}
	if side == white_color && y == 7 && x == 4 {
		if pos.white_kingside && pos.board[7][5] == 0 && pos.board[7][6] == 0
			&& pos.board[7][7] == rook && !g.square_attacked(pos, 5, 7, black_color)
			&& !g.square_attacked(pos, 6, 7, black_color) {
			moves << Move{
				from_x:    4
				from_y:    7
				to_x:      6
				to_y:      7
				is_castle: true
				score:     30
			}
		}
		if pos.white_queenside && pos.board[7][1] == 0 && pos.board[7][2] == 0
			&& pos.board[7][3] == 0 && pos.board[7][0] == rook
			&& !g.square_attacked(pos, 3, 7, black_color)
			&& !g.square_attacked(pos, 2, 7, black_color) {
			moves << Move{
				from_x:    4
				from_y:    7
				to_x:      2
				to_y:      7
				is_castle: true
				score:     20
			}
		}
	}
	if side == black_color && y == 0 && x == 4 {
		if pos.black_kingside && pos.board[0][5] == 0 && pos.board[0][6] == 0
			&& pos.board[0][7] == -rook && !g.square_attacked(pos, 5, 0, white_color)
			&& !g.square_attacked(pos, 6, 0, white_color) {
			moves << Move{
				from_x:    4
				from_y:    0
				to_x:      6
				to_y:      0
				is_castle: true
				score:     30
			}
		}
		if pos.black_queenside && pos.board[0][1] == 0 && pos.board[0][2] == 0
			&& pos.board[0][3] == 0 && pos.board[0][0] == -rook
			&& !g.square_attacked(pos, 3, 0, white_color)
			&& !g.square_attacked(pos, 2, 0, white_color) {
			moves << Move{
				from_x:    4
				from_y:    0
				to_x:      2
				to_y:      0
				is_castle: true
				score:     20
			}
		}
	}
}

fn (g &Game) apply_move(mut pos Position, mv Move) {
	piece := pos.board[mv.from_y][mv.from_x]
	side := piece_color(piece)
	mut captured := pos.board[mv.to_y][mv.to_x]
	pos.en_passant_x = no_square
	pos.en_passant_y = no_square
	if mv.is_en_passant {
		captured = pos.board[mv.from_y][mv.to_x]
		pos.board[mv.from_y][mv.to_x] = 0
	}
	pos.board[mv.from_y][mv.from_x] = 0
	pos.board[mv.to_y][mv.to_x] = if mv.promotion == 0 { piece } else { side * mv.promotion }
	if mv.is_castle {
		if mv.to_x == 6 {
			pos.board[mv.to_y][5] = pos.board[mv.to_y][7]
			pos.board[mv.to_y][7] = 0
		} else {
			pos.board[mv.to_y][3] = pos.board[mv.to_y][0]
			pos.board[mv.to_y][0] = 0
		}
	}
	if piece == king {
		pos.white_kingside = false
		pos.white_queenside = false
	}
	if piece == -king {
		pos.black_kingside = false
		pos.black_queenside = false
	}
	if mv.from_x == 0 && mv.from_y == 7 && piece == rook {
		pos.white_queenside = false
	}
	if mv.from_x == 7 && mv.from_y == 7 && piece == rook {
		pos.white_kingside = false
	}
	if mv.from_x == 0 && mv.from_y == 0 && piece == -rook {
		pos.black_queenside = false
	}
	if mv.from_x == 7 && mv.from_y == 0 && piece == -rook {
		pos.black_kingside = false
	}
	if mv.to_x == 0 && mv.to_y == 7 && captured == rook {
		pos.white_queenside = false
	}
	if mv.to_x == 7 && mv.to_y == 7 && captured == rook {
		pos.white_kingside = false
	}
	if mv.to_x == 0 && mv.to_y == 0 && captured == -rook {
		pos.black_queenside = false
	}
	if mv.to_x == 7 && mv.to_y == 0 && captured == -rook {
		pos.black_kingside = false
	}
	if piece_kind(piece) == pawn && iabs(mv.to_y - mv.from_y) == 2 {
		pos.en_passant_x = mv.from_x
		pos.en_passant_y = (mv.from_y + mv.to_y) / 2
	}
	if piece_kind(piece) == pawn || captured != 0 {
		pos.halfmove_clock = 0
	} else {
		pos.halfmove_clock++
	}
	if side == black_color {
		pos.fullmove_number++
	}
	pos.white_to_move = !pos.white_to_move
}

fn (g &Game) is_in_check(pos Position, side int) bool {
	kx, ky := g.find_king(pos, side)
	if kx == no_square {
		return true
	}
	return g.square_attacked(pos, kx, ky, -side)
}

fn (g &Game) find_king(pos Position, side int) (int, int) {
	target := side * king
	for y in 0 .. board_cells {
		for x in 0 .. board_cells {
			if pos.board[y][x] == target {
				return x, y
			}
		}
	}
	return no_square, no_square
}

fn (g &Game) square_attacked(pos Position, x int, y int, attacker int) bool {
	if attacker == white_color {
		py := y + 1
		if py < board_cells {
			if x > 0 && pos.board[py][x - 1] == pawn {
				return true
			}
			if x + 1 < board_cells && pos.board[py][x + 1] == pawn {
				return true
			}
		}
	} else {
		py := y - 1
		if py >= 0 {
			if x > 0 && pos.board[py][x - 1] == -pawn {
				return true
			}
			if x + 1 < board_cells && pos.board[py][x + 1] == -pawn {
				return true
			}
		}
	}
	for offset in knight_offsets {
		nx := x + offset.x
		ny := y + offset.y
		if inside(nx, ny) && pos.board[ny][nx] == attacker * knight {
			return true
		}
	}
	for dir in bishop_dirs {
		mut nx := x + dir.x
		mut ny := y + dir.y
		for inside(nx, ny) {
			piece := pos.board[ny][nx]
			if piece != 0 {
				if piece == attacker * bishop || piece == attacker * queen {
					return true
				}
				break
			}
			nx += dir.x
			ny += dir.y
		}
	}
	for dir in rook_dirs {
		mut nx := x + dir.x
		mut ny := y + dir.y
		for inside(nx, ny) {
			piece := pos.board[ny][nx]
			if piece != 0 {
				if piece == attacker * rook || piece == attacker * queen {
					return true
				}
				break
			}
			nx += dir.x
			ny += dir.y
		}
	}
	for offset in king_offsets {
		nx := x + offset.x
		ny := y + offset.y
		if inside(nx, ny) && pos.board[ny][nx] == attacker * king {
			return true
		}
	}
	return false
}

fn (mut g Game) update_status() {
	side := if g.pos.white_to_move { white_color } else { black_color }
	if g.pos.halfmove_clock >= 100 {
		g.game_over = true
		g.status = 'Draw by fifty-move rule.'
		g.legal_moves = []Move{}
		return
	}
	if g.position_counts[g.position_key(g.pos)] >= 3 {
		g.game_over = true
		g.status = 'Draw by threefold repetition.'
		g.legal_moves = []Move{}
		return
	}
	if is_insufficient_material(g.pos) {
		g.game_over = true
		g.status = 'Draw by insufficient material.'
		g.legal_moves = []Move{}
		return
	}
	g.legal_moves = g.legal_moves_for(g.pos, side)
	in_check := g.is_in_check(g.pos, side)
	if g.legal_moves.len == 0 {
		g.game_over = true
		g.status = if in_check {
			if side == white_color { 'Checkmate. Black wins.' } else { 'Checkmate. White wins.' }
		} else {
			'Stalemate.'
		}
		return
	}
	g.game_over = false
	side_name := if g.pos.white_to_move { 'White' } else { 'Black' }
	g.status = if in_check { '${side_name} to move, check.' } else { '${side_name} to move.' }
}

fn (mut g Game) record_position() {
	key := g.position_key(g.pos)
	g.position_counts[key]++
}

fn (g &Game) position_key(pos Position) string {
	mut key := ''
	for y in 0 .. board_cells {
		for x in 0 .. board_cells {
			key += '${pos.board[y][x]},'
		}
	}
	key += if pos.white_to_move { 'w' } else { 'b' }
	key += if pos.white_kingside { 'K' } else { '-' }
	key += if pos.white_queenside { 'Q' } else { '-' }
	key += if pos.black_kingside { 'k' } else { '-' }
	key += if pos.black_queenside { 'q' } else { '-' }
	key += '${pos.en_passant_x}:${pos.en_passant_y}'
	return key
}

fn (g &Game) copy_position(pos Position) Position {
	mut next := Position{}
	next = pos
	return next
}

fn (g &Game) draw() {
	g.ctx.begin()
	g.draw_board()
	g.draw_panel()
	if g.pending_promotions.len > 0 {
		g.draw_promotion_overlay()
	}
	g.ctx.end()
}

fn (g &Game) draw_board() {
	for y in 0 .. board_cells {
		for x in 0 .. board_cells {
			sx := board_padding + x * tile_size
			sy := top_height + board_padding + y * tile_size
			mut color := if (x + y) % 2 == 0 { gg.rgb(240, 217, 181) } else { gg.rgb(181, 136, 99) }
			if g.selected_x == x && g.selected_y == y {
				color = gg.rgb(214, 204, 91)
			}
			if g.hover_moves.any(it.to_x == x && it.to_y == y) {
				color = if g.pos.board[y][x] == 0 {
					gg.rgb(202, 219, 143)
				} else {
					gg.rgb(219, 143, 143)
				}
			}
			g.ctx.draw_rect_filled(sx, sy, tile_size, tile_size, color)
			g.ctx.draw_rect_empty(sx, sy, tile_size, tile_size, gg.rgba(0, 0, 0, 70))
			piece := g.pos.board[y][x]
			if piece != 0 {
				g.ctx.draw_image_by_id(sx + 6, sy + 6, tile_size - 12, tile_size - 12,
					g.images[piece])
			} else if g.hover_moves.any(it.to_x == x && it.to_y == y) {
				g.ctx.draw_circle_filled(f32(sx + tile_size / 2), f32(sy + tile_size / 2),
					8, gg.rgba(0, 0, 0, 85))
			}
		}
	}
	for i in 0 .. board_cells {
		g.ctx.draw_text(board_padding + i * tile_size + tile_size / 2 - 6, top_height +
			board_padding + tile_size * board_cells + 4, '${rune(`a` + i)}', color: gg.white)
		g.ctx.draw_text(4, top_height + board_padding + i * tile_size + tile_size / 2 - 8,
			'${8 - i}', color: gg.white)
	}
}

fn (g &Game) draw_panel() {
	panel_x := board_padding * 2 + board_cells * tile_size
	g.ctx.draw_text(panel_x, 88, g.status, color: gg.white, size: 20)
	g.ctx.draw_text(panel_x, 145, 'White: you', color: gg.rgb(230, 230, 230), size: 18)
	g.ctx.draw_text(panel_x, 175, 'Black: simple AI', color: gg.rgb(200, 200, 200), size: 18)
	g.ctx.draw_text(panel_x, 220, 'Click a white piece, then click a legal square.',
		color: gg.gray
		size:  16
	)
	g.ctx.draw_text(panel_x, 260, 'Controls:', color: gg.white, size: 18)
	g.ctx.draw_text(panel_x, 290, 'R  restart', color: gg.gray, size: 16)
	g.ctx.draw_text(panel_x, 316, 'Esc  quit', color: gg.gray, size: 16)
	g.ctx.draw_text(panel_x, 356, 'Promotion: click a piece or use Q/R/B/N.',
		color: gg.gray
		size:  16
	)
	g.ctx.draw_text(panel_x, 404, 'Rules:', color: gg.white, size: 18)
	g.ctx.draw_text(panel_x, 434, 'Castling', color: gg.gray, size: 16)
	g.ctx.draw_text(panel_x, 458, 'En passant', color: gg.gray, size: 16)
	g.ctx.draw_text(panel_x, 482, 'Full promotions', color: gg.gray, size: 16)
	g.ctx.draw_text(panel_x, 506, '50-move / 3-fold / material draws',
		color: gg.gray
		size:  16
	)
}

fn (g &Game) draw_promotion_overlay() {
	g.ctx.draw_rect_filled(board_padding, top_height + board_padding, tile_size * board_cells,
		tile_size * board_cells, gg.rgba(10, 10, 10, 160))
	for i, mv in g.pending_promotions {
		x, y, w, h := promotion_rect(i)
		g.ctx.draw_rect_filled(x, y, w, h, gg.rgb(230, 230, 230))
		g.ctx.draw_rect_empty(x, y, w, h, gg.black)
		piece := mv.promotion
		g.ctx.draw_image_by_id(x + 8, y + 8, w - 16, h - 16, g.images[piece])
	}
	g.ctx.draw_text(board_padding + 140, top_height + board_padding + tile_size * 2 + 4,
		'Choose promotion', color: gg.white, size: 28)
}

fn piece_color(piece int) int {
	if piece > 0 {
		return white_color
	}
	if piece < 0 {
		return black_color
	}
	return 0
}

fn piece_kind(piece int) int {
	return if piece < 0 { -piece } else { piece }
}

fn piece_value(kind int) int {
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

fn is_insufficient_material(pos Position) bool {
	mut bishops := []Pos{}
	mut knights := 0
	mut other_material := false
	for y in 0 .. board_cells {
		for x in 0 .. board_cells {
			piece := pos.board[y][x]
			kind := piece_kind(piece)
			if piece == 0 || kind == king {
				continue
			}
			if kind == pawn || kind == rook || kind == queen {
				other_material = true
				break
			}
			if kind == bishop {
				bishops << Pos{x, y}
			}
			if kind == knight {
				knights++
			}
		}
		if other_material {
			break
		}
	}
	if other_material {
		return false
	}
	if bishops.len == 0 && knights == 0 {
		return true
	}
	if bishops.len == 0 && knights == 1 {
		return true
	}
	if bishops.len == 1 && knights == 0 {
		return true
	}
	if bishops.len == 0 && knights == 2 {
		return true
	}
	if bishops.len == 2 && knights == 0 {
		return same_color_square(bishops[0]) == same_color_square(bishops[1])
	}
	return false
}

fn same_color_square(pos Pos) bool {
	return (pos.x + pos.y) % 2 == 0
}

fn inside(x int, y int) bool {
	return x >= 0 && x < board_cells && y >= 0 && y < board_cells
}

fn iabs(v int) int {
	return if v < 0 { -v } else { v }
}
