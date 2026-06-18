# rust, fnm, rg and uv
using namespace System.Management.Automation
using namespace System.Management.Automation.Language

# alias code to code-insiders
function code {
  code-insiders $args
}

# alias deno x to dx
function dx {
  deno x $args
}

if ($env:TERM_PROGRAM -ne "vscode" -and $env:TERM_PROGRAM -ne "zed")  {
  # OMP config, breaks copilot when present
  oh-my-posh init pwsh --config "D:\EDM115\Documents\Projects\dotfiles\omp\EDM115-newline.omp.json" | Invoke-Expression
}

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

# Count commits per author email
function git-commits {
  git log --pretty=format:'%ae'
    | Group-Object
    | Sort-Object Count -Descending
    | Select-Object @{Name='Email'; Expression={$_.Name}}, @{Name='Commits'; Expression={$_.Count}}
    | Format-Table -AutoSize
}

# Aggregate diff stats per author email
function git-diffs {
  $stats = @{}
  $currentEmail = ""

  git log --pretty=format:'%ae' --numstat
    | ForEach-Object {
      $line = $_.Trim()

      # Detect real email lines only
      if ($line -match '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$') {
        $currentEmail = $line

        if (-not $stats.ContainsKey($currentEmail)) {
          $stats[$currentEmail] = [PSCustomObject]@{
            FilesChanged = 0
            LinesAdded = 0
            LinesRemoved = 0
          }
        }

        return
      }

      # Handle only numstat lines
      # numstat lines always have two tabs: "<added>\t<removed>\t<path>"
      if ($line -notmatch "`t.*`t") {
        return
      }

      $parts = $line -split "`t"

      # skip binary files (they show "-" for both added and removed)
      if ($parts[0] -eq '-' -and $parts[1] -eq '-') {
        return
      }

      $added = ($parts[0] -match '^\d+$') ? [int]$parts[0] : 0
      $removed = ($parts[1] -match '^\d+$') ? [int]$parts[1] : 0

      $stats[$currentEmail].FilesChanged++
      $stats[$currentEmail].LinesAdded += $added
      $stats[$currentEmail].LinesRemoved += $removed
    }

  # Output sorted by total lines changed
  $stats.GetEnumerator()
    | Select-Object `
      @{Name='Email'; Expression={ $_.Key }},
      @{Name='FilesChanged'; Expression={ $_.Value.FilesChanged }},
      @{Name='LinesAdded'; Expression={ $_.Value.LinesAdded }},
      @{Name='LinesRemoved'; Expression={ $_.Value.LinesRemoved }},
      @{Name='TotalLines'; Expression={ $_.Value.LinesAdded + $_.Value.LinesRemoved }}
    | Sort-Object TotalLines -Descending
    | Format-Table -AutoSize
}

# get-path
function get-path {
  $env:PATH -split ';' | ForEach-Object { $_ }
}

# download files easily
function downloadURL {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Uri,

    <# Optional destination. Can be :
      - empty (save in current dir using the name from the URL)
      - a directory path (C:\path\to_dest or C:\path\to_dest\)
      - a full file path (C:\path\to_dest\name.zip)
      - just a filename (anothername.zip) #>
    [Parameter(Position=1)]
    [string]$Dest,

    # Optional arg : -BufferSize 50MB (also accepts 512KiB, 2GiB, or raw bytes), or as a positional 3rd argument if dest is provided : buffer=200MB
    [Parameter(Position=2)]
    [string]$BufferSize
  )

  # Allow "buffer=..." as the 2nd arg when Dest is omitted or looks like buffer spec
  if ($Dest -and $Dest -imatch '^\s*(buffer\s*=)?\s*\d+(\.\d+)?\s*(KB|MB|GB|KiB|MiB|GiB)?\s*$') {
    if (-not $BufferSize) {
      $BufferSize = $Dest
    }

    $Dest = $null
  }

  $ErrorActionPreference = "Stop"

  # helpers
  function Resolve-BufferBytes([string]$s, [long]$defaultBytes) {
    if ([string]::IsNullOrWhiteSpace($s)) {
      return $defaultBytes
    }

    # Accept forms like "buffer=50MB" or "50MB" or "52428800"
    if ($s -match '^\s*buffer\s*=\s*(.+)$') {
      $s = $Matches[1]
    }

    $s = $s.Trim()

    if ($s -imatch '^(?<num>\d+(\.\d+)?)\s*(?<unit>KB|MB|GB|KiB|MiB|GiB)?$') {
      $num = [double]$Matches['num']
      $unit = $Matches['unit']

      switch -Regex ($unit) {
        '^(?i)KB$' {
          return [long]([math]::Round($num * 1000))
        } '^(?i)MB$' {
          return [long]([math]::Round($num * 1000 * 1000))
        } '^(?i)GB$' {
          return [long]([math]::Round($num * 1000 * 1000 * 1000))
        } '^(?i)KiB$' {
          return [long]([math]::Round($num * 1KB))
        } '^(?i)MiB$' {
          return [long]([math]::Round($num * 1MB))
        } '^(?i)GiB$' {
          return [long]([math]::Round($num * 1GB))
        } default {
          # plain bytes
          return [long]([math]::Round($num))
        }
      }
    }

    return $defaultBytes
  }

  function Get-DefaultFileNameFromUri([string]$u) {
    try {
      $uriObj = [Uri]$u
      $name = [IO.Path]::GetFileName($uriObj.AbsolutePath)

      if ([string]::IsNullOrWhiteSpace($name)) {
        return "download.bin"
      }

      return $name
    } catch {
      return "download.bin"
    }
  }

  function Build-OutputPath([string]$u, [string]$d) {
    $defaultName = Get-DefaultFileNameFromUri $u

    if ([string]::IsNullOrWhiteSpace($d)) {
      # no destination provided -> current dir + default name
      return (Join-Path -Path (Get-Location) -ChildPath $defaultName)
    }

    # If dest looks like a bare filename (no dir separators), save in current dir with that name
    if ($d -notmatch '[\\/]' -and -not (Test-Path -LiteralPath $d -PathType Container)) {
      return (Join-Path -Path (Get-Location) -ChildPath $d)
    }

    # If dest is an existing directory, or ends with a separator, join with default name
    $endsWithSep = $d.TrimEnd() -match '[\\/]$'

    if ($endsWithSep -or (Test-Path -LiteralPath $d -PathType Container)) {
      return (Join-Path -Path $d -ChildPath $defaultName)
    }

    # Otherwise, treat as full file path
    return $d
  }
  # end helpers

  # Final and partial (.dl) paths
  $finalPath = Build-OutputPath -u $Uri -d $Dest
  $partialPath = "$finalPath.dl"
  $bufferBytes = Resolve-BufferBytes -s $BufferSize -defaultBytes (20MB)

  # Ensure destination directory exists
  $outDir = [IO.Path]::GetDirectoryName($finalPath)

  if ($outDir -and -not (Test-Path -LiteralPath $outDir -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $outDir
  }

  # HTTP client
  $handler = [System.Net.Http.HttpClientHandler]::new()
  $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
  $client = [System.Net.Http.HttpClient]::new($handler)
  $client.Timeout = [TimeSpan]::FromHours(12)

  # Resume support looks at the .dl file
  $existingBytes = 0L

  if (Test-Path -LiteralPath $partialPath) {
    $existingBytes = (Get-Item -LiteralPath $partialPath).Length
  }

  $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Uri)

  if ($existingBytes -gt 0) {
    $request.Headers.Range = [System.Net.Http.Headers.RangeHeaderValue]::new($existingBytes, $null)
  }

  # Ctrl+C handling
  $cts = [System.Threading.CancellationTokenSource]::new()
  $wasCancelled = $false
  $downloadCompleted = $false

  # state flag used for messaging
  $cancelState = [hashtable]::Synchronized(@{ cancelled = $false })
  $cancelHandler = [ConsoleCancelEventHandler]{
    param($sender, $e)
    $cancelState['cancelled'] = $true

    try {
      $cts.Cancel()
    } catch {
      # ignored
    }

    # prevent hard-terminate, let us clean up
    $e.Cancel = $true
  }

  try {
    [Console]::CancelKeyPress += $cancelHandler
  } catch {
    # ignored
  }

  $response = $null
  $stream = $null
  $file = $null
  $sw = $null
  $activity = "Downloading " + ([IO.Path]::GetFileName($finalPath))

  try {
    # Send the request with cancellation support, completion option = headers only, stream the body
    [void]($response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult())

    # If server ignored Range, restart fresh and nuke existing partial so we don't concatenate wrong
    if ($existingBytes -gt 0 -and $response.StatusCode -ne [System.Net.HttpStatusCode]::PartialContent) {
      $response.Dispose()
      $request.Dispose()

      $existingBytes = 0
      $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Get, $Uri)
      [void]($response = $client.SendAsync($request, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead, $cts.Token).GetAwaiter().GetResult())

      # Overwrite the file since we're starting fresh
      if (Test-Path -LiteralPath $partialPath) {
        Remove-Item -LiteralPath $partialPath -Force
      }
    }

    # suppress header dump
    [void]$response.EnsureSuccessStatusCode()

    $totalFromServer = $response.Content.Headers.ContentLength
    $totalBytes = $totalFromServer ? ($existingBytes + $totalFromServer) : $null

    # Allocate byte buffer
    [byte[]]$byteBuffer = New-Object byte[] $bufferBytes

    $stream = $response.Content.ReadAsStream($cts.Token)

    $fileMode = ($existingBytes -gt 0) ? [System.IO.FileMode]::Append : [System.IO.FileMode]::Create
    $file = [System.IO.FileStream]::new($partialPath, $fileMode, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None, 8192, $false)

    $downloaded = $existingBytes
    $sw = [System.Diagnostics.Stopwatch]::StartNew()

    while ($true) {
      # honor PowerShell pipeline stopping too (ex Stop-Command), if running as advanced function
      if ($PSCmdlet -and $PSCmdlet.Stopping) {
        $wasCancelled = $true
        break
      }

      if ($cts.IsCancellationRequested) {
        $wasCancelled = $true
        break
      }

      # async read that observes cancellation
      $read = $stream.ReadAsync($byteBuffer, 0, $byteBuffer.Length, $cts.Token).GetAwaiter().GetResult()

      if ($read -le 0) {
        $downloadCompleted = $true
        break
      }

      # if cancellation was requested but no exception was thrown, bail out cleanly
      if ($cts.IsCancellationRequested) {
        $wasCancelled = $true
        break
      }

      [void]$file.WriteAsync($byteBuffer, 0, $read, $cts.Token).GetAwaiter().GetResult()
      $downloaded += $read

      $elapsed = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
      $speedBps = $downloaded / $elapsed
      $speedMBs = $speedBps / 1MB

      if ($totalBytes) {
        $remaining = $totalBytes - $downloaded
        $etaSec = ($speedBps -gt 0) ? [int]($remaining / $speedBps) : 0
        $eta = [TimeSpan]::FromSeconds([math]::Max($etaSec,0)).ToString()
        $pct = [int](($downloaded / $totalBytes) * 100)
        $status = ("{0:N2} / {1:N2} MB @ {2:N1} MB/s | ETA {3}" -f ($downloaded/1MB), ($totalBytes/1MB), $speedMBs, $eta)
        Write-Progress -Activity $activity -Status $status -PercentComplete $pct
      } else {
        $status = ("{0:N2} MB downloaded @ {1:N1} MB/s" -f ($downloaded/1MB), $speedMBs)
        Write-Progress -Activity $activity -Status $status
      }
    }
  } catch [System.OperationCanceledException], [System.Management.Automation.PipelineStoppedException] {
    $wasCancelled = $true
  } finally {
    if ($file) {
      $file.Dispose()
    }

    if ($stream) {
      $stream.Dispose()
    }

    if ($response) {
      $response.Dispose()
    }

    if ($request) {
      $request.Dispose()
    }

    if ($client) {
      $client.Dispose()
    }

    # merge flags so message is reliable even if no exception was thrown
    $wasCancelled = $wasCancelled -or ($cancelState.cancelled) -or $cts.IsCancellationRequested

    if ($cancelHandler) {
      try {
        [Console]::CancelKeyPress -= $cancelHandler
      } catch {
        # ignored
      }
    }

    $cts.Dispose()
    Write-Progress -Activity $activity -Completed

    # on success, move .dl -> final (overwrite if needed)
    $canFinalize = $downloadCompleted -and -not $wasCancelled

    if ($canFinalize -and $totalBytes) {
      try {
        $len = (Get-Item -LiteralPath $partialPath).Length

        if ($len -ne $totalBytes) {
          $canFinalize = $false
        }
      } catch {
        $canFinalize = $false
      }
    }

    if ($canFinalize -and (Test-Path -LiteralPath $partialPath)) {
      try {
        if (Test-Path -LiteralPath $finalPath) {
          Remove-Item -LiteralPath $finalPath -Force
        }

        Move-Item -LiteralPath $partialPath -Destination $finalPath -Force
        Write-Host "✅ Saved to : $finalPath"
      } catch {
        Write-Host "❌ Download completed but failed to rename '$partialPath' -> '$finalPath' : $($_.Exception.Message)" -ForegroundColor Yellow
      }
    } elseif ($wasCancelled -or (Test-Path -LiteralPath $partialPath)) {
      Write-Host "⚠️ Download cancelled for $finalPath. To resume it (if the sever supports Range), keep '$partialPath' and re-run the same command :)" -ForegroundColor Yellow
    }
  }
}

# Replacement for GitHub Copilot in the CLI, powered by OpenAI Codex CLI
function Get-CodexTerminalExplainMode {
  [CmdletBinding()]
  param()

  $mode = if ($env:CT_EXPLAIN) {
    $env:CT_EXPLAIN.ToLowerInvariant()
  } else {
    "full"
  }

  $allowed = @("minimal", "simplified", "full")

  if ($mode -notin $allowed) {
    throw "Invalid CT_EXPLAIN ($mode), supported values : $($allowed -join ', ')"
  }

  return $mode
}

function Get-CodexTerminalModel {
  [CmdletBinding()]
  param()

  $model = if ($env:CT_MODEL) {
    $env:CT_MODEL.ToLowerInvariant()
  } else {
    # Good default and cheap
    "gpt-5.4-mini"
  }

  # Until we can reliably list them
  $allowed = @("gpt-5.3-codex-spark", "gpt-5.4-mini", "gpt-5.4", "gpt-5.5")

  if ($model -notin $allowed) {
    throw "Invalid CT_MODEL ($model), supported values : $($allowed -join ', ')"
  }

  return $model
}

function Get-CodexTerminalEffort {
  [CmdletBinding()]
  param()

  $effort = if ($env:CT_EFFORT) {
    $env:CT_EFFORT.ToLowerInvariant()
  } else {
    # Good enough for most cases, cheap and fast
    "medium"
  }

  $allowed = @("none", "low", "medium", "high", "xhigh")

  if ($effort -notin $allowed) {
    throw "Invalid CT_EFFORT ($effort), supported values : $($allowed -join ', ')"
  }

  return $effort
}

function Get-CodexTerminalDefaultAction {
  [CmdletBinding()]
  param()

  $action = if ($env:CT_ACTION) {
    $env:CT_ACTION.ToLowerInvariant()
  } else {
    "copy"
  }

  $allowed = @("copy", "explain", "refine", "execute", "exit")

  if ($action -notin $allowed) {
    throw "Invalid CT_ACTION ($action), supported values : $($allowed -join ', ')"
  }

  return $action
}

function Get-CodexTerminalVerbose {
  [CmdletBinding()]
  param()

  $value = $env:CT_VERBOSE

  if ([string]::IsNullOrWhiteSpace($value)) {
    return $false
  }

  return ($value -eq "1" -or $value.ToLowerInvariant() -eq "true")
}

function Repair-CodexTextEncoding {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string] $Text
  )

  $s = $Text

  # Build replacement chars without literal smart quotes in the source file
  $leftDoubleQuote  = [char]0x201C
  $rightDoubleQuote = [char]0x201D
  $leftSingleQuote  = [char]0x2018
  $rightSingleQuote = [char]0x2019
  $enDash           = [char]0x2013
  $emDash           = [char]0x2014
  $ellipsis         = [char]0x2026
  $bullet           = [char]0x2022

  # Avoid a hashtable here because mojibake/smart-quote literals breaks the profile file parsing
  $s = $s.Replace("ÔÇ£", [string]$leftDoubleQuote)
  $s = $s.Replace("ÔÇØ", [string]$rightDoubleQuote)
  $s = $s.Replace("ÔÇÿ", [string]$leftSingleQuote)
  $s = $s.Replace("ÔÇÖ", [string]$rightSingleQuote)
  $s = $s.Replace("ÔÇô", [string]$enDash)
  $s = $s.Replace("ÔÇö", [string]$emDash)
  $s = $s.Replace("ÔÇª", [string]$ellipsis)
  $s = $s.Replace("ÔÇó", [string]$bullet)
  $s = $s.Replace("ÔÇ»", " ")
  $s = $s.Replace("┬á", " ")
  $s = $s.Replace("Â ", " ")

  return $s
}

function Format-CodexNumber {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string] $Text
  )

  # Normalize weird narrow no-break spaces/damaged separators in token counts
  return (Repair-CodexTextEncoding $Text) -replace '[\u00A0\u202F]', " " -replace '\s+', ' '
}

function Convert-SimpleMarkdownToAnsi {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string] $Text
  )

  $reset = $PSStyle.Reset
  $headingColor = $PSStyle.Foreground.BrightMagenta
  $boldColor = $PSStyle.Foreground.BrightYellow
  $italicColor = $PSStyle.Foreground.BrightGreen
  $codeColor = $PSStyle.Foreground.BrightCyan
  $quoteColor = $PSStyle.Foreground.BrightBlack

  $s = Repair-CodexTextEncoding $Text
  $s = $s.TrimEnd("`r", "`n")

  # Remove fenced-code markers, keep content
  $s = [regex]::Replace($s, '(?m)^\s*```[a-zA-Z0-9_-]*\s*$', '')

  # Headings
  $s = [regex]::Replace($s, '(?m)^(#{1,6})\s+(.+?)\s*#*\s*$', {
    param($m)
    "$headingColor$($m.Groups[2].Value)$reset"
  })

  # Markdown links -> text (url)
  $s = [regex]::Replace($s, '\[([^\]]+)\]\(([^)]+)\)', {
    param($m)
    "$($m.Groups[1].Value) ($($m.Groups[2].Value))"
  })

  # Inline code
  $s = [regex]::Replace($s, '`([^`\r\n]+)`', {
    param($m)
    "$codeColor$($m.Groups[1].Value)$reset"
  })

  # Bold italic
  $s = [regex]::Replace($s, '\*\*\*([^*\r\n]+)\*\*\*', {
    param($m)
    "$boldColor$italicColor$($m.Groups[1].Value)$reset"
  })

  # Bold using stars
  $s = [regex]::Replace($s, '\*\*([^*\r\n]+)\*\*', {
    param($m)
    "$boldColor$($m.Groups[1].Value)$reset"
  })

  # Bold using underscores, but not inside identifiers
  $s = [regex]::Replace($s, '(?<![A-Za-z0-9])__([^_\r\n]+)__(?![A-Za-z0-9])', {
    param($m)
    "$boldColor$($m.Groups[1].Value)$reset"
  })

  # Italic using stars only when it does not look like a bullet/list marker
  $s = [regex]::Replace($s, '(?<!\*)\*([^*\r\n]+)\*(?!\*)', {
    param($m)
    "$italicColor$($m.Groups[1].Value)$reset"
  })

  # Italic using underscores, guarded against filenames/identifiers : output_000.mp4, n_forced, snake_case, ... will no longer match
  $s = [regex]::Replace($s, '(?<![A-Za-z0-9])_([^_\r\n]+)_(?![A-Za-z0-9])', {
    param($m)
    "$italicColor$($m.Groups[1].Value)$reset"
  })

  # Blockquotes : strip marker, color the line
  $s = [regex]::Replace($s, '(?m)^\s*>\s?(.+)$', {
    param($m)
    "$quoteColor$($m.Groups[1].Value)$reset"
  })

  # Horizontal rules
  $s = [regex]::Replace($s, '(?m)^\s*[-*_]{3,}\s*$', '')

  return $s.Trim()
}

