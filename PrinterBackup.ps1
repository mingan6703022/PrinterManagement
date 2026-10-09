#requires -version 5.1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    try {
        $powershellPath = Join-Path $PSHOME 'powershell.exe'
        $quotedScript = '"' + $PSCommandPath.Replace('"', '\"') + '"'
        Start-Process -FilePath $powershellPath -ArgumentList @('-NoLogo', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $quotedScript) -Verb RunAs -WindowStyle Hidden -WorkingDirectory (Split-Path -Parent $PSCommandPath)
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show('需要管理員權限才能匯出或匯入印表機。請重新啟動並允許 UAC 提示。', '印表機設定搬家工具', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
    }
    exit
}

[System.Windows.Forms.Application]::EnableVisualStyles()

function Get-PrintBrmPath {
    $candidates = New-Object System.Collections.Generic.List[string]
    if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
        $candidates.Add((Join-Path $env:windir 'Sysnative\spool\tools\PrintBrm.exe'))
    }
    $candidates.Add((Join-Path $env:windir 'System32\spool\tools\PrintBrm.exe'))
    $candidates.Add((Join-Path $env:windir 'SysWOW64\spool\tools\PrintBrm.exe'))
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-SystemSummary {
    $caption = 'Windows'
    $build = 0
    $architecture = [Environment]::GetEnvironmentVariable('PROCESSOR_ARCHITECTURE')
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        $caption = [string]$os.Caption
        $build = [int]$os.BuildNumber
        $architecture = [string]$os.OSArchitecture
    }
    catch {
        try {
            $currentVersion = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
            $caption = [string]$currentVersion.ProductName
            $build = [int]$currentVersion.CurrentBuildNumber
        }
        catch { }
    }
    if ($caption -match 'Windows 10' -and $build -ge 22000) { $caption = $caption -replace 'Windows 10', 'Windows 11' }
    $supported = ($caption -match 'Windows 10' -and $build -ge 10240 -and $build -lt 22000) -or
                 ($caption -match 'Windows 11' -and $build -ge 22000) -or
                 ($caption -match 'Windows Server 2022|Windows Server 2025')
    return [pscustomobject]@{ Caption = $caption; Build = $build; Architecture = $architecture; Supported = [bool]$supported }
}

function ConvertTo-CommandLineArgument([string]$Value) {
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = $Value.Replace('"', '\"')
    return '"' + $escaped + '"'
}

