import cython
import uuid
import numpy as np
from PIL import Image
from os import sep as path_sep
from src.GameBoyPrinterServer.constants import NODE

cdef unsigned char SLASH = ord(b'/')
cdef unsigned char SPACE = ord(b' ')

cdef str FULL_BLOCK = ' '
cdef str TOP_BLOCK = '▀'
cdef str LEFT_BLOCK = '▌'
cdef str DIAG_BLOCK = '▚'
cdef str TL_BLOCK = '▘'
cdef str TR_BLOCK = '▝'
cdef str BL_BLOCK = '▖'
cdef str BR_BLOCK = '▗'


cpdef unsigned char[:] decode_line(line):
    cdef int count = 1
    cdef unsigned char[:] decoded_line
    cdef unsigned c1, c2
    if line is None:
        return None
    with cython.boundscheck(False):
        try:
            line_bytes = bytes(line.strip(), 'ASCII')
            if len(line_bytes) == 0 or line_bytes[0] == SLASH:
                return None
            for i in range(len(line_bytes)):
                if line_bytes[i] == SPACE:
                    count += 1
            decoded_line = np.empty((count), dtype=np.uint8)
            count = 0
            for i in range(len(line_bytes)):
                c1 = line_bytes[i]
                if c1 != SPACE:
                    c2 = (c2 << 4) + hex_to_byte(c1)
                else:
                    decoded_line[count] = c2
                    count += 1
            decoded_line[count] = c2
            return decoded_line
        except UnicodeEncodeError as e:
            print("Unsupported character:", e)
            return None

cdef unsigned char hex_to_byte(const unsigned char byte):
    cdef unsigned char value = 0
    if byte >= '0' and byte <= '9':
        value = byte - 48  # '0'
    elif byte >= b'A' and byte <= b'F':
        value = byte - 55  # 'A') + 10
    elif byte >= b'a' and byte <= b'f':
        value = byte - 87  # 'a') + 10
    return value


cpdef str save_image(image_data, str output_dir):
    file_uuid = uuid.uuid1(node=NODE)
    file_path = output_dir + (path_sep if not output_dir.endswith(path_sep) else '') + str(file_uuid) + '.bmp'
    output_image = Image.fromarray(np.array(image_data, dtype=np.uint8), "RGB")
    print("Image size: %dx%d" % output_image.size)
    output_image.save(file_path)
    return file_path


cpdef print_image_to_terminal(image_data, int scale=1):
    cdef int x, y, last_color
    cdef str command = '\033[0m\n'
    for y in range(0, len(image_data), 2*scale):
        for x in range(0, len(image_data[y]), 2*scale):
            command += generate_terminal_print_character(image_data[y][x], image_data[y][x+1], image_data[y+1][x], image_data[y+1][x+1])
        command += '\033[0m\n'
    print(command)


cdef int abs(int number):
    if number < 0:
        return number * -1
    return number


