# Synthetic RGBA frames with semi-transparent and fully transparent pixels
from PIL import Image
def frame(name, w, h, seed):
    im = Image.new('RGBA', (w, h))
    px = im.load()
    for y in range(h):
        for x in range(w):
            r = (x * 37 + seed * 51) % 256
            g = (y * 53 + seed * 29) % 256
            b = ((x + y) * 19 + seed * 83) % 256
            a = (x * 255 // max(w - 1, 1) + y * 7 + seed * 40) % 256
            if (x // 4 + y // 4 + seed) % 5 == 0:
                a = 0
            elif (x + y + seed) % 7 == 0:
                a = 255
            px[x, y] = (r, g, b, a)
    im.save(name)
specs = [('f1', 40, 30), ('f2', 30, 20), ('f3', 36, 28), ('f4', 64, 48),
         ('f5', 20, 20), ('f6', 16, 16), ('f7', 24, 24), ('f8', 64, 48)]
for i, (n, w, h) in enumerate(specs):
    frame(n + '.png', w, h, i + 1)
