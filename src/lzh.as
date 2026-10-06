; lzh.as - reading an LZH archive: opening it, reading each member's
; header, and skipping each member's data.
;
; An LZH archive is a chain: a member's header, then its data, then the
; next header, until a 0 byte or the end of the file. Headers come in
; levels 0, 1 and 2, which are read here; level 3 is reported, not
; read. The layouts follow lhasa (reference/lhasa, lib/lha_file_header.c
; and lib/ext_header.c), which reads all three the same way.
;
; It keeps what listing and extracting need: the path, the method, the
; packed and original sizes, the date, the level, the data's CRC and
; the MS-DOS attributes. The path is the directories and the name,
; whichever way the header keeps them, made into one that MSX-DOS can
; take and that stays inside the destination (make_path).

LZH_INCLUDED	equ	1		; lzh.inc: not our names as extrn

		public	lzh_open
		public	lzh_rewind
		public	lzh_next_header
		public	lzh_skip_data
		public	lzh_name
		public	lzh_name_length
		public	lzh_method
		public	lzh_packed
		public	lzh_original
		public	lzh_time
		public	lzh_level
		public	lzh_crc
		public	lzh_attributes
		public	lzh_read
		public	lzh_seek
		public	lzh_size
		public	lzh_clean_path
		public	lzh_dir

		include	lzh.inc		; the results
		include	common.inc	; dos
		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	errors.inc	; .EOF

LEVEL0_MIN	equ	22		; the smallest level 0 header: the size
					;   byte counts from offset 2, and 22
					;   is a header with an empty name
LEVEL1_MIN	equ	25		; the same for level 1
LEVEL2_MIN	equ	26		; the smallest level 2 header, whole
COMMON_SIZE	equ	22		; what is read first: enough for the
					;   level byte, at offset 20, and
					;   level 0/1's name length, at 21
EXT_FILENAME	equ	01h		; extended header type: the file name
EXT_DIRECTORY	equ	02h		; the directories, 0FFh after each
EXT_ATTRIBUTES	equ	40h		; and the MS-DOS attributes
SEPARATOR	equ	5Ch		; "\": the path's separator, made

		cseg

; lzh_open - open an archive for reading, and find its size.
;
;   The size is what lzh_skip_data checks each member's data against:
;   _SEEK moves past the end of a file without complaint.
;
; Input:	DE -> the archive's name, zero-terminated
; Output:	A = 0, the archive is open
;		A = an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lzh_open:
		ld	a,1		; open mode: no writing
		dos	_OPEN		; B = the handle
		or	a
		ret	nz
		ld	a,b
		ld	(lzh_handle),a
		ld	a,2		; from the end: DE:HL = the size
		ld	de,0
		ld	hl,0
		call	seek
		or	a
		ret	nz
		ld	(lzh_size),hl
		ld	(lzh_size+2),de	; and on into lzh_rewind

; lzh_rewind - back to the start of the archive, to walk it again.
;
;   lzh_open ends by falling into it.
;
; Input:	none: the archive is open
; Output:	A = 0, or an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lzh_rewind:
		xor	a		; back to the start
		ld	d,a
		ld	e,a
		ld	h,a
		ld	l,a
		jp	seek

; lzh_next_header - read the next member's header.
;
;   The first 22 bytes are read, which hold the level, at offset 20.
;   The end of the archive is no bytes at all, or a 0 byte that is not
;   the start of a level 2 header (whose first byte, the low byte of
;   its length, can be 0). Anything else that is short is a file that
;   ends inside a header.
;
;   A header is valid only if its method field looks like "-l??-";
;   that is also how an LZH archive is recognised. Level 0 and 1
;   headers have a checksum, which is checked; level 2's CRC is not, in
;   Phase 1. On return with a member, the file is at the start of its
;   data, and lzh_packed holds the data's size.
;
;   read_header reads it; make_path, last, makes the path.
;
; Input:	none
; Output:	A = LZH_MEMBER, LZH_END, LZH_TRUNCATED, LZH_DAMAGED or
;		LZH_LEVEL3 (lzh.inc), or an MSX-DOS error code
;		lzh_name, lzh_name_length: the path, with LZH_MEMBER
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lzh_next_header:
		xor	a
		ld	(dir_length),a	; none, until type 2 gives some
		call	read_header
		or	a
		ret	nz
		ld	a,(lzh_method+3)	; -lhd-: a directory
		cp	"d"
		ld	a,0
		jr	nz,lzh_next_header.kind
		inc	a
