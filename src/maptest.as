; maptest.as - MAPTEST, the mapper test of Phase 0: one MapperHeap
; block is allocated, written, read back after a remap, and freed.
;
; tests.bat runs it. It prints one line per step, ending in OK or in
; what went wrong, and nothing that depends on the machine - not how
; much memory there is - so that its output can be frozen in
; tests\expected.txt.

		include	common.inc	; dos_version, dos, print, MapperHeap
		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	ascii.inc	; CHR_CR, CHR_LF
		include	farptr.inc	; fpalloc, derefp, fpfree

BLOCK_SIZE	equ	16372		; the largest block MapperHeap gives:
					;   a whole 16 KB segment, less its
					;   fences and size words

		cseg

; main - the entry point, where MSX-DOS2 starts the program.
;
;   Each step prints its line and goes on; the first that fails prints
;   what went wrong instead, and the program ends there.
;
;   The print between writing and reading is part of the test: print
;   goes through dos, which hands page 2 back to MSX-DOS, so the second
;   derefp has to map the block's segment in again. The read-back
;   therefore checks the remap, not just the first mapping.
;
; Input:	none
; Output:	does not return
; Modifies:	everything
; Scratch:	none

main:
		call	dos_version	; CY set = not MSX-DOS2
		jp	c,main.need_dos2	; too far for jr
		print	msg_title
		call	heapinit	; CY set = no mapper support
		ld	de,msg_no_mapper
		jr	c,main.fail
		print	msg_heapinit_ok
		fpalloc	block_fp,BLOCK_SIZE	; CY set = out of memory
		ld	de,msg_no_memory
		jr	c,main.fail
		print	msg_halloc_ok
		derefp	block_fp	; HL -> the block, in page 2
		call	fill_block
		print	msg_written	; page 2 goes back to MSX-DOS
		derefp	block_fp	; so this maps the segment again
		call	check_block	; CY set = a byte differs
		ld	de,msg_mismatch
		jr	c,main.fail
		print	msg_read_ok
		fpfree	block_fp
		ld	hl,(hblocks)	; blocks handed out, not given back
		ld	a,h
		or	l
		ld	de,msg_leak
		jr	nz,main.fail
		print	msg_hfree_ok
		dos	_TERM0

main.need_dos2:
		ld	de,msg_need_dos2	; _STROUT: MSX-DOS1 has it too
main.fail:
		dos	_STROUT		; DE -> what went wrong
		dos	_TERM0

; fill_block - fill the block with check_block's pattern.
;
;   Byte n of the block gets the low byte of n XOR its high byte, so
;   the pattern differs from one 256-byte page of the block to the
;   next: a page mapped in the wrong place does not read back right.
;
; Input:	HL -> the block, in page 2
; Output:	the block is filled
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

fill_block:
		ld	bc,BLOCK_SIZE	; BC = bytes still to fill
		ld	de,0		; DE = n, the byte's place in the block
fill_block.loop:
		ld	a,e
		xor	d
		ld	(hl),a
		inc	hl
		inc	de
		dec	bc
		ld	a,b
		or	c
		jr	nz,fill_block.loop
		ret

; check_block - check that the block holds fill_block's pattern.
;
; Input:	HL -> the block, in page 2
; Output:	CY set = a byte differs
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

check_block:
		ld	bc,BLOCK_SIZE	; BC = bytes still to check
		ld	de,0		; DE = n, the byte's place in the block
check_block.loop:
		ld	a,e
		xor	d
		cp	(hl)
		scf			; SCF leaves Z alone
		ret	nz		; differs: carry set
		inc	hl
		inc	de
		dec	bc
		ld	a,b
		or	c		; OR clears the carry
		jr	nz,check_block.loop
		ret			; all equal: carry clear

; Constants for main:
;
; msg_need_dos2		the refusal under MSX-DOS1
; msg_title		what the test is
; msg_heapinit_ok	heapinit worked
; msg_no_mapper		heapinit failed
; msg_halloc_ok		the block was allocated
; msg_no_memory		it was not
; msg_written		the pattern is written
; msg_read_ok		it read back right
; msg_mismatch		it did not
; msg_hfree_ok		the block was freed, none left
; msg_leak		a block is still handed out
;
msg_need_dos2:
		defb	"ERROR: MAPTEST needs MSX-DOS2 or Nextor."
		defb	CHR_CR,CHR_LF,"$"
msg_title:
		defb	"MAPTEST - a mapper block: allocate, write, read, free"
		defb	CHR_CR,CHR_LF,"$"
msg_heapinit_ok:
		defb	"heapinit: OK"
		defb	CHR_CR,CHR_LF,"$"
msg_no_mapper:
		defb	"heapinit: no mapper support"
		defb	CHR_CR,CHR_LF,"$"
msg_halloc_ok:
		defb	"halloc, 16372 bytes: OK"
		defb	CHR_CR,CHR_LF,"$"
msg_no_memory:
		defb	"halloc, 16372 bytes: out of mapper memory"
		defb	CHR_CR,CHR_LF,"$"
msg_written:
		defb	"written: 16372 bytes"
		defb	CHR_CR,CHR_LF,"$"
msg_read_ok:
		defb	"read back after a remap: OK"
		defb	CHR_CR,CHR_LF,"$"
msg_mismatch:
		defb	"read back after a remap: a byte differs"
		defb	CHR_CR,CHR_LF,"$"
msg_hfree_ok:
		defb	"hfree: OK, no blocks left"
		defb	CHR_CR,CHR_LF,"$"
msg_leak:
		defb	"hfree: blocks are left over"
		defb	CHR_CR,CHR_LF,"$"

		dseg

; Variables for main:
;
; block_fp		the block's far pointer, from fpalloc
;
block_fp:	defs	4

		end	main
