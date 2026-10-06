; kago.as - KAGO, the compressor. It writes LZH and ZIP archives, every
; member stored, of the files and directory trees named on the command
; line, and with /A adds to an LZH or ZIP archive that is there.
;
; It checks for MSX-DOS2 and the command line, and chooses the format:
; /F: names it, or the archive's extension does. LZH and ZIP are
; written; PMA says so. The archive is created new: one that exists
; already is refused, unless /A asks to add to it (open_old). Then the
; archive is made again as a temporary file beside it: the old members
; are copied first, byte for byte, but for those a file named replaces
; (copy_old); then the files; then the old archive is deleted, and the
; new one renamed into its place. Each word after the archive's name is
; a file, *
; and ? allowed, found with MSX-DOS2's _FFIRST and _FNEXT; each file
; found is added, its path as typed less the drive (word_dirs), its
; date, time and attributes, its data stored and its CRC computed on
; the way: CRC-16 for LZH, CRC-32 for ZIP. The header goes in front of
; the data, written again once the CRC and the size are known (lzhw.as
; makes LZH's, zipw.as ZIP's). A ZIP archive ends with its central
; directory, kept in mapper segments until then. A directory found is
; added whole: a -lhd- member, then everything in it, at every depth
; (add_tree). The archive itself, if a name matches it, is passed over,
; and so is a path added already in this run (path_check).
; An archive nothing was added to is deleted. Any MSX-DOS error stops,
; the archive deleted.

		include	common.inc	; common.as's routines, and print
		include	crc.inc		; crc.as: the CRC-16
		include	lzhw.inc	; lzhw.as: the member's header
		include	zipw.inc	; zipw.as: ZIP's headers
		include	progress.inc	; progress.as: the progress line
		include	seglist.inc	; seglist.as: lists in the mapper
		include	lzh.inc		; lzh.as: reading the old archive
		include	zip.inc		; zip.as: reading an old ZIP one

		include	msxdos.inc	; BDOS, the function numbers, "system"
		include	errors.inc	; .IOPT, .NOPAR, .FILEX, .NOFIL...
		include	ascii.inc	; CHR_CR, CHR_LF

COPY_SIZE	equ	8192		; copy_buffer: what is read and
					;   written at a time
PATH_SEPARATOR	equ	5Ch		; "\", the yen sign on a Japanese MSX
FIB_NAME	equ	1		; a FIB, as _FFIRST fills it in: the
FIB_ATTRIBUTES	equ	14		;   name, zero-terminated; the
FIB_TIME	equ	15		;   attributes; the time and the
FIB_CLUSTER	equ	19		;   date words; the first cluster;
FIB_SIZE	equ	21		;   the size, 4 bytes; the drive
FIB_DRIVE	equ	25
MAX_DEPTH	equ	32		; add_tree's depth: MSX-DOS2's paths
					;   are 63 characters at most, so 31
					;   directories deep
FORMAT_LZH	equ	0		; format_name's answers
FORMAT_PMA	equ	1
FORMAT_ZIP	equ	2
MARK_ADDED	equ	1		; a path's marks in path_list: added
MARK_OLD	equ	2		;   in this run; in the old archive

		cseg

; main - the entry point, where MSX-DOS2 starts the program.
;
;   A bad switch ends with .IOPT, and COMMAND2 prints its own message
;   for it: *** Invalid option. Otherwise /? prints the usage, /V the
;   banner alone; /? is tested before /V, so with both the usage wins.
;
;   Then the archive: the first word that is not a switch, and its
;   format (archive_format). With no archive named, the usage; with no
;   file named after it, .NOPAR (*** Missing parameter). The words after
;   it are added one by one (add_words). An LZH archive ends with a 0
;   byte; a ZIP archive with its central directory and end record.
;
;   With /A and an archive there, the words are walked twice: first only
;   for their paths (collecting), so that copy_old knows which old
;   members to leave out; then to add them. At the end the old archive
;   is deleted, and the new one, written as temp_name, renamed into its
;   place; if either fails, the new one is left, and KAGO says where.
;
; Input:	the command line, at COMMAND_TAIL (common.as)
; Output:	does not return
; Modifies:	everything
; Scratch:	none

main:
		call	dos_version	; CY set = not MSX-DOS2
		jp	c,main.need_dos2	; too far for jr
		call	heapinit	; MapperHeap: CY set = no mapper
		jp	c,main.no_mapper	; too far for jr
		ld	hl,switch_letters
		call	find_bad_switch	; CY set = a switch it does not take
		jp	c,main.bad_switch	; too far for jr
		ld	c,"?"
		call	switch_given
		jp	c,main.usage	; too far for jr
		ld	c,"V"
		call	switch_given
		jr	nc,main.archive
		print	msg_banner	; /V: the banner, and nothing else
		dos	_TERM0

main.archive:
		call	first_argument	; A = 0: no archive named
		or	a
		jp	z,main.usage	; too far for jr
		ld	de,archive_name	; B bytes from HL, then a 0
		ld	c,b
		ld	b,0
		ldir
		xor	a
		ld	(de),a
		ld	(files_at),hl	; HL -> just after it: the files
		call	archive_format	; returns only for LZH and ZIP
		ld	de,(files_at)
		call	next_argument	; A = 0: no file named
		or	a
		jr	nz,main.files
		ld	b,.NOPAR	; COMMAND2: *** Missing parameter
		dos	_TERM
main.files:
		call	open_old	; /A and an archive there: opened
		call	create_archive	; returns only if it was
		call	progress_init	; on the screen, not with /Q
		ld	hl,adding_line	; what the line starts with
		ld	(progress_line),hl
		call	crc_tables	; CRC-16's table, or CRC-32's
		ld	hl,0
		ld	(added),hl
		ld	a,(appending)
		or	a
		jr	z,main.add
		inc	a		; /A: the paths to be added, first
		ld	(collecting),a
		call	add_words
		xor	a
		ld	(collecting),a
		call	copy_old	; the old members kept
main.add:
		call	add_words
main.done:
		ld	hl,(added)
		ld	a,h
		or	l
		jp	z,main.nothing	; too far for jr
		ld	a,(out_format)
		or	a
		jr	nz,main.central
		ld	de,end_mark	; LZH: the end of the archive, a 0
		ld	hl,1
		call	archive_write
		jr	main.close
main.central:
		ld	a,1		; ZIP: the central directory, here
		ld	de,0
		ld	h,d
		ld	l,e
		call	archive_seek	; DE:HL = where it starts
		ld	(zipw_at),hl
		ld	(zipw_at+2),de
main.copy:
		ld	de,copy_buffer
		ld	bc,COPY_SIZE
		call	zipw_copy	; HL = how many bytes, 0 at the end
		ld	a,h
		or	l
		jr	z,main.end_record
		ld	de,copy_buffer
		call	archive_write
		jr	main.copy
main.end_record:
		call	zipw_end	; then the end record: with /A,
		ld	bc,(zip_comment)	;   the old comment's length
		push	hl
		ld	hl,20
		add	hl,de
		ld	(hl),c
		inc	hl
		ld	(hl),b
		pop	hl
		call	archive_write
		ld	hl,(zip_comment)	; and the comment, from its end
		ld	a,h
		or	l
		jr	z,main.close
		ld	(old_len),hl
		ld	hl,0
		ld	(old_len+2),hl
		ld	hl,(lzh_size)
		ld	de,(zip_comment)
		or	a
		sbc	hl,de
		ld	(old_at),hl
		ld	hl,(lzh_size+2)
		ld	de,0
		sbc	hl,de
		ld	(old_at+2),hl
		call	copy_range
main.close:
		ld	a,(archive_handle)
		ld	b,a
		dos	_CLOSE
		or	a
		jp	nz,fail_closed
		ld	a,(appending)
		or	a
		jr	nz,main.replace
		dos	_TERM0
