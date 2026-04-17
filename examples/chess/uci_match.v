module main

import engine
import os
import time

const default_games = 11
const default_base_time_ms = 60000
const default_increment_ms = 0
const default_max_plies = 240
const uci_start_timeout_ms = 3000
const uci_ready_timeout_ms = 3000

struct MatchConfig {
	old_path     string
	current_path string
	games        int
	base_time_ms int
	increment_ms int
	movetime_ms  int
	max_plies    int
}

struct GameClock {
mut:
	white_ms int
	black_ms int
}

struct UciProcess {
	label string
mut:
	process &os.Process
	outbuf  string
}

struct GameResult {
	winner        string
	reason        string
	plies         int
	current_color string
	moves         []string
	duration_ms   int
	current_ms    int
	old_ms        int
	current_moves int
	old_moves     int
}

struct MatchScore {
mut:
	current_wins int
	old_wins     int
	draws        int
}

fn main() {
	config := parse_args() or {
		eprintln(err.msg())
		print_usage()
		exit(1)
	}
	results := run_match(config) or {
		eprintln('match failed: ${err}')
		exit(1)
	}
	print_report(config, results)
}

fn parse_args() !MatchConfig {
	mut games := default_games
	mut base_time_ms := default_base_time_ms
	mut increment_ms := default_increment_ms
	mut movetime_ms := 0
	mut max_plies := default_max_plies
	mut positional := []string{}
	mut i := 1
	for i < os.args.len {
		arg := os.args[i]
		match arg {
			'-games' {
				i++
				if i >= os.args.len {
					return error('missing value for -games')
				}
				games = os.args[i].int()
			}
			'-base-time' {
				i++
				if i >= os.args.len {
					return error('missing value for -base-time')
				}
				base_time_ms = os.args[i].int()
			}
			'-inc' {
				i++
				if i >= os.args.len {
					return error('missing value for -inc')
				}
				increment_ms = os.args[i].int()
			}
			'-movetime' {
				i++
				if i >= os.args.len {
					return error('missing value for -movetime')
				}
				movetime_ms = os.args[i].int()
			}
			'-max-plies' {
				i++
				if i >= os.args.len {
					return error('missing value for -max-plies')
				}
				max_plies = os.args[i].int()
			}
			'-h', '--help' {
				return error('help requested')
			}
			else {
				positional << arg
			}
		}
		i++
	}
	if positional.len != 2 {
		return error('expected OLD_UCI_PATH and CURRENT_UCI_PATH')
	}
	if games <= 0 {
		return error('-games must be positive')
	}
	if base_time_ms <= 0 {
		return error('-base-time must be positive')
	}
	if increment_ms < 0 {
		return error('-inc must not be negative')
	}
	if movetime_ms < 0 {
		return error('-movetime must not be negative')
	}
	if max_plies <= 0 {
		return error('-max-plies must be positive')
	}
	return MatchConfig{
		old_path:     positional[0]
		current_path: positional[1]
		games:        games
		base_time_ms: base_time_ms
		increment_ms: increment_ms
		movetime_ms:  movetime_ms
		max_plies:    max_plies
	}
}

fn print_usage() {
	eprintln('Usage: ./uci_match OLD_UCI_PATH CURRENT_UCI_PATH [-games 11] [-base-time 60000] [-inc 0] [-movetime MS] [-max-plies 240]')
}

fn run_match(config MatchConfig) ![]GameResult {
	mut results := []GameResult{}
	for game_number := 1; game_number <= config.games; game_number++ {
		current_is_white := game_number % 2 == 1
		mut old_engine := start_uci(config.old_path, 'old')!
		mut current_engine := start_uci(config.current_path, 'current')!
		result := play_game(mut old_engine, mut current_engine, config, current_is_white)!
		results << result
		old_engine.close()
		current_engine.close()
		print_game_result(game_number, result)
	}
	return results
}

