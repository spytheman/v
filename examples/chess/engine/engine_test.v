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

fn test_search_finds_mate_in_one() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move: true
		en_passant_x:  no_square
		en_passant_y:  no_square
	}
	pos.board[7][4] = queen
	pos.board[7][6] = king
	pos.board[0][6] = -king
	pos.board[1][6] = -pawn
	pos.board[1][7] = -pawn
	best := e.search_best_move_with_time(pos, white_color, 50)
	assert move_to_uci(best) == 'e1e8'
}

fn test_black_first_reply_to_e4_prefers_stable_opening_over_nc6() {
	mut e := Engine{}
	mut pos := e.new_position()
	apply_legal_uci_move(mut e, mut pos, 'e2e4')
	legal := e.legal_moves_for(pos, black_color)
	ordered := e.order_moves(legal, pos, black_color, 0)
	assert ordered.len > 0
	assert move_to_uci(ordered[0]) != 'b8c6'
	assert move_to_uci(ordered[0]) in ['e7e5', 'c7c5', 'e7e6', 'c7c6', 'g8f6']
	best := e.search_best_move_with_time(pos, black_color, 50)
	assert move_to_uci(best) == 'e7e5'
}

fn test_opening_book_accepts_equivalent_e4_ep_encodings() {
	mut e := Engine{}
	mut pos := e.new_position()
	apply_legal_uci_move(mut e, mut pos, 'e2e4')
	legal := e.legal_moves_for(pos, black_color)
	if mv := opening_book_move(pos, black_color, legal) {
		assert move_to_uci(mv) == 'e7e5'
	} else {
		assert false
	}
	pos.en_passant_y = 2
	if mv := opening_book_move(pos, black_color, legal) {
		assert move_to_uci(mv) == 'e7e5'
	} else {
		assert false
	}
	pos.en_passant_x = no_square
	pos.en_passant_y = no_square
	if mv := opening_book_move(pos, black_color, legal) {
		assert move_to_uci(mv) == 'e7e5'
	} else {
		assert false
	}
}

fn test_opening_book_ignores_arbitrary_fen_like_e4_position() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   false
		white_kingside:  true
		white_queenside: true
		black_kingside:  true
		black_queenside: true
		en_passant_x:    4
		en_passant_y:    5
		fullmove_number: 1
	}
	pos.board[7][4] = king
	pos.board[4][4] = pawn
	pos.board[0][4] = -king
	pos.board[1][4] = -pawn
	legal := e.legal_moves_for(pos, black_color)
	assert legal.any(move_to_uci(it) == 'e7e5')
	if _ := opening_book_move(pos, black_color, legal) {
		assert false
	} else {
		assert true
	}
}

fn test_white_opening_book_keeps_simple_repertoire() {
	mut e := Engine{}
	mut pos := e.new_position()
	legal_start := e.legal_moves_for(pos, white_color)
	if mv := opening_book_move(pos, white_color, legal_start) {
		assert move_to_uci(mv) == 'e2e4'
	} else {
		assert false
	}
	apply_legal_uci_move(mut e, mut pos, 'e2e4')
	apply_legal_uci_move(mut e, mut pos, 'e7e5')
	legal_after_e5 := e.legal_moves_for(pos, white_color)
	if mv := opening_book_move(pos, white_color, legal_after_e5) {
		assert move_to_uci(mv) == 'g1f3'
	} else {
		assert false
	}
}

fn test_opening_move_order_penalizes_early_quiet_queen_move() {
	mut e := Engine{}
	mut pos := e.new_position()
	apply_legal_uci_move(mut e, mut pos, 'e2e4')
	apply_legal_uci_move(mut e, mut pos, 'e7e5')
	legal := e.legal_moves_for(pos, white_color)
	ordered := e.order_moves(legal, pos, white_color, 0)
	mut queen_move_idx := -1
	mut knight_move_idx := -1
	for i, mv in ordered {
		match move_to_uci(mv) {
			'd1h5' {
				queen_move_idx = i
			}
			'g1f3' {
				knight_move_idx = i
			}
			else {}
		}
	}
	assert queen_move_idx >= 0
	assert knight_move_idx >= 0
	assert knight_move_idx < queen_move_idx
}

fn test_sanity_filter_rejects_hanging_queen_move() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 3
	}
	pos.board[7][4] = king
	pos.board[7][3] = queen
	pos.board[0][4] = -king
	pos.board[0][0] = -rook
	pos.board[6][0] = pawn
	shared control := SearchControl{}
	hanging := Move{
		from_x: 3
		from_y: 7
		to_x:   3
		to_y:   0
	}
	quiet := Move{
		from_x: 0
		from_y: 6
		to_x:   0
		to_y:   5
	}
	filtered := e.sanity_filter_root_move(pos, white_color, hanging, [hanging, quiet], 0, -1, shared
		control)
	assert same_move(filtered, quiet)
}

