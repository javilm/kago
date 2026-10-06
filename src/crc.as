; crc.as - the CRC-16 of LZH archives: the members' checksum.
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

		public	crc_init
		public	crc_update
		public	crc_value

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

		dseg	buffers

; Variables for crc_init and crc_update, in the buffers segment, which
; holds memory the program file does not need to carry:
;
; crc_value		the CRC so far, a word
; crc_low, crc_high	the table: entry n's low byte, its high byte
;
crc_value:	defs	2
crc_low:	defs	256
crc_high:	defs	256

		end
