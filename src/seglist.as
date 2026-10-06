; seglist.as - lists of records kept in whole mapper segments.
;
; KAGO keeps two lists that may grow past what fits below 8000h: ZIP's
; central directory (zipw.as) and the paths it has added (kago.as).
; Each is a list of records one after the other, in whole 16 KB mapper
; segments taken with segalloc (MapperHeap) as they are needed. A record
; that would cross a segment's end starts the next one, so each segment
; holds whole records. What a record holds is the caller's business:
; seglist.as stores bytes, and gives each segment back, mapped.
;
; A list is described in low memory, LIST_SIZE bytes (seglist.inc), all
; 0 to start:
;
;	+0			how many segments are taken
;	+1			each one's far pointer, 4 bytes
;	+1 + 4 x LIST_SEGS	each one's length so far, a word
;
; Nothing here calls MSX-DOS while a segment is mapped in page 2: the
; record comes from low memory. A caller reading a segment seglist_map
; gave it must not call MSX-DOS either, until it is done with it.

SEGLIST_INCLUDED	equ	1	; seglist.inc: not our names as extrn

		public	seglist_add
		public	seglist_map

		include	seglist.inc	; LIST_SEGS, LIST_SIZE
		include	common.inc	; MapperHeap's segalloc, deref

SEG_SIZE	equ	4000h		; a segment, 16 KB

		cseg

; seglist_add - a record, added at the end of a list.
;
;   It goes after the last segment's records if it fits there, or at the
;   start of a new segment.
;
; Input:	DE -> the list
;		HL -> the record, in low memory
;		BC = its length, 1 to SEG_SIZE
; Output:	CY set = no room: LIST_SEGS taken, or no segment free
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	list_at
;		rec_at
;		rec_len

seglist_add:
		ld	(list_at),de
		ld	(rec_at),hl
		ld	(rec_len),bc
		ld	a,(de)
		or	a
		jr	z,seglist_add.new	; no segment yet
		dec	a		; the last one's length, plus this
		call	used_at
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		add	hl,bc
		ld	de,SEG_SIZE+1
		or	a
		sbc	hl,de
		jr	c,seglist_add.room	; it fits
seglist_add.new:
		ld	hl,(list_at)
		ld	a,(hl)
		cp	LIST_SEGS
		scf
		ret	z		; all taken: CY
		call	fp_at
		call	segalloc	; CY: no segment free
		ret	c
		ld	hl,(list_at)	; one more, its length 0
		inc	(hl)
seglist_add.room:
		ld	hl,(list_at)	; the last segment, in page 2
		ld	a,(hl)
		dec	a
		push	af
		call	fp_at
		call	deref		; HL = 8000h
		pop	af
		push	hl
		call	used_at		; HL -> its length
		ld	e,(hl)		; DE = its length
		inc	hl
		ld	d,(hl)
		push	de
		ex	de,hl		; its length, the record's more
		ld	bc,(rec_len)
		add	hl,bc
		ex	de,hl
		ld	(hl),d
		dec	hl
		ld	(hl),e
		pop	hl		; where the record goes: after the
		pop	de		;   records already there
		add	hl,de
		ex	de,hl
		ld	hl,(rec_at)
		ldir			; BC = its length
		or	a		; CY clear
		ret

; seglist_map - one segment of a list, in page 2.
;
; Input:	DE -> the list
;		A = the segment, from 0
; Output:	CY set = there is no such segment; otherwise
;		HL = 8000h, its start
;		BC = its length: whole records
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	list_at

seglist_map:
		ld	(list_at),de
		ex	de,hl
		cp	(hl)		; CY: A is one of them
		ccf
		ret	c
		push	af
		call	used_at
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		pop	af
		call	fp_at
		call	deref		; HL = 8000h; BC kept
		or	a		; CY clear
		ret

; fp_at, used_at - where segment A's far pointer is, and its length.
;
; Input:	A = the segment, 0 to LIST_SEGS - 1
;		list_at
; Output:	HL -> list_at + 1 + 4 x A, or
;		HL -> list_at + 1 + 4 x LIST_SEGS + 2 x A
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

fp_at:
		add	a,a
		add	a,a
		inc	a
		jr	list_plus
used_at:
		add	a,a
		add	a,1+4*LIST_SEGS
list_plus:
		ld	e,a
		ld	d,0
		ld	hl,(list_at)
		add	hl,de
		ret

		dseg

; Variables for the routines above:
;
; list_at		the list
; rec_at, rec_len	seglist_add: the record, and its length
;
list_at:	defs	2
rec_at:	defs	2
rec_len:	defs	2

		end
