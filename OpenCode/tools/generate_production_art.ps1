param(
    [string]$GodotRoot = (Join-Path $PSScriptRoot "..\godot"),
    [switch]$OverwritePlayer
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$ProductionRoot = Join-Path $GodotRoot "assets\production_art"

function Ensure-Dir {
    param([string]$Path)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

function C {
    param([string]$Hex, [int]$Alpha = 255)
    $h = $Hex.TrimStart("#")
    return [System.Drawing.Color]::FromArgb(
        $Alpha,
        [Convert]::ToInt32($h.Substring(0, 2), 16),
        [Convert]::ToInt32($h.Substring(2, 2), 16),
        [Convert]::ToInt32($h.Substring(4, 2), 16)
    )
}

function B {
    param([string]$Hex, [int]$Alpha = 255)
    return New-Object System.Drawing.SolidBrush (C $Hex $Alpha)
}

function P {
    param([string]$Hex, [float]$Width = 1.0, [int]$Alpha = 255)
    return New-Object System.Drawing.Pen (C $Hex $Alpha), $Width
}

function Rect {
    param($G, [float]$X, [float]$Y, [float]$W, [float]$H, [string]$Color, [int]$Alpha = 255)
    $brush = B $Color $Alpha
    $G.FillRectangle($brush, [int]$X, [int]$Y, [int]$W, [int]$H)
    $brush.Dispose()
}

function Ellipse {
    param($G, [float]$X, [float]$Y, [float]$W, [float]$H, [string]$Color, [int]$Alpha = 255)
    $brush = B $Color $Alpha
    $G.FillEllipse($brush, [int]$X, [int]$Y, [int]$W, [int]$H)
    $brush.Dispose()
}

function Line {
    param($G, [float]$X1, [float]$Y1, [float]$X2, [float]$Y2, [string]$Color, [float]$Width = 1.0, [int]$Alpha = 255)
    $pen = P $Color $Width $Alpha
    $G.DrawLine($pen, [int]$X1, [int]$Y1, [int]$X2, [int]$Y2)
    $pen.Dispose()
}

function Poly {
    param($G, [object[]]$Pairs, [string]$Color, [int]$Alpha = 255)
    $points = New-Object System.Drawing.Point[] $Pairs.Count
    for ($idx = 0; $idx -lt $Pairs.Count; $idx++) {
        $points[$idx] = [System.Drawing.Point]::new([int]$Pairs[$idx][0], [int]$Pairs[$idx][1])
    }
    $brush = B $Color $Alpha
    $G.FillPolygon($brush, $points)
    $brush.Dispose()
}

function Diamond {
    param($G, [float]$Cx, [float]$Cy, [float]$W, [float]$H, [string]$Color, [int]$Alpha = 255)
    Poly $G @(
        @($Cx, ($Cy - $H * 0.5)),
        @(($Cx + $W * 0.5), $Cy),
        @($Cx, ($Cy + $H * 0.5)),
        @(($Cx - $W * 0.5), $Cy)
    ) $Color $Alpha
}

function Save-Bitmap {
    param($Bitmap, [string]$Path)
    Ensure-Dir $Path
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
}

function Write-Manifest {
    param([string]$ImagePath, [int]$W, [int]$H, [int]$Frames, [float]$Fps, [bool]$Loop)
    $manifest = @{
        frame_size = @($W, $H)
        fps = $Fps
        loop = $Loop
        frames = $Frames
        pivot = "bottom_center"
    } | ConvertTo-Json -Depth 4
    Set-Content -LiteralPath ([System.IO.Path]::ChangeExtension($ImagePath, ".json")) -Value $manifest -Encoding UTF8
}

function New-Sheet {
    param(
        [string]$RelPath,
        [int]$W,
        [int]$H,
        [int]$Frames,
        [float]$Fps,
        [bool]$Loop,
        [scriptblock]$Draw
    )
    $path = Join-Path $ProductionRoot $RelPath
    Ensure-Dir $path
    $bmp = New-Object System.Drawing.Bitmap ($W * $Frames), $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    for ($i = 0; $i -lt $Frames; $i++) {
        & $Draw $g ($i * $W) 0 $i $Frames
    }
    Save-Bitmap $bmp $path
    Write-Manifest $path $W $H $Frames $Fps $Loop
    $g.Dispose()
    $bmp.Dispose()
}

function New-SingleImage {
    param([string]$RelPath, [int]$W, [int]$H, [scriptblock]$Draw)
    $path = Join-Path $ProductionRoot $RelPath
    Ensure-Dir $path
    $bmp = New-Object System.Drawing.Bitmap $W, $H, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    & $Draw $g 0 0 $W $H
    Save-Bitmap $bmp $path
    $g.Dispose()
    $bmp.Dispose()
}

function Draw-Rune {
    param($G, [float]$X, [float]$Y, [string]$Color = "49e6ff", [int]$Alpha = 255)
    Line $G $X ($Y + 1) ($X + 10) ($Y + 13) $Color 2 $Alpha
    Line $G ($X + 10) ($Y + 1) $X ($Y + 13) $Color 2 $Alpha
    Line $G ($X + 3) ($Y + 7) ($X + 15) ($Y + 7) $Color 2 $Alpha
}

function Draw-WeaponTrail {
    param($G, [float]$Ox, [float]$Oy, [float]$Power, [string]$Color)
    for ($t = 0; $t -lt 4; $t++) {
        Line $G ($Ox + 46 + $t * 4) ($Oy + 32 + $t * 5) ($Ox + 84 + $Power * 7 + $t * 2) ($Oy + 20 + $t * 7) $Color (2 + $t) (160 - $t * 28)
    }
}

function Draw-Sentinel {
    param($G, [float]$Ox, [int]$I, [int]$Frames, [string]$Kind, [string]$State)
    $phase = [Math]::Sin(($I / [Math]::Max(1, $Frames)) * [Math]::PI * 2)
    $x = $Ox + 48
    $foot = 88
    $bob = [int]([Math]::Round($phase * 2))
    if ($State -eq "death") {
        Rect $G ($x - 24) 72 44 10 "342542"
        Rect $G ($x - 12) 60 34 13 "82645b"
        Ellipse $G ($x + 12) 56 14 14 "d4475a"
        Line $G ($x - 24) 68 ($x + 33) 49 "d8d1b0" 4
        return
    }
    if ($State -eq "hurt") { $x -= 4 }
    if ($State -eq "parried") { $x -= 7; $bob = -3 }
    if ($State -eq "jump_back") { $x -= 8 + $I * 2; $bob = -8 + $I }

    Ellipse $G ($x - 18) ($foot - 4) 36 7 "080913" 110
    Line $G ($x - 8 - $phase * 3) ($foot - 8) ($x - 14) $foot "2b2233" 5
    Line $G ($x + 8 + $phase * 3) ($foot - 8) ($x + 14) $foot "2b2233" 5
    Rect $G ($x - 14) (46 + $bob) 28 30 "1b2130"
    Rect $G ($x - 11) (49 + $bob) 22 24 "39445f"
    Diamond $G $x (58 + $bob) 11 15 ($(if ($Kind -eq "ranged") { "ff9340" } else { "55ddff" }))
    Ellipse $G ($x - 12) (27 + $bob) 24 21 "20263a"
    Rect $G ($x - 8) (33 + $bob) 16 5 "f0d288"
    Rect $G ($x - 6) (35 + $bob) 5 3 "83f4ff"
    Rect $G ($x + 2) (35 + $bob) 5 3 "83f4ff"
    Poly $G @(@(($x - 16), (31 + $bob)), @($x, (19 + $bob)), @(($x + 16), (31 + $bob))) "47506f"
    Rect $G ($x - 21) (50 + $bob) 7 22 "111827"
    Rect $G ($x + 14) (50 + $bob) 7 22 "111827"

    if ($Kind -eq "melee") {
        Line $G ($x + 17) (56 + $bob) ($x + 34) (38 + $bob) "caa24a" 4
        if ($State -eq "telegraph") {
            Ellipse $G ($x + 24) (23 + $bob) 28 28 "ffdc6c" 80
            Draw-WeaponTrail $G $Ox 0 0.5 "ffdb69"
        } elseif ($State -eq "attack") {
            Draw-WeaponTrail $G $Ox 0 ($I + 1) "f6f3d2"
            Line $G ($x + 20) (58 + $bob) ($x + 70) (28 + $bob - $I) "f6f3d2" 5
            Line $G ($x + 22) (60 + $bob) ($x + 72) (31 + $bob - $I) "caa24a" 2
        } else {
            Line $G ($x + 22) (55 + $bob) ($x + 41) (23 + $bob) "e8e4c8" 4
        }
        Rect $G ($x - 28) (50 + $bob) 14 20 "254875"
        Diamond $G ($x - 21) (60 + $bob) 8 12 "4ceaff"
    } else {
        Line $G ($x + 18) (50 + $bob) ($x + 41) (63 + $bob) "b96536" 4
        Rect $G ($x + 31) (57 + $bob) 19 7 "3a2b35"
        Rect $G ($x + 45) (55 + $bob) 8 3 "ffb24d"
        if ($State -eq "telegraph" -or $State -eq "shoot") {
            Ellipse $G ($x + 49) (53 + $bob) 18 12 "ff9e3b" 110
            Rect $G ($x + 61 + $I * 2) (56 + $bob) 14 5 "ffec91"
        }
        Rect $G ($x - 20) (50 + $bob) 8 24 "41213b"
        Line $G ($x - 17) (45 + $bob) ($x - 20) (78 + $bob) "ff8b4f" 3
    }
}

function Draw-Boss {
    param($G, [float]$Ox, [int]$I, [int]$Frames, [string]$Boss, [string]$State)
    $phase = [Math]::Sin(($I / [Math]::Max(1, $Frames)) * [Math]::PI * 2)
    $x = $Ox + 128
    $foot = 230
    $bob = [int]([Math]::Round($phase * 4))
    if ($State -like "teleport*") {
        for ($n = 0; $n -lt 18; $n++) {
            $px = $x - 58 + (($n * 19 + $I * 11) % 116)
            $py = 52 + (($n * 29 + $I * 17) % 142)
            Rect $G $px $py 5 5 "55e6ff" (80 + $I * 18)
            Rect $G ($px + 9) ($py + 3) 4 8 "ff4fd8" (70 + $I * 14)
        }
        if ($State -eq "teleport_dissolve" -and $I -gt 3) { return }
    }
    if ($State -eq "death") {
        Rect $G ($x - 70) 180 140 24 "2a2035"
        Diamond $G $x 166 50 28 "ff4fd8" 150
        Line $G ($x - 70) 185 ($x + 70) 207 "ddbc65" 5
        return
    }
    if ($State -eq "hurt") { $x -= 8 }

    switch ($Boss) {
        "threshold" {
            Rect $G ($x - 42) (88 + $bob) 84 116 "2e2143"
            Rect $G ($x - 34) (98 + $bob) 68 94 "553875"
            Diamond $G $x (134 + $bob) 44 60 "9e48c7"
            Rect $G ($x - 52) (74 + $bob) 104 24 "b78430"
            Ellipse $G ($x - 34) (46 + $bob) 68 52 "30243a"
            Rect $G ($x - 20) (64 + $bob) 40 10 "f2c15c"
            Poly $G @(@(($x - 42), (59 + $bob)), @(($x - 66), (38 + $bob)), @(($x - 30), (70 + $bob))) "cf9b3a"
            Poly $G @(@(($x + 42), (59 + $bob)), @(($x + 66), (38 + $bob)), @(($x + 30), (70 + $bob))) "cf9b3a"
            Line $G ($x + 48) (130 + $bob) ($x + 94) (84 + $bob) "f0d88a" 8
            if ($State -like "attack*") { Draw-WeaponTrail $G ($Ox + 94) 68 ($I + 4) "fff0a8" }
        }
        "spider" {
            Ellipse $G ($x - 46) (100 + $bob) 92 72 "35173f"
            Ellipse $G ($x - 30) (68 + $bob) 60 45 "52206a"
            for ($leg = 0; $leg -lt 4; $leg++) {
                $dy = $leg * 22
                Line $G ($x - 34) (117 + $dy * 0.35 + $bob) ($x - 90 - $phase * 7) (94 + $dy) "b54bd9" 6
                Line $G ($x + 34) (117 + $dy * 0.35 + $bob) ($x + 90 + $phase * 7) (94 + $dy) "b54bd9" 6
            }
            Rect $G ($x - 18) (85 + $bob) 9 7 "7effff"
            Rect $G ($x + 9) (85 + $bob) 9 7 "7effff"
            if ($State -like "telegraph*" -or $State -like "attack*") {
                Line $G ($x - 60) (60 + $bob) ($x + 60) (148 + $bob) "74f7ff" 3
                Line $G ($x + 60) (60 + $bob) ($x - 60) (148 + $bob) "ff5ad8" 3
            }
        }
        "golem" {
            Rect $G ($x - 56) (78 + $bob) 112 118 "4f4a49"
            Rect $G ($x - 43) (93 + $bob) 86 88 "75684f"
            Rect $G ($x - 31) (46 + $bob) 62 42 "5e5658"
            Diamond $G $x (130 + $bob) 42 42 "ffb93d"
            Rect $G ($x - 82) (111 + $bob) 28 70 "695b49"
            Rect $G ($x + 54) (111 + $bob) 28 70 "695b49"
            Line $G ($x - 34) 196 ($x - 50 + $phase * 4) $foot "3a3435" 10
            Line $G ($x + 34) 196 ($x + 50 - $phase * 4) $foot "3a3435" 10
            if ($State -like "attack*") {
                for ($r = 0; $r -lt 3; $r++) { Ellipse $G ($x - 62 + $r * 42) (176 - $I * 2) 32 18 "ffcb5a" 90 }
            }
        }
        "archivist" {
            Ellipse $G ($x - 58) (80 + $bob) 116 130 "221a38"
            Poly $G @(@($x, (52 + $bob)), @(($x - 54), (196 + $bob)), @(($x + 54), (196 + $bob))) "3c2e68"
            Ellipse $G ($x - 29) (58 + $bob) 58 46 "f0c89b"
            Rect $G ($x - 18) (74 + $bob) 36 8 "2b1730"
            Rect $G ($x - 96) (104 + $bob + $phase * 6) 42 30 "d8b565"
            Rect $G ($x + 54) (104 + $bob - $phase * 6) 42 30 "d8b565"
            Draw-Rune $G ($x - 68) (112 + $bob) "49e6ff"
            Draw-Rune $G ($x + 66) (112 + $bob) "ff4fd8"
            if ($State -like "attack*" -or $State -like "telegraph*") {
                Ellipse $G ($x - 70) (48 + $bob) 140 140 "7e5cff" 70
            }
        }
        default {
            Rect $G ($x - 48) (74 + $bob) 96 122 "152234"
            Rect $G ($x - 37) (88 + $bob) 74 94 "203a5c"
            Ellipse $G ($x - 31) (45 + $bob) 62 50 "1d1b2f"
            Rect $G ($x - 22) (65 + $bob) 19 6 "55e6ff"
            Rect $G ($x + 3) (65 + $bob) 19 6 "ff4fd8"
            Diamond $G $x (126 + $bob) 52 46 "6df2ff"
            Line $G ($x - 70) (120 + $bob) ($x - 100) (70 + $bob) "55e6ff" 6
            Line $G ($x + 70) (120 + $bob) ($x + 100) (70 + $bob) "ff4fd8" 6
            if ($State -like "attack*" -or $State -like "telegraph*") {
                Rect $G ($x - 92) (92 + $bob) 184 8 "55e6ff" 110
                Rect $G ($x - 76) (112 + $bob) 152 8 "ff4fd8" 110
            }
        }
    }
}

function Draw-Chest {
    param($G, [float]$Ox, [int]$I, [int]$Frames, [string]$State)
    $x = $Ox + 64
    $y = 76
    Rect $G ($x - 38) ($y - 23) 76 44 "3a1f17"
    Rect $G ($x - 34) ($y - 19) 68 34 "945421"
    Rect $G ($x - 42) ($y - 26) 84 10 "d59a39"
    Rect $G ($x - 6) ($y - 7) 12 16 "f2d179"
    if ($State -eq "open") {
        Rect $G ($x - 40) ($y - 38 - $I * 2) 80 11 "dba64b"
        Ellipse $G ($x - 24) ($y - 20) 48 23 "55e6ff" 70
    } elseif ($State -eq "locked") {
        Rect $G ($x - 14) ($y - 11) 28 24 "2b2b36"
        Line $G ($x - 9) ($y - 12) ($x + 9) ($y - 12) "d8d1b0" 3
    }
}

function Draw-Altar {
    param($G, [float]$Ox, [int]$I, [int]$Frames, [string]$State)
    $x = $Ox + 64
    $pulse = [Math]::Sin(($I / [Math]::Max(1, $Frames)) * [Math]::PI * 2)
    Rect $G ($x - 42) 82 84 16 "3e334c"
    Rect $G ($x - 34) 64 68 22 "55466c"
    Rect $G ($x - 24) 48 48 20 "2a2538"
    Diamond $G $x (49 + $pulse * 3) (28 + $I) (34 + $I) ($(if ($State -eq "complete") { "55e6ff" } else { "ff4fd8" })) 210
    if ($State -ne "idle") {
        Ellipse $G ($x - 42) (20 - $I) 84 84 "55e6ff" 45
        Draw-Rune $G ($x - 9) (34 - $I) "fff0a8" 180
    }
}

function Draw-Exit {
    param($G, [float]$Ox, [int]$I, [int]$Frames, [string]$State)
    $x = $Ox + 64
    Rect $G ($x - 38) 20 76 88 "231b30"
    Rect $G ($x - 28) 31 56 66 "34234d"
    if ($State -eq "open") {
        Rect $G ($x - 22) 38 44 52 "5cecff" (110 + $I * 18)
        for ($n = 0; $n -lt 5; $n++) { Line $G ($x - 28 + $n * 14) 32 ($x - 12 + $n * 8) 96 "ff4fd8" 2 140 }
    } else {
        Rect $G ($x - 17) 55 34 26 "15131d"
        Line $G ($x - 12) 55 ($x + 12) 55 "d8d1b0" 4
    }
    Rect $G ($x - 44) 96 88 10 "a7792b"
}

function Draw-EffectSpark {
    param($G, [float]$Ox, [int]$I, [int]$Frames, [string]$Kind)
    $x = $Ox + 32
    $r = 8 + $I * 4
    if ($Kind -eq "slash") {
        for ($n = 0; $n -lt 4; $n++) { Line $G ($x - 25 + $n * 5) (44 - $n * 8) ($x + 28) (20 + $n * 4) "fff1a0" (4 - $n * 0.5) (230 - $n * 35) }
    } elseif ($Kind -eq "shield") {
        Ellipse $G ($x - $r) (32 - $r) ($r * 2) ($r * 2) "75f7ff" (180 - $I * 18)
        Diamond $G $x 32 ($r * 1.4) ($r * 1.7) "ff4fd8" 120
    } else {
        Line $G ($x - $r) 32 ($x + $r) 32 "fff1a0" 3
        Line $G $x (32 - $r) $x (32 + $r) "ff4fd8" 3
        Diamond $G $x 32 ($r) ($r) "55e6ff" 150
    }
}

function New-Projectile {
    param([string]$RelPath, [string]$Core, [string]$Glow)
    New-SingleImage $RelPath 64 64 {
        param($G, $Ox, $Oy, $W, $H)
        Ellipse $G 10 22 44 20 $Glow 80
        Rect $G 16 27 34 9 $Core 230
        Diamond $G 50 31 18 18 $Core 220
        Line $G 4 31 22 31 $Glow 4 150
    }
}

function Draw-GradientBackground {
    param($G, [int]$W, [int]$H, [string]$Top, [string]$Bottom)
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush ([System.Drawing.Rectangle]::new(0,0,$W,$H)), (C $Top), (C $Bottom), 90
    $G.FillRectangle($brush, 0, 0, $W, $H)
    $brush.Dispose()
}

function Draw-Landscape {
    param($G, [int]$W, [int]$H, [int]$Seed, [string]$Top, [string]$Bottom, [string]$Accent, [string]$Silhouette)
    Draw-GradientBackground $G $W $H $Top $Bottom
    $rng = New-Object System.Random $Seed
    for ($s = 0; $s -lt 150; $s++) {
        $sx = $rng.Next(0, $W)
        $sy = $rng.Next(20, [int]($H * 0.55))
        $size = $rng.Next(1, 4)
        Rect $G $sx $sy $size $size "fff6c4" ($rng.Next(70, 190))
    }
    Ellipse $G ([int]($W * 0.58)) ([int]($H * 0.24)) 96 96 $Accent 155
    for ($layer = 0; $layer -lt 4; $layer++) {
        $base = [int]($H * (0.58 + $layer * 0.08))
        $color = if ($layer -lt 2) { $Silhouette } else { "101426" }
        for ($x = -160; $x -lt $W + 160; $x += 180) {
            $peak = $base - $rng.Next(120, 260)
            Poly $G @(@($x, $base), @(($x + 120), $peak), @(($x + 260), $base)) $color (150 + $layer * 24)
        }
    }
    Rect $G 0 ([int]($H * 0.78)) $W ([int]($H * 0.22)) "070a14" 210
}

function New-LevelArt {
    param([string]$Folder, [int]$Seed, [string]$Top, [string]$Bottom, [string]$Accent, [string]$Silhouette, [string]$Stone, [string]$Platform)
    New-SingleImage "levels\$Folder\backgrounds\background.png" 1920 1080 {
        param($G, $Ox, $Oy, $W, $H)
        Draw-Landscape $G $W $H $Seed $Top $Bottom $Accent $Silhouette
        for ($i = 0; $i -lt 7; $i++) {
            $cx = 260 + $i * 220
            Rect $G $cx 720 70 210 "0b0d1a" 160
            Rect $G ($cx + 20) 680 30 40 $Accent 90
            Draw-Rune $G ($cx + 22) 750 $Accent 130
        }
    }
    New-SingleImage "levels\$Folder\parallax\layer_01_sky.png" 1920 1080 { param($G,$Ox,$Oy,$W,$H) Draw-GradientBackground $G $W $H $Top $Bottom }
    New-SingleImage "levels\$Folder\parallax\layer_02_far.png" 1920 1080 { param($G,$Ox,$Oy,$W,$H) for($x=-100;$x -lt $W;$x+=260){ Poly $G @(@($x,720),@(($x+130),450),@(($x+300),720)) $Silhouette 150 } }
    New-SingleImage "levels\$Folder\parallax\layer_03_mid.png" 1920 1080 { param($G,$Ox,$Oy,$W,$H) for($x=0;$x -lt $W;$x+=160){ Rect $G $x 710 50 180 "111526" 180; Poly $G @(@(($x-8),710),@(($x+25),660),@(($x+58),710)) "111526" 180 } }
    New-SingleImage "levels\$Folder\parallax\layer_04_front.png" 1920 1080 { param($G,$Ox,$Oy,$W,$H) for($x=0;$x -lt $W;$x+=90){ Rect $G $x 910 28 170 "070914" 230; Poly $G @(@(($x-18),910),@(($x+14),830),@(($x+46),910)) "070914" 230 } }
    New-SingleImage "levels\$Folder\tilesets\tileset_ground.png" 64 64 {
        param($G,$Ox,$Oy,$W,$H)
        Rect $G 0 0 64 64 $Stone
        for($y=0;$y -lt 64;$y+=16){ Line $G 0 $y 64 $y "d5a24a" 2 130 }
        for($x=0;$x -lt 64;$x+=16){ Line $G $x 0 $x 64 "140f19" 2 150 }
        Rect $G 0 0 64 8 $Platform 210
    }
    New-SingleImage "levels\$Folder\tilesets\tileset_walls.png" 64 64 {
        param($G,$Ox,$Oy,$W,$H)
        Rect $G 0 0 64 64 "171623"
        for($y=0;$y -lt 64;$y+=12){ Line $G 0 $y 64 $y $Stone 2 120 }
        for($x=8;$x -lt 64;$x+=18){ Line $G $x 0 $x 64 $Platform 1 90 }
    }
    New-SingleImage "levels\$Folder\platforms\platform_one_way.png" 256 64 {
        param($G,$Ox,$Oy,$W,$H)
        Rect $G 0 18 256 20 $Platform
        Rect $G 0 14 256 5 "f4c15f" 220
        for($x=12;$x -lt 256;$x+=36){ Diamond $G $x 26 14 18 $Accent 200 }
        Rect $G 0 39 256 8 "0c0a12" 150
    }
    New-SingleImage "levels\$Folder\props\props_common.png" 256 128 {
        param($G,$Ox,$Oy,$W,$H)
        for($i=0;$i -lt 5;$i++){ Rect $G (20+$i*42) 78 26 34 $Stone; Draw-Rune $G (24+$i*42) 84 $Accent 190 }
        Rect $G 22 28 84 18 "221a2f"; Rect $G 28 34 72 6 $Accent 180
    }
    New-SingleImage "levels\$Folder\hazards\hazards.png" 256 128 {
        param($G,$Ox,$Oy,$W,$H)
        for($i=0;$i -lt 7;$i++){ Poly $G @(@((16+$i*32),96),@((30+$i*32),38),@((44+$i*32),96)) $Accent 190 }
    }
}

function New-BossArenaArt {
    param([string]$Folder, [int]$Seed, [string]$Top, [string]$Bottom, [string]$Accent, [string]$Stone)
    New-SingleImage "boss_arenas\$Folder\background.png" 1920 1080 {
        param($G,$Ox,$Oy,$W,$H)
        Draw-Landscape $G $W $H $Seed $Top $Bottom $Accent "19122a"
        Ellipse $G 760 260 400 400 $Accent 35
        for($i=0;$i -lt 9;$i++){ Rect $G (290+$i*155) 690 84 220 "090b16" 185; Draw-Rune $G (318+$i*155) 734 $Accent 170 }
    }
    New-SingleImage "boss_arenas\$Folder\floor.png" 512 128 {
        param($G,$Ox,$Oy,$W,$H)
        Rect $G 0 26 512 58 $Stone
        Rect $G 0 20 512 8 "e0aa45" 220
        for($x=20;$x -lt 512;$x+=64){ Diamond $G $x 50 28 32 $Accent 180 }
    }
    New-SingleImage "boss_arenas\$Folder\platforms.png" 512 96 {
        param($G,$Ox,$Oy,$W,$H)
        Rect $G 0 32 512 28 $Stone
        Rect $G 0 26 512 6 "f6c15a" 220
        for($x=34;$x -lt 512;$x+=74){ Diamond $G $x 44 22 26 $Accent 170 }
    }
    New-SingleImage "boss_arenas\$Folder\foreground_props.png" 512 256 {
        param($G,$Ox,$Oy,$W,$H)
        for($i=0;$i -lt 5;$i++){ Rect $G (35+$i*92) 118 42 116 "0b0e1a" 190; Rect $G (46+$i*92) 132 20 38 $Accent 110 }
    }
    New-SingleImage "boss_arenas\$Folder\hazard_props.png" 512 128 {
        param($G,$Ox,$Oy,$W,$H)
        for($i=0;$i -lt 8;$i++){ Ellipse $G (20+$i*60) 58 38 26 $Accent 110; Line $G (20+$i*60) 72 (58+$i*60) 72 "fff0a8" 2 160 }
    }
    New-SingleImage "boss_arenas\$Folder\teleport_indicator.png" 128 128 {
        param($G,$Ox,$Oy,$W,$H)
        Ellipse $G 18 18 92 92 $Accent 70
        Diamond $G 64 64 72 72 $Accent 150
        Draw-Rune $G 55 55 "fff0a8" 210
    }
}

Write-Host "Generating production sprites..."

New-Sheet "characters\enemies\melee_sentinel\spritesheets\melee_idle.png" 96 96 6 6 $true { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "melee" "idle" }
New-Sheet "characters\enemies\melee_sentinel\spritesheets\melee_patrol.png" 96 96 8 10 $true { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "melee" "patrol" }
New-Sheet "characters\enemies\melee_sentinel\spritesheets\melee_telegraph.png" 96 96 4 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "melee" "telegraph" }
New-Sheet "characters\enemies\melee_sentinel\spritesheets\melee_attack.png" 96 96 6 12 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "melee" "attack" }
New-Sheet "characters\enemies\melee_sentinel\spritesheets\melee_hurt.png" 96 96 3 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "melee" "hurt" }
New-Sheet "characters\enemies\melee_sentinel\spritesheets\melee_death.png" 96 96 6 8 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "melee" "death" }
New-Sheet "characters\enemies\melee_sentinel\spritesheets\melee_parried.png" 96 96 4 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "melee" "parried" }

