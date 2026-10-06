rem PROGRESS.BAT - for watching, not comparing: UNKAGO's and KAGO's
rem progress lines on the screen, which TESTS.BAT cannot capture. Run it
rem from repo\, after BUILD and TESTS. What they should show is in
rem impl\009-progress.md and impl\019-kago-lzh.md. KAGO never replaces
rem an archive, so KP.LZH and KQ.LZH are deleted first.
build\unkago /O /D:tests\out tests\unkago\big1.lzh
build\unkago /O /Q /D:tests\out tests\unkago\big1.lzh
build\unkago /O /D:tests\out tests\unkago\multi0.lzh
build\unkago /O /D:tests\out tests\unkago\badcrc.lzh
del tests\out\kp.lzh
build\kago tests\out\kp.lzh tests\out\kin\big.dat
del tests\out\kq.lzh
build\kago /Q tests\out\kq.lzh tests\out\kin\big.dat
