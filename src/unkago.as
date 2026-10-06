; unkago.as - UNKAGO, the decompressor. Phase 2: it lists LZH archives,
; and extracts their stored members.
;
; It checks for MSX-DOS2 and the command line. With /L it lists the
; members of an LZH archive: sizes, method, date and name, one line
; each, and the totals. Without it, it extracts the -lh0- members into
; the current directory, checking each one's CRC-16.

		include	common.inc	; common.as's routines, and print
		include	lzh.inc		; lzh.as: reading the archive
		include	crc.inc		; crc.as: the CRC-16

		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	errors.inc	; .IOPT, .NOPAR, .FILEX, .DKFUL
		include	ascii.inc	; CHR_CR, CHR_LF, CHR_SPACE

LINE_FIXED	equ	46		; a listing line before the name
TOTAL_FIXED	equ	29		; the totals line before the count
COPY_SIZE	equ	8192		; copy_buffer: what is read and
					;   written at a time

		cseg

; main - the entry point, where MSX-DOS2 starts the program.
;
;   A bad switch ends with .IOPT, and COMMAND2 prints its own message
;   for it: *** Invalid option. Otherwise /? prints the usage and /V
;   the banner alone; /? is tested first, so with both the usage wins.
;
;   Then the archive: the first word that is not a switch. With /L it
;   is listed; without /L it is extracted, /O allowing existing files
;   to be replaced. With no archive named, /L ends with .NOPAR (***
;   Missing parameter), and a line with neither prints the usage.
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
		ld	c,"O"
		call	switch_given	; CY set: /O
		sbc	a,a		; A = 0FFh with /O, 0 without
		ld	(overwrite),a
		jp	extract_archive

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
		jp	nz,list_archive.dos_error	; not found, say
		ld	a,1
		ld	(listing),a	; report_stop: totals
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
; report_stop is the end of list_archive, and extract_archive's too:
; A = the result that stopped the walk, members = how many were read.
report_stop:
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
		ld	a,(listing)
		or	a
		call	nz,print_totals	; a listing ends with its totals
		jr	list_archive.done
list_archive.dos_error:
		ld	b,a		; COMMAND2 prints its message
		dos	_TERM

; extract_archive - extract the members of the archive named in
;   archive_name into the current directory.
;
;   Each member gets one line: extracted and OK, extracted with a CRC
;   error (and the file deleted), or skipped, with why. A member that
;   cannot be read, or a write that fails, ends the extraction; the
;   result goes to report_stop, as for a listing.
;
; Input:	archive_name: the archive's name, zero-terminated
;		overwrite: not 0 when /O was given
; Output:	does not return
; Modifies:	everything
; Scratch:	none

extract_archive:
		xor	a
		ld	(listing),a	; report_stop: no totals
		ld	de,archive_name
		call	lzh_open
		or	a
		jp	nz,report_stop	; not found, say
		call	crc_init
		ld	hl,0
		ld	(members),hl
extract_archive.next:
		call	lzh_next_header
		or	a
		jp	nz,report_stop
		ld	hl,(members)
		inc	hl
		ld	(members),hl
		call	extract_member	; A = 0, or what stopped it
		or	a
		jr	z,extract_archive.next
		jp	report_stop

; extract_member - extract, or skip, the member just read.
;
;   Only -lh0- (stored) members are extracted in this phase. The file is
;   created with _CREATE's "create new" flag unless /O was given, so an
;   existing file is never replaced by accident: MSX-DOS2 refuses with
;   .FILEX. The data is copied through copy_buffer, COPY_SIZE bytes at a
;   time, its CRC-16 computed on the way; the file is closed, and only
;   then are its date and attributes set (closing a written file gives
;   it the current date). A CRC that does not match deletes the file.
;
; Input:	lzh.as's variables: the member just read
;		overwrite: not 0 for /O
; Output:	A = 0: the next member can be read
;		A = LZH_TRUNCATED, or an MSX-DOS error code: stop
; Modifies:	everything
; Scratch:	none

extract_member:
		ld	hl,lzh_method	; -lh0- only, in this phase
		ld	de,method_lh0
		ld	b,5
extract_member.method:
		ld	a,(de)
		cp	(hl)
		jr	nz,extract_member.unsupported
		inc	hl
		inc	de
		djnz	extract_member.method
		ld	de,out_name	; the name, zero-terminated
		ld	bc,(lzh_name_length)
		ld	a,b
		or	c
		jr	z,extract_member.named	; empty: _CREATE says why
		ld	hl,lzh_name
		ldir
