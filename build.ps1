# Builds the website into _site.
# Works in Windows PowerShell 5.1 (local preview) and PowerShell 7 (GitHub Actions).
# Keep this file ASCII-only: Windows PowerShell reads scripts without a BOM as ANSI.
# Every visible word lives in data/, content/ or templates/, never in this file.
#
# Languages: English is built at /, Mongolian at /mn/ (only when data/home.mn.json exists).
# Interface words come from data/i18n.json; templates write them as {{t:key}}.
# Pages with a Mongolian text use it (data/home.mn.json, content/pages/about.mn.md,
# the *_mn fields of each chapter). Journal pages and the CV keep the language they
# were written in and get both interfaces, so a reader never leaves their language.
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
function Test-SiteFile([string]$Rel) { [IO.File]::Exists([IO.Path]::Combine($Root, $Rel)) }

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
          # Long values may continue on indented lines (the admin page wraps them).
          while ($i + 1 -lt $lines.Count -and $lines[$i + 1] -match '^\s+\S') { $i++; $v = $v + ' ' + $lines[$i].Trim() }
          if ($v -match '^"(.*)"$') { $v = $matches[1] -replace '\\"', '"' } elseif ($v -match "^'(.*)'$") { $v = $matches[1] -replace "''", "'" }
          $meta[$k] = $v
        }
        $i++
      }
    }
  }
  return @{ meta = $meta; body = $body }
}

# ---------- Languages ----------
$I18n = Get-Json 'data/i18n.json'
$Langs = @('en')
foreach ($code in @('mn')) { if (Test-SiteFile "data/home.$code.json") { $Langs += $code } }
$Prefix = @{}
foreach ($code in $Langs) { $Prefix[$code] = $(if ($code -eq 'en') { '' } else { '/' + $code }) }

