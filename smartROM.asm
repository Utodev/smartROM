; Greetings: Antonio Villena and @mcleod_idefix for all the help. Andrew Owen for help with ULAPlus details and differences between standard and ZXUno implementation
;            César Hernández Baño for ZEsarUX debugger, absolutely needed for debugging this software.

                OUTPUT  smartROM.bin
                define SMARTROMADDR       $A000
                ORG SMARTROMADDR                           ; Code is place at the middle of third 16K page

; Why at A000?
; ------------
; Well, this SmartROM needs to switch between normal mode and boot mode in the ZX-Uno, when that happens, basically the second and third page of RAM stay the same (4000-7FFF and 8000-BFFF)                
; so they are good to move things from "one side to another" and to keep the code you are running (the smartROM code, somewhere there). On the other hand, at 4000 you have the screen area
; so it's not a good idea to put the code there because it will mess the screen, so initial decision was to put the code at 8000, and have the whole page 8000-BFFF for SmartROM code.
; On the other hand, when loading ROMs the code to load them has to use ESXDOS, and basically you cannot use ESXDOS in boot mode, because ESXDOS requires a compatible ROM to be present,
; and in boot mode the visible ROM  at 0000-3999 is the ZXUNO bootloader, which is not compatible.
;
; Also, the C000-FFFF segment in normal mode is visible in boot mode at C000, if MASTERMAPPER register is set to 0.
;
; So the way to move each 16K piece of ROM to their final slots in the ZXUNO SRAM, that can only be done in boot mode, is loading them to C000 in normal mode, then switch back to boot mode
; select SRAM bank 0 with MASTERMAPPER register, copy the content of C000-3FFF somewhere else, then select the proper SRAM page for the ROM area we want to update, and move back the content
; back from "somwhere else" to C000. 
;
; And there is when a problem poped up: in boot mode, at least in ZEsarUX that is essential for debugging, you cannot use the 0000-3FFF are as a temporary buffer, as "somewhere else", because
; it's not writable, so the other 16K slot available, as smartROM code was at 8000h, is 4000-7FFF. That works, you can use that segment as temporary buffer and everything works, but it has a side
; effect: when you use that area as a buffer the content is shown in screen, which of course procudes just random content. It was not terrible, but I prefered not to have it, so what I have done
; is making the code run at A000-BFFF, which is only 8K, but it should be enough, that way I have the 16K from 6000 to 9FFF free to use as temporary buffer, as somewhere else, and the screen area
; is not affected, as it uses not even  half of the 4000-7FFF bank.

; If we ever need the SmartROM be larger than 8K, then it will have to be moved to 8000h again, and make the screen artifacts appear, unless another solution, like trying to use the 128K pagination
; together with the MASTERMAPPER mode, if that is even possible, to obtain more RAM in boot mode. Take in mind though, that 8K is way a lot considering things like the keyboard map can be stored in
; the SD card instead of the RAM.


;*****************************************************************************************************************************************************
;   DEFINITIONS AND MACROS
;*****************************************************************************************************************************************************


                define VRAM_ADDR            $4000
                define VRAM_ATTR_ADDR       $5800
                define ZXUNO_PORT           $FC3B
                define ZXUNO_DATA           $FE3B
                define STACK                $C000 ;  We will place the stack just at the end of 3rd page, so we can paginate at $C000 when needed without having problems with STACK
                define REG_MASTERCONF       $00
                define REG_MASTERMAPPER     $01
                define REG_SCANDBLCTRL      $0B
    			define REG_DEVCONTROL		$0E
	    		define REG_DEVCTRL2			$0F
                define REG_SCANCODE         $04
                define REG_KEYSTAT          $05
                define REG_JOYCONF          $06
                define REG_COREID           $FF
                define ULAPLUS_PORT         $BF3B
                define ULAPLUS_DATA         $FF3B
                define FW_VERSION           "1.0 beta"
                define FRAMES               $5C78
                define TOASTRACKMAPPER      $7FFD
                define PLUS2AMAPPER         $1FFD

                define M_GETSETDRV  	$89
                define F_OPEN  		    $9a
                define F_CLOSE 		    $9b
                define F_READ  		    $9d
                define F_WRITE 		    $9e
                define F_SEEK		    $9f       
                define FA_READ 		    $01
                define FA_WRITE		    $02
                define FA_CREATE_AL	    $0C


                define STARTLINE 0


                INCLUDE "macros.inc"


;*****************************************************************************************************************************************************
;   MAIN
;*****************************************************************************************************************************************************

