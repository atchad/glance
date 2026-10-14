"""Package reviewed, window-only Computer Use captures into README assets.

Usage: python3 scripts/readme-media/encode.py /path/to/captures
Requires Pillow. Inputs are panel.png, colors.png, search-02..04.png,
and triage-01..04.png. Never pass desktop captures or live-account images.
"""
from pathlib import Path
import sys
from PIL import Image, ImageDraw, ImageFont, ImageOps

source = Path(sys.argv[1])
output = Path(__file__).resolve().parents[2] / 'docs/images'
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial.ttf', 24)
background = '#111722'

def frame(name, caption=None, settings=False):
    im = Image.open(source / name).convert('RGB')
    expected = (1440, 1184) if settings else (880, 1220)
    if im.size != expected:
        raise ValueError(f'{name}: expected window-only capture {expected}, got {im.size}')
    # Exclude the titlebar's macOS screen-sharing indicator; retain app content.
    im = im.crop((0, 96 if settings else 72, im.width, im.height))
    mask = Image.new('L', im.size)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, im.width-1, im.height-1), radius=22, fill=255)
    canvas = Image.new('RGB', (im.width+64, im.height+64+(64 if caption else 0)), background)
    canvas.paste(im, (32,32), mask)
    if caption:
        draw = ImageDraw.Draw(canvas)
        draw.text((canvas.width/2, canvas.height-48), caption, anchor='mm', font=font, fill='#dfe6f2')
    return canvas

frame('panel.png').save(output / 'glance-panel.png', optimize=True)
frame('colors.png', settings=True).save(output / 'glance-colors.png', optimize=True)
sequences = {
    'glance-search.gif': [('panel.png','Find your next review'),
        ('search-02.png','Search by repository: desktop'),
        ('search-03.png','Switch to API work'), ('search-04.png','Clear search to see the full queue')],
    'glance-triage.gif': [('triage-01.png','Select a pull request with J / K'),
        ('triage-02.png','Press P to pin it'), ('triage-03.png','Press D to dismiss this revision'),
        ('triage-04.png','Click Undo to bring it back')],
}
for name, states in sequences.items():
    frames = [frame(path, caption) for path, caption in states]
    # One shared palette keeps text and material colors stable between states.
    atlas = Image.new('RGB',(frames[0].width,frames[0].height*len(frames)))
    for i, im in enumerate(frames): atlas.paste(im,(0, i*im.height))
    palette = atlas.quantize(colors=256)
    frames = [im.quantize(palette=palette, dither=Image.Dither.NONE) for im in frames]
    frames[0].save(output / name, save_all=True, append_images=frames[1:],
        duration=[1800,2200,2200,2200], loop=0, optimize=True, disposal=2)
# A review sheet shows every final GIF frame, including captions.
thumbs=[]
for name in sequences:
    im=Image.open(output/name)
    for index in range(im.n_frames):
        im.seek(index)
        thumbs.append(ImageOps.contain(im.convert('RGB'), (330,480)))
sheet=Image.new('RGB',(4*350,2*500),background)
for index,thumb in enumerate(thumbs): sheet.paste(thumb,((index%4)*350,(index//4)*500))
sheet.save(source/'review-sheet.png')
