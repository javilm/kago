; zip.as - reading a ZIP archive: its central directory, a member at a
; time, into the variables lzh.as gives for an LZH member.
;
; A ZIP archive keeps each member's data after a local header of its
; own, and at the end a central directory: a header for every member,
; with its sizes, method, date, CRC-32, attributes, name, and where its
; local header is. Last of all, the end of central directory record
; says how many members there are and where the directory starts. It is
; found by its signature, "PK" 5 6, in the last 8 KB of the file, where
; it must be followed by its comment and nothing more.
;
; zip_next reads the directory's headers one at a time, seeking to each,
; and leaves the member's path, sizes, date and attributes where lzh.as
; leaves an LZH member's (lzh.inc), so that the rest of UNKAGO works on
; either; the method's name goes in zip_method. The path is cleaned by
; lzh.as's clean_path. A name flagged as UTF-8 has each character past
; ASCII made "?", which MSX-DOS2 does not take in a name, so names.as
; makes it "_" and gives the name a tail.
;
; ZIP64 and split archives are not read: zip_open and zip_next report
; them as ZIP_SPLIT.

ZIP_INCLUDED	equ	1		; zip.inc: not our names as extrn

		public	zip_open
		public	zip_rewind
		public	zip_next
		public	zip_skip
		public	zip_method
		public	zip_crc
		public	zip_local
		public	zip_flags
		public	zip_data

		include	zip.inc		; ZIP_SPLIT
		include	lzh.inc		; the member's variables, lzh_read,
					;   lzh_seek, lzh_clean_path
		include	common.inc	; format_number
		include	ascii.inc	; CHR_SPACE

SEARCH_SIZE	equ	8192		; where the end record is looked for
EOCD_SIZE	equ	22		; the end record, without its comment
CDH_SIZE	equ	46		; a central header, without its name
LFH_SIZE	equ	30		; a local header, without its name

		cseg

; zip_open - find the central directory of the archive lzh_open has
;   opened, and get ready to read it.
;
;   The last SEARCH_SIZE bytes (or the whole file, if it is smaller) are
;   read into the buffer, and searched from the end for "PK" 5 6 with a
;   comment length that reaches exactly to the end of the file. Its
;   disk numbers must be 0 and its two counts the same, or it is a split
;   archive; a count of 0FFFFh, or an offset of 0FFFFFFFFh, means ZIP64.
;
; Input:	DE -> a buffer of SEARCH_SIZE bytes
;		lzh_size (lzh.as)
; Output:	A = 0, at the first member
;		A = LZH_DAMAGED: no end record
;		A = ZIP_SPLIT: ZIP64, or split
;		A = LZH_TRUNCATED, or an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	search_buf
;		search_length

zip_open:
		ld	(search_buf),de
		ld	hl,(lzh_size+2)	; the bytes to search: SEARCH_SIZE,
		ld	a,h		;   or the whole file if smaller
		or	l
		ld	hl,SEARCH_SIZE
		jr	nz,zip_open.size
		ld	de,(lzh_size)
		or	a
		sbc	hl,de
		add	hl,de
		jr	c,zip_open.size	; 8 KB or more
		ex	de,hl
zip_open.size:
		ld	(search_length),hl
		ld	de,EOCD_SIZE
		or	a
		sbc	hl,de
		jp	c,zip_open.damaged	; too small for the end record
		ld	hl,(lzh_size)	; read from size - search_length
		ld	de,(search_length)
		or	a
		sbc	hl,de
		push	hl
		ld	hl,(lzh_size+2)
		ld	de,0
		sbc	hl,de
		ex	de,hl
		pop	hl
		xor	a		; from the start
		call	lzh_seek
		or	a
		ret	nz
		ld	de,(search_buf)
		ld	hl,(search_length)
		call	lzh_read
		or	a
		ret	nz
		ld	hl,(search_length)	; HL -> the last place for it
		ld	de,EOCD_SIZE
		or	a
		sbc	hl,de
		ld	de,(search_buf)
		add	hl,de
		ld	bc,0		; BC = the bytes after it: its comment
