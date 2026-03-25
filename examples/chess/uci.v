module main

import engine
import os

const engine_name = 'VChess Engine'
const engine_author = 'Delyan Angelov'

fn main() {
	unbuffer_stdout()
	println('${engine_name}, by ${engine_author}.')
	mut e := engine.Engine{}
	mut pos := e.new_position()
	mut running := true

	for running {
		line := os.get_line().trim_right('\n\r')
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
				pos = parse_position_command(parts, mut e)
			}
			'go' {
				search_result := go_command(parts, mut e, pos)
				best_uci := engine.move_to_uci(search_result.best_move)
				println('bestmove ${best_uci}')
				apply_move(mut pos, search_result.best_move)
				e.record_position(pos)
			}
			'setoption' {}
			'ucinewgame' {
				e.reset()
				pos = e.new_position()
			}
			'quit' {
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

fn go_command(parts []string, mut e engine.Engine, pos engine.Position) engine.SearchResult {
	side := if pos.white_to_move { engine.white_color } else { engine.black_color }
	best_move := e.search_best_move(pos, side)
	return engine.SearchResult{
		best_move: best_move
	}
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
