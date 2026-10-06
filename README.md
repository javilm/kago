# kago / unkago

**kago** and **unkago** are a pair of command-line tools for MSX-DOS2 that
create and extract archives: `KAGO` packs files and whole directory trees into
an LZH, PMA or ZIP archive, and `UNKAGO` unpacks them again. One pair of tools
handles all three formats. They are written entirely in Z80 assembler.

*Kago* is Japanese for "basket": something woven that you pack things into.

> **Status: in development.** Nothing here is usable yet. This file describes
> what the tools are being built to do.

## What they do

| Format | `KAGO` creates | `UNKAGO` extracts |
|---|---|---|
| LZH (`.lzh`, `.lha`) | `-lh5-` | `-lh0-`, `-lh1-`, `-lh4-`, `-lh5-`, `-lh6-`, `-lh7-` |
| PMA (`.pma`) | `-pm0-`, `-pm2-` | `-pm0-`, `-pm1-`, `-pm2-` |
| ZIP (`.zip`) | stored, deflate | stored, deflate |

`KAGO` is told which format to write with a command-line switch. `UNKAGO`
recognises the format of an archive by itself.

- **Whole directory trees**, packed and extracted, subdirectories included.
- **Large-window archives.** `UNKAGO` reads `-lh6-` and `-lh7-` archives
  (32 KB and 64 KB windows) made by LHA on modern computers, which the
  existing MSX extractors cannot open. It does this by keeping the window in
  mapped memory.
- **Long filenames** that do not fit MSX-DOS's 8.3 form are shortened the way
  MS-DOS shortened Windows long names: `longfilename.txt` becomes
  `LONGFI~1.TXT`.
- **MSX turbo R:** the R800's multiplication instructions are used where they
  make a difference.

## Requirements

- MSX-DOS2. MSX-DOS1 is not supported.
- A memory mapper, which MSX-DOS2 always has. Large structures such as the
  sliding window live in mapped memory, through
  [MapperHeap](https://github.com/javilm/MapperHeap).

## Building

The tools are assembled and linked on the MSX itself, with
[Tatara and Tanren](https://tatara.tools). Run `build.bat` from this
directory. The include files the build needs are in `src/include/`.

## Testing

Each tool's tests are in `tests/<tool>/`. Run `tests.bat` from the `tests`
directory; the results are collected in `tests/RESULTS.TXT`. Archives made by
`lha` and `zip` on a modern computer, and by PMarc on the MSX, serve as the
reference.

## Changes

See [CHANGELOG.md](CHANGELOG.md).
