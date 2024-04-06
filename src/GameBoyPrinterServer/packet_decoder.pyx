import cython
import numpy as np

import src.GameBoyPrinterServer.constants as constants
import src.GameBoyPrinterServer.log as log

cdef str EMPTY_STRING = ''
cdef str NEWLINE_STRING = '\n'

cpdef bint is_compiled():
    return cython.compiled

cdef class __PrinterStatus:
    cdef unsigned char status_byte
    cdef bint low_battery, error_2, error_1, error_0, untran, full, busy, checksum_error
    def __init__(self, unsigned char status_byte):
        self.status_byte = status_byte
        self.low_battery = status_byte & 0b10000000  # Battery low
        self.error_2 = status_byte & 0b01000000  # Other error
        self.error_1 = status_byte & 0b00100000  # Paper jam (abnormal motor operation)
        self.error_0 = status_byte & 0b00010000  # Packet error
        self.untran = status_byte & 0b00001000  # Unprocessed data present
        self.full = status_byte & 0b00000100  # Buffer full
        self.busy = status_byte & 0b00000010  # Printer busy
        self.checksum_error = status_byte & 0b00000001  # Checksum error

    cdef bint any(self):
        return (self.low_battery or self.error_2 or self.error_1 or self.error_0 or
                self.untran or self.full or self.busy or self.checksum_error)

    cdef str get_status_string(self):
        if not self.any():
            return ""
        status_items = []
        if self.low_battery:
            status_items.append("Low battery")
        if self.error_2:
            status_items.append("Error 2")
        if self.error_1:
            status_items.append("Error 1")
        if self.error_0:
            status_items.append("Error 0")
        if self.untran:
            status_items.append("Unprocessed data")
        if self.full:
            status_items.append("Buffer full")
        if self.busy:
            status_items.append("Printer busy")
        if self.checksum_error:
            status_items.append("Checksum error")
        return "* Printer status:\t" + (', '.join(status_items))


