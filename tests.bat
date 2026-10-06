rem TESTS.BAT - run every tool's tests, and leave what they printed in
rem TESTS\RESULTS.TXT. The previous run is kept as TESTS\RESULTS.OLD.
rem Run it from repo\, where BUILD.BAT is: build, then tests.
rem
rem THE PROGRAMS ARE RUN BY PATH, from build\, so a stray KAGO.COM or
rem UNKAGO.COM elsewhere cannot be run in their place.
rem
rem TESTS\EXPECTED.TXT is what TESTS\RESULTS.TXT should hold. The two
rem are compared on the Mac, after the export, mechanically.
rem
rem NO SPACE BEFORE >>. Whatever is before it is part of the line, and
rem a trailing space in an ECHO would be one more byte to compare.

if exist tests\results.txt copy tests\results.txt tests\results.old
echo TSUZURA TEST RUN>tests\results.txt

echo === KAGO>>tests\results.txt
echo --- kago>>tests\results.txt
build\kago>>tests\results.txt
echo --- kago /f:zip archive.zip file.txt>>tests\results.txt
build\kago /f:zip archive.zip file.txt>>tests\results.txt
echo --- kago /Q /Y>>tests\results.txt
build\kago /Q /Y>>tests\results.txt
echo --- kago a/b>>tests\results.txt
build\kago a/b>>tests\results.txt
echo --- kago /?>>tests\results.txt
build\kago /?>>tests\results.txt
echo --- kago /v>>tests\results.txt
build\kago /v>>tests\results.txt
echo --- kago /V archive.lzh>>tests\results.txt
build\kago /V archive.lzh>>tests\results.txt
echo --- kago /V /?>>tests\results.txt
build\kago /V /?>>tests\results.txt
echo --- kago /X>>tests\results.txt
build\kago /X>>tests\results.txt
echo --- kago /L x.lzh>>tests\results.txt
build\kago /L x.lzh>>tests\results.txt
echo --- kago />>tests\results.txt
build\kago />>tests\results.txt
echo --- kago /V /X>>tests\results.txt
build\kago /V /X>>tests\results.txt

echo === UNKAGO>>tests\results.txt
echo --- unkago>>tests\results.txt
build\unkago>>tests\results.txt
echo --- unkago /D:B:\TEST x.lzh>>tests\results.txt
build\unkago /D:B:\TEST x.lzh>>tests\results.txt
echo --- unkago /l /q>>tests\results.txt
build\unkago /l /q>>tests\results.txt
echo --- unkago /?>>tests\results.txt
build\unkago /?>>tests\results.txt
echo --- unkago /V x.lzh>>tests\results.txt
build\unkago /V x.lzh>>tests\results.txt
echo --- unkago /F:LZH x.lzh>>tests\results.txt
build\unkago /F:LZH x.lzh>>tests\results.txt
echo --- unkago /Y>>tests\results.txt
build\unkago /Y>>tests\results.txt

echo === MAPTEST>>tests\results.txt
echo --- maptest>>tests\results.txt
build\maptest>>tests\results.txt

echo === END OF RUN>>tests\results.txt
echo Done. The results are in TESTS\RESULTS.TXT.