fn start_uci(path string, label string) !UciProcess {
	if !os.exists(path) {
		return error('${label} engine does not exist: ${path}')
	}
	mut process := os.new_process(path)
	process.set_redirect_stdio()
	process.run()
	if !process.is_alive() {
		return error('${label} engine failed to start: ${path}')
	}
	mut uci := UciProcess{
		label:   label
		process: process
	}
	uci.send('uci')
	uci.read_until_prefix('uciok', uci_start_timeout_ms)!
	uci.send('isready')
	uci.read_until_prefix('readyok', uci_ready_timeout_ms)!
	uci.send('ucinewgame')
	return uci
}

fn (mut u UciProcess) send(command string) {
	u.process.stdin_write(command + '\n')
}

fn (mut u UciProcess) read_line_timeout(timeout_ms int) !string {
	start := time.ticks()
	for time.ticks() - start <= timeout_ms {
		chunk := u.process.stdout_read()
		if chunk.len > 0 {
			u.outbuf += chunk
		}
		if idx := u.outbuf.index('\n') {
			line := u.outbuf[..idx].trim_right('\r')
			u.outbuf = u.outbuf[idx + 1..]
			return line
		}
		err_chunk := u.process.stderr_read()
		if err_chunk.len > 0 {
			eprintln('${u.label} stderr: ${err_chunk.trim_space()}')
		}
		time.sleep(5 * time.millisecond)
	}
	return error('${u.label} engine timed out after ${timeout_ms} ms')
}

fn (mut u UciProcess) read_until_prefix(prefix string, timeout_ms int) !string {
	start := time.ticks()
	for time.ticks() - start <= timeout_ms {
		line := u.read_line_timeout(timeout_ms - int(time.ticks() - start))!
		if line.starts_with(prefix) {
			return line
		}
	}
	return error('${u.label} engine did not send `${prefix}`')
}

fn (mut u UciProcess) bestmove(moves []string, config MatchConfig, clock GameClock) !string {
	position := if moves.len == 0 {
		'position startpos'
	} else {
		'position startpos moves ${moves.join(' ')}'
	}
	u.send(position)
	timeout_ms := if config.movetime_ms > 0 {
		u.send('go movetime ${config.movetime_ms}')
		config.movetime_ms
	} else {
		u.send('go wtime ${clock.white_ms} btime ${clock.black_ms} winc ${config.increment_ms} binc ${config.increment_ms}')
		if clock.white_ms > clock.black_ms { clock.white_ms } else { clock.black_ms }
	}
	line := u.read_until_prefix('bestmove ', timeout_ms + 5000)!
	fields := line.split(' ')
	if fields.len < 2 || fields[1] == '0000' {
		return error('${u.label} engine returned invalid bestmove line `${line}`')
	}
	return fields[1]
}

fn (mut u UciProcess) close() {
	if u.process.status == .running {
		u.send('quit')
		time.sleep(20 * time.millisecond)
		if u.process.is_alive() {
			u.process.signal_term()
			time.sleep(20 * time.millisecond)
		}
		if u.process.is_alive() {
			u.process.signal_kill()
		}
	}
	u.process.close()
}

