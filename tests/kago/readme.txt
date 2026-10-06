tests\kago\ - the test files for KAGO, and where they come from.

tests.bat extracts kin.lzh with UNKAGO into tests\out\kin, which gives
its files the dates and attributes below, then archives them with KAGO.
What KAGO writes lands in tests\out\ too, and is compared on the Mac
with what the Python model in impl\019-kago-lzh.md writes.

kin.lzh
    made for Tsuzura by the script in impl\019-kago-lzh.md, level 0.
    BIG.DAT is -lh5-, its data compressed by LHa for UNIX 1.14i
    (reference\lha-unix); the rest is stored (-lh0-):
      A.TXT          18 bytes  2001-02-03 04:05:06
      BIG.DAT     70000 bytes  1980-01-01 00:00:00
      EMPTY.DAT       0 bytes  2024-02-29 12:34:56
      RO.TXT         12 bytes  2100-03-01 00:00:00  read-only
      HID.TXT         9 bytes  2106-02-07 06:28:14  hidden
      A$B.TXT        23 bytes  2099-12-31 23:59:58
      SUB\         a directory 2026-10-07 10:00:00
      SUB\IN.TXT     13 bytes  2026-10-07 10:00:02
    The dates are the edges of KAGO's arithmetic: 1980, the first MS-DOS
    date; a 29 February; 2100, which is not a leap year; and the last
    even second that 32 bits of seconds since 1970 hold.
    sha256 fcd4fc3b1927fd8a9f51197faa433a359467d98771ccc8f2ef18c65ef23628a4