main.replace:
		ld	a,(lzh_handle)	; /A: the old archive closed, deleted
		ld	b,a
		dos	_CLOSE
		ld	de,archive_name
		dos	_DELETE
		or	a
		jr	nz,main.left
		ld	de,temp_name	; and the new one in its place
		ld	hl,old_entry
		dos	_RENAME
		or	a
		jr	nz,main.left
		dos	_TERM0
main.left:
		push	af		; A = why: the new one is left as it is
		print	msg_left
		ld	de,temp_name
		call	print_zero
		print	msg_crlf
		pop	af
		ld	b,a
		dos	_TERM
main.nothing:
		ld	a,(archive_handle)	; nothing added: no archive
		ld	b,a
		dos	_CLOSE
		ld	de,(write_name)
		dos	_DELETE
		print	msg_nothing
		ld	de,archive_name
		call	print_zero
		ld	de,msg_not_written
		ld	a,(appending)	; /A: the old one is as it was
		or	a
		jr	z,main.said
		ld	de,msg_not_changed
main.said:
		dos	_STROUT
		dos	_TERM0

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

; archive_format - the archive's format, from /F: or the extension.
;
;   /F: takes LZH, PMA or ZIP, in either case. Without it the archive
;   name's last four characters decide: .LZH or .LHA, .PMA, .ZIP. PMA
;   is not written yet: it ends the program saying so, as do a value
;   /F: does not take and a name that says no format.
;
; Input:	archive_name
; Output:	returns only for LZH and ZIP
;		out_format = FORMAT_LZH or FORMAT_ZIP
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

archive_format:
		ld	c,"F"
		call	switch_value	; CY set: HL -> it, B = its length
		jr	nc,archive_format.extension
		ld	a,b		; ":" and three letters
		cp	4
		jr	nz,archive_format.unknown
		ld	a,(hl)
		cp	":"
		jr	nz,archive_format.unknown
		inc	hl
		call	format_name	; Z: A = the format
		jr	nz,archive_format.unknown
		jr	archive_format.chosen
archive_format.extension:
		ld	hl,archive_name	; HL -> its end
		ld	b,0		; B = its length
archive_format.end:
		ld	a,(hl)
		or	a
		jr	z,archive_format.ended
		inc	hl
		inc	b
		jr	archive_format.end
archive_format.ended:
		ld	a,b		; "." and three letters
		cp	4
		jr	c,archive_format.none
		ld	de,-4
		add	hl,de
		ld	a,(hl)
		cp	"."
		jr	nz,archive_format.none
		inc	hl
		call	format_name	; Z: A = the format
		jr	nz,archive_format.none
archive_format.chosen:
		ld	de,msg_no_pma
		cp	FORMAT_PMA
		jr	z,archive_format.say
		ld	(out_format),a	; LZH or ZIP
		ret
archive_format.unknown:
		ld	de,msg_bad_format
		jr	archive_format.say
archive_format.none:
		ld	de,msg_no_format
archive_format.say:
		dos	_STROUT
		dos	_TERM0

; format_name - which format three letters name.
;
; Input:	HL -> the three letters, in either case
; Output:	Z set = a format, and A = FORMAT_LZH, FORMAT_PMA or
;		FORMAT_ZIP
; Modifies:	AF
;		B
;		DE
; Scratch:	none

format_name:
		ld	de,format_table
format_name.entry:
		ld	a,(de)
		or	a
		jr	z,format_name.no	; the end of the table
		push	de
		push	hl
		ld	b,3
format_name.letter:
		ld	a,(hl)
		call	fold_case
		ex	de,hl
		cp	(hl)
		ex	de,hl
		jr	nz,format_name.differ
		inc	hl
		inc	de
		djnz	format_name.letter
		ld	a,(de)		; the format
		pop	hl
		pop	de
		cp	a		; Z set
		ret
format_name.differ:
		pop	hl
		pop	de
		inc	de		; the next entry: 3 letters, a format
		inc	de
		inc	de
		inc	de
		jr	format_name.entry
format_name.no:
		inc	a		; Z clear
		ret

; create_archive - create the archive, new, and find out where it is.
;
;   _CREATE's "create new" flag refuses an archive that exists, with
;   .FILEX, which is said in KAGO's own words, the name write_name's: the
;   archive's, or with /A the temporary file's; any other error ends the
;   program with its code. Then a byte is written and the archive is
;   flushed (_ENSURE), so that its directory entry has a first cluster:
;   that cluster, the drive and the name tell it apart from every other
;   file, should a name typed after it match it (add_entry). The byte
;   is written over later.
;
; Input:	write_name -> the name
; Output:	returns only if the archive was created
;		archive_handle, archive_drive, archive_cluster,
;		archive_entry
;		in_handle = 0FFh: no file open to read
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

create_archive:
		ld	a,0FFh
		ld	(in_handle),a
		ld	de,(write_name)
		xor	a		; open mode: read and write
		ld	b,80h		; create new
		dos	_CREATE		; B = the handle
		or	a
		jr	z,create_archive.created
		cp	.FILEX
		jr	nz,create_archive.error
		ld	de,(write_name)	; it exists
		call	print_zero
		print	msg_exists
		dos	_TERM0
create_archive.error:
		ld	b,a
		dos	_TERM
create_archive.created:
		ld	a,b
		ld	(archive_handle),a
		ld	de,end_mark	; a byte, so that it has a cluster
		ld	hl,1
		call	archive_write
		ld	a,(archive_handle)
		ld	b,a
		dos	_ENSURE		; its directory entry, written
		or	a
		jp	nz,fail
		ld	de,(write_name)
		ld	b,06h		; hidden and system ones too
		ld	ix,fib
		dos	_FFIRST
		or	a
		jp	nz,fail
		ld	a,(fib+FIB_DRIVE)
		ld	(archive_drive),a
		ld	hl,(fib+FIB_CLUSTER)
		ld	(archive_cluster),hl
		ld	hl,fib+FIB_NAME	; and its name, as MSX-DOS2 has it
		ld	de,archive_entry
		ld	bc,13
		ldir
		xor	a		; back to the start
		ld	d,a
		ld	e,a
		ld	h,a
		ld	l,a
		jp	archive_seek

; add_word - add the files one word on the command line names.
;
;   The word is a path, * and ? allowed in its last part. Its
;   directories become the start of each member's path (word_dirs); a
;   word with ".." in them is refused. Every entry _FFIRST and _FNEXT
;   find is passed to add_entry: files, directories, hidden and system
;   ones. A word that finds nothing, or that MSX-DOS2 refuses, is
;   reported with MSX-DOS2's reason; an error part of the way through
;   the search stops the program.
;
; Input:	spec_text: the word, zero-terminated
; Output:	the files, added
;		added: counted
; Modifies:	everything
; Scratch:	none

add_word:
		call	word_dirs	; CY set: ".." in them
		jr	c,add_word.refused
		ld	de,spec_text
		ld	b,16h		; hidden, system, directories
		ld	ix,fib
		dos	_FFIRST
		or	a
		jr	nz,add_word.none
add_word.entry:
		call	add_entry
		ld	ix,fib
		dos	_FNEXT
		or	a
		jr	z,add_word.entry
		cp	.NOFIL
		ret	z		; no more
		jp	fail
add_word.none:
		ld	b,a
		ld	a,(collecting)	; /A's first walk says nothing
		or	a
		ret	nz
		ld	a,b
		push	af
		print	msg_skipping
		ld	de,spec_text
		call	print_zero
		print	msg_colon
		pop	af
		call	print_explanation	; MSX-DOS2's reason
		print	msg_crlf
		ret
add_word.refused:
		ld	a,(collecting)	; /A's first walk says nothing
		or	a
		ret	nz
		print	msg_skipping
		ld	de,spec_text
		call	print_zero
		print	msg_dotdot
		ret

