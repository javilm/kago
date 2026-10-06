tests\unkago\ - the test archives for UNKAGO, and where they come from.

What UNKAGO prints for each file here is compared, byte for byte, with
tests\expected.txt (see tests.bat). The lhasa archives are copies of
real archives made by the tools named. The names in the expected
listings were checked against lhasa 0.4.0's own listings; the copy of
lhasa this project keeps is reference\lhasa, at commit 75ed835.

What UNKAGO extracts from them lands in tests\out\ (see tests.bat).

multi0.lzh
    made for Tsuzura with LHa for Java (jlha-utils), level 0: README.TXT,
    A$B.TXT and EMPTY.DAT, stored (-lh0-)
    sha256 eb6851cca3aa3206cc055fe8aab6cd3bd703b665dc0e37f4f9c8d1a793c94303
multi1.lzh
    the same, level 1
    sha256 b59963643cd2dce8631c59adc0b9d0fcf79fd0d58b927b439652c817dcb4d593
multi2.lzh
    the same, level 2
    sha256 c784a944da9342979356651b39b561180f30a843e7c44d33f37254198a0a3b66
l0lh1.lzh
    lhasa test/archives/lharc113/lh1.lzh: LHarc 1.13, level 0, -lh1-
    sha256 594af58cb27d6a80e9bebd108cc82a8ab881a4b5549e4fc10379fbf7a0d83069
l0lh7.lzh
    lhasa test/archives/explzh_723/h0_lh7.lzh: Explzh 7.23, level 0, -lh7-
    sha256 f39c61e286f2eb274ff163f3bb730ac63a255ac05f770934835fc4a6ac163c58
l1lh5.lzh
    lhasa test/archives/lha213/lh5.lzh: LHA 2.13, level 1, -lh5-
    sha256 7f10d0be69536733217e984e4ff81d8980f2df06822581d7c006257bfad34851
l1lh6.lzh
    lhasa test/archives/explzh_723/h1_lh6.lzh: Explzh 7.23, level 1, -lh6-
    sha256 51f327c4b42d5a41b6c4632d527818d903d11826bbf15f2e2f44a3b8cfc9cd8c
l2lh5.lzh
    lhasa test/archives/lha_unix114i/h2_lh5.lzh: LHa for UNIX 1.14i, level 2,
    -lh5-
    sha256 67fa06a23f8b85373fff2a8bb3bfc13e3ab491b82c0c2933fa187305bd594ad6
l2lhx.lzh
    lhasa test/archives/unlha32/h2_lhx.lzh: UNLHA32, level 2, -lhx-
    sha256 c9ab661c5502714f9556be89617bddff237e0e21e72657dc019707aed9751d9b
l3lh5.lzh
    lhasa test/archives/lha_os2_208/h3_lh5.lzh: LHA 2.08 for OS/2, level 3
    sha256 d980d1ddc47323fc860b0fb7829d72ce26afbe1f3f59f89e52f0eda54f425212
badsum.lzh
    multi0.lzh with the second header's checksum byte XORed with 55h
    sha256 e1750bf8c79f93a7458d01a7d37f2acc36764d1ad7aedc55d9ee733c1ecca432
cuthead.lzh
    the first 74 bytes of multi1.lzh: it ends inside the second header
    sha256 0df0b28aaf41820b47d683ca573e276d522022415a11591ac5b9363d276800b3
cutdata.lzh
    the first 4000 bytes of l2lh5.lzh: it ends inside the member's data
    sha256 e649afa8294f60b12290618a370e5897ced14669a2d4ce669d4164a25fce6ecb
notlzh.txt
    a line of text: "This file is not an archive."
    sha256 e13d8a1c7222cbc9b05c972937419ecb387f954bb531b05d155948d891086cc4
empty.lzh
    an empty file, 0 bytes
    sha256 e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
l1lh0.lzh
    lhasa test/archives/lha213/lh0.lzh: LHA 2.13, level 1, stored: GPL-2.GZ
    sha256 f240fe79ebbcba82fa3fd10421a5a7678d0d2aa2ed374e0f79bb574a59bedbf1