START           DI
                LD SP, $C000
                CALL TimexInit
                CALL CheckBootMode
                LD E, 3
                CALL SetSpeed
                CALL InitializeVars                 ; Restart this firmware variables


; --- Load Configuration
                CALL LoadConfig
                CALL ApplyConfig

; ---  Show (C) notice
                CALL CopyrightNotice

; ------------ Try to load ROM entries
                CALL LoadROMEntries
                JR C, RunEmbeddeROM
                LD A, (cfgDefaultROMIndex)                             
                LD L, A
                CALL LoadROM

RunEmbeddeROM   CALL UnPatchROM                   ; restores the current ROM to the original 48K ROM, so it can be started if no ROMS.ZX1 file is present
                
                IM 1
                EI

Loop            JR Loop



;*****************************************************************************************************************************************************
;   FUNCTIONS
;*****************************************************************************************************************************************************


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Pauses for about 1 second
Pause               LD BC, 0
PauseLoop           BIT 0, A
                    BIT 0, A
                    AND 255
                    DEC BC
                    LD  A,C
                    OR A, B
                    JR NZ,PauseLoop
                    RET
    

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Clears the Screen and shows CopyRight notice on top
CopyrightNotice CALL ClearScreen
                CALL RestoreCursor
                _WRITE "SmartROM "
                _WRITE FW_VERSION
                _WRITE " for ZX-Uno (C) Uto 2021."
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Shows the boot screen
               
BootScreen      CALL CopyrightNotice
                LD C, 0
                LD B, STARTLINE+1
                CALL DrawHeaderFrame

                ; Show Core ID
                _PRINTAT 2, STARTLINE + 2
                _WRITE "CoreID: "
                CALL PrintCoreID

                ;Show Timings status
                _PRINTAT 2, STARTLINE+3
                _WRITE "ULA Timing: Auto"

                ;Show DivMMC mode
                _PRINTAT 34, STARTLINE+3
                _WRITE "DivMMC: Auto"

                ;Show New graphic modes
                _PRINTAT 2, STARTLINE+4
                _WRITE "New graphic modes: Auto"

                ;Show Keyboard mode
                _PRINTAT 34, STARTLINE+4
                _WRITE "Keyboard layout: Spectrum"

                ;Show  NMI-DiVMMC Status
                _PRINTAT 2, STARTLINE+5
                _WRITE "NMI-DivMMC: Auto"

                ;Show Contended Memory Status
                _PRINTAT 34, STARTLINE+5
                _WRITE "Contended memory: Auto"

                _PRINTAT 22, STARTLINE+7
                _WRITE "http://zxuno.speccy.org"

BootScreenEnd   _PRINTAT 1, 21
                _WRITE "<Break> for ROM Selection - <Edit> for Setup - <Ctrl+n> ROM #n"
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Prints char provided at A register

PrintChar       EXX                     ; IMPORTANT: Please keep this EXX here, or if you change it, make sure you updahe the place where PrintChar routine is patched
                LD H, 0
                LD L, A
                ADD HL, HL
                ADD HL, HL
                ADD HL, HL              ; HL = A * 8
                LD DE, Font - 128       ; Points to place where chr(0) would be. The font.bin file misses the first 16 characters, so that's why -128
                ADD HL, DE              ; Now HL points to where the character definition is.
                LD DE, (V_PRINT_POS)
                LD B, 8
PrintCharLoop   LD A, (HL)
                LD (DE), A
                INC HL
                INC D                   ; Point to next row in screen
                DJNZ PrintCharLoop
                CALL MoveCursorTmx    ; Update cursor position                    
                EXX
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Sets Turbo Speed at D

SetSpeed        LD A, E
                AND 3
                RRCA
                RRCA
                LD D, A
                _GETREG REG_SCANDBLCTRL
                AND 00111111b
                OR D
                LD B, A
                _SETREGB REG_SCANDBLCTRL
                RET
              
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Prints Zero terminated string placed pointed by top value in the stack

PrintString     EX (SP),HL
PrintStringLoop LD A,(HL)
                OR A                  
                JR Z, PrintStringEnd
                CALL PrintChar
                INC HL
                JR PrintStringLoop
PrintStringEnd  INC HL
                EX (SP),HL
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Prints 32 characters pointed by HL
PrintString32  LD B, 32
PrintStr32Loop LD A,(HL)
               PUSH BC 
               PUSH HL
               CALL PrintChar
               POP HL
               INC HL
               POP BC
               DJNZ  PrintStr32Loop
               RET



; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Advances printing cursor one character

MoveCursorTmx   PUSH HL
                PUSH DE
                PUSH AF
                PUSH BC
                LD HL, (V_PRINT_POS)
                LD DE, $2000
                LD A, H
                CP $60
                JR NC, MoveCursorTmx2
                ADD HL, DE
                LD (V_PRINT_POS), HL
                JR MoveCursorExit
MoveCursorTmx2  OR A            ; Clear carry flag
                SBC HL, DE
                LD (V_PRINT_POS), HL
                PUSH HL
                CALL MoveCursor
                POP HL
MoveCursorExit  POP BC
                POP AF
                POP DE
                POP HL
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Advances printing cursor one character

MoveCursor      LD HL, V_PRINT_POS
                INC (HL)
                RET NZ
                INC HL
                LD A, (HL)
                ADD A, 8
                LD (HL), A
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Clears all pixels in screen area
ClearScreen     LD HL, VRAM_ADDR
                LD BC, 192*32
                CALL ClearMem
                LD HL, VRAM_ADDR + $2000
                LD BC, 192*32
                CALL ClearMem
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Clears (sets to 0, area at HL, BC length)                
ClearMem        PUSH DE
                XOR A
                LD (HL),A
                PUSH HL
                POP  DE
                INC DE
                DEC BC
                LDIR
                POP DE
                RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Sets Timex HiResMode

TimexInit       _SETREG REG_DEVCONTROL, 11111011b ; Make sure bit 2, DI7FFD, is 0
                _SETREG REG_DEVCTRL2,   11111100b ; make sure bits 0 and 1, DITIMEX and DIULAPLUS, value is 0

                LD A, 00111110b 			  ; Enable Timex mode (HiRes)
        		OUT (255),A

SetPalette		LD A, 24                ; Paper
                LD E, 0
                CALL SetULAPlusReg


                LD A, 23                ; INK for ZX-Uno with old buggy core
                LD E, 10110110b
                CALL SetULAPlusReg

                LD A, 31                ; INK for ZX Uno with new core, or for ZEsarUX, which does not have that bug
                LD E, 10110110b
                CALL SetULAPlusReg
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Writes value E to ULAPlus register A

SetULAPlusReg   LD BC, ULAPLUS_PORT     ; Set paper to RGB 00000000
				OUT (C),A
				LD BC, ULAPLUS_DATA
				LD A, E
				OUT (C),A
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Draws a specific full with box for header

DrawHeaderFrame CALL PrintAt
                CALL PrintString
                DB 16, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 18, 0
                LD B, 4
HeaderInner     CALL PrintString
                DB 23, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 32, 19, 0
                DJNZ HeaderInner
                CALL PrintString
                DB 22, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 21, 20, 0
                RET
             
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Draws a Box at Column C, line B, with D width and E height

DrawBox         PUSH BC 
                DEC D               ; Make the height and with -2, to count just the inner borders, not the corners
                DEC D
                DEC E
                DEC E
                PUSH DE
                CALL PrintAt        ; Place at position
                POP DE
                ;Draw upper border
                LD A, 16                ; up-left coner
                CALL PrintChar
                LD B, D
BoxUpLoop       LD A, 17                ; top norder
                CALL PrintChar
                DJNZ BoxUpLoop
                LD A, 18                ; Up-right border
                CALL PrintChar
                

                ; Draw inner border
                LD  H, E                ; H used for loop instead of B
BoxInnerLoop    POP BC
                INC B
                PUSH BC                 ; Point to Next line and preserve it
                PUSH DE
                PUSH HL
                CALL PrintAt
                POP HL
                POP DE
                LD A, 23                 ;Left border
                CALL PrintChar
                LD B, D
BoxInner2Loop   LD A, ' '                 ; Filler spaces
                CALL PrintChar
                DJNZ BoxInner2Loop
                LD A, 19                ;Right Border
                CALL PrintChar
                DEC H
                JR NZ, BoxInnerLoop 

                ;Draw lower border
                POP BC
                INC B                   ; Move cursor once again
                PUSH DE
                CALL PrintAt                               
                POP  DE
                LD A, 22                ; lower-left
                CALL PrintChar
                LD B, D
BoxDownLoop     LD A, 21                ; Lower border
                CALL PrintChar
                DJNZ BoxDownLoop
                LD A, 20                ; lower-right
                CALL PrintChar
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ PENDING: Unpatch the ROM so the patched ROM can be used as normal ROM in case the ROMS.ZX1 file is absent

