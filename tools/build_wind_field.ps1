# Outil hors-jeu : construit la carte du vent qui déplace les nuages (advection), à partir des analyses du modèle
# météo GFS de la NOAA pour le jour de l'imagerie nuageuse.
#
# Source : NOAA Global Forecast System, analyses 0,25° (archive publique AWS « NOAA GFS Open Data »,
#   https://noaa-gfs-bdp-pds.s3.amazonaws.com/gfs.AAAAMMJJ/HH/atmos/gfs.tHHz.pgrb2.0p25.anl). Grâce à l'index .idx de
#   chaque fichier, seuls les champs utiles sont téléchargés (requêtes HTTP partielles, ~1 Mo par champ).
# Champs : composantes est (UGRD) et nord (VGRD) du vent à 850, 700 et 500 hPa (~1,5 / 3 / 5,5 km, l'altitude de la
#   couche nuageuse), moyennées avec les poids $levelWeights, et moyennées sur les 4 analyses du jour (00, 06, 12,
#   18 UTC) : le champ est fixe, le jeu le considère comme le vent de toute la journée.
# Sortie : assets/textures/cloud_wind.exr, 720 x 360 (0,5°), canaux R = vent vers l'est, G = vent vers le nord, en m/s
#   (flottants 32 bits). Même convention que les autres cartes : colonne 0 = 180° O, ligne 0 = 90° N, texels centrés.
#
# Seconde sortie, le profil vertical du vent (dérive des champignons atomiques, nuke/nuke_wind.gd) :
#   assets/textures/wind_profile.exr, les niveaux $profileLevels (850 hPa à 0,1 hPa, soit ~1,5 à ~64 km d'altitude)
#   empilés verticalement, du plus bas au plus haut, chacun sur 360 x 180 texels (1°, mêmes conventions). Canaux :
#   R = vent vers l'est, G = vent vers le nord (m/s), B = altitude géopotentielle du niveau (HGT, km). Même moyenne
#   sur les 4 analyses du jour.
#
# Le décodage GRIB2 (grille latitude/longitude, compression « complex packing + spatial differencing », gabarit 5.3,
# celui de GFS) est fait par une routine C# compilée à la volée : aucun outil externe n'est nécessaire.
#
# Usage (PowerShell) : tools/build_wind_field.ps1 [-date 20230715]
param([string] $date = "20230715")
$root = Split-Path -Parent $PSScriptRoot
$outPath = Join-Path $root "assets/textures/cloud_wind.exr"
$profilePath = Join-Path $root "assets/textures/wind_profile.exr"
$levelWeights = [ordered]@{ "850 mb" = 0.3; "700 mb" = 0.4; "500 mb" = 0.3 }
$profileLevels = @("850 mb", "700 mb", "500 mb", "300 mb", "250 mb", "200 mb", "150 mb", "100 mb", "50 mb", "20 mb",
    "10 mb", "5 mb", "1 mb", "0.1 mb")
$cycles = @("00", "06", "12", "18")

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.Net;

public static class Grib2Wind {
    static int U32(byte[] b, int o) { return (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]; }
    static int U16(byte[] b, int o) { return (b[o] << 8) | b[o + 1]; }
    // Entiers signés GRIB2 : bit de poids fort = signe, puis valeur absolue.
    static int S16(byte[] b, int o) { int v = U16(b, o); return (v & 0x8000) != 0 ? -(v & 0x7fff) : v; }
    static int S32(byte[] b, int o) { int v = U32(b, o); return (v & unchecked((int)0x80000000)) != 0 ? -(v & 0x7fffffff) : v; }

    public static byte[] Download(string url, long first, long last) {
        ServicePointManager.SecurityProtocol = SecurityProtocolType.Tls12;
        for (int attempt = 0; ; attempt++) {
            try {
                var request = (HttpWebRequest)WebRequest.Create(url);
                request.AddRange(first, last);
                request.Timeout = 120000;
                using (var response = request.GetResponse())
                using (var stream = response.GetResponseStream())
                using (var memory = new MemoryStream()) {
                    stream.CopyTo(memory);
                    return memory.ToArray();
                }
            } catch (WebException) {
                if (attempt >= 4) throw;
            }
        }
    }

