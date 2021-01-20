; Este es el bootloader de ZXUno headerless, una modificación del de McLeod_ideafix, que añade algunos parches sobre la ROM del 48K
; antes lanzar su ejecución. En concreto y al menos, pone en la rutina de NEW código que permit sustituir la ejecución del intérprete
; basic por la carga desde el slot de  System ROM 1 del código de la SmartROM en 8000, y lanzarlo

                       output "bootloader_copy_bram_to_sram.bin"

ZXUNOADDR             equ 0FC3Bh
ZXUNODATA             equ 0FD3Bh
MAPPER128K            equ 7FFDh
MAPPERPLUS3           equ 1FFDh
DIVIDECTRL            equ 0E3h
MASTERCONF            equ 0
MASTERMAPPER          equ 1
SCANDBLCTRL           equ 0Bh
PATCHADDR             equ 3900h
ROMBASICENTRY         equ 1293h

CHECK128              equ 74h
CHECK48               equ $E4

                      org 0

                      di
                      ;Comprobar si la ROM de 128K está presente en la pantalla principal

                      ;paso 1. Conmutar a 28 MHz
                      xor a
                      out ($FE),A
                      
                      
                      ld bc,ZXUNOADDR
                      ld a,SCANDBLCTRL
                      out (c),a
                      inc b
                      in a,(c)
                      or 0c0h     ;28 MHz para ir rapidito
                      out (c),a

                      // Voy a chequear si la ROM que me viene de 48K es válida
                      IFDEF ZESARUX
                        ld hl,8000h         ; EN ZEsarUX la tengo en 8000h
                      ELSE
                        ld bc,ZXUNOADDR     ; Y en maquina real en la shadow RAM (SRAM page 7)
                        ld a,MASTERMAPPER   
                        out (c),a
                        inc b
                        ld a,7   
                        ld hl, $C000
                      ENDIF
                      xor a
                      ld b,a
BucleChecksum         add a,(hl)
                      inc hl
                      djnz BucleChecksum
                      cp CHECK48
                      jp nz,NoArranqueInicial

                       ;paso 2. Copia de ROMs a su sitio
                      

; Uto -> Parchea la ROM de 48K

                      ; Esto es todo el código de inicialización de la SmartROM, lo copiamos directamente 
                      ; del boootloader a PATCHADDR para su ejecución. PATCHADDR está en la zona de la ROM
                      ; del 48K que está llena de FFs
                      ld hl, ROMPatch
                      ld de, PATCHADDR + $8000
                      ld bc, ROMPatchEnd- ROMPatch   
                      ldir               

                      ; Además, como es innecesario en un ZX-UNO hacer el chequeo de memoria, porque si está mal de poco sirve, y si no lo está
                      ; va a tener siempre 48K de RAM direccionable, parcheamos esa rutina para que no la haga  y salga con sus 48K (última 
                      ; dirección válida FFFFh)
                      LD HL, PatchMemCheck
                      LD DE, MEMCHECKADDR + $8000
                      LD BC, 6
                      LDIR

                      ; Finalmente, metemos un salto a nuestro parche principal en el momento que se va a pintar el (C) 1982, lo hacemos dejando
                      ; el CALL en lugar de cambiarlo a un JP, lo cual en teoría permitiría volver aquí.
                      LD HL, PATCHADDR 
                      LD (ROMBASICENTRY + $8000), HL
                    

