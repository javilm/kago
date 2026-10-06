; lh1.as - the -lh1- decoder: LHarc 1.x's LZSS with adaptive Huffman codes.
;
; -lh1- is LZHUF, Haruyasu Yoshizaki's and Haruhiko Okumura's method,
; as LHarc 1.x writes it. Like -lh5-, it is literals and matches; unlike
; it, the literal and length codes are never sent. Encoder and decoder
; both start from the same tree, every symbol at 1, and after each
; symbol both add 1 to its count and reorder the tree the same way: the
; codes adapt as the data goes. So this module only decodes symbols and
; distances, and lends them to lh5_read (sym_vector, dist_vector), as
; inflate.as does: lh5.as's window, output and bit reader do the rest
; (lh5share.inc).
;
; Where -lh1- differs from -lh5-:
;
; - The symbols are 0 to 313: a byte, or a match of (symbol - 253)
;   bytes, 3 to 60, as lh5_read takes them already.
; - A distance less 1, 0 to 4095, is its top 6 bits through a fixed code
;   of 3 to 8 bits (d_rows), then its low 6 bits as they are.
; - The window is 4 KB: -lh4-'s 8 KB ring holds it. Before the first
;   byte it is spaces, as lh5.as's ring reads.
; - The bits come highest first, as for -lh5-.
;
; THE TREE is Okumura's (LZHUF.C), three arrays of node numbers, in the
; tables' block, which -lh1- has no other use for:
;
;   freq	NODES + 1 words: each node's count, in order, smallest
;		first; freq[NODES] is 0FFFFh, a stop for the search
;   son		NODES words: a node's children, son and son + 1; NODES and up
;		is a leaf, symbol son - NODES
;   prnt	NODES + N_CHAR words: each node's parent, then each
;		symbol's leaf's, at NODES + the symbol
;
; The root is node ROOT, NODES - 1. A symbol is read from the root, a bit at a
; time, 0 for son, 1 for son + 1, down to a leaf (lh1_symbol). Then
; lh1_update adds 1 to the leaf's count and to every node above it;
; one that would come out of order changes places with the last node of
; the count it had, so freq stays sorted. When the root's count reaches
; 8000h, lh1_rebuild halves every leaf's count and builds the tree
; again.
;
; Checked before a line of Z80: a Python model of exactly this decodes
; LHarc 1.13's and LHa for UNIX's -lh1- archives byte-identical, the
; tree rebuilt three times in one of them.

		public	lh1_start

		include	lh5.inc		; lh5.as's routines
		include	lh5share.inc	; and what it shares

N_CHAR		equ	314		; the symbols: 256 bytes, 58 lengths
NODES		equ	2*N_CHAR-1	; the nodes: 627
ROOT		equ	NODES-1		; the root
MAX_FREQ	equ	8000h		; the root's count that rebuilds
FREQ		equ	0		; the arrays, in the tables' block
SON		equ	FREQ+2*NODES+2
PRNT		equ	SON+2*NODES
SLA_C		equ	21h		; SLA C's second byte: the bit order

		cseg

; lh1_start - get ready to decode the member just read: -lh1-.
;
;   lh5.as's start, with -lh1-'s symbols and distances, the bits highest
;   first, and -lh4-'s ring; then the tree, every symbol at 1.
;
; Input:	DE -> the output buffer, 8 KB, below 8000h
;		lzh_packed (lzh.as): the size of the member's data
; Output:	A = 0, ready
;		A = .NORAM: no mapper memory for the tables or the window
;		A = LZH_TRUNCATED, or an MSX-DOS error, from reading
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lh1_start:
		ld	hl,lh1_symbol	; -lh1-'s symbols and distances
		ld	(sym_vector),hl
		ld	hl,lh1_distance
		ld	(dist_vector),hl
		ld	b,"4"		; -lh4-'s ring: 8 KB
		ld	c,SLA_C		; the bits highest first
		call	window_start	; the tables mapped
		or	a
		ret	nz
		ld	hl,(tables)	; the arrays: where they are
		ld	(freq_at),hl
		ld	bc,SON
		add	hl,bc
		ld	(son_at),hl
		ld	hl,(tables)
		ld	bc,PRNT
		add	hl,bc
		ld	(prnt_at),hl
		ld	de,0		; the leaves: each symbol at 1,
