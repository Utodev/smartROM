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


;**************************************************************************************
;                           VARIABLES AND DEFINES
;**************************************************************************************



                define VRAM_ADDR            $4000
                define VRAM_ATTR_ADDR       $5800
                define ZXUNO_PORT           $FC3B
                define ZXUNO_DATA           $FE3B
                define STACK                $C000 ;  We will place the stack just at the end of 3rd page, so we can paginate at $C000 when needed without having problems with STACK
                define REG_MASTERCONF       0
                define REG_MASTERMAPPER     1
                define REG_SCANDBLCTRL      $0B
    			define REG_DEVCONTROL		$0E
	    		define REG_DEVCTRL2			$0F
                define REG_SCANCODE         4
                define REG_COREID           $FF
                define ULAPLUS_PORT         $BF3B
                define ULAPLUS_DATA         $FF3B
                define FW_VERSION           "1.0"

                define M_GETSETDRV  	$89
                define F_OPEN  		$9a
                define F_CLOSE 		$9b
                define F_READ  		$9d
                define F_WRITE 		$9e
                define F_SEEK		$9f       
                define FA_READ 		$01
                define FA_WRITE		$02
                define FA_CREATE_AL	$0C


                INCLUDE "macros.inc"

;**************************************************************************************
;
;                                  ROM STARTS HERE        
;
;
;**************************************************************************************



START           DI
                LD SP, $C000
                CALL TimexInit
                CALL ClearScreen
                CALL RestoreCursor
                CALL CheckBootMode
                LD E, 3
                CALL SetSpeed
                CALL InitializeVars                 ; Restart this firmware variables

                CALL LoadDefaultROM

                CALL BootScreen
                IM 1
                EI

Loop            JR Loop

; ------- ROM FUNCTIONS ---------
; Several useful ROM functions
; -------------------------------

; This routine shows the boot screen
                define STARTLINE 0
BootScreen      
                CALL ClearScreen
                CALL RestoreCursor
                _WRITE "      ZX-Uno  SmartROM "
                _WRITE FW_VERSION
                _WRITE " - (C) Uto 2021. License: MIT"


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


; Prints char provided at A register
PrintChar       EXX
                LD H, 0
                LD L, A
                ADD HL, HL
                ADD HL, HL
                ADD HL, HL              ;  HL = A * 8
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


; Sets Turbo Speed at D
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

                



;Prints Zero terminated string placed pointed by top value in the stack
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

; 

; Advances printing cursor one character
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

; Advances printing cursor one character
MoveCursor      LD HL, V_PRINT_POS
                INC (HL)
                RET NZ
                INC HL
                LD A, (HL)
                ADD A, 8
                LD (HL), A
                RET

; Clears all pixels in screen area
ClearScreen     LD HL, VRAM_ADDR
                LD BC, 192*32
                CALL ClearMem
                LD HL, VRAM_ADDR + $2000
                LD BC, 192*32
                CALL ClearMem
                RET

; Clears (sets to 0, area at HL, BC length)                
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


; Sets Times HiResMode
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



; Writes value E to ULAPlus register A
SetULAPlusReg   LD BC, ULAPLUS_PORT     ; Set paper to RGB 00000000
				OUT (C),A
				LD BC, ULAPLUS_DATA
				LD A, E
				OUT (C),A
                RET

; Draws a specific full with box for header
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

              


; Draws a Box at Column C, line B, with D width and E height
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
BoxDownLoop     LD A, 21                ; Lowe border
                CALL PrintChar
                DJNZ BoxDownLoop
                LD A, 20                ; lower-right
                CALL PrintChar
                RET





; Moves cursor n characters right, if end of line, continues in next line. Number of tabs provided at B                
Tabs            CALL MoveCursorTmx
                DJNZ Tabs
                RET

; Moves the cursor to column C, line B
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


; Initializes firmware system vars when ZX-Uno starts
InitializeVars XOR A                        
               CALL RestoreCursor       ; Now place Cursor at 0,0
               RET

; Places writing position at 0,0
RestoreCursor   LD DE, VRAM_ADDR
                LD (V_PRINT_POS), DE
                RET              



; Sets a register A to value E
SetZXUNOReg     PUSH BC
                LD BC, ZXUNO_PORT
                OUT (C),A
                INC B
                LD  A, E
                OUT (C),A
                POP BC
                RET
                
; Gets  value of ZXUno register
GetZXUnoReg     PUSH BC
                LD BC, ZXUNO_PORT
                OUT (C),A
                INC B
                IN A, (C)
                POP BC
                RET                                

; Gets and prints the coreID

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

