"""Deterministic vector primitives -> SVG source and FAF-compatible DDS textures.

No generated imagery or third-party artwork. Pillow rasterizes the same geometric
primitives recorded in each SVG, at 4x resolution before antialiasing.
"""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageOps, ImageEnhance

ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = ROOT / 'artifacts/module-icons'
OUT = ARTIFACTS / 'textures/modules'
VECTORS = ARTIFACTS / 'svg'
OUT.mkdir(parents=True, exist_ok=True)
VECTORS.mkdir(parents=True, exist_ok=True)
S = 4

class Vector:
    def __init__(self):
        self.image = Image.new('RGBA', (128*S,128*S))
        self.d = ImageDraw.Draw(self.image)
        self.svg = []
    def polygon(self, points, fill, stroke=None, width=2):
        self.d.polygon([(x*S,y*S) for x,y in points], fill=fill)
        if stroke: self.line(points+[points[0]], stroke, width)
        self.svg.append(f'<polygon points="{" ".join(f"{x},{y}" for x,y in points)}" fill="{fill}" stroke="{stroke or "none"}" stroke-width="{width}"/>')
    def line(self, points, color, width=3):
        self.d.line([(x*S,y*S) for x,y in points], fill=color, width=int(width*S), joint='curve')
        for x,y in (points[0],points[-1]):
            r=width*S/2;self.d.ellipse((x*S-r,y*S-r,x*S+r,y*S+r),fill=color)
        self.svg.append(f'<polyline points="{" ".join(f"{x},{y}" for x,y in points)}" fill="none" stroke="{color}" stroke-width="{width}" stroke-linecap="round" stroke-linejoin="round"/>')
    def ellipse(self, box, color, width=0):
        if width: self.d.ellipse(tuple(x*S for x in box),outline=color,width=int(width*S))
        else: self.d.ellipse(tuple(x*S for x in box),fill=color)
        x,y,x1,y1=box
        self.svg.append(f'<ellipse cx="{(x+x1)/2}" cy="{(y+y1)/2}" rx="{(x1-x)/2}" ry="{(y1-y)/2}" fill="{"none" if width else color}" stroke="{color if width else "none"}" stroke-width="{width}"/>')

FACTIONS={'uef':'#69b8fa','aeon':'#74e4bb','cybran':'#f67b83','seraphim':'#efca78'}
COLORS={'power':'#55adff','range':'#6cd8f0','regen':'#6de595','repair':'#6de595',
        'deflector':'#ffa44f','atomized':'#ffa44f','ballistic':'#ffa44f','impenetrable':'#ffa44f'}

def frame(v,faction):
    c=FACTIONS[faction]
    if faction=='uef':
        v.polygon([(15,5),(113,5),(123,15),(123,113),(113,123),(15,123),(5,113),(5,15)],'#101d2c',c,3)
        for x in (12,107): v.line([(x,20),(x+9,20)],c,2)
    elif faction=='aeon':
        v.ellipse((5,5,123,123),'#102620');v.ellipse((5,5,123,123),c,3)
        v.ellipse((12,12,116,116),'#31584e',1)
    elif faction=='cybran':
        v.polygon([(5,5),(98,5),(123,30),(123,123),(30,123),(5,98)],'#29181f',c,3)
        v.line([(11,29),(29,11),(47,11)],c,3);v.line([(81,117),(99,117),(117,99)],c,3)
    else:
        v.polygon([(64,3),(124,39),(116,104),(64,125),(12,104),(4,39)],'#292314',c,3)
        v.line([(50,16),(64,9),(78,16)],c,2)
    v.line([(28,101),(100,101)],'#3c5261',1)