big1.lzh
    made for Tsuzura: level 1, BIG.DAT, 20000 random bytes (Python's
    random, seed 2026), stored: more than copy_buffer holds
    sha256 9683e0f90ae9f8583fe321d739e557f37c1be462e80b6ccf07f9395a380ea7f9
date2.lzh
    made for Tsuzura: level 2, DATE2.DAT, stored, dated
    2001-02-03 04:05:06 UTC
    sha256 5d7eb457e36c1871c11931bc3f3f7b64641f3b1c7225569afc2dcfe7a6ede28c
readonly.lzh
    made for Tsuzura: level 0, READONLY.DAT, stored, with the
    attribute byte set to 21h (read-only, archive) and the checksum
    fixed to match
    sha256 63aac7d487368c36db274ee31d32af94731544fa47e3f5b8bbcffb4a911ad5ee
badcrc.lzh
    made for Tsuzura: level 0, BADCRC.DAT, stored, with one bit of
    the data flipped: the CRC no longer matches
    sha256 3585a04a6788fe4d3928a700e7f8fcf2d4e8a28d6c5af7e84d1da9b8210557b4
lie.lzh
    made for Tsuzura: level 0, stored. LIE.DAT's header says its
    original size is 1 byte, but it carries 16384 (55h each), so the
    free-space check passes and the disk fills while it is copied;
    then AFTER.DAT, 11 bytes, honest
    sha256 200b3f1b7be16b5c81ba99d208667f190cf26e87b9ac36d613e1585e61acbf93
pair.lzh
    made for Tsuzura: level 0, stored: BIG.DAT, the same 20000 bytes as
    big1.lzh's, then SMALL.DAT, 15 bytes. Too big for what is
    left of the RAM disk, unless only SMALL.DAT is asked for
    sha256 b8063e467d51afec2b2f56e86ec8b4ddf8e655254b04a1c020860f4831392bdd
jlh5.lzh
    made for Tsuzura with LHa for Java (jlha-utils), level 1, -lh5-:
    BIN.DAT, 40000 bytes of structured binary (Python's random, seed
    5), and MIX.DAT: gpl-2.gz's 6829 compressed bytes, then the first
    10000 bytes of the GPL text
    sha256 d689437f7019ebcd56e55a2572bb8c3cfb9e17cd66e09e846adebce6ad8007ac
lh5one.lzh
    made for Tsuzura by hand: level 0, -lh5-, ONE.DAT, the one byte
    "A": a block of 1 symbol whose three trees each hold a single
    symbol, so the byte takes no bits. lhasa tests it as correct
    sha256 681120c81407fcd3a48c8afdd53f81918ece22a6c750ef24cca74d4fb228e2e2
lh5zero.lzh
    made for Tsuzura by hand: level 0, -lh5-, ZERO.DAT, 0 bytes, no
    data. LHA itself stores an empty file as -lh0-
    sha256 b37204112c8620beac4a7095a0b3d055a1b5769f1d5bbb26dcd8a4898ba469bf
lh5bad.lzh
    lh5one.lzh's kind, BAD.DAT, but its literal tree's single symbol
    is 511, which does not exist: the data is not valid. lhasa reports
    a CRC error
    sha256 b78a50192a11c552b0a0224179ce1544ed424f559b05e514755bb87cdf013cbe
long.lzh
    lhasa test/archives/lha213/lh5_long.lzh: LHA 2.13, level 1, -lh5-,
    LONG.TXT, 1241658 bytes of very repetitive text packed into 84000:
    for SPEED.BAT, which times extracting it, not for TESTS.BAT
    sha256 8bc9c2c20bf12d0fa50a8ffbfae5e2fc7af88f63fc3be894fa2aff633db37877
l0lh4.lzh
    lhasa test/archives/lha_amiga_122/lh4.lzh: LHA for Amiga 1.22,
    level 0, -lh4-: gpl-2
    sha256 287586d14f052cb1e128cc87f6277a3da6e88431369e65c815666a67718e065c