UnPatchROM      RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Moves cursor n characters right, if end of line, continues in next line. Number of tabs provided at B                

Tabs            CALL MoveCursorTmx
                DJNZ Tabs
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Moves the cursor to column C, line B

PrintAt         CALL RestoreCursor
PrintAtLoop     PUSH BC
                LD B, 64
                CALL Tabs
                POP BC
                DJNZ PrintAtLoop
                LD A, C                 ; Discard if column is 0
                OR A
                RET Z
                LD B, C
                CALL Tabs
                RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Initializes firmware system vars when ZX-Uno starts

InitializeVars XOR A                        
               CALL RestoreCursor       ; Now place Cursor at 0,0
               RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Places writing position at 0,0

RestoreCursor   LD DE, VRAM_ADDR
                LD (V_PRINT_POS), DE
                RET              



; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Sets a register A to value E

SetZXUNOReg     PUSH BC
                LD BC, ZXUNO_PORT
                OUT (C),A
                INC B
                LD  A, E
                OUT (C),A
                POP BC
                RET



; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Gets  value of ZXUno register

GetZXUnoReg     PUSH BC
                LD BC, ZXUNO_PORT
                OUT (C),A
                INC B
                IN A, (C)
                POP BC
                RET                                



; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Gets and prints the coreID

PrintCoreID     LD BC, ZXUNO_PORT
                LD A, REG_COREID
                OUT (C),A
                LD  A, B
                INC B
PrintCoreLoop   IN A, (C)
                OR A
                RET Z
                CP 32
                JR C, CoreIDInvalid  ; Invalid value <32
                CP 128
                JR NC, CoreIDInvalid ; Invalid value > 127
                CALL PrintChar
                JR PrintCoreLoop
CoreIDInvalid   _WRITE "Legacy"
                RET



; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Checks if we are in boot mode and freezes if not

CheckBootMode  _GETREG REG_MASTERCONF
               AND 128
               RET Z
               _WRITE "ZX-Uno MASTERCONF should have LOCK = 0"              
               DI
               HALT



; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Loads the entries at the Entries buffer, if /ZXUNO/ROMS.ZX1 file exists

LoadROMEntries     LD IX, ROMSEtFilename

; --- open file
                    LD      B, FA_READ   
					RST     $08
                    DB      F_OPEN      
                    RET C
; --- Dynamically update the F_CLOSE call later on
                    LD (CloseFileEntries + 1),A

; --- reads the entry information
ReadEntryInfo		LD 	IX, ROMDirectory
					LD BC, 4096 ; Size of the entries information
					RST $08
					DB  F_READ
                    RET C
; --- Close file
CloseFileEntries	LD 		A, 0
					RST     $08
                    DB      F_CLOSE
                    RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Loads the ROM at entry L

LoadROM             LD H, 0
                    ADD HL, HL
                    ADD HL, HL
                    ADD HL, HL
                    ADD HL, HL
                    ADD HL, HL
                    ADD HL, HL    ; HL * 64
                    LD D, H
                    LD E, L
                    LD IY, ROMDirectory
                    ADD IY, DE     ; Now IY Points to entry

; --- Print ROM name and details
                    _PRINTAT 0, STARTLINE + 1
                    _WRITE "ZX-Uno (C) ZX-Uno Team - http://zxuno.speccy.org"

                    _PRINTAT 0, STARTLINE + 3
                    _WRITE "Loading ROM: "
                    LD DE, 32
                    PUSH IY
                    POP HL
                    ADD HL, DE
                    CALL PrintString32
                    
                    _PRINTAT 0, STARTLINE + 4
                    _WRITE "Number of ROM slots: "                    
                    LD A, (IY+1)
                    ADD A, 48
                    CALL PrintChar
                    
                    _PRINTAT 0, STARTLINE + 5
                    _WRITE "CoreID: "
                    CALL PrintCoreID



                    _PRINTAT 1, 21
                    _WRITE "<Break> for ROM Selection - <Edit> for Setup - <Ctrl+n> ROM #n"

KeyLoop              CALL GetKey
                     OR A
                     JR NZ, KeyLoop
                
                    _GETREG REG_DEVCONTROL      ; Patch to make  sure Timex MMU is disabled, as somehow ZEsarUX bug (v 9.1) ignores mastermapper if it is active
                    AND 10111111b               ;
                    LD E, A                     ;
                    _SETREGB REG_DEVCONTROL     ;
                    CALL ClearScreen            ; Also clear the screen before loading


