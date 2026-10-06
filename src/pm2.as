; pm2.as - the -pm2- decoder: PMARC2's LZSS, with a move-to-front list.
;
; -pm2- is what PMARC2, the MSX-DOS archiver, writes. Like -lh5-, it is
; literals and matches, with Huffman codes sent in the data; so this
; module only decodes symbols and distances, and lends them to lh5_read
; (sym_vector, dist_vector), as lh1.as and inflate.as do: lh5.as's
; window, output, bit reader and tables do the rest (lh5share.inc).
;
; Where -pm2- differs from -lh5-:
;
; - A code (up to 29 of them) says what comes next. Codes 0 to 7 are a
;   byte, as its place in a move-to-front list (below), the code saying
;   how many bits the place has (hist_rows). Codes 8 and up are a match
;   of 2 to 256 bytes: 8 to 22 are 2 to 16; 23 to 28 have extra bits
;   (copy_rows). A match goes to lh5_read as 254 + its length, so
;   pm2_start sets len_bias to 254.
; - A match's distance, less 1, is 6 bits for a match of 2. For longer
;   ones a second code, the offset code, gives its bits: 0 is 6 bits,
;   n is 1 shl (n + 5) plus n + 5 bits. A match of 256 always has a
;   distance of 1.
; - The window is 8 KB, -lh5-'s ring; spaces before the first byte.
; - The codes are not sent per block. They come at the start (the code
;   tree and an offset tree of 5 codes), then after 1 KB of output (an
;   offset tree of 6), 2 KB (7), 4 KB (a bit: 1, a new code tree; and
;   an offset tree of 8) and every 4 KB after that (a bit: 1, both
;   trees again). The counts are of bytes out, a match's included: a
;   match may cross the point, and the trees come after it, before the
;   next code (pm2_rebuild).
; - The code tree's lengths: 5 bits, how many codes; 3 bits, the
;   shortest length, or 0 for a single code (the count less 1), which
;   takes no bits; 3 bits, the bits each length has; then each length,
;   0 for no code, or the shortest + n - 1. The offset tree's: 3 bits
;   each, or none at all when there are fewer than 10 codes (or 29 and
;   one code: only matches of 256), as no match needs them. The codes
;   are given out as LHA's are, and make_table builds their tables.
; - The bits come highest first, as for -lh5-.
;
; The code tree goes in pt_table (8 bits, and a tree beyond, decode_pt),
; the offset tree in an 8-bit table of its own at C_TABLE: building
; LHA's 12-bit c_table each time would take longer than the decoding.
;
; THE LIST holds the 256 byte values, the last one out at its head
; (mtf_head); a byte's place is how many steps back from the head it is,
; through mtf_prev, or 256 less that forward, through the second half
; (MTF_NEXT on), whichever is shorter. Every byte out moves to the head,
; a match's too: those are not seen by this module as they are copied,
; so pm2_symbol moves them, through back_byte, before the next code. It
; starts as PMARC2's: 20h to 7Fh, then 00h to 1Fh, A0h to DFh, 80h to
; 9Fh, E0h to FFh.
;
; The format follows lhasa (reference/lhasa: lib/pm2_decoder.c,
; pma_common.c). Checked before a line of Z80: a Python model of exactly
; this decodes every -pm2- member in the tests as lhasa does.

		public	pm2_start

		include	lh5.inc		; lh5.as's routines
		include	lh5share.inc	; and what it shares

SLA_C		equ	21h		; SLA C's second byte: the bit order
MTF_NEXT	equ	256		; mtf_prev's second half: the steps
					;   forward

		cseg

; pm2_start - get ready to decode the member just read: -pm2-.
;
;   lh5.as's start, with -pm2-'s symbols and distances, the bits highest
;   first, and -lh5-'s 8 KB ring; then the list, and the first trees,
;   after a bit that is not used. Trees that are not valid, or a read
;   that failed, are left in lh5_error, for the first lh5_read to
;   return, as for the other methods.
;
; Input:	DE -> the output buffer, 8 KB, below 8000h
;		lzh_packed (lzh.as): the size of the member's data
; Output:	A = 0, ready
;		A = .NORAM: no mapper memory for the tables or the window
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

pm2_start:
		ld	hl,pm2_symbol	; -pm2-'s symbols and distances
		ld	(sym_vector),hl
		ld	hl,pm2_distance
		ld	(dist_vector),hl
		ld	b,"5"		; -lh5-'s ring: 8 KB
		ld	c,SLA_C		; the bits highest first
		call	window_start	; the tables mapped
		or	a
		ret	nz
		ld	hl,254		; a match of L bytes: 254 + L
		ld	(len_bias),hl
		ld	hl,mtf_prev	; a line: prev[i] = i + 1,
		xor	a		;   next[i] = i - 1; A = i
		ld	b,a		; 256 of them
