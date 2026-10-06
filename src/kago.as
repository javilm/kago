; kago.as - KAGO, the compressor. It writes LZH archives, every member
; stored, of the files and directory trees named on the command line.
;
; It checks for MSX-DOS2 and the command line, and chooses the format:
; /F: names it, or the archive's extension does. Only LZH is written so
; far; ZIP and PMA say so. The archive is created new: one that exists
; already is refused. Each word after the archive's name is a file, *
; and ? allowed, found with MSX-DOS2's _FFIRST and _FNEXT; each file
; found is added, its path as typed less the drive (word_dirs), its
; date, time and attributes, its data stored and its CRC-16 computed on
; the way. The header goes in front of the data, written again once the
; CRC and the size are known (lzhw.as makes it). A directory found is
; added whole: a -lhd- member, then everything in it, at every depth
; (add_tree). The archive itself, if a name matches it, is passed over.
; An archive nothing was added to is deleted. Any MSX-DOS error stops,
; the archive deleted.

		include	common.inc	; common.as's routines, and print
		include	crc.inc		; crc.as: the CRC-16
		include	lzhw.inc	; lzhw.as: the member's header
		include	progress.inc	; progress.as: the progress line

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
;   it are added one by one (add_word); the archive ends with a 0 byte.
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
		ld	(word_at),hl	; HL -> just after it
		call	archive_format	; returns only for LZH
		ld	de,(word_at)
		call	next_argument	; A = 0: no file named
		or	a
		jr	nz,main.files
		ld	b,.NOPAR	; COMMAND2: *** Missing parameter
		dos	_TERM
main.files:
		call	create_archive	; returns only if it was
		call	progress_init	; on the screen, not with /Q
		ld	hl,adding_line	; what the line starts with
		ld	(progress_line),hl
		call	crc_init	; the CRC-16's table
		ld	hl,0
		ld	(added),hl
main.word:
		ld	de,(word_at)
		call	next_argument	; HL -> it, B = its length
		or	a
		jr	z,main.done
		ld	(word_at),de
		ld	de,spec_text	; B bytes from HL, then a 0
		ld	c,b
		ld	b,0
		ldir
		xor	a
		ld	(de),a
		call	add_word
		jr	main.word
main.done:
		ld	hl,(added)
		ld	a,h
		or	l
		jr	z,main.nothing
		ld	de,end_mark	; the end of the archive: a 0
		ld	hl,1
		call	archive_write
		ld	a,(archive_handle)
		ld	b,a
		dos	_CLOSE
		or	a
		jp	nz,fail_closed
		dos	_TERM0
main.nothing:
		ld	a,(archive_handle)	; nothing added: no archive
		ld	b,a
		dos	_CLOSE
		ld	de,archive_name
		dos	_DELETE
		print	msg_nothing
		ld	de,archive_name
		call	print_zero
		print	msg_not_written
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

; archive_format - the archive's format, from /F: or the extension.
;
;   /F: takes LZH, PMA or ZIP, in either case. Without it the archive
;   name's last four characters decide: .LZH or .LHA, .PMA, .ZIP. Only
;   LZH is written for now: ZIP and PMA end the program saying so, as
;   do a value /F: does not take and a name that says no format.
;
; Input:	archive_name
; Output:	returns only for LZH
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
		cp	FORMAT_LZH
		ret	z
		ld	de,msg_no_pma
		cp	FORMAT_PMA
		jr	z,archive_format.say
		ld	de,msg_no_zip
		jr	archive_format.say
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
;   .FILEX, which is said in KAGO's own words; any other error ends the
;   program with its code. Then a byte is written and the archive is
;   flushed (_ENSURE), so that its directory entry has a first cluster:
;   that cluster, the drive and the name tell it apart from every other
;   file, should a name typed after it match it (add_entry). The byte
;   is written over later.
;
; Input:	archive_name
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
		ld	de,archive_name
		xor	a		; open mode: read and write
		ld	b,80h		; create new
		dos	_CREATE		; B = the handle
		or	a
		jr	z,create_archive.created
		cp	.FILEX
		jr	nz,create_archive.error
		ld	de,archive_name	; it exists
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
		ld	de,archive_name
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
		print	msg_skipping
		ld	de,spec_text
		call	print_zero
		print	msg_dotdot
		ret

