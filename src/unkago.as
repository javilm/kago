; unkago.as - UNKAGO, the decompressor. Phase 2: it lists LZH archives,
; and extracts their stored members.
;
; It checks for MSX-DOS2 and the command line. With /L it lists the
; members of an LZH archive: sizes, method, date and name, one line
; each, and the totals. Without it, it extracts the -lh0- (stored) and
; -lh5- (lh5.as) members into
; the current directory, or the one /D: names, checking first that they
; fit and then each one's CRC-16. Names after the archive's, with * and
; ?, choose the members, for listing and extracting alike. On the
; screen, each member's line shows how far through it UNKAGO is.

		include	common.inc	; common.as's routines, and print
		include	lzh.inc		; lzh.as: reading the archive
		include	crc.inc		; crc.as: the CRC-16
		include	lh5.inc		; lh5.as: the -lh5- decoder

		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	errors.inc	; .IOPT, .NOPAR, .FILEX, .DKFUL...
		include	ascii.inc	; CHR_CR, CHR_LF, CHR_SPACE

LINE_FIXED	equ	46		; a listing line before the name
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
;   lzh.as reads the headers; this prints a heading before the first
;   member, a line for each (print_member), and the totals after the
;   last (print_totals), and decides what each result means here. A
;   listing cut short by a damaged or truncated archive ends with the
;   message instead of the totals. An archive in which not a single
;   member could be read is not an LZH archive, unless the first
;   header is level 3: that is one, and the level is what is reported.
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
		ld	de,archive_name
		call	lzh_open
		or	a
		jp	nz,list_archive.dos_error	; not found, say
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
		call	lzh_next_header
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
;   First check_space walks the archive and stops unless it all fits;
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
		ld	de,archive_name
		call	lzh_open
		or	a
		jp	nz,report_stop	; not found, say
		call	check_space	; returns only if it all fits
		ld	a,1
		ld	(dest_mode),a	; walk_dest: create
		xor	a
		ld	(dest_error),a
		call	walk_dest
		ld	a,(dest_error)
		or	a
		jp	nz,report_stop	; one could not be created
		call	lzh_rewind
		or	a
		jp	nz,report_stop
		call	progress_init	; on the screen, not with /Q
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
		jp	not_extracted	; the rest, then why

; extract_member - extract, or skip, the member just read.
;
;   A member not asked for is passed over without a line. Only -lh0-
;   (stored) members are extracted in this phase. The file,
;   dest_path and the member's name, is created with _CREATE's "create
;   new" flag unless /O was given, so an existing file is never replaced
;   by accident: MSX-DOS2 refuses with .FILEX. The data is copied
;   through copy_buffer, COPY_SIZE bytes at a time, its CRC-16 computed
;   on the way; the file is closed, and only then are its date and
;   attributes set (closing a written file gives it the current date).
;   On the screen the line shows the percentage as the data is copied
;   (progress_start, progress_update), cleared before the last word
;   (progress_end). A CRC that does not match deletes the file. A full
;   disk or root
;   directory stops, where any other refusal to create only skips.
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
		jp	nz,lzh_skip_data	; not asked for: no line
		call	member_supported	; Z: -lh0-
		jp	nz,extract_member.unsupported	; too far for jr
		ld	hl,dest_path	; out_name: dest_path, a "\" if it
		ld	de,out_name	;   needs one, then the name
		ld	a,(hl)
		or	a
		jr	z,extract_member.name	; no /D
extract_member.path:
		ldi
		ld	a,(hl)
		or	a
		jr	nz,extract_member.path
		dec	de
		ld	a,(de)		; the path's last character
		inc	de
		cp	":"
		jr	z,extract_member.name
		cp	PATH_SEPARATOR
		jr	z,extract_member.name
		ld	a,PATH_SEPARATOR
		ld	(de),a
		inc	de
extract_member.name:
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
		jp	z,extract_member.created	; too far for jr
		cp	.DKFUL		; no room: stop, not skip
		ret	z
		cp	.DRFUL
		ret	z
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
		call	progress_start	; "   0%", on the screen
		ld	hl,0
		ld	(crc_value),hl
		ld	hl,(lzh_packed)	; -lh0-: the data's size
		ld	de,(lzh_packed+2)
		ld	a,(member_kind)
		cp	"5"
		jr	nz,extract_member.sized
		ld	hl,(lzh_original)	; -lh5-: what it unpacks to
		ld	de,(lzh_original+2)
extract_member.sized:
		ld	(remaining),hl
		ld	(remaining+2),de
		jr	nz,extract_member.copy	; Z still from the CP
		ld	de,copy_buffer	; the window
		call	lh5_start	; A = 0, or .NORAM
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
		cp	"5"
		jr	z,extract_member.decode
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
		call	crc_update
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
		call	progress_update
		jr	extract_member.copy
