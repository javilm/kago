; lh5.as - the -lh4- to -lh7- decoder: LZSS with static Huffman codes,
; as LHA 2.x writes it.
;
; A member's data is a series of blocks. Each block starts with its
; size in symbols and three code tables: the lengths of the codes that
; send the next table's lengths, the codes for the 510 literals and
; match lengths, and the codes for the kinds of match distance. A
; symbol under 256 is a byte; 256 and up is a match of (symbol - 253)
; bytes, copied from as far back in the output as the distance says:
; the window. The four methods differ only in how far back that can
; be, and so in how many kinds of distance there are:
;
;	-lh4-, -lh5-	 8 KB*	14 kinds, counted in 4 bits
;	-lh6-		32 KB	16 kinds, counted in 5 bits
;	-lh7-		64 KB	17 kinds, counted in 5 bits
;
; (* -lh4-'s encoder only looks 4 KB back; its data is laid out as
; -lh5-'s, and decodes the same way.)
;
; Symbols are decoded through lookup tables, as LHA does: the next 12
; bits (8 for distances) index a table that holds the symbol, or, for a
; longer code, the root of a small tree walked one bit at a time. The
; tables take 12780 bytes, in a MapperHeap block.
;
; The output goes, a part of up to 8 KB at a time, into the caller's
; buffer below 8000h, which MSX-DOS can write from: unkago's
; copy_buffer. The window is a ring of 8, 32 or 64 KB in whole mapper
; segments (segalloc); each part is copied into it, in one go, when the
; next part is asked for. So a match whose source is in the current
; part copies within the buffer, and only one that reaches further back
; reads the ring. LHA starts the window full of spaces; here a source
; before the first byte of output reads as a space instead, which saves
; filling up to 64 KB for every member.
;
; Page 2 holds the tables or one segment of the ring, never both, so
; "page2" says which, and each is mapped in only when it is not there
; already. MSX-DOS needs page 2 back for every call, which the dos macro
; gives it; after a read, the tables are mapped in again.
;
; The formats and the table builder follow LHa for UNIX 1.14i
; (reference/lha-unix: src/huf.c, maketbl.c, slide.c), checked step
; for step against lhasa through a Python model of this file.

LH5_INCLUDED	equ	1		; lh5.inc: not our names as extrn

		public	lh5_start
		public	lh5_read
		public	lh5_finish

		include	common.inc	; dos, and MapperHeap's routines
		include	farptr.inc	; fpalloc, derefp
		include	lzh.inc		; lzh_read, lzh_skip_data
		include	lh5.inc		; LH5_BAD

		include	msxdos.inc	; BDOS, "system"
		include	errors.inc	; .NORAM
		include	ascii.inc	; CHR_SPACE

C_SYMS		equ	510		; literal and length symbols
T_SYMS		equ	19		; code length symbols
TBIT		equ	5		; bits that count T_SYMS's lengths
CBIT		equ	9		; bits that count C_SYMS's lengths
NPT		equ	128		; room for T_SYMS's or p_syms' lengths
IN_SIZE		equ	2048		; in_buf: the data read at a time
SEG_MASK	equ	3Fh		; an offset's high byte, in a segment
PAGE_TABLES	equ	4		; page2: the tables are mapped in
PAGE_NONE	equ	0FFh		; page2: unknown, after MSX-DOS

; The tables' block, mapped at "tables":
C_TABLE		equ	0		; 4096 words: 12 bits to a symbol
PT_TABLE	equ	8192		; 256 words: 8 bits to a symbol
LEFT		equ	8704		; 1019 words: the trees' 0 branches
RIGHT		equ	10742		; 1019 words: their 1 branches
TABLES_SIZE	equ	12780
ROW		equ	34		; mt_count, mt_weight, mt_start:
					;   17 words each, side by side

		cseg

; lh5_start - get ready to decode the member just read.
;
;   The method sets the kinds of distance and the window's size. The
;   first time, the tables' block is allocated, and the window's
;   segments as a member first needs them; all are kept for the members
;   after. The ring starts empty, the bit reader is primed with 16 bits,
;   and the first lh5_read starts a block.
;
; Input:	B = the method's digit: "4" to "7"
;		DE -> the output buffer, 8 KB, below 8000h
;		lzh_packed (lzh.as): the size of the member's data
; Output:	A = 0, ready
;		A = .NORAM: no mapper memory for the tables or the window
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lh5_start:
		ld	(outbuf),de
		ld	a,b		; its row in lh_methods
		sub	"4"
		ld	c,a
		add	a,a
		add	a,a
		add	a,c		; 5 bytes a row
		ld	e,a
		ld	d,0
		ld	hl,lh_methods
		add	hl,de
		ld	de,p_syms	; p_syms, p_bits, win_mask, win_segs
		ld	bc,5
		ldir
		ld	a,(tables_ready)
		or	a
		jr	nz,lh5_start.window
		fpalloc	tables_fp,TABLES_SIZE	; CY set: out of memory
		ld	a,.NORAM	; COMMAND2: *** Not enough memory
		ret	c
		ld	a,1
		ld	(tables_ready),a
lh5_start.window:
		ld	a,(win_have)	; the segments still to get
		ld	hl,win_segs
		cp	(hl)
		jr	nc,lh5_start.ready
		add	a,a		; its far pointer: win_fp + 4 * n
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,win_fp
		add	hl,de
		call	segalloc	; CY set: none free
		ld	a,.NORAM
		ret	c
		ld	hl,win_have
		inc	(hl)
		jr	lh5_start.window
lh5_start.ready:
		ld	hl,(lzh_packed)	; the data still to read
		ld	(lh5_left),hl
		ld	hl,(lzh_packed+2)
		ld	(lh5_left+2),hl
		ld	hl,0
		ld	(in_count),hl
		ld	(blocksize),hl
		ld	(match_left),hl
		ld	(bitbuf),hl
		ld	(win_head),hl
		ld	(part_len),hl
		xor	a
		ld	(bitcnt),a
		ld	(lh5_error),a
		ld	(wrapped),a
		call	map_tables
		ld	b,16		; the first 16 bits
		call	fill_bits
		ld	a,(lh5_error)
		ret

; lh5_read - decode the next HL bytes of the member into the buffer.
;
;   The part before, if any, goes into the ring first. A match can end
;   beyond the part asked for: what is left of it, and its distance,
;   are kept for the next call.
;
; Input:	HL = how many, 1 to 8192
; Output:	A = 0, and the bytes at the start of the buffer
;		A = LH5_BAD: the data is not valid
;		A = LZH_TRUNCATED, or an MSX-DOS error, from reading
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

lh5_read:
		ld	(want),hl
		ld	a,PAGE_NONE	; MSX-DOS has had page 2
		ld	(page2),a
		call	ring_append	; the part before, into the ring
		ld	hl,0
		ld	(pos),hl
lh5_read.next:
		ld	a,(lh5_error)
		or	a
		ret	nz		; a bad table, or a failed read
		ld	hl,(pos)
		ld	de,(want)
		or	a
		sbc	hl,de
		jr	nc,lh5_read.done	; as many as asked for
		ld	hl,(match_left)
		ld	a,h
		or	l
		jr	nz,lh5_read.copy	; a match not finished
		call	decode_c	; HL = the symbol
		ld	a,h
		or	a
		jr	nz,lh5_read.match	; 256 and up
		ld	a,l		; a byte
		call	put_byte
		jr	lh5_read.next
lh5_read.match:
		ld	de,256-3	; the length: 3 to 256
		or	a
		sbc	hl,de
		ld	(match_left),hl
		call	decode_p	; HL = the distance, less 1
		ld	(match_dist),hl
lh5_read.copy:
		ld	hl,(match_left)
		dec	hl
		ld	(match_left),hl
		ld	hl,(match_dist)	; in this part: distance < pos
		ld	de,(pos)
		or	a
		sbc	hl,de
		jr	c,lh5_read.near
		ex	de,hl		; further back: the ring, at
		ld	hl,(win_head)	; win_head - (distance - pos) - 1
		or	a
		sbc	hl,de
		dec	hl
		call	ring_byte	; A = the byte
		jr	lh5_read.put
lh5_read.near:
		ld	hl,(pos)	; buffer[pos - distance - 1]
		ld	de,(match_dist)
		or	a
		sbc	hl,de
		dec	hl
		ld	de,(outbuf)
		add	hl,de
		ld	a,(hl)
lh5_read.put:
		call	put_byte
		jr	lh5_read.next
lh5_read.done:
		ld	hl,(want)	; for the ring, next time
		ld	(part_len),hl
		xor	a
		ret

; put_byte - A at the buffer's pos, and pos one on.
;
; Input:	A, pos, outbuf
; Output:	pos + 1
; Modifies:	DE
;		HL
; Scratch:	none

put_byte:
		ld	hl,(pos)
		ld	de,(outbuf)
		add	hl,de
		ld	(hl),a
		ld	hl,(pos)
		inc	hl
		ld	(pos),hl
		ret

; ring_byte - the byte at a place in the ring.
;
;   Until the ring has wrapped once, a place at or after win_head was
;   never written: it is before the member's first byte, a space.
;
; Input:	HL = the place, not yet masked
; Output:	A = the byte
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

ring_byte:
		ld	a,(win_mask+1)	; masked to the ring's size
		and	h
		ld	h,a
		ld	a,(win_mask)
		and	l
		ld	l,a
		ld	a,(wrapped)
		or	a
		jr	nz,ring_byte.written
		ld	de,(win_head)
		or	a
		sbc	hl,de
		add	hl,de
		ld	a,CHR_SPACE
		ret	nc		; at or after win_head: a space
ring_byte.written:
		push	hl
		ld	a,h		; segment place >> 14
		rlca
		rlca
		and	3
		call	map_window
		pop	hl
		ld	a,h		; 8000h + the offset in it
		and	SEG_MASK
		or	80h
		ld	h,a
		ld	a,(hl)
		ret

; ring_append - the part last decoded, from the buffer into the ring.
;
;   It is copied in pieces that end where a segment or the ring does,
;   whichever comes first, each with one LDIR. The ring wraps at its
;   size; win_head is where the next byte goes.
;
; Input:	part_len bytes at outbuf, win_head
; Output:	win_head moved on, wrapped set once it has wrapped
;		part_len = 0
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

ring_append:
		ld	hl,(part_len)
		ld	(app_left),hl
		ld	hl,(outbuf)
		ld	(app_src),hl
ring_append.piece:
		ld	hl,(app_left)
		ld	a,h
		or	l
		jr	z,ring_append.done
		ld	hl,(win_head)	; room to the segment's end, less 1
		ld	a,h
		and	SEG_MASK
		ld	h,a
		ex	de,hl
		ld	hl,3FFFh
		or	a
		sbc	hl,de
		push	hl
		ld	hl,(win_mask)	; room to the ring's end, less 1
		ld	de,(win_head)
		or	a
		sbc	hl,de
		pop	de		; the smaller of the two, plus 1
		or	a
		sbc	hl,de
		add	hl,de
		jr	c,ring_append.room
		ex	de,hl
ring_append.room:
		inc	hl
		ld	de,(app_left)	; and no more than is left
		or	a
		sbc	hl,de
		add	hl,de
		jr	c,ring_append.size
		ex	de,hl
ring_append.size:
		ld	(app_n),hl
		ld	a,(win_head+1)	; map the segment
		rlca
		rlca
		and	3
		call	map_window
		ld	hl,(win_head)	; DE -> 8000h + the offset
		ld	a,h
		and	SEG_MASK
		or	80h
		ld	h,a
		ex	de,hl
		ld	hl,(app_src)
		ld	bc,(app_n)
		ldir
		ld	(app_src),hl
		ld	hl,(win_head)	; win_head + n, wrapped
		ld	bc,(app_n)
		add	hl,bc
		ld	a,(win_mask+1)
		and	h
		ld	h,a
		ld	a,(win_mask)
		and	l
		ld	l,a
		ld	(win_head),hl
		ld	a,h
		or	l
		jr	nz,ring_append.left
		ld	a,1		; back at 0: it has wrapped
		ld	(wrapped),a
ring_append.left:
		ld	hl,(app_left)
		ld	bc,(app_n)
		or	a
		sbc	hl,bc
		ld	(app_left),hl
		jp	ring_append.piece	; too far for jr
ring_append.done:
		ld	(part_len),hl	; HL = 0
		ret

; lh5_finish - pass over what is left of the member's data, unread.
;
;   The decoder reads ahead, IN_SIZE bytes at a time, but never past
;   the member's data; what it has not read is skipped, so that the
;   archive is at the next header.
;
; Input:	lh5_left
; Output:	A = 0, or what lzh_skip_data returns
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

lh5_finish:
		ld	hl,(lh5_left)
		ld	(lzh_packed),hl
		ld	hl,(lh5_left+2)
		ld	(lzh_packed+2),hl
		jp	lzh_skip_data	; from here, the rest

; tables_in - the tables in page 2, if they are not there already.
;
;   map_tables, its second entry, maps them in whatever page 2 holds.
;
; Input:	page2, tables_fp
; Output:	tables -> the block, in page 2; page2 = PAGE_TABLES
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

tables_in:
		ld	a,(page2)
		cp	PAGE_TABLES
		ret	z
map_tables:
		derefp	tables_fp	; HL -> the block
		ld	(tables),hl
		ld	a,PAGE_TABLES
		ld	(page2),a
		ret

; map_window - segment A of the ring in page 2, if it is not there
;   already.
;
; Input:	A = the segment, 0 to 3
;		page2, win_fp
; Output:	page2 = A
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

map_window:
		ld	hl,page2
		cp	(hl)
		ret	z
		ld	(hl),a
		add	a,a		; win_fp + 4 * A
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,win_fp
		add	hl,de
		jp	deref		; maps it; BC is kept

; fill_bits - take B bits off the top of bitbuf, and as many in at the
;   bottom, from the data.
;
;   The data comes a byte at a time, through bitsub, whose bitcnt bits
;   not yet used are its top ones.
;
; Input:	B = how many, 0 to 16
; Output:	bitbuf
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

fill_bits:
		ld	a,b
		or	a
		ret	z
		ld	hl,(bitbuf)
		ld	a,(bitsub)
		ld	c,a		; C = bitsub
		ld	a,(bitcnt)
		ld	d,a		; D = its bits left
fill_bits.bit:
		ld	a,d
		or	a
		jr	nz,fill_bits.have
		push	hl
		push	bc
		call	next_byte	; A = the next byte
		pop	bc
		pop	hl
		ld	c,a
		ld	d,8
fill_bits.have:
		sla	c		; its top bit
		adc	hl,hl		; into the bottom of bitbuf
		dec	d
		djnz	fill_bits.bit
		ld	(bitbuf),hl
		ld	a,c
		ld	(bitsub),a
		ld	a,d
		ld	(bitcnt),a
		ret

; next_byte - the next byte of the member's data.
;
;   in_buf is refilled from the archive, IN_SIZE bytes at a time, or
;   what is left; once the data is used up, it is 0s, which the decoder
;   may look at but not use. A failed read is kept in lh5_error, and
;   gives 0s too.
;
; Input:	in_ptr, in_count, lh5_left
; Output:	A = the byte
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

next_byte:
		ld	hl,(in_count)
		ld	a,h
		or	l
		jr	z,next_byte.refill
next_byte.take:
		dec	hl
		ld	(in_count),hl
		ld	hl,(in_ptr)
		ld	a,(hl)
		inc	hl
		ld	(in_ptr),hl
		ret
next_byte.refill:
		ld	hl,(lh5_left+2)
		ld	a,h
		or	l
		ld	hl,IN_SIZE
		jr	nz,next_byte.amount	; 64 KB or more left
		ld	de,(lh5_left)
		ld	a,d
		or	e
		ret	z		; nothing left: A = 0
		or	a		; HL = IN_SIZE, DE = left
		sbc	hl,de
		add	hl,de
		jr	c,next_byte.amount	; more than IN_SIZE left
		ex	de,hl		; HL = what is left
next_byte.amount:
		ld	(in_count),hl
		ex	de,hl		; lh5_left - the amount
		ld	hl,(lh5_left)
		or	a
		sbc	hl,de
		ld	(lh5_left),hl
		ld	hl,(lh5_left+2)
		ld	bc,0
		sbc	hl,bc
		ld	(lh5_left+2),hl
		ld	de,in_buf
		ld	(in_ptr),de
		ld	hl,(in_count)
		call	lzh_read	; A = 0, or what went wrong
		push	af
		call	map_tables	; page 2 back from MSX-DOS
		pop	af
		or	a
		ld	hl,(in_count)
		jr	z,next_byte.take
		ld	(lh5_error),a
		ld	hl,0
		ld	(in_count),hl
		xor	a
		ret

; peek_bits - the top B bits of bitbuf, without taking them.
;
; Input:	B = how many, 0 to 16
; Output:	HL = them
; Modifies:	AF
;		C
;		HL
; Scratch:	none

peek_bits:
		ld	hl,(bitbuf)
		ld	a,16
		sub	b
		ret	z
		ld	c,a
peek_bits.shift:
		srl	h
		rr	l
		dec	c
		jr	nz,peek_bits.shift
		ret

; get_bits - the top B bits of bitbuf, taken.
;
; Input:	B = how many, 0 to 16
; Output:	HL = them
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

get_bits:
		call	peek_bits
		push	hl
		call	fill_bits
		pop	hl
		ret

; decode_c - the next literal or length symbol, 0 to 509.
;
;   A new block, when the last one is used up, starts with its size
;   and its three tables. The symbol is c_table's entry for the next 12
;   bits; one of C_SYMS and up is a tree's root, walked with the bits after
;   them.
;
; Input:	the bit reader, the tables
; Output:	HL = the symbol
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

decode_c:
		call	tables_in	; page 2 may hold the ring
		ld	hl,(blocksize)
		ld	a,h
		or	l
		call	z,read_block
		ld	hl,(blocksize)
		dec	hl
		ld	(blocksize),hl
		ld	hl,(bitbuf)	; the next 12 bits
		ld	b,4
decode_c.shift:
		srl	h
		rr	l
		djnz	decode_c.shift
		add	hl,hl		; a word each
		ld	de,(tables)	; C_TABLE is at 0
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)		; DE = the entry
		ld	hl,C_SYMS-1
		or	a
		sbc	hl,de
		jr	c,decode_c.tree	; C_SYMS and up: a tree
