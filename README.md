# Ggame Boy Thermal Receipt Printer

The goal of this project is to recreate the [Game Boy Printer](https://en.wikipedia.org/wiki/Game_Boy_Printer) using the [arduino-gameboy-printer-emulator](https://github.com/mofosyne/arduino-gameboy-printer-emulator?tab=readme-ov-file) project, a computer, and a modern thermal receipt printer.

This project uses the Python and Cython languages. Dependencies are in [requirements.txt](requirements.txt). The setup file is optional and is only needed if you want to compile the project for better performance.

This project is in its early stages. While it is functional, there are still bugs and incomplete functionality.

## Usage
```commandline
python3 ./src/main.py --serial SERIAL [-c CONFIG] [--no-printer] [-p PALLET] [-s SCALE] [-d DEST] [-v [VERBOSITY]] [--log LOG]
```

## The Config File

### Example config file
```ini
[general]
pallet = 1
scale = 3
output = ./images

[serial]
port = /dev/ttyACM0
baudrate = 115200
bytesize = 8
parity = N
stopbits = 1

[printer]; Printer profile. Available profiles can be found here: https://python-escpos.readthedocs.io/en/latest/printer_profiles/available-profiles.html
profile = TM-T88V
type = USB
vendorID = 0x0000
productID = 0x0000
```
