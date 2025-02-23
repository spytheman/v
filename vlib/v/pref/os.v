// Copyright (c) 2019-2024 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module pref

import os

pub enum OS {
	_auto // Reserved so .macos cannot be misunderstood as auto
	ios
	macos
	linux
	windows
	freebsd
	openbsd
	netbsd
	dragonfly
	js_node
	js_browser
	js_freestanding
	android
	termux // like android, but compiling/running natively on the devices
	solaris
	qnx
	serenity
	plan9
	vinix
	haiku
	wasm32
	wasm32_emscripten
	wasm32_wasi
	browser // -b wasm -os browser
	wasi    // -b wasm -os wasi
	raw
	all
}

// Helper function to convert string names to OS enum
pub fn os_from_string(os_str string) !OS {
	lcased_os_str := os_str.to_lower_ascii()
	match lcased_os_str {
		'' {
			return ._auto
		}
		'linux' {
			return .linux
		}
		'nix' {
			return .linux
		}
		'windows' {
			return .windows
		}
		'ios' {
			return .ios
		}
		'macos' {
			return .macos
		}
		'darwin' {
			return .macos
		}
		'freebsd' {
			return .freebsd
		}
		'openbsd' {
			return .openbsd
		}
		'netbsd' {
			return .netbsd
		}
		'dragonfly' {
			return .dragonfly
		}
		'js', 'js_node' {
			return .js_node
		}
		'js_freestanding' {
			return .js_freestanding
		}
		'js_browser' {
			return .js_browser
		}
		'solaris' {
			return .solaris
		}
		'serenity' {
			return .serenity
		}
		'qnx' {
			return .qnx
		}
		'plan9' {
			return .plan9
		}
		'vinix' {
			return .vinix
		}
		'android' {
			return .android
		}
		'termux' {
			return .termux
		}
		'haiku' {
			return .haiku
		}
		'raw' {
			return .raw
		}
		// WASM options:
		'wasm32' {
			return .wasm32
		}
		'wasm32_wasi' {
			return .wasm32_wasi
		}
		'wasm32_emscripten' {
			return .wasm32_emscripten
		}
		// Native WASM options:
		'browser' {
			return .browser
		}
		'wasi' {
			return .wasi
		}
		else {
			return error('bad OS ${os_str}')
		}
	}
}

// lower returns the name that could be used with `-os osname`, for each OS enum value
// NOTE: it is important to not change the names here, they should match 1:1, since they
// are used as part of the cache keys, when -usecache is passed.
pub fn (o OS) lower() string {
	return match o {
		._auto { '' }
		.linux { 'linux' }
		.windows { 'windows' }
		.macos { 'macos' }
		.ios { 'ios' }
		.freebsd { 'freebsd' }
		.openbsd { 'openbsd' }
		.netbsd { 'netbsd' }
		.dragonfly { 'dragonfly' }
		.js_node { 'js' }
		.js_freestanding { 'js_freestanding' }
		.js_browser { 'js_browser' }
		.solaris { 'solaris' }
		.serenity { 'serenity' }
		.qnx { 'qnx' }
		.plan9 { 'plan9' }
		.vinix { 'vinix' }
		.android { 'android' }
		.termux { 'termux' }
		.haiku { 'haiku' }
		.raw { 'raw' }
		.wasm32 { 'wasm32' }
		.wasm32_wasi { 'wasm32_wasi' }
		.wasm32_emscripten { 'wasm32_emscripten' }
		.browser { 'browser' }
		.wasi { 'wasi' }
		.all { 'all' }
	}
}

pub fn (o OS) str() string {
	// TODO: check more thoroughly, why this method needs to exist at all,
	// and why should it override the default autogenerated .str() method,
	// instead of being named something like .label() ...
	// It seems to serve only display purposes on the surface, but it is used
	// internally by the compiler for comptime comparisons, which seems very
	// error prone. It bugged the interpretation of `$if wasm32_emscripten {` for example.
	match o {
		._auto { return 'RESERVED: AUTO' }
		.ios { return 'iOS' }
		.macos { return 'MacOS' }
		.linux { return 'Linux' }
		.windows { return 'Windows' }
		.freebsd { return 'FreeBSD' }
		.openbsd { return 'OpenBSD' }
		.netbsd { return 'NetBSD' }
		.dragonfly { return 'Dragonfly' }
		.js_node { return 'NodeJS' }
		.js_freestanding { return 'JavaScript' }
		.js_browser { return 'JavaScript(Browser)' }
		.android { return 'Android' }
		.termux { return 'Termux' }
		.solaris { return 'Solaris' }
		.qnx { return 'QNX' }
		.serenity { return 'SerenityOS' }
		.plan9 { return 'Plan9' }
		.vinix { return 'Vinix' }
		.haiku { return 'Haiku' }
		.wasm32 { return 'WebAssembly' }
		.wasm32_emscripten { return 'WebAssembly(Emscripten)' }
		.wasm32_wasi { return 'WebAssembly(WASI)' }
		.browser { return 'browser' }
		.wasi { return 'wasi' }
		.raw { return 'Raw' }
		.all { return 'all' }
	}
}

pub fn get_host_os() OS {
	if os.getenv('TERMUX_VERSION') != '' {
		return .termux
	}
	$if android {
		return .android
	}
	$if emscripten ? {
		return .wasm32_emscripten
	}
	$if wasm32_emscripten {
		return .wasm32_emscripten
	}
	$if linux {
		return .linux
	}
	$if ios {
		return .ios
	}
	$if macos {
		return .macos
	}
	$if windows {
		return .windows
	}
	$if freebsd {
		return .freebsd
	}
	$if openbsd {
		return .openbsd
	}
	$if netbsd {
		return .netbsd
	}
	$if dragonfly {
		return .dragonfly
	}
	$if serenity {
		return .serenity
	}
	//$if plan9 {
	//	return .plan9
	//}
	$if vinix {
		return .vinix
	}
	$if solaris {
		return .solaris
	}
	$if haiku {
		return .haiku
	}
	$if js_node {
		return .js_node
	}
	$if js_freestanding {
		return .js_freestanding
	}
	$if js_browser {
		return .js_browser
	}
	$if js {
		return .js_node
	}
	panic('unknown host OS')
	return ._auto
}
