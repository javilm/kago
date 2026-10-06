; crc.inc - the names of crc.as's routines and its variables.

		extrn	crc_init
		extrn	crc_update
		extrn	crc_value	; the CRC-16 so far, a word
		extrn	crc32_init
		extrn	crc32_update
		extrn	crc32_value	; the CRC-32 so far, 4 bytes
