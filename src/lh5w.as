; lh5w.as - the -lh5- encoder: KAGO's compression, as LHA 2.x writes it.
;
; lh5.as, in UNKAGO, reads what this writes. A member's data is a series
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
; mkkago.py's model (note 026) is this file, step for step.

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
WINDOW		equ	8192		; how far back a match may be
MAX_MATCH	equ	256		; how long
THRESHOLD	equ	3		; and how short
CHAIN		equ	32		; a search's steps at most
HASH_SIZE	equ	2048		; head's entries: an 11-bit hash
BUF_SIZE	equ	4096		; a block's symbols, as LHA keeps them
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
BUFFER		equ	11231		; BUF_SIZE bytes: the block's symbols
TABLES_SIZE	equ	15327

		cseg

; lh5w_start - get ready to pack a member.
;
;   The first time, the tables' block and the text's and prev's segments
;   are allocated, and kept for every member after. The packed size
;   starts at 0, the bit buffer, the block and every count empty, and
;   head holds no position. The first round puts position 0 in the
;   table and searches at 1, after a match of 2 (no match).
;
; Input:	DE:HL = the member's size: packing stops when the packed
;		size reaches it
; Output:	CY set = no mapper memory
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
		inc	a		; the bit buffer: empty, its
		ld	(bitbuf),a	;   marker bit alone
		ld	hl,outbuf
		ld	(outptr),hl
		ld	hl,p_freq
		ld	bc,2*P_SYMS
		call	zero
		ld	a,(tables_ready)
		or	a
		jr	nz,lh5w_start.ready
		fpalloc	tables_fp,TABLES_SIZE	; CY set: out of memory
		ret	c
		ld	hl,text_fp
		call	segalloc
		ret	c
		ld	hl,prev_fp
		call	segalloc
		ret	c
		ld	a,1
		ld	(tables_ready),a
		ld	hl,C_SYMS	; c's tree: C_SYMS symbols, and
		ld	(c_n),hl	;   where its arrays are
		call	map_tables	; DE -> the block, in page 2
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
		ld	(src_at),de
		ld	(src_n),bc
lh5w_data.more:
		ld	hl,(src_n)
		ld	a,h
		or	l
		jr	z,lh5w_data.done
		ld	hl,(top)	; room: WINDOW - (top - r_first + 1)
		ld	de,(r_first)
		or	a
		sbc	hl,de
		inc	hl
		ex	de,hl
		ld	hl,WINDOW
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
;   sent, and the last byte filled with 0 bits, as LHA does (7 of them,
;   which complete it if any bit is waiting).
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
		ld	a,1
		ld	(eof),a
		call	rounds
		ld	a,(unpackable)
		or	a
		jr	nz,lh5w_end.done
		call	map_tables
		call	out_pending
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
		and	3Fh
		ld	d,a
		ld	e,l
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
		ld	hl,(r_first)
		call	ring_addr
		ld	de,qh
		ld	bc,(r_nq)
round.hash:
		ld	a,b
		or	c
		jr	z,round.hashed
		push	bc
		call	hash3		; BC = twice the hash
		ex	de,hl
		ld	(hl),c
		inc	hl
		ld	(hl),b
		inc	hl
		ex	de,hl
		inc	hl
		res	6,h
		pop	bc
		dec	bc
		jr	round.hash
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
		ld	hl,qh
		ld	de,(r_first)
		ld	bc,(r_nq)
round.prev:
		ld	a,b
		or	c
		jr	z,round.compare
		push	bc
		ld	c,(hl)		; BC = the position head held
		inc	hl
		ld	b,(hl)
		inc	hl
		push	hl
		ld	h,d		; prev[pos] = it
		ld	l,e
		add	hl,hl
		ld	a,h
		and	3Fh
		or	80h
		ld	h,a
		ld	(hl),c
		inc	hl
		ld	(hl),b
		ld	hl,(s_a)	; A's position: its chain
		or	a
		sbc	hl,de
		jr	z,round.walk_a
		ld	a,(r_b)		; B's, if there is a B
		or	a
		jr	z,round.prev_next
		ld	hl,(s_b)
		or	a
		sbc	hl,de
		jr	nz,round.prev_next
		ld	ix,list_b
		call	round.walk
		ld	(n_b),a
		jr	round.prev_next
round.walk_a:
		ld	ix,list_a
		call	round.walk
		ld	(n_a),a
round.prev_next:
		pop	hl
		pop	bc
		dec	bc
		inc	de
		jr	round.prev
round.walk:
		push	de		; walk's chain from BC, for DE
		ld	(w_s),de
		ld	d,b
		ld	e,c
		call	walk
		pop	de
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
		ld	l,(hl)
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
		ld	a,(big)		; from WINDOW on, the window is full
		or	a
		ret	nz
		ld	de,WINDOW
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
		and	3Fh
		or	80h
		ld	h,a
		ret

; hash3 - a position's hash, from its next three bytes.
;
;   ((b0 << 8) ^ (b1 << 4) ^ b2) & 7FFh, doubled: head's offset.
;
; Input:	HL -> the position's byte, with the text mapped
; Output:	BC = twice the hash
; Modifies:	AF
;		BC
; Scratch:	none