extract_member.named:
		xor	a
		ld	(de),a
		ld	a,(overwrite)	; B = 80h: create new, unless /O
		cpl
		and	80h
		ld	b,a
		xor	a		; open mode: read and write
		ld	de,out_name
		dos	_CREATE		; B = the handle
		or	a
		jr	z,extract_member.created
		push	af
		print	msg_skipping
		printl	lzh_name,(lzh_name_length)
		pop	af
		cp	.FILEX
		jr	nz,extract_member.refused
		print	msg_exists
		jp	lzh_skip_data	; A = 0, or what stopped it
extract_member.refused:
		push	af
		print	msg_colon
		pop	af
		call	print_explanation	; MSX-DOS2's reason
		print	msg_crlf
		jp	lzh_skip_data
extract_member.unsupported:
		print	msg_skipping
		printl	lzh_name,(lzh_name_length)
		print	msg_colon
		printl	lzh_method,5
		print	msg_not_yet
		jp	lzh_skip_data
extract_member.created:
		ld	a,b
		ld	(out_handle),a
		print	msg_extracting
		printl	lzh_name,(lzh_name_length)
		ld	hl,0
		ld	(crc_value),hl
		ld	hl,(lzh_packed)	; remaining = the data's size
		ld	(remaining),hl
		ld	hl,(lzh_packed+2)
		ld	(remaining+2),hl
extract_member.copy:
		ld	hl,(remaining+2)
		ld	a,h
		or	l
		ld	hl,COPY_SIZE
		jr	nz,extract_member.chunk	; 64 KB or more left
		ld	de,(remaining)
		ld	a,d
		or	e
		jr	z,extract_member.copied	; nothing left
		ex	de,hl		; HL = what is left, DE = COPY_SIZE
		or	a
		sbc	hl,de
		add	hl,de
		jr	c,extract_member.chunk	; less: all of it
		ex	de,hl		; HL = COPY_SIZE
extract_member.chunk:
		ld	(chunk),hl
		ld	de,copy_buffer
		call	lzh_read	; A = 0, TRUNCATED, or an error
		or	a
		jp	nz,extract_member.failed	; too far for jr
		ld	de,copy_buffer
		ld	bc,(chunk)
		call	crc_update
		ld	a,(out_handle)
		ld	b,a
		ld	de,copy_buffer
		ld	hl,(chunk)
		dos	_WRITE		; HL = how many were written
		or	a
		jr	nz,extract_member.failed
		ld	de,(chunk)
		sbc	hl,de		; carry clear from OR A
		ld	a,.DKFUL	; fewer written: the disk is full
		jr	nz,extract_member.failed
		ld	hl,(remaining)	; remaining -= chunk
		sbc	hl,de		; carry clear: the SBC above was 0
		ld	(remaining),hl
		ld	hl,(remaining+2)
		ld	de,0
		sbc	hl,de
		ld	(remaining+2),hl
		jr	extract_member.copy
extract_member.copied:
		ld	a,(out_handle)
		ld	b,a
		dos	_CLOSE
		or	a
		jr	nz,extract_member.failed_closed
		ld	hl,(crc_value)
		ld	de,(lzh_crc)
		sbc	hl,de		; carry clear from OR A
		jr	nz,extract_member.crc_error
		call	set_date_attributes
		print	msg_ok
		xor	a
		ret
extract_member.crc_error:
		ld	de,out_name
		dos	_DELETE
		print	msg_crc_error
		xor	a
		ret
extract_member.failed:
		push	af		; A = what stopped it
		ld	a,(out_handle)
		ld	b,a
		dos	_CLOSE
		jr	extract_member.discard
extract_member.failed_closed:
		push	af
extract_member.discard:
		ld	de,out_name	; never leave a partial file
		dos	_DELETE
		print	msg_crlf
		pop	af
		ret

; set_date_attributes - give the file just extracted its date and its
;   attributes.
;
;   Levels 0 and 1 store MS-DOS's time and date words, which are set as
;   they are. Level 2 stores seconds since 1970: format_date turns them
;   into the date's parts, which are packed into MS-DOS's two words; the
;   file gets its UTC time, as the listing shows it. A level 2 date
;   before 1980, which MS-DOS cannot hold, becomes 1980-01-01 00:00.
;
;   Of the attributes only read-only, hidden and system (bits 0 to 2) are
;   set, with the archive bit, which _CREATE set already; nothing is
;   done when none of the three is set. Errors are not reported: the
;   file is extracted and right, only its date or attributes are not.
;
; Input:	out_name, lzh.as's variables
; Output:	the file's date, and its attributes
; Modifies:	everything
; Scratch:	none

