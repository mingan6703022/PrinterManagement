using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

internal static class PrinterBackupLauncher
{
    [STAThread]
    private static void Main()
    {
        string folder = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(folder, "PrinterBackup.ps1");
        if (!File.Exists(script))
        {
            MessageBox.Show(
                "找不到 PrinterBackup.ps1。請先解壓縮完整資料夾，再啟動程式。",
                "印表機設定搬家工具",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
            return;
        }

        string windows = Environment.GetFolderPath(Environment.SpecialFolder.Windows);
        string powershell = Path.Combine(windows, "System32", "WindowsPowerShell", "v1.0", "powershell.exe");
        if (Environment.Is64BitOperatingSystem && !Environment.Is64BitProcess)
        {
            powershell = Path.Combine(windows, "Sysnative", "WindowsPowerShell", "v1.0", "powershell.exe");
        }

        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = powershell;
        startInfo.Arguments = "-NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File " + QuoteArgument(script);
        startInfo.WorkingDirectory = folder;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.WindowStyle = ProcessWindowStyle.Hidden;

        try
        {
            Process.Start(startInfo);
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                exception.ToString(),
                "無法啟動印表機設定搬家工具",
                MessageBoxButtons.OK,
                MessageBoxIcon.Error);
        }
    }

    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }
}
