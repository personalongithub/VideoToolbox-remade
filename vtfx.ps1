# vtfx.ps1 - recreate the Video Toolbox "Video FX" presets with ffmpeg (Windows PowerShell version).
#
#   .\vtfx.ps1 <preset> input.mov output.mp4
#   .\vtfx.ps1 list
#   .\vtfx.ps1 sketch input.mov output.mp4 -Ffmpeg "C:\temp\ffmpeg.exe"
#
# Keep the .cube files next to this script. If Windows refuses to run it, use:
#   powershell -ExecutionPolicy Bypass -File .\vtfx.ps1 <preset> input output
param(
  [string]$Preset = 'list',
  [string]$In,
  [string]$Out,
  [string]$Ffmpeg = 'ffmpeg'
)

$Presets = 'blackwhite sepia red green blue monored monogreen monoblue classic beauty 70s avenue sunset lens erosion dilation pixellate dots blur zoomblur sketch pinch stretch ghosting clock'
if ($Preset -eq 'list' -or -not $In -or -not $Out) {
  Write-Host 'usage: .\vtfx.ps1 <preset> input output [-Ffmpeg path\to\ffmpeg.exe]'
  Write-Host "presets: $Presets"
  exit 0
}
$Preset = $Preset.ToLower()

# Full paths, because the script changes folder so ffmpeg can find the .cube files by plain name
if (-not (Test-Path -LiteralPath $In)) { Write-Host "input not found: $In"; exit 1 }
$In  = (Resolve-Path -LiteralPath $In).ProviderPath
$Out = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Out)
if ($Ffmpeg -match '[\\/]' -and (Test-Path -LiteralPath $Ffmpeg)) { $Ffmpeg = (Resolve-Path -LiteralPath $Ffmpeg).ProviderPath }

# Rgb3 EXPR [OPTS]: geq filter that runs EXPR on each colour plane; write the plane as C(x,y)
function Rgb3([string]$e, [string]$opts) {
  $f = "geq=r='" + $e.Replace('C(', 'r(') + "':g='" + $e.Replace('C(', 'g(') + "':b='" + $e.Replace('C(', 'b(') + "'"
  if ($opts) { $f += ":$opts" }
  return $f
}
# Warp EXPR: like Rgb3, for presets that sample between pixels. ffmpeg's geq cannot read the
# last row/column when interpolating, so pad by one smeared pixel first and crop it off after.
function Warp([string]$e) {
  $e = $e.Replace('W', '(W-1)').Replace('H', '(H-1)')
  return 'pad=iw+1:ih+1,fillborders=right=1:bottom=1:mode=smear,' + (Rgb3 $e) + ',crop=iw-1:ih-1:0:0'
}

$Grey = 'colorchannelmixer=.2125:.7154:.0721:0:.2125:.7154:.0721:0:.2125:.7154:.0721:0'
$Lo = 'min(2*val,255)'; $Hi = 'max(2*val-255,0)'   # the two halves of GPUImage's monochrome tint
$BlurMask = 'clip((hypot((X+0.5)/W-0.5,((Y+0.5)/H-0.5)*W/H)-0.4)/0.1,0,1)'

