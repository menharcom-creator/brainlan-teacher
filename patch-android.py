# Run after `npx cap add android`: allow http/ws to the teacher's iPhone and use the BrainLAN icon.
import re,os,glob
from PIL import Image
m='android/app/src/main/AndroidManifest.xml'
s=open(m).read()
if 'usesCleartextTraffic' not in s:
    s=s.replace('<application','<application android:usesCleartextTraffic="true"',1)
open(m,'w').write(s)
res='android/app/src/main/res'
for d in glob.glob(res+'/mipmap-anydpi*'):
    for f in glob.glob(d+'/*'): os.remove(f)
    os.rmdir(d)
icon=Image.open('assets/AppIcon-512@2x.png').convert('RGBA')
for dens,px in {'mdpi':48,'hdpi':72,'xhdpi':96,'xxhdpi':144,'xxxhdpi':192}.items():
    for n in ('ic_launcher.png','ic_launcher_round.png'):
        os.makedirs(f'{res}/mipmap-{dens}',exist_ok=True)
        icon.resize((px,px),Image.LANCZOS).save(f'{res}/mipmap-{dens}/{n}')
print('android patched')
