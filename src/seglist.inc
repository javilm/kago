; seglist.inc - lists of records in mapper segments: the size of a
; list's description, and the names of seglist.as's routines.
;
; seglist.as defines SEGLIST_INCLUDED before including this file, so
; that it does not declare its own names as external.

LIST_SEGS	equ	32		; at most 32 segments, 512 KB
LIST_SIZE	equ	1+6*LIST_SEGS	; a list's description, all 0 to
					;   start

		ifndef	SEGLIST_INCLUDED
		extrn	seglist_add	; DE: the list, HL: a record, BC
					;   bytes; CY = no room
		extrn	seglist_map	; segment A in page 2: HL, BC bytes;
					;   CY = none
		endif
