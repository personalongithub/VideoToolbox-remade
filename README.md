# VideoToolbox-remade

ffmpeg recreations of the 25 "Video FX" presets from the old Video Toolbox iOS app, which no longer
runs on current macOS. Each preset is one ffmpeg filter chain, wrapped in a small script.

## Usage

macOS / Linux (needs `ffmpeg`, e.g. `brew install ffmpeg`):

```bash
chmod +x vtfx.sh
./vtfx.sh sketch input.mov output.mp4
./vtfx.sh list
```

Windows PowerShell:

```powershell
.\vtfx.ps1 sketch "C:\temp\input.mp4" "C:\temp\output.mp4" -Ffmpeg "C:\temp\ffmpeg.exe"
.\vtfx.ps1 list
```

If Windows blocks the script: `powershell -ExecutionPolicy Bypass -File .\vtfx.ps1 <preset> input output`.

Keep the `.cube` files in the same folder as the scripts. Audio is copied through unchanged.

## Presets

| Group | Presets |
|---|---|
| Colour | `blackwhite` `sepia` `red` `green` `blue` `monored` `monogreen` `monoblue` `classic` `beauty` `70s` `avenue` `sunset` `lens` |
| Shape and blur | `erosion` `dilation` `pixellate` `dots` `blur` `zoomblur` `sketch` `pinch` `stretch` |
| Other | `ghosting` `clock` |

## How close they are

Each recipe was run on the app's sample image and compared with the app's own preview thumbnail.

- Pixel-identical: `red` `green` `blue` `erosion` `dilation`
- Within 3 levels out of 255: `blackwhite` `sepia` `monored` `monogreen` `monoblue` `classic` `beauty`
  `70s` `avenue` `sunset` `lens` `zoomblur` `pinch` `stretch`
- Visually the same, small edge differences: `sketch` `blur` `pixellate`
- Approximations: `dots` (pattern differs pixel by pixel), `ghosting` (frame blending, not checked
  against the app), `clock` (time of day from when you run it; font differs)

## Notes

- `70s` and `avenue` need `VideoToolbox_70s.cube`, `VideoToolbox_Avenue_center.cube` and
  `VideoToolbox_Avenue_edge.cube`. Those are derived from the app's own image files and are not
  included in this repository.
- `avenue` `lens` `pixellate` `dots` `blur` `zoomblur` `pinch` `stretch` are computed per pixel and
  render slowly on long or high-resolution videos.
- `erosion`, `dilation` and `blur` are sized in pixels, as in the app, so they look subtler on HD
  footage than on a small preview.
- The clock uses the system font by default. Set `VTFX_FONT` to a font file path to change it.
- Tested with ffmpeg 6.1 on Linux (bash and PowerShell 7). Not yet tested on macOS or Windows.

## Credits

Most presets are filters from [GPUImage](https://github.com/BradLarson/GPUImage) by Brad Larson and
contributors. `GPUImage_Amatorka.cube` and `GPUImage_MissEtikate.cube` are converted from GPUImage's
lookup images. GPUImage's license is in `GPUImage-License.txt`.