decode_c.length:
		ld	hl,c_len
		add	hl,de
		ld	b,(hl)
		push	de
		call	fill_bits	; the code's bits, taken
		pop	hl
		ret
decode_c.tree:
		push	de
		ld	b,12
		call	fill_bits
		pop	de
		ld	hl,C_SYMS
		ld	bc,8000h
		call	tree_walk	; DE = the symbol
		ld	hl,c_len
		add	hl,de
		ld	a,(hl)
		sub	12		; the rest of the code
		ld	b,a
		push	de
		call	fill_bits
		pop	hl
		ret

; decode_p - the next match's distance, less 1: 0 to 65535.
;
;   The symbol, through pt_table and the next 8 bits, is how many bits
;   the distance has; its top bit is always 1, so it is not sent, and
;   the rest follow.
;
; Input:	the bit reader, the tables
; Output:	HL = the distance, less 1
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

decode_p:
		call	tables_in
		ld	a,(bitbuf+1)	; the next 8 bits
		ld	l,a
		ld	h,0
		add	hl,hl
		ld	de,(tables)
		add	hl,de
		ld	de,PT_TABLE
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)		; DE = the entry
		ld	a,(p_syms)
		ld	l,a
		ld	h,0
		dec	hl
		or	a
		sbc	hl,de
		jr	nc,decode_p.length
		push	de		; p_syms and up: a tree
		ld	b,8
		call	fill_bits
		pop	de
		ld	a,(p_syms)
		ld	l,a
		ld	h,0
		ld	bc,8000h
		call	tree_walk
		ld	hl,pt_len
		add	hl,de
		ld	a,(hl)
		sub	8
		jr	decode_p.take
