# Builds the website into _site.
# Works in Windows PowerShell 5.1 (local preview) and PowerShell 7 (GitHub Actions).
# Keep this file ASCII-only: Windows PowerShell reads scripts without a BOM as ANSI.
param([string]$Out = '_site')
$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutDir = [IO.Path]::Combine($Root, $Out)
$Utf8 = New-Object System.Text.UTF8Encoding($false)
$Inv = [Globalization.CultureInfo]::InvariantCulture

function Read-Text([string]$Path) { [IO.File]::ReadAllText($Path, $Utf8) }
function Write-Text([string]$Path, [string]$Text) {
  $dir = [IO.Path]::GetDirectoryName($Path)
  if (-not [IO.Directory]::Exists($dir)) { [void][IO.Directory]::CreateDirectory($dir) }
  [IO.File]::WriteAllText($Path, $Text, $Utf8)
}
function Enc([string]$s) { [System.Net.WebUtility]::HtmlEncode($s) }
function Fill([string]$Tpl, [hashtable]$Vals) {
  foreach ($k in $Vals.Keys) { $Tpl = $Tpl.Replace('{{' + $k + '}}', [string]$Vals[$k]) }
  return $Tpl
}
function Get-Template([string]$Name) { Read-Text ([IO.Path]::Combine($Root, 'templates', $Name)) }
function Get-Json([string]$Rel) { (Read-Text ([IO.Path]::Combine($Root, $Rel))) | ConvertFrom-Json }

# ---------- Markdown (the subset the admin page writes) ----------
function Convert-Inline([string]$t) {
  $t = Enc $t
  $t = [regex]::Replace($t, '!\[([^\]]*)\]\(([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\)', '<img src="$2" alt="$1" loading="lazy">')
  $t = [regex]::Replace($t, '\[([^\]]+)\]\(([^)\s]+)(?:\s+&quot;[^&]*&quot;)?\)', '<a href="$2">$1</a>')
  $t = [regex]::Replace($t, '\*\*(.+?)\*\*', '<strong>$1</strong>')
  $t = [regex]::Replace($t, '(?<![\*\w])\*(?!\s)(.+?)(?<!\s)\*(?![\*\w])', '<em>$1</em>')
  $t = [regex]::Replace($t, '(?<!\w)_(?!\s)(.+?)(?<!\s)_(?!\w)', '<em>$1</em>')
  $t = [regex]::Replace($t, '==(.+?)==', '<mark>$1</mark>')
  $t = [regex]::Replace($t, '`([^`]+)`', '<code>$1</code>')
  return $t
}
function Convert-Markdown([string]$md) {
  $md = ($md -replace "`r`n", "`n").Trim()
  if (-not $md) { return '' }
  $out = New-Object System.Collections.Generic.List[string]
  $items = New-Object System.Collections.Generic.List[string]
  $listType = $null
  foreach ($b in [regex]::Split($md, "`n[ \t]*`n")) {
    $ls = @($b -split "`n")
    $first = $ls[0]
    $type = 'p'
    if ($first -match '^\s*[-*+]\s+') { $type = 'ul' } elseif ($first -match '^\s*\d+[.)]\s+') { $type = 'ol' }
    if ($listType -and $type -ne $listType) { $out.Add("<$listType>" + ($items -join '') + "</$listType>"); $items.Clear(); $listType = $null }
    if ($ls.Count -eq 1 -and $first.Trim() -match '^\{\{chart:([a-z0-9-]+)\}\}$') {
      $chartFile = [IO.Path]::Combine($Root, 'content', 'charts', $matches[1] + '.html')
      if ([IO.File]::Exists($chartFile)) { $out.Add((Read-Text $chartFile).Trim()) }
      continue
    }
    if ($type -ne 'p') {
      $listType = $type; $cur = $null
      foreach ($l in $ls) {
        if ($l -match '^\s*(?:[-*+]|\d+[.)])\s+(.*)$') { if ($null -ne $cur) { $items.Add('<li>' + (Convert-Inline $cur) + '</li>') }; $cur = $matches[1] }
        else { $cur = $cur + ' ' + $l.Trim() }
      }
      if ($null -ne $cur) { $items.Add('<li>' + (Convert-Inline $cur) + '</li>') }
      continue
    }
    if ($ls.Count -eq 1 -and $first -match '^(#{1,6})\s+(.*)$') { $n = $matches[1].Length; $out.Add("<h$n>" + (Convert-Inline $matches[2]) + "</h$n>"); continue }
    if ($b.Trim() -match '^(-{3,}|\*{3,}|_{3,})$') { $out.Add('<hr>'); continue }
    if ($first -match '^>') {
      $inner = ($ls | ForEach-Object { $_ -replace '^>\s?', '' }) -join "`n"
      $out.Add('<blockquote>' + (Convert-Markdown $inner) + '</blockquote>'); continue
    }
    if ($ls.Count -eq 1 -and $first.Trim() -match '^!\[([^\]]*)\]\(([^)\s]+)\)$') {
      $out.Add('<figure><img src="' + (Enc $matches[2]) + '" alt="' + (Enc $matches[1]) + '" loading="lazy"></figure>'); continue
    }
    $text = ($ls | ForEach-Object { if ($_ -match '  $') { (Convert-Inline $_.Trim()) + '<br>' } else { Convert-Inline $_.Trim() } }) -join "`n"
    $out.Add("<p>$text</p>")
  }
  if ($listType) { $out.Add("<$listType>" + ($items -join '') + "</$listType>") }
  return ($out -join "`n")
}

