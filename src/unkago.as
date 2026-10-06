; unkago.as - UNKAGO, the decompressor: it lists LZH, PMA and ZIP
; archives, and extracts LZH's stored, -lh1- and -lh4- to -lh7- members,
; PMA's stored (-pm0-), -pm1- and -pm2- ones, and ZIP's stored and
; deflate ones (lh5.as, lh1.as, pm1.as, pm2.as, inflate.as). A PMA
; archive is read as LZH (lzh.as).
;
; It checks for MSX-DOS2 and the command line. The archive's first bytes
; tell its format (open_archive): ZIP's are read by zip.as, LZH's by
; lzh.as, into the same variables. With /L it lists the members: sizes,
; method, date and path, one line each, and the totals. Without it, it
; extracts the members it has the method for into the current
; directory, or the one /D: names, checking first that they fit on the
; disk and their windows in the mapper, and then each one's CRC: CRC-16
; for LZH, CRC-32 for ZIP. The directories in the members' paths are
; made as they are needed, and directory members make theirs and give
; them their dates; a part of a path that does not fit 8.3 is shortened
; the VFAT way (names.as). Names after the archive's, with * and ?,
; choose the members, for listing and extracting alike; a directory's
; name chooses what is under it. On the screen, each member's line shows
; how far through it UNKAGO is.

		include	common.inc	; common.as's routines, and print
		include	lzh.inc		; lzh.as: reading the archive
		include	crc.inc		; crc.as: the CRC-16
		include	lh5.inc		; lh5.as: the -lh5- decoder
		include	names.inc	; names.as: the MSX-DOS names
		include	zip.inc		; zip.as: reading ZIP archives
		include	inflate.inc	; inflate.as: deflate
		include	lh1.inc		; lh1.as: -lh1-
		include	pm1.inc		; pm1.as: -pm1-
		include	pm2.inc		; pm2.as: -pm2-
		include	progress.inc	; progress.as: the progress line

		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	errors.inc	; .IOPT, .NOPAR, .FILEX, .DKFUL...
		include	ascii.inc	; CHR_CR, CHR_LF, CHR_SPACE

LINE_FIXED	equ	46		; a listing line before the name
DATE_AT		equ	29		; where its date starts
TOTAL_FIXED	equ	29		; the totals line before the count
COPY_SIZE	equ	8192		; copy_buffer: what is read and
					;   written at a time
PATH_SEPARATOR	equ	5Ch		; "\", the yen sign on a Japanese MSX

		cseg

; main - the entry point, where MSX-DOS2 starts the program.
;
;   A bad switch ends with .IOPT, and COMMAND2 prints its own message
;   for it: *** Invalid option. Otherwise /? prints the usage and /V
;   the banner alone; /? is tested first, so with both the usage wins.
;
;   Then the archive: the first word that is not a switch. With /L it
;   is listed; without /L it is extracted, /O allowing existing files
;   to be replaced, /D:path naming where to. With no archive named, /L
;   ends with .NOPAR (*** Missing parameter), and a line with neither
;   prints the usage. A /D with no path ends with .NOPAR too. The
;   words after the archive that are not switches are member names.
;
; Input:	the command line, at COMMAND_TAIL (common.as)
; Output:	does not return
; Modifies:	everything
; Scratch:	none

main:
		call	dos_version	; CY set = not MSX-DOS2
		jp	c,main.need_dos2	; too far for jr
		call	heapinit	; MapperHeap: CY set = no mapper
		jp	c,main.no_mapper
		ld	hl,switch_letters
		call	find_bad_switch	; CY set = a switch it does not take
		jp	c,main.bad_switch	; too far for jr
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
		call	collect_names	; HL -> what follows it
		ld	c,"L"
		call	switch_given
		jp	c,list_archive
		ld	c,"O"
		call	switch_given	; CY set: /O
		sbc	a,a		; A = 0FFh with /O, 0 without
		ld	(overwrite),a
		xor	a
		ld	(dest_path),a	; no /D: the current directory
		ld	c,"D"
		call	switch_value	; CY set: HL -> it, B = its length
		jp	nc,extract_archive
		ld	a,(hl)		; ":" and at least one character
		cp	":"
		jr	nz,main.no_path
		dec	b
		jr	z,main.no_path
		inc	hl
		ld	de,dest_path
		ld	c,b
		ld	b,0
		ldir
		xor	a
		ld	(de),a
		jp	extract_archive
main.no_path:
		ld	b,.NOPAR	; COMMAND2: *** Missing parameter
		dos	_TERM

main.usage:
		print	msg_banner
		print	msg_usage
		dos	_TERM0

main.bad_switch:
		ld	b,.IOPT		; COMMAND2: *** Invalid option
		dos	_TERM

main.no_mapper:
		print	msg_no_mapper
		dos	_TERM0

main.need_dos2:
		print	msg_need_dos2	; _STROUT: MSX-DOS1 has it too
		dos	_TERM0		; function 00h, in MSX-DOS1 too

; collect_names - the member names given after the archive's name.
;
;   Every word after the archive that is not a switch is one, up to the
;   end of the line. Each is kept in name_list as a flag byte (0 until
;   a member matches it), then the name, folded to upper case, and a 0.
;   The command line holds at most 127 characters, so at most 64 names
;   of one character each: 192 bytes.
;
; Input:	HL -> the command line just after the archive's name
; Output:	name_list, name_count
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

collect_names:
		ex	de,hl		; DE -> the line
		ld	hl,name_list
		xor	a
		ld	(name_count),a
collect_names.next:
		ld	a,(de)
		or	a
		ret	z		; the end of the line
		cp	CHR_SPACE
		jr	z,collect_names.blank
		cp	CHR_TAB
		jr	z,collect_names.blank
		cp	"/"
		jr	nz,collect_names.word
		call	skip_word	; a switch: not a name
		jr	collect_names.next
collect_names.blank:
		inc	de
		jr	collect_names.next
collect_names.word:
		ld	(hl),0		; not matched yet
		inc	hl
collect_names.char:
		ld	a,(de)
		or	a
		jr	z,collect_names.ended
		cp	CHR_SPACE
		jr	z,collect_names.ended
		cp	CHR_TAB
		jr	z,collect_names.ended
		call	fold_case
		ld	(hl),a
		inc	hl
		inc	de
		jr	collect_names.char
collect_names.ended:
		ld	(hl),0
		inc	hl
		ld	a,(name_count)
		inc	a
		ld	(name_count),a
		jr	collect_names.next

; list_archive - list the members of the archive named in
;   archive_name: a line for each, and the totals.
;
;   lzh.as or zip.as reads the headers; this prints a heading before
;   the first member, a line for each (print_member), and the totals
;   after the last (print_totals), and decides what each result means
;   here. A listing cut short by a damaged or truncated archive ends
;   with the message instead of the totals. An archive in which not a
;   single member could be read is not an LZH archive, unless the
;   first header is level 3: that is one, and the level is what is
;   reported. A ZIP archive with no members is one: it is empty.
;
;   With member names given, only the members they match are listed
;   and added up; the heading comes with the first of them, and with
;   none there are no totals. Either way, a name that matched nothing
;   is reported at the end.
;
; Input:	archive_name: the archive's name, zero-terminated
;		name_list, name_count: the member names given
; Output:	does not return
; Modifies:	everything
; Scratch:	none

list_archive:
		call	open_archive
		or	a
		jp	nz,list_archive.stop	; not found, not read: say
		ld	a,1
		ld	(listing),a	; report_stop: totals
		ld	hl,0
		ld	(members),hl
		ld	(listed),hl
		ld	(total_packed),hl
		ld	(total_packed+2),hl
		ld	(total_original),hl
		ld	(total_original+2),hl
list_archive.next:
		call	next_member
		or	a
		jr	nz,list_archive.stop
		ld	hl,(members)	; read, asked for or not
		inc	hl
		ld	(members),hl
		call	member_selected	; Z: list it
		jr	nz,list_archive.skip
		ld	hl,(listed)
		ld	a,h
		or	l
		jr	nz,list_archive.headed
		print	msg_list_head	; before the first member
