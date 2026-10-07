; lh5w.as - the -lh5- and deflate encoder: KAGO's compression, as LHA 2.x
; writes -lh5-, and deflate for ZIP.
;
; lh5.as and inflate.as, in UNKAGO, read what this writes. The match
; finder and the blocks are the same for both; each block's codes are
; sent the one way or the other (DEFLATE, below). A member's data is a series
; of symbols: a byte (a literal), or a match, "copy L bytes from D back",
; L from 3 to 256 and D from 1 to 8192. Finding the matches is the LZ
; half of the work; giving each symbol a Huffman code is the other.
;
; THE MATCH FINDER follows LHa for UNIX's encode() (src/slide.c):
;
;   - Every position is put in a hash table, by its next three bytes:
;	head holds the latest position with each hash, and prev, for each
;	position, the one before it with the same hash. Following prev
;	from head walks a chain of earlier positions that may match.
;   - The search at a position walks its chain, at most CHAIN steps and
;	never more than 8192 bytes back, and keeps the longest match.
;   - Lazy by one: a match is sent only if the next position doesn't
;	start a longer one; otherwise a literal goes out, and the next
;	position's match is the one considered.
;
; The text, the chains and the tables don't fit below 8000h, so they are
; in the mapper, and page 2 shows one of them at a time:
;
;   text	a 16 KB segment: a ring of the member's bytes, 8 KB of
;		history and what has been read ahead
;   prev	a 16 KB segment: 8192 words, one per position in the window
;   tables	a MapperHeap block: the Huffman tables, head (2048 words,
;		an 11-bit hash) and the block's symbols (4 KB)
;
; To change page 2 as seldom as possible, the work is done in rounds:
; the positions to put in the table, and the one or two searches that
; follow them, each in four steps, one per mapping (round): the hashes
; (text), head (tables), prev and the chains (prev), the matches and the
; decision (text).
;
; THE HUFFMAN CODES: each block's symbols are kept, four KB at a time, as
; LHA keeps them (out_sym): a flags byte for every 8 symbols, one bit per
; symbol, 1 for a match; a literal is its byte, a match its length less
; 3 and its distance less 1 in two bytes. When the 4 KB are full, the
; block is sent (send_block): its size, then three code tables, then the
; symbols' codes:
;
;   pt		the lengths of the codes that send c's lengths (19 symbols:
;		lengths 0 to 16, and three that count runs of zeros)
;   c		the codes of the 510 symbols: 256 bytes and 254 lengths
;   p		the codes of the distances' sizes in bits, 0 to 13; a
;		distance is sent as its size's code, then its bits after
;		the highest
;
; make_tree builds each table's code lengths from the symbols' counts,
; as LHA's maketree.c does: a heap of the symbols used; the two least used
; joined into a node, until one is left; each symbol's depth its length,
; cut to 16 bits. A table with one symbol only is sent as that symbol,
; its code 0 bits long.
;
; The bits go out highest first, through a 1 KB buffer into the archive
; (archive_write, in kago.as). The packed size is counted as the buffer
; is written. When it reaches the member's own size, packing is
; pointless: nothing more is written, and lh5w_data or lh5w_end say so,
; for KAGO to store the member instead.
;
; DEFLATE (note 029) takes the same symbols and the same blocks, cut
; where -lh5- cuts them, and sends each one as RFC 1951 asks
; (d_send_block): a length goes as a code from 257 to 284 and its extra
; bits, a distance as a code from 0 to 29 and its own, 256 ends the
; block. Its codes are 15 bits at most, make_tree's mt_max. The block
; is dynamic, its trees sent first, or fixed, deflate's own codes,
; whichever is smaller, fixed when they are the same. A match is 256
; bytes at most, as for -lh5- (deflate's go to 258). The bits go out
; lowest first: putcode is changed in place for that (lh5w_start), and
; d_putbits writes the numbers.
;
; -PM2- (note 035), PMA's method, takes the same symbols too, sent as
; PMARC2 sends them (pm2_send): a literal goes as its place in a
; move-to-front list of the 256 byte values (mtf_place, an array, kept
; as the symbols are decided, a match's bytes too); a match as a code
; for its length (3 to 256) and an offset code for its distance's size.
; Its code tree may change only every 4 KB of output, so -pm2- sends the
; block not when it fills but at those points (pm2_count): a unit, its
; symbols counted when it is sent, then its trees and its codes. The
; first unit has offset trees of its own at 1 KB and 2 KB, as PMA asks.
; The block holds up to 4640 bytes, for a unit of literals.
;
; mkkago.py's model (notes 026, 029) is this file, step for step, and
; pm2enc.py's (note 035) its -pm2-.

		public	lh5w_start
		public	lh5w_data
		public	lh5w_end

		include	common.inc	; MapperHeap's routines
		include	farptr.inc	; fpalloc, derefp

		extrn	archive_write	; kago.as: HL bytes, from DE

C_SYMS		equ	510		; literal and match length symbols
T_SYMS		equ	19		; pt's symbols
P_SYMS		equ	14		; p's symbols: 0 to 13 bits
CBIT		equ	9		; bits that count c's lengths
TBIT		equ	5		; pt's
PBIT		equ	4		; p's
OUT_SIZE	equ	1024		; outbuf: written at a time
WINDOW		equ	8192		; how far back a match may be: at
WINDOW_SMALL	equ	4096		;   full strength, and with less
MAX_MATCH	equ	256		; how long
THRESHOLD	equ	3		; and how short
CHAIN		equ	32		; a search's steps at most
HASH_SIZE	equ	2048		; head's entries: an 11-bit hash
BUF_SIZE	equ	4096		; a block's symbols, as LHA keeps them
BUF_PM2		equ	4640		; -pm2-'s: 4096 literals and their
					;   flags, and a match after them
UNIT		equ	4096		; -pm2-: the output between code trees
PC_FREQ		equ	600		; -pm2-: the codes' counts, 29 and
					;   room, from word 600 in c_freq
PO_FREQ		equ	660		;   the offset codes', 16 words a
					;   stretch, from word 660
OFF_AT		equ	32		;   the offset codes' lengths and
					;   codes: from symbol 32
CODE_MAX	equ	12		;   the longest code, and offset code
OFF_MAX		equ	7
AHEAD		equ	514		; a round needs this many bytes read
					;   from its first position on

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
HEAD		equ	7135		; HASH_SIZE words: each hash's latest
					;   position, 0FFFFh for none
BUFFER		equ	11231		; BUF_PM2 bytes: the block's symbols
TABLES_SIZE	equ	BUFFER+BUF_PM2

; Deflate's (d_send_block): the literals' and lengths' tree in c's
; arrays, the distances' after it; their counts further on, past the
; first tree's nodes.
LL_SYMS		equ	286		; literals, 256, lengths
D_SYMS		equ	30		; distances
D_AT		equ	LL_SYMS		; the distances' lengths and codes:
					;   from symbol 286 in c_len, c_code
D_FREQ		equ	600		; their counts: from word 600 in
					;   c_freq, after 2*LL_SYMS-1
END_BLOCK	equ	256		; the block's last symbol
MAX_LL		equ	15		; deflate's longest code, and the
MAX_CL		equ	7		;   code lengths' tree's

		cseg

; lh5w_start - get ready to pack a member.
;
;   The first time, the tables' block and the text's and prev's segments
;   are allocated, and kept for every member after. The packed size
;   starts at 0, the bit buffer, the block and every count empty, and
;   head holds no position. The first round puts position 0 in the
;   table and searches at 1, after a match of 2 (no match).
;
;   With A bit 0 set, the first time, the text and prev share one
;   segment, with a 4 KB window: 32 KB of mapper instead of 48 (small,
;   R7). With bit 1, the member is deflate; putcode's two bytes are
;   set for its bits, lowest first (p_put_rot, p_put_mark). With bit 2,
;   it is -pm2- (pm2_start).
;
; Input:	DE:HL = the member's size: packing stops when the packed
;		size reaches it
;		A bit 0: small, the first call decides; bit 1: deflate;
;		bit 2: -pm2-
; Output:	CY set = no mapper memory
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

lh5w_start:
		ld	(small),a	; the mode, for now
		call	forget		; page 2: KAGO's until now
		ld	(limit),hl
		ld	(limit+2),de
		ld	a,(small)	; bit 2: -pm2-
		and	4
		ld	(pm2_mode),a
		ld	a,(small)	; bit 1: deflate
		and	2
		ld	(deflate),a
		ld	hl,11h*256+1	; -lh5-: RL C, a marker of 1
		jr	z,lh5w_start.lh5
		ld	hl,19h*256+80h	; deflate: RR C, a marker of 80h
lh5w_start.lh5:
		ld	a,h		; putcode: the bits into a byte
		ld	(p_put_rot+1),a	;   from its lowest bit up, or
		ld	a,l		;   from its highest down
		ld	(p_put_mark+1),a
		ld	(bitbuf),a	; the bit buffer: the marker alone
		ld	a,(small)	; bit 0: small
		and	1
		ld	(small),a
		ld	a,16		; -lh5-'s codes: 16 bits at most
		ld	(mt_max),a
		ld	hl,0
		ld	(packed),hl
		ld	(packed+2),hl
		ld	(top),hl
		ld	(r_first),hl
		ld	(bufpos),hl
		ld	hl,1		; the first round: 0 put in
		ld	(r_ins),hl
		ld	hl,THRESHOLD-1	; the match before: none
		ld	(m_len),hl
		xor	a
		ld	(r_b),a
		ld	(unpackable),a
		ld	(big),a
		ld	(eof),a
		ld	(done),a
		ld	(pend),a
		ld	(mask),a
		ld	(d_final),a
		ld	hl,outbuf
		ld	(outptr),hl
		ld	hl,p_freq
		ld	bc,2*P_SYMS
		call	zero
		ld	a,(tables_ready)
		or	a
		jp	nz,lh5w_start.ready	; too far for jr
		fpalloc	tables_fp,TABLES_SIZE	; CY set: out of memory
		ret	c
		ld	hl,text_fp
		call	segalloc
		ret	c
		ld	hl,WINDOW
		ld	(win_size),hl
		ld	a,(small)
		or	a
		jr	nz,lh5w_start.small
		ld	hl,prev_fp
		call	segalloc
		ret	c
		jr	lh5w_start.got
lh5w_start.small:
		ld	hl,text_fp	; small: prev in the text's
		ld	de,prev_fp	;   segment, from A000h
		ld	bc,4
		ldir
		ld	hl,WINDOW_SMALL
		ld	(win_size),hl
		call	patch_small
lh5w_start.got:
		ld	a,1
		ld	(tables_ready),a
		ld	a,(primslt)	; all three in the primary
		ld	hl,text_fp	;   mapper: p2seg can switch
		cp	(hl)		;   between them
		jr	nz,lh5w_start.slow
		ld	hl,prev_fp
		cp	(hl)
		jr	nz,lh5w_start.slow
		ld	hl,tables_fp
		cp	(hl)
		jr	nz,lh5w_start.slow
		ld	a,1
		ld	(fast),a
lh5w_start.slow:
		ld	hl,C_SYMS	; c's tree: C_SYMS symbols, and
		ld	(c_n),hl	;   where its arrays are
		derefp	tables_fp	; DE -> the block, in page 2
		ex	de,hl
		ld	hl,offsets
		ld	ix,c_freq_at
		ld	b,9
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
lh5w_start.ready:
		call	map_tables
		ld	hl,(c_freq_at)	; no symbol counted
		ld	bc,2*C_SYMS
		call	zero
		ld	hl,(head_at)	; no position in head
		ld	(hl),0FFh
		ld	d,h
		ld	e,l
		inc	de
		ld	bc,2*HASH_SIZE-1
		ldir
		ld	a,(pm2_mode)	; -pm2-: its start
		or	a
		call	nz,pm2_start
		or	a		; carry clear: ready
		ret

; lh5w_data - pack a member's bytes, as they are read.
;
;   They go into the text's ring, as many at a time as fit without
;   overwriting what the next search may still reach (8192 bytes back
;   from the next round's first position); then rounds run, as long as
;   AHEAD bytes are read from their first position on.
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

lh5w_data:
		call	forget		; page 2: KAGO's until now
		ld	(src_at),de
		ld	(src_n),bc
lh5w_data.more:
		ld	hl,(src_n)
		ld	a,h
		or	l
		jr	z,lh5w_data.done
		ld	hl,(top)	; room: window - (top - r_first + 1)
		ld	de,(r_first)
		or	a
		sbc	hl,de
		inc	hl
		ex	de,hl
		ld	hl,(win_size)
		or	a
		sbc	hl,de
		ld	de,(src_n)	; at most what is left
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	c,lh5w_data.copy
		ex	de,hl
lh5w_data.copy:
		call	copy_in
		call	rounds
		ld	a,(unpackable)
		or	a
		jr	z,lh5w_data.more
lh5w_data.done:
		ld	a,(unpackable)	; 1: CY set
		rra
		ret

; lh5w_end - the rest of the member, its last bits, and its packed size.
;
;   The rounds run to the end, the last symbol is kept, the last block
;   sent (deflate's marked the last), and the last byte filled with 0
;   bits, as LHA does (7 of them, which complete it if any bit is
;   waiting).
;
; Input:	none
; Output:	CY set = the packed size reached the member's: store it
;		DE:HL = the packed size
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

lh5w_end:
		call	forget		; page 2: KAGO's until now
		ld	a,1
		ld	(eof),a
		call	rounds
		ld	a,(unpackable)
		or	a
		jr	nz,lh5w_end.done
		call	map_tables
		call	out_pending
		ld	a,1		; deflate: the last block
		ld	(d_final),a
		call	send_block
		ld	hl,0
		ld	b,7
		call	putbits
		call	flush
lh5w_end.done:
		ld	hl,(packed)
		ld	de,(packed+2)
		ld	a,(unpackable)
		rra
		ret

; copy_in - bytes into the text's ring, where top is.
;
; Input:	HL = how many: 1 or more, room for them in the ring
;		src_at, src_n, top
; Output:	the bytes in the ring; top, src_at and src_n moved on
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

copy_in:
		ld	(cp_n),hl
		call	map_text
		ld	hl,(top)	; DE = where top is in the ring
		ld	a,h
p_copy_mask:
		and	3Fh
		ld	d,a
		ld	e,l
p_copy_size:
		ld	hl,4000h	; the room to the ring's end
		or	a
		sbc	hl,de
		ld	bc,(cp_n)
		or	a
		sbc	hl,bc
		jr	nc,copy_in.first	; all of them fit before it
		add	hl,bc		; no: as many as fit, first
		ld	b,h
		ld	c,l
copy_in.first:
		set	7,d		; DE -> in page 2
		ld	hl,(src_at)
		push	bc
		ldir
		pop	bc
		ld	(src_at),hl
		ld	hl,(cp_n)	; the rest, from the ring's start
		or	a
		sbc	hl,bc
		jr	z,copy_in.done
		ld	b,h
		ld	c,l
		ld	hl,(src_at)
		ld	de,8000h
		ldir
		ld	(src_at),hl
copy_in.done:
		ld	de,(cp_n)
		ld	hl,(top)
		add	hl,de
		ld	(top),hl
		ld	hl,(src_n)
		or	a
		sbc	hl,de
		ld	(src_n),hl
		ret

; rounds - as many rounds as the bytes read allow.
;
;   Until the member ends (done) or packing stops (unpackable). Before
;   lh5w_end, a round needs AHEAD bytes from its first position on.
;
; Input:	eof, done, unpackable, top, r_first
; Output:	the rounds run
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

rounds:
		ld	a,(unpackable)
		ld	hl,done
		or	(hl)
		ret	nz
		ld	a,(eof)
		or	a
		jr	nz,rounds.one
		ld	hl,(top)
		ld	de,(r_first)
		or	a
		sbc	hl,de
		ld	de,AHEAD
		or	a
		sbc	hl,de
		ret	c		; not enough read yet
rounds.one:
		call	round
		jr	rounds

; round - one round of LHa's loop.
;
;   A round starts at r_first: r_ins positions put in the table only,
;   then, with r_b, B's search (min 2), then A's search, whose min is
;   the match before it less 1: B's, or the last round's A's. A's
;   decision sends the match before it, or a literal, the byte before
;   A:
;
;   after a literal (r_b 0)	r_first = A + 1, r_ins 0: A's search
;   after a match of L		r_first = A + 1, r_ins = L - 2, r_b 1:
;				the match's other positions, B's search at
;				its end, A's after it
;
;   The steps: the hashes, with the text mapped; the symbol decided last
;   round sent, and head, with the tables; prev, and each search's chain
;   (walk), with prev; the matches (search) and the decision, with the
;   text. A position less than 3 bytes from the end goes in no table,
;   and finds no match. At the end, a round whose search would be past
;   it is the last (done).
;
; Input:	r_first, r_ins, r_b, m_len, m_dist, top, eof
; Output:	the next round's r_first, r_ins, r_b; m_len, m_dist: A's
;		match; pend: the symbol to send
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

round:
		ld	hl,(r_first)	; B, then A
		ld	de,(r_ins)
		add	hl,de
		ld	(s_b),hl
		ld	a,(r_b)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	(s_a),hl
		ld	hl,(r_ins)	; how many positions
		add	hl,de
		inc	hl
		ld	(r_cnt),hl
		ld	a,(eof)
		or	a
		jr	z,round.go
		ld	a,(r_b)		; at the end: is there a search?
		or	a
		jr	z,round.no_b
		ld	hl,(s_b)
		ld	de,(top)
		or	a
		sbc	hl,de
		jr	c,round.go
		jr	round.last
round.no_b:
		ld	hl,(top)
		ld	de,(s_a)
		or	a
		sbc	hl,de
		jr	nc,round.go
round.last:
		ld	a,1		; no: the member is done
		ld	(done),a
		ret
round.go:
		ld	hl,(top)	; nq: those 3 bytes from the end
		ld	de,(r_first)	;   or more
		or	a
		sbc	hl,de
		ld	de,2
		or	a
		sbc	hl,de
		jr	nc,round.room
		ld	hl,0
round.room:
		ld	de,(r_cnt)
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	c,round.counted
		ex	de,hl
round.counted:
		ld	(r_nq),hl
		call	map_text	; the hashes
		ld	hl,(r_nq)
		ld	a,h
		or	l
		jr	z,round.hashed
		ld	a,l		; B' = how many (256 is 0)
		exx
		ld	b,a
		ld	hl,qh		; HL' -> where they go
		exx
		ld	hl,(r_first)	; C, D, E: the first three bytes
		call	ring_addr
		ld	c,(hl)
		inc	hl
p_hash_1:
		res	6,h
		ld	d,(hl)
		inc	hl
p_hash_2:
		res	6,h
		ld	e,(hl)
		inc	hl
p_hash_3:
		res	6,h
round.hash:
		ld	a,d		; ((C << 8) ^ (D << 4) ^ E) & 7FFh,
		rrca			;   doubled, into qh
		rrca
		rrca
		rrca
		ld	b,a		; D's nibbles swapped
		and	0Fh
		xor	c
		and	7
		ld	c,a		; C = its high byte
		ld	a,b
		and	0F0h
		xor	e
		add	a,a
		rl	c
		exx
		ld	(hl),a
		inc	hl
		exx
		ld	a,c
		exx
		ld	(hl),a
		inc	hl
		exx
		ld	c,d		; the next position's bytes
		ld	d,e
		ld	e,(hl)
		inc	hl
p_hash_4:
		res	6,h
		exx
		dec	b
		exx
		jr	nz,round.hash
round.hashed:
		call	map_tables	; the last symbol; head
		call	out_pending
		ld	hl,qh
		ld	de,(r_first)
		ld	bc,(r_nq)
round.head:
		ld	a,b
		or	c
		jr	z,round.headed
		push	bc
		ld	c,(hl)		; BC = twice the hash
		inc	hl
		ld	b,(hl)
		dec	hl
		push	hl
		ld	hl,(head_at)
		add	hl,bc
		ld	c,(hl)		; BC = the position there; the
		ld	(hl),e		;   new one in its place
		inc	hl
		ld	b,(hl)
		ld	(hl),d
		pop	hl
		ld	(hl),c		; the old one, for prev
		inc	hl
		ld	(hl),b
		inc	hl
		inc	de
		pop	bc
		dec	bc
		jr	round.head
round.headed:
		call	map_prev	; prev, and the chains
		xor	a
		ld	(n_b),a
		ld	(n_a),a
		ld	hl,(r_nq)	; first those only put in:
		ld	de,(r_ins)	;   r_ins of them, or nq
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	c,round.plain
		ex	de,hl
round.plain:
		ld	b,h		; BC = how many
		ld	c,l
		ld	hl,qh
		ld	de,(r_first)
round.prev:
		ld	a,b
		or	c
		jr	z,round.searches
		push	bc
		call	prev_put	; prev[DE] = (HL), and on
		pop	bc
		dec	bc
		jr	round.prev
round.searches:
		ld	bc,(r_nq)	; then B's and A's, if they are
		ld	a,(r_b)		;   3 bytes from the end or more
		or	a
		jr	z,round.prev_a
		ld	hl,(s_b)
		ld	(w_s),hl
		call	round.chain
		jr	c,round.compare
		ld	ix,list_b
		call	walk
		ld	(n_b),a
		ld	bc,(r_nq)
round.prev_a:
		ld	hl,(s_a)
		ld	(w_s),hl
		call	round.chain
		jr	c,round.compare
		ld	ix,list_a
		call	walk
		ld	(n_a),a
		jr	round.compare
round.chain:
		ld	hl,(w_s)	; past nq: no chain (CY set)
		ld	de,(r_first)
		or	a
		sbc	hl,de
		push	hl
		or	a
		sbc	hl,bc
		pop	hl
		ccf
		ret	c
		add	hl,hl		; its old position, from qh
		ld	de,qh
		add	hl,de
		ld	de,(w_s)
		call	prev_put	; prev[s] = it
		dec	hl
		ld	d,(hl)
		dec	hl
		ld	e,(hl)		; DE = it: walk's start
		or	a
		ret

; prev_put - a position's prev: the position head held before it.
;
; Input:	DE = the position
;		HL -> its old position, in qh
;		prev mapped
; Output:	prev[DE] written; HL -> the next in qh; DE + 1
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

prev_put:
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		inc	hl
		push	hl
		ld	h,d
		ld	l,e
		add	hl,hl
		ld	a,h
p_prev_and_1:
		and	3Fh
p_prev_or_1:
		or	80h
		ld	h,a
		ld	(hl),c
		inc	hl
		ld	(hl),b
		pop	hl
		inc	de
		ret
round.compare:
		call	map_text	; the matches
		ld	a,(r_b)
		or	a
		jr	z,round.a
		ld	hl,(s_b)	; B's: min 2
		ld	(w_s),hl
		ld	ix,list_b
		ld	a,(n_b)
		ld	b,a
		ld	hl,THRESHOLD-1
		call	search
		ld	hl,(best_len)
		ld	(m_len),hl
		ld	hl,(best_d)
		ld	(m_dist),hl
round.a:
		ld	hl,(m_len)	; the match before A: last
		ld	(last_len),hl
		ld	hl,(m_dist)
		ld	(last_dist),hl
		ld	hl,(s_a)	; A's: min its length less 1
		ld	(w_s),hl
		ld	ix,list_a
		ld	a,(n_a)
		ld	b,a
		ld	hl,(last_len)
		dec	hl
		call	search
		ld	hl,(best_len)
		ld	(m_len),hl
		ld	hl,(best_d)
		ld	(m_dist),hl
		ld	hl,(last_len)	; last under 3: a literal
		ld	de,THRESHOLD
		or	a
		sbc	hl,de
		jr	c,round.literal
		ld	hl,(last_len)	; A's longer: a literal
		ld	de,(m_len)
		or	a
		sbc	hl,de
		jr	c,round.literal
		ld	a,2		; otherwise last, the match
		ld	(pend),a
		ld	hl,(last_len)
		ld	de,256-THRESHOLD
		add	hl,de
		ld	(pend_c),hl
		ld	hl,(last_dist)
		dec	hl
		ld	(pend_p),hl
		ld	a,(pm2_mode)	; -pm2-: its bytes to the list's
		or	a		;   head
		call	nz,mtf_match
		ld	hl,(last_len)	; next: its other positions, B
		dec	hl		;   and A
		dec	hl
		ld	(r_ins),hl
		ld	a,1
		ld	(r_b),a
		jr	round.after
round.literal:
		ld	a,1		; the byte before A
		ld	(pend),a
		ld	hl,(s_a)
		dec	hl
		call	ring_addr
		ld	c,(hl)
		ld	a,(pm2_mode)	; -pm2-: its place in the list
		or	a
		ld	a,c
		call	nz,mtf_place
		ld	l,a
		ld	h,0
		ld	(pend_c),hl
		ld	hl,0		; next: A + 1's search
		ld	(r_ins),hl
		xor	a
		ld	(r_b),a
round.after:
		ld	hl,(s_a)
		inc	hl
		ld	(r_first),hl
		ld	a,(big)		; from window on, the window is full
		or	a
		ret	nz
		ld	de,(win_size)
		or	a
		sbc	hl,de
		ret	c
		ld	a,1
		ld	(big),a
		ret

; ring_addr - where a position's byte is, with the text mapped.
;
; Input:	HL = the position
; Output:	HL -> its byte in page 2
; Modifies:	AF
;		HL
; Scratch:	none

ring_addr:
		ld	a,h
p_ring_mask:
		and	3Fh
		or	80h
		ld	h,a
		ret

; walk - a search's chain: the positions to compare.
;
;   From the position head held, back along prev, while each is further
;   back than the one before, no further than the window allows (8192,
;   or the member's start), and CHAIN at most. With d = s - c, both
;   limits are one test: x = wlim - d must be under span, which starts at
;   wlim and becomes x each time; a d too far back, or not further than
;   the last, makes x too big (16-bit, it wraps). B' counts down.
;
; Input:	DE = the position head held
;		w_s = the search's position
;		IX -> the list
;		big; prev mapped
; Output:	A = how many positions in the list
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		B'
; Scratch:	none

walk:
		ld	hl,(win_size)	; wlim: the window, or the start
		ld	a,(big)
		or	a
		jr	nz,walk.limit
		ld	hl,(w_s)
		ld	bc,(win_size)
		or	a
		sbc	hl,bc
		ld	hl,(win_size)
		jr	nc,walk.limit
		ld	hl,(w_s)
walk.limit:
		ld	b,h		; BC = span: wlim
		ld	c,l
		push	de		; x = c + (wlim - s)
		ld	de,(w_s)
		or	a
		sbc	hl,de
		ld	(w_neg),hl
		pop	de
		exx
		ld	b,CHAIN
		exx
walk.next:
		ld	hl,(w_neg)	; x
		add	hl,de
		ld	a,l		; under span, or stop
		sub	c
		ld	a,h
		sbc	a,b
		jr	nc,walk.done
		ld	b,h		; span = x
		ld	c,l
		ld	(ix+0),e
		ld	(ix+1),d
		inc	ix
		inc	ix
		exx			; CHAIN of them: stop
		dec	b
		exx
		jr	z,walk.done
		ex	de,hl		; c = prev[c]
		add	hl,hl
		ld	a,h
p_prev_and_2:
		and	3Fh
p_prev_or_2:
		or	80h
		ld	h,a
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		jr	walk.next
walk.done:
		exx			; CHAIN less those left
		ld	a,CHAIN
		sub	b
		exx
		ret

; search - the longest match at a position, from its list.
;
;   It must be longer than min (2 at least) and is at most 256, or what
;   is left of the member. Each position's byte at the best length so
;   far is looked at first, as LHA does: a longer match must have it.
;   A match as long as it can be ends the search. B' counts the
;   positions left.
;
; Input:	HL = min
;		w_s = the position
;		IX -> the list
;		B = how many in it
;		top; the text mapped
; Output:	best_len: the match's length, or min (2 at least)
;		best_d: its distance, 0 for none
; Modifies:	AF
;		BC
;		DE
;		HL
;		B'
; Scratch:	none

search:
		ld	a,h		; at least 2
		or	a
		jr	nz,search.min
		ld	a,l
		cp	THRESHOLD-1
		jr	nc,search.min
		ld	l,THRESHOLD-1
search.min:
		ld	(best_len),hl
		ld	hl,0
		ld	(best_d),hl
		ld	a,b		; none to try
		or	a
		ret	z
		ld	(s_n),a
		ld	hl,(top)	; mx: 256, or what is left
		ld	de,(w_s)
		or	a
		sbc	hl,de
		ld	de,MAX_MATCH
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	c,search.mx
		ex	de,hl
search.mx:
		ld	(mx),hl
		ld	hl,(w_s)	; s's byte
		call	ring_addr
		ld	(s_at),hl
		push	ix
		pop	hl
		ld	(s_list),hl
search.aim:
		ld	hl,(best_len)	; as long as it can be already
		ld	de,(mx)
		or	a
		sbc	hl,de
		ret	nc
		ld	hl,(w_s)	; s's byte at the best length
		ld	bc,(best_len)
		add	hl,bc
		call	ring_addr
		ld	a,(hl)
		ld	(s_byte),a
		ld	a,(s_n)
		exx
		ld	b,a
		exx
		ld	hl,(s_list)
search.next:
		ld	e,(hl)		; DE = the next position
		inc	hl
		ld	d,(hl)
		inc	hl
		push	hl
		ld	h,d		; its byte at the best length
		ld	l,e
		add	hl,bc
		ld	a,h
p_cand_mask:
		and	3Fh
		or	80h
		ld	h,a
		ld	a,(s_byte)
		cp	(hl)
		pop	hl
		jr	z,search.same
		exx
		dec	b
		exx
		jr	nz,search.next
		ret
search.same:
		ld	(s_list),hl	; the same: compare from the start
		exx
		ld	a,b
		exx
		dec	a
		ld	(s_n),a
		ld	(s_c),de
		ex	de,hl
		call	ring_addr
		ex	de,hl
		ld	hl,(s_at)
		ld	a,(mx)		; 256 is 0: 256 times
		ld	b,a
search.byte:
		ld	a,(de)
		cp	(hl)
		jr	nz,search.differ
		inc	de
p_cmp_d:
		res	6,d
		inc	hl
p_cmp_h:
		res	6,h
		djnz	search.byte
		ld	hl,(mx)		; all of them
		jr	search.length
search.differ:
		ld	a,(mx)		; mx - B
		sub	b
		ld	l,a
		ld	h,0
search.length:
		ld	de,(best_len)	; longer: the best so far
		push	hl
		or	a
		sbc	hl,de
		pop	hl
		jr	c,search.on
		jr	z,search.on
		ld	(best_len),hl
		ld	hl,(w_s)	; its distance: s - c
		ld	de,(s_c)
		or	a
		sbc	hl,de
		ld	(best_d),hl
		ld	a,(s_n)		; none left
		or	a
		ret	z
		jp	search.aim	; too far for jr
search.on:
		ld	a,(s_n)
		or	a
		ret	z
		exx
		ld	b,a
		exx
		ld	bc,(best_len)
		ld	hl,(s_list)
		jp	search.next	; too far for jr

; out_pending - send the symbol the last round decided, if there is one.
;
; Input:	pend: 0 none, 1 a literal, 2 a match; pend_c, pend_p
;		the tables mapped
; Output:	in the block; pend = 0
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

out_pending:
		ld	a,(pend)
		or	a
		ret	z
		ld	hl,(pend_c)
		ld	de,(pend_p)
		call	out_sym
		xor	a
		ld	(pend),a
		ret

; out_sym - a symbol into the block, counted.
;
;   huf.c's output_st1: a flags byte starts every 8 symbols; when it
;   would start with fewer than 24 bytes left in the block, the block is
;   sent first (send_block); for -pm2-, at PMA's points instead
;   (pm2_count). A literal is its byte (-pm2-: its place in the list);
;   a match is its symbol's low byte (length - 3), then its distance -
;   1, high byte first, its flag bit set. Each symbol's count, and each
;   distance's size's, go up by one.
;
; Input:	A = 1 for a literal, 2 for a match
;		HL = the symbol: 0 to 509
;		DE = the distance - 1, for a match
;		the tables mapped
; Output:	in the block
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

out_sym:
		ld	(o_kind),a
		ld	(o_c),hl
		ld	(o_p),de
		ld	a,(mask)	; the next flag bit
		srl	a
		ld	(mask),a
		jr	nz,out_sym.put
		ld	a,80h		; none left: a new flags byte
		ld	(mask),a
		ld	a,(pm2_mode)	; -pm2-: sent at its points
		or	a
		jr	nz,out_sym.group
		ld	hl,(bufpos)
		ld	de,BUF_SIZE-24
		or	a
		sbc	hl,de
		jr	c,out_sym.group
		call	send_block	; no room for 8 more: send it
		ld	hl,0
		ld	(bufpos),hl
out_sym.group:
		ld	hl,(bufpos)
		ld	(cpos),hl
		ld	de,(buf_at)
		add	hl,de
		ld	(hl),0
		ld	hl,(bufpos)
		inc	hl
		ld	(bufpos),hl
out_sym.put:
		ld	hl,(bufpos)	; the symbol's low byte
		ld	de,(buf_at)
		add	hl,de
		ld	a,(o_c)
		ld	(hl),a
		inc	hl
		push	hl
		ld	hl,(o_c)	; its count
		add	hl,hl
		ld	de,(c_freq_at)
		add	hl,de
		inc	(hl)
		jr	nz,out_sym.counted
		inc	hl
		inc	(hl)
out_sym.counted:
		pop	hl
		ld	a,(o_kind)
		cp	2
		jr	nz,out_sym.done
		push	hl		; a match: its flag
		ld	hl,(cpos)
		ld	de,(buf_at)
		add	hl,de
		ld	a,(mask)
		or	(hl)
		ld	(hl),a
		pop	hl
		ld	de,(o_p)	; the distance - 1
		ld	(hl),d
		inc	hl
		ld	(hl),e
		inc	hl
		push	hl
		ex	de,hl		; its size's count
		call	bitlen
		ld	l,a
		ld	h,0
		add	hl,hl
		ld	de,p_freq
		add	hl,de
		inc	(hl)
		jr	nz,out_sym.sized
		inc	hl
		inc	(hl)
out_sym.sized:
		pop	hl
out_sym.done:
		ld	de,(buf_at)
		or	a
		sbc	hl,de
		ld	(bufpos),hl
		ld	a,(pm2_mode)	; -pm2-: counted, and at its
		or	a		;   points sent
		ret	z
		jp	pm2_count

; bitlen - how many bits a number takes: 0 for 0.
;
; Input:	HL = the number
; Output:	A = its bits
; Modifies:	AF
;		B
;		HL
; Scratch:	none

bitlen:
		ld	b,8		; a high byte: 8 + its bits
		ld	a,h
		or	a
		jr	nz,bitlen.byte
		ld	b,h		; otherwise the low byte's
		ld	a,l
bitlen.byte:
		or	a
		jr	z,bitlen.done
		srl	a
		inc	b
		jr	bitlen.byte
bitlen.done:
		ld	a,b
		ret

; send_block - the block: its tables, then its symbols' codes.
;
;   huf.c's send_block: c's tree; the block's size (its root's count);
;   pt's tree and lengths, and c's lengths (or c's one symbol); p's tree
;   and lengths (or its one symbol); then each symbol's code, a match's
;   distance after it (encode_p). The counts go back to 0. A deflate
;   member's block goes to d_send_block instead, and a -pm2- member's
;   last unit to pm2_end.
;
; Input:	the block, its counts; the tables mapped
; Output:	written
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

send_block:
		ld	a,(deflate)	; deflate's way
		or	a
		jp	nz,d_send_block
		ld	a,(pm2_mode)	; -pm2-'s
		or	a
		jp	nz,pm2_end
		ld	hl,c_n		; c's tree
		call	make_tree	; HL = its root
		ld	(c_root),hl
		call	freq_of		; its count: the block's size
		ld	(blk_size),hl
		ld	b,16
		call	putbits
		ld	hl,(c_root)
		ld	de,C_SYMS
		or	a
		sbc	hl,de
		jr	c,send_block.one_c	; one symbol only
		call	count_t_freq	; pt's tree, from c's lengths
		ld	hl,t_n
		call	make_tree
		ld	de,T_SYMS
		or	a
		sbc	hl,de
		jr	c,send_block.one_t
		ld	c,T_SYMS	; pt's lengths
		ld	de,TBIT*256+3
		call	write_pt_len
		jr	send_block.c_len
send_block.one_t:
		add	hl,de		; one length only: 0, and it
		push	hl
		ld	hl,0
		ld	b,TBIT
		call	putbits
		pop	hl
		ld	b,TBIT
		call	putbits
send_block.c_len:
		call	write_c_len	; c's lengths
		jr	send_block.p
send_block.one_c:
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
send_block.p:
		ld	hl,p_n		; p's tree
		call	make_tree
		ld	de,P_SYMS
		or	a
		sbc	hl,de
		jr	c,send_block.one_p
		ld	c,P_SYMS	; p's lengths
		ld	de,PBIT*256+0FFh
		call	write_pt_len
		jr	send_block.codes
send_block.one_p:
		add	hl,de		; one size only: 0, and it
		push	hl
		ld	hl,0
		ld	b,PBIT
		call	putbits
		pop	hl
		ld	b,PBIT
		call	putbits
send_block.codes:
		ld	hl,(buf_at)	; then each symbol's code
		ld	(e_at),hl
		xor	a
		ld	(e_bit),a
send_block.symbol:
		ld	hl,(blk_size)
		ld	a,h
		or	l
		jr	z,send_block.sent
		dec	hl
		ld	(blk_size),hl
		call	buf_next	; CY: a match
		ld	d,0
		jr	nc,send_block.literal
		inc	d		; its symbol: 256 + the byte
		push	bc		; its distance - 1
		call	c_code_out
		pop	hl
		call	encode_p
		jr	send_block.symbol
send_block.literal:
		call	c_code_out
		jr	send_block.symbol
send_block.sent:
		ld	hl,(c_freq_at)	; the counts: 0
		ld	bc,2*C_SYMS
		call	zero
		ld	hl,p_freq
		ld	bc,2*P_SYMS
		jp	zero

; PMA (note 035): -pm2-, PMARC2's way of sending the same symbols.
;
; pm2_count - after out_sym, for -pm2-: one more symbol, and its bytes
;   off what is left of the unit; when that runs out, the unit is sent.
;
;   A unit is the symbols up to the one whose bytes reach the next 4 KB
;   of output, which may run past it: PMA's code tree may change only
;   there. Then what is left starts at 4096 again, less that overrun.
;
; Input:	o_kind, o_c: the symbol out_sym has just put in
;		pm2_left, pm2_syms; the tables mapped
; Output:	pm2_left, pm2_syms; the unit sent when it is complete
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

pm2_count:
		ld	hl,(pm2_syms)
		inc	hl
		ld	(pm2_syms),hl
		ld	de,1		; its bytes: 1, or a match's length
		ld	a,(o_kind)
		cp	2
		jr	nz,pm2_count.bytes
		ld	a,(o_c)		; the length less 3
		ld	e,a
		inc	de
		inc	de
		inc	de
pm2_count.bytes:
		ld	hl,(pm2_left)
		or	a
		sbc	hl,de
		ld	(pm2_left),hl
		jr	z,pm2_count.send	; exactly at the point
		bit	7,h
		ret	z		; not there yet
pm2_count.send:
		call	pm2_send
		ld	hl,(pm2_left)	; the next unit: 4096 less the
		ld	de,UNIT		;   overrun
		add	hl,de
		ld	(pm2_left),hl
		ret

; pm2_send - a unit's trees, then its symbols' codes.
;
;   Twice through the unit's symbols (pm2_code). First they are counted:
;   each one's code, and each match's offset code, by stretch: in the
;   first unit, the first, second and next 2 KB of output (points 1024
;   and 2048) have offset trees of their own, of 5, 6 and 7 codes, as
;   the distances they can have; later units one of 8. Then, after a 1
;   bit in a later unit (a new code tree), the code tree; the first
;   stretch's offset tree, if there are offset codes (pm2_need); then
;   each symbol's codes and bits, the next stretch's offset tree after
;   the symbol that reaches its point.
;
; Input:	the unit's symbols, pm2_syms of them, in the block
;		pm2_unit; the tables mapped
; Output:	written; the block empty; pm2_unit one on, to 2 at most
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

pm2_send:
		ld	hl,(c_freq_at)	; the counts: 0
		ld	de,2*PC_FREQ
		add	hl,de
		ld	bc,2*(PO_FREQ+48-PC_FREQ)
		call	zero
		call	pm2_walk	; counted
pm2_send.count:
		call	pm2_code
		ld	a,(ps_code)	; its code
		ld	l,a
		ld	h,0
		ld	de,PC_FREQ
		call	pm2_inc
		ld	a,(ps_m)	; a match: its offset code, in its
		or	a		;   stretch's counts
		jr	z,pm2_send.counted
		ld	a,(ps_st)
		add	a,a
		add	a,a
		add	a,a
		add	a,a
		ld	hl,ps_oc
		add	a,(hl)
		ld	l,a
		ld	h,0
		ld	de,PO_FREQ
		call	pm2_inc
pm2_send.counted:
		call	pm2_advance
		call	pm2_left_one
		jr	nz,pm2_send.count
		ld	a,(pm2_unit)	; a later unit: 1, a new code tree
		or	a
		jr	z,pm2_send.trees
		ld	hl,1
		ld	b,1
		call	putbits
pm2_send.trees:
		call	code_tree_out
		call	pm2_walk	; then the codes
		ld	a,(pm2_need)
		or	a
		call	nz,off_tree_out
pm2_send.symbol:
		call	pm2_code
		ld	a,(ps_code)	; the code, and its bits
		ld	e,a
		ld	d,0
		call	c_code_out
		ld	a,(ps_xb)
		or	a
		jr	z,pm2_send.match
		ld	b,a
		ld	hl,(ps_xv)
		call	putbits
pm2_send.match:
		ld	a,(ps_m)	; a match: its offset code, its bits
		or	a
		jr	z,pm2_send.sent
		ld	a,(ps_oc)
		add	a,OFF_AT
		ld	e,a
		ld	d,0
		call	c_code_out
		ld	a,(ps_ob)
		ld	b,a
		ld	hl,(ps_d)
		call	putbits
pm2_send.sent:
		call	pm2_advance	; CY: a new stretch
		jr	nc,pm2_send.next
		ld	a,(pm2_need)
		or	a
		call	nz,off_tree_out
pm2_send.next:
		call	pm2_left_one
		jr	nz,pm2_send.symbol
		ld	hl,0		; the block: empty
		ld	(bufpos),hl
		ld	(pm2_syms),hl
		xor	a
		ld	(mask),a
		ld	a,(pm2_unit)	; the next unit: 1, then 2 for all
		cp	2		;   after
		ret	nc
		inc	a
		ld	(pm2_unit),a
		ret

; pm2_walk - back to the unit's first symbol, at its first stretch.
;
; Input:	buf_at, pm2_syms
; Output:	e_at, e_bit, ps_o, ps_st, ps_cnt
; Modifies:	AF
;		HL
; Scratch:	none

pm2_walk:
		ld	hl,(buf_at)
		ld	(e_at),hl
		ld	hl,(pm2_syms)
		ld	(ps_cnt),hl
		ld	hl,0
		ld	(ps_o),hl
		xor	a
		ld	(e_bit),a
		ld	(ps_st),a
		ret

; pm2_left_one - one symbol fewer to go.
;
; Input:	ps_cnt
; Output:	ps_cnt less 1; Z set = none left
; Modifies:	AF
;		HL
; Scratch:	none

pm2_left_one:
		ld	hl,(ps_cnt)
		dec	hl
		ld	(ps_cnt),hl
		ld	a,h
		or	l
		ret

; pm2_inc - one more in a count.
;
; Input:	HL + DE = the count's word, in c_freq
; Modifies:	AF
;		HL
; Scratch:	none

pm2_inc:
		add	hl,de
		add	hl,hl
		ld	de,(c_freq_at)
		add	hl,de
		inc	(hl)
		ret	nz
		inc	hl
		inc	(hl)
		ret

; pm2_advance - the output, past the symbol; in the first unit, the
;   stretch it reaches. No symbol is long enough to pass two points.
;
; Input:	ps_o, ps_n, ps_st, pm2_unit
; Output:	ps_o; CY set = a new stretch, ps_st one on
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

pm2_advance:
		ld	hl,(ps_o)
		ld	de,(ps_n)
		add	hl,de
		ld	(ps_o),hl
		ld	a,(pm2_unit)	; later units: one stretch
		or	a
		ret	nz		; CY clear
		ld	a,h		; the output's whole KB
		rrca
		rrca
		and	3Fh
		ld	c,a
		ld	a,(ps_st)	; the next point: (stretch + 1) KB,
		cp	2		;   1 and 2 only
		ret	nc
		inc	a
		ld	b,a
		ld	a,c
		cp	b		; CY: not reached
		ccf
		ret	nc
		ld	a,b
		ld	(ps_st),a
		ret			; CY set

; pm2_code - the unit's next symbol, as -pm2- sends it.
;
;   A literal is its place in the list (round): its code is its row in
;   hist_rows, the place's low bits after it. A match's code is 9 to 22
;   for 3 to 16 bytes; longer, its row in copy_rows, and the length's
;   offset in it after it. Its distance less 1: offset code 0 and 6
;   bits under 64; otherwise its bits less 6, and the distance's bits
;   but the highest after it, which putbits leaves out.
;
; Input:	the block, at e_at (buf_next)
; Output:	ps_m: 0FFh for a match; ps_code; ps_xv, ps_xb: the bits
;		after it; ps_n: its bytes; for a match ps_d, ps_oc, ps_ob
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

pm2_code:
		call	buf_next	; CY: a match, E = length - 3,
		ld	hl,0		;   BC = distance - 1; else E
		ld	(ps_xv),hl	;   = the place
		sbc	a,a		; ps_m: 0FFh for a match
		ld	(ps_m),a
		jr	c,pm2_code.match
		inc	hl		; a byte: 1
		ld	(ps_n),hl
		ld	a,e
		ld	(ps_xv),a	; its low bits go
		ld	hl,hist_rows+14	; its row: from the last back
		ld	c,7
pm2_code.row:
		cp	(hl)
		jr	nc,pm2_code.byte
		dec	hl
		dec	hl
		dec	c
		jr	pm2_code.row
pm2_code.byte:
		inc	hl
		ld	a,(hl)
		ld	(ps_xb),a
		ld	a,c
		ld	(ps_code),a
		ret
pm2_code.match:
		ld	(ps_d),bc
		ld	a,e		; its bytes: E + 3
		ld	l,a
		ld	h,0
		inc	hl
		inc	hl
		inc	hl
		ld	(ps_n),hl
		cp	14		; 3 to 16: code E + 9, no bits
		jr	nc,pm2_code.long
		add	a,9
		ld	(ps_code),a
		xor	a
		ld	(ps_xb),a
		jr	pm2_code.distance
pm2_code.long:
		ld	hl,copy_rows+12	; its row: from the last back
pm2_code.lrow:
		cp	(hl)
		jr	nc,pm2_code.length
		dec	hl
		dec	hl
		dec	hl
		jr	pm2_code.lrow
pm2_code.length:
		sub	(hl)		; its offset in the row
		ld	(ps_xv),a
		inc	hl
		ld	a,(hl)
		ld	(ps_code),a
		inc	hl
		ld	a,(hl)
		ld	(ps_xb),a
pm2_code.distance:
		ld	hl,(ps_d)	; its bits: under 7, code 0 and 6
		call	bitlen
		sub	6
		jr	nc,pm2_code.far
		xor	a
pm2_code.far:
		ld	(ps_oc),a
		add	a,5		; code n: n + 5 bits; code 0: 6
		cp	5
		jr	nz,pm2_code.bits
		inc	a
pm2_code.bits:
		ld	(ps_ob),a
		ret

; code_tree_out - the unit's code tree: its lengths, as PMA sends them.
;
;   make_tree, 12 bits at most, two codes at least (guarded_tree). Then
;   how many codes there are, up to the last with a length (5 bits); the
;   shortest length (3 bits); the bits each length takes (3 bits); and
;   each length, 0 for none, else less the shortest, plus 1. Ten codes
;   or more mean there are matches, and offset trees (pm2_need).
;
; Input:	PC_FREQ's counts; the tables mapped
; Output:	written; c_len, c_code from symbol 0; pm2_need
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	pw_n
;		pw_min
;		pw_lb

code_tree_out:
		ld	a,CODE_MAX
		ld	(mt_max),a
		ld	bc,29		; 29 codes, from symbol 0, their
		ld	de,0		;   counts from PC_FREQ
		ld	hl,PC_FREQ
		call	d_tree
		ld	hl,(c_len_at)	; how many: up to the last length
		ld	bc,29
		add	hl,bc
code_tree_out.last:
		dec	hl
		ld	a,(hl)
		or	a
		jr	nz,code_tree_out.counted
		dec	c
		jr	code_tree_out.last
code_tree_out.counted:
		ld	a,c
		ld	(pw_n),a
		cp	10		; ten or more: offset trees
		sbc	a,a
		inc	a
		ld	(pm2_need),a
		ld	hl,(c_len_at)	; the shortest and the longest
		ld	b,c
		ld	de,0FFh		; D = longest, E = shortest
code_tree_out.scan:
		ld	a,(hl)
		inc	hl
		or	a
		jr	z,code_tree_out.skip
		cp	e
		jr	nc,code_tree_out.short
		ld	e,a
code_tree_out.short:
		cp	d
		jr	c,code_tree_out.skip
		ld	d,a
code_tree_out.skip:
		djnz	code_tree_out.scan
		ld	a,e
		ld	(pw_min),a
		ld	a,d		; the bits for longest - shortest + 1
		sub	e
		inc	a
		ld	l,a
		ld	h,0
		call	bitlen
		ld	(pw_lb),a
		ld	a,(pw_n)	; then the three numbers
		ld	l,a
		ld	h,0
		ld	b,5
		call	putbits
		ld	a,(pw_min)
		ld	l,a
		ld	h,0
		ld	b,3
		call	putbits
		ld	a,(pw_lb)
		ld	l,a
		ld	h,0
		ld	b,3
		call	putbits
		ld	hl,(c_len_at)	; and the lengths
		ld	(pw_at),hl
code_tree_out.length:
		ld	hl,(pw_at)
		ld	a,(hl)
		inc	hl
		ld	(pw_at),hl
		or	a
		jr	z,code_tree_out.put
		ld	hl,pw_min
		sub	(hl)
		inc	a
code_tree_out.put:
		ld	l,a
		ld	h,0
		ld	a,(pw_lb)
		ld	b,a
		call	putbits
		ld	hl,pw_n
		dec	(hl)
		jr	nz,code_tree_out.length
		ret

; off_tree_out - the stretch's offset tree: 3 bits a length.
;
;   Of 5, 6 or 7 codes in the first unit's three stretches, 8 later;
;   make_tree, 7 bits at most, two codes at least. A stretch with no
;   match gets codes 0 and 1, never sent.
;
; Input:	ps_st, pm2_unit; PO_FREQ's counts, 16 words a stretch
; Output:	written; c_len, c_code from OFF_AT
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	pw_n
;		pw_at

off_tree_out:
		ld	a,OFF_MAX
		ld	(mt_max),a
		ld	a,(ps_st)	; its codes: 5 + stretch, or 8
		ld	c,a
		add	a,5
		ld	b,a
		ld	a,(pm2_unit)
		or	a
		jr	z,off_tree_out.codes
		ld	b,8
off_tree_out.codes:
		ld	a,b
		ld	(pw_n),a
		ld	a,c		; its counts: PO_FREQ + 16 * stretch
		add	a,a
		add	a,a
		add	a,a
		add	a,a
		ld	l,a
		ld	h,0
		ld	de,PO_FREQ
		add	hl,de
		ld	c,b
		ld	b,0
		ld	de,OFF_AT
		call	d_tree
		ld	hl,(c_len_at)	; the lengths
		ld	de,OFF_AT
		add	hl,de
		ld	(pw_at),hl
off_tree_out.length:
		ld	hl,(pw_at)
		ld	a,(hl)
		inc	hl
		ld	(pw_at),hl
		ld	l,a
		ld	h,0
		ld	b,3
		call	putbits
		ld	hl,pw_n
		dec	(hl)
		jr	nz,off_tree_out.length
		ret

; pm2_end - the member's last unit, and what a decoder reads at a point
;   the data ends on.
;
;   A member that ends exactly at a unit's end (4096, 8192...) has that
;   unit sent already, and a decoder reads, there, the next unit's 1 bit:
;   it gets a 0 (the code tree kept), and after the first unit an offset
;   tree too, of codes 0 and 1, if there are offset codes.
;
; Input:	pm2_syms, pm2_left, pm2_unit, pm2_need; the tables mapped
; Output:	written
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

pm2_end:
		ld	hl,(pm2_syms)	; symbols left: the last unit
		ld	a,h
		or	l
		jp	nz,pm2_send
		ld	hl,(pm2_left)	; none: at a unit's end?
		ld	de,UNIT
		or	a
		sbc	hl,de
		ret	nz
		ld	a,(pm2_unit)	; (not before the first)
		or	a
		ret	z
		ld	hl,0		; the code tree kept: 0
		ld	b,1
		call	putbits
		ld	a,(pm2_unit)	; after the first unit only: an offset
		dec	a		;   tree, if there are offset codes
		ret	nz
		ld	(ps_st),a
		ld	a,(pm2_need)
		or	a
		ret	z
		ld	hl,(c_freq_at)	; no counts: codes 0 and 1
		ld	de,2*PO_FREQ
		add	hl,de
		ld	bc,32
		call	zero
		jp	off_tree_out

; pm2_start - for -pm2-: the list, the units' counts, and the bit
;   that comes first and is not used.
;
; Input:	none
; Output:	mtf_order; pm2_left, pm2_unit, pm2_syms; the bit, written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

pm2_start:
		ld	hl,UNIT
		ld	(pm2_left),hl
		ld	hl,0
		ld	(pm2_syms),hl
		xor	a
		ld	(pm2_unit),a
		ld	de,mtf_order	; the list: PMARC2's groups, in order
		ld	hl,mtf_groups
		ld	c,5
pm2_start.group:
		ld	a,(hl)		; the first byte, then how many
		inc	hl
		ld	b,(hl)
		inc	hl
pm2_start.byte:
		ld	(de),a
		inc	de
		inc	a
		djnz	pm2_start.byte
		dec	c
		jr	nz,pm2_start.group
		ld	hl,0		; the bit not used: 0
		ld	b,1
		jp	putbits

; mtf_place - a byte's place in the list, and the byte to its head.
;
;   The list is an array, the head first: CPIR finds the byte, its
;   place 255 less what is left of the count; LDDR moves those before it
;   one on, and it goes first. As the decoder's list, the same order.
;
; Input:	A = the byte
; Output:	A = its place, 0 to 255; the list
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

mtf_place:
		ld	hl,mtf_order
		ld	bc,256
		cpir			; HL -> after it, C = 255 - its place
		ld	e,a		; E = the byte
		ld	a,255
		sub	c		; A = its place
		ret	z		; the head already
		push	af
		push	de
		dec	hl		; those before it, one on
		ld	d,h
		ld	e,l
		dec	hl
		ld	c,a		; B is 0
		lddr
		pop	hl		; and it first: DE -> mtf_order
		ld	a,l
		ld	(de),a
		pop	af
		ret

; mtf_match - a match's bytes, to the list's head, in order.
;
; Input:	last_len, s_a: the match, from s_a - 1; the text mapped
; Output:	the list
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	mm_n
;		mm_at

mtf_match:
		ld	hl,(last_len)
		ld	(mm_n),hl
		ld	hl,(s_a)
		dec	hl
		ld	(mm_at),hl
mtf_match.byte:
		ld	hl,(mm_at)
		call	ring_addr
		ld	a,(hl)
		call	mtf_place
		ld	hl,(mm_at)
		inc	hl
		ld	(mm_at),hl
		ld	hl,(mm_n)
		dec	hl
		ld	(mm_n),hl
		ld	a,h
		or	l
		jr	nz,mtf_match.byte
		ret

; buf_next - the block's next symbol, from e_at.
;
;   A flags byte comes before every 8 symbols (out_sym); e_bit counts
;   the flags left in e_flags, their next in bit 7.
;
; Input:	e_at, e_bit, e_flags; the tables mapped
; Output:	CY set = a match: E = its length - 3, BC = its distance - 1
;		CY clear = a literal: E = the byte
;		e_at, e_bit, e_flags moved on
; Modifies:	AF
;		BC
;		E
;		HL
; Scratch:	none

buf_next:
		ld	a,(e_bit)	; every 8: a flags byte
		or	a
		jr	nz,buf_next.shift
		ld	hl,(e_at)
		ld	a,(hl)
		inc	hl
		ld	(e_at),hl
		ld	(e_flags),a
		ld	a,7
		ld	(e_bit),a
		jr	buf_next.flag
buf_next.shift:
		dec	a
		ld	(e_bit),a
		ld	a,(e_flags)
		add	a,a
		ld	(e_flags),a
buf_next.flag:
		ld	a,(e_flags)
		add	a,a		; bit 7: a match
		ld	hl,(e_at)
		ld	e,(hl)
		inc	hl
		jr	nc,buf_next.done
		ld	b,(hl)		; its distance - 1
		inc	hl
		ld	c,(hl)
		inc	hl
buf_next.done:
		ld	(e_at),hl
		ret

; c_code_out - c's code for a symbol.
;
; Input:	DE = the symbol
;		c_len, c_code; the tables mapped
; Output:	its code, written
; Modifies:	AF
;		BC
;		HL
; Scratch:	none

c_code_out:
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
		jp	putcode

; encode_p - a match's distance - 1: the code for its size in bits, then
;   its bits below the highest.
;
; Input:	HL = the distance - 1
;		pt_len, pt_code: p's
; Output:	written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

encode_p:
		push	hl
		call	bitlen		; A = its size
		ld	(ep_k),a
		call	pt_code_out
		pop	hl
		ld	a,(ep_k)
		cp	2
		ret	c		; 0 or 1: the size says it all
		dec	a
		ld	b,a
		jp	putbits

; d_send_block - the block, deflate's way: its header, its trees if it
;   sends them, its symbols' codes, then the end of block.
;
;   The symbols are counted again, as deflate numbers them (d_walk): a
;   literal is its byte, a match a length code and a distance code; 256
;   ends the block. From the counts, two trees, MAX_LL bits at most: the
;   literals' and lengths' (286 symbols) in c's arrays, and the
;   distances' (30) after it, from D_AT; their counts from D_FREQ
;   (d_tree). Their lengths go out in one run, HLIT always 286, with a
;   third tree, MAX_CL bits at most (cl_runs). Then d_compare weighs
;   the block both ways: fixed, if no bigger, and fixed_codes puts its
;   codes in the trees' place.
;
;   The header: BFINAL, BTYPE; for a dynamic block, HLIT - 257 (29),
;   HDIST - 1, HCLEN - 4, then the third tree's lengths, 3 bits each, in
;   cl_order's order, and the run.
;
; Input:	the block; d_final: 1 for the member's last
;		the tables mapped
; Output:	written
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

d_send_block:
		xor	a		; first counted: d_write 0
		ld	(d_write),a
		ld	hl,(c_freq_at)	; both trees' counts: 0
		ld	bc,2*D_FREQ+2*D_SYMS
		call	zero
		call	d_walk		; each symbol, counted
		ld	de,END_BLOCK	; and the block's end
		call	d_out
		ld	a,MAX_LL	; the two trees
		ld	(mt_max),a
		ld	bc,LL_SYMS	; literals and lengths
		ld	de,0
		ld	hl,0
		call	d_tree
		ld	bc,D_SYMS	; distances
		ld	de,D_AT
		ld	hl,D_FREQ
		call	d_tree
		ld	hl,(c_len_at)	; HDIST: the distances' lengths,
		ld	de,D_AT		;   not the zeros after them
		add	hl,de
		ld	bc,D_SYMS
		call	trim
		ld	a,c
		ld	(d_hdist),a
		ld	hl,t_freq	; the lengths' tree, from the run
		ld	bc,2*T_SYMS
		call	zero
		call	cl_runs
		ld	a,MAX_CL
		ld	(mt_max),a
		ld	hl,t_n
		call	guarded_tree
		ld	hl,cl_order+T_SYMS-1	; HCLEN: its lengths sent, in
		ld	b,T_SYMS	;   cl_order's order, 4 at least
d_send_block.hclen:
		ld	a,b
		cp	5
		jr	c,d_send_block.sized
		ld	e,(hl)
		ld	d,0
		push	hl
		ld	hl,pt_len
		add	hl,de
		ld	a,(hl)
		pop	hl
		or	a
		jr	nz,d_send_block.sized
		dec	hl
		dec	b
		jr	d_send_block.hclen
d_send_block.sized:
		ld	a,b
		ld	(d_hclen),a
		call	d_compare	; CY: dynamic is smaller
		jr	nc,d_send_block.fixed
		ld	a,(d_final)	; BFINAL, BTYPE 2, HLIT 29
		or	4+29*8
		ld	l,a
		ld	h,0
		ld	b,8
		call	d_putbits
		ld	a,(d_hclen)	; HDIST - 1, HCLEN - 4
		sub	4
		ld	l,a
		ld	h,0
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	a,(d_hdist)
		dec	a
		or	l
		ld	l,a
		ld	b,9
		call	d_putbits
		ld	hl,cl_order	; the lengths' tree's lengths
		ld	a,(d_hclen)
		ld	b,a
d_send_block.cl:
		push	bc
		push	hl
		ld	e,(hl)
		ld	d,0
		ld	hl,pt_len
		add	hl,de
		ld	l,(hl)
		ld	b,3
		call	d_putbits
		pop	hl
		inc	hl
		pop	bc
		djnz	d_send_block.cl
		ld	a,1		; the run, written
		ld	(d_write),a
		call	cl_runs
		jr	d_send_block.codes
d_send_block.fixed:
		ld	a,(d_final)	; BFINAL, BTYPE 1
		or	2
		ld	l,a
		ld	h,0
		ld	b,3
		call	d_putbits
		call	fixed_codes
d_send_block.codes:
		ld	a,1		; the symbols' codes
		ld	(d_write),a
		call	d_walk
		ld	de,END_BLOCK	; and the end of block
		ld	b,0
		jp	d_out

; d_walk - every symbol in the block, as deflate numbers it, to d_out.
;
; Input:	the block: from buf_at, bufpos bytes; d_write
;		the tables mapped
; Output:	counted, or written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

d_walk:
		ld	hl,(buf_at)
		ld	(e_at),hl
		ld	de,(bufpos)	; the block's end
		add	hl,de
		ld	(d_end),hl
		xor	a
		ld	(e_bit),a
d_walk.next:
		ld	hl,(e_at)	; at the end: done
		ld	de,(d_end)
		or	a
		sbc	hl,de
		ret	z
		call	buf_next	; CY: a match
		jr	c,d_walk.match
		ld	d,0		; a literal: its byte
		ld	b,0
		call	d_out
		jr	d_walk.next
d_walk.match:
		push	bc
		ld	a,e		; its length's code
		call	len_code
		call	d_out
		pop	hl		; its distance's
		call	dist_code
		call	d_out
		jr	d_walk.next

; d_out - one symbol: counted (d_write 0), or its code written, and its
;   extra bits after it.
;
; Input:	DE = the symbol: 0 to 285, D_AT on for a distance
;		HL = its extra bits; B = how many, 0 for none
;		d_write; the trees' codes when writing
; Output:	counted, or written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

d_out:
		ld	a,(d_write)
		or	a
		jr	nz,d_out.write
		call	freq_at		; one more
		inc	(hl)
		ret	nz
		inc	hl
		inc	(hl)
		ret
d_out.write:
		push	hl
		push	bc
		call	c_code_out
		pop	bc
		pop	hl
		jp	d_putbits

; freq_at - where a symbol's count is: c_freq's word for a literal or a
;   length, D_FREQ's on for a distance.
;
; Input:	DE = the symbol: 0 to 285, D_AT on for a distance
; Output:	HL -> its count
; Modifies:	F
;		BC
;		HL
; Scratch:	none

freq_at:
		ld	h,d
		ld	l,e
		ld	bc,-D_AT	; CY: a distance
		add	hl,bc
		ld	h,d
		ld	l,e
		jr	nc,freq_at.word
		ld	bc,D_FREQ-D_AT
		add	hl,bc
freq_at.word:
		add	hl,hl
		ld	bc,(c_freq_at)
		add	hl,bc
		ret

; len_code - a match's length code, and its extra bits.
;
;   Lengths 3 to 10 are codes 257 to 264. From 11 on, each four codes
;   cover twice as many lengths as the four before: length - 3, k bits
;   long, is code 257 + 4 (k - 2) + its two bits below the highest, and
;   its k - 3 lowest bits follow.
;
; Input:	A = the length - 3: 0 to 253
; Output:	DE = its code: 257 to 284
;		HL = the length - 3; B = how many of its bits follow
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

len_code:
		ld	l,a
		ld	h,0
		ld	b,h		; no bits follow
		cp	8
		jr	c,len_code.code	; 3 to 10: 257 + it
		ld	c,a
		call	bitlen		; A = k: 4 to 8
		sub	3
		ld	b,a		; k - 3 bits follow
		push	bc
		ld	a,c
len_code.shift:
		srl	a
		djnz	len_code.shift
		pop	bc
		and	3		; the two below the highest
		ld	e,a
		ld	a,b
		inc	a
		add	a,a
		add	a,a
		add	a,e		; 4 (k - 2) + them
		ld	l,c
		ld	h,0
len_code.code:
		ld	e,a
		ld	d,1		; 256 + it, and 1
		inc	de
		ret

; dist_code - a match's distance code, and its extra bits.
;
;   Distances 1 to 4 are codes 0 to 3. From 5 on, each two codes cover
;   twice as many as the two before: distance - 1, k bits long, is code
;   2 (k - 1) + its bit below the highest, and its k - 2 lowest bits
;   follow.
;
; Input:	HL = the distance - 1: 0 to 8191
; Output:	DE = D_AT + its code: 0 to 25
;		HL = the distance - 1; B = how many of its bits follow
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

dist_code:
		ld	b,0		; no bits follow
		ld	a,h
		or	a
		jr	nz,dist_code.long
		ld	a,l
		cp	4
		jr	c,dist_code.code	; 1 to 4: it
dist_code.long:
		push	hl
		call	bitlen		; A = k: 3 to 13
		pop	hl
		push	hl
		sub	2
		ld	b,a		; k - 2 bits follow
		push	bc
dist_code.shift:
		srl	h
		rr	l
		djnz	dist_code.shift
		pop	bc
		ld	a,l		; the bit below the highest
		and	1
		ld	c,a
		ld	a,b
		inc	a
		add	a,a		; 2 (k - 1) + it
		add	a,c
		pop	hl
dist_code.code:
		ld	e,a
		ld	d,0
		push	hl
		ld	hl,D_AT
		add	hl,de
		ex	de,hl
		pop	hl
		ret

; d_tree, guarded_tree - one of deflate's trees.
;
;   d_tree makes its descriptor (d_desc) and goes on into guarded_tree,
;   which makes sure two symbols at least are counted (two_used) before
;   make_tree.
;
; Input:	d_tree: BC = how many symbols; DE = where its lengths and
;		codes start, by symbol: 0, or D_AT; HL = where its counts
;		start, by symbol: 0, or D_FREQ
;		guarded_tree: HL -> a descriptor: n, freq, len, code
;		mt_max
; Output:	as make_tree
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

d_tree:
		call	d_desc
guarded_tree:
		push	hl
		call	two_used
		pop	hl
		jp	make_tree

; d_desc - a descriptor for make_tree or lens_code, in dt_n: one of
;   deflate's trees, in c's arrays.
;
; Input:	BC = how many symbols; DE = where its lengths and codes
;		start, by symbol; HL = where its counts start, by symbol
; Output:	HL -> dt_n
; Modifies:	BC
;		HL
; Scratch:	none

d_desc:
		ld	(dt_n),bc
		add	hl,hl
		ld	bc,(c_freq_at)
		add	hl,bc
		ld	(dt_freq),hl
		ld	hl,(c_len_at)
		add	hl,de
		ld	(dt_len),hl
		ld	hl,(c_code_at)
		add	hl,de
		add	hl,de
		ld	(dt_code),hl
		ld	hl,dt_n
		ret

; two_used - two symbols counted at least, for a tree.
;
;   A tree of one symbol, or none, would have codes deflate's readers
;   may refuse: a block of literals only has no distance. With fewer
;   than two, symbols 0 and 1 count once, if they don't already, as
;   zlib's deflate does.
;
; Input:	HL -> n, then a pointer to the counts
; Output:	the counts
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

two_used:
		ld	c,(hl)		; BC = n
		inc	hl
		ld	b,(hl)
		inc	hl
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ex	de,hl		; HL -> the counts
		push	hl
		ld	d,0		; D = how many used
two_used.count:
		ld	a,(hl)
		inc	hl
		or	(hl)
		inc	hl
		jr	z,two_used.next
		inc	d
		ld	a,d
		cp	2
		jr	z,two_used.enough
two_used.next:
		dec	bc
		ld	a,b
		or	c
		jr	nz,two_used.count
		pop	hl		; fewer: 0 and 1, once
		ld	b,2
two_used.one:
		ld	a,(hl)
		inc	hl
		or	(hl)
		dec	hl
		jr	nz,two_used.has
		ld	(hl),1
two_used.has:
		inc	hl
		inc	hl
		djnz	two_used.one
		ret
two_used.enough:
		pop	hl
		ret

; cl_runs - the literals' and distances' lengths, in one run, for the
;   lengths' tree: counted (d_write 0) or written.
;
;   The 286 lengths, then HDIST more. A length goes as itself once,
;   then 3 to 6 more of it as 16 (2 bits: how many - 3); zeros as 18,
;   11 to 138 of them (7 bits: - 11), then 17, 3 to 10 (3 bits: - 3).
;   What is left, 1 or 2, goes as itself. A run may cross from the
;   literals to the distances.
;
; Input:	c_len; d_hdist; d_write
; Output:	t_freq counted, or the run written
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

cl_runs:
		ld	hl,(c_len_at)
		ld	(cr_at),hl
		ld	a,(d_hdist)
		ld	l,a
		ld	h,0
		ld	de,LL_SYMS
		add	hl,de
		ld	(cr_n),hl
cl_runs.next:
		ld	bc,(cr_n)
		ld	a,b
		or	c
		ret	z
		ld	hl,(cr_at)	; DE = how many the same
		ld	a,(hl)
		ld	(cr_v),a
		ld	de,0
cl_runs.same:
		ld	a,b
		or	c
		jr	z,cl_runs.counted
		ld	a,(cr_v)
		cp	(hl)
		jr	nz,cl_runs.counted
		inc	hl
		inc	de
		dec	bc
		jr	cl_runs.same
cl_runs.counted:
		ld	(cr_at),hl
		ld	(cr_n),bc
		ld	a,(cr_v)
		or	a
		jr	z,cl_runs.zeros
		push	de		; a length: itself
		ld	b,0
		call	cl_sym
		pop	de
		dec	de
		ld	ix,rep_16	; then 16s
		call	cl_rep
		jr	cl_runs.tail
cl_runs.zeros:
		ld	ix,rep_18	; zeros: 18s, then a 17
		call	cl_rep
		ld	ix,rep_17
		call	cl_rep
cl_runs.tail:
		ld	a,e		; 0 to 2 left: each itself
		or	a
		jr	z,cl_runs.next
		push	de
		ld	a,(cr_v)
		ld	b,0
		call	cl_sym
		pop	de
		dec	e
		jr	cl_runs.tail

; cl_rep - as many repeats of one kind as the run allows.
;
; Input:	IX -> the kind: its symbol, the fewest and the most it
;		says, its extra bits
;		DE = how many are left in the run
; Output:	DE = how many are left: fewer than the fewest
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

cl_rep:
		ld	a,d
		or	a
		jr	nz,cl_rep.most
		ld	a,e
		cp	(ix+1)		; too few
		ret	c
		cp	(ix+2)
		jr	c,cl_rep.k
cl_rep.most:
		ld	a,(ix+2)	; as many as it says
cl_rep.k:
		push	de
		push	af
		sub	(ix+1)		; the extra bits: how many - fewest
		ld	l,a
		ld	h,0
		ld	b,(ix+3)
		ld	a,(ix+0)
		call	cl_sym
		pop	af
		pop	de
		ld	l,a		; fewer left
		ld	h,0
		ex	de,hl
		or	a
		sbc	hl,de
		ex	de,hl
		jr	cl_rep

; cl_sym - one of the lengths' tree's symbols: counted (d_write 0), or
;   its code written, and its extra bits after it.
;
; Input:	A = the symbol: 0 to 18
;		HL = its extra bits; B = how many, 0 for none
;		d_write; pt_len, pt_code when writing
; Output:	t_freq counted, or written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

cl_sym:
		push	hl
		push	bc
		ld	c,a
		ld	a,(d_write)
		or	a
		ld	a,c
		jr	nz,cl_sym.write
		call	t_count
		pop	bc
		pop	hl
		ret
cl_sym.write:
		call	pt_code_out
		pop	bc
		pop	hl
		jp	d_putbits

; d_compare - the block's size, dynamic less fixed, in bits.
;
;   Only what differs: each symbol's count times its code's length,
;   dynamic less fixed (the extra bits are the same both ways); and
;   for dynamic, the run, its extra bits, the lengths' tree's lengths,
;   and HLIT, HDIST and HCLEN (14 bits). In acc, 24 bits, signed.
;
; Input:	the counts and lengths of the three trees; d_hclen
; Output:	CY set = dynamic is smaller
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

d_compare:
		ld	hl,0
		ld	(acc),hl
		xor	a
		ld	(acc+2),a
		ld	de,0		; the literals, lengths, distances
d_compare.ld:
		push	de
		call	freq_at
		ld	a,(hl)		; HL = the count
		inc	hl
		ld	h,(hl)
		ld	l,a
		push	hl
		call	fixed_len	; less the fixed length
		ld	c,a
		ld	hl,(c_len_at)
		add	hl,de
		ld	a,(hl)
		sub	c
		pop	hl
		call	acc_mul
		pop	de
		inc	de
		ld	hl,LL_SYMS+D_SYMS
		or	a
		sbc	hl,de
		jr	nz,d_compare.ld
		ld	ix,t_freq	; the run: its codes and bits
		ld	de,pt_len
		ld	c,0
d_compare.cl:
		ld	a,c		; B = the symbol's extra bits
		ld	b,0
		cp	16
		jr	c,d_compare.extra
		ld	b,2
		jr	z,d_compare.extra
		ld	b,3
		cp	17
		jr	z,d_compare.extra
		ld	b,7
d_compare.extra:
		ld	a,(de)
		add	a,b
		ld	l,(ix+0)
		ld	h,(ix+1)
		push	de
		push	bc
		call	acc_mul
		pop	bc
		pop	de
		inc	ix
		inc	ix
		inc	de
		inc	c
		ld	a,c
		cp	T_SYMS
		jr	nz,d_compare.cl
		ld	a,(d_hclen)	; 14 + 3 bits for each length
		ld	l,a		;   of the lengths' tree
		ld	h,0
		ld	d,h
		ld	e,l
		add	hl,hl
		add	hl,de
		ld	de,14
		add	hl,de
		ld	a,1
		call	acc_mul
		ld	a,(acc+2)	; negative: dynamic is smaller
		rla
		ret

; acc_mul - acc += HL * A.
;
; Input:	HL = a count
;		A = what each one adds: -15 to 15, or 1
; Output:	acc
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

acc_mul:
		ld	b,a
		ld	a,h		; nothing to add
		or	l
		ret	z
		ld	a,b
		or	a
		ret	z
		ld	de,(acc)	; C:DE = acc
		ld	a,(acc+2)
		ld	c,a
		bit	7,b
		jr	nz,acc_mul.less
acc_mul.add:
		ex	de,hl
		add	hl,de
		ex	de,hl
		jr	nc,acc_mul.added
		inc	c
acc_mul.added:
		djnz	acc_mul.add
		jr	acc_mul.done
acc_mul.less:
		ld	a,b
		neg
		ld	b,a
acc_mul.sub:
		ex	de,hl
		or	a
		sbc	hl,de
		ex	de,hl
		jr	nc,acc_mul.subbed
		dec	c
acc_mul.subbed:
		djnz	acc_mul.sub
acc_mul.done:
		ld	(acc),de
		ld	a,c
		ld	(acc+2),a
		ret

; fixed_len - a symbol's fixed code length: literals 0 to 143, 8 bits;
;   144 to 255, 9; 256 to 279, 7; 280 to 285, 8; a distance, 5.
;
; Input:	DE = the symbol: 0 to 285, D_AT on for a distance
; Output:	A = the length
; Modifies:	AF
; Scratch:	none

fixed_len:
		ld	a,d
		or	a
		jr	nz,fixed_len.high
		ld	a,e
		cp	144
		ld	a,8
		ret	c
		inc	a
		ret
fixed_len.high:
		ld	a,e		; 256 on
		cp	280-256
		ld	a,7
		ret	c
		ld	a,e
		cp	D_AT-256
		ld	a,8
		ret	c
		ld	a,5
		ret

; fixed_codes - the fixed codes, in the trees' place.
;
;   The literals' codes are made from 288 lengths: 286 and 287, 8 bits,
;   count for the 9-bit codes after them to be right, though they are
;   never sent. The distances' lengths, 5, then take their place.
;
; Input:	none
; Output:	c_len, c_code: the fixed codes
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

fixed_codes:
		ld	hl,(c_len_at)	; every length
		ld	de,0
fixed_codes.len:
		call	fixed_len
		ld	(hl),a
		inc	hl
		inc	de
		push	hl
		ld	hl,LL_SYMS+D_SYMS
		or	a
		sbc	hl,de
		pop	hl
		jr	nz,fixed_codes.len
		ld	hl,(c_len_at)	; 286 and 287: 8, for now
		ld	de,LL_SYMS
		add	hl,de
		ld	(hl),8
		inc	hl
		ld	(hl),8
		push	hl
		ld	bc,LL_SYMS+2	; the literals' and lengths' codes
		ld	de,0
		ld	hl,0
		call	d_desc
		call	lens_code
		pop	hl		; then the distances'
		ld	(hl),5
		dec	hl
		ld	(hl),5
		ld	bc,D_SYMS
		ld	de,D_AT
		ld	hl,D_FREQ
		call	d_desc
		jp	lens_code

; d_putbits - write bits, lowest first: deflate's numbers.
;
; Input:	B = how many bits: 0 to 16
;		HL = the bits: the lowest B
; Output:	written, through outbuf
; Modifies:	AF
;		BC
;		HL
; Scratch:	none

d_putbits:
		inc	b
		dec	b
		ret	z		; none
		ld	a,(bitbuf)
		ld	c,a
d_putbits.bit:
		srl	h
		rr	l
		rr	c
		jr	nc,d_putbits.more
		call	put_byte	; C = 8 bits
		ld	c,80h
d_putbits.more:
		djnz	d_putbits.bit
		ld	a,c
		ld	(bitbuf),a
		ret

; patch_small - the code for small packing: the text an 8 KB ring at
;   8000h, prev 4096 words at A000h, both in one segment.
;
;   The masks are in the code, as immediates and as RES instructions,
;   where they cost nothing at full strength. For small packing each is
;   changed in place, once, from the table: an 8 KB ring is masked with
;   1Fh where 16 KB is with 3Fh, wraps with RES 5 where 16 KB wraps
;   with RES 6, and prev's words start at A0h instead of 80h. map_prev
;   maps the text's segment, which is prev's too.
;
; Input:	patch_list
; Output:	the code changed
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

patch_small:
		ld	hl,patch_list
		ld	b,PATCH_COUNT
patch_small.next:
		ld	e,(hl)		; DE -> the byte, A = its new value
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	a,(hl)
		inc	hl
		ld	(de),a
		djnz	patch_small.next
		ret

; map_text, map_prev, map_tables - the text's segment, prev's, or the
;   tables' block in page 2, if it isn't there already.
;
;   p2cur says which of the three page 2 shows, 0 for none. The first
;   after forget is mapped with deref; after that, if all three are in
;   the primary mapper (fast), p2seg switches between them, which only
;   changes the segment, and costs a third as much (alloc.as, note 027).
;
; Input:	text_fp, prev_fp, tables_fp; p2cur, p2fast, fast
; Output:	mapped
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

map_text:
		ld	a,1
		jr	map
map_prev:
p_map_prev:
		ld	a,2
		jr	map
map_tables:
		ld	a,3
map:
		ld	hl,p2cur
		cp	(hl)
		ret	z		; there already
		ld	(hl),a
		add	a,a		; its far pointer: text_fp, prev_fp
		add	a,a		;   or tables_fp
		ld	e,a
		ld	d,0
		ld	hl,text_fp-4
		add	hl,de
		ld	a,(p2fast)
		or	a
		jr	z,map.deref
		inc	hl		; its segment, directly
		ld	a,(hl)
		jp	p2seg
map.deref:
		call	deref
		ld	a,(fast)	; page 2 shows the primary mapper's
		ld	(p2fast),a	;   slot now, if all three are there
		ret

; forget - page 2's contents unknown: after MSX-DOS, or KAGO.
;
; Input:	none
; Output:	p2cur, p2fast: 0
; Modifies:	AF
; Scratch:	none

forget:
		xor	a
		ld	(p2cur),a
		ld	(p2fast),a
		ret

; make_tree - a Huffman tree: every symbol's code length and code.
;
;   maketree.c's make_tree, make_len and make_code. count_leaf, which
;   walks the tree recursively for each depth's number of symbols, is a
;   loop here: a node is always made after its two branches, so going
;   from the root down through the nodes, each one's depth is known
;   before its branches are reached. A depth past mt_max counts as
;   mt_max, as count_leaf counts one past 16: 16 for -lh5-, 15 or 7 for
;   deflate. make_len then makes the lengths fit, as it does for 16.
;   make_code, the last step, is also lens_code's.
;
; Input:	HL -> n, then pointers to freq, len and code: 4 words
;		freq: n counts, room for 2n-1
;		mt_max: the longest code, 16 at most
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
		push	hl		; C = its branches' depth,
		ld	de,(mt_depth)	;   mt_max at most
		add	hl,de
		ld	a,(hl)
		inc	a
		ld	c,a
		ld	a,(mt_max)
		cp	c
		jr	nc,make_tree.capped
		ld	c,a
make_tree.capped:
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
		ld	hl,0FFFFh	; make_len: cum, the sum of each
		ld	ix,leaf_num+2	;   count << (max - depth), less
		ld	a,(mt_max)	;   1 << max: the -1, shifted
		ld	b,a
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
		ex	de,hl		; too deep: leaf_num[max] -= cum
		call	leaf_max
		ld	a,(hl)
		sub	e
		ld	(hl),a
		inc	hl
		ld	a,(hl)
		sbc	a,d
		ld	(hl),a
make_tree.adjust:
		call	leaf_max	; the deepest depth under max
		dec	hl
		dec	hl
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
		ld	ix,(mt_code)	; the lengths, max down to 1,
		call	leaf_max	;   in the symbols' order
		ld	a,(mt_max)
		ld	c,a
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
make_code:
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

; leaf_max - where leaf_num[mt_max] is, for make_tree.
;
; Input:	mt_max
; Output:	HL -> it
; Modifies:	AF
;		BC
;		HL
; Scratch:	none

leaf_max:
		ld	a,(mt_max)
		add	a,a
		ld	l,a
		ld	h,0
		ld	bc,leaf_num
		add	hl,bc
		ret

; lens_code - a tree's codes from its lengths alone: make_tree's last
;   step, make_code, after each length's symbols are counted. For the
;   fixed codes, fewer than 256 of each length.
;
; Input:	HL -> n, then pointers to freq, len and code: 4 words
;		len: n lengths
; Output:	code: the n codes
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		IY
; Scratch:	none

lens_code:
		ld	de,mt_n
		ld	bc,8
		ldir
		ld	hl,leaf_num	; each length's symbols: none
		ld	bc,34
		call	zero
		ld	hl,(mt_len)
		ld	bc,(mt_n)
lens_code.count:
		ld	e,(hl)		; one more of its length
		inc	hl
		ld	d,0
		push	hl
		ld	hl,leaf_num
		add	hl,de
		add	hl,de
		inc	(hl)
		pop	hl
		dec	bc
		ld	a,b
		or	c
		jr	nz,lens_code.count
		jp	make_code

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
;
;   It works with addresses: dh_p -> heap[i]; heap[2i] is at twice
;   that less heap_at; dh_end -> heap[hs].
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

downheap:
		add	hl,hl		; dh_p -> heap[i]
		ld	de,(heap_at)
		add	hl,de
		ld	(dh_p),hl
		ld	e,(hl)		; k, and its count
		inc	hl
		ld	d,(hl)
		ld	(dh_k),de
		ex	de,hl
		call	freq_of
		ld	(dh_kf),hl
		ld	hl,(hs)		; dh_end -> heap[hs]
		add	hl,hl
		ld	de,(heap_at)
		add	hl,de
		ld	(dh_end),hl
		ld	hl,(dh_p)
downheap.loop:
		add	hl,hl		; HL -> heap[2i]: 2 dh_p - heap_at
		ld	de,(heap_at)
		or	a
		sbc	hl,de
		ex	de,hl		; past heap[hs]: done
		ld	hl,(dh_end)
		or	a
		sbc	hl,de
		ex	de,hl
		jr	c,downheap.done
		jr	z,downheap.one	; heap[hs]: no j+1
		ld	e,(hl)		; the lesser of j and j+1
		inc	hl
		ld	d,(hl)
		inc	hl
		ld	c,(hl)
		inc	hl
		ld	b,(hl)
		dec	hl
		dec	hl
		dec	hl
		push	hl
		ld	hl,(mt_freq)	; DE = j's count
		add	hl,de
		add	hl,de
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		ld	hl,(mt_freq)	; HL = j+1's
		add	hl,bc
		add	hl,bc
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		or	a
		sbc	hl,de
		pop	hl
		jr	nc,downheap.one
		inc	hl		; j+1 is used less
		inc	hl
downheap.one:
		ld	e,(hl)		; k used no more than j: k stays
		inc	hl
		ld	d,(hl)
		dec	hl
		push	hl
		ld	hl,(mt_freq)
		add	hl,de
		add	hl,de
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		ld	bc,(dh_kf)
		or	a
		sbc	hl,bc
		pop	hl
		jr	nc,downheap.done
		push	hl		; heap[i] = heap[j], i = j
		ld	hl,(dh_p)
		ld	(hl),e
		inc	hl
		ld	(hl),d
		pop	hl
		ld	(dh_p),hl
		jr	downheap.loop
downheap.done:
		ld	hl,(dh_p)	; heap[i] = k
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
;   For deflate, lh5w_start makes RL C an RR C, and the marker 80h:
;   then each bit goes in at the top and the marker falls out of bit 0,
;   so the first bit is the byte's lowest. A code still goes highest
;   bit first, as deflate wants; its numbers go through d_putbits.
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
p_put_rot:
		rl	c
		jr	nc,putcode.more
		call	put_byte	; C = 8 bits
p_put_mark:
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
		call	forget		; MSX-DOS had page 2
		call	map_tables
flush.done:
		pop	hl
		pop	de
		pop	bc
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
;			order of c_freq_at to buf_at
; t_n, p_n		pt's tree and p's, for make_tree: how many
;			symbols, their arrays
; patch_list		patch_small: where each byte is, and its value
;			for small packing; PATCH_COUNT of them
; weights		make_code: the step between codes of each length,
;			1 to 16 bits
; cl_order		deflate: the order the lengths' tree's lengths go in
; rep_16, rep_17, rep_18
;			cl_runs' repeats: the symbol, the fewest and the
;			most it says, its extra bits
;
offsets:	defw	C_FREQ,C_LEN,C_CODE,LEFT,RIGHT,DEPTH,HEAP
		defw	HEAD,BUFFER
t_n:		defw	T_SYMS,t_freq,pt_len,pt_code
p_n:		defw	P_SYMS,p_freq,pt_len,pt_code
PATCH_COUNT	equ	15
patch_list:	defw	p_copy_mask+1		; and 1Fh: an 8 KB ring
		defb	1Fh
		defw	p_copy_size+2		; ld hl,2000h: its size
		defb	20h
		defw	p_ring_mask+1
		defb	1Fh
		defw	p_cand_mask+1
		defb	1Fh
		defw	p_hash_1+1		; res 5,h: it wraps at A000h
		defb	0ACh
		defw	p_hash_2+1
		defb	0ACh
		defw	p_hash_3+1
		defb	0ACh
		defw	p_hash_4+1
		defb	0ACh
		defw	p_cmp_h+1
		defb	0ACh
		defw	p_cmp_d+1		; res 5,d
		defb	0AAh
		defw	p_prev_and_1+1		; prev: 4096 words, at A000h
		defb	1Fh
		defw	p_prev_or_1+1
		defb	0A0h
		defw	p_prev_and_2+1
		defb	1Fh
		defw	p_prev_or_2+1
		defb	0A0h
		defw	p_map_prev+1		; map_prev: the text's segment
		defb	1
weights:	defw	8000h,4000h,2000h,1000h,800h,400h,200h,100h
		defw	80h,40h,20h,10h,8,4,2,1
cl_order:	defb	16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15
rep_16:		defb	16,3,6,2
rep_17:		defb	17,3,10,3
rep_18:		defb	18,11,138,7
; hist_rows		pm2_code: for codes 0 to 7, a place's first and
;			the bits after the code
; copy_rows		pm2_code: for codes 23 to 27, a length's first,
;			less 3, the code and the bits after it
; mtf_groups		pm2_start: the list's groups, as PMARC2 starts
;			it: each one's first byte and how many
;
hist_rows:	defb	0,3,8,3,16,4,32,5,64,5,96,5,128,6,192,6
copy_rows:	defb	14,23,3,22,24,3,30,25,5,62,26,6,126,27,7
mtf_groups:	defb	20h,96,00h,32,0A0h,64,80h,32,0E0h,32

		dseg

; Variables:
;
; tables_ready		not 0 once the mapper memory is allocated
; text_fp, prev_fp, tables_fp
;			the text's and prev's segments, and the tables'
;			block: far pointers, in this order (map)
; fast			1 when all three are in the primary mapper
; small, win_size	1 for small packing (lh5w_start); how far back a
;			match may be: 8192, or 4096 small
; deflate		not 0 for a deflate member (lh5w_start)
; p2cur, p2fast		map: which of them page 2 shows, 0 for none;
;			whether p2seg may switch
; c_n, c_freq_at, c_len_at, c_code_at
;			c's tree, for make_tree: C_SYMS, and its arrays'
;			addresses in page 2
; left_at, right_at, depth_at, heap_at, head_at, buf_at
;			make_tree's arrays, head and the block, in page 2
; limit			the member's size, 4 bytes
; packed		the packed size so far, 4 bytes
; unpackable		1 once packed reached limit
; bitbuf		the bits waiting, and the marker above them
; outptr		where the next byte goes in outbuf
; src_at, src_n		lh5w_data: the bytes still to go into the ring
; cp_n			copy_in: how many
; top			the position after the last byte read
; big			1 once a round starts 8192 bytes or more in
; eof			1 in lh5w_end: no more bytes come
; done			1 once the last round has run
; r_first, r_ins, r_b	the next round: its first position, how many
;			are only put in the tables, whether B searches
; r_cnt, r_nq		this round: how many positions, and how many of
;			them 3 bytes from the end or more
; s_b, s_a		this round's searches' positions
; r_at, r_pos, r_left	round's prev step: the next old position, its
;			position, how many are left
; m_len, m_dist		the last search's match
; last_len, last_dist	the match A's decision weighs: B's or the last
;			round's A's
; pend, pend_c, pend_p	the symbol to send: 0 none, 1 a literal, 2 a
;			match; the symbol; the distance - 1
; n_b, n_a, list_b, list_a
;			the two searches' positions to try: how many,
;			and each
; qh			the round's hashes, doubled, then the positions
;			head held: MAX_MATCH words
; w_s, w_neg		walk: the search's position; the furthest back
;			it may go less it
; mx, best_len, best_d	search: the longest a match may be, the best so
;			far, its distance
; s_c, s_n, s_at, s_list, s_byte
;			search: the position being tried, how many are
;			left after it, where s's byte is, where the list
;			goes on, s's byte at the best length
; bufpos, cpos, mask	out_sym: where in the block, where the flags
;			byte is, the next flag bit
; o_kind, o_c, o_p	out_sym's symbol
; c_root, blk_size	send_block: c's root; the symbols left
; e_at, e_bit, e_flags	send_block: the next byte, the flag bits left,
;			the flags
; ep_k			encode_p: the distance's size
; mt_n, mt_freq, mt_len, mt_code
;			make_tree: the tree it is making
; mt_max		make_tree: the longest code, 16 for -lh5-
; mt_left, mt_right, mt_depth
;			left_at and right_at less 2n, depth_at less n:
;			indexed by node
; avail, hs, sort_at	the next node, the heap's size, where the next
;			symbol out goes in code
; mt_i, mt_j, mt_root	the two nodes taken out, and the new one
; dh_p, dh_end, dh_k, dh_kf
;			downheap: -> heap[i], -> heap[hs], k and k's
;			count
; leaf_num, first_code
;			how many symbols at each depth, and each length's
;			next code: 17 words each, 0 not used
; t_freq, p_freq	pt's counts, p's: 2n-1 words each
; pt_len, pt_code	pt's lengths and codes, or p's: T_SYMS each
; wp_special, wp_nbit, wp_n, wp_i
;			write_pt_len: special and nbit, how many, i
; wc_n, wc_at		write_c_len: how many are left, and where
; d_final		1 for the member's last block: deflate's BFINAL
; d_write		d_walk, cl_runs: 0 to count, 1 to write
; d_end			d_walk: where the block ends
; dt_n, dt_freq, dt_len, dt_code
;			d_desc: a tree's descriptor
; d_hdist, d_hclen	the distances' lengths sent, and the lengths'
;			tree's
; acc			d_compare: dynamic less fixed, 3 bytes
; cr_at, cr_n, cr_v	cl_runs: where it is, how many are left, the
;			length being repeated
; pm2_mode		not 0 for a -pm2- member (lh5w_start)
; pm2_left, pm2_syms	the unit: its bytes still to come, below 0 once
;			a match runs past it; its symbols
; pm2_unit		0 for the first unit, 1 for the second, 2 after
; pm2_need		not 0 when the code tree has ten codes or more:
;			offset trees
; ps_o, ps_st, ps_cnt	pm2_send: the output so far in the unit, the
;			stretch, the symbols left
; ps_m, ps_code, ps_xv, ps_xb, ps_n, ps_d, ps_oc, ps_ob
;			pm2_code: a match or not, the code, the bits after
;			it and how many, the bytes, the distance less 1,
;			its offset code and its bits
; pw_n, pw_min, pw_lb, pw_at
;			code_tree_out, off_tree_out: how many lengths, the
;			shortest, the bits each, where the next is
; mm_n, mm_at		mtf_match: the bytes left, the next one's position
; outbuf		the bytes for the archive: OUT_SIZE, in the buffers
;			segment
; mtf_order		-pm2-'s list, the head first, in the buffers segment
;
tables_ready:	defs	1
text_fp:	defs	4
prev_fp:	defs	4
tables_fp:	defs	4
fast:		defs	1
small:		defs	1
win_size:	defs	2
deflate:	defs	1
p2cur:		defs	1
p2fast:		defs	1
c_n:		defs	2
c_freq_at:	defs	2
c_len_at:	defs	2
c_code_at:	defs	2
left_at:	defs	2
right_at:	defs	2
depth_at:	defs	2
heap_at:	defs	2
head_at:	defs	2
buf_at:		defs	2
limit:		defs	4
packed:		defs	4
unpackable:	defs	1
bitbuf:		defs	1
outptr:		defs	2
src_at:		defs	2
src_n:		defs	2
cp_n:		defs	2
top:		defs	2
big:		defs	1
eof:		defs	1
done:		defs	1
r_first:	defs	2
r_ins:		defs	2
r_b:		defs	1
r_cnt:		defs	2
r_nq:		defs	2
s_b:		defs	2
s_a:		defs	2
m_len:		defs	2
m_dist:		defs	2
last_len:	defs	2
last_dist:	defs	2
pend:		defs	1
pend_c:		defs	2
pend_p:		defs	2
n_b:		defs	1
n_a:		defs	1
list_b:		defs	2*CHAIN
list_a:		defs	2*CHAIN
w_s:		defs	2
w_neg:		defs	2
mx:		defs	2
best_len:	defs	2
best_d:		defs	2
s_c:		defs	2
s_n:		defs	1
s_at:		defs	2
s_list:		defs	2
s_byte:		defs	1
bufpos:		defs	2
cpos:		defs	2
mask:		defs	1
o_kind:		defs	1
o_c:		defs	2
o_p:		defs	2
c_root:		defs	2
blk_size:	defs	2
e_at:		defs	2
e_bit:		defs	1
e_flags:	defs	1
ep_k:		defs	1
mt_n:		defs	2
mt_freq:	defs	2
mt_len:		defs	2
mt_code:	defs	2
mt_max:		defs	1
mt_left:	defs	2
mt_right:	defs	2
mt_depth:	defs	2
avail:		defs	2
hs:		defs	2
sort_at:	defs	2
mt_i:		defs	2
mt_j:		defs	2
mt_root:	defs	2
dh_p:		defs	2
dh_end:		defs	2
dh_k:		defs	2
dh_kf:		defs	2
leaf_num:	defs	34
first_code:	defs	34
t_freq:		defs	4*T_SYMS-2
p_freq:		defs	4*P_SYMS-2
pt_len:		defs	T_SYMS
pt_code:	defs	2*T_SYMS
wp_special:	defs	1
wp_nbit:	defs	1
wp_n:		defs	1
wp_i:		defs	1
wc_n:		defs	2
wc_at:		defs	2
d_final:	defs	1
d_write:	defs	1
d_end:		defs	2
dt_n:		defs	2
dt_freq:	defs	2
dt_len:		defs	2
dt_code:	defs	2
d_hdist:	defs	1
d_hclen:	defs	1
acc:		defs	3
cr_at:		defs	2
cr_n:		defs	2
cr_v:		defs	1
pm2_mode:	defs	1
pm2_left:	defs	2
pm2_syms:	defs	2
pm2_unit:	defs	1
pm2_need:	defs	1
ps_o:		defs	2
ps_st:		defs	1
ps_cnt:		defs	2
ps_m:		defs	1
ps_code:	defs	1
ps_xv:		defs	2
ps_xb:		defs	1
ps_n:		defs	2
ps_d:		defs	2
ps_oc:		defs	1
ps_ob:		defs	1
pw_n:		defs	1
pw_min:		defs	1
pw_lb:		defs	1
pw_at:		defs	2
mm_n:		defs	2
mm_at:		defs	2

		dseg	buffers
qh:		defs	2*MAX_MATCH
outbuf:		defs	OUT_SIZE
mtf_order:	defs	256

		end
