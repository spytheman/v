module engine

import time

const ai_time_limit_ms = 2000

pub fn (mut e Engine) new_position() Position {
	return Position{
		board:           [
			[-rook, -knight, -bishop, -queen, -king, -bishop, -knight, -rook]!,
			[-pawn, -pawn, -pawn, -pawn, -pawn, -pawn, -pawn, -pawn]!,
			[0, 0, 0, 0, 0, 0, 0, 0]!,
			[0, 0, 0, 0, 0, 0, 0, 0]!,
			[0, 0, 0, 0, 0, 0, 0, 0]!,
			[0, 0, 0, 0, 0, 0, 0, 0]!,
			[pawn, pawn, pawn, pawn, pawn, pawn, pawn, pawn]!,
			[rook, knight, bishop, queen, king, bishop, knight, rook]!,
		]!
		fullmove_number: 1
	}
}

pub fn (mut e Engine) search_best_move(pos Position, side int) Move {
	return e.search_best_move_with_time(pos, side, ai_time_limit_ms)
}

pub fn (mut e Engine) search_best_move_with_time(pos Position, side int, time_limit_ms int) Move {
	e.killer_moves = [2][64]int{}
	e.history = [2][64][64]int{}
	mut best_score := -checkmate_score
	mut best_move := Move{}
	mut alpha := -checkmate_score
	mut beta := checkmate_score
	window := 50
	start_time := time.ticks()
	moves := e.legal_moves_for(pos, side)
	if moves.len == 0 {
		return Move{}
	}
	for current_depth := 1; current_depth <= search_depth; current_depth++ {
		if time.ticks() - start_time > time_limit_ms {
			break
		}
		for mv in moves {
			if time.ticks() - start_time > time_limit_ms {
				break
			}
			mut next := e.copy_position(pos)
			apply_move(mut next, mv)
			other_side := if side == black_color { white_color } else { black_color }
			score := e.search(next, other_side, current_depth - 1, alpha, beta, 0)
			if score > best_score {
				best_score = score
				best_move = mv
			}
		}
		if best_score <= alpha || best_score >= beta {
			alpha = -checkmate_score
			beta = checkmate_score
		} else {
			alpha = best_score - window
			beta = best_score + window
		}
	}
	if best_move == Move{} {
		best_move = moves[0]
	}
	return best_move
}

fn (mut e Engine) search(pos Position, side int, depth int, alpha0 int, beta0 int, ply int) int {
	if pos.halfmove_clock >= 100 || is_insufficient_material(pos) {
		return 0
	}
	mut alpha := alpha0
	mut beta := beta0
	moves := e.legal_moves_for(pos, side)
	if moves.len == 0 {
		if e.is_in_check(pos, side) {
			return if side == black_color {
				-checkmate_score - depth
			} else {
				checkmate_score + depth
			}
		}
		return 0
	}
	if depth == 0 {
		return e.quiescence(pos, alpha, beta, side, 0)
	}
	ordered := e.order_moves(moves, pos, side, ply)
	if side == black_color {
		mut best := -checkmate_score
		for mv in ordered {
			mut next := e.copy_position(pos)
			apply_move(mut next, mv)
			score := e.search(next, white_color, depth - 1, alpha, beta, ply + 1)
			if score > best {
				best = score
			}
			if best > alpha {
				alpha = best
			}
			if alpha >= beta {
				if mv.score == 0 {
					e.killer_moves[1][ply] = mv.to_y * 64 + mv.to_x
					e.history[1][mv.from_y][mv.from_x] += depth * depth
				}
				break
			}
		}
		return best
	}
	mut best := checkmate_score
	for mv in ordered {
		mut next := e.copy_position(pos)
		apply_move(mut next, mv)
		score := e.search(next, black_color, depth - 1, alpha, beta, ply + 1)
		if score < best {
			best = score
		}
		if best < beta {
			beta = best
		}
		if alpha >= beta {
			if mv.score == 0 {
				e.killer_moves[0][ply] = mv.to_y * 64 + mv.to_x
				e.history[0][mv.from_y][mv.from_x] += depth * depth
			}
			break
		}
	}
	return best
}

