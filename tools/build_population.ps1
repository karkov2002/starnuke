# Outil hors-jeu : convertit la grille mondiale de population GHS-POP (JRC, Commission européenne, R2023A, époque
# 2030, 30 secondes d'arc, WGS84) en assets/population_2030.bin, lu par scripts/population_grid.gd.
#
# Entrée : GHS_POP_E2030_GLOBE_R2023A_4326_30ss_V1_0.tif (BigTIFF, flottants 64 bits, LZW, carreaux de 256 x 256 ;
# 43 202 x 21 384 cellules à partir de −180,0079°, 89,0996°). Téléchargement (~460 Mo) :
#   https://jeodpp.jrc.ec.europa.eu/ftp/jrc-opendata/GHSL/GHS_POP_GLOBE_R2023A/GHS_POP_E2030_GLOBE_R2023A_4326_30ss/V1-0/
#
# Sortie : grille de 43 200 x 21 600 cellules de 1/120° (ligne 0 = 90° N, colonne 0 = 180° O), découpée en tuiles
# de 5° (600 x 600 cellules, 72 colonnes x 36 lignes, même découpage que assets/earth_tiles). La grille source est
# décalée de moins de 0,05 cellule (~40 m) : la cellule (ligne r, colonne c) reprend la cellule source (r − 108,
# c + 1), sans rééchantillonnage. Les valeurs négatives (absence de données) valent 0.
# Chaque cellule est quantifiée sur 16 bits : q = round(sqrt(habitants) · 64) (pas relatif ~3 % à 1 habitant, ~0,1 %
# en ville), puis chaque tuile habitée est compressée (zlib).
#
# Format (petit-boutiste) :
#   en-tête : "SNPOP001" ; int32 tuiles en largeur (72), en hauteur (36), cellules par tuile (600) ; float32
#   facteur de quantification (64) ;
#   index (72 x 36 entrées, ligne de tuiles après ligne, de 90° N vers le sud) : int64 position des données (0 : tuile
#   vide), int32 taille compressée, float64 population de la tuile ;
#   données : uint16 par cellule, ligne après ligne (nord vers sud, ouest vers est), compressées zlib.
#
# Usage (PowerShell) : tools/build_population.ps1 -src <chemin du .tif>
param([Parameter(Mandatory = $true)] $src)
$root = Split-Path -Parent $PSScriptRoot
$outPath = Join-Path $root "assets/population_2030.bin"

Add-Type -TypeDefinition @"
using System;
using System.IO;
using System.IO.Compression;

public static class PopulationGrid {
    const int TileCells = 600, TilesX = 72, TilesY = 36, Cols = TilesX * TileCells, Rows = TilesY * TileCells;
    const int RowShift = 108, ColShift = 1;
    const float Quant = 64f;

    // Décodeur LZW des TIFF (codes de 9 à 12 bits, poids fort d'abord, changement de largeur anticipé d'un code).
    static int Lzw(byte[] src, byte[] dst) {
        var prefix = new int[4096]; var suffix = new byte[4096]; var first = new byte[4096]; var length = new int[4096];
        for (int i = 0; i < 256; i++) { prefix[i] = -1; suffix[i] = (byte)i; first[i] = (byte)i; length[i] = 1; }
        int next = 258, width = 9, old = -1, outPos = 0;
        long bitPos = 0, totalBits = (long)src.Length * 8;
        var stack = new byte[4096];
        while (bitPos + width <= totalBits) {
            int code = 0;
            for (int b = 0; b < width; b++, bitPos++)
                code = (code << 1) | ((src[bitPos >> 3] >> (7 - (int)(bitPos & 7))) & 1);
            if (code == 257) break;
            if (code == 256) { next = 258; width = 9; old = -1; continue; }
            int emit;
            if (old == -1) { emit = code; }
            else {
                if (code < next) {
                    emit = code;
                    if (next < 4096) { prefix[next] = old; suffix[next] = first[code]; first[next] = first[old]; length[next] = length[old] + 1; next++; }
                } else {
                    if (next < 4096) { prefix[next] = old; suffix[next] = first[old]; first[next] = first[old]; length[next] = length[old] + 1; next++; }
                    emit = code;
                }
            }
            int len = length[emit], c = emit;
            for (int k = len - 1; k >= 0; k--) { stack[k] = suffix[c]; c = prefix[c]; }
            int n = Math.Min(len, dst.Length - outPos);
            Buffer.BlockCopy(stack, 0, dst, outPos, n);
            outPos += n;
            old = code;
            if (next + 1 >= (1 << width) && width < 12) width++;
        }
        return outPos;
    }

    static uint Adler32(byte[] data) {
        uint a = 1, b = 0;
        for (int i = 0; i < data.Length; i++) { a = (a + data[i]) % 65521; b = (b + a) % 65521; }
        return (b << 16) | a;
    }

    static byte[] Zlib(byte[] raw) {
        using (var ms = new MemoryStream()) {
            ms.WriteByte(0x78); ms.WriteByte(0x9C);
            using (var ds = new DeflateStream(ms, CompressionLevel.Optimal, true)) ds.Write(raw, 0, raw.Length);
            uint adler = Adler32(raw);
            ms.WriteByte((byte)(adler >> 24)); ms.WriteByte((byte)(adler >> 16)); ms.WriteByte((byte)(adler >> 8)); ms.WriteByte((byte)adler);
            return ms.ToArray();
        }
    }

