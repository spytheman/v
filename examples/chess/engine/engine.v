module engine

import time

const ai_time_limit_ms = 2000
const tt_bound_exact = 0
const tt_bound_lower = 1
const tt_bound_upper = 2
const opening_phase_plies = 8
const root_sanity_candidate_count = 4
pub const tactical_time_bonus_percent = 50

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
		white_to_move:   true
		white_kingside:  true
		white_queenside: true
		black_kingside:  true
		black_queenside: true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 1
	}
}

pub fn (mut e Engine) search_best_move(pos Position, side int) Move {
	return e.search_best_move_with_time(pos, side, ai_time_limit_ms)
}

pub fn (mut e Engine) search_best_move_with_time(pos Position, side int, time_limit_ms int) Move {
	shared control := SearchControl{}
	return e.search_best_move_with_control(pos, side, time_limit_ms, shared control)
}

pub fn (mut e Engine) search_best_move_with_control(pos Position, side int, time_limit_ms int, shared control SearchControl) Move {
	e.killer_moves = [2][64]int{}
	e.history = [2][64][64]int{}
	mut best_score := worst_score_for(side)
	mut best_move := Move{}
	window := 50
	start_time := time.ticks()
	legal_moves := e.legal_moves_for(pos, side)
	if legal_moves.len == 0 {
		return Move{}
	}
	if book_move := opening_book_move(pos, side, legal_moves) {
		return book_move
	}
	root_key := e.position_key(pos)
	mut tt_root_move := Move{}
	if root_key in e.transposition_table {
		tt_root_move = e.transposition_table[root_key].best_move
	}
	for current_depth := 1; current_depth <= search_depth; current_depth++ {
		if should_stop_search(start_time, time_limit_ms, shared control) {
			break
		}
		mut alpha := -checkmate_score
		mut beta := checkmate_score
		if current_depth > 1 {
			alpha = clamp_score(best_score - window)
			beta = clamp_score(best_score + window)
		}
		priority_move := if best_move != Move{} { best_move } else { tt_root_move }
		mut depth_best_score := worst_score_for(side)
		mut depth_best_move := Move{}
		mut completed_depth := false
		for {
			depth_best_score, depth_best_move, completed_depth = e.search_root_depth(pos,
				legal_moves, side, current_depth, alpha, beta, start_time, time_limit_ms, shared
				control, priority_move)
			if !completed_depth || depth_best_move == Move{} {
				break
			}
			if current_depth == 1
				|| (depth_best_score > alpha && depth_best_score < beta)
				|| (alpha == -checkmate_score && beta == checkmate_score) {
				break
			}
			alpha = -checkmate_score
			beta = checkmate_score
		}
		if !completed_depth || depth_best_move == Move{} {
			break
		}
		best_score = depth_best_score
		best_move = depth_best_move
	}
	if best_move == Move{} {
		best_move = legal_moves[0]
	}
	best_move = e.sanity_filter_root_move(pos, side, best_move, legal_moves, start_time,
		time_limit_ms, shared control)
	return best_move
}

fn (mut e Engine) search_root_depth(pos Position, legal_moves []engine.Move, side int, depth int, alpha0 int, beta0 int, start_time i64, time_limit_ms int, shared control SearchControl, priority_move Move) (int, Move, bool) {
	mut alpha := alpha0
	mut beta := beta0
	mut best_score := worst_score_for(side)
	mut best_move := Move{}
	in_check := e.is_in_check(pos, side)
	king_exposed := e.is_king_exposed(pos, side)
	mut ordered_root := e.order_moves(legal_moves, pos, side, 0)
	ordered_root = prioritize_move(ordered_root, priority_move)
	for i, mv in ordered_root {
		if should_stop_search(start_time, time_limit_ms, shared control) {
			return best_score, best_move, false
		}
		mut next := e.copy_position(pos)
		apply_move(mut next, mv)
		next_side := other_side(side)
		mut score := 0
		if i == 0 || depth <= 1 || in_check || king_exposed {
			score = e.search(next, next_side, depth - 1, alpha, beta, 0, start_time, time_limit_ms, shared
				control)
		} else if side == black_color {
			score = e.search(next, next_side, depth - 1, alpha, alpha + 1, 0, start_time,
				time_limit_ms, shared control)
			if !should_stop_search(start_time, time_limit_ms, shared control) && score > alpha
				&& score < beta {
				score = e.search(next, next_side, depth - 1, alpha, beta, 0, start_time,
					time_limit_ms, shared control)
			}
		} else {
			score = e.search(next, next_side, depth - 1, beta - 1, beta, 0, start_time,
				time_limit_ms, shared control)
			if !should_stop_search(start_time, time_limit_ms, shared control) && score < beta
				&& score > alpha {
				score = e.search(next, next_side, depth - 1, alpha, beta, 0, start_time,
					time_limit_ms, shared control)
			}
		}
		if should_stop_search(start_time, time_limit_ms, shared control) {
			return best_score, best_move, false
		}
		if best_move == Move{} || is_better_root_score(score, best_score, side) {
			best_score = score
			best_move = mv
		}
		if side == black_color {
			if score > alpha {
				alpha = score
			}
		} else {
			if score < beta {
				beta = score
			}
		}
		if alpha >= beta {
			break
		}
	}
	return best_score, best_move, true
}

fn is_better_root_score(score int, best_score int, side int) bool {
	return if side == black_color { score > best_score } else { score < best_score }
}

fn worst_score_for(side int) int {
	return if side == black_color { -checkmate_score } else { checkmate_score }
}

fn other_side(side int) int {
	return -side
}

