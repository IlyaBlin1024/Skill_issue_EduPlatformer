param(
    [string]$OutputRoot = ".\godot\assets\generated_menu"
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$script:Root = Join-Path (Resolve-Path (Join-Path $PSScriptRoot "..")).Path $OutputRoot
$script:Random = [System.Random]::new(20260508)

function Ensure-Dir([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path | Out-Null
    }
}

function Save-Png($Bitmap, [string]$Path) {
    Ensure-Dir (Split-Path -Parent $Path)
    $Bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $Bitmap.Dispose()
}

function New-Canvas([int]$Width, [int]$Height, [bool]$Transparent = $true) {
    $bmp = [System.Drawing.Bitmap]::new($Width, $Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::None
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    if ($Transparent) {
        $g.Clear([System.Drawing.Color]::Transparent)
    } else {
        $g.Clear([System.Drawing.Color]::Black)
    }
    return [pscustomobject]@{
        Bitmap = $bmp
        Graphics = $g
    }
}

function Color([int]$A, [int]$R, [int]$G, [int]$B) {
    return [System.Drawing.Color]::FromArgb($A, $R, $G, $B)
}

function Brush($Color) {
    return [System.Drawing.SolidBrush]::new($Color)
}

function Pen($Color, [float]$Width = 1.0) {
    return [System.Drawing.Pen]::new($Color, $Width)
}

function Draw-Rect($G, [int]$X, [int]$Y, [int]$W, [int]$H, $Fill, $Outline = $null, [int]$OutlineWidth = 1) {
    $rect = [System.Drawing.Rectangle]::new($X, $Y, $W, $H)
    if ($Fill -ne $null) {
        $b = Brush $Fill
        $G.FillRectangle($b, $rect)
        $b.Dispose()
    }
    if ($Outline -ne $null) {
        $p = Pen $Outline $OutlineWidth
        $G.DrawRectangle($p, $rect)
        $p.Dispose()
    }
}

function Draw-Polygon($G, [System.Drawing.Point[]]$Points, $Fill, $Outline = $null, [int]$OutlineWidth = 1) {
    $b = Brush $Fill
    $G.FillPolygon($b, $Points)
    $b.Dispose()
    if ($Outline -ne $null) {
        $p = Pen $Outline $OutlineWidth
        $G.DrawPolygon($p, $Points)
        $p.Dispose()
    }
}

function Draw-Diamond($G, [int]$Cx, [int]$Cy, [int]$Size, $Fill, $Outline) {
    $pts = @(
        [System.Drawing.Point]::new($Cx, $Cy - $Size),
        [System.Drawing.Point]::new($Cx + $Size, $Cy),
        [System.Drawing.Point]::new($Cx, $Cy + $Size),
        [System.Drawing.Point]::new($Cx - $Size, $Cy)
    )
    Draw-Polygon $G $pts $Fill $Outline 2
}

function Draw-Beveled-Frame($G, [int]$X, [int]$Y, [int]$W, [int]$H, [bool]$Selected = $false, [bool]$Locked = $false) {
    $W = [int]($W | Select-Object -First 1)
    $H = [int]($H | Select-Object -First 1)
    $outer = if ($Selected) { Color 255 16 187 255 } elseif ($Locked) { Color 255 126 92 50 } else { Color 255 255 137 22 }
    $gold = Color 255 233 167 49
    $shadow = Color 255 48 24 12
    $inner = if ($Locked) { Color 215 8 8 16 } else { Color 230 8 11 26 }
    $panel = if ($Selected) { Color 230 10 43 88 } else { $inner }

    Draw-Rect $G $X $Y $W $H (Color 210 5 7 17) $shadow 6
    Draw-Rect $G ($X + 6) ($Y + 6) ($W - 12) ($H - 12) $panel $outer 4
    Draw-Rect $G ($X + 14) ($Y + 14) ($W - 28) ($H - 28) (Color 175 3 4 13) $gold 2

    $corner = 22
    foreach ($dx in @(0, ($W - $corner))) {
        foreach ($dy in @(0, ($H - $corner))) {
            Draw-Rect $G ($X + $dx) ($Y + $dy) $corner $corner (Color 255 114 56 18) $gold 2
            Draw-Diamond $G ($X + $dx + [int]($corner / 2)) ($Y + $dy + [int]($corner / 2)) 5 (Color 255 98 15 180) (Color 255 255 198 68)
        }
    }
    Draw-Diamond $G ($X + [int]($W / 2)) ($Y + 6) 13 (Color 255 90 13 168) $gold
    Draw-Diamond $G ($X + [int]($W / 2)) ($Y + $H - 6) 13 (Color 255 90 13 168) $gold
}

function Draw-UiTexture($G, [int]$X, [int]$Y, [int]$W, [int]$H) {
    for ($i = 0; $i -lt 600; $i++) {
        $px = $X + $script:Random.Next(0, [Math]::Max(1, $W))
        $py = $Y + $script:Random.Next(0, [Math]::Max(1, $H))
        $alpha = $script:Random.Next(12, 36)
        Draw-Rect $G $px $py 2 2 (Color $alpha 255 220 118) $null 0
    }
}

function Create-Button([string]$Name, [int]$Width, [int]$Height, [bool]$Selected) {
    $pair = New-Canvas $Width $Height
    $bmp = $pair.Bitmap
    $g = $pair.Graphics
    Draw-Beveled-Frame $g 4 4 ($Width - 8) ($Height - 8) $Selected $false
    Draw-UiTexture $g 20 18 ($Width - 40) ($Height - 36)
    if ($Selected) {
        Draw-Rect $g 18 18 ($Width - 36) 8 (Color 175 38 201 255) $null 0
        Draw-Rect $g 18 ($Height - 26) ($Width - 36) 5 (Color 120 38 201 255) $null 0
    }
    $g.Dispose()
    Save-Png $bmp (Join-Path $script:Root "buttons\$Name.png")
}

function Create-Frame([string]$Name, [int]$Width, [int]$Height, [bool]$Selected, [bool]$Locked) {
    $pair = New-Canvas $Width $Height
    $bmp = $pair.Bitmap
    $g = $pair.Graphics
    Draw-Beveled-Frame $g 4 4 ($Width - 8) ($Height - 8) $Selected $Locked
    Draw-UiTexture $g 24 24 ($Width - 48) ($Height - 48)
    $g.Dispose()
    Save-Png $bmp (Join-Path $script:Root "cards\$Name.png")
}

function Draw-CardArtBase($G, [int]$W, [int]$H, $SkyTop, $SkyBottom) {
    for ($y = 0; $y -lt $H; $y++) {
        $t = $y / [Math]::Max(1, $H - 1)
        $r = [int]($SkyTop.R + ($SkyBottom.R - $SkyTop.R) * $t)
        $gg = [int]($SkyTop.G + ($SkyBottom.G - $SkyTop.G) * $t)
        $b = [int]($SkyTop.B + ($SkyBottom.B - $SkyTop.B) * $t)
        Draw-Rect $G 0 $y $W 1 (Color 255 $r $gg $b) $null 0
    }
    for ($i = 0; $i -lt 90; $i++) {
        $x = $script:Random.Next(0, $W)
        $y = $script:Random.Next(0, $H)
        Draw-Rect $G $x $y 2 2 (Color 45 255 224 144) $null 0
    }
}

function Draw-Knight($G, [int]$X, [int]$Y, [int]$S) {
    Draw-Rect $G ($X + 5*$S) ($Y + 4*$S) (4*$S) (4*$S) (Color 255 230 188 132) (Color 255 35 24 20) $S
    Draw-Rect $G ($X + 3*$S) ($Y + 8*$S) (8*$S) (10*$S) (Color 255 32 49 74) (Color 255 10 11 17) $S
    Draw-Rect $G ($X + 2*$S) ($Y + 10*$S) (4*$S) (7*$S) (Color 255 37 70 103) (Color 255 10 11 17) $S
    Draw-Rect $G ($X + 4*$S) ($Y + 18*$S) (3*$S) (8*$S) (Color 255 22 25 34) $null 0
    Draw-Rect $G ($X + 9*$S) ($Y + 18*$S) (3*$S) (8*$S) (Color 255 22 25 34) $null 0
    $blade = @(
        [System.Drawing.Point]::new($X + 12*$S, $Y + 9*$S),
        [System.Drawing.Point]::new($X + 23*$S, $Y + 1*$S),
        [System.Drawing.Point]::new($X + 15*$S, $Y + 12*$S)
    )
    Draw-Polygon $G $blade (Color 255 202 214 225) (Color 255 49 57 70) $S
    Draw-Rect $G ($X + 10*$S) ($Y + 12*$S) (6*$S) (2*$S) (Color 255 227 154 49) (Color 255 45 22 8) $S
}

function Create-CardArt([string]$Name, [string]$Kind, [int]$SeedOffset) {
    $script:Random = [System.Random]::new(20260508 + $SeedOffset)
    $W = 384
    $H = 512
    $pair = New-Canvas $W $H $false
    $bmp = $pair.Bitmap
    $g = $pair.Graphics
    Draw-CardArtBase $g $W $H (Color 255 39 42 86) (Color 255 216 100 42)

    $ground = Color 255 28 48 36
    if ($Kind -like "boss*") { $ground = Color 255 54 22 38 }
    Draw-Polygon $g @(
        [System.Drawing.Point]::new(0, 350),
        [System.Drawing.Point]::new(384, 310),
        [System.Drawing.Point]::new(384, 512),
        [System.Drawing.Point]::new(0, 512)
    ) $ground $null 0

    for ($i = 0; $i -lt 24; $i++) {
        $x = $script:Random.Next(-20, $W)
        $h = $script:Random.Next(35, 105)
        Draw-Polygon $g @(
            [System.Drawing.Point]::new($x, 365),
            [System.Drawing.Point]::new($x + 20, 365 - $h),
            [System.Drawing.Point]::new($x + 42, 365)
        ) (Color 205 9 24 31) $null 0
    }

    switch -Wildcard ($Kind) {
        "tutorial" {
            Draw-Knight $g 78 248 6
            Draw-Rect $g 250 230 42 120 (Color 255 137 97 44) (Color 255 43 26 13) 5
            Draw-Rect $g 228 240 86 62 (Color 255 176 141 74) (Color 255 55 34 18) 4
            Draw-Rect $g 253 252 36 36 (Color 255 154 32 32) (Color 255 242 221 150) 5
            Draw-Rect $g 263 262 16 16 (Color 255 242 221 150) $null 0
        }
        "level1" {
            Draw-Knight $g 80 250 6
            Draw-Rect $g 230 210 92 130 (Color 220 20 28 55) (Color 255 225 167 49) 4
            Draw-Rect $g 250 238 54 14 (Color 255 28 211 240) $null 0
            Draw-Rect $g 250 270 28 14 (Color 255 236 78 214) $null 0
        }
        "level2" {
            Draw-Knight $g 82 260 5
            Draw-Rect $g 210 214 24 132 (Color 255 104 70 31) $null 0
            Draw-Polygon $g @(
                [System.Drawing.Point]::new(230, 224),
                [System.Drawing.Point]::new(325, 254),
                [System.Drawing.Point]::new(230, 284)
            ) (Color 255 210 151 47) (Color 255 49 25 9) 4
            Draw-Polygon $g @(
                [System.Drawing.Point]::new(226, 290),
                [System.Drawing.Point]::new(134, 324),
                [System.Drawing.Point]::new(226, 350)
            ) (Color 255 75 145 210) (Color 255 18 28 54) 4
        }
        "level3" {
            Draw-Knight $g 82 266 5
            for ($i = 0; $i -lt 6; $i++) {
                Draw-Rect $g (170 + $i*24) (276 + [Math]::Sin($i)*24) 48 12 (Color 255 189 141 75) (Color 255 52 29 14) 2
            }
            Draw-Diamond $g 270 218 32 (Color 255 40 203 228) (Color 255 238 202 88)
        }
        "level4" {
            Draw-Knight $g 70 260 5
            Draw-Diamond $g 250 245 60 (Color 255 71 50 102) (Color 255 238 188 66)
            Draw-Diamond $g 250 245 35 (Color 255 18 22 44) (Color 255 53 205 240)
            Draw-Rect $g 215 236 70 18 (Color 255 235 157 51) $null 0
            Draw-Rect $g 241 210 18 70 (Color 255 235 157 51) $null 0
        }
        "level5" {
            Draw-Knight $g 72 262 5
            Draw-Rect $g 220 160 78 190 (Color 255 21 24 47) (Color 255 236 171 44) 4
            for ($i = 0; $i -lt 6; $i++) {
                Draw-Rect $g (235 + ($i % 2)*30) (180 + $i*25) 18 18 (Color 255 48 215 240) $null 0
            }
            Draw-Diamond $g 258 126 34 (Color 255 227 72 210) (Color 255 255 217 93)
        }
        "boss*" {
            Draw-Knight $g 56 286 4
            $cx = 245
            $cy = 240
            $scale = 1 + ($SeedOffset % 4)
            Draw-Diamond $g $cx $cy (48 + 4*$scale) (Color 255 77 23 104) (Color 255 226 113 38)
            Draw-Rect $g ($cx - 38) ($cy + 20) 76 88 (Color 255 88 25 105) (Color 255 28 10 34) 5
            Draw-Rect $g ($cx - 20) ($cy - 8) 16 14 (Color 255 247 78 44) $null 0
            Draw-Rect $g ($cx + 8) ($cy - 8) 16 14 (Color 255 247 78 44) $null 0
            for ($i = 0; $i -lt 6; $i++) {
                Draw-Diamond $g ($script:Random.Next(150, 345)) ($script:Random.Next(80, 350)) ($script:Random.Next(6, 16)) (Color 175 228 42 207) (Color 220 40 200 240)
            }
        }
    }

    $g.Dispose()
    Save-Png $bmp (Join-Path $script:Root "card_art\$Name.png")
}

function Create-MenuBackground() {
    $lowW = 480
    $lowH = 270
    $pair = New-Canvas $lowW $lowH $false
    $bmp = $pair.Bitmap
    $g = $pair.Graphics

    for ($y = 0; $y -lt $lowH; $y++) {
        $t = $y / ($lowH - 1)
        $r = [int](18 + 95 * $t)
        $gg = [int](12 + 24 * $t)
        $b = [int](54 + 42 * (1 - $t))
        if ($y -gt 85 -and $y -lt 150) {
            $r += 58
            $gg += 29
        }
        Draw-Rect $g 0 $y $lowW 1 (Color 255 ([Math]::Min(255, $r)) ([Math]::Min(255, $gg)) ([Math]::Min(255, $b))) $null 0
    }

    Draw-Rect $g 246 116 28 10 (Color 255 255 181 64) $null 0
    Draw-Rect $g 254 106 12 28 (Color 255 255 201 98) $null 0

    Draw-Polygon $g @(
        [System.Drawing.Point]::new(0, 122),
        [System.Drawing.Point]::new(75, 70),
        [System.Drawing.Point]::new(150, 130),
        [System.Drawing.Point]::new(255, 75),
        [System.Drawing.Point]::new(372, 136),
        [System.Drawing.Point]::new(480, 86),
        [System.Drawing.Point]::new(480, 270),
        [System.Drawing.Point]::new(0, 270)
    ) (Color 205 32 28 63) $null 0

    Draw-Polygon $g @(
        [System.Drawing.Point]::new(285, 142),
        [System.Drawing.Point]::new(430, 154),
        [System.Drawing.Point]::new(480, 170),
        [System.Drawing.Point]::new(480, 270),
        [System.Drawing.Point]::new(260, 270)
    ) (Color 255 12 19 34) $null 0

    for ($i = 0; $i -lt 55; $i++) {
        $x = $script:Random.Next(300, 456)
        $h = $script:Random.Next(32, 105)
        Draw-Rect $g $x (168 - $h) $script:Random.Next(5, 17) $h (Color 255 13 15 31) $null 0
        Draw-Polygon $g @(
            [System.Drawing.Point]::new($x - 4, 168 - $h),
            [System.Drawing.Point]::new($x + 6, 146 - $h),
            [System.Drawing.Point]::new($x + 16, 168 - $h)
        ) (Color 255 9 10 22) $null 0
        if ($i % 5 -eq 0) {
            Draw-Rect $g ($x + 3) (160 - [int]($h / 2)) 2 2 (Color 255 255 153 54) $null 0
        }
    }

    Draw-Polygon $g @(
        [System.Drawing.Point]::new(0, 148),
        [System.Drawing.Point]::new(150, 152),
        [System.Drawing.Point]::new(270, 142),
        [System.Drawing.Point]::new(480, 150),
        [System.Drawing.Point]::new(480, 270),
        [System.Drawing.Point]::new(0, 270)
    ) (Color 255 18 34 47) $null 0

    for ($i = 0; $i -lt 80; $i++) {
        $x = $script:Random.Next(0, 480)
        $y = $script:Random.Next(152, 242)
        $w = $script:Random.Next(8, 28)
        Draw-Rect $g $x $y $w 2 (Color 70 248 111 48) $null 0
        Draw-Rect $g ($x + 2) ($y + 4) ([Math]::Max(2, $w - 8)) 1 (Color 42 69 209 245) $null 0
    }

    for ($i = 0; $i -lt 40; $i++) {
        $x = $script:Random.Next(-30, 160)
        $h = $script:Random.Next(22, 82)
        Draw-Polygon $g @(
            [System.Drawing.Point]::new($x, 188),
            [System.Drawing.Point]::new($x + 17, 188 - $h),
            [System.Drawing.Point]::new($x + 34, 188)
        ) (Color 255 5 20 18) $null 0
    }

    for ($i = 0; $i -lt 1400; $i++) {
        $x = $script:Random.Next(0, $lowW)
        $y = $script:Random.Next(0, $lowH)
        $c = $bmp.GetPixel($x, $y)
        $n = $script:Random.Next(-9, 10)
        $bmp.SetPixel($x, $y, (Color 255 ([Math]::Max(0, [Math]::Min(255, $c.R + $n))) ([Math]::Max(0, [Math]::Min(255, $c.G + $n))) ([Math]::Max(0, [Math]::Min(255, $c.B + $n)))))
    }

    $g.Dispose()
    $final = [System.Drawing.Bitmap]::new(1920, 1080, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $fg = [System.Drawing.Graphics]::FromImage($final)
    $fg.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
    $fg.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half
    $fg.DrawImage($bmp, 0, 0, 1920, 1080)
    $fg.Dispose()
    $bmp.Dispose()
    Save-Png $final (Join-Path $script:Root "backgrounds\main_menu_background.png")
}

function Create-FontAtlas() {
    $cellW = 64
    $cellH = 72
    $cols = 16
    $rows = 8
    $pair = New-Canvas ($cellW * $cols) ($cellH * $rows)
    $bmp = $pair.Bitmap
    $g = $pair.Graphics
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::SingleBitPerPixelGridFit
    $family = "Georgia"
    $font = [System.Drawing.Font]::new($family, 39, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $small = [System.Drawing.Font]::new("Consolas", 9, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $format = [System.Drawing.StringFormat]::new()
    $format.Alignment = [System.Drawing.StringAlignment]::Center
    $format.LineAlignment = [System.Drawing.StringAlignment]::Center

    $outline = Brush (Color 255 9 7 5)
    $gold = Brush (Color 255 255 221 111)
    $goldDark = Brush (Color 255 181 103 31)
    $dim = Brush (Color 90 138 122 91)
    for ($id = 0; $id -lt 128; $id++) {
        $x = ($id % $cols) * $cellW
        $y = [Math]::Floor($id / $cols) * $cellH
        Draw-Rect $g $x $y $cellW $cellH (Color 0 0 0 0) $null 0
        $label = if ($id -ge 32 -and $id -le 126) { [char]$id } elseif ($id -eq 127) { "DEL" } else { "" }
        if ($label -ne "") {
            $rect = [System.Drawing.RectangleF]::new($x + 1, $y + 4, $cellW - 2, $cellH - 8)
            foreach ($dx in @(-3, 0, 3)) {
                foreach ($dy in @(-3, 0, 3)) {
                    if ($dx -ne 0 -or $dy -ne 0) {
                        $r = [System.Drawing.RectangleF]::new($rect.X + $dx, $rect.Y + $dy, $rect.Width, $rect.Height)
                        $g.DrawString([string]$label, $font, $outline, $r, $format)
                    }
                }
            }
            $rShadow = [System.Drawing.RectangleF]::new($rect.X + 0, $rect.Y + 3, $rect.Width, $rect.Height)
            $g.DrawString([string]$label, $font, $goldDark, $rShadow, $format)
            $g.DrawString([string]$label, $font, $gold, $rect, $format)
        } else {
            $rect = [System.Drawing.RectangleF]::new($x, $y + 28, $cellW, 12)
            $g.DrawString($id.ToString(), $small, $dim, $rect, $format)
        }
    }
    $font.Dispose()
    $small.Dispose()
    $format.Dispose()
    $outline.Dispose()
    $gold.Dispose()
    $goldDark.Dispose()
    $dim.Dispose()
    $g.Dispose()
    $fontPath = Join-Path $script:Root "font\skill_issue_ascii_gold.png"
    Save-Png $bmp $fontPath

    $fnt = @()
    $fnt += 'info face="SkillIssueGoldAscii" size=39 bold=1 italic=0 charset="" unicode=0 stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1'
    $fnt += "common lineHeight=$cellH base=56 scaleW=$($cellW * $cols) scaleH=$($cellH * $rows) pages=1 packed=0"
    $fnt += 'page id=0 file="skill_issue_ascii_gold.png"'
    $fnt += "chars count=128"
    for ($id = 0; $id -lt 128; $id++) {
        $x = ($id % $cols) * $cellW
        $y = [Math]::Floor($id / $cols) * $cellH
        $w = if ($id -ge 32 -and $id -le 126) { $cellW } else { 0 }
        $fnt += "char id=$id x=$x y=$y width=$w height=$cellH xoffset=0 yoffset=0 xadvance=$cellW page=0 chnl=15"
    }
    Set-Content -LiteralPath (Join-Path $script:Root "font\skill_issue_ascii_gold.fnt") -Value ($fnt -join "`n") -Encoding ASCII
}

function Create-PreviewSheet() {
    $pair = New-Canvas 1600 1200 $false
    $bmp = $pair.Bitmap
    $g = $pair.Graphics
    Draw-Rect $g 0 0 1600 1200 (Color 255 17 10 32) $null 0

    $bg = [System.Drawing.Bitmap]::FromFile((Join-Path $script:Root "backgrounds\main_menu_background.png"))
    $g.DrawImage($bg, 30, 30, 760, 428)
    $bg.Dispose()

    foreach ($item in @(
        @("buttons\button_main_idle.png", 840, 60, 520, 101),
        @("buttons\button_main_selected.png", 840, 190, 520, 101),
        @("buttons\button_small_idle.png", 840, 320, 260, 78),
        @("buttons\button_small_selected.png", 1120, 320, 260, 78),
        @("cards\card_large_selected.png", 60, 510, 230, 348),
        @("cards\card_large_idle.png", 330, 510, 230, 348),
        @("cards\card_large_locked.png", 600, 510, 230, 348),
        @("cards\inventory_slot_idle.png", 870, 510, 190, 190)
    )) {
        $img = [System.Drawing.Bitmap]::FromFile((Join-Path $script:Root $item[0]))
        $g.DrawImage($img, [int]$item[1], [int]$item[2], [int]$item[3], [int]$item[4])
        $img.Dispose()
    }

    $font = [System.Drawing.Bitmap]::FromFile((Join-Path $script:Root "font\skill_issue_ascii_gold.png"))
    $g.DrawImage($font, 60, 910, 1024, 288)
    $font.Dispose()

    $x = 1120
    $y = 500
    foreach ($name in @("tutorial_art", "level_01_variables", "level_02_if_else", "level_03_loops", "level_04_functions", "level_05_integration", "boss_01", "boss_02", "boss_03", "boss_04", "boss_05")) {
        $img = [System.Drawing.Bitmap]::FromFile((Join-Path $script:Root "card_art\$name.png"))
        $g.DrawImage($img, $x, $y, 115, 154)
        $img.Dispose()
        $x += 125
        if ($x -gt 1480) {
            $x = 1120
            $y += 170
        }
    }

    $g.Dispose()
    Save-Png $bmp (Join-Path $script:Root "preview_contact_sheet.png")
}

Ensure-Dir $script:Root
Create-MenuBackground

Create-Button "button_main_idle" 720 140 $false
Create-Button "button_main_selected" 720 140 $true
Create-Button "button_small_idle" 320 96 $false
Create-Button "button_small_selected" 320 96 $true
Create-Button "button_back_idle" 260 86 $false
Create-Button "button_back_selected" 260 86 $true

Create-Frame "card_large_idle" 320 480 $false $false
Create-Frame "card_large_selected" 320 480 $true $false
Create-Frame "card_large_locked" 320 480 $false $true
Create-Frame "card_wide_idle" 520 330 $false $false
Create-Frame "card_wide_selected" 520 330 $true $false
Create-Frame "save_card_idle" 300 560 $false $false
Create-Frame "save_card_selected" 300 560 $true $false
Create-Frame "inventory_slot_idle" 240 240 $false $false
Create-Frame "inventory_slot_selected" 240 240 $true $false
Create-Frame "panel_settings" 980 640 $false $false

Create-CardArt "tutorial_art" "tutorial" 1
Create-CardArt "level_01_variables" "level1" 2
Create-CardArt "level_02_if_else" "level2" 3
Create-CardArt "level_03_loops" "level3" 4
Create-CardArt "level_04_functions" "level4" 5
Create-CardArt "level_05_integration" "level5" 6
Create-CardArt "boss_01" "boss1" 11
Create-CardArt "boss_02" "boss2" 12
Create-CardArt "boss_03" "boss3" 13
Create-CardArt "boss_04" "boss4" 14
Create-CardArt "boss_05" "boss5" 15

Create-FontAtlas

$manifest = [ordered]@{
    generated_at = (Get-Date).ToString("s")
    style = "pixel fantasy menu, gold bevel frame, cyan selected glow, dark parchment panels"
    note = "Generated assets only; scenes are not wired yet."
    folders = @("backgrounds", "buttons", "cards", "card_art", "font")
    font = @{
        atlas = "font/skill_issue_ascii_gold.png"
        bmfont = "font/skill_issue_ascii_gold.fnt"
        ascii_cells = 128
        printable_range = "32-126"
    }
}
$manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $script:Root "asset_manifest.json") -Encoding UTF8

Create-PreviewSheet

Write-Host "Generated menu assets in $script:Root"