; --- open file
                    LD      IX, ROMSEtFilename
                    LD      B, FA_READ   
					RST     $08
                    DB      F_OPEN      
                    RET C

; -- Update CloseFile so it uses the proper file handler
                    LD (CloseFile + 1),A
                    LD (SeekLoopHandler+1),A
                    LD (ReadROMHandler+1),A

; --- seek up to first ROM position

					LD BC, 0   			 ; BCDE --> Offset 
                    LD DE, 4096 + 65     ; The entries plus 65 bytes not used in the ROMS.ZX1 file
					LD IXL, 1 			 ; IXL = 1 --> Seek from current position
					RST	$08
					DB	F_SEEK
                    RET C

; Seek Up to expected ROM Offset, it's done by seeking 16384 bytes forward n times, once the file is at $1041, where the ROMs start

SeekSlot
; -- First we check it it's Slot 0
                    LD E, A             ; Preserve file handler
                    LD A, (IY + 0)      ; Get Slot Number
                    OR A                   
                    JR Z, AfterSeek     ; Checks the OR above the LD A, if zero, it's first slot, skip loop
                    LD A, E             ; Restore file handler
                    LD B, (IY+0)        ; Get slot number again
FSeekLoop           PUSH BC
					LD BC, 0   			 ; BCDE --> Offset 
                    LD DE, 16384         ; One seek per slot
					LD IXL,1 			 ; L=1 --> Seek from current position
SeekLoopHandler     LD A ,0              ; This is the file handler, that 0 is modified above just after FOPEN
					RST	$08
					DB	F_SEEK
                    JR C, FSeekFail
                    POP BC
                    DJNZ FSeekLoop
                    JR  AfterSeek
FSeekFail           POP BC
                    RET                    

      
;  --- Disable Timex Mode before loading any ROM to avoid writing at $6000 being visible on screen
AfterSeek           XOR A
                    OUT (255),A                 ; Disable timex mode
                    OUT (254), A                 ; Border 0




ReadROMPages        LD B, (IY+1)                ; Get number of slots for this ROM. B will count the number of slots left to save
                    LD E, 8                     ; SRAM slot for System ROM 0 is slot 7 with MASTERMAPPER, the following ROM slots are 9, 10 and 11, so E will point to next SRAM slot to use
RomPagesLoop        PUSH BC
                    PUSH DE
                    

; --- read a 16K block ROM from file
ReadROMFromFile     LD IX, $C000
                    LD BC, $4000
ReadROMHandler      LD A, 0                      ; the 0 is the file handler, updated above
                    RST $08
                    DB F_READ


; --- Now go back to boot mode and put the ROM at C000 in the proper SRAM ROM slot

                    _SETREG REG_MASTERCONF, 1   ; Activate boot mode and disable DivMMC
                    _SETREG REG_MASTERMAPPER, 0   ; Make page selected at C000 be page 0, which happens to be the same page selected at C000 when boot mode is off
                    LD HL, $C000
                    LD DE, $6000
                    LD BC, $4000
                    LDIR                    ; Copy from C000 to 0000 (which in boot mode, is the BRAM)
                    POP DE                  ; restore E (slot number)
                    _SETREGB REG_MASTERMAPPER   ; System ROM 
                    INC E
                    PUSH DE
                    LD HL, $6000
                    LD DE, $C000
                    LD BC, $4000
                    LDIR                    ; Copy back from BRAM to the proper slot
                    _SETREG REG_MASTERMAPPER, 0   ; Revert to normal mastermapper bank (probably not necessary)
                    _SETREG REG_MASTERCONF, 2   ; back to user mode and DivMMC Enabled
                    POP DE
                    POP BC
                    DJNZ RomPagesLoop

; --- Close file
CloseFile			LD 		A, 0
					RST     $08
                    DB      F_CLOSE


; --- Now that the ROMs are at their proper places, let's go and load ROM settings

