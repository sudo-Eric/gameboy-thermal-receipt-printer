import os
import pyximport
import cython
import argparse
import serial

if not cython.compiled:
    pyximport.install(language_level='3str', pyimport=True)
import src.GameBoyPrinterServer.constants as constants
import src.GameBoyPrinterServer.log as log
import src.GameBoyPrinterServer.utils as utils
from src.GameBoyPrinterServer.dummy_printer import Printer as DummyPrinter
from src.GameBoyPrinterServer.dummy_serial import Serial as DummySerial
from src.GameBoyPrinterServer.serial_buffer import SerialBuffer as SerialBuffer
from src.GameBoyPrinterServer.packet_decoder import PacketDecoder as PacketDecoder


@cython.cfunc
def get_serial_device(port):
    ser = serial.Serial(
        port=port,
        baudrate=115200,
        bytesize=serial.EIGHTBITS,
        parity=serial.PARITY_NONE,
        stopbits=serial.STOPBITS_ONE
    )
    # ser.timeout = None          #block read
    ser.timeout = 1  # non-block read
    # ser.timeout = 2              #timeout block read
    ser.xonxoff = False  # disable software flow control
    ser.rtscts = False  # disable hardware (RTS/CTS) flow control
    ser.dsrdtr = False  # disable hardware (DSR/DTR) flow control
    ser.writeTimeout = 2  # timeout for write
    if not ser.isOpen():
        try:
            ser.open()
        except Exception as e:
            print("error open serial port: " + str(e))
            exit()
    ser.flushInput()  # flush input buffer, discarding all its contents
    ser.flushOutput()  # flush output buffer, aborting current output and discard all that is in buffer
    return ser

@cython.cclass
class GameBoyPrinterService:
    def __init__(self, serial_port, printer_vendor_id, printer_product_id,
                 image_save_location, color_pallet, output_image_scale):
        log.info('Initializing %s' % constants.NAME)

        self.output_dir = image_save_location
        self.create_output_dir()
        self.image_scale = output_image_scale

        if serial_port == 'DUMMY':  # TODO Make better for future use
            ser = DummySerial()
        else:
            ser = get_serial_device(serial_port)
        self.ser = SerialBuffer(ser)
        log.debug('Connecting to serial device \'%s\'' % serial_port)
        if printer_vendor_id == 0 or printer_product_id == 0:
            log.debug('No printer selected. Images will only be saved.')
            self.printer = DummyPrinter()
        else:
            log.debug('Connecting to printer')
            from escpos import printer
            self.printer = printer.Usb(printer_vendor_id, printer_product_id)

        log.debug('Initializing packet decoder')
        self.packet_decoder = PacketDecoder()
        self.packet_decoder.set_color_pallet(color_pallet)

        log.debug('Initialization completed!')

    @cython.cfunc
    def create_output_dir(self):
        log.debug('Creating output directory "%s"' % self.output_dir)
        if self.output_dir == constants.PATH_TMP:
            os.makedirs(self.output_dir, exist_ok=True)
        else:
            if not (os.path.exists(self.output_dir) and os.path.isdir(self.output_dir)):
                print("The output folder does not exist")
                exit(1)

    @cython.ccall
    def start(self):
        log.info('%s running' % constants.NAME)
        for i in range(500):
            decoded_line = utils.decode_line(self.ser.readline())
            if decoded_line is None:
                continue
            else:
                log.raw(decoded_line)
                self.packet_decoder.process_packet(decoded_line)
                if self.packet_decoder.image_ready():
                    pass
                    image_data = self.packet_decoder.get_scaled_image(self.image_scale)
                    # image_data = self.packet_decoder.get_image()
                    # utils.print_image_to_terminal(self.packet_decoder.get_image())
                    # image_data = [[0, 0xFFFFFF, 0], [0xFFFFFF, 0, 0xFFFFFF], [0, 0xFFFFFF, 0]]
                    image_file_location = utils.save_image(image_data, self.output_dir)
                    print("File saved to %s" % image_file_location)
                # print()

    @cython.ccall
    def stop(self):
        log.close()


@cython.ccall
def generate_version_string():
    return constants.NAME + " " + constants.VERSION


@cython.ccall
def generate_about_message(show_detailed_message):
    message = constants.NAME + ", version: " + constants.VERSION + ", " + constants.DESCRIPTION + "."

    if show_detailed_message:
        message += " Constants:\t%s" % ("COMPILED" if constants.COMPILED else "NOT COMPILED")
        message += " Service:\t%s" % ("COMPILED" if cython.compiled else "NOT COMPILED")
        message += " Decoder:\t%s" % "COMPILED"

    return message


@cython.ccall
def main():
    # print(constants.COMPILED)
    parser = argparse.ArgumentParser()
    parser.add_argument('--version', action='version', version=generate_version_string())
    parser.add_argument("--about", action='version',
                        version=generate_about_message(constants.DISPLAY_DETAILED_ABOUT),
                        help="Display information about program")
    parser.add_argument('--serial', required=True, help='Location of the GameBoy Printer Emulator serial device')
    printer_group = parser.add_mutually_exclusive_group(required=True)
    printer_group.add_argument('--printer', nargs=2, help='Vendor and product ID of the thermal printer')
    printer_group.add_argument('--no-printer', action='store_true', help='Do not use a printer. Save images only.')
    parser.add_argument("--pallet", type=int, choices=range(len(constants.COLOR_PALLET_NAMES)),
                        default=constants.DEFAULT_PALLET, help="Specify the color pallet to use for the saved image")
    parser.add_argument('--scale', type=int, choices=range(1, 6), default=3,
                        help='Specify the amount the image should be scaled')
    parser.add_argument("-d", "--dest", default=constants.PATH_TMP,
                        help="Location to store saved images. Default is the systems temp directory.")
    parser.add_argument('-v', '--verbose', type=int, nargs='?', default=1, dest='verbosity')
    parser.add_argument('--no-color', action='store_true', help='Disable color on terminal output')

    args = parser.parse_args()

    if args.verbosity is None:
        args.verbosity = 2

    if args.no_printer:
        args.printer = (0, 0)
    if not args.no_printer and args.pallet != constants.DEFAULT_PALLET:
        print("Pallet must be %d (%s) when using a printer" %
              (constants.DEFAULT_PALLET, constants.COLOR_PALLET_NAMES[constants.DEFAULT_PALLET]))
        exit(1)

    log.set_verbosity(args.verbosity)
    log.enable_debug_output()
    log.enable_color_output(not args.no_color)

    service = GameBoyPrinterService(
        serial_port=args.serial,
        printer_vendor_id=args.printer[0],
        printer_product_id=args.printer[1],
        image_save_location=args.dest,
        color_pallet=args.pallet,
        output_image_scale=args.scale)

    service.start()  # TODO Make the server run on a different thread
    service.stop()