; add_entry - add the entry just found.
;
;   "." and "..", the archive itself and the one /A adds to are passed
;   over without a line; a directory is added whole (add_tree). In /A's
;   first walk, only its path is kept (path_collect). A file added
;   already in this run says so, and is not added again. A file is opened
;   through its FIB; its header is written as far as it is known (the
;   CRC still 0), then its data, COPY_SIZE bytes at a time, the CRC
;   computed and the bytes counted on the way; then the header again,
;   in its place, with the CRC and the size as read. On the screen the
;   line shows the percentage as the data is copied.
;
; Input:	fib: the entry
;		lzhw_dir: the word's directories (word_dirs)
; Output:	the member, added
;		added: one more
; Modifies:	everything
; Scratch:	none

add_entry:
		ld	a,(fib+FIB_ATTRIBUTES)
		and	10h		; a directory
		jp	nz,add_entry.directory	; too far for jr
		ld	hl,archive_drive	; the archive being written?
		call	same_file
		ret	z		; it is: passed over
		ld	a,(appending)	; the one /A adds to?
		or	a
		jr	z,add_entry.file
		ld	hl,old_drive
		call	same_file
		ret	z
add_entry.file:
		call	entry_path	; lzhw_path, lzhw_length
		ld	a,(collecting)	; /A's first walk: the path only
		or	a
		jp	nz,path_collect
		call	path_check	; CY: added already
		jp	c,already
		call	entry_details	; the size, for the line and for now
		ld	hl,method_lh0	; stored
		ld	de,lzhw_method
		ld	bc,5
		ldir
		ld	de,fib
		ld	a,1		; open mode: no writing
		dos	_OPEN		; B = the handle
		or	a
		jp	nz,fail
		ld	a,b
		ld	(in_handle),a
		call	write_header	; as far as it is known
		call	adding_line	; Adding, or Replacing, and the path
		ld	hl,(lzhw_size)
		ld	de,(lzhw_size+2)
		call	progress_start	; "   0%", on the screen
		call	crc_start	; the data's CRC
		ld	hl,0
		ld	(lzhw_size),hl	; and its size, as it is read
		ld	(lzhw_size+2),hl
add_entry.copy:
		ld	a,(in_handle)
		ld	b,a
		ld	de,copy_buffer
		ld	hl,COPY_SIZE
		dos	_READ		; HL = how many were read
		or	a
		jr	z,add_entry.read
		cp	.EOF
		jp	nz,fail
		jr	add_entry.copied	; nothing left
add_entry.read:
		ld	(chunk),hl
		ld	b,h
		ld	c,l
		ld	de,copy_buffer
		call	crc_add
		ld	de,copy_buffer
		ld	hl,(chunk)
		call	archive_write
		ld	hl,(lzhw_size)	; the size, counted
		ld	de,(chunk)
		add	hl,de
		ld	(lzhw_size),hl
		ld	hl,(lzhw_size+2)
		ld	de,0
		adc	hl,de
		ld	(lzhw_size+2),hl
		ld	hl,(chunk)
		call	progress_update
		jr	add_entry.copy
add_entry.copied:
		ld	a,(in_handle)
		ld	b,a
		dos	_CLOSE
		ld	a,0FFh
		ld	(in_handle),a
		call	crc_done	; lzhw_crc, or zipw_crc
		xor	a		; back to the header
		ld	hl,(header_at)
		ld	de,(header_at+2)
		call	archive_seek
		call	member_header	; the same length: only numbers changed
		call	archive_write
		ld	a,2		; on to the end again
		ld	de,0
		ld	h,d
		ld	l,e
		call	archive_seek
		call	keep_member	; ZIP: its central record
		call	progress_end	; the number off the line
		print	msg_ok
		ld	hl,(added)
		inc	hl
		ld	(added),hl
		ret
add_entry.directory:
		ld	a,(fib+FIB_NAME)	; "." and "..": passed over
		cp	"."
		ret	z		; and on into add_tree otherwise

; add_tree - add a directory: its own -lhd- member, then everything in
;   it, at every depth.
;
;   Its path is the directories so far and its name, then a "\": all of
;   it directories, the name empty, as LHA stores a directory. Then
;   everything in it is found as add_word finds a word's entries, with
;   _FFIRST given the directory's FIB and an empty name, and each entry
;   goes to add_entry, which comes back here for a directory inside it.
;   The FIB being searched is kept in fib_stack while that happens
;   (fib_push), and put back after (fib_pop), so the search goes on;
;   lzhw_dir, kept on the stack, is put back too. MSX-DOS2's paths of
;   63 characters at most keep it within MAX_DEPTH: deeper, _FFIRST
;   refuses, and the program stops on its error.
;
; Input:	fib: the directory
;		lzhw_path, lzhw_dir: the directories so far
; Output:	the directory, and all in it, added
;		added: counted
; Modifies:	everything
; Scratch:	none

add_tree:
		call	entry_path	; lzhw_path: the directories, the name
		ld	hl,(lzhw_length)	; then a "\"
		ld	de,lzhw_path
		add	hl,de
		ld	(hl),PATH_SEPARATOR
		ld	hl,(lzhw_length)
		inc	hl
		ld	(lzhw_length),hl
		ld	a,(lzhw_dir)	; the directories so far, for after
		push	af
		ld	a,l		; all of it directories now
		ld	(lzhw_dir),a
		ld	a,(collecting)	; /A's first walk: the path only
		or	a
		jr	z,add_tree.check
		call	path_collect
		jr	add_tree.inside
add_tree.check:
		call	path_check	; CY: added already
		jr	nc,add_tree.new
		call	already		; but what is in it may not be
		jr	add_tree.inside
add_tree.new:
		call	entry_details
		ld	hl,method_lhd
		ld	de,lzhw_method
		ld	bc,5
		ldir
		call	write_header	; no data: written once
		call	keep_member	; ZIP: its central record
		call	adding_line
		print	msg_ok
		ld	hl,(added)
		inc	hl
		ld	(added),hl
add_tree.inside:
		call	fib_push	; HL -> the directory's FIB, kept
		ex	de,hl
		ld	hl,no_name	; everything in it
		ld	b,16h		; hidden, system, directories
		ld	ix,fib
		dos	_FFIRST
add_tree.found:
		or	a
		jr	nz,add_tree.searched
		call	add_entry
		ld	ix,fib
		dos	_FNEXT
		jr	add_tree.found
add_tree.searched:
		cp	.NOFIL
		jp	nz,fail
		call	fib_pop		; the search it was found by, back
		pop	af
		ld	(lzhw_dir),a
		ret

; entry_details - the member's attributes, date, time and size, from
;   the FIB; its CRC 0, for now.
;
; Input:	fib
; Output:	lzhw_attr, lzhw_date, lzhw_size, lzhw_crc
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

entry_details:
		ld	a,(fib+FIB_ATTRIBUTES)
		ld	(lzhw_attr),a
		ld	hl,fib+FIB_TIME	; the time and the date
		ld	de,lzhw_date
		ld	bc,4
		ldir
		ld	hl,fib+FIB_SIZE
		ld	de,lzhw_size
		ld	bc,4
		ldir
		ld	hl,0
		ld	(lzhw_crc),hl
		ld	(zipw_crc),hl
		ld	(zipw_crc+2),hl
		ret

; write_header - the member's header, where the archive is now.
;
;   Where that is goes in header_at, to come back to, and in zipw_at,
;   for ZIP's central record.
;
; Input:	lzhw.as's variables; zipw_crc
; Output:	the header, written
;		header_at, zipw_at
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

write_header:
		ld	a,1		; here
		ld	de,0
		ld	h,d
		ld	l,e
		call	archive_seek	; DE:HL = where the archive is
		ld	(header_at),hl
		ld	(header_at+2),de
		ld	(zipw_at),hl
		ld	(zipw_at+2),de
		call	member_header
		jp	archive_write

; member_header - the member's header, LZH's or ZIP's, by out_format.
;
; Input:	out_format; lzhw.as's variables; zipw_crc
; Output:	DE -> it
;		HL = its length
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

member_header:
		ld	a,(out_format)
		or	a
		jp	z,lzhw_header
		jp	zipw_local

