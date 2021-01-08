; Este fichero genera un ROMpatch.bin, para ser parcheado de manera externa sobre la ROM de 48K, para poder probar el sistema en ZesarUX, donde no podemos
; parchearla desde el boot loader


            org $3900
            output "ROMpatch.bin"

ZXUNOADDR             equ $0FC3B
ZXUNODATA             equ $0FD3B
MASTERCONF            equ 0
MASTERMAPPER          equ 1


            include "ROMPatch.inc"
