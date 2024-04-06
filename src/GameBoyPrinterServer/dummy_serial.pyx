cdef class Serial:
    cdef int current_line, end_line
    cdef public int in_waiting
    cdef list dummy_serial_data
    def __init__(self):
        serial_file = open('dummy_serial_data.txt', 'r')
        self.current_line = -1
        self.dummy_serial_data = serial_file.readlines()
        self.end_line = len(self.dummy_serial_data) - 1
        self.in_waiting = self.end_line - self.current_line
        serial_file.close()

    cpdef readline(self):
        if self.current_line == self.end_line:
            return ''
        self.current_line += 1
        self.in_waiting = self.end_line - self.current_line
        return self.dummy_serial_data[self.current_line].encode('ASCII')
