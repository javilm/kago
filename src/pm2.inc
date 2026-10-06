; pm2.inc - the names of pm2.as's public routines: -pm2-'s start, and
; the move-to-front list, which pm1.as uses too.

		extrn	pm2_start	; get ready for a -pm2- member
		extrn	mtf_start	; the list, as PMarc starts it
		extrn	mtf_moved	; the last HL bytes, to its head
		extrn	mtf_find	; A = the byte at place A