lzh_next_header.kind:
		ld	(lzh_dir),a
		jp	make_path	; A = LZH_MEMBER from it too

; read_header - read the next member's header, as it is stored.
;
; Input:	none
; Output:	as lzh_next_header, but lzh_name holds only the name, and
;		dir_text, dir_length the directories of a type 2 header
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

read_header:
		ld	de,lzh_header
		ld	hl,COMMON_SIZE
		call	read_bytes	; HL = how many were read
		or	a
		ret	nz		; an MSX-DOS error
		ld	a,h
		or	l
		jr	z,read_header.end	; nothing at all
		ld	a,(lzh_header)
		or	a
		jr	nz,read_header.not_end
		ld	a,l
		cp	COMMON_SIZE
		jr	c,read_header.end	; a 0 and less than a header
		ld	a,(lzh_header+20)
		cp	2
		jr	nz,read_header.end	; a 0, and not level 2
read_header.not_end:
		ld	a,l
		cp	COMMON_SIZE
		jr	c,read_header.truncated
		ld	a,(lzh_header+20)	; the level
		cp	3
		jr	z,read_header.level3
		jr	nc,read_header.damaged	; 4 and up: damaged
		ld	a,(lzh_header+2)	; the method: "-l??-"
		cp	"-"
		jr	nz,read_header.damaged
		ld	a,(lzh_header+3)
		cp	"l"
		jr	nz,read_header.damaged
		ld	a,(lzh_header+6)
		cp	"-"
		jr	nz,read_header.damaged
		ld	hl,lzh_header+2	; the method, the packed and original
		ld	de,lzh_method	;   sizes and the time: 17 bytes at 2,
		ld	bc,17		;   in the same order
		ldir
		ld	a,(lzh_header+20)
		ld	(lzh_level),a
		ld	a,(lzh_header+19)	; the attributes: byte 19,
		ld	(lzh_attributes),a	;   unless type 40h gives them
		ld	a,(lzh_header+20)
		cp	2
		jp	z,read_level2
		jp	read_level01
read_header.end:
		ld	a,LZH_END
		ret
read_header.truncated:
		ld	a,LZH_TRUNCATED
		ret
read_header.level3:
		ld	a,LZH_LEVEL3
		ret
read_header.damaged:
		ld	a,LZH_DAMAGED
		ret

; read_level01 - the rest of a level 0 or level 1 header.
;
;   The size byte, at offset 0, counts the header from offset 2, so the
;   whole base header is that plus 2. Its bytes from offset 2 add up,
;   modulo 256, to the checksum at offset 1. The name is at offset 22,
;   its length at 21. A level 1 header goes on with extended headers;
;   the first one's size is the last word of the base header, and their
;   sizes are counted in the packed size, which read_ext_chain takes
;   them off again.
;
; Input:	lzh_header: the first 22 bytes, level 0 or 1
; Output:	as lzh_next_header
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

read_level01:
		ld	c,LEVEL0_MIN	; C = the smallest valid size
		ld	a,(lzh_header+20)
		or	a
		jr	z,read_level01.min
		ld	c,LEVEL1_MIN
read_level01.min:
		ld	a,(lzh_header)	; the size byte
		cp	c
		jr	c,read_level01.damaged	; too small for a header
		sub	COMMON_SIZE-2	; the bytes not read yet
		ld	l,a
		ld	h,0
		ld	de,lzh_header+COMMON_SIZE
		push	bc
		call	read_exact
		pop	bc
		or	a
		ret	nz		; truncated, or an MSX-DOS error
		ld	a,(lzh_header)	; the checksum: the size byte's worth
		ld	b,a		;   of bytes from offset 2
		ld	hl,lzh_header+2
		xor	a
