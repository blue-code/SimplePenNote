from PIL import Image, ImageDraw, ImageFont
import os

def create_note_icon(size=1024):
    # 1. Create base canvas (Clean White)
    img = Image.new('RGB', (size, size), color=(255, 255, 255))
    draw = ImageDraw.Draw(img)
    
    # 2. Draw a stylish pen shape
    # Body of the pen (Blue)
    pen_color = (0, 122, 255) # iOS Blue
    
    # Pen body
    draw.rounded_rectangle([size*0.3, size*0.2, size*0.4, size*0.7], fill=pen_color, radius=int(size*0.05))
    # Pen tip
    draw.polygon([(size*0.3, size*0.7), (size*0.4, size*0.7), (size*0.35, size*0.85)], fill=pen_color)
    # Pen clip
    draw.rounded_rectangle([size*0.4, size*0.3, size*0.45, size*0.5], fill=pen_color, radius=int(size*0.02))
    
    # 3. Add some "writing" lines
    line_color = (200, 200, 200)
    for i in range(3):
        y = size * (0.4 + i * 0.1)
        draw.line([size*0.55, y, size*0.8, y], fill=line_color, width=int(size*0.02))

    img.save("/Volumes/SSD/DEV_SSD/MY/SimplePenNote/SimplePenNote/Resources/AppIcon.png")
    print("App icon generated: AppIcon.png")

if __name__ == "__main__":
    create_note_icon()