function Write-SimpleMarkdown {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [AllowEmptyString()]
    [string] $Text
  )

  Write-Host (Convert-SimpleMarkdownToAnsi -Text $Text)
}

function Get-InvocationRemainder {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Line,

    [Parameter(Mandatory)]
    [string] $InvocationName,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $FallbackArgs
  )

  if ($Line -and $InvocationName) {
    $pattern = '^\s*' + [regex]::Escape($InvocationName) + '\s*'
    $raw = [regex]::Replace($Line, $pattern, '', 1)

    if ($null -ne $raw) {
      return $raw.Trim()
    }
  }

  return ($FallbackArgs -join " ")
}

function Escape-ForSingleQuotedPrompt {
  param([Parameter(Mandatory)][string]$Text)

  return ($Text -replace "'", "''")
}

function Normalize-CodexRawCommand {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Text)

  $s = $Text.Trim([char]0xFEFF).Trim()

  if (-not $s) {
    return $s
  }

  $lines = $s -split "\r?\n"

  # Drop markdown code fences lines
  $lines = $lines | Where-Object { $_ -notmatch '^\s*```' }

  # Strip common leading bullets/markers per-line
  $lines = $lines | ForEach-Object {
    ($_ -replace '^\s*(?:[●•○]|-\s+|\*\s+|>\s+)\s*', '')
  }

  while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
    $lines = $lines[1..($lines.Count - 1)]
  }

  while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[-1])) {
    $lines = $lines[0..($lines.Count - 2)]
  }

  $out = ($lines -join "`n").Trim()

  if ($out -match '^\s*`(.+)`\s*$') {
    $out = $Matches[1].Trim()
  }

  return $out.TrimEnd("`r", "`n")
}

function ConvertFrom-CodexExecOutput {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Text
  )

  $raw = Repair-CodexTextEncoding ($Text.Trim([char]0xFEFF))

  $version = $null
  $model = $null
  $effort = $null
  $tokensUsed = $null
  $answer = $raw.Trim()

  if ($raw -match '(?m)^\s*OpenAI Codex v(?<v>[^\r\n]+)\s*$') {
    $version = $Matches.v.Trim()
  }

  if ($raw -match '(?m)^\s*model:\s*(?<v>[^\r\n]+)\s*$') {
    $model = $Matches.v.Trim()
  }

  if ($raw -match '(?m)^\s*reasoning effort:\s*(?<v>[^\r\n]+)\s*$') {
    $effort = $Matches.v.Trim()
  }

  if ($raw -match '(?m)^\s*tokens used\s*$\r?\n\s*(?<v>[^\r\n]+)\s*$') {
    $tokensUsed = Format-CodexNumber $Matches.v.Trim()
  }

  if ($raw -match '(?ms)^\s*codex\s*\r?\n(?<answer>.*?)(?:\r?\n)?^\s*tokens used\s*$') {
    $answer = $Matches.answer.Trim()
  }

  return [pscustomobject]@{
    Answer = Repair-CodexTextEncoding $answer
    Version = $version
    Model = $model
    Effort = $effort
    TokensUsed = $tokensUsed
    Raw = $raw
  }
}

function New-CodexTerminalStatsBag {
  [CmdletBinding()]
  param()

  return [pscustomobject]@{
    Turns = 0
    TotalDuration = [TimeSpan]::Zero
    TotalTokens = 0
    LastVersion = $null
    LastModel = $null
    LastEffort = $null
    TurnStats = @()
  }
}

function Get-CodexTerminalTokenInt {
  [CmdletBinding()]
  param(
    [AllowNull()]
    [string] $Text
  )

  if ([string]::IsNullOrWhiteSpace($Text)) {
    return 0
  }

  $digits = ($Text -replace '\D', '')

  if ([string]::IsNullOrWhiteSpace($digits)) {
    return 0
  }

  return [int64]$digits
}

function Add-CodexTerminalTurnStats {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [pscustomobject] $Stats,

    [Parameter(Mandatory)]
    [pscustomobject] $Parsed
  )

  $duration = if ($Parsed.Duration) {
    $Parsed.Duration
  } else {
    [TimeSpan]::Zero
  }

  $tokens = Get-CodexTerminalTokenInt $Parsed.TokensUsed

  $Stats.Turns++
  $Stats.TotalDuration = $Stats.TotalDuration + $duration
  $Stats.TotalTokens += $tokens

  if ($Parsed.Version) {
    $Stats.LastVersion = $Parsed.Version
  }

  if ($Parsed.Model) {
    $Stats.LastModel = $Parsed.Model
  }

  if ($Parsed.Effort) {
    $Stats.LastEffort = $Parsed.Effort
  }

  $Stats.TurnStats += [pscustomobject]@{
    Turn = $Stats.Turns
    Duration = $duration
    Tokens = $tokens
  }
}

function Format-CodexTerminalDuration {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [TimeSpan] $Duration
  )

  if ($Duration.TotalSeconds -ge 1) {
    return "{0:n2}s" -f $Duration.TotalSeconds
  }

  return "{0:n0}ms" -f $Duration.TotalMilliseconds
}