New-Sheet "characters\enemies\ranged_sentinel\spritesheets\ranged_idle.png" 96 96 6 6 $true { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "ranged" "idle" }
New-Sheet "characters\enemies\ranged_sentinel\spritesheets\ranged_patrol.png" 96 96 8 10 $true { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "ranged" "patrol" }
New-Sheet "characters\enemies\ranged_sentinel\spritesheets\ranged_telegraph.png" 96 96 4 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "ranged" "telegraph" }
New-Sheet "characters\enemies\ranged_sentinel\spritesheets\ranged_shoot.png" 96 96 6 12 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "ranged" "shoot" }
New-Sheet "characters\enemies\ranged_sentinel\spritesheets\ranged_jump_back.png" 96 96 5 12 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "ranged" "jump_back" }
New-Sheet "characters\enemies\ranged_sentinel\spritesheets\ranged_hurt.png" 96 96 3 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "ranged" "hurt" }
New-Sheet "characters\enemies\ranged_sentinel\spritesheets\ranged_death.png" 96 96 6 8 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "ranged" "death" }
New-Sheet "characters\enemies\ranged_sentinel\spritesheets\ranged_parried.png" 96 96 4 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-Sentinel $G $Ox $I $F "ranged" "parried" }
New-Projectile "characters\enemies\shared_projectiles\enemy_projectile.png" "ffad46" "ff5138"
New-Projectile "characters\enemies\shared_projectiles\reflected_projectile.png" "83ffe6" "55e6ff"

