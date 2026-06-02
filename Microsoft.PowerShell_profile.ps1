# rust, fnm and uv
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

# VS Code Shell integration
if ($env:TERM_PROGRAM -eq "vscode") {
  . "$(code --locate-shell-integration-path pwsh)"
} else {
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

# Replacement for GitHub Copilot in the CLI
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

  return ($FallbackArgs -join ' ')
}

function Escape-ForSingleQuotedPrompt {
  param([Parameter(Mandatory)][string]$Text)
  # We embed the input inside single quotes in the Copilot prompt
  return ($Text -replace "'", "''")
}

function Normalize-CopilotRawCommand {
  [CmdletBinding()]
  param([Parameter(Mandatory)][string]$Text)

  # Remove BOM + trim outer whitespace
  $s = $Text.Trim([char]0xFEFF).Trim()

  if (-not $s) {
    return $s
  }

  $lines = $s -split "\r?\n"

  # Drop markdown code fences lines (``` or ```bash etc.)
  $lines = $lines | Where-Object { $_ -notmatch '^\s*```' }

  # Strip common leading bullets/markers per-line
  $lines = $lines | ForEach-Object {
    ($_ -replace '^\s*(?:[●•○]|-\s+|\*\s+|>\s+)\s*', '')
  }

  # Trim empty leading/trailing lines
  while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[0])) {
    $lines = $lines[1..($lines.Count-1)]
  }

  while ($lines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($lines[-1])) {
    $lines = $lines[0..($lines.Count-2)]
  }

  # If it came back as a single backticked inline snippet, unwrap it
  $out = ($lines -join "`n").Trim()

  if ($out -match '^\s*`(.+)`\s*$') {
    $out = $Matches[1].Trim()
  }

  return $out.TrimEnd("`r","`n")
}

function Write-GhCyanDotsWhileWaiting {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [System.Diagnostics.Process] $Process,

    [Parameter(Mandatory)]
    [string] $Message,

    [int] $IntervalMs = 220
  )

  $icons = @('🔄', '🔃')
  $iconIdx = 0
  $dots = 0
  $lastLen = 0

  while (-not $Process.HasExited) {
    $dots = ($dots % 3) + 1

    if ($dots -eq 1) {
      $iconIdx = ($iconIdx + 1) % $icons.Count
    }

    $text = '{0} {1}{2}' -f $icons[$iconIdx], $Message, ('.' * $dots)
    $pad = 0

    if ($lastLen -gt $text.Length) {
      $pad = $lastLen - $text.Length
    }

    $lastLen = $text.Length

    Write-Host -NoNewline ("`r" + $text + (' ' * $pad)) -ForegroundColor Cyan
    Start-Sleep -Milliseconds $IntervalMs
  }

  # Clear spinner line
  Write-Host -NoNewline ("`r" + (' ' * $lastLen) + "`r")
}