read_level01.sum:
		add	a,(hl)
		inc	hl
		djnz	read_level01.sum
		ld	hl,lzh_header+1
		cp	(hl)
		jr	nz,read_level01.damaged
		ld	a,(lzh_header+21)	; the name must fit
		add	a,c
		jr	c,read_level01.damaged
		ld	b,a
		ld	a,(lzh_header)
		cp	b
		jr	c,read_level01.damaged
		ld	a,(lzh_header+21)	; the name, as stored
		ld	l,a
		ld	h,0
		ld	(lzh_name_length),hl
		or	a
		jr	z,read_level01.named
		ld	c,a
		ld	b,0
		ld	hl,lzh_header+COMMON_SIZE
		ld	de,lzh_name
		ldir
read_level01.named:
		ld	a,(lzh_header+21)	; the CRC: after the name
		ld	e,a
		ld	d,0
		ld	hl,lzh_header+COMMON_SIZE
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		ld	(lzh_crc),hl
		ld	a,(lzh_header+20)
		or	a
		ret	z		; level 0: done, A = LZH_MEMBER
		ld	(ext_level1),a	; level 1: sizes off lzh_packed
		ld	a,(lzh_header)	; the first extended header's size:
		ld	e,a		;   the last word of the base header
		ld	d,0
		ld	hl,lzh_header
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		jp	read_ext_chain
read_level01.damaged:
		ld	a,LZH_DAMAGED
		ret

; read_level2 - the rest of a level 2 header.
;
;   Its first word is the length of the whole header, extended headers
;   included. The base header is 26 bytes; the first extended header's
;   size is its last word. The name is in an extended header of type 1;
;   a header without one has an empty name. What is left of the header
;   after the extended headers, if anything, is skipped.
;
; Input:	lzh_header: the first 22 bytes, level 2
; Output:	as lzh_next_header
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

read_level2:
		ld	hl,(lzh_header)	; the header's length
		ld	de,LEVEL2_MIN
		or	a
		sbc	hl,de
		jr	c,read_level2.damaged	; too short for a header
		ld	(lzh_rest),hl	; what follows the base header
		ld	de,lzh_header+COMMON_SIZE
		ld	hl,LEVEL2_MIN-COMMON_SIZE
		call	read_exact
		or	a
		ret	nz
		ld	hl,(lzh_header+21)	; the CRC, at 21
		ld	(lzh_crc),hl
		ld	hl,0		; no name until type 1 gives one
		ld	(lzh_name_length),hl
		xor	a
		ld	(ext_level1),a
		ld	hl,(lzh_header+24)	; the first extended size
		call	read_ext_chain
		or	a
		ret	nz
		ld	hl,(lzh_rest)	; the rest, less the extended headers
		ld	de,(ext_consumed)
		sbc	hl,de		; carry clear from OR A
		jr	c,read_level2.damaged	; they ran past the header
		ld	a,h
		or	l
		ret	z		; nothing left: A = LZH_MEMBER
		ld	de,0
		call	seek_on		; skip what is left
		or	a
		ret
read_level2.damaged:
		ld	a,LZH_DAMAGED
		ret

; read_ext_chain - read a chain of extended headers.
;
;   Each one is its type (1 byte), its data, and the size of the next
;   one (a word); its size counts all three, so it is at least 3. A
;   size of 0 ends the chain. Type 1 is the file name: up to 255 bytes
;   of it are kept, the rest skipped. Every other type is skipped.
;
;   For level 1, each size is taken off lzh_packed, which counts the
;   extended headers as well as the data; a size larger than what is
;   left of it means a damaged header.
;
; Input:	HL = the size of the first extended header
;		ext_level1: not 0 for level 1
; Output:	as lzh_next_header
;		ext_consumed: the bytes the chain took
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	ext_size
;		ext_data
;		ext_consumed
;		ext_type
;		ext_level1