extract_member.copied:
		ld	a,(member_kind)
		cp	"5"
		jr	nz,extract_member.close	; -lh0-: all of it was read
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
		ld	hl,(crc_value)
		ld	de,(lzh_crc)
		or	a
		sbc	hl,de
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
;   extracts: -lh0- (stored) or -lh5-.
;
; Input:	lzh_method (lzh.as)
; Output:	Z set = it is, and then
;		A = member_kind = "0" or "5"
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

member_supported:
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
		cp	"5"
		ret			; Z set: -lh5-

; check_space - stop, saying why, unless the extraction fits.
;
;   The archive is walked once, and each member that will be extracted
;   counts its original size, rounded up to whole clusters; a 0-byte
;   file takes none. Each directory /D: will create takes one cluster
;   more. The cluster's size and the free clusters come from _ALLOC,
;   for the drive /D: names or the current one.
;
;   A file that exists already counts in full, though without /O it is
;   skipped and with /O it frees its own space: the estimate errs on the
;   safe side. A walk that fails (a damaged or cut-off archive, a read
;   error) ends here, through report_stop, with nothing written.
;
; Input:	the archive open, at its start
;		dest_path
; Output:	returns only if it fits
;		cluster_shift: log2 of the cluster's size in bytes
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
		ld	hl,(new_dirs)	; a cluster for each directory
		ld	(need_clusters),hl
		ld	hl,0
		ld	(need_clusters+2),hl
		ld	(members),hl
check_space.next:
		call	lzh_next_header
		or	a
		jr	nz,check_space.end
		ld	hl,(members)
		inc	hl
		ld	(members),hl
		call	member_selected	; Z: asked for
		jr	nz,check_space.skip
		call	member_supported	; Z: it will be extracted
		jr	nz,check_space.skip
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
check_space.skip:
		call	lzh_skip_data
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
		ld	hl,(need_clusters+2)
		ld	a,h
		or	l
		jr	nz,check_space.short	; 64K clusters or more
		ld	hl,(free_clusters)
		ld	de,(need_clusters)
		or	a
		sbc	hl,de
		ret	nc		; it fits
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
;   With dest_mode 0, a directory _ATTR cannot find adds 1 to new_dirs;
;   with dest_mode 1 it is created with _CREATE, one that is there
;   already (.DIRX) being no error. The first other error is kept in
;   dest_error, and the walk goes on. The drive and a leading "\" are
;   not directories to make, and neither is an empty part, as in a path
;   ending in "\".
;
; Input:	dest_path
;		dest_mode
; Output:	new_dirs, counted; or the directories, and dest_error
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

walk_dest:
		ld	hl,dest_path
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
		ld	d,h		; DE -> where this part starts
		ld	e,l
walk_dest.scan:
		ld	a,(hl)
		or	a
		jr	z,walk_dest.part	; the last part, then return
		cp	PATH_SEPARATOR
		jr	z,walk_dest.more
		inc	hl
		jr	walk_dest.scan
walk_dest.more:
		call	walk_dest.part
		inc	hl
		jr	walk_dest.start
walk_dest.part:
		or	a		; HL -> its end, DE -> its start
		sbc	hl,de
		add	hl,de		; Z from the SBC: empty
		ret	z
		push	hl
		ld	a,(hl)
		push	af
		ld	(hl),0		; the path down to here
		ld	de,dest_path
		ld	a,(dest_mode)
		or	a
		jr	nz,walk_dest.create
		dos	_ATTR		; A = 0: get
		or	a
		jr	z,walk_dest.restore	; it is there
		ld	hl,(new_dirs)
		inc	hl
		ld	(new_dirs),hl
		jr	walk_dest.restore
walk_dest.create:
		ld	b,10h		; a subdirectory
		dos	_CREATE
		or	a
		jr	z,walk_dest.restore
		cp	.DIRX
		jr	z,walk_dest.restore	; it was there
		ld	c,a
		ld	a,(dest_error)
		or	a
		jr	nz,walk_dest.restore	; keep the first
		ld	a,c
		ld	(dest_error),a
walk_dest.restore:
		pop	af
		pop	hl
		ld	(hl),a
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
		call	lzh_rewind
		or	a
		jr	nz,not_extracted.done
		ld	hl,0
		ld	(walked),hl
not_extracted.next:
		call	lzh_next_header
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
		printl	lzh_name,(lzh_name_length)
		print	msg_crlf
not_extracted.skip:
		call	lzh_skip_data
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
; Output:	Z set = it was asked for
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
		ld	hl,lzh_name
		ld	bc,(lzh_name_length)
		call	match_name	; Z: it matches
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

