; unkago.as - UNKAGO, the decompressor. Phase 1: it lists LZH archives.
;
; It checks for MSX-DOS2 and the command line, and with /L lists the
; members of an LZH archive: sizes, method, date and name, one line
; each, and the totals. Extracting comes in Phase 2.

		include	common.inc	; common.as's routines, and print
		include	lzh.inc		; lzh.as: reading the archive

		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	errors.inc	; .IOPT, .NOPAR
		include	ascii.inc	; CHR_CR, CHR_LF, CHR_SPACE

LINE_FIXED	equ	46		; a listing line before the name
TOTAL_FIXED	equ	29		; the totals line before the count

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
;   archive_name: a line for each, and the totals.
;
;   lzh.as reads the headers; this prints a heading before the first
;   member, a line for each (print_member), and the totals after the
;   last (print_totals), and decides what each result means here. A
;   listing cut short by a damaged or truncated archive ends with the
;   message instead of the totals. An archive in which not a single
;   member could be read is not an LZH archive, unless the first
;   header is level 3: that is one, and the level is what is reported.
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
		ld	(total_packed),hl
		ld	(total_packed+2),hl
		ld	(total_original),hl
		ld	(total_original+2),hl
list_archive.next:
		call	lzh_next_header
		or	a
		jr	nz,list_archive.stop
		ld	hl,(members)
		ld	a,h
		or	l
		jr	nz,list_archive.headed
		print	msg_list_head	; before the first member
list_archive.headed:
		call	print_member
		call	add_totals
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
		jr	z,list_archive.end
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
list_archive.end:
		call	print_totals
		jr	list_archive.done
list_archive.dos_error:
		ld	b,a		; COMMAND2 prints its message
		dos	_TERM

; print_member - one line of the listing: the member just read.
;
;   The line is built in line_text, whose separators are fixed: the
;   packed and original sizes, 10 digits wide; the method; the date; then
;   the name, printed after it with printl, since it may hold a "$".
;
; Input:	lzh_packed, lzh_original, lzh_method, lzh_time, lzh_level,
;		lzh_name, lzh_name_length (lzh.as)
; Output:	the line is printed
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

print_member:
		ld	hl,(lzh_packed)
		ld	de,(lzh_packed+2)
		ld	b,10
		ld	ix,line_text+10
		call	format_number
		ld	hl,(lzh_original)
		ld	de,(lzh_original+2)
		ld	b,10
		ld	ix,line_text+21
		call	format_number
		ld	hl,lzh_method
		ld	de,line_text+22
		ld	bc,5
		ldir
		call	format_date
		printl	line_text,LINE_FIXED
		printl	lzh_name,(lzh_name_length)
		print	msg_crlf
		ret

; format_date - the member's date and time, into line_text as
;   YYYY-MM-DD HH:MM.
;
;   Levels 0 and 1 store MS-DOS's two words: the time (hours in bits 15
;   to 11, minutes in 10 to 5) and then the date (years since 1980 in
;   bits 15 to 9, the month in 8 to 5, the day in 4 to 0). Level 2
;   stores seconds since 1970, UTC: divided by 60, 60 and 24 they give
;   the minute, the hour and the days since 1970, which are counted off
;   a year and then a month at a time. A year divisible by 4 is a leap
;   year, except 2100; level 2's 32 bits end in 2106.
;
; Input:	lzh_time, lzh_level (lzh.as)
; Output:	line_text: the date
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

format_date:
		ld	a,(lzh_level)
		cp	2
		jr	z,format_date.unix
		ld	hl,(lzh_time+2)	; MS-DOS: the date word
		ld	a,h
		srl	a		; A = years since 1980
		ld	e,a
		ld	d,0
		push	hl
		ld	hl,1980
		add	hl,de
		ld	(date_year),hl
		pop	hl
		ld	a,l
		and	1Fh
		ld	(date_day),a
		ld	b,5		; the month: bits 8 to 5
format_date.month_bits:
		srl	h
		rr	l
		djnz	format_date.month_bits
		ld	a,l
		and	0Fh
		ld	(date_month),a
		ld	hl,(lzh_time)	; the time word
		ld	a,h
		rrca
		rrca
		rrca
		and	1Fh
		ld	(date_hour),a
		ld	b,5		; the minute: bits 10 to 5
format_date.minute_bits:
		srl	h
		rr	l
		djnz	format_date.minute_bits
		ld	a,l
		and	3Fh
		ld	(date_minute),a
		jr	format_date.text
format_date.unix:
		ld	hl,(lzh_time)	; level 2: seconds since 1970
		ld	de,(lzh_time+2)
		ld	c,60
		call	divide_by_c	; DE:HL = minutes
		ld	c,60
		call	divide_by_c	; DE:HL = hours, A = minute
		ld	(date_minute),a
		ld	c,24
		call	divide_by_c	; HL = days, A = hour
		ld	(date_hour),a
		ld	bc,1970		; BC = the year
format_date.year:
		ld	de,365		; DE = its length
		ld	a,c
		and	3
		jr	nz,format_date.length
		ld	a,b		; divisible by 4: a leap year,
		cp	HIGH 2100	;   but for 2100
		jr	nz,format_date.leap
		ld	a,c
		cp	LOW 2100
		jr	z,format_date.length
format_date.leap:
		inc	de
format_date.length:
		or	a
		sbc	hl,de
		jr	c,format_date.in_year
		inc	bc
		jr	format_date.year
