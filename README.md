# Codex History Sync Tool

这个目录是一个适合直接发布到 GitHub 的版本。

它保留了当前实际可用工具的原始结构和中文界面，只补了最基础的开源发布文件，
比如 `LICENSE` 和 `.gitignore`，并把文档里的个人路径改成了通用写法。

这个工具用于把本机 Codex Desktop 已保存的本地线程历史，重新挂到当前
`config.toml` 里正在使用的 `model_provider` 下面。

## Files

- `sync_backend.py`: SQLite backup, status, sync, and restore logic.
- `launch_ui.ps1`: Minimal WinForms desktop UI and shortcut installer.

## Requirements

- Windows PowerShell 5.1 or newer
- `py -3` available in PATH
- Local Codex data in `%USERPROFILE%\.codex`

## Typical usage

- Launch the UI: run `launch_ui.ps1`
- Create a desktop shortcut: run `launch_ui.ps1 -InstallShortcutOnly`
- CLI status: `py -3 .\sync_backend.py --json status`
- CLI sync: `py -3 .\sync_backend.py --json sync`

## Backup behavior

- Every sync creates a backup in `%USERPROFILE%\.codex\history_sync_backups`
- Every restore creates a safety backup before replacing the live database

## Notes

- The tool only works when the local Codex history files still exist on this machine.
- The safest flow is to close Codex Desktop before syncing or restoring.
