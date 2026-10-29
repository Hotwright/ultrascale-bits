# Bare-metal A53 programs on the KV260

Built with `sw/build.sh baremetal <prog.elf> <src.c...>`, which also writes
`<prog>.bin`. The program runs from OCM (0xFFFC0000) with the MMU and
caches off, so every access is Device memory: keep buffers aligned to the
access size (`str q` needs 16). `bm.h` has the console (`bm_printf` on
UART1, COM9) and `main`'s return value is kept in `bm_exit`.

## Over JTAG

    env/kv260_jtag_load.sh design.bit
    env/kv260_run_bm.sh prog.elf [seconds]

Resets A53 #0 (Linux or U-Boot stops), loads the ELF, runs it, prints its
log and exit code.

## From the SD card, no JTAG

Put the bitstream, the program's `.bin` and a script made by `mkscr.py` in
a folder on the SD card's FAT boot partition (`/boot/firmware` under the
board's Linux; `hotwright/` here):

    sw/baremetal/mkscr.py run.scr hotwright axi.bit prog.bin

Stop U-Boot's autoboot with a key on the console, then:

    fatload mmc 1:1 0x10000000 hotwright/run.scr; source 0x10000000

The script loads the bitstream (`fpga loadb`, through the PMU firmware),
copies the program into OCM through DDR (fatload refuses OCM), turns
U-Boot's caches off and jumps. `start.S` takes either EL3 (JTAG) or EL2
(U-Boot). The program does not return; power-cycle to get Linux back.
Linux's own boot (`boot.scr.uimg`, `image.fit`) is untouched.
