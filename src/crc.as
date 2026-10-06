; crc.as - the CRC-16 of LZH archives and the CRC-32 of ZIP archives:
; the members' checksums.
;
; A CRC (cyclic redundancy check) is a 16-bit number computed from every
; byte of a file such that almost any change to the file changes it: a
; flipped bit, a lost byte, two bytes swapped. LZH stores each member's
; CRC in its header; extracting computes it again over what was written
; and compares the two.
;
; This is the CRC-16 that LHA and ARC use: polynomial 8005h, bits taken
; lowest first (so the polynomial appears reversed, A001h), starting from
; 0. lhasa's lib/crc16.c (reference/lhasa) has the same table, written
; out. Here the table is built at run time, which takes 512 bytes of
; memory but none of the program file.
;
; ZIP's CRC-32 is the same idea, 32 bits wide: polynomial 04C11DB7h,
; reversed EDB88320h, starting from 0FFFFFFFFh, the result complemented.
; Its table is four of 256 bytes, one for each byte of an entry. An
; archive is one format or the other, so the two tables share one KB:
; crc_init builds CRC-16's in its first half, crc32_init CRC-32's in all
; of it.

		public	crc_init
		public	crc_update
		public	crc_value
		public	crc32_init
		public	crc32_update
		public	crc32_value

CRC_POLY	equ	0A001h		; 8005h, bits reversed

		cseg

; crc_init - build the table and start the CRC at 0.
;
;   Entry n of the table is the CRC of the single byte n: shifted right
;   8 times, the polynomial XORed in each time a 1 falls out. It is kept
;   as two tables of 256 bytes, low bytes and high bytes.
;
; Input:	none
; Output:	crc_low, crc_high: the table
;		crc_value = 0
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

crc_init:
		ld	c,0		; C = n, 0 to 255
crc_init.entry:
		ld	e,c
		ld	d,0		; DE = n
		ld	b,8
crc_init.bit:
		srl	d
		rr	e		; a bit out: carry
		jr	nc,crc_init.zero
		ld	a,d
		xor	HIGH CRC_POLY
		ld	d,a
		ld	a,e
		xor	LOW CRC_POLY
		ld	e,a
crc_init.zero:
		djnz	crc_init.bit	; B = 0 after it
		ld	hl,crc_low
		add	hl,bc
		ld	(hl),e
		ld	hl,crc_high
		add	hl,bc
		ld	(hl),d
		inc	c
		jr	nz,crc_init.entry
		ld	hl,0
		ld	(crc_value),hl
		ret

; crc_update - add BC bytes at DE to crc_value.
;
;   For each byte: the table entry for the CRC's low byte XOR the byte,
;   XORed with the CRC shifted 8 bits right, is the new CRC.
;
; Input:	DE -> the bytes
;		BC = how many
;		crc_value: the CRC so far
; Output:	crc_value: updated
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

crc_update:
		ld	a,b
		or	c
		ret	z		; nothing to add
		ld	hl,(crc_value)	; HL = the CRC
crc_update.byte:
		ld	a,(de)
		inc	de
		xor	l		; A = the entry's number
		push	de
		push	bc
		ld	c,a
		ld	b,0
		ex	de,hl		; DE = the CRC
		ld	hl,crc_low
		add	hl,bc
		ld	a,(hl)
		xor	d		; the new low byte
		ld	e,a
		ld	hl,crc_high
		add	hl,bc
		ld	d,(hl)		; the new high byte
		ex	de,hl		; HL = the CRC
		pop	bc
		pop	de
		dec	bc
		ld	a,b
		or	c
		jr	nz,crc_update.byte
		ld	(crc_value),hl
		ret

; crc32_init - build CRC-32's table, over CRC-16's, and start the CRC.
;
;   Entry n is the CRC-32 of the single byte n, as crc_init's: shifted
;   right 8 times, the polynomial XORed in each time a 1 falls out. Its
;   four bytes go in crc_table's four 256-byte parts, lowest first, so
;   that the parts are 256 bytes apart: INC H steps from one to the next.
;
; Input:	none
; Output:	crc_table: the table
;		crc32_value = 0FFFFFFFFh
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

crc32_init:
		ld	c,0		; C = n, 0 to 255
crc32_init.entry:
		ld	e,c		; H:L:D:E = n
		ld	d,0
		ld	hl,0
		ld	b,8
crc32_init.bit:
		srl	h
		rr	l
		rr	d
		rr	e		; a bit out: carry
		jr	nc,crc32_init.zero
		ld	a,h		; the polynomial, EDB88320h
		xor	0EDh
		ld	h,a
		ld	a,l
		xor	0B8h
		ld	l,a
		ld	a,d
		xor	83h
		ld	d,a
		ld	a,e
		xor	20h
		ld	e,a
crc32_init.zero:
		djnz	crc32_init.bit	; B = 0 after it
		push	hl
		ld	hl,crc_table	; entry n of each part
		add	hl,bc
		ld	(hl),e
		inc	h
		ld	(hl),d
		pop	de		; D, E = the two high bytes
		inc	h
		ld	(hl),e
		inc	h
		ld	(hl),d
		inc	c
		jr	nz,crc32_init.entry
		ld	hl,0FFFFh
		ld	(crc32_value),hl
		ld	(crc32_value+2),hl
		ret

; crc32_update - add BC bytes at DE to crc32_value.
;
;   For each byte: entry (the CRC's low byte XOR the byte), XORed with
;   the CRC shifted 8 bits right, is the new CRC.
;
; Input:	DE -> the bytes
;		BC = how many
;		crc32_value: the CRC so far
; Output:	crc32_value: updated
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

crc32_update:
		ld	a,b
		or	c
		ret	z		; nothing to add
crc32_update.byte:
		push	bc
		ld	a,(de)
		inc	de
		push	de
		ld	hl,crc32_value
		xor	(hl)		; the entry's number
		ld	c,a
		ld	b,0
		ld	hl,crc_table
		add	hl,bc		; HL -> its lowest byte
		ld	a,(crc32_value+1)	; the new lowest byte
		xor	(hl)
		ld	e,a
		inc	h
		ld	a,(crc32_value+2)
		xor	(hl)
		ld	d,a
		inc	h
		ld	a,(crc32_value+3)
		xor	(hl)
		ld	c,a
		inc	h
		ld	b,(hl)		; the new highest byte
		ld	(crc32_value),de
		ld	(crc32_value+2),bc
		pop	de
		pop	bc
		dec	bc
		ld	a,b
		or	c
		jr	nz,crc32_update.byte
		ret

		dseg	buffers

; Variables for crc_init and crc_update, in the buffers segment, which
; holds memory the program file does not need to carry:
;
; crc_value		the CRC-16 so far, a word
; crc32_value		the CRC-32 so far, 4 bytes
; crc_low, crc_high	CRC-16's table: entry n's low byte, its high byte
; crc_table		CRC-32's table: four 256-byte parts, the entries'
;			bytes, lowest first; over crc_low and crc_high
;
crc_value:	defs	2
crc32_value:	defs	4
crc_table:
crc_low:	defs	256
crc_high:	defs	256
		defs	512		; CRC-32's last two parts

		end
