# export_for_drive.ps1
# Builds a clean, organized export folder ready to upload to Google Drive.
# Run from the project root:
#   cd C:\Users\jericho.james.guanga\projects\dermatrack-acne
#   .\export_for_drive.ps1

$ErrorActionPreference = "Stop"

$src  = $PSScriptRoot
$dest = Join-Path $PSScriptRoot "DermaTrack_System_Folder"

Write-Host ""
Write-Host "=== DermaTrack Google Drive Export ===" -ForegroundColor Cyan
Write-Host "Source : $src"
Write-Host "Output : $dest"
Write-Host ""

# ── Clean slate ────────────────────────────────────────────────────────────
if (Test-Path $dest) {
    Write-Host "Removing existing export folder..." -ForegroundColor Yellow
    Remove-Item $dest -Recurse -Force
}
New-Item -ItemType Directory -Path $dest | Out-Null

# ── Helper: copy a file list, preserving relative structure ────────────────
function Copy-Files($files, $destBase) {
    foreach ($f in $files) {
        if (Test-Path $f) {
            $rel  = [System.IO.Path]::GetFileName($f)
            $outP = Join-Path $destBase $rel
            $dir  = [System.IO.Path]::GetDirectoryName($outP)
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
            Copy-Item $f $outP -Force
        }
    }
}

