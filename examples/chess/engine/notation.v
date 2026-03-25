module engine

fn file_char(x int) string {
	return '${`a` + x}'.runes().string()
}

fn rank_char(y int) string {
	return '${`8` - y}'.runes().string()
}

pub fn move_to_uci(mv Move) string {
	mut s := ''
	s += file_char(mv.from_x)
	s += rank_char(mv.from_y)
	s += file_char(mv.to_x)
	s += rank_char(mv.to_y)
	if mv.promotion == queen {
		s += 'q'
	} else if mv.promotion == rook {
		s += 'r'
	} else if mv.promotion == bishop {
		s += 'b'
	} else if mv.promotion == knight {
		s += 'n'
	}
	return s
}

pub fn uci_to_move(uci string) ?Move {
	if uci.len < 4 {
		return none
	}
	from_file := int(uci[0] - `a`)
	from_rank := int(`8` - uci[1])
	to_file := int(uci[2] - `a`)
	to_rank := int(`8` - uci[3])
	mut promotion := 0
	if uci.len == 5 {
		promotion = match uci[4] {
			`q` { queen }
			`r` { rook }
			`b` { bishop }
			`n` { knight }
			else { 0 }
		}
	}
	return Move{
		from_x:    from_file
		from_y:    from_rank
		to_x:      to_file
		to_y:      to_rank
		promotion: promotion
	}
}

pub fn move_to_san(mv Move, pos Position) string {
	piece := pos.board[mv.from_y][mv.from_x]
	kind := piece_kind(piece)
	captured := pos.board[mv.to_y][mv.to_x]
	is_white := piece > 0
	mut next := pos
	apply_move(mut next, mv)
	mut san := ''
	if mv.is_castle {
		if mv.to_x == 6 {
			return 'O-O'
		}
		return 'O-O-O'
	}
	if kind != pawn {
		san = piece_to_san_char(kind)
	}
	need_file, need_rank := san_disambiguation(mv, pos, kind)
	if need_file {
		san += file_char(mv.from_x)
	}
	if need_rank {
		san += rank_char(mv.from_y)
	}
	if kind == pawn && captured != 0 {
		san = file_char(mv.from_x)
	} else if kind == pawn && mv.is_en_passant {
		san = file_char(mv.from_x)
	}
	if captured != 0 || mv.is_en_passant {
		san += 'x'
	}
	san += file_char(mv.to_x) + rank_char(mv.to_y)
	if mv.promotion != 0 {
		san += '=' + piece_to_san_char(mv.promotion)
	}
	if is_white {
		if is_in_check(next, black_color) {
			if is_checkmate(next, black_color) {
				san += '#'
			} else {
				san += '+'
			}
		}
	} else {
		if is_in_check(next, white_color) {
			if is_checkmate(next, white_color) {
				san += '#'
			} else {
				san += '+'
			}
		}
	}
	return san
}

fn san_disambiguation(mv Move, pos Position, kind int) (bool, bool) {
	if kind == pawn || kind == king {
		return false, false
	}
	mut e := Engine{}
	side := if pos.white_to_move { white_color } else { black_color }
	mut same_file := false
	mut same_rank := false
	mut found := false
	for other in e.legal_moves_for(pos, side) {
		if other.from_x == mv.from_x && other.from_y == mv.from_y {
			continue
		}
		if other.to_x != mv.to_x || other.to_y != mv.to_y || other.promotion != mv.promotion {
			continue
		}
		piece := pos.board[other.from_y][other.from_x]
		if piece != 0 && piece_kind(piece) == kind {
			found = true
			if other.from_x == mv.from_x {
				same_file = true
			}
			if other.from_y == mv.from_y {
				same_rank = true
			}
		}
	}
	if !found {
		return false, false
	}
	if !same_file {
		return true, false
	}
	if !same_rank {
		return false, true
	}
	return true, true
}

pub fn find_move_in_legal(pos Position, from_x int, from_y int, to_x int, to_y int, promotion int) ?Move {
	mut e := Engine{}
	moves := e.legal_moves_for(pos, if pos.white_to_move { white_color } else { black_color })
	for mv in moves {
		if mv.from_x == from_x && mv.from_y == from_y && mv.to_x == to_x && mv.to_y == to_y
			&& mv.promotion == promotion {
			return mv
		}
	}
	return none
}

fn piece_to_san_char(kind int) string {
	return match kind {
		knight { 'N' }
		bishop { 'B' }
		rook { 'R' }
		queen { 'Q' }
		king { 'K' }
		else { '' }
	}
}