list_archive.headed:
		call	print_member
		call	add_totals
		ld	hl,(listed)
		inc	hl
		ld	(listed),hl
list_archive.skip:
		call	skip_member
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
		ld	a,(archive_format)	; none read: ZIP, a result;
		or	a		;   anything else, not an
		ld	a,c		;   archive
		jr	nz,list_archive.zip
		cp	LZH_LEVEL3
		jr	z,list_archive.level3
		ld	de,msg_not_lzh	; no member read at all
		jr	list_archive.say
list_archive.zip:
		ld	de,msg_empty
		cp	LZH_END
		jr	z,list_archive.say
list_archive.some:
		ld	de,msg_split
		cp	ZIP_SPLIT
		jr	z,list_archive.say
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
		jr	z,list_archive.unmatched
		ld	hl,(listed)
		ld	a,h
		or	l
		call	nz,print_totals	; a listing ends with its totals
list_archive.unmatched:
		call	report_unmatched
		jr	list_archive.done
list_archive.dos_error:
		ld	b,a		; COMMAND2 prints its message
		dos	_TERM

; extract_archive - extract the members of the archive named in
;   archive_name, into the current directory or dest_path.
;
;   First name_walk gives every part of every path its MSX-DOS name;
;   then check_space walks the archive and stops unless it all fits;
;   then the directories /D: names are created; then the archive is
;   walked again, extracting.
;
;   Each member gets one line: extracted and OK, extracted with a CRC
;   error (and the file deleted), or skipped, with why. A write that
;   fails, a full disk or root directory included, ends the extraction,
;   and not_extracted names the members left before saying why.
;
; Input:	archive_name: the archive's name, zero-terminated
;		overwrite: not 0 when /O was given
;		dest_path: where to, zero-terminated; empty for here
; Output:	does not return
; Modifies:	everything
; Scratch:	none

extract_archive:
		xor	a
		ld	(listing),a	; report_stop: no totals
		call	open_archive
		or	a
		jp	nz,report_stop	; not found, not read: say
		call	name_walk	; the names; back at the start
		call	check_space	; returns only if it all fits
		ld	a,1
		ld	(dest_mode),a	; walk_dest: create
		xor	a
		ld	(dest_error),a
		call	walk_dest
		ld	a,(dest_error)
		or	a
		jp	nz,report_stop	; one could not be created
		ld	(last_length),a	; A = 0: no member's directories yet
		call	rewind_archive
		or	a
		jp	nz,report_stop
		call	progress_init	; on the screen, not with /Q
		ld	hl,extracting_line	; what the line starts with
		ld	(progress_line),hl
		call	crc_tables	; CRC-16's, or CRC-32's
		ld	hl,0
		ld	(members),hl
extract_archive.next:
		call	next_member
		or	a
		jp	nz,report_stop
		ld	hl,(members)
		inc	hl
		ld	(members),hl
		call	extract_member	; A = 0, or what stopped it
		or	a
		jr	z,extract_archive.next
		jp	not_extracted	; the rest, then why

; extract_member - extract, or skip, the member just read.
;
;   A member not asked for is passed over without a line, and one
;   whose method UNKAGO does not have gets a line saying so; an
;   encrypted ZIP member's says that instead. The directories in the
;   member's path are made first (member_dirs); one that cannot be skips
;   the member, with MSX-DOS2's reason. A directory member is made, and
;   given its date and its hidden attribute, whether it was there
;   already or not. A ZIP member's local header is read next (zip_data),
;   so that a damaged one stops before anything is created. The file,
;   out_name, is created with _CREATE's "create new" flag unless /O was
;   given, so an existing file is never replaced by accident: MSX-DOS2
;   refuses with .FILEX. The data is copied through copy_buffer,
;   COPY_SIZE bytes at a time, its CRC computed on the way (crc_add);
;   the file is closed, and only then are its date and attributes set
;   (closing a written file gives it the current date). On the screen
;   the line shows the percentage as the data is copied (progress_start,
;   progress_update), cleared before the last word (progress_end). A CRC
;   that does not match deletes the file. A full disk or root directory
;   stops, where any other refusal to create only skips.
;
; Input:	lzh.as's variables: the member just read
;		overwrite: not 0 for /O
;		dest_path
; Output:	A = 0: the next member can be read
;		A = LZH_TRUNCATED, or an MSX-DOS error code: stop
; Modifies:	everything
; Scratch:	none

extract_member:
		call	member_selected	; Z: asked for
		jp	nz,skip_member	; not asked for: no line
		call	member_supported	; Z: one UNKAGO extracts
		jp	nz,extract_member.unsupported	; too far for jr
		call	out_path	; out_name: where it goes
		call	member_dirs	; its directories, made
		ld	a,(dest_error)
		or	a
		jp	nz,extract_member.no_dir
		ld	a,(member_kind)
		cp	"d"
		jp	z,extract_member.directory
		ld	a,(archive_format)	; ZIP: to the data, past
		or	a		;   the local header
		call	nz,zip_data	; A = 0, or what stops it
		or	a
		ret	nz
		ld	a,(overwrite)	; B = 80h: create new, unless /O
		cpl
		and	80h
		ld	b,a
		xor	a		; open mode: read and write
		ld	de,out_name
		dos	_CREATE		; B = the handle
		or	a
		jp	z,extract_member.created	; too far for jr
		cp	.FILEX
		jr	nz,extract_member.no_dir
		print	msg_skipping	; "create new" refused
		call	print_target
		print	msg_exists
		jp	skip_member	; A = 0, or what stopped it
extract_member.no_dir:
		cp	.DKFUL		; no room: stop, not skip
		ret	z
		cp	.DRFUL
		ret	z
		push	af
		print	msg_skipping
		call	print_target
		print	msg_colon
		pop	af
		call	print_explanation	; MSX-DOS2's reason
		print	msg_crlf
		jp	skip_member
extract_member.directory:
		ld	hl,(lzh_name_length)
		ld	a,h
		or	l
		jp	z,skip_member	; the destination itself: no line
		print	msg_extracting
		call	print_target
		call	set_date_attributes
		print	msg_ok
		jp	skip_member	; no data, but on to the next header
extract_member.unsupported:
		print	msg_skipping
		call	print_path
		ld	a,(archive_format)	; encrypted ZIP: say so
		or	a
		jr	z,extract_member.method
		ld	a,(zip_flags)
		rrca
		jr	nc,extract_member.method
		print	msg_encrypted
		jp	skip_member
extract_member.method:
		print	msg_colon
		call	print_method
		print	msg_not_yet
		jp	skip_member
extract_member.created:
		ld	a,b
		ld	(out_handle),a
		print	msg_extracting
		call	print_target
		ld	hl,(lzh_original)	; what the member unpacks to
		ld	de,(lzh_original+2)
		call	progress_start	; "   0%", on the screen
		call	crc_start
		ld	hl,(lzh_packed)	; -lh0-: the data's size
		ld	de,(lzh_packed+2)
		ld	a,(member_kind)
		cp	"0"
		jr	z,extract_member.sized
		ld	hl,(lzh_original)	; -lhN-: what it unpacks to
		ld	de,(lzh_original+2)
extract_member.sized:
		ld	(remaining),hl
		ld	(remaining+2),de
		jr	z,extract_member.copy	; -lh0-: Z still from the CP
		ld	de,copy_buffer	; the output buffer
		ld	a,(archive_format)	; ZIP: deflate
		or	a
		jr	nz,extract_member.inflate
		ld	a,(member_kind)	; B = the method's digit
		cp	"1"		; -lh1-: its own symbols
		jr	z,extract_member.lh1
		cp	"2"		; -pm2-: its own too
		jr	z,extract_member.pm2
		cp	"p"		; -pm1-: and its
		jr	z,extract_member.pm1
		ld	b,a
		call	lh5_start	; A = 0, or .NORAM
		jr	extract_member.started
extract_member.lh1:
		call	lh1_start	; A = 0, .NORAM, or a read error
		jr	extract_member.started
extract_member.pm2:
		call	pm2_start	; A = 0, or .NORAM
		jr	extract_member.started
extract_member.pm1:
		call	pm1_start	; A = 0, or .NORAM
		jr	extract_member.started