$bossDefs = @(
    @("01_threshold_warden", "threshold", @("idle","move","telegraph","attack_threshold","hurt","death"), "9e48c7"),
    @("02_logic_spider", "spider", @("idle","crawl","telegraph_branch","attack_branch","hurt","death"), "b54bd9"),
    @("03_assembly_golem", "golem", @("idle","walk","telegraph_loop","attack_loop","hurt","death"), "ffb93d"),
    @("04_archivist", "archivist", @("idle","float","telegraph_function","attack_function","hurt","death"), "7e5cff"),
    @("05_system_admin", "admin", @("idle","move","telegraph_system","attack_system","teleport_dissolve","teleport_materialize","hurt","death"), "55e6ff")
)
foreach ($def in $bossDefs) {
    $folder = $def[0]; $kind = $def[1]; $anims = $def[2]; $accent = $def[3]
    foreach ($anim in $anims) {
        $state = $anim
        if ($anim -eq "crawl" -or $anim -eq "walk" -or $anim -eq "float") { $state = "move" }
        if ($anim -like "telegraph*") { $state = "telegraph" }
        if ($anim -like "attack*") { $state = "attack" }
        New-Sheet "bosses\$folder\spritesheets\$anim.png" 256 256 8 8 ($anim -eq "idle" -or $anim -eq "move" -or $anim -eq "crawl" -or $anim -eq "walk" -or $anim -eq "float") { param($G,$Ox,$Oy,$I,$F) Draw-Boss $G $Ox $I $F $kind $state }
    }
    New-SingleImage "bosses\$folder\portraits\dialogue.png" 256 256 { param($G,$Ox,$Oy,$W,$H) Draw-Boss $G 0 2 8 $kind "idle"; Ellipse $G 24 24 208 208 $accent 35 }
}