read_ext_chain:
		ld	(ext_size),hl
		ld	hl,0
		ld	(ext_consumed),hl
read_ext_chain.next:
		ld	hl,(ext_size)
		ld	a,h
		or	l
		ret	z		; the end of the chain: A = 0
		ld	de,3
		sbc	hl,de		; carry clear from OR L
		jp	c,read_ext_chain.damaged	; smaller than 3: too
					;   far for jr
		ld	(ext_data),hl	; HL = the data's length
		ld	hl,(ext_consumed)
		ld	de,(ext_size)
		add	hl,de
		jr	c,read_ext_chain.damaged	; over 64 KB of them
		ld	(ext_consumed),hl
		ld	a,(ext_level1)
		or	a
		jr	z,read_ext_chain.type
		ld	hl,(lzh_packed)	; level 1: lzh_packed -= the size
		sbc	hl,de		; carry clear from OR A
		ld	(lzh_packed),hl
		ld	hl,(lzh_packed+2)
		ld	de,0
		sbc	hl,de
		ld	(lzh_packed+2),hl
		jr	c,read_ext_chain.damaged	; more than was left
read_ext_chain.type:
		ld	de,ext_type
		ld	hl,1
		call	read_exact
		or	a
		ret	nz
		ld	a,(ext_type)
		cp	EXT_ATTRIBUTES
		jr	z,read_ext_chain.attributes
		cp	EXT_DIRECTORY
		jr	z,read_ext_chain.directory
		cp	EXT_FILENAME
		jr	nz,read_ext_chain.skip
		ld	hl,(ext_data)	; the name: up to 255 bytes of it
		ld	a,h
		or	a
		ld	a,l
		jr	z,read_ext_chain.fits
		ld	a,255
read_ext_chain.fits:
		ld	e,a		; DE = the bytes kept
		ld	d,0
		ld	(lzh_name_length),de
		sbc	hl,de		; carry clear: E <= HL
		ld	(ext_data),hl	; what is left to skip
		ex	de,hl
		ld	de,lzh_name
		call	read_exact
		or	a
		ret	nz
read_ext_chain.skip:
		ld	hl,(ext_data)
		ld	a,h
		or	l
		jr	z,read_ext_chain.size
		ld	de,0
		call	seek_on
		or	a
		ret	nz
read_ext_chain.size:
		ld	de,ext_size	; the next one's size
		ld	hl,2
		call	read_exact
		or	a
		ret	nz
		jp	read_ext_chain.next	; too far for jr
read_ext_chain.damaged:
		ld	a,LZH_DAMAGED
		ret
read_ext_chain.attributes:
		ld	hl,(ext_data)	; the low byte of its word
		ld	a,h
		or	l
		jr	z,read_ext_chain.skip	; empty: nothing to take
		dec	hl
		ld	(ext_data),hl	; what is left to skip
		ld	de,lzh_attributes
		ld	hl,1
		call	read_exact
		or	a
		ret	nz
		jr	read_ext_chain.skip
read_ext_chain.directory:
		ld	hl,(ext_data)	; the directories: up to 254 bytes
		ld	a,h
		or	a
		ld	a,254
		jr	nz,read_ext_chain.dir_cut	; 256 and more
		cp	l
		jr	c,read_ext_chain.dir_cut	; 255
		ld	a,l
read_ext_chain.dir_cut:
		ld	(dir_length),a
		ld	e,a		; DE = the bytes kept
		ld	d,0
		or	a
		sbc	hl,de
		ld	(ext_data),hl	; what is left to skip
		ld	a,e
		or	a
		jr	z,read_ext_chain.skip	; nothing to read
		ex	de,hl
		ld	de,dir_text
		call	read_exact
		or	a
		ret	nz
		jr	read_ext_chain.skip