fn clamp_score(score int) int {
	if score < -checkmate_score {
		return -checkmate_score
	}
	if score > checkmate_score {
		return checkmate_score
	}
	return score
}

fn square_index(x int, y int) int {
	return y * board_cells + x
}

fn move_order_key(mv Move) int {
	from_sq := square_index(mv.from_x, mv.from_y)
	to_sq := square_index(mv.to_x, mv.to_y)
	return 1 + from_sq * 64 + to_sq + mv.promotion * 4096
}

fn same_move(a Move, b Move) bool {
	return a.from_x == b.from_x && a.from_y == b.from_y && a.to_x == b.to_x && a.to_y == b.to_y
		&& a.promotion == b.promotion
}

fn prioritize_move(moves []engine.Move, priority Move) []engine.Move {
	if priority == Move{} {
		return moves
	}
	mut ordered := moves.clone()
	for i, mv in ordered {
		if same_move(mv, priority) {
			ordered[0], ordered[i] = ordered[i], ordered[0]
			break
		}
	}
	return ordered
}

fn side_index(side int) int {
	return if side == black_color { 1 } else { 0 }
}

fn is_capture_move(pos Position, mv Move) bool {
	return mv.is_en_passant || pos.board[mv.to_y][mv.to_x] != 0
}

fn is_tactical_move(pos Position, mv Move) bool {
	return is_capture_move(pos, mv) || mv.promotion != 0
}

fn is_quiet_move(pos Position, mv Move) bool {
	return !is_tactical_move(pos, mv)
}

fn (e &Engine) is_quiet_opening_queen_move(pos Position, mv Move, side int) bool {
	if opening_ply(pos) >= opening_phase_plies {
		return false
	}
	piece := pos.board[mv.from_y][mv.from_x]
	return piece_color(piece) == side && piece_kind(piece) == queen && is_quiet_move(pos, mv)
		&& !e.move_gives_check(pos, mv, side)
}

fn tactical_order_score(pos Position, mv Move) int {
	attacker := piece_value(piece_kind(pos.board[mv.from_y][mv.from_x]))
	victim := if mv.is_en_passant {
		piece_value(pawn)
	} else if pos.board[mv.to_y][mv.to_x] != 0 {
		piece_value(piece_kind(pos.board[mv.to_y][mv.to_x]))
	} else {
		0
	}
	promotion_bonus := if mv.promotion != 0 { piece_value(mv.promotion) + 50 } else { 0 }
	return victim * 16 - attacker + promotion_bonus
}

fn tt_bound_for(score int, alpha_orig int, beta_orig int) int {
	if score <= alpha_orig {
		return tt_bound_upper
	}
	if score >= beta_orig {
		return tt_bound_lower
	}
	return tt_bound_exact
}

fn (mut e Engine) store_tt_entry(key string, depth int, score int, bound int, best_move Move) {
	if key !in e.transposition_table && e.transposition_table.len >= tt_max_entries {
		e.transposition_table = map[string]TTEntry{}
	}
	e.transposition_table[key] = TTEntry{
		depth:     depth
		score:     score
		bound:     bound
		best_move: best_move
	}
}

