; Greetings: Antonio Villena and @mcleod_idefix for all the help. Andrew Owen for help with ULAPlus details and differences between standard and ZXUno implementation
;            César Hernández Baño for ZEsarUX debugger, absolutely needed for debugging this software.

                OUTPUT  smartROM.bin
                define SMARTROMADDR       $A000
                ;define USE_SDRAM 1    ; Uncomment this line to generate code compatible with SDRAM  (does not use Turbo mode)
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
; effect: when you use that area as a buffer the content is shown in screen, which of course produces just random content. It was not terrible, but I prefered not to have it, so what I have done
; is making the code run at A000-BFFF, which is only 8K, but it should be enough, that way I have the 16K from 6000 to 9FFF free to use as temporary buffer, as "somewhere else", and the screen area
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
                define REG_KEYMAP           $07
                define ULAPLUS_PORT         $BF3B
                define ULAPLUS_DATA         $FF3B
                define FRAMES               $5C78
                define TOASTRACKMAPPER      $7FFD
                define PLUS2AMAPPER         $1FFD
                define PATCHADDR            $3900
                define ROMBASICENTRY        $1293
                define MEMCHECKADDR         $11DA
                define BANKM                $5B5C

                define FW_VERSION           "release A (Atic Atac)"

                define M_GETSETDRV  	$89
                define F_OPEN  		    $9a
                define F_CLOSE 		    $9b
                define F_READ  		    $9d
                define F_WRITE 		    $9e
                define F_SEEK		    $9f       
                define FA_READ 		    $01
                define FA_CREATE_AL	    $0C

                define KEY_1            $01
                define KEY_2            $02
                define KEY_3            $03
                define KEY_4            $04
                define KEY_5            $05
                define KEY_6            $06
                define KEY_7            $07
                define KEY_8            $08
                define KEY_9            $09
                define KEY_0            $00

                define KEY_Q            $17
                define KEY_A            $16
                define KEY_O            $15
                define KEY_P            $18

                define KEY_D            $30
                define KEY_F            $31
                define KEY_R            $32

                define KEY_SPACE        $0A
                define KEY_ENTER        $0B
                define KEY_M            $20
                define NO_KEY           $FF



                define STARTLINE 0


                INCLUDE "macros.inc"


;*****************************************************************************************************************************************************
;   MAIN
;*****************************************************************************************************************************************************

START           DI
                LD A, 7
                OUT ($FE), A
                LD SP, $C000
                CALL TimexInit
                CALL CheckBootMode
                CALL SetTurboSpeed
                CALL InitializeVars                 ; Restart this firmware variables


;Patch to make  sure Timex MMU is disabled, as somehow ZEsarUX bug (v 9.1) ignores mastermapper if it is active

                _GETREG REG_DEVCONTROL      ; 
                AND 10111111b               ;
                LD E, A                     ;
                _SETREGB REG_DEVCONTROL     ;


; --- Load Configuration
                CALL LoadConfig
                CALL ApplyConfig

; ---- Load Keymap file if exists
                CALL LoadKeyMap                

; ---  Show (C) notice
                CALL CopyrightNotice

; ------------ Try to load ROM entries
                CALL LoadROMEntries
                JR C, RunEmbeddeROM
                LD A, (cfgDefaultROMIndex)                             
                LD L, A
                JP LoadROM


RunEmbeddeROM   _PRINTAT 0, 3
                _WRITE "Unable to find ROMS.ZX1 at /ZXUNO/ folder"
                _PRINTAT 0, 4
                _WRITE "Press <enter> to load embedded ROM"




EmbeddedKeyLoop CALL GetKey
                CP KEY_ENTER
                JR NZ, EmbeddedKeyLoop

EmbeddedGo      XOR A
                OUT (255), A                 ; Disable timex mode
                OUT (254), A                 ; Border 0

                CALL SetNormalSpeed                   ; Back to normal Speed

                CALL UnPatchROM                      ; restores the current ROM to the original 48K ROM, so it can be started if no ROMS.ZX1 file is present


; -- Set the device so it becomes a 128K +2A with a 48K ROM with DivMMC active and NMI
                _SETREG REG_DEVCONTROL, 0            ; Everything enabled but Timex MMU
                _SETREG REG_DEVCTRL2, 7              ; Disable extra modes

