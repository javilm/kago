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
rem
rem EVERY RUN HAS /Q, so the banner is printed only where a test asks
rem for it; the ECHO lines leave the /Q out. Without /Q the banner comes
rem first, before anything else: the BANNER section, at the end.

if exist tests\results.txt copy tests\results.txt tests\results.old
echo TSUZURA TEST RUN>tests\results.txt

echo === KAGO>>tests\results.txt
echo --- kago>>tests\results.txt
build\kago /Q>>tests\results.txt
echo --- kago /f:zip archive.zip file.txt>>tests\results.txt
build\kago /Q /f:zip archive.zip file.txt>>tests\results.txt
echo --- kago /Q /Y>>tests\results.txt
build\kago /Q /Y>>tests\results.txt
echo --- kago a/b>>tests\results.txt
build\kago /Q a/b>>tests\results.txt
echo --- kago /?>>tests\results.txt
build\kago /Q /?>>tests\results.txt
echo --- kago /v>>tests\results.txt
build\kago /Q /v>>tests\results.txt
echo --- kago /V archive.lzh>>tests\results.txt
build\kago /Q /V archive.lzh>>tests\results.txt
echo --- kago /V /?>>tests\results.txt
build\kago /Q /V /?>>tests\results.txt
echo --- kago /X>>tests\results.txt
build\kago /Q /X>>tests\results.txt
echo --- kago /L x.lzh>>tests\results.txt
build\kago /Q /L x.lzh>>tests\results.txt
echo --- kago />>tests\results.txt
build\kago /Q />>tests\results.txt
echo --- kago /V /X>>tests\results.txt
build\kago /Q /V /X>>tests\results.txt

echo === UNKAGO>>tests\results.txt
echo --- unkago>>tests\results.txt
build\unkago /Q>>tests\results.txt
echo --- unkago /D:B:\TEST x.lzh>>tests\results.txt
build\unkago /Q /D:B:\TEST x.lzh>>tests\results.txt
echo --- unkago /l /q>>tests\results.txt
build\unkago /l /q>>tests\results.txt
echo --- unkago /?>>tests\results.txt
build\unkago /Q /?>>tests\results.txt
echo --- unkago /V x.lzh>>tests\results.txt
build\unkago /Q /V x.lzh>>tests\results.txt
echo --- unkago /F:LZH x.lzh>>tests\results.txt
build\unkago /Q /F:LZH x.lzh>>tests\results.txt
echo --- unkago /Y>>tests\results.txt
build\unkago /Q /Y>>tests\results.txt

echo --- unkago /L tests\unkago\nosuch.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\nosuch.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\multi0.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\multi0.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\multi1.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\multi1.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\multi2.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\multi2.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l0lh1.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\l0lh1.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l0lh7.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\l0lh7.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l1lh5.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\l1lh5.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l1lh6.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\l1lh6.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l2lh5.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\l2lh5.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l2lhx.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\l2lhx.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\l3lh5.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\l3lh5.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\badsum.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\badsum.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\cuthead.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\cuthead.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\cutdata.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\cutdata.lzh>>tests\results.txt
echo --- unkago /L tests\unkago\notlzh.txt>>tests\results.txt
build\unkago /Q /L tests\unkago\notlzh.txt>>tests\results.txt
echo --- unkago /L tests\unkago\empty.lzh>>tests\results.txt
build\unkago /Q /L tests\unkago\empty.lzh>>tests\results.txt

rem EXTRACTING runs in TESTS\OUT, where the files are left for the
rem Mac to compare. READONLY.DAT is left read-only, so it is made
rem writable first, for /O to replace it.
echo === UNKAGO EXTRACTING>>tests\results.txt
attrib -r tests\out\readonly.dat
cd tests\out
echo --- unkago /O ..\unkago\multi0.lzh>>..\results.txt
..\..\build\unkago /Q /O ..\unkago\multi0.lzh>>..\results.txt
echo --- unkago ..\unkago\multi0.lzh>>..\results.txt
..\..\build\unkago /Q ..\unkago\multi0.lzh>>..\results.txt
echo --- unkago /O ..\unkago\l1lh0.lzh>>..\results.txt
..\..\build\unkago /Q /O ..\unkago\l1lh0.lzh>>..\results.txt
echo --- unkago /O ..\unkago\big1.lzh>>..\results.txt
..\..\build\unkago /Q /O ..\unkago\big1.lzh>>..\results.txt
echo --- unkago /O ..\unkago\date2.lzh>>..\results.txt
..\..\build\unkago /Q /O ..\unkago\date2.lzh>>..\results.txt
echo --- unkago /O ..\unkago\readonly.lzh>>..\results.txt
..\..\build\unkago /Q /O ..\unkago\readonly.lzh>>..\results.txt
echo --- unkago /O ..\unkago\badcrc.lzh>>..\results.txt
..\..\build\unkago /Q /O ..\unkago\badcrc.lzh>>..\results.txt
echo --- unkago /O ..\unkago\l2lh5.lzh>>..\results.txt
..\..\build\unkago /Q /O ..\unkago\l2lh5.lzh>>..\results.txt
echo --- unkago /O ..\unkago\cutdata.lzh>>..\results.txt
..\..\build\unkago /Q /O ..\unkago\cutdata.lzh>>..\results.txt
echo --- del readonly.dat>>..\results.txt
del readonly.dat>>..\results.txt
cd ..\..
dir tests\out>tests\dates.txt

