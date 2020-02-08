// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module pref

import (
	filepath
	os
)

pub const (
	default_module_path = os.home_dir() + '.vmodules'
)

pub fn (p mut Preferences) fill_with_defaults() {
	if p.vroot == '' {
		// Location of all vlib files
		p.vroot = filepath.dir(vexe_path())
	}
	if p.vlib_path == '' {
		p.vlib_path = filepath.join(p.vroot,'vlib')
	}
	if p.vpath == '' {
		p.vpath = default_module_path
	}
	if p.out_name == ''{
		rpath := os.realpath(p.path)
		base := filepath.filename(rpath)
		p.out_name = base.trim_space().all_before('.')

		if rpath == '$p.vroot/cmd/v' && os.is_dir('vlib/compiler') {
			// Building V? Use v2, since we can't overwrite a running
			// executable on Windows + the precompiled V is more
			// optimized.
			println('Saving the resulting V executable in `./v2`')
			println('Use `v -o v vlib/cmd/v` if you want to replace current ' + 'V executable.')
			p.out_name = 'v2'
		}
	}
	if p.os == ._auto {
		// No OS specifed? Use current system
		p.os = get_host_os()
	}
	if p.ccompiler == '' {
		p.ccompiler = default_c_compiler()
	}
}

fn default_c_compiler() string {
	// fast_clang := '/usr/local/Cellar/llvm/8.0.0/bin/clang'
	// if os.exists(fast_clang) {
	// return fast_clang
	// }
	// TODO fix $if after 'string'
	$if windows {
		return 'gcc'
	}
	return 'cc'
}

//TODO Remove code duplication
fn vexe_path() string {
	vexe := os.getenv('VEXE')
	if vexe != '' {
		return vexe
	}
	real_vexe_path := os.realpath(os.executable())
	os.setenv('VEXE', real_vexe_path, true)
	return real_vexe_path
}

pub fn get_host_os() OS {
	$if linux {
		return .linux
	}
	$if macos {
		return .mac
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
	$if solaris {
		return .solaris
	}
	$if haiku {
		return .haiku
	}
	panic('unknown host OS')
}