function Write-CodexTerminalFinalVerboseHeader {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [pscustomobject] $Stats
  )

  $border = $PSStyle.Foreground.BrightCyan
  $label = $PSStyle.Foreground.BrightBlue
  $value = $PSStyle.Foreground.BrightWhite
  $muted = $PSStyle.Foreground.BrightBlack
  $reset = $PSStyle.Reset

  Write-Host ""
  Write-Host "$border╭─ Codex CLI stats ──────────────────$reset"

  if ($Stats.LastVersion) {
    Write-Host "$border│ $label Version      : $value$($Stats.LastVersion)$reset"
  }

  if ($Stats.LastModel) {
    Write-Host "$border│ $label Model        : $value$($Stats.LastModel)$reset"
  }

  if ($Stats.LastEffort) {
    Write-Host "$border│ $label Effort       : $value$($Stats.LastEffort)$reset"
  }

  Write-Host "$border│ $label Turns        : $value$($Stats.Turns)$reset"
  Write-Host "$border│ $label Total time   : $value$(Format-CodexTerminalDuration $Stats.TotalDuration)$reset"
  Write-Host "$border│ $label Total tokens : $value$('{0:n0}' -f $Stats.TotalTokens)$reset"

  if ($Stats.TurnStats.Count -gt 1) {
    Write-Host "$border│$reset"

    foreach ($turn in $Stats.TurnStats) {
      $durationText = Format-CodexTerminalDuration $turn.Duration
      $tokensText = "{0:n0}" -f $turn.Tokens
      Write-Host "$border│ $muted Turn $($turn.Turn) : $durationText - $tokensText tokens$reset"
    }
  }

  Write-Host "$border╰────────────────────────────────────$reset"
  Write-Host ""
}

function Write-CodexCyanDotsWhileWaiting {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Diagnostics.Process] $Process,

    [Parameter(Mandatory)]
    [string] $Message,

    [int] $IntervalMs = 220
  )

  $icons = @("🔄", "🔃")
  $iconIdx = 0
  $dots = 0
  $lastLen = 0

  while (-not $Process.HasExited) {
    $dots = ($dots % 3) + 1

    if ($dots -eq 1) {
      $iconIdx = ($iconIdx + 1) % $icons.Count
    }

    $text = "{0} {1}{2}" -f $icons[$iconIdx], $Message, ("." * $dots)
    $pad = 0

    if ($lastLen -gt $text.Length) {
      $pad = $lastLen - $text.Length
    }

    $lastLen = $text.Length

    Write-Host -NoNewline ("`r" + $text + (" " * $pad)) -ForegroundColor Cyan
    Start-Sleep -Milliseconds $IntervalMs
  }

  Write-Host -NoNewline ("`r" + (" " * $lastLen) + "`r")
}

function Invoke-CodexWithSpinner {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Prompt,

    [string] $Model = $(Get-CodexTerminalModel),

    [string] $Effort = $(Get-CodexTerminalEffort),

    [Parameter(Mandatory)]
    [string] $SpinnerMessage,

    [int] $SpinnerIntervalMs = 220
  )

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = "codex"

  $null = $psi.ArgumentList.Add("exec")
  $null = $psi.ArgumentList.Add("--ephemeral")
  $null = $psi.ArgumentList.Add("--skip-git-repo-check")
  $null = $psi.ArgumentList.Add("--model")
  $null = $psi.ArgumentList.Add($Model)
  $null = $psi.ArgumentList.Add("-c")
  $null = $psi.ArgumentList.Add("model_reasoning_effort=$Effort")
  $null = $psi.ArgumentList.Add($Prompt)

  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true

  # Important : Codex emits UTF-8. Without this, fancy quotes/thin spaces can become ÔÇ£, ...
  $psi.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
  $psi.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

  $p = [System.Diagnostics.Process]::new()
  $p.StartInfo = $psi

  $sw = [System.Diagnostics.Stopwatch]::StartNew()

  if (-not $p.Start()) {
    throw "❌ Failed to start codex"
  }

  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()

  Write-CodexCyanDotsWhileWaiting -Process $p -Message $SpinnerMessage -IntervalMs $SpinnerIntervalMs

  $p.WaitForExit()
  [System.Threading.Tasks.Task]::WaitAll(@($outTask, $errTask))
  $sw.Stop()

  $stdout = Repair-CodexTextEncoding ($outTask.Result ?? "")
  $stderr = Repair-CodexTextEncoding ($errTask.Result ?? "")

  $combined = ($stdout + "`n" + $stderr).Trim()

  $parsed = ConvertFrom-CodexExecOutput -Text $combined
  $parsed | Add-Member -NotePropertyName Duration -NotePropertyValue $sw.Elapsed -Force

  return [pscustomobject]@{
    ExitCode = $p.ExitCode
    StdOut = $stdout
    StdErr = $stderr
    Combined = $combined
    Duration = $sw.Elapsed
    Parsed = $parsed
  }
}

function New-CodexTerminalCommandPrompt {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $UserRequest,

    [string] $PreviousCommand,

    [string] $Refinement
  )

  $escapedUserRequest = Escape-ForSingleQuotedPrompt $UserRequest

  if ($PreviousCommand -and $Refinement) {
    $escapedPreviousCommand = Escape-ForSingleQuotedPrompt $PreviousCommand
    $escapedRefinement = Escape-ForSingleQuotedPrompt $Refinement
@"
You are generating ONE terminal command for the user to paste and run.

<original_user_request>
'$escapedUserRequest'
</original_user_request>

<previous_assistant_command>
'$escapedPreviousCommand'
</previous_assistant_command>

<user_refinement>
'$escapedRefinement'
</user_refinement>

The user wants a refined replacement for the previous command. Keep what was good, fix or adjust what the user requested, and output the improved command.

HARD RULES (must follow):
- Output EXACTLY ONE runnable command line. No extra text
- No markdown, no code fences, no bullets, no leading markers (like ●), no comments
- No surrounding quotes around the whole command. No trailing whitespace
- Must be a non-interactive command (no prompts) unless the user explicitly asked for interactive behavior
- Do not insert line breaks in places where this can break the execution or even line separators. A one-liner will always be preferred, even if this means the line is very long !

SHELL/OS:
- Infer the target shell/OS from the user request (ex "pwsh 7", "bash", "windows 11", "linux")
- If unspecified, default to PowerShell 7 on Windows 11
- Use correct quoting/escaping for that shell (especially spaces and nested quotes). In PowerShell, remember the escape char is backtick and single-quotes inside single-quoted strings are doubled

SAFETY/DEFAULTS (because the output may be executed):
- Avoid destructive/irreversible actions unless explicitly requested
- Avoid overwriting files by default, prefer writing to a new output file unless the user asked to overwrite
- Prefer "safe" flags when available (ex no-clobber equivalents, dry-run/preview modes)
- Prefer built-in/common tools, don't require installing dependencies unless the user asked

QUALITY:
- Quote any path/arg that may contain spaces or special chars
- If multiple steps are required, express them as a single command line (pipeline / && / ; as appropriate for the shell)

Now output ONLY the raw command:
"@
  } else {
@"
You are generating ONE terminal command for the user to paste and run.

<user_request>
'$escapedUserRequest'
</user_request>

HARD RULES (must follow):
- Output EXACTLY ONE runnable command line. No extra text
- No markdown, no code fences, no bullets, no leading markers (like ●), no comments
- No surrounding quotes around the whole command. No trailing whitespace
- Must be a non-interactive command (no prompts) unless the user explicitly asked for interactive behavior
- Do not insert line breaks in places where this can break the execution or even line separators. A one-liner will always be preferred, even if this means the line is very long !

SHELL/OS:
- Infer the target shell/OS from the user request (ex "pwsh 7", "bash", "windows 11", "linux")
- If unspecified, default to PowerShell 7 on Windows 11
- Use correct quoting/escaping for that shell (especially spaces and nested quotes). In PowerShell, remember the escape char is backtick and single-quotes inside single-quoted strings are doubled

SAFETY/DEFAULTS (because the output may be executed):
- Avoid destructive/irreversible actions unless explicitly requested
- Avoid overwriting files by default, prefer writing to a new output file unless the user asked to overwrite
- Prefer "safe" flags when available (ex no-clobber equivalents, dry-run/preview modes)
- Prefer built-in/common tools, don't require installing dependencies unless the user asked

QUALITY:
- Quote any path/arg that may contain spaces or special chars
- If multiple steps are required, express them as a single command line (pipeline / && / ; as appropriate for the shell)

Now output ONLY the raw command:
"@
  }
}

function New-CodexTerminalExplainPrompt {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $EscapedCommand,

    [Parameter(Mandatory)]
    [ValidateSet("minimal", "simplified", "full")]
    [string] $Mode
  )

  switch ($Mode) {
    "minimal" {
@"
Explain the following command in exactly ONE concise sentence:

'$EscapedCommand'

Rules:
- Output only the sentence
- No heading
- No bullet points
- No markdown at all
- Be concrete about the command's purpose
"@
    } "simplified" {
@"
Explain the following command in short paragraphs:

'$EscapedCommand'

Rules:
- Keep it under 3 paragraphs
- Prefer 2-3 sentences max per paragraph
- Mention the executable, the main action, important safety/side-effect flags, and output behavior
- No detailed token-by-token breakdown
- Markdown only if necessary, and in that case only use stars for emphasis
- No questions
"@
    } default {
@"
Explain the following command:

'$EscapedCommand'

OUTPUT FORMAT RULES (IMPORTANT):
- plain text is preferred, markdown can be used if useful (only basic one)
- use # / ## headings if helpful
- use **stars** for emphasis, never __underscores__ (for both italic & bold)
- use backticks for commands, flags, filenames, placeholders, and code-like text
- use multiple lines with clear headings
- use bullet points
- do NOT ask questions, make reasonable assumptions and pick the most likely interpretation

STRUCTURE:
1) Summary (1-2 sentences)
2) Breakdown (bullet list): explain each token/flag/operator in order once, the first time it appears
   - identify the executable, each switch, each argument
   - explain quoting where relevant
   - explain operators like |, >, 2>&1, ... if necessary
3) Pipeline stages (if any): one section per stage, what it consumes/produces
4) Notes/caveats: if necessary, some bullets (gotchas, side effects, safety tips, ...)

Be thorough and concrete: explain what happens step-by-step. Follow the structure unless the command is very simple, in such case a simple detailed explanation in 2-3 paragraphs is enough (don't go overkill).
"@
    }
  }
}

function Invoke-CodexTerminalCommandGeneration {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $UserRequest,

    [string] $PreviousCommand,

    [string] $Refinement
  )

  $codexPrompt = New-CodexTerminalCommandPrompt -UserRequest $UserRequest -PreviousCommand $PreviousCommand -Refinement $Refinement

  $spinnerMessage = if ($PreviousCommand -and $Refinement) {
    "Codex is refining your command"
  } else {
    "Codex is generating your command"
  }

  $res = Invoke-CodexWithSpinner -Prompt $codexPrompt -SpinnerMessage $spinnerMessage

  if ($res.ExitCode -ne 0) {
    $msg = ($res.StdErr + $res.StdOut).Trim()

    if (-not $msg) {
      $msg = "Codex exited with code $($res.ExitCode)"
    }

    throw $msg
  }

  $raw = Normalize-CodexRawCommand -Text ($res.Parsed.Answer ?? "")

  return [pscustomobject]@{
    Command = $raw
    Parsed = $res.Parsed
    Duration = $res.Duration
    RawResult = $res
  }
}

function Clear-CodexTerminalMenu {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [int] $Top,

    [Parameter(Mandatory)]
    [int] $LineCount
  )

  $rawUi = $Host.UI.RawUI
  $width = [Math]::Max(1, $rawUi.BufferSize.Width - 1)
  $blank = " " * $width

  for ($i = 0; $i -lt $LineCount; $i++) {
    $y = $Top + $i

    if ($y -lt 0 -or $y -ge $rawUi.BufferSize.Height) {
      continue
    }

    $rawUi.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, $y)
    [Console]::Write($blank)
  }

  $rawUi.CursorPosition = [System.Management.Automation.Host.Coordinates]::new(0, $Top)
}

function Get-CodexTerminalActionIndex {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $DefaultAction,

    [Parameter(Mandatory)]
    [object[]] $Actions
  )

  for ($i = 0; $i -lt $Actions.Count; $i++) {
    if ($Actions[$i].Name -eq $DefaultAction) {
      return $i
    }
  }

  return 0
}

function Invoke-CodexTerminalExplainCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Command,

    [Parameter(Mandatory)]
    [string] $Caller
  )

  $escaped = Escape-ForSingleQuotedPrompt $Command
  $mode = Get-CodexTerminalExplainMode
  $codexPrompt = New-CodexTerminalExplainPrompt -EscapedCommand $escaped -Mode $mode
  $spinnerMessage = ($Caller -eq "explain") ? "Codex is explaining your command" : "Codex is explaining the suggested command"

  $res = Invoke-CodexWithSpinner -Prompt $codexPrompt -SpinnerMessage $spinnerMessage

  if ($res.ExitCode -ne 0) {
    $msg = ($res.StdErr + $res.StdOut).Trim()

    if (-not $msg) {
      $msg = "Codex exited with code $($res.ExitCode)"
    }

    throw $msg
  }

  return [pscustomobject]@{
    Explanation = $res.Parsed.Answer
    Parsed = $res.Parsed
    Duration = $res.Duration
    RawResult = $res
  }
}

