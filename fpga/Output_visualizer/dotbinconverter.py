from PIL import Image

# 1. Path to your new image on your PC
new_image_path = r"C:\Users\nakul\OneDrive\Desktop\projects\fpga\test_image_2_gray_sizedagain.jpg" 
img = Image.open(new_image_path)

# 2. Rescale directly to your exact Sobel matrix geometry (80x48)
img_gray = img.convert("L").resize((80, 48))

# 3. Save as the raw binary data file name expected by Thonny
with open("mimager.bin", "wb") as f:
    f.write(img_gray.tobytes())

print(f"Success! Generated 'mimage.bin' (exactly {len(img_gray.tobytes())} bytes).")
print("Upload this file to your RP2040 root directory using Thonny.")
