# rust, fnm and uv
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# Suppress the "Loading personal and system profiles took xxxms" message
$ErrorActionPreference = "SilentlyContinue"
# Display PowerShell version
Write-Host "PowerShell $($PSVersionTable.PSVersion.Major).$($PSVersionTable.PSVersion.Minor).$($PSVersionTable.PSVersion.Patch)"
Write-Host ""
# Reset the error action preference to its default value
$ErrorActionPreference = "Continue"

# OMP config
oh-my-posh init pwsh --config 'C:\Users\EDM115\AppData\Local\Programs\oh-my-posh\themes\EDM115-newline.omp.json' | Invoke-Expression
oh-my-posh completion powershell | Out-String | Invoke-Expression

# sudo in Windows
function sudo {
    # Create a command line string with properly escaped arguments
    $escapedArgs = @()
    foreach ($arg in $args) {
        if ($arg -match '\s') {
            # If argument contains spaces, wrap it in quotes and escape internal quotes
            $escapedArg = '"' + ($arg -replace '"', '\"') + '"'
        } else {
            # Just escape internal quotes
            $escapedArg = $arg -replace '"', '\"'
        }
        $escapedArgs += $escapedArg
    }
    
    $command = $escapedArgs -join ' '
    
    # Base64 encode the command to avoid PowerShell parsing
    $bytes = [System.Text.Encoding]::Unicode.GetBytes($command + "; pause")
    $encodedCommand = [Convert]::ToBase64String($bytes)
    
    # Use Start-Process to execute the command in a new elevated PowerShell instance
    Start-Process pwsh -ArgumentList @("-ExecutionPolicy", "Bypass", "-EncodedCommand", $encodedCommand) -Verb RunAs
}

# git-pulls
function git-pulls {
    Get-ChildItem -Directory | ForEach-Object {
        if (Test-Path "$($_.FullName)\.git") {
            Set-Location $_.FullName
            git pull
        }
    }
    cd ..
}

# alias code to code-insiders
function code {
    code-insiders $args
}

# fnm
fnm env --use-on-cd --version-file-strategy=recursive --shell powershell | Out-String | Invoke-Expression
fnm completions --shell powershell | Out-String | Invoke-Expression

# GitHub Copilot in the CLI
gh copilot alias -- pwsh | Out-String | Invoke-Expression

# zoxide
zoxide init powershell --cmd cd | Out-String | Invoke-Expression

# Terminal icons
Import-Module -Name Terminal-Icons
$themes = Get-TerminalIconsTheme
foreach ($theme in $themes) {
    if ([string]::IsNullOrEmpty($theme.Color.Name)) {
        Add-TerminalIconsColorTheme -Force "D:\EDM115\Documents\.config\dracula.psd1"
        Set-TerminalIconsTheme -ColorTheme dracula
    }
}

# rust
rustup completions powershell | Out-String | Invoke-Expression

# hcloud cli
hcloud completion powershell | Out-String | Invoke-Expression

# uv
uv generate-shell-completion powershell | Out-String | Invoke-Expression
uvx --generate-shell-completion powershell | Out-String | Invoke-Expression

# $env:PYTHONIOENCODING="utf-8"
# See https://github.com/nvbn/thefuck/issues/1449#issuecomment-2155277179
iex "$(thefuck --alias)"

# arrpc
function Invoke-ARRPC {
    Start-Job -ScriptBlock {
        Set-Location -Path "D:\EDM115\Programmes\Discord RPC\arrpc"
        node src
    } -Name "arrpc"
}
Set-Alias -Name arrpc -Value Invoke-ARRPC

# 8LWXpg/ptr
(ptr completion) -join "`n" | iex

function edit-history {
    notepad "C:\Users\EDM115\AppData\Roaming\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
}

# Stuff from https://github.com/ChrisTitusTech/powershell-profile/blob/main/Microsoft.PowerShell_profile.ps1
function Test-CommandExists {
    param($command)
    $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
    return $exists
}

function touch($file) { "" | Out-File $file -Encoding UTF-8 }

function ff($name) {
    Get-ChildItem -recurse -filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Output "$($_.FullName)"
    }
}

function Get-PubIP { (Invoke-WebRequest http://ifconfig.me/ip).Content }

function uptime {
    if ($PSVersionTable.PSVersion.Major -eq 5) {
        Get-WmiObject win32_operatingsystem | Select-Object @{Name='LastBootUpTime'; Expression={$_.ConverttoDateTime($_.lastbootuptime)}} | Format-Table -HideTableHeaders
    } else {
        net statistics workstation | Select-String "since" | ForEach-Object { $_.ToString().Replace('Statistics since ', '') }
    }
}

function unzip ($file) {
    Write-Output("Extracting", $file, "to", $pwd)
    $fullFile = Get-ChildItem -Path $pwd -Filter $file | ForEach-Object { $_.FullName }
    Expand-Archive -Path $fullFile -DestinationPath $pwd
}

function hb {
    if ($args.Length -eq 0) {
        Write-Error "No file path specified."
        return
    }
    
    $FilePath = $args[0]
    
    if (Test-Path $FilePath) {
        $Content = Get-Content $FilePath -Raw
    } else {
        Write-Error "File path does not exist."
        return
    }
    
    $uri = "http://bin.christitus.com/documents"
    try {
        $response = Invoke-RestMethod -Uri $uri -Method Post -Body $Content -ErrorAction Stop
        $hasteKey = $response.key
        $url = "http://bin.christitus.com/$hasteKey"
        Write-Output $url
    } catch {
        Write-Error "Failed to upload the document. Error: $_"
    }
}

function grep($regex, $dir) {
    if ( $dir ) {
        Get-ChildItem $dir | Select-String $regex
        return
    }
    $input | Select-String $regex
}

function df { Get-Volume }

function sed($file, $find, $replace) { (Get-Content $file).replace("$find", $replace) | Set-Content $file }

function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }

function export($name, $value) { Set-Item -force -path "env:$name" -value $value; }

function pkill($name) { Get-Process $name -ErrorAction SilentlyContinue | Stop-Process }

function pgrep($name) { Get-Process $name }

function head {
  param($Path, $n = 10)
  Get-Content $Path -Head $n
}

function tail {
  param($Path, $n = 10, [switch]$f = $false)
  Get-Content $Path -Tail $n -Wait:$f
}

# Quick File Creation
function nf { param($name) New-Item -ItemType "file" -Path . -Name $name }

# Directory Management
function mkcd { param($dir) mkdir $dir -Force; Set-Location $dir }

# Simplified Process Management
function k9 { Stop-Process -Name $args[0] }

# Enhanced Listing
function la { Get-ChildItem -Path . -Force | Format-Table -AutoSize }
function ll { Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize }

# Quick Access to System Information
function sysinfo { Get-ComputerInfo }

# Networking Utilities
function flushdns {
	Clear-DnsClientCache
	Write-Host "DNS has been flushed"
}

# Clipboard Utilities
function cpy { Set-Clipboard $args[0] }

function pst { Get-Clipboard }


#f45873b3-b655-43a6-b217-97c00aa0db58 PowerToys CommandNotFound module
Import-Module -Name Microsoft.WinGet.CommandNotFound
#f45873b3-b655-43a6-b217-97c00aa0db58