zip_open.look:
		ld	a,(hl)
		cp	"P"
		jr	nz,zip_open.back
		push	hl
		inc	hl
		ld	a,(hl)
		cp	"K"
		jr	nz,zip_open.not
		inc	hl
		ld	a,(hl)
		cp	5
		jr	nz,zip_open.not
		inc	hl
		ld	a,(hl)
		cp	6
		jr	nz,zip_open.not
		ld	de,17		; its comment's length, at 20
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		or	a
		sbc	hl,bc
		pop	hl
		jr	z,zip_open.found	; it reaches the end: it
		jr	zip_open.back
zip_open.not:
		pop	hl
zip_open.back:
		push	hl		; one byte back, unless at the start
		ld	de,(search_buf)
		or	a
		sbc	hl,de
		pop	hl
		jr	z,zip_open.damaged
		dec	hl
		inc	bc
		jr	zip_open.look
zip_open.found:
		push	hl
		pop	ix
		ld	a,(ix+4)	; this disk, and the directory's: 0
		or	(ix+5)
		or	(ix+6)
		or	(ix+7)
		jr	nz,zip_open.split
		ld	l,(ix+8)	; the members on this disk, and in all
		ld	h,(ix+9)
		ld	e,(ix+10)
		ld	d,(ix+11)
		or	a
		sbc	hl,de
		jr	nz,zip_open.split
		ld	a,d
		and	e
		inc	a
		jr	z,zip_open.split	; 0FFFFh: ZIP64
		ld	(zip_total),de
		ld	l,(ix+16)	; where the directory starts
		ld	h,(ix+17)
		ld	(cd_offset),hl
		ld	a,l
		and	h
		ld	l,(ix+18)
		ld	h,(ix+19)
		ld	(cd_offset+2),hl
		and	l
		and	h
		inc	a
		jr	nz,zip_rewind	; 0FFFFFFFFh: ZIP64
zip_open.split:
		ld	a,ZIP_SPLIT
		ret
zip_open.damaged:
		ld	a,LZH_DAMAGED
		ret

; zip_rewind - back to the first member, to walk the directory again.
;
;   zip_open ends in it.
;
; Input:	cd_offset, zip_total
; Output:	A = 0
; Modifies:	AF
;		HL
; Scratch:	none

zip_rewind:
		ld	hl,(cd_offset)
		ld	(cd_next),hl
		ld	hl,(cd_offset+2)
		ld	(cd_next+2),hl
		ld	hl,(zip_total)
		ld	(zip_left),hl
		xor	a
		ret

; zip_skip - pass over the member's data: nothing to do, since each
;   header is sought from cd_next.
;
; Input:	none
; Output:	A = 0
; Modifies:	AF
; Scratch:	none

zip_skip:
		xor	a
		ret

; zip_next - read the next member's central header.
;
;   The member's variables are lzh.as's: lzh_name and its length, the
;   path; lzh_packed and lzh_original, the sizes; lzh_time, MS-DOS's
;   time and date words, with lzh_level 0, as for a level 0 header;
;   lzh_attributes; lzh_dir. zip_method is the method's name, zip_crc
;   the CRC-32, zip_local where the local header is and zip_flags the
;   flags' low byte.
;
;   A name ending in "/" is a directory. The attributes are MS-DOS's,
;   the low byte of the external attributes, unless the archive was
;   made on Unix: then only read-only, when the owner may not write.
;   A name longer than 255 bytes keeps its first 255.
;
; Input:	cd_next, zip_left
; Output:	A = LZH_MEMBER, LZH_END, LZH_DAMAGED, ZIP_SPLIT,
;		LZH_TRUNCATED, or an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

zip_next:
		ld	hl,(zip_left)
		ld	a,h
		or	l
		ld	a,LZH_END
		ret	z
		dec	hl
		ld	(zip_left),hl
		ld	hl,(cd_next)	; the header
		ld	de,(cd_next+2)
		xor	a		; from the start
		call	lzh_seek
		or	a
		ret	nz
		ld	de,zip_header
		ld	hl,CDH_SIZE
		call	lzh_read
		or	a
		ret	nz
		ld	hl,zip_header	; "PK" 1 2
		ld	de,cdh_signature
		ld	b,4