extract_member.inflate:
		call	inflate_start	; A = 0, or .NORAM
extract_member.started:
		or	a
		jp	nz,extract_member.failed
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
		ld	a,(member_kind)
		cp	"0"
		jr	nz,extract_member.decode
		ld	de,copy_buffer
		call	lzh_read	; A = 0, TRUNCATED, or an error
		jr	extract_member.read
extract_member.decode:
		call	lh5_read	; A = 0, LH5_BAD, or as lzh_read
extract_member.read:
		or	a
		jp	nz,extract_member.not_read	; too far for jr
		ld	de,copy_buffer
		ld	bc,(chunk)
		call	crc_add
		ld	a,(out_handle)
		ld	b,a
		ld	de,copy_buffer
		ld	hl,(chunk)
		dos	_WRITE		; HL = how many were written
		or	a
		jp	nz,extract_member.failed	; too far for jr
		ld	de,(chunk)
		sbc	hl,de		; carry clear from OR A
		ld	a,.DKFUL	; fewer written: the disk is full
		jp	nz,extract_member.failed
		ld	hl,(remaining)	; remaining -= chunk
		sbc	hl,de		; carry clear: the SBC above was 0
		ld	(remaining),hl
		ld	hl,(remaining+2)
		ld	de,0
		sbc	hl,de
		ld	(remaining+2),hl
		ld	hl,(chunk)
		call	progress_update
		jr	extract_member.copy
extract_member.copied:
		ld	a,(member_kind)
		cp	"0"
		jr	z,extract_member.close	; -lh0-: all of it was read
		call	lh5_finish	; the data not read: A = 0, or
		or	a
		jp	nz,extract_member.failed
extract_member.close:
		ld	a,(out_handle)
		ld	b,a
		dos	_CLOSE
		or	a
		jr	nz,extract_member.failed_closed
		call	progress_end	; the number off the line
		call	crc_check	; Z: it matches
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
extract_member.not_read:
		cp	LH5_BAD		; bad data: this member only
		jr	nz,extract_member.failed
		ld	a,(out_handle)
		ld	b,a
		dos	_CLOSE
		ld	de,out_name
		dos	_DELETE
		call	lh5_finish	; on to the next member
		or	a
		ret	nz
		call	progress_end
		print	msg_data_error
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

; member_supported - whether the member just read is one UNKAGO
;   extracts: -lh0- (stored), -lh1-, -lh4- to -lh7-, or -lhd- (a
;   directory); of PMarc's, -pm0- (stored), as -lh0-, -pm2-, "2", and
;   -pm1-, "p", as "1" is -lh1-'s.
;   Of a ZIP archive's, its directories and its stored and deflate
;   members: stored ones as -lh0-, deflate ones with -lh6-'s window
;   ("6", for the memory check); not an encrypted one.
;
; Input:	lzh_method, lzh_dir (lzh.as); zip_method, zip_flags;
;		archive_format
; Output:	Z set = it is
;		member_kind = the method's digit
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

member_supported:
		ld	a,(archive_format)
		or	a
		jr	z,member_supported.lzh
		ld	a,(lzh_dir)	; ZIP: a directory
		or	a
		ld	a,"d"
		jr	nz,member_supported.zip
		ld	a,(zip_flags)	; encrypted: no
		rrca
		jr	c,member_supported.no
		ld	a,(zip_method)	; "stored ": as -lh0-
		cp	"s"
		ld	a,"0"
		jr	z,member_supported.zip
		ld	a,(zip_method)	; "deflate": -lh6-'s window
		cp	"d"
		jr	nz,member_supported.no
		ld	a,"6"
member_supported.zip:
		ld	(member_kind),a
		xor	a		; Z set
		ret
member_supported.lzh:
		ld	a,(lzh_method+1)	; PMarc's: -pm0-, stored
		cp	"p"
		jr	nz,member_supported.lh
		ld	a,(lzh_method+2)
		cp	"m"
		jr	nz,member_supported.no
		ld	a,(lzh_method+3)
		ld	(member_kind),a	; "0": as -lh0-; "2": -pm2-
		cp	"0"
		ret	z
		cp	"2"
		ret	z
		cp	"1"
		jr	nz,member_supported.no
		ld	a,"p"		; -pm1-
		ld	(member_kind),a
		xor	a		; Z set
		ret
member_supported.lh:
		ld	hl,lzh_method
		ld	de,method_lh0
		ld	b,3		; "-lh"
member_supported.next:
		ld	a,(de)
		cp	(hl)
		ret	nz
		inc	hl
		inc	de
		djnz	member_supported.next
		ld	a,(lzh_method+4)
		cp	"-"
		ret	nz
		ld	a,(lzh_method+3)	; the method's number
		ld	(member_kind),a
		cp	"0"
		ret	z
		cp	"d"		; -lhd-
		ret	z
		cp	"1"		; -lh1-
		ret	z
		sub	"4"		; "4" to "7": 0 to 3
		cp	4
		jr	nc,member_supported.no
		xor	a		; Z set: -lh4- to -lh7-
		ret
member_supported.no:
		or	1		; Z clear
		ret

; name_walk - the MSX-DOS name of every part of every member's path.
;
;   Every member, asked for or not: the numbers in the tails must not
;   depend on which ones are. One walk puts each path into names.as's
;   table, names_assign gives the tails, and the archive is rewound for
;   check_space. A walk that fails ends here, through report_stop, as
;   check_space's would, members counted the same way. A table that
;   does not fit in the mapper is R7's shortage: one segment more than
;   it has had.
;
; Input:	the archive open, at its start
; Output:	the table; the archive at its start
; Modifies:	everything
; Scratch:	none

name_walk:
		call	names_init
		ld	hl,0
		ld	(members),hl
name_walk.next:
		call	next_member
		or	a
		jr	nz,name_walk.end
		ld	hl,(members)
		inc	hl
		ld	(members),hl
		call	names_add	; CY: no room
		jr	c,name_walk.full
		call	skip_member
		or	a
		jr	z,name_walk.next
		jp	report_stop	; cut off, or a read error
name_walk.end:
		cp	LZH_END
		jp	nz,report_stop	; damaged, level 3, an error
		call	names_assign
		call	rewind_archive
		or	a
		ret	z
		jp	report_stop
name_walk.full:
		ld	a,(names_segs)	; free: what it took; needed: one more
		ld	l,a
		ld	h,0
		ld	(free_segs),hl
		inc	a
		ld	(need_segs),a
		jp	check_memory.short

; check_space - stop, saying why, unless the extraction fits.
;
;   The archive is walked once, and each member that will be extracted
;   counts its original size, rounded up to whole clusters; a 0-byte
;   file takes none. Each directory /D: will create, and each one a
;   member's path needs that is not there (member_dirs), takes one
;   cluster more. The cluster's size and the free clusters come from _ALLOC,
;   for the drive /D: names or the current one.
;
;   A file that exists already counts in full, though without /O it is
;   skipped and with /O it frees its own space: the estimate errs on the
;   safe side. A walk that fails (a damaged or cut-off archive, a read
;   error) ends here, through report_stop, with nothing written.
;
;   The walk also finds the largest window among the members, which
;   check_memory, last, weighs against the free mapper memory.
;
; Input:	the archive open, at its start
;		dest_path
; Output:	returns only if it fits, on the disk and in the mapper
; Modifies:	everything
; Scratch:	none

check_space:
		call	dest_drive	; E = the drive
		dos	_ALLOC		; A, BC: the cluster; HL: free ones
		ld	(free_clusters),hl
		inc	a		; A = 0FFh: no such drive
		jp	z,check_space.no_drive
		dec	a
		ld	d,-1		; D = log2(sectors per cluster)
check_space.sectors:
		inc	d
		srl	a
		jr	nz,check_space.sectors
		dec	d		; and + log2(bytes per sector)
check_space.bytes:
		inc	d
		srl	b
		rr	c
		ld	a,b
		or	c
		jr	nz,check_space.bytes
		ld	a,d
		ld	(cluster_shift),a
		xor	a
		ld	(dest_mode),a	; walk_dest: count
		ld	hl,0
		ld	(new_dirs),hl
		call	walk_dest
		ld	hl,0
		ld	(need_clusters),hl
		ld	(need_clusters+2),hl
		ld	(members),hl
		xor	a
		ld	(need_segs),a	; no window yet
		ld	(last_length),a	; no member's directories yet
