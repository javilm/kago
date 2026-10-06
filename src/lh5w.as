; lh5w.as - the -lh5- encoder: KAGO's compression, as LHA 2.x writes it.
;
; lh5.as, in UNKAGO, reads what this writes: a member's data is a
; series of blocks, each its size in symbols, then three code tables,
; then the symbols. A symbol under 256 is a byte (a literal); 256 and up
; would be a match, which note 026 adds: for now every symbol is a
; literal, and each block is the bytes of one read, up to 8 KB.
;
; Each table gives every symbol used a code of 1 to 16 bits: a Huffman
; code, short for a symbol used often, long for one used rarely. Only
; the codes' lengths are sent; the decoder rebuilds the codes from them.
; make_tree builds the lengths from the symbols' counts:
;
;   1. A heap (a binary tree kept in an array, the least used symbol at
;	its top) holds every symbol used.
;   2. The two least used are taken out, and a new node, used as often
;	as both together, goes in. When one node is left, it is the tree's
;	root; a symbol's code is as long as the symbol is deep in it.
;   3. A code longer than 16 bits is not allowed: those are made 16 bits
;	long, and shorter codes made one bit longer until the lengths fit
;	again (make_len, in maketree.c).
;   4. The codes themselves: each length's codes follow one another,
;	in symbol order (make_code).
;
; A block's tables, in the order they are written:
;
;   16 bits	the block's size, in symbols
;   pt		the lengths of the codes that send the c table's lengths
;		(19 symbols: lengths 0 to 16, and three that count runs of
;		zeros), 5 bits for how many, then each in 3 bits or more
;   c		the lengths of the 510 symbols' codes, sent with pt's codes
;   p		the match distances' codes: none yet
;
; A table with a single symbol in it is sent as that symbol alone, and
; its code is 0 bits long. The bits go out highest first, through a
; 1 KB buffer into the archive (archive_write, in kago.as).
;
; The packed size is counted as the buffer is written. When it reaches
; the member's own size, compressing is pointless: the rest of the output
; is not written, and lh5w_block or lh5w_end say so, for KAGO to store
; the member instead. What was written so far is shorter than the member,
; so storing it writes over all of it.
;
; The tables are in a MapperHeap block, mapped into page 2 while they are
; used, mapped again after every write, since MSX-DOS takes page 2 back.
;
; make_tree follows LHa for UNIX 1.14i (reference/lha-unix: src/
; maketree.c), the tables src/huf.c's send_block; mkkago.py's model
; (note 025) is this file, step for step.

		public	lh5w_start
		public	lh5w_block
		public	lh5w_end

		include	common.inc	; MapperHeap's routines
		include	farptr.inc	; fpalloc, derefp

		extrn	archive_write	; kago.as: HL bytes, from DE

C_SYMS		equ	510		; literal and match length symbols
T_SYMS		equ	19		; pt's symbols
CBIT		equ	9		; bits that count c's lengths
TBIT		equ	5		; pt's
PBIT		equ	4		; p's
OUT_SIZE	equ	1024		; outbuf: written at a time

; The tables' block, mapped by map_tables:
C_FREQ		equ	0		; 2*C_SYMS-1 words: each symbol's
					;   count; make_tree's nodes' too
LEFT		equ	2038		; C_SYMS-1 words each: a node's
RIGHT		equ	3056		;   branches, by node - n
DEPTH		equ	4074		; C_SYMS-1 bytes: a node's depth
HEAP		equ	4583		; C_SYMS+1 words: the heap, from 1
C_LEN		equ	5605		; C_SYMS bytes: each code's length
C_CODE		equ	6115		; C_SYMS words: each code, highest
					;   bits first; make_tree's order
					;   of the symbols first
TABLES_SIZE	equ	7135

		cseg

; lh5w_start - get ready to pack a member.
;
;   The first time, the tables' block is allocated, and kept for every
;   member after. The packed size starts at 0, the bit buffer empty.
;
; Input:	DE:HL = the member's size: packing stops when the packed
;		size reaches it
; Output:	CY set = no mapper memory for the tables
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

lh5w_start:
		ld	(limit),hl
		ld	(limit+2),de
		ld	hl,0
		ld	(packed),hl
		ld	(packed+2),hl
		xor	a
		ld	(unpackable),a
		inc	a		; the bit buffer: empty, its
		ld	(bitbuf),a	;   marker bit alone
		ld	hl,outbuf
		ld	(outptr),hl
		ld	a,(tables_ready)
		or	a
		ret	nz		; carry clear from OR A
		fpalloc	tables_fp,TABLES_SIZE	; CY set: out of memory
		ret	c
		ld	a,1
		ld	(tables_ready),a
		call	map_tables	; DE -> the block, in page 2
		ld	hl,C_SYMS	; c's tree: C_SYMS symbols, and
		ld	(c_n),hl	;   where its arrays are
		ld	hl,offsets
		ld	ix,c_freq_at
		ld	b,7
