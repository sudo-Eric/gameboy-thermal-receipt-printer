import pyximport; pyximport.install(language_level='3str', pyimport=True)

import src.GameBoyPrinterServer.gameboy_printer_service as gameboy_printer_service


if __name__ == '__main__':
    print("===== Program Start =====")
    gameboy_printer_service.main()
    print("===== Program End =====")
