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

echo --- unkago /L tests\unkago\nosuch.lzh>>tests\results.txt
build\unkago /L tests\unkago\nosuch.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\multi0.lzh>>tests\results.txt
build\unkago /L tests\unkago\multi0.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\multi1.lzh>>tests\results.txt
build\unkago /L tests\unkago\multi1.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\multi2.lzh>>tests\results.txt
build\unkago /L tests\unkago\multi2.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l0lh1.lzh>>tests\results.txt
build\unkago /L tests\unkago\l0lh1.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l0lh7.lzh>>tests\results.txt
build\unkago /L tests\unkago\l0lh7.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l1lh5.lzh>>tests\results.txt
build\unkago /L tests\unkago\l1lh5.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l1lh6.lzh>>tests\results.txt
build\unkago /L tests\unkago\l1lh6.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l2lh5.lzh>>tests\results.txt
build\unkago /L tests\unkago\l2lh5.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l2lhx.lzh>>tests\results.txt
build\unkago /L tests\unkago\l2lhx.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l3lh5.lzh>>tests\results.txt
build\unkago /L tests\unkago\l3lh5.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\badsum.lzh>>tests\results.txt
build\unkago /L tests\unkago\badsum.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\cuthead.lzh>>tests\results.txt
build\unkago /L tests\unkago\cuthead.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\cutdata.lzh>>tests\results.txt
build\unkago /L tests\unkago\cutdata.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\notlzh.txt>>tests\results.txt
build\unkago /L tests\unkago\notlzh.txt>>tests\results.txt
echo --- unkago /L tests\unkago\empty.lzh>>tests\results.txt
build\unkago /L tests\unkago\empty.lzh>>tests\results.txt

rem EXTRACTING runs in TESTS\OUT, where the files are left for the
rem Mac to compare. READONLY.DAT is left read-only, so it is made
rem writable first, for /O to replace it.
echo === UNKAGO EXTRACTING>>tests\results.txt
attrib -r tests\out\readonly.dat
cd tests\out
echo --- unkago /O ..\unkago\multi0.lzh>>..\results.txt
..\..\build\unkago /O ..\unkago\multi0.lzh>>..\results.txt
echo --- unkago ..\unkago\multi0.lzh>>..\results.txt
..\..\build\unkago ..\unkago\multi0.lzh>>..\results.txt
echo --- unkago /O ..\unkago\l1lh0.lzh>>..\results.txt
..\..\build\unkago /O ..\unkago\l1lh0.lzh>>..\results.txt
echo --- unkago /O ..\unkago\big1.lzh>>..\results.txt
..\..\build\unkago /O ..\unkago\big1.lzh>>..\results.txt
echo --- unkago /O ..\unkago\date2.lzh>>..\results.txt
..\..\build\unkago /O ..\unkago\date2.lzh>>..\results.txt
echo --- unkago /O ..\unkago\readonly.lzh>>..\results.txt
..\..\build\unkago /O ..\unkago\readonly.lzh>>..\results.txt
echo --- unkago /O ..\unkago\badcrc.lzh>>..\results.txt
..\..\build\unkago /O ..\unkago\badcrc.lzh>>..\results.txt
echo --- unkago /O ..\unkago\l2lh5.lzh>>..\results.txt
..\..\build\unkago /O ..\unkago\l2lh5.lzh>>..\results.txt
echo --- unkago /O ..\unkago\cutdata.lzh>>..\results.txt
..\..\build\unkago /O ..\unkago\cutdata.lzh>>..\results.txt
echo --- del readonly.dat>>..\results.txt
del readonly.dat>>..\results.txt
cd ..\..
dir tests\out>tests\dates.txt

echo === MAPTEST>>tests\results.txt
echo --- maptest>>tests\results.txt
build\maptest>>tests\results.txt

echo === END OF RUN>>tests\results.txt
echo Done. The results are in TESTS\RESULTS.TXT.