# ---------- Front matter ----------
function Read-Entry([string]$Path) {
  $raw = (Read-Text $Path) -replace "`r`n", "`n"
  $meta = @{}; $body = $raw
  if ($raw.StartsWith("---`n")) {
    $end = $raw.IndexOf("`n---", 4)
    if ($end -gt 0) {
      $lines = @($raw.Substring(4, $end - 4) -split "`n")
      $body = $raw.Substring($end + 4).TrimStart("`n")
      $i = 0
      while ($i -lt $lines.Count) {
        if ($lines[$i] -match '^([A-Za-z0-9_]+):\s*(.*)$') {
          $k = $matches[1]; $v = $matches[2].Trim()
          if ($v -match '^[>|][-+]?$') {
            $fold = $v.StartsWith('>'); $buf = @(); $i++
            while ($i -lt $lines.Count -and ($lines[$i] -match '^\s+\S' -or $lines[$i].Trim() -eq '')) { $buf += $lines[$i].Trim(); $i++ }
            $meta[$k] = $(if ($fold) { ($buf -join ' ').Trim() } else { ($buf -join "`n").Trim() })
            continue
          }
          if ($v -match '^"(.*)"$') { $v = $matches[1] -replace '\\"', '"' } elseif ($v -match "^'(.*)'$") { $v = $matches[1] -replace "''", "'" }
          $meta[$k] = $v
        }
        $i++
      }
    }
  }
  return @{ meta = $meta; body = $body }
}

# ---------- Data ----------
$site = Get-Json 'data/site.json'
$homeData = Get-Json 'data/home.json'
$siteName = Enc ([string]$site.name)
$baseUrl = ([string]$site.url).TrimEnd('/')
$year = (Get-Date).Year
$langNames = @{ en = 'English'; mn = '&#1052;&#1086;&#1085;&#1075;&#1086;&#1083;'; ko = '&#54620;&#44397;&#50612;' }
$statusNames = @{ seedling = 'Seedling'; growing = 'Growing'; evergreen = 'Evergreen' }

