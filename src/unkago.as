; unkago.as - UNKAGO, the decompressor. Phase 0: the skeleton.
;
; It checks for MSX-DOS2, checks the command line for a switch it does
; not take, and prints its usage or its banner. Nothing else yet.

		extrn	dos_version	; in common.as
		extrn	find_bad_switch	; in common.as
		extrn	switch_given	; in common.as
		extrn	print_dollar_string	; in common.as

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
		ld	de,msg_banner	; /V: the banner, and nothing else
		call	print_dollar_string
		system	_TERM0

main.usage:
		ld	de,msg_banner
		call	print_dollar_string
		ld	de,msg_usage
		call	print_dollar_string
		system	_TERM0

main.bad_switch:
		ld	b,.IOPT		; COMMAND2: *** Invalid option
		system	_TERM

main.need_dos2:
		ld	de,msg_need_dos2
		system	_STROUT		; the one way MSX-DOS1 can print
		system	_TERM0		; function 00h, in MSX-DOS1 too

; Constants for main:
;
; switch_letters	the switches UNKAGO takes, upper case, ending in 0
; msg_need_dos2		the refusal under MSX-DOS1, for _STROUT
; msg_banner		the name, version, copyright and web address
; msg_usage		the rest of the usage, after the banner
;
switch_letters:	defb	"DLQV?",0
msg_need_dos2:	defb	"ERROR: UNKAGO needs MSX-DOS2 or Nextor."
		defb	CHR_CR,CHR_LF,"$"
msg_banner:
		defb	"UNKAGO LZH/PMA/ZIP Decompressor v0.1.0"
		defb	CHR_CR,CHR_LF
		defb	"Copyright (C) 2026 Javier Lavandeira"
		defb	CHR_CR,CHR_LF
		defb	"https://github.com/javilm/kago"
		defb	CHR_CR,CHR_LF,"$"
msg_usage:
		defb	CHR_CR,CHR_LF
		defb	"Usage: UNKAGO [switches] archive [members...]"
		defb	CHR_CR,CHR_LF
		defb	CHR_CR,CHR_LF
		defb	"  /D:path  extract into path, made if missing:"
		defb	CHR_CR,CHR_LF
		defb	"           B:  B:\TEST  \TEMP  TEMP\FILES"
		defb	CHR_CR,CHR_LF
		defb	"  /L       list the archive, extract nothing"
		defb	CHR_CR,CHR_LF
		defb	"  /Q       quiet: no progress"
		defb	CHR_CR,CHR_LF
		defb	"  /V       the banner above, and nothing else"
		defb	CHR_CR,CHR_LF
		defb	"  /?       this text"
		defb	CHR_CR,CHR_LF
		defb	CHR_CR,CHR_LF
		defb	"Members may use * and ?. Naming a directory"
		defb	CHR_CR,CHR_LF
		defb	"extracts everything under it."
		defb	CHR_CR,CHR_LF
		defb	CHR_CR,CHR_LF,"$"

		end	main