rem DESTINATION AND SPACE uses a 16 KB RAM disk, H:, made here and
rem removed at the end: A RAM DISK ALREADY THERE IS LOST. What lands on
rem it is listed in TESTS\DATES.TXT, after TESTS\OUT.
echo === UNKAGO DESTINATION AND SPACE>>tests\results.txt
ramdisk 16 /d
echo --- unkago /O /D:tests\out\d1\d2 tests\unkago\l1lh0.lzh>>tests\results.txt
build\unkago /Q /O /D:tests\out\d1\d2 tests\unkago\l1lh0.lzh>>tests\results.txt
echo --- unkago /D: tests\unkago\multi0.lzh>>tests\results.txt
build\unkago /Q /D: tests\unkago\multi0.lzh>>tests\results.txt
echo --- unkago /D:H:\NO\DIR tests\unkago\big1.lzh>>tests\results.txt
build\unkago /Q /D:H:\NO\DIR tests\unkago\big1.lzh>>tests\results.txt
echo --- unkago /D:H:\NEW\SUB tests\unkago\multi0.lzh>>tests\results.txt
build\unkago /Q /D:H:\NEW\SUB tests\unkago\multi0.lzh>>tests\results.txt
echo --- unkago /D:H:\NEW\SUB tests\unkago\multi0.lzh>>tests\results.txt
build\unkago /Q /D:H:\NEW\SUB tests\unkago\multi0.lzh>>tests\results.txt
echo --- unkago /D:H: tests\unkago\lie.lzh>>tests\results.txt
build\unkago /Q /D:H: tests\unkago\lie.lzh>>tests\results.txt
echo --- unkago /D:H: tests\unkago\pair.lzh small.dat>>tests\results.txt
build\unkago /Q /D:H: tests\unkago\pair.lzh small.dat>>tests\results.txt
dir h:\>>tests\dates.txt
dir h:\new\sub>>tests\dates.txt
ramdisk 0 /d

rem MEMBERS runs in TESTS\OUT and extracts into TESTS\OUT\SEL:
rem members chosen by name, any case, with * and ?.
echo === UNKAGO MEMBERS>>tests\results.txt
cd tests\out
echo --- unkago /O /D:sel ..\unkago\multi0.lzh readme.txt>>..\results.txt
..\..\build\unkago /Q /O /D:sel ..\unkago\multi0.lzh readme.txt>>..\results.txt
echo --- unkago /D:sel ..\unkago\multi0.lzh nosuch.txt>>..\results.txt
..\..\build\unkago /Q /D:sel ..\unkago\multi0.lzh nosuch.txt>>..\results.txt
echo --- unkago /O /D:sel ..\unkago\multi0.lzh *.dat a?b.*>>..\results.txt
..\..\build\unkago /Q /O /D:sel ..\unkago\multi0.lzh *.dat a?b.*>>..\results.txt
echo --- unkago /D:sel ..\unkago\multi0.lzh empty.dat /O>>..\results.txt
..\..\build\unkago /Q /D:sel ..\unkago\multi0.lzh empty.dat /O>>..\results.txt
echo --- unkago /L ..\unkago\multi0.lzh *.txt>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\multi0.lzh *.txt>>..\results.txt
echo --- unkago /L ..\unkago\multi0.lzh *e*e*>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\multi0.lzh *e*e*>>..\results.txt
echo --- unkago /L ..\unkago\multi0.lzh x*>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\multi0.lzh x*>>..\results.txt
cd ..\..

rem LH5 runs in TESTS\OUT and extracts into TESTS\OUT\LH5.
echo === UNKAGO LH5>>tests\results.txt
cd tests\out
echo --- unkago /O /D:lh5 ..\unkago\l1lh5.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\l1lh5.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\l2lh5.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\l2lh5.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\jlh5.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\jlh5.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\lh5one.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\lh5one.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\lh5zero.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\lh5zero.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\lh5bad.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\lh5bad.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\l0lh4.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\l0lh4.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\far6.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\far6.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\far7.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh5 ..\unkago\far7.lzh>>..\results.txt
cd ..\..

rem LH1 runs in TESTS\OUT and extracts into TESTS\OUT\LH1: LHarc 1.13's
rem GPL-2 (L0LH1.LZH), then LH1.LZH, from LHa for UNIX: FAR.DAT, long
rem enough that the adaptive tree is rebuilt twice, BIN.DAT and BIG.DAT.
echo === UNKAGO LH1>>tests\results.txt
cd tests\out
echo --- unkago /O /D:lh1 ..\unkago\l0lh1.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh1 ..\unkago\l0lh1.lzh>>..\results.txt
echo --- unkago /L ..\unkago\lh1.lzh>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\lh1.lzh>>..\results.txt
echo --- unkago /O /D:lh1 ..\unkago\lh1.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lh1 ..\unkago\lh1.lzh>>..\results.txt
cd ..\..