fn test_sanity_filter_returns_immediately_when_stopped() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 3
	}
	pos.board[7][4] = king
	pos.board[7][3] = queen
	pos.board[0][4] = -king
	pos.board[0][0] = -rook
	pos.board[6][0] = pawn
	shared control := SearchControl{
		stop: true
	}
	hanging := Move{
		from_x: 3
		from_y: 7
		to_x:   3
		to_y:   0
	}
	quiet := Move{
		from_x: 0
		from_y: 6
		to_x:   0
		to_y:   5
	}
	filtered := e.sanity_filter_root_move(pos, white_color, hanging, [hanging, quiet], 0, -1, shared
		control)
	assert same_move(filtered, hanging)
}

fn test_sanity_filter_allows_favorable_major_piece_capture() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 5
	}
	pos.board[7][6] = king
	pos.board[7][3] = rook
	pos.board[0][4] = -king
	pos.board[0][3] = -queen
	shared control := SearchControl{}
	favorable := Move{
		from_x: 3
		from_y: 7
		to_x:   3
		to_y:   0
	}
	quiet := Move{
		from_x: 6
		from_y: 7
		to_x:   7
		to_y:   7
	}
	filtered := e.sanity_filter_root_move(pos, white_color, favorable, [favorable, quiet], 0, -1, shared
		control)
	assert same_move(filtered, favorable)
}

fn test_sanity_filter_keeps_top_ordered_fallback_when_best_was_low_priority() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 5
	}
	pos.board[7][6] = king
	pos.board[7][3] = queen
	pos.board[7][0] = rook
	pos.board[7][1] = rook
	pos.board[7][2] = rook
	pos.board[4][4] = pawn
	pos.board[0][7] = -king
	pos.board[0][1] = -knight
	pos.board[1][3] = -knight
	pos.board[3][6] = -bishop
	pos.board[3][3] = -queen
	pos.board[2][0] = -pawn
	pos.board[2][1] = -pawn
	pos.board[2][2] = -pawn
	shared control := SearchControl{}
	safe_top_fallback := Move{
		from_x: 4
		from_y: 4
		to_x:   3
		to_y:   3
	}
	bad_fallback_1 := Move{
		from_x: 0
		from_y: 7
		to_x:   0
		to_y:   2
	}
	bad_fallback_2 := Move{
		from_x: 1
		from_y: 7
		to_x:   1
		to_y:   2
	}
	bad_fallback_3 := Move{
		from_x: 2
		from_y: 7
		to_x:   2
		to_y:   2
	}
	bad_best := Move{
		from_x: 3
		from_y: 7
		to_x:   3
		to_y:   0
	}
	filtered := e.sanity_filter_root_move(pos, white_color, bad_best, [
		safe_top_fallback,
		bad_fallback_1,
		bad_fallback_2,
		bad_fallback_3,
		bad_best,
	], 0, -1, shared control)
	assert same_move(filtered, safe_top_fallback)
}

fn test_sanity_filter_rejects_hanging_minor_piece() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 5
	}
	pos.board[7][6] = king
	pos.board[7][5] = bishop
	pos.board[6][0] = pawn
	pos.board[0][6] = -king
	pos.board[3][1] = -pawn
	shared control := SearchControl{}
	hanging := Move{
		from_x: 5
		from_y: 7
		to_x:   2
		to_y:   4
	}
	quiet := Move{
		from_x: 0
		from_y: 6
		to_x:   0
		to_y:   5
	}
	filtered := e.sanity_filter_root_move(pos, white_color, hanging, [hanging, quiet], 0, -1, shared
		control)
	assert same_move(filtered, quiet)
}

fn test_reduced_tactical_search_detects_discovered_queen_loss() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 5
	}
	pos.board[7][6] = king
	pos.board[7][0] = queen
	pos.board[6][0] = knight
	pos.board[6][7] = pawn
	pos.board[0][6] = -king
	pos.board[0][0] = -rook
	exposes_queen := Move{
		from_x: 0
		from_y: 6
		to_x:   1
		to_y:   4
	}
	assert !e.tactical_verification_fails(pos, white_color, exposes_queen)
	assert e.is_catastrophic_root_move(pos, white_color, exposes_queen)
	mut next := e.copy_position(pos)
	apply_move(mut next, exposes_queen)
	assert e.reduced_tactical_search_fails(next, white_color)
}

fn test_exposed_king_marks_position_tactical() {
	e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 8
	}
	pos.board[7][4] = king
	pos.board[7][3] = queen
	pos.board[0][4] = -king
	pos.board[0][3] = -queen
	pos.board[0][0] = -rook
	assert e.is_king_exposed(pos, white_color)
	assert e.is_tactical_position(pos, white_color)
}

fn test_exposed_king_depth_extension_is_root_only() {
	e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 8
	}
	pos.board[7][4] = king
	pos.board[7][3] = queen
	pos.board[0][4] = -king
	pos.board[0][3] = -queen
	pos.board[0][0] = -rook
	root_depth, root_exposed := e.search_depth_with_extensions(pos, white_color, 1, 0)
	child_depth, child_exposed := e.search_depth_with_extensions(pos, white_color, 1, 1)
	assert root_exposed
	assert child_exposed
	assert root_depth == 2
	assert child_depth == 1
}

