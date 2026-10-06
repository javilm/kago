; zipw.as - writing a ZIP archive: each member's local header, the
; central directory, kept in mapper segments until the end, and the end
; record.
;
; A ZIP archive is each member's local header and data, one after the
; other; then the central directory, a record for each member that
; repeats its local header's details and adds its attributes and where
; its local header is; then the end record, which says where the
; central directory is (zip.as reads an archive from it). KAGO describes
; each member in lzhw.as's variables, as for LZH, with zipw_crc for its
; CRC-32 and zipw_at for where its local header is.
;
; The central directory is kept until the end in central_list, a list
; of records in mapper segments (seglist.as). At the end zipw_copy hands
; it out, to be written after the last member. Nothing here calls MSX-DOS
; while a segment is mapped in page 2: each record is made in
; zipw_buffer first, then added.
;
; Every member is stored (method 0). The system it was made on is
; MS-DOS, so the external attributes' low byte is MS-DOS's attributes.
; A directory's name ends in "/" and needs version 2.0, a file 1.0.
; Names keep MSX-DOS's case; each "\" becomes "/", but never the second
; byte of a two-byte character (kanji_lead, in common.as).

		public	zipw_local
		public	zipw_keep
		public	zipw_copy
		public	zipw_end
		public	zipw_crc
		public	zipw_at

		include	common.inc	; kanji_lead
		include	lzhw.inc	; the member: lzhw_path ... lzhw_attr
		include	seglist.inc	; seglist_add, seglist_map

PATH_SEPARATOR	equ	5Ch		; "\" in lzhw_path

		cseg

; zipw_local - the member's local header.
;
;   "PK" 3 4, the fields it shares with the central record (zipw_fields),
;   then the name.
;
; Input:	lzhw.as's variables, zipw_crc
; Output:	DE -> the header, in zipw_buffer
;		HL = its length
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

zipw_local:
		ld	hl,local_sig
		ld	de,zipw_buffer
		ld	bc,4
		ldir
		call	zipw_fields
		call	copy_name
		ex	de,hl		; HL = its length
		ld	de,zipw_buffer
		or	a
		sbc	hl,de
		ret

; zipw_keep - the member's central record, kept for the end.
;
;   "PK" 1 2, made on MS-DOS by version 2.0, zipw_fields' 26 bytes, no
;   comment, disk 0, no internal attributes, the external ones (MS-DOS's
;   in the low byte), where the local header is, then the name: made in
;   zipw_buffer, then added to central_list.
;
; Input:	lzhw.as's variables, zipw_crc, zipw_at
; Output:	CY set = no mapper memory left for it
;		zipw_count, zipw_size: one more record
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	record_length

zipw_keep:
		ld	hl,central_sig
		ld	de,zipw_buffer
		ld	bc,4
		ldir
		ld	a,20		; made by: version 2.0,
		ld	(de),a
		inc	de
		xor	a		; on MS-DOS
		ld	(de),a
		inc	de
		call	zipw_fields
		xor	a		; no comment, disk 0, no internal
		ld	b,6		;   attributes
zipw_keep.zero:
		ld	(de),a
		inc	de
		djnz	zipw_keep.zero
		ld	a,(lzhw_attr)	; the external ones: MS-DOS's
		ld	(de),a
		inc	de
		xor	a
		ld	(de),a
		inc	de
		ld	(de),a
		inc	de
		ld	(de),a
		inc	de
		ld	hl,zipw_at	; where the local header is
		ld	bc,4
		ldir
		call	copy_name
		ex	de,hl		; HL = the record's length
		ld	de,zipw_buffer
		or	a
		sbc	hl,de
		ld	(record_length),hl
		ld	b,h
		ld	c,l
		ld	de,central_list
		ld	hl,zipw_buffer
		call	seglist_add	; CY: no room
		ret	c
		ld	hl,(zipw_count)
		inc	hl
		ld	(zipw_count),hl
		ld	hl,(zipw_size)	; the central directory's size
		ld	bc,(record_length)
		add	hl,bc
		ld	(zipw_size),hl
		ld	hl,(zipw_size+2)
		ld	bc,0
		adc	hl,bc
		ld	(zipw_size+2),hl
		or	a		; CY clear
		ret

; zipw_copy - the next part of the central directory, copied out.
;
;   copy_seg and copy_pos say how far it has got: each call copies from
;   there, up to the end of that segment's records or BC bytes, whichever
;   comes first, while the segment is in page 2.
;
; Input:	DE -> where it goes
;		BC = how much room there is, 1 or more
; Output:	HL = how many bytes were copied: 0 when all were
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	copy_to
;		copy_room

zipw_copy:
		ld	(copy_to),de
		ld	(copy_room),bc
zipw_copy.segment:
		ld	de,central_list
		ld	a,(copy_seg)
		call	seglist_map	; HL = its start, BC = its length
		jr	c,zipw_copy.none	; past the last segment
		push	hl
		ld	h,b		; what is left in it
		ld	l,c
		ld	de,(copy_pos)
		or	a
		sbc	hl,de
		jr	nz,zipw_copy.some
		pop	hl		; none: on to the next segment
		ld	hl,copy_seg
		inc	(hl)
		ld	hl,0
		ld	(copy_pos),hl
		jr	zipw_copy.segment
