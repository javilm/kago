rem PROGRESS.BAT - for watching, not comparing: UNKAGO's progress line
rem on the screen, which TESTS.BAT cannot capture. Run it from repo\,
rem after BUILD. What it should show is in impl\009-progress.md.
build\unkago /O /D:tests\out tests\unkago\big1.lzh
build\unkago /O /Q /D:tests\out tests\unkago\big1.lzh
build\unkago /O /D:tests\out tests\unkago\multi0.lzh
build\unkago /O /D:tests\out tests\unkago\badcrc.lzh
