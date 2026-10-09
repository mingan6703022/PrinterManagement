# 印表機設定搬家工具（免安裝版）

繁體中文 Windows 小工具，使用 Windows 內建的 PrintBRM 匯出或還原整台電腦的印表機伺服器設定。程式以 PowerShell 5.1 與 .NET Framework Windows Forms 製作，使用 Windows 內建元件，不需要另外安裝執行環境。

完整圖文操作說明請開啟同資料夾中的 [README.HTML](README.HTML)。

## 使用方式

1. 將此資料夾完整解壓縮到電腦上。
2. 雙擊 `PrinterBackup.exe` 或「一鍵啟動.cmd」，並在 UAC 視窗允許管理員權限。EXE 內建 `requireAdministrator` 設定，Windows 會在程式啟動前要求管理員權限。
3. 舊電腦按「匯出備份」，將產生的 `.printerExport` 檔複製到新電腦。
4. 新電腦以相同方式開啟工具，按「匯入還原」並選取備份檔。

備份與還原都由 Microsoft PrintBRM 執行。程式會檢查 PrintBRM 與 Print Spooler 是否可用，並顯示執行結果。還原時，同名佇列可能會更新。

## 目標系統

- Windows 10
- Windows 11
- Windows Server 2022
- Windows Server 2025

Windows Server 請使用 Desktop Experience（桌面體驗）；Server Core 沒有可供此視窗介面使用的桌面環境。

程式本身不需安裝。啟動時會要求管理員權限；若找不到 PrintBRM，Windows 10/11 會透過 DISM 安裝「Print Management Console」選用功能，Windows Server 2022/2025 會安裝「RSAT-Print-Services」。這些都是 Windows 官方元件，缺少時由 Windows 元件來源（通常是 Windows Update 或組織設定的 Features on Demand 來源）下載。若網路或 WSUS 原則封鎖功能來源，程式會顯示安裝錯誤。安裝完成後會自動繼續開放匯出／匯入。Print Spooler 服務也必須正在執行。

## 備份範圍與注意事項

PrintBRM 可搬移支援的印表機佇列、驅動程式、連接埠、共用資訊、列印伺服器設定與自訂紙張表單。匯入後請檢查每個佇列、紙張尺寸和驅動程式設定；建議查看事件檢視器的「Applications and Services Logs / Microsoft / PrintBRM / Admin」記錄。

來源與目的電腦最好使用相同處理器架構。不同 Windows 版本、驅動程式版本或廠牌可能需要手動重設機型專屬選項；廠商掃描工具、帳號憑證、印表機面板設定及應用程式的個人列印偏好不會由 PrintBRM 一併搬移。USB 印表機還可能需要在新電腦重新接線或指定連接埠。

## 參考

- [Microsoft：備份和還原印表機](https://learn.microsoft.com/en-us/troubleshoot/windows-server/printing/back-up-restore-printers)
- [Microsoft：PrintBRM 命令列工具](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-server-2012-R2-and-2012/jj134237(v=ws.11))