fn test_low_material_endgame_king_is_not_exposed() {
	e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 40
	}
	pos.board[4][4] = king
	pos.board[2][2] = -king
	pos.board[3][4] = pawn
	pos.board[1][2] = -pawn
	assert !e.is_king_exposed(pos, white_color)
}

fn test_ordinary_pawn_capture_does_not_force_tactical_time() {
	mut e := Engine{}
	mut pos := e.new_position()
	apply_legal_uci_move(mut e, mut pos, 'a2a3')
	apply_legal_uci_move(mut e, mut pos, 'h7h6')
	apply_legal_uci_move(mut e, mut pos, 'b2b4')
	apply_legal_uci_move(mut e, mut pos, 'a7a5')
	assert e.legal_moves_for(pos, white_color).any(move_to_uci(it) == 'b4a5')
	assert !e.is_tactical_position(pos, white_color)
}

fn test_tactical_position_gets_time_budget_bonus() {
	e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 8
	}
	pos.board[7][4] = king
	pos.board[7][3] = queen
	pos.board[0][4] = -king
	pos.board[0][3] = -queen
	pos.board[0][0] = -rook
	assert e.is_tactical_position(pos, white_color)
	assert tactical_time_bonus_percent == 50
	assert e.time_budget_with_tactical_bonus(pos, white_color, 998) == 1497
}

fn test_queen_harassed_by_development_is_catastrophic() {
	mut e := Engine{}
	mut pos := e.new_position()
	apply_legal_uci_move(mut e, mut pos, 'e2e4')
	apply_legal_uci_move(mut e, mut pos, 'e7e5')
	legal := e.legal_moves_for(pos, white_color)
	queen_move := find_uci_move(legal, 'd1h5') or { panic('expected d1h5') }
	assert e.is_catastrophic_root_move(pos, white_color, queen_move)
}

fn test_harmless_multiple_checks_do_not_force_rejection() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   false
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 8
	}
	pos.board[7][4] = king
	pos.board[7][0] = rook
	pos.board[7][7] = rook
	pos.board[6][0] = queen
	pos.board[0][6] = -king
	pos.board[0][0] = -queen
	pos.board[5][7] = -rook
	assert e.is_king_exposed(pos, white_color)
	assert !e.allows_forcing_check_sequence(pos, white_color)
}

fn test_tactical_queen_capture_is_not_rejected_as_opening_harassment() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 3
	}
	pos.board[7][6] = king
	pos.board[7][3] = queen
	pos.board[0][6] = -king
	pos.board[5][5] = -bishop
	pos.board[0][7] = -rook
	capture := Move{
		from_x: 3
		from_y: 7
		to_x:   5
		to_y:   5
	}
	assert is_tactical_move(pos, capture)
	assert !e.is_quiet_opening_queen_move(pos, capture, white_color)
}

fn test_tactical_verification_ignores_unrelated_hanging_material() {
	mut e := Engine{}
	mut pos := Position{
		white_to_move:   true
		en_passant_x:    no_square
		en_passant_y:    no_square
		fullmove_number: 5
	}
	pos.board[7][6] = king
	pos.board[7][0] = queen
	pos.board[6][1] = pawn
	pos.board[5][0] = -pawn
	pos.board[0][6] = -king
	pos.board[0][0] = -rook
	candidate := Move{
		from_x: 1
		from_y: 6
		to_x:   0
		to_y:   5
	}
	assert is_tactical_move(pos, candidate)
	assert !e.tactical_verification_fails(pos, white_color, candidate)
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
	expected := e.quiescence(next, -checkmate_score, checkmate_score, black_color, 1, 0, -1, shared
		control)
	actual := e.quiescence(pos, -checkmate_score, checkmate_score, white_color, 0, 0, -1, shared
		control)
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

fn test_evaluate_castled_white_king_is_safer_than_uncastled() {
	mut e := Engine{}
	mut uncastled := Position{
		white_to_move: true
		en_passant_x:  no_square
		en_passant_y:  no_square
	}
	uncastled.board[7][4] = king
	uncastled.board[7][7] = rook
	uncastled.board[7][3] = queen
	uncastled.board[6][6] = pawn
	uncastled.board[6][7] = pawn
	uncastled.board[0][4] = -king
	uncastled.board[0][7] = -rook
	uncastled.board[0][3] = -queen
	uncastled.board[1][6] = -pawn
	uncastled.board[1][7] = -pawn
	mut castled := uncastled
	castled.board[7][4] = 0
	castled.board[7][7] = 0
	castled.board[7][6] = king
	castled.board[7][5] = rook
	assert e.evaluate(castled, 0, white_color) < e.evaluate(uncastled, 0, white_color)
}

fn test_evaluate_more_advanced_passed_pawn_scores_better() {
	mut e := Engine{}
	mut base := Position{
		white_to_move: true
		en_passant_x:  no_square
		en_passant_y:  no_square
	}
	base.board[7][6] = king
	base.board[0][6] = -king
	mut early := base
	early.board[5][4] = pawn
	mut advanced := base
	advanced.board[2][4] = pawn
	assert e.evaluate(advanced, 0, white_color) < e.evaluate(early, 0, white_color)
}
