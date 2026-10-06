; zip.inc - what a module includes to read ZIP archives with zip.as:
; its one result of its own, and the names of its routines and
; variables. Its other results are lzh.inc's, which it shares.
;
; zip.as defines ZIP_INCLUDED before including this file, so that it
; does not declare its own names as external.

ZIP_SPLIT	equ	6		; ZIP64, or a split archive: not
					;   read; lzh.inc's results are 0 to
					;   4, and lh5.inc's LH5_BAD is 5

		ifndef	ZIP_INCLUDED
		extrn	zip_open	; find the central directory
		extrn	zip_rewind	; back to the first member
		extrn	zip_next	; the next member's central header
		extrn	zip_skip	; past its data: nothing to do
		extrn	zip_method	; its method's name, 7 characters
		extrn	zip_crc		; its CRC-32, 4 bytes
		extrn	zip_local	; where its local header is
		endif