; keep_member - ZIP: the member's central record, kept for the end.
;
;   None is left in the mapper: KAGO stops (no_memory).
;
; Input:	out_format; lzhw.as's variables; zipw_crc, zipw_at
; Output:	returns only if it was kept, or for LZH
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

keep_member:
		ld	a,(out_format)
		or	a
		ret	z		; LZH: nothing to keep
		call	zipw_keep	; CY: no room
		ret	nc
		jp	no_memory

; path_check - whether the member's path was added already in this run,
;   and which word its line starts with.
;
;   The paths are kept in path_list, a list of records in mapper
;   segments (seglist.as): each its length, its marks, then the path.
;   All of them come from MSX-DOS2's names and the word's directories,
;   folded to upper case, with "\" between parts, so they are compared
;   byte for byte. A path already marked MARK_ADDED is a file named
;   twice: it is added once. One there unmarked, kept by /A's first walk
;   (path_collect), is marked now; if the old archive had it too
;   (path_mark_old), its line says "Replacing". One not there is kept,
;   marked.
;
; Input:	lzhw_path, lzhw_length
; Output:	CY set = it was added already
;		line_word -> msg_adding, or msg_replacing
;		returns only if it could be kept (no_memory)
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

path_check:
		ld	hl,msg_adding
		ld	(line_word),hl
		call	path_seen	; CY: HL -> its record, in page 2
		jr	nc,path_check.new
		inc	hl		; its marks
		ld	a,(hl)
		bit	0,a		; MARK_ADDED: added already
		scf
		ret	nz
		or	MARK_ADDED
		ld	(hl),a
		and	MARK_OLD	; CY clear
		ret	z
		ld	hl,msg_replacing	; the old archive had it
		ld	(line_word),hl
		ret
path_check.new:
		ld	a,MARK_ADDED
		jp	path_keep

; path_collect - /A's first walk: the path kept, unmarked, if it is
;   not there already.
;
; Input:	lzhw_path, lzhw_length
; Output:	path_list
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

path_collect:
		call	path_seen
		ret	c		; named twice: once is enough
		xor	a		; no marks
		jp	path_keep

; path_mark_old - whether an old member's path will be added: if so,
;   it is marked MARK_OLD, and the member is not copied.
;
; Input:	lzhw_path, lzhw_length: the old member's, as old_path
;		made it
; Output:	CY set = it will be added: the old member is replaced
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

path_mark_old:
		call	path_seen	; CY: HL -> its record, in page 2
		ret	nc
		inc	hl
		ld	a,(hl)
		or	MARK_OLD
		ld	(hl),a
		scf
		ret

; path_keep - the member's path, kept in path_list with marks A.
;
; Input:	A = the marks
;		lzhw_path, lzhw_length
; Output:	returns only if it could be kept (no_memory); CY clear
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

path_keep:
		ld	(path_record+1),a	; the record: the length, the
		ld	a,(lzhw_length)	;   marks, the path
		ld	(path_record),a
		ld	c,a
		ld	b,0
		ld	hl,lzhw_path
		ld	de,path_record+2
		ldir
		ld	a,(lzhw_length)
		add	a,2
		ld	c,a
		ld	de,path_list
		ld	hl,path_record
		call	seglist_add	; CY: no room
		jp	c,no_memory
		ret			; CY clear

; path_seen - whether the member's path is in path_list.
;
;   Each segment, in page 2, is walked record by record: a length that
;   differs moves on at once. Nothing calls MSX-DOS while a segment is
;   mapped, and the record found is left mapped for the caller. A known
;   ceiling: n members take n x n / 2 comparisons; a hash table is the
;   way on, if an archive ever makes it matter.
;
; Input:	lzhw_path, lzhw_length; path_list
; Output:	CY set = it is, and HL -> its record, in page 2
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	seen_seg

path_seen:
		xor	a
		ld	(seen_seg),a
path_seen.segment:
		ld	de,path_list
		ld	a,(seen_seg)
		call	seglist_map	; HL = its start, BC = its length
		ccf
		ret	nc		; no more segments: not there
		push	hl		; DE = its end
		add	hl,bc
		ex	de,hl
		pop	hl
path_seen.record:
		or	a		; at the end?
		sbc	hl,de
		add	hl,de
		jr	nc,path_seen.next
		ld	a,(lzhw_length)	; the same length?
		cp	(hl)
		jr	nz,path_seen.skip
		push	de
		push	hl
		inc	hl		; past the length and the marks
		inc	hl
		ld	de,lzhw_path
		ld	b,a
path_seen.byte:
		ld	a,(de)
		cp	(hl)
		jr	nz,path_seen.differ
		inc	hl
		inc	de
		djnz	path_seen.byte
		pop	hl		; the same: there
		pop	de
		scf
		ret
path_seen.differ:
		pop	hl
		pop	de
path_seen.skip:
		ld	a,(hl)		; past it: its length, and 2
		add	a,2
		add	a,l
		ld	l,a
		jr	nc,path_seen.record
		inc	h
		jr	path_seen.record
path_seen.next:
		ld	hl,seen_seg
		inc	(hl)
		jr	path_seen.segment

; already - the line for a member added already in this run.
;
; Input:	lzhw_path, lzhw_length
; Output:	"Skipping PATH: added already"
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

already:
		print	msg_skipping
		call	print_member
		print	msg_already
		ret

; no_memory - stop: the mapper has no room left for a list.
;
;   The line is ended, KAGO says so, and stops, the archive deleted
;   (fail, with no MSX-DOS error).
;
; Input:	none
; Output:	does not return
; Modifies:	everything
; Scratch:	none

no_memory:
		print	msg_crlf
		print	msg_no_memory
		xor	a		; no MSX-DOS error
		jp	fail

; crc_tables, crc_start, crc_add, crc_done - the data's CRC, by
;   out_format: CRC-16 for LZH, CRC-32 for ZIP.
;
;   crc_tables builds the table, once; crc_start starts a member's CRC
;   (0 for CRC-16, 0FFFFFFFFh for CRC-32); crc_add adds BC bytes at DE;
;   crc_done puts it where the header takes it: lzhw_crc, or zipw_crc,
;   complemented.
;
; Input:	out_format; crc_value, crc32_value (crc.as)
; Output:	crc_done: lzhw_crc, or zipw_crc
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

crc_tables:
		ld	a,(out_format)
		or	a
		jp	z,crc_init
		jp	crc32_init

crc_start:
		ld	a,(out_format)
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
		ld	a,(out_format)
		or	a
		jp	z,crc_update
		jp	crc32_update

crc_done:
		ld	a,(out_format)
		or	a
		jr	nz,crc_done.zip
		ld	hl,(crc_value)
		ld	(lzhw_crc),hl
		ret
crc_done.zip:
		ld	hl,crc32_value	; complemented
		ld	de,zipw_crc
		ld	b,4
crc_done.byte:
		ld	a,(hl)
		cpl
		ld	(de),a
		inc	hl
		inc	de
		djnz	crc_done.byte
		ret

; fib_push, fib_pop - keep fib in fib_stack, one level deeper, and
;   put it back.
;
;   fib_slot gives the place of level depth: fib_stack + 64 x depth.
;
; Input:	fib, depth
; Output:	fib_push: HL -> the copy kept; depth one more
;		fib_pop: fib as it was kept; depth one less
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

fib_push:
		call	fib_slot
		push	hl
		ex	de,hl
		ld	hl,fib
		ld	bc,64
		ldir
		ld	hl,depth
		inc	(hl)
		pop	hl
		ret

fib_pop:
		ld	hl,depth
		dec	(hl)
		call	fib_slot
		ld	de,fib
		ld	bc,64
		ldir
		ret

fib_slot:
		ld	a,(depth)
		ld	l,a
		ld	h,0
		add	hl,hl		; times 64
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		add	hl,hl
		ld	de,fib_stack
		add	hl,de
		ret