; ------------ Page In Back System ROM 1 (48K ROM)

                LD   BC,$7FFD       ; I/O address of horizontal ROM/RAM switch
                LD   A,(BANKM)      ; get current switch state
                OR   $10            ; System ROM 1
                LD   (BANKM),A      ; update the system variable (very important)
                OUT  (C),A          ; make the switch						

                _SETREG REG_MASTERCONF, $82          ; Enable DivMMC, Lock, and get out of boot mode



; -- And launch
                DI
                JP 1




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
Inverse         XOR 0
                LD (DE), A
                INC HL
                INC D                   ; Point to next row in screen
                DJNZ PrintCharLoop
                CALL MoveCursorTmx    ; Update cursor position                    
                EXX
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Sets Inverse mode for PrintChar (A=1 inverse, A=0 normal)

SetInverseMode  OR A
                JR NZ, IsInverse
                XOR A
                LD (Inverse+1), A ; XOR 0
                RET
IsInverse       LD A, $FF         
                LD (Inverse+1), A ; XOR FF
                RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Sets Turbo Speed

SetTurboSpeed   IFNDEF USE_SDRAM
                _GETREG REG_SCANDBLCTRL
                AND 00111111b
                OR  11000000b
                LD E, A
                _SETREGB REG_SCANDBLCTRL
                ENDIF
                RET

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Sets  Normal Speed

SetNormalSpeed  _GETREG REG_SCANDBLCTRL
                AND 00111111b
                LD E, A
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
; ************  Unpatch the ROM so the patched ROM can be used as normal ROM in case the ROMS.ZX1 file is absent

UnPatchROM      _SETREG REG_MASTERCONF, 1    ; MasterMapper mode
                _SETREG REG_MASTERMAPPER, 9  ; System ROM 1
; --- UnPatch the launch code at PATCHADDR
                LD HL, PATCHADDR + $C000
                LD A, $FF
                LD (HL), A
                LD DE, PATCHADDR + 1 + $C000
                LD BC, $48F                 ; Size minus 1 of the whole FFs area in the 48K ROM 
                

; -- Restore the original CALL to show "(C) 1982" that was replaced with the boot code
                LD HL, $0D6B
                ;LD HL, $0C0A
                LD (ROMBASICENTRY + $C000 ), HL

; -- Restore  the ROM memory check that was removed to speed up

                LD HL, $6B62
                LD (MEMCHECKADDR+ $C000), HL
                LD HL, $0236
                LD (MEMCHECKADDR + 2 + $C000), HL
                LD HL, $BC2B
                LD (MEMCHECKADDR + 4 + $C000), HL
                _SETREG REG_MASTERCONF, 2    ;  Back to normal mode
                RET


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
; ************ Gets  value of ZXUno register at A

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
               _PRINTAT 0, 22
               _WRITE "Critical ERROR: ZX-Uno MASTERCONF should have LOCK = 0"              
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

; -- Determine last valid entry
                    LD E, 0                    ; E will contain last valid entry
                    LD HL, ROMDirectory + 64    ; Points to second entry, number of slots
ValidEntryLoop      LD A, (HL)
                    LD BC, 64
                    ADD HL, BC
                    OR A
                    JR Z, FoundLast
                    INC E
                    JR ValidEntryLoop
FoundLast           LD A, E
                    LD (LAST_VALID_ENTRY), A
                    RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-
; ************ Loads the ROM at entry L

LoadROM             PUSH HL                 ; Preserve L entry
                    POP HL
                    PUSH HL                 ; Preserve L entry again
                    LD H, 0
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
                    CALL SetTurboSpeed

                    _PRINTAT 0, STARTLINE + 1
                    _WRITE "ZX-Uno Copyleft ZX-Uno Team - http://zxuno.speccy.org"
                    _PRINTAT 0, STARTLINE + 2
                    _WRITE "CoreID: "
                    CALL PrintCoreID

                    _PRINTAT 0, STARTLINE + 7
                    _WRITE "ROM: ["
                    POP HL
                    PUSH HL
                    LD A, L
                    CALL DivByTen ; Reminder in A and Quotient in D
                    PUSH AF
                    LD A, D
                    ADD '0'
                    CALL PrintChar
                    POP AF
                    ADD '0'
                    CALL PrintChar
                    _WRITE "] "
                    LD DE, 32
                    PUSH IY
                    POP HL
                    ADD HL, DE
                    CALL PrintString32
                    _PRINTAT 21, STARTLINE + 18
                    _INVERSE 1
                    _WRITE " QAOP to select ROM "

                    _INVERSE 0
                    _PRINTAT 7, STARTLINE + 20
                    _WRITE "   <Enter> normal boot - <Space> boot options "

                    _PRINTAT 0, 22
                    _WRITE " Press keys 0 to 9 to select ROMs #1 to #10 (0 selects ROM #10) "

                    CALL SetNormalSpeed