pm2_start.line:
		inc	a
		ld	(hl),a
		inc	h		; next[i], MTF_NEXT on
		sub	2
		ld	(hl),a
		dec	h
		add	a,2		; the next i
		inc	hl
		djnz	pm2_start.line
		ld	hl,mtf_links	; cut into PMARC2's groups
		ld	b,5
pm2_start.link:
		ld	e,(hl)		; prev[E] = C, next[C] = E
		inc	hl
		ld	c,(hl)
		inc	hl
		push	hl
		ld	d,0
		ld	hl,mtf_prev
		add	hl,de
		ld	(hl),c
		ld	a,e
		ld	e,c
		ld	hl,mtf_prev+MTF_NEXT
		add	hl,de
		ld	(hl),a
		pop	hl
		djnz	pm2_start.link
		ld	a,20h
		ld	(mtf_head),a
		ld	hl,0
		ld	(pm2_pend),hl
		ld	(pm2_left),hl
		xor	a
		ld	(pm2_state),a
		ld	b,1		; a bit, not used
		call	fill_bits
		call	pm2_rebuild	; the first trees
		xor	a
		ret

; pm2_symbol - lh5_read's next symbol, from -pm2-: a byte (0 to 255),
;   or a match's length L as 254 + L (256 to 510).
;
;   First the last symbol's bytes move to the list's head, oldest first,
;   straight from the buffer when they are all in this part, through
;   back_byte one at a time when not; and they are counted: when the
;   count to the next trees runs out, they are read (pm2_rebuild). Then
;   the code: a byte is found in the list; a match's length is the
;   code's, or read after it.
;
; Input:	the bit reader, the tables
; Output:	HL = the symbol
;		lh5_error = LH5_BAD for trees that are not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

pm2_symbol:
		ld	hl,(pm2_pend)	; the last symbol's bytes
		ld	a,h
		or	l
		jr	z,pm2_symbol.counted
		dec	hl		; the first of them
		call	back_byte	; CY: all in this part, at HL
		jr	nc,pm2_symbol.ring
		ld	bc,(pm2_pend)
pm2_symbol.part:
		push	bc
		push	hl
		ld	a,(hl)
		call	mtf_update
		pop	hl
		pop	bc
		inc	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,pm2_symbol.part
		jr	pm2_symbol.count
pm2_symbol.ring:
		ld	hl,(pm2_pend)	; some in the ring: one at a time
		ld	(pm2_k),hl
pm2_symbol.back:
		ld	hl,(pm2_k)	; from pend back to 1 back
		dec	hl
		ld	(pm2_k),hl
		call	back_byte	; A = the byte
		call	mtf_update
		ld	hl,(pm2_k)
		ld	a,h
		or	l
		jr	nz,pm2_symbol.back
pm2_symbol.count:
		ld	hl,(pm2_left)	; counted
		ld	de,(pm2_pend)
		or	a
		sbc	hl,de
		ld	(pm2_left),hl
		ld	hl,0
		ld	(pm2_pend),hl
pm2_symbol.counted:
		call	tables_in	; back_byte may have mapped the ring
		ld	hl,(pm2_left)	; 0 or less: the trees again
		dec	hl
		bit	7,h
		call	nz,pm2_rebuild
		ld	a,(code_one)	; a single code: no bits
		cp	0FFh
		jr	nz,pm2_symbol.code
		call	decode_pt	; E = the code
		ld	a,e
pm2_symbol.code:
		cp	8
		jr	nc,pm2_symbol.match
		add	a,a		; a byte: its place, from hist_rows
		ld	e,a
		ld	d,0
		ld	hl,hist_rows
		add	hl,de
		ld	c,(hl)		; C = the first place
		inc	hl
		ld	b,(hl)		; B = the bits after it
		push	bc
		call	get_bits
		pop	bc
		ld	a,l
		add	a,c
		call	mtf_find	; A = the byte
		ld	hl,1
		ld	(pm2_pend),hl
		ld	l,a
		ld	h,0
		ret
pm2_symbol.match:
		sub	8		; a match
		ld	(pm2_c),a
		cp	15
		jr	nc,pm2_symbol.long
		add	a,2		; 2 to 16 bytes
		ld	l,a
		ld	h,0
		jr	pm2_symbol.length