/*---------------------------------------------------------------------
The flags included in ROMS.ZX1:

 flags 1 (IY+2)
      Bits 0-1. Machine timings: 00=48K, 01=128K, 10=Pentagon
      Bit 2. NMI DivMMC: 0=disabled, 1=enabled
      Bit 3. DivMMC: 0=disabled, 1=enabled
      Bit 4. Contention: 0=disabled, 1=enabled
      Bit 5. Keyboard issue: 0=issue 2, 1=issue 3
  flags 2 (IY+3)
      Bit 0. AY chip: 0=enabled, 1=disabled
      Bit 1. 2nd AY chip (TurboSound): 0=enabled, 1=disabled
      Bit 2. 7ffd port: 0=enabled, 1=disabled
      Bit 3. 1ffd port: 0=enabled, 1=disabled
      Bit 4. ROM low bit: 0=enabled, 1=disabled
      Bit 5. ROM high bit: 0=enabled, 1=disabled
      Bit 6. horizontal MMU in Timex: 0=disabled, 1=enabled
      Bit 7. DivMMC and ZXMMC ports: 0=enabled, 1=disabled
  flags 3 (IY+4)
      Bit 0:Disable ULAPlus
      Bit 1: Disable Timex Modes
      Bit 2: Disable Radastan mode

      Flags 2 and 3 exactly match the DEVCONTROL and DEVCTRL2 registers. Flag 1 contains values for MASTERCONF but not in the same order
-------------------------------------------------*/

SetROMSettings      LD A, (IY+3); Flags 2
RomSetDevControl    OR 0 
                    AND $FF                         ; This AND and OR may be modified above to force specific settings and ignoring the ROM settings
                    LD E, A
                    _SETREGB REG_DEVCONTROL

                    LD A, (IY+4); Flags 3
RomSetDevCtrl2      OR 0 
                    AND $FF                         ; This AND and OR may be modified above to force specific settings and ignoring the ROM settings
                    LD E, A
                    _SETREGB REG_DEVCTRL2

                    CALL PrepareMasterConf          ; Flags 1 comes with values needed in MASTERCONF, but not the same order
RomSetMasterConf    OR  10000000b                   ; Make sure LOCK is active
                    AND $FF                         ; This AND and OR may be modified above to force specific settings and ignoring the ROM settings
                    LD E, A  
                    PUSH AF                         ; Preserve MASTERCONF valus                      
                    _SETREGB REG_MASTERCONF         


                    LD E, 0
                    CALL SetSpeed                   ; Back to normal Speed

                    POP AF
                    AND 2
                    JP Z, 00000h                     ; If no DivMMC, we jump to 0000 to run System ROM 0

; -- We have DivMMC active

                    LD A, (IY+1)                    ; Make sure USR 0 mode is set when needed, that is, when there is more than one ROM slot
                    DEC A                           ; A = Number of slots -1
                    OR A                   
;
USR0                CALL NZ, SetUSROMode            ; And set USR 0 mode for that specific number of slots

                    DI                              ; Otherwise simulate first instruccion in ESXDOS compatible ROMs (DI) and jump to 1 to avoid ESXDOS to page in at 0000 trap
                    JP 1


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ The ROMS.ZX1 file comes with the configuration for MASTERCONF in a different order
; ************ than the one expected by MASTERCONF. Also, some values are the other way around, that
; ************ is, 1 becomes 0 and viceversa. This routine sorts it out and returns the value in A
;
;    IN:
;
; Bits 0-1. Machine timings: 00=48K, 01=128K, 10=Pentagon
; Bit 2. NMI DivMMC: 0=disabled, 1=enabled
; Bit 3. DivMMC: 0=disabled, 1=enabled
; Bit 4. Contention: 0=disabled, 1=enabled
; Bit 5. Keyboard issue: 0=issue 2, 1=issue 3
;      
;      OUT: 7-LOCK	6-MODE1	5-DISCONT	4-MODE0	3-I2KB	2-DISNMI	1-DIVEN	0-BOOTM



PrepareMasterConf   LD HL, AUX    ; We will be storing here her
                    XOR A
                    LD (HL),A 
                    LD E, (IY+2) ; Flags 1
                    LD A, E
                    AND 00010000b   ; Contention, bit 4 IN
                    JR NZ, CheckDivMMC  ; To keep MemoryContention active, bit 5 must be 0 as it is DISCONT (Disable Contention)
                    SET 5, (HL)
CheckDivMMC         LD A, E
                    AND 00001000b   ;  DivMMC, bit 3 IN
                    JR Z, CheckNMI  ; To keepDivMMC active, bit 1 must be 1 as it is DIVEN (DiVMMC ENabled)
                    SET 1, (HL)
CheckNMI            LD A, E
                    AND 00000100b   ;  NMI, bit 2 IN
                    JR NZ, KeyboardIssue  ; To keepDivMMC active, bit 1 must be 1 as it is DIVEN (DiVMMC ENabled)
                    SET 2, (HL)