# An interface word in language L; falls back to English, then to the key itself.
function Get-Str([string]$L, [string]$Key) {
  $v = $null
  if ($I18n.$L) { $v = $I18n.$L.$Key }
  if (-not $v -and $L -ne 'en') { $v = $I18n.en.$Key }
  if ($null -eq $v) { return $Key }
  return [string]$v
}
# Fills {n}, {total}, {title} and the like.
function Format-Str([string]$s, [hashtable]$Vals) {
  foreach ($k in $Vals.Keys) { $s = $s.Replace('{' + $k + '}', [string]$Vals[$k]) }
  return $s
}
function Format-Day($d, [string]$L) {
  $f = Get-Str $L 'date_format'
  if (-not $f) { return $d.ToString('d MMMM yyyy', $Inv) }
  return (Format-Str $f @{ y = $d.Year; m = $d.Month; d = $d.Day })
}
# Replaces every {{t:key}} in a page with the interface word.
function Set-Strings([string]$Html, [string]$L) {
  $keys = @([regex]::Matches($Html, '\{\{t:([a-z0-9_]+)\}\}') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
  foreach ($k in $keys) { $Html = $Html.Replace('{{t:' + $k + '}}', (Enc (Get-Str $L $k))) }
  return $Html
}
# The same page in another language: /journal/ and /mn/journal/.
function Get-Alt([string]$Path, [string]$From, [string]$To) {
  $base = $Path
  if ($Prefix[$From]) { $base = $Path.Substring($Prefix[$From].Length) }
  return $Prefix[$To] + $base
}
# Links written in texts keep the reader inside their language.
function Get-LocalUrl([string]$L, [string]$Url) {
  if ($Prefix[$L] -and $Url -match '^/($|journal/|my-20s/|about/|cv/)') { return $Prefix[$L] + $Url }
  return $Url
}

# ---------- Data ----------
$site = Get-Json 'data/site.json'
$HomeData = @{}
foreach ($L in $Langs) { $HomeData[$L] = Get-Json $(if ($L -eq 'en') { 'data/home.json' } else { "data/home.$L.json" }) }
# A home-page text in language L. A field missing from the translation uses the English one.
function Get-HomeValue([string]$L, [string]$Key) {
  $v = $HomeData[$L].$Key
  if ($null -eq $v) { $v = $HomeData['en'].$Key }
  return $v
}
function Get-Tagline([string]$L) { if ($L -eq 'en') { [string]$site.tagline } else { Get-Str $L 'tagline' } }
function Get-Description([string]$L) { if ($L -eq 'en') { [string]$site.description } else { Get-Str $L 'description' } }
$siteName = Enc ([string]$site.name)
$baseUrl = ([string]$site.url).TrimEnd('/')
$year = (Get-Date).Year
$langNames = @{ en = 'English'; mn = '&#1052;&#1086;&#1085;&#1075;&#1086;&#1083;'; ko = '&#54620;&#44397;&#50612;' }
$statuses = @('seedling', 'growing', 'evergreen')

# ---------- Journal pages ----------
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
    $status = $(if ($statuses -contains [string]$m['status']) { [string]$m['status'] } else { 'seedling' })
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

# ---------- My 20s chapters (content/chapters/01-the-grain.md and so on) ----------
# English: title, years, ages, headline, summary, quote and the body (the story).
# Mongolian: title_mn ... quote_mn and story_mn. An empty Mongolian field uses the English one.
$chapters = @()
$chapterDir = [IO.Path]::Combine($Root, 'content', 'chapters')
if ([IO.Directory]::Exists($chapterDir)) {
  foreach ($f in [IO.Directory]::GetFiles($chapterDir, '*.md')) {
    $e = Read-Entry $f
    $m = $e.meta
    $slug = ([IO.Path]::GetFileNameWithoutExtension($f)) -replace '^\d+-', ''
    $text = @{}
    foreach ($L in $Langs) {
      $h = @{}
      foreach ($k in @('title', 'years', 'ages', 'headline', 'summary', 'quote')) {
        $v = $(if ($L -eq 'en') { '' } else { [string]$m[$k + '_' + $L] })
        if (-not $v) { $v = [string]$m[$k] }
        $h[$k] = $v
      }
      $story = $(if ($L -eq 'en') { [string]$e.body } else { [string]$m['story_' + $L] })
      $h.story_lang = $L
      if (-not $story.Trim()) { $story = [string]$e.body; $h.story_lang = 'en' }
      $h.has_story = [bool]($story.Trim())
      $h.story = Convert-Markdown $story
      $text[$L] = $h
    }
    $chapters += [pscustomobject]@{
      Num = $(if ([string]$m['number'] -match '^\d+$') { [int]$m['number'] } else { 0 }); Slug = $slug; Url = "/my-20s/$slug/"; Text = $text
    }
  }
}
$chapters = @($chapters | Sort-Object Num)

# ---------- Shared pieces ----------
function Get-Row($x, [string]$L) {
  '<a class="post" href="' + $Prefix[$L] + $x.Url + '"><div><p class="kicker">' + (Enc (Format-Day $x.Date $L)) + '</p><h3 lang="' + $x.Lang + '"><span class="uline">' + (Enc $x.Title) + '</span></h3><p lang="' + $x.Lang + '">' + (Enc $x.Excerpt) + '</p></div>' +
  '<div class="meta"><span>' + $x.Lang.ToUpper() + '</span><i class="dot ' + $x.Status + '" title="' + (Enc (Get-Str $L ('status_' + $x.Status))) + '"></i><span class="arrow">&rarr;</span></div></a>'
}
function Get-Rows([string]$L, [int]$Max) {
  $out = @()
  foreach ($x in $newestFirst) {
    if ($Max -gt 0 -and $out.Count -ge $Max) { break }
    $out += Get-Row $x $L
  }
  return ($out -join "`n")
}
function Get-Legend([string]$L) {
  $out = foreach ($s in $statuses) { '<span><i class="dot ' + $s + '"></i>' + (Enc (Get-Str $L ('status_' + $s))) + '</span>' }
  return ('<div class="legend">' + ($out -join '') + '</div>')
}
function Get-Count([string]$L) {
  if ($entries.Count -eq 0) { return (Get-Str $L 'count_zero') }
  if ($entries.Count -eq 1) { return (Get-Str $L 'count_one') }
  return (Format-Str (Get-Str $L 'count_many') @{ n = $entries.Count })
}
function Get-Invite([string]$L) {
  $b = ''
  if ($site.instagram) { $b += '<a class="btn solid" href="' + (Enc $site.instagram) + '" rel="me">Instagram</a>' }
  if ($site.studywithme) { $b += '<a class="btn line" href="' + (Enc $site.studywithme) + '" rel="me">' + (Enc (Get-Str $L 'study_with_me')) + '</a>' }
  if ($site.youtube) { $b += '<a class="btn solid" href="' + (Enc $site.youtube) + '" rel="me">YouTube</a>' }
  else { $b += '<span class="btn ghost" aria-disabled="true">' + (Enc (Get-Str $L 'youtube_soon')) + '</span>' }
  if ($site.email) { $b += '<a class="btn line" href="mailto:' + (Enc $site.email) + '">' + (Enc (Get-Str $L 'write_to_me')) + '</a>' }
  if ($site.newsletter) { $b += '<a class="btn line" href="' + (Enc $site.newsletter) + '">' + (Enc (Get-Str $L 'newsletter')) + '</a>' }
  return (Fill (Get-Template 'invite.html') @{ invite_title = (Enc (Get-HomeValue $L 'invite_title')); invite_text = (Enc (Get-HomeValue $L 'invite_text')); buttons = $b })
}
function Get-NowBand([string]$L) {
  $items = ''
  foreach ($line in @(Get-HomeValue $L 'now')) {
    $s = [string]$line
    if (-not $s) { continue }
    $cut = $s.IndexOf(' - ')
    if ($cut -gt 0) { $items += '<span><b>' + (Enc $s.Substring(0, $cut)) + '</b> - ' + (Enc $s.Substring($cut + 3)) + '<i>&#10043;</i></span>' }
    else { $items += '<span>' + (Enc $s) + '<i>&#10043;</i></span>' }
  }
  if (-not $items) { return '' }
  return ('<div class="now" aria-label="' + (Enc (Get-Str $L 'aria_now')) + '"><div class="marquee"><div class="set">' + $items + '</div><div class="set" aria-hidden="true">' + $items + '</div></div></div>')
}
function Get-ChapterCards([string]$L) {
  $out = foreach ($c in $chapters) {
    $t = $c.Text[$L]
    $foot = $(if ($t.has_story) { '<span class="more"><span class="uline">' + (Enc (Get-Str $L 'read_chapter')) + '</span> &rarr;</span>' } else { '<span class="more soon-tag">' + (Enc (Get-Str $L 'coming_soon')) + '</span>' })
    '<a class="card dots chapter-card" href="' + $Prefix[$L] + $c.Url + '"><p class="num">' + ('{0:D2}' -f $c.Num) + ' &middot; ' + (Enc $t.title) + '</p><h3>' + (Enc $t.headline) + '</h3><blockquote>' + (Enc $t.summary) + '</blockquote>' + $foot + '</a>'
  }
  return ($out -join "`n")
}
# Older home pages listed "layers" instead of chapters; kept as a fallback.
function Get-LayerCards([string]$L) {
  $list = @(Get-HomeValue $L 'layers'); $out = @()
  for ($i = 0; $i -lt $list.Count; $i++) {
    $c = $list[$i]
    if ($c) { $out += '<article class="card dots"><p class="num">' + ('{0:D2}' -f ($i + 1)) + ' &middot; ' + (Enc $c.name) + '</p><h3>' + (Enc $c.title) + '</h3><blockquote>' + (Enc $c.text) + '</blockquote></article>' }
  }
  return ($out -join "`n")
}
function Get-ChaptersSection([string]$L) {
  $cards = Get-ChapterCards $L
  if (-not $cards) { return '' }
  return ('<section class="wrap block" id="chapters"><div class="sec-head"><h2>' + (Enc (Get-Str $L 'chapters_heading')) + '</h2><span class="label">2015 &rarr; 2025</span></div><div class="layers">' + $cards + '</div></section>')
}
# Language toggle: one link to the same page in the other language. The knob sits
# under the current language and slides across when clicked (see site.css).
function Get-LangSwitch([string]$L, [string]$Path, [bool]$Single) {
  if ($Langs.Count -lt 2) { return '' }
  $other = @($Langs | Where-Object { $_ -ne $L })[0]
  $href = $(if ($Single) { $Prefix[$other] + '/' } else { Get-Alt $Path $L $other })
  $opts = foreach ($o in $Langs) { '<span class="lt-opt' + $(if ($o -eq $L) { ' on' } else { '' }) + '" lang="' + $o + '">' + (Enc (Get-Str $o 'lang_label')) + '</span>' }
  $at = $(if ([array]::IndexOf($Langs, $L) -gt 0) { ' at-2' } else { '' })
  $label = Enc (Get-Str $other 'lang_switch_to')
  return ('<a class="lang-toggle' + $at + '" href="' + $href + '" hreflang="' + $other + '" lang="' + $other + '" aria-label="' + $label + '" title="' + $label + '">' + ($opts -join '') + '<span class="lt-knob" aria-hidden="true"></span></a>')
}

$layout = Get-Template 'layout.html'
# A short fingerprint of site.css, so browsers load the new styles right after an update.
$cssFile = [IO.Path]::Combine($Root, 'assets', 'css', 'site.css')
$cssV = '1'
if ([IO.File]::Exists($cssFile)) {
  $sha = [Security.Cryptography.SHA1]::Create()
  $cssV = ([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($cssFile))) -replace '-', '').Substring(0, 10).ToLowerInvariant()
}
# Path: this page's address. Canon: the main address when the same text appears under
# both interfaces (journal pages, the CV). Single: the page exists in one language only.
function Get-Page([string]$L, [string]$Title, [string]$Desc, [string]$Main, [string]$Path, [string]$Type = 'website', [string]$Canon = '', [switch]$Single) {
  $head = ''; $alts = ''
  if ($baseUrl) {
    $c = $(if ($Canon) { $Canon } else { $Path })
    $head = '<link rel="canonical" href="' + $baseUrl + $c + '"><meta property="og:url" content="' + $baseUrl + $c + '">'
    if (-not $Canon -and -not $Single -and $Langs.Count -gt 1) {
      $list = foreach ($o in $Langs) { '<link rel="alternate" hreflang="' + $o + '" href="' + $baseUrl + (Get-Alt $Path $L $o) + '">' }
      $alts = ($list -join "`n") + "`n" + '<link rel="alternate" hreflang="x-default" href="' + $baseUrl + (Get-Alt $Path $L 'en') + '">'
    }
  }
  $scripts = $(if ($Main.Contains('data-chart=')) { '<script src="/assets/js/life-score.js" defer></script><script src="/assets/js/charts.js" defer></script>' } else { '' })
  $page = $layout.Replace('{{main}}', $Main)
  $page = Fill $page @{ title = $Title; description = $Desc; canonical = $head; alternates = $alts; og_type = $Type; site_name = $siteName; year = $year
    scripts = $scripts; lang = $L; p = $Prefix[$L]; css_v = $cssV; lang_switch = (Get-LangSwitch $L $Path $Single.IsPresent) }
  return (Set-Strings $page $L)
}
# Writes /mn/journal/ to _site/mn/journal/index.html.
function Save-Page([string]$UrlPath, [string]$Html) {
  $rel = $UrlPath.TrimStart('/')
  if ($rel -eq '' -or $rel.EndsWith('/')) { $rel += 'index.html' }
  Write-Text ([IO.Path]::Combine($OutDir, $rel.Replace('/', [string][IO.Path]::DirectorySeparatorChar))) $Html
}

