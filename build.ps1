# ============================================================
# Dayı Sigorta - Statik Site Üretim Betiği (PowerShell 5.1+)
# Kullanım:  powershell -ExecutionPolicy Bypass -File build.ps1
# Çıktı:     dist/ klasörü (yayınlanacak tüm dosyalar)
# ============================================================
$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $root "src"
$dist = Join-Path $root "dist"

if (Test-Path $dist) { Remove-Item $dist -Recurse -Force }
New-Item -ItemType Directory -Path $dist | Out-Null

# ---------- 1) Yapılandırma ----------
$configRaw = Get-Content (Join-Path $root "site.config.json") -Raw -Encoding UTF8
$config    = $configRaw | ConvertFrom-Json

# ---------- 2) Token haritası ----------
$tokens = @{
    "SITE_URL"          = $config.siteUrl
    "BRAND"             = $config.brand
    "LEGAL_NAME"        = $config.legalName
    "FOUNDED_YEAR"      = $config.foundedYear
    "CITY"              = $config.city
    "SERVICE_REGION"    = $config.serviceRegion
    "SEDDK_LICENSE"     = $config.seddkLicense
    "SEDDK_LICENSE_SHORT" = $config.seddkLicenseShort
    "SEDDK_URL"         = $config.seddkUrl
    "ADDRESS"           = $config.address.full
    "STREET"            = $config.address.street
    "DISTRICT"          = $config.address.district
    "ADDRESS_CITY"      = $config.address.city
    "POSTAL_CODE"       = $config.address.postalCode
    "PHONE"             = $config.phone
    "PHONE_HREF"        = $config.phoneHref
    "WHATSAPP"          = $config.whatsapp
    "WHATSAPP_HREF"     = $config.whatsappHref
    "EMAIL"             = $config.email
    "OPENING_HOURS"     = $config.openingHours
    "INSURERS_CSV"      = ($config.insurers -join ", ")
    "INSURERS_LIST"     = ($config.insurers | ForEach-Object { "<li>$_</li>" }) -join ""
    "DIFF_EXPERIENCE"   = $config.diff.experience
    "DIFF_CLIENTS"      = $config.diff.clients
    "DIFF_SUPPORT"      = $config.diff.support
    "DIFF_COMPARISON"   = $config.diff.comparison
    "SITE_UPDATED"      = $config.siteUpdated
    "SITE_UPDATED_ISO"  = $config.siteUpdatedIso
    "KVKK_URL"          = $config.kvkkUrl
    "CEREZ_URL"         = $config.cerezUrl
    "GOOGLE_MAPS_EMBED" = $config.googleMapsEmbed
    "FORM_ENDPOINT"     = $config.formEndpoint
}
$i = 1
foreach ($a in $config.authors) {
    $tokens["AUTHOR${i}_NAME"]  = $a.name
    $tokens["AUTHOR${i}_TITLE"] = $a.title
    $tokens["AUTHOR${i}_BIO"]   = $a.bio
    $i++
}

function Format-Tokens([string]$text, $map) {
    return [regex]::Replace($text, '\{\{([A-Z0-9_]+)\}\}', {
        param($m)
        $k = $m.Groups[1].Value
        if ($map.ContainsKey($k)) { return [string]$map[$k] }
        return $m.Value
    })
}

# ---------- 3) Kurumsal JSON-LD (tüm sayfalarda head içinde) ----------
$orgSchema = @'
{
  "@context": "https://schema.org",
  "@graph": [
    {
      "@type": "InsuranceAgency",
      "@id": "{{SITE_URL}}/#organization",
      "name": "{{BRAND}}",
      "legalName": "{{LEGAL_NAME}}",
      "url": "{{SITE_URL}}/",
      "foundingDate": "{{FOUNDED_YEAR}}",
      "description": "{{CITY}} merkezli, SEDDK lisanslı sigorta brokerliği. Kasko, trafik, konut, DASK, sağlık, ferdi kaza, işyeri, nakliyat, sorumluluk ve mühendislik sigortalarında {{INSURERS_CSV}} ve diğer şirketlerden fiyat karşılaştırması sunar.",
      "telephone": "{{PHONE}}",
      "email": "{{EMAIL}}",
      "areaServed": { "@type": "Country", "name": "Türkiye" },
      "identifier": {
        "@type": "PropertyValue",
        "name": "SEDDK Sigorta Aracılık Faaliyet Belgesi No",
        "value": "0000000"
      },
      "address": {
        "@type": "PostalAddress",
        "streetAddress": "{{STREET}}",
        "addressLocality": "{{ADDRESS_CITY}}",
        "addressRegion": "{{DISTRICT}}",
        "postalCode": "{{POSTAL_CODE}}",
        "addressCountry": "TR"
      },
      "openingHours": "{{OPENING_HOURS}}",
      "hasMap": "{{GOOGLE_MAPS_EMBED}}",
      "knowsLanguage": ["tr", "en"],
      "contactPoint": {
        "@type": "ContactPoint",
        "contactType": "hasar bildirimi ve teklif",
        "telephone": "{{PHONE}}",
        "email": "{{EMAIL}}",
        "availableLanguage": ["Turkish"]
      }
    },
    {
      "@type": "WebSite",
      "@id": "{{SITE_URL}}/#website",
      "url": "{{SITE_URL}}/",
      "name": "{{BRAND}}",
      "publisher": { "@id": "{{SITE_URL}}/#organization" },
      "inLanguage": "tr"
    }
  ]
}
'@
$orgSchemaJson = (Format-Tokens $orgSchema $tokens) -replace '\s+', ' '