zip_next.sig:
		ld	a,(de)
		cp	(hl)
		jp	nz,zip_next.damaged	; too far for jr
		inc	hl
		inc	de
		djnz	zip_next.sig
		ld	hl,CDH_SIZE	; cd_next: past it, its name, extra and
		call	cd_add		;   comment
		ld	hl,(zip_header+28)
		call	cd_add
		ld	hl,(zip_header+30)
		call	cd_add
		ld	hl,(zip_header+32)
		call	cd_add
		ld	hl,zip_header+20	; ZIP64: 0FFFFFFFFh
		call	is_ffffffff
		jp	z,zip_next.split
		ld	hl,zip_header+24
		call	is_ffffffff
		jp	z,zip_next.split
		ld	hl,zip_header+42
		call	is_ffffffff
		jp	z,zip_next.split
		ld	hl,(zip_header+28)	; the name: up to 255 bytes
		ld	a,h
		or	a
		jr	z,zip_next.short
		ld	hl,255
zip_next.short:
		ld	(lzh_name_length),hl
		ld	a,l
		or	a
		jr	z,zip_next.named
		ld	de,lzh_name
		call	lzh_read
		or	a
		ret	nz
zip_next.named:
		ld	hl,zip_header+12	; the time and date words
		ld	de,lzh_time
		ld	bc,4
		ldir
		ld	hl,zip_header+16	; the CRC-32
		ld	de,zip_crc
		ld	bc,4
		ldir
		ld	hl,zip_header+20	; the sizes
		ld	de,lzh_packed
		ld	bc,8
		ldir
		ld	a,(zip_header+8)	; the flags: bit 0, encrypted
		ld	(zip_flags),a
		ld	hl,zip_header+42	; the local header
		ld	de,zip_local
		ld	bc,4
		ldir
		xor	a		; MS-DOS's date, as level 0
		ld	(lzh_level),a
		call	method_text
		xor	a		; a directory: a name ending in "/"
		ld	(lzh_dir),a
		ld	hl,(lzh_name_length)
		ld	a,l
		or	a
		jr	z,zip_next.file
		ld	de,lzh_name-1
		add	hl,de
		ld	a,(hl)
		cp	"/"
		jr	z,zip_next.dir
		cp	5Ch
		jr	nz,zip_next.file
zip_next.dir:
		ld	a,1
		ld	(lzh_dir),a
zip_next.file:
		ld	a,(zip_header+5)	; made on: 3 is Unix
		cp	3
		ld	a,(zip_header+38)	; MS-DOS's attributes
		jr	nz,zip_next.attributes
		ld	a,(zip_header+40)	; Unix: owner's write, 80h
		and	80h
		ld	a,0
		jr	nz,zip_next.attributes
		inc	a		; read-only
zip_next.attributes:
		ld	(lzh_attributes),a
		ld	a,(zip_header+9)	; the flags' bit 11: UTF-8
		bit	3,a
		call	nz,utf8_name
		jp	lzh_clean_path	; A = LZH_MEMBER
zip_next.split:
		ld	a,ZIP_SPLIT
		ret
zip_next.damaged:
		ld	a,LZH_DAMAGED
		ret

; zip_data - to the member's data: past its local header.
;
;   The local header repeats much of the central one, but its name and
;   extra field need not be as long, so their lengths are read from it.
;   The sizes are the central header's: the local one may hold 0, with
;   the real ones after the data.
;
; Input:	zip_local
; Output:	A = 0, the archive at the member's data
;		A = LZH_DAMAGED: no local header there
;		A = LZH_TRUNCATED, or an MSX-DOS error code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

zip_data:
		ld	hl,(zip_local)
		ld	de,(zip_local+2)
		xor	a		; from the start
		call	lzh_seek
		or	a
		ret	nz
		ld	de,local_header
		ld	hl,LFH_SIZE
		call	lzh_read
		or	a
		ret	nz
		ld	hl,local_header	; "PK" 3 4
		ld	de,lfh_signature
		ld	b,4
zip_data.sig:
		ld	a,(de)
		cp	(hl)
		ld	a,LZH_DAMAGED
		ret	nz
		inc	hl
		inc	de
		djnz	zip_data.sig
		ld	hl,(local_header+26)	; past its name and extra field
		ld	de,(local_header+28)
		add	hl,de
		ld	de,0
		jr	nc,zip_data.seek
		inc	de
zip_data.seek:
		ld	a,1		; from here
		call	lzh_seek
		or	a
		ret

; cd_add - HL bytes more to cd_next.
;
; Input:	HL
; Output:	cd_next, 4 bytes, HL more
; Modifies:	F
;		DE
;		HL
; Scratch:	none

