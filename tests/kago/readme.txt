tests\kago\ - the test files for KAGO, and where they come from.

tests.bat extracts kin.lzh and edge.lzh with UNKAGO into tests\out\kin
and tests\out\edge, which gives their files the dates and attributes
below, then archives them with KAGO. What KAGO writes lands in
tests\out\ too, and is compared on the Mac with what the Python model in
the latest KAGO note (impl\025-kago-lh5.md, for now) writes.

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
      SUB\DEEP\    a directory 2026-10-07 10:00:04  hidden, empty
    The dates are the edges of KAGO's arithmetic: 1980, the first MS-DOS
    date; a 29 February; 2100, which is not a leap year; and the last
    even second that 32 bits of seconds since 1970 hold.
    sha256 f3e7311e0a58243b6a2f9da51d72eab40dfb8727fffef1cabe23f1958071cf86

edge.lzh
    made for Tsuzura by the script in impl\025-kago-lh5.md, level 0,
    every file stored (-lh0-). The -lh5- encoder's edge cases:
      ONE.DAT      3000 bytes  2026-10-08 12:00:00  "A" only: a code
                                                    table of one symbol
      HALF.DAT     8192 bytes  2026-10-08 12:00:02  bytes 0 to 127, 64
                                                    times: every code 7
                                                    bits long
      ALL.DAT     10240 bytes  2026-10-08 12:00:04  bytes 0 to 255, 40
                                                    times: no smaller
                                                    packed, so stored
    sha256 4472af40d755fe71314b4447c22ac3d83b3f801d93ffdc95265a599e69f626aa
