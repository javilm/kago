; lzhw.as - writing an LZH archive: a member's header, level 2.
;
; KAGO describes each member in lzhw.as's variables: its path, its size,
; its data's CRC-16, its MS-DOS date and time and its attributes; then
; lzhw_header makes the header from them, ready to be written in front
; of the data. Every file is stored (-lh0-) until the compressor comes;
; a directory is -lhd-, its path all directories and its name empty.
;
; A level 2 header is a fixed part of 26 bytes, then extended headers,
; each one its type, its data and the next one's size (lzh.as reads
; them; lha-unix's header.c, in reference/lha-unix, writes them this
; way):
;
;   0	the whole header's length, a word
;   2	the method, "-lh0-"
;   7	the packed size and the original size, 4 bytes each
;   15	the date, in seconds since 1970 (unix_time)
;   19	20h, then the level, 2
;   21	the data's CRC-16
;   23	the system it was made on: "M", MS-DOS
;   24	the first extended header's size
;   26	type 00h: the CRC-16 of the whole header, computed with it at 0
;	type 01h: the name, the path's last part
;	type 02h: the directories, 0FFh after each, when there are any
;	type 40h: the MS-DOS attributes, a word
;
; The whole header's length is never a multiple of 256: its first byte
; would be 0, which is how an archive ends, so a 0 byte is added after
; the last extended header, as LHA does.

		public	lzhw_header
		public	lzhw_method
		public	lzhw_path
		public	lzhw_dir
		public	lzhw_length
		public	lzhw_size
		public	lzhw_crc
		public	lzhw_date
		public	lzhw_attr

		include	common.inc	; kanji_lead
		include	crc.inc		; crc_update, crc_value

EXT_COMMON	equ	00h		; extended header types: the header's
EXT_FILENAME	equ	01h		;   CRC, the name, the directories and
EXT_DIRECTORY	equ	02h		;   the MS-DOS attributes
EXT_ATTRIBUTES	equ	40h
PATH_SEPARATOR	equ	5Ch		; "\" in lzhw_path

		cseg

; lzhw_header - the member's header, from lzhw.as's variables.
;
;   The fixed part first, then the extended headers one after the other,
;   each one's size written just before it. The directories are copied
;   by copy_dirs, which turns each "\" into 0FFh. Last, the header's own
;   CRC, over all of it with that CRC at 0.
;
;   A directory's name is empty: its extended header 01h is there all
;   the same, 3 bytes, as LHA writes it.
;
; Input:	lzhw_method, lzhw_path, lzhw_dir, lzhw_length, lzhw_size,
;		lzhw_crc, lzhw_date, lzhw_attr
; Output:	DE -> the header, in lzhw_buffer
;		HL = its length
;		crc_value: the header's CRC (crc.as)
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lzhw_header:
		ld	hl,lzhw_method	; the method
		ld	de,lzhw_buffer+2
		ld	bc,5
		ldir
		ld	hl,lzhw_size	; the packed size: stored, the same
		ld	bc,4
		ldir
		ld	hl,lzhw_size	; the original size
		ld	bc,4
		ldir
		call	unix_time	; DE:HL = seconds since 1970
		ld	(lzhw_buffer+15),hl
		ld	(lzhw_buffer+17),de
		ld	hl,0220h	; 20h, then level 2
		ld	(lzhw_buffer+19),hl
		ld	hl,(lzhw_crc)
		ld	(lzhw_buffer+21),hl
		ld	a,"M"		; MS-DOS
		ld	(lzhw_buffer+23),a
		ld	hl,5		; type 00h: its size
		ld	(lzhw_buffer+24),hl
		xor	a
		ld	(lzhw_buffer+26),a	; EXT_COMMON
		ld	h,a		; the header's CRC: 0, to compute it
		ld	l,a
		ld	(lzhw_buffer+27),hl
		ld	a,(lzhw_dir)	; type 01h: the name, after the dirs
		ld	c,a
		ld	a,(lzhw_length)
		sub	c
		ld	c,a		; C = the name's length
		add	a,3
		ld	l,a
		ld	h,0
		ld	(lzhw_buffer+29),hl
		ld	a,EXT_FILENAME
		ld	(lzhw_buffer+31),a
		ld	a,(lzhw_dir)
		ld	e,a
		ld	d,0
		ld	hl,lzhw_path
		add	hl,de		; HL -> the name
		ld	de,lzhw_buffer+32
		ld	b,0
		ld	a,c
		or	a
		jr	z,lzhw_header.named	; a directory: no name
		ldir
