import configparser
import logging
import os
from typing import Optional, Union
import escpos.printer as escpos_printer
import pyximport
import cython
import serial

if not cython.compiled:
    pyximport.install(language_level='3str', pyimport=True)
import src.GameBoyPrinterServer.constants as constants
import src.GameBoyPrinterServer.utils as utils
from src.GameBoyPrinterServer.dummy_serial import Serial as DummySerial
from src.GameBoyPrinterServer.packet_decoder import PacketDecoder as PacketDecoder


@cython.cfunc
def get_serial_device(serial_config: configparser.SectionProxy):
    logging.info('Opening serial device')
    try:
        ser = serial.Serial(
            port=serial_config.get('port'),
            baudrate=serial_config.getint('baudrate', 115200),
            bytesize=serial_config.getint('bytesize', serial.EIGHTBITS),
            parity=serial_config.get('parity', serial.PARITY_NONE),
            stopbits=serial_config.getfloat('stopbits', serial.STOPBITS_ONE)
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
    except Exception as e:
        logging.error('Error at %s', 'division', exc_info=e)  # TODO Update error message


@cython.cfunc
def initialize_printer(printer_config: configparser.SectionProxy):
    if printer_config is None:
        logging.info('No printer specified. Initializing dummy printer.')
        return escpos_printer.Dummy()
    logging.info('Initializing printer')
    printer_type = printer_config.get('type').upper()
    printer_profile = printer_config.get('profile', None).upper()
    printer = None
    if printer_type is None:
        logging.error('Printer type was not specified')
        exit(1)
    elif printer_type == "USB":
        vendor_id = int(printer_config.get('vendorID'), 16)
        product_id = int(printer_config.get('productID'), 16)
        timeout = printer_config.getint('timeout', fallback=0)
        printer = escpos_printer.Usb(idVendor=vendor_id,
                                     idProduct=product_id,
                                     timeout=timeout,
                                     profile=printer_profile)
    elif printer_type == "SERIAL":
        device = printer_config.get('device')
        baudrate = printer_config.getint('baudrate', fallback=9600)
        bytesize = printer_config.getint('bytesize', fallback=8)
        parity = printer_config.get('parity', fallback='N')
        stopbits = printer_config.getint('stopbits', fallback=1)
        timeout = printer_config.getfloat('timeout', fallback=1.0)
        xonxoff = printer_config.getboolean('xonxoff', fallback=False)
        dsrdtr = printer_config.getboolean('dsrdtr', fallback=True)
        printer = escpos_printer.Serial(devfile=device,
                                        baudrate=baudrate,
                                        bytesize=bytesize,
                                        timeout=timeout,
                                        parity=parity,
                                        stopbits=stopbits,
                                        xonxoff=xonxoff,
                                        dsrdtr=dsrdtr,
                                        profile=printer_profile)
    elif printer_type == "NETWORK":
        host = printer_config.get('host')
        port = printer_config.getint('port', fallback=9100)
        timeout = printer_config.getint('timeout', fallback=60)
        printer = escpos_printer.Network(host=host,
                                         port=port,
                                         timeout=timeout,
                                         profile=printer_profile)
    elif printer_type == "FILE":
        file = printer_config.get('file')
        auto_flush = printer_config.getboolean('autoFlush', fallback=True)
        printer = escpos_printer.File(devfile=file,
                                      auto_flush=auto_flush,
                                      profile=printer_profile)
    elif printer_type == "DUMMY":
        printer = escpos_printer.Dummy(profile=printer_profile)
    else:
        logging.error('Invalid printer type "%s"', printer_type)
    if not printer.is_usable():
        logging.info('Printer is ready')
    return printer


@cython.cfunc
def format_raw_data(raw_data):
    message: str = 'RAW: \t'
    for data in raw_data:
        message += hex(data)[2:].upper().zfill(2) + ' '
    return message


@cython.cclass
class GameBoyPrinterService:
    def __init__(self,
                 serial: Union[serial.Serial, DummySerial],
                 printer: Union[escpos_printer.Usb, escpos_printer.Serial, escpos_printer.Network, escpos_printer.File, escpos_printer.Dummy],
                 image_save_location,
                 color_pallet: int,
                 output_image_scale: int):
        logging.info('Initializing %s', constants.NAME)

        self.ser = serial
        self.printer = printer

        self.output_dir = image_save_location
        self.create_output_dir()
        self.image_scale = output_image_scale

        logging.debug('Initializing packet decoder')
        self.packet_decoder = PacketDecoder()
        self.packet_decoder.set_color_pallet(color_pallet)

        logging.debug('Initialization completed!')

    @cython.cfunc
    def create_output_dir(self):
        logging.info('Creating output directory "%s"', self.output_dir)
        if self.output_dir == constants.PATH_TMP:
            os.makedirs(self.output_dir, exist_ok=True)
        else:
            if os.path.exists(self.output_dir) and not os.path.isdir(self.output_dir):
                logging.error('The output location is not a folder')
                exit(1)
            try:
                os.makedirs(self.output_dir, exist_ok=True)
            except Exception as e:
                logging.error('Unable to create output directory "%s"', self.output_dir)
                exit(1)

    @cython.ccall
    def start(self):
        logging.debug('%s running', constants.NAME)
        for i in range(500):
            decoded_line = utils.decode_line(self.ser.readline())
            if decoded_line is None:
                continue
            else:
                logging.debug(format_raw_data(decoded_line))
                self.packet_decoder.process_packet(decoded_line)
                if self.packet_decoder.image_ready():
                    pass
                    image_data = self.packet_decoder.get_scaled_image(self.image_scale)
                    # image_data = self.packet_decoder.get_image()
                    # utils.print_image_to_terminal(self.packet_decoder.get_image())
                    # image_data = [[0, 0xFFFFFF, 0], [0xFFFFFF, 0, 0xFFFFFF], [0, 0xFFFFFF, 0]]
                    image_file_location = utils.save_image(image_data, self.output_dir)
                    logging.info("Image saved to %s", image_file_location)
                    logging.info("Printing image")
                    self.printer.image(image_file_location)
                    self.printer.cut()
                # print()

    @cython.ccall
    def stop(self):
        pass


game_boy_printer_service: Optional[GameBoyPrinterService] = None


@cython.ccall
def generate_version_string():
    return constants.NAME + " " + constants.VERSION


@cython.ccall
def generate_about_message():
    return constants.NAME + ', version: ' + constants.VERSION + ', ' + constants.DESCRIPTION + '.'


@cython.ccall
def start(config: dict):
    global game_boy_printer_service
    logging.info("Starting Game Boy printer service")
    if game_boy_printer_service is not None:
        logging.error("Game Boy printer service is already running")
        return

    if config['serial'].get('port').startswith(constants.DUMMY_SERIAL_PREFIX):  # For testing purposes only
        logging.debug('Initializing dummy serial device')
        temp = config['serial'].get('port').split('=')
        if len(temp) == 1:
            serial_device = DummySerial('dummy_serial_data.txt')
        else:
            serial_device = DummySerial(temp[1])
    else:
        serial_device = get_serial_device(config['serial'])

    printer = initialize_printer(config['printer'])

    game_boy_printer_service = GameBoyPrinterService(
        serial=serial_device,
        printer=printer,
        image_save_location=config['output'],
        color_pallet=config['pallet'],
        output_image_scale=config['scale'])

    game_boy_printer_service.start()  # TODO Make the server run on a different thread


@cython.ccall
def stop():
    global game_boy_printer_service
    if game_boy_printer_service is None:
        logging.warning("Game Boy printer service is not running")
        return
    logging.info("Stopping Game Boy printer service")
    game_boy_printer_service.stop()