New-Sheet "interactables\chests\spritesheets\chest_idle.png" 128 128 6 6 $true { param($G,$Ox,$Oy,$I,$F) Draw-Chest $G $Ox $I $F "idle" }
New-Sheet "interactables\chests\spritesheets\chest_open.png" 128 128 7 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-Chest $G $Ox $I $F "open" }
New-Sheet "interactables\chests\spritesheets\chest_locked.png" 128 128 4 6 $true { param($G,$Ox,$Oy,$I,$F) Draw-Chest $G $Ox $I $F "locked" }
New-SingleImage "interactables\chests\icons\chest_hint_icon.png" 128 128 { param($G,$Ox,$Oy,$W,$H) Draw-Chest $G 0 0 1 "open"; Draw-Rune $G 55 42 "55e6ff" 220 }
New-Sheet "interactables\altars\spritesheets\altar_idle.png" 128 128 6 6 $true { param($G,$Ox,$Oy,$I,$F) Draw-Altar $G $Ox $I $F "idle" }
New-Sheet "interactables\altars\spritesheets\altar_activate.png" 128 128 7 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-Altar $G $Ox $I $F "activate" }
New-Sheet "interactables\altars\spritesheets\altar_complete.png" 128 128 6 8 $true { param($G,$Ox,$Oy,$I,$F) Draw-Altar $G $Ox $I $F "complete" }
New-Sheet "interactables\exits\spritesheets\exit_locked.png" 128 128 4 6 $true { param($G,$Ox,$Oy,$I,$F) Draw-Exit $G $Ox $I $F "locked" }
New-Sheet "interactables\exits\spritesheets\exit_open.png" 128 128 8 10 $true { param($G,$Ox,$Oy,$I,$F) Draw-Exit $G $Ox $I $F "open" }

