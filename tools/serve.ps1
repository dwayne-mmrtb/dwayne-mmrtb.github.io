#Requires -Version 7
# Builds the site, then serves _site/ at http://localhost:8642 for previewing.
param([int]$Port = ($env:PORT ? [int]$env:PORT : 8642))
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
& (Join-Path $root 'build.ps1')
$site = Join-Path $root '_site'
$types = @{ '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.xml' = 'application/xml'; '.txt' = 'text/plain'; '.js' = 'text/javascript' }
$listener = [Net.HttpListener]::new(); $listener.Prefixes.Add("http://localhost:$Port/"); $listener.Start()
Write-Host "Serving $site at http://localhost:$Port/"
while ($listener.IsListening) {
    $ctx = $listener.GetContext()
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
    if ($path.EndsWith('/')) { $path += 'index.html' }
    $file = Join-Path $site $path.TrimStart('/')
    $status = 200
    if (-not (Test-Path $file -PathType Leaf) -or -not ([IO.Path]::GetFullPath($file)).StartsWith($site)) { $file = Join-Path $site '404.html'; $status = 404 }
    try {
        $bytes = [IO.File]::ReadAllBytes($file)
        $ctx.Response.StatusCode = $status
        $ctx.Response.ContentType = $types[[IO.Path]::GetExtension($file)] ?? 'application/octet-stream'
        $ctx.Response.ContentLength64 = $bytes.Length
        if ($ctx.Request.HttpMethod -ne 'HEAD') { $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length) }
    } catch { Write-Warning "$path : $_" }
    finally { $ctx.Response.Close() }
}
