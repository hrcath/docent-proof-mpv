<#
  Docent-Proof MPV - configuration web panel
  ---------------------------------------------------------------
  Serves a small web page at http://<this-PC-IP>:<Port>/ where staff can:
    * pick the featured video  (moves it into dp-videos\featured and moves the
      previous one back to dp-videos)
    * pick the screen image     (writes its name to docent-proof\logo.txt)

  Works with the PowerShell 5.1 that ships with Windows 11 - nothing to install.
  Run setup.ps1 once as Administrator so other devices can reach the page.
#>
param(
    [int]   $Port    = 8080,
    [string]$BaseDir = (Join-Path $env:USERPROFILE 'Videos\docent-proof'),
    [string]$Pin     = ''          # optional: require this PIN to save changes
)

$ErrorActionPreference = 'Stop'
$VideoDir    = Join-Path $BaseDir 'dp-videos'
$FeaturedDir = Join-Path $VideoDir 'featured'
$LogoSetting = Join-Path $BaseDir 'logo.txt'
$AddrFile    = Join-Path $BaseDir 'config-address.txt'
$LogFile     = Join-Path $PSScriptRoot 'config-server.log'
$Utf8NoBom   = New-Object System.Text.UTF8Encoding($false)

$VideoExt = @('.mp4','.m4v','.mov','.mkv','.webm','.avi','.wmv','.mpg','.mpeg','.ts')
$ImageMime = @{
    '.jpg'='image/jpeg'; '.jpeg'='image/jpeg'; '.png'='image/png'; '.bmp'='image/bmp'
    '.gif'='image/gif';  '.webp'='image/webp'; '.tif'='image/tiff'; '.tiff'='image/tiff'
}

function Write-Log([string]$text) {
    try {
        if ((Test-Path -LiteralPath $LogFile) -and (Get-Item -LiteralPath $LogFile).Length -gt 1MB) {
            Remove-Item -LiteralPath $LogFile -Force
        }
        Add-Content -LiteralPath $LogFile -Value ("{0:yyyy-MM-dd HH:mm:ss}  {1}" -f (Get-Date), $text)
    } catch { }
}

foreach ($d in $BaseDir, $VideoDir, $FeaturedDir) {
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
}

# ---------------------------------------------------------------- files
function Get-Files([string]$dir, [string[]]$exts) {
    @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue |
        Where-Object { $exts -contains $_.Extension.ToLower() } |
        Sort-Object Name)
}
function Get-Videos   { Get-Files $VideoDir    $VideoExt }
function Get-Featured { Get-Files $FeaturedDir $VideoExt }
function Get-Images   { Get-Files $BaseDir     @($ImageMime.Keys) }

# Current screen image: logo.txt if valid, otherwise the first image (and save
# that choice, so the player and this page always agree).
function Get-CurrentLogo {
    $images = Get-Images
    if ($images.Count -eq 0) { return $null }
    $want = ''
    if (Test-Path -LiteralPath $LogoSetting) {
        $want = ([IO.File]::ReadAllText($LogoSetting, [Text.Encoding]::UTF8)).Trim()
    }
    $match = $images | Where-Object { $_.Name -eq $want } | Select-Object -First 1
    if ($match) { return $match.Name }
    Set-Logo $images[0].Name | Out-Null
    return $images[0].Name
}

function Set-Logo([string]$name) {
    if (-not ((Get-Images) | Where-Object { $_.Name -eq $name })) { throw "Image not found: $name" }
    [IO.File]::WriteAllText($LogoSetting, $name, $Utf8NoBom)
    Write-Log "Logo set to '$name'"
    "Screen image changed to '$name'."
}

function Set-Featured([string]$name) {
    $current = Get-Featured
    if ($current | Where-Object { $_.Name -eq $name }) { return "'$name' is already the featured video." }
    $src = (Get-Videos) | Where-Object { $_.Name -eq $name } | Select-Object -First 1
    if (-not $src) { throw "Video not found: $name" }

    $undo = New-Object System.Collections.ArrayList
    try {
        foreach ($c in $current) {
            $dest = Join-Path $VideoDir $c.Name
            if (Test-Path -LiteralPath $dest) { throw "A file named '$($c.Name)' already exists in dp-videos." }
            Move-Item -LiteralPath $c.FullName -Destination $dest
            [void]$undo.Add(@($dest, $c.FullName))
        }
        Move-Item -LiteralPath $src.FullName -Destination (Join-Path $FeaturedDir $src.Name)
    } catch {
        foreach ($u in $undo) { try { Move-Item -LiteralPath $u[0] -Destination $u[1] } catch { } }
        if ($_.Exception -is [System.IO.IOException]) {
            throw "Couldn't move the file - the video is probably playing right now. Wait for it to finish (or press Back on the clicker) and try again."
        }
        throw
    }
    Write-Log "Featured video set to '$name'"
    "Now featuring '$name'. It will play on the next click."
}