; add_words - add the files every word after the archive's name names.
;
; Input:	files_at: where the words start
; Output:	each word, through add_word
; Modifies:	everything
; Scratch:	none

add_words:
		ld	hl,(files_at)
		ld	(word_at),hl
add_words.next:
		ld	de,(word_at)
		call	next_argument	; HL -> it, B = its length
		or	a
		ret	z
		ld	(word_at),de
		ld	de,spec_text	; B bytes from HL, then a 0
		ld	c,b
		ld	b,0
		ldir
		xor	a
		ld	(de),a
		call	add_word
		jr	add_words.next

; open_old - with /A, the archive there is to add to.
;
;   Without /A, or with no archive by that name, the archive is made
;   new, as before (write_name = archive_name). With one there, it is
;   opened through lzh.as; an LZH archive's first header is read, or
;   none at all, and a ZIP archive's central directory found (zip_open),
;   so that one that is not of the format chosen, or is damaged, is
;   refused before anything is written (not_readable). Its drive,
;   first cluster and name are kept, as create_archive keeps the new
;   archive's, so that a word that names it passes it over. The new
;   archive is written as a temporary file beside it (make_temp).
;
; Input:	archive_name, out_format; the command line
; Output:	returns only if the archive is to be made new or added to
;		write_name: the file to write
;		appending: not 0 when adding to an archive
;		old_drive, old_cluster, old_entry; temp_name
; Modifies:	AF
;		BC
;		DE
;		HL
;		IX
; Scratch:	none

open_old:
		ld	hl,archive_name
		ld	(write_name),hl
		ld	c,"A"
		call	switch_given	; CY set: /A
		ret	nc
		ld	de,archive_name	; is it there?
		ld	b,06h		; hidden and system ones too
		ld	ix,fib
		dos	_FFIRST
		or	a
		ret	nz		; no: it is made new
		ld	a,(fib+FIB_DRIVE)	; its drive, cluster and name
		ld	(old_drive),a
		ld	hl,(fib+FIB_CLUSTER)
		ld	(old_cluster),hl
		ld	hl,fib+FIB_NAME
		ld	de,old_entry
		ld	bc,13
		ldir
		ld	de,archive_name
		call	lzh_open	; A = 0, or an MSX-DOS error
		or	a
		jr	nz,open_old.error
		ld	a,(out_format)
		or	a
		jr	nz,open_old.zip
		call	lzh_next_header	; a member, or the end
		cp	LZH_END
		jr	z,open_old.ok
		or	a		; LZH_MEMBER
		jr	z,open_old.ok
open_old.checked:
		cp	80h
		jr	nc,open_old.error	; an MSX-DOS error
		call	not_readable	; not that format, or damaged
		dos	_TERM0
open_old.zip:
		ld	de,copy_buffer	; zip_open's buffer, 8 KB
		call	zip_open	; A = 0: its central directory found
		or	a
		jr	z,open_old.ok
		jr	open_old.checked
open_old.error:
		ld	b,a
		dos	_TERM
open_old.ok:
		call	make_temp
		ld	hl,temp_name
		ld	(write_name),hl
		ld	a,1
		ld	(appending),a
		ret

; make_temp - the temporary file's name: in the archive's directory,
;   the archive's name with ".$$$" for its extension.
;
;   The directory is what archive_name has before its last "\" or ":",
;   the second byte of a two-byte character never taken for a "\"; the
;   name is MSX-DOS2's, old_entry, up to its ".".
;
; Input:	archive_name, old_entry
; Output:	temp_name
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

make_temp:
		ld	hl,archive_name	; DE -> after the last "\" or ":"
		ld	d,h
		ld	e,l
make_temp.scan:
		ld	a,(hl)
		or	a
		jr	z,make_temp.dirs
		inc	hl
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	c,make_temp.pair
		cp	PATH_SEPARATOR
		jr	z,make_temp.after
		cp	":"
		jr	nz,make_temp.scan
make_temp.after:
		ld	d,h
		ld	e,l
		jr	make_temp.scan
make_temp.pair:
		ld	a,(hl)
		or	a
		jr	z,make_temp.dirs
		inc	hl
		jr	make_temp.scan
make_temp.dirs:
		ex	de,hl		; BC = the directory's length
		ld	de,archive_name
		or	a
		sbc	hl,de
		ld	b,h
		ld	c,l
		ld	hl,archive_name
		ld	de,temp_name
		ld	a,b
		or	c
		jr	z,make_temp.base	; none
		ldir
make_temp.base:
		ld	hl,old_entry
make_temp.char:
		ld	a,(hl)
		or	a
		jr	z,make_temp.ext
		cp	"."
		jr	z,make_temp.ext
		ld	(de),a
		inc	hl
		inc	de
		jr	make_temp.char
make_temp.ext:
		ld	hl,temp_ext	; ".$$$" and a 0
		ld	bc,5
		ldir
		ret

; copy_old - the old archive's members, all but those to be replaced,
;   into the new one, byte for byte. A ZIP archive's: copy_old_zip.
;
;   For each member: where its header starts, then the header (lzh.as),
;   then where its data starts: the header's length and the data's are
;   what is copied, from where the header starts (copy_range), so any
;   level and any method goes across as it was. Its path, as KAGO writes
;   paths (old_path), is looked up in path_list: one that will be added
;   is marked as replacing (path_mark_old), and the member's data is
;   skipped. A damaged archive stops, the new one deleted and the old
;   one as it was (old_bad).
;
; Input:	the old archive, open (lzh.as); path_list, from the first
;		walk
; Output:	the members kept, written
; Modifies:	everything
; Scratch:	none

copy_old:
		ld	a,(out_format)
		or	a
		jp	nz,copy_old_zip
		call	lzh_rewind
		or	a
		jp	nz,fail
copy_old.next:
		ld	a,1		; where this header starts
		ld	de,0
		ld	h,d
		ld	l,e
		call	lzh_seek	; DE:HL = here
		or	a
		jp	nz,fail
		ld	(old_at),hl
		ld	(old_at+2),de
		call	lzh_next_header
		cp	LZH_END
		ret	z		; all of them
		or	a
		jp	nz,old_bad
		ld	a,1		; where its data starts
		ld	de,0
		ld	h,d
		ld	l,e
		call	lzh_seek
		or	a
		jp	nz,fail
		ld	bc,(old_at)	; less where it started: the header
		or	a
		sbc	hl,bc
		ex	de,hl
		ld	bc,(old_at+2)
		sbc	hl,bc
		ex	de,hl
		ld	bc,(lzh_packed)	; and the data
		add	hl,bc
		ex	de,hl
		ld	bc,(lzh_packed+2)
		adc	hl,bc
		ex	de,hl
		ld	(old_len),hl
		ld	(old_len+2),de
		call	old_path	; CY: too long for any path KAGO makes
		jr	c,copy_old.keep
		call	path_mark_old	; CY: it is to be replaced
		jr	nc,copy_old.keep
		call	lzh_skip_data	; A = 0, or what stops it
		or	a
		jp	nz,old_bad
		jr	copy_old.next
copy_old.keep:
		call	copy_range	; to the next header
		jr	copy_old.next

; copy_range - old_len bytes of the old archive, from old_at, into the
;   new one, COPY_SIZE bytes at a time.
;
; Input:	old_at, old_len
; Output:	they are written; the old archive is just after them
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

copy_range:
		xor	a		; from old_at
		ld	hl,(old_at)
		ld	de,(old_at+2)
		call	lzh_seek
		or	a
		jp	nz,fail
copy_range.chunk:
		ld	hl,(old_len+2)
		ld	a,h
		or	l
		ld	hl,COPY_SIZE
		jr	nz,copy_range.sized	; 64 KB or more left
		ld	de,(old_len)
		ld	a,d
		or	e
		ret	z		; nothing left
		ex	de,hl		; HL = what is left, DE = COPY_SIZE
		or	a
		sbc	hl,de
		add	hl,de
		jr	c,copy_range.sized	; less: all of it
		ex	de,hl		; HL = COPY_SIZE