check_space.next:
		call	next_member
		or	a
		jr	nz,check_space.end
		ld	hl,(members)
		inc	hl
		ld	(members),hl
		call	member_selected	; Z: asked for
		jr	nz,check_space.skip
		call	member_supported	; Z: it will be extracted
		jr	nz,check_space.skip
		call	out_path	; its new directories, counted
		call	member_dirs
		ld	hl,(lzh_original)
		ld	de,(lzh_original+2)
		call	to_clusters	; DE:HL = its clusters
		ld	bc,(need_clusters)
		add	hl,bc
		ld	(need_clusters),hl
		ex	de,hl
		ld	bc,(need_clusters+2)
		adc	hl,bc
		ld	(need_clusters+2),hl
		ld	a,(member_kind)	; its window, in segments
		cp	"d"
		jr	z,check_space.skip	; -lhd-: none
		cp	"1"		; -lh1-: -lh4-'s ring
		jr	z,check_space.lh4
		cp	"2"		; -pm2-: -lh5-'s, the same
		jr	z,check_space.lh4
		cp	"p"		; -pm1-: -lh6-'s, 32 KB
		jr	nz,check_space.ring
		ld	a,"6"
		jr	check_space.ring
check_space.lh4:
		ld	a,"4"
check_space.ring:
		sub	"4"		; "4" to "7": 0 to 3
		jr	c,check_space.skip	; -lh0-: none
		ld	e,a
		ld	d,0
		ld	hl,window_segs
		add	hl,de
		ld	a,(hl)
		ld	hl,need_segs	; the largest so far
		cp	(hl)
		jr	c,check_space.skip
		ld	(hl),a
check_space.skip:
		call	skip_member
		or	a
		jr	z,check_space.next
		jp	report_stop	; cut off, or a read error
check_space.end:
		cp	LZH_END
		jp	nz,report_stop	; damaged, level 3, an error
		ld	hl,(members)
		ld	a,h
		or	l
		ld	a,LZH_END
		jp	z,report_stop	; no member at all: not LZH
		ld	hl,(need_clusters)	; a cluster for each directory
		ld	de,(new_dirs)
		add	hl,de
		ld	(need_clusters),hl
		jr	nc,check_space.dirs
		ld	hl,(need_clusters+2)
		inc	hl
		ld	(need_clusters+2),hl
check_space.dirs:
		ld	hl,(need_clusters+2)
		ld	a,h
		or	l
		jr	nz,check_space.short	; 64K clusters or more
		ld	hl,(free_clusters)
		ld	de,(need_clusters)
		or	a
		sbc	hl,de
		jp	nc,check_memory	; it fits: now the mapper
check_space.short:
		print	msg_space_need
		ld	hl,(need_clusters)
		ld	de,(need_clusters+2)
		ld	a,1		; rounded up
		call	print_size
		print	msg_space_free
		ld	hl,(free_clusters)
		ld	de,0
		xor	a		; rounded down
		call	print_size
		print	msg_space_on
		ld	a,(dest_letter)
		ld	(msg_space_drive),a
		print	msg_space_drive
		dos	_TERM0
check_space.no_drive:
		ld	a,.IDRV		; COMMAND2: *** Invalid drive
		jp	report_stop

; to_clusters - a size in bytes, as whole clusters, rounded up.
;
; Input:	DE:HL = the size
;		cluster_shift
; Output:	DE:HL = the clusters
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

to_clusters:
		ld	a,(cluster_shift)	; 9 or more
		ld	b,a
		ld	c,0		; C = 1 if a 1 bit falls out
to_clusters.bit:
		srl	d
		rr	e
		rr	h
		rr	l
		jr	nc,to_clusters.next
		ld	c,1
to_clusters.next:
		djnz	to_clusters.bit
		ld	b,0		; part of a cluster: one more
		add	hl,bc
		ret	nc
		inc	de
		ret

; dest_drive - the drive extracting writes to.
;
;   The one dest_path starts with ("B:"), or the current one.
;
; Input:	dest_path
; Output:	E = the drive's number, 1 for A:
;		dest_letter = its letter
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

dest_drive:
		ld	hl,dest_path
		ld	a,(hl)
		or	a
		jr	z,dest_drive.current	; no /D
		inc	hl
		ld	a,(hl)
		dec	hl
		cp	":"
		jr	nz,dest_drive.current
		ld	a,(hl)
		and	0DFh		; a-z to A-Z
		jr	dest_drive.letter
dest_drive.current:
		dos	_CURDRV		; A = 0 for A:
		add	a,"A"
dest_drive.letter:
		ld	(dest_letter),a
		sub	"A"-1
		ld	e,a
		ret

; walk_dest - each directory in dest_path, from the top down: counted,
;   or created.
;
;   The drive and a leading "\" are not directories to make; the rest
;   is walk_parts'.
;
; Input:	dest_path
;		dest_mode
; Output:	as walk_parts
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

walk_dest:
		ld	hl,dest_path
		ld	(walk_path),hl
		ld	a,(hl)
		or	a
		ret	z		; no /D: nothing to walk
		inc	hl
		ld	a,(hl)
		dec	hl
		cp	":"
		jr	nz,walk_dest.top
		inc	hl		; past the drive
		inc	hl
walk_dest.top:
		ld	a,(hl)
		cp	PATH_SEPARATOR
		jr	nz,walk_dest.start
		inc	hl		; past the root
walk_dest.start:
		ld	d,h		; walk_end: its 0
		ld	e,l
walk_dest.end:
		ld	a,(de)
		or	a
		jr	z,walk_dest.found
		inc	de
		jr	walk_dest.end
walk_dest.found:
		ld	(walk_end),de	; and on into walk_parts

; walk_parts - each directory in a path, from the first part given
;   down: counted, or created.
;
;   Each part ends at a "\" or at walk_end, and the path down to its
;   end is given to MSX-DOS2, with a 0 put after it for the while. With
;   dest_mode 0, a directory _ATTR cannot find adds 1 to new_dirs; with
;   dest_mode 1 it is created with _CREATE, one that is there already
;   (.DIRX) being no error. The first other error is kept in
;   dest_error, and the walk goes on. An empty part, as in a path
;   ending in "\", is not a directory to make.
;
; Input:	HL -> the first part to walk
;		walk_path -> the whole path, from its start
;		walk_end -> where the walk ends
;		dest_mode
; Output:	new_dirs, counted; or the directories, and dest_error
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

walk_parts:
		ld	d,h		; DE -> where this part starts
		ld	e,l
walk_parts.scan:
		call	walk_at_end	; Z: HL is at walk_end
		jr	z,walk_parts.part	; the last part, then return
		ld	a,(hl)
		cp	PATH_SEPARATOR
		jr	z,walk_parts.more
		inc	hl
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	nc,walk_parts.scan
		call	walk_at_end
		jr	z,walk_parts.part
		inc	hl
		jr	walk_parts.scan
walk_parts.more:
		call	walk_parts.part
		inc	hl
		jr	walk_parts
walk_parts.part:
		or	a		; HL -> its end, DE -> its start
		sbc	hl,de
		add	hl,de		; Z from the SBC: empty
		ret	z
		push	hl
		ld	a,(hl)
		push	af
		ld	(hl),0		; the path down to here
		ld	de,(walk_path)
		ld	a,(dest_mode)
		or	a
		jr	nz,walk_parts.create
		dos	_ATTR		; A = 0: get
		or	a
		jr	z,walk_parts.restore	; it is there
		ld	hl,(new_dirs)
		inc	hl
		ld	(new_dirs),hl
		jr	walk_parts.restore
walk_parts.create:
		ld	b,10h		; a subdirectory
		dos	_CREATE
		or	a
		jr	z,walk_parts.restore
		cp	.DIRX
		jr	z,walk_parts.restore	; it was there
		ld	c,a
		ld	a,(dest_error)
		or	a
		jr	nz,walk_parts.restore	; keep the first
		ld	a,c
		ld	(dest_error),a