rem PMA runs in TESTS\OUT and extracts into TESTS\OUT\PMA: PMA
rem archives listed, PMARC2's made for Tsuzura, PMarc2's and PMarc
rem 1.24's from lhasa, two self-extracting ones among them, their
rem extractor (-pms-) passed over. Then the stored (-pm0-), -pm2- and
rem -pm1- members extracted. PMARC2 wrote one match of BIN.PMA wrong,
rem so BIN.DAT is a CRC error, as with PMEXT.
echo === UNKAGO PMA>>tests\results.txt
cd tests\out
echo --- unkago /L ..\unkago\gpl-2no.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\gpl-2no.pma>>..\results.txt
echo --- unkago /L ..\unkago\gpl-2.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\gpl-2.pma>>..\results.txt
echo --- unkago /L ..\unkago\far.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\far.pma>>..\results.txt
echo --- unkago /L ..\unkago\bin.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\bin.pma>>..\results.txt
echo --- unkago /L ..\unkago\big.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\big.pma>>..\results.txt
echo --- unkago /L ..\unkago\pmext222.com>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\pmext222.com>>..\results.txt
echo --- unkago /L ..\unkago\p2pm0.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\p2pm0.pma>>..\results.txt
echo --- unkago /L ..\unkago\p2long.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\p2long.pma>>..\results.txt
echo --- unkago /L ..\unkago\p2comm.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\p2comm.pma>>..\results.txt
echo --- unkago /L ..\unkago\p2sfx.com>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\p2sfx.com>>..\results.txt
echo --- unkago /L ..\unkago\p1pm0.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\p1pm0.pma>>..\results.txt
echo --- unkago /L ..\unkago\p1pm1.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\p1pm1.pma>>..\results.txt
echo --- unkago /L ..\unkago\p1long.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\p1long.pma>>..\results.txt
echo --- unkago /L ..\unkago\mtcd.pma>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\mtcd.pma>>..\results.txt
echo --- unkago /O /D:pma ..\unkago\gpl-2no.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma ..\unkago\gpl-2no.pma>>..\results.txt
echo --- unkago /O /D:pma\p2 ..\unkago\p2pm0.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\p2 ..\unkago\p2pm0.pma>>..\results.txt
echo --- unkago /O /D:pma\p1 ..\unkago\p1pm0.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\p1 ..\unkago\p1pm0.pma>>..\results.txt
echo --- unkago /O /D:pma ..\unkago\pmext222.com>>..\results.txt
..\..\build\unkago /Q /O /D:pma ..\unkago\pmext222.com>>..\results.txt
echo --- unkago /O /D:pma\pm2 ..\unkago\gpl-2.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\pm2 ..\unkago\gpl-2.pma>>..\results.txt
echo --- unkago /O /D:pma\pm2 ..\unkago\far.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\pm2 ..\unkago\far.pma>>..\results.txt
echo --- unkago /O /D:pma\pm2 ..\unkago\big.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\pm2 ..\unkago\big.pma>>..\results.txt
echo --- unkago /O /D:pma\pm2 ..\unkago\bin.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\pm2 ..\unkago\bin.pma>>..\results.txt
echo --- unkago /O /D:pma\pm2 ..\unkago\p2comm.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\pm2 ..\unkago\p2comm.pma>>..\results.txt
echo --- unkago /O /D:pma\sfx ..\unkago\p2sfx.com>>..\results.txt
..\..\build\unkago /Q /O /D:pma\sfx ..\unkago\p2sfx.com>>..\results.txt
echo --- unkago /O /D:pma\p1 ..\unkago\p1pm1.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\p1 ..\unkago\p1pm1.pma>>..\results.txt
echo --- unkago /O /D:pma\mtcd ..\unkago\mtcd.pma>>..\results.txt
..\..\build\unkago /Q /O /D:pma\mtcd ..\unkago\mtcd.pma>>..\results.txt
cd ..\..

