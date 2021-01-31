; This is the bootloader for ZXUNO for FPGA without a flash memory (or where the flash memory can't be used). Basically is a fork of Mcleod_ikeafix's
; bootloader for such core, and is to be included in the "no flash" core, replacing bootloader_copy_bram_to_sram.hex file. That is requires the 
; core to be rebuilt.
;
; Greetings: a big thanks to McLeod_ideafix, whose support made this possible. Also a big thanks to Cesar Hernández, because his help with ZEsarUX emulator
; and custom feature to load the ZXUno RAm made this possible in a reasonable time. Alsom, many thanks to Antonio Villena and Fernando Mosquera for their 
; support with firmware issues and for help getting ZX-Uno core synthesized
;
; What changes from McLeod's code?
; This bootloader basically does the same but:
; - Preserves a copy of the 32K ROM (the 128Ken one) included in McLeod's at SRAM slots 13 and 14, and then patches the ROM at several places before continuing:
;     1) At the memory check, which is skipped
;     2) At the place where the "(C) 1982 Sinclair..." message is about to be displayed, to jump to PATCHADDR instead
;     3) At PATCHADDR, where a routine is installed that is executed after ESXDOS is initialized
; - Jumps to 0 at the end without setting lock mode in MASTERCONF register. That allows going back to boot mode later and access all ZXUNO SRAM
; - In case a hard reset happens, the bootloader checks if the 32K rom is at SRAM slots 13 and 14 to recover it an run as in a fresh start
;
; Basically the rest is the same, but let's now explain what is done at PATCHADDR, because that is a complete different program, which is included
; in the bootloader only to be copied and run later:
;
; When the ROM patch at PATCHADD is run, aside of copying itself to RAM area (PATCHRUNADDR), it tries to find a file in the SD card named
; SMARTROM.ZX1, located at ZXUNO folder. If found, it is loaded at SMARTROMADDR and executed. This SmartROM is complete new piece of software which can
; enable and load other Spectrum ROMS, just as the ZX-UNO firmware does.
;
; If SMARTROM.ZX1 is not found, then the patch code tries still to boot a ZX-Spectrum. To do so, it restores the original 48K ROM that was saved at SRAM slot 3,
; then executes it. That way, even if the SMARTROM.ZX1 file is missing, or even the SD Card is missing, the Spectrum core can boot a Spectrum.

                       output "bootloader.bin"


                      define USE_SDRAM 1    ; Uncomment this line to generate code compatible with SDRAM  (does not use Turbo mode)


                      define ZXUNO_PORT           $FC3B
                      define TOASTRACKMAPPER      $7FFD
                      define PLUS2AMAPPER         $1FFD
                      define DIVIDECTRL           $0E3
                      define PATCHADDR            $3900
                      define PATCHRUNADDR         $6000
                      define ROM_CLS              $0DAF

                      define REG_MASTERCONF       $00
                      define REG_MASTERMAPPER     $01
                      define REG_SCANDBLCTRL      $0B
                      define REG_DEVCONTROL		    $0E
                      define REG_DEVCTRL2		    	$0F
                      define REG_SCANCODE         $04
                      define REG_KEYSTAT          $05
                      define REG_JOYCONF          $06
                      define REG_COREID           $FF
                      define REG_KEYMAP           $07

                      define ROMBASICENTRY        $1293    ; Address where the original 48K ROM enters the basic interpretr
                      define MEMCHECKADDR         $11DA    ; Address where the original 48K ROM makes the memory check


                      define CHECK128 74h                   ;Checksum of the 256 first bytes of Spectrum 128K ROM (System ROM 0)
                      define CHECK48 $E4                    ;Checksum of the 256 first bytes of Spectrum 48K ROM

                      define SMARTROMADDR         $A000    ; Where the SmartROM should be loaded
                      define SMARTROMSIZE         $4000    

                      define BANKM                $5B5C    ; System Variable


                      define M_GETSETDRV  	      $89      ; ESXDOS functions and parameters
                      define F_OPEN  		          $9a
                      define F_CLOSE 		          $9b
                      define F_READ  		          $9d
                      define FA_READ 		          $01

                      

                      ; -- Useful macro

                      MACRO _SETREG regID,value ; Sets ZXuno register at A to value at E
                      LD A, regID
                      LD BC, ZXUNO_PORT
                      OUT (C),A
                      INC B
                      LD A, value
                      OUT (C),A
                      ENDM