zipw_copy.some:
		ld	bc,(copy_room)	; BC = the room, or what is left
		or	a
		sbc	hl,bc
		add	hl,bc
		jr	nc,zipw_copy.sized
		ld	b,h
		ld	c,l
zipw_copy.sized:
		pop	hl		; HL -> where it got to
		ld	de,(copy_pos)
		add	hl,de
		ld	de,(copy_to)
		push	bc
		ldir
		pop	bc
		ld	hl,(copy_pos)
		add	hl,bc
		ld	(copy_pos),hl
		ld	h,b
		ld	l,c
		ret
zipw_copy.none:
		ld	hl,0
		ret

; zipw_end - the end record.
;
;   "PK" 5 6, disk 0 and the central directory's disk 0, its records on
;   this disk and in all (the same), its size, where it starts, and no
;   comment: 22 bytes.
;
; Input:	zipw_count, zipw_size; zipw_at: where the central
;		directory starts
; Output:	DE -> the record, in zipw_buffer
;		HL = its length, 22
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

zipw_end:
		ld	hl,end_sig
		ld	de,zipw_buffer
		ld	bc,4
		ldir
		xor	a		; the disks: 0 and 0
		ld	b,4
zipw_end.disks:
		ld	(de),a
		inc	de
		djnz	zipw_end.disks
		ld	hl,zipw_count	; the records, here and in all
		ld	bc,2
		ldir
		ld	hl,zipw_count
		ld	bc,2
		ldir
		ld	hl,zipw_size
		ld	bc,4
		ldir
		ld	hl,zipw_at
		ld	bc,4
		ldir
		xor	a		; no comment
		ld	(de),a
		inc	de
		ld	(de),a
		ld	de,zipw_buffer
		ld	hl,22
		ret

; zipw_fields - the 26 bytes a local header and a central record share.
;
;   The version needed (2.0 for a directory, whose path is all
;   directories; 1.0 for a file), no flags, method 0, MS-DOS's time and
;   date, the CRC-32, the size twice, the name's length, no extra field.
;
; Input:	DE -> where they go
;		lzhw.as's variables, zipw_crc
; Output:	DE -> just after them
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

zipw_fields:
		ld	a,(lzhw_dir)	; a directory?
		ld	hl,lzhw_length
		cp	(hl)
		ld	a,10
		jr	nz,zipw_fields.version
		ld	a,20
zipw_fields.version:
		ld	(de),a
		inc	de
		xor	a
		ld	(de),a
		inc	de
		ld	b,4		; no flags, method 0
zipw_fields.zero:
		ld	(de),a
		inc	de
		djnz	zipw_fields.zero
		ld	hl,lzhw_date	; the time, then the date
		ld	bc,4
		ldir
		ld	hl,zipw_crc
		ld	bc,4
		ldir
		ld	hl,lzhw_size	; packed: stored, the same
		ld	bc,4
		ldir
		ld	hl,lzhw_size	; the size
		ld	bc,4
		ldir
		ld	a,(lzhw_length)	; the name's length
		ld	(de),a
		inc	de
		xor	a
		ld	(de),a
		inc	de
		ld	(de),a		; no extra field
		inc	de
		ld	(de),a
		inc	de
		ret

; copy_name - the member's path, each "\" made "/".
;
; Input:	DE -> where it goes
;		lzhw_path, lzhw_length: 1 or more bytes
; Output:	DE -> just after it
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

copy_name:
		ld	hl,lzhw_path
		ld	a,(lzhw_length)
		ld	b,a
copy_name.byte:
		ld	a,(hl)
		inc	hl
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	c,copy_name.pair
		cp	PATH_SEPARATOR
		jr	nz,copy_name.put
		ld	a,"/"
copy_name.put:
		ld	(de),a
		inc	de
		djnz	copy_name.byte
		ret
copy_name.pair:
		ld	(de),a
		inc	de
		dec	b
		ret	z		; cut short: cannot be
		ld	a,(hl)
		inc	hl
		jr	copy_name.put

; Constants for the routines above:
;
; local_sig, central_sig, end_sig
;			the signatures: "PK" and two bytes
;
local_sig:	defb	"PK",3,4
central_sig:	defb	"PK",1,2
end_sig:	defb	"PK",5,6

		dseg

; Variables for the routines above:
;
; zipw_crc		the member's CRC-32, 4 bytes, as stored
; zipw_at		where the member's local header is, 4 bytes; for
;			zipw_end, where the central directory starts
; zipw_buffer		a header or a record: 46 bytes and the name, at
;			most 140: under 200
; zipw_count		the records kept
; zipw_size		their bytes, 4
; central_list		the central records: a list, seglist.as's
; record_length		zipw_keep: the record's length
; copy_seg, copy_pos	zipw_copy: how far it has got
; copy_to, copy_room	zipw_copy: where to, and how much room
;
zipw_crc:	defs	4
zipw_at:	defs	4
zipw_buffer:	defs	200
zipw_count:	defs	2
zipw_size:	defs	4
central_list:	defs	LIST_SIZE
record_length:	defs	2
copy_seg:	defs	1
copy_pos:	defs	2
copy_to:	defs	2
copy_room:	defs	2

		end