; make_path - the member's whole path, clean, in lzh_name.
;
;   Level 1 and 2 headers may keep the directories apart, in an
;   extended header of type 2: they go in front of the name, a
;   separator between, the whole cut at 255 bytes. clean_path then
;   tidies it, whatever the level.
;
; Input:	lzh_name, lzh_name_length: the name
;		dir_text, dir_length: the directories, if any
; Output:	lzh_name, lzh_name_length: the path
;		A = LZH_MEMBER
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

make_path:
		ld	a,(dir_length)
		or	a
		jr	z,clean_path	; the name alone
		inc	a		; C = the directories and a separator
		ld	c,a
		ld	a,(lzh_name_length)
		ld	b,a		; B = the name, cut to what is left
		ld	a,255
		sub	c
		cp	b
		jr	nc,make_path.fits
		ld	b,a
make_path.fits:
		ld	a,b
		add	a,c
		ld	(lzh_name_length),a	; the high byte is still 0
		ld	a,b
		or	a
		jr	z,make_path.moved	; no name to move
		push	bc
		ld	e,b		; the name, C bytes on, from its end
		ld	d,0
		ld	hl,lzh_name-1
		add	hl,de		; HL -> its last byte
		push	hl
		ld	e,c
		add	hl,de
		ex	de,hl		; DE -> where it goes
		pop	hl
		ld	c,b
		ld	b,0
		lddr
		pop	bc
make_path.moved:
		dec	c		; the directories in front
		ld	b,0
		ld	hl,dir_text
		ld	de,lzh_name
		ldir
		ld	a,SEPARATOR	; then the separator
		ld	(de),a		; and on into clean_path

; clean_path - make lzh_name a path MSX-DOS can take, and one that
;   stays inside the destination.
;
;   "\", "/" and 0FFh all separate directories (MS-DOS, Unix and LHA's
;   extended headers): each becomes "\". A drive at the start ("A:")
;   goes, and so do empty parts, which takes off separators at the
;   start, so nothing is taken from the root. "." goes; ".." takes off
;   the part before it, but never climbs above the start, as lhasa
;   does. A separator at the end, as level 0 writes after a directory,
;   goes too. The second byte of a two-byte character is never taken
;   for a separator.
;
;   The path is rewritten where it is: writing never gets ahead of
;   reading, since every part and separator written was read first.
;
;   Public as lzh_clean_path: zip.as cleans a ZIP member's path with it.
;
; Input:	lzh_name, lzh_name_length
; Output:	the same, clean
;		A = LZH_MEMBER
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	clean_end
;		part_start

lzh_clean_path:
clean_path:
		ld	hl,(lzh_name_length)	; just after the path
		ld	de,lzh_name
		add	hl,de
		ld	(clean_end),hl
		ld	hl,lzh_name	; HL reads, DE writes
		ld	a,(lzh_name_length)
		cp	2
		jr	c,clean_path.part
		ld	a,(lzh_name+1)
		cp	":"
		jr	nz,clean_path.part
		inc	hl		; past a drive
		inc	hl
clean_path.part:
		call	clean_at_end	; Z: no more
		jr	z,clean_path.done
		ld	(part_start),hl
clean_path.scan:
		call	clean_at_end
		jr	z,clean_path.ended
		ld	a,(hl)
		call	is_separator	; Z: one
		jr	z,clean_path.ended
		inc	hl
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	nc,clean_path.scan
		call	clean_at_end
		jr	z,clean_path.ended
		inc	hl
		jr	clean_path.scan
clean_path.ended:
		push	hl		; HL -> the separator, or the end
		ld	bc,(part_start)
		or	a
		sbc	hl,bc
		ld	b,h		; BC = the part's length
		ld	c,l
		ld	hl,(part_start)
		call	clean_part	; written, or not
		pop	hl
		call	clean_at_end
		jr	z,clean_path.done
		inc	hl		; past the separator
		jr	clean_path.part