; *********************************************************************************************************
;                                              MAIN
; *********************************************************************************************************
                      ORG 0
                      

START                 DI
                      _SETREG REG_MASTERCONF, 1      ; This is mainly to make sure DivMMC is not active and boot mode is set after a a hard reset, when the ZxUno starts for the first time
                                                     ; MASTERCONF value is already 1. AFAIK this should not be needed in a real ZXUno


                      EXX                   ; We will use E' later to determine if we have done some specific action, it's set to 0 to say that action has not been done yet
                      LD E, 0
                      EXX

                                           
                      IFNDEF USE_SDRAM      ; if no a SDRAM machine, speed up
                      ld bc,ZXUNO_PORT
                      ld a,REG_SCANDBLCTRL
                      out (c),a
                      inc b
                      in a,(c)
                      or 0c0h             ;28 MHz 
                      out (c),a
                      ENDIF



; -- Step 1: check if 128K ROM is in $4000 (main screen)

CheckChecksum         ld hl, $4000
                      xor a
                      ld b,a
BucleChecksum         add a,(hl)
                      inc hl
                      djnz BucleChecksum
                      cp CHECK128
                      jp nz,NoArranqueInicial

;--- Step 2, move ROMs to their ROM slots
                      

                      ; Copy the 128K editor ROM to Banks 0 and 2
                      _SETREG REG_MASTERMAPPER, 8     ;System ROM 0
                     
                      ld hl,$4000
                      ld de,$c000
                      ld bc,$4000
                      ldir

                      _SETREG REG_MASTERMAPPER, 10    ;System ROM 2

                      ld hl,$4000
                      ld de,$c000
                      ld bc,$4000
                      ldir

                      _SETREG REG_MASTERMAPPER, 13    ; also backup to slot 13, to be used after a hard reset

                      ld hl,$4000
                      ld de,$c000
                      ld bc,$4000
                      ldir

                      ; Page in Shadow Screen as the 48K ROM should be there

                      _SETREG REG_MASTERMAPPER, 7     ; Bring back 48K ROM from Shadow Screen

                      IFDEF ZESARUX                   ; In ZesarUX, the 48K ROM comes at $8000, not at shadow screen, so we move it so the code after this can be the same
                      EXX
                      LD A, E
                      EXX
                      OR A                    
                      JR NZ, NoZesarUXRestart         ; But we do it only if it's fresh start, not after a hard reset
                      LD HL, $8000
                      LD DE, $C000
                      LD BC, $4000
                      LDIR
NoZesarUXRestart
                      ENDIF

                      
                      ; Make a copy at SRAM Bank 14 in case we need it unpatched later, and also to recover after a hard reset


                      LD HL, $C000  ; First make a copy at $4000 as temporary buffer
                      LD DE, $8000
                      LD BC, $4000
                      LDIR

                      

                      _SETREG REG_MASTERMAPPER, 14     ; Select SRAM 14 and make a copy there
                      LD HL, $8000
                      LD DE, $C000
                      LD BC, $4000
                      LDIR

                      _SETREG REG_MASTERMAPPER, 7     ; Back to shadow screen


; Step 2.1 -  Patch the 48K ROM before moving it

                      ; This is the SmartROM initialization code
                      ld hl, ROMPatch
                      ld de, PATCHADDR + $C000
                      ld bc, ROMPatchEnd - ROMPatch
                      ldir               

                      ; Also, shotcircuit the Memory Check code in the ROM to save time
                      LD HL, PatchMemCheck
                      LD DE, MEMCHECKADDR + $C000
                      LD BC, 6
                      LDIR

                      ; Finally, replace the call to print the usual "(C) 1982 Sinclair" message to call the SmartROM initialization code instead
                      LD HL, PATCHADDR 
                      LD (ROMBASICENTRY + $C000), HL
                  
                  
                      ; Now place the patched 48K ROM at the proper sytem rom slots

                      ld hl,$c000
                      ld de,$4000                       ; use $4000 as temporary buffer
                      ld bc,$4000
                      ldir

                      _SETREG REG_MASTERMAPPER, 9     ;System ROM 1
                      ld hl,$4000
                      ld de,$c000
                      ld bc,$4000
                      ldir

                      _SETREG REG_MASTERMAPPER, 11    ;System ROM 3
                      ld hl,$4000
                      ld de,$c000
                      ld bc,$4000
                      ldir