lh5w_start.at:
		ld	a,(hl)
		inc	hl
		push	hl
		ld	h,(hl)
		ld	l,a
		add	hl,de
		ld	(ix+0),l
		ld	(ix+1),h
		inc	ix
		inc	ix
		pop	hl
		inc	hl
		djnz	lh5w_start.at
		or	a		; carry clear: ready
		ret

; lh5w_block - pack a block of literals.
;
;   Each byte's count, then c's tree; then pt's tree, from c's lengths
;   (count_t_freq); then the block: its size, pt's lengths, c's lengths
;   (write_c_len), p's (empty), and each byte's code.
;
; Input:	DE -> the bytes, below 8000h
;		BC = how many: 1 to 8192
; Output:	CY set = the packed size reached the member's: store it
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

lh5w_block:
		ld	(block_at),de
		ld	(block_size),bc
		call	map_tables
		ld	hl,(c_freq_at)	; the counts: 0
		ld	bc,2*C_SYMS
		call	zero
		ld	de,(block_at)
		ld	bc,(block_size)
lh5w_block.count:
		ld	a,(de)
		inc	de
		ld	l,a
		ld	h,0
		add	hl,hl
		push	de
		ld	de,(c_freq_at)
		add	hl,de
		pop	de
		inc	(hl)
		jr	nz,lh5w_block.counted
		inc	hl
		inc	(hl)
lh5w_block.counted:
		dec	bc
		ld	a,b
		or	c
		jr	nz,lh5w_block.count
		ld	hl,c_n		; c's tree
		call	make_tree	; HL = its root
		ld	(c_root),hl
		call	freq_of		; its count: the block's size
		ld	b,16
		call	putbits
		ld	hl,(c_root)
		ld	de,C_SYMS
		or	a
		sbc	hl,de
		jr	c,lh5w_block.one_c	; one symbol only
		call	count_t_freq	; pt's tree, from c's lengths
		ld	hl,t_n
		call	make_tree
		ld	de,T_SYMS
		or	a
		sbc	hl,de
		jr	c,lh5w_block.one_t
		ld	c,T_SYMS	; pt's lengths
		ld	de,TBIT*256+3
		call	write_pt_len
		jr	lh5w_block.c_len
lh5w_block.one_t:
		add	hl,de		; one length only: 0, and it
		push	hl
		ld	hl,0
		ld	b,TBIT
		call	putbits
		pop	hl
		ld	b,TBIT
		call	putbits
lh5w_block.c_len:
		call	write_c_len	; c's lengths
		jr	lh5w_block.p
lh5w_block.one_c:
		ld	hl,0		; c and pt: 0, 0; 0 and the
		ld	b,TBIT		;   symbol
		call	putbits
		ld	hl,0
		ld	b,TBIT
		call	putbits
		ld	hl,0
		ld	b,CBIT
		call	putbits
		ld	hl,(c_root)
		ld	b,CBIT
		call	putbits
lh5w_block.p:
		ld	hl,0		; p: no matches, its one
		ld	b,PBIT		;   symbol 0 (note 026)
		call	putbits
		ld	hl,0
		ld	b,PBIT
		call	putbits
		ld	de,(block_at)	; then each byte's code
		ld	bc,(block_size)
lh5w_block.byte:
		push	bc
		ld	a,(de)
		inc	de
		push	de
		ld	e,a
		ld	d,0
		ld	hl,(c_len_at)
		add	hl,de
		ld	b,(hl)
		ld	hl,(c_code_at)
		add	hl,de
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		call	putcode
		pop	de
		pop	bc
		dec	bc
		ld	a,b
		or	c
		jr	nz,lh5w_block.byte
		ld	a,(unpackable)	; 1: CY set
		rra
		ret

; lh5w_end - the member's last bits, and its packed size.
;
;   The last byte is filled with 0 bits, as LHA does (7 of them, which
;   complete it if any bit is waiting), and the buffer written.
;
; Input:	none
; Output:	CY set = the packed size reached the member's: store it
;		DE:HL = the packed size
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lh5w_end:
		ld	hl,0
		ld	b,7
		call	putbits
		call	flush
		ld	hl,(packed)
		ld	de,(packed+2)
		ld	a,(unpackable)
		rra
		ret

