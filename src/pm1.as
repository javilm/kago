; pm1.as - the -pm1- decoder: PMarc 1.x's LZSS, with a move-to-front
; list.
;
; -pm1- is what PMarc 1.x wrote, before PMARC2's -pm2-. Like -pm2-, it
; is bytes and matches, a byte sent as its place in pm2.as's
; move-to-front list (mtf_start, mtf_moved, mtf_find, through pm2.inc);
; but its codes are fixed, never sent. So this module only decodes
; symbols and distances, and lends them to lh5_read (sym_vector,
; dist_vector), as pm2.as does: lh5.as's window, output and bit reader
; do the rest (lh5share.inc).
;
; The data, after 5 bits that choose one of 32 small trees (pm1_trees),
; is a series of commands:
;
; - 0, a match; or 1, a block of 1 to 216 bytes (block_length), which a
;   match always follows, unless the block was 216 long.
; - A byte: its row, through the tree chosen at the start (byte_row),
;   then its place in that row's range (byte_rows), as -pm2- does.
; - A match: a range of distances (pm1_symbol), the first 2 of which
;   mean a match of 2 bytes, the others one of 3 to 244 (match_length);
;   then the distance less 1, through the range (dist_rows). Early in
;   the output some ranges are not yet possible, and their bits are not
;   sent; others are shorter (early_rows). The output counted so far,
;   pm1_pos, decides.
; - A match from before the first byte is not valid.
; - The window is 16 KB: -lh6-'s 32 KB ring holds it. The bits come
;   highest first.
;
; A match goes to lh5_read as 254 + its length, as -pm2-'s does.
;
; The format follows lhasa (reference/lhasa: lib/pm1_decoder.c), which
; Simon Howard worked out from Alwin Henseler's UNPMA10 source. Checked
; before a line of Z80: a Python model of exactly this decodes every
; -pm1- member in the tests as lhasa does.

		public	pm1_start

		include	lh5.inc		; lh5.as's routines
		include	lh5share.inc	; and what it shares
		include	pm2.inc		; pm2.as's list

SLA_C		equ	21h		; SLA C's second byte: the bit order
BLOCK_MAX	equ	216		; the longest block of bytes

		cseg

; pm1_start - get ready to decode the member just read: -pm1-.
;
;   lh5.as's start, with -pm1-'s symbols and distances, the bits highest
;   first, and -lh6-'s 32 KB ring; then the list, and the tree the
;   first 5 bits choose. A read that fails is left in lh5_error, for
;   the first lh5_read to return.
;
; Input:	DE -> the output buffer, 8 KB, below 8000h
;		lzh_packed (lzh.as): the size of the member's data
; Output:	A = 0, ready
;		A = .NORAM: no mapper memory for the tables or the window
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

pm1_start:
		ld	hl,pm1_symbol	; -pm1-'s symbols and distances
		ld	(sym_vector),hl
		ld	hl,pm1_distance
		ld	(dist_vector),hl
		ld	b,"6"		; -lh6-'s ring: 32 KB
		ld	c,SLA_C		; the bits highest first
		call	window_start
		or	a
		ret	nz
		ld	hl,254		; a match of L bytes: 254 + L
		ld	(len_bias),hl
		call	mtf_start	; the list
		ld	b,5		; the tree: pm1_trees + 5 * n
		call	get_bits
		ld	d,h
		ld	e,l
		add	hl,hl
		add	hl,hl
		add	hl,de
		ld	de,pm1_trees
		add	hl,de
		ld	(pm1_tree),hl
		ld	hl,0
		ld	(pm1_pend),hl
		ld	(pm1_pos),hl
		xor	a
		ld	(pm1_left),a
		ld	(pm1_copy),a
		ret

; pm1_symbol - lh5_read's next symbol, from -pm1-: a byte (0 to 255),
;   or a match's length L as 254 + L (256 to 498).
;
;   First the last symbol's bytes move to the list's head (mtf_moved),
;   and are counted in pm1_pos. Then: the next byte of a block; or the
;   match that ends one; or a command, 1 for a block, 0 for a match. A
;   match's range is 0 to 5, from up to 3 bits, some of them sent only
;   once pm1_pos has reached 64, 576 or 2624 (bit_after): ranges 0 and
;   1 are a match of 2, the rest are followed by its length.
;
; Input:	the bit reader
; Output:	HL = the symbol
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

