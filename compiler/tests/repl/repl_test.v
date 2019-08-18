import os

fn test_repl(){
	assert 0 == os.system('v run compiler/tests/repl/repl_test_runner.v')
}