rem DIRECTORIES runs in TESTS\OUT and extracts into TESTS\OUT\DIRS,
rem PATHS and SEL2: trees from each header level, -lhd- members, paths
rem that are cleaned (from the root, with a drive, with . and ..), a
rem directory that cannot be made, and members chosen by directory.
rem What they hold, dates and the hidden HID included, goes into
rem TESTS\DATES.TXT.
echo === UNKAGO DIRECTORIES>>tests\results.txt
cd tests\out
echo --- unkago /L ..\unkago\tree.lzh>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\tree.lzh>>..\results.txt
echo --- unkago /O /D:dirs ..\unkago\tree.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:dirs ..\unkago\tree.lzh>>..\results.txt
echo --- unkago /D:dirs ..\unkago\tree.lzh>>..\results.txt
..\..\build\unkago /Q /D:dirs ..\unkago\tree.lzh>>..\results.txt
echo --- unkago /O /D:dirs\l0 ..\unkago\dirl0.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:dirs\l0 ..\unkago\dirl0.lzh>>..\results.txt
echo --- unkago /O /D:dirs\l1 ..\unkago\dirl1.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:dirs\l1 ..\unkago\dirl1.lzh>>..\results.txt
echo --- unkago /O /D:dirs\h0 ..\unkago\dirh0.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:dirs\h0 ..\unkago\dirh0.lzh>>..\results.txt
echo --- unkago /O /D:dirs\h1 ..\unkago\dirh1.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:dirs\h1 ..\unkago\dirh1.lzh>>..\results.txt
echo --- unkago /O /D:dirs\h2 ..\unkago\dirh2.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:dirs\h2 ..\unkago\dirh2.lzh>>..\results.txt
echo --- unkago /L ..\unkago\paths.lzh>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\paths.lzh>>..\results.txt
echo --- unkago /O /D:paths ..\unkago\paths.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:paths ..\unkago\paths.lzh>>..\results.txt
echo --- unkago /O /D:sel2 ..\unkago\tree.lzh tree\sub>>..\results.txt
..\..\build\unkago /Q /O /D:sel2 ..\unkago\tree.lzh tree\sub>>..\results.txt
echo --- unkago /L ..\unkago\tree.lzh *\deep>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\tree.lzh *\deep>>..\results.txt
cd ..\..
dir tests\out\dirs\tree>>tests\dates.txt
dir tests\out\dirs\tree\sub>>tests\dates.txt
dir tests\out\paths>>tests\dates.txt
dir /h tests\out\paths>>tests\dates.txt

rem LONG NAMES runs in TESTS\OUT and extracts into TESTS\OUT\LFN and
rem LSEL: names that do not fit 8.3, shortened the VFAT way, their ~N
rem from the archive alone, whichever members are asked for. What LFN
rem holds goes into TESTS\DATES.TXT.
echo === UNKAGO LONG NAMES>>tests\results.txt
cd tests\out
echo --- unkago /L ..\unkago\lfn.lzh>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\lfn.lzh>>..\results.txt
echo --- unkago /O /D:lfn ..\unkago\lfn.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:lfn ..\unkago\lfn.lzh>>..\results.txt
echo --- unkago /D:lfn ..\unkago\lfn.lzh>>..\results.txt
..\..\build\unkago /Q /D:lfn ..\unkago\lfn.lzh>>..\results.txt
echo --- unkago /O /D:lsel ..\unkago\lfn.lzh collision11.txt>>..\results.txt
..\..\build\unkago /Q /O /D:lsel ..\unkago\lfn.lzh collision11.txt>>..\results.txt
cd ..\..
dir tests\out\lfn>>tests\dates.txt
dir tests\out\lfn\longdi~1>>tests\dates.txt

rem ZIP runs in TESTS\OUT and extracts into TESTS\OUT\ZIP: listings of
rem ZIP archives, stored and deflate, with a comment, with UTF-8 names,
rem empty, and ZIP64; then their stored members extracted, a deflated
rem one skipped, an encrypted one refused, sizes after the data, and a
rem CRC error. RO.TXT is left read-only, so it is made writable first,
rem for /O to replace it. What ZIP holds, the hidden DOS.TXT included,
rem goes into TESTS\DATES.TXT.
echo === UNKAGO ZIP>>tests\results.txt
attrib -r tests\out\zip\ztree\ro.txt
cd tests\out
echo --- unkago /L ..\unkago\ztree.zip>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\ztree.zip>>..\results.txt
echo --- unkago /L ..\unkago\zdefl.zip>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\zdefl.zip>>..\results.txt
echo --- unkago /L ..\unkago\zcomm.zip>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\zcomm.zip>>..\results.txt
echo --- unkago /L ..\unkago\zutf8.zip>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\zutf8.zip>>..\results.txt
echo --- unkago /L ..\unkago\zempty.zip>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\zempty.zip>>..\results.txt
echo --- unkago /L ..\unkago\z64.zip>>..\results.txt
..\..\build\unkago /Q /L ..\unkago\z64.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\ztree.zip>>..\results.txt
..\..\build\unkago /Q /O /D:zip ..\unkago\ztree.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zutf8.zip>>..\results.txt
..\..\build\unkago /Q /O /D:zip ..\unkago\zutf8.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zdefl.zip>>..\results.txt
..\..\build\unkago /Q /O /D:zip ..\unkago\zdefl.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zenc.zip>>..\results.txt
..\..\build\unkago /Q /O /D:zip ..\unkago\zenc.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zdesc.zip>>..\results.txt
..\..\build\unkago /Q /O /D:zip ..\unkago\zdesc.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zbadcrc.zip>>..\results.txt
..\..\build\unkago /Q /O /D:zip ..\unkago\zbadcrc.zip>>..\results.txt
echo --- unkago /D:zip ..\unkago\zempty.zip>>..\results.txt
..\..\build\unkago /Q /D:zip ..\unkago\zempty.zip>>..\results.txt
echo --- unkago /D:zip ..\unkago\z64.zip>>..\results.txt
..\..\build\unkago /Q /D:zip ..\unkago\z64.zip>>..\results.txt
cd ..\..
dir tests\out\zip\ztree>>tests\dates.txt
dir /h tests\out\zip>>tests\dates.txt

