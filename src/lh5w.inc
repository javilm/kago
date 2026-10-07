; lh5w.inc - the names of lh5w.as's routines: a member's data, packed
; with -lh5-, deflate or -pm2-.

		extrn	lh5w_start	; DE:HL = the size, A the mode;
					;   CY: no memory
		extrn	lh5w_data	; BC bytes at DE; CY: no smaller
		extrn	lh5w_end	; DE:HL = the packed size; CY: as above
