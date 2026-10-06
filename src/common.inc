; common.inc - what a program's main module includes to use common.as:
; the names of its routines, MapperHeap's (alloc.inc), and the dos and
; print macros. A program that includes it links common.tro and
; alloc.tro.
;
; DO NOT WRAP THE MACRO IN IFNDEF. A macro has to be defined once per
; pass, and a guard keyed on a symbol fires only on the first; see
; msxdos.inc, which says the same of its "system" macro.

		extrn	dos_version
		extrn	find_bad_switch
		extrn	switch_given
		extrn	safe_p2restore

		include	alloc.inc	; MapperHeap: heapinit, p2restore...

; dos - call an MSX-DOS function, with page 2 handed back to MSX-DOS
; first.
;
;   EVERY MSX-DOS CALL GOES THROUGH dos, never through "system" alone.
;   MapperHeap's rule is that page 2 belongs to MSX-DOS whenever MSX-DOS
;   runs; safe_p2restore (common.as) gives it back and keeps AF, BC, DE
;   and HL, so the call's parameters can be loaded before dos as they
;   would be before "system". "system" is msxdos.inc's macro, so a
;   module that uses dos includes msxdos.inc as well.
;
; Input:	func = the MSX-DOS function number
;		the function's parameters, in their registers
; Output:	what the function returns
; Modifies:	what the function modifies, and C
; Scratch:	none

dos		macro	func
		call	safe_p2restore
		system	func
		endm

; print - write a "$"-terminated string to standard output.
;
;   Short for DE loaded with the string's address and _STROUT, through
;   dos. It works under MSX-DOS1 too, so it also prints the message that
;   says MSX-DOS2 is needed.
;
;   _STROUT stops at the first "$", so a string that may hold one - a
;   file name, say - cannot be printed this way. For those the macros
;   will be printz, for a zero-terminated string, and printl, for one
;   given by its length: added when something first needs them, with
;   the routines behind them.
;
; Input:	string = the address of the string, "$" terminated
; Output:	it is written to standard output
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

print		macro	string
		ld	de,string
		dos	_STROUT
		endm