fn play_game(mut old_engine UciProcess, mut current_engine UciProcess, config MatchConfig, current_is_white bool) !GameResult {
	game_start := time.ticks()
	mut adjudicator := engine.Engine{}
	mut pos := adjudicator.new_position()
	adjudicator.record_position(pos)
	mut moves := []string{}
	mut current_ms := 0
	mut old_ms := 0
	mut current_moves := 0
	mut old_moves := 0
	mut clock := GameClock{
		white_ms: config.base_time_ms
		black_ms: config.base_time_ms
	}
	current_color := if current_is_white { 'white' } else { 'black' }
	for ply := 0; ply < config.max_plies; ply++ {
		over, reason := adjudicator.is_game_over(pos)
		if over {
			clear_progress_line()
			return game_result_from_reason(reason, ply, current_color, current_is_white, moves,
				game_start, current_ms, old_ms, current_moves, old_moves)
		}
		side := if pos.white_to_move { engine.white_color } else { engine.black_color }
		current_to_move := (side == engine.white_color && current_is_white)
			|| (side == engine.black_color && !current_is_white)
		move_start := time.ticks()
		uci_move := if current_to_move {
			current_engine.bestmove(moves, config, clock)!
		} else {
			old_engine.bestmove(moves, config, clock)!
		}
		elapsed_ms := max_int(1, int(time.ticks() - move_start))
		if current_to_move {
			current_ms += elapsed_ms
			current_moves++
		} else {
			old_ms += elapsed_ms
			old_moves++
		}
		if config.movetime_ms == 0 {
			timeout_result := update_clock(mut clock, side, elapsed_ms, config.increment_ms,
				current_to_move, current_color, ply, moves, game_start, current_ms, old_ms,
				current_moves, old_moves)
			if timeout_result.winner != '' {
				clear_progress_line()
				return timeout_result
			}
		}
		legal_move := find_legal_uci_move(adjudicator, pos, side, uci_move) or {
			clear_progress_line()
			winner := if current_to_move { 'old' } else { 'current' }
			return GameResult{
				winner:        winner
				reason:        'Illegal move `${uci_move}` by ${if current_to_move {
					'current'
				} else {
					'old'
				}}.'
				plies:         ply
				current_color: current_color
				moves:         moves
				duration_ms:   int(time.ticks() - game_start)
				current_ms:    current_ms
				old_ms:        old_ms
				current_moves: current_moves
				old_moves:     old_moves
			}
		}
		engine.apply_move(mut pos, legal_move)
		adjudicator.record_position(pos)
		moves << uci_move
		print_progress(current_color, moves, game_start, current_ms, old_ms, current_moves,
			old_moves)
	}
	clear_progress_line()
	return GameResult{
		winner:        'draw'
		reason:        'Draw by max plies (${config.max_plies}).'
		plies:         config.max_plies
		current_color: current_color
		moves:         moves
		duration_ms:   int(time.ticks() - game_start)
		current_ms:    current_ms
		old_ms:        old_ms
		current_moves: current_moves
		old_moves:     old_moves
	}
}

fn update_clock(mut clock GameClock, side int, elapsed_ms int, increment_ms int, current_to_move bool, current_color string, ply int, moves []string, game_start i64, current_ms int, old_ms int, current_moves int, old_moves int) GameResult {
	if side == engine.white_color {
		clock.white_ms = clock.white_ms - elapsed_ms + increment_ms
		if clock.white_ms <= 0 {
			return GameResult{
				winner:        if current_to_move { 'old' } else { 'current' }
				reason:        'White lost on time.'
				plies:         ply + 1
				current_color: current_color
				moves:         moves
				duration_ms:   int(time.ticks() - game_start)
				current_ms:    current_ms
				old_ms:        old_ms
				current_moves: current_moves
				old_moves:     old_moves
			}
		}
	} else {
		clock.black_ms = clock.black_ms - elapsed_ms + increment_ms
		if clock.black_ms <= 0 {
			return GameResult{
				winner:        if current_to_move { 'old' } else { 'current' }
				reason:        'Black lost on time.'
				plies:         ply + 1
				current_color: current_color
				moves:         moves
				duration_ms:   int(time.ticks() - game_start)
				current_ms:    current_ms
				old_ms:        old_ms
				current_moves: current_moves
				old_moves:     old_moves
			}
		}
	}
	return GameResult{}
}

fn print_progress(current_color string, moves []string, game_start i64, current_ms int, old_ms int, current_moves int, old_moves int) {
	last_moves := last_n_moves(moves, 3)
	now := time.now().format_ss()
	elapsed := int(time.ticks() - game_start)
	current_avg := average_ms(current_ms, current_moves)
	old_avg := average_ms(old_ms, old_moves)
	print('\r${'':160s}\r')
	print('${now} current ${current_color:5s} ply ${moves.len:3d} elapsed ${format_ms(elapsed)} current avg ${current_avg:7.1f} ms old avg ${old_avg:7.1f} ms last3: ${last_moves}')
	flush_stdout()
}

