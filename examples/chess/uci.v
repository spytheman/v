module main

import engine
import os

const engine_name = 'VChess Engine'
const engine_author = 'Delyan Angelov'
const infinite_time_control_ms = -1
const default_time_control_ms = 2000
const minimum_time_slice_ms = 25
const time_safety_margin_ms = 50

struct GoParams {
mut:
	movetime  int
	wtime     int
	btime     int
	winc      int
	binc      int
	movestogo int
	infinite  bool
}

struct SearchOutcome {
	id        int
	best_move engine.Move
}

fn main() {
	unbuffer_stdout()
	println('${engine_name}, by ${engine_author}.')
	command_ch := chan string{cap: 1}
	result_ch := chan SearchOutcome{cap: 1}
	spawn stdin_reader(command_ch)
	mut e := engine.Engine{}
	mut pos := e.new_position()
	mut running := true
	shared search_control := engine.SearchControl{}
	mut search_id := 0
	mut active_search_id := 0
	mut search_running := false

	for running {
		select {
			line := <-command_ch {
				if line == '' {
					continue
				}
				parts := line.split(' ')
				cmd := parts[0]
				match cmd {
					'uci' {
						println('id name ${engine_name}')
						println('id author ${engine_author}')
						println('uciok')
					}
					'isready' {
						println('readyok')
					}
					'position' {
						if search_running {
							_ = stop_search(active_search_id, result_ch, shared search_control)
							search_running = false
						}
						pos = parse_position_command(parts, mut e)
					}
					'go' {
						if search_running {
							_ = stop_search(active_search_id, result_ch, shared search_control)
							search_running = false
						}
						set_search_stop(false, shared search_control)
						search_id++
						active_search_id = search_id
						search_running = true
						start_search(parts, e, pos, active_search_id, shared search_control,
							result_ch)
					}
					'stop' {
						if search_running {
							result := stop_search(active_search_id, result_ch, shared
								search_control)
							search_running = false
							apply_search_result(mut pos, mut e, result.best_move)
						}
					}
					'setoption' {}
					'ucinewgame' {
						if search_running {
							_ = stop_search(active_search_id, result_ch, shared search_control)
							search_running = false
						}
						e.reset()
						pos = e.new_position()
					}
					'quit' {
						if search_running {
							set_search_stop(true, shared search_control)
						}
						running = false
					}
					'help' {
						println('VChess is a simple chess engine, written in the V programming language.')
					}
					else {
						println('Unknown command: `${cmd}`. Type help for more info.')
					}
				}
			}
			result := <-result_ch {
				if !search_running || result.id != active_search_id {
					continue
				}
				search_running = false
				apply_search_result(mut pos, mut e, result.best_move)
			}
		}
	}
}

fn stdin_reader(command_ch chan string) {
	for {
		command_ch <- os.get_line().trim_right('\n\r')
	}
}

fn parse_position_command(parts []string, mut e engine.Engine) engine.Position {
	mut pos := e.new_position()
	mut i := 1

	if i < parts.len && parts[i] == 'startpos' {
		i++
	} else if i < parts.len && parts[i] == 'fen' {
		i++
		if i < parts.len {
			fen := parts[i..].join(' ')
			pos = parse_fen(fen)
			i = parts.len
		}
	}

	if i < parts.len && parts[i] == 'moves' {
		i++
		for i < parts.len {
			uci := parts[i]
			if mv := engine.uci_to_move(uci) {
				legal := e.legal_moves_for(pos, if pos.white_to_move {
					engine.white_color
				} else {
					engine.black_color
				})
				for lm in legal {
					if lm.from_x == mv.from_x && lm.from_y == mv.from_y && lm.to_x == mv.to_x
						&& lm.to_y == mv.to_y && lm.promotion == mv.promotion {
						apply_move(mut pos, lm)
						e.record_position(pos)
						break
					}
				}
			}
			i++
		}
	}

	return pos
}

fn start_search(parts []string, _ engine.Engine, pos engine.Position, search_id int, shared search_control engine.SearchControl, result_ch chan SearchOutcome) {
	params := parse_go_params(parts)
	time_limit_ms := compute_time_limit_ms(params, pos)
	side := if pos.white_to_move { engine.white_color } else { engine.black_color }
	spawn search_worker(pos, side, time_limit_ms, search_id, shared search_control, result_ch)
}