# ---------- Output ----------
if ([IO.Directory]::Exists($OutDir)) { [IO.Directory]::Delete($OutDir, $true) }
[void][IO.Directory]::CreateDirectory($OutDir)
foreach ($dir in 'assets', 'admin') {
  $src = [IO.Path]::Combine($Root, $dir)
  if ([IO.Directory]::Exists($src)) { Copy-Item -LiteralPath $src -Destination ([IO.Path]::Combine($OutDir, $dir)) -Recurse }
}

$pagesDir = [IO.Path]::Combine($Root, 'content', 'pages')
$enAboutPath = [IO.Path]::Combine($pagesDir, 'about.md')
$enAbout = $(if ([IO.File]::Exists($enAboutPath)) { Read-Entry $enAboutPath } else { $null })
$cvPath = [IO.Path]::Combine($pagesDir, 'cv.md')
$cv = $(if ([IO.File]::Exists($cvPath)) { Read-Entry $cvPath } else { $null })

foreach ($L in $Langs) {
  $pre = $Prefix[$L]
  $invite = Get-Invite $L

  # Home
  $cards = Get-ChapterCards $L
  $link = [string](Get-HomeValue $L 'measured_link')
  if (-not $link) { $link = [string]$HomeData['en'].measured_link }
  $measuredMore = $(if ($link) { '<a class="more" href="' + (Enc (Get-LocalUrl $L $link)) + '"><span class="uline">' + (Enc (Get-Str $L 'read_numbers')) + '</span> &rarr;</a>' } else { '' })
  $more = $(if ($newestFirst.Count -gt 5) { '<a class="more" href="' + $pre + '/journal/"><span class="uline">' + (Enc (Get-Str $L 'all_journal_pages')) + '</span> &rarr;</a>' } else { '' })
  $homeMain = Fill (Get-Template 'home.html') @{
    eyebrow = (Enc (Get-HomeValue $L 'eyebrow')); headline = (Convert-Inline (Get-HomeValue $L 'headline')); intro = (Enc (Get-HomeValue $L 'intro'))
    now_band = (Get-NowBand $L); manifesto = (Convert-Inline (Get-HomeValue $L 'manifesto')); legend = (Get-Legend $L); rows = (Get-Rows $L 5); more = $more
    layers = $(if ($cards) { $cards } else { Get-LayerCards $L }); measured_title = (Enc (Get-HomeValue $L 'measured_title')); measured_text = (Enc (Get-HomeValue $L 'measured_text'))
    measured_more = $measuredMore; forwho_label = (Enc (Get-HomeValue $L 'forwho_label')); forwho_title = (Enc (Get-HomeValue $L 'forwho_title')); forwho_text = (Enc (Get-HomeValue $L 'forwho_text')); invite = $invite
  }
  Save-Page ($pre + '/') (Get-Page $L ($siteName + ' &middot; ' + (Enc (Get-Tagline $L))) (Enc (Get-Description $L)) $homeMain ($pre + '/'))

  # Journal list
  $journalMain = Fill (Get-Template 'journal.html') @{ tagline = (Enc (Get-Tagline $L)); legend = (Get-Legend $L); rows = (Get-Rows $L 0); count = (Enc (Get-Count $L)); invite = $invite }
  Save-Page ($pre + '/journal/') (Get-Page $L ((Enc (Get-Str $L 'journal')) + ' &middot; ' + $siteName) (Enc (Get-Str $L 'journal_desc')) $journalMain ($pre + '/journal/'))

  # Journal pages: the text stays in its own language, the interface follows the reader.
  for ($i = 0; $i -lt $oldestFirst.Count; $i++) {
    $x = $oldestFirst[$i]
    $prev = '<span></span>'; $next = '<span></span>'
    if ($i -gt 0) { $o = $oldestFirst[$i - 1]; $prev = '<a class="prev" href="' + $pre + $o.Url + '">&larr; ' + (Enc (Get-Str $L 'older')) + '<span lang="' + $o.Lang + '">' + (Enc $o.Title) + '</span></a>' }
    if ($i -lt $oldestFirst.Count - 1) { $o = $oldestFirst[$i + 1]; $next = '<a class="next" href="' + $pre + $o.Url + '">' + (Enc (Get-Str $L 'newer')) + ' &rarr;<span lang="' + $o.Lang + '">' + (Enc $o.Title) + '</span></a>' }
    $img = $(if ($x.Image) { '<figure class="letter-img"><img src="' + (Enc $x.Image) + '" alt=""></figure>' } else { '' })
    $main = (Get-Template 'entry.html').Replace('{{body}}', $x.Body)
    $main = Fill $main @{ date = (Enc (Format-Day $x.Date $L)); title = (Enc $x.Title); post_lang = $x.Lang; lang_label = $langNames[$x.Lang]
      status = $x.Status; status_label = (Enc (Get-Str $L ('status_' + $x.Status))); image = $img; prev = $prev; next = $next; invite = $invite }
    $mainLang = $(if ($Langs -contains $x.Lang) { $x.Lang } else { 'en' })
    Save-Page ($pre + $x.Url) (Get-Page $L ((Enc $x.Title) + ' &middot; ' + $siteName) (Enc $x.Excerpt) $main ($pre + $x.Url) 'article' ($Prefix[$mainLang] + $x.Url))
  }

  # My 20s chapters
  for ($i = 0; $i -lt $chapters.Count; $i++) {
    $c = $chapters[$i]; $t = $c.Text[$L]
    $prev = '<span></span>'; $next = '<span></span>'
    if ($i -gt 0) { $o = $chapters[$i - 1]; $prev = '<a class="prev" href="' + $pre + $o.Url + '">&larr; ' + (Enc (Format-Str (Get-Str $L 'chapter_n') @{ n = $o.Num })) + '<span>' + (Enc ($o.Text[$L].title)) + '</span></a>' }
    if ($i -lt $chapters.Count - 1) { $o = $chapters[$i + 1]; $next = '<a class="next" href="' + $pre + $o.Url + '">' + (Enc (Format-Str (Get-Str $L 'chapter_n') @{ n = $o.Num })) + ' &rarr;<span>' + (Enc ($o.Text[$L].title)) + '</span></a>' }
    $bodyLang = $L
    if ($t.has_story) {
      $body = $t.story; $bodyLang = $t.story_lang
      if ($t.story_lang -ne $L) { $body = '<p class="soon-note" lang="' + $L + '">' + (Enc (Get-Str $L 'only_english')) + '</p>' + "`n" + $body }
    } else {
      $body = '<p class="soon-note">' + (Enc (Get-Str $L 'chapter_soon_note')) + '</p>'
    }
    $main = (Get-Template 'chapter.html').Replace('{{body}}', $body)
    $main = Fill $main @{ chapter_label = (Enc (Format-Str (Get-Str $L 'chapter_label') @{ n = $c.Num; total = $chapters.Count; title = $t.title })); headline = (Enc $t.headline)
      years = (Enc $t.years); ages = (Enc $t.ages); quote = (Enc $t.quote); body_lang = $bodyLang; prev = $prev; next = $next; invite = $invite }
    Save-Page ($pre + $c.Url) (Get-Page $L ((Enc $t.headline) + ' &middot; ' + (Enc (Get-Str $L 'my20s')) + ' &middot; ' + $siteName) (Enc $t.summary) $main ($pre + $c.Url) 'article')
  }

  # My story (about.md, or about.mn.md for Mongolian; the photo comes from the English page when left empty)
  $aboutPath = $(if ($L -eq 'en') { $enAboutPath } else { [IO.Path]::Combine($pagesDir, "about.$L.md") })
  $aboutLang = $L
  if (-not [IO.File]::Exists($aboutPath)) { $aboutPath = $enAboutPath; $aboutLang = 'en' }
  if ([IO.File]::Exists($aboutPath)) {
    $about = Read-Entry $aboutPath
    $photoSrc = [string]$about.meta['photo']
    if (-not $photoSrc -and $enAbout) { $photoSrc = [string]$enAbout.meta['photo'] }
    $photo = $(if ($photoSrc) { '<figure class="about-photo"><img src="' + (Enc $photoSrc) + '" alt="' + $siteName + '"></figure>' } else { '' })
    $aboutMain = (Get-Template 'page.html').Replace('{{body}}', (Convert-Markdown $about.body)).Replace('{{invite}}', (Get-ChaptersSection $L) + "`n{{invite}}")
    $aboutMain = Fill $aboutMain @{ title = (Enc $about.meta['title']); site_name = $siteName; photo = $photo; body_lang = $aboutLang; invite = $invite }
    Save-Page ($pre + '/about/') (Get-Page $L ((Enc $about.meta['title']) + ' &middot; ' + $siteName) (Enc (Get-Description $L)) $aboutMain ($pre + '/about/'))
  }

  # CV (English text under both interfaces)
  if ($cv) {
    $pdf = $(if ($cv.meta['pdf']) { '<p class="cv-pdf"><a class="btn solid" href="' + (Enc $cv.meta['pdf']) + '">' + (Enc (Get-Str $L 'cv_download')) + '</a></p>' } else { '' })
    $cvTitle = $(if ($L -eq 'en') { [string]$cv.meta['title'] } else { Get-Str $L 'cv_title' })
    $cvMain = (Get-Template 'page.html').Replace('{{body}}', $pdf + (Convert-Markdown $cv.body))
    $cvMain = Fill $cvMain @{ title = (Enc $cvTitle); site_name = $siteName; photo = ''; body_lang = 'en'; invite = $invite }
    Save-Page ($pre + '/cv/') (Get-Page $L ((Enc $cvTitle) + ' &middot; ' + $siteName) ('Curriculum vitae of ' + $siteName + '.') $cvMain ($pre + '/cv/') 'website' '/cv/')
  }
}

