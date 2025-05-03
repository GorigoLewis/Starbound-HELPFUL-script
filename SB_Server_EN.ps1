# Configuration
$workshopPath = "D:\SteamLibrary\steamapps\workshop\content\211820"
$modsPath = "D:\SteamLibrary\steamapps\common\Starbound\mods"
$serverExe = "D:\SteamLibrary\steamapps\common\Starbound\win64\starbound_server.exe"
$reportFile = "mods_processing_report.txt"

function Process-Mod {
    param(
        [string]$folderPath,
        [string]$modId
    )
    
    $contentPak = "$folderPath\contents.pak"
    $hasContentPak = Test-Path $contentPak
    $otherFiles = Get-ChildItem $folderPath -Exclude .DS_Store, Thumbs.db, desktop.ini
    
    # Создаем запись в отчете
    $report = [PSCustomObject]@{
        ModID = $modId
        Status = "Pending"
        Type = ""
        Details = ""
    }

    try {
        if ($hasContentPak) {
            # Обработка стандартных модов
            $newName = "$modsPath\$modId.pak"
            Copy-Item $contentPak $newName -Force
            $report.Type = "PAK File"
            $report.Details = "Copied contents.pak as $modId.pak"
            $report.Status = "Success"
            return "pak"
        }
        elseif ($otherFiles.Count -gt 0) {
            # Обработка кастомных модов
            $modFolder = "$modsPath\$modId"
            if (Test-Path $modFolder) {
                Remove-Item $modFolder -Recurse -Force
            }
            New-Item -ItemType Directory -Path $modFolder | Out-Null
            
            # Копируем все файлы кроме системных
            Copy-Item "$folderPath\*" $modFolder -Recurse -Exclude .DS_Store, Thumbs.db, desktop.ini
            
            $report.Type = "Mod Folder"
            $report.Details = "Copied entire mod folder structure"
            $report.Status = "Success"
            return "folder"
        }
        else {
            $report.Type = "Empty"
            $report.Details = "No valid files found"
            $report.Status = "Warning"
            return "empty"
        }
    }
    catch {
        $report.Status = "Error"
        $report.Details = $_.Exception.Message
        return "error"
    }
    finally {
        $global:processingReport.Add($report) | Out-Null
    }
}

function Update-Mods {
    $global:processingReport = [System.Collections.Generic.List[object]]::new()
    $warningList = @()
    
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Starting mod processing..." -ForegroundColor Magenta
    
    try {
        # Удаляем только автоматически созданные файлы и папки
        Get-ChildItem $modsPath | Where-Object {
            $_.Name -match '^\d+\.pak$' -or 
            ($_.PSIsContainer -and $_.Name -match '^\d+$')
        } | Remove-Item -Recurse -Force -ErrorAction Stop
        
        Write-Host "[OK] Old mods cleaned" -ForegroundColor Green
    }
    catch {
        Write-Host "[ERROR] Cleanup failed: $_" -ForegroundColor Red
        return $false
    }

    $total = 0
    $errors = 0
    $warnings = 0
    $folders = @(Get-ChildItem $workshopPath -Directory)
    $i = 0
    
    foreach ($folder in $folders) {
        $i++
        $modId = $folder.Name
        
        Write-Progress -Activity "Processing mods" -Status "$modId ($i/$($folders.Count))" -PercentComplete ($i/$folders.Count*100)

        $result = Process-Mod -folderPath $folder.FullName -modId $modId
        
        switch ($result) {
            "pak" { $total++ }
            "folder" { $total++ }
            "error" { $errors++ }
            "empty" { $warnings++ }
        }
    }

    # Генерация отчета
    try {
        $reportContent = @"
=== MOD PROCESSING REPORT ===
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

Total Mods Processed: $($folders.Count)
Success: $total
Warnings: $warnings
Errors: $errors

[WARNING DETAILS]
$($global:processingReport | Where-Object {$_.Status -ne 'Success'} | Format-Table | Out-String)

[ADVICE]
1. For 'Mod Folder' types - ensure folder structure is correct
2. For 'Empty' mods - re-subscribe through Steam
3. Check mod compatibility for folder-based mods

Note: Folder-based mods must contain 'mod.info' and '_metadata' to work!
"@
        Set-Content -Path $reportFile -Value $reportContent -Encoding UTF8
        Invoke-Item $reportFile
    }
    catch {
        Write-Host "[ERROR] Report generation failed: $_" -ForegroundColor Red
    }

    Write-Progress -Completed -Activity "Processing mods"
    
    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Results:" -ForegroundColor Magenta
    Write-Host "Processed:  $total" -ForegroundColor Cyan
    Write-Host "Warnings:   $warnings" -ForegroundColor Yellow
    Write-Host "Errors:     $errors" -ForegroundColor Red
    
    return ($errors -eq 0)
}

function Start-Server {
    if (-not (Test-Path $serverExe)) {
        Write-Host "[ERROR] Server executable not found: $serverExe" -ForegroundColor Red
        pause
        return
    }

    Write-Host "`n[$(Get-Date -Format 'HH:mm:ss')] Starting server..." -ForegroundColor Cyan
    try {
        & $serverExe
    }
    catch {
        Write-Host "[ERROR] Failed to start server: $_" -ForegroundColor Red
    }
}

# Main menu
do {
    Clear-Host
    Write-Host "`n`t=== Starbound Server Manager ===" -ForegroundColor Cyan
    Write-Host "`n[1] Update mods and start server"
    Write-Host "[2] Start server without update"
    Write-Host "[Q] Exit`n"
    
    $choice = Read-Host "Enter your choice (1/2/Q)"
    
    switch ($choice.ToUpper()) {
        '1' {
            if (Update-Mods) {
                Start-Server
            }
            else {
                Write-Host "`n[WARN] Update completed with errors. Server start canceled." -ForegroundColor Yellow
                pause
            }
        }
        '2' { Start-Server }
        'Q' { exit }
        default {
            Write-Host "`n[ERROR] Invalid choice, try again" -ForegroundColor Red
            Start-Sleep -Seconds 1
        }
    }
} while ($true)