function Read-CodexTerminalCommandAction {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $DefaultAction
  )

  $actions = @(
    [pscustomobject]@{
      Name = "copy"
      Label = "Copy"
      Description = "Copy command to clipboard"
    },
    [pscustomobject]@{
      Name = "explain"
      Label = "Explain"
      Description = "Explain the suggested command"
    },
    [pscustomobject]@{
      Name = "refine"
      Label = "Refine"
      Description = "Add more instructions and regenerate"
    },
    [pscustomobject]@{
      Name = "execute"
      Label = "Execute"
      Description = "Run command in this shell session"
    },
    [pscustomobject]@{
      Name = "exit"
      Label = "Exit"
      Description = "Do nothing"
    }
  )

  $selected = Get-CodexTerminalActionIndex -DefaultAction $DefaultAction -Actions $actions

  $reset = $PSStyle.Reset
  $titleColor = $PSStyle.Foreground.Magenta
  $hintColor = $PSStyle.Foreground.BrightBlack
  $normalColor = $PSStyle.Foreground.White
  $descColor = $PSStyle.Foreground.BrightBlack
  $selectedFg = $PSStyle.Foreground.Black
  $selectedBg = $PSStyle.Background.Cyan

  # Blank line before menu, this line is part of the redraw block
  $lineCount = 1 + 2 + $actions.Count + 1
  $renderedOnce = $false

  $oldCursorVisible = $true

  try {
    $oldCursorVisible = [Console]::CursorVisible
    [Console]::CursorVisible = $false
  } catch { }

  function Strip-Ansi {
    param([AllowEmptyString()][string] $Text)

    return ($Text -replace "`e\[[0-9;]*m", "")
  }

  function Get-SafeMenuLine {
    param([AllowEmptyString()][string] $Text)

    $width = [Math]::Max(20, [Console]::BufferWidth - 1)
    $plain = Strip-Ansi $Text

    # Keep menu lines comfortably short, this avoids wrapping, which ruins redraw
    if ($plain.Length -ge $width) {
      $max = [Math]::Max(1, $width - 4)

      return $plain.Substring(0, [Math]::Min($plain.Length, $max)) + "..."
    }

    return $Text
  }

  function Write-MenuBlock {
    if ($script:renderedOnce) {
      # Move cursor back to beginning of previous menu block, then clear it
      [Console]::Write("`e[$script:lineCount`A")
      [Console]::Write("`e[0J")
    }

    $lines = New-Object System.Collections.Generic.List[string]

    $lines.Add("")
    $lines.Add("$script:titleColor Choose action$script:reset")
    $lines.Add("$script:hintColor Up/Down move - Enter select - Esc exit$script:reset")

    for ($i = 0; $i -lt $script:actions.Count; $i++) {
      $prefix = if ($i -eq $script:selected) { ">" } else { " " }
      $label = $script:actions[$i].Label.PadRight(8)
      $description = $script:actions[$i].Description

      if ($i -eq $script:selected) {
        $lines.Add("$script:selectedBg$script:selectedFg $prefix $label $description $script:reset")
      } else {
        $lines.Add("$script:normalColor $prefix $label$script:reset $script:descColor$description$script:reset")
      }
    }

    $lines.Add("")

    foreach ($line in $lines) {
      [Console]::WriteLine((Get-SafeMenuLine $line))
    }

    $script:renderedOnce = $true
  }

  function Clear-MenuBlock {
    if ($script:renderedOnce) {
      [Console]::Write("`e[$script:lineCount`A")
      [Console]::Write("`e[0J")
      $script:renderedOnce = $false
    }
  }

  try {
    # Use script scope only inside these nested functions
    $script:actions = $actions
    $script:selected = $selected
    $script:lineCount = $lineCount
    $script:renderedOnce = $renderedOnce
    $script:reset = $reset
    $script:titleColor = $titleColor
    $script:hintColor = $hintColor
    $script:normalColor = $normalColor
    $script:descColor = $descColor
    $script:selectedFg = $selectedFg
    $script:selectedBg = $selectedBg

    Write-MenuBlock

    while ($true) {
      $key = [Console]::ReadKey($true)

      switch ($key.Key) {
        "UpArrow" {
          $script:selected--

          if ($script:selected -lt 0) {
            $script:selected = $script:actions.Count - 1
          }

          Write-MenuBlock
        } "DownArrow" {
          $script:selected++

          if ($script:selected -ge $script:actions.Count) {
            $script:selected = 0
          }

          Write-MenuBlock
        } "Enter" {
          $chosen = $script:actions[$script:selected].Name
          Clear-MenuBlock
          return $chosen
        } "Escape" {
          Clear-MenuBlock
          return "exit"
        }
      }
    }
  } finally {
    Clear-MenuBlock

    Remove-Variable -Name actions -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name selected -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name lineCount -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name renderedOnce -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name reset -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name titleColor -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name hintColor -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name normalColor -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name descColor -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name selectedFg -Scope Script -ErrorAction SilentlyContinue
    Remove-Variable -Name selectedBg -Scope Script -ErrorAction SilentlyContinue

    try {
      [Console]::CursorVisible = $oldCursorVisible
    } catch { }
  }
}

function Add-CodexTerminalCommandToHistory {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Command
  )

  try {
    $psrl = [type]::GetType("Microsoft.PowerShell.PSConsoleReadLine", $false)

    if ($psrl) {
      $addToHistory = $psrl.GetMethod(
        "AddToHistory",
        [System.Reflection.BindingFlags] "Public, Static",
        $null,
        [type[]] @([string]),
        $null
      )

      if ($addToHistory) {
        $null = $addToHistory.Invoke($null, @($Command))

        return
      }
    }

    # Fallback for normal PowerShell 7/PSReadLine sessions, this class is provided by the PSReadLine module and is what backs the interactive command-line editing/history experience
    if ("Microsoft.PowerShell.PSConsoleReadLine" -as [type]) {
      [Microsoft.PowerShell.PSConsoleReadLine]::AddToHistory($Command)

      return
    }
  } catch {
    # Best-effort only, execution should not fail if history insertion fails
  }
}

function Invoke-CodexTerminalGeneratedCommand {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Command
  )

  try {
    Add-CodexTerminalCommandToHistory -Command $Command
    Invoke-Expression $Command
  } catch {
    Write-Host "❌ Execution failed : $($_.Exception.Message)" -ForegroundColor Red
  }
}

function cts {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Prompt
  )

  $text = Get-InvocationRemainder -Line $MyInvocation.Line -InvocationName $MyInvocation.InvocationName @Prompt

  if ($text -match '^\s*--%\s*(.*)$') {
    $text = $Matches[1]
  }

  if (-not $text) {
    throw "❌ No query provided, use cts --% <what you want to run> (ex : cts --% git, get the 5 most active committers in the last month and sort them by number of commits)"
  }

  try {
    $defaultAction = Get-CodexTerminalDefaultAction
    $originalUserPrompt = $text
    $currentCommand = $null
    $refinement = $null
    $needsGeneration = $true
    $stats = New-CodexTerminalStatsBag

    while ($true) {
      if ($needsGeneration) {
        $generation = Invoke-CodexTerminalCommandGeneration -UserRequest $originalUserPrompt -PreviousCommand $currentCommand -Refinement $refinement
  
        $currentCommand = $generation.Command
        Add-CodexTerminalTurnStats -Stats $stats -Parsed $generation.Parsed
  
        Write-SimpleMarkdown -Text $currentCommand
  
        $needsGeneration = $false
      }

      $action = Read-CodexTerminalCommandAction -DefaultAction $defaultAction

      switch ($action) {
        "copy" {
          Set-Clipboard -Value $currentCommand

          if (Get-CodexTerminalVerbose) {
            Write-CodexTerminalFinalVerboseHeader -Stats $stats
          } else {
            Write-Host ""
          }

          Write-Host "✅ Command copied to the clipboard" -ForegroundColor Green

          return
        } "explain" {
          Write-Host ""
  
          $explanation = Invoke-CodexTerminalExplainCommand -Command $currentCommand -Caller "refine"
          Add-CodexTerminalTurnStats -Stats $stats -Parsed $explanation.Parsed
  
          Write-SimpleMarkdown -Text $explanation.Explanation
          Write-Host ""
  
          continue
        } "refine" {
          Write-Host ""
          $newRefinement = Read-Host "🧪 Refine "

          if ([string]::IsNullOrWhiteSpace($newRefinement)) {
            Write-Host "No refinement entered, returning to menu" -ForegroundColor Yellow
            continue
          }

          $refinement = $newRefinement
          $needsGeneration = $true
          Write-Host ""

          continue
        } "execute" {
          if (Get-CodexTerminalVerbose) {
            Write-CodexTerminalFinalVerboseHeader -Stats $stats
          } else {
            Write-Host ""
          }

          Invoke-CodexTerminalGeneratedCommand -Command $currentCommand

          return
        } "exit" {
          if (Get-CodexTerminalVerbose) {
            Write-CodexTerminalFinalVerboseHeader -Stats $stats
          } else {
            Write-Host ""
          }

          Write-Host "↩ Exited without copying or executing" -ForegroundColor DarkGray

          return
        }
      }
    }
  } catch {
    Write-Host "❌ cts failed : $($_.Exception.Message)" -ForegroundColor Red
  }
}

function cte {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Prompt
  )

  $text = Get-InvocationRemainder -Line $MyInvocation.Line -InvocationName $MyInvocation.InvocationName @Prompt

  # Support : cte --% raw command with pipes/redirections/quotes
  if ($text -match '^\s*--%\s*(.*)$') {
    $text = $Matches[1]
  }

  if (-not $text) {
    throw "❌ No query provided, use cte --% <command to explain> (ex : cte --% git log --oneline --graph --decorate --all | head -20)"
  }

  try {
    $stats = New-CodexTerminalStatsBag
    $explanation = Invoke-CodexTerminalExplainCommand -Command $text -Caller "explain"
    Add-CodexTerminalTurnStats -Stats $stats -Parsed $explanation.Parsed
  
    if (Get-CodexTerminalVerbose) {
      Write-CodexTerminalFinalVerboseHeader -Stats $stats
    }
  
    Write-SimpleMarkdown -Text $explanation.Explanation
  } catch {
    Write-Host "❌ cte failed : $($_.Exception.Message)" -ForegroundColor Red
  }
}

