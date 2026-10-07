# KAGO / UNKAGO

**KAGO** and **UNKAGO** are a pair of command-line tools for MSX-DOS2 that
create and extract archives. `KAGO` packs files and whole directory trees
into an LZH, PMA or ZIP archive, and `UNKAGO` lists and unpacks them. One pair
of tools handles all three formats. They are written entirely in Z80
assembler.

*Kago* is Japanese for "basket": something woven that you pack things into.

Version 1.0.0. Web site: <https://kago.tools>

## What they do

| Format | `KAGO` creates | `UNKAGO` extracts |
|---|---|---|
| ZIP (`.zip`) | deflate, stored | deflate, stored |
| LZH (`.lzh`, `.lha`) | `-lh5-`, `-lh0-` (stored) | `-lh0-`, `-lh1-`, `-lh4-`, `-lh5-`, `-lh6-`, `-lh7-` |
| PMA (`.pma`) | `-pm2-`, `-pm0-` (stored) | `-pm0-`, `-pm1-`, `-pm2-` |

- **One pair of tools for all three formats.** `KAGO` takes the format from
  the archive's extension, or from `/F:ZIP`, `/F:LZH` or `/F:PMA`. `UNKAGO`
  recognises the format of an archive by itself.
- **Whole directory trees**, packed and extracted, in ZIP and LZH archives.
  Name a directory and everything under it goes in.
- **Archives made on modern computers.** `UNKAGO` reads the `-lh6-` and
  `-lh7-` archives (32 KB and 64 KB windows) that LHA can write today, which
  the older MSX extractors cannot open, and ZIP files made by `zip`, Windows
  or macOS. It keeps the window in mapper memory.
- **PMarc's formats**: `-pm1-` and `-pm2-` archives, self-extracting PMA
  files (`.COM`) included, read without PMEXT; and PMA archives that PMEXT
  reads, written by `KAGO`.
- **Long filenames** that do not fit MSX-DOS's 8.3 form are shortened the way
  Windows shortens them for MS-DOS: `longfilename.txt` becomes
  `LONGFI~1.TXT`. The same archive always gives the same names.
- **Adding to an archive** (`/A`), in all three formats: new files go in,
  files with the same path are replaced.
- **Safe extraction.** `UNKAGO` checks that everything fits on the disk, and
  in memory, before it writes anything. If the disk fills anyway, it deletes
  the file it was writing. A member whose CRC does not match is deleted, and
  an existing file is never replaced unless you ask (`/O`).
- **Some members only**, chosen with `*` and `?`, for listing and
  extracting; and **another destination** (`/D:path`), created if it does
  not exist.
- **Dates and attributes kept**: each file's date and time, and its
  read-only, hidden and system attributes.
- **Any amount of memory.** Both tools use the mapper memory that is free
  when they run. With less than it needs for full strength, `KAGO` packs
  with a smaller window, or stores, after asking (`/Y` skips the question).
- **A progress percentage** for each file, on the screen.

## MSX turbo R

Both tools run on an MSX turbo R, in Z80 and in R800 mode, and are simply
faster in R800 mode. They do not use the R800's multiplication instructions
(`MULUB`, `MULUW`): every multiplication in them was measured, and none takes
more than a quarter of one per cent of the time, so a second code path for
the R800 would not be worth it.

## Requirements

- **MSX-DOS2** (or Nextor). MSX-DOS1 is not supported: under it, both tools
  say so and stop.
- **A memory mapper**, which MSX-DOS2 always has. 128 KB is enough. What
  each tool uses of it, when free:

| | Memory |
|---|---|
| `KAGO`, LZH or PMA | 64 KB for full packing; 48 KB packs with a smaller window |
| `KAGO`, ZIP | 80 KB for full packing; 64 KB packs with a smaller window |
| `UNKAGO`, `-lh1-`, `-lh4-`, `-lh5-`, `-pm2-` | 32 KB |
| `UNKAGO`, `-lh6-`, `-pm1-`, deflate | 48 KB |
| `UNKAGO`, `-lh7-` | 80 KB |
| `UNKAGO`, stored members | none |

With less, `KAGO` asks whether to pack with less or store the files, and
`UNKAGO` says how much it needs and how much is free, and stops.

## Installation

Copy `KAGO.COM` and `UNKAGO.COM` to any directory in your `PATH`. For
example, with the tools on drive B: and your commands in `A:\UTILS`:

```
A>COPY B:KAGO.COM A:\UTILS
A>COPY B:UNKAGO.COM A:\UTILS
```

`PATH` alone shows the directories MSX-DOS2 searches. If yours is not among
them, add it with the `PATH` command (`HELP PATH` describes it), and put that
line in `AUTOEXEC.BAT` to keep it. Then check that the tools run:

```
A>KAGO /V
A>UNKAGO /V
```

Nothing else is needed: no configuration files, no environment variables.

## Usage

```
KAGO [switches] archive files...
UNKAGO [switches] archive [members...]
```