function Read-PrintBrmOutput([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    if ($bytes.Length -eq 0) { return '' }
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        return [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        return [Text.Encoding]::BigEndianUnicode.GetString($bytes, 2, $bytes.Length - 2)
    }
    try {
        $strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
        return $strictUtf8.GetString($bytes)
    }
    catch {
        try {
            $oemCodePage = [Globalization.CultureInfo]::CurrentCulture.TextInfo.OEMCodePage
            return [Text.Encoding]::GetEncoding($oemCodePage).GetString($bytes)
        }
        catch {
            return [Text.Encoding]::Default.GetString($bytes)
        }
    }
}

function Format-PrintBrmOutput([string]$Text) {
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $formatted = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $formatted = [regex]::Replace($formatted, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    $formatted = [regex]::Replace($formatted, '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
    $formatted = [regex]::Replace($formatted, '(?m)^[ \t]*\*{4,}[^\n]*\*{4,}[ \t]*$', '')
    return $formatted.Trim()
}

$script:brmPath = Get-PrintBrmPath
$script:systemSummary = Get-SystemSummary
$script:installState = if ($script:brmPath) { 'Ready' } else { 'NotStarted' }
$script:spoolerStatus = '無法讀取'
try { $script:spoolerStatus = (Get-Service -Name Spooler -ErrorAction Stop).Status.ToString() } catch { }

$form = New-Object System.Windows.Forms.Form
$form.Text = '印表機設定搬家工具'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(900, 700)
$form.MinimumSize = New-Object System.Drawing.Size(820, 640)
$form.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10)
$form.BackColor = [System.Drawing.Color]::FromArgb(246, 248, 251)

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 102
$header.BackColor = [System.Drawing.Color]::FromArgb(24, 54, 92)
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = '印表機設定搬家工具'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 20, [System.Drawing.FontStyle]::Bold)
$title.AutoSize = $true
$title.Location = New-Object System.Drawing.Point(24, 16)
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = '一鍵備份或還原印表機、驅動程式、連接埠與紙張表單'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(220, 231, 245)
$subtitle.AutoSize = $true
$subtitle.Location = New-Object System.Drawing.Point(28, 62)
$header.Controls.Add($subtitle)

$statusGroup = New-Object System.Windows.Forms.GroupBox
$statusGroup.Text = '電腦狀態'
$statusGroup.Location = New-Object System.Drawing.Point(22, 118)
$statusGroup.Size = New-Object System.Drawing.Size(840, 115)
$statusGroup.Anchor = 'Top,Left,Right'
$form.Controls.Add($statusGroup)

$osLabel = New-Object System.Windows.Forms.Label
$osLabel.AutoSize = $true
$osLabel.Location = New-Object System.Drawing.Point(18, 28)
$osText = if ($script:systemSummary.Supported) { '支援' } else { '未列入支援清單' }
$osLabel.Text = ('作業系統：{0}（組建 {1}，{2}）— {3}' -f $script:systemSummary.Caption, $script:systemSummary.Build, $script:systemSummary.Architecture, $osText)
$statusGroup.Controls.Add($osLabel)

$brmLabel = New-Object System.Windows.Forms.Label
$brmLabel.AutoSize = $true
$brmLabel.Location = New-Object System.Drawing.Point(18, 55)
$brmLabel.Text = if ($script:brmPath) { 'PrintBRM：已找到 Windows 內建工具' } else { 'PrintBRM：未找到，啟動時將自動下載安裝' }
$statusGroup.Controls.Add($brmLabel)

$spoolerLabel = New-Object System.Windows.Forms.Label
$spoolerLabel.AutoSize = $true
$spoolerLabel.Location = New-Object System.Drawing.Point(18, 82)
$spoolerLabel.Text = 'Print Spooler：' + $script:spoolerStatus
$statusGroup.Controls.Add($spoolerLabel)

$helpLabel = New-Object System.Windows.Forms.Label
$helpLabel.AutoSize = $false
$helpLabel.Location = New-Object System.Drawing.Point(25, 246)
$helpLabel.Size = New-Object System.Drawing.Size(830, 48)
$helpLabel.Anchor = 'Top,Left,Right'
$helpLabel.ForeColor = [System.Drawing.Color]::FromArgb(65, 76, 92)
$helpLabel.Text = '請在原電腦按「匯出備份」，將 .printerExport 檔帶到新電腦，再按「匯入還原」。匯入會更新同名佇列，並新增備份中的項目。'
$form.Controls.Add($helpLabel)

$exportButton = New-Object System.Windows.Forms.Button
$exportButton.Text = '匯出備份'
$exportButton.Location = New-Object System.Drawing.Point(25, 302)
$exportButton.Size = New-Object System.Drawing.Size(170, 48)
$exportButton.BackColor = [System.Drawing.Color]::FromArgb(34, 105, 178)
$exportButton.ForeColor = [System.Drawing.Color]::White
$exportButton.FlatStyle = 'Flat'
$exportButton.FlatAppearance.BorderSize = 0
$exportButton.Cursor = 'Hand'
$form.Controls.Add($exportButton)

$importButton = New-Object System.Windows.Forms.Button
$importButton.Text = '匯入還原'
$importButton.Location = New-Object System.Drawing.Point(210, 302)
$importButton.Size = New-Object System.Drawing.Size(170, 48)
$importButton.BackColor = [System.Drawing.Color]::FromArgb(46, 125, 80)
$importButton.ForeColor = [System.Drawing.Color]::White
$importButton.FlatStyle = 'Flat'
$importButton.FlatAppearance.BorderSize = 0
$importButton.Cursor = 'Hand'
$form.Controls.Add($importButton)

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = New-Object System.Drawing.Point(25, 366)
$progress.Size = New-Object System.Drawing.Size(830, 12)
$progress.Anchor = 'Top,Left,Right'
$progress.Style = 'Continuous'
$form.Controls.Add($progress)

$logTitle = New-Object System.Windows.Forms.Label
$logTitle.Text = '執行紀錄'
$logTitle.AutoSize = $true
$logTitle.Location = New-Object System.Drawing.Point(25, 392)
$logTitle.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($logTitle)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Location = New-Object System.Drawing.Point(25, 420)
$logBox.Size = New-Object System.Drawing.Size(830, 170)
$logBox.Anchor = 'Top,Bottom,Left,Right'
$logBox.Multiline = $true
$logBox.ReadOnly = $true
$logBox.ScrollBars = 'Vertical'
$logBox.BackColor = [System.Drawing.Color]::White
$logBox.Font = New-Object System.Drawing.Font('Microsoft JhengHei UI', 9)
$form.Controls.Add($logBox)

$footnote = New-Object System.Windows.Forms.Label
$footnote.AutoSize = $false
$footnote.Location = New-Object System.Drawing.Point(25, 601)
$footnote.Size = New-Object System.Drawing.Size(830, 42)
$footnote.Anchor = 'Bottom,Left,Right'
$footnote.ForeColor = [System.Drawing.Color]::FromArgb(88, 96, 108)
$footnote.Text = '備份檔包含 Windows PrintBRM 支援的佇列、驅動程式、連接埠、共用資訊與自訂紙張表單。印表機廠商的掃描工具、帳號憑證及特定機型附加程式不在備份範圍。'
$form.Controls.Add($footnote)

$script:activeProcess = $null
$script:stdoutPath = $null
$script:stderrPath = $null
$jobTimer = New-Object System.Windows.Forms.Timer
$jobTimer.Interval = 500

function Complete-PrinterJob([int]$ExitCode, [string]$StdOut, [string]$StdErr, [string]$FailureDetails) {
    $progress.Style = 'Continuous'
    if ($script:activeJob.Operation -eq 'Install') {
        $script:brmPath = Get-PrintBrmPath
        if ($StdOut) { $logBox.AppendText($StdOut.Trim() + "`r`n") }
        if ($StdErr) { $logBox.AppendText($StdErr.Trim() + "`r`n") }
        if ($ExitCode -eq 0 -and $script:brmPath) {
            $script:installState = 'Ready'
            $brmLabel.Text = 'PrintBRM：已自動安裝並找到 Windows 工具'
            $exportButton.Enabled = $true
            $importButton.Enabled = $true
            $logBox.AppendText("Windows 列印管理元件安裝完成，可開始匯出或匯入。`r`n")
        }
        else {
            $script:installState = 'Failed'
            $brmLabel.Text = 'PrintBRM：自動安裝失敗'
            $exportButton.Enabled = $false
            $importButton.Enabled = $false
            $installDetails = $FailureDetails
            if ([string]::IsNullOrWhiteSpace($installDetails)) {
                $installDetails = (($StdErr + "`r`n" + $StdOut).Trim())
            }
            if ([string]::IsNullOrWhiteSpace($installDetails)) {
                $installDetails = "Windows 安裝程序結束碼：$ExitCode。此元件需要從 Windows Update 或組織設定的 Features on Demand 來源取得；請確認網路、Windows Update／WSUS 原則，並查看 DISM 記錄。"
            }
            $logBox.AppendText("`r`nWindows 列印管理元件未能安裝：`r`n$installDetails`r`n")
            [System.Windows.Forms.MessageBox]::Show($installDetails, '自動安裝失敗', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        return
    }
    $exportButton.Enabled = $true
    $importButton.Enabled = $true
    if (-not [string]::IsNullOrWhiteSpace($FailureDetails)) {
        $logBox.AppendText("`r`n作業失敗：`r`n$FailureDetails`r`n")
        [System.Windows.Forms.MessageBox]::Show($FailureDetails, '作業失敗', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
    else {
        if ($StdOut) { $logBox.AppendText($StdOut.Trim() + "`r`n") }
        if ($StdErr) { $logBox.AppendText($StdErr.Trim() + "`r`n") }
        if ($ExitCode -eq 0) {
            $logBox.AppendText("完成：$($script:activeJob.FilePath)`r`n")
            [System.Windows.Forms.MessageBox]::Show("作業完成。`r`n`r`n檔案：$($script:activeJob.FilePath)`r`n`r`n建議確認「應用程式及服務記錄 > Microsoft > PrintBRM > Admin」，查看每個佇列及驅動程式是否都成功處理。", '完成', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
        else {
            $logBox.AppendText("PrintBRM 結束碼：$ExitCode`r`n")
            [System.Windows.Forms.MessageBox]::Show("PrintBRM 作業未成功完成（結束碼 $ExitCode）。請查看上方輸出與 Windows 事件檢視器中的 PrintBRM 記錄。", '作業失敗', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
        try { $script:spoolerStatus = (Get-Service -Name Spooler).Status.ToString(); $spoolerLabel.Text = 'Print Spooler：' + $script:spoolerStatus } catch { }
    }
}

$jobTimer.add_Tick({
    if (-not $script:activeProcess) { $jobTimer.Stop(); return }
    $jobFinished = $false
    try {
        $script:activeProcess.Refresh()
        if (-not $script:activeProcess.HasExited) { return }
        $jobFinished = $true
        $exitCode = $script:activeProcess.ExitCode
        $stdout = if ($script:stdoutPath) { Format-PrintBrmOutput (Read-PrintBrmOutput $script:stdoutPath) } else { '' }
        $stderr = if ($script:stderrPath) { Format-PrintBrmOutput (Read-PrintBrmOutput $script:stderrPath) } else { '' }
        $script:activeProcess.Dispose()
        $script:activeProcess = $null
        Complete-PrinterJob -ExitCode $exitCode -StdOut $stdout -StdErr $stderr -FailureDetails ''
    }
    catch {
        $jobFinished = $true
        $failureDetails = $_.Exception.ToString()
        if ([string]::IsNullOrWhiteSpace($failureDetails)) { $failureDetails = $_.ToString() }
        if ($script:activeProcess) {
            try { $script:activeProcess.Dispose() } catch { }
            $script:activeProcess = $null
        }
        Complete-PrinterJob -ExitCode -1 -StdOut '' -StdErr '' -FailureDetails $failureDetails
    }
    if ($jobFinished) {
        foreach ($tempPath in @($script:stdoutPath, $script:stderrPath)) {
            if ($tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        }
        $script:stdoutPath = $null
        $script:stderrPath = $null
    }
})

function Start-TrackedProcess([string]$Executable, [string]$Arguments, [string]$Operation, [string]$Description) {
    $script:activeJob = [pscustomobject]@{ Operation = $Operation; FilePath = $Description }
    $tempPrefix = 'PrinterBackup-' + [Guid]::NewGuid().ToString('N')
    $script:stdoutPath = Join-Path ([IO.Path]::GetTempPath()) ($tempPrefix + '.out.log')
    $script:stderrPath = Join-Path ([IO.Path]::GetTempPath()) ($tempPrefix + '.err.log')
    try {
        $script:activeProcess = Start-Process -FilePath $Executable -ArgumentList $Arguments -PassThru -WindowStyle Hidden -RedirectStandardOutput $script:stdoutPath -RedirectStandardError $script:stderrPath
        $exportButton.Enabled = $false
        $importButton.Enabled = $false
        $progress.Style = 'Marquee'
        $jobTimer.Start()
    }
    catch {
        $failureDetails = $_.Exception.ToString()
        if ([string]::IsNullOrWhiteSpace($failureDetails)) { $failureDetails = $_.ToString() }
        foreach ($tempPath in @($script:stdoutPath, $script:stderrPath)) {
            if ($tempPath) { Remove-Item -LiteralPath $tempPath -Force -ErrorAction SilentlyContinue }
        }
        $script:stdoutPath = $null
        $script:stderrPath = $null
        if ($Operation -eq 'Install') {
            $script:installState = 'Failed'
            $brmLabel.Text = 'PrintBRM：自動安裝失敗'
        }
        $logBox.AppendText("`r`n無法啟動 $Description：`r`n$failureDetails`r`n")
        [System.Windows.Forms.MessageBox]::Show($failureDetails, '無法啟動工作', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

function Start-PrintBrmInstall {
    $script:installState = 'Installing'
    $brmLabel.Text = 'PrintBRM：正在下載並安裝 Windows 列印管理工具'
    $logBox.AppendText("PrintBRM 不存在，正在透過 Windows 官方元件來源自動下載並安裝列印管理工具。`r`n")
    if ($script:systemSummary.Caption -match 'Windows Server') {
        $installScript = @'
Import-Module ServerManager -ErrorAction Stop
$feature = Get-WindowsFeature -Name 'RSAT-Print-Services' -ErrorAction Stop
if (-not $feature) { throw 'RSAT-Print-Services is not available on this Windows Server installation.' }
$result = Install-WindowsFeature -Name 'RSAT-Print-Services' -IncludeAllSubFeature -ErrorAction Stop
if (-not $result.Success) { exit 1 }
exit 0
'@
        $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($installScript))
        $executable = Join-Path $PSHOME 'powershell.exe'
        $arguments = '-NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encodedCommand
        Start-TrackedProcess -Executable $executable -Arguments $arguments -Operation 'Install' -Description 'Windows Server 列印管理工具'
    }
    else {
        $executable = Join-Path $env:windir 'System32\dism.exe'
        if ([Environment]::Is64BitOperatingSystem -and -not [Environment]::Is64BitProcess) {
            $executable = Join-Path $env:windir 'Sysnative\dism.exe'
        }
        $arguments = '/Online /Add-Capability /CapabilityName:Print.Management.Console~~~~0.0.1.0'
        Start-TrackedProcess -Executable $executable -Arguments $arguments -Operation 'Install' -Description 'Windows 列印管理工具'
    }
}

function Start-PrinterJob([string]$Operation, [string]$FilePath) {
    if (-not $script:brmPath) {
        [System.Windows.Forms.MessageBox]::Show('此電腦尚未安裝 PrintBRM。請等待自動安裝完成，或重新啟動程式重試。', '缺少 Windows 元件', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if ($script:spoolerStatus -ne 'Running') {
        [System.Windows.Forms.MessageBox]::Show('Print Spooler 服務目前沒有執行。請先在 Windows 服務中啟動「Print Spooler／列印多工緩衝處理器」，然後重試。', '列印服務未啟動', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    if ([string]::IsNullOrWhiteSpace($FilePath)) { return }
    if ($Operation -eq 'Import') {
        $answer = [System.Windows.Forms.MessageBox]::Show("確定要匯入這份備份嗎？`r`n`r`n同名印表機佇列的設定可能會被更新；備份內其他佇列與驅動程式也會加入此電腦。`r`n`r`n$FilePath", '確認匯入', [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    }
    $verb = if ($Operation -eq 'Export') { '匯出' } else { '匯入' }
    $logBox.AppendText("開始$verb：$FilePath`r`n")
    $operationArgument = if ($Operation -eq 'Export') { '-b' } else { '-r' }
    $arguments = $operationArgument + ' -f ' + (ConvertTo-CommandLineArgument $FilePath)
    Start-TrackedProcess -Executable $script:brmPath -Arguments $arguments -Operation $Operation -Description $FilePath
}

$exportButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.SaveFileDialog
    $dialog.Title = '選擇印表機備份位置'
    $dialog.Filter = '印表機備份 (*.printerExport)|*.printerExport|所有檔案 (*.*)|*.*'
    $dialog.DefaultExt = 'printerExport'
    $dialog.AddExtension = $true
    $dialog.FileName = ('{0}-{1}.printerExport' -f $env:COMPUTERNAME, (Get-Date -Format 'yyyyMMdd-HHmm'))
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        Start-PrinterJob -Operation 'Export' -FilePath $dialog.FileName
    }
    $dialog.Dispose()
})

$importButton.Add_Click({
    $dialog = New-Object System.Windows.Forms.OpenFileDialog
    $dialog.Title = '選擇要還原的印表機備份'
    $dialog.Filter = '印表機備份 (*.printerExport)|*.printerExport|所有檔案 (*.*)|*.*'
    $dialog.CheckFileExists = $true
    if ($dialog.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) {
        Start-PrinterJob -Operation 'Import' -FilePath $dialog.FileName
    }
    $dialog.Dispose()
})

$form.Add_Shown({
    $logBox.AppendText(('已就緒。系統：{0}；PrintBRM：{1}；管理員：是。' -f $script:systemSummary.Caption, $(if ($script:brmPath) { '可用' } else { '未找到' })) + "`r`n")
    if (-not $script:systemSummary.Supported) { $logBox.AppendText('注意：此 Windows 版本未列入目標清單，請先確認 PrintBRM 是否適用。' + "`r`n") }
    if (-not $script:brmPath) {
        $exportButton.Enabled = $false
        $importButton.Enabled = $false
        Start-PrintBrmInstall
    }
})

[void]$form.ShowDialog()
