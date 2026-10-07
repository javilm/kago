; progress.as - the progress line of both tools: a member's line, then
; how far through the member's data the tool is, as a percentage (R9).
;
; The line is the tool's, given to progress_show: a word ("Extracting "
; in UNKAGO, "Adding " or "Replacing " in KAGO) and the path. Each
; redraw goes back to the left edge with a CR, prints the line again,
; then the number; a line too long for one row is shortened to its end
; while the number is shown, so that the CR stays on its row. On the
; screen only, and not with /Q (progress_init).

		public	progress_init
		public	progress_start
		public	progress_update
		public	progress_end
		public	progress_show

		include	common.inc	; dos, print, divide_by_c...
		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	ascii.inc	; CHR_CR
		include	workarea.inc	; LINLEN: the screen's width

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

; progress_show - a member's line, before its data: the tool's word
;   and the text after it, shortened to one row when the percentage
;   follows.
;
;   The word is "Adding ", "Replacing " or "Extracting ", ending in "$";
;   the text is the path, and UNKAGO's " as " name; both are kept for
;   the redraws. Without progress the line is printed whole. With it,
;   each redraw goes back to the left edge with a CR, which only goes
;   back along one row: a line that, with " NNN%" after it, does not
;   fit in LINLEN - 1 columns (the last one moves the cursor to the next
;   row) is shown as the word, "..." and as much of the text's end as
;   fits, so that the file's name stays in view. The cut moves on to a
;   whole character, never into a two-byte one (kanji_lead). A screen
;   too narrow even for that gets no percentage for the member. The line
;   is printed whole again by progress_end.
;
; Input:	HL -> the word, ending in "$"
;		DE -> the text
;		BC = the text's length
;		progress
; Output:	the line, printed
;		pl_word, pl_text, pl_length, pl_short, pl_from, pl_tail,
;		pct_on
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

progress_show:
		ld	(pl_word),hl
		ld	(pl_text),de
		ld	(pl_length),bc
		xor	a		; whole, unless it is too long
		ld	(pl_short),a
		ld	a,(progress)	; a percentage, if any is shown
		ld	(pct_on),a
		or	a
		jr	z,progress_show.print	; none: the line, whole
		ld	b,0		; B = the word's length
progress_show.count:
		ld	a,(hl)
		cp	"$"
		jr	z,progress_show.counted
		inc	hl
		inc	b
		jr	progress_show.count
progress_show.counted:
		ld	a,(LINLEN)	; C = the columns for the text:
		sub	6		;   all but the last, " NNN%"
		jr	c,progress_show.narrow	;   and the word
		sub	b
		jr	c,progress_show.narrow
		ld	c,a
		ld	hl,(pl_length)	; it fits: whole
		ld	a,h
		or	a
		jr	nz,progress_show.long
		ld	a,c
		cp	l
		jr	nc,progress_show.print
progress_show.long:
		ld	a,c		; room for its end, after "..."
		sub	3
		jr	c,progress_show.narrow
		jr	z,progress_show.narrow
		ld	e,a
		ld	d,0
		ld	hl,(pl_length)	; DE = the bytes to leave out, at
		or	a		;   least
		sbc	hl,de
		ex	de,hl
		ld	hl,(pl_text)	; BC = where the end shown starts,
		ld	bc,0		;   a character at a time
progress_show.walk:
		ld	a,c		; BC - DE: far enough?
		sub	e
		ld	a,b
		sbc	a,d
		jr	nc,progress_show.cut
		ld	a,(hl)
		inc	hl
		inc	bc
		call	kanji_lead	; CY: and its second byte
		jr	nc,progress_show.walk
		inc	hl
		inc	bc
		jr	progress_show.walk
progress_show.cut:
		ld	(pl_from),bc
		ld	hl,(pl_length)	; pl_tail = what is left, 0 at
		or	a		;   least
		sbc	hl,bc
		jr	nc,progress_show.tail
		ld	hl,0
progress_show.tail:
		ld	(pl_tail),hl
		ld	a,1
		ld	(pl_short),a
		jr	progress_show.print