walk_parts.restore:
		pop	af
		pop	hl
		ld	(hl),a
		ret

; walk_at_end - whether HL is at walk_end.
;
; Input:	HL, walk_end
; Output:	Z set = it is
; Modifies:	F
; Scratch:	none

walk_at_end:
		push	de
		ld	de,(walk_end)
		or	a
		sbc	hl,de
		add	hl,de		; Z from the SBC
		pop	de
		ret

; out_path - out_name: the destination, then the member's path, as
;   names_out gives it in MSX-DOS names.
;
; Input:	dest_path; lzh_name, lzh_name_length (lzh.as); the names
; Output:	out_name: the two, a "\" between if the destination
;		needs one, and a 0
;		out_member -> where the member's path starts in it
;		names_changed: not 0 if a part was shortened
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

out_path:
		ld	hl,dest_path
		ld	de,out_name
		ld	a,(hl)
		or	a
		jr	z,out_path.name	; no /D
out_path.dest:
		ldi
		ld	a,(hl)
		or	a
		jr	nz,out_path.dest
		dec	de
		ld	a,(de)		; the path's last character
		inc	de
		cp	":"
		jr	z,out_path.name
		cp	PATH_SEPARATOR
		jr	z,out_path.name
		ld	a,PATH_SEPARATOR
		ld	(de),a
		inc	de
out_path.name:
		ld	(out_member),de
		call	names_out	; empty: _CREATE says why
		xor	a
		ld	(de),a
		ret

; member_dirs - the directories in the member's path: counted or
;   created, by walk_parts, under the destination.
;
;   A file's are the parts of its path before the last; a directory
;   member's (-lhd-) are all of them. The member before left its own in
;   last_dir, and the parts the two share from the start were walked
;   then, so only the rest are walked now: an archive keeps a
;   directory's members together, and most members walk nothing. One
;   that comes back to a directory after leaving it walks it again;
;   counting, a directory not there yet is then counted twice, which
;   errs on the safe side. Names are compared as MSX-DOS2 does, upper
;   and lower case alike.
;
;   A walk that fails to create leaves last_dir empty, so that the next
;   member tries again, and is skipped with its own reason.
;
; Input:	out_name, out_member (out_path)
;		member_kind
;		dest_mode: 0 to count, 1 to create
;		last_dir, last_length
; Output:	new_dirs; or the directories, and dest_error, 0 for none
;		last_dir, last_length: this member's directories
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	dirs_end
;		dirs_shared

member_dirs:
		xor	a
		ld	(dest_error),a
		ld	hl,(out_member)	; dirs_end: the last "\", or the start
		ld	(dirs_end),hl
member_dirs.scan:
		ld	a,(hl)
		or	a
		jr	z,member_dirs.ended
		cp	PATH_SEPARATOR
		jr	nz,member_dirs.char
		ld	(dirs_end),hl
member_dirs.char:
		inc	hl
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	nc,member_dirs.scan
		ld	a,(hl)
		or	a
		jr	z,member_dirs.ended
		inc	hl
		jr	member_dirs.scan
member_dirs.ended:
		ld	a,(member_kind)
		cp	"d"
		jr	nz,member_dirs.file
		ld	(dirs_end),hl	; a directory: all of it
member_dirs.file:
		ld	hl,(dirs_end)	; C = this member's directories' length
		ld	de,(out_member)
		or	a
		sbc	hl,de
		ld	c,l
		ld	(dirs_shared),de	; nothing shared yet
		ld	a,(last_length)	; B = the shorter of the two
		cp	c
		jr	c,member_dirs.shorter
		ld	a,c
member_dirs.shorter:
		ld	b,a
		ld	hl,last_dir	; HL, DE: the two side by side
		or	a
		jr	z,member_dirs.ends	; nothing to compare
member_dirs.compare:
		ld	a,(de)
		call	fold_case
		push	bc
		ld	c,a
		ld	a,(hl)
		call	fold_case
		cp	c
		pop	bc
		jr	nz,member_dirs.walk	; they part here
		cp	PATH_SEPARATOR
		jr	nz,member_dirs.next
		push	de		; shared up to this "\"
		inc	de
		ld	(dirs_shared),de
		pop	de
member_dirs.next:
		inc	hl
		inc	de
		djnz	member_dirs.compare
member_dirs.ends:
		ld	a,(last_length)	; the shorter used up: is it a whole
		cp	c		;   part of the longer?
		jr	z,member_dirs.all	; the same directories
		jr	c,member_dirs.longer
		ld	a,(hl)		; last_dir's go on
		cp	PATH_SEPARATOR
		jr	nz,member_dirs.walk
member_dirs.all:
		ld	hl,(dirs_end)	; nothing left to walk
		ld	(dirs_shared),hl
		jr	member_dirs.walk
member_dirs.longer:
		ld	a,(de)		; this member's go on
		cp	PATH_SEPARATOR
		jr	nz,member_dirs.walk
		ld	(dirs_shared),de	; the rest, from that "\"
member_dirs.walk:
		ld	hl,out_name
		ld	(walk_path),hl
		ld	hl,(dirs_end)
		ld	(walk_end),hl
		ld	hl,(dirs_shared)
		call	walk_parts
		ld	hl,(dirs_end)	; kept for the next member
		ld	de,(out_member)
		or	a
		sbc	hl,de
		ld	b,h
		ld	c,l
		ld	a,c
		ld	(last_length),a
		ex	de,hl
		ld	de,last_dir
		or	a
		jr	z,member_dirs.kept
		ldir
member_dirs.kept:
		ld	a,(dest_error)
		or	a
		ret	z
		xor	a		; failed: the next member walks again
		ld	(last_length),a
		ret


; not_extracted - after extracting stopped part way: a line for each
;   member not extracted, then the reason, through report_stop.
;
;   The member that failed is number members. The archive is walked
;   again from the start, the members before it passed over, and it and
;   each one after it named. A walk that fails ends the lines; the reason
;   given is still what stopped the extraction.
;
; Input:	A = what stopped it
;		members
; Output:	does not return
; Modifies:	everything
; Scratch:	none

not_extracted:
		ld	(stop_code),a
		call	rewind_archive
		or	a
		jr	nz,not_extracted.done
		ld	hl,0
		ld	(walked),hl
not_extracted.next:
		call	next_member
		or	a
		jr	nz,not_extracted.done
		ld	hl,(walked)
		inc	hl
		ld	(walked),hl
		ld	de,(members)
		sbc	hl,de		; carry clear from OR A
		jr	c,not_extracted.skip	; before the one that failed
		call	member_selected	; only those asked for
		jr	nz,not_extracted.skip
		print	msg_not_extracted
		call	print_path
		print	msg_crlf
not_extracted.skip:
		call	skip_member
		or	a
		jr	z,not_extracted.next
not_extracted.done:
		ld	a,(stop_code)
		jp	report_stop

; print_size - an amount of disk space, given in clusters: "N KB", or
;   "N.N MB" from 1024 KB, as R5 asks.
;
;   The clusters are made 512-byte units first (a cluster is 512 bytes
;   or a power of two more): a KB is 2 units, a tenth of an MB 204.8.
;   The space free is rounded down and the space needed up, so a
;   shortage never looks smaller than it is.
;
; Input:	DE:HL = the clusters
;		A = 0 to round down, 1 to round up
;		cluster_shift
; Output:	the amount, on standard output
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

print_size:
		ld	(size_round),a
		ld	a,(cluster_shift)
		sub	9
		jr	z,print_size.units
		ld	b,a
print_size.double:
		add	hl,hl
		rl	e
		rl	d
		djnz	print_size.double
print_size.units:
		ld	a,d		; DE:HL = 512-byte units
		or	e
		jr	nz,print_size.mb
		ld	a,h
		cp	08h
		jr	nc,print_size.mb	; 2048 units: 1024 KB
		ld	a,(size_round)
		ld	c,a
		ld	b,0
		add	hl,bc		; one more, to round up
		srl	h
		rr	l		; HL = KB
		ld	bc,msg_kb
		jr	print_size.number