cdef class PacketDecoder:
    cdef char VERBOSITY
    cdef unsigned char[:,:] COLOR_LUT
    cdef list processed_data, finished_image
    cdef bint data_end_packet_received, print_data_ready
    cdef bint ignore_checksum_errors

    def __init__(self):
        self.VERBOSITY = 0
        self.processed_data = []
        self.finished_image = []
        self.data_end_packet_received = False
        self.print_data_ready = False
        self.ignore_checksum_errors = True
        self.COLOR_LUT = np.empty((4,3), dtype=np.uint8)
        self.set_color_pallet(constants.DEFAULT_PALLET)

    cpdef set_verbosity(self, char verbosity):
        if verbosity < 0:
            self.VERBOSITY = 0
        else:
            self.VERBOSITY = verbosity

    cpdef set_color_pallet(self, int pallet):
        cdef tuple color_tuple = constants.COLOR_TABLE_LOOKUP[constants.COLOR_PALLET_NAMES[pallet]]
        with cython.boundscheck(False):
            for i in range(4):
                self.COLOR_LUT[i][0] = (color_tuple[i] & 0xFF0000) >> 16
                self.COLOR_LUT[i][1] = (color_tuple[i] & 0x00FF00) >> 8
                self.COLOR_LUT[i][2] = (color_tuple[i] & 0x0000FF)

    cpdef process_packet(self, packet_data):
        # Packet header variables
        cdef int data_len = len(packet_data)
        cdef unsigned char calc_hb, calc_lb, chk_hb, chk_lb
        cdef unsigned int checksum
        cdef int i, packet_type

        # Print packet variables
        cdef unsigned char sheets, lf_before, lf_after, pallet, density

        # Data packet variables
        cdef int data_length
        cdef bint compressed

        if data_len < 10:
            log.error("Packet size too small") #TODO Should this be a warning?

        with cython.boundscheck(True):
            with cython.wraparound(False):
                if not (packet_data[0] == 0x88 and packet_data[1] == 0x33):
                    log.error("Error in packet data sync bytes") #TODO Should this be a warning?
                    return

                #TODO Checksum calculations are unstable. Find a way to fix.
                for i in range(2, data_len - 4):
                    checksum += packet_data[i]
                calc_hb = (checksum & 0xFF00) >> 8
                calc_lb = checksum & 0xFF
                chk_hb = packet_data[data_len - 3]
                chk_lb = packet_data[data_len - 4]
                if not (chk_hb == calc_hb and chk_lb == calc_lb):
                    log.warn("Checksum error in packet")
                    log.warn("Expected\t%s %s" % (chk_hb, chk_lb))
                    log.warn("Received\t%s %s" % (calc_hb, calc_lb))
                    if not self.ignore_checksum_errors:
                        return

                packet_type = packet_data[2]

                if packet_type == 0x01:  # Initialize packet
                    log.info("Initialize packet")
                    if not data_len == 10:
                        log.warn("* Length of initialize packet incorrect")
                        return
                    if not (packet_data[3] == 0x00 and packet_data[4] == 0x00 and packet_data[5] == 0x00):
                        log.warn("* Error in initialize packet header")
                        return
                    log.info("* Printer initialized")

                elif packet_type == 0x02:  # Print instruction packet
                    log.info("Print instruction packet")
                    if not data_len == 14:
                        log.warn("* Length of print packet incorrect")
                        return
                    if not (packet_data[3] == 0x00 and packet_data[4] == 0x04 and packet_data[5] == 0x00):
                        log.warn("* Error in print packet header")
                        return
                    sheets = packet_data[6]
                    log.info("* Sheets:\t\t" + str(sheets))
                    lf_before = (packet_data[7] & 0xF0) >> 4
                    lf_after = packet_data[7] & 0x0F
                    log.info("* LF before:\t" + str(lf_before))
                    log.info("* LF after:\t\t" + str(lf_after))
                    pallet = packet_data[8]
                    log.info("* Pallet:\t\t" + ("0x%0.2X" % pallet))
                    density = packet_data[9]
                    log.info("* Density:\t\t" + "{0:+.2f}%".format((density / 254) - 0.25))
                    if self.data_end_packet_received:
                        if lf_after != 0:
                            log.info("Image transmission finished")
                            self.adjust_pallet(pallet)
                            log.info("Pallet adjusted")
                            self.finished_image = self.processed_data
                            self.processed_data = []
                            self.print_data_ready = True
                        else:
                            log.info("* Multi-screen image print")
                        self.data_end_packet_received = False
                    else:
                        log.warn("Print command issued before image-end packet sent")

                elif packet_type == 0x04:  # Data packet
                    log.info("Data packet")
                    data_length = (packet_data[4] + (packet_data[5] << 8))
                    compressed = packet_data[3] != 0x00
                    if not data_len == data_length + 10:
                        log.warn("* Length of data packet incorrect")
                        return
                    if data_length == 0:
                        log.info("* Data-End packet")
                        self.data_end_packet_received = True
                    else:
                        log.info("* Length:\t\t" + str(data_length))
                        log.info("* Compressed:\t" + str(compressed))
                        self.decode_packet_image_data(packet_data[6:data_len-4], compressed)

                elif packet_type == 0x08:  # Break packet
                    log.info("Break packet")
                    if not data_len == 10:
                        log.warn("* Length of break packet incorrect")
                        return
                    if not (packet_data[3] == 0x00 and packet_data[4] == 0x00 and packet_data[5] == 0x00):
                        log.warn("* Error in break packet header")
                        return

                elif packet_type == 0x0F:  # NUL packet (Inquiry packet)
                    log.info("NUL packet")
                    if not data_len == 10:
                        log.warn("* Length of NUL packet incorrect")
                        return
                    if not (packet_data[3] == 0x00 and packet_data[4] == 0x00 and packet_data[5] == 0x00):
                        log.warn("* Error in NUL packet header")
                        return

                else:
                    log.error("Unknown command") #TODO Should this be a warning?

                # Check printer status
                if packet_data[data_len - 2] == 0xFF and packet_data[data_len - 1] == 0xFF:
                    log.warn("* Printer is off or disconnected")
                    return
                if not (packet_data[data_len - 2] == 0x81):
                    log.warn("* Response not from printer")
                status = __PrinterStatus(packet_data[data_len - 1])
                if status.any():
                    log.info(status.get_status_string()) #TODO Enhance status printing

    cdef decode_packet_image_data(self, unsigned char[:] data, bint compressed):
        cdef int width = 40
        cdef int height = 16
        cdef int data_packet_valid_size = 640

        cdef int data_len, i, j, o, raw_start_pos, raw_end_pos, reps
        cdef unsigned char value
        cdef int y1, y2, x

        with cython.boundscheck(True):
            with cython.wraparound(False):
                image_data_chunk = np.zeros((height, width), dtype=np.uint8)
                if compressed:
                    new_data = np.zeros((data_packet_valid_size), dtype=np.uint8)
                    i = 0
                    j = 0
                    data_len = len(data)
                    while i < data_len:
                        if data[i] < 0x80:
                            raw_start_pos = i + 1
                            raw_end_pos = raw_start_pos + data[i] + 1
                            i += 1
                            for o in range(raw_start_pos, raw_end_pos):
                                if j >= data_packet_valid_size:
                                    break
                                new_data[j] = data[i]
                                i += 1
                                j += 1
                        else:
                            reps = data[i] - 0x7E
                            value = data[i + 1]
                            i += 2
                            for o in range(reps):
                                if j >= data_packet_valid_size:
                                    break
                                new_data[j] = value
                                j += 1
                    if i != data_len:
                        log.error("* Error in decompression of compressed data")
                    data = new_data

                if len(data) != data_packet_valid_size:
                    log.warn("* Data size incorrect!")
                    return

                i = 0
                for y2 in range(2):
                    for x in range(0, width, 2):
                        for y1 in range(8):
                            image_data_chunk[y1 + (y2 * 8)][x] = data[i]
                            image_data_chunk[y1 + (y2 * 8)][x + 1] = data[i + 1]
                            i += 2

                self.processed_data.append(image_data_chunk)

    cdef adjust_pallet(self, unsigned char pallet):
        cdef int i, j, x, y, a
        cdef unsigned char bitmask, bit_shift, value1, value2, pixel_value
        cdef unsigned char[:] lut_result

        pallet_lut = cython.declare(cython.uchar[:,:], np.zeros((4, 2), dtype=np.uint8))

        with cython.boundscheck(True):
            with cython.wraparound(False):
                bitmask = 0b00000001
                for i in range(4):  # Decode pallet
                    for j in range(1, -1, -1):
                        pallet_lut[i][j] = 1 if (pallet & bitmask != 0) else 0
                        bitmask = bitmask << 1

                for i in range(len(self.processed_data)):
                        chunk: cython.uchar[:,:] = self.processed_data[i]
                        for y in range(len(chunk)):
                            for x in range(0, len(chunk[y]), 2):
                                bitmask = 0b10000000
                                bit_shift: cython.uchar = 7
                                value1 = chunk[y][x]
                                value2 = chunk[y][x + 1]
                                for a in range(8):
                                    pixel_value = ((chunk[y][x] & bitmask) >> bit_shift) + (
                                        (chunk[y][x + 1] & bitmask) >> bit_shift << 1)
                                    lut_result: cython.uchar[:] = pallet_lut[pixel_value]

                                    if lut_result[1] == 0:
                                         value1 = value1 & ((~bitmask) & 0xFF)
                                    else:
                                        value1 = value1 | bitmask

                                    if lut_result[0] == 0:
                                        value2 = value2 & ((~bitmask) & 0xFF)
                                    else:
                                        value2 = value2 | bitmask

                                    bitmask = bitmask >> 1
                                    bit_shift -= 1
                                chunk[y][x] = value1
                                chunk[y][x + 1] = value2

    cpdef bint image_ready(self):
        return self.print_data_ready

    cpdef unsigned char[:,:,:] get_image(self):
        if not self.print_data_ready:
            return None
        cdef int width = 160
        cdef int height = len(self.finished_image) * 16
        cdef unsigned char[:,:,:] image_data = np.empty((height, width, 3), dtype=np.uint8)
        cdef int i, chunk_number, y, x1, x2, comp_x, comp_y
        cdef unsigned char bitmask, bit_shift, lb, hb
        cdef unsigned char[:] pixel_values

        with cython.boundscheck(True):
            with cython.wraparound(False):
                for chunk_number in range(len(self.finished_image)):
                    for y in range(16):
                        for x2 in range(0, 20 * 2, 2):
                            bitmask = 0b10000000
                            bit_shift = 7
                            for x1 in range(8):
                                lb = ((self.finished_image[chunk_number][y][x2] & bitmask) >> bit_shift)
                                hb = (self.finished_image[chunk_number][y][x2 + 1] & bitmask) >> bit_shift << 1
                                pixel_values = self.COLOR_LUT[hb + lb]
                                comp_y = y + (chunk_number * 16)
                                comp_x = (x2 * 4) + x1
                                image_data[comp_y][comp_x][0] = pixel_values[0]
                                image_data[comp_y][comp_x][1] = pixel_values[1]
                                image_data[comp_y][comp_x][2] = pixel_values[2]
                                bitmask = bitmask >> 1
                                bit_shift -= 1

        self.print_data_ready = False
        return image_data

    cpdef unsigned char[:,:,:] get_scaled_image(self, int scale):
        if not self.print_data_ready:
            return None
        cdef int width = 160
        cdef int height = len(self.finished_image) * 16
        cdef unsigned char[:,:,:] image_data = np.empty((height * scale, width * scale, 3), dtype=np.uint8)
        cdef int i, chunk_number, y, x1, x2, comp_x, comp_y, yy, xx, comp_xx, comp_yy
        cdef unsigned char bitmask, bit_shift, lb, hb
        cdef unsigned char[:] pixel_values

        with cython.boundscheck(True):
            with cython.wraparound(False):
                for chunk_number in range(len(self.finished_image)):
                    for y in range(16):
                        for x2 in range(0, 20 * 2, 2):
                            bitmask = 0b10000000
                            bit_shift = 7
                            for x1 in range(8):
                                lb = ((self.finished_image[chunk_number][y][x2] & bitmask) >> bit_shift)
                                hb = (self.finished_image[chunk_number][y][x2 + 1] & bitmask) >> bit_shift << 1
                                pixel_values = self.COLOR_LUT[hb + lb]
                                comp_y = y + (chunk_number * 16)
                                comp_x = (x2 * 4) + x1
                                for yy in range(scale):
                                    for xx in range(scale):
                                        comp_yy = (comp_y * scale) + yy
                                        comp_xx = (comp_x * scale) + xx
                                        image_data[comp_yy][comp_xx][0] = pixel_values[0]
                                        image_data[comp_yy][comp_xx][1] = pixel_values[1]
                                        image_data[comp_yy][comp_xx][2] = pixel_values[2]
                                bitmask = bitmask >> 1
                                bit_shift -= 1

        self.print_data_ready = False
        return image_data