pm1_symbol:
		ld	hl,(pm1_pend)	; the last symbol's bytes: to the
		ld	a,h		;   list's head, and counted
		or	l
		jr	z,pm1_symbol.counted
		call	mtf_moved
		ld	hl,(pm1_pos)	; pm1_pos + pend, at most 0FFFFh
		ld	de,(pm1_pend)
		add	hl,de
		jr	nc,pm1_symbol.pos
		ld	hl,0FFFFh
pm1_symbol.pos:
		ld	(pm1_pos),hl
		ld	hl,0
		ld	(pm1_pend),hl
pm1_symbol.counted:
		ld	a,(pm1_left)	; in a block: its next byte
		or	a
		jr	nz,pm1_symbol.byte
		ld	a,(pm1_copy)	; a block's end: its match
		or	a
		jr	nz,pm1_symbol.match
		ld	b,1		; a command: 1, a block
		call	get_bits
		ld	a,l
		or	a
		jr	z,pm1_symbol.match
		call	block_length	; A = 1 to 216
		ld	(pm1_left),a
		sub	BLOCK_MAX	; a match after it, unless 216 long
		ld	(pm1_copy),a
pm1_symbol.byte:
		ld	hl,pm1_left
		dec	(hl)
		call	byte_row	; A = the row, 0 to 5
		add	a,a		; byte_rows: the first place, the bits
		ld	e,a
		ld	d,0
		ld	hl,byte_rows
		add	hl,de
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		push	bc
		call	get_bits
		pop	bc
		ld	a,l
		add	a,c
		call	mtf_find	; A = the byte
		ld	hl,1
		ld	(pm1_pend),hl
		ld	l,a
		ld	h,0
		ret
pm1_symbol.match:
		xor	a		; a match: its range
		ld	(pm1_copy),a
		ld	b,1
		call	get_bits
		ld	a,l
		or	a
		jr	nz,pm1_symbol.high
		ld	de,576		; 0: then 1 (from 576), 4
		ld	c,0
		call	bit_after
		ld	a,4
		jr	nz,pm1_symbol.range
		ld	de,64		; or 0 or 1 (from 64)
		ld	c,0
		call	bit_after
		jr	pm1_symbol.range
pm1_symbol.high:
		ld	de,64		; 1: then 0 (from 64), 3
		ld	c,1
		call	bit_after
		ld	a,3
		jr	z,pm1_symbol.range
		ld	de,2624		; or 1, 2; 0 (from 2624), 5
		ld	c,1
		call	bit_after
		ld	a,2
		jr	nz,pm1_symbol.range
		ld	a,5
pm1_symbol.range:
		ld	(pm1_r),a
		cp	2
		ld	hl,2		; 0 and 1: a match of 2
		jr	c,pm1_symbol.length
		call	match_length	; A = 3 to 244
		ld	l,a
		ld	h,0
pm1_symbol.length:
		ld	(pm1_pend),hl	; its bytes, for the list
		ld	de,254
		add	hl,de
		ret

; pm1_distance - lh5_read's next distance, less 1, from -pm1-: 0 to
;   10815, for the match pm1_symbol has just given.
;
;   Its range's row in dist_rows, or early in the output a row with
;   fewer bits, from early_rows: the first of the range's entries whose
;   point pm1_pos has not reached. A distance from before the first
;   byte is not valid.
;
; Input:	pm1_r, pm1_pos, the bit reader
; Output:	HL = the distance, less 1
;		lh5_error = LH5_BAD, HL = 0, for one before the first byte
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

pm1_distance:
		ld	a,(pm1_r)
		ld	c,a		; C = the row
		ld	hl,early_rows
pm1_distance.scan:
		ld	a,(hl)		; the range, or 0FFh: the end
		cp	0FFh
		jr	z,pm1_distance.row
		cp	c
		inc	hl
		ld	e,(hl)		; DE = the point
		inc	hl
		ld	d,(hl)
		inc	hl
		jr	nz,pm1_distance.next	; another range's
		push	hl
		ld	hl,(pm1_pos)
		or	a
		sbc	hl,de
		pop	hl
		jr	nc,pm1_distance.next	; reached
		ld	c,(hl)		; not yet: its row
		jr	pm1_distance.row
pm1_distance.next:
		inc	hl
		jr	pm1_distance.scan
