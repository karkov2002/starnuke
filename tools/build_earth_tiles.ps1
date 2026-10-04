# Outil hors-jeu : découpe 8 tuiles NASA 500 m (21600 x 21600 px, nommées A1..D2 : A..D = 90° de longitude
# depuis 180° O, 1 = hémisphère nord, 2 = sud) en tuiles de 5° (1200 x 1200 px, rLL_cCC.jpg, chargées à la
# demande par scripts/earth_detail_tiles.gd) et produit la texture globale 16384 x 8192 à partir de la même source.
# Fait en .NET car Godot refuse les images de plus de 268 Mpx (les sources en font 466).
#
#   -kind day   : Blue Marble Next Generation, world.200407.3x21600x21600.{A1..D2}.jpg (Visible Earth 74092)
#                 -> assets/earth_tiles/, assets/textures/earth_bluemarble_16k.jpg
#   -kind night : Black Marble 2016, BlackMarble_2016_{A1..D2}.jpg (Visible Earth 144898)
#                 -> assets/earth_night_tiles/, assets/textures/earth_night_16k.jpg
#
# Usage (PowerShell) : tools/build_earth_tiles.ps1 -src <dossier contenant A1.jpg ... D2.jpg> [-kind day|night]
param([Parameter(Mandatory = $true)] $src, [ValidateSet("day", "night")] $kind = "day")
$root = Split-Path -Parent $PSScriptRoot
if ($kind -eq "night") {
  $tileDir = Join-Path $root "assets/earth_night_tiles"
  $globalPath = Join-Path $root "assets/textures/earth_night_16k.jpg"
} else {
  $tileDir = Join-Path $root "assets/earth_tiles"
  $globalPath = Join-Path $root "assets/textures/earth_bluemarble_16k.jpg"
}
New-Item -ItemType Directory -Force $tileDir | Out-Null
Add-Type -AssemblyName System.Drawing
$names = @('A1','B1','C1','D1','A2','B2','C2','D2')
$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]90)
$global = New-Object System.Drawing.Bitmap(16384, 8192, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gg = [System.Drawing.Graphics]::FromImage($global)
$gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
for ($i = 0; $i -lt 8; $i++) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  $qx = [int]($i % 4); $qy = [int][math]::Floor($i / 4)
  $img = [System.Drawing.Image]::FromFile("$src\$($names[$i]).jpg")
  for ($r = 0; $r -lt 18; $r++) {
    for ($c = 0; $c -lt 18; $c++) {
      $tile = New-Object System.Drawing.Bitmap(1200, 1200, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
      $g = [System.Drawing.Graphics]::FromImage($tile)
      $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
      $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
      $g.DrawImage($img, (New-Object System.Drawing.Rectangle(0, 0, 1200, 1200)), (New-Object System.Drawing.Rectangle(($c * 1200), ($r * 1200), 1200, 1200)), [System.Drawing.GraphicsUnit]::Pixel)
      $g.Dispose()
      $row = [int]($qy * 18 + $r); $col = [int]($qx * 18 + $c)
      $tile.Save(("{0}\r{1:D2}_c{2:D2}.jpg" -f $tileDir, $row, $col), $enc, $ep)
      $tile.Dispose()
    }
  }
  $gg.DrawImage($img, (New-Object System.Drawing.Rectangle(($qx * 4096), ($qy * 4096), 4096, 4096)), (New-Object System.Drawing.Rectangle(0, 0, 21600, 21600)), [System.Drawing.GraphicsUnit]::Pixel)
  $img.Dispose()
  [GC]::Collect()
  Write-Output "$($names[$i]) : $($sw.Elapsed.TotalSeconds) s"
}
$gg.Dispose()
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]92)
$global.Save($globalPath, $enc, $ep)
$global.Dispose()
Write-Output "done"