# ---------- 4) Kısmi şablonlar ----------
$header = Get-Content (Join-Path $src "partials\header.html") -Raw -Encoding UTF8
$footer = Get-Content (Join-Path $src "partials\footer.html") -Raw -Encoding UTF8

# ---------- 5) Sayfaları üret ----------
$pages = Get-ChildItem (Join-Path $src "pages") -Recurse -Filter *.html
$sitemapEntries = @()

foreach ($page in $pages) {
    $raw = Get-Content $page.FullName -Raw -Encoding UTF8

    # İlk satırdaki meta JSON'u ayıkla: <!--{...}-->
    if ($raw -notmatch '(?s)\A<!--\s*(\{.*?\})\s*-->\s*(.*)\z') {
        Write-Warning "Meta bloğu yok: $($page.Name) — sayfa atlandı."
        continue
    }
    $meta     = $Matches[1] | ConvertFrom-Json
    $content  = $Matches[2]

    # Meta title/description içindeki token'ları da çöz (ör. "{{BRAND}} | Hakkımızda")
    $meta.title       = Format-Tokens ([string]$meta.title) $tokens
    $meta.description = Format-Tokens ([string]$meta.description) $tokens

    $path     = $meta.path
    $noindex  = ""
    if ($meta.noindex) { $noindex = '<meta name="robots" content="noindex, follow">' }

    $pageTokens = @{
        "PAGE_TITLE"       = $meta.title
        "PAGE_DESCRIPTION" = $meta.description
        "PAGE_CANONICAL"   = $config.siteUrl + $path
        "PAGE_NOINDEX"     = $noindex
        "PAGE_ORG_SCHEMA"  = $orgSchemaJson
    }
    $merged = @{ }
    foreach ($k in $tokens.Keys)  { $merged[$k] = $tokens[$k] }
    foreach ($k in $pageTokens.Keys) { $merged[$k] = $pageTokens[$k] }

    $html = Format-Tokens ($header + $content + $footer) $merged

    # Çıktı yolu: "/hizmetler/kasko-sigortasi/" -> dist\hizmetler\kasko-sigortasi\index.html
    if ($path.EndsWith(".html")) {
        $outFile = Join-Path $dist ($path.TrimStart("/") -replace "/", "\")
    } else {
        $outFile = Join-Path (Join-Path $dist ($path.TrimStart("/") -replace "/", "\")) "index.html"
    }
    $outDir = Split-Path $outFile -Parent
    if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
    [System.IO.File]::WriteAllText($outFile, $html, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "  üretildi: $($path)"

    if ($meta.sitemap -ne $false) {
        $sitemapEntries += [PSCustomObject]@{
            loc        = $config.siteUrl + $path
            changefreq = if ($meta.changefreq) { $meta.changefreq } else { "monthly" }
            priority   = if ($meta.priority)  { $meta.priority }  else { "0.6" }
            lastmod    = $config.siteUpdatedIso
        }
    }
}

# ---------- 6) sitemap.xml ----------
$ns = 'http://www.sitemaps.org/schemas/sitemap/0.9'
$lines = @('<?xml version="1.0" encoding="UTF-8"?>', "<urlset xmlns=`"$ns`">")
foreach ($e in $sitemapEntries) {
    $lines += ""
    $lines += "  <url>"
    $lines += "    <loc>$($e.loc)</loc>"
    $lines += "    <lastmod>$($e.lastmod)</lastmod>"
    $lines += "    <changefreq>$($e.changefreq)</changefreq>"
    $lines += "    <priority>$($e.priority)</priority>"
    $lines += "  </url>"
}
$lines += "</urlset>"
[System.IO.File]::WriteAllText((Join-Path $dist "sitemap.xml"), ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))

# ---------- 7) robots.txt + llms.txt + CSS ----------
Copy-Item (Join-Path $src "assets") $dist -Recurse -Force
foreach ($f in @("robots.txt", "llms.txt")) {
    $t = Get-Content (Join-Path $src $f) -Raw -Encoding UTF8
    [System.IO.File]::WriteAllText((Join-Path $dist $f), (Format-Tokens $t $tokens), (New-Object System.Text.UTF8Encoding($false)))
}

Write-Host ""
Write-Host "✅ Build tamamlandı -> $dist ($($pages.Count) sayfa, $($sitemapEntries.Count) sitemap girdisi)"
