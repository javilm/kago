; inflate.as - the deflate decoder: ZIP's method 8.
;
; Deflate is the same kind of method as -lh5-: literals and matches,
; Huffman-coded, in blocks. So this module only reads deflate's blocks,
; and lends lh5.as two routines (sym_vector, dist_vector) through which
; lh5_read takes its symbols and distances; lh5.as's tables, window,
; output and bit reader do the rest (lh5share.inc).
;
; Where deflate differs:
;
; - Its bits are written lowest first. window_start is given SRL C, so
;   fill_bits takes each byte's bits from the bottom, and the codes,
;   which deflate writes first bit highest, arrive in bitbuf as LHA's
;   do: the same tables and make_table decode them. A number (a block's
;   header, a match's extra bits, a stored block's bytes) is written
;   lowest bit first instead, so inf_bits turns its bits round.
; - A block is stored (its bytes as they are, after its length), fixed
;   (built-in code lengths) or dynamic (its own, sent before it).
; - The literal and length symbols are 0 to 287: 256 ends the block,
;   257 to 285 are lengths 3 to 258 with extra bits after them. They go
;   to lh5_read as LHA's symbols, a length L as 253 + L.
; - The distance symbols are 0 to 29: distances 1 to 32768, with extra
;   bits. The window is -lh6-'s: 32 KB, in two segments.
;
; Checked before a line of Z80: a Python model of exactly this, the bits
; and the tables as lh5.as keeps them, decodes Info-ZIP's and zlib's
; archives byte-identical to zlib.

		public	inflate_start

		include	lh5.inc		; LH5_BAD, lh5.as's routines
		include	lh5share.inc	; and what it shares

LIT_SYMS	equ	288		; deflate's literal and length symbols
DIST_SYMS	equ	32		; its distance symbols, 30 and 31 not
					;   valid
SRL_C		equ	39h		; SRL C's second byte: the bit order
STATE_HEADER	equ	0		; inf_state: a block's header next
STATE_HUFFMAN	equ	1		;   in a fixed or dynamic block
STATE_STORED	equ	2		;   in a stored block

		cseg

; inflate_start - get ready to decode the member just read: deflate.
;
;   lh5.as's start, with deflate's bit order, symbols and distances, and
;   -lh6-'s 32 KB window. The first block is read when the first symbol
;   is asked for.
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

inflate_start:
		ld	hl,inf_symbol	; deflate's symbols and distances
		ld	(sym_vector),hl
		ld	hl,inf_distance
		ld	(dist_vector),hl
		ld	hl,LIT_SYMS
		ld	(c_symbols),hl
		xor	a
		ld	(inf_state),a	; STATE_HEADER: a block first
		ld	(inf_final),a
		ld	b,"6"		; -lh6-'s window: 32 KB
		ld	c,SRL_C		; the bits lowest first
		jp	window_start

; inf_bits - a number of B bits, written lowest bit first.
;
;   get_bits gives the first bit highest; the bits are turned round.
;
; Input:	B = how many, 1 to 16
; Output:	HL = the number
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

inf_bits:
		push	bc
		call	get_bits	; HL = them, the first highest
		pop	bc
		ld	de,0
inf_bits.turn:
		srl	h		; the last bit out...
		rr	l
		rl	e		; ...in at the bottom: it ends highest
		rl	d
		djnz	inf_bits.turn
		ex	de,hl
		ret

