SmartROM for ZX-Uno
===================

This is SmartROM for ZX-UNO, a kind of firmware allowing loading different ROMS for implementations of the ZX-Uno core in FPGA boards without flash memory, or where the flash memory cannot be used by the ZX-Uno core.

In order to use it you have to either synthetize the core for the target machine, or use the COREnnSmartROM.ZX1 if you are using a ZX-Uno for testing purposes.


Setup
=====
Once you have the core installed, you will need:

1) Get an SD card and put BIN/SYS/TMP folders from ESXDOS 0.8.8 in it
2) Also, create a folder named "ZXUNO" and put SMARTROM.ZX1 in there (it's at the "binaries" folder of this repository). 
3) If your device uses a real Spectrum keyboard, or you use a non Spanish PS/2 keyboard, you make also copy any of the keymap files in the binaries/keymaps folders, and put the one you choose at the ZXUNO folder. Rename it to KEYMAP.ZX1 if you want it to be loaded.
4) Obtain a ROMS.ZX1 file from any ZX-Uno distribuition, or export the ROMS.ZX1 from the original ZX-Uno BIOS. Put the file at the ZXUNO folder too. Please notice the use of some ROMS may require you to license/purchase them.

Now that everything is in, boot yout device. You should see the usual ESXDOS loading screen (make sure you get OK for all opcions but maybe RTC.SYS), and then you will see the SmartROM showing up.

Possible errors
===============

- If you get a message about SmartROM not found make sure you have put SMARTROM.ZX1 file in the ZXUNO folder of the SD card.
- If you get a message about not ROMs file, please make sure you put the ROMS.ZX1 file  in the ZXUNO folder of the SD card.
- If every time you choose a ROM file the same one it's loaded, then make sure when ESXDOS starts all SYS files load OK (if RTC.SYS fails it doesn't matter, check the others). If not, make sure you put the proper ESXDOs BIN/SYS/TMP files in the SD card. Version of ESXDOS must be 0.8.8.
- If you choose 128K models but you get booted in 48K mode, please have in mind ESXDOS and DivMMC work like that, the computer starts in "USR 0 mode", which means even if it's a 128K computer and games or utilities can access the extra RAM, AY chip, etc. the boot is made with the 48K ROM active.
- If you are using VGA video output you probably see nothing. Press ScrollLock key to change video output to VGA.


Technical information for developers
====================================
Changes in the core:

McLeod_Ideafix already had created a core for ZX-Uno tha wasn't needing a flash memory, it was very simple though, and could only boot as Spectrum +2A in USR 0 mode. The change made in the core just replaces the bootloader with one that, instead of loading that ROM and booting, patches it (assumes is a toastrack 32K ROM) to do the following:

1) Skip the RAM test
2) Don't set the LOCK bit in the MASTERCONF register (ZX-Uno)
2) Start a routine which will try to find a file named SMARTROM.ZX1 at the ZXUNO folder of the SD and load it. If not, then it unpatches the ROM and runs just as McLeod's core

The core itself has been changed by adding a new "define" in the common/config.vh file, "USE SMARTROM". If that one is defined and "define LOAD_ROM_FROM_FLASH_OPTION" is commented, the SmartROM core will be generated when synthetized. Also, some changes have been made to the common/rom.v file, so instead loading the usual bootloader_copy_bram_to_sram.hex, it takes smartrom_bootloader_and_esxdos.hex, which is an hex file containing the concatenated bootloader.asm result and the ESXMMC.BIN file from ESXDOS. Please notice the original McLeod code used two different files, one for the bootloader and one for ESXDOS, this fork doesn't.

The SmartROM:

The SmartROM is the code loaded by the patched ROM, and runs at A000h. It presents a menu of options and manages to allow the user to choose different ROMs among other things. It takes advantage on being loaded *after* ESXDOS, so it can use ESXDOS to load and save files from the SD card. The code of the SmartROM is complex, but it's well commented and has been made to be readable as much as possible. Same goes for the booloader code. Probably.. surely, it is not optimized code. At this moment there is no need of more speed nor more space so it's left like that because it's prioritary for the author to keep readability over speed or space.

Greetings
=========

Greetings: a big thanks to McLeod_ideafix, whose support made this possible. Also a big thanks to Cesar Hernández, because his help with ZEsarUX emulator and custom feature to load the ZXUno RAm made this possible in a reasonable time. Also, many thanks to Antonio Villena and Fernando Mosquera for their support with firmware issues and for help getting ZX-Uno core synthesized. Finally, thanks to Andrew Owen for the ideas, and their valuable information about ULAPlus.


Copyright and License
=====================

The bootloader.asm file is (C) Miguel Angel Rodriguez (McLeod_ideafix) and Carlos Sánchez (Uto) and it's made public under the GPLv3 license.

The SmartROM.asm file is (C) Carlo Sánchez (Uto) and it's made public under the GPLv3 license.

The core files are (C) ZX Uno Team, and I guess the few lines Uto changed are also (C) Uto, but well, cough cough... not much :-). It's also released under the GPLv3 license.