rem INFLATE runs in TESTS\OUT and extracts into TESTS\OUT\INFL:
rem deflate's fixed and stored blocks, an empty stored block between
rem two fixed ones, a match 32000 bytes back, and dynamic blocks.
echo === UNKAGO INFLATE>>tests\results.txt
cd tests\out
echo --- unkago /O /D:infl ..\unkago\zfixed.zip>>..\results.txt
..\..\build\unkago /Q /O /D:infl ..\unkago\zfixed.zip>>..\results.txt
echo --- unkago /O /D:infl ..\unkago\zstore.zip>>..\results.txt
..\..\build\unkago /Q /O /D:infl ..\unkago\zstore.zip>>..\results.txt
echo --- unkago /O /D:infl ..\unkago\zflush.zip>>..\results.txt
..\..\build\unkago /Q /O /D:infl ..\unkago\zflush.zip>>..\results.txt
echo --- unkago /O /D:infl ..\unkago\zdyn.zip>>..\results.txt
..\..\build\unkago /Q /O /D:infl ..\unkago\zdyn.zip>>..\results.txt
cd ..\..

rem KAGO ARCHIVING runs in TESTS\OUT. UNKAGO extracts KIN.LZH into
rem KIN, which gives its files and directories fixed dates and
rem attributes; KAGO archives the tree into K1.LZH, stored (/0), which
rem UNKAGO lists, then extracts into KOUT for the Mac to compare. Then
rem the refusals, a format the switch chooses, a directory named, files
rem named twice, /A adding to K5.LZH and Z5.ZIP, and to copies of
rem ZDESC.ZIP (a data descriptor) and ZCOMM.ZIP (comments, in
rem TESTS\OUT\ZIP), and an archive among the files it is made of, made
rem and then added to. The same tree goes into Z1.ZIP, KIN\BIG.DAT
rem deflated, which UNKAGO lists and extracts into ZOUT, and KIN\SUB
rem into Z2.DAT, ZIP by the switch. KAGO never replaces an archive, so
rem its archives are deleted first. RO.TXT is left read-only, so it is
rem made writable first, for /O to replace it. What KOUT\KIN and
rem ZOUT\KIN hold goes into TESTS\DATES.TXT.
echo === KAGO ARCHIVING>>tests\results.txt
attrib -r tests\out\kin\ro.txt
attrib -r tests\out\kout\kin\ro.txt
attrib -r tests\out\zout\kin\ro.txt
cd tests\out
del k1.lzh
del k2.dat
del k3.lzh
del k4.lzh
del k5.lzh
del k6.lzh
del k5.$$$
del z5.zip
del zd.zip
del z1.zip
del z2.dat
echo --- unkago /O /D:kin ..\kago\kin.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:kin ..\kago\kin.lzh>>..\results.txt
echo --- kago /0 k1.lzh kin\*.*>>..\results.txt
..\..\build\kago /Q /0 k1.lzh kin\*.*>>..\results.txt
echo --- unkago /L k1.lzh>>..\results.txt
..\..\build\unkago /Q /L k1.lzh>>..\results.txt
echo --- unkago /O /D:kout k1.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:kout k1.lzh>>..\results.txt
echo --- kago k1.lzh kin\a.txt>>..\results.txt
..\..\build\kago /Q k1.lzh kin\a.txt>>..\results.txt
echo --- kago k2.lzh>>..\results.txt
..\..\build\kago /Q k2.lzh>>..\results.txt
echo --- kago k2.lzh nosuch.txt>>..\results.txt
..\..\build\kago /Q k2.lzh nosuch.txt>>..\results.txt
echo --- kago k2.lzh ..\kago\kin.lzh>>..\results.txt
..\..\build\kago /Q k2.lzh ..\kago\kin.lzh>>..\results.txt
echo --- unkago /L k2.lzh>>..\results.txt
..\..\build\unkago /Q /L k2.lzh>>..\results.txt
echo --- kago z1.zip kin\*.*>>..\results.txt
..\..\build\kago /Q z1.zip kin\*.*>>..\results.txt
echo --- unkago /L z1.zip>>..\results.txt
..\..\build\unkago /Q /L z1.zip>>..\results.txt
echo --- unkago /O /D:zout z1.zip>>..\results.txt
..\..\build\unkago /Q /O /D:zout z1.zip>>..\results.txt
echo --- kago /f:zip z2.dat kin\sub>>..\results.txt
..\..\build\kago /Q /f:zip z2.dat kin\sub>>..\results.txt
echo --- unkago /L z2.dat>>..\results.txt
..\..\build\unkago /Q /L z2.dat>>..\results.txt
echo --- kago k2.pma kin\a.txt>>..\results.txt
..\..\build\kago /Q k2.pma kin\a.txt>>..\results.txt
echo --- kago k2.txt kin\a.txt>>..\results.txt
..\..\build\kago /Q k2.txt kin\a.txt>>..\results.txt
echo --- kago /F:ABC k2.lzh kin\a.txt>>..\results.txt
..\..\build\kago /Q /F:ABC k2.lzh kin\a.txt>>..\results.txt
echo --- kago /f:lzh k2.dat .\kin\a.txt kin\.\ro.txt>>..\results.txt
..\..\build\kago /Q /f:lzh k2.dat .\kin\a.txt kin\.\ro.txt>>..\results.txt
echo --- unkago /L k2.dat>>..\results.txt
..\..\build\unkago /Q /L k2.dat>>..\results.txt
echo --- kago k3.lzh kin\sub>>..\results.txt
..\..\build\kago /Q k3.lzh kin\sub>>..\results.txt
echo --- unkago /L k3.lzh>>..\results.txt
..\..\build\unkago /Q /L k3.lzh>>..\results.txt
echo --- kago k4.lzh kin\a.txt kin\*.txt kin\sub\ kin\sub>>..\results.txt
..\..\build\kago /Q k4.lzh kin\a.txt kin\*.txt kin\sub\ kin\sub>>..\results.txt
echo --- unkago /L k4.lzh>>..\results.txt
..\..\build\unkago /Q /L k4.lzh>>..\results.txt
echo --- kago k5.lzh kin\a.txt kin\sub>>..\results.txt
..\..\build\kago /Q k5.lzh kin\a.txt kin\sub>>..\results.txt
echo --- kago /A k5.lzh kin\*.txt>>..\results.txt
..\..\build\kago /Q /A k5.lzh kin\*.txt>>..\results.txt
echo --- unkago /L k5.lzh>>..\results.txt
..\..\build\unkago /Q /L k5.lzh>>..\results.txt
echo --- kago /F:LZH k5.$$$ kin\a.txt>>..\results.txt
..\..\build\kago /Q /F:LZH k5.$$$ kin\a.txt>>..\results.txt
echo --- kago /A k5.lzh kin\ro.txt>>..\results.txt
..\..\build\kago /Q /A k5.lzh kin\ro.txt>>..\results.txt
del k5.$$$
echo --- kago /A k5.lzh nosuch.txt>>..\results.txt
..\..\build\kago /Q /A k5.lzh nosuch.txt>>..\results.txt
echo --- kago /A k6.lzh kin\a.txt>>..\results.txt
..\..\build\kago /Q /A k6.lzh kin\a.txt>>..\results.txt
echo --- kago /A /F:LZH z1.zip kin\a.txt>>..\results.txt
..\..\build\kago /Q /A /F:LZH z1.zip kin\a.txt>>..\results.txt
echo --- kago /A /F:ZIP k1.lzh kin\a.txt>>..\results.txt
..\..\build\kago /Q /A /F:ZIP k1.lzh kin\a.txt>>..\results.txt
echo --- kago z5.zip kin\a.txt kin\sub>>..\results.txt
..\..\build\kago /Q z5.zip kin\a.txt kin\sub>>..\results.txt
echo --- kago /A z5.zip kin\*.txt>>..\results.txt
..\..\build\kago /Q /A z5.zip kin\*.txt>>..\results.txt
echo --- unkago /L z5.zip>>..\results.txt
..\..\build\unkago /Q /L z5.zip>>..\results.txt
copy ..\unkago\zdesc.zip zd.zip
echo --- kago /A zd.zip kin\a.txt>>..\results.txt
..\..\build\kago /Q /A zd.zip kin\a.txt>>..\results.txt
echo --- unkago /L zd.zip>>..\results.txt
..\..\build\unkago /Q /L zd.zip>>..\results.txt
cd zip
del zc.zip
copy ..\..\unkago\zcomm.zip zc.zip
echo --- kago /A zc.zip ztree\a.txt>>..\..\results.txt
..\..\..\build\kago /Q /A zc.zip ztree\a.txt>>..\..\results.txt
echo --- unkago /L zc.zip>>..\..\results.txt
..\..\..\build\unkago /Q /L zc.zip>>..\..\results.txt
cd ..
echo --- kago kout\kin\self.lzh kout\kin\*.*>>..\results.txt
..\..\build\kago /Q kout\kin\self.lzh kout\kin\*.*>>..\results.txt
echo --- unkago /L kout\kin\self.lzh>>..\results.txt
..\..\build\unkago /Q /L kout\kin\self.lzh>>..\results.txt
echo --- kago /A kout\kin\self.lzh kout\kin\*.*>>..\results.txt
..\..\build\kago /Q /A kout\kin\self.lzh kout\kin\*.*>>..\results.txt
echo --- unkago /L kout\kin\self.lzh>>..\results.txt
..\..\build\unkago /Q /L kout\kin\self.lzh>>..\results.txt
del kout\kin\self.lzh
cd ..\..
dir /h tests\out\kout\kin>>tests\dates.txt
dir /h tests\out\kout\kin\sub>>tests\dates.txt
dir /h tests\out\zout\kin>>tests\dates.txt
dir /h tests\out\zout\kin\sub>>tests\dates.txt