decode_p.length:
		ld	hl,pt_len
		add	hl,de
		ld	a,(hl)
decode_p.take:
		ld	b,a
		push	de
		call	fill_bits
		pop	de		; E = the symbol
		ld	a,e
		or	a
		ld	h,a
		ld	l,a
		ret	z		; 0: a distance of 1
		dec	a		; 1 shifted left symbol - 1 times...
		ld	b,a
		ld	hl,1
		jr	z,decode_p.bits
decode_p.power:
		add	hl,hl
		djnz	decode_p.power
		ld	b,e		; ...plus symbol - 1 bits
		dec	b
decode_p.bits:
		push	hl
		call	get_bits
		pop	de
		add	hl,de
		ret

; tree_walk - from a tree's root to its symbol, a bit at a time.
;
;   The bits are looked at, not taken: the caller takes the code's
;   length once the symbol is known. A walk that runs out of bits is
;   a table that is not valid.
;
; Input:	DE = the root
;		HL = the symbols' count: anything under it is one
;		BC = the first bit to look at, as a mask on bitbuf
; Output:	DE = the symbol
;		lh5_error = LH5_BAD, and DE = 0, for a walk with no end
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

tree_walk:
		ld	(walk_limit),hl
		ld	(walk_mask),bc
tree_walk.step:
		ld	hl,(bitbuf)
		ld	a,(walk_mask+1)
		and	h
		ld	c,a
		ld	a,(walk_mask)
		and	l
		or	c		; NZ: the bit is 1
		ld	hl,LEFT
		jr	z,tree_walk.side
		ld	hl,RIGHT