; make_tree - a Huffman tree: every symbol's code length and code.
;
;   maketree.c's make_tree, make_len and make_code. count_leaf, which
;   walks the tree recursively for each depth's number of symbols, is a
;   loop here: a node is always made after its two branches, so going
;   from the root down through the nodes, each one's depth is known
;   before its branches are reached. A depth past 16 counts as 16, as
;   count_leaf counts it.
;
; Input:	HL -> n, then pointers to freq, len and code: 4 words
;		freq: n counts, room for 2n-1
; Output:	HL = the root: n or more, or the one symbol used (0 when
;		none is), whose code is 0 bits long
;		len, code: the n symbols' lengths and codes
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

make_tree:
		ld	de,mt_n
		ld	bc,8
		ldir
		ld	de,(mt_n)	; depth, left, right: by node - n
		ld	hl,(depth_at)
		or	a
		sbc	hl,de
		ld	(mt_depth),hl
		ex	de,hl
		add	hl,hl
		ex	de,hl
		ld	hl,(left_at)
		or	a
		sbc	hl,de
		ld	(mt_left),hl
		ld	hl,(right_at)
		or	a
		sbc	hl,de
		ld	(mt_right),hl
		ld	hl,(mt_n)	; the nodes are numbered from n
		ld	(avail),hl
		ld	ix,(heap_at)
		ld	(ix+2),0	; heap[1] = 0, for none used
		ld	(ix+3),0
		ld	hl,(mt_freq)	; each symbol used goes in
		ld	de,(heap_at)
		inc	de
		inc	de
		ld	bc,0
		ld	ix,(mt_len)
make_tree.leaf:
		ld	(ix+0),0	; its length: 0 for now
		inc	ix
		ld	a,(hl)
		inc	hl
		or	(hl)
		inc	hl
		jr	z,make_tree.unused
		ld	a,c
		ld	(de),a
		inc	de
		ld	a,b
		ld	(de),a
		inc	de
make_tree.unused:
		inc	bc
		push	hl
		ld	hl,(mt_n)
		or	a
		sbc	hl,bc
		pop	hl
		jr	nz,make_tree.leaf
		ex	de,hl		; how many: hs
		ld	de,(heap_at)
		or	a
		sbc	hl,de
		srl	h
		rr	l
		dec	hl
		ld	(hs),hl
		ld	a,h
		or	a
		jr	nz,make_tree.build
		ld	a,l
		cp	2
		jr	nc,make_tree.build
		call	heap_top	; 0 or 1 symbol: no tree
		push	hl
		add	hl,hl
		ld	de,(mt_code)
		add	hl,de
		ld	(hl),0
		inc	hl
		ld	(hl),0
		pop	hl
		ret
make_tree.build:
		srl	h		; the heap: from hs/2 down to 1
		rr	l
make_tree.heapify:
		push	hl
		call	downheap
		pop	hl
		dec	hl
		ld	a,h
		or	l
		jr	nz,make_tree.heapify
		ld	hl,(mt_code)	; the symbols, as they come out
		ld	(sort_at),hl
make_tree.pair:
		call	heap_top	; i: the least used
		ld	(mt_i),hl
		call	sort_leaf
		ld	hl,(hs)		; heap[1] = heap[hs--]
		call	heap_addr
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		call	heap_put
		ld	hl,(hs)
		dec	hl
		ld	(hs),hl
		ld	hl,1
		call	downheap
		call	heap_top	; j: the next least used
		ld	(mt_j),hl
		call	sort_leaf
		ld	hl,(avail)	; a new node: root
		ld	(mt_root),hl
		inc	hl
		ld	(avail),hl
		ld	hl,(mt_i)	; used as often as both
		call	freq_of
		push	hl
		ld	hl,(mt_j)
		call	freq_of
		pop	de
		add	hl,de
		ex	de,hl
		ld	hl,(mt_root)
		add	hl,hl
		ld	bc,(mt_freq)
		add	hl,bc
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	de,(mt_root)	; on the heap's top
		call	heap_put
		ld	hl,1
		call	downheap
		ld	hl,(mt_root)	; its branches: i and j
		add	hl,hl
		push	hl
		ld	de,(mt_left)
		add	hl,de
		ld	de,(mt_i)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		pop	hl
		ld	de,(mt_right)
		add	hl,de
		ld	de,(mt_j)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	hl,(hs)		; until one is left
		ld	a,h
		or	a
		jp	nz,make_tree.pair	; too far for jr
		ld	a,l
		cp	2
		jp	nc,make_tree.pair	; too far for jr
		ld	hl,leaf_num	; each depth's symbols: none
		ld	bc,34
		call	zero
		ld	hl,(mt_root)	; the root: depth 0
		ld	de,(mt_depth)
		add	hl,de
		ld	(hl),0
		ld	hl,(mt_root)
make_tree.depth:
		push	hl		; C = its branches' depth
		ld	de,(mt_depth)
		add	hl,de
		ld	a,(hl)
		inc	a
		cp	17
		jr	c,make_tree.capped
		ld	a,16