$entries = @()
$journalDir = [IO.Path]::Combine($Root, 'content', 'journal')
if ([IO.Directory]::Exists($journalDir)) {
  foreach ($f in [IO.Directory]::GetFiles($journalDir, '*.md')) {
    $e = Read-Entry $f
    $m = $e.meta
    $ds = [string]$m['date']
    $d = $(if ($ds.Length -ge 10) { [datetime]::ParseExact($ds.Substring(0, 10), 'yyyy-MM-dd', $Inv) } else { [IO.File]::GetLastWriteTime($f) })
    $excerpt = [string]$m['excerpt']
    if (-not $excerpt) {
      $paras = @([regex]::Split($e.body, "`n[ \t]*`n") | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 40 -and $_ -notmatch '^(#|!\[|>)' })
      $excerpt = $(if ($paras.Count) { $paras[0] -replace '[*_`=]', '' } else { '' })
    }
    $lang = $(if ($langNames.ContainsKey([string]$m['lang'])) { [string]$m['lang'] } else { 'en' })
    $status = $(if ($statusNames.ContainsKey([string]$m['status'])) { [string]$m['status'] } else { 'seedling' })
    $slug = [IO.Path]::GetFileNameWithoutExtension($f)
    $entries += [pscustomobject]@{
      Title = [string]$m['title']; Date = $d; Slug = $slug; Url = "/journal/$slug/"
      Body = (Convert-Markdown $e.body); Excerpt = $excerpt; Lang = $lang; Status = $status; Image = [string]$m['image']
      Order = $(if ([string]$m['order'] -match '^\d+$') { [int]$m['order'] } else { 0 })
    }
  }
}
$oldestFirst = @($entries | Sort-Object Date, Order, Slug)
$newestFirst = @($entries | Sort-Object Date, Order, Slug -Descending)

# My 20s chapters (content/chapters/01-the-grain.md and so on)
$chapters = @()
$chapterDir = [IO.Path]::Combine($Root, 'content', 'chapters')
if ([IO.Directory]::Exists($chapterDir)) {
  foreach ($f in [IO.Directory]::GetFiles($chapterDir, '*.md')) {
    $e = Read-Entry $f
    $m = $e.meta
    $slug = ([IO.Path]::GetFileNameWithoutExtension($f)) -replace '^\d+-', ''
    $chapters += [pscustomobject]@{
      Num = $(if ([string]$m['number'] -match '^\d+$') { [int]$m['number'] } else { 0 }); Slug = $slug; Url = "/my-20s/$slug/"
      Title = [string]$m['title']; Headline = [string]$m['headline']; Summary = [string]$m['summary']; Quote = [string]$m['quote']
      Years = [string]$m['years']; Ages = [string]$m['ages']; Body = (Convert-Markdown $e.body); HasStory = [bool]($e.body.Trim())
    }
  }
}
$chapters = @($chapters | Sort-Object Num)

function Format-Day($d) { $d.ToString('d MMMM yyyy', $Inv) }
function Get-Row($x) {
  '<a class="post" href="' + $x.Url + '"><div><p class="kicker">' + (Format-Day $x.Date) + '</p><h3><span class="uline">' + (Enc $x.Title) + '</span></h3><p>' + (Enc $x.Excerpt) + '</p></div>' +
  '<div class="meta"><span>' + $x.Lang.ToUpper() + '</span><i class="dot ' + $x.Status + '" title="' + $statusNames[$x.Status] + '"></i><span class="arrow">&rarr;</span></div></a>'
}