tree_walk.side:
		ld	bc,(tables)
		add	hl,bc
		ex	de,hl
		add	hl,hl		; the node's word
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)		; DE = the branch
		ld	hl,(walk_mask)
		srl	h
		rr	l
		ld	(walk_mask),hl
		ld	hl,(walk_limit)
		dec	hl
		or	a
		sbc	hl,de
		ret	nc		; under the count: a symbol
		ld	hl,(walk_mask)
		ld	a,h
		or	l
		jr	nz,tree_walk.step
		ld	a,LH5_BAD	; no bits left: not valid
		ld	(lh5_error),a
		ld	de,0
		ret

; read_block - a block's size and its three tables.
;
; Input:	the bit reader
; Output:	blocksize, the tables
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

read_block:
		ld	b,16
		call	get_bits
		ld	(blocksize),hl
		ld	b,T_SYMS	; the code length codes
		ld	c,TBIT
		ld	d,3		; three can be followed by 0s
		call	read_pt_len
		call	read_c_len
		ld	a,(p_syms)	; the distance codes
		ld	b,a
		ld	a,(p_bits)
		ld	c,a
		ld	d,0FFh		; none
		jp	read_pt_len

; read_pt_len - the code lengths for T_SYMS or p_syms symbols, and
;   pt_table.
;
;   C bits give how many lengths follow. None means a single symbol,
;   whose number follows: every entry is it, with a length of 0. Each
;   length is 3 bits, 0 to 6; 7 means 7 and one more for each 1 bit
;   after it, then a 0. After the length at "special", 2 bits give how
;   many 0 lengths follow.
;
; Input:	B = the symbols' count
;		C = the bits that count the lengths
;		D = the length after which 0s are counted, 0FFh for none
; Output:	pt_len, and pt_table through make_table
;		lh5_error = LH5_BAD for a table that is not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