print_size.mb:
		ld	(size_value),hl
		ld	(size_value+2),de
		add	hl,hl		; times 4
		rl	e
		rl	d
		add	hl,hl
		rl	e
		rl	d
		ld	bc,(size_value)	; plus once: 5
		add	hl,bc
		ex	de,hl
		ld	bc,(size_value+2)
		adc	hl,bc
		ex	de,hl
		add	hl,hl		; twice that: 10
		rl	e
		rl	d
		ld	a,(size_round)
		or	a
		jr	z,print_size.tenths
		ld	bc,2047		; to round up
		add	hl,bc
		jr	nc,print_size.tenths
		inc	de
print_size.tenths:
		ld	b,11		; / 2048: tenths of an MB
print_size.halve:
		srl	d
		rr	e
		rr	h
		rr	l
		djnz	print_size.halve
		ld	c,10
		call	divide_by_c	; DE:HL = MB, A = tenths
		add	a,"0"
		ld	(mb_digit),a
		ld	bc,msg_mb
print_size.number:
		push	bc		; the unit
		ld	ix,size_text+10
		ld	b,10
		call	format_number	; IX -> the field
print_size.blank:
		ld	a,(ix+0)
		cp	CHR_SPACE
		jr	nz,print_size.digits
		inc	ix
		jr	print_size.blank
print_size.digits:
		push	ix
		pop	de		; DE -> the first digit
		ld	hl,size_text+10
		or	a
		sbc	hl,de		; HL = how many
		call	print_length
		pop	de
		dos	_STROUT		; " KB", or ".N MB"
		ret

; member_selected - whether the member just read was asked for.
;
;   With no names given, every member is. Otherwise it must match at
;   least one of them; each name it matches is marked as matched, so
;   that report_unmatched can name the ones nothing matched.
;
; Input:	lzh_name, lzh_name_length (lzh.as)
;		name_list, name_count
; Output:	Z set = it was asked for, by its path or a directory it is
;		in (match_path)
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

member_selected:
		ld	a,(name_count)
		or	a
		ret	z		; no names: all of them
		ld	b,a
		ld	c,1		; C = 0 once one matches
		ld	hl,name_list
member_selected.next:
		push	bc
		push	hl
		inc	hl		; past the flag
		ex	de,hl		; DE -> the name given
		call	match_path	; Z: it matches
		pop	hl
		pop	bc
		jr	nz,member_selected.skip
		ld	(hl),1		; matched
		ld	c,0
member_selected.skip:
		inc	hl		; to the next flag
		ld	a,(hl)
		or	a
		jr	nz,member_selected.skip
		inc	hl
		djnz	member_selected.next
		ld	a,c
		or	a		; Z: one matched
		ret

; match_path - whether a name given matches the member's path, or a
;   directory the member is in.
;
;   R6: naming a directory extracts what is under it. So the whole path
;   is tried, then each part of it up to a "\", with and without that
;   "\": both DOCS and DOCS\ choose DOCS\README.TXT.
;
; Input:	DE -> the name given, upper case, ending in 0
;		lzh_name, lzh_name_length (lzh.as)
; Output:	Z set = it matches
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	match_given

match_path:
		ld	(match_given),de
		ld	hl,lzh_name
		ld	bc,(lzh_name_length)
		call	match_name
		ret	z		; the whole path
		ld	a,(lzh_name_length)
		ld	b,a		; B = the bytes left to look at
		ld	hl,lzh_name
match_path.scan:
		ld	a,b
		or	a
		jr	z,match_path.no
		ld	a,(hl)
		cp	PATH_SEPARATOR
		jr	z,match_path.part
		inc	hl
		dec	b
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	nc,match_path.scan
		ld	a,b
		or	a
		jr	z,match_path.no
		inc	hl
		dec	b
		jr	match_path.scan
match_path.part:
		push	bc
		push	hl
		ld	de,lzh_name	; BC = the length up to the "\"
		or	a
		sbc	hl,de
		ld	b,h
		ld	c,l
		push	bc
		ld	de,(match_given)
		ld	hl,lzh_name
		call	match_name	; without it
		pop	bc
		jr	z,match_path.matched
		inc	bc
		ld	de,(match_given)
		ld	hl,lzh_name
		call	match_name	; with it
match_path.matched:
		pop	hl
		pop	bc
		ret	z
		inc	hl
		dec	b
		jr	match_path.scan
match_path.no:
		or	1		; Z clear
		ret

; match_name - whether a member's name matches a name given, with its
;   wildcards.
;
;   "?" matches any one character, "*" any run of them, none included;
;   anything else matches itself, upper and lower case alike. The whole
;   name must match. When a character does not match, the last "*" is
;   tried again one character further on, which is enough: a later "*"
;   can always take up what an earlier one did not.
;
; Input:	DE -> the name given, upper case, ending in 0
;		HL -> the member's name
;		BC = its length
; Output:	Z set = it matches
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

match_name:
		push	hl
		add	hl,bc
		ld	(match_end),hl	; just after the member's name
		pop	hl
		ld	bc,0
		ld	(match_star),bc	; no "*" yet
match_name.next:
		ld	a,(de)
		cp	"*"
		jr	z,match_name.star
		call	match_at_end	; Z: no more of the member's name
		jr	z,match_name.end
		ld	a,(de)
		or	a
		jr	z,match_name.back	; the name given is used up
		cp	"?"
		jr	z,match_name.one
		ld	c,a
		ld	a,(hl)
		call	fold_case
		cp	c
		jr	nz,match_name.back
match_name.one:
		inc	de
		inc	hl
		jr	match_name.next
match_name.star:
		inc	de
		ld	(match_star),de	; what follows it
		ld	(match_from),hl	; where it starts taking
		jr	match_name.next
match_name.back:
		ld	de,(match_star)
		ld	a,d
		or	e
		jr	z,match_name.no	; no "*" to take one more
		ld	hl,(match_from)
		call	match_at_end
		jr	z,match_name.no
		inc	hl
		ld	(match_from),hl
		jr	match_name.next
match_name.end:
		ld	a,(de)		; any "*" left matches nothing
		cp	"*"
		jr	nz,match_name.ended
		inc	de
		jr	match_name.end
match_name.ended:
		or	a		; Z: the name given is used up too
		ret
match_name.no:
		or	1		; Z clear
		ret

; match_at_end - whether HL is at the end of the member's name.
;
; Input:	HL
;		match_end
; Output:	Z set = it is
; Modifies:	AF
; Scratch:	none

match_at_end:
		push	de
		ld	de,(match_end)
		or	a
		sbc	hl,de
		add	hl,de		; Z from the SBC
		pop	de
		ret

; report_unmatched - a line for each name given that matched nothing.
;
; Input:	name_list, name_count
; Output:	the lines, on standard output
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

report_unmatched:
		ld	a,(name_count)
		or	a
		ret	z
		ld	b,a
		ld	hl,name_list
report_unmatched.next:
		ld	a,(hl)		; the flag
		inc	hl		; HL -> the name
		or	a
		jr	nz,report_unmatched.skip
		push	bc
		push	hl
		print	msg_not_in
		pop	de
		push	de
		call	print_zero
		print	msg_crlf
		pop	hl
		pop	bc
report_unmatched.skip:
		ld	a,(hl)
		inc	hl
		or	a
		jr	nz,report_unmatched.skip
		djnz	report_unmatched.next
		ret
; extracting_line - the start of a member's line, "Extracting " and its
;   path. progress.as calls it through progress_line, to redraw the
;   line.
;
; Input:	lzh.as's variables; out_member, names_changed
; Output:	they are printed
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

extracting_line:
		print	msg_extracting
		jp	print_target

; check_memory - stop, saying why, unless the window and the tables fit
;   in the free mapper memory, as R7 asks.
;
;   The largest window among the members to be extracted (check_space
;   found it, in segments), and one segment more for the decoder's
;   tables, against mapfree's free segments. A shortage gives both
;   figures, in KB or MB, as for the disk; print_size is told that a
;   "cluster" is a 16 KB segment. name_walk prints its own shortage
;   from check_memory.short, need_segs and free_segs set.
;
; Input:	need_segs: the largest window, 0 for none
; Output:	returns only if it fits
; Modifies:	everything
; Scratch:	none

