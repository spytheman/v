200 12 + . ." is the result of + " cr
200 12 - . ." is the result of - " cr
200 12 * . ." is the result of * " cr
200 12 / . ." is the result of / " cr
200 12 mod . ." is the result of mod " cr

: square dup * ;
: cube dup dup * * ;
." The square of 5 is: " 5 square . cr
." The cube of 5 is: " 5 cube . cr

: ?DAY dup 32 < IF  . ." looks like a valid month day " ELSE  . ." is not a valid month day " THEN cr ;
10 ?DAY
20 ?DAY
50 ?DAY

.s
10 20 .s
30 .s
* .s
* .s
cr
bye