; -------- Now we place EXDOS at its proper SRAM slot too

                      _SETREG REG_MASTERMAPPER, 12    ; ESXDOS SRAM bank
                      ld hl,ESXDOSRom
                      ld de,$c000
                      ld bc,$2000
                      ldir

                      JR CantRecover                 ; No need to check if the ROMs are in bank slots 13 and 14, we have already loaded them

; ----  Step 3  - prepare last phase in RAM
NoArranqueInicial



                     EXX
                     LD A, E   ; get E' Value. If Zero we have not tried to restore default ROM backup from SRAM slots 13 and 14
                     EXX
                     OR A
                     JR NZ, CantRecover
                     EXX
                     LD E, $FF            ; Set E'=$FF so this doesn't become and endless loop
                     EXX

                    ; Now, restore backed up ROMs that originally were coming in BRAM
RecoverBackup        _SETREG REG_MASTERMAPPER, 14  ;  Second part of 32K ROM backup bank (the 48K RAM)
                     LD HL, $C000
                     LD DE, $4000
                     LD BC, $4000
                     LDIR

                     _SETREG REG_MASTERMAPPER, 7  ;  Bring up back to Shadow RAM
                     LD HL, $4000
                     LD DE, $C000
                     LD BC, $4000
                     LDIR

                     _SETREG REG_MASTERMAPPER, 13  ;  First part of 32K ROM backup bank (the 128K Basic editor)
                     LD HL, $C000
                     LD DE, $4000
                     LD BC, $4000
                     LDIR                         ;  Bring back to $4000, as it comes on start

                     _SETREG REG_MASTERMAPPER, 0  ;  back to normal



                     JP CheckChecksum             ; Try Checksum again. Note: there is a chance a program may be using slots 13 and 14 and recovery is impossible. 
                                                  ; Not very likely at the date this is written (January 2021), but maybe some upgrade uses those slots in the 
                                                  ; future or a given OS uses them. That's why the checksum is executed again, to be sure we are not just restoring
                                                  ; garbage, at least to an extent.


CantRecover           ld hl, UltimaFaseEnRAM
                      ld de,$8000
                      ld bc,LongUltimaFase
                      ldir

                      jp 8000h

; ---- Step 4 - machine setup

UltimaFaseEnRAM       

                      _SETREG REG_MASTERCONF, 00000010b  ; 48K timings, with DivMMC and ESXDOS, no locked and not boot mode

                      ld bc,TOASTRACKMAPPER
                      ld a,00010000b
                      out (c),a
                      ld bc,PLUS2AMAPPER
                      ld a,00000100b        
                      out (c),a                           ; Select System ROM 3

; -- Step 5  --- DivMMC RAM clearing to force reset
                      

                      ld a,80h    ;16 páginas de 8KB cada una + CONMEM
BucleEraseDivMMC      out (DIVIDECTRL),a
                      ld hl,$2000
                      ld de,$2001
                      ld bc,$1FFF
                      ld (hl),l
                      ldir
                      inc a
                      cp 90h
                      jr nz,BucleEraseDivMMC
                      xor a
                      out (DIVIDECTRL),a

; -- Step 6 - Go back to 3.5MHz and launch ROM with DivMMC support
                      _SETREG REG_SCANDBLCTRL, 0

                      JP 0
LongUltimaFase        equ $-UltimaFaseEnRAM

; *****************************************************************************************************************************
; ***************************** This is the code the bootloader places at PATCHADDR patching the ROM **************************
; *****************************************************************************************************************************
ROMPatch            DI

RomPatchCopy        LD HL, PATCHADDR + LoadSmartROM  - ROMPatch 
                    LD DE, PATCHRUNADDR
                    LD BC, ROMPatchEnd - LoadSmartROM
                    LDIR
                    LD SP, PATCHRUNADDR
                    JP PATCHRUNADDR

LoadSmartROM        
; --- Set default disk  
  
                    XOR	A  
                    RST $08 
                    DB M_GETSETDRV
                    JR  C, NoSmartROM

; --- open file     
                    LD IX, PATCHRUNADDR + SmartROMFileName - LoadSmartROM
                    LD B, FA_READ
					          RST $08
                    DB F_OPEN      
                    JR  C, NoSmartROM

                    LD (PATCHRUNADDR + CloseFile - LoadSmartROM + 1), A   ; Patches code below so F_CLOSE has the proper file handler

