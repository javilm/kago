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

rem DESTINATION AND SPACE uses a 16 KB RAM disk, H:, made here and
rem removed at the end: A RAM DISK ALREADY THERE IS LOST. What lands on
rem it is listed in TESTS\DATES.TXT, after TESTS\OUT.
echo === UNKAGO DESTINATION AND SPACE>>tests\results.txt
ramdisk 16 /d
echo --- unkago /O /D:tests\out\d1\d2 tests\unkago\l1lh0.lzh>>tests\results.txt
build\unkago /O /D:tests\out\d1\d2 tests\unkago\l1lh0.lzh>>tests\results.txt
echo --- unkago /D: tests\unkago\multi0.lzh>>tests\results.txt
build\unkago /D: tests\unkago\multi0.lzh>>tests\results.txt
echo --- unkago /D:H:\NO\DIR tests\unkago\big1.lzh>>tests\results.txt
build\unkago /D:H:\NO\DIR tests\unkago\big1.lzh>>tests\results.txt
echo --- unkago /D:H:\NEW\SUB tests\unkago\multi0.lzh>>tests\results.txt
build\unkago /D:H:\NEW\SUB tests\unkago\multi0.lzh>>tests\results.txt
echo --- unkago /D:H:\NEW\SUB tests\unkago\multi0.lzh>>tests\results.txt
build\unkago /D:H:\NEW\SUB tests\unkago\multi0.lzh>>tests\results.txt
echo --- unkago /D:H: tests\unkago\lie.lzh>>tests\results.txt
build\unkago /D:H: tests\unkago\lie.lzh>>tests\results.txt
echo --- unkago /D:H: tests\unkago\pair.lzh small.dat>>tests\results.txt
build\unkago /D:H: tests\unkago\pair.lzh small.dat>>tests\results.txt
dir h:\>>tests\dates.txt
dir h:\new\sub>>tests\dates.txt
ramdisk 0 /d

rem MEMBERS runs in TESTS\OUT and extracts into TESTS\OUT\SEL:
rem members chosen by name, any case, with * and ?.
echo === UNKAGO MEMBERS>>tests\results.txt
cd tests\out
echo --- unkago /O /D:sel ..\unkago\multi0.lzh readme.txt>>..\results.txt
..\..\build\unkago /O /D:sel ..\unkago\multi0.lzh readme.txt>>..\results.txt
echo --- unkago /D:sel ..\unkago\multi0.lzh nosuch.txt>>..\results.txt
..\..\build\unkago /D:sel ..\unkago\multi0.lzh nosuch.txt>>..\results.txt
echo --- unkago /O /D:sel ..\unkago\multi0.lzh *.dat a?b.*>>..\results.txt
..\..\build\unkago /O /D:sel ..\unkago\multi0.lzh *.dat a?b.*>>..\results.txt
echo --- unkago /D:sel ..\unkago\multi0.lzh empty.dat /O>>..\results.txt
..\..\build\unkago /D:sel ..\unkago\multi0.lzh empty.dat /O>>..\results.txt
echo --- unkago /L ..\unkago\multi0.lzh *.txt>>..\results.txt
..\..\build\unkago /L ..\unkago\multi0.lzh *.txt>>..\results.txt
echo --- unkago /L ..\unkago\multi0.lzh *e*e*>>..\results.txt
..\..\build\unkago /L ..\unkago\multi0.lzh *e*e*>>..\results.txt
echo --- unkago /L ..\unkago\multi0.lzh x*>>..\results.txt
..\..\build\unkago /L ..\unkago\multi0.lzh x*>>..\results.txt
cd ..\..