read_pt_len:
		ld	a,b
		ld	(pt_n),a
		ld	a,c
		ld	(pt_nbit),a
		ld	a,d
		ld	(pt_special),a
		ld	b,c
		call	get_bits	; HL = how many lengths
		ld	a,h
		or	l
		jr	nz,read_pt_len.lengths
		ld	a,(pt_nbit)	; one symbol only
		ld	b,a
		call	get_bits	; L = it
		ld	a,(pt_n)
		ld	b,a
		ld	a,l
		cp	b
		jp	nc,bad_table	; no such symbol
		ld	hl,pt_len	; all the lengths 0
		ld	b,NPT
read_pt_len.zero:
		ld	(hl),0
		inc	hl
		djnz	read_pt_len.zero
		ld	e,a		; every entry: the symbol
		ld	d,0
		ld	hl,(tables)
		ld	bc,PT_TABLE
		add	hl,bc
		ld	b,0		; 256 entries
read_pt_len.fill:
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		djnz	read_pt_len.fill
		ret
read_pt_len.lengths:
		ld	a,h		; the count, at most NPT
		or	a
		ld	a,l
		jr	nz,read_pt_len.cap
		cp	NPT+1
		jr	c,read_pt_len.count
read_pt_len.cap:
		ld	a,NPT
read_pt_len.count:
		ld	(pt_count),a
		xor	a
		ld	(pt_i),a
read_pt_len.next:
		ld	a,(pt_count)
		ld	b,a
		ld	a,(pt_i)
		cp	b
		jr	nc,read_pt_len.rest
		ld	b,3
		call	peek_bits	; L = 0 to 7
		ld	a,l
		cp	7
		jr	z,read_pt_len.long
		ld	(pt_c),a
		ld	b,3
		call	fill_bits
		jr	read_pt_len.store
read_pt_len.long:
		ld	(pt_c),a	; 7, and 1 more for each 1 bit
		ld	hl,(bitbuf)
		ld	de,1000h	; the bit after the three
read_pt_len.unary:
		ld	a,d
		and	h
		ld	c,a
		ld	a,e
		and	l
		or	c
		jr	z,read_pt_len.counted	; a 0 ends it
		ld	a,(pt_c)
		inc	a
		ld	(pt_c),a
		srl	d
		rr	e
		ld	a,d
		or	e
		jr	nz,read_pt_len.unary	; until the bits run out
read_pt_len.counted:
		ld	a,(pt_c)
		sub	3		; the 3, the 1s and the 0
		ld	b,a
		call	fill_bits
read_pt_len.store:
		ld	hl,(pt_i)	; L = i
		ld	h,0
		ld	de,pt_len
		add	hl,de
		ld	a,(pt_c)
		ld	(hl),a
		ld	a,(pt_i)
		inc	a
		ld	(pt_i),a
		ld	hl,pt_special
		cp	(hl)
		jr	nz,read_pt_len.next
		ld	b,2		; then 0 to 3 0s
		call	get_bits
		ld	b,l
		inc	b
read_pt_len.zeros:
		dec	b
		jr	z,read_pt_len.next
		ld	a,(pt_i)
		cp	NPT
		jr	nc,read_pt_len.next
		ld	l,a
		ld	h,0
		ld	de,pt_len
		add	hl,de
		ld	(hl),0
		inc	a
		ld	(pt_i),a
		jr	read_pt_len.zeros
read_pt_len.rest:
		ld	a,(pt_n)	; 0s up to the count of symbols
		ld	b,a
		ld	a,(pt_i)
read_pt_len.pad:
		cp	b
		jr	nc,read_pt_len.make
		ld	l,a
		ld	h,0
		ld	de,pt_len
		add	hl,de
		ld	(hl),0
		inc	a
		jr	read_pt_len.pad
read_pt_len.make:
		ld	a,(pt_n)
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

; read_c_len - the code lengths for the C_SYMS literal and length symbols,
;   and c_table.
;
;   CBIT bits give how many lengths follow; none means a single symbol,
;   as for read_pt_len. Each length comes through pt_table: symbols 3
;   to 18 are the lengths 1 to 16; 0 is one 0 length, 1 is 3 to 18 of
;   them (4 bits more), 2 is 20 to 531 (CBIT bits more).
;
; Input:	the bit reader, pt_table and pt_len
; Output:	c_len, and c_table through make_table
;		lh5_error = LH5_BAD for a table that is not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

