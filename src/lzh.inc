; lzh.inc - what a module includes to read LZH archives with lzh.as:
; the results lzh.as gives, and the names of its routines and variables.
;
; lzh.as defines LZH_INCLUDED before including this file, so that it
; does not declare its own names as external.

; The result in A, from lzh_next_header and lzh_skip_data, and from
; zip.as's routines too. Anything 80h and above is an MSX-DOS error
; code, passed on as it came.
;
; The member's variables below are the member just read, LZH or ZIP:
; zip.as fills them in as lzh.as does.

LZH_MEMBER	equ	0		; a member's header was read
LZH_END		equ	1		; the end of the archive
LZH_TRUNCATED	equ	2		; the file ends inside a header or
					;   inside a member's data
LZH_DAMAGED	equ	3		; a header is not valid
LZH_LEVEL3	equ	4		; a level 3 header, not read

		ifndef	LZH_INCLUDED
		extrn	lzh_open
		extrn	lzh_rewind
		extrn	lzh_next_header
		extrn	lzh_skip_data
		extrn	lzh_name	; the member's path, clean
		extrn	lzh_name_length	; a word: 0 to 255
		extrn	lzh_method	; 5 characters
		extrn	lzh_packed	; 4 bytes
		extrn	lzh_original	; 4 bytes
		extrn	lzh_time	; 4 bytes, by level
		extrn	lzh_level	; 0 to 2
		extrn	lzh_crc		; the data's CRC-16
		extrn	lzh_attributes	; MS-DOS attributes
		extrn	lzh_read	; read HL bytes into DE
		extrn	lzh_seek	; A = 0, 1, 2: to DE:HL from the
					;   start, here, or the end
		extrn	lzh_size	; the archive's size, 4 bytes
		extrn	lzh_clean_path	; clean lzh_name, as a path
		extrn	lzh_dir		; not 0 for a directory
		endif
