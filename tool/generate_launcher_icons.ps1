#requires -version 5.1
<#
.SYNOPSIS
    Generate TrafArch launcher icons following the official Android adaptive icon design spec.
.DESCRIPTION
    Implements the layer geometry of the official design guide
    (https://developer.android.com/develop/ui/compose/system/icon_design_adaptive):
      - every layer is a 108x108 dp canvas
      - the 72x72 dp viewport is what remains visible after any OEM mask
      - the central 66x66 dp safe zone is guaranteed never to be clipped,
        so the logo must fit in 66x66 dp and should be at least 48x48 dp
      - the outer 18 dp on each edge is reserved for the mask and for
        parallax / pulse effects; nothing critical may live there
      - layers must not carry masks, borders or background shadows of their own
      - themed icons (Android 13+) need a monochrome variant of the logo
    Extracts the artwork layer from a solid-background source image, centres it
    inside the safe zone, validates the result against the spec geometry and writes:
      - res/mipmap-<density>/ic_launcher.png             legacy icon (API < 26)
      - res/mipmap-<density>/ic_launcher_background.png  adaptive background layer (flat sampled color, 108 dp canvas)
      - res/mipmap-<density>/ic_launcher_foreground.png  adaptive foreground
      - res/mipmap-<density>/ic_launcher_monochrome.png  Android 13+ themed layer (white silhouette)
      - res/mipmap-anydpi-v26/ic_launcher.xml            adaptive icon definition
      - res/mipmap-anydpi-v26/ic_launcher_round.xml      round variant, same layers
      - res/values/ic_launcher_background.xml            background color resource (sampled from source; layers use the mipmap PNGs)
      - assets/icon/app_icon.png                         in-app icon (About page etc.)
    Background and artwork colors are detected automatically (white-on-blue, blue-on-white, etc.).
.PARAMETER SourceImage
    Source artwork path. If omitted, the newest *.png in D:\iteam is used automatically.
.PARAMETER ContentRatio
    Logo bounding-box size as a fraction of the 108 dp canvas.
    Default 0.6111 = 66/108 dp, the documented upper bound
    ("a logo must not exceed 66x66 dp"). Do not raise this value;
    higher ratios push the artwork beyond the safe zone.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\tool\generate_launcher_icons.ps1
#>
param(
    [string]$SourceImage = '',
    [double]$ContentRatio = 0.6111
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Core')
{
    Write-Host '[WARN] PowerShell 7 detected. If Add-Type fails, re-run with Windows PowerShell 5.1 (powershell.exe).' -ForegroundColor Yellow
}

try
{
    Add-Type -AssemblyName System.Drawing
}
catch
{
    Write-Host '[ERROR] Cannot load System.Drawing. Run this script with Windows PowerShell 5.1 (powershell.exe).' -ForegroundColor Red
    exit 1
}

if ([string]::IsNullOrWhiteSpace($SourceImage))
{
    $pick = Get-ChildItem -LiteralPath 'D:\iteam' -Filter '*.png' -File |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($null -eq $pick)
    {
        Write-Host '[ERROR] No *.png file found in D:\iteam. Pass -SourceImage explicitly.' -ForegroundColor Red
        exit 1
    }
    $SourceImage = $pick.FullName
    Write-Host ('Auto-detected source: ' + $SourceImage) -ForegroundColor Cyan
}

if (-not (Test-Path -LiteralPath $SourceImage))
{
    Write-Host ('[ERROR] Source image not found: ' + $SourceImage) -ForegroundColor Red
    exit 1
}

$ResRoot = Join-Path $PSScriptRoot '..\android\app\src\main\res'
if (-not (Test-Path -LiteralPath $ResRoot))
{
    Write-Host ('[ERROR] Android res directory not found: ' + $ResRoot) -ForegroundColor Red
    exit 1
}
$ResRoot = (Resolve-Path -LiteralPath $ResRoot).Path

if (-not ('TrafArchIconGenerator' -as [type]))
{
    $asmRef = @('System.Drawing')
    if ($PSVersionTable.PSEdition -eq 'Core') { $asmRef = @('System.Drawing.Common') }

    $csharp = @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

public static class TrafArchIconGenerator
{
    private static int ClampByte(double v)
    {
        int i = (int)Math.Round(v);
        if (i < 0) return 0;
        if (i > 255) return 255;
        return i;
    }

    public static string Process(string srcPath, string resRoot, double contentRatio)
    {
        StringBuilder log = new StringBuilder();

        if (!File.Exists(srcPath))
            throw new FileNotFoundException("Source image not found: " + srcPath);

        // 1) load source, center-crop to square
        Bitmap square;
        using (FileStream fs = new FileStream(srcPath, FileMode.Open, FileAccess.Read))
        using (Image img = Image.FromStream(fs))
        {
            int side = Math.Min(img.Width, img.Height);
            int ox = (img.Width - side) / 2;
            int oy = (img.Height - side) / 2;
            square = new Bitmap(side, side, PixelFormat.Format32bppArgb);
            using (Graphics g = Graphics.FromImage(square))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(img, new Rectangle(0, 0, side, side), new Rectangle(ox, oy, side, side), GraphicsUnit.Pixel);
            }
        }
        log.AppendLine("Source: " + Path.GetFileName(srcPath) + "  (" + square.Width + " x " + square.Height + ")");

        // 2) work bitmap capped at 1024px (larger than any output size)
        int work = Math.Min(square.Width, 1024);
        Bitmap workBmp = new Bitmap(work, work, PixelFormat.Format32bppArgb);
        using (Graphics g = Graphics.FromImage(workBmp))
        {
            g.InterpolationMode = InterpolationMode.HighQualityBicubic;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.DrawImage(square, new Rectangle(0, 0, work, work));
        }
        square.Dispose();

        // 3) read pixels
        BitmapData wd = workBmp.LockBits(new Rectangle(0, 0, work, work), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
        byte[] wbuf = new byte[wd.Stride * work];
        Marshal.Copy(wd.Scan0, wbuf, 0, wbuf.Length);
        workBmp.UnlockBits(wd);

        // 4a) sample background color from the four corners
        int c = Math.Max(8, work / 40);
        long sr = 0, sg = 0, sb = 0, cnt = 0;
        int[] cxs = new int[] { 0, work - c, 0, work - c };
        int[] cys = new int[] { 0, 0, work - c, work - c };
        for (int k = 0; k < 4; k++)
        {
            for (int y = 0; y < c; y++)
            {
                int row = (cys[k] + y) * wd.Stride;
                for (int x = 0; x < c; x++)
                {
                    int i = row + (cxs[k] + x) * 4;
                    sb += wbuf[i];
                    sg += wbuf[i + 1];
                    sr += wbuf[i + 2];
                    cnt++;
                }
            }
        }
        double bgR = (double)sr / cnt;
        double bgG = (double)sg / cnt;
        double bgB = (double)sb / cnt;

        int bgRi = ClampByte(bgR), bgGi = ClampByte(bgG), bgBi = ClampByte(bgB);
        string bgHex = string.Format("#{0:X2}{1:X2}{2:X2}", bgRi, bgGi, bgBi);
        log.AppendLine("Background color: " + bgHex);

        // 4b) estimate the artwork color as the average of pixels farthest from the background
        double maxDist = 0.0;
        for (int y = 0; y < work; y++)
        {
            int row = y * wd.Stride;
            for (int x = 0; x < work; x++)
            {
                int i = row + x * 4;
                double dr = wbuf[i + 2] - bgR;
                double dg = wbuf[i + 1] - bgG;
                double db = wbuf[i] - bgB;
                double d = Math.Sqrt(dr * dr + dg * dg + db * db);
                if (d > maxDist) maxDist = d;
            }
        }
        if (maxDist < 48.0)
            throw new Exception("Artwork and background colors are too similar; cannot separate them.");

        double fgR = 0.0, fgG = 0.0, fgB = 0.0;
        long fcnt = 0;
        double keep = maxDist * 0.6;
        for (int y = 0; y < work; y++)
        {
            int row = y * wd.Stride;
            for (int x = 0; x < work; x++)
            {
                int i = row + x * 4;
                double dr = wbuf[i + 2] - bgR;
                double dg = wbuf[i + 1] - bgG;
                double db = wbuf[i] - bgB;
                double d = Math.Sqrt(dr * dr + dg * dg + db * db);
                if (d >= keep)
                {
                    fgR += wbuf[i + 2];
                    fgG += wbuf[i + 1];
                    fgB += wbuf[i];
                    fcnt++;
                }
            }
        }
        fgR /= fcnt;
        fgG /= fcnt;
        fgB /= fcnt;
        int fgRi = ClampByte(fgR), fgGi = ClampByte(fgG), fgBi = ClampByte(fgB);
        string fgHex = string.Format("#{0:X2}{1:X2}{2:X2}", fgRi, fgGi, fgBi);
        log.AppendLine("Artwork color: " + fgHex);

        double distFgBg = Math.Sqrt((fgR - bgR) * (fgR - bgR) + (fgG - bgG) * (fgG - bgG) + (fgB - bgB) * (fgB - bgB));
        if (distFgBg < 32.0)
            throw new Exception("Artwork color is too close to the background color.");

        // 5) extract the artwork layer: artwork color + alpha (antialias-safe)
        const double noiseFloor = 0.04;
        // Snap alpha to keep the cutout contract from the icon brief: background
        // and enclosed white areas stay exactly transparent, artwork strokes
        // exactly opaque, so the themed layer cannot fade into a haze or block.
        const double cutoutCeiling = 0.12;
        const double solidFloor = 0.88;
        byte[] pbuf = new byte[wbuf.Length];
        int minX = work, minY = work, maxX = -1, maxY = -1;
        for (int y = 0; y < work; y++)
        {
            int row = y * wd.Stride;
            for (int x = 0; x < work; x++)
            {
                int i = row + x * 4;
                double dr = wbuf[i + 2] - bgR;
                double dg = wbuf[i + 1] - bgG;
                double db = wbuf[i] - bgB;
                double t = Math.Sqrt(dr * dr + dg * dg + db * db) / distFgBg;
                double a = 0.0;
                if (t > noiseFloor) a = (t - noiseFloor) / (1.0 - noiseFloor);
                if (a <= cutoutCeiling) a = 0.0;
                else if (a >= solidFloor) a = 1.0;
                byte A = (byte)Math.Round(a * 255.0);
                pbuf[i] = (byte)fgBi;
                pbuf[i + 1] = (byte)fgGi;
                pbuf[i + 2] = (byte)fgRi;
                pbuf[i + 3] = A;
                if (A > 16)
                {
                    if (x < minX) minX = x;
                    if (x > maxX) maxX = x;
                    if (y < minY) minY = y;
                    if (y > maxY) maxY = y;
                }
            }
        }
        if (maxX < 0)
            throw new Exception("No artwork found. Expecting white shapes on a solid colored background.");
        int bw = maxX - minX + 1;
        int bh = maxY - minY + 1;
        log.AppendLine("Artwork bbox: " + bw + " x " + bh + " px");

        // ---- official adaptive icon geometry ------------------------------------
        // Canvas 108 dp per layer; the 72 dp viewport is what any OEM mask leaves
        // visible; the central 66 dp safe zone is never clipped; the outer 18 dp
        // on every edge is reserved for the mask and parallax / pulse effects.
        const double SpecCanvasDp = 108.0;
        const double SpecViewportDp = 72.0;
        const double SpecSafeZoneDp = 66.0;
        const double SpecMinLogoDp = 48.0;

        // the artwork is drawn at contentRatio x canvas, so one artwork pixel
        // maps to this many dp in the final icon
        double dpPerPx = (SpecCanvasDp * contentRatio) / Math.Max(bw, bh);
        double logoWDp = bw * dpPerPx;
        double logoHDp = bh * dpPerPx;

        // farthest opaque pixel from the artwork centre (which becomes the canvas centre)
        double bboxCx = minX + bw / 2.0;
        double bboxCy = minY + bh / 2.0;
        double maxRadiusPx = 0.0;
        for (int y = minY; y <= maxY; y++)
        {
            int row = y * wd.Stride;
            for (int x = minX; x <= maxX; x++)
            {
                if (pbuf[row + x * 4 + 3] <= 16) continue;
                double rx = x + 0.5 - bboxCx;
                double ry = y + 0.5 - bboxCy;
                double rr = Math.Sqrt(rx * rx + ry * ry);
                if (rr > maxRadiusPx) maxRadiusPx = rr;
            }
        }
        double maxRadiusDp = maxRadiusPx * dpPerPx;

        log.AppendLine("Geometry check (108dp canvas / 72dp viewport / 66dp safe zone / 18dp edge):");
        log.AppendLine("  logo bbox: " + Math.Round(logoWDp, 1) + " x " + Math.Round(logoHDp, 1) +
                       " dp  (spec: " + SpecMinLogoDp + ".." + SpecSafeZoneDp + " dp)");
        log.AppendLine("  max radius: " + Math.Round(maxRadiusDp, 1) + " dp  (66dp safe circle: <= " +
                       (SpecSafeZoneDp / 2) + " dp, 72dp viewport circle: <= " + (SpecViewportDp / 2) + " dp)");
        if (logoWDp < SpecMinLogoDp && logoHDp < SpecMinLogoDp)
            log.AppendLine("  [WARN] logo is below the 48x48 dp minimum; the icon may look weak on the launcher.");
        if (maxRadiusDp > SpecViewportDp / 2)
            log.AppendLine("  [WARN] artwork reaches beyond the 72 dp viewport circle; a circular OEM mask would clip it - round the corners or shrink the artwork.");
        else if (maxRadiusDp > SpecSafeZoneDp / 2)
            log.AppendLine("  [NOTE] corners exceed the 66 dp safe circle but stay inside the 72 dp viewport circle: safe on rounded-square masks, only an extreme circular mask could touch the rounded corners.");
        else
            log.AppendLine("  [OK] artwork fits inside the 66 dp safe zone; no OEM mask can clip it.");

        Bitmap patternBmp = new Bitmap(work, work, PixelFormat.Format32bppArgb);
        BitmapData pdat = patternBmp.LockBits(new Rectangle(0, 0, work, work), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(pbuf, 0, pdat.Scan0, pbuf.Length);
        patternBmp.UnlockBits(pdat);

        // 5b) white silhouette bitmap for the Android 13 monochrome layer
        byte[] wsil = new byte[pbuf.Length];
        for (int i = 0; i < pbuf.Length; i += 4)
        {
            wsil[i] = 255;
            wsil[i + 1] = 255;
            wsil[i + 2] = 255;
            wsil[i + 3] = pbuf[i + 3];
        }
        long opaqueCount = 0;
        for (int i = 3; i < wsil.Length; i += 4)
        {
            if (wsil[i] > 128) opaqueCount++;
        }
        double monoCoverage = (double)opaqueCount / (work * work);
        log.AppendLine("Monochrome opaque coverage: " + Math.Round(monoCoverage * 100.0, 1) + "%");
        if (monoCoverage > 0.60)
        {
            log.AppendLine("  [WARN] Monochrome covers most of the canvas; the themed icon may render as a solid block. Check the source background.");
        }
        Bitmap monoBmp = new Bitmap(work, work, PixelFormat.Format32bppArgb);
        BitmapData mdat = monoBmp.LockBits(new Rectangle(0, 0, work, work), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
        Marshal.Copy(wsil, 0, mdat.Scan0, wsil.Length);
        monoBmp.UnlockBits(mdat);

        // 6) emit assets for every density
        string[] dens = new string[] { "mdpi", "hdpi", "xhdpi", "xxhdpi", "xxxhdpi" };
        int[] legacySizes = new int[] { 48, 72, 96, 144, 192 };
        int[] adaptiveSizes = new int[] { 108, 162, 216, 324, 432 };

        for (int k = 0; k < dens.Length; k++)
        {
            string dir = Path.Combine(resRoot, "mipmap-" + dens[k]);
            Directory.CreateDirectory(dir);

            // legacy launcher icon (API < 26): full artwork
            using (Bitmap lg = new Bitmap(legacySizes[k], legacySizes[k], PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(lg))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(workBmp, new Rectangle(0, 0, legacySizes[k], legacySizes[k]));
                }
                lg.Save(Path.Combine(dir, "ic_launcher.png"), ImageFormat.Png);
            }

            // adaptive foreground + monochrome, artwork centered inside the safe zone
            int size = adaptiveSizes[k];
            double scale = (size * contentRatio) / Math.Max(bw, bh);
            int dw = Math.Max(1, (int)Math.Round(bw * scale));
            int dh = Math.Max(1, (int)Math.Round(bh * scale));
            int dx = (size - dw) / 2;
            int dy = (size - dh) / 2;
            Rectangle dest = new Rectangle(dx, dy, dw, dh);
            Rectangle crop = new Rectangle(minX, minY, bw, bh);

            // adaptive background layer: the full 108 dp canvas flat-filled with the
            // sampled brand color. Background layers run edge to edge (no safe-zone
            // inset); the launcher mask crops them just like the foreground.
            using (Bitmap bg = new Bitmap(size, size, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(bg))
                {
                    g.Clear(Color.FromArgb(bgRi, bgGi, bgBi));
                }
                bg.Save(Path.Combine(dir, "ic_launcher_background.png"), ImageFormat.Png);
            }

            // adaptive foreground: brand artwork on transparent background
            using (Bitmap fg = new Bitmap(size, size, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(fg))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(patternBmp, dest, crop, GraphicsUnit.Pixel);
                }
                fg.Save(Path.Combine(dir, "ic_launcher_foreground.png"), ImageFormat.Png);
            }

            // Android 13+ monochrome layer: white silhouette, recolored by the launcher
            using (Bitmap mono = new Bitmap(size, size, PixelFormat.Format32bppArgb))
            {
                using (Graphics g = Graphics.FromImage(mono))
                {
                    g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                    g.DrawImage(monoBmp, dest, crop, GraphicsUnit.Pixel);
                }
                mono.Save(Path.Combine(dir, "ic_launcher_monochrome.png"), ImageFormat.Png);
            }
            log.AppendLine("  mipmap-" + dens[k] + ": ic_launcher.png " + legacySizes[k] + "px, background + foreground + monochrome " + size + "px");
        }

        // 7) write XML resources
        string anydpi = Path.Combine(resRoot, "mipmap-anydpi-v26");
        Directory.CreateDirectory(anydpi);
        string iconXml =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
            "<adaptive-icon xmlns:android=\"http://schemas.android.com/apk/res/android\">\n" +
            "    <background android:drawable=\"@mipmap/ic_launcher_background\" />\n" +
            "    <foreground android:drawable=\"@mipmap/ic_launcher_foreground\" />\n" +
            "    <monochrome android:drawable=\"@mipmap/ic_launcher_monochrome\" />\n" +
            "</adaptive-icon>\n";
        File.WriteAllText(Path.Combine(anydpi, "ic_launcher.xml"), iconXml, new UTF8Encoding(false));
        File.WriteAllText(Path.Combine(anydpi, "ic_launcher_round.xml"), iconXml, new UTF8Encoding(false));
        string colorXml =
            "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n" +
            "<resources>\n" +
            "    <color name=\"ic_launcher_background\">" + bgHex + "</color>\n" +
            "</resources>\n";
        File.WriteAllText(Path.Combine(resRoot, "values", "ic_launcher_background.xml"), colorXml, new UTF8Encoding(false));
        log.AppendLine("XML: mipmap-anydpi-v26/ic_launcher.xml + ic_launcher_round.xml (mipmap background/foreground/monochrome), values/ic_launcher_background.xml");

        // 8) in-app icon asset for the About page and similar UI spots
        string projectRoot = Path.GetFullPath(Path.Combine(resRoot, "..", "..", "..", "..", ".."));
        string assetDir = Path.Combine(projectRoot, "assets", "icon");
        Directory.CreateDirectory(assetDir);
        using (Bitmap appIcon = new Bitmap(512, 512, PixelFormat.Format32bppArgb))
        {
            using (Graphics g = Graphics.FromImage(appIcon))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.DrawImage(workBmp, new Rectangle(0, 0, 512, 512));
            }
            appIcon.Save(Path.Combine(assetDir, "app_icon.png"), ImageFormat.Png);
        }
        log.AppendLine("In-app icon asset: assets/icon/app_icon.png (512px)");

        monoBmp.Dispose();
        patternBmp.Dispose();
        workBmp.Dispose();
        return log.ToString();
    }
}
'@
    Add-Type -TypeDefinition $csharp -ReferencedAssemblies $asmRef
}

Write-Host 'Generating launcher icons...' -ForegroundColor Cyan
try
{
    $summary = [TrafArchIconGenerator]::Process($SourceImage, $ResRoot, $ContentRatio)
    Write-Host ''
    Write-Host '=== Done ===' -ForegroundColor Green
    Write-Host $summary
    Write-Host ''
    Write-Host 'Next steps:' -ForegroundColor Cyan
    Write-Host '  1) flutter clean'
    Write-Host '  2) flutter build apk --release   (or flutter run)'
    Write-Host '  3) Android 13+: enable "Themed icons" in the launcher to see the monochrome layer recolor.'
    Write-Host '     From Android 16 QPR 2 the system themes apps automatically.'

}
catch
{
    Write-Host ''
    Write-Host '[ERROR] Icon generation failed:' -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    if ($_.Exception.InnerException) { Write-Host $_.Exception.InnerException.Message -ForegroundColor Red }
    exit 1
}