fn (e &Engine) quiescence(pos Position, alpha_ int, beta_ int, side int, depth int) int {
	if depth >= quiescence_depth {
		return e.evaluate(pos, 0, side)
	}
	mut alpha := alpha_
	mut beta := beta_
	mut captures := e.legal_moves_for(pos, side).filter(it.score > 0 || it.is_en_passant)
	if captures.len == 0 {
		return e.evaluate(pos, 0, side)
	}
	e.sort_captures(mut captures, pos)
	if side == black_color {
		mut stand_pat := e.evaluate(pos, 0, side)
		if stand_pat > alpha {
			alpha = stand_pat
		}
		if alpha >= beta {
			return beta
		}
		mut best := -checkmate_score
		for mv in captures {
			mut next := e.copy_position(pos)
			apply_move(mut next, mv)
			score := e.quiescence(next, alpha, beta, white_color, depth + 1)
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
	mut stand_pat := e.evaluate(pos, 0, side)
	if stand_pat < beta {
		beta = stand_pat
	}
	mut best := checkmate_score
	for mv in captures {
		mut next := e.copy_position(pos)
		apply_move(mut next, mv)
		score := e.quiescence(next, alpha, beta, black_color, depth + 1)
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

fn (e &Engine) order_moves(moves []Move, pos Position, side int, ply int) []Move {
	mut scored := moves.map(fn [e, pos, side, ply] (mv Move) int {
		mut s := 0
		if mv.is_en_passant {
			s += 500
		}
		if mv.score > 0 {
			s += 10000
		}
		to_sq := mv.to_y * 64 + mv.to_x
		if side == black_color {
			if e.killer_moves[1][ply] == to_sq {
				s += 900
			}
			s += e.history[1][mv.from_y][mv.from_x]
		} else {
			if e.killer_moves[0][ply] == to_sq {
				s += 900
			}
			s += e.history[0][mv.from_y][mv.from_x]
		}
		if mv.is_castle {
			s += 50
		}
		if e.is_in_check(pos, side) {
			s += 50
		}
		return s
	})
	mut result := []Move{}
	for i, mv in moves {
		mut m := mv
		m.score = scored[i]
		result << m
	}
	result.sort(a.score > b.score)
	return result
}

fn (e &Engine) sort_captures(mut moves []Move, _ Position) {
	moves.sort(a.score > b.score)
}

fn (e &Engine) evaluate(pos Position, mobility int, side int) int {
	mut score := 0
	mut white_bishops := 0
	mut black_bishops := 0
	mut white_has_queen := false
	mut black_has_queen := false
	mut white_pawn_files := [8]int{}
	mut black_pawn_files := [8]int{}
	mut white_pawn_attacks := [8]int{}
	mut black_pawn_attacks := [8]int{}
	mut white_king_rank := 7
	mut black_king_rank := 0
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
			piece := pos.board[y][x]
			if piece == 0 {
				continue
			}
			color := piece_color(piece)
			kind := piece_kind(piece)
			mut value := piece_value(kind)
			mut pst_bonus := 0
			py := if color == white_color { 7 - y } else { y }
			match kind {
				pawn {
					pst_bonus = pawn_pst[py][x]
					if color == white_color {
						white_pawn_files[x]++
						mut blocked := false
						for ey := y - 1; ey >= 0; ey-- {
							if pos.board[ey][x] == pawn || pos.board[ey][x] == -pawn {
								blocked = true
								break
							}
						}
						if !blocked {
							mut is_passed := true
							for dx := -1; dx <= 1; dx++ {
								nx := x + dx
								if nx < 0 || nx > 7 {
									continue
								}
								for ey := y - 1; ey >= 0; ey-- {
									if pos.board[ey][nx] == -pawn {
										is_passed = false
										break
									}
								}
							}
							if is_passed {
								pst_bonus += 50 + y * 15
							}
						}
						if x > 0 {
							white_pawn_attacks[x - 1]++
						}
						if x < 7 {
							white_pawn_attacks[x + 1]++
						}
					} else {
						black_pawn_files[x]++
						mut blocked := false
						for ey := y + 1; ey < 8; ey++ {
							if pos.board[ey][x] == pawn || pos.board[ey][x] == -pawn {
								blocked = true
								break
							}
						}
						if !blocked {
							mut is_passed := true
							for dx := -1; dx <= 1; dx++ {
								nx := x + dx
								if nx < 0 || nx > 7 {
									continue
								}
								for ey := y + 1; ey < 8; ey++ {
									if pos.board[ey][nx] == pawn {
										is_passed = false
										break
									}
								}
							}
							if is_passed {
								pst_bonus += 50 + (7 - y) * 15
							}
						}
						if x > 0 {
							black_pawn_attacks[x - 1]++
						}
						if x < 7 {
							black_pawn_attacks[x + 1]++
						}
					}
				}
				knight {
					pst_bonus = knight_pst[py][x]
					if color == white_color && (py >= 4 && (x == 2 || x == 5)) {
						pst_bonus += 15
					}
					if color == black_color && (py <= 3 && (x == 2 || x == 5)) {
						pst_bonus += 15
					}
				}
				bishop {
					pst_bonus = bishop_pst[py][x]
					if color == white_color {
						white_bishops++
						if x >= 2 && x <= 5 && y >= 3 && y <= 4 {
							pst_bonus += 10
						}
					} else {
						black_bishops++
						if x >= 2 && x <= 5 && y >= 3 && y <= 4 {
							pst_bonus += 10
						}
					}
				}
				rook {
					pst_bonus = rook_pst[py][x]
					mut open_file := white_pawn_files[x] == 0 && black_pawn_files[x] == 0
					mut semi_open_white := color == white_color && black_pawn_files[x] == 0
					mut semi_open_black := color == black_color && white_pawn_files[x] == 0
					if open_file {
						pst_bonus += 25
					} else if semi_open_white && color == white_color {
						pst_bonus += 15
					} else if semi_open_black && color == black_color {
						pst_bonus += 15
					}
				}
				queen {
					pst_bonus = queen_pst[py][x]
					if color == white_color {
						white_has_queen = true
					} else {
						black_has_queen = true
					}
				}
				king {
					if color == white_color {
						white_king_rank = y
					} else {
						black_king_rank = y
					}
					if white_has_queen || black_has_queen {
						pst_bonus = king_pst_middle[py][x]
					} else {
						pst_bonus = king_pst_end[py][x]
					}
				}
				else {}
			}
			value += pst_bonus
			score += if color == black_color { value } else { -value }
		}
	}
	for x := 0; x < 8; x++ {
		if white_pawn_files[x] > 1 {
			score -= 15 * (white_pawn_files[x] - 1)
		}
		if black_pawn_files[x] > 1 {
			score += 15 * (black_pawn_files[x] - 1)
		}
	}
	for x := 0; x < 8; x++ {
		if white_pawn_files[x] > 0 && white_pawn_attacks[x] == 0 {
			score -= 20
		}
		if black_pawn_files[x] > 0 && black_pawn_attacks[x] == 0 {
			score += 20
		}
	}
	if white_bishops >= 2 {
		score += 30
	}
	if black_bishops >= 2 {
		score -= 30
	}
	white_castled := !pos.white_kingside || !pos.white_queenside || pos.white_to_move == false
	black_castled := !pos.black_kingside || !pos.black_queenside || pos.white_to_move == true
	if white_castled {
		score += 30
	}
	if black_castled {
		score -= 30
	}
	if white_castled && black_has_queen {
		score += 25
	}
	if black_castled && white_has_queen {
		score -= 25
	}
	king_safety_bonus := 15
	if white_king_rank <= 1 {
		score += king_safety_bonus
	}
	if black_king_rank >= 6 {
		score -= king_safety_bonus
	}
	white_moves := e.legal_moves_for(pos, white_color).len
	black_moves := e.legal_moves_for(pos, black_color).len
	score += (black_moves - white_moves) * 8
	score += 10
	if e.is_in_check(pos, white_color) {
		score += 40
	}
	if e.is_in_check(pos, black_color) {
		score -= 40
	}
	return score
}

pub fn (e &Engine) legal_moves_for(pos Position, side int) []Move {
	mut legal := []Move{}
	for mv in e.pseudo_moves_for(pos, side) {
		mut next := e.copy_position(pos)
		apply_move(mut next, mv)
		if !e.is_in_check(next, side) {
			legal << mv
		}
	}
	return legal
}

fn (e &Engine) pseudo_moves_for(pos Position, side int) []Move {
	mut moves := []Move{}
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
			piece := pos.board[y][x]
			if piece == 0 || piece_color(piece) != side {
				continue
			}
			match piece_kind(piece) {
				pawn {
					e.add_pawn_moves(pos, side, x, y, mut moves)
				}
				knight {
					e.add_knight_moves(pos, side, x, y, mut moves)
				}
				bishop {
					e.add_sliding_moves(pos, side, x, y, bishop_dirs, mut moves)
				}
				rook {
					e.add_sliding_moves(pos, side, x, y, rook_dirs, mut moves)
				}
				queen {
					e.add_sliding_moves(pos, side, x, y, bishop_dirs, mut moves)
					e.add_sliding_moves(pos, side, x, y, rook_dirs, mut moves)
				}
				king {
					e.add_king_moves(pos, side, x, y, mut moves)
				}
				else {}
			}
		}
	}
	return moves
}

