#Requires -Version 7
# Renders the social-share images (og-fr.png, og-en.png) and the PNG icons with
# Microsoft Edge, from tools/og.html and static/favicon.svg. Run after changing
# either; the PNGs are committed so GitHub doesn't need Edge.
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$edge = @("${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $edge) { throw 'Microsoft Edge not found' }
$tmp = Join-Path ([IO.Path]::GetTempPath()) "mmrtb-img-$PID"; New-Item -ItemType Directory $tmp -Force | Out-Null

function Shot($html, $w, $h, $out) {
    $src = Join-Path $tmp 'page.html'
    [IO.File]::WriteAllText($src, $html, [Text.UTF8Encoding]::new($false))
    & $edge --headless=new --disable-gpu --hide-scrollbars --force-device-scale-factor=1 --user-data-dir="$tmp\profile" "--window-size=$w,$h" "--screenshot=$out" ([Uri]$src).AbsoluteUri 2>$null | Out-Null
    for ($i = 0; $i -lt 50 -and -not (Test-Path $out); $i++) { Start-Sleep -Milliseconds 200 }
    if (-not (Test-Path $out)) { throw "Edge did not write $out" }
}

$svg  = Get-Content (Join-Path $root 'static/favicon.svg') -Raw
$tpl  = Get-Content (Join-Path $PSScriptRoot 'og.html') -Raw
$text = @{
    fr = @{ title = 'Consultant TI pour PME'; sub = 'Virtualisation · Infonuagique · Réseautique · Cybersécurité'; area = 'Lanaudière · Laval · Montréal' }
    en = @{ title = 'IT consultant for SMBs'; sub = 'Virtualization · Cloud · Networking · Cybersecurity'; area = 'Lanaudière · Laval · Montréal' }
}
foreach ($l in 'fr', 'en') {
    $html = $tpl.Replace('{{logo}}', $svg).Replace('{{title}}', $text[$l].title).Replace('{{sub}}', $text[$l].sub).Replace('{{area}}', $text[$l].area)
    Shot $html 1200 630 (Join-Path $root "static/assets/og-$l.png")
}
foreach ($s in @(@{ n = 'apple-touch-icon.png'; px = 180 }, @{ n = 'favicon-32.png'; px = 32 })) {
    $html = "<!doctype html><style>html,body{margin:0;background:#0E1B2C}svg{display:block;width:$($s.px)px;height:$($s.px)px}</style>$($svg -replace 'rx=\"7\"', 'rx=\"0\"')"
    Shot $html $s.px $s.px (Join-Path $root "static/$($s.n)")
}
Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host 'Images written to static/'