fn (mut e Engine) search(pos Position, side int, depth int, alpha0 int, beta0 int, ply int, start_time i64, time_limit_ms int, shared control SearchControl) int {
	if should_stop_search(start_time, time_limit_ms, shared control) {
		return e.evaluate(pos, 0, side)
	}
	if pos.halfmove_clock >= 100 || is_insufficient_material(pos) {
		return 0
	}
	mut alpha := alpha0
	mut beta := beta0
	remaining_depth, king_exposed := e.search_depth_with_extensions(pos, side, depth, ply)
	alpha_orig := alpha0
	beta_orig := beta0
	tt_key := e.position_key(pos)
	mut tt_best_move := Move{}
	if tt_key in e.transposition_table {
		entry := e.transposition_table[tt_key]
		tt_best_move = entry.best_move
		if entry.depth >= remaining_depth {
			match entry.bound {
				tt_bound_exact {
					return entry.score
				}
				tt_bound_lower {
					if entry.score > alpha {
						alpha = entry.score
					}
				}
				tt_bound_upper {
					if entry.score < beta {
						beta = entry.score
					}
				}
				else {}
			}
			if alpha >= beta {
				return entry.score
			}
		}
	}
	moves := e.legal_moves_for(pos, side)
	if moves.len == 0 {
		if e.is_in_check(pos, side) {
			score := if side == black_color {
				-checkmate_score - remaining_depth
			} else {
				checkmate_score + remaining_depth
			}
			e.store_tt_entry(tt_key, remaining_depth, score, tt_bound_exact, Move{})
			return score
		}
		e.store_tt_entry(tt_key, remaining_depth, 0, tt_bound_exact, Move{})
		return 0
	}
	if remaining_depth == 0 {
		return e.quiescence(pos, alpha, beta, side, 0, start_time, time_limit_ms, shared control)
	}
	in_check := e.is_in_check(pos, side)
	mut ordered := e.order_moves(moves, pos, side, ply)
	ordered = prioritize_move(ordered, tt_best_move)
	if side == black_color {
		mut best := -checkmate_score
		mut best_move := Move{}
		mut completed := true
		for i, mv in ordered {
			if should_stop_search(start_time, time_limit_ms, shared control) {
				completed = false
				break
			}
			mut next := e.copy_position(pos)
			apply_move(mut next, mv)
			mut score := 0
			if i == 0 || remaining_depth <= 1 || in_check || king_exposed {
				score = e.search(next, white_color, remaining_depth - 1, alpha, beta, ply + 1,
					start_time, time_limit_ms, shared control)
			} else {
				score = e.search(next, white_color, remaining_depth - 1, alpha, alpha + 1, ply + 1,
					start_time, time_limit_ms, shared control)
				if !should_stop_search(start_time, time_limit_ms, shared control) && score > alpha
					&& score < beta {
					score = e.search(next, white_color, remaining_depth - 1, alpha, beta, ply + 1,
						start_time, time_limit_ms, shared control)
				}
			}
			if should_stop_search(start_time, time_limit_ms, shared control) {
				completed = false
				break
			}
			if score > best {
				best = score
				best_move = mv
			}
			if best > alpha {
				alpha = best
			}
			if alpha >= beta {
				if is_quiet_move(pos, mv) {
					from_sq := square_index(mv.from_x, mv.from_y)
					to_sq := square_index(mv.to_x, mv.to_y)
					e.killer_moves[1][ply] = move_order_key(mv)
					e.history[1][from_sq][to_sq] += depth * depth
				}
				break
			}
		}
		if best == -checkmate_score {
			score := e.evaluate(pos, 0, side)
			if completed {
				e.store_tt_entry(tt_key, remaining_depth, score, tt_bound_exact, Move{})
			}
			return score
		}
		if completed {
			e.store_tt_entry(tt_key, remaining_depth, best, tt_bound_for(best, alpha_orig,
				beta_orig), best_move)
		}
		return best
	}
	mut best := checkmate_score
	mut best_move := Move{}
	mut completed := true
	for i, mv in ordered {
		if should_stop_search(start_time, time_limit_ms, shared control) {
			completed = false
			break
		}
		mut next := e.copy_position(pos)
		apply_move(mut next, mv)
		mut score := 0
		if i == 0 || remaining_depth <= 1 || in_check || king_exposed {
			score = e.search(next, black_color, remaining_depth - 1, alpha, beta, ply + 1,
				start_time, time_limit_ms, shared control)
		} else {
			score = e.search(next, black_color, remaining_depth - 1, beta - 1, beta, ply + 1,
				start_time, time_limit_ms, shared control)
			if !should_stop_search(start_time, time_limit_ms, shared control) && score < beta
				&& score > alpha {
				score = e.search(next, black_color, remaining_depth - 1, alpha, beta, ply + 1,
					start_time, time_limit_ms, shared control)
			}
		}
		if should_stop_search(start_time, time_limit_ms, shared control) {
			completed = false
			break
		}
		if score < best {
			best = score
			best_move = mv
		}
		if best < beta {
			beta = best
		}
		if alpha >= beta {
			if is_quiet_move(pos, mv) {
				from_sq := square_index(mv.from_x, mv.from_y)
				to_sq := square_index(mv.to_x, mv.to_y)
				e.killer_moves[0][ply] = move_order_key(mv)
				e.history[0][from_sq][to_sq] += depth * depth
			}
			break
		}
	}
	if best == checkmate_score {
		score := e.evaluate(pos, 0, side)
		if completed {
			e.store_tt_entry(tt_key, remaining_depth, score, tt_bound_exact, Move{})
		}
		return score
	}
	if completed {
		e.store_tt_entry(tt_key, remaining_depth, best, tt_bound_for(best, alpha_orig, beta_orig),
			best_move)
	}
	return best
}

fn (e &Engine) search_depth_with_extensions(pos Position, side int, depth int, ply int) (int, bool) {
	mut remaining_depth := depth
	if remaining_depth > 0 && remaining_depth <= 2 && e.is_in_check(pos, side) {
		remaining_depth++
	}
	king_exposed := e.is_king_exposed(pos, side)
	if remaining_depth > 0 && remaining_depth <= 2 && king_exposed && ply == 0 {
		remaining_depth++
	}
	return remaining_depth, king_exposed
}