make_tree.capped:
		ld	c,a
		pop	hl
		push	hl
		add	hl,hl
		push	hl
		ld	de,(mt_left)
		add	hl,de
		call	branch
		pop	hl
		ld	de,(mt_right)
		add	hl,de
		call	branch
		pop	hl
		ld	de,(mt_n)	; down to node n
		or	a
		sbc	hl,de
		jr	z,make_tree.counted
		add	hl,de
		dec	hl
		jr	make_tree.depth
make_tree.counted:
		ld	hl,0		; make_len: cum, the sum of each
		ld	ix,leaf_num+2	;   count << (16 - depth)
		ld	b,16
make_tree.cum:
		add	hl,hl
		ld	e,(ix+0)
		ld	d,(ix+1)
		add	hl,de
		inc	ix
		inc	ix
		djnz	make_tree.cum
		ld	a,h
		or	l
		jr	z,make_tree.fits
		ex	de,hl		; too deep: leaf_num[16] -= cum
		ld	hl,(leaf_num+32)
		or	a
		sbc	hl,de
		ld	(leaf_num+32),hl
make_tree.adjust:
		ld	hl,leaf_num+30	; the deepest depth under 16
make_tree.find:
		ld	a,(hl)		;   that has symbols
		inc	hl
		or	(hl)
		dec	hl
		jr	nz,make_tree.found
		dec	hl
		dec	hl
		jr	make_tree.find
make_tree.found:
		push	de		; one fewer there, two more
		ld	e,(hl)		;   one deeper
		inc	hl
		ld	d,(hl)
		dec	de
		ld	(hl),d
		dec	hl
		ld	(hl),e
		inc	hl
		inc	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		inc	de
		inc	de
		ld	(hl),d
		dec	hl
		ld	(hl),e
		pop	de
		dec	de
		ld	a,d
		or	e
		jr	nz,make_tree.adjust
make_tree.fits:
		ld	ix,(mt_code)	; the lengths, 16 down to 1,
		ld	hl,leaf_num+32	;   in the symbols' order
		ld	c,16
make_tree.length:
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		dec	hl
		dec	hl
		dec	hl
		push	hl
make_tree.symbol:
		ld	a,d
		or	e
		jr	z,make_tree.next_length
		ld	l,(ix+0)
		ld	h,(ix+1)
		inc	ix
		inc	ix
		push	de
		ld	de,(mt_len)
		add	hl,de
		ld	(hl),c
		pop	de
		dec	de
		jr	make_tree.symbol
make_tree.next_length:
		pop	hl
		dec	c
		jr	nz,make_tree.length
		ld	ix,leaf_num+2	; make_code: each length's first
		ld	iy,first_code+2	;   code
		ld	de,0
		ld	c,1
make_tree.start:
		ld	(iy+0),e
		ld	(iy+1),d
		ld	l,(ix+0)
		ld	h,(ix+1)
		ld	a,16
		sub	c
		jr	z,make_tree.shifted
make_tree.shift:
		add	hl,hl
		dec	a
		jr	nz,make_tree.shift
make_tree.shifted:
		add	hl,de
		ex	de,hl
		inc	ix
		inc	ix
		inc	iy
		inc	iy
		inc	c
		ld	a,c
		cp	17
		jr	nz,make_tree.start
		ld	hl,(mt_len)	; each symbol's code: the next
		ld	ix,(mt_code)	;   of its length's
		ld	bc,(mt_n)
make_tree.code:
		ld	a,(hl)
		inc	hl
		or	a
		jr	z,make_tree.coded	; not used
		push	hl
		push	bc
		ld	l,a
		ld	h,0
		add	hl,hl
		push	hl
		ld	de,first_code
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(ix+0),e
		ld	(ix+1),d
		ex	(sp),hl		; its length's step: weight
		ld	bc,weights-2
		add	hl,bc
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		ex	de,hl
		add	hl,bc
		ex	de,hl
		pop	hl
		ld	(hl),d
		dec	hl
		ld	(hl),e
		pop	bc
		pop	hl
make_tree.coded:
		inc	ix
		inc	ix
		dec	bc
		ld	a,b
		or	c
		jr	nz,make_tree.code
		ld	hl,(mt_root)
		ret

; branch - one branch of a node, in make_tree: a symbol counts at depth
;   C, a node gets C as its depth.
;
; Input:	HL -> the branch, in left or right
;		C = the depth
; Output:	leaf_num, or the node's depth
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

branch:
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	hl,(mt_n)
		ex	de,hl		; HL = the branch, DE = n
		or	a
		sbc	hl,de
		jr	c,branch.symbol
		add	hl,de
		ld	de,(mt_depth)
		add	hl,de
		ld	(hl),c
		ret
