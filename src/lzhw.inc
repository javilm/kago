; lzhw.inc - the name of lzhw.as's routine, and of the variables that
; describe the member it makes a header for.

		extrn	lzhw_header	; DE -> the header, HL = its length
		extrn	lzhw_method	; 5 characters: "-lh5-", "-lh0-"...
		extrn	lzhw_path	; the member's path, "\" between parts
		extrn	lzhw_dir	; the directories' length, a byte
		extrn	lzhw_length	; the path's length, a word
		extrn	lzhw_size	; the data's size, 4 bytes
		extrn	lzhw_packed	; its packed size, 4 bytes
		extrn	lzhw_crc	; the data's CRC-16
		extrn	lzhw_date	; MS-DOS's time word, then its date
		extrn	lzhw_attr	; the MS-DOS attributes