ReleaseKey          CALL GetKey                 ;Wait until key is released
                    CP NO_KEY                   
                    JR NZ, ReleaseKey


                    LD L, 0                 ; It will be some kind of timer, although when a key is pressed then timeout doesn't happen 
                    LD A, (cfgDelay)
                    LD H, A
KeyLoop             CALL GetKey
                    CP NO_KEY
                    JR NZ, KeyPressed
                    DEC HL
                    LD A, H
                    OR L                    
                    JR NZ, KeyLoop
                    LD A, (KEY_HAS_BEEN_PRESSED)
                    OR A
                    JR NZ, KeyLoop
                    LD A, NO_KEY
                    JR KeyNotPressed

KeyPressed          PUSH AF                   ; c
                    LD A, 1
                    LD (KEY_HAS_BEEN_PRESSED), A
                    POP AF

                    
KeyNotPressed       CP KEY_SPACE            ; Boot Options
                    JR NZ, KeyPressed3
                    CALL ClearScreen
                    JP BootOptions
                    

KeyPressed3         CP KEY_ENTER            ; Normal Boot
                    JR NZ, KeyPressed4
                    JP ContinueLoad


KeyPressed4         CP $0A ; Keys 0-9                     
                    JR NC, KeyPressed5
                    POP HL                     ; For cleaning purposes
                    OR A
                    JR NZ, ChangeROM
                    LD A, 10                   ; Button 0 => ROM 10
ChangeROM           LD L, A            
                    JP LoadROM



KeyPressed5         CP KEY_Q                      
                    JR NZ, KeyPressed6
                    POP HL
                    LD A, L
                    ADD A, 10
                    LD L, A
                    LD A, (LAST_VALID_ENTRY)       
                    CP L
                    JP NC, LoadROM              ; It's checking after the CP, as LD does not alter the flags
                    LD A, (LAST_VALID_ENTRY)
                    LD L, A
                    JP LoadROM

KeyPressed6         CP KEY_A
                    JP NZ, KeyPressed7
                    POP HL
                    LD A, L
                    SUB 10  
                    LD L, A
                    JP NC, LoadROM              ; It's checking after the SUB, as LD does not alter the flags
                    LD L, 0
                    JP LoadROM


KeyPressed7         CP KEY_O
                    JR NZ, KeyPressed8
                    POP HL
                    LD A, L
                    OR A 
                    JP Z, LoadROM
                    DEC L
                    JP LoadROM

KeyPressed8         CP KEY_P
                    JR NZ, KeyPressed9
                    POP HL                     ; For cleaning purposes
                    LD A, (LAST_VALID_ENTRY)
                    CP L
                    JP Z, LoadROM
                    INC L
                    JP LoadROM



KeyPressed9         LD A ,(KEY_HAS_BEEN_PRESSED)
                    OR A
                    JP NZ, ReleaseKey


ContinueLoad        POP HL                      ; Restore L-slot value, just for cleaning
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
                    OUT (255), A                 ; Disable timex mode
                    OUT (254), A                 ; Border 0




ReadROMPages        LD B, (IY+1)                ; Get number of slots for this ROM. B will count the number of slots left to load
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
                    _SETREGB REG_MASTERMAPPER  
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

; --- Now fill the empty System ROM slots. 
                    _SETREG REG_MASTERCONF, 1   ; Activate boot mode and disable DivMMC

CloneROMs           LD A, (IY+1)             ;If ROM uses just one slot, we copy the same ROM to all SystemROM banks (0-3, SRAM 8-11 iN ZX-Uno)
                    CP 1
                    JR NZ, Not1SlotROM
                    LD BC, $0809
                    CALL CopyROMBank
                    LD C, $0A
                    CALL CopyRomBankB
                    LD C, $0B
                    CALL CopyRomBankB
                    JR FourSlots

Not1SlotROM         CP 2                       ;If ROM uses just two slots, we copy rom at slot 0 to slot 2 and from slot 1 to slot 3 (In ZXUno SRAM 8 to 10 and 9 to 11)
                    JR NZ, FourSlots
                    LD BC, $080A
                    CALL CopyROMBank
                    LD C, $0B
                    CALL CopyRomBankB