rem LH5 runs in TESTS\OUT and extracts into TESTS\OUT\LH5.
echo === UNKAGO LH5>>tests\results.txt
cd tests\out
echo --- unkago /O /D:lh5 ..\unkago\l1lh5.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\l1lh5.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\l2lh5.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\l2lh5.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\jlh5.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\jlh5.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\lh5one.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\lh5one.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\lh5zero.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\lh5zero.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\lh5bad.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\lh5bad.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\l0lh4.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\l0lh4.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\far6.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\far6.lzh>>..\results.txt
echo --- unkago /O /D:lh5 ..\unkago\far7.lzh>>..\results.txt
..\..\build\unkago /O /D:lh5 ..\unkago\far7.lzh>>..\results.txt
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
..\..\build\unkago /L ..\unkago\tree.lzh>>..\results.txt
echo --- unkago /O /D:dirs ..\unkago\tree.lzh>>..\results.txt
..\..\build\unkago /O /D:dirs ..\unkago\tree.lzh>>..\results.txt
echo --- unkago /D:dirs ..\unkago\tree.lzh>>..\results.txt
..\..\build\unkago /D:dirs ..\unkago\tree.lzh>>..\results.txt
echo --- unkago /O /D:dirs\l0 ..\unkago\dirl0.lzh>>..\results.txt
..\..\build\unkago /O /D:dirs\l0 ..\unkago\dirl0.lzh>>..\results.txt
echo --- unkago /O /D:dirs\l1 ..\unkago\dirl1.lzh>>..\results.txt
..\..\build\unkago /O /D:dirs\l1 ..\unkago\dirl1.lzh>>..\results.txt
echo --- unkago /O /D:dirs\h0 ..\unkago\dirh0.lzh>>..\results.txt
..\..\build\unkago /O /D:dirs\h0 ..\unkago\dirh0.lzh>>..\results.txt
echo --- unkago /O /D:dirs\h1 ..\unkago\dirh1.lzh>>..\results.txt
..\..\build\unkago /O /D:dirs\h1 ..\unkago\dirh1.lzh>>..\results.txt
echo --- unkago /O /D:dirs\h2 ..\unkago\dirh2.lzh>>..\results.txt
..\..\build\unkago /O /D:dirs\h2 ..\unkago\dirh2.lzh>>..\results.txt
echo --- unkago /L ..\unkago\paths.lzh>>..\results.txt
..\..\build\unkago /L ..\unkago\paths.lzh>>..\results.txt
echo --- unkago /O /D:paths ..\unkago\paths.lzh>>..\results.txt
..\..\build\unkago /O /D:paths ..\unkago\paths.lzh>>..\results.txt
echo --- unkago /O /D:sel2 ..\unkago\tree.lzh tree\sub>>..\results.txt
..\..\build\unkago /O /D:sel2 ..\unkago\tree.lzh tree\sub>>..\results.txt
echo --- unkago /L ..\unkago\tree.lzh *\deep>>..\results.txt
..\..\build\unkago /L ..\unkago\tree.lzh *\deep>>..\results.txt
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
..\..\build\unkago /L ..\unkago\lfn.lzh>>..\results.txt
echo --- unkago /O /D:lfn ..\unkago\lfn.lzh>>..\results.txt
..\..\build\unkago /O /D:lfn ..\unkago\lfn.lzh>>..\results.txt
echo --- unkago /D:lfn ..\unkago\lfn.lzh>>..\results.txt
..\..\build\unkago /D:lfn ..\unkago\lfn.lzh>>..\results.txt
echo --- unkago /O /D:lsel ..\unkago\lfn.lzh collision11.txt>>..\results.txt
..\..\build\unkago /O /D:lsel ..\unkago\lfn.lzh collision11.txt>>..\results.txt
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
..\..\build\unkago /L ..\unkago\ztree.zip>>..\results.txt
echo --- unkago /L ..\unkago\zdefl.zip>>..\results.txt
..\..\build\unkago /L ..\unkago\zdefl.zip>>..\results.txt
echo --- unkago /L ..\unkago\zcomm.zip>>..\results.txt
..\..\build\unkago /L ..\unkago\zcomm.zip>>..\results.txt
echo --- unkago /L ..\unkago\zutf8.zip>>..\results.txt
..\..\build\unkago /L ..\unkago\zutf8.zip>>..\results.txt
echo --- unkago /L ..\unkago\zempty.zip>>..\results.txt
..\..\build\unkago /L ..\unkago\zempty.zip>>..\results.txt
echo --- unkago /L ..\unkago\z64.zip>>..\results.txt
..\..\build\unkago /L ..\unkago\z64.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\ztree.zip>>..\results.txt
..\..\build\unkago /O /D:zip ..\unkago\ztree.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zutf8.zip>>..\results.txt
..\..\build\unkago /O /D:zip ..\unkago\zutf8.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zdefl.zip>>..\results.txt
..\..\build\unkago /O /D:zip ..\unkago\zdefl.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zenc.zip>>..\results.txt
..\..\build\unkago /O /D:zip ..\unkago\zenc.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zdesc.zip>>..\results.txt
..\..\build\unkago /O /D:zip ..\unkago\zdesc.zip>>..\results.txt
echo --- unkago /O /D:zip ..\unkago\zbadcrc.zip>>..\results.txt
..\..\build\unkago /O /D:zip ..\unkago\zbadcrc.zip>>..\results.txt
echo --- unkago /D:zip ..\unkago\zempty.zip>>..\results.txt
..\..\build\unkago /D:zip ..\unkago\zempty.zip>>..\results.txt
echo --- unkago /D:zip ..\unkago\z64.zip>>..\results.txt
..\..\build\unkago /D:zip ..\unkago\z64.zip>>..\results.txt
cd ..\..
dir tests\out\zip\ztree>>tests\dates.txt
dir /h tests\out\zip>>tests\dates.txt

rem INFLATE runs in TESTS\OUT and extracts into TESTS\OUT\INFL:
rem deflate's fixed and stored blocks, an empty stored block between
rem two fixed ones, a match 32000 bytes back, and dynamic blocks.
echo === UNKAGO INFLATE>>tests\results.txt
cd tests\out
echo --- unkago /O /D:infl ..\unkago\zfixed.zip>>..\results.txt
..\..\build\unkago /O /D:infl ..\unkago\zfixed.zip>>..\results.txt
echo --- unkago /O /D:infl ..\unkago\zstore.zip>>..\results.txt
..\..\build\unkago /O /D:infl ..\unkago\zstore.zip>>..\results.txt
echo --- unkago /O /D:infl ..\unkago\zflush.zip>>..\results.txt
..\..\build\unkago /O /D:infl ..\unkago\zflush.zip>>..\results.txt
echo --- unkago /O /D:infl ..\unkago\zdyn.zip>>..\results.txt
..\..\build\unkago /O /D:infl ..\unkago\zdyn.zip>>..\results.txt
cd ..\..