progress_show.narrow:
		xor	a		; too narrow: no percentage
		ld	(pct_on),a
progress_show.print:
		jp	line_print

; progress_start - the first percentage, after the line's start.
;
;   One per cent of the member's data is worked out here, once: every
;   later update only adds. A member under 100 bytes has 0 bytes per per
;   cent, and goes straight to 100 at its first update.
;
;   The line is drawn again before the number, from the left edge: when
;   KAGO stores a file it could not pack, and starts again, the new
;   "   0%" goes over the old number, not after it.
;
; Input:	DE:HL = the member's size, in bytes
;		pct_on; the line, from progress_show
; Output:	the line and "   0%", when showing progress
;		pct, pct_step, pct_next, copied
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

progress_start:
		ld	a,(pct_on)
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
		call	progress_prefix	; the line again, from its start
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
; Scratch:	none

progress_update:
		ld	a,(pct_on)
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
;   A whole line is drawn again without the number, blanked, and drawn
;   once more, so that " OK" or " CRC error" follows the name. A
;   shortened one has its row blanked, and the line is printed whole,
;   on as many rows as it takes.
;
;   progress_prefix, its second half, is the line's start alone: back
;   to the left edge, then the line as progress_show showed it
;   (line_print).
;
; Input:	pct_on; the line, from progress_show
; Output:	the cursor just after the line
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

progress_end:
		ld	a,(pct_on)
		or	a
		ret	z
		ld	a,(pl_short)
		or	a
		jr	nz,progress_end.short
		call	progress_prefix
		print	msg_blank	; over the number
progress_prefix:
		print	msg_cr		; back to the line's start
		jr	line_print
progress_end.short:
		print	msg_cr		; the row blanked: LINLEN - 1
		ld	a,(LINLEN)	;   spaces
		dec	a
		ld	b,a
progress_end.blank:
		push	bc
		ld	e," "
		dos	_CONOUT
		pop	bc
		djnz	progress_end.blank
		print	msg_cr
		xor	a		; then the line, whole
		ld	(pl_short),a

; line_print - the line as progress_show keeps it: the word, then the
;   text whole, or "..." and its end.
;
; Input:	pl_word, pl_text, pl_length, pl_short, pl_from, pl_tail
; Output:	the line, printed
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

line_print:
		ld	de,(pl_word)
		dos	_STROUT
		ld	a,(pl_short)
		or	a
		jr	nz,line_print.short
		ld	de,(pl_text)	; whole
		ld	hl,(pl_length)
		jp	print_length
line_print.short:
		print	msg_dots
		ld	hl,(pl_text)	; its end
		ld	de,(pl_from)
		add	hl,de
		ex	de,hl
		ld	hl,(pl_tail)
		jp	print_length

; Constants for the routines above:
;
; msg_cr, msg_blank, pct_text
;			the progress line: back to its start, five
;			spaces over the number, the number; progress_number
;			writes its digits
; msg_dots		before a shortened line's end
;
msg_cr:		defb	CHR_CR,"$"
msg_blank:	defb	"     $"
pct_text:	defb	"   0%$"
msg_dots:	defb	"...$"

		dseg

; Variables for the routines above:
;
; progress		not 0 to show progress
; pct_on		not 0 to show it for this member: progress, and
;			a screen wide enough (progress_show)
; pl_word, pl_text, pl_length
;			the line: the word, ending in "$"; the text, and
;			its length
; pl_short		not 0 while the line is shortened
; pl_from, pl_tail	a shortened line: where its end shown starts in
;			the text, and its length
; pct			the percentage on the screen
; pct_step		the bytes in one per cent, 4 bytes
; pct_next		where the next per cent is reached, 4 bytes
; copied		the member's bytes copied so far, 4 bytes
;
progress:	defs	1
pct_on:		defs	1
pl_word:	defs	2
pl_text:	defs	2
pl_length:	defs	2
pl_short:	defs	1
pl_from:	defs	2
pl_tail:	defs	2
pct:		defs	1
pct_step:	defs	4
pct_next:	defs	4
copied:		defs	4