FourSlots           _SETREG REG_MASTERCONF, 2   ; back to user mode and DivMMC Enabled

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
                    PUSH AF                         ; Preserve MASTERCONF value                      
                    _SETREGB REG_MASTERCONF         

                    CALL SetNormalSpeed                   ; Back to normal Speed

                    POP AF
                    AND 2
                    JP Z, 00000h                     ; If no DivMMC, we jump to 0000 to run System ROM 0

; -- Set USR0 mode

USR0                CALL  SetUSROMode               

                    DI                              ; Simulate first instruccion in ESXDOS compatible ROMs (DI) and jump to 1 to avoid ESXDOS to page in once more at 0000 trap
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
; ************ Sets USR 0 mode byy choosing System ROM 3

SetUSROMode         LD BC, TOASTRACKMAPPER       
                    LD A,00010000b
                    OUT (C), A
                    LD BC, PLUS2AMAPPER
                    LD A, 00000100b
                    OUT (C), A
                    RET

; --  Notice: in case it's 2 additional slots, that is, 3 in total, we will end up using System ROM 2, which is actually las slot used, so in the end
;     this makes the ROM use the last slot created.

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Save Configuration from file

SaveConfig               
; -- Get Screen settings so they are saved with config

                    _GETREG REG_SCANDBLCTRL         ; This is temporary, just to get if the user changes using Scroll Lock
                    AND 00111111b                   ; Remove turbo bits
                    LD (cfgSCANDBLCTRL),A

; --- open file					
                    LD IX,  CFGFilename
                    LD      B, FA_CREATE_AL
                    RST     $08
                    DB      F_OPEN      
                    RET C

; --- Dynamically update the F_CLOSE call later on
                    LD (CloseFileCfgSave + 1),A

; --- reads the entry information
WriteConfig  		LD 	IX, ConfigurationBEGIN
					LD BC, ConfigurationEND - ConfigurationBEGIN
					RST $08
					DB  F_WRITE
                    RET C
; --- Close file
CloseFileCfgSave  	LD 		A, 0
					RST     $08
                    DB      F_CLOSE
                    RET




; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Load Configuration from file

; --- Set default disk  
LoadConfig          XOR	A  
                    RST     $08 
                    DB      M_GETSETDRV

; --- open file     
                    LD IX,  CFGFilename
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
; ************ Copies a ZXUNO BANK from bank at B register to bank at C register using $4000 bytes at $6000
; ************ A Seconday entry at CopyRomBankB allows copying what is at $6000 to C000. Used to copy same thing several times

CopyROMBank         PUSH BC
                    LD E, B
                     _SETREGB REG_MASTERMAPPER   ; Make page selected at C000 be page 0, which happens to be the same page selected at C000 when boot mode is off
                    LD HL, $C000
                    LD DE, $6000
                    LD BC, $4000
                    LDIR        
                    POP BC
CopyRomBankB        LD E, C
                     _SETREGB REG_MASTERMAPPER   ; Make page selected at C000 be page 0, which happens to be the same page selected at C000 when boot mode is off
                    LD HL, $6000
                    LD DE, $C000
                    LD BC, $4000
                    LDIR     
                     _SETREG REG_MASTERMAPPER, 0 
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
                    AND 00111111b                   ;  Remove the Turbo part
                    IFNDEF USE_SDRAM
                    OR  11000000b                   ;  Set 28Mhz Speed
                    ENDIF
                    LD E, A
                    _SETREGB REG_SCANDBLCTRL

CheckSilentMode     LD A, (cfgSilentMode)
                    OR A
                    JR Z, UseVerboseMode
                    LD A, $C9; RET
                    LD (PrintChar), A
                    RET
UseVerboseMode      LD A, $D9; EXX
                    LD (PrintChar), A
                    RET




; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Shows boot options

BootOptions             CALL SetTurboSpeed

                        _INVERSE 1
                        _PRINTAT 14,8
                        _WRITE "                                     "
                        _PRINTAT 14,9
                        _WRITE " <Space> to Cancel                   "
                        _PRINTAT 14,10
                        _WRITE " <Intro> Normal boot                 "
                        _PRINTAT 14,11
                        _WRITE " <D> Normal boot and make default    " 
                        _PRINTAT 14,12
                        _WRITE " <R> Rooted boot                     "              
                        _PRINTAT 14,13
                        _WRITE "                                     " 
                        _INVERSE 0

                        CALL SetNormalSpeed