KeyboardIssue       LD A, E
                    AND 00100000b   ;  Keyboard Issue, bit 5 IN
                    JR NZ, TimingsLow  ; the input value is negated, so if NZ we keep 0, otherwise we set
                    SET 3, (HL)
TimingsLow          LD A, E          ; Low bit for the timings, move from bit 0 to bit 4
                    AND 1
                    JR Z, TimingsHigh
                    SET 4, (HL)
TimingsHigh         LD A, E          ; Low bit for the timings, move from bit 0 to bit 4
                    AND 2
                    JR Z, CompletedMConf
                    SET 6, (HL)
CompletedMConf      LD A, (HL)
                    RET                    

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Sets USR 0 mode so the ROM Starts in 48K mode and - main reason - so ESXDOS and DivMMC work fine
; ************ A = Number of additional slots (other than the first one)


SetUSROMode         LD D, A                       ; IMPORTANT: DON'T CHANGE THIS LD D, A, or if you do, check where this address is patched to patch it properly
                    AND  1                        ; 1 or 3 slots more
                    JR Z, USR0Continue
                    LD BC, TOASTRACKMAPPER        ; If 1 or 3 slots more, we will use System ROM 1 or 3
                    LD A,00010000b
                    OUT (C), A

USR0Continue        LD A, D                       ; If it's 3 more, we will use System ROM 3
                    AND 2
                    RET Z
                    LD BC, PLUS2AMAPPER
                    LD A, 00000100b
                    OUT (C), A
                    RET

; --  Notice: in case it's 2 additional slots, that is, 3 in total, we will end up using System ROM 2, which is actually las slot used, so in the end
;     this makes the ROM use the last slot created.
                    
; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Load Configuration from file

; --- Set default disk  
LoadConfig          XOR	A  
                    RST     $08 
                    DB      M_GETSETDRV

; --- open file
                    LD      B, FA_READ   
					RST     $08
                    DB      F_OPEN      
                    RET C

; --- Dynamically update the F_CLOSE call later on
                    LD (CloseFileCfg + 1),A

; --- reads the entry information
ReadConfig  		LD 	IX, ConfigurationBEGIN
					LD BC, ConfigurationEND - ConfigurationBEGIN
					RST $08
					DB  F_READ
                    RET C
; --- Close file
CloseFileCfg    	LD 		A, 0
					RST     $08
                    DB      F_CLOSE
                    RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Applies the configuration in the way as much as is possible

ApplyConfig         LD A, (cfgDevcontrolOR)         ; Modify code above so the OR and AND for DevControl Are applied
                    LD (RomSetDevControl + 1), A
                    LD A, (cfgDevcontrolAND)
                    LD (RomSetDevControl + 3), A

                    LD A, (cfgDevctrl2OR)         ; Modify code above so the OR and AND for DevControl Are applied
                    LD (RomSetDevCtrl2 + 1), A
                    LD A, (cfgDevctrl2AND)
                    LD (RomSetDevCtrl2 + 3), A

                    LD A, (cfgMasterControlOR)         ; Modify code above so the OR and AND for Mastefconf Are applied
                    LD (RomSetMasterConf + 1), A
                    LD A, (cfgMasterControlAND)
                    LD (RomSetMasterConf + 3), A

                    LD A, (cfgSCANDBLCTRL)
                    LD E, A
                    _SETREGB REG_SCANDBLCTRL



                    LD A, (cfgBoot128KMode)
                    OR A
                    JR Z, UseUsr0
                    LD A, $C9; RET
UseUsr0             LD A, $57; LD D, A
                    LD (SetUSROMode), A


                    LD A, (cfgSilentMode)
                    OR A
                    JR Z, UseVerboseMode
                    LD A, $C9; RET
UseVerboseMode      LD A, $D9; EXX
                    LD (PrintChar), A

                    RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Returns key or joy pressed pressed at A, following the next table:
;
;      O, 5, Shift+5,  CursorLeft        --> $05         ESC  -> $0A
;      A, 6, Shift+6,  CursorDown        --> $06         F1 --> $0B
;      Q, 7, Shift+4,  CursorUp          --> $07         
;      P, 8, Shift+8, Cursor Right       --> $08
;      Space, 0, enter                   --> $00         No key or invalid key --> $FF

GetKey          _GETREG REG_KEYSTAT   
                LD E, A
                AND 1
                JR Z, NoKey
                
                XOR A
                LD C, A                 ; C will be zero if not extended key, 1 if extended                               
                _GETREG REG_SCANCODE
                CP $E0
                JR NZ, GetKey1
                _GETREG REG_SCANCODE
                LD C, 1                 ; It's a extended key
                OR A

