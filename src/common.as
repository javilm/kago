; common.as - what every program here needs: the MSX-DOS2 check,
; reading the switches on the command line, and safe_p2restore, which
; the dos macro (common.inc) calls before every MSX-DOS call. Printing
; is the print macro, in common.inc.
;
; Phase 0 keeps it to the minimum. A routine that only one tool needs
; stays in that tool's own module.

		public	dos_version
		public	find_bad_switch
		public	switch_given
		public	safe_p2restore

		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	ascii.inc	; CHR_SPACE, CHR_TAB
		include	alloc.inc	; p2restore, in MapperHeap

COMMAND_TAIL	equ	0081h		; the command line after the command
					;   name, ending in 0, put here by
					;   MSX-DOS2

		cseg

; dos_version - find out whether we are running under MSX-DOS2.
;
;   _DOSVER exists only from MSX-DOS2 onwards. Under MSX-DOS1 the call
;   does nothing at all, so B is loaded with 1 first and still holds 1
;   when the call returns. Nextor answers 2 or more, and is accepted.
;
; Input:	none
; Output:	CY set = not MSX-DOS2
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

dos_version:
		ld	b,1		; the value MSX-DOS1 leaves untouched
		call	safe_p2restore	; keeps B; see the dos macro
		system	_DOSVER		; MSX-DOS2 -> B = the major version
		ld	a,b
		cp	2
		ret	nc		; 2 or more: MSX-DOS2, carry clear
		scf			; otherwise carry set
		ret

; find_bad_switch - look for a switch the tool does not take.
;
;   Each switch's letter must be one of the tool's letters. Whatever
;   follows the letter in the same word - the ":LZH" of "/F:LZH" - is
;   not looked at: Phase 0 only tells a usage request from a bad
;   switch, and the phase that uses a switch checks its value.
;
; Input:	HL -> the tool's switch letters, upper case, ending in 0
; Output:	CY set = a bad switch was found
; Modifies:	AF
;		C
;		DE
; Scratch:	none

find_bad_switch:
		ld	de,COMMAND_TAIL
find_bad_switch.next:
		call	next_switch	; A = its letter, 0 = no more
		or	a
		ret	z		; no more switches: carry clear
		ld	c,a		; C = the letter to look for
		push	hl
find_bad_switch.search:
		ld	a,(hl)
		or	a
		jr	z,find_bad_switch.bad	; not one of the tool's letters
		cp	c
		jr	z,find_bad_switch.found
		inc	hl
		jr	find_bad_switch.search
find_bad_switch.bad:
		pop	hl
		scf
		ret
find_bad_switch.found:
		pop	hl
		jr	find_bad_switch.next

; switch_given - whether a switch was given on the command line.
;
;   Its value, if it has one, is not looked at.
;
; Input:	C = the switch's letter, upper case
; Output:	CY set = it was given
; Modifies:	AF
;		DE
; Scratch:	none

switch_given:
		ld	de,COMMAND_TAIL
switch_given.next:
		call	next_switch	; A = its letter, 0 = no more
		or	a
		ret	z		; no more switches: carry clear
		cp	c
		jr	nz,switch_given.next
		scf			; this is the one
		ret

; next_switch - the letter of the next switch on the command line.
;
;   A switch is a word that starts with "/". Words are separated by
;   spaces and tabs, as COMMAND2 separates them, so a "/" in the
;   middle of a word is not a switch. The letter is folded to upper
;   case, because COMMAND2 does not fold the command line unless
;   UPPER is ON.
;
;   A "/" with no letter after it gives "/" as the letter, which is
;   no tool's switch: it is a bad switch, and it cannot be mistaken
;   for the 0 that means no more switches.
;
; Input:	DE -> where to start, in the command line
; Output:	A = the letter, upper case
;		A = "/" for a "/" with no letter
;		A = 0 when there are no more switches
;		DE -> just after the switch's word
; Modifies:	AF
;		DE
; Scratch:	none

next_switch:
		ld	a,(de)
		or	a
		ret	z		; the end of the line: A = 0
		inc	de
		cp	CHR_SPACE
		jr	z,next_switch
		cp	CHR_TAB
		jr	z,next_switch
		cp	"/"
		jr	z,next_switch.slash
		call	skip_word	; a word that is not a switch
		jr	next_switch
next_switch.slash:
		ld	a,(de)		; the letter, if there is one
		or	a
		jr	z,next_switch.no_letter
		cp	CHR_SPACE
		jr	z,next_switch.no_letter
		cp	CHR_TAB
		jr	z,next_switch.no_letter
		inc	de
		cp	"a"		; fold a-z to A-Z
		jr	c,next_switch.folded
		cp	"z"+1
		jr	nc,next_switch.folded
		sub	"a"-"A"
next_switch.folded:
		push	af
		call	skip_word	; the rest of the word: its value
		pop	af
		ret
next_switch.no_letter:
		ld	a,"/"
		ret

; skip_word - step over the rest of a word on the command line.
;
; Input:	DE -> somewhere in the word
; Output:	DE -> the space, tab or 0 after it
; Modifies:	AF
;		DE
; Scratch:	none

skip_word:
		ld	a,(de)
		or	a
		ret	z
		cp	CHR_SPACE
		ret	z
		cp	CHR_TAB
		ret	z
		inc	de
		jr	skip_word

; safe_p2restore - p2restore, keeping the registers it would destroy.
;
;   MapperHeap's rule: page 2 belongs to MSX-DOS whenever MSX-DOS runs,
;   so p2restore (in alloc.as) comes before every MSX-DOS call. But
;   p2restore destroys AF, BC, DE and HL, and those are where an
;   MSX-DOS call takes its parameters, already loaded by the time the
;   call is made: B for _TERM, DE for _STROUT. So they are pushed
;   around it here, once, rather than at every call; the dos macro
;   (common.inc) calls this.
;
;   Until heapinit has run, p2restore returns at once, so this is safe
;   from the first instruction of a program, under MSX-DOS1 included.
;
;   IX and IY are not kept: p2restore's header does not name them, and
;   no MSX-DOS call made so far takes a parameter in them. To be checked
;   when the first one does.
;
; Input:	none
; Output:	page 2 belongs to MSX-DOS
; Modifies:	none
; Scratch:	none

safe_p2restore:
		push	af
		push	bc
		push	de
		push	hl
		call	p2restore
		pop	hl
		pop	de
		pop	bc
		pop	af
		ret

		end