New-Sheet "effects\combat\hit_spark.png" 64 64 6 14 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "spark" }
New-Sheet "effects\combat\slash_arc.png" 64 64 5 14 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "slash" }
New-Sheet "effects\combat\parry_flash.png" 64 64 5 14 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "shield" }
New-Sheet "effects\combat\shield_reflect.png" 64 64 6 14 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "shield" }
New-Sheet "effects\combat\death_burst.png" 64 64 8 12 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "spark" }
New-Projectile "effects\projectiles\player_shot_trail.png" "7eefff" "55e6ff"
New-Projectile "effects\projectiles\enemy_shot_trail.png" "ffad46" "ff5138"
New-Sheet "effects\boss\teleport_indicator.png" 64 64 8 10 $true { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "shield" }
New-Sheet "effects\boss\dissolve_particles.png" 64 64 8 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "spark" }
New-Sheet "effects\terminal\task_success_flash.png" 64 64 6 14 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "shield" }
New-Sheet "effects\terminal\task_error_flash.png" 64 64 6 14 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "spark" }
New-Sheet "effects\pickup\chest_reward.png" 64 64 6 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "shield" }
New-Sheet "effects\pickup\altar_energy.png" 64 64 6 10 $false { param($G,$Ox,$Oy,$I,$F) Draw-EffectSpark $G $Ox $I $F "spark" }

