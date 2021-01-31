#!/bin/bash


# Notes:
# - sjasmplus is supposed to be in the path
# -  update ZESARUXPATH to the path where ZEsarUX is installed

SJASM=sjasmplus

########## STEP 1 - COMPILE PARTS ##########

# Prepend define ZESARUX to the file and compile a temporary file. Note: it should bne possible to do this with -DZESARUX=1 parameter for sjasm, but it doesn't  seem to work, so this is a walkaround
echo "Compiling bootloader..."
$SJASM  bootloader.asm 
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

echo "Compiling smartROM..."
$SJASM smartROM.asm 
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

########## STEP 2 - Generate hex files ##########

# In SmartROM mode, the core expect the bootloader and ESXDOS in same hex file
cat bootloader.bin assets/ESXMMC.BIN > allboot.bin     
tools/bin2hex allboot.bin
rm allboot.bin
mv allboot.hex /d/PC-FPGA/EXP27MOSQUERA/Spectrum_EXP27-200820_SRAM/common/smartrom_bootloader_and_esxdos.hex