pm2_symbol.long:
		sub	15		; copy_rows' row, 3 bytes each
		ld	c,a
		add	a,a
		add	a,c
		ld	e,a
		ld	d,0
		ld	hl,copy_rows
		add	hl,de
		ld	e,(hl)		; DE = the first length
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	b,(hl)		; B = the bits after it, 0 to 7
		push	de
		call	get_bits
		pop	de
		add	hl,de
pm2_symbol.length:
		ld	(pm2_pend),hl	; its bytes, for the list
		ld	de,254
		add	hl,de
		ret

; pm2_distance - lh5_read's next distance, less 1, from -pm2-: 0 to
;   8191, for the match pm2_symbol has just given.
;
; Input:	pm2_c, the bit reader, the tables
; Output:	HL = the distance, less 1
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

pm2_distance:
		ld	a,(pm2_c)
		or	a
		jr	z,pm2_distance.six	; a match of 2: 6 bits
		cp	20
		jr	nc,pm2_distance.one	; of 256: always 1 back
		ld	a,(off_one)	; the offset code: a single one,
		cp	0FFh		;   no bits
		jr	nz,pm2_distance.code
		call	off_code	; A = the offset code
pm2_distance.code:
		or	a
		jr	z,pm2_distance.six
		add	a,5		; n: 1 shl (n + 5), plus n + 5 bits
		ld	b,a
		ld	hl,1
pm2_distance.power:
		add	hl,hl
		djnz	pm2_distance.power
		push	hl
		ld	b,a		; A is still n + 5
		call	get_bits
		pop	de
		add	hl,de
		ret
pm2_distance.six:
		ld	b,6
		jp	get_bits
pm2_distance.one:
		ld	hl,0
		ret

; pm2_rebuild - the trees that are due, and the bytes until the next.
;
;   pm2_state counts the points: 0 at the start (the code tree, 5
;   offset codes), 1 after 1 KB (6), 2 after 2 KB (7), 3 after 4 KB (a
;   bit: 1, a code tree; then 8), 4 every 4 KB after (a bit: 1, a code
;   tree and 8). The bytes to the next are added to pm2_left, which a
;   match may have taken below 0.
;
; Input:	pm2_state, pm2_left, the bit reader, the tables mapped
; Output:	the trees; pm2_state, pm2_left
;		lh5_error = LH5_BAD for trees that are not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

pm2_rebuild:
		ld	a,(pm2_state)
		or	a
		jr	z,pm2_rebuild.start
		cp	3
		jr	z,pm2_rebuild.third
		jr	nc,pm2_rebuild.later
		add	a,5		; 1 and 2: 6 and 7 offset codes
		call	off_tree
		jr	pm2_rebuild.next
pm2_rebuild.start:
		call	code_tree
		ld	a,5
		call	off_tree
		jr	pm2_rebuild.next
pm2_rebuild.third:
		ld	b,1		; 1: a code tree
		call	get_bits
		ld	a,l
		or	a
		call	nz,code_tree
		ld	a,8
		call	off_tree
		jr	pm2_rebuild.next
pm2_rebuild.later:
		ld	b,1		; 1: both trees
		call	get_bits
		ld	a,l
		or	a
		jr	z,pm2_rebuild.next
		call	code_tree
		ld	a,8
		call	off_tree
pm2_rebuild.next:
		ld	a,(pm2_state)	; the next point
		cp	4
		jr	z,pm2_rebuild.left
		inc	a
		ld	(pm2_state),a
pm2_rebuild.left:
		dec	a		; its bytes, from rebuild_bytes
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,rebuild_bytes
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	hl,(pm2_left)
		add	hl,de
		ld	(pm2_left),hl
		ret

; code_tree - the code tree's lengths, and its table.
;
;   How many codes (5 bits, 1 to 29) and the shortest length (3 bits);
;   0 is a single code, the count less 1, in code_one. Otherwise the
;   bits each length has (3 bits), and the lengths into pt_len, for
;   make_table: pt_table, 8 bits, p_syms = the count; a longer code (up
;   to 13 bits) goes on through a tree, as decode_pt walks it. pm2_need
;   says whether
;   there will be offset codes.
;
; Input:	the bit reader, the tables mapped
; Output:	pt_len, pt_table, p_syms, code_one, pm2_need
;		lh5_error = LH5_BAD for lengths that are not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	ct_n
;		ct_min
;		ct_bits
;		ct_at
;		ct_i

