rem BUILD.BAT - assemble and link KAGO, UNKAGO and MAPTEST, with Tatara.

rem SILENCE IS SUCCESS. /Q prints nothing for a module that works and
rem errors print anyway. Between the === lines, only the three DIR
rem listings at the end should appear.

set TATARA=src\include

echo === Assembling...
tatara /q src\kago.as kago.tro
tatara /q src\unkago.as unkago.tro
tatara /q src\lzh.as lzh.tro
tatara /q src\crc.as crc.tro
tatara /q src\lh5.as lh5.tro
tatara /q src\common.as common.tro
tatara /q src\alloc.as alloc.tro
tatara /q src\maptest.as maptest.tro

rem DELETE THE TARGETS BEFORE THE LINK, so a link that fails leaves no
rem binary at all rather than the previous one.
rem
rem TANREN'S OUTPUT GOES TO THE .MAP FILES, its errors included. /M
rem lists every segment's base, size and end: the memory budget. So
rem a failed link prints nothing here, and the DIR listings below are
rem what tell: "File not found" means read that tool's .MAP file.

echo === Linking...
del build\kago.com
del build\unkago.com
del build\maptest.com
tanren /m /o:build\kago.com @kago.lnk > build\kago.map
tanren /m /o:build\unkago.com @unkago.lnk > build\unkago.map
tanren /m /o:build\maptest.com @maptest.lnk > build\maptest.map

echo === Cleaning up...
del *.tro

echo === The binaries
dir build\kago.com
dir build\unkago.com
dir build\maptest.com

echo === Done
