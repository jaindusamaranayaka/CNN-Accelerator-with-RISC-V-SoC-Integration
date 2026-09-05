import serial
import time
import sys
import os

# Configuration (Change COM3 to whatever your DE2-115 shows up as in Device Manager)
COM_PORT = 'COM3'
BAUD_RATE = 115200

def send_image():
    print(f"Connecting to FPGA on {COM_PORT} at {BAUD_RATE} baud...")
    
    try:
        ser = serial.Serial(COM_PORT, BAUD_RATE, timeout=2)
    except Exception as e:
        print(f"Error opening port: {e}")
        print("Make sure you have the correct COM port and it is not in use.")
        sys.exit(1)
        
    # Wait a moment for connection to stabilize
    time.sleep(2)
    
    # 1. Create a dummy 28x28 image (784 bytes)
    # In a real scenario, you would use PIL/cv2 to open an image:
    # img = cv2.imread('digit.png', cv2.IMREAD_GRAYSCALE)
    # img = cv2.resize(img, (28, 28))
    # image_bytes = img.flatten().tobytes()
    
    print("Generating dummy 28x28 image...")
    image_bytes = bytes([128] * 784) # Dummy image filled with gray (value 128)
    
    # 2. Send Start Token
    print("Sending Start Token 'S'...")
    ser.write(b'S')
    
    # 3. Send Image Bytes
    print("Sending 784 bytes of image data...")
    ser.write(image_bytes)
    
    # 4. Wait for Result
    print("Waiting for classification result...")
    while True:
        token = ser.read(1)
        if token == b'R':
            result_byte = ser.read(1)
            result = int.from_bytes(result_byte, byteorder='little')
            print(f"=====================================")
            print(f"SUCCESS! FPGA Classified Digit as: {result}")
            print(f"=====================================")
            break
            
    ser.close()

if __name__ == "__main__":
    send_image()