branch.symbol:
		ld	l,c
		ld	h,0
		add	hl,hl
		ld	de,leaf_num
		add	hl,de
		inc	(hl)
		ret	nz
		inc	hl
		inc	(hl)
		ret

; downheap - send heap entry i down, below the entries used less often.
;
;   maketree.c's downheap: k, the entry at i, goes down while a branch
;   of it is used less; the lesser branch takes its place.
;
; Input:	HL = i, 1 to hs
;		the heap, hs, mt_freq
; Output:	the heap
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

downheap:
		ld	(dh_i),hl
		call	heap_addr	; k = heap[i], and its count
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	(dh_k),de
		ex	de,hl
		call	freq_of
		ld	(dh_kf),hl
downheap.loop:
		ld	hl,(dh_i)	; j = 2i, while j <= hs
		add	hl,hl
		ld	(dh_j),hl
		ex	de,hl
		ld	hl,(hs)
		or	a
		sbc	hl,de
		jr	c,downheap.done
		jr	z,downheap.one
		ld	hl,(dh_j)	; j < hs: the lesser of j and j+1
		inc	hl
		call	heap_freq
		push	hl
		ld	hl,(dh_j)
		call	heap_freq
		pop	de
		or	a
		sbc	hl,de
		jr	c,downheap.one
		jr	z,downheap.one
		ld	hl,(dh_j)	; j+1 is used less
		inc	hl
		ld	(dh_j),hl
downheap.one:
		ld	hl,(dh_j)	; k used no more than j: k stays
		call	heap_freq
		ld	de,(dh_kf)
		or	a
		sbc	hl,de
		jr	nc,downheap.done
		ld	hl,(dh_i)	; heap[i] = heap[j], i = j
		call	heap_addr
		push	hl
		ld	hl,(dh_j)
		call	heap_addr
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		pop	hl
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ld	hl,(dh_j)
		ld	(dh_i),hl
		jr	downheap.loop
downheap.done:
		ld	hl,(dh_i)	; heap[i] = k
		call	heap_addr
		ld	de,(dh_k)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ret

; heap_addr, heap_freq, heap_top, heap_put, freq_of, sort_leaf - make_tree's
;   small steps.
;
;   heap_addr: HL = i -> HL -> heap[i]. heap_freq: HL = i -> HL = the
;   count of heap[i]. heap_top: HL = heap[1]. heap_put: heap[1] = DE.
;   freq_of: HL = a node -> HL = its count. sort_leaf: HL = a node; a
;   symbol is put next in the order make_len gives lengths in.
;
; Input:	as above; heap_at, mt_freq, mt_n, sort_at
; Output:	as above
; Modifies:	F
;		DE
;		HL
; Scratch:	none

heap_addr:
		add	hl,hl
		ld	de,(heap_at)
		add	hl,de
		ret
heap_freq:
		call	heap_addr
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl
freq_of:
		add	hl,hl
		ld	de,(mt_freq)
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl
		ret
heap_top:
		ld	hl,(heap_at)
		inc	hl
		inc	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl
		ret
heap_put:
		ld	hl,(heap_at)
		inc	hl
		inc	hl
		ld	(hl),e
		inc	hl
		ld	(hl),d
		ret
sort_leaf:
		ex	de,hl		; DE = the node
		ld	hl,(mt_n)	; a symbol: under n
		scf
		sbc	hl,de
		ret	c
		ld	hl,(sort_at)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		ld	(sort_at),hl
		ret

; count_t_freq - pt's counts, from c's lengths.
;
;   huf.c's count_t_freq: a length is sent as symbol length + 2; a run
;   of zeros as 1 or 2 symbols 0 (1 or 2 of them), symbol 1 (3 to 18),
;   symbols 0 and 1 (19), or symbol 2 (20 and more). The zeros after
;   the last length are not sent.
;
; Input:	c_len
; Output:	t_freq
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

count_t_freq:
		ld	hl,t_freq
		ld	bc,2*T_SYMS
		call	zero
		ld	hl,(c_len_at)
		ld	bc,C_SYMS
		call	trim		; BC = the lengths sent
count_t_freq.next:
		ld	a,b
		or	c
		ret	z
		ld	a,(hl)
		inc	hl
		dec	bc
		or	a
		jr	z,count_t_freq.zeros
		add	a,2
		call	t_count
		jr	count_t_freq.next
count_t_freq.zeros:
		ld	de,1		; DE = the run's length
count_t_freq.run:
		ld	a,b
		or	c
		jr	z,count_t_freq.counted
		ld	a,(hl)
		or	a
		jr	nz,count_t_freq.counted
		inc	hl
		dec	bc
		inc	de
		jr	count_t_freq.run