fn search_worker(pos engine.Position, side int, time_limit_ms int, search_id int, shared search_control engine.SearchControl, result_ch chan SearchOutcome) {
	best_move := compute_best_move_with_control(pos, side, time_limit_ms, shared search_control)
	result_ch <- SearchOutcome{
		id:        search_id
		best_move: best_move
	}
}

fn compute_best_move_with_control(pos engine.Position, side int, time_limit_ms int, shared search_control engine.SearchControl) engine.Move {
	mut worker := engine.Engine{}
	return worker.search_best_move_with_control(pos, side, time_limit_ms, shared search_control)
}

fn stop_search(search_id int, result_ch chan SearchOutcome, shared search_control engine.SearchControl) SearchOutcome {
	set_search_stop(true, shared search_control)
	for {
		result := <-result_ch
		if result.id == search_id {
			return result
		}
	}
	return SearchOutcome{}
}

fn set_search_stop(stop bool, shared search_control engine.SearchControl) {
	lock search_control {
		search_control.stop = stop
	}
}

fn apply_search_result(mut pos engine.Position, mut e engine.Engine, best_move engine.Move) {
	legal_move := find_legal_move_for_position(e, pos, best_move)
	println('bestmove ${bestmove_string(legal_move)}')
}

fn bestmove_string(best_move engine.Move) string {
	if best_move == engine.Move{} {
		return '0000'
	}
	return engine.move_to_uci(best_move)
}

fn find_legal_move_for_position(e engine.Engine, pos engine.Position, best_move engine.Move) engine.Move {
	side := if pos.white_to_move { engine.white_color } else { engine.black_color }
	legal_moves := e.legal_moves_for(pos, side)
	for mv in legal_moves {
		if same_move(mv, best_move) {
			return mv
		}
	}
	if legal_moves.len > 0 {
		return legal_moves[0]
	}
	return engine.Move{}
}

fn same_move(a engine.Move, b engine.Move) bool {
	return a.from_x == b.from_x && a.from_y == b.from_y && a.to_x == b.to_x && a.to_y == b.to_y
		&& a.promotion == b.promotion
}

fn parse_go_params(parts []string) GoParams {
	mut params := GoParams{}
	mut i := 1
	for i < parts.len {
		match parts[i] {
			'movetime' {
				if i + 1 < parts.len {
					params.movetime = parts[i + 1].int()
					i++
				}
			}
			'wtime' {
				if i + 1 < parts.len {
					params.wtime = parts[i + 1].int()
					i++
				}
			}
			'btime' {
				if i + 1 < parts.len {
					params.btime = parts[i + 1].int()
					i++
				}
			}
			'winc' {
				if i + 1 < parts.len {
					params.winc = parts[i + 1].int()
					i++
				}
			}
			'binc' {
				if i + 1 < parts.len {
					params.binc = parts[i + 1].int()
					i++
				}
			}
			'movestogo' {
				if i + 1 < parts.len {
					params.movestogo = parts[i + 1].int()
					i++
				}
			}
			'infinite' {
				params.infinite = true
			}
			else {}
		}
		i++
	}
	return params
}

fn compute_time_limit_ms(params GoParams, pos engine.Position) int {
	if params.movetime > 0 {
		return max_time_budget(params.movetime)
	}
	if params.infinite {
		return infinite_time_control_ms
	}
	remaining := if pos.white_to_move { params.wtime } else { params.btime }
	increment := if pos.white_to_move { params.winc } else { params.binc }
	if remaining <= 0 {
		return default_time_control_ms
	}
	moves_left := if params.movestogo > 0 { params.movestogo } else { 30 }
	safe_remaining := max_int(minimum_time_slice_ms, remaining - time_safety_margin_ms)
	mut budget := safe_remaining / moves_left
	if increment > 0 {
		budget += increment / 2
	}
	return min_int(max_time_budget(budget), safe_remaining)
}

