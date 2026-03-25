module main

import gg
import os
import os.asset
import time
import engine

const tile_size = 80
const board_padding = 18
const panel_width = 360
const top_height = 0
const window_width = board_padding * 2 + tile_size * 8 + panel_width
const window_height = board_padding * 2 + tile_size * 8

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

@[heap]
struct Game {
mut:
	ctx                &gg.Context = unsafe { nil }
	eng                engine.Engine
	pos                engine.Position
	selected_x         int = engine.no_square
	selected_y         int = engine.no_square
	hover_moves        []engine.Move
	pending_promotions []engine.Move
	status             string = 'White to move'
	game_over          bool
	images             map[int]int
	ai_thinking        bool
	pending_ai_move    engine.Move
	best_move_so_far   engine.Move
	thinking_frame     int
	ai_start_time      i64
	pgn_moves          []string
	pgn_result         string = '*'
	pgn_output_path    string
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
	g.pos = g.eng.new_position()
	g.selected_x = engine.no_square
	g.selected_y = engine.no_square
	g.hover_moves = []engine.Move{}
	g.pending_promotions = []engine.Move{}
	g.game_over = false
	g.eng.reset()
	g.pgn_moves = []string{}
	g.pgn_result = '*'
	g.pgn_output_path = ''
	g.eng.record_position(g.pos)
	g.update_status()
	g.write_pgn_file()
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
						g.try_promotion_shortcut(engine.rook)
					} else {
						g.reset()
					}
				}
				.q {
					g.try_promotion_shortcut(engine.queen)
				}
				.b {
					g.try_promotion_shortcut(engine.bishop)
				}
				.n {
					g.try_promotion_shortcut(engine.knight)
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
	mut matching := []engine.Move{}
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
	if engine.piece_color(piece) == engine.white_color {
		if g.selected_x == x && g.selected_y == y {
			g.clear_selection()
		} else {
			g.selected_x = x
			g.selected_y = y
			g.hover_moves = g.eng.legal_moves_for(g.pos, engine.white_color).filter(it.from_x == x
				&& it.from_y == y)
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
	start_x := board_padding + (tile_size * 8 - total) / 2
	y := top_height + board_padding + tile_size * 3
	return start_x + index * (width + spacing), y, width, height
}

fn (mut g Game) clear_selection() {
	g.selected_x = engine.no_square
	g.selected_y = engine.no_square
	g.hover_moves = []engine.Move{}
	g.pending_promotions = []engine.Move{}
}

fn board_square_from_mouse(mouse_x int, mouse_y int) (int, int, bool) {
	board_x := mouse_x - board_padding
	board_y := mouse_y - top_height - board_padding
	if board_x < 0 || board_y < 0 {
		return 0, 0, false
	}
	x := board_x / tile_size
	y := board_y / tile_size
	if x < 0 || x >= 8 || y < 0 || y >= 8 {
		return 0, 0, false
	}
	return x, y, true
}

fn (mut g Game) commit_player_move(mv engine.Move) {
	pos_before := g.pos
	engine.apply_move(mut g.pos, mv)
	g.record_pgn_move(mv, pos_before)
	g.clear_selection()
	g.eng.record_position(g.pos)
	g.update_status()
	g.write_pgn_file()
	if !g.game_over {
		g.make_ai_move()
	}
}

fn (mut g Game) make_ai_move() {
	side := if g.pos.white_to_move { engine.white_color } else { engine.black_color }
	moves := g.eng.legal_moves_for(g.pos, side)
	if moves.len == 0 {
		g.update_status()
		return
	}
	g.ai_thinking = true
	g.thinking_frame = 0
	g.status = 'Black is thinking...'
	g.pending_ai_move = engine.Move{}
	g.best_move_so_far = engine.Move{}
	g.ai_start_time = time.ticks()
	spawn g.compute_ai_move(moves)
}

fn (mut g Game) compute_ai_move(moves []engine.Move) {
	side := if g.pos.white_to_move { engine.white_color } else { engine.black_color }
	g.pending_ai_move = g.eng.search_best_move(g.pos, side)
}

fn (mut g Game) apply_ai_move() {
	if g.pending_ai_move == engine.Move{} {
		return
	}
	pos_before := g.pos
	engine.apply_move(mut g.pos, g.pending_ai_move)
	g.record_pgn_move(g.pending_ai_move, pos_before)
	g.eng.record_position(g.pos)
	g.update_status()
	g.write_pgn_file()
	g.ai_thinking = false
}

fn (mut g Game) update_status() {
	side := if g.pos.white_to_move { engine.white_color } else { engine.black_color }
	is_over, msg := g.eng.is_game_over(g.pos)
	if is_over {
		g.game_over = true
		g.status = msg
		g.pgn_result = pgn_result_from_status(msg)
		g.hover_moves = []engine.Move{}
		return
	}
	legal_moves := g.eng.legal_moves_for(g.pos, side)
	in_check := g.eng.is_in_check(g.pos, side)
	if legal_moves.len == 0 {
		g.game_over = true
		g.status = if in_check {
			if side == engine.white_color {
				'Checkmate. Black wins.'
			} else {
				'Checkmate. White wins.'
			}
		} else {
			'Stalemate.'
		}
		g.pgn_result = pgn_result_from_status(g.status)
		g.hover_moves = []engine.Move{}
		return
	}
	g.game_over = false
	g.pgn_result = '*'
	side_name := if g.pos.white_to_move { 'White' } else { 'Black' }
	g.status = if in_check { '${side_name} to move, check.' } else { '${side_name} to move.' }
}

fn (mut g Game) draw() {
	if g.ai_thinking && g.pending_ai_move != engine.Move{} {
		g.apply_ai_move()
	}
	g.ctx.begin()
	g.draw_board()
	g.draw_panel()
	if g.ai_thinking {
		g.draw_thinking_indicator()
	}
	if g.pending_promotions.len > 0 {
		g.draw_promotion_overlay()
	}
	g.ctx.end()
}

fn (g &Game) draw_board() {
	for y := 0; y < 8; y++ {
		for x := 0; x < 8; x++ {
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
	for i := 0; i < 8; i++ {
		g.ctx.draw_text(board_padding + i * tile_size + tile_size / 2 - 6, top_height +
			board_padding + tile_size * 8 + 4, '${u8(`a` + i)}', color: gg.white)
		g.ctx.draw_text(4, top_height + board_padding + i * tile_size + tile_size / 2 - 8,
			'${8 - i}', color: gg.white)
	}
}

fn (g &Game) draw_panel() {
	panel_x := board_padding * 2 + 8 * tile_size
	g.ctx.draw_text(panel_x, 88, g.status, color: gg.white, size: 20)
	g.ctx.draw_text(panel_x, 145, 'White: you', color: gg.rgb(230, 230, 230), size: 18)
	g.ctx.draw_text(panel_x, 175, 'Black: AI', color: gg.rgb(200, 200, 200), size: 18)
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

fn (mut g Game) draw_thinking_indicator() {
	g.thinking_frame++
	dots := (g.thinking_frame / 15) % 4
	dots_str := '.'.repeat(dots)
	elapsed_ms := int(time.ticks() - g.ai_start_time)
	panel_x := board_padding * 2 + 8 * tile_size
	g.ctx.draw_text(panel_x, 88, 'Black is thinking${dots_str} (${elapsed_ms}ms)',
		color: gg.rgb(200, 200, 100)
		size:  20
	)
	if g.pending_ai_move != engine.Move{} && g.pending_ai_move != g.best_move_so_far {
		g.best_move_so_far = g.pending_ai_move
	}
	if g.best_move_so_far != engine.Move{} {
		move_str := engine.move_to_san(g.best_move_so_far, g.pos)
		g.ctx.draw_text(panel_x, 115, 'Best: ${move_str}',
			color: gg.rgb(180, 180, 180)
			size:  16
		)
	}
}

fn (mut g Game) record_pgn_move(mv engine.Move, pos_before engine.Position) {
	g.eng.move_history << mv
	move_str := engine.move_to_san(mv, pos_before)
	is_white := pos_before.white_to_move
	if is_white {
		g.pgn_moves << '${g.eng.fullmove_number}. ${move_str}'
	} else {
		g.pgn_moves << move_str
		g.eng.fullmove_number++
	}
}

fn (g &Game) pgn_text() string {
	now := time.now()
	date_tag := '${now.year:04}.${now.month:02}.${now.day:02}'
	mut text := '[Event "V Chess"]\n'
	text += '[Site "?"]\n'
	text += '[Date "${date_tag}"]\n'
	text += '[White "You"]\n'
	text += '[Black "AI"]\n'
	text += '[Result "${g.pgn_result}"]\n\n'
	mut movetext := g.pgn_moves.join(' ')
	if movetext.len > 0 {
		movetext += ' '
	}
	movetext += g.pgn_result
	text += movetext + '\n'
	return text
}

fn (mut g Game) write_pgn_file() {
	pgn_dir := os.join_path(os.vtmp_dir(), 'chess')
	os.mkdir_all(pgn_dir) or {
		eprintln('failed to create PGN directory ${pgn_dir}: ${err}')
		return
	}
	path := if g.game_over {
		g.final_pgn_output_path()
	} else {
		os.join_path(pgn_dir, 'gui_game__current.pgn')
	}
	os.write_file(path, g.pgn_text()) or { eprintln('failed to write PGN to ${path}: ${err}') }
}

fn (mut g Game) final_pgn_output_path() string {
	if g.pgn_output_path == '' {
		now := time.now()
		g.pgn_output_path = os.join_path(os.vtmp_dir(), 'chess', 'gui_game__${now.year:04}_${now.month:02}_${now.day:02}__${now.hour:02}_${now.minute:02}_${now.second:02}.pgn')
		println('Saved game file: ${g.pgn_output_path}')
	}
	return g.pgn_output_path
}

fn pgn_result_from_status(status string) string {
	return match true {
		status.contains('White wins') { '1-0' }
		status.contains('Black wins') { '0-1' }
		status.contains('Draw') || status.contains('Stalemate') { '1/2-1/2' }
		else { '*' }
	}
}

fn (mut g Game) draw_promotion_overlay() {
	g.ctx.draw_rect_filled(board_padding, top_height + board_padding, tile_size * 8, tile_size * 8,
		gg.rgba(10, 10, 10, 160))
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
