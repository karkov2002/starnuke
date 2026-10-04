# Outil hors-jeu : construit la carte de couverture nuageuse (« alpha ») à partir d'une vraie journée d'imagerie
# satellite, par différence avec la Terre sans nuages (Blue Marble).
#
# Entrées :
#   -viirs <dossier> : tuiles VIIRS NOAA-20 Corrected Reflectance True Color (NASA GIBS) d'une journée, même
#                      découpage que assets/earth_tiles (rLL_cCC.jpg, 5°, 1200 x 1200 px). Téléchargement :
#                      WMS https://gibs.earthdata.nasa.gov/wms/epsg4326/best/wms.cgi, couche
#                      VIIRS_NOAA20_CorrectedReflectance_TrueColor, TIME=2023-07-15, BBOX de chaque tuile.
#   assets/earth_tiles/ (Blue Marble, sol sans nuages) et assets/textures/earth_clouds_8k.jpg (carte nuageuse
#   Blue Marble, utilisée là où la journée VIIRS n'a pas de données : nuit polaire, trous entre passages).
# Sorties :
#   assets/earth_cloud_tiles/rLL_cCC.jpg (niveaux de gris, 500 m/px) et assets/textures/earth_clouds_16k.jpg.
#
# Couverture = (luminance VIIRS − luminance Blue Marble) / (1 − luminance Blue Marble), seuillée, et atténuée
# pour les pixels colorés (les nuages sont blancs ou gris ; sable, végétation, eau turbide sont colorés).
#
# Usage (PowerShell) : tools/build_cloud_tiles.ps1 -viirs <dossier des tuiles VIIRS>
param([Parameter(Mandatory = $true)] $viirs)
$root = Split-Path -Parent $PSScriptRoot
$dayDir = Join-Path $root "assets/earth_tiles"
$outDir = Join-Path $root "assets/earth_cloud_tiles"
$globalPath = Join-Path $root "assets/textures/earth_clouds_16k.jpg"
$fallbackPath = Join-Path $root "assets/textures/earth_clouds_8k.jpg"
New-Item -ItemType Directory -Force $outDir | Out-Null
Add-Type -AssemblyName System.Drawing

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;

public static class CloudMatte {
    static byte[] Read(Bitmap bmp, out int stride) {
        var data = bmp.LockBits(new Rectangle(0, 0, bmp.Width, bmp.Height), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
        stride = data.Stride;
        var bytes = new byte[stride * bmp.Height];
        Marshal.Copy(data.Scan0, bytes, 0, bytes.Length);
        bmp.UnlockBits(data);
        return bytes;
    }

    static float Smooth(float a, float b, float x) {
        float t = Math.Min(Math.Max((x - a) / (b - a), 0f), 1f);
        return t * t * (3f - 2f * t);
    }

    // Moyenne et écart-type locaux (fenêtre carrée de rayon r) via images intégrales.
    static void LocalStats(float[] lum, int w, int h, int r, float[] std) {
        var s1 = new double[(w + 1) * (h + 1)];
        var s2 = new double[(w + 1) * (h + 1)];
        for (int y = 0; y < h; y++) {
            double row1 = 0, row2 = 0;
            for (int x = 0; x < w; x++) {
                double l = lum[y * w + x];
                row1 += l; row2 += l * l;
                s1[(y + 1) * (w + 1) + x + 1] = s1[y * (w + 1) + x + 1] + row1;
                s2[(y + 1) * (w + 1) + x + 1] = s2[y * (w + 1) + x + 1] + row2;
            }
        }
        for (int y = 0; y < h; y++) {
            int y0 = Math.Max(y - r, 0), y1 = Math.Min(y + r + 1, h);
            for (int x = 0; x < w; x++) {
                int x0 = Math.Max(x - r, 0), x1 = Math.Min(x + r + 1, w);
                double n = (x1 - x0) * (y1 - y0);
                double a = s1[y1 * (w + 1) + x1] - s1[y0 * (w + 1) + x1] - s1[y1 * (w + 1) + x0] + s1[y0 * (w + 1) + x0];
                double b = s2[y1 * (w + 1) + x1] - s2[y0 * (w + 1) + x1] - s2[y1 * (w + 1) + x0] + s2[y0 * (w + 1) + x0];
                double mean = a / n;
                std[y * w + x] = (float)Math.Sqrt(Math.Max(b / n - mean * mean, 0.0));
            }
        }
    }

    // Les trois images doivent avoir la même taille (24 bpp). Retourne une image en niveaux de gris (24 bpp).
    public static Bitmap Matte(Bitmap viirs, Bitmap day, Bitmap fallback) {
        int w = viirs.Width, h = viirs.Height, sv, sd, sf;
        byte[] v = Read(viirs, out sv);
        byte[] d = Read(day, out sd);
        byte[] f = Read(fallback, out sf);
        var lum = new float[w * h];
        for (int y = 0; y < h; y++)
            for (int x = 0; x < w; x++) {
                int iv = y * sv + x * 3;
                lum[y * w + x] = (0.114f * v[iv] + 0.587f * v[iv + 1] + 0.299f * v[iv + 2]) / 255f;
            }
        var std = new float[w * h];
        LocalStats(lum, w, h, 6, std);

        var output = new Bitmap(w, h, PixelFormat.Format24bppRgb);
        var outData = output.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format24bppRgb);
        var o = new byte[outData.Stride * h];
        for (int y = 0; y < h; y++) {
            for (int x = 0; x < w; x++) {
                int iv = y * sv + x * 3, id = y * sd + x * 3, iff = y * sf + x * 3, io = y * outData.Stride + x * 3;
                // Ordre BGR en mémoire.
                float vb = v[iv] / 255f, vg = v[iv + 1] / 255f, vr = v[iv + 2] / 255f;
                float db = d[id] / 255f, dg = d[id + 1] / 255f, dr = d[id + 2] / 255f;
                float vmax = Math.Max(vr, Math.Max(vg, vb)), vmin = Math.Min(vr, Math.Min(vg, vb));
                float alpha;
                if (vmax < 0.04f) {
                    // Pas de donnée VIIRS (nuit polaire, trou) : carte nuageuse Blue Marble.
                    alpha = Smooth(0.12f, 0.7f, f[iff + 2] / 255f);
                } else {
                    float lv = lum[y * w + x];
                    float lb = 0.299f * dr + 0.587f * dg + 0.114f * db;
                    float diff = (lv - lb) / Math.Max(1f - lb, 0.15f);
                    float saturation = (vmax - vmin) / Math.Max(vmax, 1e-3f);
                    float neutral = 1f - Smooth(0.22f, 0.5f, saturation);
                    alpha = Smooth(0.12f, 0.9f, diff) * neutral;
                    // Reflet du soleil sur l'océan : voile gris d'intensité moyenne mais très lisse, alors qu'un
                    // nuage est texturé. Supprimé sur l'eau quand l'écart-type local est faible.
                    bool ocean = lb < 0.15f && db > dr;
                    if (ocean && diff < 0.6f) {
                        alpha *= Smooth(0.012f, 0.045f, std[y * w + x]);
                    }
                }
                byte a = (byte)Math.Round(Math.Min(Math.Max(alpha, 0f), 1f) * 255f);
                o[io] = a; o[io + 1] = a; o[io + 2] = a;
            }
        }
        Marshal.Copy(o, 0, outData.Scan0, o.Length);
        output.UnlockBits(outData);
        return output;
    }
}
"@