function Invoke-CopilotWithSpinner {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)]
    [string] $Prompt,

    [string] $Model = 'gpt-5.4-mini',

    [Parameter(Mandatory)]
    [string] $SpinnerMessage,

    [switch] $Stream,

    [int] $SpinnerIntervalMs = 220
  )

  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = 'copilot'

  $null = $psi.ArgumentList.Add('--stream')
  $null = $psi.ArgumentList.Add($(if ($Stream) {
    'on'
  } else {
    'off'
  }))

  $null = $psi.ArgumentList.Add('--silent')
  $null = $psi.ArgumentList.Add('--model'); $null = $psi.ArgumentList.Add($Model)
  $null = $psi.ArgumentList.Add('-p'); $null = $psi.ArgumentList.Add($Prompt)

  # Required for redirection
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true

  $p = [System.Diagnostics.Process]::new()
  $p.StartInfo = $psi

  if ($Stream) {
    # Stream mode: redirect + mirror chunks ourselves (so we can animate safely)
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    if (-not $p.Start()) {
      throw "❌ Failed to start copilot"
    }

    # Spinner state
    $icons = @('🔄', '🔃')
    $iconIdx = 0
    $dots = 0
    $lastLen = 0
    $spinnerActive = $true

    # Buffers + async reads (no PowerShell scriptblocks on background threads)
    $outBuf = New-Object char[] 2048
    $errBuf = New-Object char[] 2048

    $outDone = $false
    $errDone = $false

    $outTask = $p.StandardOutput.ReadAsync($outBuf, 0, $outBuf.Length)
    $errTask = $p.StandardError.ReadAsync($errBuf, 0, $errBuf.Length)

    while (-not ($outDone -and $errDone)) {
      $tasks = @()

      if (-not $outDone) {
        $tasks += $outTask
      }
      if (-not $errDone) {
        $tasks += $errTask
      }

      # Wait a bit for any output, if none, we use the timeout tick to animate
      $idx = [System.Threading.Tasks.Task]::WaitAny($tasks, $SpinnerIntervalMs)

      # Timeout tick -> animate spinner (only until first output)
      if ($idx -eq -1) {
        if ($spinnerActive) {
          $dots = ($dots % 3) + 1

          if ($dots -eq 1) {
            $iconIdx = ($iconIdx + 1) % $icons.Count
          }

          $text = '{0} {1}{2}' -f $icons[$iconIdx], $SpinnerMessage, ('.' * $dots)
          $pad = 0

          if ($lastLen -gt $text.Length) {
            $pad = $lastLen - $text.Length
          }

          $lastLen = $text.Length
          Write-Host -NoNewline ("`r" + $text + (' ' * $pad)) -ForegroundColor Cyan
        }

        continue
      }

      # Drain stdout if ready
      if (-not $outDone -and $outTask.IsCompleted) {
        $n = $outTask.Result

        if ($n -gt 0) {
          if ($spinnerActive) {
            # Clear spinner line once we get first real output
            Write-Host -NoNewline ("`r" + (' ' * $lastLen) + "`r")
            $spinnerActive = $false
          }

          [Console]::Out.Write($outBuf, 0, $n)
          $outTask = $p.StandardOutput.ReadAsync($outBuf, 0, $outBuf.Length)
        } else {
          $outDone = $true
        }
      }

      # Drain stderr if ready
      if (-not $errDone -and $errTask.IsCompleted) {
        $n = $errTask.Result

        if ($n -gt 0) {
          if ($spinnerActive) {
            Write-Host -NoNewline ("`r" + (' ' * $lastLen) + "`r")
            $spinnerActive = $false
          }

          [Console]::Error.Write($errBuf, 0, $n)
          $errTask = $p.StandardError.ReadAsync($errBuf, 0, $errBuf.Length)
        } else {
          $errDone = $true
        }
      }
    }

    $p.WaitForExit()

    return [pscustomobject]@{
      ExitCode = $p.ExitCode
      StdOut = $null
      StdErr = $null
    }
  }

  # Non-stream mode: capture output safely (async reads avoid stdout/stderr deadlocks)
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError  = $true

  if (-not $p.Start()) {
    throw "❌ Failed to start copilot"
  }

  $outTask = $p.StandardOutput.ReadToEndAsync()
  $errTask = $p.StandardError.ReadToEndAsync()

  Write-GhCyanDotsWhileWaiting -Process $p -Message $SpinnerMessage -IntervalMs $SpinnerIntervalMs

  $p.WaitForExit()
  [System.Threading.Tasks.Task]::WaitAll(@($outTask, $errTask))

  return [pscustomobject]@{
    ExitCode = $p.ExitCode
    StdOut = $outTask.Result
    StdErr = $errTask.Result
  }
}

function ghcs {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Prompt
  )

  $text = Get-InvocationRemainder -Line $MyInvocation.Line -InvocationName $MyInvocation.InvocationName @Prompt

  if (-not $text) {
    return
  }

  $escaped = Escape-ForSingleQuotedPrompt $text
  $copilotPrompt = @"
You are generating ONE terminal command for the user to paste and run.

USER REQUEST:
'$escaped'

HARD RULES (must follow):
- Output EXACTLY ONE runnable command line. No extra text
- No markdown, no code fences, no bullets, no leading markers (like ●), no comments
- No surrounding quotes around the whole command. No trailing whitespace
- Must be non-interactive (no prompts) unless the user explicitly asked for interactive behavior
- Do not insert line breaks in places where this can break the execution. A one-liner will always be preferred, even if this means the line is very long !