    class Bits {
        readonly byte[] data; long pos;
        public Bits(byte[] data, int offset) { this.data = data; pos = (long)offset * 8; }
        public int Read(int n) {
            int v = 0;
            for (int i = 0; i < n; i++) {
                int bit = (data[pos >> 3] >> (7 - (int)(pos & 7))) & 1;
                v = (v << 1) | bit;
                pos++;
            }
            return v;
        }
        public int ReadSigned(int n) { int sign = Read(1); int v = Read(n - 1); return sign == 1 ? -v : v; }
        public void Align() { pos = (pos + 7) & ~7L; }
    }

    // Décode un message GRIB2 (un seul champ) : grille 1440 x 721, du nord au sud, longitudes 0 -> 359,75.
    public static float[] Decode(byte[] msg, out int ni, out int nj) {
        if (msg[0] != 'G' || msg[1] != 'R' || msg[2] != 'I' || msg[3] != 'B' || msg[7] != 2)
            throw new Exception("message GRIB2 attendu");
        int o = 16;
        ni = nj = 0;
        int npts = 0, template5 = -1, nbits = 0, ng = 0, refWidth = 0, bitsWidth = 0, refLen = 0, incLen = 0;
        int lastLen = 0, bitsLen = 0, order = 0, nOctets = 0, missing = 0, split = 0;
        float reference = 0; int binaryScale = 0, decimalScale = 0;
        float[] values = null;
        while (o + 4 <= msg.Length) {
            if (msg[o] == '7' && msg[o + 1] == '7' && msg[o + 2] == '7' && msg[o + 3] == '7') break;
            int len = U32(msg, o);
            int sec = msg[o + 4];
            if (sec == 3) {
                if (U16(msg, o + 12) != 0) throw new Exception("grille latitude/longitude attendue");
                ni = U32(msg, o + 30);
                nj = U32(msg, o + 34);
                int la1 = S32(msg, o + 46), la2 = S32(msg, o + 55), scan = msg[o + 71];
                if (la1 < la2 || (scan & 0xe0) != 0) throw new Exception("balayage inattendu");
            } else if (sec == 5) {
                npts = U32(msg, o + 5);
                template5 = U16(msg, o + 9);
                if (template5 != 3 && template5 != 2) throw new Exception("compression non gérée : 5." + template5);
                reference = BitConverter.ToSingle(new byte[] { msg[o + 14], msg[o + 13], msg[o + 12], msg[o + 11] }, 0);
                binaryScale = S16(msg, o + 15);
                decimalScale = S16(msg, o + 17);
                nbits = msg[o + 19];
                split = msg[o + 21];
                missing = msg[o + 22];
                ng = U32(msg, o + 31);
                refWidth = msg[o + 35];
                bitsWidth = msg[o + 36];
                refLen = U32(msg, o + 37);
                incLen = msg[o + 41];
                lastLen = U32(msg, o + 42);
                bitsLen = msg[o + 46];
                if (template5 == 3) { order = msg[o + 47]; nOctets = msg[o + 48]; }
                if (missing != 0 || split != 1) throw new Exception("valeurs manquantes non gérées");
            } else if (sec == 6) {
                if (msg[o + 5] != 255) throw new Exception("bitmap non géré");
            } else if (sec == 7) {
                var bits = new Bits(msg, o + 5);
                int ival1 = 0, ival2 = 0, minsd = 0;
                if (order > 0) {
                    ival1 = bits.ReadSigned(nOctets * 8);
                    if (order == 2) ival2 = bits.ReadSigned(nOctets * 8);
                    minsd = bits.ReadSigned(nOctets * 8);
                }
                var gref = new int[ng]; var gwidth = new int[ng]; var glen = new int[ng];
                for (int g = 0; g < ng; g++) gref[g] = bits.Read(nbits);
                bits.Align();
                for (int g = 0; g < ng; g++) gwidth[g] = bits.Read(bitsWidth) + refWidth;
                bits.Align();
                for (int g = 0; g < ng; g++) glen[g] = bits.Read(bitsLen) * incLen + refLen;
                glen[ng - 1] = lastLen;
                bits.Align();
                var ifld = new long[npts];
                int n = 0;
                for (int g = 0; g < ng; g++)
                    for (int k = 0; k < glen[g]; k++)
                        ifld[n++] = gref[g] + (gwidth[g] > 0 ? bits.Read(gwidth[g]) : 0);
                if (n != npts) throw new Exception("nombre de points incohérent");
                if (order == 1) {
                    ifld[0] = ival1;
                    for (int i = 1; i < npts; i++) ifld[i] += minsd + ifld[i - 1];
                } else if (order == 2) {
                    ifld[0] = ival1; ifld[1] = ival2;
                    for (int i = 2; i < npts; i++) ifld[i] += minsd + 2 * ifld[i - 1] - ifld[i - 2];
                }
                double bscale = Math.Pow(2.0, binaryScale), dscale = Math.Pow(10.0, -decimalScale);
                values = new float[npts];
                for (int i = 0; i < npts; i++) values[i] = (float)((reference + ifld[i] * bscale) * dscale);
            }
            o += len;
        }
        if (values == null || values.Length != ni * nj) throw new Exception("champ GRIB2 incomplet");
        return values;
    }

