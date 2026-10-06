; progress.as - the progress line of both tools: a member's line, then
; how far through the member's data the tool is, as a percentage (R9).
;
; The line's start is the tool's: progress_line holds the address of a
; routine that prints it, "Extracting " and the path in UNKAGO,
; "Adding " and the path in KAGO. Each redraw goes back to the left edge
; and calls it, then prints the number. On the screen only, and not with
; /Q (progress_init).

		public	progress_init
		public	progress_start
		public	progress_update
		public	progress_end
		public	progress_line

		include	common.inc	; dos, print, divide_by_c...
		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	ascii.inc	; CHR_CR

		cseg

; progress_init - whether the tool shows its progress.
;
;   Only on the screen, as R9 asks, and not with /Q. _IOCTL says whether
;   standard output is a device (bit 7 of its status) or a file: with
;   output redirected into a file, each member gets its final line only,
;   so RESULTS.TXT does not change from one run to the next.
;
; Input:	the command line
; Output:	progress: not 0 to show it
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

progress_init:
		ld	c,"Q"
		call	switch_given	; CY set: /Q
		ld	a,0
		jr	c,progress_init.set
		ld	b,1		; standard output
		xor	a		; get its status
		dos	_IOCTL		; DE = the status
		or	a
		jr	nz,progress_init.set	; an error: A is not 0, no
		ld	a,e
		and	80h		; a device: the screen
progress_init.set:
		ld	(progress),a
		ret

; progress_start - the first percentage, after the line's start.
;
;   One per cent of the member's data is worked out here, once: every
;   later update only adds. A member under 100 bytes has 0 bytes per per
;   cent, and goes straight to 100 at its first update.
;
; Input:	DE:HL = the member's size, in bytes
;		progress
; Output:	"   0%" on the screen, when showing progress
;		pct, pct_step, pct_next, copied
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

progress_start:
		ld	a,(progress)
		or	a
		ret	z
		ld	c,100
		call	divide_by_c	; DE:HL = bytes per per cent
		ld	(pct_step),hl
		ld	(pct_step+2),de
		ld	(pct_next),hl	; reached at 1%
		ld	(pct_next+2),de
		ld	hl,0
		ld	(copied),hl
		ld	(copied+2),hl
		xor	a
		ld	(pct),a
		jr	progress_number

; progress_update - after each chunk: the percentage, redrawn only if it
;   has changed, so at most 100 times a member.
;
;   copied grows by the chunk; while it has reached pct_next, pct goes up
;   by one and pct_next by pct_step. 100 is as far as it goes.
;
;   progress_number, its second entry, prints the number alone, as
;   " NNN%".
;
; Input:	HL = the bytes just copied
;		progress_start's variables
; Output:	the line, redrawn when the number changes
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
;		and what progress_line's routine modifies
; Scratch:	none

progress_update:
		ld	a,(progress)
		or	a
		ret	z
		ex	de,hl		; DE = the bytes
		ld	hl,(copied)
		add	hl,de
		ld	(copied),hl
		ld	hl,(copied+2)
		ld	de,0
		adc	hl,de
		ld	(copied+2),hl
		ld	a,(pct)
		ld	b,a		; B = the number on the screen
progress_update.more:
		ld	a,(pct)
		cp	100
		jr	nc,progress_update.drawn	; as far as it goes
		ld	hl,(copied)	; copied - pct_next
		ld	de,(pct_next)
		or	a
		sbc	hl,de
		ld	hl,(copied+2)
		ld	de,(pct_next+2)
		sbc	hl,de
		jr	c,progress_update.drawn	; not there yet
		ld	hl,pct
		inc	(hl)
		ld	hl,(pct_next)	; pct_next + pct_step
		ld	de,(pct_step)
		add	hl,de
		ld	(pct_next),hl
		ld	hl,(pct_next+2)
		ld	de,(pct_step+2)
		adc	hl,de
		ld	(pct_next+2),hl
		jr	progress_update.more
progress_update.drawn:
		ld	a,(pct)
		cp	b
		ret	z		; the same: nothing to redraw
		call	progress_prefix
progress_number:
		ld	a,(pct)		; " NNN%"
		ld	l,a
		ld	h,0
		ld	de,0
		ld	b,3
		ld	ix,pct_text+4
		call	format_number
		print	pct_text
		ret

; progress_end - clear the percentage before the member's last word.
;
;   The line is drawn again without the number, blanked, and drawn once
;   more, so that " OK" or " CRC error" follows the name.
;
;   progress_prefix, its second half, is the line's start alone: back
;   to the left edge, then progress_line's routine.
;
; Input:	progress, progress_line
; Output:	the cursor just after the line's start
; Modifies:	AF
;		BC
;		DE
;		HL
;		and what progress_line's routine modifies
; Scratch:	none

progress_end:
		ld	a,(progress)
		or	a
		ret	z
		call	progress_prefix
		print	msg_blank	; over the number
progress_prefix:
		print	msg_cr		; back to the line's start
		ld	hl,(progress_line)
		jp	(hl)

; Constants for the routines above:
;
; msg_cr, msg_blank, pct_text
;			the progress line: back to its start, five
;			spaces over the number, the number; progress_number
;			writes its digits
;
msg_cr:		defb	CHR_CR,"$"
msg_blank:	defb	"     $"
pct_text:	defb	"   0%$"

		dseg

; Variables for the routines above:
;
; progress_line		the routine that prints the line's start, set by
;			the tool
; progress		not 0 to show progress
; pct			the percentage on the screen
; pct_step		the bytes in one per cent, 4 bytes
; pct_next		where the next per cent is reached, 4 bytes
; copied		the member's bytes copied so far, 4 bytes
;
progress_line:	defs	2
progress:	defs	1
pct:		defs	1
pct_step:	defs	4
pct_next:	defs	4
copied:		defs	4

		end
