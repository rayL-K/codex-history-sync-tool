param(
  [switch]$InstallShortcutOnly,
  [switch]$SmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$script:UiScriptPath = $MyInvocation.MyCommand.Path
$script:ToolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:BackendPath = Join-Path $script:ToolRoot 'sync_backend.py'
$script:ShortcutName = 'Codex 对话同步工具.lnk'
$script:IconLocation = 'C:\Windows\System32\imageres.dll,15'
$script:BackupMap = @{}
$script:LatestState = $null

function Invoke-Backend {
  param(
    [Parameter(Mandatory = $true)]
    [string[]]$Arguments
  )

  if (-not (Test-Path -LiteralPath $script:BackendPath)) {
    throw "缺少后端脚本: $script:BackendPath"
  }

  $output = & py -3 $script:BackendPath @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  $text = (($output | ForEach-Object { "$_" }) -join [Environment]::NewLine).Trim()
  if (-not $text) {
    throw '后端没有返回任何内容。'
  }

  try {
    $json = $text | ConvertFrom-Json
  } catch {
    throw "后端 JSON 解析失败。`r`n原始错误: $($_.Exception.Message)`r`n返回内容:`r`n$text"
  }

  if ($exitCode -ne 0 -or -not $json.ok) {
    if ($json.error) {
      throw [string]$json.error
    }
    throw "后端执行失败。`r`n$text"
  }

  return $json
}

function New-DesktopShortcut {
  $desktopPath = [Environment]::GetFolderPath('Desktop')
  $shortcutPath = Join-Path $desktopPath $script:ShortcutName
  $targetPath = Join-Path $PSHOME 'powershell.exe'
  $arguments = "-NoProfile -ExecutionPolicy Bypass -Sta -WindowStyle Hidden -File `"$script:UiScriptPath`""

  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $targetPath
  $shortcut.Arguments = $arguments
  $shortcut.WorkingDirectory = $script:ToolRoot
  $shortcut.IconLocation = $script:IconLocation
  $shortcut.Description = 'Codex history sync UI'
  $shortcut.Save()

  return $shortcutPath
}

if ($InstallShortcutOnly) {
  $createdShortcut = New-DesktopShortcut
  Write-Output "桌面快捷方式已创建: $createdShortcut"
  exit 0
}

function Append-Log {
  param([string]$Message)

  $timestamp = Get-Date -Format 'HH:mm:ss'
  $logBox.AppendText("[$timestamp] $Message`r`n")
  $logBox.SelectionStart = $logBox.TextLength
  $logBox.ScrollToCaret()
}

function Format-Counts {
  param($Counts)

  if (-not $Counts -or $Counts.Count -eq 0) {
    return '无'
  }

  return (($Counts | ForEach-Object { "$($_.provider)=$($_.count)" }) -join ', ')
}

function Format-ModelCounts {
  param($Counts)

  if (-not $Counts -or $Counts.Count -eq 0) {
    return '无'
  }

  return (($Counts | ForEach-Object { "$($_.model)=$($_.count)" }) -join ', ')
}

function Refresh-State {
  $status = Invoke-Backend @('--json', 'status')
  $script:LatestState = $status

  $providerLabel.Text = "当前 provider: $($status.current_provider)    需同步 provider 线程: $($status.provider_movable_threads)"
  $modelLabel.Text = if ($status.current_model) { "当前模型: $($status.current_model)    需同步模型线程: $($status.model_movable_threads)" } else { '当前模型: 未读取到' }
  $summaryLabel.Text = "线程总数: $($status.total_threads)    可同步到当前 provider/model 的线程: $($status.movable_threads)"
  $pathLabel.Text = "数据库: $($status.db_path)"

  $providersView.Items.Clear()
  foreach ($row in $status.provider_counts) {
    $isCurrent = if ($row.provider -eq $status.current_provider) { '是' } else { '' }
    $item = New-Object System.Windows.Forms.ListViewItem([string]$row.provider)
    [void]$item.SubItems.Add([string]$row.count)
    [void]$item.SubItems.Add($isCurrent)
    [void]$providersView.Items.Add($item)
  }

  $backupList.Items.Clear()
  $script:BackupMap = @{}
  foreach ($backup in $status.backups) {
    $label = "$($backup.modified_at)    $($backup.name)"
    $script:BackupMap[$label] = $backup.path
    [void]$backupList.Items.Add($label)
  }

  Append-Log "状态已刷新。当前 provider=$($status.current_provider)，当前模型=$($status.current_model)，可同步线程=$($status.movable_threads)。"
}

function Confirm-Action {
  param(
    [string]$Message,
    [string]$Title = '确认操作'
  )

  $choice = [System.Windows.Forms.MessageBox]::Show(
    $Message,
    $Title,
    [System.Windows.Forms.MessageBoxButtons]::OKCancel,
    [System.Windows.Forms.MessageBoxIcon]::Question
  )

  return $choice -eq [System.Windows.Forms.DialogResult]::OK
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Codex 历史同步工具'
$form.StartPosition = 'CenterScreen'
$form.Size = New-Object System.Drawing.Size(860, 640)
$form.MinimumSize = New-Object System.Drawing.Size(860, 640)
$form.BackColor = [System.Drawing.Color]::FromArgb(247, 248, 250)
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 9)

$headerLabel = New-Object System.Windows.Forms.Label
$headerLabel.Text = 'Codex 历史同步工具'
$headerLabel.Font = New-Object System.Drawing.Font('Microsoft YaHei UI', 16, [System.Drawing.FontStyle]::Bold)
$headerLabel.AutoSize = $true
$headerLabel.Location = New-Object System.Drawing.Point(20, 18)
$form.Controls.Add($headerLabel)

$warningLabel = New-Object System.Windows.Forms.Label
$warningLabel.Text = '请先关闭 Codex Desktop 再做同步或恢复；否则 Codex 可能同时写库，导致同步不完整或被覆盖。'
$warningLabel.ForeColor = [System.Drawing.Color]::FromArgb(163, 64, 31)
$warningLabel.AutoSize = $true
$warningLabel.Location = New-Object System.Drawing.Point(22, 52)
$form.Controls.Add($warningLabel)

$providerLabel = New-Object System.Windows.Forms.Label
$providerLabel.Text = '当前 provider:'
$providerLabel.AutoSize = $true
$providerLabel.Location = New-Object System.Drawing.Point(22, 88)
$form.Controls.Add($providerLabel)

$modelLabel = New-Object System.Windows.Forms.Label
$modelLabel.Text = '当前模型:'
$modelLabel.AutoSize = $true
$modelLabel.Location = New-Object System.Drawing.Point(22, 112)
$form.Controls.Add($modelLabel)

$summaryLabel = New-Object System.Windows.Forms.Label
$summaryLabel.Text = '线程总数:'
$summaryLabel.AutoSize = $true
$summaryLabel.Location = New-Object System.Drawing.Point(22, 136)
$form.Controls.Add($summaryLabel)

$pathLabel = New-Object System.Windows.Forms.Label
$pathLabel.Text = '数据库:'
$pathLabel.AutoSize = $true
$pathLabel.Location = New-Object System.Drawing.Point(22, 160)
$pathLabel.MaximumSize = New-Object System.Drawing.Size(790, 0)
$form.Controls.Add($pathLabel)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = '刷新状态'
$refreshButton.Size = New-Object System.Drawing.Size(110, 34)
$refreshButton.Location = New-Object System.Drawing.Point(22, 200)
$form.Controls.Add($refreshButton)

$syncButton = New-Object System.Windows.Forms.Button
$syncButton.Text = '一键同步到当前'
$syncButton.Size = New-Object System.Drawing.Size(150, 34)
$syncButton.Location = New-Object System.Drawing.Point(142, 200)
$syncButton.BackColor = [System.Drawing.Color]::FromArgb(32, 91, 177)
$syncButton.ForeColor = [System.Drawing.Color]::White
$syncButton.FlatStyle = 'Flat'
$form.Controls.Add($syncButton)

$backupButton = New-Object System.Windows.Forms.Button
$backupButton.Text = '手动备份'
$backupButton.Size = New-Object System.Drawing.Size(110, 34)
$backupButton.Location = New-Object System.Drawing.Point(312, 200)
$form.Controls.Add($backupButton)

$openBackupsButton = New-Object System.Windows.Forms.Button
$openBackupsButton.Text = '打开备份目录'
$openBackupsButton.Size = New-Object System.Drawing.Size(120, 34)
$openBackupsButton.Location = New-Object System.Drawing.Point(442, 200)
$form.Controls.Add($openBackupsButton)

$shortcutButton = New-Object System.Windows.Forms.Button
$shortcutButton.Text = '重建桌面图标'
$shortcutButton.Size = New-Object System.Drawing.Size(120, 34)
$shortcutButton.Location = New-Object System.Drawing.Point(578, 200)
$form.Controls.Add($shortcutButton)

$providersBox = New-Object System.Windows.Forms.GroupBox
$providersBox.Text = 'Provider 统计'
$providersBox.Location = New-Object System.Drawing.Point(22, 252)
$providersBox.Size = New-Object System.Drawing.Size(370, 170)
$form.Controls.Add($providersBox)

$providersView = New-Object System.Windows.Forms.ListView
$providersView.View = 'Details'
$providersView.FullRowSelect = $true
$providersView.GridLines = $true
$providersView.Location = New-Object System.Drawing.Point(12, 26)
$providersView.Size = New-Object System.Drawing.Size(346, 132)
[void]$providersView.Columns.Add('Provider', 170)
[void]$providersView.Columns.Add('线程数', 80)
[void]$providersView.Columns.Add('当前', 60)
$providersBox.Controls.Add($providersView)

$backupsBox = New-Object System.Windows.Forms.GroupBox
$backupsBox.Text = '备份列表'
$backupsBox.Location = New-Object System.Drawing.Point(410, 252)
$backupsBox.Size = New-Object System.Drawing.Size(410, 170)
$form.Controls.Add($backupsBox)

$backupList = New-Object System.Windows.Forms.ListBox
$backupList.Location = New-Object System.Drawing.Point(12, 24)
$backupList.Size = New-Object System.Drawing.Size(386, 94)
$backupsBox.Controls.Add($backupList)

$restoreButton = New-Object System.Windows.Forms.Button
$restoreButton.Text = '恢复选中备份'
$restoreButton.Size = New-Object System.Drawing.Size(120, 32)
$restoreButton.Location = New-Object System.Drawing.Point(12, 126)
$backupsBox.Controls.Add($restoreButton)

$restoreLatestButton = New-Object System.Windows.Forms.Button
$restoreLatestButton.Text = '恢复最新备份'
$restoreLatestButton.Size = New-Object System.Drawing.Size(120, 32)
$restoreLatestButton.Location = New-Object System.Drawing.Point(146, 126)
$backupsBox.Controls.Add($restoreLatestButton)

$logBox = New-Object System.Windows.Forms.TextBox
$logBox.Multiline = $true
$logBox.ScrollBars = 'Vertical'
$logBox.ReadOnly = $true
$logBox.Location = New-Object System.Drawing.Point(22, 440)
$logBox.Size = New-Object System.Drawing.Size(798, 148)
$logBox.BackColor = [System.Drawing.Color]::White
$form.Controls.Add($logBox)

$refreshButton.Add_Click({
  try {
    Refresh-State
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '刷新失败', 'OK', 'Error') | Out-Null
    Append-Log "刷新失败: $($_.Exception.Message)"
  }
})

$syncButton.Add_Click({
  try {
    if (-not $script:LatestState) {
      Refresh-State
    }
    if ([int]$script:LatestState.movable_threads -le 0) {
      [System.Windows.Forms.MessageBox]::Show('当前已经全部归到正在使用的 provider/model 下面了。', '无需同步', 'OK', 'Information') | Out-Null
      Append-Log '同步跳过：没有需要迁移的线程。'
      return
    }
    $message = "请先关闭 Codex Desktop，再继续同步。`r`n`r`n将会把其他 provider/model 的线程统一归到当前设置:`r`nprovider: $($script:LatestState.current_provider)`r`nmodel: $($script:LatestState.current_model)`r`n`r`n本次预计移动线程数: $($script:LatestState.movable_threads)`r`n每次都会先自动备份数据库。"
    if (-not (Confirm-Action -Message $message -Title '确认同步')) {
      Append-Log '用户取消了同步。'
      return
    }

    $result = Invoke-Backend @('--json', 'sync')
    Append-Log "同步完成。已移动 $($result.updated_rows) 条线程。"
    Append-Log "Provider 同步前: $(Format-Counts $result.before_counts)"
    Append-Log "Provider 同步后: $(Format-Counts $result.after_counts)"
    Append-Log "模型同步前: $(Format-ModelCounts $result.before_model_counts)"
    Append-Log "模型同步后: $(Format-ModelCounts $result.after_model_counts)"
    Append-Log "备份文件: $($result.backup_path)"
    Refresh-State
    [System.Windows.Forms.MessageBox]::Show('同步完成。若左侧历史列表没有立刻刷新，重开一次 Codex 即可。', '同步完成', 'OK', 'Information') | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '同步失败', 'OK', 'Error') | Out-Null
    Append-Log "同步失败: $($_.Exception.Message)"
  }
})

$backupButton.Add_Click({
  try {
    $result = Invoke-Backend @('--json', 'backup')
    Append-Log "手动备份完成: $($result.backup_path)"
    Refresh-State
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '备份失败', 'OK', 'Error') | Out-Null
    Append-Log "备份失败: $($_.Exception.Message)"
  }
})

$openBackupsButton.Add_Click({
  try {
    if (-not $script:LatestState) {
      Refresh-State
    }
    $folder = $script:LatestState.backup_dir
    if (-not (Test-Path -LiteralPath $folder)) {
      New-Item -ItemType Directory -Force -Path $folder | Out-Null
    }
    Start-Process explorer.exe $folder
    Append-Log "已打开备份目录: $folder"
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '打开目录失败', 'OK', 'Error') | Out-Null
    Append-Log "打开备份目录失败: $($_.Exception.Message)"
  }
})

$shortcutButton.Add_Click({
  try {
    $path = New-DesktopShortcut
    Append-Log "桌面快捷方式已更新: $path"
    [System.Windows.Forms.MessageBox]::Show("桌面快捷方式已更新：`r`n$path", '完成', 'OK', 'Information') | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '创建快捷方式失败', 'OK', 'Error') | Out-Null
    Append-Log "创建快捷方式失败: $($_.Exception.Message)"
  }
})

$restoreButton.Add_Click({
  try {
    if ($backupList.SelectedItem -eq $null) {
      [System.Windows.Forms.MessageBox]::Show('先在右侧选一个备份。', '未选择备份', 'OK', 'Warning') | Out-Null
      return
    }
    $selectedLabel = [string]$backupList.SelectedItem
    $backupPath = $script:BackupMap[$selectedLabel]
    if (-not $backupPath) {
      throw '无法解析选中的备份路径。'
    }

    $message = "请先关闭 Codex Desktop，再继续恢复。`r`n`r`n将会恢复这个备份：`r`n$backupPath`r`n`r`n恢复前会再自动生成一份安全备份。"
    if (-not (Confirm-Action -Message $message -Title '确认恢复')) {
      Append-Log '用户取消了恢复。'
      return
    }

    $result = Invoke-Backend @('--json', 'restore', '--backup', $backupPath)
    Append-Log "恢复完成。来源备份: $($result.restored_from)"
    Append-Log "恢复前安全备份: $($result.safety_backup)"
    Refresh-State
    [System.Windows.Forms.MessageBox]::Show('恢复完成。建议重开一次 Codex 再看历史列表。', '恢复完成', 'OK', 'Information') | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '恢复失败', 'OK', 'Error') | Out-Null
    Append-Log "恢复失败: $($_.Exception.Message)"
  }
})

$restoreLatestButton.Add_Click({
  try {
    if (-not (Confirm-Action -Message '请先关闭 Codex Desktop，再继续恢复。将会恢复最新备份，并在恢复前再做一次安全备份。' -Title '确认恢复最新备份')) {
      Append-Log '用户取消了恢复最新备份。'
      return
    }

    $result = Invoke-Backend @('--json', 'restore')
    Append-Log "已恢复最新备份: $($result.restored_from)"
    Append-Log "恢复前安全备份: $($result.safety_backup)"
    Refresh-State
    [System.Windows.Forms.MessageBox]::Show('恢复完成。建议重开一次 Codex 再看历史列表。', '恢复完成', 'OK', 'Information') | Out-Null
  } catch {
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '恢复失败', 'OK', 'Error') | Out-Null
    Append-Log "恢复失败: $($_.Exception.Message)"
  }
})

try {
  $createdShortcut = New-DesktopShortcut
  Append-Log "桌面快捷方式已准备好: $createdShortcut"
} catch {
  Append-Log "初始化快捷方式失败: $($_.Exception.Message)"
}

try {
  Refresh-State
} catch {
  Append-Log "初始化状态失败: $($_.Exception.Message)"
  [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, '启动失败', 'OK', 'Error') | Out-Null
}

if ($SmokeTest) {
  Write-Output 'Smoke test OK'
  exit 0
}

[void]$form.ShowDialog()