count_t_freq.counted:
		ld	a,d
		or	a
		jr	nz,count_t_freq.long
		ld	a,e
		cp	3
		jr	nc,count_t_freq.mid
		xor	a		; 1 or 2: symbol 0, as many
		call	t_count
		dec	e
		jr	z,count_t_freq.next
		xor	a
		call	t_count
		jr	count_t_freq.next
count_t_freq.mid:
		cp	19
		jr	c,count_t_freq.one	; 3 to 18
		jr	nz,count_t_freq.long
		xor	a		; 19: symbols 0 and 1
		call	t_count
count_t_freq.one:
		ld	a,1
		call	t_count
		jr	count_t_freq.next
count_t_freq.long:
		ld	a,2		; 20 and more
		call	t_count
		jr	count_t_freq.next

; t_count - one more of pt's symbol A.
;
; Input:	A = the symbol
; Output:	t_freq
; Modifies:	AF
; Scratch:	none

t_count:
		push	hl
		push	de
		ld	e,a
		ld	d,0
		ld	hl,t_freq
		add	hl,de
		add	hl,de
		inc	(hl)
		jr	nz,t_count.done
		inc	hl
		inc	(hl)
t_count.done:
		pop	de
		pop	hl
		ret

; trim - how many lengths are sent: the zeros at the end are not.
;
; Input:	HL -> the lengths
;		BC = how many
; Output:	BC = how many, less the zeros at the end
; Modifies:	AF
;		BC
; Scratch:	none

trim:
		push	hl
		add	hl,bc
trim.next:
		ld	a,b
		or	c
		jr	z,trim.done
		dec	hl
		ld	a,(hl)
		or	a
		jr	nz,trim.done
		dec	bc
		jr	trim.next
trim.done:
		pop	hl
		ret

; write_pt_len - pt's (or p's) code lengths.
;
;   huf.c's write_pt_len: how many, in nbit bits; then each length,
;   0 to 6 in 3 bits, 7 and up as that many minus 3 bits: 1s then a 0.
;   After length number "special", the zeros to length 6 are counted
;   in 2 bits.
;
; Input:	C = how many lengths
;		D = nbit
;		E = special: 3 for pt, 0FFh for none
;		pt_len
; Output:	the lengths, written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

write_pt_len:
		ld	(wp_special),de
		ld	hl,pt_len
		ld	b,0
		call	trim
		ld	a,c
		ld	(wp_n),a
		ld	l,c
		ld	h,0
		ld	a,(wp_nbit)
		ld	b,a
		call	putbits
		xor	a
		ld	(wp_i),a
write_pt_len.next:
		ld	a,(wp_n)
		ld	c,a
		ld	a,(wp_i)
		cp	c
		ret	nc		; i may pass n at "special"
		ld	e,a		; k = pt_len[i++]
		ld	d,0
		inc	a
		ld	(wp_i),a
		ld	hl,pt_len
		add	hl,de
		ld	a,(hl)
		cp	7
		jr	nc,write_pt_len.long
		ld	l,a		; 0 to 6: 3 bits
		ld	h,0
		ld	b,3
		call	putbits
		jr	write_pt_len.special
write_pt_len.long:
		sub	3		; 7 and up: k - 3 bits, 1...10
		ld	b,a
		ld	hl,0FFFEh
		call	putbits
write_pt_len.special:
		ld	a,(wp_special)
		ld	c,a
		ld	a,(wp_i)
		cp	c
		jr	nz,write_pt_len.next
write_pt_len.zeros:
		cp	6		; the zeros up to 6, in 2 bits
		jr	nc,write_pt_len.counted
		ld	e,a
		ld	d,0
		ld	hl,pt_len
		add	hl,de
		ld	a,(hl)
		or	a
		ld	a,e
		jr	nz,write_pt_len.counted
		inc	a
		jr	write_pt_len.zeros
write_pt_len.counted:
		ld	(wp_i),a
		sub	3
		ld	l,a
		ld	h,0
		ld	b,2
		call	putbits
		jr	write_pt_len.next

; write_c_len - c's code lengths, sent with pt's codes.
;
;   huf.c's write_c_len: how many, in CBIT bits; then each length, as
;   count_t_freq counted it; a run of 3 to 18 zeros is followed by its
;   length less 3 in 4 bits, 19 zeros by 15 in 4 bits, 20 and more by
;   their length less 20 in CBIT bits.
;
; Input:	c_len, pt_len, pt_code
; Output:	the lengths, written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

write_c_len:
		ld	hl,(c_len_at)
		ld	bc,C_SYMS
		call	trim
		ld	(wc_n),bc
		ld	(wc_at),hl
		ld	h,b
		ld	l,c
		ld	b,CBIT
		call	putbits