New-LevelArt "tutorial" 101 "211b3a" "0a1022" "55e6ff" "1b2750" "3d3158" "7e5cff"
New-LevelArt "level_01_variables" 201 "30234c" "101426" "9e48c7" "1a1730" "4e3d6d" "72529b"
New-LevelArt "level_02_if_else" 202 "163a35" "0b1d1a" "55e6aa" "11302a" "315b4c" "4a9a76"
New-LevelArt "level_03_loops" 203 "3b2b18" "12100d" "ffb93d" "2d2114" "6b5130" "b78338"
New-LevelArt "level_04_functions" 204 "2f2419" "11100c" "d8b565" "251b14" "69553a" "b98d45"
New-LevelArt "level_05_integration" 205 "132945" "070e1d" "55e6ff" "0e1b32" "304966" "55a8cf"

New-BossArenaArt "boss_01_threshold_warden" 301 "322047" "0d0b18" "9e48c7" "59416a"
New-BossArenaArt "boss_02_logic_spider" 302 "251540" "090712" "b54bd9" "4d2a62"
New-BossArenaArt "boss_03_assembly_golem" 303 "392716" "0e0b08" "ffb93d" "6b5130"
New-BossArenaArt "boss_04_archivist" 304 "2c2218" "0c0907" "d8b565" "69553a"
New-BossArenaArt "boss_05_system_admin" 305 "0d2940" "050914" "55e6ff" "254865"

Write-Host "Production art generated in $ProductionRoot"