; add_entry - add the entry just found.
;
;   "." and "..", and the archive itself, are passed over without a
;   line; a directory is added whole (add_tree). A file is opened
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
		ld	a,(archive_drive)	; the archive itself?
		ld	hl,fib+FIB_DRIVE
		cp	(hl)
		jr	nz,add_entry.file
		ld	hl,(fib+FIB_CLUSTER)
		ld	de,(archive_cluster)
		or	a
		sbc	hl,de
		jr	nz,add_entry.file
		ld	hl,fib+FIB_NAME
		ld	de,archive_entry
add_entry.same:
		ld	a,(de)
		cp	(hl)
		jr	nz,add_entry.file
		inc	hl
		inc	de
		or	a
		jr	nz,add_entry.same
		ret			; it is: passed over
add_entry.file:
		call	entry_path	; lzhw_path, lzhw_length
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
		ld	a,1		; where the header goes: here
		ld	de,0
		ld	h,d
		ld	l,e
		call	archive_seek	; DE:HL = where the file is now
		ld	(header_at),hl
		ld	(header_at+2),de
		call	lzhw_header	; DE -> it, HL = its length
		call	archive_write
		print	msg_adding
		call	print_member
		ld	hl,(lzhw_size)
		ld	de,(lzhw_size+2)
		call	progress_start	; "   0%", on the screen
		ld	hl,0
		ld	(crc_value),hl	; the data's CRC, from 0
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
		call	crc_update
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
		ld	hl,(crc_value)
		ld	(lzhw_crc),hl
		xor	a		; back to the header
		ld	hl,(header_at)
		ld	de,(header_at+2)
		call	archive_seek
		call	lzhw_header	; the same length: only numbers changed
		call	archive_write
		ld	a,2		; on to the end again
		ld	de,0
		ld	h,d
		ld	l,e
		call	archive_seek
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
		call	entry_details
		ld	hl,method_lhd
		ld	de,lzhw_method
		ld	bc,5
		ldir
		call	lzhw_header	; no data: written once
		call	archive_write
		print	msg_adding
		call	print_member
		print	msg_ok
		ld	hl,(added)
		inc	hl
		ld	(added),hl
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

; adding_line - the start of a member's line, "Adding " and its path.
;   progress.as calls it through progress_line, to redraw the line.
;
;   print_member, its second half, is the path alone: printl, since it
;   may hold a "$".
;
; Input:	lzhw_path, lzhw_length
; Output:	they are printed
; Modifies:	AF
;		BC
;		DE
;		HL
; Scratch:	none

adding_line:
		print	msg_adding
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
;   is deleted: a partial archive is never left behind. COMMAND2 prints
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
		ld	de,archive_name
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
; msg_no_format, msg_bad_format, msg_no_zip, msg_no_pma
;			archive_format's refusals
; format_table		the formats' names: three letters, then the
;			format, for each; 0 after the last
; msg_exists		after the archive's name, when it exists
; msg_nothing, msg_not_written
;			around the archive's name, when nothing was added
; msg_adding, msg_ok, msg_skipping, msg_colon, msg_crlf, msg_dotdot
;			adding's words, put together per member
; method_lh0, method_lhd	the methods: stored, a directory
; no_name, end_mark	a 0 byte: the empty name, for "everything in
;			it", and the end of an archive
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
msg_no_zip:
		defb	"Writing ZIP archives is not supported yet."
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
msg_adding:	defb	"Adding $"
msg_ok:		defb	" OK",CHR_CR,CHR_LF,"$"
msg_skipping:	defb	"Skipping $"
msg_colon:	defb	": $"
msg_crlf:	defb	CHR_CR,CHR_LF,"$"
msg_dotdot:	defb	": a path with .. cannot be stored"
		defb	CHR_CR,CHR_LF,"$"
method_lh0:	defb	"-lh0-"
method_lhd:	defb	"-lhd-"
no_name:
end_mark:	defb	0

		dseg

; Variables for main and the routines above:
;
; archive_name		the archive's name, from the command line, and a 0
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
; copy_buffer		the data, COPY_SIZE bytes at a time, in the
;			buffers segment, which the program file does not
;			carry
; fib_stack		add_tree: each directory's FIB, kept while what
;			is in it is added; MAX_DEPTH of 64 bytes, in the
;			buffers segment
;
archive_name:	defs	128
archive_handle:	defs	1
archive_drive:	defs	1
archive_cluster:	defs	2
archive_entry:	defs	13
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

		dseg	buffers
copy_buffer:	defs	COPY_SIZE
fib_stack:	defs	MAX_DEPTH*64

		end	main