write_c_len.next:
		ld	bc,(wc_n)
		ld	a,b
		or	c
		ret	z
		ld	hl,(wc_at)
		ld	a,(hl)
		inc	hl
		dec	bc
		or	a
		jr	z,write_c_len.zeros
		ld	(wc_at),hl
		ld	(wc_n),bc
		add	a,2		; a length: its symbol
		call	pt_code_out
		jr	write_c_len.next
write_c_len.zeros:
		ld	de,1		; DE = the run's length
write_c_len.run:
		ld	a,b
		or	c
		jr	z,write_c_len.counted
		ld	a,(hl)
		or	a
		jr	nz,write_c_len.counted
		inc	hl
		dec	bc
		inc	de
		jr	write_c_len.run
write_c_len.counted:
		ld	(wc_at),hl
		ld	(wc_n),bc
		ld	a,d
		or	a
		jr	nz,write_c_len.long
		ld	a,e
		cp	3
		jr	nc,write_c_len.mid
		push	de		; 1 or 2: symbol 0, as many
		xor	a
		call	pt_code_out
		pop	de
		dec	e
		jr	z,write_c_len.next
		xor	a
		call	pt_code_out
		jr	write_c_len.next
write_c_len.mid:
		cp	19
		jr	z,write_c_len.nineteen
		jr	nc,write_c_len.long
		push	de		; 3 to 18: symbol 1, then the
		ld	a,1		;   length less 3
		call	pt_code_out
		pop	hl
		ld	bc,-3
		add	hl,bc
		ld	b,4
		call	putbits
		jr	write_c_len.next
write_c_len.nineteen:
		xor	a		; 19: symbols 0 and 1, then 15
		call	pt_code_out
		ld	a,1
		call	pt_code_out
		ld	hl,15
		ld	b,4
		call	putbits
		jr	write_c_len.next
write_c_len.long:
		push	de		; 20 and more: symbol 2, then
		ld	a,2		;   the length less 20
		call	pt_code_out
		pop	hl
		ld	bc,-20
		add	hl,bc
		ld	b,CBIT
		call	putbits
		jp	write_c_len.next	; too far for jr

; pt_code_out - pt's code for symbol A.
;
; Input:	A = the symbol
;		pt_len, pt_code
; Output:	its code, written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

pt_code_out:
		ld	e,a
		ld	d,0
		ld	hl,pt_len
		add	hl,de
		ld	b,(hl)
		ld	hl,pt_code
		add	hl,de
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		jr	putcode

; putbits, putcode - write bits, highest first.
;
;   putcode writes the highest B bits of HL, putbits the lowest. The
;   bits gather in bitbuf, which starts as 1: the 1 is a marker, shifted
;   up as bits come in, and when it falls out, 8 bits are there.
;
; Input:	B = how many bits: 0 to 16 (putbits: 1 to 16)
;		HL = the bits
; Output:	written, through outbuf
; Modifies:	AF
;		BC
;		HL
; Scratch:	none

putbits:
		ld	a,16		; the lowest B bits, to the top
		sub	b
		jr	z,putcode
putbits.shift:
		add	hl,hl
		dec	a
		jr	nz,putbits.shift
putcode:
		inc	b
		dec	b
		ret	z		; 0 bits: a symbol alone
		ld	a,(bitbuf)
		ld	c,a
putcode.bit:
		add	hl,hl
		rl	c
		jr	nc,putcode.more
		call	put_byte	; C = 8 bits
		ld	c,1
putcode.more:
		djnz	putcode.bit
		ld	a,c
		ld	(bitbuf),a
		ret

; put_byte - a byte into outbuf; when it is full, it is written.
;
; Input:	C = the byte
; Output:	in outbuf, or written
; Modifies:	AF
; Scratch:	none

put_byte:
		push	hl
		push	de
		ld	hl,(outptr)
		ld	(hl),c
		inc	hl
		ld	(outptr),hl
		ld	de,outbuf+OUT_SIZE
		or	a
		sbc	hl,de
		pop	de
		pop	hl
		ret	nz		; full: on into flush

; flush - write what outbuf holds, and count it.
;
;   When the packed size reaches the member's, nothing more is written:
;   unpackable is set. MSX-DOS takes page 2 for the write, so the
;   tables are mapped again after it.
;
; Input:	outbuf, outptr
; Output:	written; packed, unpackable
;		outptr -> outbuf
; Modifies:	AF
; Scratch:	none

flush:
		push	bc
		push	de
		push	hl
		ld	hl,(outptr)	; HL = how many
		ld	de,outbuf
		ld	(outptr),de
		or	a
		sbc	hl,de
		jr	z,flush.done
		push	hl
		ld	de,(packed)	; packed += them
		add	hl,de
		ld	(packed),hl
		ld	hl,(packed+2)
		ld	de,0
		adc	hl,de
		ld	(packed+2),hl
		ld	hl,(packed)	; reached the member's size?
		ld	de,(limit)
		or	a
		sbc	hl,de
		ld	hl,(packed+2)
		ld	de,(limit+2)
		sbc	hl,de
		pop	hl
		jr	c,flush.write
		ld	a,1		; yes: no more is written
		ld	(unpackable),a
		jr	flush.done
