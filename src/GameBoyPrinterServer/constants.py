import cython
import os
import random

# Info
NAME = 'Game Boy Printer Server'
VERSION = '1.0'
DESCRIPTION = 'A program to allow a GameBoy to print to a standard thermal printer'

COMPILED: cython.bint = cython.compiled
DISPLAY_DETAILED_ABOUT: cython.bint = True

# Paths
TMP_FOLDER_NAME = 'GameBoyPrinter'
if os.name == 'nt':
    PATH_TMP = os.getenv("SystemDrive") + os.sep + 'temp' + os.sep + TMP_FOLDER_NAME + os.sep
elif os.name == 'posix':
    PATH_TMP = os.sep + 'tmp' + os.sep + TMP_FOLDER_NAME + os.sep
else:
    PATH_TMP = '.' + os.sep

# Color table
COLOR_TABLE_LOOKUP = {
    "Black and White": (0xFFFFFF, 0xFFFFFF, 0x000000, 0x000000),
    "Grayscale": (0xFFFFFF, 0xAAAAAA, 0x555555, 0x000000),
    "Original Game Boy": (0x9BBC0F, 0x77A112, 0x306230, 0x0F380F),
    "Game Boy Pocket": (0xC4CFA1, 0x8B956D, 0x4D533C, 0x1F1F1F),
    "Game Boy Color (Game Boy Camera, UE/US)": (0xFFFFFF, 0x7BFF30, 0x0163C6, 0x000000),
    "Game Boy Color (PocketCamera, JP)": (0xFFFFFF, 0xFFAD63, 0x833100, 0x000000),
    "bgb emulator": (0xE0F8D0, 0x88C070, 0x346856, 0x081820),
    "Grafixkid Gray": (0xE0DBCD, 0xA89f94, 0x706B66, 0x2B2B26),
    "Grafixkid Green": (0xDBF4B4, 0xABC396, 0x7B9278, 0x4C625A),
    "Game Boy (Black Zero) pallet": (0x7E8416, 0x577B46, 0x385D49, 0x2E463D)
}
COLOR_PALLET_NAMES = list(COLOR_TABLE_LOOKUP.keys())
DEFAULT_PALLET: cython.int = 1

# Random constants
NODE: cython.int = random.randint(0x000000000000, 0xFFFFFFFFFFFF)