lh1_start.leaf:
		ld	h,d		;   node i its leaf, NODES + i
		ld	l,e
		call	at_freq
		ld	(hl),1
		inc	hl
		ld	(hl),0
		ld	hl,NODES
		add	hl,de
		push	hl
		ld	h,d
		ld	l,e
		call	at_son
		pop	bc
		ld	(hl),c
		inc	hl
		ld	(hl),b
		ld	h,b		; prnt[T + i] = i
		ld	l,c
		call	at_prnt
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	de
		ld	hl,N_CHAR
		or	a
		sbc	hl,de
		jr	nz,lh1_start.leaf
		ld	hl,0		; the nodes, N_CHAR to ROOT: node j
		ld	(node_i),hl	;   over i and i + 1, its count
lh1_start.node:
		ld	hl,(node_i)	;   theirs added
		call	at_freq
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		inc	hl
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		add	hl,bc
		push	hl
		ld	h,d
		ld	l,e
		call	at_freq
		pop	bc
		ld	(hl),c
		inc	hl
		ld	(hl),b
		ld	h,d		; son[j] = i
		ld	l,e
		call	at_son
		ld	bc,(node_i)
		ld	(hl),c
		inc	hl
		ld	(hl),b
		ld	hl,(node_i)	; prnt[i] = prnt[i + 1] = j
		call	at_prnt
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	hl,(node_i)
		inc	hl
		inc	hl
		ld	(node_i),hl
		inc	de
		ld	hl,ROOT
		or	a
		sbc	hl,de
		jr	nc,lh1_start.node
		ld	hl,NODES	; freq[NODES]: the search's stop
		call	at_freq
		ld	(hl),0FFh
		inc	hl
		ld	(hl),0FFh
		ld	hl,ROOT		; the root has no parent
		call	at_prnt
		ld	(hl),0
		inc	hl
		ld	(hl),0
		xor	a
		ret

; lh1_symbol - lh5_read's next symbol, from -lh1-: a byte (0 to 255), or
;   a match's length L as 253 + L (256 to 313).
;
;   From the root down, a bit at a time: each bit is looked at in
;   bitbuf, through a mask, and they are taken all at once at the leaf;
;   or 16 at a time, for a code longer than that. Then the tree is
;   updated.
;
; Input:	the bit reader, the tree
; Output:	HL = the symbol
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lh1_symbol:
		call	tables_in	; page 2 may hold the ring
		ld	hl,ROOT		; c = son[ROOT]
		call	at_son
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		xor	a		; no bits looked at yet
		ld	(walk_n),a
		ld	bc,8000h	; the first: bitbuf's top
lh1_symbol.walk:
		ld	hl,NODES-1	; NODES and up: a leaf
		or	a
		sbc	hl,de
		jr	c,lh1_symbol.leaf
		ld	hl,(bitbuf)	; the bit: 0, son[c]; 1, son[c] + 1
		ld	a,h
		and	b
		ld	h,a
		ld	a,l
		and	c
		or	h
		ex	de,hl
		jr	z,lh1_symbol.zero
		inc	hl
lh1_symbol.zero:
		push	bc
		call	at_son
		pop	bc
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	hl,walk_n
		inc	(hl)
		srl	b		; the next bit
		rr	c
		ld	a,b
		or	c
		jr	nz,lh1_symbol.walk
		push	de		; all 16 looked at: taken
		ld	b,16
		call	fill_bits
		pop	de
		xor	a
		ld	(walk_n),a
		ld	bc,8000h
		jr	lh1_symbol.walk
lh1_symbol.leaf:
		push	de		; the bits looked at: taken
		ld	a,(walk_n)
		ld	b,a
		call	fill_bits
		pop	de
		ld	hl,-NODES	; the symbol: c - NODES
		add	hl,de
		push	hl
		ex	de,hl
		call	lh1_update
		pop	hl
		ret