# Search terms in configurable folders
function Search-Term {
  [CmdletBinding()]
  param(
    [switch] $Help,

    [ValidateSet("All", "Any", "Phrase")]
    [string] $Mode = "All",

    [switch] $Regex,
    [switch] $CaseSensitive,
    [switch] $NoWordBoundary,
    [switch] $NoHighlight,

    # Enabled by default, use -Delta:$false to use the built-in formatter
    [bool] $Delta = $true,

    # Folder paths to search, can be absolute or relative. Relative paths are resolved from the current directory at runtime.
    [Alias("Paths", "Folder", "Folders")]
    [string[]] $Path,

    # Split quoted strings too :
    #   Search-Term -Mode Any "query1 query2" -SplitQuoted
    # becomes :
    #   query1 OR query2 (searches on the same line)
    [switch] $SplitQuoted,

    # File encoding strategy
    # auto = rg utf-8 pass, then windows-1252 fallback for missed lines
    # You can also force one or more explicit rg encodings :
    #   -Encoding utf-8
    #   -Encoding windows-1252
    #   -Encoding utf-8, windows-1252
    [string[]] $Encoding = @("auto"),

    [Parameter(Position = 0, ValueFromRemainingArguments = $true)]
    [string[]] $Query
  )

  $esc = [char]27
  $bold = "$esc[1m"
  $reset = "$esc[0m"
  $cyan = "$esc[36m"
  $yellow = "$esc[33m"
  $gray = "$esc[90m"
  $green = "$esc[32m"
  $red = "$esc[31m"

  function Split-STPaths {
    param([string] $Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
      return @()
    }

    $items = New-Object System.Collections.Generic.List[string]
    $current = New-Object System.Text.StringBuilder

    for ($i = 0; $i -lt $Value.Length; $i++) {
      $char = $Value[$i]

      # A colon is a Windows drive colon if it looks like :
      #   C:\
      #   C:/
      #
      # This must work both at the beginning :
      #   C:\foo
      #
      # and after an ST_PATHS separator :
      #   C:\foo:C:\bar
      $isWindowsDriveColon =
        $char -eq ":" -and
        $i -gt 0 -and
        $Value[$i - 1] -match "[A-Za-z]" -and
        $Value.Length -gt ($i + 1) -and
        ($Value[$i + 1] -eq "\" -or $Value[$i + 1] -eq "/") -and
        (
          $i -eq 1 -or
          $Value[$i - 2] -eq ":"
        )

      $isSeparator = $char -eq ":" -and -not $isWindowsDriveColon

      if ($isSeparator) {
        $item = $current.ToString().Trim()

        if ($item -ne "") {
          $items.Add($item)
        }

        [void] $current.Clear()
      } else {
        [void] $current.Append($char)
      }
    }

    $last = $current.ToString().Trim()

    if ($last -ne "") {
      $items.Add($last)
    }

    return @($items)
  }

  function Resolve-STSearchPath {
    param([string] $InputPath)

    if ([string]::IsNullOrWhiteSpace($InputPath)) {
      return $null
    }

    $trimmed = $InputPath.Trim()

    if ([IO.Path]::IsPathRooted($trimmed)) {
      return [IO.Path]::GetFullPath($trimmed)
    }

    $currentDirectory = (Get-Location).ProviderPath

    return [IO.Path]::GetFullPath((Join-Path $currentDirectory $trimmed))
  }

  function Normalize-STPath {
    param([string] $InputPath)

    return ([IO.Path]::GetFullPath($InputPath)).TrimEnd("\", "/")
  }

  if ($Help) {
    Write-Host ""
    Write-Host "${bold}${cyan}Search-Term${reset}"
    Write-Host ""
    Write-Host "Searches folders with ripgrep, uses delta by default syntax highlighting and sorting"
    Write-Host ""
    Write-Host "${bold}Usage${reset}"
    Write-Host "  Search-Term query"
    Write-Host "  Search-Term query1 query2"
    Write-Host "  Search-Term -Mode Any query1 query2"
    Write-Host "  Search-Term -Mode Phrase 'query1 query2'"
    Write-Host "  Search-Term -Regex 'pattern'"
    Write-Host "  Search-Term query -Path src, tests"
    Write-Host "  Search-Term query -Path C:\Code\project, .\local"
    Write-Host "  Search-Term query '--' -g '*.ini'"
    Write-Host "  Search-Term query '--' --type py --hidden"
    Write-Host ""
    Write-Host "${bold}Path resolution${reset}"
    Write-Host "  -Path/-Paths     Folders to search, can be absolute or relative"
    Write-Host "                   Relative paths are resolved from the current directory at runtime"
    Write-Host ""
    Write-Host "  ST_PATHS         Fallback environment variable when -Path is omitted"
    Write-Host "                   Uses colon-separated folders"
    Write-Host "                   Example : `$env:ST_PATHS = 'src:tests:C:\Code\project'"
    Write-Host ""
    Write-Host "  Default          If neither -Path nor ST_PATHS is provided, searches the current directory"
    Write-Host ""
    Write-Host "${bold}Modes${reset}"
    Write-Host "  -Mode All        Default, keep only lines containing every query term"
    Write-Host "                   Example : Search-Term query1 query2"
    Write-Host ""
    Write-Host "  -Mode Any        Keep lines containing at least one query term"
    Write-Host "                   Example : Search-Term -Mode Any query1 query2"
    Write-Host ""
    Write-Host "  -Mode Phrase     Treat the whole query as one phrase"
    Write-Host "                   Example : Search-Term -Mode Phrase 'query1 query2'"
    Write-Host ""
    Write-Host "${bold}Query parsing${reset}"
    Write-Host "  Search-Term query1 query2"
    Write-Host "    => two terms : query1, query2"
    Write-Host ""
    Write-Host "  Search-Term 'query1 query2'"
    Write-Host "    => one term : query1 query2"
    Write-Host ""
    Write-Host "  Search-Term 'query1 query2' -SplitQuoted"
    Write-Host "    => two terms : query1, query2"
    Write-Host ""
    Write-Host "${bold}Parameters${reset}"
    Write-Host "  -Path            Folders to search"
    Write-Host "  -Regex           Treat query terms as regex patterns instead of literal strings"
    Write-Host "  -CaseSensitive   Match case exactly, by default search is case-insensitive"
    Write-Host "  -NoWordBoundary  Disable rg -w, useful for partial identifiers"
    Write-Host "  -NoHighlight     Disable yellow highlighting in built-in formatter"
    Write-Host "  -Delta           Use delta for syntax highlighting/sorting, enabled by default"
    Write-Host "                   Disable with : Search-Term query -Delta:`$false"
    Write-Host "  -SplitQuoted     Split quoted query strings by whitespace in All/Any modes"
    Write-Host "  -Encoding        File encoding strategy, default is auto"
    Write-Host "                   auto = rg utf-8 pass, then windows-1252 fallback for missed lines"
    Write-Host "                   You can also force one or more explicit rg encodings :"
    Write-Host "                     -Encoding utf-8"
    Write-Host "                     -Encoding windows-1252"
    Write-Host "                     -Encoding utf-8, windows-1252"
    Write-Host "  '--' <rg args>   Pass custom arguments directly to rg"
    Write-Host "                   Example : Search-Term query '--' -g '*.py' --hidden"
    Write-Host "  -Help            Show this help"
    Write-Host ""

    return
  }

  # Split Search-Term query args from raw rg passthrough args
  #
  # PowerShell consumes unquoted --, so prefer :
  #   Search-Term dstd --rg -g '*.ini'
  #
  # Quoted '--' also works :
  #   Search-Term dstd '--' -g '*.ini'
  $rgPassthroughArgs = @()
  $searchTermArgs = @()
  $separatorIndex = -1

  for ($i = 0; $i -lt $Query.Count; $i++) {
    if ($Query[$i] -eq "--rg" -or $Query[$i] -eq "--") {
      $separatorIndex = $i
      break
    }
  }

  if ($separatorIndex -ge 0) {
    if ($separatorIndex -gt 0) {
      $searchTermArgs = @($Query[0..($separatorIndex - 1)])
    }

    if ($separatorIndex -lt ($Query.Count - 1)) {
      $rgPassthroughArgs = @($Query[($separatorIndex + 1)..($Query.Count - 1)])
    }

    $Query = $searchTermArgs
  }

  if (-not $Query -or $Query.Count -eq 0) {
    Write-Host "${red}Missing query${reset}, use ${bold}Search-Term -Help${reset} for examples"

    return
  }

  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)

  if (-not (Get-Command rg -ErrorAction SilentlyContinue)) {
    throw "ripgrep (rg) was not found in PATH"
  }

  if ($Delta -and -not (Get-Command delta -ErrorAction SilentlyContinue)) {
    throw "delta was not found in PATH, install delta or run with -Delta:`$false"
  }

  # Build search terms
  #
  # Default :
  #   Search-Term query1 query2    => query1, query2
  #   Search-Term "query1 query2"  => query1 query2
  #
  # With -SplitQuoted :
  #   Search-Term "query1 query2"  => query1, query2
  #
  # Phrase :
  #   Search-Term -Mode Phrase query 1 query 2
  #   Search-Term -Mode Phrase "query 1 query 2"
  # both become :
  #   query 1 query 2
  if ($Mode -eq "Phrase") {
    $terms = @($Query -join " ")
  } elseif ($SplitQuoted) {
    $terms = @(
      $Query |
        ForEach-Object { $_ -split "\s+" } |
        Where-Object { $_ -ne "" }
    )
  } else {
    $terms = @($Query | Where-Object { $_ -ne "" })
  }

  if (-not $terms -or $terms.Count -eq 0) {
    Write-Host "${red}Missing query${reset}, use ${bold}Search-Term -Help${reset} for examples"

    return
  }

  # Build search paths :
  #   1. -Path
  #   2. ST_PATHS
  #   3. current directory
  $requestedPaths = @()

  if ($Path -and $Path.Count -gt 0) {
    $requestedPaths = @($Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
  } elseif (-not [string]::IsNullOrWhiteSpace($env:ST_PATHS)) {
    $requestedPaths = @(Split-STPaths $env:ST_PATHS)
  } else {
    $requestedPaths = @(".")
  }

  $searchRoots = @()

  foreach ($requestedPath in $requestedPaths) {
    $resolvedPath = Resolve-STSearchPath $requestedPath

    if (-not $resolvedPath) {
      continue
    }

    if (Test-Path -LiteralPath $resolvedPath) {
      $normalizedPath = Normalize-STPath $resolvedPath
      $name = Split-Path -Leaf $normalizedPath

      if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $normalizedPath
      }

      $searchRoots += [pscustomobject]@{
        Name = $name
        Path = $normalizedPath
      }
    } else {
      Write-Warning "Missing search path : $resolvedPath"
    }
  }

  $searchRoots = @(
    $searchRoots |
      Group-Object Path |
      ForEach-Object { $_.Group[0] }
  )

  if ($searchRoots.Count -eq 0) {
    Write-Host "${red}No search folders found${reset}"

    return
  }

  $searchPaths = @($searchRoots | ForEach-Object { $_.Path })

  $rgBaseArgs = @(
    "--json",
    "--no-heading",
    "--color=never",
    "--column"
  )

  $rgSearchArgs = @()

  if (-not $CaseSensitive) {
    $rgSearchArgs += "-i"
  }

  if (-not $NoWordBoundary) {
    $rgSearchArgs += "-w"
  }

  if (-not $Regex) {
    $rgSearchArgs += "--fixed-strings"
  }

  foreach ($term in $terms) {
    $rgSearchArgs += @("-e", $term)
  }

  if ($rgPassthroughArgs.Count -gt 0) {
    $rgSearchArgs += $rgPassthroughArgs
  }

  $rgSearchArgs += $searchPaths

  function Invoke-STRipgrep {
    param(
      [string[]] $BaseArgs,
      [string[]] $SearchArgs,
      [string] $EncodingName
    )

    $ripgrepArgs = @()
    $ripgrepArgs += $BaseArgs

    if (-not [string]::IsNullOrWhiteSpace($EncodingName)) {
      $ripgrepArgs += @("--encoding", $EncodingName)
    }

    $ripgrepArgs += $SearchArgs

    $oldConsoleEncoding = [Console]::OutputEncoding
    $oldOutputEncoding = $OutputEncoding

    try {
      [Console]::OutputEncoding = $utf8NoBom
      $OutputEncoding = $utf8NoBom

      return @(& rg @ripgrepArgs 2>$null)
    } finally {
      [Console]::OutputEncoding = $oldConsoleEncoding
      $OutputEncoding = $oldOutputEncoding
    }
  }

  function Get-STDecodeScore {
    param([string] $Text)

    if ($null -eq $Text) {
      return 999999
    }

    $score = 0

    # Unicode replacement char, typical failed UTF-8 decode
    $score += ([regex]::Matches($Text, [char]0xfffd).Count * 100)

    # Common UTF-8-as-Windows-1252 mojibake
    $score += ([regex]::Matches($Text, 'Ã|Â|â€™|â€œ|â€|â€“|â€”').Count * 20)

    # Control chars, excluding normal tab
    $score += ([regex]::Matches($Text, '[\x00-\x08\x0B\x0C\x0E-\x1F]').Count * 50)

    return $score
  }

  $encodingPlan = @()

  if (
    -not $Encoding -or
    $Encoding.Count -eq 0 -or
    (
      $Encoding.Count -eq 1 -and
      [string]::IsNullOrWhiteSpace($Encoding[0])
    ) -or
    (
      $Encoding.Count -eq 1 -and
      $Encoding[0].Equals("auto", [StringComparison]::OrdinalIgnoreCase)
    )
  ) {
    # Auto strategy : Run both explicit decoders, then keep the cleaner decoded line
    # This handles mixed UTF-8/Windows-1252 trees better than rg default mode, because rg default can skip non-UTF-8 lines
    $encodingPlan = @("utf-8", "windows-1252")
  } else {
    $encodingPlan = @(
      $Encoding |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object {
          if ($_.Equals("auto", [StringComparison]::OrdinalIgnoreCase)) {
            "utf-8"
            "windows-1252"
          } elseif ($_.Equals("default", [StringComparison]::OrdinalIgnoreCase)) {
            ""
          } else {
            $_
          }
        }
    )
  }

  $bestMatchByLine = @{}
  $metadata = New-Object System.Collections.Generic.List[string]

  foreach ($encodingName in $encodingPlan) {
    $passResults = Invoke-STRipgrep `
      -BaseArgs $rgBaseArgs `
      -SearchArgs $rgSearchArgs `
      -EncodingName $encodingName

    foreach ($jsonLine in $passResults) {
      try {
        $item = $jsonLine | ConvertFrom-Json -ErrorAction Stop
      } catch {
        continue
      }

      if ($item.type -ne "match") {
        # Keep metadata from the first pass only
        if ($metadata.Count -lt 100 -and $encodingName -eq $encodingPlan[0]) {
          [void] $metadata.Add($jsonLine)
        }

        continue
      }

      if (-not $item.data -or -not $item.data.path -or -not $item.data.path.text) {
        continue
      }

      $lineRaw = $item.data.lines.text

      if ($null -eq $lineRaw) {
        continue
      }

      $path = [string] $item.data.path.text
      $line = [string] $item.data.line_number

      # One rg JSON "match" record is line-based and contains submatches, so path + line is the right dedupe key
      $key = "$path`u{1f}$line"

      $text = [string] $lineRaw
      $score = Get-STDecodeScore $text

      if (-not $bestMatchByLine.ContainsKey($key)) {
        $bestMatchByLine[$key] = [pscustomobject]@{
          JsonLine = $jsonLine
          Score    = $score
          Encoding = $encodingName
        }

        continue
      }

      $current = $bestMatchByLine[$key]

      if ($score -lt $current.Score) {
        $bestMatchByLine[$key] = [pscustomobject]@{
          JsonLine = $jsonLine
          Score    = $score
          Encoding = $encodingName
        }
      }
    }
  }

  $rawResults = @(
    $metadata
    $bestMatchByLine.Values | ForEach-Object { $_.JsonLine }
  )

  function Invoke-STDelta {
    param([object[]] $InputObject)

    $oldConsoleEncoding = [Console]::OutputEncoding
    $oldOutputEncoding = $OutputEncoding

    try {
      [Console]::OutputEncoding = $utf8NoBom
      $OutputEncoding = $utf8NoBom

      $InputObject | delta
    } finally {
      [Console]::OutputEncoding = $oldConsoleEncoding
      $OutputEncoding = $oldOutputEncoding
    }
  }

  function Get-STMatchCountFromJson {
    param([object[]] $InputObject)

    $count = 0

    foreach ($jsonLine in $InputObject) {
      try {
        $item = $jsonLine | ConvertFrom-Json -ErrorAction Stop
      } catch {
        continue
      }

      if ($item.type -ne "match") {
        continue
      }

      if (-not $item.data -or -not $item.data.path -or -not $item.data.path.text) {
        continue
      }

      if ($null -eq $item.data.lines.text) {
        continue
      }

      $count++
    }

    return $count
  }

  function Write-STMatchCount {
    param([int] $Count)

    if ($Count -eq 0) {
      Write-Host "${gray}No matches found${reset}"
    } elseif ($Count -eq 1) {
      Write-Host ""
      Write-Host "${gray}1 match${reset}"
    } else {
      Write-Host ""
      Write-Host "${gray}${Count} matches${reset}"
    }
  }

  # Delta path :
  #   rg --json pattern | delta
  #
  # We still preserve Search-Term query semantics :
  #   - Mode Any / Phrase can go straight to delta
  #   - Mode All needs post-filtering because rg -e term1 -e term2 is OR semantics
  if ($Delta) {
    if ($Mode -ne "All") {
      $matchCount = Get-STMatchCountFromJson $rawResults

      if ($matchCount -eq 0) {
        Write-STMatchCount $matchCount

        return
      }

      Invoke-STDelta $rawResults
      Write-STMatchCount $matchCount

      return
    }

    $comparison =
      if ($CaseSensitive) {
        [StringComparison]::Ordinal
      } else {
        [StringComparison]::OrdinalIgnoreCase
      }

    $options =
      if ($CaseSensitive) {
        [Text.RegularExpressions.RegexOptions]::None
      } else {
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
      }

    $deltaResults = @(
      $rawResults |
        ForEach-Object {
          $jsonLine = $_

          try {
            $item = $jsonLine | ConvertFrom-Json -ErrorAction Stop
          } catch {
            return
          }

          if ($item.type -ne "match") {
            return
          }

          $lineRaw = $item.data.lines.text

          if ($null -eq $lineRaw) {
            return
          }

          $line = [string]$lineRaw
          $keep = $true

          foreach ($term in $terms) {
            if ($Regex) {
              if (-not [regex]::IsMatch($line, $term, $options)) {
                $keep = $false

                break
              }
            } else {
              if ($line.IndexOf($term, $comparison) -lt 0) {
                $keep = $false

                break
              }
            }
          }

          if ($keep) {
            $jsonLine
          }
        }
    )

    if ($deltaResults.Count -eq 0) {
      Write-STMatchCount 0

      return
    }

    $matchCount = Get-STMatchCountFromJson $deltaResults

    Invoke-STDelta $deltaResults
    Write-STMatchCount $matchCount

    return
  }

  function Get-STRootForPath {
    param([string] $FullPath)

    $normalizedFullPath = Normalize-STPath $FullPath

    $matches = @(
      $searchRoots |
        Where-Object {
          $rootPath = $_.Path
          $normalizedFullPath.Equals($rootPath, [StringComparison]::OrdinalIgnoreCase) -or
          $normalizedFullPath.StartsWith($rootPath + "\", [StringComparison]::OrdinalIgnoreCase) -or
          $normalizedFullPath.StartsWith($rootPath + "/", [StringComparison]::OrdinalIgnoreCase)
        } |
        Sort-Object @{ Expression = { $_.Path.Length }; Descending = $true }
    )

    if ($matches.Count -gt 0) {
      return $matches[0]
    }

    return [pscustomobject]@{
      Name = "."
      Path = Normalize-STPath (Get-Location).ProviderPath
    }
  }

  $results = @(
    $rawResults |
      ForEach-Object {
        try {
          $item = $_ | ConvertFrom-Json -ErrorAction Stop
        } catch {
          return
        }

        if ($item.type -ne "match") {
          return
        }

        if (-not $item.data -or -not $item.data.path -or -not $item.data.path.text) {
          return
        }

        # rg JSON can occasionally have lines.text = $null depending on encoding/data, avoid crashing, skip those records
        $lineRaw = $item.data.lines.text

        if ($null -eq $lineRaw) {
          return
        }

        $fullPath = Normalize-STPath $item.data.path.text
        $rootItem = Get-STRootForPath $fullPath

        $lineText = [string]$lineRaw
        $lineText = $lineText.TrimEnd("`r", "`n")
        $lineNo = [int]$item.data.line_number

        $columns = @()

        if ($item.data.submatches) {
          foreach ($submatch in $item.data.submatches) {
            if ($null -ne $submatch.start) {
              $columns += ([int]$submatch.start + 1)
            }
          }
        }

        if ($columns.Count -eq 0) {
          $columns += 1
        }

        $relativePath = [IO.Path]::GetRelativePath($rootItem.Path, $fullPath)

        foreach ($column in $columns) {
          [pscustomobject]@{
            Root     = $rootItem.Name
            RootPath = $rootItem.Path
            File     = $relativePath
            FullPath = $fullPath
            Line     = $lineNo
            Column   = $column
            Text     = $lineText
          }
        }
      }
  )

  # In All mode, rg finds candidate lines with OR semantics, then we keep only lines containing every term
  if ($Mode -eq "All") {
    $comparison =
      if ($CaseSensitive) {
        [StringComparison]::Ordinal
      } else {
        [StringComparison]::OrdinalIgnoreCase
      }

    $options =
      if ($CaseSensitive) {
        [Text.RegularExpressions.RegexOptions]::None
      } else {
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
      }

    $results = @(
      $results | Where-Object {
        $line = $_.Text

        foreach ($term in $terms) {
          if ($Regex) {
            if (-not [regex]::IsMatch($line, $term, $options)) {
              return $false
            }
          } else {
            if ($line.IndexOf($term, $comparison) -lt 0) {
              return $false
            }
          }
        }

        return $true
      }
    )
  }

  # Dedupe because rg can emit more than one submatch for the same line/term combo
  $results = @(
    $results |
      Group-Object FullPath, Line, Column |
      ForEach-Object { $_.Group[0] } |
      Sort-Object `
        @{ Expression = { [array]::IndexOf(@($searchRoots.Path), $_.RootPath) } }, `
        @{ Expression = { $_.File } }, `
        @{ Expression = { $_.Line } }, `
        @{ Expression = { $_.Column } }
  )

  function Format-MatchText {
    param([string] $Text)

    if ($NoHighlight) {
      return $Text
    }

    if ($Regex) {
      return $Text
    }

    $escapedTerms = @(
      $terms |
        Where-Object { $_ } |
        Sort-Object Length -Descending |
        ForEach-Object { [regex]::Escape($_) }
    )

    if (-not $escapedTerms -or $escapedTerms.Count -eq 0) {
      return $Text
    }

    $options =
      if ($CaseSensitive) {
        [Text.RegularExpressions.RegexOptions]::None
      } else {
        [Text.RegularExpressions.RegexOptions]::IgnoreCase
      }

    $pattern = "(" + ($escapedTerms -join "|") + ")"

    return [regex]::Replace(
      $Text,
      $pattern,
      "${yellow}`$1${reset}",
      $options
    )
  }

  $currentRoot = $null
  $currentFile = $null
  $count = 0

  foreach ($result in $results) {
    if ($result.RootPath -ne $currentRoot) {
      if ($null -ne $currentRoot) {
        Write-Host ""
      }

      $currentRoot = $result.RootPath
      $currentFile = $null

      Write-Host "${bold}${cyan}$($result.Root)${reset}"
      Write-Host "  ${gray}$($result.RootPath)${reset}"
    }

    if ($result.File -ne $currentFile) {
      $currentFile = $result.File
      Write-Host "  ${bold}${green}${currentFile}${reset}"
    }

    $location = "{0}:{1}" -f $result.Line, $result.Column
    $text = Format-MatchText $result.Text

    Write-Host "    ${gray}${location}${reset}  $text"

    $count++
  }

  Write-STMatchCount $count
}

function Diff-Changes {
  [CmdletBinding()]
  param(
    [Parameter(
      Position = 0,
      ValueFromRemainingArguments = $true
    )]
    [string[]] $Path,

    [Parameter()]
    [string] $OriginalBase,

    [Parameter()]
    [string] $ChangedBase,

    [Parameter()]
    [hashtable] $FolderMap,

    [switch] $NoPager,

    [switch] $Help
  )

  if ($Help) {
    @"
Diff-Changes

Compares files between an original base folder and a changed base folder using git diff --no-index

USAGE
  Diff-Changes -Path <path[]> -OriginalBase <path> -ChangedBase <path> -FolderMap <hashtable> [-NoPager]

EXAMPLES
  `$folderMap = @{
    "folder1_dev" = "folder1_prod"
    "folder2_dev" = "folder2_prod"
  }

  Diff-Changes `
    -OriginalBase "C:\Users\EDM115\Path\To\BaseDevFolder" `
    -ChangedBase "\\192.168.1.1\path\to\prodfolder" `
    -FolderMap `$folderMap `
    -Path "folder1_dev\file.ts" `
    -NoPager

  Diff-Changes `
    -OriginalBase "C:\Users\EDM115\Path\To\BaseDevFolder" `
    -ChangedBase "\\192.168.1.1\path\to\prodfolder" `
    -FolderMap `$folderMap `
    "\\192.168.1.3\path\to\prodfolder\folder1_prod\file.ts"

PARAMETERS
  -Path
      One or more relative changed paths, such as :
        folder1_dev\file.ts

      Full paths under ChangedBase are also accepted

  -OriginalBase
      Base folder containing the original folders

  -ChangedBase
      Base folder containing the changed folders

  -FolderMap
      Hashtable mapping changed folder names to original folder names
      Example :
        "folder1_dev" = "folder1_prod"

  -NoPager
      Runs git diff with --no-pager

  -Help
      Shows this help text
"@

    return
  }

  if (-not $Path -or $Path.Count -eq 0) {
    throw "Path is required, use -Help for usage"
  }

  if ([string]::IsNullOrWhiteSpace($OriginalBase)) {
    throw "OriginalBase is required, use -Help for usage"
  }

  if ([string]::IsNullOrWhiteSpace($ChangedBase)) {
    throw "ChangedBase is required, use -Help for usage"
  }

  if (-not $FolderMap -or $FolderMap.Count -eq 0) {
    throw "FolderMap is required and must contain at least one mapping, use -Help for usage"
  }

  $git = Get-Command git -ErrorAction SilentlyContinue

  if (-not $git) {
    throw "git.exe was not found in PATH, install Git or add git.exe to PATH"
  }

  $originalBaseNormalized = $OriginalBase.TrimEnd('\') -replace '/', '\'
  $changedBaseNormalized  = $ChangedBase.TrimEnd('\') -replace '/', '\'

  foreach ($inputPath in $Path) {
    $relativePath = $inputPath.Trim('"').Trim("'") -replace '/', '\'

    if ($relativePath.StartsWith($changedBaseNormalized, [StringComparison]::OrdinalIgnoreCase)) {
      $relativePath = $relativePath.Substring($changedBaseNormalized.Length).TrimStart('\')
    }

    $parts = $relativePath -split '\\+', 2

    if ($parts.Count -lt 2) {
      Write-Error "Expected a path like 'folder1_dev\file.ts', got '$inputPath'"

      continue
    }

    $changedFolder = $parts[0]
    $fileRelativeToApp = $parts[1]

    if (-not $FolderMap.ContainsKey($changedFolder)) {
      Write-Error "Unknown folder '$changedFolder', expected one of : $($FolderMap.Keys -join ', ')"

      continue
    }

    $originalFolder = $FolderMap[$changedFolder]

    $changedFile = Join-Path $changedBaseNormalized $relativePath
    $originalFile = Join-Path (
      Join-Path $originalBaseNormalized $originalFolder
    ) $fileRelativeToApp

    if (-not (Test-Path -LiteralPath $changedFile -PathType Leaf)) {
      Write-Error "Changed file not found : $changedFile"

      continue
    }

    if (-not (Test-Path -LiteralPath $originalFile -PathType Leaf)) {
      Write-Error "Original file not found : $originalFile"

      continue
    }

    Write-Host ""
    Write-Host "=== Diff : $relativePath ===" -ForegroundColor Cyan
    Write-Host "Original : $originalFile" -ForegroundColor DarkGray
    Write-Host "Changed : $changedFile" -ForegroundColor DarkGray
    Write-Host ""

    $hadNativePref = Test-Path Variable:\PSNativeCommandUseErrorActionPreference

    if ($hadNativePref) {
      $oldNativePref = $PSNativeCommandUseErrorActionPreference
      $PSNativeCommandUseErrorActionPreference = $false
    }

    try {
      if ($NoPager) {
        & $git.Source --no-pager diff --no-index -- $originalFile $changedFile
      } else {
        & $git.Source diff --no-index -- $originalFile $changedFile
      }

      $exitCode = $LASTEXITCODE

      if ($exitCode -gt 1) {
        Write-Error "git diff failed for '$relativePath' with exit code $exitCode"
      }
    } finally {
      if ($hadNativePref) {
        $PSNativeCommandUseErrorActionPreference = $oldNativePref
      }
    }
  }
}

function Convert-CrlfToLfPreserveEncoding {
  [CmdletBinding(SupportsShouldProcess)]
  param(
    [string] $Path = ".",

    [switch] $Help,

    [string[]] $Extensions = @(
      ".py",
      ".txt",
      ".ini",
      ".cfg",
      ".json",
      ".md",
      ".yml",
      ".yaml",
      ".html",
      ".css",
      ".js",
      ".ts",
      ".xml",
      ".csv"
    ),

    [string[]] $ExcludeDirectoryNames = @(
      ".git",
      ".venv",
      "venv",
      "node_modules",
      "__pycache__"
    ),

    [switch] $IncludeDotDirectories
  )

  if ($Help) {
    @"
Convert-CrlfToLfPreserveEncoding

Converts CRLF line endings to LF while preserving detected file encoding

Encoding detection policy :
  - UTF-8 with BOM     => preserved as UTF-8 with BOM
  - Valid UTF-8        => written back as UTF-8 without BOM
  - Ambiguous UTF-8/Windows-1252 => treated as UTF-8
  - Otherwise Windows-1252 if valid
  - Otherwise skipped

Usage :
  Convert-CrlfToLfPreserveEncoding
  Convert-CrlfToLfPreserveEncoding -Path .
  Convert-CrlfToLfPreserveEncoding -Path . -Extensions .py,.txt,.ini
  Convert-CrlfToLfPreserveEncoding -Path . -Extensions "*"
  Convert-CrlfToLfPreserveEncoding -Path . -Extensions "*" -WhatIf
  Convert-CrlfToLfPreserveEncoding -Help

Parameters :
  -Path
      Root directory to process, defaults to current directory

  -Extensions
      File extensions to process
      Use "*" to process all likely-text files dynamically
      Binary-looking files are skipped when using "*"

  -ExcludeDirectoryNames
      Directory names to skip during recursion

  -IncludeDotDirectories
      By default, directories whose name starts with "." are skipped
      Use this switch to include them

  -WhatIf
      Preview changes without writing files (dry-run)
"@
    return
  }

  # Needed in PowerShell 7/.NET for legacy code pages like windows-1252, RegisterProvider makes those encodings available through Encoding.GetEncoding()
  try {
    Add-Type -AssemblyName System.Text.Encoding.CodePages -ErrorAction SilentlyContinue
    [System.Text.Encoding]::RegisterProvider(
      [System.Text.CodePagesEncodingProvider]::Instance
    )
  } catch {
    # Already registered/unavailable, ignore here
  }

  function Test-BytePrefix {
    param(
      [Parameter(Mandatory)]
      [byte[]] $Bytes,

      [Parameter(Mandatory)]
      [byte[]] $Prefix
    )

    if ($Bytes.Length -lt $Prefix.Length) {
      return $false
    }

    for ($i = 0; $i -lt $Prefix.Length; $i++) {
      if ($Bytes[$i] -ne $Prefix[$i]) {
        return $false
      }
    }

    return $true
  }

  function New-StrictEncoding {
    param(
      [Parameter(Mandatory)]
      [string] $Name,

      [switch] $Utf8Bom
    )

    $base = [System.Text.Encoding]::GetEncoding($Name)

    # For UTF-8, control BOM explicitly and throw on invalid byte sequences
    if ($base.CodePage -eq 65001) {
      return [System.Text.UTF8Encoding]::new([bool] $Utf8Bom, $true)
    }

    # For legacy encodings, throw if decoding/encoding fails
    return [System.Text.Encoding]::GetEncoding(
      $base.CodePage,
      [System.Text.EncoderFallback]::ExceptionFallback,
      [System.Text.DecoderFallback]::ExceptionFallback
    )
  }

  function Test-LikelyTextBytes {
    param(
      [Parameter(Mandatory)]
      [byte[]] $Bytes,

      [int] $ProbeLength = 8192,

      [double] $MaxControlRatio = 0.05
    )

    if ($Bytes.Length -eq 0) {
      return $true
    }

    $length = [Math]::Min($Bytes.Length, $ProbeLength)
    $controlCount = 0

    for ($i = 0; $i -lt $length; $i++) {
      $b = $Bytes[$i]

      # NUL bytes are a very strong binary signal for our use case
      if ($b -eq 0x00) {
        return $false
      }

      # Allow common text control chars :
      # TAB, LF, CR, FF, BS
      if (
        $b -eq 0x09 -or
        $b -eq 0x0A -or
        $b -eq 0x0D -or
        $b -eq 0x0C -or
        $b -eq 0x08
      ) {
        continue
      }

      # Other C0 controls + DEL are suspicious in text files
      if ($b -lt 0x20 -or $b -eq 0x7F) {
        $controlCount++
      }
    }

    return (($controlCount / $length) -le $MaxControlRatio)
  }

  function Get-Utf8OrWindows1252Encoding {
    param(
      [Parameter(Mandatory)]
      [byte[]] $Bytes
    )

    $utf8BomBytes = [byte[]] (0xEF, 0xBB, 0xBF)

    if (Test-BytePrefix -Bytes $Bytes -Prefix $utf8BomBytes) {
      return [pscustomobject]@{
        Name      = "utf-8-bom"
        Encoding  = New-StrictEncoding -Name "utf-8" -Utf8Bom
        BomLength = 3
        Ambiguous = $false
      }
    }

    $utf8 = New-StrictEncoding -Name "utf-8"
    $win1252 = New-StrictEncoding -Name "windows-1252"

    $utf8Ok = $false
    $win1252Ok = $false

    try {
      $null = $utf8.GetString($Bytes)
      $utf8Ok = $true
    } catch { }

    try {
      $null = $win1252.GetString($Bytes)
      $win1252Ok = $true
    } catch { }

    # Requested policy : ambiguous => utf-8
    if ($utf8Ok) {
      return [pscustomobject]@{
        Name      = if ($win1252Ok) { "utf-8-ambiguous" } else { "utf-8" }
        Encoding  = $utf8
        BomLength = 0
        Ambiguous = $win1252Ok
      }
    }

    if ($win1252Ok) {
      return [pscustomobject]@{
        Name      = "windows-1252"
        Encoding  = $win1252
        BomLength = 0
        Ambiguous = $false
      }
    }

    return $null
  }

  $root = (Resolve-Path -LiteralPath $Path).Path

  $allTextLikeFiles = $Extensions.Count -eq 1 -and $Extensions[0] -eq "*"

  $normalizedExtensions = if ($allTextLikeFiles) {
    @("*")
  } else {
    $Extensions | ForEach-Object {
      if ($_.StartsWith(".")) { $_ } else { ".$_" }
    }
  }

  Get-ChildItem -LiteralPath $root -Recurse -File | ForEach-Object {
    $file = $_

    $relative = [System.IO.Path]::GetRelativePath($root, $file.FullName)
    $parent = Split-Path -Path $relative -Parent

    if ($parent) {
      $dirNames = $parent -split '[\\/]'

      foreach ($dirName in $dirNames) {
        if ($dirName -in $ExcludeDirectoryNames) {
          return
        }

        if (-not $IncludeDotDirectories -and $dirName.StartsWith(".")) {
          return
        }
      }
    }

    if (
      -not $allTextLikeFiles -and
      $normalizedExtensions.Count -gt 0 -and
      $file.Extension -notin $normalizedExtensions
    ) {
      return
    }

    try {
      $bytes = [System.IO.File]::ReadAllBytes($file.FullName)

      if ($allTextLikeFiles -and -not (Test-LikelyTextBytes -Bytes $bytes)) {
        [pscustomobject]@{
          Path   = $file.FullName
          Status = "skipped : likely binary"
        }

        return
      }

      $detected = Get-Utf8OrWindows1252Encoding -Bytes $bytes

      if ($null -eq $detected) {
        [pscustomobject]@{
          Path     = $file.FullName
          Encoding = "unknown"
          Status   = "skipped : neither utf-8 nor windows-1252"
        }

        return
      }

      $text = $detected.Encoding.GetString(
        $bytes,
        $detected.BomLength,
        $bytes.Length - $detected.BomLength
      )

      if (-not $text.Contains("`r`n")) {
        return
      }

      $newText = $text.Replace("`r`n", "`n")

      if ($PSCmdlet.ShouldProcess($file.FullName, "CRLF -> LF preserving $($detected.Name)")) {
        [System.IO.File]::WriteAllText(
          $file.FullName,
          $newText,
          $detected.Encoding
        )

        [pscustomobject]@{
          Path      = $file.FullName
          Encoding  = $detected.Name
          Ambiguous = $detected.Ambiguous
          Status    = "converted"
        }
      }
    } catch {
      [pscustomobject]@{
        Path   = $file.FullName
        Status = "error"
        Error  = $_.Exception.Message
      }
    }
  }
}

# fnm
fnm env --use-on-cd --version-file-strategy=recursive --shell powershell | Out-String | Invoke-Expression
fnm completions --shell powershell | Out-String | Invoke-Expression

# zoxide
zoxide init powershell --cmd cd | Out-String | Invoke-Expression

# PNPM
pnpm completion pwsh | Out-String | Invoke-Expression

# Codex
codex completion powershell | Out-String | Invoke-Expression

# ripgrep
rg --generate complete-powershell | Out-String | Invoke-Expression

# rust
rustup completions powershell | Out-String | Invoke-Expression

# hcloud cli
hcloud completion powershell | Out-String | Invoke-Expression

# uv
uv generate-shell-completion powershell | Out-String | Invoke-Expression
uvx --generate-shell-completion powershell | Out-String | Invoke-Expression

# deno, add `--dynamic` once ready
deno completions powershell | Out-String | Invoke-Expression

# jj
$env:COMPLETE = "powershell"
jj | Out-String | Invoke-Expression
Remove-Item Env:\COMPLETE

# Terminal icons
Import-Module -Name Terminal-Icons
$themes = Get-TerminalIconsTheme
foreach ($theme in $themes) {
  if ([string]::IsNullOrEmpty($theme.Color.Name)) {
    Add-TerminalIconsColorTheme -Force "D:\EDM115\Documents\.config\dracula.psd1"
    Set-TerminalIconsTheme -ColorTheme dracula
  }
}

function edit-history {
  notepad "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
}

function bun-upgrade {
  $basePath = "C:\Users\EDM115\Desktop\bun-upgrade-playground"
  New-Item -ItemType Directory -Path $basePath
  Push-Location $basePath
  bun init -y
  bun pm cache rm
  bun upgrade --stable
  bun build --compile --target=bun-linux-x64 index.ts --outfile ./out && bun build --compile --target=bun-linux-arm64 index.ts --outfile ./out && bun build --compile --target=bun-linux-x64-musl index.ts --outfile ./out && bun build --compile --target=bun-linux-arm64-musl index.ts --outfile ./out && bun build --compile --target=bun-darwin-x64 index.ts --outfile ./out && bun build --compile --target=bun-darwin-arm64 index.ts --outfile ./out && bun build --compile --target=bun-windows-x64 index.ts --outfile ./out.exe && bun build --compile --target=bun-windows-arm64 index.ts --outfile ./out.exe
  Pop-Location
  Remove-Item $basePath -Recurse -Force
  $bunVersion = (& bun -v | Out-String).Trim()
  Write-Host "✅ Upgraded Bun to $bunVersion" -ForegroundColor Green
}

# -----
# Stuff from https://github.com/ChrisTitusTech/powershell-profile/blob/main/Microsoft.PowerShell_profile.ps1
function Test-CommandExists {
  param($command)
  $exists = $null -ne (Get-Command $command -ErrorAction SilentlyContinue)

  return $exists
}

function touch($file) {
  "" | Out-File $file -Encoding UTF-8
}

function ff($name) {
  Get-ChildItem -recurse -filter "*${name}*" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Output "$($_.FullName)"
  }
}

function Get-PubIP {
  (Invoke-WebRequest http://ifconfig.me/ip).Content
}

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

function df {
  Get-Volume
}

function sed($file, $find, $replace) {
  (Get-Content $file).replace("$find", $replace) | Set-Content $file
}

function which($name) {
  Get-Command $name | Select-Object -ExpandProperty Definition
}

function export($name, $value) {
  Set-Item -force -path "env:$name" -value $value;
}

function pkill($name) {
  Get-Process $name -ErrorAction SilentlyContinue | Stop-Process
}

function pgrep($name) {
  Get-Process $name
}

function head {
  param($Path, $n = 10)
  Get-Content $Path -Head $n
}

function tail {
  param($Path, $n = 10, [switch]$f = $false)
  Get-Content $Path -Tail $n -Wait:$f
}

# Quick File Creation
function nf {
  param($name) New-Item -ItemType "file" -Path . -Name $name
}

# Directory Management
function mkcd {
  param($dir) mkdir $dir -Force; Set-Location $dir
}

# Simplified Process Management
function k9 {
  Stop-Process -Name $args[0]
}

# Enhanced Listing
function la {
  Get-ChildItem -Path . -Force | Format-Table -AutoSize
}

function ll {
  Get-ChildItem -Path . -Force -Hidden | Format-Table -AutoSize
}

# Quick Access to System Information
function sysinfo {
  Get-ComputerInfo
}

# Networking Utilities
function flushdns {
  Clear-DnsClientCache
  Write-Host "DNS has been flushed"
}

# Clipboard Utilities
function cpy {
  Set-Clipboard $args[0]
}

function pst {
  Get-Clipboard
}

# -----

#f45873b3-b655-43a6-b217-97c00aa0db58 PowerToys CommandNotFound module

Import-Module -Name Microsoft.WinGet.CommandNotFound
#f45873b3-b655-43a6-b217-97c00aa0db58

# DO NOT MODIFY -- coreutils -- 60b36fc6-2d59-49df-be51-28dd2f4c3c9a
# vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
# Inlining the template into the profile shaves off ~10ms (25%).
$script:__COREUTILS__ = [System.Collections.Generic.HashSet[string]]::new(
    [string[]]@(
        'arch', 'b2sum', 'base32', 'base64', 'basename',
        'basenc', 'cat', 'cksum', 'comm', 'cp',
        'csplit', 'cut', 'date', 'df', 'dirname',
        'du', 'echo', 'env', 'expr', 'factor',
        'false', 'find', 'fmt', 'fold', 'grep',
        'head', 'hostname', 'join', 'la', 'link',
        'ln', 'ls', 'md5sum', 'mkdir', 'mktemp',
        'mv', 'nl', 'nproc', 'numfmt', 'od',
        'pathchk', 'pr', 'printenv', 'printf', 'ptx',
        'pwd', 'readlink', 'realpath', 'rm', 'rmdir',
        'seq', 'sha1sum', 'sha224sum', 'sha256sum', 'sha384sum',
        'sha512sum', 'shuf', 'sleep', 'sort', 'split',
        'stat', 'sum', 'tac', 'tail', 'tee',
        'test', 'touch', 'tr', 'true', 'truncate',
        'tsort', 'unexpand', 'uniq', 'unlink', 'uptime',
        'wc', 'xargs', 'yes'
    ),
    [System.StringComparer]::OrdinalIgnoreCase
)

$script:__COREUTILS_FAST_SKIP__ = [regex]::new(
    '\b(?:' + ($script:__COREUTILS__ -join '|') + ')\b',
    [System.Text.RegularExpressions.RegexOptions]::Compiled -bor `
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
)

# Casting the scriptblock to Func<Ast,bool> once and reusing it avoids the
# per-FindAll scriptblock-to-delegate wrapping overhead (~1.7x faster).
$script:__COREUTILS_CMD_PREDICATE__ = [System.Func[System.Management.Automation.Language.Ast, bool]] {
    param($n) $n -is [System.Management.Automation.Language.CommandAst]
}

$script:__COREUTILS_ARG_SPECIAL__ = [char[]] @("'", '"', '`', '$')

# Wrap arguments into quotes. By being a function we can properly handle $variables.
# As per MSVCRT, any `\` before `"` must be doubled to escape them.
function global:__coreutils_q {
    param($s)
    '"' + (([string]$s) -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
}

# PowerShell tokenizes `*"a"*` as [BareWord] instead of the expected [DoubleQuoted, BareWord, DoubleQuoted].
# To work around that we use... regex. Group 1 = 'single', 2 = "double", 3 = `escape, 4 = bare run.
$script:__COREUTILS_ARG_RX__ = [regex]::new(
    "'((?:[^']|'')*)'|""((?:[^""``]|""""|``.)*)""|``(.)|([^'""``]+)",
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)
$script:__COREUTILS_ARG_EVAL__ = [System.Text.RegularExpressions.MatchEvaluator] {
    param($m)
    if ($m.Groups[1].Success) {
        # Single-quoted: literal. PS '' -> ', then MSVCRT-quote.
        $body = $m.Groups[1].Value.Replace("''", "'")
        if ($body -match '^(.*?)(\\+)$') {
            return '"' + ($matches[1] -replace '(\\*)"', '$1$1\"') + '"' + $matches[2]
        }
        return '"' + ($body -replace '(\\*)"', '$1$1\"') + '"'
    }
    if ($m.Groups[2].Success) {
        # Double-quoted: collapse PS quote-escapes to raw " / ', let ExpandString
        # resolve `n / `t / $var, then MSVCRT-quote.
        $body = $m.Groups[2].Value.
        Replace('`"', '"').
        Replace("``'", "'").
        Replace('""', '"')
        $body = $ExecutionContext.InvokeCommand.ExpandString($body)
        if ($body -match '^(.*?)(\\+)$') {
            return '"' + ($matches[1] -replace '(\\*)"', '$1$1\"') + '"' + $matches[2]
        }
        return '"' + ($body -replace '(\\*)"', '$1$1\"') + '"'
    }
    if ($m.Groups[3].Success) {
        # Backtick-escaped char outside a string: " -> \"; everything else
        # becomes a one-char quoted region so glob metas stay literal.
        $c = $m.Groups[3].Value
        if ($c -eq '"') {
            return '\"'
        }
        return '"' + $c + '"'
    }
    # Bare run: passed through unquoted so coreutils can glob it; expand $vars.
    return $ExecutionContext.InvokeCommand.ExpandString($m.Groups[4].Value)
}

# PSConsoleHostReadLine override that rewrites coreutils command names to their
# .cmd equivalents after PSReadLine returns (history keeps the original).
#
# Why .cmd over .exe: PSNativeCommandArgumentPassing = 'Windows' results in a behavior
# where passing bare quotes to CreateProcess() is impossible. This prevents us from
# passing "*" as "*" to coreutils and instead will be given as a bare *.
# This causes it to treat it as a glob pattern. "*.cmd" files however are automatically
# treated as PSNativeCommandArgumentPassing = 'Legacy', which preserves quotes.
# It is the only possible workaround and the only way coreutils can work at all.
function PSConsoleHostReadLine {
    [System.Diagnostics.DebuggerHidden()]
    param()

    $lastRunStatus = $?
    Microsoft.PowerShell.Core\Set-StrictMode -Off
    $line = [Microsoft.PowerShell.PSConsoleReadLine]::ReadLine($host.Runspace, $ExecutionContext, $lastRunStatus)

    # If the line contains no coreutils name, we don't need to parse the AST at all.
    if (-not $script:__COREUTILS_FAST_SKIP__.IsMatch($line)) {
        return $line
    }

    $ast = [System.Management.Automation.Language.Parser]::ParseInput($line, [ref]$null, [ref]$null)
    $commands = $ast.FindAll($script:__COREUTILS_CMD_PREDICATE__, $true)

    # Process right-to-left so earlier offsets stay valid after each splice.
    # In-place reverse beats Sort-Object for the typical 1-command line.
    if ($commands.Count -gt 1) {
        $commands = [System.Collections.Generic.List[object]]::new($commands)
        $commands.Reverse()
    }

    foreach ($cmd in $commands) {
        $name = $cmd.GetCommandName()
        if (!$name) {
            continue
        }

        $baseName = $name
        if ($name.EndsWith('.exe') -or $name.EndsWith('.cmd')) {
            $baseName = $name.Substring(0, $name.Length - 4)
        }
        if (!$script:__COREUTILS__.Contains($baseName)) {
            continue
        }

        # ls/la get colour + listing flags injected; la also rewrites to ls.
        $cmdElement = $cmd.CommandElements[0]
        $start = $cmdElement.Extent.StartOffset
        $end = $cmdElement.Extent.EndOffset
        $replacement = "& 'C:\Program Files\coreutils\cmd\"

        switch ($baseName) {
            'la' { $replacement += "ls.cmd' --color=auto -AFhl" }
            'ls' { $replacement += "ls.cmd' --color=auto" }
            default { $replacement += "$baseName.cmd'" }
        }

        # Walk command elements, merging adjacent ones whose extents touch
        # (e.g. `'a'*` parses as [SingleQuoted, BareWord] but is one shell word).
        # The inverse case `*'a'*` parses as a single BareWord whose text
        # contains the embedded quotes, which is why AST-only analysis
        # isn't enough and we still need to re-tokenize the source span.
        $argsStart = $end
        $argsEnd = $cmd.Extent.EndOffset
        $rewrittenArgs = ''
        $elements = $cmd.CommandElements
        $count = $elements.Count
        $i = 1
        while ($i -lt $count) {
            $first = $elements[$i]
            $wordStart = $first.Extent.StartOffset
            $wordEnd = $first.Extent.EndOffset
            $merged = $false
            while ($i + 1 -lt $count -and $elements[$i + 1].Extent.StartOffset -eq $wordEnd) {
                $i++
                $wordEnd = $elements[$i].Extent.EndOffset
                $merged = $true
            }
            $source = $line.Substring($wordStart, $wordEnd - $wordStart)
            $rewrittenArgs += $line.Substring($argsStart, $wordStart - $argsStart)
            $argsStart = $wordEnd
            # IndexOfAny beats running the regex per arg.
            if ($source.IndexOfAny($script:__COREUTILS_ARG_SPECIAL__) -lt 0) {
                $rewrittenArgs += $source
                $i++
                continue
            }
            # A single un-merged PS expression that needs $var resolution
            # (bare $var, "...$var...", $x.Member, $($expr), etc.).
            # Defer evaluation to runtime so the value reaches coreutils as a literal arg.
            # This matches POSIX behaviour where variable expansions don't result in globbing.
            if (-not $merged -and
                ($first -is [System.Management.Automation.Language.VariableExpressionAst] -or
                $first -is [System.Management.Automation.Language.ExpandableStringExpressionAst] -or
                $first -is [System.Management.Automation.Language.MemberExpressionAst])) {
                $rewrittenArgs += '(__coreutils_q ' + $source + ')'
                $i++
                continue
            }
            # Slow path: re-tokenise and re-emit as MSVCRT-style quoting,
            # then wrap in PS single quotes so PS hands the body verbatim.
            $windowsQuoted = $script:__COREUTILS_ARG_RX__.Replace($source, $script:__COREUTILS_ARG_EVAL__)
            $rewrittenArgs += "'" + $windowsQuoted.Replace("'", "''") + "'"
            $i++
        }
        $rewrittenArgs += $line.Substring($argsStart, $argsEnd - $argsStart)

        $line = $line.Substring(0, $start) + $replacement + $rewrittenArgs + $line.Substring($argsEnd)
    }

    return $line
}
# ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# DO NOT MODIFY -- coreutils -- 60b36fc6-2d59-49df-be51-28dd2f4c3c9a

# VS Code Shell integration, have to be last per https://github.com/microsoft/vscode/issues/321273
if ($env:TERM_PROGRAM -eq "vscode") {
  . "$(code --locate-shell-integration-path pwsh)"
}