read_c_len:
		ld	b,CBIT
		call	get_bits	; HL = how many lengths
		ld	a,h
		or	l
		jr	nz,read_c_len.lengths
		ld	b,CBIT		; one symbol only
		call	get_bits	; HL = it
		ld	de,C_SYMS-1
		ex	de,hl
		or	a
		sbc	hl,de
		jp	c,bad_table	; no such symbol
		push	de
		ld	hl,c_len	; all the lengths 0
		ld	de,c_len+1
		ld	(hl),0
		ld	bc,C_SYMS-1
		ldir
		pop	de		; every entry: the symbol
		ld	hl,(tables)
		ld	bc,4096
read_c_len.fill:
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,read_c_len.fill
		ret
read_c_len.lengths:
		ld	de,C_SYMS	; the count, at most C_SYMS
		ex	de,hl
		or	a
		sbc	hl,de
		add	hl,de
		jr	c,read_c_len.count	; C_SYMS < the count: C_SYMS
		ex	de,hl
read_c_len.count:
		ld	(c_count),hl
		ld	hl,0
		ld	(c_i),hl
read_c_len.next:
		ld	hl,(c_i)
		ld	de,(c_count)
		or	a
		sbc	hl,de
		jp	nc,read_c_len.rest	; too far for jr
		ld	a,(bitbuf+1)	; pt_table: the next 8 bits
		ld	l,a
		ld	h,0
		add	hl,hl
		ld	de,(tables)
		add	hl,de
		ld	de,PT_TABLE
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)		; DE = the symbol
		ld	hl,T_SYMS-1
		or	a
		sbc	hl,de
		jr	nc,read_c_len.symbol
		ld	hl,T_SYMS	; T_SYMS and up: a tree
		ld	bc,0080h	; the bit after the 8
		call	tree_walk
read_c_len.symbol:
		ld	hl,pt_len
		add	hl,de
		ld	b,(hl)
		push	de
		call	fill_bits	; the code, taken
		pop	de
		ld	a,e
		cp	3
		jr	nc,read_c_len.length
		ld	hl,1		; 0: one 0
		or	a
		jr	z,read_c_len.zeros
		ld	b,4		; 1: 3 to 18 of them
		ld	de,3
		dec	a
		jr	z,read_c_len.more
		ld	b,CBIT		; 2: 20 to 531
		ld	de,20
read_c_len.more:
		push	de
		call	get_bits
		pop	de
		add	hl,de
read_c_len.zeros:
		ld	a,h
		or	l
		jr	z,read_c_len.next
		dec	hl
		push	hl
		ld	hl,(c_i)
		ld	de,C_SYMS
		or	a
		sbc	hl,de
		pop	hl
		jr	nc,read_c_len.next	; all C_SYMS filled
		push	hl
		ld	hl,(c_i)
		ld	de,c_len
		add	hl,de
		ld	(hl),0
		ld	hl,(c_i)
		inc	hl
		ld	(c_i),hl
		pop	hl
		jr	read_c_len.zeros
read_c_len.length:
		sub	2		; 3 to 18: lengths 1 to 16
		ld	hl,(c_i)
		ld	de,c_len
		add	hl,de
		ld	(hl),a
		ld	hl,(c_i)
		inc	hl
		ld	(c_i),hl
		jp	read_c_len.next	; too far for jr
read_c_len.rest:
		ld	hl,(c_i)	; 0s up to C_SYMS
read_c_len.pad:
		ld	de,C_SYMS
		or	a
		sbc	hl,de
		add	hl,de
		jr	nc,read_c_len.make
		push	hl
		ld	de,c_len
		add	hl,de
		ld	(hl),0
		pop	hl
		inc	hl
		jr	read_c_len.pad
read_c_len.make:
		ld	hl,C_SYMS
		ld	(mt_n),hl
		ld	hl,c_len
		ld	(mt_len),hl
		ld	a,12
		ld	(mt_bits),a
		ld	hl,(tables)	; C_TABLE is at 0
		ld	(mt_table),hl
		jp	make_table

; bad_table - a table that is not valid.
;
; Output:	lh5_error = LH5_BAD
; Modifies:	AF
; Scratch:	none

bad_table:
		ld	a,LH5_BAD
		ld	(lh5_error),a
		ret

; make_table - a lookup table and its trees, from code lengths.
;
;   Codes are given out in order of length, and within a length in
;   order of symbol, so the lengths alone fix them: start[k] is the
;   first code of length k, as a fraction of 10000h, and weight[k] the
;   share of it one code of length k takes. They must add up to
;   exactly 10000h, or the codes are not a valid set.
;
;   A code no longer than mt_bits fills the table entries that start
;   with it. A longer one puts a tree's root in the entry for its first
;   mt_bits bits, and each bit after them is a step left or right, new
;   nodes being numbered from mt_n up, in LEFT and RIGHT.
;
;   The method is LHa for UNIX's make_table (src/maketbl.c).
;
; Input:	mt_n = the symbols' count
;		mt_len -> their lengths, a byte each, 0 to 16
;		mt_bits = the table's bits, 8 or 12
;		mt_table -> the table, in the mapped block
; Output:	the table, and LEFT and RIGHT
;		lh5_error = LH5_BAD for lengths that are not valid
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

make_table:
		ld	hl,mt_count	; count[] = 0
		ld	b,34
make_table.clear:
		ld	(hl),0
		inc	hl
		djnz	make_table.clear
		ld	hl,(mt_len)	; count[length]++
		ld	bc,(mt_n)
make_table.count:
		ld	a,(hl)
		cp	17
		jp	nc,bad_table	; over 16: not valid
		push	hl
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,mt_count
		add	hl,de
		inc	(hl)
		jr	nz,make_table.counted
		inc	hl
		inc	(hl)
