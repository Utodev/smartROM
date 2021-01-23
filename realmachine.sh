#!/bin/bash


# Notes:
# - sjasmplus is supposed to be in the path
# -  update ZESARUXPATH to the path where ZEsarUX is installed

SJASM=sjasmplus

########## STEP 1 - COMPILER PARTS ##########

# Prepend define ZESARUX to the file and compile a temporary file. Note: it should bne possible to do this with -DZESARUX=1 parameter for sjasm, but it doesn't  seem to work, so this is a walkaround
echo "Compiling bootloader..."
$SJASM  bootloader.asm 
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

echo "Compiling smartROM..."
$SJASM smartROM.asm 
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

########## STEP 2 - Generate hex files ##########
cat smartROM.bin assets/48.rom > 128.bin
tools/bin2hex 128.bin
tools/bin2hex bootloader_copy_bram_to_sram.bin

