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

Possile errors
==============

- If you get a message about SmartROM not found make sure you have put SMARTROM.ZX1 file in the ZXUNO folder of the SD card.
- If you get a message about not ROMs file, please make sure you put the ROMS.ZX1 file  in the ZXUNO folder of the SD card.
- If every time you choose a ROM file the same one it's loaded, then make sure when ESXDOS starts all SYS files load OK (if RTC.SYS fails it doesn't matter, check the others). If not, make sure you put the proper ESXDOs BIN/SYS/TMP files in the SD card. Version of ESXDOS must be 0.8.8.
- If you choose 128K models but you get booted in 48K mode, please have in mind ESXDOS and DivMMC work like that, the computer starts in "USR 0 mode", which means even if it's a 128K computer and games or utilities can access the extra RAM, AY chip, etc. the boot is made with the 48K ROM active.



