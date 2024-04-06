from setuptools import setup
from Cython.Build import cythonize

from src.GameBoyPrinterServer import constants

setup(
    name=constants.NAME,
    version=constants.VERSION,
    description=constants.DESCRIPTION,
    install_requires=[
        'pillow>=10.2.0',
        'numpy>=1.26.4',
        'python-escpos~=3.1',
        'pyserial>=3.5'],
    ext_modules=cythonize([
        "src/*.py",
        "src/GameBoyPrinterServer/*.py",
        "src/GameBoyPrinterServer/*.pyx"
    ], language_level='3str', annotate=True)
)
