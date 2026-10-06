; lh5share.inc - what inflate.as, lh1.as, pm1.as and pm2.as share of
; lh5.as beyond
; lh5.inc: the tables' layout, the routines it builds and reads them
; with, and the variables they work on. Only they and lh5.as include it.
;
; lh5.as defines LH5_INCLUDED before including this file, so that it
; does not declare its own names as external.

; The tables' block, mapped at "tables":
C_TABLE		equ	0		; 4096 words: 12 bits to a symbol
PT_TABLE	equ	8192		; 256 words: 8 bits to a symbol

		ifndef	LH5_INCLUDED
		extrn	window_start	; lh5_start, the bit order in C
		extrn	decode_sym	; HL = the next c_table symbol
		extrn	decode_pt	; DE = the next pt_table symbol
		extrn	get_bits	; HL = the next B bits, taken
		extrn	fill_bits	; take B bits
		extrn	make_table	; a table, from mt_n, mt_len...
		extrn	bad_table	; lh5_error = LH5_BAD
		extrn	tables_in	; the tables in page 2
		extrn	tables		; -> them, a word
		extrn	mt_n		; make_table: the symbols, a word
		extrn	mt_len		; -> their lengths
		extrn	mt_bits		; the table's bits: 8 or 12
		extrn	mt_table	; -> the table
		extrn	c_len		; c_table's codes' lengths, 510
		extrn	pt_len		; pt_table's, 128
		extrn	c_symbols		; c_table's symbols, a word
		extrn	p_syms		; pt_table's, a byte
		extrn	lh5_error	; 0, or what went wrong
		extrn	bitcnt		; the bits left in the byte now
		extrn	sym_vector	; where lh5_read's symbols come
		extrn	dist_vector	;   from, and its distances
		extrn	bitbuf		; the next 16 bits, the first highest
		extrn	len_bias	; a match's symbol less its length
		extrn	back_byte	; A = the byte HL + 1 back
		endif