clean_path.done:
		ex	de,hl		; the length: as far as writing got
		ld	de,lzh_name
		or	a
		sbc	hl,de
		ld	(lzh_name_length),hl
		xor	a		; LZH_MEMBER
		ret

; clean_part - one part of the path, written after what is clean.
;
;   Nothing for an empty part or "."; for "..", the last part written
;   is taken off again; anything else is written, after a separator
;   unless it is the first.
;
; Input:	HL -> the part
;		BC = its length, 0 to 255
;		DE -> where writing has got to
; Output:	DE -> where writing has got to now
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

clean_part:
		ld	a,c
		or	a
		ret	z		; empty
		cp	1
		jr	z,clean_part.one
		cp	2
		jr	nz,clean_part.keep
		ld	a,(hl)
		cp	"."
		jr	nz,clean_part.keep
		inc	hl
		ld	a,(hl)
		dec	hl
		cp	"."
		jr	z,clean_part.up	; ".."
		jr	clean_part.keep
clean_part.one:
		ld	a,(hl)
		cp	"."
		ret	z		; "."
clean_part.keep:
		push	hl
		ld	hl,lzh_name	; a separator first, unless first
		or	a
		sbc	hl,de
		pop	hl
		jr	z,clean_part.copy
		ld	a,SEPARATOR
		ld	(de),a
		inc	de
clean_part.copy:
		ldir
		ret
clean_part.up:
		ld	hl,lzh_name	; back to the last separator written,
		ld	b,h		;   or to the start: BC -> it
		ld	c,l
clean_part.find:
		or	a
		sbc	hl,de
		add	hl,de
		jr	z,clean_part.found	; all of it looked at
		ld	a,(hl)
		cp	SEPARATOR
		jr	nz,clean_part.char
		ld	b,h
		ld	c,l
clean_part.char:
		inc	hl
		call	kanji_lead
		jr	nc,clean_part.find
		or	a		; a pair: its second byte too
		sbc	hl,de
		add	hl,de
		jr	z,clean_part.found
		inc	hl
		jr	clean_part.find
clean_part.found:
		ld	d,b
		ld	e,c
		ret

; clean_at_end - whether HL is at the end of the path.
;
; Input:	HL, clean_end
; Output:	Z set = it is
; Modifies:	F
; Scratch:	none

clean_at_end:
		push	de
		ld	de,(clean_end)
		or	a
		sbc	hl,de
		add	hl,de		; Z from the SBC
		pop	de
		ret

; is_separator - whether A separates parts of a stored path.
;
; Input:	A
; Output:	Z set = it is "\", "/" or 0FFh
; Modifies:	F
; Scratch:	none

is_separator:
		cp	SEPARATOR
		ret	z
		cp	"/"
		ret	z
		cp	0FFh
		ret

; lzh_skip_data - skip the data of the member just read.
;
;   The file must still reach the end of the data; a member whose data
;   runs past the end of the file means the file was cut short.
;
; Input:	lzh_packed: the size of the data
; Output:	A = 0, the file is at the next header
;		A = LZH_TRUNCATED, or an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lzh_skip_data:
		ld	hl,(lzh_packed)
		ld	de,(lzh_packed+2)
		call	seek_on		; DE:HL = the new position
		or	a
		ret	nz
		ld	(lzh_position),hl
		ld	(lzh_position+2),de
		ld	hl,(lzh_size)	; the size less the position
		ld	de,(lzh_position)
		sbc	hl,de		; carry clear from OR A
		ld	hl,(lzh_size+2)
		ld	de,(lzh_position+2)
		sbc	hl,de
		ld	a,LZH_TRUNCATED
		ret	c		; past the end of the file
		xor	a
		ret

; read_bytes - read up to HL bytes from the archive.
;
;   _READ reports the end of the file as .EOF, but only for a read that
;   reads nothing; that is returned here as 0 bytes and no error.
;
; Input:	DE -> where to put them
;		HL = how many
; Output:	A = 0, HL = how many were read
;		A = an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