switch ($Preset) {
  'blackwhite' { $G = $Grey }
  'sepia'      { $G = 'colorchannelmixer=.3588:.7044:.1368:0:.2990:.5870:.1140:0:.2392:.4696:.0912:0' }
  'red'        { $G = "lutrgb=r='$Lo'" }
  'green'      { $G = "lutrgb=g='$Lo'" }
  'blue'       { $G = "lutrgb=b='$Lo'" }
  'monored'    { $G = "$Grey,lutrgb=r='$Lo':g='$Hi':b='$Hi'" }
  'monogreen'  { $G = "$Grey,lutrgb=g='$Lo':r='$Hi':b='$Hi'" }
  'monoblue'   { $G = "$Grey,lutrgb=b='$Lo':r='$Hi':g='$Hi'" }
  'classic'    { $G = 'lut3d=GPUImage_Amatorka.cube' }
  'beauty'     { $G = 'lut3d=GPUImage_MissEtikate.cube' }
  '70s'        { $G = 'lut3d=VideoToolbox_70s.cube' }
  'avenue'     { # centre grade and edge grade, mixed by squared distance from the centre
                 $G = "split[a][b];[a]lut3d=VideoToolbox_Avenue_center.cube[a];[b]lut3d=VideoToolbox_Avenue_edge.cube[b];[a][b]blend=all_expr='A+(B-A)*pow(max(min(1,pow(2*(X+0.5)/W-1,2)+pow(2*(Y+0.5)/H-1,2))-0.42,0)/0.58,1.25)'" }
  'sunset'     { $G = "curves=b='0/0 0.5/0 1/0.75'" }
  'lens'       { $G = Rgb3 'st(0,clip((hypot((X+0.5)/W-0.5,(Y+0.5)/H-0.5)-0.3)/0.45,0,1));C(X,Y)*(1-ld(0)*ld(0)*(3-2*ld(0)))' 'interpolation=nearest' }
  'erosion'    { $G = 'erosion,erosion,erosion,erosion' }
  'dilation'   { $G = 'dilation,dilation,dilation,dilation' }
  'pixellate'  { $G = Rgb3 'st(0,W/20);C((floor((X+0.5)/ld(0))+0.5)*ld(0),(floor((Y+0.5)/ld(0))+0.5)*ld(0))' 'interpolation=nearest' }
  'dots'       { $G = Rgb3 'st(0,W/92.6);st(1,(floor((X+0.5)/ld(0))+0.5)*ld(0));st(2,(floor((Y+0.5)/ld(0))+0.5)*ld(0));if(lte(hypot(X+0.5-ld(1),Y+0.5-ld(2)),0.45*ld(0)),C(ld(1),ld(2)),0)' 'interpolation=nearest' }
  'blur'       { $G = "split[a][b];[b]gblur=sigma=5[b];[a][b]blend=all_expr='A+(B-A)*pow($BlurMask,2)*(3-2*$BlurMask)'" }
  'zoomblur'   { $G = Warp 'st(0,(W/2-X-0.5)*0.025);st(1,(H/2-Y-0.5)*0.025);0.18*C(X,Y)+0.15*(C(X+ld(0),Y+ld(1))+C(X-ld(0),Y-ld(1)))+0.12*(C(X+2*ld(0),Y+2*ld(1))+C(X-2*ld(0),Y-2*ld(1)))+0.09*(C(X+3*ld(0),Y+3*ld(1))+C(X-3*ld(0),Y-3*ld(1)))+0.05*(C(X+4*ld(0),Y+4*ld(1))+C(X-4*ld(0),Y-4*ld(1)))' }
  'sketch'     { $G = "$Grey,sobel=scale=0.5,negate" }
  'pinch'      { $G = Warp 'st(0,(X+0.5)/W-0.5);st(1,(Y+0.5)/H-0.5);st(2,2-2*hypot(ld(0),ld(1)*H/W));C((ld(0)*ld(2)+0.5)*W-0.5,(ld(1)*ld(2)+0.5)*H-0.5)' }
  'stretch'    { $G = Warp 'st(0,2*(X+0.5)/W-1);st(1,abs(ld(0)));st(2,clip((ld(1)-0.25)/0.25,0,1));st(3,sgn(ld(0))*(0.5*ld(1)+0.5*ld(2)*ld(2)*(3-2*ld(2))*ld(1)));st(4,2*(Y+0.5)/H-1);st(5,abs(ld(4)));st(6,clip((ld(5)-0.25)/0.25,0,1));st(7,sgn(ld(4))*(0.5*ld(5)+0.5*ld(6)*ld(6)*(3-2*ld(6))*ld(5)));C((ld(3)/2+0.5)*W-0.5,(ld(7)/2+0.5)*H-0.5)' }
  'ghosting'   { # approximation: each frame is half itself plus fading copies of the frames before it
                 $G = "tmix=frames=6:weights='1 2 4 8 16 32'" }
  'clock'      { # approximation: time of day at the top, starting from now and running with the video
                 $epoch = [int64]([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalSeconds
                 # Font: VTFX_FONT if set (a normal path is fine), else the system font, else ffmpeg's default
                 $font = $env:VTFX_FONT
                 if (-not $font) {
                   $onWindows = ($PSVersionTable.PSVersion.Major -lt 6) -or $IsWindows
                   if ($onWindows) { $candidates = @("$env:WINDIR\Fonts\segoeui.ttf", "$env:WINDIR\Fonts\arial.ttf") }
                   elseif ($IsMacOS) { $candidates = @('/System/Library/Fonts/SFNS.ttf', '/System/Library/Fonts/HelveticaNeue.ttc') }
                   else { $candidates = @() }
                   foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { $font = $c; break } }
                 }
                 $G = "drawtext=text='%{pts\:localtime\:$epoch\:%H\\\:%M\\\:%S}':fontsize=h/8:fontcolor=white:borderw=3:bordercolor=black:x=(w-text_w)/2:y=h/20"
                 # ffmpeg wants forward slashes and an escaped drive colon inside a filter
                 if ($font) { $G += ":fontfile='" + $font.Replace('\:', ':').Replace('\', '/').Replace(':', '\:') + "'" } }
  default      { Write-Host "unknown preset '$Preset'"; Write-Host "presets: $Presets"; exit 1 }
}

$pix = if ($env:VTFX_PIXFMT) { $env:VTFX_PIXFMT } else { 'yuv420p' }
$extra = @(); if ($env:VTFX_EXTRA) { $extra = $env:VTFX_EXTRA -split ' ' }

Push-Location -LiteralPath $PSScriptRoot
try {
  & $Ffmpeg -hide_banner -y -i $In -filter_complex "[0:v]format=gbrp,$G,format=$pix[v]" -map '[v]' -map '0:a?' -c:a copy @extra $Out
  $code = $LASTEXITCODE
} finally { Pop-Location }
exit $code