def glyph(v,family):
    c=COLORS[family];pale='#e8f5ff'
    shield=[(37,30),(64,20),(91,30),(88,59),(79,76),(64,88),(49,76),(40,59)]
    if family=='power':
        v.polygon(shield,'#153959',c,4)
        v.line([(64,34),(64,70)],pale,7);v.line([(47,52),(81,52)],pale,7)
    elif family=='range':
        v.ellipse((40,32,88,80),c,4);v.ellipse((57,49,71,63),pale,2)
        for dx,dy in [(1,0),(-1,0),(0,1),(0,-1)]:
            x,y=64+dx*42,56+dy*38
            v.line([(64+dx*29,56+dy*26),(x,y)],c,4)
            v.line([(x-dx*8-dy*6,y-dy*8+dx*6),(x,y),(x-dx*8+dy*6,y-dy*8-dx*6)],c,3)
    elif family=='regen':
        pts=[(64+30*math.cos(t),54+30*math.sin(t)) for t in [math.radians(i) for i in range(-65,221,8)]]
        v.line(pts,c,5);v.polygon([(34,67),(32,85),(50,81)],c)
        v.line([(64,39),(64,69)],pale,5);v.line([(49,54),(79,54)],pale,5)
    elif family=='repair':
        v.polygon([(33,79),(65,48),(63,32),(73,23),(74,39),(84,43),(96,31),(96,50),(82,60),(70,58),(44,90)],'#214a33',c,4)
        v.ellipse((32,75,44,87),pale,2);v.line([(35,36),(35,54)],pale,4);v.line([(26,45),(44,45)],pale,4)
    elif family=='deflector':
        v.polygon([(65,24),(88,32),(88,61),(78,77),(65,87),(52,77),(44,61),(44,47)],'#4b321c',c,3)
        v.line([(24,75),(54,45),(28,45)],pale,5)
        v.line([(54,45),(54,69)],pale,5)
        v.line([(29,30),(43,37)],c,3)
    elif family=='atomized':
        v.ellipse((57,49,71,63),pale)
        for angle in (0,120,240):
            a=math.radians(angle)
            pts=[(64+r*math.cos(a+t),56+r*math.sin(a+t)) for r,t in [(15,-.45),(38,-.5),(38,.5),(15,.45)]]
            v.polygon(pts,c)
        v.ellipse((20,12,108,100),c,2)
        v.line([(35,25),(92,88)],pale,4)
    elif family=='ballistic':
        v.polygon([(66,20),(78,40),(78,66),(88,80),(74,76),(66,90),(58,76),(44,80),(54,66),(54,40)],'#4b321c',c,3)
        v.ellipse((60,44,72,56),pale,3)
        v.line([(28,78),(97,32)],pale,6);v.line([(83,31),(98,30),(98,45)],pale,4)
    else:
        v.polygon(shield,'#4b321c',c,4)
        v.line([(46,44),(46,70),(82,70),(82,44)],pale,4)
        v.line([(46,56),(82,56)],pale,3);v.line([(58,44),(58,56)],pale,3);v.line([(70,56),(70,70)],pale,3)

sheet=Image.new('RGB',(24*80,4*100),'#080e16');draw=ImageDraw.Draw(sheet)
for row,(faction,accent) in enumerate(FACTIONS.items()):
    column=0
    for family in COLORS:
        for level in (range(1,6) if family in ('power','range','regen','repair') else [1]):
            key=f'{family}_{level}' if family in ('power','range','regen','repair') else family
            v=Vector();frame(v,faction);glyph(v,family)
            for pip in range(5 if family in ('power','range','regen','repair') else 1):
                x=37+pip*12 if family in ('power','range','regen','repair') else 61
                v.polygon([(x,108),(x+6,108),(x+6,114),(x,114)],COLORS[family] if pip<level else '#34414c')
            image=v.image.resize((128,128),Image.Resampling.LANCZOS)
            image.save(OUT/f'{faction}_{key}.dds',pixel_format='DXT5')
            gray=ImageOps.grayscale(image).point(lambda p:int(p*.6)).convert('RGBA');gray.putalpha(image.getchannel('A'))
            gray.save(OUT/f'{faction}_{key}_dim.dds',pixel_format='DXT5')
            (VECTORS/f'{faction}_{key}.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128">'+''.join(v.svg)+'</svg>')
            sheet.paste(image.resize((72,72)),(column*80,row*100+20),image.resize((72,72)))
            column+=1
    draw.text((4,row*100+3),faction.upper(),fill=accent)
sheet.save(ARTIFACTS/'contact-sheet.png')
print('Generated 96 faction/module SVGs and 192 DDS textures.')
