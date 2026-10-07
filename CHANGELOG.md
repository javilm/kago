# Changelog

All notable changes to KAGO and UNKAGO, newest first.

## v1.0.0 - unreleased

The first release.

**KAGO**, the compressor:

- Creates ZIP (deflate), LZH (`-lh5-`) and PMA (`-pm2-`) archives, storing
  any file that would not get smaller. The format comes from the archive's
  extension, or from `/F:ZIP`, `/F:LZH` or `/F:PMA`.
- Packs whole directory trees into ZIP and LZH archives, paths kept as typed
  without the drive; dates, times and attributes kept.
- Adds files to an existing archive, in all three formats, replacing those
  with the same path (`/A`).
- Stores without packing on request (`/0`).
- Uses the mapper memory that is free: packs with a smaller window, or
  stores, when there is not enough for full packing, after asking (`/Y`
  proceeds without asking).
- PMA archives as PMARC2 writes them, readable by PMEXT: directories and
  empty files are left out.

**UNKAGO**, the decompressor:

- Extracts ZIP (stored, deflate), LZH (`-lh0-`, `-lh1-`, `-lh4-` to
  `-lh7-`) and PMA (`-pm0-`, `-pm1-`, `-pm2-`) archives, self-extracting
  PMA files included, recognising the format by itself.
- Reads LZH headers of levels 0, 1 and 2, and ZIP archives whose sizes come
  after the data.
- Recreates directory trees, with their dates, and restores each file's
  date, time and attributes; checks every CRC.
- Shortens long filenames the VFAT way (`LONGFI~1.TXT`), the same names
  every time.
- Lists an archive (`/L`); extracts some members only, with `*` and `?`;
  extracts into another directory, created if missing (`/D:path`); replaces
  existing files only when asked (`/O`).
- Checks the disk space and the mapper memory before writing anything, and
  deletes a partly written file if the disk fills.

**Both:**

- Run under MSX-DOS2 or Nextor, with any memory mapper, from 128 KB.
- Show each file's progress as a percentage on the screen; print their
  banner first, unless `/Q` is given.
- Run on the MSX turbo R in Z80 and R800 mode. They do not use the R800's
  multiplication instructions: none of their multiplications is worth it.