check_memory:
		ld	a,(need_segs)
		or	a
		ret	z		; nothing to decode: no mapper
		inc	a		; and the tables' block
		ld	(need_segs),a
		call	mapfree		; HL = free segments
		ld	(free_segs),hl
		ld	a,(need_segs)
		ld	e,a
		ld	d,0
		or	a
		sbc	hl,de
		ret	nc		; it fits
check_memory.short:
		ld	a,14		; print_size: segments of 16 KB
		ld	(cluster_shift),a
		print	msg_mem_need
		ld	a,(need_segs)
		ld	l,a
		ld	h,0
		ld	de,0
		ld	a,1		; rounded up
		call	print_size
		print	msg_mem_free
		ld	hl,(free_segs)
		ld	de,0
		xor	a		; rounded down
		call	print_size
		print	msg_mem_end
		dos	_TERM0

; set_date_attributes - give the file just extracted its date and its
;   attributes.
;
;   Levels 0 and 1 store MS-DOS's time and date words, which are set as
;   they are, unless the date is not one (no_date: PMARC2 writes 0); then
;   the file keeps the date it was written with. Level 2 stores seconds
;   since 1970: format_date turns them
;   into the date's parts, which are packed into MS-DOS's two words; the
;   file gets its UTC time, as the listing shows it. A level 2 date
;   before 1980, which MS-DOS cannot hold, becomes 1980-01-01 00:00.
;
;   Of the attributes only read-only, hidden and system (bits 0 to 2) are
;   set, with the archive bit, which _CREATE set already; nothing is
;   done when none of the three is set. A directory (-lhd-) can only
;   be made hidden: that bit is added to the ones it has. Errors are
;   not reported: the file is extracted and right, only its date or
;   attributes are not.
;
; Input:	out_name, lzh.as's variables
; Output:	the file's date, and its attributes
; Modifies:	everything
; Scratch:	none

set_date_attributes:
		call	no_date		; Z: no date to set
		jr	z,set_date_attributes.attributes_only
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
set_date_attributes.attributes_only:
		ld	a,(member_kind)
		cp	"d"
		ld	a,(lzh_attributes)
		jr	z,set_date_attributes.directory
		and	07h		; read-only, hidden, system
		ret	z
		or	20h		; and archive, which it has
		jr	set_date_attributes.attributes
set_date_attributes.directory:
		and	02h		; hidden
		ret	z
		ld	de,out_name	; added to what it has: the others
		xor	a		;   cannot be changed (.IATTR)
		dos	_ATTR		; get: L
		ld	a,l
		or	02h
set_date_attributes.attributes:
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

; print_path - the member's path, on standard output; a -lhd-
;   member's ends in "\".
;
; Input:	lzh_name, lzh_name_length, lzh_dir (lzh.as)
; Output:	the path is printed
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

print_path:
		printl	lzh_name,(lzh_name_length)
		ld	a,(lzh_dir)
		or	a
		ret	z
		print	msg_separator
		ret

; print_target - the member's path, and where it goes when that is
;   not the same: " as " and out_name's part, when a part of the path
;   had to be shortened.
;
; Input:	lzh.as's variables; out_member, names_changed (out_path)
; Output:	the path is printed
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

print_target:
		call	print_path
		ld	a,(names_changed)
		or	a
		ret	z
		print	msg_as
		ld	de,(out_member)
		call	print_zero
		ld	a,(lzh_dir)	; a directory's ends in "\"
		or	a
		ret	z
		print	msg_separator
		ret

; crc_tables, crc_start, crc_add, crc_check - the member's CRC, by
;   archive_format: CRC-16 for LZH, CRC-32 for ZIP.
;
;   crc_tables builds the table, once; crc_start starts a member's CRC
;   (0 for CRC-16, 0FFFFFFFFh for CRC-32); crc_add adds BC bytes at DE;
;   crc_check compares it with the header's (CRC-32's complemented).
;
; Input:	archive_format; lzh_crc, zip_crc
; Output:	crc_check: Z set = it matches
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

crc_tables:
		ld	a,(archive_format)
		or	a
		jp	z,crc_init
		jp	crc32_init

crc_start:
		ld	a,(archive_format)
		or	a
		ld	hl,0
		jr	z,crc_start.lzh
		dec	hl		; 0FFFFh
		ld	(crc32_value),hl
		ld	(crc32_value+2),hl
		ret
crc_start.lzh:
		ld	(crc_value),hl
		ret

crc_add:
		ld	a,(archive_format)
		or	a
		jp	z,crc_update
		jp	crc32_update

crc_check:
		ld	a,(archive_format)
		or	a
		jr	nz,crc_check.zip
		ld	hl,(crc_value)
		ld	de,(lzh_crc)
		or	a
		sbc	hl,de
		ret
crc_check.zip:
		ld	hl,crc32_value	; its complement, byte by byte
		ld	de,zip_crc
		ld	b,4
crc_check.byte:
		ld	a,(hl)
		cpl
		ex	de,hl
		cp	(hl)
		ex	de,hl
		ret	nz
		inc	hl
		inc	de
		djnz	crc_check.byte
		ret			; Z set

; print_method - the member's method, for "not supported yet": LZH's
;   5 characters, or ZIP's name without the spaces after it.
;
; Input:	lzh_method, zip_method; archive_format
; Output:	the method is printed
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

print_method:
		ld	a,(archive_format)
		or	a
		jr	nz,print_method.zip
		printl	lzh_method,5
		ret
print_method.zip:
		ld	hl,zip_method+7	; B = its length, the spaces off
		ld	b,7
print_method.trim:
		dec	hl
		ld	a,(hl)
		cp	CHR_SPACE
		jr	nz,print_method.print
		djnz	print_method.trim
print_method.print:
		ld	l,b
		ld	h,0
		ld	de,zip_method
		jp	print_length

; open_archive - open the archive named in archive_name, and tell its
;   format by its first bytes.
;
;   "PK" 3 4, a local header, or "PK" 5 6, the end record of an empty
;   archive, is ZIP: zip_open finds its central directory, reading the
;   end of the file into copy_buffer. Anything else, a file shorter than
;   4 bytes included, is read as LZH, from its start.
;
; Input:	archive_name
; Output:	A = 0, ready for the first member
;		A = what lzh_open, lzh_read or zip_open gave
;		archive_format: 0 for LZH, 1 for ZIP
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

open_archive:
		xor	a
		ld	(archive_format),a
		ld	de,archive_name
		call	lzh_open
		or	a
		ret	nz
		ld	de,copy_buffer	; its first 4 bytes
		ld	hl,4
		call	lzh_read
		cp	LZH_TRUNCATED
		jr	z,open_archive.lzh	; fewer: not ZIP
		or	a
		ret	nz
		ld	hl,copy_buffer
		ld	a,(hl)
		cp	"P"
		jr	nz,open_archive.lzh
		inc	hl
		ld	a,(hl)
		cp	"K"
		jr	nz,open_archive.lzh
		inc	hl
		ld	a,(hl)
		inc	hl
		cp	3
		jr	nz,open_archive.empty
		ld	a,(hl)
		cp	4
		jr	z,open_archive.zip
		jr	open_archive.lzh
open_archive.empty:
		cp	5
		jr	nz,open_archive.lzh
		ld	a,(hl)
		cp	6
		jr	nz,open_archive.lzh
open_archive.zip:
		ld	a,1
		ld	(archive_format),a
		ld	de,copy_buffer
		jp	zip_open
open_archive.lzh:
		jp	lzh_rewind

; next_member, skip_member, rewind_archive - lzh.as's or zip.as's
;   lzh_next_header, lzh_skip_data and lzh_rewind, by archive_format.
;
; Input:	archive_format
; Output:	as the routine's
; Modifies:	as the routine's
; Scratch:	none

next_member:
		ld	a,(archive_format)
		or	a
		jp	z,lzh_next_header
		jp	zip_next

skip_member:
		ld	a,(archive_format)
		or	a
		jp	z,lzh_skip_data
		jp	zip_skip

rewind_archive:
		ld	a,(archive_format)
		or	a
		jp	z,lzh_rewind
		jp	zip_rewind

