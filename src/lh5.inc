; lh5.inc - what a module includes to decode -lh5- members with lh5.as:
; its result code, and the names of its routines. What inflate.as
; shares beyond these is in lh5share.inc.
;
; lh5.as defines LH5_INCLUDED before including this file, so that it
; does not declare its own names as external.

LH5_BAD		equ	5		; the member's compressed data is
					;   not valid; lzh.inc's results
					;   are 0 to 4

		ifndef	LH5_INCLUDED
		extrn	lh5_start	; get ready for the member just read
		extrn	lh5_read	; decode HL bytes into the window
		extrn	lh5_finish	; skip the data not read
		endif