flush.write:
		ld	de,outbuf
		call	archive_write
		call	map_tables
flush.done:
		pop	hl
		pop	de
		pop	bc
		ret

; map_tables - the tables' block in page 2.
;
; Input:	tables_fp
; Output:	DE -> the block
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

map_tables:
		derefp	tables_fp
		ex	de,hl
		ret

; zero - fill BC bytes with 0.
;
; Input:	HL -> them
;		BC = how many: 2 or more
; Output:	all 0
; Modifies:	BC
;		DE
;		HL
; Scratch:	none

zero:
		ld	(hl),0
		ld	d,h
		ld	e,l
		inc	de
		dec	bc
		ldir
		ret

; The constants:
;
; offsets		where the arrays are in the tables' block, in the
;			order of c_freq_at to heap_at
; t_n			pt's tree, for make_tree: T_SYMS symbols, its arrays
; weights		make_code: the step between codes of each length,
;			1 to 16 bits
;
offsets:	defw	C_FREQ,C_LEN,C_CODE,LEFT,RIGHT,DEPTH,HEAP
t_n:		defw	T_SYMS,t_freq,pt_len,pt_code
weights:	defw	8000h,4000h,2000h,1000h,800h,400h,200h,100h
		defw	80h,40h,20h,10h,8,4,2,1

		dseg

; Variables:
;
; tables_ready		not 0 once the tables' block is allocated
; tables_fp		its far pointer
; c_n, c_freq_at, c_len_at, c_code_at
;			c's tree, for make_tree: C_SYMS, and its arrays'
;			addresses in page 2
; left_at, right_at, depth_at, heap_at
;			make_tree's arrays, in page 2
; limit			the member's size, 4 bytes
; packed		the packed size so far, 4 bytes
; unpackable		1 once packed reached limit
; bitbuf		the bits waiting, and the marker above them
; outptr		where the next byte goes in outbuf
; block_at, block_size	lh5w_block: the bytes, and how many
; c_root		c's tree's root
; mt_n, mt_freq, mt_len, mt_code
;			make_tree: the tree it is making
; mt_left, mt_right, mt_depth
;			left_at and right_at less 2n, depth_at less n:
;			indexed by node
; avail, hs, sort_at	the next node, the heap's size, where the next
;			symbol out goes in code
; mt_i, mt_j, mt_root	the two nodes taken out, and the new one
; dh_i, dh_j, dh_k, dh_kf
;			downheap: i, j, k and k's count
; leaf_num, first_code
;			how many symbols at each depth, and each length's
;			next code: 17 words each, 0 not used
; t_freq		pt's counts: 2*T_SYMS-1 words
; pt_len, pt_code	pt's lengths and codes: T_SYMS each
; wp_special, wp_nbit, wp_n, wp_i
;			write_pt_len: special and nbit, how many, i
; wc_n, wc_at		write_c_len: how many are left, and where
; outbuf		the bytes for the archive: OUT_SIZE, in the buffers
;			segment
;
tables_ready:	defs	1
tables_fp:	defs	4
c_n:		defs	2
c_freq_at:	defs	2
c_len_at:	defs	2
c_code_at:	defs	2
left_at:	defs	2
right_at:	defs	2
depth_at:	defs	2
heap_at:	defs	2
limit:		defs	4
packed:		defs	4
unpackable:	defs	1
bitbuf:		defs	1
outptr:		defs	2
block_at:	defs	2
block_size:	defs	2
c_root:		defs	2
mt_n:		defs	2
mt_freq:	defs	2
mt_len:		defs	2
mt_code:	defs	2
mt_left:	defs	2
mt_right:	defs	2
mt_depth:	defs	2
avail:		defs	2
hs:		defs	2
sort_at:	defs	2
mt_i:		defs	2
mt_j:		defs	2
mt_root:	defs	2
dh_i:		defs	2
dh_j:		defs	2
dh_k:		defs	2
dh_kf:		defs	2
leaf_num:	defs	34
first_code:	defs	34
t_freq:		defs	4*T_SYMS-2
pt_len:		defs	T_SYMS
pt_code:	defs	2*T_SYMS
wp_special:	defs	1
wp_nbit:	defs	1
wp_n:		defs	1
wp_i:		defs	1
wc_n:		defs	2
wc_at:		defs	2

		dseg	buffers
outbuf:		defs	OUT_SIZE

		end