set_date_attributes:
		ld	a,(lzh_level)
		cp	2
		jr	z,set_date_attributes.unix
		ld	hl,(lzh_time)	; levels 0, 1: IX = time, HL = date
		push	hl
		pop	ix
		ld	hl,(lzh_time+2)
		jr	set_date_attributes.set
set_date_attributes.unix:
		call	format_date	; date_year ... date_second
		call	pack_date	; HL = date, IX = time
set_date_attributes.set:
		ld	de,out_name
		ld	a,1		; set
		dos	_FTIME
		ld	a,(lzh_attributes)
		and	07h		; read-only, hidden, system
		ret	z
		or	20h		; and archive, which it has
		ld	l,a
		ld	de,out_name
		ld	a,1		; set
		dos	_ATTR
		ret

; pack_date - MS-DOS's date and time words, from format_date's
;   parts.
;
;   The date is the year since 1980 in bits 15 to 9, the month in 8 to 5
;   and the day in 4 to 0; the time is the hour in bits 15 to 11, the
;   minute in 10 to 5 and the seconds halved in 4 to 0.
;
; Input:	date_year ... date_second
; Output:	HL = the date word
;		IX = the time word
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

pack_date:
		ld	hl,(date_year)
		ld	de,1980
		or	a
		sbc	hl,de		; L = years since 1980
		jr	c,pack_date.early
		ld	a,l
		add	a,a
		ld	h,a		; H = the years, shifted
		ld	l,0
		ld	a,(date_month)
		ld	e,a
		ld	d,0
		ld	b,5
pack_date.month:
		sla	e
		rl	d
		djnz	pack_date.month
		add	hl,de
		ld	a,(date_day)
		ld	e,a
		ld	d,0
		add	hl,de		; HL = the date word
		push	hl
		ld	a,(date_hour)
		add	a,a
		add	a,a
		add	a,a
		ld	h,a		; H = the hour, shifted
		ld	l,0
		ld	a,(date_minute)
		ld	e,a
		ld	d,0
		ld	b,5
pack_date.minute:
		sla	e
		rl	d
		djnz	pack_date.minute
		add	hl,de
		ld	a,(date_second)
		srl	a
		ld	e,a
		ld	d,0
		add	hl,de
		push	hl
		pop	ix		; IX = the time word
		pop	hl		; HL = the date word
		ret
pack_date.early:
		ld	hl,0021h	; before 1980: 1980-01-01 00:00
		ld	ix,0
		ret

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
;		date_year ... date_second: its parts
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
		call	divide_by_c	; DE:HL = minutes, A = second
		ld	(date_second),a
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
; msg_not_lzh		no member could be read
; msg_damaged		a header is not valid
; msg_truncated		the file ends inside a member
; msg_level3		a level 3 header
; msg_list_head		the listing's heading
; msg_list_foot		the rule above the totals
; msg_file		after a count of 1
; msg_files		after any other count
; month_lengths		the days in each month, February at 28
; msg_extracting, msg_skipping, msg_ok, msg_crc_error, msg_exists,
; msg_colon, msg_not_yet	extracting's words, put together per member
; method_lh0		the one method extracted in this phase
;
switch_letters:	defb	"DLOQV?",0
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
		defb	"  /O       overwrite files that already exist"
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
msg_extracting:	defb	"Extracting $"
msg_skipping:	defb	"Skipping $"
msg_ok:		defb	" OK",CHR_CR,CHR_LF,"$"
msg_crc_error:	defb	" CRC error",CHR_CR,CHR_LF,"$"
msg_exists:	defb	": it already exists",CHR_CR,CHR_LF,"$"
msg_colon:	defb	": $"
msg_not_yet:	defb	" is not supported yet",CHR_CR,CHR_LF,"$"
method_lh0:	defb	"-lh0-"

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
; date_month, date_day, date_hour, date_minute, date_second, date_leap
;			format_date: the rest, a byte each; date_leap is
;			the low byte of the year's length
; listing		not 0 while listing: report_stop prints totals
; overwrite		not 0 with /O
; out_handle		the file being extracted
; out_name		its name, zero-terminated
; remaining		its data still to copy, 4 bytes
; chunk			the bytes in copy_buffer this time round
; copy_buffer		the data, COPY_SIZE bytes at a time, in the
;			buffers segment, which the program file does not
;			carry
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
date_second:	defs	1
listing:	defs	1
overwrite:	defs	1
out_handle:	defs	1
out_name:	defs	256
remaining:	defs	4
chunk:	defs	2

		dseg	buffers
copy_buffer:	defs	COPY_SIZE

		end	main
