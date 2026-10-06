; unkago.as - UNKAGO, the decompressor. Phase 1: it lists LZH archives.
;
; It checks for MSX-DOS2 and the command line, and with /L lists the
; members of an LZH archive, one name per line. Extracting comes in
; Phase 2.

		include	common.inc	; common.as's routines, and print
		include	lzh.inc		; lzh.as: reading the archive

		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	errors.inc	; .IOPT, .NOPAR
		include	ascii.inc	; CHR_CR, CHR_LF

		cseg

; main - the entry point, where MSX-DOS2 starts the program.
;
;   A bad switch ends with .IOPT, and COMMAND2 prints its own message
;   for it: *** Invalid option. Otherwise /? prints the usage and /V
;   the banner alone; /? is tested first, so with both the usage wins.
;
;   Then the archive: the first word that is not a switch. With /L it
;   is listed. Without /L, extracting is what is asked for, and that
;   is Phase 2. With no archive named, /L ends with .NOPAR (*** Missing
;   parameter), and a line with neither prints the usage.
;
; Input:	the command line, at COMMAND_TAIL (common.as)
; Output:	does not return
; Modifies:	everything
; Scratch:	none

main:
		call	dos_version	; CY set = not MSX-DOS2
		jp	c,main.need_dos2	; too far for jr
		ld	hl,switch_letters
		call	find_bad_switch	; CY set = a switch it does not take
		jr	c,main.bad_switch
		ld	c,"?"
		call	switch_given
		jr	c,main.usage
		ld	c,"V"
		call	switch_given
		jr	nc,main.archive
		print	msg_banner	; /V: the banner, and nothing else
		dos	_TERM0

main.archive:
		call	first_argument	; A = 0: no archive named
		or	a
		jr	nz,main.named
		ld	c,"L"
		call	switch_given
		jr	nc,main.usage	; nothing on the line: the usage
		ld	b,.NOPAR	; COMMAND2: *** Missing parameter
		dos	_TERM

main.named:
		ld	de,archive_name	; B bytes from HL, then a 0
		ld	c,b
		ld	b,0
		ldir
		xor	a
		ld	(de),a
		ld	c,"L"
		call	switch_given
		jp	c,list_archive
		print	msg_no_extract
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

; list_archive - list the members of the archive named in
;   archive_name: one name per line.
;
;   lzh.as reads the headers; this prints each member's name with
;   printl, since a name may hold a "$", and decides what each result
;   means here. An archive in which not a single member could be read
;   is not an LZH archive, unless the first header is level 3: that is
;   one, and the level is what is reported.
;
; Input:	archive_name: the archive's name, zero-terminated
; Output:	does not return
; Modifies:	everything
; Scratch:	none

list_archive:
		ld	de,archive_name
		call	lzh_open
		or	a
		jr	nz,list_archive.dos_error	; not found, say
		ld	hl,0
		ld	(members),hl
list_archive.next:
		call	lzh_next_header
		or	a
		jr	nz,list_archive.stop
		printl	lzh_name,(lzh_name_length)
		print	msg_crlf
		ld	hl,(members)
		inc	hl
		ld	(members),hl
		call	lzh_skip_data
		or	a
		jr	z,list_archive.next
list_archive.stop:
		bit	7,a		; 80h and up: an MSX-DOS error
		jr	nz,list_archive.dos_error
		ld	c,a		; C = the result
		ld	hl,(members)
		ld	a,h
		or	l
		ld	a,c
		jr	nz,list_archive.some
		cp	LZH_LEVEL3
		jr	z,list_archive.level3
		ld	de,msg_not_lzh	; no member read at all
		jr	list_archive.say
list_archive.some:
		cp	LZH_END
		jr	z,list_archive.done
		ld	de,msg_damaged
		cp	LZH_DAMAGED
		jr	z,list_archive.say
		ld	de,msg_truncated
		cp	LZH_TRUNCATED
		jr	z,list_archive.say
list_archive.level3:
		ld	de,msg_level3
list_archive.say:
		dos	_STROUT
list_archive.done:
		dos	_TERM0
list_archive.dos_error:
		ld	b,a		; COMMAND2 prints its message
		dos	_TERM

; Constants for main:
;
; switch_letters	the switches UNKAGO takes, upper case, ending in 0
; msg_need_dos2		the refusal under MSX-DOS1
; msg_banner		the name, version, copyright and web address
; msg_usage		the rest of the usage, after the banner
; msg_crlf		the end of a line
; msg_no_extract		asked to extract, in Phase 1
; msg_not_lzh		no member could be read
; msg_damaged		a header is not valid
; msg_truncated		the file ends inside a member
; msg_level3		a level 3 header
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
msg_crlf:	defb	CHR_CR,CHR_LF,"$"
msg_no_extract:
		defb	"UNKAGO cannot extract yet: use /L to list."
		defb	CHR_CR,CHR_LF,"$"
msg_not_lzh:
		defb	"Not an LZH archive."
		defb	CHR_CR,CHR_LF,"$"
msg_damaged:
		defb	"The archive is damaged: a header is not valid."
		defb	CHR_CR,CHR_LF,"$"
msg_truncated:
		defb	"The archive ends in the middle of a member."
		defb	CHR_CR,CHR_LF,"$"
msg_level3:
		defb	"Header level 3: UNKAGO reads levels 0, 1 and 2."
		defb	CHR_CR,CHR_LF,"$"

		dseg

; Variables for main and list_archive:
;
; archive_name		the archive's name, from the command line, and a 0
; members		how many members have been listed
;
archive_name:	defs	128
members:	defs	2

		end	main
