; names.as - the MSX-DOS names of an archive's members: every part of
; every path, shortened the VFAT way when it does not fit 8.3.
;
; A part that fits (README.TXT, or readme.txt, which only needs upper
; case) is used as it is. One that does not is cut down to a basis, as
; MS-DOS cut VFAT's long names: spaces and leading periods dropped, the
; characters MSX-DOS cannot take (and VFAT's + , ; = [ ]) made "_", up
; to 8 characters before the last period and 3 after it. Then a tail,
; "~1", "~2" and on, the base cut to make room, the number the first that
; no other name in the same directory has:
;
;	longfilename.txt	LONGFI~1.TXT
;	my file.c		MYFILE~1.C
;	a+b.txt			A_B~1.TXT
;	a.b.c			AB~1.C
;	the tenth of ten	COLLI~10.TXT
;	collision??.txt
;
; The numbers come from the archive alone, not from the disk, so the
; same archive always gives the same names, whichever members are asked
; for: a second extraction finds LONGFI~1.TXT there and skips it, or
; replaces it with /O. The names that fit are kept first; the tails are
; given afterwards, in the order the parts first appear in the archive.
;
; The table: one entry per part, its directory (the entry of the part
; before, 0 for the top), in whole mapper segments taken with segalloc,
; up to NAME_SEGS of them. An entry is
;
;	+0	the directory's entry number, a word; 0FFFFh instead
;		means the segment ends here: on to the next
;	+2	the tail's number, a word: 0 for none, 0FFFFh not given yet
;	+4	the part's length, L
;	+5	the part, as stored (case kept)
;	+5+L	the basis: its base's length, the base (up to 8 bytes),
;		its extension's length, the extension (up to 3)
;
; Entries are found by walking the table from the start, comparing the
; directory and then the part, in any case. Nothing here calls MSX-DOS
; while a segment is mapped: lead_table, built once, says which bytes
; start a two-byte character, in place of kanji_lead.

NAMES_INCLUDED	equ	1		; names.inc: not our names as extrn

		public	names_init
		public	names_add
		public	names_assign
		public	names_out
		public	names_changed
		public	names_segs

		include	names.inc
		include	common.inc	; dos, kanji_lead, divide_by_c;
					;   MapperHeap's segalloc, deref
		include	lzh.inc		; lzh_name, lzh_name_length
		include	msxdos.inc	; BDOS, "system", _CHKCHR
		include	ascii.inc	; CHR_SPACE

NAME_SEGS	equ	8		; at most 128 KB of names
SEG_END		equ	3FFEh		; an entry and the 2-byte end
					;   mark must fit below this
SEPARATOR	equ	5Ch		; "\", between the parts of a path

		cseg

; names_init - an empty table, and lead_table.
;
; Input:	none
; Output:	names_count, names_segs, names_top = 0
;		lead_table: bit n of byte (n - 80h) / 8 set when n starts a
;		two-byte character, for n = 80h to 0FFh
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

names_init:
		ld	hl,0
		ld	(names_count),hl
		ld	(names_top),hl
		xor	a
		ld	(names_segs),a
		ld	hl,lead_table	; 16 bytes of 0, then each byte
		ld	b,16
names_init.clear:
		ld	(hl),a
		inc	hl
		djnz	names_init.clear
		ld	c,80h		; C = the byte asked about
names_init.byte:
		ld	a,c
		call	kanji_lead	; CY: a lead byte
		jr	nc,names_init.next
		call	lead_bit	; HL -> its byte, A = its bit
		or	(hl)
		ld	(hl),a
names_init.next:
		inc	c
		jr	nz,names_init.byte
		ret

; lead_bit - where a byte's bit is in lead_table.
;
; Input:	C = the byte, 80h to 0FFh
; Output:	HL -> lead_table's byte for it
;		A = its bit, as a mask
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

lead_bit:
		ld	a,c
		and	7Fh
		rrca			; (byte - 80h) / 8
		rrca
		rrca
		and	0Fh
		ld	e,a
		ld	d,0
		ld	hl,lead_table
		add	hl,de
		ld	a,c
		and	7
		ld	b,a
		ld	a,1
		inc	b
lead_bit.shift:
		dec	b
		ret	z
		add	a,a
		jr	lead_bit.shift

; is_lead - kanji_lead's answer, from lead_table: no MSX-DOS call.
;
; Input:	A = the byte
; Output:	CY set = it starts a two-byte character
; Modifies:	F
; Scratch:	none

is_lead:
		cp	80h
		ccf
		ret	nc		; ASCII: CY clear
		push	af
		push	bc
		push	de
		push	hl
		ld	c,a
		call	lead_bit
		and	(hl)		; NZ: a lead byte
		pop	hl
		pop	de
		pop	bc
		jr	z,is_lead.no
		pop	af
		scf
		ret
is_lead.no:
		pop	af
		or	a
		ret

; names_add - the parts of the member's path, into the table: each one
;   not there yet gets an entry, with its basis, and a tail to come if
;   the basis lost anything.
;
; Input:	lzh_name, lzh_name_length (lzh.as): the clean path
; Output:	CY set = no room: the table is full, or the mapper is
;		CY clear = all of them are in the table
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

names_add:
		call	path_start
names_add.part:
		call	part_next	; Z: no more
		ret	z		; CY clear, from part_next
		call	names_find	; Z: there already
		jr	z,names_add.found
		call	names_append	; CY: no room
		ret	c
names_add.found:
		ld	hl,(found_id)	; the next part's directory
		ld	(parent),hl
		jr	names_add.part

; path_start - get ready to take lzh_name a part at a time.
;
; Input:	lzh_name, lzh_name_length
; Output:	part_at, path_end; parent = 0, the top
; Modifies:	DE
;		HL
; Scratch:	none

path_start:
		ld	hl,0
		ld	(parent),hl
		ld	hl,lzh_name
		ld	(part_at),hl
		ld	de,(lzh_name_length)
		add	hl,de
		ld	(path_end),hl
		ret

; part_next - the next part of lzh_name: up to a "\" or the end.
;
; Input:	part_at, path_end
; Output:	Z set, CY clear = no more parts
;		Z clear = comp_ptr, comp_len: the part; part_at past it
; Modifies:	AF
;		B
;		HL
; Scratch:	none

part_next:
		push	de
		ld	hl,(part_at)
		ld	(comp_ptr),hl
		ld	b,0		; B = its length
		call	part_at_end
		jr	z,part_next.done	; Z: nothing left
part_next.scan:
		call	part_at_end
		jr	z,part_next.ended
		ld	a,(hl)
		cp	SEPARATOR
		jr	z,part_next.separator
		inc	hl
		inc	b
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	nc,part_next.scan
		call	part_at_end
		jr	z,part_next.ended
		inc	hl
		inc	b
		jr	part_next.scan
part_next.separator:
		inc	hl		; past it
part_next.ended:
		ld	(part_at),hl
		ld	a,b
		ld	(comp_len),a
		or	1		; Z clear: a part
part_next.done:
		pop	de		; CY clear either way
		ret

; part_at_end - whether HL is at path_end.
;
; Input:	HL, path_end
; Output:	Z set = it is; CY clear
; Modifies:	F
; Scratch:	none

part_at_end:
		push	de
		ld	de,(path_end)
		or	a
		sbc	hl,de
		add	hl,de		; Z from the SBC; CY clear
		pop	de
		ret

; names_find - the entry for comp_ptr, comp_len in the directory parent.
;
; Input:	parent, comp_ptr, comp_len
; Output:	Z set = found: found_id, and HL -> it, mapped
;		Z clear = not in the table
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

names_find:
		call	scan_start	; Z: an empty table
		jr	z,names_find.none
names_find.entry:
		call	scan_entry	; HL -> the entry
		push	hl
		ld	e,(hl)		; its directory
		inc	hl
		ld	d,(hl)
		ld	hl,(parent)
		or	a
		sbc	hl,de
		pop	hl
		jr	nz,names_find.next
		push	hl
		inc	hl		; its part
		inc	hl
		inc	hl
		inc	hl
		ld	a,(comp_len)
		cp	(hl)
		jr	nz,names_find.differ	; another length
		ld	b,a
		inc	hl
		ld	de,(comp_ptr)
names_find.byte:
		ld	a,(de)
		call	fold
		ld	c,a
		ld	a,(hl)
		call	fold
		cp	c
		jr	nz,names_find.differ
		inc	hl
		inc	de
		djnz	names_find.byte
		pop	hl		; found
		ld	de,(scan_id)
		ld	(found_id),de
		xor	a		; Z set
		ret
names_find.differ:
		pop	hl
names_find.next:
		call	scan_next	; Z: no more
		jr	nz,names_find.entry
names_find.none:
		or	1		; Z clear
		ret

; fold - a-z to A-Z, as unkago.as's fold_case.
;
; Input:	A
; Output:	A, upper case if it was a lower case letter
; Modifies:	F
; Scratch:	none

fold:
		cp	"a"
		ret	c
		cp	"z"+1
		ret	nc
		sub	"a"-"A"
		ret

; names_append - a new entry, last in the table, for comp_ptr, comp_len
;   in the directory parent.
;
;   A new segment is taken when the entry and the end mark would not
;   fit in the last one; the end mark goes where the entry would have.
;
; Input:	parent, comp_ptr, comp_len
; Output:	CY set = no room
;		CY clear = found_id: the new entry's number
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	entry_size

names_append:
		call	make_basis	; basis_*, from comp_ptr, comp_len
		ld	a,(comp_len)	; entry_size = 7 + L + base + extension
		ld	l,a
		ld	h,0
		ld	a,(basis_blen)
		ld	e,a
		ld	d,0
		add	hl,de
		ld	a,(basis_xlen)
		ld	e,a
		add	hl,de
		ld	e,7
		add	hl,de
		ld	(entry_size),hl
		ld	a,(names_segs)
		or	a
		jr	z,names_append.new	; no segment yet
		ld	de,(names_top)	; room in the last one?
		add	hl,de
		ld	de,SEG_END+1
		or	a
		sbc	hl,de
		jr	c,names_append.room
		call	map_top		; no: the end mark, then a new one
		ld	(hl),0FFh
		inc	hl
		ld	(hl),0FFh
names_append.new:
		ld	a,(names_segs)
		cp	NAME_SEGS
		scf
		ret	z		; the table is full: CY
		add	a,a		; its far pointer: names_fp + 4 * n
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,names_fp
		add	hl,de
		call	segalloc	; CY: no segment free
		ret	c
		ld	hl,names_segs
		inc	(hl)
		ld	hl,0
		ld	(names_top),hl
names_append.room:
		call	map_top		; HL -> where the entry goes
		ex	de,hl
		ld	hl,parent	; its directory
		ldi
		ldi
		ld	a,(basis_lossy)	; the tail: 0FFFFh to come, or 0
		or	a
		jr	z,names_append.tail
		ld	a,0FFh
names_append.tail:
		ld	(de),a
		inc	de
		ld	(de),a
		inc	de
		ld	a,(comp_len)	; the part
		ld	(de),a
		inc	de
		ld	c,a
		ld	b,0
		ld	hl,(comp_ptr)
		ldir
		ld	a,(basis_blen)	; the basis: length and base,
		inc	a
		ld	c,a
		ld	hl,basis_blen
		ldir
		ld	a,(basis_xlen)	;   length and extension
		inc	a
		ld	c,a
		ld	hl,basis_xlen
		ldir
		ld	hl,(names_top)
		ld	de,(entry_size)
		add	hl,de
		ld	(names_top),hl
		ld	hl,(names_count)
		inc	hl
		ld	(names_count),hl
		ld	(found_id),hl
		or	a		; CY clear
		ret

; map_top - the last segment in page 2.
;
; Input:	names_segs, names_top
; Output:	HL -> names_top in it
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

map_top:
		ld	a,(names_segs)
		dec	a
		call	map_seg
		ld	de,(names_top)
		add	hl,de
		ret

; map_seg - segment A of the table in page 2.
;
; Input:	A = the segment, 0 to NAME_SEGS - 1
; Output:	HL = 8000h, its start
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

map_seg:
		add	a,a		; names_fp + 4 * A
		add	a,a
		ld	e,a
		ld	d,0
		ld	hl,names_fp
		add	hl,de
		jp	deref		; HL = 8000h; BC kept

; make_basis - a part's basis, VFAT's way, and whether anything was
;   lost: a space, a leading period, a period before the last, a
;   character made "_", or more than 8 + 3.
;
;   The extension is what follows the last period; the base, what comes
;   before it. A two-byte character is taken whole, or not at all. A
;   base left empty becomes "_".
;
; Input:	comp_ptr, comp_len: the part, in low memory
; Output:	basis_blen, basis_base, basis_xlen, basis_ext
;		basis_lossy: not 0 if anything was lost
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	basis_dot

make_basis:
		xor	a
		ld	(basis_blen),a
		ld	(basis_xlen),a
		ld	(basis_lossy),a
		ld	hl,(comp_ptr)	; the last period: basis_dot, the end
		ld	a,(comp_len)	;   if there is none
		ld	e,a
		ld	d,0
		add	hl,de
		ld	(basis_dot),hl
		ld	hl,(comp_ptr)
		ld	b,a
make_basis.find:
		ld	a,(hl)
		cp	"."
		jr	nz,make_basis.char
		ld	(basis_dot),hl
make_basis.char:
		inc	hl
		call	kanji_lead	; CY: a pair, its second byte no period
		jr	nc,make_basis.counted
		dec	b
		jr	z,make_basis.found
		inc	hl
make_basis.counted:
		djnz	make_basis.find
make_basis.found:
		ld	hl,(comp_ptr)	; the leading periods and spaces go
		ld	a,(comp_len)
		ld	b,a
make_basis.lead:
		ld	a,(hl)
		cp	"."
		jr	z,make_basis.drop
		cp	CHR_SPACE
		jr	nz,make_basis.base
make_basis.drop:
		ld	a,1
		ld	(basis_lossy),a
		inc	hl
		djnz	make_basis.lead
		jr	make_basis.ends	; nothing but periods and spaces
make_basis.base:
		ld	ix,basis_blen	; the base, up to the last period
		ld	c,8
make_basis.base_char:
		push	hl
		ld	de,(basis_dot)
		or	a
		sbc	hl,de
		pop	hl
		jr	z,make_basis.dot	; at the last period
		call	basis_char	; one character, into the field at IX
		dec	b
		jr	nz,make_basis.base_char
		jr	make_basis.ends
make_basis.dot:
		inc	hl		; past it
		dec	b
		jr	z,make_basis.ends
		ld	ix,basis_xlen	; the extension
		ld	c,3
make_basis.ext_char:
		call	basis_char
		dec	b
		jr	nz,make_basis.ext_char
make_basis.ends:
		ld	a,(basis_blen)
		or	a
		ret	nz
		ld	a,"_"		; an empty base
		ld	(basis_base),a
		ld	a,1
		ld	(basis_blen),a
		ld	(basis_lossy),a
		ret

; basis_char - one character of the part into the basis: dropped (a
;   space, or a period in the base), made "_" or upper case (vfat_char),
;   or taken whole as a pair; dropped as well when the field is full.
;
; Input:	HL -> the character; B = what is left of the part, 1 or
;		more
;		IX -> the field's length, its bytes after it
;		C = the field's size, 8 or 3
; Output:	HL, B past it (B one less again for a pair's second byte);
;		basis_lossy set for anything lost
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

basis_char:
		ld	a,(hl)
		inc	hl
		cp	CHR_SPACE
		jr	z,basis_char.lost
		cp	"."
		jr	z,basis_char.lost
		call	kanji_lead
		jr	c,basis_char.pair
		call	vfat_char	; CY: made "_"
		jr	nc,basis_char.put
		push	af
		ld	a,1
		ld	(basis_lossy),a
		pop	af
basis_char.put:
		push	hl
		ld	e,a		; E = the character
		ld	a,(ix+0)	; the field's length so far
		cp	c
		jr	nc,basis_char.full
		inc	(ix+0)
		push	ix		; HL -> its next byte
		pop	hl
		inc	hl
		add	a,l
		ld	l,a
		adc	a,h
		sub	l
		ld	h,a
		ld	(hl),e
		pop	hl
		ret
basis_char.full:
		pop	hl
basis_char.lost:
		ld	a,1
		ld	(basis_lossy),a
		ret
basis_char.pair:
		ld	e,a		; E, D = the two bytes
		ld	a,b
		cp	2
		jr	c,basis_char.lost	; no second byte
		dec	b		; counted here
		ld	d,(hl)
		inc	hl
		ld	a,(ix+0)	; room for both?
		inc	a
		cp	c
		jr	nc,basis_char.lost
		push	hl
		dec	a		; HL -> the field's next byte
		push	ix
		pop	hl
		inc	hl
		add	a,l
		ld	l,a
		adc	a,h
		sub	l
		ld	h,a
		ld	(hl),e
		inc	hl
		ld	(hl),d
		inc	(ix+0)
		inc	(ix+0)
		pop	hl
		ret

; vfat_char - a character as it goes into a short name: upper case, as
;   MSX-DOS2's language has it, or "_" for one MSX-DOS2 does not take in
;   a name and for VFAT's + , ; = [ ].
;
; Input:	A = the character, not a space, period or lead byte
; Output:	A = what goes in
;		CY set = it was made "_"
; Modifies:	AF
; Scratch:	none

vfat_char:
		push	bc
		push	hl
		ld	hl,vfat_bad
		ld	bc,6
		cpir			; Z: one of them
		jr	z,vfat_char.bad
		push	de
		ld	e,a
		ld	d,0		; a file name's character, upper cased
		dos	_CHKCHR		; E: upper case; D bit 4: not valid
		ld	a,e
		bit	4,d
		pop	de
		jr	nz,vfat_char.bad
		pop	hl
		pop	bc
		or	a		; CY clear
		ret
vfat_char.bad:
		pop	hl
		pop	bc
		ld	a,"_"
		scf
		ret

; names_assign - the tails: each entry waiting for one, in table order,
;   gets the first number whose short name no other entry in the same
;   directory has. Entries still waiting do not count; those that fit,
;   and those already given a number, do.
;
; Input:	the table
; Output:	every entry's tail, in the table
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	cand_parent
;		cand_n
;		cand_text
;		cand_length
;		other_text
;		outer_state

names_assign:
		call	scan_start	; Z: an empty table
		ret	z
names_assign.entry:
		call	scan_entry	; waiting for a tail?
		inc	hl
		inc	hl
		ld	a,(hl)
		inc	hl
		and	(hl)
		inc	a
		jp	nz,names_assign.next	; too far for jr
		call	scan_entry
		ld	e,(hl)		; its directory
		inc	hl
		ld	d,(hl)
		ld	(cand_parent),de
		ld	hl,scan_state	; where it is, kept
		ld	de,outer_state
		ld	bc,5
		ldir
		ld	hl,1
		ld	(cand_n),hl
names_assign.try:
		ld	hl,outer_state	; back to it: its name with cand_n
		ld	de,scan_state
		ld	bc,5
		ldir
		call	scan_entry
		ld	de,(cand_n)
		ld	(short_n),de
		ld	de,cand_text
		call	short_with_n
		ld	hl,cand_text	; its length
		ex	de,hl
		or	a
		sbc	hl,de
		ld	a,l
		ld	(cand_length),a
		call	scan_start	; every name in its directory
names_assign.check:
		call	scan_entry
		ld	e,(hl)
		inc	hl
		ld	d,(hl)
		dec	hl
		push	hl
		ld	hl,(cand_parent)
		or	a
		sbc	hl,de
		pop	hl
		jr	nz,names_assign.other	; another directory
		push	hl
		inc	hl
		inc	hl
		ld	a,(hl)
		inc	hl
		and	(hl)
		pop	hl
		inc	a
		jr	z,names_assign.other	; still waiting: no name yet
		ld	de,other_text
		call	entry_short
		ld	hl,other_text	; the same length?
		ex	de,hl
		or	a
		sbc	hl,de
		ld	a,(cand_length)
		cp	l
		jr	nz,names_assign.other
		ld	b,a		; the same bytes?
		ld	hl,cand_text
		ld	de,other_text
names_assign.compare:
		ld	a,(de)
		cp	(hl)
		jr	nz,names_assign.other
		inc	hl
		inc	de
		djnz	names_assign.compare
		ld	hl,(cand_n)	; taken: the next number
		inc	hl
		ld	(cand_n),hl
		jr	names_assign.try
names_assign.other:
		call	scan_next	; Z: no more
		jr	nz,names_assign.check
		ld	hl,outer_state	; free: it is the entry's
		ld	de,scan_state
		ld	bc,5
		ldir
		call	scan_entry
		inc	hl
		inc	hl
		ld	de,(cand_n)
		ld	(hl),e
		inc	hl
		ld	(hl),d
names_assign.next:
		call	scan_next
		jp	nz,names_assign.entry	; too far for jr
		ret

; names_out - the member's path as MSX-DOS names, from the table.
;
;   A part that is not in the table, which names_add makes impossible,
;   is written as it is.
;
; Input:	DE -> where it goes
;		lzh_name, lzh_name_length (lzh.as)
; Output:	DE -> just after it; no 0 is written
;		names_changed: not 0 if a part got a tail
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

names_out:
		xor	a
		ld	(names_changed),a
		push	de
		call	path_start
		pop	de
names_out.part:
		call	part_next	; Z: no more
		ret	z
		push	de
		call	names_find	; Z: HL -> its entry
		pop	de
		jr	nz,names_out.raw
		ld	bc,(found_id)	; the next part's directory
		ld	(parent),bc
		call	entry_short
		ld	hl,(short_n)
		ld	a,h
		or	l
		jr	z,names_out.next
		ld	a,1
		ld	(names_changed),a
		jr	names_out.next
names_out.raw:
		ld	hl,(comp_ptr)
		ld	a,(comp_len)
		ld	c,a
		ld	b,0
		ldir
names_out.next:
		ld	hl,(part_at)	; a "\" unless it was the last
		call	part_at_end
		jr	z,names_out.part
		ld	a,SEPARATOR
		ld	(de),a
		inc	de
		jr	names_out.part

; entry_short - the short name an entry stands for: its basis, and its
;   tail if it has one, the base cut to make room for it.
;
;   short_with_n, its second entry, takes the tail's number from short_n
;   rather than from the entry: names_assign tries numbers with it.
;
; Input:	HL -> the entry, mapped
;		DE -> where the name goes
; Output:	DE -> just after it
;		short_n: the tail's number, 0 for none
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	short_blen
;		short_base
;		short_ext

entry_short:
		push	hl
		inc	hl		; its tail's number
		inc	hl
		ld	a,(hl)
		inc	hl
		ld	h,(hl)
		ld	l,a
		ld	(short_n),hl
		pop	hl
short_with_n:
		push	de
		ld	de,4		; past the directory and the number
		add	hl,de
		ld	e,(hl)		; past the part
		inc	hl
		add	hl,de
		ld	a,(hl)		; the basis
		ld	(short_blen),a
		inc	hl
		ld	(short_base),hl
		ld	e,a
		add	hl,de
		ld	(short_ext),hl	; -> the extension's length
		pop	de
		ld	hl,(short_n)
		ld	a,h
		or	l
		ld	a,(short_blen)	; C = the base's bytes to take: all
		ld	c,a
		jr	z,entry_short.base	; no tail
		push	de
		call	make_tail	; tail_start, tail_length
		pop	de
		ld	a,8		; B = the room left for the base
		ld	hl,tail_length
		sub	(hl)
		ld	b,a
		ld	hl,(short_base)	; C = what fits, whole characters
		ld	c,0
entry_short.cut:
		ld	a,(short_blen)
		cp	c
		jr	z,entry_short.base	; all of it
		ld	a,(hl)
		call	is_lead		; CY: two bytes
		ld	a,c
		inc	a
		jr	nc,entry_short.one
		inc	a
		inc	hl
entry_short.one:
		inc	hl
		cp	b
		jr	z,entry_short.fits
		jr	nc,entry_short.base	; over: not this one
entry_short.fits:
		ld	c,a
		jr	entry_short.cut
entry_short.base:
		ld	hl,(short_base)	; C bytes of the base
		ld	b,0
		ld	a,c
		or	a
		jr	z,entry_short.tail
		ldir
entry_short.tail:
		ld	hl,(short_n)
		ld	a,h
		or	l
		jr	z,entry_short.ext
		ld	hl,(tail_start)
		ld	a,(tail_length)
		ld	c,a
		ldir
entry_short.ext:
		ld	hl,(short_ext)	; a period and the extension, if any
		ld	a,(hl)
		or	a
		ret	z
		ld	c,a
		ld	a,"."
		ld	(de),a
		inc	de
		inc	hl
		ldir
		ret

; make_tail - "~N", in tail_text.
;
; Input:	HL = N, 1 or more
; Output:	tail_start -> "~", tail_length = its length, 2 to 6
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

make_tail:
		ld	de,0		; DE:HL = N
		ld	ix,tail_text+6
make_tail.digit:
		ld	c,10
		call	divide_by_c	; A = the last digit
		add	a,"0"
		dec	ix
		ld	(ix+0),a
		ld	a,h
		or	l
		jr	nz,make_tail.digit
		dec	ix
		ld	(ix+0),"~"
		ld	(tail_start),ix
		push	ix
		pop	de
		ld	hl,tail_text+6
		or	a
		sbc	hl,de
		ld	a,l
		ld	(tail_length),a
		ret

; scan_start, scan_entry, scan_next - a walk through the table, an
;   entry at a time; scan_state says where it is.
;
;   scan_start: Z set for an empty table; else at the first entry.
;   scan_entry: HL -> the entry, its segment mapped.
;   scan_next: Z set after the last; else at the next, the next
;   segment's first where the end mark is.
;
; Input:	scan_state; names_count, names_fp
; Output:	as above
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

scan_start:
		ld	hl,(names_count)
		ld	a,h
		or	l
		ret	z
		xor	a
		ld	(scan_seg),a
		ld	hl,0
		ld	(scan_off),hl
		inc	hl
		ld	(scan_id),hl
		inc	a		; Z clear
		ret

scan_entry:
		ld	a,(scan_seg)
		call	map_seg
		ld	de,(scan_off)
		add	hl,de
		ret

scan_next:
		ld	hl,(scan_id)
		ld	de,(names_count)
		or	a
		sbc	hl,de
		ret	z		; that was the last
		add	hl,de
		inc	hl
		ld	(scan_id),hl
		call	scan_entry	; the size of the one it was at
		push	hl
		ld	de,4
		add	hl,de
		ld	e,(hl)		; its part
		inc	hl
		add	hl,de
		ld	e,(hl)		; its base
		inc	hl
		add	hl,de
		ld	e,(hl)		; its extension
		inc	hl
		add	hl,de
		pop	de
		or	a
		sbc	hl,de		; HL = its size
		ld	de,(scan_off)
		add	hl,de
		ld	(scan_off),hl
		call	scan_entry	; the end mark?
		ld	a,(hl)
		inc	hl
		and	(hl)
		inc	a
		ret	nz		; no: on the next entry
		ld	hl,scan_seg	; yes: the next segment's first
		inc	(hl)
		ld	hl,0
		ld	(scan_off),hl
		or	1		; Z clear
		ret

; Constants for the routines above:
;
; vfat_bad		the characters VFAT does not keep in a short name
;
vfat_bad:	defb	"+,;=[]"

		dseg

; Variables for the routines above:
;
; names_fp		the table's segments, a far pointer each
; names_segs		how many it has
; names_top		where the next entry goes in the last one
; names_count		how many entries, numbered from 1
; names_changed		names_out: not 0 if a part got a tail
; lead_table		a bit for each byte 80h to 0FFh: it starts a pair
; scan_state		scan_seg, scan_off, scan_id: where a walk is:
;			the segment, the offset in it, the entry's number
; outer_state		names_assign: the entry waiting, while the walk
;			checks the others
; parent		the directory of the part looked for or added
; found_id		the entry found, or added
; part_at, path_end	part_next: the next part, and the path's end
; comp_ptr, comp_len	part_next: the part
; entry_size		names_append: the new entry's size
; basis_blen, basis_base, basis_xlen, basis_ext
;			make_basis: the basis, as it goes in an entry
; basis_lossy		make_basis: not 0 if anything was lost
; basis_dot		make_basis: the last period, or the part's end
; short_n		entry_short: the tail's number
; short_blen, short_base, short_ext
;			entry_short: the base's length, where it is,
;			and the extension's length's place
; tail_text, tail_start, tail_length
;			make_tail: "~N", where it starts, how long
; cand_parent, cand_n, cand_text, cand_length
;			names_assign: the entry's directory, the number
;			tried, and the name it gives
; other_text		names_assign: another entry's name
;
names_fp:	defs	4*NAME_SEGS
names_segs:	defs	1
names_top:	defs	2
names_count:	defs	2
names_changed:	defs	1
lead_table:	defs	16
scan_state:
scan_seg:	defs	1
scan_off:	defs	2
scan_id:	defs	2
outer_state:	defs	5
parent:	defs	2
found_id:	defs	2
part_at:	defs	2
path_end:	defs	2
comp_ptr:	defs	2
comp_len:	defs	1
entry_size:	defs	2
basis_blen:	defs	1
basis_base:	defs	8
basis_xlen:	defs	1
basis_ext:	defs	3
basis_lossy:	defs	1
basis_dot:	defs	2
short_n:	defs	2
short_blen:	defs	1
short_base:	defs	2
short_ext:	defs	2
tail_text:	defs	6
tail_start:	defs	2
tail_length:	defs	1
cand_parent:	defs	2
cand_n:	defs	2
cand_text:	defs	12
cand_length:	defs	1
other_text:	defs	12

		end