; print_member - one line of the listing: the member just read.
;
;   The line is built in line_text: the packed and original sizes, 10
;   digits wide; the method; the date, or spaces for one MS-DOS cannot
;   hold (no_date); then the path, printed after it by print_path, since
;   it may hold a "$".
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
		ld	hl,lzh_method	; the method: LZH's 5 characters, or
		ld	bc,5		;   ZIP's first 6
		ld	a,(archive_format)
		or	a
		jr	z,print_member.method
		ld	hl,zip_method
		ld	bc,6
print_member.method:
		ld	de,line_text+22
		ldir
		call	no_date		; Z: spaces for the date
		jr	z,print_member.blank
		ld	hl,date_mask	; the separators, then the digits
		ld	de,line_text+DATE_AT
		ld	bc,16
		ldir
		call	format_date
		jr	print_member.dated
print_member.blank:
		ld	hl,line_text+DATE_AT
		ld	b,16
print_member.space:
		ld	(hl),CHR_SPACE
		inc	hl
		djnz	print_member.space
print_member.dated:
		printl	line_text,LINE_FIXED
		call	print_path
		print	msg_crlf
		ret

; no_date - whether the member's date is one MS-DOS cannot hold.
;
;   Only levels 0 and 1 can say so, with MS-DOS's date word: a day of 0,
;   or a month of 0 or over 12. PMARC2 writes 0, which is both.
;
; Input:	lzh_level, lzh_time (lzh.as)
; Output:	Z set = no date
; Modifies:	AF
;		C
;		HL
; Scratch:	none

no_date:
		ld	a,(lzh_level)	; level 2: seconds, always a date
		cp	2
		jr	z,no_date.dated
		ld	hl,(lzh_time+2)	; the date word
		ld	a,l		; the day: bits 4 to 0
		and	1Fh
		ret	z
		ld	a,l		; the month: bits 8 to 5
		rlca
		rlca
		rlca
		and	7
		ld	c,a
		ld	a,h
		and	1
		add	a,a
		add	a,a
		add	a,a
		or	c
		ret	z
		cp	13
		jr	nc,no_date.none
no_date.dated:
		or	1		; Z clear
		ret
no_date.none:
		xor	a		; Z set
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
; Input:	total_packed, total_original, listed
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
		ld	hl,(listed)
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
		ld	hl,(listed)
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
; msg_empty		a ZIP archive with no members
; msg_split		ZIP64, or a split archive
; msg_list_head		the listing's heading
; msg_list_foot		the rule above the totals
; msg_file		after a count of 1
; msg_files		after any other count
; month_lengths		the days in each month, February at 28
; msg_extracting, msg_skipping, msg_ok, msg_crc_error, msg_exists,
; msg_colon, msg_not_yet, msg_separator, msg_as, msg_encrypted
;			extracting's words, put together per member
; method_lh0		the one method extracted in this phase
; date_mask		print_member: the date's separators, before
;			format_date writes its digits
; msg_space_need, msg_space_free, msg_space_on, msg_space_drive
;			the shortage, with the amounts and the drive
;			between them; check_space writes the letter
; msg_kb, msg_mb, mb_digit	print_size's units; it writes the tenths
; msg_not_extracted	not_extracted's line, before the name
; msg_not_in		report_unmatched's line, before the name
; msg_data_error		a member whose compressed data is not valid
; msg_mem_need, msg_mem_free, msg_mem_end
;			the mapper's shortage, around its two amounts
; window_segs		the window's segments, -lh4- to -lh7-, as
;			lh5.as allocates them
; msg_no_mapper		heapinit found no mapper support
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
		defb	"Not an LZH or ZIP archive."
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
msg_empty:
		defb	"The archive is empty."
		defb	CHR_CR,CHR_LF,"$"
msg_split:
		defb	"ZIP64 and split archives are not read."
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
msg_separator:	defb	PATH_SEPARATOR,"$"
msg_as:		defb	" as $"
msg_not_yet:	defb	" is not supported yet",CHR_CR,CHR_LF,"$"
msg_encrypted:	defb	": it is encrypted",CHR_CR,CHR_LF,"$"
method_lh0:	defb	"-lh0-"
date_mask:	defb	"0000-00-00 00:00"
msg_space_need:	defb	"Extracting this archive would take $"
msg_space_free:	defb	" on disk, but only $"
msg_space_on:	defb	" are free on $"
msg_space_drive:
		defb	"A:.",CHR_CR,CHR_LF,"$"
msg_kb:		defb	" KB$"
msg_mb:		defb	"."
mb_digit:	defb	"0 MB$"
msg_not_extracted:
		defb	"Not extracted $"
msg_not_in:	defb	"Not in the archive: $"
msg_data_error:	defb	" data error",CHR_CR,CHR_LF,"$"
msg_mem_need:	defb	"Extracting this archive needs $"
msg_mem_free:	defb	" of mapper memory, but only $"
msg_mem_end:	defb	" are free.",CHR_CR,CHR_LF,"$"
window_segs:	defb	1,1,2,4
msg_no_mapper:	defb	"UNKAGO needs MSX-DOS2's mapper support."
		defb	CHR_CR,CHR_LF,"$"

		dseg

; Variables for main and list_archive:
;
; archive_name		the archive's name, from the command line, and a 0
; archive_format	0 for LZH, 1 for ZIP: open_archive
; members		how many members have been read
; listed		how many of them were listed
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
; out_name		its name, zero-terminated, with dest_path: 384
;			bytes, in the buffers segment
; out_member		where the member's path starts in out_name
; remaining		its data still to copy, 4 bytes
; chunk			the bytes in copy_buffer this time round
; dest_path		/D:'s path, zero-terminated; empty without /D
; dest_mode		walk_parts: 0 counts directories, 1 creates them
; dest_error		walk_parts: the first error creating them
; walk_path, walk_end	walk_parts: the path, and where the walk ends
; dirs_end		member_dirs: the end of the member's directories
; dirs_shared		member_dirs: where those not shared start
; last_dir, last_length	member_dirs: the directories of the member
;			before, in the buffers segment, and how long
; dest_letter		the drive extracted to, for the message
; new_dirs		the directories the extraction will create
; cluster_shift		log2 of the cluster's size, in bytes
; free_clusters		_ALLOC's free clusters
; need_clusters		what the extraction takes, 4 bytes
; stop_code		not_extracted: what stopped the extraction
; walked		not_extracted: the members walked again
; member_kind		the member's method's letter: "0", "1", "4" to
;			"7", or "d", as member_supported found it; "2"
;			for -pm2-, "p" for -pm1-
; need_segs		check_space: the largest window, in segments;
;			check_memory: and the tables'
; free_segs		mapfree's free segments
; name_list		the member names given: a flag, the name, a 0
; name_count		how many
; match_end, match_star, match_from
;			match_name: the end of the member's name, what
;			follows the last "*", where that "*" starts
; match_given		match_path: the name given
; size_round, size_value, size_text
;			print_size: rounding up or not, the amount in
;			tenths, and the number, 10 wide
; copy_buffer		the data, COPY_SIZE bytes at a time, in the
;			buffers segment, which the program file does not
;			carry
;
archive_name:	defs	128
members:	defs	2
archive_format:	defs	1
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
remaining:	defs	4
chunk:	defs	2
dest_path:	defs	128
dest_mode:	defs	1
dest_error:	defs	1
walk_path:	defs	2
walk_end:	defs	2
dirs_end:	defs	2
dirs_shared:	defs	2
last_length:	defs	1
out_member:	defs	2
dest_letter:	defs	1
new_dirs:	defs	2
cluster_shift:	defs	1
free_clusters:	defs	2
need_clusters:	defs	4
stop_code:	defs	1
walked:	defs	2
size_round:	defs	1
size_value:	defs	4
size_text:	defs	10
listed:	defs	2
member_kind:	defs	1
need_segs:	defs	1
free_segs:	defs	2
name_list:	defs	192
name_count:	defs	1
match_end:	defs	2
match_star:	defs	2
match_from:	defs	2
match_given:	defs	2

		dseg	buffers
copy_buffer:	defs	COPY_SIZE
out_name:	defs	384
last_dir:	defs	255

		end	main