; lh1_update - one more of a symbol: its leaf's count, and every node's
;   above it.
;
;   LZHUF.C's update. The count k goes up by 1; if the next node's is
;   now smaller, the node changes places with the last of those whose
;   count is under k (the search stops at freq[NODES]): their counts, their
;   children, and the children's parents. Then on up, to the root's
;   parent, 0. Before all that, a root's count of MAX_FREQ rebuilds the
;   tree.
;
; Input:	DE = the symbol: 0 to 313
; Output:	the tree
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lh1_update:
		ld	hl,ROOT		; the root at MAX_FREQ: rebuilt
		call	at_freq
		ld	a,(hl)
		or	a
		jr	nz,lh1_update.go
		inc	hl
		ld	a,(hl)
		cp	MAX_FREQ/256
		jr	nz,lh1_update.go
		push	de
		call	lh1_rebuild
		pop	de
lh1_update.go:
		ld	hl,NODES	; c = prnt[NODES + symbol]: its leaf
		add	hl,de
		call	at_prnt
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
lh1_update.node:
		ld	h,d		; k = ++freq[c]
		ld	l,e
		call	at_freq
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		inc	bc
		ld	(hl),b
		dec	hl
		ld	(hl),c
		push	hl		; -> freq[c]
		inc	hl		; freq[c + 1] under k?
		inc	hl
		ld	a,(hl)
		sub	c
		inc	hl
		ld	a,(hl)
		sbc	a,b
		dec	hl
		jr	nc,lh1_update.up	; no: in order
lh1_update.scan:
		inc	hl		; l: the last under k
		inc	hl
		ld	a,(hl)
		sub	c
		inc	hl
		ld	a,(hl)
		sbc	a,b
		dec	hl
		jr	c,lh1_update.scan
		dec	hl
		dec	hl
		ld	e,(hl)		; freq[c] = freq[l], freq[l] = k
		ld	(hl),c
		inc	hl
		ld	d,(hl)
		ld	(hl),b
		dec	hl
		ex	(sp),hl
		ld	(hl),e
		inc	hl
		ld	(hl),d
		dec	hl
		call	node_of		; c and l, as node numbers
		ld	(up_c),hl
		pop	hl
		call	node_of
		ld	(up_l),hl
		ld	hl,(up_c)	; i = son[c]: its parent is l
		call	at_son
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(up_i),de
		ld	bc,(up_l)
		call	set_prnt
		ld	hl,(up_l)	; j = son[l]; son[l] = i
		call	at_son
		ld	bc,(up_i)
		ld	e,(hl)
		ld	(hl),c
		inc	hl
		ld	d,(hl)
		ld	(hl),b
		push	de		; j's parent is c
		ld	bc,(up_c)
		call	set_prnt
		pop	de
		ld	hl,(up_c)	; son[c] = j
		call	at_son
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	de,(up_l)	; on from l
		ld	h,d
		ld	l,e
		call	at_freq
		push	hl
lh1_update.up:
		pop	hl		; c = prnt[c]
		ld	bc,PRNT-FREQ
		add	hl,bc
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	a,d
		or	e
		jp	nz,lh1_update.node	; too far for jr
		ret

; lh1_rebuild - the tree built again, every leaf's count halved.
;
;   LZHUF.C's reconst. The leaves go to the front, in their order, each
;   count (freq + 1) / 2. Then each node, N_CHAR to NODES - 1, over i and
;   i + 1, its count theirs added, goes in where freq stays in order: at
;   k, after the last count no bigger, the nodes from k on moving up
;   one, freq's and son's. Then each node's children are given it as
;   their parent.
;
; Input:	the tree
; Output:	the tree
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lh1_rebuild:
		ld	de,0		; j: the next leaf's place
		ld	hl,0		; i
