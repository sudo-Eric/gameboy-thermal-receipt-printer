#!/usr/bin/python3

import pyximport;pyximport.install(language_level='3str', pyimport=True)
import configparser
import argparse
import os.path
import logging
import sys
from logging import handlers

import GameBoyPrinterServer.constants as constants
import GameBoyPrinterServer.game_boy_printer_server as game_boy_printer_server

LOGGING_LEVELS = {
    'DEBUG': logging.DEBUG,
    'INFO': logging.INFO,
    'WARNING': logging.WARNING,
    'ERROR': logging.ERROR,
    'CRITICAL': logging.CRITICAL
}


def determine_config_value(config_file_value, param_value, default_value, validator=None):
    value = default_value
    if config_file_value is not None:
        value = config_file_value
    if param_value is not None:
        value = param_value
    if validator is not None:
        validator(value)
    return value


def validate_log_level(log_level):
    if log_level not in LOGGING_LEVELS:
        print('Invalid logging level specified. Valid log levels are %s.' % ', '.join(LOGGING_LEVELS.keys()))
        exit(1)


def validate_pallet(pallet):
    if pallet not in range(len(constants.COLOR_PALLET_NAMES)):
        print("Invalid color pallet specified.")
        exit(1)


def validate_scale(scale):
    if scale not in constants.SCALE_RANGE:
        print("Invalid scale specified. Valid scale values are %s." %
              ', '.join([str(x) for x in constants.SCALE_RANGE]))
        exit(1)


def validate_serial_device(serial):
    if serial is None:
        print('Serial device not specified. Please specify serial device.')
        exit(1)


def log_config_values(config, args):
    logging.debug('Program args: %s', args)
    logging.debug('Verbosity: %s', dict((v, k) for k, v in LOGGING_LEVELS.items())[config['verbosity']])
    logging.debug('Printer: %s', config['printer'])
    logging.debug('Pallet: %s', constants.COLOR_PALLET_NAMES[config['pallet']])
    logging.debug('Scale: %s', config['scale'])
    logging.debug('Output directory: %s', config['output'])


def initialize_logger(log_level, log_location):
    logger = logging.getLogger()
    for handler in logger.handlers:
        logger.removeHandler(handler)
    logger.setLevel(log_level)
    formatter = logging.Formatter(logging.BASIC_FORMAT)

    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(formatter)
    logger.addHandler(ch)

    # fh = handlers.RotatingFileHandler(log_location)  # TODO Uncomment later
    # fh.setFormatter(formatter)
    # fh.setLevel(logging.DEBUG)
    # logger.addHandler(fh)


if __name__ == '__main__':
    config = {
        'verbosity': 'WARNING',
        'printer': None,
        'serial': None,
        'pallet': constants.DEFAULT_PALLET,
        'scale': 3,
        'output': constants.PATH_TMP
    }

    parser = argparse.ArgumentParser()
    parser.add_argument('--version', action='version', version=game_boy_printer_server.generate_version_string())
    parser.add_argument("--about", action='version', version=game_boy_printer_server.generate_about_message())
    parser.add_argument('-c', '--config', default=constants.DEFAULT_CONFIG_NAME,
                        help='Location of program config (default config.ini)')
    parser.add_argument('--serial', required=True,
                        help='Location of the GameBoy Printer Emulator serial device')
    parser.add_argument('--no-printer', action='store_true', help='Do not use a printer. Save images only.')
    parser.add_argument('-p', '--pallet', type=int, choices=range(len(constants.COLOR_PALLET_NAMES)),
                        default=constants.DEFAULT_PALLET, help="Specify the color pallet to use for the saved image")
    parser.add_argument('-s', '--scale', type=int, choices=constants.SCALE_RANGE, default=3,
                        help='Specify the amount the image should be scaled')
    parser.add_argument('-d', '--dest', default=constants.PATH_TMP,
                        help='Location to store saved images. Default is the systems temp directory.')
    parser.add_argument('-v', '--verbose', type=str, default=config['verbosity'], nargs='?', dest='verbosity')
    parser.add_argument('--log', type=str, help='Location of the log file')

    args = parser.parse_args()

    # Process logging level first
    if args.verbosity is None:
        args.verbosity = 'INFO'
    config['verbosity'] = determine_config_value(
        config_file_value=None,
        param_value=args.verbosity.upper(),
        default_value='WARNING',
        validator=validate_log_level)
    config['verbosity'] = LOGGING_LEVELS[args.verbosity.upper()]
    log_location = os.path.abspath(determine_config_value(
        config_file_value=constants.LOG_FILE_NAME,
        param_value=args.log,
        default_value=constants.LOG_FILE_NAME
    ))

    if os.path.isdir(log_location):
        if os.path.exists(log_location):
            log_location = os.path.join(log_location, constants.LOG_FILE_NAME)
        else:
            logging.error('Log folder location does not exist "%s"', log_location)
            exit(1)
    else:
        if not os.path.exists(os.path.abspath(os.path.join(log_location, os.pardir))):
            logging.error('Log file location does not exist "%s"', log_location)
            exit(1)

    initialize_logger(config['verbosity'], log_location)

    if not os.path.exists(args.config) or not os.path.isfile(args.config):
        logging.warning('Specified config file does not exist "%s". Using default config.' % args.config)
        args.config = constants.DEFAULT_CONFIG_NAME

    config_parser = configparser.ConfigParser()
    config_parser.read(args.config)

    config['pallet'] = determine_config_value(
        config_file_value=config_parser.getint('general', 'pallet', fallback=constants.DEFAULT_PALLET),
        param_value=args.pallet,
        default_value=constants.DEFAULT_PALLET,
        validator=validate_pallet
    )

    config['scale'] = determine_config_value(
        config_file_value=config_parser.getint('general', 'scale', fallback=3),
        param_value=args.scale,
        default_value=3,
        validator=validate_scale
    )

    if not args.no_printer:
        config['printer'] = config_parser['printer']
        if config['pallet'] != constants.DEFAULT_PALLET:
            logging.warning('Pallet not (yet) valid when using printer. Using default pallet.')
            config['pallet'] = constants.DEFAULT_PALLET

    config_parser.set('serial', 'port', str(
        determine_config_value(
            config_file_value=config_parser.get('serial', 'port', fallback=None),
            param_value=args.serial,
            default_value=None,
            validator=validate_serial_device
        )))

    config['serial'] = config_parser['serial']

    config['output'] = determine_config_value(
        config_file_value=config_parser.get('general', 'output', fallback=constants.PATH_TMP),
        param_value=os.path.abspath(args.dest),
        default_value=constants.PATH_TMP,
        validator=validate_serial_device
    )

    log_config_values(config, args)

    game_boy_printer_server.start(config)