read_bytes:
		ld	a,(lzh_handle)
		ld	b,a
		dos	_READ
		cp	.EOF
		jr	z,read_bytes.eof
		or	a
		ret
read_bytes.eof:
		ld	hl,0
		xor	a
		ret

; read_exact - read exactly HL bytes from the archive.
;
;   Public as lzh_read: extracting reads a member's data with it.
;
; Input:	DE -> where to put them
;		HL = how many
; Output:	A = 0, they were read
;		A = LZH_TRUNCATED: the file ended first
;		A = an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lzh_read:
read_exact:
		push	hl
		call	read_bytes
		pop	de		; DE = how many were wanted
		or	a
		ret	nz
		sbc	hl,de		; carry clear from OR A
		ret	z		; all of them: A = 0
		ld	a,LZH_TRUNCATED
		ret

; seek_on - move the archive's file pointer DE:HL bytes on.
;
; Input:	DE:HL = how far
; Output:	A = 0, DE:HL = the new position
;		A = an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

seek_on:
		ld	a,1		; relative to where it is

; seek - move the archive's file pointer.
;
;   seek_on, above, falls into this with A = 1. Public as lzh_seek:
;   zip.as seeks to the central directory's headers with it.
;
; Input:	A = 0, 1 or 2: from the start, from here, from the end
;		DE:HL = the offset, signed
; Output:	A = 0, DE:HL = the new position
;		A = an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lzh_seek:
seek:
		push	af
		ld	a,(lzh_handle)
		ld	b,a
		pop	af
		dos	_SEEK
		ret

		dseg

; Variables for the routines above:
;
; lzh_name		the member's path, made by make_path, up to 255
;			bytes; read_header leaves only the name in it
; lzh_name_length	how long it is: a word, 0 to 255
; dir_text		the directories of a type 2 extended header, as
;			stored, up to 254 bytes
; dir_length		how long they are, 0 for none
; clean_end		clean_path: just after the path
; part_start		clean_path: where the part being read starts
; lzh_handle		the archive's file handle
; lzh_size		the archive's size, 4 bytes
; lzh_position		where lzh_skip_data left the file pointer
; lzh_method		the method, 5 characters: "-lh5-"
; lzh_packed		the size of the member's data, 4 bytes; for
;			level 1, extended headers taken off
; lzh_original		the member's size, once extracted, 4 bytes
; lzh_time		the date and time, 4 bytes: MS-DOS time and date
;			words (levels 0, 1), or seconds since 1970 UTC
;			(level 2)
; lzh_level		the header's level, 0 to 2
; lzh_crc		the CRC-16 of the member's data, from the header
; lzh_attributes	the MS-DOS attributes: byte 19, or type 40h
; lzh_dir		not 0 for a directory: -lhd-
; lzh_rest		read_level2: the header after its base
; lzh_header		the base header: 22 bytes, then the rest of a
;			level 0 or 1 header, up to 257 in all
;
; lzh_method to lzh_time are copied from the header in one go, so they
; stay together and in this order.
;
lzh_name:	defs	255
lzh_name_length:
		defs	2
lzh_handle:	defs	1
lzh_size:	defs	4
lzh_position:	defs	4
lzh_method:	defs	5
lzh_packed:	defs	4
lzh_original:	defs	4
lzh_time:	defs	4
lzh_level:	defs	1
lzh_crc:	defs	2
lzh_attributes:	defs	1
lzh_dir:	defs	1
lzh_rest:	defs	2
lzh_header:	defs	257
dir_text:	defs	254
dir_length:	defs	1
clean_end:	defs	2
part_start:	defs	2

		dseg	scratch,transient
		group	read_ext_chain
ext_size:	defs	2		; the size of the extended header
ext_data:	defs	2		; its data's length, or what is left
ext_consumed:	defs	2		; the chain's bytes so far
ext_type:	defs	1		; its type
ext_level1:	defs	1		; not 0: level 1, sizes off lzh_packed

		end