; inf_symbol - lh5_read's next symbol, from deflate: a byte (0 to 255),
;   or a match's length L as 253 + L (256 to 511).
;
;   Reads a block's header when one is due. In a stored block each byte
;   is a symbol; in a Huffman block, the symbol is decode_sym's, 256
;   ending the block, and a length's extra bits are read at once. A
;   length symbol c' (its number less 257) is 3 + c' below 8, 258 at
;   28, and otherwise (4 + c' mod 4) << e + 3 and e extra bits, e being
;   (c' - 4) / 4. Asked for more after the last block, or given a
;   symbol over 285, it is data that is not valid.
;
; Input:	the bit reader, the tables
; Output:	HL = the symbol
;		lh5_error = LH5_BAD for data that is not valid, HL = 0
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

inf_symbol:
		ld	a,(lh5_error)	; a read that failed: no more
		or	a
		jr	nz,inf_symbol.zero
		ld	a,(inf_state)
		cp	STATE_HUFFMAN
		jr	z,inf_symbol.huffman
		cp	STATE_STORED
		jr	z,inf_symbol.stored
		ld	a,(inf_final)	; a header: after the last block, none
		or	a
		jr	nz,inf_symbol.bad
		call	read_header
		jr	inf_symbol
inf_symbol.stored:
		ld	hl,(stored_left)
		ld	a,h
		or	l
		jr	z,inf_symbol.ended
		dec	hl
		ld	(stored_left),hl
		ld	b,8		; the byte as it is
		jp	inf_bits
inf_symbol.ended:
		xor	a		; STATE_HEADER
		ld	(inf_state),a
		jr	inf_symbol
inf_symbol.huffman:
		call	tables_in
		call	decode_sym	; HL = 0 to 287
		ld	a,h
		or	a
		ret	z		; a byte
		ld	de,257		; 256 ends the block
		or	a
		sbc	hl,de
		jr	c,inf_symbol.ended
		ld	a,l		; A = c', 0 to 30
		cp	29
		jr	nc,inf_symbol.bad
		cp	8
		jr	nc,inf_symbol.extra
		ld	l,a		; 3 + c': 256 + c' for lh5_read
		ld	h,1
		ret
inf_symbol.extra:
		cp	28
		jr	nz,inf_symbol.code
		ld	hl,253+258
		ret
inf_symbol.code:
		ld	c,a		; e = (c' - 4) / 4: 1 to 5
		sub	4
		rrca
		rrca
		and	3Fh
		ld	b,a
		push	bc
		call	inf_bits	; HL = the extra bits
		pop	bc
		ex	de,hl
		ld	a,c		; (4 + c' mod 4) << e
		and	3
		add	a,4
		ld	l,a
		ld	h,0
inf_symbol.shift:
		add	hl,hl
		djnz	inf_symbol.shift
		add	hl,de		; + the extra bits + 3, + 253
		ld	de,3+253
		add	hl,de
		ret
inf_symbol.bad:
		call	bad_table
inf_symbol.zero:
		ld	hl,0
		ret

; inf_distance - lh5_read's next distance, less 1, from deflate.
;
;   A distance symbol d is the distance d + 1 below 4, and otherwise
;   ((2 + d mod 2) << e) + 1 and e extra bits, e being d / 2 - 1. The
;   symbols 30 and 31 are not valid.
;
; Input:	the bit reader, the tables
; Output:	HL = the distance, less 1
;		lh5_error = LH5_BAD for a symbol that is not valid
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

inf_distance:
		call	decode_pt	; DE = the symbol
		ld	a,e
		cp	30
		jr	nc,inf_distance.bad
		cp	4
		jr	nc,inf_distance.extra
		ld	l,a		; 0 to 3
		ld	h,0
		ret
inf_distance.extra:
		ld	c,a		; e = d / 2 - 1: 1 to 13
		srl	a
		dec	a
		ld	b,a
		push	bc
		call	inf_bits	; HL = the extra bits
		pop	bc
		ex	de,hl
		ld	a,c		; (2 + d mod 2) << e
		and	1
		add	a,2
		ld	l,a
		ld	h,0
inf_distance.shift:
		add	hl,hl
		djnz	inf_distance.shift
		add	hl,de		; + the extra bits
		ret
inf_distance.bad:
		call	bad_table
		ld	hl,0
		ret

; read_header - a block's header: the last block or not, its type, and
;   what follows for that type.
;
;   Stored: to the next byte's start, then the length and its
;   complement, 16 bits each. Fixed: the built-in lengths. Dynamic: the
;   block's own (dynamic_tables). Type 3 is never valid.
;
; Input:	the bit reader
; Output:	inf_final, inf_state; stored_left, or the tables
;		lh5_error = LH5_BAD for a header that is not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

read_header:
		ld	b,1		; the last block?
		call	inf_bits
		ld	a,l
		ld	(inf_final),a
		ld	b,2		; its type
		call	inf_bits
		ld	a,l
		or	a
		jr	z,read_header.stored
		dec	a
		jr	z,fixed_tables
		dec	a
		jp	z,dynamic_tables
		jp	bad_table	; 3: not valid
read_header.stored:
		ld	a,(bitcnt)	; to the next byte: past the bits
		and	7		;   left in this one, 8 being none
		ld	b,a
		call	fill_bits
		ld	b,16		; the length
		call	inf_bits
		ld	(stored_left),hl
		ld	b,16		; and its complement
		call	inf_bits
		ld	de,(stored_left)
		ld	a,l
		cpl
		cp	e
		jp	nz,bad_table
		ld	a,h
		cpl
		cp	d
		jp	nz,bad_table
		ld	a,STATE_STORED
		ld	(inf_state),a
		ret

; fixed_tables - the tables of a fixed block: literal and length codes
;   of 8 bits for 0 to 143, 9 for 144 to 255, 7 for 256 to 279 and 8
;   for 280 to 287; distance codes of 5 bits, all 32.
;
; Input:	none
; Output:	the tables; inf_state = STATE_HUFFMAN
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

fixed_tables:
		call	tables_in
		ld	hl,c_len
		ld	bc,144*256+8	; B = how many, C = their length
		call	fill_lengths
		ld	bc,112*256+9
		call	fill_lengths
		ld	bc,24*256+7
		call	fill_lengths
		ld	bc,8*256+8
		call	fill_lengths
		ld	hl,pt_len
		ld	bc,32*256+5
		call	fill_lengths
		ld	a,STATE_HUFFMAN
		ld	(inf_state),a	; and on into build_tables

; build_tables - c_table from c_len's first 288, and pt_table from
;   pt_len's first 32, with make_table.
;
; Input:	c_len, pt_len
; Output:	the tables; p_syms = DIST_SYMS
;		lh5_error = LH5_BAD for lengths that are not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

build_tables:
		ld	hl,LIT_SYMS	; the literals and lengths, 12 bits
		ld	(mt_n),hl
		ld	hl,c_len
		ld	(mt_len),hl
		ld	a,12
		ld	(mt_bits),a
		ld	hl,(tables)
		ld	de,C_TABLE
		add	hl,de
		ld	(mt_table),hl
		call	make_table
		ld	a,DIST_SYMS	; the distances, 8 bits
		ld	(p_syms),a
		ld	hl,DIST_SYMS
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

; dynamic_tables - the tables of a dynamic block, as its header sends
;   them.
;
;   HLIT (5 bits) + 257 literal and length codes, HDIST (5) + 1
;   distance codes, HCLEN (4) + 4 code length codes. First the code
;   length codes' lengths, 3 bits each, in cl_order's order: they make
;   pt_table (19 symbols, 8 bits). Then, decoded through it, the
;   HLIT + HDIST lengths in one run, into c_len: 0 to 15 is a length;
;   16 repeats the one before 3 to 6 times (2 extra bits); 17 is 3 to
;   10 zeros (3 bits); 18 is 11 to 138 zeros (7 bits). A repeat may
;   cross from the literals to the distances, which is why they are
;   read as one run. The distances' lengths then move to pt_len, and
;   build_tables makes both tables.
;
;   A block may send one distance code, or none (only literals). That
;   set is not complete, and make_table refuses it, so dummies of
;   length 1 complete it (complete_distances); they are 30 and 31,
;   which inf_distance never takes. zlib always sends two, so these
;   archives never need it.
;
; Input:	the bit reader
; Output:	the tables; inf_state = STATE_HUFFMAN
;		lh5_error = LH5_BAD for lengths that are not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	hlit
;		hdist
;		len_total
;		len_i
;		rep_value

dynamic_tables:
		ld	b,5		; HLIT + 257
		call	inf_bits
		ld	de,257
		add	hl,de
		ld	(hlit),hl
		ld	b,5		; HDIST + 1
		call	inf_bits
		inc	l
		ld	a,l
		ld	(hdist),a
		ld	b,4		; HCLEN + 4
		call	inf_bits
		ld	a,l
		add	a,4
		push	af
		call	tables_in
		ld	hl,pt_len	; the code length codes' lengths:
		ld	bc,19*256+0	;   0 unless sent
		call	fill_lengths
		pop	bc		; B = HCLEN + 4
		ld	hl,cl_order
dynamic_tables.order:
		push	bc
		push	hl
		ld	b,3
		call	inf_bits	; L = the length
		ld	a,l
		pop	hl
		ld	e,(hl)		; its symbol, from cl_order
		inc	hl
		push	hl
		ld	d,0
		ld	hl,pt_len
		add	hl,de
		ld	(hl),a
		pop	hl
		pop	bc
		djnz	dynamic_tables.order
		ld	a,19		; pt_table: the code length codes
		ld	(p_syms),a
		ld	hl,19
		ld	(mt_n),hl
		ld	hl,pt_len
		ld	(mt_len),hl
		ld	a,8
		ld	(mt_bits),a
		ld	hl,(tables)
		ld	de,PT_TABLE
		add	hl,de
		ld	(mt_table),hl
		call	make_table
		ld	a,(lh5_error)
		or	a
		ret	nz
		ld	hl,(hlit)	; the lengths: HLIT + HDIST of them
		ld	a,(hdist)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	(len_total),hl
		ld	hl,0
		ld	(len_i),hl
dynamic_tables.length:
		ld	hl,(len_i)
		ld	de,(len_total)
		or	a
		sbc	hl,de
		jr	nc,dynamic_tables.read	; all of them
		call	decode_pt	; E = 0 to 18
		ld	a,(lh5_error)
		or	a
		ret	nz
		ld	a,e
		cp	16
		jr	nc,dynamic_tables.repeat
		ld	hl,(len_i)	; a length
		ld	bc,c_len
		add	hl,bc
		ld	(hl),a
		ld	hl,(len_i)
		inc	hl
		ld	(len_i),hl
		jr	dynamic_tables.length
dynamic_tables.repeat:
		cp	17
		jr	nc,dynamic_tables.zeros
		ld	hl,(len_i)	; 16: the one before, 3 to 6 times
		ld	a,h
		or	l
		jp	z,bad_table	; there is none
		dec	hl
		ld	bc,c_len
		add	hl,bc
		ld	a,(hl)
		ld	(rep_value),a
		ld	b,2
		call	inf_bits
		ld	a,l
		add	a,3
		jr	dynamic_tables.run
dynamic_tables.zeros:
		ld	b,3		; 17: 3 to 10 zeros, 3 bits
		ld	c,3
		jr	z,dynamic_tables.zero_bits	; Z still from CP 17
		ld	b,7		; 18: 11 to 138, 7 bits
		ld	c,11
dynamic_tables.zero_bits:
		push	bc
		call	inf_bits
		pop	bc
		xor	a
		ld	(rep_value),a
		ld	a,l
		add	a,c
dynamic_tables.run:
		ld	c,a		; BC = how many
		ld	b,0
		ld	hl,(len_i)	; no further than the last
		add	hl,bc
		ld	de,(len_total)
		ex	de,hl
		or	a
		sbc	hl,de
		jp	c,bad_table
		ld	hl,(len_i)
		push	hl
		add	hl,bc
		ld	(len_i),hl
		pop	hl
		ld	de,c_len
		add	hl,de
		ld	b,c
		ld	a,(rep_value)
		ld	c,a
		call	fill_lengths
		jp	dynamic_tables.length	; too far for jr
dynamic_tables.read:
		ld	hl,pt_len	; the distances' lengths: to pt_len,
		ld	bc,32*256+0	;   0 after them
		call	fill_lengths
		ld	hl,(hlit)
		ld	de,c_len
		add	hl,de
		push	hl
		ld	de,pt_len
		ld	a,(hdist)
		ld	c,a
		ld	b,0
		ldir
		pop	hl		; c_len after the literals: 0
		ld	de,(hlit)
		ex	de,hl
		push	de
		ld	de,LIT_SYMS
		ex	de,hl
		or	a
		sbc	hl,de
		pop	de
		ld	a,l		; 0 to 31 of them
		ex	de,hl
		or	a
		jr	z,dynamic_tables.complete
		ld	b,a
		ld	c,0
		call	fill_lengths
dynamic_tables.complete:
		call	complete_distances
		ld	a,STATE_HUFFMAN
		ld	(inf_state),a
		jp	build_tables

; complete_distances - one distance code, or none, made a complete set:
;   with 30 and 31, of length 1, for none; with 31 (or 30, if the one is
;   31), of length 1, for one. A single code of another length stays
;   as it is, and make_table refuses it, as zlib does.
;
; Input:	pt_len: 32 lengths
; Output:	pt_len
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

complete_distances:
		ld	hl,pt_len	; C = how many have a code,
					;   E = the last of them
		ld	bc,32*256+0
		ld	de,0		; D = the number looked at
complete_distances.count:
		ld	a,(hl)
		or	a
		jr	z,complete_distances.next
		inc	c
		ld	e,d
complete_distances.next:
		inc	hl
		inc	d
		djnz	complete_distances.count
		ld	a,c
		cp	2
		ret	nc		; two or more: as sent
		or	a
		jr	z,complete_distances.none
		ld	a,e		; one: a partner, 31, or 30 if it is 31
		ld	hl,pt_len+31
		cp	31
		jr	nz,complete_distances.partner
		dec	hl
complete_distances.partner:
		ld	(hl),1
		ret
complete_distances.none:
		ld	hl,pt_len+30
		ld	(hl),1
		inc	hl
		ld	(hl),1
		ret

; fill_lengths - B code lengths of C, at HL.
;
; Input:	HL -> where they go
;		B = how many, C = the length
; Output:	HL -> after them
; Modifies:	B
;		HL
; Scratch:	none

fill_lengths:
		ld	(hl),c
		inc	hl
		djnz	fill_lengths
		ret

; Constants for the routines above:
;
; cl_order		the order in which a dynamic block sends its code
;			length codes' lengths
;
cl_order:	defb	16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15

		dseg

; Variables for the routines above:
;
; inf_state		STATE_HEADER, STATE_HUFFMAN or STATE_STORED
; inf_final		not 0 once the last block's header is read
; stored_left		a stored block's bytes not given yet
; hlit, hdist		dynamic_tables: the literal and length codes, and
;			the distance codes, the block sends
; len_total, len_i	dynamic_tables: the lengths to read, and the next
; rep_value		dynamic_tables: the length a repeat repeats
;
inf_state:	defs	1
inf_final:	defs	1
stored_left:	defs	2
hlit:		defs	2
hdist:		defs	1
len_total:	defs	2
len_i:		defs	2
rep_value:	defs	1

		end