fn (e &Engine) quiescence(pos Position, alpha_ int, beta_ int, side int, depth int, start_time i64, time_limit_ms int, shared control SearchControl) int {
	if should_stop_search(start_time, time_limit_ms, shared control) {
		return e.evaluate(pos, 0, side)
	}
	if depth >= quiescence_depth {
		return e.evaluate(pos, 0, side)
	}
	mut alpha := alpha_
	mut beta := beta_
	in_check := e.is_in_check(pos, side)
	mut stand_pat := 0
	mut moves := []Move{}
	if in_check {
		moves = e.order_moves(e.legal_moves_for(pos, side), pos, side, 0)
		if moves.len == 0 {
			return if side == black_color {
				-checkmate_score - depth
			} else {
				checkmate_score + depth
			}
		}
	} else {
		stand_pat = e.evaluate(pos, 0, side)
		moves = e.legal_moves_for(pos, side).filter(is_tactical_move(pos, it))
		if moves.len == 0 {
			return stand_pat
		}
		e.sort_captures(mut moves, pos)
	}
	if side == black_color {
		if !in_check && stand_pat > alpha {
			alpha = stand_pat
		}
		if !in_check && alpha >= beta {
			return beta
		}
		mut best := -checkmate_score
		for mv in moves {
			if should_stop_search(start_time, time_limit_ms, shared control) {
				break
			}
			mut next := e.copy_position(pos)
			apply_move(mut next, mv)
			score := e.quiescence(next, alpha, beta, white_color, depth + 1, start_time,
				time_limit_ms, shared control)
			if should_stop_search(start_time, time_limit_ms, shared control) {
				break
			}
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
		if best == -checkmate_score {
			return stand_pat
		}
		return best
	}
	if !in_check && stand_pat < beta {
		beta = stand_pat
	}
	if !in_check && alpha >= beta {
		return alpha
	}
	mut best := checkmate_score
	for mv in moves {
		if should_stop_search(start_time, time_limit_ms, shared control) {
			break
		}
		mut next := e.copy_position(pos)
		apply_move(mut next, mv)
		score := e.quiescence(next, alpha, beta, black_color, depth + 1, start_time, time_limit_ms, shared
			control)
		if should_stop_search(start_time, time_limit_ms, shared control) {
			break
		}
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
	if best == checkmate_score {
		return stand_pat
	}
	return best
}

fn should_stop_search(start_time i64, time_limit_ms int, shared control SearchControl) bool {
	if time_limit_ms >= 0 && time.ticks() - start_time > time_limit_ms {
		return true
	}
	return rlock control {
		control.stop
	}
}

fn (e &Engine) order_moves(moves []engine.Move, pos Position, side int, ply int) []engine.Move {
	in_check := e.is_in_check(pos, side)
	mut scored := moves.map(fn [e, pos, side, ply, in_check] (mv Move) int {
		mut s := 0
		if is_tactical_move(pos, mv) {
			s += 10000 + tactical_order_score(pos, mv)
		}
		sidx := side_index(side)
		from_sq := square_index(mv.from_x, mv.from_y)
		to_sq := square_index(mv.to_x, mv.to_y)
		if e.killer_moves[sidx][ply] == move_order_key(mv) {
			s += 900
		}
		s += e.history[sidx][from_sq][to_sq]
		if mv.is_castle {
			s += 120
		}
		if in_check {
			s += 50
		}
		if opening_ply(pos) < opening_phase_plies {
			s += e.opening_move_order_score(pos, mv, side)
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

fn (e &Engine) sort_captures(mut moves []engine.Move, pos Position) {
	moves.sort_with_compare(fn [pos] (a &Move, b &Move) int {
		a_score := tactical_order_score(pos, *a)
		b_score := tactical_order_score(pos, *b)
		return if a_score > b_score {
			-1
		} else if a_score < b_score {
			1
		} else {
			0
		}
	})
}

fn opening_ply(pos Position) int {
	return (pos.fullmove_number - 1) * 2 + if pos.white_to_move {
		0
	} else {
		1
	}
}

fn (e &Engine) opening_move_order_score(pos Position, mv Move, side int) int {
	piece := pos.board[mv.from_y][mv.from_x]
	kind := piece_kind(piece)
	tactical_reason := is_tactical_move(pos, mv) || e.move_gives_check(pos, mv, side)
	mut score := 0
	if mv.is_castle {
		score += 260
	}
	if is_developing_minor_from_home(mv, side, kind) {
		score += 90
	}
	if is_center_pawn_advance(mv, side, kind) {
		score += 65
	}
	if kind == queen && !tactical_reason {
		score -= 220
	}
	if is_repeated_opening_piece_move(mv, side, kind) && !tactical_reason {
		score -= 140
	}
	if is_startpos_after_1_e4(pos, side) {
		if mv.from_x == 1 && mv.from_y == 0 && mv.to_x == 2 && mv.to_y == 2 {
			score -= 260
		}
		if mv.from_x == 4 && mv.from_y == 1 && mv.to_x == 4 && mv.to_y == 3 {
			score += 180
		}
		if mv.from_x == 2 && mv.from_y == 1 && mv.to_x == 2 && mv.to_y == 3 {
			score += 130
		}
		if mv.from_x == 4 && mv.from_y == 1 && mv.to_x == 4 && mv.to_y == 2 {
			score += 105
		}
		if mv.from_x == 2 && mv.from_y == 1 && mv.to_x == 2 && mv.to_y == 2 {
			score += 95
		}
		if mv.from_x == 6 && mv.from_y == 0 && mv.to_x == 5 && mv.to_y == 2 {
			score += 85
		}
	}
	return score
}

fn (e &Engine) move_gives_check(pos Position, mv Move, side int) bool {
	mut next := e.copy_position(pos)
	apply_move(mut next, mv)
	return e.is_in_check(next, -side)
}

fn is_developing_minor_from_home(mv Move, side int, kind int) bool {
	if kind != knight && kind != bishop {
		return false
	}
	home_rank := if side == white_color { 7 } else { 0 }
	return mv.from_y == home_rank
}

fn is_center_pawn_advance(mv Move, side int, kind int) bool {
	if kind != pawn || mv.from_x !in [2, 3, 4] {
		return false
	}
	start_row := if side == white_color { 6 } else { 1 }
	return mv.from_y == start_row && iabs(mv.to_y - mv.from_y) <= 2
}

fn is_repeated_opening_piece_move(mv Move, side int, kind int) bool {
	if kind == pawn || kind == king {
		return false
	}
	home_rank := if side == white_color { 7 } else { 0 }
	return mv.from_y != home_rank
}

fn is_startpos_after_1_e4(pos Position, side int) bool {
	if side != black_color || pos.white_to_move || pos.fullmove_number != 1
		|| pos.halfmove_clock != 0 || !pos.white_kingside || !pos.white_queenside
		|| !pos.black_kingside || !pos.black_queenside {
		return false
	}
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
			if pos.board[y][x] != expected_piece_after_1_e4(x, y) {
				return false
			}
		}
	}
	return true
}

fn expected_piece_after_1_e4(x int, y int) int {
	return match y {
		0 {
			match x {
				0 { -rook }
				1 { -knight }
				2 { -bishop }
				3 { -queen }
				4 { -king }
				5 { -bishop }
				6 { -knight }
				7 { -rook }
				else { 0 }
			}
		}
		1 {
			-pawn
		}
		4 {
			if x == 4 {
				pawn
			} else {
				0
			}
		}
		6 {
			if x == 4 {
				0
			} else {
				pawn
			}
		}
		7 {
			match x {
				0 { rook }
				1 { knight }
				2 { bishop }
				3 { queen }
				4 { king }
				5 { bishop }
				6 { knight }
				7 { rook }
				else { 0 }
			}
		}
		else {
			0
		}
	}
}

fn opening_book_move(pos Position, side int, legal_moves []engine.Move) ?Move {
	if is_startpos(pos, side) {
		if mv := find_uci_move(legal_moves, 'e2e4') {
			return mv
		}
	}
	if is_startpos_after_1_e4(pos, side) {
		if mv := find_uci_move(legal_moves, 'e7e5') {
			return mv
		}
	}
	for line in white_opening_book_lines(pos, side) {
		if mv := find_uci_move(legal_moves, line) {
			return mv
		}
	}
	return none
}

fn is_startpos(pos Position, side int) bool {
	if side != white_color || !pos.white_to_move || pos.fullmove_number != 1
		|| pos.halfmove_clock != 0 || !pos.white_kingside || !pos.white_queenside
		|| !pos.black_kingside || !pos.black_queenside {
		return false
	}
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
			if pos.board[y][x] != initial_piece_at(x, y) {
				return false
			}
		}
	}
	return true
}

fn initial_piece_at(x int, y int) int {
	return match y {
		0 {
			expected_piece_after_1_e4(x, y)
		}
		1 {
			-pawn
		}
		6 {
			pawn
		}
		7 {
			expected_piece_after_1_e4(x, y)
		}
		else {
			0
		}
	}
}

fn white_opening_book_lines(pos Position, side int) []string {
	if side != white_color || !pos.white_to_move || opening_ply(pos) >= opening_phase_plies {
		return []
	}
	if moves_match_position(pos, ['e2e4', 'e7e5']) {
		return ['g1f3']
	}
	if moves_match_position(pos, ['e2e4', 'c7c5']) {
		return ['g1f3']
	}
	if moves_match_position(pos, ['e2e4', 'e7e6']) {
		return ['d2d4']
	}
	if moves_match_position(pos, ['e2e4', 'c7c6']) {
		return ['d2d4']
	}
	if moves_match_position(pos, ['e2e4', 'g8f6']) {
		return ['e4e5']
	}
	return []
}

fn moves_match_position(pos Position, ucis []string) bool {
	mut e := Engine{}
	mut replay := e.new_position()
	for uci in ucis {
		mv := find_legal_uci_move(e, replay, uci) or { return false }
		apply_move(mut replay, mv)
	}
	return same_position_for_book(pos, replay)
}

fn find_legal_uci_move(e Engine, pos Position, uci string) ?Move {
	side := if pos.white_to_move { white_color } else { black_color }
	for mv in e.legal_moves_for(pos, side) {
		if move_to_uci(mv) == uci {
			return mv
		}
	}
	return none
}

fn same_position_for_book(a Position, b Position) bool {
	if a.white_to_move != b.white_to_move || a.fullmove_number != b.fullmove_number
		|| a.halfmove_clock != b.halfmove_clock || a.white_kingside != b.white_kingside
		|| a.white_queenside != b.white_queenside || a.black_kingside != b.black_kingside
		|| a.black_queenside != b.black_queenside {
		return false
	}
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
			if a.board[y][x] != b.board[y][x] {
				return false
			}
		}
	}
	return true
}