; Continua el código original de McLeod

                      ; Copio la SmartROM a los bancos 0 y 2
                      ld bc,ZXUNOADDR
                      ld a,MASTERMAPPER
                      out (c),a
                      inc b
                      ld a,8   ; System ROM bank 0
                      out (c),a
                      ld hl,$4000
                      ld de,$c000
                      ld bc,$4000
                      ldir

                      ld bc,ZXUNODATA
                      ld a,10  ;banco ROM 2
                      out (c),a
                      ld hl,$4000
                      ld de,$c000
                      ld bc,$4000
                      ldir


                    IFDEF ZESARUX               ; With ZEsarUX --zxuno-initial-64k feature, the 48K ROM piece of ROM is at 8000h  already, not at the Shadow Screen
                      ld bc,ZXUNODATA
                      ld a,9   ;banco ROM 1
                      out (c),a
                      ld hl,8000h
                      ld de,0c000h
                      ld bc,4000h
                      ldir

                      ld bc,ZXUNODATA
                      ld a,11  ;banco ROM 3
                      out (c),a
                      ld hl,8000h
                      ld de,0c000h
                      ld bc,4000h
                      ldir
                     ELSE                           ; Si es la maquina real, la segunda pieza de la ROM está en la shadow Screen
                     
                      ld bc,ZXUNODATA
                      ld a,7   ;shadow screen           ; la paginamos la shadow screen en C000
                      out (c),a
                      ld hl,0c000h
                      ld de,4000h                       ; copiamos a un sitio fuera del ultimo banco de 16KB como buffer temporal
                      ld bc,4000h
                      ldir

                      ld bc,ZXUNODATA                   ; Y la copiamos al banco de System ROM 1 y 3
                      ld a,9   ;banco ROM 1
                      out (c),a
                      ld hl,4000h
                      ld de,0c000h
                      ld bc,4000h
                      ldir

                      ld bc,ZXUNODATA
                      ld a,11  ;banco ROM 3
                      out (c),a
                      ld hl,4000h
                      ld de,0c000h
                      ld bc,4000h
                      ldir
                    ENDIF

                      ld bc,ZXUNODATA               ; Colocamos el ESXDOS en su sitio también
                      ld a,12  ;banco ESXDOS
                      out (c),a
                      ld hl,ESXDOSRom
                      ld de,0c000h
                      ld bc,2000h
                      ldir


NoArranqueInicial      ;paso 3. Preparar la fase en RAM
                      
                      ld hl,UltimaFaseEnRAM
                      ld de,8000h
                      ld bc,LongUltimaFase
                      ldir

                      jp 8000h

UltimaFaseEnRAM       ;paso 4. Configuramos máquina
                      
                      ld bc,ZXUNOADDR
                      ld a,MASTERCONF
                      out (c),a
                      inc b
                      ld a,00000010b  ;Modo timings 48K, con DivMMC y ESXDOS, configuración NO bloqueada y no boot
                      out (c),a

                      ld bc,MAPPER128K
                      ld a,00010000b
                      out (c),a
                      ld bc,MAPPERPLUS3
                      ld a,00000100b        ; Select System ROM 3
                      out (c),a

                       ;paso 5. Borrado de la ROM del DivMMC para forzar reinicio
                      

                      ld a,80h    ;16 páginas de 8KB cada una + CONMEM
BucleEraseDivMMC      out (DIVIDECTRL),a
                      ld hl,2000h
                      ld de,2001h
                      ld bc,1FFFh
                      ld (hl),l
                      ldir
                      inc a
                      cp 90h
                      jr nz,BucleEraseDivMMC
                      xor a
                      out (DIVIDECTRL),a

                      ;paso 6. Volvemos a 3.5 MHz y arrancamos ROM normal de 128K (con DivMMC)
                      

                      ld bc,ZXUNOADDR
                      ld a,SCANDBLCTRL
                      out (c),a
                      inc b
                      in a,(c)
                      and 3Fh     ;echamos el freno y volvemos a los 3.5 MHz
                      out (c),a


                      jp 0
LongUltimaFase        equ $-UltimaFaseEnRAM

ROMPatch             include "ROMPatch.inc"

ROMPatchEnd
                      IFDEF ZESARUX
                      FPOS 512
                      ORG 512
ESXDOSRom             INCBIN ASSETS\ESXMMC.BIN
                      FPOS 16383; Just to fill up to 16384 bytes
                      DB 0
                      ELSE 
                      ENDIF
    