WaitKeyLoopBoot         CALL GetKey                                     ; First wait until space is released (to avoid to be triggered twice)
                        CP NO_KEY
                        JR NZ, WaitKeyLoopBoot

WaitKeyLoopBoot2        CALL GetKey                                     ; No wait for a key to be pressed
                        CP NO_KEY
                        JR Z, WaitKeyLoopBoot2

CancelBootOptions       CP KEY_SPACE
                        JR NZ, SetDefaultROM
                        CALL ClearScreen
                        CALL CopyrightNotice
                        POP HL                                          ; Recover Selected ROM index at L
                        JP LoadROM

SetDefaultROM           CP KEY_D
                        JR NZ, NormalBoot
                        POP HL
                        PUSH HL                                         ; Get and restore L, index of ROM
                        LD A, L
                        LD (cfgDefaultROMIndex), A                      ; Save default ROM in settings
                        CALL SaveConfig                                 ; Save Settings to SD
                        LD A, KEY_ENTER                                 ; To force it to enter next "entry"

NormalBoot              CP KEY_ENTER                                    ; Execute the ROM
                        JR NZ, RootedBoot
NormalBootGo            POP HL
                        JP ContinueLoad                        


RootedBoot              CP KEY_R
                        JR NZ, WaitKeyLoopBoot
                        XOR A
                        LD (RomSetMasterConf+1), A                      ; Disables LOCK but in MasterConf
                        JR NormalBootGo


                        JR WaitKeyLoopBoot

; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Divides A by 10 and returns the remainder in A and the quotient in D^***
DivByTen				LD 	D, A			; Does A / 10
						LD 	E, 10			; At this point do H / 10
						LD 	B, 8
						XOR 	A				; A = 0, Carry Flag = 0
DivByTenLoop			SLA	D
						RLA			
						CP	E		
						JR	C, DivByTenNoSub
						SUB	E		
						INC	D		
DivByTenNoSub			DJNZ DivByTenLoop
						RET				;A= remainder, D = quotient


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Loads key map from /ZXUNO/KEYMAP.ZX1 is existis

LoadKeyMap          LD IX, KEYMAPFilename

; --- open file
                    LD      B, FA_READ   
					RST     $08
                    DB      F_OPEN      
                    RET C
; --- Dynamically update the F_CLOSE call later on
                    LD (CloseFileKeyMap + 1), A

; --- reads the entry information
ReadkeyMap  		LD 	IX, ROMDirectory            ; Used as temporaty location
					LD BC, 4096 ; Size of the entries information
					RST $08
					DB  F_READ
                    RET C
; --- Close file
CloseFileKeyMap	    LD 		A, 0
					RST     $08
                    DB      F_CLOSE

; Loads the KEY MAP
                    LD BC, ZXUNO_PORT
                    LD A, REG_KEYMAP
                    OUT (C), A
                    LD HL, ROMDirectory
                    LD B, 16                         ; 16 times
OuterLoop           PUSH BC
                    LD B, 0                          ; 256 time  (total, 16x256 = 4096)
InnerLoop           PUSH BC
                    LD A, (HL)
                    LD BC, ZXUNO_DATA
                    OUT (C), A
                    POP BC
                    DJNZ InnerLoop
                    POP BC
                    DJNZ OuterLoop
                    RET


; +-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+-+
; ************ Returns key or joy pressed pressed at A, following the next table:
;
;      1                   --> $01        O      --> $15
;      2                   --> $02        P      --> $18
;      3                   --> $03        Q      --> $17
;      4                   --> $04        A      --> $16
;      5, CursorLeft       --> $05        Space  --> $0A
;      6, CursorDown       --> $06        Enter  --> $0B
;      7, CursorUp         --> $07        M      --> $20  
;      8, Cursor Right     --> $08
;      9                   --> $09
;      0                   --> $00         No key or invalid key --> $FF

GetKey          

GetKey2         LD BC,  $7FFE; B, N, M, Symbol Shift, Space
                IN A,(C)
                LD D, A     ; Preserve value
                AND 4
                JP Z, MPressed    ; M
                LD A, D
                AND 1
                JR Z, SpacePressed

