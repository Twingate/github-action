# Does the Twingate app (Twingate.exe) get the job's OIDC variables?
# Prints only whether each variable is present, never a value.
$ErrorActionPreference = 'Continue'
$Vars = 'ACTIONS_ID_TOKEN_REQUEST_URL', 'ACTIONS_ID_TOKEN_REQUEST_TOKEN'
$Summary = if ($env:GITHUB_STEP_SUMMARY) { $env:GITHUB_STEP_SUMMARY } else { 'NUL' }

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

public static class ProcEnv
{
    [StructLayout(LayoutKind.Sequential)]
    private struct BasicInfo
    {
        public IntPtr ExitStatus;
        public IntPtr PebBaseAddress;
        public IntPtr AffinityMask;
        public IntPtr BasePriority;
        public IntPtr UniqueProcessId;
        public IntPtr InheritedFromUniqueProcessId;
    }

    [DllImport("ntdll.dll")]
    private static extern int NtQueryInformationProcess(IntPtr process, int infoClass, ref BasicInfo info, int length, out int returned);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(int access, bool inherit, int pid);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] buffer, IntPtr size, out IntPtr read);

    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    private static IntPtr ReadPointer(IntPtr process, IntPtr address)
    {
        var buffer = new byte[8];
        IntPtr read;
        if (!ReadProcessMemory(process, address, buffer, (IntPtr)8, out read))
        {
            throw new Exception("Win32 error " + Marshal.GetLastWin32Error());
        }
        return (IntPtr)BitConverter.ToInt64(buffer, 0);
    }

    // x64 only: PEB.ProcessParameters at 0x20, Environment at 0x80, EnvironmentSize at 0x3F0.
    public static string[] Names(int pid)
    {
        IntPtr process = OpenProcess(0x0410, false, pid);
        if (process == IntPtr.Zero)
        {
            throw new Exception("Win32 error " + Marshal.GetLastWin32Error());
        }
        try
        {
            var info = new BasicInfo();
            int returned;
            int status = NtQueryInformationProcess(process, 0, ref info, Marshal.SizeOf(info), out returned);
            if (status != 0)
            {
                throw new Exception("NtQueryInformationProcess returned " + status);
            }
            IntPtr parameters = ReadPointer(process, info.PebBaseAddress + 0x20);
            IntPtr environment = ReadPointer(process, parameters + 0x80);
            long size = (long)ReadPointer(process, parameters + 0x3F0);
            var buffer = new byte[size];
            IntPtr read;
            if (!ReadProcessMemory(process, environment, buffer, (IntPtr)size, out read))
            {
                throw new Exception("Win32 error " + Marshal.GetLastWin32Error());
            }
            var names = new List<string>();
            foreach (var entry in Encoding.Unicode.GetString(buffer, 0, (int)read).Split('\0'))
            {
                if (entry.Length < 2)
                {
                    continue;
                }
                int equals = entry.IndexOf('=', 1);
                if (equals > 0)
                {
                    names.Add(entry.Substring(0, equals));
                }
            }
            return names.ToArray();
        }
        finally
        {
            CloseHandle(process);
        }
    }
}
'@

[System.Diagnostics.Process]::EnterDebugMode()

function Section($text) { Write-Output ''; Write-Output "=== $text" }
function Result($text) { Write-Output "RESULT: $text"; Add-Content -Path $Summary -Value "- $text" }

function Get-AppProcess {
    for ($i = 0; $i -lt 30; $i++) {
        $p = Get-Process -Name Twingate -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($p) { return $p }
        Start-Sleep -Seconds 1
    }
    return $null
}

function Report-App {
    $p = Get-AppProcess
    if (-not $p) { return 'app: not running' }
    try {
        $names = [ProcEnv]::Names($p.Id)
        $parts = foreach ($v in $Vars) { "$v=$(if ($names -contains $v) { 'yes' } else { 'no' })" }
        $owner = (Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" | Invoke-CimMethod -MethodName GetOwner).User
        "app: pid $($p.Id), session $($p.SessionId), user $owner, $($parts -join ' ') (vars readable: $($names.Count))"
    }
    catch {
        "app: pid $($p.Id), session $($p.SessionId), environment not readable: $($_.Exception.Message)"
    }
}

Add-Content -Path $Summary -Value '## Windows'

Section 'Step environment'
foreach ($v in $Vars) {
    if ([Environment]::GetEnvironmentVariable($v)) { "${v}: present in the step" } else { "${v}: MISSING in the step" }
}

Section 'Session context'
"step user: $(whoami), step session: $((Get-Process -Id $PID).SessionId), interactive: $([Environment]::UserInteractive)"
query session 2>&1

Section 'Install Twingate'
$msi = Join-Path $env:RUNNER_TEMP 'twingate.msi'
$log = Join-Path $env:RUNNER_TEMP 'twingate-install.log'
Invoke-WebRequest 'https://api.twingate.com/download/windows?installer=msi' -OutFile $msi
$install = Start-Process msiexec.exe -Wait -PassThru -ArgumentList "/i `"$msi`" /quiet /l*v `"$log`""
"msiexec exit code: $($install.ExitCode)"
Select-String -Path $log -Pattern 'client launch|Launched .* in session|WTSQueryUserToken|CreateEnvironmentBlock|CreateProcessAsUser|No active user session' |
    ForEach-Object { $_.Line.Trim() }

Section 'After install'
Result "after install: $(Report-App)"

Section 'Workaround: restart the app from the step'
$exe = Join-Path $env:ProgramFiles 'Twingate\Twingate.exe'
Get-Process -Name Twingate -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 2
Start-Process -FilePath $exe
Result "workaround: $(Report-App)"
Start-Sleep -Seconds 10
if (Get-Process -Name Twingate -ErrorAction SilentlyContinue) {
    Result 'workaround: still running after 10 s'
}
else {
    Result 'workaround: exited within 10 s'
}
