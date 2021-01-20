#!/bin/bash


# Notes:
# - sjasmplus is supposed to be in the path
# -  update ZESARUXPATH to the path where ZEsarUX is installed

ZESARUXPATH=/c/PortableApps/ZEsarUX-9.2-windows/
MMCFILE="media/disk_images/zxuno.mmc"
MMCFILE="tbblue.mmc"
SJASM=sjasmplus

########## STEP 1 - COMPILER PARTS ##########

# Prepend define ZESARUX to the file and compile a temporary file. Note: it should bne possible to do this with -DZESARUX=1 parameter for sjasm, but it doesn't  seem to work, so this is a walkaround
echo "Compiling bootloader..."
$SJASM  zesarux.inc bootloader.asm 
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi


echo "Compiling rompatch..."
$SJASM testpatch.asm 
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

echo "Compiling smartROM..."
$SJASM smartROM.asm --sym=symbols.a80
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

########## STEP 2 - Prepare the full 64K file for ZesarUX ##########

cat bootloader_copy_bram_to_sram.bin smartROM.bin assets/48.rom  assets/filler.bin >  SmartROM64K.bin
# The memory map is |  Bootloader  + ESXDOS | smartROM | 48K ROM | filler |  => filler is just 16K more to be placed at C000, but has no use other than making ZESARUX work (as it expects a 64K file)
cp SmartROM64K.bin $ZESARUXPATH/SmartROM64K.bin



    echo "Run smartROM (Y/N)"
    read -p "" yn
    case $yn in
        [yY]* ) (
                    cp SmartROM64K.bin $ZESARUXPATH
                    cd $ZESARUXPATH                   
                    ./zesarux --noconfigfile --verbose 3 --machine zxuno --disablemultitaskmenu --enable-breakpoints --set-breakpoint 1 "PC=A5AEh" --set-breakpoint 2 "PC=f552h" --set-breakpoint 3 "PC=A618h" --enable-esxdos-handler --esxdos-root-dir "C:\Users\csanc\PersonalDrive\Github\smartROM\assets\ESXDOS_HANDLER" --zxunospi-persistent-writes  --enabletimexvideo --enableulaplus --no-detect-realvideo --zoom 2  --nosplash --forcevisiblehotkeys --forceconfirmyes  --nowelcomemessage   --cpuspeed 100 --zxuno-initial-64k SmartROM64K.bin
                    exit;
                    break;
                );;
        [nN]]* ) (
                    echo "broken"
                    break;
                );;


    esac