| Switch | Tool | What it does |
|---|---|---|
| `/A` | KAGO | add to the archive, replacing files with the same path |
| `/F:fmt` | KAGO | the format: `ZIP`, `LZH` or `PMA`; without it, the extension decides |
| `/0` | KAGO | store the files, without packing them |
| `/Y` | KAGO | proceed without asking when memory is short |
| `/L` | UNKAGO | list the archive, extract nothing |
| `/D:path` | UNKAGO | extract into `path`, created if missing |
| `/O` | UNKAGO | overwrite files that already exist |
| `/Q` | both | quiet: no banner, no progress |
| `/V` | both | print the banner, and nothing else |
| `/?` | both | print the usage |

The full description of both tools is in [MANUAL.md](MANUAL.md) (on the MSX,
`MANUAL.TXT`).

## Examples

### ZIP

Pack every file in the current directory into `GAMES.ZIP`, then extract it
somewhere else:

```
A>KAGO GAMES.ZIP *.*
A>UNKAGO /D:B:\GAMES GAMES.ZIP
```

### LZH

Pack the text files into `DOCS.LZH`, and extract them in the current
directory:

```
A>KAGO DOCS.LZH *.TXT
A>UNKAGO DOCS.LZH
```

`.LHA` works too: it is the same format.

### PMA

Pack two files into `TOOLS.PMA`, which PMEXT can extract as well, and
extract it again:

```
A>KAGO TOOLS.PMA EDIT.COM EDIT.DOC
A>UNKAGO TOOLS.PMA
```

PMA archives cannot hold directories or empty files: `KAGO` skips those that
a wildcard finds, and refuses to start if you name one.

### Directory trees, ZIP

Pack the directory `PROJECT`, with all its subdirectories, then extract the
whole tree into `B:\BACKUP`:

```
A>KAGO PROJECT.ZIP PROJECT
A>UNKAGO /D:B:\BACKUP PROJECT.ZIP
```

The paths are kept as typed (`PROJECT\SRC\MAIN.AS`), so the files come back
in `B:\BACKUP\PROJECT\...`.

### Directory trees, LZH

The same with LZH, from another drive: `B:\WORK\*.*` stores the files and
directories of `B:\WORK` with paths starting at `WORK\`, the drive left out:

```
A>KAGO WORK.LZH B:\WORK\*.*
A>UNKAGO WORK.LZH
```

### Listing an archive

```
A>UNKAGO /L GAMES.ZIP
    Packed   Original Method Date             Name
---------- ---------- ------ ---------------- ------------
      9218      16384 deflat 1994-03-12 18:40 GAME1.ROM
     12030      32768 deflat 1994-03-12 18:41 GAME2.ROM
---------- ---------- ------                  ------------
     21248      49152        2 files
```

### Extracting some members only

Only the `.DOC` files, and everything under the directory `SRC`:

```
A>UNKAGO DOCS.LZH *.DOC
A>UNKAGO PROJECT.ZIP PROJECT\SRC
```

### Replacing files that exist

`UNKAGO` skips a file that is already there; `/O` replaces it:

```
A>UNKAGO /O GAMES.ZIP
```

### Adding to an archive

Add `README.TXT` to `GAMES.ZIP`, or replace it if it is there already:

```
A>KAGO /A GAMES.ZIP README.TXT
```

### Choosing the format by switch

An archive whose name does not end in `.ZIP`, `.LZH`, `.LHA` or `.PMA`:

```
A>KAGO /F:LZH BACKUP.DAT *.*
```

### Storing without packing

Files that are already packed (images, other archives) gain nothing from
packing; `/0` stores them, which is much faster:

```
A>KAGO /0 PICS.ZIP *.SC8
```

### In a batch file

`/Y` never asks about memory, and `/Q` prints no banner and no progress:

```
KAGO /Y /Q BACKUP.LZH A:\WORK
```

`KAGO` never overwrites an archive that exists: delete the old one first, or
use `/A` to add to it.

### Self-extracting PMA files

`UNKAGO` lists and extracts a self-extracting PMA file without running it:

```
A>UNKAGO /L TOOLS.COM
A>UNKAGO TOOLS.COM
```

## Building

The tools are assembled and linked on the MSX itself, with
[Tatara and Tanren](https://tatara.tools). Run `BUILD.BAT` from this
directory; `KAGO.COM` and `UNKAGO.COM` are written to `build\`, with their
memory maps beside them. The include files the build needs are in
`src\include\`.

## Testing

Run `TESTS.BAT` from this directory, after `BUILD.BAT`. The results are
collected in `tests\RESULTS.TXT`, which must be identical to
`tests\EXPECTED.TXT`. `tests\SPEED.BAT` times both tools. Archives made by
`lha` and `zip` on a modern computer, and by PMarc on the MSX, serve as the
reference.

## License

Copyright 2026 Javier Lavandeira.

Licensed under the Apache License, Version 2.0: see [LICENSE](LICENSE).

## Changes

See [CHANGELOG.md](CHANGELOG.md).
