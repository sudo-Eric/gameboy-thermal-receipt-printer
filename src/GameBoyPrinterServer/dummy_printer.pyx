cdef class Printer:
    def __init__(self):
        pass
    
    cpdef image(self, imageFile):
        print('%%DUMMY_PRINTER%% | Printing image "%s"' % imageFile)
    
    cpdef cut(self):
        print('%DUMMY_PRINTER% | Cutting paper')

    cpdef close(self):
        pass