fn find_uci_move(moves []engine.Move, uci string) ?Move {
	for mv in moves {
		if move_to_uci(mv) == uci {
			return mv
		}
	}
	return none
}

fn (mut e Engine) sanity_filter_root_move(pos Position, side int, best_move Move, legal_moves []engine.Move, start_time i64, time_limit_ms int, shared control SearchControl) Move {
	if should_stop_search(start_time, time_limit_ms, shared control) {
		return best_move
	}
	if best_move == Move{} || !e.is_catastrophic_root_move(pos, side, best_move) {
		return best_move
	}
	ordered := e.order_moves(legal_moves, pos, side, 0)
	limit := min_int(root_sanity_candidate_count, ordered.len)
	for i := 0; i < limit; i++ {
		if should_stop_search(start_time, time_limit_ms, shared control) {
			break
		}
		mv := ordered[i]
		if same_move(mv, best_move) {
			continue
		}
		if !e.is_catastrophic_root_move(pos, side, mv) {
			return mv
		}
	}
	return best_move
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

fn (mut e Engine) is_catastrophic_root_move(pos Position, side int, mv Move) bool {
	captured_value := captured_material_value(pos, mv)
	mut next := e.copy_position(pos)
	apply_move(mut next, mv)
	if e.allows_immediate_mate(next, side) {
		return true
	}
	if e.hangs_piece_to_one_move_tactic(next, side, mv, captured_value) {
		return true
	}
	if e.allows_forcing_check_sequence(next, side) {
		return true
	}
	if e.is_quiet_opening_queen_move(pos, mv, side)
		&& e.queen_can_be_harassed_by_development(next, side, mv) {
		return true
	}
	return e.tactical_verification_fails(pos, side, mv)
}

fn (e &Engine) allows_immediate_mate(pos Position, side int) bool {
	opponent := -side
	for reply in e.legal_moves_for(pos, opponent) {
		mut after_reply := e.copy_position(pos)
		apply_move(mut after_reply, reply)
		if e.is_in_check(after_reply, side) && e.legal_moves_for(after_reply, side).len == 0 {
			return true
		}
	}
	return false
}

fn (e &Engine) hangs_piece_to_one_move_tactic(pos Position, side int, mv Move, captured_value int) bool {
	moved_piece := pos.board[mv.to_y][mv.to_x]
	if piece_color(moved_piece) != side {
		return false
	}
	moved_kind := piece_kind(moved_piece)
	if moved_kind != queen && moved_kind != rook && moved_kind != bishop && moved_kind != knight {
		return false
	}
	moved_value := piece_value(moved_kind)
	if captured_value >= moved_value {
		return false
	}
	for reply in e.legal_moves_for(pos, -side) {
		if reply.to_x != mv.to_x || reply.to_y != mv.to_y {
			continue
		}
		attacker_value := piece_value(piece_kind(pos.board[reply.from_y][reply.from_x]))
		if moved_value - attacker_value >= piece_value(pawn) {
			return true
		}
	}
	return false
}

fn (mut e Engine) tactical_verification_fails(pos Position, side int, mv Move) bool {
	if !e.is_sharp_position(pos, side) && !is_tactical_move(pos, mv)
		&& !e.move_gives_check(pos, mv, side) {
		return false
	}
	mut next := e.copy_position(pos)
	apply_move(mut next, mv)
	opponent := -side
	opponent_moves := e.legal_moves_for(next, opponent)
	for reply in opponent_moves {
		reply_gives_check := e.move_gives_check(next, reply, opponent)
		if !is_tactical_move(next, reply) && !reply_gives_check {
			continue
		}
		mut after_reply := e.copy_position(next)
		apply_move(mut after_reply, reply)
		if e.is_in_check(after_reply, side) && e.legal_moves_for(after_reply, side).len == 0 {
			return true
		}
		if reply.to_x == mv.to_x && reply.to_y == mv.to_y
			&& tactical_order_score(next, reply) >= piece_value(bishop) * 16 - piece_value(pawn)
			&& !e.has_recapture(after_reply, side, reply.to_x, reply.to_y) {
			return true
		}
	}
	return false
}

fn (e &Engine) has_recapture(pos Position, side int, x int, y int) bool {
	for mv in e.legal_moves_for(pos, side) {
		if mv.to_x == x && mv.to_y == y {
			return true
		}
	}
	return false
}

fn (e &Engine) allows_forcing_check_sequence(pos Position, side int) bool {
	if !e.is_king_exposed(pos, side) {
		return false
	}
	opponent := -side
	for reply in e.legal_moves_for(pos, opponent) {
		if !e.move_gives_check(pos, reply, opponent) {
			continue
		}
		mut after_reply := e.copy_position(pos)
		apply_move(mut after_reply, reply)
		if e.legal_moves_for(after_reply, side).len <= 1 {
			return true
		}
		if e.check_reply_wins_decisive_material(after_reply, side) {
			return true
		}
	}
	return false
}

fn (e &Engine) check_reply_wins_decisive_material(pos Position, side int) bool {
	opponent := -side
	for reply in e.legal_moves_for(pos, side) {
		mut after_reply := e.copy_position(pos)
		apply_move(mut after_reply, reply)
		if e.is_in_check(after_reply, side) {
			continue
		}
		if !e.has_decisive_capture(after_reply, opponent) {
			return false
		}
	}
	return true
}

fn (e &Engine) has_decisive_capture(pos Position, side int) bool {
	for mv in e.legal_moves_for(pos, side) {
		if is_capture_move(pos, mv) && captured_material_value(pos, mv) >= piece_value(rook) {
			return true
		}
	}
	return false
}

fn (e &Engine) queen_can_be_harassed_by_development(pos Position, side int, mv Move) bool {
	moved_piece := pos.board[mv.to_y][mv.to_x]
	if piece_color(moved_piece) != side || piece_kind(moved_piece) != queen {
		return false
	}
	if e.square_attacked(pos, mv.to_x, mv.to_y, -side) {
		return true
	}
	for reply in e.legal_moves_for(pos, -side) {
		piece := pos.board[reply.from_y][reply.from_x]
		kind := piece_kind(piece)
		if !is_developing_minor_from_home(reply, -side, kind) {
			continue
		}
		mut after_reply := e.copy_position(pos)
		apply_move(mut after_reply, reply)
		if e.square_attacked(after_reply, mv.to_x, mv.to_y, -side) {
			return true
		}
	}
	return false
}

// is_tactical_position reports whether the side should spend extra time on forcing play.
pub fn (e &Engine) is_tactical_position(pos Position, side int) bool {
	return e.is_in_check(pos, side) || e.is_king_exposed(pos, side)
		|| e.has_sharp_forcing_move(pos, side) || e.has_sharp_forcing_move(pos, -side)
}

// time_budget_with_tactical_bonus returns budget with extra time for tactical positions.
pub fn (e &Engine) time_budget_with_tactical_bonus(pos Position, side int, budget int) int {
	if e.is_tactical_position(pos, side) {
		return budget + budget * tactical_time_bonus_percent / 100
	}
	return budget
}

fn (e &Engine) is_sharp_position(pos Position, side int) bool {
	return e.is_tactical_position(pos, side)
}

fn (e &Engine) has_sharp_forcing_move(pos Position, side int) bool {
	for mv in e.legal_moves_for(pos, side) {
		if e.move_gives_check(pos, mv, side) || mv.promotion != 0 {
			return true
		}
		if e.is_significant_capture(pos, mv) {
			return true
		}
	}
	return false
}

fn (e &Engine) is_significant_capture(pos Position, mv Move) bool {
	if !is_capture_move(pos, mv) {
		return false
	}
	attacker_value := piece_value(piece_kind(pos.board[mv.from_y][mv.from_x]))
	victim_value := captured_material_value(pos, mv)
	return victim_value >= piece_value(rook) || victim_value - attacker_value >= piece_value(pawn)
}

fn (e &Engine) is_king_exposed(pos Position, side int) bool {
	kx, ky := e.find_king(pos, side)
	if kx == no_square {
		return true
	}
	if e.is_in_check(pos, side) {
		return true
	}
	if e.is_low_material_endgame(pos) {
		return false
	}
	castled := if side == white_color {
		(pos.board[7][6] == king || pos.board[7][2] == king)
	} else {
		(pos.board[0][6] == -king || pos.board[0][2] == -king)
	}
	mut danger := 0
	if !castled && opening_ply(pos) >= opening_phase_plies {
		danger++
	}
	if e.king_pawn_shield_count(pos, side, kx, ky) <= 1 {
		danger++
	}
	if e.king_adjacent_attacks(pos, side, kx, ky) >= 2 {
		danger++
	}
	if e.open_line_to_king(pos, side, kx, ky) {
		danger++
	}
	return danger >= 2
}

fn (e &Engine) is_low_material_endgame(pos Position) bool {
	mut queens := 0
	mut non_pawn_material := 0
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
			kind := piece_kind(pos.board[y][x])
			if kind == queen {
				queens++
			}
			if kind != 0 && kind != king && kind != pawn {
				non_pawn_material += piece_value(kind)
			}
		}
	}
	return queens == 0 && non_pawn_material <= piece_value(rook) * 2
}

