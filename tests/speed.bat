rem SPEED.BAT - how long UNKAGO takes to extract LONG.LZH (84000 bytes
rem of -lh5- data) and LONG7.LZH (76620 of -lh7-): the same 1241658
rem bytes out. Run it from repo\, after BUILD.
rem TIME, before and after, goes to TESTS\SPEED.TXT, which is read on the
rem Mac. TESTS\ENTER.TXT answers TIME's question with Enter, which
rem keeps the clock as it is. The file lands in TESTS\OUT\SPEED.
time<tests\enter.txt>tests\speed.txt
build\unkago /O /Q /D:tests\out\speed tests\unkago\long.lzh>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\unkago /O /Q /D:tests\out\speed tests\unkago\long7.lzh>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