far6.lzh
    made for Tsuzura with LHa for UNIX 1.14i-ac20260723 (built from
    reference/lha-unix, commit 16619b0), lha -ao6, level 2, -lh6-:
    FAR.DAT, 86000 bytes of made-up text whose 5000-byte passages
    come back 20 to 60 KB later; matches reach 32750 bytes back
    sha256 237ad0dd13d9a8b31f6256afb773381463471416c1da0f78029d58aec3efcc0e
far7.lzh
    the same file, lha -ao7, -lh7-: matches reach 65367 bytes back
    sha256 b3398acd90a531c37a56925ab06e3d8a7d87184c3ea805b78a810731c08aa957
long7.lzh
    lhasa test/archives/lha_unix114i/lh7_long.lzh: LHa for UNIX
    1.14i, level 1, -lh7-, long.txt, the same 1241658 bytes as
    long.lzh's in 76620: for SPEED.BAT, not for TESTS.BAT
    sha256 37ffaebe08c9d8dcf8e9add232187bcdaa1313b13f7c22efe810b8bf883eaae5
tree.lzh
    made for Tsuzura with LHa for UNIX 1.14i-ac20260723, level 2: a
    tree with -lhd- members for TREE, TREE\EMPTY, TREE\SUB and
    TREE\SUB\DEEP, and A.TXT, SUB\B.TXT, SUB\DEEP\C.TXT, stored
    (-lh0-); directory dates 3 to 5 October 2026, 12:00 UTC
    sha256 9a6f1f7776eec97d52e8476b0a93ae12e0b4f1cebe950626737a2bddc72997c6
dirl0.lzh
    lhasa test/archives/lh2_222/subdir.lzh: LH 2.22, level 0, the path
    in the name with "\": subdir\SUBDIR2\HELLO.TXT
    sha256 8423e0d69258bffd28dc322ed6ebfb7b2ded44cf5c23d6438a726d16e5319d69
dirl1.lzh
    lhasa test/archives/lha213/subdir.lzh: LHA 2.13, level 1, the
    directories in an extended header: SUBDIR\SUBDIR2\HELLO.TXT
    sha256 10b776b9b34f1d0292ce8fcefee1e187ad812fa250b58e507b77679cda1e11f7
dirh0.lzh
    lhasa test/archives/explzh_723/h0_subdir.lzh: Explzh 7.23, level 0,
    -lhd- members for subdir and subdir\subdir2, then hello.txt
    sha256 1c2225eb7054a62cbb4dc23a14982261c82e2e7bc0e14077e8e16ad605d1dfec
dirh1.lzh
    lhasa test/archives/explzh_723/h1_subdir.lzh: the same, level 1
    sha256 ea8db6439e1b2bc06e6fff5cc795dbac0d51aa8d767738764c2887d9cd084f75
dirh2.lzh
    lhasa test/archives/explzh_723/h2_subdir.lzh: the same, level 2
    sha256 a06dbcc6bb6ee2a2196ec359a595987198399295af6239ce8c29080dbd00cfe0
paths.lzh
    made for Tsuzura by a Python script (note 013), level 0, stored:
    paths from the root, with a drive, with . and .., with "/" and
    doubled separators; a file CLASH and then CLASH\F.TXT; a hidden
    -lhd- member HID; and a path of more than 63 characters
    sha256 ae58067e5f42398b4e4e26ada13c5feb187000065ce8628cfbd135fb8c80895c
lfn.lzh
    made for Tsuzura by a Python script (note 014), level 0, stored:
    names that do not fit 8.3 (long, with a space, with "+", with two
    periods, with a leading period, with a 4-letter extension), one
    LONGFI~1.TXT stored as it is, a -lhd- member and two files in "Long
    Directory Name", and collision01.txt to collision11.txt
    sha256 aa9e32aca78bcba11f1d86ec1c42b6dfc773a0abb6333d81bc711d2d01a23d9b

The archives from lhasa are distributed under its licence:

ISC License

Copyright (c) 2011-2025, Simon Howard

Permission to use, copy, modify, and/or distribute this software
for any purpose with or without fee is hereby granted, provided
that the above copyright notice and this permission notice appear
in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL
WARRANTIES WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE
AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT, INDIRECT, OR
CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT,
NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN
CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