copy_range.sized:
		ld	(chunk),hl
		ld	de,copy_buffer
		call	lzh_read	; A = 0, LZH_TRUNCATED or an error
		or	a
		jp	nz,old_bad
		ld	de,copy_buffer
		ld	hl,(chunk)
		call	archive_write
		ld	hl,(old_len)	; old_len -= chunk
		ld	de,(chunk)
		or	a
		sbc	hl,de
		ld	(old_len),hl
		ld	hl,(old_len+2)
		ld	de,0
		sbc	hl,de
		ld	(old_len+2),hl
		jr	copy_range.chunk

; old_bad - stop: the old archive is damaged, or cut short.
;
;   An MSX-DOS error goes to fail as it is. Otherwise KAGO says so, and
;   stops through fail with no error of its own: the new archive, a
;   temporary file, is deleted, and the old one is left as it was.
;
; Input:	A = an LZH result (lzh.inc), or an MSX-DOS error code
; Output:	does not return
; Modifies:	everything
; Scratch:	none

old_bad:
		cp	80h
		jp	nc,fail		; an MSX-DOS error
		call	not_readable
		xor	a		; no MSX-DOS error
		jp	fail

; copy_old_zip - copy_old for ZIP: the old members, all but those to be
;   replaced, into the new archive, as they were.
;
;   zip.as walks the old central directory (zip_next), its records
;   one after the other from cd_next. For each one kept:
;   - its local header, data and data descriptor, if it has one, are
;     copied byte for byte (copy_range), from zip_local: the local
;     header's length comes from zip_data, which stops at the data;
;   - its central record is read again, whole, as it was (its extra
;     field and comment too), from where zip_next found it; only where
;     the local header now is changes, at 42; then it is kept for the end
;     (zipw_add).
;   A record over COPY_SIZE bytes, which no tool writes, is taken for
;   damage.
;
; Input:	the old archive, open (lzh.as, zip.as); path_list
; Output:	the members kept, written; their central records kept
; Modifies:	everything
; Scratch:	none

copy_old_zip:
		call	zip_rewind
copy_old_zip.next:
		ld	hl,(cd_next)	; where this record is
		ld	(cd_at),hl
		ld	hl,(cd_next+2)
		ld	(cd_at+2),hl
		call	zip_next
		cp	LZH_END
		ret	z		; all of them
		or	a
		jp	nz,old_bad
		ld	hl,(cd_next)	; its length: to where the next is
		ld	de,(cd_at)
		or	a
		sbc	hl,de
		ld	(cd_len),hl
		ld	hl,(cd_next+2)
		ld	de,(cd_at+2)
		sbc	hl,de
		ld	a,h
		or	l
		ld	a,LZH_DAMAGED
		jp	nz,old_bad	; 64 KB or more
		ld	hl,(cd_len)
		ld	de,COPY_SIZE+1
		or	a
		sbc	hl,de
		ld	a,LZH_DAMAGED
		jp	nc,old_bad	; over COPY_SIZE
		call	old_path	; CY: too long for any path KAGO makes
		jr	c,copy_old_zip.keep
		call	path_mark_old	; CY: it is to be replaced
		jr	c,copy_old_zip.next	; nothing to skip
copy_old_zip.keep:
		call	zip_data	; A = 0: at its data
		or	a
		jp	nz,old_bad
		ld	a,1		; where the data starts
		ld	de,0
		ld	h,d
		ld	l,e
		call	lzh_seek
		or	a
		jp	nz,fail
		ld	bc,(zip_local)	; less where the local header is
		or	a
		sbc	hl,bc
		ex	de,hl
		ld	bc,(zip_local+2)
		sbc	hl,bc
		ex	de,hl
		ld	bc,(lzh_packed)	; and the data
		add	hl,bc
		ex	de,hl
		ld	bc,(lzh_packed+2)
		adc	hl,bc
		ex	de,hl
		ld	(old_len),hl
		ld	(old_len+2),de
		ld	a,(zip_flags)	; bit 3: a data descriptor after it
		bit	3,a
		call	nz,descriptor
		ld	hl,(zip_local)	; from the local header
		ld	(old_at),hl
		ld	hl,(zip_local+2)
		ld	(old_at+2),hl
		ld	a,1		; where it goes in the new archive
		ld	de,0
		ld	h,d
		ld	l,e
		call	archive_seek
		ld	(zipw_at),hl
		ld	(zipw_at+2),de
		call	copy_range
		xor	a		; its central record, whole, into
		ld	hl,(cd_at)	;   copy_buffer
		ld	de,(cd_at+2)
		call	lzh_seek
		or	a
		jp	nz,fail
		ld	de,copy_buffer
		ld	hl,(cd_len)
		call	lzh_read
		or	a
		jp	nz,old_bad
		ld	hl,(zipw_at)	; where its local header is now
		ld	(copy_buffer+42),hl
		ld	hl,(zipw_at+2)
		ld	(copy_buffer+44),hl
		ld	hl,copy_buffer
		ld	bc,(cd_len)
		call	zipw_add	; CY: no room
		jp	c,no_memory
		jp	copy_old_zip.next	; too far for jr

; descriptor - a data descriptor's length, added to old_len.
;
;   It follows the data: the CRC-32 and the two sizes, 12 bytes, or 16
;   with "PK" 7 8 in front, which is how the two are told apart.
;
; Input:	the old archive at the member's data; lzh_packed
; Output:	old_len: 12 or 16 more
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

descriptor:
		ld	hl,(lzh_packed)	; past the data
		ld	de,(lzh_packed+2)
		ld	a,1
		call	lzh_seek
		or	a
		jp	nz,fail
		ld	de,sig_buf
		ld	hl,4
		call	lzh_read
		or	a
		jp	nz,old_bad
		ld	hl,sig_buf
		ld	de,descriptor_sig
		ld	b,4
		ld	c,12		; without "PK" 7 8: 12 bytes
descriptor.byte:
		ld	a,(de)
		cp	(hl)
		jr	nz,descriptor.add
		inc	hl
		inc	de
		djnz	descriptor.byte
		ld	c,16		; with it: 16
descriptor.add:
		ld	hl,(old_len)
		ld	b,0
		add	hl,bc
		ld	(old_len),hl
		ret	nc
		ld	hl,(old_len+2)
		inc	hl
		ld	(old_len+2),hl
		ret

; not_readable - "NAME: not an LZH archive KAGO can read.", or a ZIP
;   archive, by out_format.
;
; Input:	archive_name, out_format
; Output:	the line
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

not_readable:
		ld	de,archive_name
		call	print_zero
		ld	de,msg_not_lzh
		ld	a,(out_format)
		or	a
		jr	z,not_readable.say
		ld	de,msg_not_zip
not_readable.say:
		dos	_STROUT
		ret

; old_path - an old member's path, as KAGO writes paths, in lzhw_path.
;
;   lzh.as has cleaned it: "\" between parts, the case as it was stored.
;   It is folded to upper case, the second byte of a two-byte character
;   left as it is, and a directory's gets its "\", so that path_seen can
;   compare it byte for byte. One of 140 bytes or more is no path KAGO
;   makes: it is kept, not looked up.
;
; Input:	lzh_name, lzh_name_length, lzh_dir (lzh.as)
; Output:	CY set = too long: not looked up
;		lzhw_path, lzhw_length
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

old_path:
		ld	a,(lzh_name_length)	; under 140 bytes?
		cp	140
		ccf
		ret	c
		ld	b,a
		ld	hl,lzh_name
		ld	de,lzhw_path
		or	a
		jr	z,old_path.dir	; empty
old_path.byte:
		ld	a,(hl)
		inc	hl
		call	kanji_lead	; CY: a pair, its second byte as it is
		jr	c,old_path.pair
		call	fold_case
old_path.put:
		ld	(de),a
		inc	de
		djnz	old_path.byte
		jr	old_path.dir