# ---------------------------------------------------------------- html
function HtmlEnc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function UrlEnc([string]$s) { [Uri]::EscapeDataString($s) }
function Format-Size([long]$b) {
    if ($b -ge 1GB) { '{0:N1} GB' -f ($b / 1GB) } else { '{0:N0} MB' -f [Math]::Max(1, $b / 1MB) }
}

function Render-Page([string]$note, [string]$err) {
    $featured = Get-Featured
    $featName = if ($featured.Count) { $featured[0].Name } else { '' }
    $all = @($featured) + @(Get-Videos)
    $logo = Get-CurrentLogo
    $pinField = if ($Pin) { '<input type="password" name="pin" placeholder="PIN" inputmode="numeric" required>' } else { '' }

    $vrows = foreach ($v in $all) {
        $chk = if ($v.Name -eq $featName) { 'checked' } else { '' }
        $tag = if ($v.Name -eq $featName) { '<span class="tag">featured</span>' } else { '' }
        "<label class='row'><input type='radio' name='video' value='$(HtmlEnc $v.Name)' $chk required><span class='name'>$(HtmlEnc $v.Name)</span>$tag<span class='size'>$(Format-Size $v.Length)</span></label>"
    }
    if (-not $all.Count) { $vrows = "<p class='empty'>No videos found in $(HtmlEnc $VideoDir)</p>" }

    $irows = foreach ($i in Get-Images) {
        $chk = if ($i.Name -eq $logo) { 'checked' } else { '' }
        "<label class='tile'><input type='radio' name='logo' value='$(HtmlEnc $i.Name)' $chk required><img src='/image?f=$(UrlEnc $i.Name)' alt='' loading='lazy'><span>$(HtmlEnc $i.Name)</span></label>"
    }
    if (-not $irows) { $irows = "<p class='empty'>No images found in $(HtmlEnc $BaseDir)</p>" }

    $banner = ''
    if ($note) { $banner = "<div class='ok'>$(HtmlEnc $note)</div>" }
    if ($err)  { $banner = "<div class='err'>$(HtmlEnc $err)</div>" }

@"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Docent-Proof MPV</title>
<style>
 body{font-family:system-ui,Segoe UI,sans-serif;margin:0;background:#f4f4f2;color:#222}
 main{max-width:760px;margin:auto;padding:16px}
 h1{font-size:1.4rem;margin:.2em 0 .6em} h2{font-size:1.1rem;margin:0 0 .6em}
 section{background:#fff;border-radius:10px;padding:16px;margin-bottom:16px;box-shadow:0 1px 3px #0002}
 .row{display:flex;align-items:center;gap:10px;padding:10px 6px;border-bottom:1px solid #eee;cursor:pointer}
 .row:last-of-type{border-bottom:0}
 .row input{width:20px;height:20px;flex:none}
 .name{flex:1;word-break:break-all} .size{color:#888;font-size:.85em;white-space:nowrap}
 .tag{background:#1b6e3a;color:#fff;border-radius:4px;padding:1px 6px;font-size:.75em}
 .grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px}
 .tile{display:flex;flex-direction:column;gap:4px;border:3px solid transparent;border-radius:8px;padding:4px;cursor:pointer;font-size:.8em;word-break:break-all}
 .tile input{display:none} .tile:has(input:checked){border-color:#1b6e3a;background:#e8f3ec}
 .tile img{width:100%;aspect-ratio:16/9;object-fit:contain;background:#000;border-radius:4px}
 .actions{display:flex;gap:10px;margin-top:12px;flex-wrap:wrap}
 button{background:#1b6e3a;color:#fff;border:0;border-radius:6px;padding:10px 18px;font-size:1rem;cursor:pointer}
 input[type=password]{padding:9px;border:1px solid #ccc;border-radius:6px;width:110px}
 .ok,.err{padding:10px 14px;border-radius:8px;margin-bottom:16px} .ok{background:#e3f4e8} .err{background:#fbe4e4}
 .empty{color:#888} footer{color:#999;font-size:.8em;text-align:center}
</style></head><body><main>
<h1>Docent-Proof MPV &middot; Settings</h1>
$banner
<section><h2>Featured video</h2>
<form method="post" action="/feature">
$($vrows -join "`n")
<div class="actions">$pinField<button type="submit">Feature this video</button></div>
</form></section>
<section><h2>Screen image</h2>
<form method="post" action="/logo"><div class="grid">
$($irows -join "`n")
</div><div class="actions">$pinField<button type="submit">Use this image</button></div>
</form></section>
<footer>To add videos or images, copy them into $(HtmlEnc $BaseDir) on this computer, then reload this page.</footer>
</main></body></html>
"@
}

# ---------------------------------------------------------------- http
function Parse-Form([string]$s) {
    $h = @{}
    if ([string]::IsNullOrEmpty($s)) { return $h }
    foreach ($pair in $s.Split('&')) {
        if (-not $pair) { continue }
        $kv = $pair.Split('=', 2)
        $k = [Uri]::UnescapeDataString($kv[0].Replace('+', ' '))
        $v = if ($kv.Count -gt 1) { [Uri]::UnescapeDataString($kv[1].Replace('+', ' ')) } else { '' }
        $h[$k] = $v
    }
    return $h
}

function Send($ctx, [int]$code, [string]$type, [byte[]]$bytes) {
    $r = $ctx.Response
    $r.StatusCode = $code
    $r.ContentType = $type
    $r.Headers['Cache-Control'] = 'no-store'
    $r.ContentLength64 = $bytes.Length
    if ($bytes.Length) { $r.OutputStream.Write($bytes, 0, $bytes.Length) }
}
function Send-Html($ctx, [string]$html, [int]$code = 200) {
    Send $ctx $code 'text/html; charset=utf-8' $Utf8NoBom.GetBytes($html)
}
function Redirect($ctx, [string]$key, [string]$text) {
    $ctx.Response.StatusCode = 303
    $ctx.Response.RedirectLocation = "/?$key=$(UrlEnc $text)"
}

function Handle-Request($ctx) {
    $req = $ctx.Request
    $raw = $req.RawUrl
    $q = $raw.IndexOf('?')
    $path  = if ($q -ge 0) { $raw.Substring(0, $q) } else { $raw }
    $query = Parse-Form $(if ($q -ge 0) { $raw.Substring($q + 1) } else { '' })
    $form = @{}
    if ($req.HttpMethod -eq 'POST') {
        $reader = New-Object System.IO.StreamReader($req.InputStream, [Text.Encoding]::UTF8)
        $form = Parse-Form $reader.ReadToEnd()
        $reader.Close()
    }

    switch ($path) {
        '/' { Send-Html $ctx (Render-Page $query['msg'] $query['err']); return }

        '/image' {
            $img = (Get-Images) | Where-Object { $_.Name -eq $query['f'] } | Select-Object -First 1
            if (-not $img) { Send-Html $ctx 'Not found' 404; return }
            Send $ctx 200 $ImageMime[$img.Extension.ToLower()] ([IO.File]::ReadAllBytes($img.FullName))
            return
        }

        { $_ -in '/feature', '/logo' } {
            if ($req.HttpMethod -ne 'POST') { Redirect $ctx 'err' 'Use the buttons on the page.'; return }
            if ($Pin -and $form['pin'] -ne $Pin) { Redirect $ctx 'err' 'Wrong PIN.'; return }
            try {
                $result = if ($path -eq '/feature') { Set-Featured $form['video'] } else { Set-Logo $form['logo'] }
                Redirect $ctx 'msg' $result
            } catch {
                Write-Log "Error: $($_.Exception.Message)"
                Redirect $ctx 'err' $_.Exception.Message
            }
            return
        }

        '/favicon.ico' { Send $ctx 204 'text/plain' ([byte[]]@()); return }
        default        { Send-Html $ctx 'Not found' 404 }
    }
}

# ---------------------------------------------------------------- main
function Get-LanAddresses {
    $ips = @()
    try {
        $ips = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
            Select-Object -ExpandProperty IPAddress)
    } catch {
        $ips = @([System.Net.Dns]::GetHostAddresses([System.Net.Dns]::GetHostName()) |
            Where-Object { $_.AddressFamily -eq 'InterNetwork' -and -not $_.ToString().StartsWith('127.') } |
            ForEach-Object { $_.ToString() })
    }
    $ips
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://+:$Port/")
try {
    $listener.Start()
} catch {
    # Not set up for network access (run setup.ps1 as Administrator) - fall back
    # to this PC only so the player still works.
    Write-Log "Could not listen on all addresses ($($_.Exception.Message)). Falling back to localhost only. Run setup.ps1 as Administrator."
    $listener = New-Object System.Net.HttpListener
    $listener.Prefixes.Add("http://localhost:$Port/")
    try { $listener.Start() } catch {
        Write-Log "Could not start on port $Port ($($_.Exception.Message)). Is another copy already running?"
        exit 1
    }
}

$urls = @(Get-LanAddresses | ForEach-Object { "http://${_}:$Port/" })
if ($env:COMPUTERNAME) { $urls += "http://$($env:COMPUTERNAME):$Port/" }
[IO.File]::WriteAllText($AddrFile, ($urls -join "`r`n"), $Utf8NoBom)
Write-Log ("Config panel running: " + ($urls -join '  '))
Get-CurrentLogo | Out-Null

while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    try {
        Handle-Request $ctx
    } catch {
        Write-Log "Request error: $($_.Exception.Message)"
        try { Send-Html $ctx 'Server error' 500 } catch { }
    } finally {
        try { $ctx.Response.Close() } catch { }
    }
}
