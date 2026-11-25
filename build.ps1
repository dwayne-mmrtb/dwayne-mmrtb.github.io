#Requires -Version 7
<#
  Builds the mmrtb.ca website into _site/.

  pages/fr/**.html and pages/en/**.html hold the page bodies, each starting with a
  small header between --- lines (title, description, alt = the other language's URL).
  layout.html wraps every page; site.json holds everything shared.

  Run locally:   pwsh -File build.ps1
  GitHub runs the same script on every push to main (.github/workflows/static.yml).
#>
param([string]$Out = (Join-Path $PSScriptRoot '_site'))
$ErrorActionPreference = 'Stop'
$root   = $PSScriptRoot
$site   = Get-Content (Join-Path $root 'site.json') -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
$layout = Get-Content (Join-Path $root 'layout.html') -Raw -Encoding utf8
$base   = $site.baseUrl.TrimEnd('/')
$today  = (Get-Date).ToString('yyyy-MM-dd')
$version = (Get-Date).ToString('yyyyMMddHHmm')

function Enc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function Fill([string]$text, [hashtable]$vars) {
    [regex]::Replace($text, '\{\{(\w+)\}\}', {
        param($m) $k = $m.Groups[1].Value
        if ($vars.ContainsKey($k)) { [string]$vars[$k] } else { throw "Unknown token {{$k}}" }
    })
}

# ---- read pages ---------------------------------------------------------------
$pages = foreach ($file in Get-ChildItem (Join-Path $root 'pages') -Recurse -Filter *.html) {
    $raw = Get-Content $file.FullName -Raw -Encoding utf8
    if ($raw -notmatch '(?s)\A---\r?\n(.*?)\r?\n---\r?\n(.*)\z') { throw "$($file.FullName): missing --- header" }
    $header = $Matches[1]; $body = $Matches[2]
    $fm = @{}
    foreach ($line in $header -split '\r?\n') {
        if ($line -match '^\s*(\w+)\s*:\s*(.*?)\s*$') { $fm[$Matches[1]] = $Matches[2] }
    }
    $rel  = [IO.Path]::GetRelativePath((Join-Path $root 'pages'), $file.FullName) -replace '\\', '/'
    $lang = $rel.Split('/')[0]
    if (-not $site.locales.ContainsKey($lang)) { throw "${rel}:unknown language folder '$lang'" }
    foreach ($k in 'title', 'description') { if (-not $fm[$k]) { throw "${rel}:'$k' is required" } }
    $slug = ($rel.Substring($lang.Length + 1) -replace '\.html$', '') -replace '(^|/)index$', ''
    $is404 = $slug -eq '404'
    $url = if ($is404) { '/404.html' } else { $site.locales[$lang].prefix + '/' + ($(if ($slug) { "$slug/" } else { '' })) }
    if ($fm.description.Length -gt 160) { Write-Warning "${rel}:description is $($fm.description.Length) chars (Google shows ~155)" }
    if ($fm.title.Length -gt 65)       { Write-Warning "${rel}:title is $($fm.title.Length) chars (Google shows ~60)" }
    [pscustomobject]@{ Rel = $rel; Lang = $lang; Url = $url; Fm = $fm; Body = $body; Is404 = $is404 }
}
$byUrl = @{}; foreach ($p in $pages) { $byUrl[$p.Url] = $p }

# every page must name its translation, and the translation must point back
foreach ($p in $pages | Where-Object { -not $_.Is404 }) {
    $alt = $p.Fm.alt
    if (-not $alt) { throw "$($p.Rel): 'alt' (the other language's URL) is required" }
    if (-not $byUrl.ContainsKey($alt)) { throw "$($p.Rel): alt '$alt' is not a page" }
    if ($byUrl[$alt].Fm.alt -ne $p.Url) { throw "$($p.Rel) -> $alt does not point back (it says '$($byUrl[$alt].Fm.alt)')" }
}

# ---- shared fragments ----------------------------------------------------------
function Icon($name) { "<span class=`"icon`" aria-hidden=`"true`"><svg viewBox=`"0 0 24 24`">$($site.icons[$name])</svg></span>" }

function ServiceCards($lang) {
    $items = foreach ($s in $site.services) {
        $t = $s[$lang]
        "<li class=`"card`">$(Icon $s.icon)<h3><a href=`"$($t.url)`">$(Enc $t.title)</a></h3><p>$(Enc $t.blurb)</p></li>"
    }
    "<ul class=`"cards`">$($items -join '')</ul>"
}

function ServiceNav($lang, $current) {
    $items = foreach ($s in $site.services) {
        $t = $s[$lang]; $cur = if ($t.url -eq $current) { ' aria-current="page"' } else { '' }
        "<li><a href=`"$($t.url)`"$cur>$(Enc $t.title)</a></li>"
    }
    "<ul>$($items -join '')</ul>"
}

function OrgNode {
    $org = [ordered]@{
        '@type'      = 'ProfessionalService'
        '@id'        = "$base/#org"
        name         = $site.name
        url          = "$base/"
        logo         = "$base/apple-touch-icon.png"
        image        = "$base/assets/og-fr.png"
        email        = $site.email
        description  = $site.locales.fr.tagline
        knowsLanguage = @('fr-CA', 'en-CA')
        areaServed   = @($site.areas | ForEach-Object { [ordered]@{ '@type' = 'Place'; name = $_ } })
        address      = [ordered]@{ '@type' = 'PostalAddress'; addressRegion = 'QC'; addressCountry = 'CA' }
    }
    if ($site.phone)        { $org.telephone = $site.phone }
    if ($site.foundingYear) { $org.foundingDate = $site.foundingYear }
    $same = @($site.linkedin) | Where-Object { $_ }
    if ($same) { $org.sameAs = @($same) }
    $org
}

# ---- render ----------------------------------------------------------------------
if (Test-Path $Out) { Remove-Item $Out -Recurse -Force }
New-Item -ItemType Directory $Out | Out-Null
Copy-Item (Join-Path $root 'static/*') $Out -Recurse -Force
Copy-Item (Join-Path $root 'CNAME') $Out

foreach ($p in $pages) {
    $L = $site.locales[$p.Lang]
    $fm = $p.Fm
    $altPage = if ($fm.alt) { $byUrl[$fm.alt] } else { $null }
    $altLang = if ($p.Lang -eq 'fr') { 'en' } else { 'fr' }
    $altUrl  = if ($altPage) { $altPage.Url } else { $site.locales[$altLang].prefix + '/' }
    $isService = $fm.type -eq 'service'

    # body tokens
    $bodyVars = @{
        services   = ServiceCards $p.Lang
        serviceNav = ServiceNav $p.Lang $p.Url
        areas      = '<ul class="areas">' + (($site.areas | ForEach-Object { "<li>$(Enc $_)</li>" }) -join '') + '</ul>'
        bookingUrl = $site.bookingUrl
        email      = $site.email
        cta        = Enc $L.cta
        ctaButtons = "<div class=`"btn-row`"><a class=`"btn btn-primary`" href=`"$($site.bookingUrl)`" rel=`"noopener`">$(Enc $L.cta)</a><a class=`"btn btn-ghost`" href=`"mailto:$($site.email)`">$(Enc $site.email)</a></div>"
    }
    foreach ($s in $site.services) { $bodyVars['svc_' + ($s.icon)] = $s[$p.Lang].url }
    $content = Fill $p.Body $bodyVars
    # French typography: never let : ; ? ! start a new line (space before them becomes non-breaking)
    if ($p.Lang -eq 'fr') { $content = [regex]::Replace($content, ' ([:;?!])(?=[\s<])', "`u{00A0}`$1") }

    # nav
    $nav = ($L.nav | ForEach-Object {
        $cur = if ($p.Url.StartsWith($_.url)) { ' aria-current="page"' } else { '' }
        "<a href=`"$($_.url)`"$cur>$(Enc $_.label)</a>"
    }) -join "`n      "

    # breadcrumb (service pages and inner pages)
    $crumbs = @()
    if ($p.Url -ne "$($L.prefix)/" -and -not $p.Is404) {
        $crumbs += , @($L.home, "$($L.prefix)/")
        if ($isService) { $crumbs += , @($L.servicesLabel, $L.servicesUrl) }
        $crumbs += , @(($fm.crumb ? $fm.crumb : $fm.title), $p.Url)
    }
    $breadcrumb = ''
    if ($crumbs.Count) {
        $lis = for ($i = 0; $i -lt $crumbs.Count; $i++) {
            if ($i -eq $crumbs.Count - 1) { "<li aria-current=`"page`">$(Enc $crumbs[$i][0])</li>" }
            else { "<li><a href=`"$($crumbs[$i][1])`">$(Enc $crumbs[$i][0])</a></li>" }
        }
        $breadcrumb = "<nav class=`"breadcrumb`" aria-label=`"Breadcrumb`"><div class=`"wrap`"><ol>$($lis -join '')</ol></div></nav>"
    }

    # structured data
    $graph = [System.Collections.Generic.List[object]]::new()
    $graph.Add((OrgNode))
    $graph.Add([ordered]@{ '@type' = 'WebSite'; '@id' = "$base/#site"; url = "$base/"; name = $site.name; inLanguage = @('fr-CA', 'en-CA'); publisher = @{ '@id' = "$base/#org" } })
    if ($isService) {
        $graph.Add([ordered]@{ '@type' = 'Service'; name = ($fm.crumb ? $fm.crumb : $fm.title); description = $fm.description; url = "$base$($p.Url)"; inLanguage = $L.htmlLang; provider = @{ '@id' = "$base/#org" }; areaServed = @($site.areas) })
    }
    if ($crumbs.Count) {
        $pos = 0
        $graph.Add([ordered]@{ '@type' = 'BreadcrumbList'; itemListElement = @($crumbs | ForEach-Object { $pos++; [ordered]@{ '@type' = 'ListItem'; position = $pos; name = $_[0]; item = "$base$($_[1])" } }) })
    }
    $jsonld = ([ordered]@{ '@context' = 'https://schema.org'; '@graph' = $graph } | ConvertTo-Json -Depth 12 -Compress) -replace '</', '<\/'

    # hreflang
    $hreflang = ''
    if ($altPage) {
        $fr = if ($p.Lang -eq 'fr') { $p.Url } else { $altPage.Url }
        $en = if ($p.Lang -eq 'en') { $p.Url } else { $altPage.Url }
        $hreflang = "<link rel=`"alternate`" hreflang=`"fr-CA`" href=`"$base$fr`">`n<link rel=`"alternate`" hreflang=`"en-CA`" href=`"$base$en`">`n<link rel=`"alternate`" hreflang=`"x-default`" href=`"$base$fr`">"
    }

    # CTA band
    $ctaBand = if ($fm.nocta -eq 'true' -or $p.Is404) { '' } else {
        "<section class=`"cta-band`"><div class=`"wrap`"><div><h2>$(Enc $L.ctaBandTitle)</h2><p>$(Enc $L.ctaBandText)</p></div>$($bodyVars.ctaButtons)</div></section>"
    }

    $footerServiceLinks = ($site.services | ForEach-Object { "<li><a href=`"$($_[$p.Lang].url)`">$(Enc $_[$p.Lang].title)</a></li>" }) -join ''
    $contactLinks = @("<li><a href=`"mailto:$($site.email)`">$(Enc $site.email)</a></li>")
    if ($site.phone)    { $contactLinks += "<li><a href=`"tel:$($site.phone -replace '[^\d+]', '')`">$(Enc $site.phone)</a></li>" }
    $contactLinks += "<li><a href=`"$($site.bookingUrl)`" rel=`"noopener`">$(Enc $L.cta)</a></li>"
    if ($site.linkedin) { $contactLinks += "<li><a href=`"$($site.linkedin)`" rel=`"noopener`">LinkedIn</a></li>" }

    $html = Fill $layout @{
        htmlLang = $L.htmlLang; lang = $p.Lang; ogLocale = $L.ogLocale
        title = Enc $fm.title; description = Enc $fm.description
        canonical = "$base$($p.Url)"; baseUrl = $base; hreflang = $hreflang
        siteName = Enc $site.name; tagline = Enc $L.tagline; home = Enc $L.home
        homeUrl = "$($L.prefix)/"; skip = Enc $L.skip; menu = Enc $L.menu
        nav = $nav; altUrl = $altUrl; altLang = $site.locales[$altLang].htmlLang
        switchLabel = $L.switchLabel; switchTitle = Enc $L.switchTitle
        bookingUrl = $site.bookingUrl; cta = Enc $L.cta
        breadcrumb = $breadcrumb; content = $content; ctaBand = $ctaBand
        footerServices = Enc $L.footerServices; footerServiceLinks = $footerServiceLinks
        footerAreas = Enc $L.footerAreas; footerAreasText = Enc $L.footerAreasText
        footerContact = Enc $L.footerContact; footerContactLinks = ($contactLinks -join '')
        year = (Get-Date).Year; rights = Enc $L.rights
        jsonld = $jsonld; version = $version
    }
    if ($p.Is404) { $html = $html -replace '<link rel="canonical"[^>]*>', '<meta name="robots" content="noindex">' }

    $dest = if ($p.Is404) { Join-Path $Out '404.html' } else { Join-Path $Out ($p.Url.TrimStart('/') + 'index.html') }
    New-Item -ItemType Directory (Split-Path $dest) -Force | Out-Null
    [IO.File]::WriteAllText($dest, $html, [Text.UTF8Encoding]::new($false))
}

# ---- sitemap + robots ----------------------------------------------------------------
$entries = foreach ($p in $pages | Where-Object { -not $_.Is404 } | Sort-Object Url) {
    $alt = $byUrl[$p.Fm.alt]
    $fr = if ($p.Lang -eq 'fr') { $p.Url } else { $alt.Url }
    $en = if ($p.Lang -eq 'en') { $p.Url } else { $alt.Url }
    @"
  <url>
    <loc>$base$($p.Url)</loc>
    <lastmod>$today</lastmod>
    <xhtml:link rel="alternate" hreflang="fr-CA" href="$base$fr"/>
    <xhtml:link rel="alternate" hreflang="en-CA" href="$base$en"/>
    <xhtml:link rel="alternate" hreflang="x-default" href="$base$fr"/>
  </url>
"@
}
$sitemap = "<?xml version=`"1.0`" encoding=`"UTF-8`"?>`n<urlset xmlns=`"http://www.sitemaps.org/schemas/sitemap/0.9`" xmlns:xhtml=`"http://www.w3.org/1999/xhtml`">`n$($entries -join "`n")`n</urlset>`n"
[IO.File]::WriteAllText((Join-Path $Out 'sitemap.xml'), $sitemap, [Text.UTF8Encoding]::new($false))
[IO.File]::WriteAllText((Join-Path $Out 'robots.txt'), "User-agent: *`nAllow: /`n`nSitemap: $base/sitemap.xml`n", [Text.UTF8Encoding]::new($false))

Write-Host "Built $($pages.Count) pages into $Out"
