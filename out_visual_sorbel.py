import serial
import numpy as np
import cv2

SERIAL_PORT = "COM15" # Update to match your active port connection
BAUD_RATE = 115200
IMAGE_WIDTH = 80
IMAGE_HEIGHT = 46  # Processed window height drops by 2 rows due to Sobel border losses
EXPECTED_BYTES = 3680 # 80 * 46

try:
    ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=0.5)
    print(f"Connected to {SERIAL_PORT}. Listening for Sobel edge data frames...")
except serial.SerialException as e:
    print(f"Error: {e}")
    exit()

raw_stream_buffer = bytearray()
cv2.namedWindow("FPGA Sobel Edge Detector", cv2.WINDOW_NORMAL)

while True:
    data = ser.read(2048)
    if data:
        raw_stream_buffer.extend(data)
        
        if b"START_FRAME" in raw_stream_buffer and b"END_FRAME" in raw_stream_buffer:
            start_idx = raw_stream_buffer.find(b"START_FRAME") + len(b"START_FRAME")
            end_idx = raw_stream_buffer.find(b"END_FRAME")
            
            pixel_payload = raw_stream_buffer[start_idx:end_idx]
            
            if len(pixel_payload) == EXPECTED_BYTES:
                img_np = np.frombuffer(pixel_payload, dtype=np.uint8)
                
                # Align the pipeline lag offset
                aligned_pixels = np.roll(img_np, -2)
                
                img_gray = aligned_pixels.reshape((IMAGE_HEIGHT, IMAGE_WIDTH))
                scaled_img = cv2.resize(img_gray, (400, 230), interpolation=cv2.INTER_NEAREST)
                
                cv2.imshow("FPGA Sobel Edge Detector", scaled_img)
                
            raw_stream_buffer = raw_stream_buffer[end_idx + len(b"END_FRAME"):]
            
    if cv2.waitKey(1) & 0xFF == ord('q'):
        break

ser.close()
cv2.destroyAllWindows()
