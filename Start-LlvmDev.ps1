<#
.SYNOPSIS
    Provision a Copilot credential file on the host and start the llvm-dev
    container with that file bind-mounted as a Docker secret.

.DESCRIPTION
    Stores a GitHub token (PAT or GitHub App installation token) at a
    user-only-readable path on the host, then starts (or restarts) a
    long-lived `llvm-dev-shell` container with the file bind-mounted at
    /run/secrets/copilot_token (read-only).

    The token never ends up in the image, in `docker inspect` output, or in
    a Docker volume. It only exists:
      * on disk at $TokenPath (NTFS-ACL'd to the current user), and
      * inside the container as a read-only file.

    Re-running this script with a new token rotates the credential. The
    container picks up the new value on the next read (the post-receive
    hook re-reads the file on every invocation).

.PARAMETER TokenPath
    Where to store the token on the host. Defaults to
    $env:USERPROFILE\.secrets\copilot-token.

.PARAMETER Token
    The token value. If omitted, you'll be prompted (input is hidden).

.PARAMETER ImageName
    Docker image to run. Default: llvm-dev.

.PARAMETER ContainerName
    Container name to create/reuse. Default: llvm-dev-shell.

.PARAMETER Recreate
    If set, removes any existing container with the same name before starting.

.EXAMPLE
    .\Start-LlvmDev.ps1
    # Prompts for a token, stores it, starts the container.

.EXAMPLE
    .\Start-LlvmDev.ps1 -Token (Get-Content .\new-token.txt -Raw) -Recreate
#>
[CmdletBinding()]
param(
    [string] $TokenPath     = (Join-Path $env:USERPROFILE '.secrets\copilot-token'),
    [string] $Token,
    [string] $ImageName     = 'llvm-dev',
    [string] $ContainerName = 'llvm-dev-shell',
    [switch] $Recreate
)

$ErrorActionPreference = 'Stop'

function Write-TokenFile {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Value
    )

    $dir = Split-Path -Parent $Path
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    # Write as UTF-8 *without* a BOM and *without* a trailing newline; the
    # Copilot CLI / git hook will use the file contents verbatim.
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value.TrimEnd("`r","`n"))
    [System.IO.File]::WriteAllBytes($Path, $bytes)

    # Lock NTFS ACLs to just the current user (and SYSTEM, so backups still work).
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)   # disable inheritance, drop inherited rules

    $me = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $sys = New-Object System.Security.Principal.SecurityIdentifier `
        ([System.Security.Principal.WellKnownSidType]::LocalSystemSid, $null)

    foreach ($sid in @($me, $sys)) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow)
        $acl.AddAccessRule($rule)
    }
    Set-Acl -Path $Path -AclObject $acl
}

function Get-DockerContainerState {
    param([Parameter(Mandatory)] [string] $Name)
    $raw = docker ps -a --filter "name=^$([regex]::Escape($Name))$" --format '{{.State}}'
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return $raw.Trim()
}

# ---------- 1. Acquire the token ----------
if (-not $Token) {
    $secure = Read-Host -AsSecureString "GitHub token for Copilot (input hidden)"
    if (-not $secure -or $secure.Length -eq 0) {
        throw "No token entered."
    }
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $Token = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

if (-not $Token -or $Token.Trim().Length -eq 0) {
    throw "Empty token; refusing to write."
}

Write-Host "==> Writing token to $TokenPath"
Write-TokenFile -Path $TokenPath -Value $Token
# Drop the in-memory copy as soon as possible.
$Token = $null

# ---------- 2. Sanity-check the image ----------
$null = docker image inspect $ImageName 2>$null
if ($LASTEXITCODE -ne 0) {
    throw "Docker image '$ImageName' not found. Build it first: docker build -t $ImageName ."
}

# ---------- 3. Start (or restart) the container ----------
$state = Get-DockerContainerState -Name $ContainerName

if ($state -and $Recreate) {
    Write-Host "==> Removing existing container '$ContainerName'"
    docker rm -f $ContainerName | Out-Null
    $state = $null
}

if ($state) {
    if ($state -ne 'running') {
        Write-Host "==> Starting existing container '$ContainerName' (was: $state)"
        docker start $ContainerName | Out-Null
    } else {
        Write-Host "==> Container '$ContainerName' already running; reusing."
        Write-Host "    NOTE: bind mounts are fixed at create time. To pick up a"
        Write-Host "          changed -TokenPath, re-run with -Recreate."
    }
} else {
    Write-Host "==> Creating and starting container '$ContainerName'"
    docker run -dit `
        --name $ContainerName `
        --mount "type=bind,src=$TokenPath,dst=/run/secrets/copilot_token,readonly" `
        $ImageName | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "docker run failed."
    }
}

Write-Host ""
Write-Host "Container ready."
Write-Host "  Open a shell:  docker exec -it $ContainerName bash"
Write-Host "  Run Copilot:   docker exec -it $ContainerName copilot-run --prompt '...'"
Write-Host "  Stop:          docker stop $ContainerName"
Write-Host "  Rotate token:  re-run this script (use -Recreate to also rebind the mount)"