$enc = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
$ep = New-Object System.Drawing.Imaging.EncoderParameters(1)
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]88)
$fallback = [System.Drawing.Image]::FromFile($fallbackPath)
# Assemblage sur une grille entière (228 px par tuile) puis réduction à 16384 x 8192 : évite les liserés aux
# bords des tuiles (TileFlipXY empêche le filtrage de mélanger le bord avec du noir).
$cell = 228
$global = New-Object System.Drawing.Bitmap((72 * $cell), (36 * $cell), [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$wrap = New-Object System.Drawing.Imaging.ImageAttributes
$wrap.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
$gg = [System.Drawing.Graphics]::FromImage($global)
$gg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
$sw = [Diagnostics.Stopwatch]::StartNew()
$fw = $fallback.Width / 72.0; $fh = $fallback.Height / 36.0

for ($r = 0; $r -lt 36; $r++) {
  for ($c = 0; $c -lt 72; $c++) {
    $name = "r{0:D2}_c{1:D2}.jpg" -f $r, $c
    $viirsTile = New-Object System.Drawing.Bitmap((Join-Path $viirs $name))
    $dayTile = New-Object System.Drawing.Bitmap((Join-Path $dayDir $name))
    $fbTile = New-Object System.Drawing.Bitmap(1200, 1200, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $g = [System.Drawing.Graphics]::FromImage($fbTile)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBilinear
    $g.DrawImage($fallback, (New-Object System.Drawing.RectangleF(0, 0, 1200, 1200)), (New-Object System.Drawing.RectangleF(($c * $fw), ($r * $fh), $fw, $fh)), [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    # Copies 24 bpp (les JPEG peuvent être chargés dans un autre format).
    $v24 = $viirsTile.Clone((New-Object System.Drawing.Rectangle(0, 0, 1200, 1200)), [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $d24 = $dayTile.Clone((New-Object System.Drawing.Rectangle(0, 0, 1200, 1200)), [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $alpha = [CloudMatte]::Matte($v24, $d24, $fbTile)
    $alpha.Save((Join-Path $outDir $name), $enc, $ep)
    $gg.DrawImage($alpha, (New-Object System.Drawing.Rectangle(($c * $cell), ($r * $cell), $cell, $cell)), 0, 0, 1200, 1200, [System.Drawing.GraphicsUnit]::Pixel, $wrap)
    foreach ($b in @($viirsTile, $dayTile, $fbTile, $v24, $d24, $alpha)) { $b.Dispose() }
  }
  Write-Output ("ligne {0}/36 ({1:N0} s)" -f ($r + 1), $sw.Elapsed.TotalSeconds)
}
$gg.Dispose()
$fallback.Dispose()
$ep.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]92)
$final = New-Object System.Drawing.Bitmap(16384, 8192, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$gf = [System.Drawing.Graphics]::FromImage($final)
$gf.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gf.DrawImage($global, (New-Object System.Drawing.Rectangle(0, 0, 16384, 8192)), 0, 0, $global.Width, $global.Height, [System.Drawing.GraphicsUnit]::Pixel, $wrap)
$gf.Dispose()
$global.Dispose()
$final.Save($globalPath, $enc, $ep)
$final.Dispose()
Write-Output "done"