# ── Helper: copy entire directory tree ────────────────────────────────────
function Copy-Dir($from, $to, $exclude = @()) {
    if (-not (Test-Path $from)) { return }
    New-Item -ItemType Directory -Path $to -Force | Out-Null
    $items = Get-ChildItem $from -Recurse
    foreach ($item in $items) {
        $skip = $false
        foreach ($ex in $exclude) {
            if ($item.FullName -like "*\$ex\*" -or $item.Name -eq $ex) { $skip = $true; break }
        }
        if ($skip) { continue }
        $rel  = $item.FullName.Substring($from.Length).TrimStart('\')
        $outP = Join-Path $to $rel
        if ($item.PSIsContainer) {
            New-Item -ItemType Directory -Path $outP -Force | Out-Null
        } else {
            $dir = [System.IO.Path]::GetDirectoryName($outP)
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
            Copy-Item $item.FullName $outP -Force
        }
    }
}

# ══════════════════════════════════════════════════════════════════════════
# 1. README / Setup Guide
# ══════════════════════════════════════════════════════════════════════════
Write-Host "1/7  Copying setup guides..." -ForegroundColor Green
$guidesDest = Join-Path $dest "1_README_AND_SETUP"
New-Item -ItemType Directory -Path $guidesDest | Out-Null

$guides = @(
    "$src\PANELIST_SETUP_GUIDE.md",
    "$src\README.md",
    "$src\SETUP_GUIDE_FOR_CO_AUTHOR.md",
    "$src\HANDOFF.md"
)
Copy-Files $guides $guidesDest

# ══════════════════════════════════════════════════════════════════════════
# 2. Full Flutter Project (app/)
# ══════════════════════════════════════════════════════════════════════════
Write-Host "2/7  Copying Flutter project..." -ForegroundColor Green
$flutterDest = Join-Path $dest "2_Flutter_Project"

# lib/ — all Dart source
Copy-Dir "$src\app\lib" "$flutterDest\lib"

# pubspec files
Copy-Files @("$src\app\pubspec.yaml", "$src\app\pubspec.lock") $flutterDest

# analysis options
if (Test-Path "$src\app\analysis_options.yaml") {
    Copy-Item "$src\app\analysis_options.yaml" "$flutterDest\analysis_options.yaml"
}

# test/
Copy-Dir "$src\app\test" "$flutterDest\test"

Write-Host "    lib/ : $(( Get-ChildItem "$src\app\lib" -Recurse -Filter '*.dart' ).Count) Dart files" -ForegroundColor Gray

# ══════════════════════════════════════════════════════════════════════════
# 3. Assets
# ══════════════════════════════════════════════════════════════════════════
Write-Host "3/7  Copying assets..." -ForegroundColor Green
$assetsDest = Join-Path $dest "3_Assets"
Copy-Dir "$src\app\assets" "$assetsDest\assets"

# ══════════════════════════════════════════════════════════════════════════
# 4. Supabase — Config, Migrations, Schema
# ══════════════════════════════════════════════════════════════════════════
Write-Host "4/7  Copying Supabase config & migrations..." -ForegroundColor Green
$sbDest = Join-Path $dest "4_Supabase_Configuration"
New-Item -ItemType Directory -Path $sbDest | Out-Null

# migrations/
Copy-Dir "$src\supabase\migrations" "$sbDest\migrations"

# schema files
$schemaFiles = @(
    "$src\supabase\full_schema.sql",
    "$src\supabase\schema.md",
    "$src\supabase\apply_to_live_db.sql"
)
Copy-Files $schemaFiles $sbDest

# config.toml if present
if (Test-Path "$src\supabase\config.toml") {
    Copy-Item "$src\supabase\config.toml" "$sbDest\config.toml"
}

Write-Host "    Migrations: $(( Get-ChildItem "$src\supabase\migrations" -Filter '*.sql' ).Count) files" -ForegroundColor Gray

# ══════════════════════════════════════════════════════════════════════════
# 5. Supabase Edge Functions
# ══════════════════════════════════════════════════════════════════════════
Write-Host "5/7  Copying Edge Functions..." -ForegroundColor Green
$fnDest = Join-Path $dest "5_Supabase_Edge_Functions"
Copy-Dir "$src\supabase\functions" $fnDest

# ══════════════════════════════════════════════════════════════════════════
# 6. Android Build Files
# ══════════════════════════════════════════════════════════════════════════
Write-Host "6/7  Copying Android build files..." -ForegroundColor Green
$androidDest = Join-Path $dest "6_Android_Build_Files"
New-Item -ItemType Directory -Path $androidDest | Out-Null

# Key Android files only (no generated build cache)
$androidFiles = @(
    "$src\app\android\app\src\main\AndroidManifest.xml",
    "$src\app\android\app\build.gradle.kts",
    "$src\app\android\app\proguard-rules.pro"
)
Copy-Files $androidFiles $androidDest

# res/ (icons, splash, drawables)
Copy-Dir "$src\app\android\app\src\main\res" "$androidDest\res" -exclude @("build")

# MainActivity
$ktSrc = "$src\app\android\app\src\main\kotlin"
if (Test-Path $ktSrc) {
    Copy-Dir $ktSrc "$androidDest\kotlin"
}

# gradle wrapper
$gradleSrc = "$src\app\android\gradle\wrapper"
if (Test-Path $gradleSrc) {
    Copy-Dir $gradleSrc "$androidDest\gradle\wrapper"
}

# ══════════════════════════════════════════════════════════════════════════
# 7. Thesis Documentation & Diagrams
# ══════════════════════════════════════════════════════════════════════════
Write-Host "7/7  Copying thesis docs & diagrams..." -ForegroundColor Green
$thesisDest = Join-Path $dest "7_Thesis_Documentation"
Copy-Dir "$src\thesis-docs" $thesisDest

# ══════════════════════════════════════════════════════════════════════════
# Summary
# ══════════════════════════════════════════════════════════════════════════
$totalFiles = (Get-ChildItem $dest -Recurse -File).Count
$totalSizeMB = [math]::Round(((Get-ChildItem $dest -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB), 2)

Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host " Export complete!" -ForegroundColor Green
Write-Host " Folder : $dest"
Write-Host " Files  : $totalFiles"
Write-Host " Size   : ${totalSizeMB} MB"
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next step: Upload the 'DermaTrack_System_Folder' to Google Drive." -ForegroundColor Yellow
Write-Host "  1. Open Google Drive in your browser"
Write-Host "  2. Click '+ New' → 'Folder upload'"
Write-Host "  3. Select: $dest"
Write-Host ""