pm1_distance.row:
		ld	a,c		; dist_rows, 3 bytes each: the first
		add	a,a		;   distance, the bits
		add	a,c
		ld	e,a
		ld	d,0
		ld	hl,dist_rows
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	b,(hl)
		push	de
		call	get_bits
		pop	de
		add	hl,de		; HL = the distance, less 1
		ex	de,hl		; under pm1_pos, or not valid
		ld	hl,(pm1_pos)
		or	a
		sbc	hl,de
		ex	de,hl
		jr	z,pm1_distance.bad
		ret	nc
pm1_distance.bad:
		call	bad_table	; lh5_error = LH5_BAD
		ld	hl,0
		ret

; bit_after - a bit, once the output has reached a point; before it, a
;   given value, and no bit read.
;
; Input:	DE = the point, C = the value before it
; Output:	A = the bit or the value, Z set if it is 0
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

bit_after:
		ld	hl,(pm1_pos)
		or	a
		sbc	hl,de
		ld	a,c
		jr	c,bit_after.value
		ld	b,1
		call	get_bits
		ld	a,l
bit_after.value:
		or	a
		ret

; byte_row - a byte's row, 0 to 5, through the tree pm1_start chose.
;
;   A tree is a byte a node: its high nibble the branch for 0, its low
;   one for 1; 10 to 15 is a row (A to F), under 10 how many bytes on
;   the child node is. A tree of 0 is no tree: always row 0.
;
; Input:	pm1_tree, the bit reader
; Output:	A = the row
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

byte_row:
		ld	hl,(pm1_tree)
		ld	a,(hl)
		or	a
		ret	z		; no tree: row 0
byte_row.node:
		push	hl
		ld	b,1
		call	get_bits
		ld	a,l
		pop	hl
		ld	c,(hl)
		or	a
		ld	a,c
		jr	nz,byte_row.one
		rrca			; 0: the high nibble
		rrca
		rrca
		rrca
byte_row.one:
		and	0Fh
		cp	10
		jr	nc,byte_row.leaf
		ld	e,a		; on to the child
		ld	d,0
		add	hl,de
		jr	byte_row.node
byte_row.leaf:
		sub	10
		ret

; block_length - how many bytes a block has: 1 to 216.
;
;   2 bits: 1 to 3; or 3 more: 4 to 10; or 4 more: 11 to 24; or, after
;   14, 6 more: 25 to 88; after 15, 7 more: 89 to 216.
;
; Input:	the bit reader
; Output:	A = the length
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

block_length:
		ld	b,2
		call	get_bits
		ld	a,l
		cp	3
		jr	nc,block_length.more
		inc	a
		ret
block_length.more:
		ld	b,3
		call	get_bits
		ld	a,l
		cp	7
		jr	nc,block_length.most
		add	a,4
		ret
block_length.most:
		ld	b,4
		call	get_bits
		ld	a,l
		cp	14
		jr	nc,block_length.long
		add	a,11
		ret
block_length.long:
		jr	nz,block_length.longest
		ld	b,6
		call	get_bits
		ld	a,l
		add	a,25
		ret
block_length.longest:
		ld	b,7
		call	get_bits
		ld	a,l
		add	a,89
		ret

; match_length - how many bytes a match of range 2 to 5 has: 3 to 244.
;
;   2 bits: 3 to 5; or 3 more: 6 to 10, or, after 5, 2 more: 11 to 14,
;   after 6, 3 more: 15 to 22; after 7, 6 more: 23 to 84, or, after 62,
;   5 more: 85 to 116, after 63, 7 more: 117 to 244.
;
; Input:	the bit reader
; Output:	A = the length
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

match_length:
		ld	b,2
		call	get_bits
		ld	a,l
		cp	3
		jr	nc,match_length.more
		add	a,3
		ret
match_length.more:
		ld	b,3
		call	get_bits
		ld	a,l
		cp	5
		jr	nc,match_length.five
		add	a,6
		ret
match_length.five:
		jr	nz,match_length.six
		ld	b,2
		call	get_bits
		ld	a,l
		add	a,11
		ret
match_length.six:
		cp	6
		jr	nz,match_length.seven
		ld	b,3
		call	get_bits
		ld	a,l
		add	a,15
		ret
match_length.seven:
		ld	b,6
		call	get_bits
		ld	a,l
		cp	62
		jr	nc,match_length.long
		add	a,23
		ret