fn (e &Engine) king_pawn_shield_count(pos Position, side int, kx int, ky int) int {
	shield_y := ky + if side == white_color { -1 } else { 1 }
	if shield_y < 0 || shield_y >= board_cells {
		return 0
	}
	mut count := 0
	for dx := -1; dx <= 1; dx++ {
		x := kx + dx
		if inside(x, shield_y) && pos.board[shield_y][x] == side * pawn {
			count++
		}
	}
	return count
}

fn (e &Engine) king_adjacent_attacks(pos Position, side int, kx int, ky int) int {
	mut attacks := 0
	for offset in king_offsets {
		x := kx + offset.x
		y := ky + offset.y
		if inside(x, y) && e.square_attacked(pos, x, y, -side) {
			attacks++
		}
	}
	return attacks
}

fn (e &Engine) open_line_to_king(pos Position, side int, kx int, ky int) bool {
	for dir in rook_dirs {
		mut nx := kx + dir.x
		mut ny := ky + dir.y
		mut blockers := 0
		for inside(nx, ny) {
			piece := pos.board[ny][nx]
			if piece != 0 {
				if piece_color(piece) == side {
					blockers++
					if blockers > 1 {
						break
					}
				} else if blockers == 0 && (piece_kind(piece) == rook || piece_kind(piece) == queen) {
					return true
				} else {
					break
				}
			}
			nx += dir.x
			ny += dir.y
		}
	}
	for dir in bishop_dirs {
		mut nx := kx + dir.x
		mut ny := ky + dir.y
		mut blockers := 0
		for inside(nx, ny) {
			piece := pos.board[ny][nx]
			if piece != 0 {
				if piece_color(piece) == side {
					blockers++
					if blockers > 1 {
						break
					}
				} else if blockers == 0
					&& (piece_kind(piece) == bishop || piece_kind(piece) == queen) {
					return true
				} else {
					break
				}
			}
			nx += dir.x
			ny += dir.y
		}
	}
	return false
}