GetKey3         LD BC, $BFFE; H, J, K, L, Enter
                IN A,(C)
                AND 1
                JR Z, EnterPressed ; Enter
                     
                LD BC, $DFFE; Y, U, I, O, P
                IN A,(C)
                LD D, A     ; Preserve value
                AND 1
                JP Z, PPressed ; P
                LD A, D
                AND 2
                JP Z, OPressed ; O

                LD BC, $EFFE ; 6, 7, 8, 9, 0
                IN A,(C)
                LD D, A     ; Preserve value
                AND 1
                JR Z, ZeroPressed ; 0
                LD A, D
                AND 2
                JR Z, NinePressed ; 9
                LD A, D
                AND 4
                JR Z, EightPressed ; 8
                LD A, D
                AND 8
                JR Z, SevenPressed  ; 7
                LD A, D
                AND 16
                JR Z, SixPressed ; 6

                LD BC, $F7FE;  5, 4, 3, 2, 1
                IN A,(C)
                LD D, A
                AND 16
                JR Z, FivePressed ; 5
                LD A, D
                AND 8
                JR Z, FourPressed
                LD A, D
                AND 4
                JR Z, ThreePressed
                LD A, D
                AND 2
                JR Z, TwoPressed
                LD A, D
                AND 1
                JR Z, OnePressed

 
                LD BC, 64510; T, R, E, W, Q
                IN A,(C)
                LD D, A
                AND 1
                JR Z, QPressed ; Q
                LD A, D
                AND 8
                JR Z, RPressed ; R
              
                LD BC, 65022 ; G, F, D, S, A
                IN A,(C)
                LD D, A
                AND 1
                JR Z, APressed ; A
                LD A, D
                AND 4
                JR Z, DPressed ; D
                LD A, D
                AND 8
                JR Z, FPressed ; F

; -- No Valid Keys
                LD A, NO_KEY
                RET

SpacePressed    LD A, KEY_SPACE
                RET
EnterPressed    LD A, KEY_ENTER
                RET             
MPressed        LD A, KEY_M
                RET
OnePressed      LD A, KEY_1
                RET
TwoPressed      LD A, KEY_2
                RET                
ThreePressed    LD A, KEY_3
                RET                
FourPressed     LD A, KEY_4
                RET                
FivePressed     LD A, KEY_5
                RET
SixPressed      LD A, KEY_6
                RET
SevenPressed    LD A, KEY_7
                RET
EightPressed    LD A, KEY_8
                RET
NinePressed     LD A, KEY_9
                RET
ZeroPressed     LD A, KEY_0
                RET                
QPressed        LD A, KEY_Q
                RET
APressed        LD A, KEY_A
                RET
OPressed        LD A, KEY_O
                RET                
PPressed        LD A, KEY_P
                RET
DPressed        LD A, KEY_D
                RET
FPressed        LD A, KEY_F
                RET
RPressed        LD A, KEY_R
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

; -- Keymap
KEYMAPFilename      DB 'ZXUNO\KEYMAP.ZX1', 0


; -- Config File
CFGFilename         DB 'ZXUNO\SETTINGS.ZX1',0

ConfigurationBEGIN
cfgMasterControlOR  DB 0         ; When a ROM file is loaded, its setting will pass through this OR and AND masks (flags1)
cfgMasterControlAND DB $FF
cfgDevcontrolOR     DB 0         ; When a ROM file is loaded, its setting will pass through this OR and AND masks (flags2)
cfgDevcontrolAND    DB $FF
cfgDevctrl2OR       DB 0         ; When a ROM file is loaded, its setting will pass through this OR and AND masks (flags3)
cfgDevctrl2AND      DB $FF 
cfgSCANDBLCTRL      DB 0         ; Saves the SCANDBLCTRL value, but the turbo bits will be ignored and always set to 00
cfgDefaultROMIndex  DB 0         ; Rom Index (not the slot, the index in the ROMS.ZX1 "directory")
cfgSilentMode       DB 0         ; 0 - verbose, 1 - silent
cfgDelay            DB 46        ; cfgValue * 256 = number of loops in ROM selection if Key not pressed before loading default ROM
cfgJOYCONF          DB 00100001b ; value for Joystick Configuration, defaults to Sinclair1 for DB9 and Kempston for PC Keyboard Cursors
cfgReserved         DS 13
ConfigurationEND                              


; -- Variables for internal use
V_PRINT_POS             DB 0
AUX                     DB 0
LAST_VALID_ENTRY        DB 0
KEY_HAS_BEEN_PRESSED    DB 0

;*****************************************************************************************************************************************************
;   FILLER
;*****************************************************************************************************************************************************
                       FPOS 16383; Just to fill up to 16384 bytes
                       DB 0
