module main

import ftp

fn test_all() {
	mut fails := 0
	mut ftp := ftp.new()
	//ftp.debug()
	
	// ftp.rediris.org
	if ftp.connect('ftp.redhat.com') { 
		println("connected")
		assert true
		
		if ftp.login('ftp','ftp') {
			println('logged-in')
			assert true
			
			pwd := ftp.pwd()
			println('pwd: $pwd')
			assert true
			
			ftp.cd('/')
			
			data := ftp.dir() or {
				eprintln('cannot list folder')
				assert false
				return
			}	
			println(data)
			
			ftp.cd('/suse/linux/enterprise/11Server/en/SAT-TOOLS/SRPMS/')
			
			dir_list := ftp.dir() or {
				eprintln('cannot list folder')
				assert false
				return
			}
			println('$dir_list')
			assert true
			
			blob := ftp.get('katello-host-tools-3.3.5-8.sles11_4sat.src.rpm') or {
				eprintln("couldn't download it")
				assert false
				return
			}
			
			println('downloaded $blob.len bytes')
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
