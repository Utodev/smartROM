#!/bin/bash


# Notes:
# - sjasmplus is supposed to be in the path
# -  update ZESARUXPATH to the path where ZEsarUX is installed

ZESARUXPATH=/c/PortableApps/ZEsarUX-9.2-windows/
MMCFILE="media/disk_images/zxuno.mmc"
MMCFILE="tbblue.mmc"
SJASM=sjasmplus

########## STEP 1 - COMPILE PARTS ##########

# Prepend define ZESARUX to the file and compile a temporary file. Note: it should bne possible to do this with -DZESARUX=1 parameter for sjasm, but it doesn't  seem to work, so this is a walkaround
echo "Compiling bootloader..."
$SJASM  zesarux.inc bootloader.asm --sym=symbolsboot.a80
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

echo "Compiling smartROM..."
$SJASM smartROM.asm --sym=symbolssmart.a80
rc=$?; if [[ $rc != 0 ]]; then exit $rc; fi

########## STEP 2 - Prepare the full 64K file for ZesarUX ##########

cat bootloader.bin assets/128en.rom  assets/filler.bin >  SmartROM64K.bin
rm bootloader.bin
# The memory map is |  Bootloader  + ESXDOS | 128K ROM (32K) | filler |  => filler is just 16K more to be placed at C000, but has no use other than making ZESARUX work (as it expects a 64K file)
mv SmartROM64K.bin $ZESARUXPATH/SmartROM64K.bin
mv SMARTROM.ZX1 assets/ESXDOS_HANDLER/ZXUNO/SMARTROM.ZX1
cp assets/ESXDOS_HANDLER/ZXUNO/SMARTROM.ZX1 /g/ZXUNO/SMARTROM.ZX1


    echo "Run smartROM (Y/N)"
    read -p "" yn
    case $yn in
        [yY]* ) (
                    cp assets/smartROM.mmc $ZESARUXPATH
                    cd $ZESARUXPATH                   
                    #./zesarux --noconfigfile --verbose 3 --machine zxuno --enable-breakpoints --set-breakpoint 1 "PC=3A8Dh" --set-breakpoint 2 "PC=3900h" --set-breakpoint 3 "PC=A618h" --disablemultitaskmenu  --enable-esxdos-handler --esxdos-root-dir "C:\Users\csanc\PersonalDrive\Github\smartROM\assets\ESXDOS_HANDLER" --zxunospi-persistent-writes  --enabletimexvideo --enableulaplus --no-detect-realvideo --zoom 2  --nosplash --forcevisiblehotkeys --forceconfirmyes  --nowelcomemessage   --cpuspeed 100 --zxuno-initial-64k SmartROM64K.bin
                    ./zesarux --noconfigfile --verbose 3 --machine zxuno  --enable-breakpoints --set-breakpoint 1 "PC=A699h" --set-breakpoint 2 "PC=A5E6h" --set-breakpoint 3 "PC=F618h"  --disablemultitaskmenu --enable-mmc --enable-divmmc --mmc-file smartROM.mmc --zxunospi-persistent-writes  --enabletimexvideo --enableulaplus --no-detect-realvideo --zoom 2  --nosplash --forcevisiblehotkeys --forceconfirmyes  --nowelcomemessage   --cpuspeed 100 --zxuno-initial-64k SmartROM64K.bin
                    exit;
                    break;
                );;
        [nN]]* ) (
                    echo "broken"
                    break;
                );;


    esac