fn (e &Engine) add_pawn_moves(pos Position, side int, x int, y int, mut moves []Move) {
	step := if side == white_color { -1 } else { 1 }
	start_row := if side == white_color { 6 } else { 1 }
	promo_row := if side == white_color { 0 } else { 7 }
	one_y := y + step
	if inside(x, one_y) && pos.board[one_y][x] == 0 {
		e.add_pawn_move_or_promotions(side, x, y, x, one_y, 0, false, mut moves)
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
			e.add_pawn_move_or_promotions(side, x, y, nx, ny, piece_value(piece_kind(target)),
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
		_ = true
	}
}

fn (e &Engine) add_pawn_move_or_promotions(side int, from_x int, from_y int, to_x int, to_y int, score int, is_en_passant bool, mut moves []Move) {
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

fn (e &Engine) add_knight_moves(pos Position, side int, x int, y int, mut moves []Move) {
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

fn (e &Engine) add_sliding_moves(pos Position, side int, x int, y int, dirs [4]Pos, mut moves []Move) {
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

fn (e &Engine) add_king_moves(pos Position, side int, x int, y int, mut moves []Move) {
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
	if e.is_in_check(pos, side) {
		return
	}
	if side == white_color && y == 7 && x == 4 {
		if pos.white_kingside && pos.board[7][5] == 0 && pos.board[7][6] == 0
			&& pos.board[7][7] == rook && !e.square_attacked(pos, 5, 7, black_color)
			&& !e.square_attacked(pos, 6, 7, black_color) {
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
			&& !e.square_attacked(pos, 3, 7, black_color)
			&& !e.square_attacked(pos, 2, 7, black_color) {
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
			&& pos.board[0][7] == -rook && !e.square_attacked(pos, 5, 0, white_color)
			&& !e.square_attacked(pos, 6, 0, white_color) {
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
			&& !e.square_attacked(pos, 3, 0, white_color)
			&& !e.square_attacked(pos, 2, 0, white_color) {
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

pub fn apply_move(mut pos Position, mv Move) {
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

pub fn (e &Engine) is_in_check(pos Position, side int) bool {
	kx, ky := e.find_king(pos, side)
	if kx == no_square {
		return true
	}
	return e.square_attacked(pos, kx, ky, -side)
}

fn (e &Engine) find_king(pos Position, side int) (int, int) {
	target := side * king
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
			if pos.board[y][x] == target {
				return x, y
			}
		}
	}
	return no_square, no_square
}

fn (e &Engine) square_attacked(pos Position, x int, y int, attacker int) bool {
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

pub fn (mut e Engine) record_position(pos Position) {
	key := e.position_key(pos)
	e.position_counts[key]++
}

pub fn (e &Engine) position_key(pos Position) string {
	mut key := ''
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
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

fn (e &Engine) copy_position(pos Position) Position {
	mut next := Position{}
	next = pos
	return next
}

pub fn (e &Engine) is_game_over(pos Position) (bool, string) {
	side := if pos.white_to_move { white_color } else { black_color }
	if pos.halfmove_clock >= 100 {
		return true, 'Draw by fifty-move rule.'
	}
	if e.position_counts[e.position_key(pos)] >= 3 {
		return true, 'Draw by threefold repetition.'
	}
	if is_insufficient_material(pos) {
		return true, 'Draw by insufficient material.'
	}
	legal_moves := e.legal_moves_for(pos, side)
	in_check := e.is_in_check(pos, side)
	if legal_moves.len == 0 {
		if in_check {
			return true, if side == white_color {
				'Checkmate. Black wins.'
			} else {
				'Checkmate. White wins.'
			}
		}
		return true, 'Stalemate.'
	}
	return false, ''
}

pub fn is_insufficient_material(pos Position) bool {
	mut bishops := []Pos{}
	mut knights := 0
	mut other_material := false
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
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
