import sys
import shrike
from machine import Pin, SPI
import time

shrike.flash("FPGA_bitstream_MCU.bin")

IMAGE_WIDTH = 80
IMAGE_HEIGHT = 48
TOTAL_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT
SOBEL_PAYLOAD_SIZE = IMAGE_WIDTH * (IMAGE_HEIGHT - 2) * 3

SPI_ID, SCK_PIN, MOSI_PIN, MISO_PIN, CS_PIN, RESET_PIN = 0, 2, 3, 0, 1, 14

reset_pin = Pin(RESET_PIN, Pin.OUT, value=1)
reset_pin.value(0)
time.sleep_ms(50)
reset_pin.value(1)
time.sleep_ms(100)

cs = Pin(CS_PIN, Pin.OUT, value=1)
spi = SPI(SPI_ID, baudrate=5000000, polarity=0, phase=0,
          bits=8, firstbit=SPI.MSB, sck=Pin(SCK_PIN), mosi=Pin(MOSI_PIN), miso=Pin(MISO_PIN))

# Pre-allocate static transmission buffers to optimize runtime memory performance
tx_buffer = bytearray(SOBEL_PAYLOAD_SIZE)
rx_buffer = bytearray(SOBEL_PAYLOAD_SIZE)

def run_sobel_streaming(filename):
    try:
        with open(filename, "rb") as f:
            raw_pixels = f.read(TOTAL_PIXELS)
            
        idx = 0
        for y in range(1, IMAGE_HEIGHT - 1):
            row_top = (y - 1) * IMAGE_WIDTH
            row_mid = y * IMAGE_WIDTH
            row_bot = (y + 1) * IMAGE_WIDTH
            
            for x in range(IMAGE_WIDTH):
                tx_buffer[idx]   = raw_pixels[row_top + x]
                tx_buffer[idx+1] = raw_pixels[row_mid + x]
                tx_buffer[idx+2] = raw_pixels[row_bot + x]
                idx += 3

        # HIGH SPEED CONTINUOUS BURST
        cs.value(0)
        spi.write_readinto(tx_buffer, rx_buffer)
        cs.value(1)
        
        # Extract edge pixels (one processed byte per every 3 input bytes)
        edge_pixels = bytearray(IMAGE_WIDTH * (IMAGE_HEIGHT - 2))
        for i in range(len(edge_pixels)):
            edge_pixels[i] = rx_buffer[i * 3 + 2] 

        sys.stdout.buffer.write(b"START_FRAME")
        sys.stdout.buffer.write(edge_pixels)
        sys.stdout.buffer.write(b"END_FRAME")
        
    except OSError:
        pass

while True:
    run_sobel_streaming("mimage.bin")
    time.sleep(1)

