import src.GameBoyPrinterServer.constants as constants
import uuid

cdef str LOG_FILE_PATH = constants.PATH_TMP + str(uuid.uuid1(node=constants.NODE)) + ".log"
__LOG_FILE = None

cdef str NEWLINE_STRING = '\n'
cdef str DEBUG = 'DEBUG: \t%s'
cdef str INFO = 'INFO: \t%s'
cdef str WARN = 'WARN: \t%s'
cdef str ERROR = 'ERROR: \t%s'

cdef str ESC = chr(0x1B)
cdef str RED = ESC + '[31m'
cdef str YELLOW = ESC + '[33m'
cdef str BLUE = ESC + '[34m'
cdef str GREY = ESC + '[90m' #or 37
cdef str DEFAULT = ESC + '[0m'

cdef int __VERBOSITY = 0
cdef bint __USE_COLORS = False
cdef bint __DEBUG_OUTPUT = False


cpdef set_verbosity(int verbosity):
    global __VERBOSITY
    if verbosity < 0:
        __VERBOSITY = 0
    else:
        __VERBOSITY = verbosity

cpdef enable_debug_output(bint enable = True):
    global __DEBUG_OUTPUT
    __DEBUG_OUTPUT = enable

cpdef enable_color_output(bint enable = True):
    global __USE_COLORS
    __USE_COLORS = enable

cdef __open_log_file():
    global __LOG_FILE
    __LOG_FILE = open(LOG_FILE_PATH, 'a')


cpdef close():
    global __LOG_FILE
    __LOG_FILE.close()


cdef __log(str log_item):
    if __LOG_FILE is None:
        __open_log_file()
    __LOG_FILE.write(log_item)


cpdef debug(str s, str end=NEWLINE_STRING):
    if __VERBOSITY > 3:
        if __USE_COLORS:
            print(GREY + (DEBUG % s) + DEFAULT)
        else:
            print(DEBUG % s, end=end)
    if __DEBUG_OUTPUT or __VERBOSITY > 3:
        __log(DEBUG % (s + end))


cpdef info(str s, str end=NEWLINE_STRING):
    if __VERBOSITY > 2:
        if __USE_COLORS:
            print(BLUE + (INFO % s) + DEFAULT)
        else:
            print(INFO % s, end=end)
    __log(INFO % (s + end))


cpdef warn(str s, str end=NEWLINE_STRING):
    if __VERBOSITY > 1:
        if __USE_COLORS:
            print(YELLOW + (WARN % s) + DEFAULT)
        else:
            print(WARN % s, end=end)
    __log(WARN % (s + end))


cpdef error(str s, str end=NEWLINE_STRING):
    if __VERBOSITY:
        if __USE_COLORS:
             print(RED + (ERROR % s) + DEFAULT)
        else:
            print(ERROR % s, end=end)
    __log(ERROR % (s + end))


cpdef raw(unsigned char[:] raw_data):
    cdef str message = 'RAW: \t'
    cdef str value
    if __DEBUG_OUTPUT and __VERBOSITY > 3:
        print(message, end='')
        __log(message)
        for j in range(len(raw_data)):
            value = hex(raw_data[j])[2:].upper().zfill(2)
            print(value, end=' ')
            __log(value + ' ')
        print()
        __log('\n')