rem KAGO ARCHIVING runs in TESTS\OUT. UNKAGO extracts KIN.LZH into
rem KIN, which gives its files and directories fixed dates and
rem attributes; KAGO archives the tree into K1.LZH, which UNKAGO lists,
rem then extracts into KOUT for the Mac to compare. Then the refusals, a
rem format the switch chooses, a directory named, and an archive among
rem the files it is made of. KAGO never replaces an archive, so its
rem archives are deleted first. RO.TXT is left read-only, so it is made
rem writable first, for /O to replace it. What KOUT\KIN holds goes into
rem TESTS\DATES.TXT.
echo === KAGO ARCHIVING>>tests\results.txt
attrib -r tests\out\kin\ro.txt
attrib -r tests\out\kout\kin\ro.txt
cd tests\out
del k1.lzh
del k2.dat
del k3.lzh
echo --- unkago /O /D:kin ..\kago\kin.lzh>>..\results.txt
..\..\build\unkago /O /D:kin ..\kago\kin.lzh>>..\results.txt
echo --- kago k1.lzh kin\*.*>>..\results.txt
..\..\build\kago k1.lzh kin\*.*>>..\results.txt
echo --- unkago /L k1.lzh>>..\results.txt
..\..\build\unkago /L k1.lzh>>..\results.txt
echo --- unkago /O /D:kout k1.lzh>>..\results.txt
..\..\build\unkago /O /D:kout k1.lzh>>..\results.txt
echo --- kago k1.lzh kin\a.txt>>..\results.txt
..\..\build\kago k1.lzh kin\a.txt>>..\results.txt
echo --- kago k2.lzh>>..\results.txt
..\..\build\kago k2.lzh>>..\results.txt
echo --- kago k2.lzh nosuch.txt>>..\results.txt
..\..\build\kago k2.lzh nosuch.txt>>..\results.txt
echo --- kago k2.lzh ..\kago\kin.lzh>>..\results.txt
..\..\build\kago k2.lzh ..\kago\kin.lzh>>..\results.txt
echo --- unkago /L k2.lzh>>..\results.txt
..\..\build\unkago /L k2.lzh>>..\results.txt
echo --- kago k2.zip kin\a.txt>>..\results.txt
..\..\build\kago k2.zip kin\a.txt>>..\results.txt
echo --- kago k2.pma kin\a.txt>>..\results.txt
..\..\build\kago k2.pma kin\a.txt>>..\results.txt
echo --- kago k2.txt kin\a.txt>>..\results.txt
..\..\build\kago k2.txt kin\a.txt>>..\results.txt
echo --- kago /F:ABC k2.lzh kin\a.txt>>..\results.txt
..\..\build\kago /F:ABC k2.lzh kin\a.txt>>..\results.txt
echo --- kago /f:lzh k2.dat .\kin\a.txt kin\.\ro.txt>>..\results.txt
..\..\build\kago /f:lzh k2.dat .\kin\a.txt kin\.\ro.txt>>..\results.txt
echo --- unkago /L k2.dat>>..\results.txt
..\..\build\unkago /L k2.dat>>..\results.txt
echo --- kago k3.lzh kin\sub>>..\results.txt
..\..\build\kago k3.lzh kin\sub>>..\results.txt
echo --- unkago /L k3.lzh>>..\results.txt
..\..\build\unkago /L k3.lzh>>..\results.txt
echo --- kago kout\kin\self.lzh kout\kin\*.*>>..\results.txt
..\..\build\kago kout\kin\self.lzh kout\kin\*.*>>..\results.txt
echo --- unkago /L kout\kin\self.lzh>>..\results.txt
..\..\build\unkago /L kout\kin\self.lzh>>..\results.txt
del kout\kin\self.lzh
cd ..\..
dir /h tests\out\kout\kin>>tests\dates.txt
dir /h tests\out\kout\kin\sub>>tests\dates.txt

rem MEMORY makes a 320 KB RAM disk, then asks for FAR7.LZH's 64 KB
rem window. On a plain FS-A1GT (512 KB, about 336 KB free) that leaves
rem too little, and UNKAGO must refuse; with more memory it extracts.
rem The result goes to TESTS\MEMORY.TXT, read on the Mac, not compared,
rem since it depends on the machine.
ramdisk 320 /d>tests\memory.txt
ramdisk>>tests\memory.txt
build\unkago /D:tests\out\mem tests\unkago\far7.lzh>>tests\memory.txt
ramdisk 0 /d

echo === MAPTEST>>tests\results.txt
echo --- maptest>>tests\results.txt
build\maptest>>tests\results.txt

echo === END OF RUN>>tests\results.txt
echo Done. The results are in TESTS\RESULTS.TXT.