lzhw_header.named:
		ld	a,(lzhw_dir)	; type 02h, when there are directories
		or	a
		jr	z,lzhw_header.attributes
		add	a,3
		ld	(de),a
		inc	de
		xor	a
		ld	(de),a
		inc	de
		ld	a,EXT_DIRECTORY
		ld	(de),a
		inc	de
		call	copy_dirs
lzhw_header.attributes:
		ld	a,5		; type 40h: its size
		ld	(de),a
		inc	de
		xor	a
		ld	(de),a
		inc	de
		ld	a,EXT_ATTRIBUTES
		ld	(de),a
		inc	de
		ld	a,(lzhw_attr)	; the attributes, a word
		ld	(de),a
		inc	de
		xor	a
		ld	(de),a
		inc	de
		ld	(de),a		; no more extended headers: size 0
		inc	de
		ld	(de),a
		inc	de
		ex	de,hl		; HL = the header's length
		ld	de,lzhw_buffer
		or	a
		sbc	hl,de
		ld	a,l
		or	a
		jr	nz,lzhw_header.sized
		add	hl,de		; a multiple of 256: a 0 byte more
		ld	(hl),a
		sbc	hl,de		; carry clear from the ADD
		inc	hl
lzhw_header.sized:
		ld	(lzhw_buffer),hl
		push	hl
		ld	b,h
		ld	c,l
		ld	hl,0
		ld	(crc_value),hl
		call	crc_update	; DE -> the header, BC = its length
		ld	hl,(crc_value)
		ld	(lzhw_buffer+27),hl
		pop	hl
		ld	de,lzhw_buffer
		ret

; copy_dirs - the member's directories, for extended header 02h.
;
;   Each "\" becomes 0FFh. The second byte of a two-byte character is
;   copied as it is, even when it is 5Ch (kanji_lead, in common.as).
;
; Input:	DE -> where they go
;		lzhw_path, lzhw_dir: 1 or more bytes
; Output:	DE -> just after them
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

copy_dirs:
		ld	hl,lzhw_path
		ld	a,(lzhw_dir)
		ld	b,a
copy_dirs.byte:
		ld	a,(hl)
		inc	hl
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	c,copy_dirs.pair
		cp	PATH_SEPARATOR
		jr	nz,copy_dirs.put
		ld	a,0FFh
copy_dirs.put:
		ld	(de),a
		inc	de
		djnz	copy_dirs.byte
		ret
copy_dirs.pair:
		ld	(de),a
		inc	de
		dec	b
		ret	z		; cut short: cannot be, it ends in "\"
		ld	a,(hl)
		inc	hl
		jr	copy_dirs.put

; unix_time - the member's date and time, in seconds since 1970.
;
;   MS-DOS's time and date words are taken as they are, as UTC: MSX-DOS
;   knows no time zone, and UNKAGO reads level 2's dates back the same
;   way. The days since 1970-01-01 are 365 for each year, one more for
;   each leap year passed (every fourth from 1972, but not 2100), the
;   days of the months passed, 29 February included in a leap year, and
;   the day of the month less one; at most 50,000, a word. Then hours,
;   minutes and seconds, each a multiplication and an addition
;   (times_add). MS-DOS's dates run to 2107, but 32 bits of seconds end
;   on 7 February 2106: a later date wraps round.
;
; Input:	lzhw_date: MS-DOS's time word, then its date word
; Output:	DE:HL = the seconds
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	unix_year
;		unix_month
;		unix_day
;		unix_hour
;		unix_minute
;		unix_second

