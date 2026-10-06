; names.inc - what a module includes to use names.as: the names of its
; routines, and the two variables others read.
;
; names.as defines NAMES_INCLUDED before including this file, so that it
; does not declare its own names as external.

		ifndef	NAMES_INCLUDED
		extrn	names_init	; an empty table
		extrn	names_add	; the member's path into the table
		extrn	names_assign	; the tails, once all are in
		extrn	names_out	; the member's path as MSX-DOS names
		extrn	names_changed	; a byte: not 0 if names_out gave a
					;   part a tail
		extrn	names_segs	; a byte: the table's segments
		endif