    // Rééchantillonne une grille globale (ni x nj points, nord -> sud, longitude 0 en colonne 0) en texture de
    // w x h texels centrés, colonne 0 = 180° O, par interpolation bilinéaire.
    public static float[] Resample(float[] grid, int ni, int nj, int w, int h) {
        var res = new float[w * h];
        double dlon = 360.0 / ni, dlat = 180.0 / (nj - 1);
        for (int y = 0; y < h; y++) {
            double lat = 90.0 - (y + 0.5) * 180.0 / h;
            double fy = (90.0 - lat) / dlat;
            int y0 = Math.Min((int)fy, nj - 2); double ty = fy - y0;
            for (int x = 0; x < w; x++) {
                double lon = -180.0 + (x + 0.5) * 360.0 / w;
                double fx = ((lon % 360.0) + 360.0) % 360.0 / dlon;
                int x0 = (int)fx; double tx = fx - x0; int x1 = (x0 + 1) % ni; x0 %= ni;
                double a = grid[y0 * ni + x0] * (1 - tx) + grid[y0 * ni + x1] * tx;
                double b = grid[(y0 + 1) * ni + x0] * (1 - tx) + grid[(y0 + 1) * ni + x1] * tx;
                res[y * w + x] = (float)(a * (1 - ty) + b * ty);
            }
        }
        return res;
    }

    static void Str(BinaryWriter wr, string s) { foreach (char c in s) wr.Write((byte)c); wr.Write((byte)0); }

    // Écrit un OpenEXR minimal : lignes non compressées, canaux R et G en flottants 32 bits.
    public static void WriteExr(string path, float[] r, float[] g, int w, int h) {
        WriteExr(path, new[] { "G", "R" }, new[] { g, r }, w, h);
    }

    // Même chose avec des canaux quelconques, nommés en ordre alphabétique (exigé par le format) : « B », « G », « R ».
    public static void WriteExr(string path, string[] names, float[][] channels, int w, int h) {
        using (var wr = new BinaryWriter(File.Create(path))) {
            wr.Write(20000630); wr.Write(2);
            Str(wr, "channels"); Str(wr, "chlist"); wr.Write(names.Length * (2 + 16) + 1);
            foreach (var name in names) { Str(wr, name); wr.Write(2); wr.Write(0); wr.Write(1); wr.Write(1); }
            wr.Write((byte)0);
            Str(wr, "compression"); Str(wr, "compression"); wr.Write(1); wr.Write((byte)0);
            Str(wr, "dataWindow"); Str(wr, "box2i"); wr.Write(16); wr.Write(0); wr.Write(0); wr.Write(w - 1); wr.Write(h - 1);
            Str(wr, "displayWindow"); Str(wr, "box2i"); wr.Write(16); wr.Write(0); wr.Write(0); wr.Write(w - 1); wr.Write(h - 1);
            Str(wr, "lineOrder"); Str(wr, "lineOrder"); wr.Write(1); wr.Write((byte)0);
            Str(wr, "pixelAspectRatio"); Str(wr, "float"); wr.Write(4); wr.Write(1.0f);
            Str(wr, "screenWindowCenter"); Str(wr, "v2f"); wr.Write(8); wr.Write(0.0f); wr.Write(0.0f);
            Str(wr, "screenWindowWidth"); Str(wr, "float"); wr.Write(4); wr.Write(1.0f);
            wr.Write((byte)0);
            long tableStart = wr.BaseStream.Position;
            int lineBytes = 8 + w * 4 * names.Length;
            for (int y = 0; y < h; y++) wr.Write(tableStart + 8L * h + (long)y * lineBytes);
            for (int y = 0; y < h; y++) {
                wr.Write(y); wr.Write(w * 4 * names.Length);
                foreach (var c in channels)
                    for (int x = 0; x < w; x++) wr.Write(c[y * w + x]);
            }
        }
    }

    // sum[offset + k] += weight * values[k] (boucle trop lente en PowerShell pour les 14 niveaux du profil).
    public static void Accumulate(double[] sum, float[] values, double weight, int offset) {
        for (int k = 0; k < values.Length; k++) sum[offset + k] += weight * values[k];
    }