code_tree:
		ld	b,5		; how many codes
		call	get_bits
		ld	a,l
		ld	(ct_n),a
		or	a
		jp	z,bad_table
		cp	30
		jp	nc,bad_table
		ld	b,3		; the shortest length
		call	get_bits
		ld	a,l
		ld	(ct_min),a
		ld	c,0		; offset codes: 10 or more codes,
		ld	a,(ct_n)	;   but not 29 and a single one
		cp	10
		jr	c,code_tree.need
		inc	c
		cp	29
		jr	nz,code_tree.need
		ld	a,(ct_min)
		or	a
		jr	nz,code_tree.need
		dec	c
code_tree.need:
		ld	a,c
		ld	(pm2_need),a
		ld	a,(ct_min)
		or	a
		jr	nz,code_tree.lengths
		ld	a,(ct_n)	; a single code
		dec	a
		ld	(code_one),a
		ret
code_tree.lengths:
		ld	b,3		; the bits each length has
		call	get_bits
		ld	a,l
		ld	(ct_bits),a
		ld	hl,pt_len
		ld	(ct_at),hl
		ld	a,(ct_n)
		ld	(ct_i),a
code_tree.next:
		ld	a,(ct_bits)	; 0: no code; n: the shortest
		ld	b,a		;   + n - 1
		call	get_bits
		ld	a,l
		or	a
		jr	z,code_tree.put
		ld	hl,ct_min
		add	a,(hl)
		dec	a
code_tree.put:
		ld	hl,(ct_at)
		ld	(hl),a
		inc	hl
		ld	(ct_at),hl
		ld	hl,ct_i
		dec	(hl)
		jr	nz,code_tree.next
		ld	a,0FFh		; a table
		ld	(code_one),a
		ld	a,(ct_n)
		ld	(p_syms),a
		ld	l,a
		ld	h,0
		ld	(mt_n),hl
		ld	hl,pt_len
		ld	(mt_len),hl
		ld	a,8
		ld	(mt_bits),a
		ld	hl,(tables)
		ld	de,PT_TABLE
		add	hl,de
		ld	(mt_table),hl
		jp	make_table

; off_tree - an offset tree of A codes, if there are any, and its
;   table.
;
;   A lengths of 3 bits into c_len, for make_table: 8 bits, at C_TABLE,
;   which -pm2- has no other use for; no code is longer than 7 bits,
;   so there is never a tree (off_code). A single code is kept in
;   off_one, and takes no bits.
;
; Input:	A = how many codes, 5 to 8; pm2_need
; Output:	c_len, the table at C_TABLE, off_one
;		lh5_error = LH5_BAD for lengths that are not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	ct_n
;		ct_at
;		ct_i
;		ct_bits

off_tree:
		ld	c,a
		ld	a,(pm2_need)
		or	a
		ret	z		; no offset codes
		ld	a,c
		ld	(ct_n),a
		ld	(ct_i),a
		xor	a
		ld	(ct_bits),a	; the codes there are
		ld	hl,c_len
		ld	(ct_at),hl
off_tree.next:
		ld	b,3
		call	get_bits
		ld	a,l
		ld	hl,(ct_at)
		ld	(hl),a
		inc	hl
		ld	(ct_at),hl
		or	a
		jr	z,off_tree.none
		ld	hl,ct_bits	; one more, and the last one's
		inc	(hl)		;   number: n - i
		ld	a,(ct_n)
		ld	hl,ct_i
		sub	(hl)
		ld	(off_one),a
off_tree.none:
		ld	hl,ct_i
		dec	(hl)
		jr	nz,off_tree.next
		ld	a,(ct_bits)	; a single code: off_one
		dec	a
		ret	z
		ld	a,0FFh		; a table
		ld	(off_one),a
		ld	a,(ct_n)
		ld	l,a
		ld	h,0
		ld	(mt_n),hl
		ld	hl,c_len
		ld	(mt_len),hl
		ld	a,8
		ld	(mt_bits),a
		ld	hl,(tables)	; C_TABLE is at 0
		ld	(mt_table),hl
		jp	make_table

; off_code - the next offset code, through off_tree's table.
;
;   The table's entry for the next 8 bits is the code; its length is
;   taken. No code is longer than 7 bits, so there is no tree.
;
; Input:	the bit reader; c_len, the table at C_TABLE
; Output:	A = the code
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

off_code:
		call	tables_in
		ld	a,(bitbuf+1)	; the next 8 bits
		ld	l,a
		ld	h,0
		add	hl,hl		; a word each
		ld	de,(tables)	; C_TABLE is at 0
		add	hl,de
		ld	e,(hl)		; under 8: one byte
		ld	d,0
		ld	hl,c_len
		add	hl,de
		ld	b,(hl)
		push	de
		call	fill_bits
		pop	de
		ld	a,e
		ret