cd_add:
		ld	de,(cd_next)
		add	hl,de
		ld	(cd_next),hl
		ret	nc
		ld	hl,(cd_next+2)
		inc	hl
		ld	(cd_next+2),hl
		ret

; is_ffffffff - whether 4 bytes are all 0FFh.
;
; Input:	HL -> them
; Output:	Z set = they are
; Modifies:	AF
;		HL
; Scratch:	none

is_ffffffff:
		ld	a,(hl)
		inc	hl
		and	(hl)
		inc	hl
		and	(hl)
		inc	hl
		and	(hl)
		inc	a
		ret

; method_text - the method's name, 7 characters, in zip_method:
;   "stored ", "deflate", or "m" and the number.
;
; Input:	zip_header: the method, at 10
; Output:	zip_method
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	number_text

method_text:
		ld	hl,zip_method	; spaces first
		ld	b,7
method_text.space:
		ld	(hl),CHR_SPACE
		inc	hl
		djnz	method_text.space
		ld	hl,(zip_header+10)
		ld	a,h
		or	a
		jr	nz,method_text.number
		ld	de,text_stored
		ld	a,l
		or	a
		jr	z,method_text.copy
		ld	de,text_deflate
		cp	8
		jr	z,method_text.copy
method_text.number:
		ld	de,0		; "m", then the digits
		ld	b,5
		ld	ix,number_text+5
		call	format_number
		ld	hl,zip_method
		ld	(hl),"m"
		inc	hl
		ld	de,number_text
		ld	b,5
method_text.digit:
		ld	a,(de)
		inc	de
		cp	CHR_SPACE
		jr	z,method_text.next
		ld	(hl),a
		inc	hl
method_text.next:
		djnz	method_text.digit
		ret
method_text.copy:
		ex	de,hl
		ld	de,zip_method
		ld	bc,7
		ldir
		ret

; utf8_name - each character past ASCII in lzh_name made "?".
;
;   In UTF-8 such a character is a byte from 0C0h up, then bytes 80h to
;   0BFh: the first becomes "?", the others go.
;
; Input:	lzh_name, lzh_name_length
; Output:	the same
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

utf8_name:
		ld	a,(lzh_name_length)
		or	a
		ret	z
		ld	b,a
		ld	hl,lzh_name	; HL reads, DE writes
		ld	d,h
		ld	e,l
utf8_name.byte:
		ld	a,(hl)
		inc	hl
		cp	80h
		jr	c,utf8_name.put	; ASCII
		cp	0C0h
		jr	c,utf8_name.next	; the rest of a character
		ld	a,"?"
utf8_name.put:
		ld	(de),a
		inc	de
utf8_name.next:
		djnz	utf8_name.byte
		ex	de,hl
		ld	de,lzh_name
		or	a
		sbc	hl,de
		ld	(lzh_name_length),hl
		ret

; Constants for the routines above:
;
; cdh_signature		a central header's first 4 bytes
; lfh_signature		a local header's
; text_stored, text_deflate
;			the two methods' names, 7 characters
;
cdh_signature:	defb	"PK",1,2
lfh_signature:	defb	"PK",3,4
text_stored:	defb	"stored "
text_deflate:	defb	"deflate"

		dseg

; Variables for the routines above:
;
; zip_method		the member's method, 7 characters
; zip_crc		its CRC-32, 4 bytes
; zip_local		where its local header is, 4 bytes
; zip_flags		its flags' low byte: bit 0, encrypted
; local_header		zip_data: the local header, 30 bytes
; zip_header		the central header just read: 46 bytes
; zip_total		the members in the directory
; zip_left		those not read yet
; cd_offset		where the directory starts, 4 bytes
; cd_next		where the next header is, 4 bytes
; search_buf		zip_open: the buffer
; search_length		zip_open: the bytes searched
; number_text		method_text: a method's number, 5 wide
;
zip_method:	defs	7
zip_crc:	defs	4
zip_local:	defs	4
zip_flags:	defs	1
local_header:	defs	LFH_SIZE
zip_header:	defs	CDH_SIZE
zip_total:	defs	2
zip_left:	defs	2
cd_offset:	defs	4
cd_next:	defs	4
search_buf:	defs	2
search_length:	defs	2
number_text:	defs	5

		end
