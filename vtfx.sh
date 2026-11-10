#!/bin/bash
# vtfx.sh - recreate the Video Toolbox "Video FX" presets with ffmpeg.
#
#   ./vtfx.sh <preset> input.mov output.mp4
#   ./vtfx.sh list
#
# Needs ffmpeg (brew install ffmpeg). Keep the .cube files next to this script.
# Presets: blackwhite sepia red green blue monored monogreen monoblue
#          classic beauty 70s avenue sunset lens
#          erosion dilation pixellate dots blur zoomblur sketch pinch stretch
#          ghosting clock

set -e
PRESETS="blackwhite sepia red green blue monored monogreen monoblue classic beauty 70s avenue sunset lens erosion dilation pixellate dots blur zoomblur sketch pinch stretch ghosting clock"
if [ "$1" = "list" ] || [ $# -lt 3 ]; then
  echo "usage: $0 <preset> input output"; echo "presets: $PRESETS"; exit 0
fi
PRESET=$(echo "$1" | tr 'A-Z' 'a-z'); IN=$2; OUT=$3

# lut3d wants a plain path, so work from the folder that holds the .cube files
abspath() { case "$1" in /*) echo "$1";; *) echo "$PWD/$1";; esac; }
IN=$(abspath "$IN"); OUT=$(abspath "$OUT")
cd "$(dirname "$0")"

# rgb3 EXPR [OPTS]: geq filter that runs EXPR on each colour plane; write the plane as C(x,y)
rgb3() { local e=$1; echo "geq=r='${e//C(/r(}':g='${e//C(/g(}':b='${e//C(/b(}'${2:+:$2}"; }

# warp EXPR: like rgb3, for presets that sample between pixels. ffmpeg's geq cannot read the
# last row/column when interpolating, so pad by one smeared pixel first and crop it off after.
warp() { local e=$1; e=${e//W/(W-1)}; e=${e//H/(H-1)}; echo "pad=iw+1:ih+1,fillborders=right=1:bottom=1:mode=smear,$(rgb3 "$e"),crop=iw-1:ih-1:0:0"; }

GREY="colorchannelmixer=.2125:.7154:.0721:0:.2125:.7154:.0721:0:.2125:.7154:.0721:0"
LO="min(2*val,255)"; HI="max(2*val-255,0)"     # the two halves of GPUImage's monochrome tint

case "$PRESET" in
  blackwhite) G="$GREY" ;;
  sepia)      G="colorchannelmixer=.3588:.7044:.1368:0:.2990:.5870:.1140:0:.2392:.4696:.0912:0" ;;
  red)        G="lutrgb=r='$LO'" ;;
  green)      G="lutrgb=g='$LO'" ;;
  blue)       G="lutrgb=b='$LO'" ;;
  monored)    G="$GREY,lutrgb=r='$LO':g='$HI':b='$HI'" ;;
  monogreen)  G="$GREY,lutrgb=g='$LO':r='$HI':b='$HI'" ;;
  monoblue)   G="$GREY,lutrgb=b='$LO':r='$HI':g='$HI'" ;;
  classic)    G="lut3d=GPUImage_Amatorka.cube" ;;
  beauty)     G="lut3d=GPUImage_MissEtikate.cube" ;;
  70s)        G="lut3d=VideoToolbox_70s.cube" ;;
  avenue)     # centre grade and edge grade, mixed by squared distance from the centre
              G="split[a][b];[a]lut3d=VideoToolbox_Avenue_center.cube[a];[b]lut3d=VideoToolbox_Avenue_edge.cube[b];[a][b]blend=all_expr='A+(B-A)*pow(max(min(1,pow(2*(X+0.5)/W-1,2)+pow(2*(Y+0.5)/H-1,2))-0.42,0)/0.58,1.25)'" ;;
  sunset)     G="curves=b='0/0 0.5/0 1/0.75'" ;;
  lens)       G=$(rgb3 "st(0,clip((hypot((X+0.5)/W-0.5,(Y+0.5)/H-0.5)-0.3)/0.45,0,1));C(X,Y)*(1-ld(0)*ld(0)*(3-2*ld(0)))" "interpolation=nearest") ;;
  erosion)    G="erosion,erosion,erosion,erosion" ;;
  dilation)   G="dilation,dilation,dilation,dilation" ;;
  pixellate)  G=$(rgb3 "st(0,W/20);C((floor((X+0.5)/ld(0))+0.5)*ld(0),(floor((Y+0.5)/ld(0))+0.5)*ld(0))" "interpolation=nearest") ;;
  dots)       G=$(rgb3 "st(0,W/92.6);st(1,(floor((X+0.5)/ld(0))+0.5)*ld(0));st(2,(floor((Y+0.5)/ld(0))+0.5)*ld(0));if(lte(hypot(X+0.5-ld(1),Y+0.5-ld(2)),0.45*ld(0)),C(ld(1),ld(2)),0)" "interpolation=nearest") ;;
  blur)       G="split[a][b];[b]gblur=sigma=5[b];[a][b]blend=all_expr='A+(B-A)*pow(clip((hypot((X+0.5)/W-0.5,((Y+0.5)/H-0.5)*W/H)-0.4)/0.1,0,1),2)*(3-2*clip((hypot((X+0.5)/W-0.5,((Y+0.5)/H-0.5)*W/H)-0.4)/0.1,0,1))'" ;;
  zoomblur)   G=$(warp "st(0,(W/2-X-0.5)*0.025);st(1,(H/2-Y-0.5)*0.025);0.18*C(X,Y)+0.15*(C(X+ld(0),Y+ld(1))+C(X-ld(0),Y-ld(1)))+0.12*(C(X+2*ld(0),Y+2*ld(1))+C(X-2*ld(0),Y-2*ld(1)))+0.09*(C(X+3*ld(0),Y+3*ld(1))+C(X-3*ld(0),Y-3*ld(1)))+0.05*(C(X+4*ld(0),Y+4*ld(1))+C(X-4*ld(0),Y-4*ld(1)))") ;;
  sketch)     G="$GREY,sobel=scale=0.5,negate" ;;
  pinch)      G=$(warp "st(0,(X+0.5)/W-0.5);st(1,(Y+0.5)/H-0.5);st(2,2-2*hypot(ld(0),ld(1)*H/W));C((ld(0)*ld(2)+0.5)*W-0.5,(ld(1)*ld(2)+0.5)*H-0.5)") ;;
  stretch)    G=$(warp "st(0,2*(X+0.5)/W-1);st(1,abs(ld(0)));st(2,clip((ld(1)-0.25)/0.25,0,1));st(3,sgn(ld(0))*(0.5*ld(1)+0.5*ld(2)*ld(2)*(3-2*ld(2))*ld(1)));st(4,2*(Y+0.5)/H-1);st(5,abs(ld(4)));st(6,clip((ld(5)-0.25)/0.25,0,1));st(7,sgn(ld(4))*(0.5*ld(5)+0.5*ld(6)*ld(6)*(3-2*ld(6))*ld(5)));C((ld(3)/2+0.5)*W-0.5,(ld(7)/2+0.5)*H-0.5)") ;;
  ghosting)   # approximation: each frame is half itself plus fading copies of the frames before it
              G="tmix=frames=6:weights='1 2 4 8 16 32'" ;;
  clock)      # approximation: time of day at the top, starting from now and running with the video.
              # Font: VTFX_FONT if set, else the macOS system font, else whatever ffmpeg picks by default.
              FONT=$VTFX_FONT
              if [ -z "$FONT" ] && [ "$(uname)" = "Darwin" ]; then
                for f in /System/Library/Fonts/SFNS.ttf /System/Library/Fonts/HelveticaNeue.ttc /System/Library/Fonts/Helvetica.ttc; do
                  [ -f "$f" ] && { FONT=$f; break; }
                done
              fi
              G="drawtext=text='%{pts\:localtime\:$(date +%s)\:%H\\\\\:%M\\\\\:%S}':fontsize=h/8:fontcolor=white:borderw=3:bordercolor=black:x=(w-text_w)/2:y=h/20${FONT:+:fontfile='${FONT//:/\\:}'}" ;;
  *) echo "unknown preset '$1'"; echo "presets: $PRESETS"; exit 1 ;;
esac

ffmpeg -hide_banner -y -i "$IN" \
  -filter_complex "[0:v]format=gbrp,$G,format=${VTFX_PIXFMT:-yuv420p}[v]" \
  -map "[v]" -map "0:a?" -c:a copy $VTFX_EXTRA "$OUT"
