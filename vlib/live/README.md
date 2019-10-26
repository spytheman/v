This module contains the code that will be embedded inside each app
compiled with -live.

The subfolder executable/ contains the part that will go into the main
executable, i.e. the live reloading checker logic.

The subfolder sharedlib/ contains the part that will go into the shared
library that will get reloaded. 

Note: the content of the files 
vlib/live/sharedlib/1_structs.v 
and 
vlib/live/executable/1_structs.v 
should be kept in sync.