rem KAGO PMA runs in TESTS\OUT\KIN, KIN's files as KAGO ARCHIVING
rem left them: they go into KP1.PMA, packed (-pm2-) or, when that does
rem not make them smaller, stored (-pm0-), but EMPTY.DAT,
rem as PMEXT cannot read an empty member, and SUB, as PMA has no
rem directories; UNKAGO lists it and extracts it into
rem PMOUT, for the Mac to compare. Then the refusals, a directory
rem named and a path with one, nothing written; and /A replacing
rem A.TXT in KP1.PMA, listed again. PMOUT goes into TESTS\DATES.TXT.
echo === KAGO PMA>>tests\results.txt
attrib -r tests\out\pmout\ro.txt
del tests\out\pmout\empty.dat
cd tests\out\kin
del ..\kp1.pma
del ..\kp2.pma
echo --- kago ..\kp1.pma *.*>>..\..\results.txt
..\..\..\build\kago /Q ..\kp1.pma *.*>>..\..\results.txt
echo --- unkago /L ..\kp1.pma>>..\..\results.txt
..\..\..\build\unkago /Q /L ..\kp1.pma>>..\..\results.txt
echo --- unkago /O /D:..\pmout ..\kp1.pma>>..\..\results.txt
..\..\..\build\unkago /Q /O /D:..\pmout ..\kp1.pma>>..\..\results.txt
echo --- kago ..\kp2.pma a.txt sub>>..\..\results.txt
..\..\..\build\kago /Q ..\kp2.pma a.txt sub>>..\..\results.txt
echo --- kago ..\kp2.pma sub\in.txt>>..\..\results.txt
..\..\..\build\kago /Q ..\kp2.pma sub\in.txt>>..\..\results.txt
echo --- kago /A ..\kp1.pma a.txt>>..\..\results.txt
..\..\..\build\kago /Q /A ..\kp1.pma a.txt>>..\..\results.txt
echo --- unkago /L ..\kp1.pma>>..\..\results.txt
..\..\..\build\unkago /Q /L ..\kp1.pma>>..\..\results.txt
cd ..\..\..
dir /h tests\out\pmout>>tests\dates.txt