# ---------- Shared pieces ----------
$legend = '<div class="legend"><span><i class="dot seedling"></i>Seedling</span><span><i class="dot growing"></i>Growing</span><span><i class="dot evergreen"></i>Evergreen</span></div>'
$emailBtn = $(if ($site.email) { '<a class="btn line" href="mailto:' + (Enc $site.email) + '">Write to me</a>' } else { '' })
$newsBtn = $(if ($site.newsletter) { '<a class="btn line" href="' + (Enc $site.newsletter) + '">Get new pages by email</a>' } else { '' })
$instaBtn = $(if ($site.instagram) { '<a class="btn solid" href="' + (Enc $site.instagram) + '" rel="me">Instagram</a>' } else { '' })
$studyBtn = $(if ($site.studywithme) { '<a class="btn line" href="' + (Enc $site.studywithme) + '" rel="me">Study with me</a>' } else { '' })
$ytBtn = $(if ($site.youtube) { '<a class="btn solid" href="' + (Enc $site.youtube) + '" rel="me">YouTube</a>' } else { '<span class="btn ghost" aria-disabled="true">YouTube, coming soon</span>' })
$socialBtns = $instaBtn + $studyBtn + $ytBtn
$invite = Fill (Get-Template 'invite.html') @{ invite_title = (Enc $homeData.invite_title); invite_text = (Enc $homeData.invite_text); buttons = ($socialBtns + $emailBtn + $newsBtn) }
$rowsAll = ($newestFirst | ForEach-Object { Get-Row $_ }) -join "`n"
$rowsHome = ($newestFirst | Select-Object -First 5 | ForEach-Object { Get-Row $_ }) -join "`n"
$more = $(if ($newestFirst.Count -gt 5) { '<a class="more" href="/journal/"><span class="uline">All journal pages</span> &rarr;</a>' } else { '' })
$countText = $(if ($entries.Count -eq 0) { 'The first page is on its way.' } elseif ($entries.Count -eq 1) { 'One page so far.' } else { [string]$entries.Count + ' pages so far.' })

$nowItems = @($homeData.now | ForEach-Object {
  $s = [string]$_; $cut = $s.IndexOf(' - ')
  if ($cut -gt 0) { '<span><b>' + (Enc $s.Substring(0, $cut)) + '</b> - ' + (Enc $s.Substring($cut + 3)) + '<i>&#10043;</i></span>' } else { '<span>' + (Enc $s) + '<i>&#10043;</i></span>' }
}) -join ''
$nowBand = $(if ($nowItems) { '<div class="now" aria-label="Now"><div class="marquee"><div class="set">' + $nowItems + '</div><div class="set" aria-hidden="true">' + $nowItems + '</div></div></div>' } else { '' })
$n = 0
$layerCards = @($homeData.layers | ForEach-Object {
  $n++
  '<article class="card dots"><p class="num">' + ('{0:D2}' -f $n) + ' &middot; ' + (Enc $_.name) + '</p><h3>' + (Enc $_.title) + '</h3><blockquote>' + (Enc $_.text) + '</blockquote></article>'
}) -join "`n"
$chapterCards = ($chapters | ForEach-Object {
  '<a class="card dots chapter-card" href="' + $_.Url + '"><p class="num">' + ('{0:D2}' -f $_.Num) + ' &middot; ' + (Enc $_.Title) + '</p><h3>' + (Enc $_.Headline) + '</h3><blockquote>' + (Enc $_.Summary) + '</blockquote>' +
  $(if ($_.HasStory) { '<span class="more"><span class="uline">Read the chapter</span> &rarr;</span>' } else { '<span class="more soon-tag">Coming soon</span>' }) + '</a>'
}) -join "`n"
$chaptersSection = $(if ($chapterCards) { '<section class="wrap block" id="chapters"><div class="sec-head"><h2>My 20s, in four chapters</h2><span class="label">2015 &rarr; 2025</span></div><div class="layers">' + $chapterCards + '</div></section>' } else { '' })
$measuredMore = $(if ($homeData.measured_link) { '<a class="more" href="' + (Enc $homeData.measured_link) + '"><span class="uline">Read what the numbers said</span> &rarr;</a>' } else { '' })

$layout = Get-Template 'layout.html'
function Get-Page([string]$Title, [string]$Desc, [string]$Main, [string]$Path, [string]$Type = 'website') {
  $canon = $(if ($baseUrl) { '<link rel="canonical" href="' + $baseUrl + $Path + '"><meta property="og:url" content="' + $baseUrl + $Path + '">' } else { '' })
  $scripts = $(if ($Main.Contains('data-chart=')) { '<script src="/assets/js/life-score.js" defer></script><script src="/assets/js/charts.js" defer></script>' } else { '' })
  $page = $layout.Replace('{{main}}', $Main)
  return (Fill $page @{ title = $Title; description = $Desc; canonical = $canon; og_type = $Type; site_name = $siteName; year = $year; scripts = $scripts })
}