unix_time:
		ld	hl,(lzhw_date)	; the time: hour, minute, seconds/2
		ld	a,l
		and	1Fh
		add	a,a
		ld	(unix_second),a
		ld	a,h
		rrca
		rrca
		rrca
		and	1Fh
		ld	(unix_hour),a
		add	hl,hl		; the minute, into H's low 6 bits
		add	hl,hl
		add	hl,hl
		ld	a,h
		and	3Fh
		ld	(unix_minute),a
		ld	hl,(lzhw_date+2)	; the date: year, month, day
		ld	a,l
		and	1Fh
		ld	(unix_day),a
		ld	a,h
		srl	a
		ld	(unix_year),a	; since 1980
		add	hl,hl		; the month, into H's low 4 bits
		add	hl,hl
		add	hl,hl
		ld	a,h
		and	0Fh
		ld	(unix_month),a
		ld	a,(unix_year)	; 365 days a year since 1970
		add	a,10
		ld	c,a
		ld	hl,365
		ld	de,0
		xor	a
		call	times_add	; DE = 0: under 65536 days
		ld	a,(unix_year)	; a day for each leap year before it
		add	a,11
		srl	a
		srl	a
		ld	e,a
		ld	d,0
		add	hl,de
		ld	a,(unix_year)
		cp	121		; from 2101: 2100 was counted wrongly
		jr	c,unix_time.months
		dec	hl
unix_time.months:
		ld	a,(unix_month)	; the days of the months before it
		dec	a
		cp	12
		jr	nc,unix_time.day	; 0, or over 12: not a month
		add	a,a
		ld	e,a
		ld	d,0
		push	hl
		ld	hl,month_days
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		pop	hl
		add	hl,de
		cp	4		; A = 2 * (month - 1): before March?
		jr	c,unix_time.day
		ld	a,(unix_year)	; a leap year: 29 February too
		and	3
		jr	nz,unix_time.day
		ld	a,(unix_year)
		cp	120		; but not 2100
		jr	z,unix_time.day
		inc	hl
unix_time.day:
		ld	a,(unix_day)	; the day of the month, less 1
		ld	e,a
		ld	d,0
		add	hl,de
		dec	hl
		ld	de,0		; DE:HL = the days
		ld	a,(unix_hour)
		ld	c,24
		call	times_add	; the hours
		ld	a,(unix_minute)
		ld	c,60
		call	times_add	; the minutes
		ld	a,(unix_second)
		ld	c,60		; and on into times_add: the seconds

; times_add - DE:HL times C, plus A.
;
;   Shift and add, the multiplier's bits highest first.
;
; Input:	DE:HL = the number
;		C = the multiplier
;		A = what is added
; Output:	DE:HL = the result, modulo 2^32
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	times_value

times_add:
		push	af		; the addition, for later
		ld	(times_value),hl
		ld	(times_value+2),de
		ld	hl,0
		ld	d,h
		ld	e,l
		ld	b,8
times_add.bit:
		add	hl,hl		; the result, a bit left
		rl	e
		rl	d
		sla	c		; the multiplier's next bit
		jr	nc,times_add.next
		push	bc
		ld	bc,(times_value)	; the number added in
		add	hl,bc
		ex	de,hl
		ld	bc,(times_value+2)
		adc	hl,bc
		ex	de,hl
		pop	bc
times_add.next:
		djnz	times_add.bit
		pop	af
		ld	c,a
		ld	b,0
		add	hl,bc
		ret	nc
		inc	de
		ret

; Constants for the routines above:
;
; month_days		the days in the year before each month,
;			February at 28
;
month_days:	defw	0,31,59,90,120,151,181,212,243,273,304,334

		dseg

; Variables: the member, as KAGO describes it, and the header:
;
; lzhw_method		the method, 5 characters: "-lh0-", "-lhd-"
; lzhw_path		the member's path, "\" between its parts, as it
;			is stored: the directories, then the name
; lzhw_dir		the directories' length, each with its "\": 0
;			for none
; lzhw_length		the whole path's length, a word
; lzhw_size		the data's size, 4 bytes
; lzhw_crc		the data's CRC-16
; lzhw_date		MS-DOS's time word, then its date word
; lzhw_attr		the MS-DOS attributes
; lzhw_buffer		the header: 26 bytes, then the extended headers,
;			with at most 13 of name, 126 of directories and
;			a 0 byte after: under 200
; times_value		times_add: the number, 4 bytes
; unix_year ... unix_second
;			unix_time: the date's parts, a byte each
;
lzhw_method:	defs	5
lzhw_path:	defs	144
lzhw_dir:	defs	1
lzhw_length:	defs	2
lzhw_size:	defs	4
lzhw_crc:	defs	2
lzhw_date:	defs	4
lzhw_attr:	defs	1
lzhw_buffer:	defs	200
times_value:	defs	4
unix_year:	defs	1
unix_month:	defs	1
unix_day:	defs	1
unix_hour:	defs	1
unix_minute:	defs	1
unix_second:	defs	1

		end