; -- Check if key pressed is one of the valid ones    

GetKey1         CP $05 ; F1 
                JR NZ, GetKey2
                LD A, $0B
                RET
                
GetKey2         CP $76 ; ESC
                JR NZ, GetKey3
                LD A, $0A
                RET

; -- Now the intro/toggle ones

GetKey3         CP $29 ; SPACE
                JR NZ, GetKey4
IntroKey        XOR A
                RET

GetKey4         CP $45 ; 0
                JR Z, IntroKey

GetKey5         CP $5A ; ENTER
                JR Z, IntroKey

; --  Now the "Right" ones
GetKey6         CP $3E ; 8
                JR NZ, GetKey7
RightKey        LD A, $08
                RET

GetKey7         CP $4D ; P                
                JR Z, RightKey

GetKey8         CP $74 ; Right arrow (extended)
                JR NZ, GetKey9
                LD A, C     ; It's extended
                AND 1
                JR Z, RightKey

; --  Now the "Left" ones                

GetKey9         CP $3E ; 5
                JR NZ, GetKey10
LeftKey         LD A, $05
                RET

GetKey10        CP $44 ; O
                JR Z, LeftKey

GetKey11        CP $6B ; Left arrow (extended)
                JR NZ, GetKey12
                LD A, C     ; It's extended
                AND 1
                JR Z, LeftKey


; --  Now the "Up" ones                

GetKey12        CP $3D ; 7
                JR NZ, GetKey13
UpKey           LD A, $07
                RET

GetKey13        CP $15 ; Q
                JR Z, UpKey

GetKey14        CP $75 ; Up arrow (extended)
                JR NZ, GetKey15
                LD A, C     ; It's extended
                AND 1
                JR Z, UpKey

; --  Now the "Down" ones                

GetKey15        CP $36 ; 6
                JR NZ, GetKey16
DownKey         LD A, $07
                RET

GetKey16        CP $1C ; A
                JR Z, DownKey

GetKey17        CP $72  ; Up arrow (extended)
                JR NZ, GetKey18
                LD A, C     ; It's extended
                AND 1
                JR Z, DownKey

GetKey18
NoKey           LD A, $FF
                RET



;*****************************************************************************************************************************************************
;   THE FONT
;*****************************************************************************************************************************************************

Font                INCBIN     assets\font.bin

;*****************************************************************************************************************************************************
;   VARIABLES
;*****************************************************************************************************************************************************

; -- ROM Directory
ROMSEtFilename      DB 'ZXUNO\ROMS.ZX1', 0
ROMDirectory        DS 4096

; -- Config File
CFGFilename         DB 'ZXUNO\ZXUNO.CFG',0

ConfigurationBEGIN
cfgMasterControlOR  DB 0        ; When a ROM file is loaded, its setting will pass through this OR and AND masks (flags1)
cfgMasterControlAND DB $FF
cfgDevcontrolOR     DB 0        ; When a ROM file is loaded, its setting will pass through this OR and AND masks (flags2)
cfgDevcontrolAND    DB $FF
cfgDevctrl2OR       DB 0        ; When a ROM file is loaded, its setting will pass through this OR and AND masks (flags3)
cfgDevctrl2AND      DB $FF
cfgSCANDBLCTRL      DB 0        ; Saves the SCANDBLCTRL value, but the turbo bits will be ignored and always set to 00
cfgKeyMap           DB 0        ; 1 - Loads /ZXUNO/ENGLISH.KEY, 2- Loads /ZXUNO/SPECTRUM.KEY, 3 - Loads /ZXUNO/CUSTOM.CFG. Any other value loads nothing and defaults to Spanish
cfgDefaultROMIndex  DB 0        ; Rom Index (not the slot, the index in the ROMS.ZX1 "directory")
cfgSilentMode       DB 0        ; 0 - verbose, 1 - silent
cfgDelay            DB 0        ; 0 - standard delay on boot, any other value, delay in ~seconds
cfgBoot128KMode     DB 0        ; 0 - starst in USR mode those ROMS with DivMMC, 1 - Starts ROM normally (risky)
cfgReserved         DS 12
ConfigurationEND                              
                               


; -- Variables for internal use
V_PRINT_POS             DB 0
AUX                     DB 0

;*****************************************************************************************************************************************************
;   FILLER
;*****************************************************************************************************************************************************
                       FPOS 16383; Just to fill up to 16384 bytes
                       DB 0