make_table.counted:
		pop	hl
		inc	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,make_table.count
		ld	hl,(mt_count)	; all 0: not valid
		ld	de,(mt_n)
		or	a
		sbc	hl,de
		jp	z,bad_table
		ld	hl,8000h	; weight[k] = 10000h >> k
		ld	ix,mt_weight+2
		ld	b,16
make_table.weight:
		ld	(ix+0),l
		ld	(ix+1),h
		inc	ix
		inc	ix
		srl	h
		rr	l
		djnz	make_table.weight
		ld	hl,0		; start[k], and the total
		ld	ix,mt_start+2
		ld	iy,mt_count+2	; count and weight run side by side
		ld	b,16
make_table.start:
		ld	(ix+0),l
		ld	(ix+1),h
		ld	e,(iy+0)	; total + weight * count
		ld	d,(iy+1)
		push	bc
		ld	c,(iy+ROW)
		ld	b,(iy+ROW+1)
make_table.add:
		ld	a,d
		or	e
		jr	z,make_table.added
		add	hl,bc
		dec	de
		jr	make_table.add
make_table.added:
		pop	bc
		inc	ix
		inc	ix
		inc	iy
		inc	iy
		djnz	make_table.start
		ld	a,h		; 10000h: 0 in 16 bits
		or	l
		jp	nz,bad_table
		ld	a,(mt_bits)	; m = 16 - bits
		ld	b,a
		ld	a,16
		sub	b
		ld	(mt_shift),a
		ld	ix,mt_start+2	; start[k], weight[k] >> m, k to bits
make_table.scale:
		push	bc
		ld	a,(mt_shift)
		ld	b,a
		ld	l,(ix+0)
		ld	h,(ix+1)
		ld	e,(ix-ROW)
		ld	d,(ix-ROW+1)
make_table.halve:
		srl	h
		rr	l
		srl	d
		rr	e
		djnz	make_table.halve
		ld	(ix+0),l
		ld	(ix+1),h
		ld	(ix-ROW),e
		ld	(ix-ROW+1),d
		inc	ix
		inc	ix
		pop	bc
		djnz	make_table.scale
		ld	l,(ix+0)	; j = start[bits + 1] >> m
		ld	h,(ix+1)
		ld	a,(mt_shift)
		ld	b,a
make_table.first:
		srl	h
		rr	l
		djnz	make_table.first
		ex	de,hl		; DE = j: the entries from it are 0
		ld	a,(mt_bits)
		ld	b,a
		ld	hl,1
make_table.size:
		add	hl,hl
		djnz	make_table.size
		or	a		; HL = the entries: 1 << bits
		sbc	hl,de		; how many to clear
		jr	z,make_table.cleared
		jr	c,make_table.cleared
		ld	b,h
		ld	c,l
		ex	de,hl
		add	hl,hl
		ld	de,(mt_table)
		add	hl,de
make_table.zero:
		ld	(hl),0
		inc	hl
		ld	(hl),0
		inc	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,make_table.zero
make_table.cleared:
		ld	hl,(mt_n)	; new nodes from mt_n up
		ld	(mt_avail),hl
		ld	hl,0
		ld	(mt_sym),hl
make_table.symbol:
		ld	hl,(mt_sym)
		ld	de,(mt_n)
		or	a
		sbc	hl,de
		ret	nc		; every symbol done
		ld	hl,(mt_sym)
		ld	de,(mt_len)
		add	hl,de
		ld	a,(hl)		; k = its length
		or	a
		jp	z,make_table.next	; no code
		ld	(mt_k),a
		add	a,a		; IX -> start[k]
		ld	e,a
		ld	d,0
		ld	ix,mt_start
		add	ix,de
		ld	l,(ix+0)	; l = start[k] + weight[k]
		ld	h,(ix+1)
		ld	e,(ix-ROW)
		ld	d,(ix-ROW+1)
		add	hl,de
		ld	(mt_end),hl
		ld	a,(mt_bits)
		ld	b,a
		ld	a,(mt_k)
		cp	b
		jr	z,make_table.short
		jr	nc,make_table.long
make_table.short:
		ld	l,(ix+0)	; table[start .. end) = the symbol
		ld	h,(ix+1)
make_table.put:
		ld	de,(mt_end)
		or	a
		sbc	hl,de
		add	hl,de
		jp	nc,make_table.stepped	; too far for jr
		push	hl
		add	hl,hl
		ld	de,(mt_table)
		add	hl,de
		ld	de,(mt_sym)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		pop	hl
		inc	hl
		jr	make_table.put
make_table.long:
		ld	l,(ix+0)	; i = start[k]
		ld	h,(ix+1)
		push	hl
		ld	a,(mt_shift)	; p -> table[i >> m]
		ld	b,a
make_table.index:
		srl	h
		rr	l
		djnz	make_table.index
		add	hl,hl
		ld	de,(mt_table)
		add	hl,de
		ld	(mt_p),hl
		pop	hl
		ld	a,(mt_bits)	; i << bits
		ld	b,a
make_table.align:
		add	hl,hl
		djnz	make_table.align
		ld	(mt_i),hl
		ld	a,(mt_bits)	; k - bits steps
		ld	b,a
		ld	a,(mt_k)
		sub	b
		ld	b,a
make_table.step:
		push	bc
		ld	hl,(mt_p)	; no node there yet: a new one
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	a,d
		or	e
		jr	nz,make_table.node
		ld	de,(mt_avail)
		ld	(hl),d
		dec	hl
		ld	(hl),e
		push	de
		ld	hl,LEFT		; left[new] = right[new] = 0
		call	make_table.branch
		ld	(hl),0
		inc	hl
		ld	(hl),0
		pop	de
		push	de
		ld	hl,RIGHT
		call	make_table.branch
		ld	(hl),0
		inc	hl
		ld	(hl),0
		pop	de
		ld	hl,(mt_avail)
		inc	hl
		ld	(mt_avail),hl
