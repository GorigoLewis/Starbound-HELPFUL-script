# SB_Manager.ps1
$configPath = Join-Path $PSScriptRoot "sb_manager.cfg"
$reportFile = Join-Path $PSScriptRoot "mods_report.txt"
$logFile = Join-Path $PSScriptRoot "mods.log"

$paths = @{
    Workshop = ""
    Mods = ""
    ServerExe = ""
}

function Show-Header {
    Clear-Host
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host " STARBOUND SERVER MANAGER v2.0 " -ForegroundColor White -BackgroundColor DarkMagenta
    Write-Host "==============================================" -ForegroundColor Cyan
    Write-Host ""
}

function Log-Message {
    param([string]$message)
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $message" | Add-Content $logFile
}

function Initialize-Config {
    Show-Header
    Write-Host " Initial Configuration Setup " -ForegroundColor Yellow -BackgroundColor DarkGray
    $paths.Workshop = Read-Host "`nEnter Workshop path (e.g. D:\SteamLibrary\steamapps\workshop\content\211820)"
    $paths.Mods = Read-Host "Enter Mods folder path (e.g. D:\SteamLibrary\steamapps\common\Starbound\mods)"
    $paths.ServerExe = Read-Host "Enter Server EXE path (e.g. D:\SteamLibrary\steamapps\common\Starbound\win64\starbound_server.exe)"
    
    $paths | ConvertTo-Json | Set-Content $configPath -Force
    Write-Host "`nConfiguration saved!" -ForegroundColor Green
    Start-Sleep -Seconds 2
}

function Load-Config {
    if (Test-Path $configPath) {
        try {
            $config = Get-Content $configPath | ConvertFrom-Json
            $paths.Workshop = $config.Workshop
            $paths.Mods = $config.Mods
            $paths.ServerExe = $config.ServerExe
        }
        catch {
            Write-Host "Error loading config! Reinitializing..." -ForegroundColor Red
            Initialize-Config
        }
    }
    else {
        Initialize-Config
    }
}

function Show-Progress {
    param(
        [int]$total,
        [int]$current,
        [string]$activity,
        [string]$status
    )
    $percent = ($current / $total) * 100
    Write-Progress -Activity $activity -Status $status -PercentComplete $percent
}

function Process-Mods {
    $warnings = @()
    $errors = @()
    $processed = 0
    $totalMods = 0

    try {
        # Deleting only Workshop-mods
        $itemsToRemove = Get-ChildItem $paths.Mods | Where-Object {
            $_.Name -match '^\d+$' -or    # Folders with ID
            $_.Name -match '^\d+\.pak$'   # .pak files with ID
        }
        
        if ($itemsToRemove) {
            Write-Host "[INFO] Removing old Workshop mods..." -ForegroundColor DarkGray
            $itemsToRemove | Remove-Item -Recurse -Force
        }

        # Get workshop mods
        $workshopFolders = @(Get-ChildItem $paths.Workshop -Directory -ErrorAction Stop | Where-Object { $_.Name -match '^\d+$' })
        $totalMods = $workshopFolders.Count
        
        if ($totalMods -eq 0) {
            Write-Host "[ERROR] No mods found in Workshop folder!" -ForegroundColor Red
            return $false
        }

        # Processing
        Write-Host "`n[STATUS] Found $totalMods mods to process" -ForegroundColor Cyan
        
        for ($i = 0; $i -lt $workshopFolders.Count; $i++) {
            $folder = $workshopFolders[$i]
            $modId = $folder.Name
            
            Show-Progress -total $workshopFolders.Count -current ($i+1) `
                -activity "Processing Mods" -status "Mod ID: $modId ($($i+1)/$totalMods)"

            try {
                $contentPak = Join-Path $folder.FullName "contents.pak"
                
                if (Test-Path $contentPak) {
                    $dest = Join-Path $paths.Mods "$modId.pak"
                    Copy-Item $contentPak $dest -Force
                    $processed++
                }
                else {
                    $customFiles = Get-ChildItem $folder.FullName -File -Filter *.pak
                    if ($customFiles) {
                        $destFolder = Join-Path $paths.Mods $modId
                        New-Item $destFolder -ItemType Directory -Force | Out-Null
                        $customFiles | Copy-Item -Destination $destFolder -Force
                        $processed++
                    }
                    else {
                        $warnings += $modId
                    }
                }
            }
            catch {
                $errors += $modId
            }
        }

        # Generate report
        $reportContent = @"
=== MOD PROCESSING REPORT ===
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

[STATISTICS]
Total Workshop Mods: $totalMods
Successfully processed: $processed
Warnings: $($warnings.Count)
Errors: $($errors.Count)

[WARNINGS]
$($warnings -join "`n")

[ERRORS]
$($errors -join "`n")

[NOTE] Custom mods (non-numeric names) were preserved

[RECOMMENDATIONS]
1. Verify Workshop subscriptions for missing mods
2. Check mod compatibility
3. Re-subscribe to problematic mods
"@
        Set-Content $reportFile -Value $reportContent -Encoding UTF8
        Invoke-Item $reportFile

        return ($errors.Count -eq 0)
    }
    catch {
        Write-Host "[FATAL] $_" -ForegroundColor Red
        return $false
    }
}

function Start-Server {
    try {
        Write-Host "`n[STATUS] Starting Starbound server..." -ForegroundColor Cyan
        Start-Process $paths.ServerExe -ArgumentList "-bootconfig sbinit.config" -NoNewWindow -Wait
    }
    catch {
        Write-Host "[ERROR] Failed to start server: $_" -ForegroundColor Red
    }
}

function Show-MainMenu {
    Show-Header
    Write-Host " MAIN MENU " -ForegroundColor White -BackgroundColor DarkBlue
    Write-Host ""
    Write-Host " 1. Update mods and start server" -ForegroundColor Green
    Write-Host " 2. Update mods only" -ForegroundColor Yellow
    Write-Host " 3. Start server without update" -ForegroundColor Cyan
    Write-Host " 4. Exit" -ForegroundColor Gray
    Write-Host ""
}

# Main execution flow
try {
    Load-Config

    do {
        Show-MainMenu
        $choice = Read-Host "`nEnter your choice (1-4)"

        switch ($choice) {
            '1' {
                if (Process-Mods) {
                    Write-Host "`n[SUCCESS] Mods updated successfully!" -ForegroundColor Green
                    Start-Server
                }
                else {
                    Write-Host "`n[WARNING] Mod update completed with issues!" -ForegroundColor Yellow
                }
                pause
            }
            '2' {
                if (Process-Mods) {
                    Write-Host "`n[SUCCESS] Mods updated successfully!" -ForegroundColor Green
                }
                else {
                    Write-Host "`n[WARNING] Mod update completed with issues!" -ForegroundColor Yellow
                }
                pause
            }
            '3' {
                Start-Server
                pause
            }
            '4' { exit }
            default {
                Write-Host "`n[ERROR] Invalid selection!" -ForegroundColor Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($true)
}
catch {
    Write-Host "`n[CRITICAL ERROR] $_" -ForegroundColor White -BackgroundColor Red
    pause
}
