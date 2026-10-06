; kago.as - KAGO, the compressor. Phase 0: the skeleton.
;
; It checks for MSX-DOS2, checks the command line for a switch it does
; not take, and prints its usage or its banner. Nothing else yet.

		include	common.inc	; common.as's routines, and print

		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	errors.inc	; .IOPT
		include	ascii.inc	; CHR_CR, CHR_LF

		cseg

; main - the entry point, where MSX-DOS2 starts the program.
;
;   A bad switch ends with .IOPT, and COMMAND2 prints its own message
;   for it: *** Invalid option. Otherwise /? prints the usage, /V the
;   banner alone, and anything else the usage, which in Phase 0 is all
;   there is to do. /? is tested before /V, so with both the usage
;   wins: it contains the banner anyway.
;
; Input:	the command line, at COMMAND_TAIL (common.as)
; Output:	does not return
; Modifies:	everything
; Scratch:	none

main:
		call	dos_version	; CY set = not MSX-DOS2
		jr	c,main.need_dos2
		ld	hl,switch_letters
		call	find_bad_switch	; CY set = a switch it does not take
		jr	c,main.bad_switch
		ld	c,"?"
		call	switch_given
		jr	c,main.usage
		ld	c,"V"
		call	switch_given
		jr	nc,main.usage
		print	msg_banner	; /V: the banner, and nothing else
		dos	_TERM0

main.usage:
		print	msg_banner
		print	msg_usage
		dos	_TERM0

main.bad_switch:
		ld	b,.IOPT		; COMMAND2: *** Invalid option
		dos	_TERM

main.need_dos2:
		print	msg_need_dos2	; _STROUT: MSX-DOS1 has it too
		dos	_TERM0		; function 00h, in MSX-DOS1 too

; Constants for main:
;
; switch_letters	the switches KAGO takes, upper case, ending in 0
; msg_need_dos2		the refusal under MSX-DOS1
; msg_banner		the name, version, copyright and web address
; msg_usage		the rest of the usage, after the banner
;
switch_letters:	defb	"FYQV?",0
msg_need_dos2:	defb	"ERROR: KAGO needs MSX-DOS2 or Nextor."
		defb	CHR_CR,CHR_LF,"$"
msg_banner:
		defb	"KAGO LZH/PMA/ZIP Compressor v0.1.0"
		defb	CHR_CR,CHR_LF
		defb	"Copyright (C) 2026 Javier Lavandeira"
		defb	CHR_CR,CHR_LF
		defb	"https://github.com/javilm/kago"
		defb	CHR_CR,CHR_LF,"$"
msg_usage:
		defb	CHR_CR,CHR_LF
		defb	"Usage: KAGO [switches] archive files..."
		defb	CHR_CR,CHR_LF
		defb	CHR_CR,CHR_LF
		defb	"  /F:fmt  the format: LZH, PMA or ZIP. Without it,"
		defb	CHR_CR,CHR_LF
		defb	"          the archive name's extension decides"
		defb	CHR_CR,CHR_LF
		defb	"  /Y      proceed without asking when memory is short"
		defb	CHR_CR,CHR_LF
		defb	"  /Q      quiet: no progress"
		defb	CHR_CR,CHR_LF
		defb	"  /V      the banner above, and nothing else"
		defb	CHR_CR,CHR_LF
		defb	"  /?      this text"
		defb	CHR_CR,CHR_LF
		defb	CHR_CR,CHR_LF,"$"

		end	main