old_path.pair:
		ld	(de),a
		inc	de
		dec	b
		jr	z,old_path.dir
		ld	a,(hl)
		inc	hl
		jr	old_path.put
old_path.dir:
		ld	a,(lzh_dir)	; a directory: its "\"
		or	a
		jr	z,old_path.length
		ld	a,PATH_SEPARATOR
		ld	(de),a
		inc	de
old_path.length:
		ex	de,hl
		ld	de,lzhw_path
		or	a
		sbc	hl,de
		ld	(lzhw_length),hl
		ret			; CY clear from the SBC

; same_file - whether the entry just found is a file KAGO is writing or
;   reading.
;
; Input:	fib: the entry
;		HL -> a drive, a first cluster and a name, as MSX-DOS2's
;		FIB has them: archive_drive..., or old_drive...
; Output:	Z set = it is that file
; Modifies:	AF
;		DE
;		HL
; Scratch:	none

same_file:
		ld	a,(fib+FIB_DRIVE)
		cp	(hl)
		ret	nz
		inc	hl
		ld	e,(hl)		; DE = its first cluster
		inc	hl
		ld	d,(hl)
		inc	hl
		push	hl
		ld	hl,(fib+FIB_CLUSTER)
		or	a
		sbc	hl,de
		pop	de		; DE -> its name
		ret	nz
		ld	hl,fib+FIB_NAME
same_file.char:
		ld	a,(de)
		cp	(hl)
		ret	nz
		inc	hl
		inc	de
		or	a
		jr	nz,same_file.char
		ret			; Z: all of the name

