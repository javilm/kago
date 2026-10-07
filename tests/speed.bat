rem SPEED.BAT - how long UNKAGO takes to extract LONG.LZH (84000 bytes
rem of -lh5- data), LONG7.LZH (76620 of -lh7-), ZLONG.ZIP (80331 of
rem deflate) and LONG1.LZH (110241 of -lh1-): the same 1241658 bytes
rem out; then P2LONG.PMA (85397 of -pm2-) and P1LONG.PMA (105071 of
rem -pm1-), lhasa's LONG.TXT, 1241659 bytes, into TESTS\OUT\P2LONG and
rem TESTS\OUT\P1LONG. Then how long KAGO takes to
rem pack GPL-2 (18092 bytes of text, from the UNKAGO tests),
rem BUILD\UNKAGO.COM and KIN\BIG.DAT (70000 bytes), each into its own
rem archive: LZH, then ZIP, then PMA, the last from each file's own
rem directory, as PMA has no directories. Run it from repo\, after BUILD
rem and TESTS.
rem TIME, before and after, goes to TESTS\SPEED.TXT, which is read on the
rem Mac. TESTS\ENTER.TXT answers TIME's question with Enter, which
rem keeps the clock as it is. The file lands in TESTS\OUT\SPEED.
time<tests\enter.txt>tests\speed.txt
build\unkago /O /Q /D:tests\out\speed tests\unkago\long.lzh>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\unkago /O /Q /D:tests\out\speed tests\unkago\long7.lzh>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\unkago /O /Q /D:tests\out\speed tests\unkago\zlong.zip>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\unkago /O /Q /D:tests\out\speed tests\unkago\long1.lzh>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\unkago /O /Q /D:tests\out\p2long tests\unkago\p2long.pma>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\unkago /O /Q /D:tests\out\p1long tests\unkago\p1long.pma>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
del tests\out\speed\kgpl.lzh
del tests\out\speed\kcom.lzh
del tests\out\speed\kbig.lzh
del tests\out\speed\kgpl.zip
del tests\out\speed\kcom.zip
del tests\out\speed\kbig.zip
del tests\out\speed\kgpl.pma
del tests\out\speed\kcom.pma
del tests\out\speed\kbig.pma
time<tests\enter.txt>>tests\speed.txt
build\kago /Q tests\out\speed\kgpl.lzh tests\out\gpl-2>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\kago /Q tests\out\speed\kcom.lzh build\unkago.com>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\kago /Q tests\out\speed\kbig.lzh tests\out\kin\big.dat>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\kago /Q tests\out\speed\kgpl.zip tests\out\gpl-2>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\kago /Q tests\out\speed\kcom.zip build\unkago.com>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
build\kago /Q tests\out\speed\kbig.zip tests\out\kin\big.dat>>tests\speed.txt
time<tests\enter.txt>>tests\speed.txt
cd tests\out
..\..\build\kago /Q speed\kgpl.pma gpl-2>>..\speed.txt
time<..\enter.txt>>..\speed.txt
cd ..\..\build
kago /Q ..\tests\out\speed\kcom.pma unkago.com>>..\tests\speed.txt
time<..\tests\enter.txt>>..\tests\speed.txt
cd ..\tests\out\kin
..\..\..\build\kago /Q ..\speed\kbig.pma big.dat>>..\..\speed.txt
time<..\..\enter.txt>>..\..\speed.txt
cd ..\..\..