make_table.node:
		ld	hl,(mt_i)	; its 1 or 0 branch, by i's top bit
		add	hl,hl
		ld	(mt_i),hl
		ld	hl,LEFT
		jr	nc,make_table.side
		ld	hl,RIGHT
make_table.side:
		call	make_table.branch
		ld	(mt_p),hl
		pop	bc
		djnz	make_table.step
		ld	hl,(mt_p)	; the last branch: the symbol
		ld	de,(mt_sym)
		ld	(hl),e
		inc	hl
		ld	(hl),d
make_table.stepped:
		ld	hl,(mt_end)	; start[k] = end
		ld	(ix+0),l
		ld	(ix+1),h
make_table.next:
		ld	hl,(mt_sym)
		inc	hl
		ld	(mt_sym),hl
		jp	make_table.symbol

; make_table.branch - HL -> LEFT or RIGHT's word for node DE.
;
; Input:	HL = LEFT or RIGHT, DE = the node
; Output:	HL -> the word, in the mapped block
; Modifies:	DE
;		HL
; Scratch:	none

make_table.branch:
		ex	de,hl
		add	hl,hl
		add	hl,de
		ld	de,(tables)
		add	hl,de
		ret

; lh_methods		per method, -lh4- to -lh7-: p_syms, p_bits,
;			win_mask (a word) and win_segs
;
lh_methods:	defb	14,4
		defw	1FFFh
		defb	1
		defb	14,4
		defw	1FFFh
		defb	1
		defb	16,5
		defw	7FFFh
		defb	2
		defb	17,5
		defw	0FFFFh
		defb	4

		dseg

; Variables for lh5.as:
;
; tables_ready		not 0 once the tables' block is allocated; 0 in
;			the program file, so it starts at 0
; tables_fp		its far pointer
; tables		-> it, in page 2, once mapped
; win_have		the window's segments got so far; 0 in the
;			program file
; win_fp		their far pointers, 4 bytes each, up to 4
; outbuf		-> the output buffer: the caller's
; p_syms, p_bits, win_mask, win_segs
;			the method's: kinds of distance, the bits that
;			count them, the ring's size less 1, its segments
; win_head		where the ring's next byte goes
; wrapped		not 0 once the ring has wrapped
; part_len		the part in the buffer, not yet in the ring
; app_left, app_src, app_n	ring_append: what is left, where from,
;			this piece
; page2			what page 2 holds: PAGE_TABLES, a segment of the
;			ring (0 to 3), or PAGE_NONE
; want, pos		lh5_read: how many bytes, how many so far
; match_left, match_dist	a match not finished: bytes left, its distance
; lh5_left		the member's data not yet read, 4 bytes
; lh5_error		0, or what went wrong: LH5_BAD, or from reading
; in_count, in_ptr	in_buf: bytes not used yet, the next one
; bitbuf		the next 16 bits
; bitsub, bitcnt	the byte they come from, and its bits left
; blocksize		the symbols left in this block
; walk_limit, walk_mask	tree_walk: the symbols' count, the bit to look at
; pt_n, pt_nbit, pt_special, pt_count, pt_i, pt_c
;			read_pt_len: its inputs, how many lengths, the
;			next one's number, the length; pt_i is read as a
;			word, so pt_c follows it
; c_count, c_i		read_c_len: how many lengths, the next one's
; mt_n, mt_len, mt_bits, mt_table
;			make_table's inputs
; mt_shift, mt_avail, mt_sym, mt_k, mt_end, mt_p, mt_i
;			make_table: 16 - bits, the next new node, the
;			symbol, its length, where its codes end, the entry
;			or branch being followed, the code's bits
; in_buf		the data, IN_SIZE bytes at a time
; c_len			the literal and length codes' lengths
; pt_len		the code length or distance codes' lengths
; mt_count, mt_weight, mt_start
;			make_table: per length, 1 to 16, how many codes,
;			the share of one, the first; side by side, ROW
;			bytes apart
;
tables_ready:	defb	0
tables_fp:	defs	4
tables:		defs	2
win_have:	defb	0
win_fp:		defs	16
outbuf:		defs	2
p_syms:		defs	1
p_bits:		defs	1
win_mask:	defs	2
win_segs:	defs	1
win_head:	defs	2
wrapped:	defs	1
part_len:	defs	2
app_left:	defs	2
app_src:	defs	2
app_n:		defs	2
page2:		defs	1
want:		defs	2
pos:		defs	2
match_left:	defs	2
match_dist:	defs	2
lh5_left:	defs	4
lh5_error:	defs	1
in_count:	defs	2
in_ptr:		defs	2
bitbuf:		defs	2
bitsub:		defs	1
bitcnt:		defs	1
blocksize:	defs	2
walk_limit:	defs	2
walk_mask:	defs	2
pt_n:		defs	1
pt_nbit:	defs	1
pt_special:	defs	1
pt_count:	defs	1
pt_i:		defs	1
pt_c:		defs	1
c_count:	defs	2
c_i:		defs	2
mt_n:		defs	2
mt_len:		defs	2
mt_bits:	defs	1
mt_table:	defs	2
mt_shift:	defs	1
mt_avail:	defs	2
mt_sym:		defs	2
mt_k:		defs	1
mt_end:		defs	2
mt_p:		defs	2
mt_i:		defs	2

		dseg	buffers
in_buf:		defs	IN_SIZE
c_len:		defs	C_SYMS
pt_len:		defs	NPT
mt_count:	defs	ROW
mt_weight:	defs	ROW
mt_start:	defs	ROW

		end