lh1_rebuild.gather:
		push	hl
		call	at_son		; a leaf: son[i] >= NODES
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		ld	hl,NODES-1
		or	a
		sbc	hl,bc
		pop	hl
		jr	nc,lh1_rebuild.skip
		push	hl		; son[j] = son[i]
		push	bc
		ld	h,d
		ld	l,e
		call	at_son
		pop	bc
		ld	(hl),c
		inc	hl
		ld	(hl),b
		pop	hl
		push	hl		; freq[j] = (freq[i] + 1) / 2
		call	at_freq
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		inc	bc
		srl	b
		rr	c
		ld	h,d
		ld	l,e
		push	bc
		call	at_freq
		pop	bc
		ld	(hl),c
		inc	hl
		ld	(hl),b
		pop	hl
		inc	de
lh1_rebuild.skip:
		inc	hl
		push	hl
		ld	bc,NODES
		or	a
		sbc	hl,bc
		pop	hl
		jr	nz,lh1_rebuild.gather
		ld	hl,0		; i, over the nodes' children
		ld	(node_i),hl
		ld	de,N_CHAR	; j: the next node
lh1_rebuild.node:
		ld	hl,(node_i)	; f = freq[i] + freq[i + 1]
		call	at_freq
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		inc	hl
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		add	hl,bc
		ld	(rb_f),hl
		ld	h,d		; k: from j - 1 down, while f is
		ld	l,e		;   under freq[k]
		dec	hl
		call	at_freq
		ld	bc,(rb_f)
lh1_rebuild.find:
		ld	a,c		; f - freq[k]: CY, under
		sub	(hl)
		inc	hl
		ld	a,b
		sbc	a,(hl)
		dec	hl
		jr	nc,lh1_rebuild.found
		dec	hl
		dec	hl
		jr	lh1_rebuild.find
lh1_rebuild.found:
		inc	hl		; k + 1: the place
		inc	hl
		push	hl		; -> freq[k]
		call	node_of		; k, a node number
		ld	(rb_k),hl
		ex	de,hl		; the nodes from k to j - 1:
		push	hl		;   j - k of them, 2 bytes each
		or	a
		sbc	hl,de
		add	hl,hl
		ld	(rb_n),hl
		pop	de		; j
		pop	hl		; freq: from k, up one; f at k
		push	de
		ld	de,(rb_f)
		call	rb_insert
		ld	hl,(rb_k)	; son: the same, i at k
		call	at_son
		ld	de,(node_i)
		call	rb_insert
		pop	de
		ld	hl,(node_i)
		inc	hl
		inc	hl
		ld	(node_i),hl
		inc	de
		ld	hl,NODES
		or	a
		sbc	hl,de
		jr	nz,lh1_rebuild.node
		ld	de,0		; the parents: i over every node
lh1_rebuild.parent:
		ld	h,d
		ld	l,e
		call	at_son		; k = son[i]
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		push	de		; prnt[k] = i, and prnt[k + 1]
		ld	h,d		;   if k is a node
		ld	l,e
		ld	d,b
		ld	e,c
		ld	b,h
		ld	c,l
		call	set_prnt
		pop	de
		inc	de
		ld	hl,NODES
		or	a
		sbc	hl,de
		jr	nz,lh1_rebuild.parent
		ret

; rb_insert - a word put in, at an array's place, the rb_n bytes from
;   there moving up 2.
;
; Input:	HL -> the place
;		DE = the word
;		rb_n
; Output:	the array
; Modifies:	AF
;		BC
;		HL
; Scratch:	none

rb_insert:
		ld	bc,(rb_n)
		ld	a,b
		or	c
		jr	z,rb_insert.put
		push	hl
		push	de
		add	hl,bc		; LDDR from the last byte
		dec	hl
		ld	d,h
		ld	e,l
		inc	de
		inc	de
		lddr
		pop	de
		pop	hl
rb_insert.put:
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ret

; set_prnt - a node's or a leaf's parent: prnt[DE] = BC, and for a node
;   (under NODES), prnt[DE + 1] too, its other child.
;
; Input:	DE = the child: a son value
;		BC = the parent
; Output:	prnt
; Modifies:	AF
;		HL
; Scratch:	none

set_prnt:
		ld	h,d
		ld	l,e
		push	bc
		call	at_prnt
		pop	bc
		ld	(hl),c
		inc	hl
		ld	(hl),b
		inc	hl
		push	hl
		ld	hl,NODES-1	; NODES and up: a leaf, one child
		or	a
		sbc	hl,de
		pop	hl
		ret	c
		ld	(hl),c
		inc	hl
		ld	(hl),b
		ret