hash3:
		push	hl
		ld	a,(hl)		; b0's low 3 bits: 8 to 10
		and	7
		ld	b,a
		inc	hl
		res	6,h
		ld	a,(hl)		; b1, its nibbles swapped
		rrca
		rrca
		rrca
		rrca
		ld	c,a
		and	0Fh		; its high one: 8 to 11
		xor	b
		and	7
		ld	b,a
		ld	a,c		; its low one: 4 to 7
		and	0F0h
		ld	c,a
		inc	hl
		res	6,h
		ld	a,(hl)		; b2: 0 to 7
		xor	c
		ld	c,a
		sla	c
		rl	b
		pop	hl
		ret

; walk - a search's chain: the distances to compare.
;
;   From the position head held, back along prev, while each is further
;   back than the one before, no further than the window allows (8192,
;   or the member's start), and CHAIN at most. The list starts after a
;   0 word: the distance before the first.
;
; Input:	DE = the position head held
;		w_s = the search's position
;		IX -> the list
;		big; prev mapped
; Output:	A = how many distances in the list
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

walk:
		ld	hl,WINDOW	; the furthest: 8192, or the start
		ld	a,(big)
		or	a
		jr	nz,walk.limit
		ld	hl,(w_s)
		ld	bc,WINDOW
		or	a
		sbc	hl,bc
		ld	hl,WINDOW
		jr	nc,walk.limit
		ld	hl,(w_s)
walk.limit:
		ld	(wlim),hl
		ld	a,CHAIN
		ld	(w_n),a
		ld	bc,(w_s)	; BC = s
walk.next:
		ld	h,b		; d = s - c
		ld	l,c
		or	a
		sbc	hl,de
		ld	a,(ix-2)	; no further back than the last:
		sub	l		;   stop
		ld	a,(ix-1)
		sbc	a,h
		jr	nc,walk.done
		ld	a,(wlim)	; past the limit: stop
		sub	l
		ld	a,(wlim+1)
		sbc	a,h
		jr	c,walk.done
		ld	(ix+0),l
		ld	(ix+1),h
		inc	ix
		inc	ix
		ld	hl,w_n
		dec	(hl)
		jr	z,walk.done
		ex	de,hl		; c = prev[c]
		add	hl,hl
		ld	a,h
		and	3Fh
		or	80h
		ld	h,a
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		jr	walk.next
walk.done:
		ld	a,(w_n)		; CHAIN less those not taken
		ld	b,a
		ld	a,CHAIN
		sub	b
		ret

; search - the longest match at a position, from its list.
;
;   It must be longer than min (2 at least) and is at most 256, or what
;   is left of the member. Each distance's byte at the best length so
;   far is looked at first, as LHA does: a longer match must have it.
;   A match as long as it can be ends the search.
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
;		IX
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
		ld	a,b
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
		ld	a,(s_n)		; none to try
		or	a
		ret	z
		ld	hl,(w_s)	; s's byte
		call	ring_addr
		ld	(s_at),hl
search.aim:
		ld	hl,(best_len)	; as long as it can be already
		ld	de,(mx)
		or	a
		sbc	hl,de
		ret	nc
		ld	hl,(w_s)	; s's byte at the best length
		ld	de,(best_len)
		add	hl,de
		call	ring_addr
		ld	(s_at_l),hl
		ld	a,(hl)
		ld	(s_byte),a
search.next:
		ld	e,(ix+0)	; the next distance
		ld	d,(ix+1)
		inc	ix
		inc	ix
		ld	hl,(s_at_l)	; its byte at the best length
		or	a
		sbc	hl,de
		ld	a,h
		and	3Fh
		or	80h
		ld	h,a
		ld	a,(s_byte)
		cp	(hl)
		jr	nz,search.skip
		ld	(s_d),de	; the same: compare from the start
		ld	hl,(s_at)
		or	a
		sbc	hl,de
		ld	a,h
		and	3Fh
		or	80h
		ld	d,a
		ld	e,l
		ld	hl,(s_at)
		ld	a,(mx)		; 256 is 0: 256 times
		ld	b,a
search.byte:
		ld	a,(de)
		cp	(hl)
		jr	nz,search.differ
		inc	de
		res	6,d
		inc	hl
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
		jr	c,search.skip
		jr	z,search.skip
		ld	(best_len),hl
		ld	de,(s_d)
		ld	(best_d),de
		ld	hl,s_n
		dec	(hl)
		jp	nz,search.aim	; too far for jr
		ret
search.skip:
		ld	hl,s_n
		dec	(hl)
		jr	nz,search.next
		ret

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
;   sent first (send_block). A literal is its byte; a match is its
;   symbol's low byte (length - 3), then its distance - 1, high byte
;   first, its flag bit set. Each symbol's count, and each distance's
;   size's, go up by one.
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
		ret

; bitlen - how many bits a number takes: 0 for 0.
;
; Input:	HL = the number
; Output:	A = its bits
; Modifies:	AF
;		B
;		HL
; Scratch:	none

bitlen:
		ld	b,0
bitlen.next:
		ld	a,h
		or	l
		ld	a,b
		ret	z
		srl	h
		rr	l
		inc	b
		jr	bitlen.next

; send_block - the block: its tables, then its symbols' codes.
;
;   huf.c's send_block: c's tree; the block's size (its root's count);
;   pt's tree and lengths, and c's lengths (or c's one symbol); p's tree
;   and lengths (or its one symbol); then each symbol's code, a match's
;   distance after it (encode_p). The counts go back to 0.
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
		ld	a,(e_bit)	; every 8: a flags byte
		or	a
		jr	nz,send_block.shift
		ld	hl,(e_at)
		ld	a,(hl)
		inc	hl
		ld	(e_at),hl
		ld	(e_flags),a
		ld	a,7
		ld	(e_bit),a
		jr	send_block.flag
send_block.shift:
		dec	a
		ld	(e_bit),a
		ld	a,(e_flags)
		add	a,a
		ld	(e_flags),a
send_block.flag:
		ld	a,(e_flags)
		add	a,a		; bit 7: a match
		ld	hl,(e_at)
		ld	e,(hl)
		inc	hl
		ld	d,0
		jr	nc,send_block.literal
		inc	d		; its symbol: 256 + the byte
		ld	b,(hl)		; its distance - 1
		inc	hl
		ld	c,(hl)
		inc	hl
		ld	(e_at),hl
		push	bc
		call	c_code_out
		pop	hl
		call	encode_p
		jr	send_block.symbol
send_block.literal:
		ld	(e_at),hl
		call	c_code_out
		jr	send_block.symbol
send_block.sent:
		ld	hl,(c_freq_at)	; the counts: 0
		ld	bc,2*C_SYMS
		call	zero
		ld	hl,p_freq
		ld	bc,2*P_SYMS
		jp	zero

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

; map_text, map_prev - the text's segment, or prev's, in page 2.
;
; Input:	text_fp, prev_fp
; Output:	mapped, at 8000h
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

map_text:
		derefp	text_fp
		ret
map_prev:
		derefp	prev_fp
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
;			order of c_freq_at to buf_at
; t_n, p_n		pt's tree and p's, for make_tree: how many
;			symbols, their arrays
; weights		make_code: the step between codes of each length,
;			1 to 16 bits
;
offsets:	defw	C_FREQ,C_LEN,C_CODE,LEFT,RIGHT,DEPTH,HEAP
		defw	HEAD,BUFFER
t_n:		defw	T_SYMS,t_freq,pt_len,pt_code
p_n:		defw	P_SYMS,p_freq,pt_len,pt_code
weights:	defw	8000h,4000h,2000h,1000h,800h,400h,200h,100h
		defw	80h,40h,20h,10h,8,4,2,1

		dseg

; Variables:
;
; tables_ready		not 0 once the mapper memory is allocated
; tables_fp, text_fp, prev_fp
;			the tables' block, and the text's and prev's
;			segments: far pointers
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
;			the two searches' distances: how many, and each
; qh			the round's hashes, doubled, then the positions
;			head held: MAX_MATCH words
; w_s, w_c, wlim, d_last
;			walk: the search's position, the chain's, the
;			furthest back, the last distance
; mx, best_len, best_d, s_d, s_q
;			search: the longest a match may be, the best so
;			far, and the distance and position being tried
; bufpos, cpos, mask	out_sym: where in the block, where the flags
;			byte is, the next flag bit
; o_kind, o_c, o_p	out_sym's symbol
; c_root, blk_size	send_block: c's root; the symbols left
; e_at, e_bit, e_flags	send_block: the next byte, the flag bits left,
;			the flags
; ep_k			encode_p: the distance's size
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
; t_freq, p_freq	pt's counts, p's: 2n-1 words each
; pt_len, pt_code	pt's lengths and codes, or p's: T_SYMS each
; wp_special, wp_nbit, wp_n, wp_i
;			write_pt_len: special and nbit, how many, i
; wc_n, wc_at		write_c_len: how many are left, and where
; outbuf		the bytes for the archive: OUT_SIZE, in the buffers
;			segment
;
tables_ready:	defs	1
tables_fp:	defs	4
text_fp:	defs	4
prev_fp:	defs	4
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
		defs	2		; a 0 word before each list
list_b:		defs	2*CHAIN
		defs	2
list_a:		defs	2*CHAIN
w_s:		defs	2
w_n:		defs	1
wlim:		defs	2
mx:		defs	2
best_len:	defs	2
best_d:		defs	2
s_d:		defs	2
s_n:		defs	1
s_at:		defs	2
s_at_l:		defs	2
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
p_freq:		defs	4*P_SYMS-2
pt_len:		defs	T_SYMS
pt_code:	defs	2*T_SYMS
wp_special:	defs	1
wp_nbit:	defs	1
wp_n:		defs	1
wp_i:		defs	1
wc_n:		defs	2
wc_at:		defs	2

		dseg	buffers
qh:		defs	2*MAX_MATCH
outbuf:		defs	OUT_SIZE

		end