    public static string Run(string srcPath, string outPath) {
        var fs = File.OpenRead(srcPath);
        var br = new BinaryReader(fs);
        br.ReadUInt16(); if (br.ReadUInt16() != 43) throw new Exception("BigTIFF attendu");
        br.ReadUInt16(); br.ReadUInt16();
        fs.Position = (long)br.ReadUInt64();
        long n = (long)br.ReadUInt64();
        int width = 0, height = 0, tw = 0, th = 0, bits = 0, compression = 0;
        long offsetsPos = 0, countsPos = 0, tileCount = 0;
        for (long i = 0; i < n; i++) {
            ushort tag = br.ReadUInt16(); br.ReadUInt16(); long count = (long)br.ReadUInt64(); long val = (long)br.ReadUInt64();
            switch (tag) {
                case 256: width = (int)val; break;
                case 257: height = (int)val; break;
                case 258: bits = (int)val; break;
                case 259: compression = (int)val; break;
                case 322: tw = (int)val; break;
                case 323: th = (int)val; break;
                case 324: offsetsPos = val; tileCount = count; break;
                case 325: countsPos = val; break;
            }
        }
        if (bits != 64 || compression != 5) throw new Exception("flottants 64 bits LZW attendus");
        int tilesAcross = (width + tw - 1) / tw, tilesDown = (height + th - 1) / th;
        var offsets = new long[tileCount]; var counts = new long[tileCount];
        fs.Position = offsetsPos; for (int i = 0; i < tileCount; i++) offsets[i] = (long)br.ReadUInt64();
        fs.Position = countsPos; for (int i = 0; i < tileCount; i++) counts[i] = br.ReadUInt32();

        var band = new ushort[TileCells * Cols];        // une ligne de tuiles de sortie
        var bandSum = new double[TilesX];
        var raw = new byte[tw * th * 8];
        var tileBytes = new byte[TileCells * TileCells * 2];
        var index = new long[TilesX * TilesY]; var sizes = new int[TilesX * TilesY]; var sums = new double[TilesX * TilesY];
        double world = 0;
        int written = 0;
        using (var outFs = File.Create(outPath)) using (var bw = new BinaryWriter(outFs)) {
            bw.Write(System.Text.Encoding.ASCII.GetBytes("SNPOP001"));
            bw.Write(TilesX); bw.Write(TilesY); bw.Write(TileCells); bw.Write(Quant);
            long indexPos = outFs.Position;
            outFs.Position += (long)TilesX * TilesY * 20;
            for (int ty = 0; ty < TilesY; ty++) {
                Array.Clear(band, 0, band.Length); Array.Clear(bandSum, 0, TilesX);
                int r0 = ty * TileCells, r1 = r0 + TileCells; // lignes de sortie de la bande
                int s0 = Math.Max(r0 - RowShift, 0), s1 = Math.Min(r1 - RowShift, height);
                for (int sty = s0 / th; s1 > s0 && sty <= (s1 - 1) / th; sty++) {
                    for (int stx = 0; stx < tilesAcross; stx++) {
                        int t = sty * tilesAcross + stx;
                        if (counts[t] == 0) continue;
                        fs.Position = offsets[t];
                        var comp = br.ReadBytes((int)counts[t]);
                        Array.Clear(raw, 0, raw.Length);
                        Lzw(comp, raw);
                        for (int y = 0; y < th; y++) {
                            int sr = sty * th + y;
                            if (sr < s0 || sr >= s1) continue;
                            int orow = sr + RowShift - r0;
                            for (int x = 0; x < tw; x++) {
                                int oc = stx * tw + x - ColShift;
                                if (oc < 0 || oc >= Cols) continue;
                                double v = BitConverter.ToDouble(raw, (y * tw + x) * 8);
                                if (!(v > 0)) continue;
                                int q = (int)Math.Round(Math.Sqrt(v) * Quant);
                                if (q > 65535) q = 65535;
                                band[orow * Cols + oc] = (ushort)q;
                                bandSum[oc / TileCells] += v;
                            }
                        }
                    }
                }
                for (int tx = 0; tx < TilesX; tx++) {
                    int idx = ty * TilesX + tx;
                    sums[idx] = bandSum[tx];
                    world += bandSum[tx];
                    if (bandSum[tx] <= 0) continue;
                    for (int y = 0; y < TileCells; y++)
                        Buffer.BlockCopy(band, (y * Cols + tx * TileCells) * 2, tileBytes, y * TileCells * 2, TileCells * 2);
                    var z = Zlib(tileBytes);
                    index[idx] = outFs.Position; sizes[idx] = z.Length;
                    bw.Write(z);
                    written++;
                }
                Console.Write(".");
            }
            outFs.Position = indexPos;
            for (int i = 0; i < TilesX * TilesY; i++) { bw.Write(index[i]); bw.Write(sizes[i]); bw.Write(sums[i]); }
        }
        fs.Dispose();
        return String.Format("\n{0} tuiles habitées, population mondiale {1:N0}, {2:N1} Mo", written, world,
            new FileInfo(outPath).Length / 1048576.0);
    }
}
"@
$sw = [Diagnostics.Stopwatch]::StartNew()
[PopulationGrid]::Run((Resolve-Path $src).Path, $outPath)
Write-Output "$($sw.Elapsed.TotalSeconds) s"