; --- reads the SmartROM
          		      LD IX, SMARTROMADDR
					          LD BC, SMARTROMSIZE
					          RST $08
					          DB  F_READ
                    JR  C, NoSmartROM

; --- Close file

CloseFile          	LD A, 0
					          RST $08
                    DB F_CLOSE

                    JP SMARTROMADDR           ; Execute SmartROM

; --- If /ZXUNO/SMARTROM.ZX1 file is not found, just bring back the backed-up 48K ROM and reboot
NoSmartROM          PUSH AF   ; Preserve error code

; -- Print error message

                    CALL ROM_CLS
                    LD HL, PATCHRUNADDR + ErrorMsg - LoadSmartROM
ErrorMsgLoop        LD A, (HL)
                    OR A
                    JR Z, EndErroMsgLoop
                    RST $10
                    INC HL
                    JR ErrorMsgLoop

EndErroMsgLoop      POP AF         ; Restore Error Core

DivByTen				    LD 	D, A		
						        LD 	E, 10		
						        LD 	B, 8
						        XOR 	A				
DivByTenLoop			  SLA	D
  						      RLA			
	  					      CP	E		
		  				      JR	C, DivByTenNoSub
			    	        SUB	E		
						        INC	D		
DivByTenNoSub	  		DJNZ DivByTenLoop    ; At the end A= reminder, D=quotient

                    LD E, A       ; preserve reminder

                    LD A, 13      ; Print a carriage return
                    RST $10

                    LD A, D
                    ADD '0'       ; print quotient
                    RST $10
                    LD A, E
                    ADD '0'
                    RST $10       ; print reminder

; --- A delay, so the error message can be seen

Pause               LD BC, 0      
PauseLoop           BIT 0, A
                    BIT 0, A
                    AND 255
                    DEC BC
                    LD  A,C
                    LD A, C
                    OR A, B
                    JR NZ,PauseLoop

; -- Restore backed up 48K ROM

                    _SETREG REG_MASTERCONF, 1    ; REG_MASTERMAPPER mode
                    _SETREG REG_MASTERMAPPER, 14  ; Bring back page 14 where we have a copy of unpatched 48K ROM


                    LD HL, $C000                ; Copy Backed up ROM contents to $4000
                    LD DE, $8000
                    LD BC, $4000
                    LDIR
                    
; --- Copy to System ROM 1 and 3 

                    _SETREG REG_MASTERMAPPER, 9  ; System ROM 1

                    LD HL, $8000                ; Copy ROM contents to $C000
                    LD DE, $C000
                    LD BC, $4000
                    LDIR

                    _SETREG REG_MASTERMAPPER, 11  ; System ROM 3

                    LD HL, $8000                
                    LD DE, $C000
                    LD BC, $4000
                    LDIR


; --- Back to normal mode and set some default configuration

                    _SETREG REG_MASTERCONF, 2    ;  Back to normal mode

                    _SETREG REG_DEVCONTROL, 0            ; Everything enabled but Timex MMU
                    _SETREG REG_DEVCTRL2, 7              ; Disable extra modes
                    _SETREG REG_SCANDBLCTRL, 0           ; RGB mode with PAL Sync and No turbo mode

; ------------ Page In Back System ROM 3 (usr 0)

                    _SETREG REG_MASTERCONF, $82          ; Enable DivMMC, Lock, and get out of boot mode

                    LD BC, TOASTRACKMAPPER       
                    LD A,00010000b
                    OUT (C), A
                    LD BC, PLUS2AMAPPER
                    LD A, 00000100b
                    OUT (C), A
                    

; -- And launch
                    DI
                    JP 1


ErrorMsg            DB "Not found: "
SmartROMFileName    DB "/ZXUNO/SMARTROM.ZX1", 0    ; The file name is placed here for easily point to it



ROMPatchEnd

; ----------------- This is the patch to avoid memory check
PatchMemCheck       LD HL, $FFFF
                    JP $11FF


                      IFDEF ZESARUX
                      ;FPOS 512
                      ;ORG 512
ESXDOSRom             INCBIN ASSETS\ESXMMC.BIN
                      FPOS 16383; Just to fill up to 16384 bytes
                      DB 0
                      ELSE 
ESXDOSRom                      
                      ENDIF
    