    public static float[] Scale(double[] sum, double divisor) {
        var res = new float[sum.Length];
        for (int k = 0; k < sum.Length; k++) res[k] = (float)(sum[k] / divisor);
        return res;
    }
}
"@

$width = 720
$height = 360
$sumU = New-Object 'double[]' ($width * $height)
$sumV = New-Object 'double[]' ($width * $height)
$weightTotal = 0.0
# Profil : niveaux empilés (le plus bas en haut de l'image), 1°.
$profileWidth = 360
$profileHeight = 180
$profileSize = $profileWidth * $profileHeight
$profileU = New-Object 'double[]' ($profileSize * $profileLevels.Count)
$profileV = New-Object 'double[]' ($profileSize * $profileLevels.Count)
$profileZ = New-Object 'double[]' ($profileSize * $profileLevels.Count)
$levels = @($levelWeights.Keys) + @($profileLevels | Where-Object { -not $levelWeights.Contains($_) })
foreach ($cycle in $cycles) {
    $url = "https://noaa-gfs-bdp-pds.s3.amazonaws.com/gfs.$date/$cycle/atmos/gfs.t${cycle}z.pgrb2.0p25.anl"
    Write-Host "GFS $date ${cycle}Z"
    [string[]] $index = (New-Object System.Net.WebClient).DownloadString("$url.idx") -split "`n" | Where-Object { $_ }
    foreach ($level in $levels) {
        $profileIndex = [array]::IndexOf($profileLevels, $level)
        $components = if ($profileIndex -ge 0) { @("UGRD", "VGRD", "HGT") } else { @("UGRD", "VGRD") }
        $fields = @{}
        $profileFields = @{}
        foreach ($component in $components) {
            $i = [array]::FindIndex($index, [Predicate[string]] { param($l) $l -like "*:${component}:${level}:anl*" })
            if ($i -lt 0) { throw "$component $level absent de $url" }
            $first = [long]($index[$i] -split ":")[1]
            $last = [long]($index[$i + 1] -split ":")[1] - 1
            $ni = 0; $nj = 0
            $grid = [Grib2Wind]::Decode([Grib2Wind]::Download($url, $first, $last), [ref]$ni, [ref]$nj)
            if ($levelWeights.Contains($level) -and $component -ne "HGT") {
                $fields[$component] = [Grib2Wind]::Resample($grid, $ni, $nj, $width, $height)
            }
            if ($profileIndex -ge 0) {
                $profileFields[$component] = [Grib2Wind]::Resample($grid, $ni, $nj, $profileWidth, $profileHeight)
            }
        }
        if ($levelWeights.Contains($level)) {
            $weight = $levelWeights[$level]
            [Grib2Wind]::Accumulate($sumU, $fields["UGRD"], $weight, 0)
            [Grib2Wind]::Accumulate($sumV, $fields["VGRD"], $weight, 0)
            $weightTotal += $weight
        }
        if ($profileIndex -ge 0) {
            $offset = $profileIndex * $profileSize
            [Grib2Wind]::Accumulate($profileU, $profileFields["UGRD"], 1.0, $offset)
            [Grib2Wind]::Accumulate($profileV, $profileFields["VGRD"], 1.0, $offset)
            [Grib2Wind]::Accumulate($profileZ, $profileFields["HGT"], 0.001, $offset)
        }
        $u = if ($profileIndex -ge 0) { $profileFields["UGRD"] } else { $fields["UGRD"] }
        $max = ($u | Measure-Object -Maximum -Minimum)
        Write-Host ("  {0} : vent est {1:F1} .. {2:F1} m/s" -f $level, $max.Minimum, $max.Maximum)
    }
}
$outU = [Grib2Wind]::Scale($sumU, $weightTotal)
$outV = [Grib2Wind]::Scale($sumV, $weightTotal)
[Grib2Wind]::WriteExr($outPath, $outU, $outV, $width, $height)
Write-Host "Écrit : $outPath"
$cycleCount = [double] $cycles.Count
[Grib2Wind]::WriteExr($profilePath, [string[]] @("B", "G", "R"), [float[][]] @([Grib2Wind]::Scale($profileZ, $cycleCount),
    [Grib2Wind]::Scale($profileV, $cycleCount), [Grib2Wind]::Scale($profileU, $cycleCount)),
    $profileWidth, $profileHeight * $profileLevels.Count)
Write-Host "Écrit : $profilePath"