# ---------- Output ----------
if ([IO.Directory]::Exists($OutDir)) { [IO.Directory]::Delete($OutDir, $true) }
[void][IO.Directory]::CreateDirectory($OutDir)
foreach ($dir in 'assets', 'admin') {
  $src = [IO.Path]::Combine($Root, $dir)
  if ([IO.Directory]::Exists($src)) { Copy-Item -LiteralPath $src -Destination ([IO.Path]::Combine($OutDir, $dir)) -Recurse }
}

$homeMain = Fill (Get-Template 'home.html') @{
  eyebrow = (Enc $homeData.eyebrow); headline = (Convert-Inline $homeData.headline); intro = (Enc $homeData.intro)
  now_band = $nowBand; manifesto = (Convert-Inline $homeData.manifesto); legend = $legend; rows = $rowsHome; more = $more
  layers = $(if ($chapterCards) { $chapterCards } else { $layerCards }); measured_title = (Enc $homeData.measured_title); measured_text = (Enc $homeData.measured_text)
  measured_more = $measuredMore; forwho_label = (Enc $homeData.forwho_label); forwho_title = (Enc $homeData.forwho_title); forwho_text = (Enc $homeData.forwho_text); invite = $invite
}
Write-Text ([IO.Path]::Combine($OutDir, 'index.html')) (Get-Page ($siteName + ' &middot; ' + (Enc $site.tagline)) (Enc $site.description) $homeMain '/')

$journalMain = Fill (Get-Template 'journal.html') @{ legend = $legend; rows = $rowsAll; count = $countText; invite = $invite }
Write-Text ([IO.Path]::Combine($OutDir, 'journal', 'index.html')) (Get-Page ('Journal &middot; ' + $siteName) 'Every journal page, newest first.' $journalMain '/journal/')

for ($i = 0; $i -lt $oldestFirst.Count; $i++) {
  $x = $oldestFirst[$i]
  $prev = '<span></span>'; $next = '<span></span>'
  if ($i -gt 0) { $p = $oldestFirst[$i - 1]; $prev = '<a class="prev" href="' + $p.Url + '">&larr; Older<span>' + (Enc $p.Title) + '</span></a>' }
  if ($i -lt $oldestFirst.Count - 1) { $q = $oldestFirst[$i + 1]; $next = '<a class="next" href="' + $q.Url + '">Newer &rarr;<span>' + (Enc $q.Title) + '</span></a>' }
  $img = $(if ($x.Image) { '<figure class="letter-img"><img src="' + (Enc $x.Image) + '" alt=""></figure>' } else { '' })
  $main = (Get-Template 'entry.html').Replace('{{body}}', $x.Body)
  $main = Fill $main @{ date = (Format-Day $x.Date); title = (Enc $x.Title); lang = $x.Lang; lang_label = $langNames[$x.Lang]
    status = $x.Status; status_label = $statusNames[$x.Status]; image = $img; prev = $prev; next = $next; invite = $invite }
  Write-Text ([IO.Path]::Combine($OutDir, 'journal', $x.Slug, 'index.html')) (Get-Page ((Enc $x.Title) + ' &middot; ' + $siteName) (Enc $x.Excerpt) $main $x.Url 'article')
}

