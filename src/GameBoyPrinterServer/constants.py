import datetime
import cython
import random
import os

# Info
NAME = 'Game Boy Printer Server'
VERSION = '1.0'
DESCRIPTION = 'A program to allow a GameBoy to print to a standard thermal printer'

# Paths
TMP_FOLDER_NAME = 'GameBoyPrinter'
if os.name == 'nt':
    PATH_TMP = os.path.join(os.getenv("TEMP"), TMP_FOLDER_NAME)
elif os.name == 'posix':
    PATH_TMP = os.path.join(os.sep, 'tmp', TMP_FOLDER_NAME)
else:
    PATH_TMP = os.path.join('.', TMP_FOLDER_NAME)

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
NODE: cython.int = random.getrandbits(48) | (1 << 40)

# Other constants
DEFAULT_CONFIG_NAME = 'config.ini'
SCALE_RANGE = range(1, 6)
DUMMY_SERIAL_PREFIX = 'DUMMY'
LOG_FILE_NAME = "log_%s.log" % datetime.datetime.now().replace(microsecond=0).isoformat()