; mtf_find - the byte at a place in the list.
;
; Input:	A = the place: 0, the head, to 255
; Output:	A = the byte
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

mtf_find:
		ld	b,a
		ld	a,(mtf_head)
		inc	b		; 0: the head
		dec	b
		ret	z
		ld	e,a
		ld	d,0
		bit	7,b
		jr	nz,mtf_find.forward
mtf_find.back:
		ld	hl,mtf_prev	; under 128: back from the head
		add	hl,de
		ld	e,(hl)
		djnz	mtf_find.back
		ld	a,e
		ret
mtf_find.forward:
		xor	a		; 128 and up: 256 less it,
		sub	b		;   forward
		ld	b,a
mtf_find.step:
		ld	hl,mtf_prev+MTF_NEXT
		add	hl,de
		ld	e,(hl)
		djnz	mtf_find.step
		ld	a,e
		ret

; mtf_update - a byte, to the list's head.
;
;   It is taken out from between its neighbours, and put in after the
;   head, which it becomes: lhasa's update_history_list.
;
; Input:	A = the byte
; Output:	the list
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

mtf_update:
		ld	c,a		; C = the byte
		ld	a,(mtf_head)
		cp	c
		ret	z		; already the head
		ld	b,a		; B = the head
		ld	e,c
		ld	d,0
		ld	hl,mtf_prev
		add	hl,de
		ld	a,(hl)		; A = prev[C]
		ld	(hl),b		; prev[C] = the head
		inc	h
		ld	e,(hl)		; E = next[C]
		push	hl
		push	de
		ld	hl,mtf_prev	; prev[next[C]] = prev[C]
		add	hl,de
		ld	(hl),a
		ld	e,a		; next[prev[C]] = next[C]
		ld	hl,mtf_prev+MTF_NEXT
		add	hl,de
		pop	de
		ld	(hl),e
		ld	e,b		; next[C] = next[head]
		ld	hl,mtf_prev+MTF_NEXT
		add	hl,de
		ld	a,(hl)
		ld	(hl),c		; next[head] = C
		pop	hl
		ld	(hl),a
		ld	e,a		; prev[that one] = C
		ld	hl,mtf_prev
		add	hl,de
		ld	(hl),c
		ld	a,c
		ld	(mtf_head),a
		ret

; hist_rows		pm2_symbol: for codes 0 to 7, a byte's first place
;			and the bits after it
; copy_rows		pm2_symbol: for codes 23 to 28, a match's first
;			length (a word) and the bits after it
; rebuild_bytes		pm2_rebuild: the bytes to the next trees, for
;			points 1 to 4
; mtf_links		pm2_start: where the list's line is cut, as pairs
;			(E, C): prev[E] = C, next[C] = E
;
hist_rows:	defb	0,3,8,3,16,4,32,5,64,5,96,5,128,6,192,6
copy_rows:	defw	17
		defb	3
		defw	25
		defb	3
		defw	33
		defb	5
		defw	65
		defb	6
		defw	129
		defb	7
		defw	256
		defb	0
rebuild_bytes:	defw	1024,1024,2048,4096
mtf_links:	defb	7Fh,00h,1Fh,0A0h,0DFh,80h,9Fh,0E0h,0FFh,20h

		dseg

; Variables for pm2.as:
;
; mtf_head		the list's head: the last byte out
; pm2_pend		the last symbol's bytes, not yet in the list
; pm2_k			pm2_symbol: how far back the next of them is
; pm2_left		the bytes until the next trees; below 0, a match
;			went past them
; pm2_state		which trees come next: 0 to 4
; pm2_need		not 0 if there are offset codes
; pm2_c			the match's code, less 8, for pm2_distance
; code_one, off_one	a single code tree's or offset tree's code, or
;			0FFh for a table
; ct_n, ct_min, ct_bits, ct_at, ct_i
;			code_tree, off_tree: how many codes, the shortest
;			length, the bits each has (off_tree: the codes
;			there are), where the next goes, how many are left
;
mtf_head:	defs	1
pm2_pend:	defs	2
pm2_k:		defs	2
pm2_left:	defs	2
pm2_state:	defs	1
pm2_need:	defs	1
pm2_c:		defs	1
code_one:	defs	1
off_one:	defs	1
ct_n:		defs	1
ct_min:		defs	1
ct_bits:	defs	1
ct_at:		defs	2
ct_i:		defs	1

		dseg	buffers

; mtf_prev		the list: each byte's step back, then (MTF_NEXT
;			bytes on) its step forward
;
mtf_prev:	defs	512

		end