match_length.long:
		jr	nz,match_length.longest
		ld	b,5
		call	get_bits
		ld	a,l
		add	a,85
		ret
match_length.longest:
		ld	b,7
		call	get_bits
		ld	a,l
		add	a,117
		ret

; byte_rows		byte_row's rows, 0 to 5: a byte's first place
;			and the bits after it
; dist_rows		pm1_distance: per row, the first distance less 1
;			(a word) and the bits after it; rows 0 to 5 are
;			the ranges, 6 to 14 their early, shorter forms
; early_rows		pm1_distance: per range, its early rows, in
;			order: the range, the point before which the row
;			holds (a word), the row; 0FFh ends it
; pm1_trees		pm1_start: the 32 trees, 5 bytes each; see
;			byte_row
;
byte_rows:	defb	0,4,16,4,32,5,64,6,128,6,192,6
dist_rows:	defw	0
		defb	6
		defw	64
		defb	8
		defw	0
		defb	6
		defw	64
		defb	9
		defw	576
		defb	11
		defw	2624
		defb	13
		defw	64
		defb	8
		defw	576
		defb	8
		defw	576
		defb	9
		defw	576
		defb	10
		defw	2624
		defb	8
		defw	2624
		defb	9
		defw	2624
		defb	10
		defw	2624
		defb	11
		defw	2624
		defb	12
early_rows:	defb	3
		defw	320
		defb	6,4
		defw	832
		defb	7,4
		defw	1088
		defb	8,4
		defw	1600
		defb	9,5
		defw	2880
		defb	10,5
		defw	3136
		defb	11,5
		defw	3648
		defb	12,5
		defw	4672
		defb	13,5
		defw	6720
		defb	14,0FFh
pm1_trees:	defb	12h,2Dh,0EFh,1Ch,0ABh
		defb	12h,23h,0DEh,0ABh,0CFh
		defb	12h,2Ch,0D2h,0ABh,0EFh
		defb	12h,0A2h,0D2h,0BCh,0EFh
		defb	12h,0A2h,0C2h,0BDh,0EFh
		defb	12h,0A2h,0CDh,0B1h,0EFh
		defb	12h,0ABh,12h,0CDh,0EFh
		defb	12h,0ABh,1Dh,0C1h,0EFh
		defb	12h,0ABh,0C1h,0D1h,0EFh
		defb	0A1h,12h,2Ch,0DEh,0BFh
		defb	0A1h,1Dh,1Ch,0B1h,0EFh
		defb	0A1h,12h,2Dh,0EFh,0BCh
		defb	0A1h,12h,0B2h,0DEh,0CFh
		defb	0A1h,12h,0BCh,0D1h,0EFh
		defb	0A1h,1Ch,0B1h,0D1h,0EFh
		defb	0A1h,0B1h,12h,0CDh,0EFh
		defb	0A1h,0B1h,0C1h,0D1h,0EFh
		defb	12h,1Ch,0DEh,0ABh,0
		defb	12h,0A2h,0CDh,0BEh,0
		defb	12h,0ABh,0C1h,0DEh,0
		defb	0A1h,1Dh,1Ch,0BEh,0
		defb	0A1h,12h,0BCh,0DEh,0
		defb	0A1h,1Ch,0B1h,0DEh,0
		defb	0A1h,0B1h,0C1h,0DEh,0
		defb	1Dh,1Ch,0ABh,0,0
		defb	1Ch,0A1h,0BDh,0,0
		defb	12h,0ABh,0CDh,0,0
		defb	0A1h,1Ch,0BDh,0,0
		defb	0A1h,0B1h,0CDh,0,0
		defb	0A1h,0BCh,0,0,0
		defb	0ABh,0,0,0,0
		defb	0,0,0,0,0

		dseg

; Variables for pm1.as:
;
; pm1_tree		-> the tree pm1_start chose, in pm1_trees
; pm1_pend		the last symbol's bytes, not yet in the list
; pm1_pos		the bytes out so far, at most 0FFFFh
; pm1_left		the bytes still to come in this block
; pm1_copy		not 0 if a match ends the block
; pm1_r			the match's range, or row, for pm1_distance
;
pm1_tree:	defs	2
pm1_pend:	defs	2
pm1_pos:	defs	2
pm1_left:	defs	1
pm1_copy:	defs	1
pm1_r:		defs	1

		end
