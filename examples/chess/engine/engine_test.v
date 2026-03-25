module engine

fn apply_legal_uci_move(mut e Engine, mut pos Position, uci string) {
	target := uci_to_move(uci) or { panic('failed to parse UCI move `${uci}`') }
	side := if pos.white_to_move { white_color } else { black_color }
	for mv in e.legal_moves_for(pos, side) {
		if mv.from_x == target.from_x && mv.from_y == target.from_y && mv.to_x == target.to_x
			&& mv.to_y == target.to_y && mv.promotion == target.promotion {
			apply_move(mut pos, mv)
			return
		}
	}
	panic('move `${uci}` was not legal for side `${side}`')
}

fn test_new_position_initializes_castling_rights() {
	mut e := Engine{}
	pos := e.new_position()
	assert pos.white_kingside
	assert pos.white_queenside
	assert pos.black_kingside
	assert pos.black_queenside
	assert pos.en_passant_x == no_square
	assert pos.en_passant_y == no_square
}

fn test_white_castle_replay_keeps_black_to_move() {
	mut e := Engine{}
	mut pos := e.new_position()
	for uci in [
		'e2e3',
		'h7h5',
		'f1c4',
		'h5h4',
		'd1g4',
		'g8f6',
		'g4g5',
		'd7d5',
		'c4b5',
		'c7c6',
		'b5a4',
		'd8d6',
		'c2c4',
		'd5c4',
		'b2b3',
		'f6e4',
		'g5a5',
		'b7b6',
		'c1a3',
		'b6a5',
		'a3d6',
		'e4d6',
		'b3c4',
		'd6c4',
		'd2d3',
		'c4d6',
		'g1f3',
		'd6b5',
		'g2g3',
		'h4g3',
		'f2g3',
		'b5d6',
		'f3e5',
		'c8d7',
		'e5d7',
		'e8d7',
		'e1g1',
	] {
		apply_legal_uci_move(mut e, mut pos, uci)
	}
	assert pos.board[7][6] == king
	assert pos.board[7][5] == rook
	assert pos.white_to_move == false
	assert !e.legal_moves_for(pos, black_color).any(move_to_uci(it) == 'e3e4')
}

fn test_search_best_move_stays_legal_across_repeated_searches() {
	mut e := Engine{}
	pos := e.new_position()
	legal := e.legal_moves_for(pos, white_color)
	best_first := e.search_best_move_with_time(pos, white_color, 20)
	best_second := e.search_best_move_with_time(pos, white_color, 20)
	assert legal.any(same_move(it, best_first))
	assert legal.any(same_move(it, best_second))
}

fn test_quiescence_searches_non_capture_check_evasions() {
	mut e := Engine{}
	shared control := SearchControl{}
	mut pos := Position{
		white_to_move: true
		en_passant_x:  no_square
		en_passant_y:  no_square
	}
	pos.board[7][0] = king
	pos.board[7][1] = bishop
	pos.board[6][1] = pawn
	pos.board[0][0] = -rook
	pos.board[0][7] = -king
	legal := e.legal_moves_for(pos, white_color)
	assert legal.len == 1
	assert move_to_uci(legal[0]) == 'b1a2'
	assert !is_capture_move(pos, legal[0])
	mut next := pos
	apply_move(mut next, legal[0])
	expected := e.quiescence(next, -checkmate_score, checkmate_score, black_color, 1,
		0, -1, shared control)
	actual := e.quiescence(pos, -checkmate_score, checkmate_score, white_color, 0, 0,
		-1, shared control)
	assert actual == expected
}

fn test_quiescence_includes_quiet_promotions() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move: true
		en_passant_x:  no_square
		en_passant_y:  no_square
	}
	pos.board[1][0] = pawn
	pos.board[7][7] = king
	pos.board[0][7] = -king
	tactical := e.legal_moves_for(pos, white_color).filter(is_tactical_move(pos, it))
	assert tactical.len == 4
	assert tactical.all(it.from_x == 0 && it.from_y == 1 && it.to_x == 0 && it.to_y == 0)
	assert tactical.all(it.promotion in [queen, rook, bishop, knight])
}