; word_dirs - the directories of a word on the command line, as the
;   start of each member's path.
;
;   They are what comes before the word's last "\", the drive left out:
;   "B:\WORK\*.TXT" gives "WORK\". Each part is folded to upper case,
;   as MSX-DOS2 names are kept; empty parts (a leading "\") and "." are
;   left out, and ".." refuses the word, since it would take the member
;   out of where it is extracted. The second byte of a two-byte
;   character is never taken for a "\" (kanji_lead, in common.as).
;
; Input:	spec_text: the word
; Output:	CY set = refused: ".." in it
;		lzhw_path, lzhw_dir: the directories, each with its "\"
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	dirs_from
;		dirs_end
;		part_from

word_dirs:
		ld	hl,spec_text
		ld	a,(spec_text+1)	; a drive: "B:"
		cp	":"
		jr	nz,word_dirs.start
		inc	hl
		inc	hl
word_dirs.start:
		ld	(dirs_from),hl	; where the directories start
		ld	(dirs_end),hl	; and end, until a "\" is found
word_dirs.scan:
		ld	a,(hl)
		or	a
		jr	z,word_dirs.scanned
		inc	hl
		call	kanji_lead	; CY: a pair, so its second byte too
		jr	c,word_dirs.pair
		cp	PATH_SEPARATOR
		jr	nz,word_dirs.scan
		ld	(dirs_end),hl	; just after it
		jr	word_dirs.scan
word_dirs.pair:
		ld	a,(hl)
		or	a
		jr	z,word_dirs.scanned
		inc	hl
		jr	word_dirs.scan
word_dirs.scanned:
		ld	de,lzhw_path	; DE writes
		ld	hl,(dirs_from)	; HL reads
word_dirs.part:
		ld	bc,(dirs_end)	; the end of the directories?
		or	a
		sbc	hl,bc
		add	hl,bc
		jr	z,word_dirs.done
		ld	(part_from),hl
word_dirs.seek:
		ld	a,(hl)		; to the part's "\"
		inc	hl
		call	kanji_lead
		jr	c,word_dirs.second
		cp	PATH_SEPARATOR
		jr	nz,word_dirs.seek
		push	hl		; HL -> just after the "\"
		dec	hl
		ld	bc,(part_from)
		or	a
		sbc	hl,bc
		ld	c,l		; C = the part's length
		ld	hl,(part_from)
		call	dirs_part	; CY set: ".."
		pop	hl
		ret	c
		jr	word_dirs.part
word_dirs.second:
		inc	hl
		jr	word_dirs.seek
word_dirs.done:
		ex	de,hl		; the directories' length
		ld	de,lzhw_path
		or	a
		sbc	hl,de
		ld	a,l
		ld	(lzhw_dir),a
		ret			; CY clear from the SBC

; dirs_part - one part of a word's directories, into lzhw_path.
;
; Input:	HL -> the part
;		C = its length, 0 to 125
;		DE -> where it goes
; Output:	CY set = it is "..": refused
;		DE -> after it and its "\"; nothing written for an
;		empty part or "."
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

dirs_part:
		ld	a,c
		or	a
		ret	z		; empty: CY clear
		ld	a,(hl)
		cp	"."
		jr	nz,dirs_part.copy
		ld	a,c
		dec	a
		ret	z		; ".": CY clear from the CP
		dec	a
		jr	nz,dirs_part.copy
		inc	hl
		ld	a,(hl)
		dec	hl
		cp	"."
		jr	nz,dirs_part.copy
		scf			; ".."
		ret
dirs_part.copy:
		ld	b,c
dirs_part.byte:
		ld	a,(hl)
		inc	hl
		call	kanji_lead	; CY: a pair, its second byte as it is
		jr	c,dirs_part.pair
		call	fold_case
dirs_part.put:
		ld	(de),a
		inc	de
		djnz	dirs_part.byte
		ld	a,PATH_SEPARATOR
		ld	(de),a
		inc	de
		or	a		; CY clear
		ret
dirs_part.pair:
		ld	(de),a
		inc	de
		dec	b
		ld	a,(hl)
		inc	hl
		jr	dirs_part.put

; entry_path - the member's whole path: the word's directories, then
;   the name MSX-DOS2 found.
;
; Input:	lzhw_path, lzhw_dir: the directories
;		fib: the entry
; Output:	lzhw_path, lzhw_length: the path
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

entry_path:
		ld	a,(lzhw_dir)
		ld	b,a		; B = the length so far
		ld	e,a
		ld	d,0
		ld	hl,lzhw_path
		add	hl,de
		ex	de,hl		; DE -> after the directories
		ld	hl,fib+FIB_NAME
entry_path.char:
		ld	a,(hl)
		or	a
		jr	z,entry_path.done
		ld	(de),a
		inc	hl
		inc	de
		inc	b
		jr	entry_path.char
entry_path.done:
		ld	l,b
		ld	h,0
		ld	(lzhw_length),hl
		ret

; adding_line - the start of a member's line, "Adding " or "Replacing "
;   (line_word, from path_check), and its path. progress.as calls it
;   through progress_line, to redraw the line.
;
;   print_member, its second half, is the path alone: printl, since it
;   may hold a "$".
;
; Input:	line_word; lzhw_path, lzhw_length
; Output:	they are printed
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

adding_line:
		ld	de,(line_word)
		dos	_STROUT
print_member:
		printl	lzhw_path,(lzhw_length)
		ret

; archive_write - write HL bytes from DE to the archive.
;
;   Fewer bytes written than asked means the disk is full.
;
; Input:	DE -> the bytes
;		HL = how many
; Output:	returns only if all were written
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

archive_write:
		push	hl
		ld	a,(archive_handle)
		ld	b,a
		dos	_WRITE		; HL = how many were written
		pop	de
		or	a
		jp	nz,fail
		sbc	hl,de		; carry clear from OR A
		ret	z
		ld	a,.DKFUL
		jp	fail

; archive_seek - move the archive's file pointer.
;
; Input:	A = 0 from the start, 1 from here, 2 from the end
;		DE:HL = how far
; Output:	DE:HL = where it is now, from the start
;		returns only if it worked
; Modifies:	AF
;		B
;		DE
;		HL
; Scratch:	none

archive_seek:
		push	af
		ld	a,(archive_handle)
		ld	b,a
		pop	af
		dos	_SEEK
		or	a
		ret	z		; an error: on into fail

; fail - stop on an MSX-DOS error: the archive is deleted.
;
;   The file being read, if one is, is closed, then the archive, which
;   is deleted: a partial archive is never left behind. With /A it is
;   the temporary file that is deleted; the old archive is left as it
;   was. COMMAND2 prints
;   the error's message, as it does for _TERM's code. fail_closed, its
;   second entry, is for when the archive is closed already.
;
; Input:	A = the MSX-DOS error code
;		in_handle: 0FFh, or the file being read
; Output:	does not return
; Modifies:	everything
; Scratch:	none

fail:
		push	af
		ld	a,(in_handle)
		cp	0FFh
		jr	z,fail.archive	; no file open to read
		ld	b,a
		dos	_CLOSE
fail.archive:
		ld	a,(archive_handle)
		ld	b,a
		dos	_CLOSE
		pop	af
fail_closed:
		push	af
		ld	de,(write_name)	; the archive, or with /A the new one
		dos	_DELETE
		pop	af
		ld	b,a
		dos	_TERM

; Constants for main and the routines above:
;
; switch_letters	the switches KAGO takes, upper case, ending in 0
; msg_need_dos2		the refusal under MSX-DOS1
; msg_banner		the name, version, copyright and web address
; msg_usage		the rest of the usage, after the banner
; msg_no_mapper		heapinit found no mapper support
; msg_no_memory		no mapper memory left for a list
; msg_no_format, msg_bad_format, msg_no_pma
;			archive_format's refusals
; format_table		the formats' names: three letters, then the
;			format, for each; 0 after the last
; msg_exists		after the archive's name, when it exists
; msg_nothing, msg_not_written, msg_not_changed
;			around the archive's name, when nothing was added
; msg_not_lzh, msg_not_zip
;			/A's refusals
; descriptor_sig	a data descriptor's signature
; msg_left		where the new archive is, when it could not take
;			the old one's place
; temp_ext		the temporary file's extension, and a 0
; msg_adding, msg_replacing, msg_ok, msg_skipping, msg_colon, msg_crlf,
; msg_dotdot, msg_already
;			adding's words, put together per member
; method_lh0, method_lhd	the methods: stored, a directory
; no_name, end_mark	a 0 byte: the empty name, for "everything in
;			it", and the end of an archive
;
switch_letters:	defb	"AFYQV?",0
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
		defb	"  /A      add to the archive, replacing same paths"
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
		defb	CHR_CR,CHR_LF
		defb	"Files may use * and ?."
		defb	CHR_CR,CHR_LF
		defb	CHR_CR,CHR_LF,"$"
msg_no_format:
		defb	"Which format? Name the archive .LZH, .LHA, .PMA or"
		defb	CHR_CR,CHR_LF
		defb	".ZIP, or use /F:LZH, /F:PMA or /F:ZIP."
		defb	CHR_CR,CHR_LF,"$"
msg_bad_format:
		defb	"Unknown format: use /F:LZH, /F:PMA or /F:ZIP."
		defb	CHR_CR,CHR_LF,"$"
msg_no_mapper:	defb	"KAGO needs MSX-DOS2's mapper support."
		defb	CHR_CR,CHR_LF,"$"
msg_no_memory:	defb	"Not enough mapper memory left."
		defb	CHR_CR,CHR_LF,"$"
msg_no_pma:
		defb	"Writing PMA archives is not supported yet."
		defb	CHR_CR,CHR_LF,"$"
format_table:	defb	"LZH",FORMAT_LZH,"LHA",FORMAT_LZH
		defb	"PMA",FORMAT_PMA,"ZIP",FORMAT_ZIP,0
msg_exists:	defb	" already exists.",CHR_CR,CHR_LF,"$"
msg_nothing:	defb	"Nothing to add: $"
msg_not_written:
		defb	" was not written.",CHR_CR,CHR_LF,"$"
msg_not_changed:
		defb	" was not changed.",CHR_CR,CHR_LF,"$"
msg_not_lzh:	defb	": not an LZH archive KAGO can read."
		defb	CHR_CR,CHR_LF,"$"
msg_not_zip:	defb	": not a ZIP archive KAGO can read."
		defb	CHR_CR,CHR_LF,"$"
descriptor_sig:	defb	"PK",7,8
msg_left:	defb	"The new archive is left as $"
temp_ext:	defb	".$$$",0
msg_adding:	defb	"Adding $"
msg_replacing:	defb	"Replacing $"
msg_ok:		defb	" OK",CHR_CR,CHR_LF,"$"
msg_skipping:	defb	"Skipping $"
msg_colon:	defb	": $"
msg_crlf:	defb	CHR_CR,CHR_LF,"$"
msg_dotdot:	defb	": a path with .. cannot be stored"
		defb	CHR_CR,CHR_LF,"$"
msg_already:	defb	": added already",CHR_CR,CHR_LF,"$"
method_lh0:	defb	"-lh0-"
method_lhd:	defb	"-lhd-"
no_name:
end_mark:	defb	0

		dseg

; Variables for main and the routines above:
;
; archive_name		the archive's name, from the command line, and a 0
; files_at		where the words after it start
; write_name		the file written: archive_name, or temp_name
; appending		not 0 when /A adds to an archive there
; collecting		not 0 in /A's first walk
; old_drive, old_cluster, old_entry
;			the old archive's drive, first cluster and name,
;			as MSX-DOS2 finds it: open_old
; temp_name		the temporary file's name, and a 0: make_temp
; old_at, old_len	copy_old: where an old member starts, and its
;			header's and data's length, 4 bytes each;
;			copy_old_zip: its local header's, data's and
;			descriptor's
; cd_at, cd_len		copy_old_zip: where an old central record is, 4
;			bytes, and its length
; sig_buf		descriptor: the 4 bytes after the data
; line_word		"Adding " or "Replacing ": path_check
; out_format		FORMAT_LZH or FORMAT_ZIP: archive_format
; archive_handle	the archive, open to write
; archive_drive, archive_cluster, archive_entry
;			its drive, first cluster and name, as MSX-DOS2
;			finds it: create_archive
; word_at		where the next word on the command line starts
; spec_text		the word being added, and a 0
; added			how many members have been added
; fib			_FFIRST's and _FNEXT's entry: 64 bytes
; in_handle		the file being read, 0FFh for none
; header_at		where its header is in the archive, 4 bytes
; chunk			the bytes in copy_buffer this time round
; dirs_from, dirs_end, part_from
;			word_dirs: where the word's directories start
;			and end, and where the part being read starts
; depth			add_tree: how many directories deep
; path_list		the paths added: a list, seglist.as's
; seen_seg		path_seen: the segment being walked
; copy_buffer		the data, COPY_SIZE bytes at a time, in the
;			buffers segment, which the program file does not
;			carry
; fib_stack		add_tree: each directory's FIB, kept while what
;			is in it is added; MAX_DEPTH of 64 bytes, in the
;			buffers segment
; path_record		path_keep: a path's record, its length, its marks
;			and the path, in the buffers segment
;
archive_name:	defs	128
out_format:	defs	1
archive_handle:	defs	1
archive_drive:	defs	1
archive_cluster:	defs	2
archive_entry:	defs	13
files_at:	defs	2
write_name:	defs	2
appending:	defs	1
collecting:	defs	1
old_drive:	defs	1
old_cluster:	defs	2
old_entry:	defs	13
temp_name:	defs	136
old_at:	defs	4
old_len:	defs	4
cd_at:	defs	4
cd_len:	defs	2
sig_buf:	defs	4
line_word:	defs	2
word_at:	defs	2
spec_text:	defs	128
added:	defs	2
fib:	defs	64
in_handle:	defs	1
header_at:	defs	4
chunk:	defs	2
dirs_from:	defs	2
dirs_end:	defs	2
part_from:	defs	2
depth:	defs	1
path_list:	defs	LIST_SIZE
seen_seg:	defs	1

		dseg	buffers
copy_buffer:	defs	COPY_SIZE
fib_stack:	defs	MAX_DEPTH*64
path_record:	defs	146

		end	main