format_date.in_year:
		add	hl,de		; HL = the day of the year, from 0
		ld	(date_year),bc
		ld	a,e
		ld	(date_leap),a	; 6Eh, the low byte of 366: leap
		ld	ix,month_lengths
		ld	b,1		; B = the month
format_date.month:
		ld	e,(ix+0)
		ld	d,0
		ld	a,b
		cp	2
		jr	nz,format_date.month_length
		ld	a,(date_leap)
		cp	LOW 366
		jr	nz,format_date.month_length
		inc	de		; February of a leap year
format_date.month_length:
		or	a
		sbc	hl,de
		jr	c,format_date.in_month
		inc	ix
		inc	b
		jr	format_date.month
format_date.in_month:
		add	hl,de
		ld	a,b
		ld	(date_month),a
		ld	a,l
		inc	a
		ld	(date_day),a
format_date.text:
		ld	hl,(date_year)
		ld	b,4
		ld	ix,line_text+33
		call	format_two
		ld	a,(date_month)
		ld	ix,line_text+36
		call	format_byte
		ld	a,(date_day)
		ld	ix,line_text+39
		call	format_byte
		ld	a,(date_hour)
		ld	ix,line_text+42
		call	format_byte
		ld	a,(date_minute)
		ld	ix,line_text+45
		jr	format_byte

; format_byte - A as two digits, zero in front, ending before IX.
;
;   format_two, below, is the same for HL and B digits.
;
; Input:	A = the number, 0 to 99
;		IX -> just after the two digits
; Output:	the digits
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

format_byte:
		ld	l,a
		ld	h,0
		ld	b,2
format_two:
		ld	de,0
		jp	format_padded

; add_totals - add the member just read to the totals.
;
; Input:	lzh_packed, lzh_original (lzh.as)
; Output:	total_packed, total_original
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

add_totals:
		ld	hl,(total_packed)
		ld	de,(lzh_packed)
		add	hl,de
		ld	(total_packed),hl
		ld	hl,(total_packed+2)
		ld	de,(lzh_packed+2)
		adc	hl,de
		ld	(total_packed+2),hl
		ld	hl,(total_original)
		ld	de,(lzh_original)
		add	hl,de
		ld	(total_original),hl
		ld	hl,(total_original+2)
		ld	de,(lzh_original+2)
		adc	hl,de
		ld	(total_original+2),hl
		ret

; print_totals - the listing's last two lines: the rule, then the
;   totals and how many files.
;
;   The count is written 5 wide and printed from its first digit, then
;   " file" or " files".
;
; Input:	total_packed, total_original, members
; Output:	they are printed
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

print_totals:
		print	msg_list_foot
		ld	hl,(total_packed)
		ld	de,(total_packed+2)
		ld	b,10
		ld	ix,total_text+10
		call	format_number
		ld	hl,(total_original)
		ld	de,(total_original+2)
		ld	b,10
		ld	ix,total_text+21
		call	format_number
		printl	total_text,TOTAL_FIXED
		ld	hl,(members)
		ld	de,0
		ld	b,5
		ld	ix,count_text+5
		call	format_number
		ld	hl,count_text	; from the first digit
print_totals.skip:
		ld	a,(hl)
		cp	CHR_SPACE
		jr	nz,print_totals.count
		inc	hl
		jr	print_totals.skip
print_totals.count:
		ex	de,hl		; DE -> it; HL = how many digits
		ld	hl,count_text+5
		or	a
		sbc	hl,de
		call	print_length
		ld	hl,(members)
		dec	hl
		ld	a,h
		or	l
		ld	de,msg_files
		jr	nz,print_totals.word
		ld	de,msg_file	; exactly 1
print_totals.word:
		dos	_STROUT
		ret

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
; msg_list_head		the listing's heading
; msg_list_foot		the rule above the totals
; msg_file		after a count of 1
; msg_files		after any other count
; month_lengths		the days in each month, February at 28
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
msg_list_head:
		defb	"    Packed   Original Method Date"
		defb	"             Name"
		defb	CHR_CR,CHR_LF
		defb	"---------- ---------- ------ "
		defb	"---------------- ------------"
		defb	CHR_CR,CHR_LF,"$"
msg_list_foot:
		defb	"---------- ---------- ------ "
		defb	"                 ------------"
		defb	CHR_CR,CHR_LF,"$"
msg_file:	defb	" file",CHR_CR,CHR_LF,"$"
msg_files:	defb	" files",CHR_CR,CHR_LF,"$"
month_lengths:	defb	31,28,31,30,31,30,31,31,30,31,30,31

		dseg

; Variables for main and list_archive:
;
; archive_name		the archive's name, from the command line, and a 0
; members		how many members have been listed
; total_packed		the packed sizes added up, 4 bytes
; total_original		the original sizes added up, 4 bytes
; line_text		a listing line, before the name; print_member
;			writes the numbers, the method and the date
;			between its fixed separators
; total_text		the totals line, before the count
; count_text		the count of files, 5 wide
; date_year		format_date: the year, a word
; date_month, date_day, date_hour, date_minute, date_leap
;			format_date: the rest, a byte each; date_leap is
;			the low byte of the year's length
;
archive_name:	defs	128
members:	defs	2
total_packed:	defs	4
total_original:	defs	4
line_text:	defb	"0000000000 0000000000 -lh0-  "
		defb	"0000-00-00 00:00 "
total_text:	defb	"                             "
count_text:	defs	5
date_year:	defs	2
date_month:	defs	1
date_day:	defs	1
date_hour:	defs	1
date_minute:	defs	1
date_leap:	defs	1

		end	main