rem KAGO PACKING runs in TESTS\OUT too. KIN's tree goes into K7.LZH,
rem packed: -lh5-, but for the files that do not get smaller, which are
rem stored. UNKAGO lists it, then extracts it into POUT for the Mac to
rem compare; then /A replaces KIN\A.TXT in it, which copies the -lh5-
rem member KIN\BIG.DAT as it is, and UNKAGO lists it again. EDGE.LZH
rem holds the encoders' edge cases, extracted into EDGE: one byte over
rem and over (ONE.DAT), runs of 128 and 256 different bytes (HALF.DAT,
rem ALL.DAT), noise, which does not get smaller (NOISE.DAT), and a short
rem text deflate sends with its fixed codes (FIXED.DAT). They go into
rem K8.LZH, listed and extracted into POUT too, into Z8.ZIP, deflate,
rem listed and extracted into ZPOUT, and into KP3.PMA, -pm2-, from inside
rem EDGE, as PMA has no directories, listed and extracted into PPOUT.
echo === KAGO PACKING>>tests\results.txt
attrib -r tests\out\pout\kin\ro.txt
cd tests\out
del k7.lzh
del k8.lzh
del z8.zip
del kp3.pma
echo --- kago k7.lzh kin\*.*>>..\results.txt
..\..\build\kago /Q k7.lzh kin\*.*>>..\results.txt
echo --- unkago /L k7.lzh>>..\results.txt
..\..\build\unkago /Q /L k7.lzh>>..\results.txt
echo --- unkago /O /D:pout k7.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:pout k7.lzh>>..\results.txt
echo --- kago /A k7.lzh kin\a.txt>>..\results.txt
..\..\build\kago /Q /A k7.lzh kin\a.txt>>..\results.txt
echo --- unkago /L k7.lzh>>..\results.txt
..\..\build\unkago /Q /L k7.lzh>>..\results.txt
echo --- unkago /O /D:edge ..\kago\edge.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:edge ..\kago\edge.lzh>>..\results.txt
echo --- kago k8.lzh edge\*.*>>..\results.txt
..\..\build\kago /Q k8.lzh edge\*.*>>..\results.txt
echo --- unkago /L k8.lzh>>..\results.txt
..\..\build\unkago /Q /L k8.lzh>>..\results.txt
echo --- unkago /O /D:pout k8.lzh>>..\results.txt
..\..\build\unkago /Q /O /D:pout k8.lzh>>..\results.txt
echo --- kago z8.zip edge\*.*>>..\results.txt
..\..\build\kago /Q z8.zip edge\*.*>>..\results.txt
echo --- unkago /L z8.zip>>..\results.txt
..\..\build\unkago /Q /L z8.zip>>..\results.txt
echo --- unkago /O /D:zpout z8.zip>>..\results.txt
..\..\build\unkago /Q /O /D:zpout z8.zip>>..\results.txt
cd edge
echo --- kago ..\kp3.pma *.*>>..\..\results.txt
..\..\..\build\kago /Q ..\kp3.pma *.*>>..\..\results.txt
cd ..
echo --- unkago /L kp3.pma>>..\results.txt
..\..\build\unkago /Q /L kp3.pma>>..\results.txt
echo --- unkago /O /D:ppout kp3.pma>>..\results.txt
..\..\build\unkago /Q /O /D:ppout kp3.pma>>..\results.txt
cd ..\..