cdef str generate_terminal_print_character(int color_00, int color_01, int color_10, int color_11):
    cdef int background_color, foreground_color
    cdef int background_R, background_G, background_B, foreground_R, foreground_G, foreground_B
    cdef str character
    cdef int threshold_R, threshold_G, threshold_B

    cdef int R_top, R_bottom, R_left, R_right, R_diag_1, R_diag_2, R_tb_abs, R_lr_abs, R_di_abs
    cdef int G_top, G_bottom, G_left, G_right, G_diag_1, G_diag_2, G_tb_abs, G_lr_abs, G_di_abs
    cdef int B_top, B_bottom, B_left, B_right, B_diag_1, B_diag_2, B_tb_abs, B_lr_abs, B_di_abs

    if color_00 == color_01 and color_01 == color_10 and color_10 == color_11:
        foreground_color = 0
        background_color = color_00
        character = FULL_BLOCK
    elif color_00 == color_01 and color_10 == color_11:
        foreground_color = color_00
        background_color = color_10
        character = TOP_BLOCK
    elif color_00 == color_10 and color_01 == color_11:
        foreground_color = color_00
        background_color = color_01
        character = LEFT_BLOCK
    elif color_00 == color_11 and color_01 == color_10:
        foreground_color = color_00
        background_color = color_01
        character = DIAG_BLOCK
    elif color_01 == color_10 and color_10 == color_11:
        foreground_color = color_00
        background_color = color_01
        character = TL_BLOCK
    elif color_00 == color_10 and color_10 == color_11:
        foreground_color = color_01
        background_color = color_00
        character = TR_BLOCK
    elif color_00 == color_01 and color_01 == color_11:
        foreground_color = color_10
        background_color = color_00
        character = BL_BLOCK
    elif color_00 == color_01 and color_01 == color_10:
        foreground_color = color_11
        background_color = color_00
        character = BR_BLOCK
    else:
        if color_00 == color_01:
            foreground_color = color_00
            background_color = int((color_10 + color_11) / 2)
            character = TOP_BLOCK
        elif color_10 == color_11:
            foreground_color = int((color_00 + color_01) / 2)
            background_color = color_10
            character = TOP_BLOCK
        elif color_00 == color_10:
            foreground_color = color_00
            background_color = int((color_01 + color_11) / 2)
            character = LEFT_BLOCK
        elif color_01 == color_11:
            foreground_color = int((color_00 + color_10) / 2)
            background_color = color_01
            character = LEFT_BLOCK
        elif color_00 == color_11:
            foreground_color = color_00
            background_color = int((color_01 + color_10) / 2)
            character = DIAG_BLOCK
        elif color_01 == color_10:
            foreground_color = int((color_00 + color_11) / 2)
            background_color = color_01
            character = DIAG_BLOCK
        else:
            R_top = int((((color_00 >> 16) & 0xFF) + ((color_01 >> 16) & 0xFF)) / 2)
            R_bottom = int((((color_10 >> 16) & 0xFF) + ((color_11 >> 16) & 0xFF)) / 2)
            R_left = int((((color_00 >> 16) & 0xFF) + ((color_10 >> 16) & 0xFF)) / 2)
            R_right = int((((color_01 >> 16) & 0xFF) + ((color_11 >> 16) & 0xFF)) / 2)
            R_diag_1 = int((((color_00 >> 16) & 0xFF) + ((color_11 >> 16) & 0xFF)) / 2)
            R_diag_2 = int((((color_01 >> 16) & 0xFF) + ((color_10 >> 16) & 0xFF)) / 2)

            R_tb_abs = abs(R_top - R_bottom)
            R_lr_abs = abs(R_left - R_right)
            R_di_abs = abs(R_diag_1 - R_diag_2)

            G_top = int((((color_00 >> 8) & 0xFF) + ((color_01 >> 8) & 0xFF)) / 2)
            G_bottom = int((((color_10 >> 8) & 0xFF) + ((color_11 >> 8) & 0xFF)) / 2)
            G_left = int((((color_00 >> 8) & 0xFF) + ((color_10 >> 8) & 0xFF)) / 2)
            G_right = int((((color_01 >> 8) & 0xFF) + ((color_11 >> 8) & 0xFF)) / 2)
            G_diag_1 = int((((color_00 >> 8) & 0xFF) + ((color_11 >> 8) & 0xFF)) / 2)
            G_diag_2 = int((((color_01 >> 8) & 0xFF) + ((color_10 >> 8) & 0xFF)) / 2)

            G_tb_abs = abs(R_top - R_bottom)
            G_lr_abs = abs(R_left - R_right)
            G_di_abs = abs(R_diag_1 - R_diag_2)

            B_top = int(((color_00 & 0xFF) + (color_01 & 0xFF)) / 2)
            B_bottom = int(((color_10 & 0xFF) + (color_11 & 0xFF)) / 2)
            B_left = int(((color_00 & 0xFF) + (color_10 & 0xFF)) / 2)
            B_right = int(((color_01 & 0xFF) + (color_11 & 0xFF)) / 2)
            B_diag_1 = int(((color_00 & 0xFF) + (color_11 & 0xFF)) / 2)
            B_diag_2 = int(((color_01 & 0xFF) + (color_10 & 0xFF)) / 2)

            B_tb_abs = abs(R_top - R_bottom)
            B_lr_abs = abs(R_left - R_right)
            B_di_abs = abs(R_diag_1 - R_diag_2)

            if R_tb_abs > R_lr_abs and R_tb_abs > R_di_abs: # TODO Need to finish implementation
                foreground_color = int((color_00 + color_01) /2)
                background_color = int((color_10 + color_11) / 2)
                character = TOP_BLOCK
            elif R_lr_abs > R_tb_abs and R_lr_abs > R_di_abs:
                foreground_color = int((color_00 + color_10) /2)
                background_color = int((color_01 + color_11) / 2)
                character = LEFT_BLOCK
            else:
                foreground_color = int((color_00 + color_11) /2)
                background_color = int((color_01 + color_10) /2)
                character = DIAG_BLOCK


    background_R = (background_color >> 16) & 0xFF
    background_G = (background_color >> 8) & 0xFF
    background_B = (background_color) & 0xFF
    background_color = int(16 + (36 * (background_R / 51)) + (6 * (background_G / 51)) + (background_B / 51))

    foreground_R = (foreground_color >> 16) & 0xFF
    foreground_G = (foreground_color >> 8) & 0xFF
    foreground_B = (foreground_color) & 0xFF
    foreground_color = int(16 + (36 * (foreground_R / 51)) + (6 * (foreground_G / 51)) + (foreground_B / 51))

    return '\033[38;5;' + str(foreground_color) + ';48;5;' + str(background_color) + "m" + character