; fold_case - a-z to A-Z.
;
; Input:	A
; Output:	A, upper case if it was a lower case letter
; Modifies:	AF
; Scratch:	none

fold_case:
		cp	"a"
		ret	c
		cp	"z"+1
		ret	nc
		sub	"a"-"A"
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
; progress_init - whether extracting shows its progress.
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

; progress_start - the first percentage, after "Extracting NAME".
;
;   One per cent of the member's data is worked out here, once: every
;   later update only adds. A member under 100 bytes has 0 bytes per per
;   cent, and goes straight to 100 at its first update.
;
; Input:	lzh_original (lzh.as), progress
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
		ld	hl,(lzh_original)
		ld	de,(lzh_original+2)
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
;   copied grows by chunk; while it has reached pct_next, pct goes up by
;   one and pct_next by pct_step. 100 is as far as it goes.
;
;   progress_number, its second entry, prints the number alone, as
;   " NNN%".
;
; Input:	chunk, and progress_start's variables
; Output:	the line, redrawn when the number changes
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

progress_update:
		ld	a,(progress)
		or	a
		ret	z
		ld	hl,(copied)
		ld	de,(chunk)
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
;   to the left edge, "Extracting " and the name.
;
; Input:	progress
; Output:	the cursor just after "Extracting NAME"
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

progress_end:
		ld	a,(progress)
		or	a
		ret	z
		call	progress_prefix
		print	msg_blank	; over the number
progress_prefix:
		print	msg_cr		; back to the line's start
		print	msg_extracting
		printl	lzh_name,(lzh_name_length)
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
; msg_list_head		the listing's heading
; msg_list_foot		the rule above the totals
; msg_file		after a count of 1
; msg_files		after any other count
; month_lengths		the days in each month, February at 28
; msg_extracting, msg_skipping, msg_ok, msg_crc_error, msg_exists,
; msg_colon, msg_not_yet	extracting's words, put together per member
; method_lh0		the one method extracted in this phase
; msg_space_need, msg_space_free, msg_space_on, msg_space_drive
;			the shortage, with the amounts and the drive
;			between them; check_space writes the letter
; msg_kb, msg_mb, mb_digit	print_size's units; it writes the tenths
; msg_not_extracted	not_extracted's line, before the name
; msg_not_in		report_unmatched's line, before the name
; msg_data_error		a member whose -lh5- data is not valid
; msg_no_mapper		heapinit found no mapper support
; msg_cr, msg_blank, pct_text
;			the progress line: back to its start, five
;			spaces over the number, the number; progress_number
;			writes its digits
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
msg_no_mapper:	defb	"UNKAGO needs MSX-DOS2's mapper support."
		defb	CHR_CR,CHR_LF,"$"
msg_cr:		defb	CHR_CR,"$"
msg_blank:	defb	"     $"
pct_text:	defb	"   0%$"

		dseg

; Variables for main and list_archive:
;
; archive_name		the archive's name, from the command line, and a 0
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
; remaining		its data still to copy, 4 bytes
; chunk			the bytes in copy_buffer this time round
; dest_path		/D:'s path, zero-terminated; empty without /D
; dest_mode		walk_dest: 0 counts directories, 1 creates them
; dest_error		walk_dest: the first error creating them
; dest_letter		the drive extracted to, for the message
; new_dirs		the directories /D: will create
; cluster_shift		log2 of the cluster's size, in bytes
; free_clusters		_ALLOC's free clusters
; need_clusters		what the extraction takes, 4 bytes
; stop_code		not_extracted: what stopped the extraction
; walked		not_extracted: the members walked again
; member_kind		"0" or "5": the member's method, as
;			member_supported found it
; progress		not 0 to show progress
; pct			the percentage on the screen
; pct_step		the bytes in one per cent, 4 bytes
; pct_next		where the next per cent is reached, 4 bytes
; copied		the member's bytes copied so far, 4 bytes
; name_list		the member names given: a flag, the name, a 0
; name_count		how many
; match_end, match_star, match_from
;			match_name: the end of the member's name, what
;			follows the last "*", where that "*" starts
; size_round, size_value, size_text
;			print_size: rounding up or not, the amount in
;			tenths, and the number, 10 wide
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
remaining:	defs	4
chunk:	defs	2
dest_path:	defs	128
dest_mode:	defs	1
dest_error:	defs	1
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
progress:	defs	1
pct:	defs	1
pct_step:	defs	4
pct_next:	defs	4
copied:	defs	4
name_list:	defs	192
name_count:	defs	1
match_end:	defs	2
match_star:	defs	2
match_from:	defs	2

		dseg	buffers
copy_buffer:	defs	COPY_SIZE
out_name:	defs	384

		end	main