fn captured_material_value(pos Position, mv Move) int {
	if mv.is_en_passant {
		return piece_value(pawn)
	}
	return piece_value(piece_kind(pos.board[mv.to_y][mv.to_x]))
}

fn perspective_rank(y int, side int) int {
	return if side == white_color { 7 - y } else { y }
}

fn feature_score(side int, value int) int {
	return if side == black_color { value } else { -value }
}

fn is_passed_pawn(pos Position, side int, x int, y int) bool {
	for dx := -1; dx <= 1; dx++ {
		nx := x + dx
		if nx < 0 || nx >= board_cells {
			continue
		}
		if side == white_color {
			for ey := y - 1; ey >= 0; ey-- {
				if pos.board[ey][nx] == -pawn {
					return false
				}
			}
		} else {
			for ey := y + 1; ey < board_cells; ey++ {
				if pos.board[ey][nx] == pawn {
					return false
				}
			}
		}
	}
	return true
}

fn (e &Engine) evaluate(pos Position, mobility int, side int) int {
	_ = mobility
	_ = side
	mut score := 0
	mut white_bishops := 0
	mut black_bishops := 0
	mut white_has_queen := false
	mut black_has_queen := false
	mut white_pawn_files := [8]int{}
	mut black_pawn_files := [8]int{}
	mut white_pawn_attacks := [8]int{}
	mut black_pawn_attacks := [8]int{}
	mut white_king_rank := 0
	mut black_king_rank := 0
	mut white_home_minors := 0
	mut black_home_minors := 0
	mut white_queen_developed := false
	mut black_queen_developed := false
	for y := 0; y < board_cells; y++ {
		for x := 0; x < board_cells; x++ {
			piece := pos.board[y][x]
			if piece == 0 {
				continue
			}
			color := piece_color(piece)
			kind := piece_kind(piece)
			match kind {
				pawn {
					if color == white_color {
						white_pawn_files[x]++
						if x > 0 {
							white_pawn_attacks[x - 1]++
						}
						if x < 7 {
							white_pawn_attacks[x + 1]++
						}
					} else {
						black_pawn_files[x]++
						if x > 0 {
							black_pawn_attacks[x - 1]++
						}
						if x < 7 {
							black_pawn_attacks[x + 1]++
						}
					}
				}
				bishop {
					if color == white_color {
						white_bishops++
						if y == 7 {
							white_home_minors++
						}
					} else {
						black_bishops++
						if y == 0 {
							black_home_minors++
						}
					}
				}
				knight {
					if color == white_color && y == 7 {
						white_home_minors++
					} else if color == black_color && y == 0 {
						black_home_minors++
					}
				}
				queen {
					if color == white_color {
						white_has_queen = true
						white_queen_developed = x != 3 || y != 7
					} else {
						black_has_queen = true
						black_queen_developed = x != 3 || y != 0
					}
				}
				king {
					if color == white_color {
						white_king_rank = perspective_rank(y, white_color)
					} else {
						black_king_rank = perspective_rank(y, black_color)
					}
				}
				else {}
			}
		}
	}
	endgame := !white_has_queen && !black_has_queen
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
			py := perspective_rank(y, color)
			match kind {
				pawn {
					pst_bonus = pawn_pst[py][x]
					if is_passed_pawn(pos, color, x, y) {
						pst_bonus += 35 + py * 18
					}
				}
				knight {
					pst_bonus = knight_pst[py][x]
					if py >= 4 && (x == 2 || x == 5) {
						pst_bonus += 15
					}
				}
				bishop {
					pst_bonus = bishop_pst[py][x]
					if x >= 2 && x <= 5 && y >= 2 && y <= 5 {
						pst_bonus += 10
					}
				}
				rook {
					pst_bonus = rook_pst[py][x]
					if white_pawn_files[x] == 0 && black_pawn_files[x] == 0 {
						pst_bonus += 25
					} else if color == white_color && white_pawn_files[x] == 0 {
						pst_bonus += 15
					} else if color == black_color && black_pawn_files[x] == 0 {
						pst_bonus += 15
					}
					if py == 6 {
						pst_bonus += 20
					}
				}
				queen {
					pst_bonus = queen_pst[py][x]
				}
				king {
					if endgame {
						pst_bonus = king_pst_end[py][x]
					} else {
						pst_bonus = king_pst_middle[py][x]
					}
				}
				else {}
			}
			value += pst_bonus
			score += feature_score(color, value)
		}
	}
	for x := 0; x < 8; x++ {
		if white_pawn_files[x] > 1 {
			score -= feature_score(white_color, 15 * (white_pawn_files[x] - 1))
		}
		if black_pawn_files[x] > 1 {
			score -= feature_score(black_color, 15 * (black_pawn_files[x] - 1))
		}
		if white_pawn_files[x] > 0 && white_pawn_attacks[x] == 0 {
			score -= feature_score(white_color, 20)
		}
		if black_pawn_files[x] > 0 && black_pawn_attacks[x] == 0 {
			score -= feature_score(black_color, 20)
		}
	}
	if white_bishops >= 2 {
		score += feature_score(white_color, 30)
	}
	if black_bishops >= 2 {
		score += feature_score(black_color, 30)
	}
	if opening_ply(pos) < opening_phase_plies {
		score -= feature_score(white_color, white_home_minors * 18)
		score -= feature_score(black_color, black_home_minors * 18)
		if white_queen_developed {
			score -= feature_score(white_color, 70)
		}
		if black_queen_developed {
			score -= feature_score(black_color, 70)
		}
	}
	white_castled := pos.board[7][6] == king || pos.board[7][2] == king
	black_castled := pos.board[0][6] == -king || pos.board[0][2] == -king
	if white_castled {
		score += feature_score(white_color, 55)
	}
	if black_castled {
		score += feature_score(black_color, 55)
	}
	if !white_castled && (pos.white_kingside || pos.white_queenside) {
		score += feature_score(white_color, 12)
	}
	if !black_castled && (pos.black_kingside || pos.black_queenside) {
		score += feature_score(black_color, 12)
	}
	if white_castled && black_has_queen {
		score += feature_score(white_color, 25)
	}
	if black_castled && white_has_queen {
		score += feature_score(black_color, 25)
	}
	king_safety_bonus := 15
	if !endgame && white_king_rank <= 1 {
		score += feature_score(white_color, king_safety_bonus)
	}
	if !endgame && black_king_rank <= 1 {
		score += feature_score(black_color, king_safety_bonus)
	}
	white_moves := e.pseudo_moves_for(pos, white_color).len
	black_moves := e.pseudo_moves_for(pos, black_color).len
	score += (black_moves - white_moves) * 8
	score += if pos.white_to_move { -10 } else { 10 }
	if e.is_in_check(pos, white_color) {
		score += 40
	}
	if e.is_in_check(pos, black_color) {
		score -= 40
	}
	return score
}

pub fn (e &Engine) legal_moves_for(pos Position, side int) []engine.Move {
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

fn (e &Engine) pseudo_moves_for(pos Position, side int) []engine.Move {
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

fn (e &Engine) add_pawn_moves(pos Position, side int, x int, y int, mut moves []engine.Move) {
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

fn (e &Engine) add_pawn_move_or_promotions(side int, from_x int, from_y int, to_x int, to_y int, score int, is_en_passant bool, mut moves []engine.Move) {
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

fn (e &Engine) add_knight_moves(pos Position, side int, x int, y int, mut moves []engine.Move) {
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

fn (e &Engine) add_sliding_moves(pos Position, side int, x int, y int, dirs [4]Pos, mut moves []engine.Move) {
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

fn (e &Engine) add_king_moves(pos Position, side int, x int, y int, mut moves []engine.Move) {
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