fn max_time_budget(v int) int {
	return max_int(v, minimum_time_slice_ms)
}

fn min_int(a int, b int) int {
	return if a < b { a } else { b }
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

fn parse_fen(fen string) engine.Position {
	mut pos := engine.Position{}
	parts := fen.split(' ')
	if parts.len < 1 {
		return pos
	}
	rows := parts[0].split('/')
	if rows.len != 8 {
		return pos
	}
	for y := 0; y < 8 && y < rows.len; y++ {
		mut x := 0
		for ch in rows[y].runes() {
			if ch >= `1` && ch <= `8` {
				x += int(ch - `0`)
			} else {
				piece := char_to_piece(ch)
				if x < 8 {
					pos.board[y][x] = piece
					x++
				}
			}
		}
	}
	if parts.len > 1 {
		pos.white_to_move = parts[1] == 'w'
	}
	if parts.len > 2 {
		pos.white_kingside = parts[2].contains('K')
		pos.white_queenside = parts[2].contains('Q')
		pos.black_kingside = parts[2].contains('k')
		pos.black_queenside = parts[2].contains('q')
	}
	if parts.len > 3 {
		ep := parts[3]
		if ep != '-' && ep.len >= 2 {
			pos.en_passant_x = int(ep[0] - `a`)
			pos.en_passant_y = int(ep[1] - `1`)
		}
	}
	if parts.len > 4 {
		pos.halfmove_clock = parts[4].int()
	}
	if parts.len > 5 {
		pos.fullmove_number = parts[5].int()
	}
	return pos
}

fn char_to_piece(ch rune) int {
	return match ch {
		`P` { engine.pawn }
		`N` { engine.knight }
		`B` { engine.bishop }
		`R` { engine.rook }
		`Q` { engine.queen }
		`K` { engine.king }
		`p` { -engine.pawn }
		`n` { -engine.knight }
		`b` { -engine.bishop }
		`r` { -engine.rook }
		`q` { -engine.queen }
		`k` { -engine.king }
		else { 0 }
	}
}

fn apply_move(mut pos engine.Position, mv engine.Move) {
	piece := pos.board[mv.from_y][mv.from_x]
	side := engine.piece_color(piece)
	mut captured := pos.board[mv.to_y][mv.to_x]
	pos.en_passant_x = engine.no_square
	pos.en_passant_y = engine.no_square
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
	if piece == engine.king {
		pos.white_kingside = false
		pos.white_queenside = false
	}
	if piece == -engine.king {
		pos.black_kingside = false
		pos.black_queenside = false
	}
	if mv.from_x == 0 && mv.from_y == 7 && piece == engine.rook {
		pos.white_queenside = false
	}
	if mv.from_x == 7 && mv.from_y == 7 && piece == engine.rook {
		pos.white_kingside = false
	}
	if mv.from_x == 0 && mv.from_y == 0 && piece == -engine.rook {
		pos.black_queenside = false
	}
	if mv.from_x == 7 && mv.from_y == 0 && piece == -engine.rook {
		pos.black_kingside = false
	}
	if mv.to_x == 0 && mv.to_y == 7 && captured == engine.rook {
		pos.white_queenside = false
	}
	if mv.to_x == 7 && mv.to_y == 7 && captured == engine.rook {
		pos.white_kingside = false
	}
	if mv.to_x == 0 && mv.to_y == 0 && captured == -engine.rook {
		pos.black_queenside = false
	}
	if mv.to_x == 7 && mv.to_y == 0 && captured == -engine.rook {
		pos.black_kingside = false
	}
	if engine.piece_kind(piece) == engine.pawn && iabs(mv.to_y - mv.from_y) == 2 {
		pos.en_passant_x = mv.from_x
		pos.en_passant_y = (mv.from_y + mv.to_y) / 2
	}
	if engine.piece_kind(piece) == engine.pawn || captured != 0 {
		pos.halfmove_clock = 0
	} else {
		pos.halfmove_clock++
	}
	if side == engine.black_color {
		pos.fullmove_number++
	}
	pos.white_to_move = !pos.white_to_move
}

fn iabs(v int) int {
	return if v < 0 { -v } else { v }
}