; Checks if we are in boot mode and freezes if not
CheckBootMode  _GETREG REG_MASTERCONF
               AND 128
               RET Z
               _WRITE "ZX-Uno MASTERCONF should have LOCK = 0"              
               DI
               HALT

; Loads default ROM
LoadDefaultROM LD HL, ROMSEtFilename

; Expects ZXR file name to load pointed by HL
LoadROM         

; --- Set default disk  
                    XOR	A  
                    RST     $08 
                    DB      M_GETSETDRV

; --- open file
                    LD      B, FA_READ   
                    PUSH HL
                    POP IX
					RST     $08
                    DB      F_OPEN      
                    RET C

; --- Preserve A register, containing the file handle 
                    LD (CloseFile+1),A


; --- read header
					LD 	IX, ROMHeader
					LD BC, 64 ; Size of rom header
					RST $08
					DB  F_READ     

; --- seek up to first ROM position

					LD BC, 0   			 ; BCDE --> Offset 
                    LD DE, $1041          ; First position after the entries blocks
					LD IXL, 0 			 ; L=0 --> Seek from start
					LD L, 0
					RST	$08
					DB	F_SEEK
                    RET C
; --- read ROM      
                   LD IX, $C000
                   LD BC, $4000
                   RST $08
                   DB F_READ
; Close file

CloseFile			LD 		A, 0
					RST     $08
                    DB      F_CLOSE

ActivateROM         _GETREG REG_DEVCONTROL      ; Patch to make  sure Timex MMU is disabled, as somehow ZEsarUX bug (v 9.1) ignores mastermapper if it is active
                    AND 10111111b               ;
                    LD E, A                     ;
                    _SETREGB REG_DEVCONTROL     ;
                    CALL ClearScreen
      
                    ; Lets disable Timex Mode and set all attributes to black     
                    XOR A
                    OUT (255),A                 ; Disable timex mode
                    OUT (254), A                 ; Border 0


                    _SETREG REG_MASTERCONF, 1   ; Activate boot mode and disable DivMMC
                    _SETREG REG_MASTERMAPPER, 0   ; Make page selected at C000 be page 0, which happens to be the same page selected at C000 when boot mode is off
                    LD HL, $C000
                    LD DE, $6000
                    LD BC, $4000
                    LDIR                    ; Copy from C000 to 0000 (which in boot mode, is the BRAM)
                    _SETREG REG_MASTERMAPPER, 8   ; System ROM 0
                    LD HL, $6000
                    LD DE, $C000
                    LD BC, $4000
                    LDIR                    ; Copy back from BRAM to the proper slot
                    _SETREG REG_MASTERMAPPER, 0   ; Revert to normal mastermapper bank (probably not necessary)
                    _SETREG REG_MASTERCONF, 2   ; back to user mode and DivMMC Enabled
RunROM              DI
                    JP 1







; Interrupt routine handles V_FRAMES and V_SECONDS. Do not confuse V_FRAMES with FRAMES
Interrupt       DI
                PUSH AF
                PUSH  HL
                LD A, (V_FRAMES)
                INC A
                LD (V_FRAMES), A
                CP 50
                JR NZ, EndInterrupt
                LD HL, V_SECONDS
                INC (HL)
                XOR A
                LD (V_FRAMES), A        
EndInterrupt    POP HL
                POP AF
                EI
                RETI




Font                INCBIN     assets\font.bin
ROMSEtFilename      DB 'ZXUNO\ROMS.ZX1', 0

; In the ROMS.ZX1 file, first there are 64 headers
ROMHeader
ROMHeaderStart      DB 0
ROMHeaderLength     DB 0
ROMHeaderFlags1     DB 0
ROMHeaderFlags2     DB 0
ROMHeaderFlags3     DB 0
ROMHeaderReserved   DB 0,0,0
ROMHeaderChecksum   DB 0,0
ROMHeaderReserved2  DS 12
ZXRHeaderName   DS 32


; -------------- Variables --------------------------------------
                               
                               
;Config Vars are BIOS related variables which are saved in the config file. 
cfgNewGraphicModes      DB 0
cfgDivMMCEnabled        DB 0
cfgDivMMVNMIEnabled     DB 0
cfgULATiming            DB 0
cfgKeyboardLayout       DB 0
cfgContendedMemory      DB 0
cfgDefaultROMIndex      DB 0
cfgFrequency            DB 0
cfgVideoOutput          DB 0
cfgFWColorSchema        DB 0

; variables for internal use
V_PRINT_POS             DB 0
V_RAM_SIZE              DB 0
V_FRAMES                DB 0
V_SECONDS               DB 0


                        FPOS 16383; Just to fill up to 16384 bytes
                        DB 0