$nf = '<section class="wrap page-head"><p class="label">' + (Enc (Get-Str 'en' 'notfound_label')) + '</p><h1 class="page-title">' + (Enc (Get-Str 'en' 'notfound_title')) + '</h1><p class="intro"><a class="more" href="/"><span class="uline">' + (Enc (Get-Str 'en' 'notfound_link')) + '</span> &rarr;</a></p></section>'
Save-Page '/404.html' (Get-Page 'en' ('Not found &middot; ' + $siteName) 'Page not found.' $nf '/404.html' 'website' '' -Single)

$items = ($newestFirst | Select-Object -First 20 | ForEach-Object {
  $link = $baseUrl + $_.Url
  '<item><title>' + (Enc $_.Title) + '</title><link>' + $link + '</link><guid>' + $link + '</guid><pubDate>' + $_.Date.ToString('r', $Inv) + '</pubDate><description><![CDATA[' + $_.Body + ']]></description></item>'
}) -join "`n"
$feed = '<?xml version="1.0" encoding="UTF-8"?>' + "`n" + '<rss version="2.0"><channel><title>' + $siteName + ' &#183; ' + (Enc $site.tagline) + '</title><link>' + $baseUrl + '/</link><description>' + (Enc $site.description) + '</description><language>en</language>' + "`n" + $items + "`n</channel></rss>`n"
Write-Text ([IO.Path]::Combine($OutDir, 'feed.xml')) $feed

Write-Host ("Built {0} journal page(s) in {1} language(s) ({2}) into {3}" -f $entries.Count, $Langs.Count, ($Langs -join ', '), $OutDir)