fn is_in_check(pos Position, side int) bool {
	mut kx := -1
	mut ky := -1
	for y := 0; y < 8; y++ {
		for x := 0; x < 8; x++ {
			if pos.board[y][x] == side * king {
				kx = x
				ky = y
				break
			}
		}
	}
	if kx < 0 {
		return false
	}
	attacker := -side
	if attacker == 1 {
		py := ky + 1
		if py < 8 {
			if kx > 0 && pos.board[py][kx - 1] == pawn {
				return true
			}
			if kx < 7 && pos.board[py][kx + 1] == pawn {
				return true
			}
		}
	} else {
		py := ky - 1
		if py >= 0 {
			if kx > 0 && pos.board[py][kx - 1] == -pawn {
				return true
			}
			if kx < 7 && pos.board[py][kx + 1] == -pawn {
				return true
			}
		}
	}
	for offset in knight_offsets {
		nx := kx + offset.x
		ny := ky + offset.y
		if inside(nx, ny) && pos.board[ny][nx] == attacker * knight {
			return true
		}
	}
	for dir in bishop_dirs {
		mut nx := kx + dir.x
		mut ny := ky + dir.y
		for inside(nx, ny) {
			p := pos.board[ny][nx]
			if p != 0 {
				if p == attacker * bishop || p == attacker * queen {
					return true
				}
				break
			}
			nx += dir.x
			ny += dir.y
		}
	}
	for dir in rook_dirs {
		mut nx := kx + dir.x
		mut ny := ky + dir.y
		for inside(nx, ny) {
			p := pos.board[ny][nx]
			if p != 0 {
				if p == attacker * rook || p == attacker * queen {
					return true
				}
				break
			}
			nx += dir.x
			ny += dir.y
		}
	}
	for offset in king_offsets {
		nx := kx + offset.x
		ny := ky + offset.y
		if inside(nx, ny) && pos.board[ny][nx] == attacker * king {
			return true
		}
	}
	return false
}

fn is_checkmate(pos Position, side int) bool {
	if !is_in_check(pos, side) {
		return false
	}
	for y := 0; y < 8; y++ {
		for x := 0; x < 8; x++ {
			piece := pos.board[y][x]
			if piece == 0 || piece_color(piece) != side {
				continue
			}
			kind := piece_kind(piece)
			match kind {
				pawn {
					if has_legal_pawn_moves(pos, x, y, side) {
						return false
					}
				}
				knight {
					if has_legal_knight_moves(pos, x, y, side) {
						return false
					}
				}
				bishop, rook, queen {
					if has_legal_sliding_moves(pos, x, y, side) {
						return false
					}
				}
				king {
					if has_legal_king_moves(pos, x, y, side) {
						return false
					}
				}
				else {}
			}
		}
	}
	return true
}

fn has_legal_pawn_moves(pos Position, x int, y int, side int) bool {
	step := if side == 1 { -1 } else { 1 }
	start_row := if side == 1 { 6 } else { 1 }
	one_y := y + step
	if inside(x, one_y) && pos.board[one_y][x] == 0 {
		mut next := pos
		next.board[y][x] = 0
		next.board[one_y][x] = side * pawn
		if !is_in_check(next, side) {
			return true
		}
		if y == start_row {
			two_y := y + step * 2
			if pos.board[two_y][x] == 0 {
				next = pos
				next.board[y][x] = 0
				next.board[two_y][x] = side * pawn
				if !is_in_check(next, side) {
					return true
				}
			}
		}
	}
	for dx := -1; dx <= 1; dx += 2 {
		nx := x + dx
		ny := y + step
		if !inside(nx, ny) {
			continue
		}
		target := pos.board[ny][nx]
		if target != 0 && piece_color(target) == -side {
			mut next := pos
			next.board[y][x] = 0
			next.board[ny][nx] = side * pawn
			if !is_in_check(next, side) {
				return true
			}
		}
	}
	return false
}

fn has_legal_knight_moves(pos Position, x int, y int, side int) bool {
	for offset in knight_offsets {
		nx := x + offset.x
		ny := y + offset.y
		if !inside(nx, ny) {
			continue
		}
		target := pos.board[ny][nx]
		if target == 0 || piece_color(target) == -side {
			mut next := pos
			next.board[y][x] = 0
			next.board[ny][nx] = side * knight
			if !is_in_check(next, side) {
				return true
			}
		}
	}
	return false
}

fn has_legal_sliding_moves(pos Position, x int, y int, side int) bool {
	kind := piece_kind(pos.board[y][x])
	for dir in bishop_dirs {
		mut nx := x + dir.x
		mut ny := y + dir.y
		for inside(nx, ny) {
			target := pos.board[ny][nx]
			if target != 0 && piece_color(target) == -side {
				mut next := pos
				next.board[y][x] = 0
				next.board[ny][nx] = pos.board[y][x]
				if !is_in_check(next, side) {
					return true
				}
			}
			if target != 0 {
				break
			}
			nx += dir.x
			ny += dir.y
		}
	}
	if kind == queen || kind == bishop {
		return false
	}
	for dir in rook_dirs {
		mut nx := x + dir.x
		mut ny := y + dir.y
		for inside(nx, ny) {
			target := pos.board[ny][nx]
			if target != 0 && piece_color(target) == -side {
				mut next := pos
				next.board[y][x] = 0
				next.board[ny][nx] = pos.board[y][x]
				if !is_in_check(next, side) {
					return true
				}
			}
			if target != 0 {
				break
			}
			nx += dir.x
			ny += dir.y
		}
	}
	return false
}

fn has_legal_king_moves(pos Position, x int, y int, side int) bool {
	for offset in king_offsets {
		nx := x + offset.x
		ny := y + offset.y
		if !inside(nx, ny) {
			continue
		}
		target := pos.board[ny][nx]
		if target == 0 || piece_color(target) == -side {
			mut next := pos
			next.board[y][x] = 0
			next.board[ny][nx] = side * king
			if !is_in_check(next, side) {
				return true
			}
		}
	}
	return false
}