SHELL / OS:
- Infer the target shell/OS from the user request (e.g. "pwsh 7", "bash", "windows 11", "linux")
- If unspecified, default to PowerShell 7 on Windows 11
- Use correct quoting/escaping for that shell (especially spaces and nested quotes). In PowerShell, remember the escape char is backtick and single-quotes inside single-quoted strings are doubled

SAFETY / DEFAULTS (because the output may be executed):
- Avoid destructive/irreversible actions unless explicitly requested
- Avoid overwriting files by default; prefer writing to a new output file unless the user asked to overwrite
- Prefer “safe” flags when available (e.g., no-clobber equivalents, dry-run/preview modes)
- Prefer built-in/common tools; don’t require installing dependencies unless the user asked

QUALITY:
- Quote any path/arg that may contain spaces or special chars
- If multiple steps are required, express them as a single command line (pipeline / && / ; as appropriate for the shell)

Now output ONLY the raw command:
"@

  try {
    $res = Invoke-CopilotWithSpinner -Prompt $copilotPrompt -Model 'gpt-5.4-mini' -SpinnerMessage "Copilot is generating your command"

    if ($res.ExitCode -ne 0) {
      $msg = ($res.StdErr + $res.StdOut).Trim()

      if (-not $msg) {
        $msg = "copilot exited with code $($res.ExitCode)"
      }

      throw $msg
    }

    $raw = Normalize-CopilotRawCommand -Text ($res.StdOut ?? "")
    $raw
    Set-Clipboard -Value $raw

    Write-Host ""
    Write-Host "✅ Command copied to the clipboard" -ForegroundColor Green
  } catch {
    Write-Host "❌ ghcs failed: $($_.Exception.Message)" -ForegroundColor Red
  }
}

function ghce {
  [CmdletBinding()]
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Prompt
  )

  $text = Get-InvocationRemainder -Line $MyInvocation.Line -InvocationName $MyInvocation.InvocationName @Prompt

  if (-not $text) {
    return
  }

  $escaped = Escape-ForSingleQuotedPrompt $text
  $copilotPrompt = @"
Explain the following command: '$escaped'

OUTPUT FORMAT RULES (IMPORTANT):
- plain text is preferred, markdown can be used if necessary
- use multiple lines with clear headings
- use bullet points
- Do not ask questions. Make reasonable assumptions and pick the most likely interpretation.

STRUCTURE:
1) Summary (1-2 sentences)
2) Breakdown (bullet list): explain each token/flag/operator in order once, the first time it appears
   - identify the executable, each switch, each argument
   - explain quoting where relevant
   - explain operators like |, >, 2>&1, etc.
3) Pipeline stages (if any): one section per stage, what it consumes/produces
4) Notes / caveats: if necessary, 3-6 bullets (gotchas, side effects, safety tips)

Be thorough and concrete: explain what happens step-by-step. Follow the structure unless the command is very simple, in such case a simple detailed explanation is enough.
"@

  try {
    $res = Invoke-CopilotWithSpinner -Prompt $copilotPrompt -Model 'gpt-5.4-mini' -SpinnerMessage "Copilot is explaining your command" -Stream

    if ($res.ExitCode -ne 0) {
      throw "copilot exited with code $($res.ExitCode)"
    }
  } catch {
    Write-Host "❌ ghce failed: $($_.Exception.Message)" -ForegroundColor Red
  }
}

# fnm
fnm env --use-on-cd --version-file-strategy=recursive --shell powershell | Out-String | Invoke-Expression
fnm completions --shell powershell | Out-String | Invoke-Expression

# zoxide
zoxide init powershell --cmd cd | Out-String | Invoke-Expression

# PNPM
pnpm completion pwsh | Out-String | Invoke-Expression

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

# deno, add `--dynamic` once ready
deno completions powershell | Out-String | Invoke-Expression

# jj
$env:COMPLETE = "powershell"
jj | Out-String | Invoke-Expression
Remove-Item Env:\COMPLETE

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