fn clear_progress_line() {
	print('\r${'':160s}\r')
	flush_stdout()
}

fn last_n_moves(moves []string, n int) string {
	if moves.len == 0 {
		return '-'
	}
	start := if moves.len > n { moves.len - n } else { 0 }
	return moves[start..].join(' ')
}

fn average_ms(total_ms int, move_count int) f64 {
	if move_count == 0 {
		return 0.0
	}
	return f64(total_ms) / f64(move_count)
}

fn find_legal_uci_move(e engine.Engine, pos engine.Position, side int, uci string) ?engine.Move {
	for mv in e.legal_moves_for(pos, side) {
		if engine.move_to_uci(mv) == uci {
			return mv
		}
	}
	return none
}

fn game_result_from_reason(reason string, plies int, current_color string, current_is_white bool, moves []string, game_start i64, current_ms int, old_ms int, current_moves int, old_moves int) GameResult {
	winner := if reason.contains('White wins') {
		if current_is_white { 'current' } else { 'old' }
	} else if reason.contains('Black wins') {
		if current_is_white { 'old' } else { 'current' }
	} else {
		'draw'
	}
	return GameResult{
		winner:        winner
		reason:        reason
		plies:         plies
		current_color: current_color
		moves:         moves
		duration_ms:   int(time.ticks() - game_start)
		current_ms:    current_ms
		old_ms:        old_ms
		current_moves: current_moves
		old_moves:     old_moves
	}
}

fn print_game_result(game_number int, result GameResult) {
	move_text := if result.moves.len == 0 { '-' } else { result.moves.join(' ') }
	println('game ${game_number:2d}: current as ${result.current_color:5s} -> ${result.winner:7s} (${result.reason}, ${result.plies} plies)')
	println('  duration: ${format_ms(result.duration_ms)}, current avg: ${average_ms(result.current_ms,
		result.current_moves):.1f} ms/move (${result.current_moves} moves), old avg: ${average_ms(result.old_ms,
		result.old_moves):.1f} ms/move (${result.old_moves} moves)')
	println('  moves: ${move_text}')
}

fn print_report(config MatchConfig, results []GameResult) {
	mut score := MatchScore{}
	for result in results {
		match result.winner {
			'current' { score.current_wins++ }
			'old' { score.old_wins++ }
			else { score.draws++ }
		}
	}
	points := f64(score.current_wins) + f64(score.draws) * 0.5
	total := f64(results.len)
	println('')
	println('Match: current vs abe171f')
	println('Old UCI:     ${config.old_path}')
	println('Current UCI: ${config.current_path}')
	if config.movetime_ms > 0 {
		println('Games: ${results.len}, movetime: ${config.movetime_ms} ms, max plies: ${config.max_plies}')
	} else {
		println('Games: ${results.len}, base time: ${config.base_time_ms} ms, increment: ${config.increment_ms} ms, max plies: ${config.max_plies}')
	}
	println('Result: current ${score.current_wins} wins, old ${score.old_wins} wins, draws ${score.draws}')
	println('Score: current ${points:.1f}/${total:.1f}')
}

fn max_int(a int, b int) int {
	return if a > b { a } else { b }
}

fn format_ms(ms int) string {
	if ms < 1000 {
		return '${ms:4d}ms'
	}
	seconds := ms / 1000
	remainder := ms % 1000
	if seconds < 10 {
		return '${seconds}.${remainder / 100}s'
	}
	if seconds < 100 {
		return '${seconds:2d}.${remainder / 100}s'
	}
	if seconds < 6000 {
		return '${seconds / 60:2d}m${seconds % 60:02d}'
	}
	return '99m59+'
}
