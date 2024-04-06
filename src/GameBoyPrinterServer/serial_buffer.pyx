import cython
import serial
from queue import Queue

cdef class SerialBuffer:
    cdef object ser
    cdef object line_buffer

    def __init__(self, ser, max_buffer_size=10):
        self.ser = ser
        self.line_buffer = Queue(max_buffer_size)

    cpdef readline(self):
        while self.ser.in_waiting != 0 and not self.line_buffer.full():
            self.line_buffer.put(self.ser.readline().decode("ASCII"))
        if self.line_buffer.empty():
            return None
        return self.line_buffer.get()