; at_freq, at_son, at_prnt - where a node's word is in each array.
;
; Input:	HL = the node, or a son value for at_prnt
; Output:	HL -> its word, in the tables' block
; Modifies:	F
;		BC
;		HL
; Scratch:	none

at_freq:
		add	hl,hl
		ld	bc,(freq_at)
		add	hl,bc
		ret
at_son:
		add	hl,hl
		ld	bc,(son_at)
		add	hl,bc
		ret
at_prnt:
		add	hl,hl
		ld	bc,(prnt_at)
		add	hl,bc
		ret

; node_of - the node whose freq word HL points at.
;
; Input:	HL -> freq[n]
; Output:	HL = n
; Modifies:	F
;		BC
;		HL
; Scratch:	none

node_of:
		ld	bc,(freq_at)
		or	a
		sbc	hl,bc
		srl	h
		rr	l
		ret

; lh1_distance - lh5_read's next distance, less 1, from -lh1-: 0 to 4095.
;
;   Its top 6 bits come first, as a code of 3 to 8 bits, which the next
;   8 bits tell: d_rows gives, for each length, the first 8 bits its
;   codes start with and the first number they give. Its low 6 bits
;   follow; get_bits takes both at once.
;
; Input:	the bit reader
; Output:	HL = the distance, less 1
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lh1_distance:
		ld	a,(bitbuf+1)	; the next 8 bits
		ld	c,a
		ld	hl,d_rows+3*5	; the row they are in: from
lh1_distance.row:
		ld	a,c		;   the last
		cp	(hl)
		jr	nc,lh1_distance.found
		dec	hl
		dec	hl
		dec	hl
		jr	lh1_distance.row
lh1_distance.found:
		sub	(hl)		; how far into the row
		inc	hl
		ld	d,(hl)		; D = its first number
		inc	hl
		ld	e,(hl)		; E = its codes' length
		ld	c,a		; one number every 1 << (8 - length)
		ld	a,8
		sub	e
		ld	b,a
		ld	a,c
		inc	b
lh1_distance.shift:
		dec	b
		jr	z,lh1_distance.top
		srl	a
		jr	lh1_distance.shift
lh1_distance.top:
		add	a,d		; the top 6 bits
		ld	(top6),a
		ld	a,e		; the code and the low 6 bits, taken
		add	a,6
		ld	b,a
		call	get_bits
		ld	a,l
		and	3Fh
		ld	e,a
		ld	a,(top6)	; the top 6 bits, then the low 6
		ld	h,a
		ld	l,0
		srl	h
		rr	l
		srl	h
		rr	l
		ld	a,l
		or	e
		ld	l,a
		ret

; d_rows		lh1_distance: for codes of 3 to 8 bits, the first 8
;			bits they start with, the first number they give,
;			and the length; the counts are LZHUF's: 1, 3, 8,
;			12, 24 and 16 numbers
;
d_rows:		defb	00h,0,3,20h,1,4,50h,4,5
		defb	90h,12,6,0C0h,24,7,0F0h,48,8

		dseg

; Variables for lh1.as:
;
; freq_at, son_at, prnt_at
;			the arrays, in the tables' block in page 2
; node_i		lh1_start, lh1_rebuild: the next node's children
; walk_n		lh1_symbol: the bits looked at, not yet taken
; up_c, up_l, up_i	lh1_update: the node and the one it changes places
;			with, and the node's children
; rb_f, rb_k, rb_n	lh1_rebuild: a node's count, its place, the bytes
;			that move up
; top6			lh1_distance: the distance's top 6 bits
;
freq_at:	defs	2
son_at:		defs	2
prnt_at:	defs	2
node_i:		defs	2
walk_n:		defs	1
up_c:		defs	2
up_l:		defs	2
up_i:		defs	2
rb_f:		defs	2
rb_k:		defs	2
rb_n:		defs	2
top6:		defs	1

		end
