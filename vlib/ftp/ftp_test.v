module main

import ftp

[if debug] fn debug_println(s string){	println(s) }

fn test_all() {
	mut fails := 0
	mut ftp := ftp.new()
	$if debug {
		ftp.debug()
	}
	
	// ftp.rediris.org
	if ftp.connect('ftp.redhat.com') { 
		debug_println('connected')
		assert true
		
		if ftp.login('ftp','ftp') {
			debug_println('logged-in')
			assert true
			
			pwd := ftp.pwd()
			debug_println('pwd: $pwd')
			assert true
			
			ftp.cd('/')
			
			data := ftp.dir() or {
				debug_println('cannot list folder')
				assert false
				return
			}	
			debug_println(data)
			
			ftp.cd('/suse/linux/enterprise/11Server/en/SAT-TOOLS/SRPMS/')
			
			dir_list := ftp.dir() or {
				debug_println('cannot list folder')
				assert false
				return
			}
			debug_println(dir_list)
			assert true
			
			blob := ftp.get('katello-host-tools-3.3.5-8.sles11_4sat.src.rpm') or {
				debug_println("couldn't download it")
				assert false
				return
			}
			
			debug_println('downloaded $blob.len bytes')
			assert blob.len == 55670
		}else{
			fails++
		}
		
		ftp.close()
	}else{
		fails++
	}
	assert fails == 0
}