rem MEMORY takes mapper memory with a RAM disk, and asks for more. On a
rem plain FS-A1GT (512 KB, about 336 KB free), a 272 KB RAM disk leaves
rem about 64 KB: too little for ZIP's full packing (80 KB, one segment
rem more for its central directory), and /Y deflates KIN\BIG.DAT small,
rem a 4 KB window, into MEM\M3.ZIP. A 288 KB one leaves about 48 KB:
rem too little for KAGO's full packing of LZH (64 KB). KAGO says so and
rem asks; N (TESTS\NO.TXT) stops it, and /Y packs KIN\BIG.DAT small
rem into MEM\M1.LZH. For ZIP that is too little even for small, and Y
rem (TESTS\YES.TXT) stores it, into MEM\M4.ZIP. A 304 KB one leaves
rem about 32 KB, and Y stores KIN\BIG.DAT into MEM\M2.LZH. A 320 KB
rem one leaves too little for FAR7.LZH's 64 KB window, and UNKAGO must
rem refuse; with more memory it extracts. The results go to
rem TESTS\MEMORY.TXT, read on the Mac, not compared, since they depend
rem on the machine; the archives in MEM are compared with the model.
ramdisk 272 /d>tests\memory.txt
ramdisk>>tests\memory.txt
cd tests\out
del mem\m1.lzh
del mem\m2.lzh
del mem\m3.zip
del mem\m4.zip
..\..\build\kago /Q /Y mem\m3.zip kin\big.dat>>..\memory.txt
..\..\build\unkago /Q /L mem\m3.zip>>..\memory.txt
ramdisk 0 /d
ramdisk 288 /d>>..\memory.txt
ramdisk>>..\memory.txt
..\..\build\kago /Q mem\m1.lzh kin\big.dat<..\no.txt>>..\memory.txt
..\..\build\kago /Q /Y mem\m1.lzh kin\big.dat>>..\memory.txt
..\..\build\unkago /Q /L mem\m1.lzh>>..\memory.txt
..\..\build\kago /Q mem\m4.zip kin\big.dat<..\yes.txt>>..\memory.txt
..\..\build\unkago /Q /L mem\m4.zip>>..\memory.txt
ramdisk 0 /d
ramdisk 304 /d>>..\memory.txt
ramdisk>>..\memory.txt
..\..\build\kago /Q mem\m2.lzh kin\big.dat<..\yes.txt>>..\memory.txt
..\..\build\unkago /Q /L mem\m2.lzh>>..\memory.txt
ramdisk 0 /d
cd ..\..
ramdisk 320 /d>>tests\memory.txt
ramdisk>>tests\memory.txt
build\unkago /Q /D:tests\out\mem tests\unkago\far7.lzh>>tests\memory.txt
ramdisk 0 /d

echo === BANNER>>tests\results.txt
rem Without /Q, the banner and a blank line before anything else: /V,
rem /V with /Q, a bad switch (COMMAND2's line after the banner), adding
rem A.TXT into KB.LZH, listing KP1.PMA, extracting KB.LZH into BOUT, and
rem the usage.
cd tests\out\kin
del ..\kb.lzh
echo --- kago /V>>..\..\results.txt
..\..\..\build\kago /V>>..\..\results.txt
echo --- kago /Q /V>>..\..\results.txt
..\..\..\build\kago /Q /V>>..\..\results.txt
echo --- kago /X>>..\..\results.txt
..\..\..\build\kago /X>>..\..\results.txt
echo --- kago ..\kb.lzh a.txt>>..\..\results.txt
..\..\..\build\kago ..\kb.lzh a.txt>>..\..\results.txt
cd ..
echo --- unkago /L kp1.pma>>..\results.txt
..\..\build\unkago /L kp1.pma>>..\results.txt
echo --- unkago /O /D:bout kb.lzh>>..\results.txt
..\..\build\unkago /O /D:bout kb.lzh>>..\results.txt
echo --- unkago>>..\results.txt
..\..\build\unkago>>..\results.txt
cd ..\..

echo === MAPTEST>>tests\results.txt
echo --- maptest>>tests\results.txt
build\maptest>>tests\results.txt

echo === END OF RUN>>tests\results.txt
echo Done. The results are in TESTS\RESULTS.TXT.
