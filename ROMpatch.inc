; This code should be placed on the original ROM at address $118B (1 byte further than the NEW routine)
; This include is used from:
;     a) The bootloader, for the normal and final operation, where the original 48K ROM should be patched so instead of going to BASIC it brings the SmarROM, 
;        which is placed at System ROM 1 Slot, to SMARTROMADDR and executed
;     b) From testpatch.asm, where the patch is generated as an standalone file, in order to patch the ROM manually before adding it to the ZEsarUX flash 
;        file for testing purposes

SMARTROMADDR          equ $A000
SMARTROMSIZE          equ $4000
BANKM                 equ $5B5C
MEMCHECKADDR          equ $11DA

PatchStart
; First copy this code to RAM, we will run from there

            LD HL, PatchStartCopy
            LD DE, $6000
            LD BC, PatchEnd - PatchStartCopy
            LDIR
            JP $6000
            
PatchStartCopy
            DI
; ------------ Page In System ROM 0 (where SmartROM is placed)

            LD   BC,$7FFD       ; I/O address of horizontal ROM/RAM switch
			LD   A,(BANKM)      ; get current switch state
			AND  $EF            ; System ROM 0
			LD   (BANKM),A      ; update the system variable (very important)
			OUT  (C),A          ; make the switch						


; ------------ Copy System ROM 0 content 
            LD HL, $0000
            LD DE, SMARTROMADDR
            LD BC, SMARTROMSIZE
            LDIR


; ------------ Page In Back System ROM 1 (48K ROM)

            LD   BC,$7FFD       ; I/O address of horizontal ROM/RAM switch
			LD   A,(BANKM)      ; get current switch state
			OR   $10            ; System ROM 1
			LD   (BANKM),A      ; update the system variable (very important)
			OUT  (C),A          ; make the switch						

; ------------ Jump to smarROM
            EI
            JP SMARTROMADDR
PatchEnd

; ----------------- Thi is the patch to avoid memory check
PatchMemCheck LD HL, $FFFF
              JP $11FF

