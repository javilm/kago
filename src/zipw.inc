; zipw.inc - the names of zipw.as's routines and variables.

		extrn	zipw_local	; DE -> the local header, HL: length
		extrn	zipw_keep	; the central record kept: CY = no room
		extrn	zipw_add	; record HL, BC bytes: CY = no room
		extrn	zipw_copy	; the next of them into DE: HL bytes
		extrn	zipw_end	; DE -> the end record, HL = 22
		extrn	zipw_crc	; the member's CRC-32, 4 bytes
		extrn	zipw_at		; where its local header is, 4 bytes