for ($i = 0; $i -lt $chapters.Count; $i++) {
  $c = $chapters[$i]
  $prev = '<span></span>'; $next = '<span></span>'
  if ($i -gt 0) { $p = $chapters[$i - 1]; $prev = '<a class="prev" href="' + $p.Url + '">&larr; Chapter ' + $p.Num + '<span>' + (Enc $p.Title) + '</span></a>' }
  if ($i -lt $chapters.Count - 1) { $q = $chapters[$i + 1]; $next = '<a class="next" href="' + $q.Url + '">Chapter ' + $q.Num + ' &rarr;<span>' + (Enc $q.Title) + '</span></a>' }
  $chapterBody = $(if ($c.HasStory) { $c.Body } else { '<p class="soon-note">This chapter is still being written. Coming soon.</p>' })
  $main = (Get-Template 'chapter.html').Replace('{{body}}', $chapterBody)
  $main = Fill $main @{ number = $c.Num; total = $chapters.Count; title = (Enc $c.Title); headline = (Enc $c.Headline); years = (Enc $c.Years); ages = (Enc $c.Ages)
    quote = (Enc $c.Quote); prev = $prev; next = $next; invite = $invite }
  Write-Text ([IO.Path]::Combine($OutDir, 'my-20s', $c.Slug, 'index.html')) (Get-Page ((Enc $c.Headline) + ' &middot; My 20s &middot; ' + $siteName) (Enc $c.Summary) $main $c.Url 'article')
}

$aboutPath = [IO.Path]::Combine($Root, 'content', 'pages', 'about.md')
if ([IO.File]::Exists($aboutPath)) {
  $about = Read-Entry $aboutPath
  $photo = $(if ($about.meta['photo']) { '<figure class="about-photo"><img src="' + (Enc $about.meta['photo']) + '" alt="' + $siteName + '"></figure>' } else { '' })
  $aboutMain = (Get-Template 'page.html').Replace('{{body}}', (Convert-Markdown $about.body)).Replace('{{invite}}', $chaptersSection + "`n{{invite}}")
  $aboutMain = Fill $aboutMain @{ title = (Enc $about.meta['title']); site_name = $siteName; photo = $photo; invite = $invite }
  Write-Text ([IO.Path]::Combine($OutDir, 'about', 'index.html')) (Get-Page ((Enc $about.meta['title']) + ' &middot; ' + $siteName) (Enc $site.description) $aboutMain '/about/')
}

$cvPath = [IO.Path]::Combine($Root, 'content', 'pages', 'cv.md')
if ([IO.File]::Exists($cvPath)) {
  $cv = Read-Entry $cvPath
  $pdf = $(if ($cv.meta['pdf']) { '<p class="cv-pdf"><a class="btn solid" href="' + (Enc $cv.meta['pdf']) + '">Download my CV (PDF)</a></p>' } else { '' })
  $cvMain = (Get-Template 'page.html').Replace('{{body}}', $pdf + (Convert-Markdown $cv.body))
  $cvMain = Fill $cvMain @{ title = (Enc $cv.meta['title']); site_name = $siteName; photo = ''; invite = $invite }
  Write-Text ([IO.Path]::Combine($OutDir, 'cv', 'index.html')) (Get-Page ('CV &middot; ' + $siteName) ('Curriculum vitae of ' + $siteName + '.') $cvMain '/cv/')
}

$nf = '<section class="wrap page-head"><p class="label">A lost page</p><h1 class="page-title">This page drifted away.</h1><p class="intro"><a class="more" href="/"><span class="uline">Go back home</span> &rarr;</a></p></section>'
Write-Text ([IO.Path]::Combine($OutDir, '404.html')) (Get-Page ('Not found &middot; ' + $siteName) 'Page not found.' $nf '/404.html')

$items = ($newestFirst | Select-Object -First 20 | ForEach-Object {
  $link = $baseUrl + $_.Url
  '<item><title>' + (Enc $_.Title) + '</title><link>' + $link + '</link><guid>' + $link + '</guid><pubDate>' + $_.Date.ToString('r', $Inv) + '</pubDate><description><![CDATA[' + $_.Body + ']]></description></item>'
}) -join "`n"
$feed = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<rss version="2.0"><channel><title>' + $siteName + ' &#183; ' + (Enc $site.tagline) + '</title><link>' + $baseUrl + '/</link><description>' + (Enc $site.description) + '</description><language>en</language>' + "`n" + $items + "`n</channel></rss>`n"
Write-Text ([IO.Path]::Combine($OutDir, 'feed.xml')) $feed

Write-Host ("Built {0} journal page(s) into {1}" -f $entries.Count, $OutDir)
