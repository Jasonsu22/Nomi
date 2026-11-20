<#
Nomi for Windows, Phase 0: can this PC run Nomi's models live, and which set suits it?

Double-click run-phase0.cmd, or in PowerShell:
    .\run-phase0.ps1            # everything, about 30-60 minutes
    .\run-phase0.ps1 -Quick     # one clip, small models only, about 10 minutes

Put one or more lecture recordings (WAV, any rate) in the clips folder first. Without them a
short public sample is used, which says much less.

Results go to results\<PC name>-<date>\ and are zipped; send the zip back.
Nothing is installed and nothing leaves the PC except the model downloads.
#>
param(
    [switch]$Quick,
    [switch]$SkipDownload,
    [switch]$CpuOnly
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $here
$asrExe = Join-Path $here 'asr\asr-bench.exe'
$llmExe = Join-Path $here 'llm\llm-bench.exe'
$config = Get-Content (Join-Path $here 'models.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$out = Join-Path $here ("results\{0}-{1}" -f $env:COMPUTERNAME, $stamp)
New-Item -ItemType Directory -Force -Path $out, (Join-Path $here 'models'), (Join-Path $here 'clips') | Out-Null
$log = Join-Path $out 'run.log'

function Say($text) {
    Write-Host $text
    Add-Content -Path $log -Value $text -Encoding UTF8
}

function Run-Tool($exe, [string[]]$arguments, $name) {
    $errFile = Join-Path $out "$name.stderr.txt"
    $process = Start-Process -FilePath $exe -ArgumentList $arguments -NoNewWindow -PassThru -Wait -RedirectStandardError $errFile -RedirectStandardOutput (Join-Path $out "$name.stdout.txt")
    if ($process.ExitCode -ne 0) {
        Say "  ! $name failed (exit $($process.ExitCode)); see $name.stderr.txt"
        return $false
    }
    return $true
}

function Read-Result($name) {
    $path = Join-Path $out "$name.json"
    if (Test-Path $path) { return Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json }
    return $null
}

# ---------- 1. This PC ----------
Say "Nomi Phase 0 on $env:COMPUTERNAME, $(Get-Date)"
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$computer = Get-CimInstance Win32_ComputerSystem
$os = Get-CimInstance Win32_OperatingSystem
$gpus = @(Get-CimInstance Win32_VideoController | ForEach-Object {
    [pscustomobject]@{ name = $_.Name; driver = $_.DriverVersion; driver_date = "$($_.DriverDate)"; memory_mb = [math]::Round($_.AdapterRAM / 1MB) }
})
$battery = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
$onBattery = $false
if ($battery) { $onBattery = ($battery.BatteryStatus -eq 1) }
$system = [pscustomobject]@{
    computer = $env:COMPUTERNAME
    manufacturer = $computer.Manufacturer
    model = $computer.Model
    os = "$($os.Caption) $($os.Version)"
    cpu = $cpu.Name.Trim()
    cores = $cpu.NumberOfCores
    threads = $cpu.NumberOfLogicalProcessors
    memory_gb = [math]::Round($computer.TotalPhysicalMemory / 1GB, 1)
    free_memory_gb = [math]::Round($os.FreePhysicalMemory * 1KB / 1GB, 1)
    gpus = $gpus
    on_battery = $onBattery
    asr_devices = $null
    llm_devices = $null
}
& $asrExe devices 1> (Join-Path $out 'asr-devices.json') 2> (Join-Path $out 'asr-devices.stderr.txt')
& $llmExe devices 1> (Join-Path $out 'llm-devices.json') 2> (Join-Path $out 'llm-devices.stderr.txt')
$asrDevices = @(Get-Content (Join-Path $out 'asr-devices.json') -Raw | ConvertFrom-Json)
$llmDevices = @(Get-Content (Join-Path $out 'llm-devices.json') -Raw | ConvertFrom-Json)
$system.asr_devices = $asrDevices
$system.llm_devices = $llmDevices
$system | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $out 'system.json') -Encoding UTF8
Say "CPU: $($system.cpu), $($system.cores) cores / $($system.threads) threads, $($system.memory_gb) GB memory"
foreach ($gpu in $gpus) { Say "Graphics: $($gpu.name), driver $($gpu.driver)" }
if ($onBattery) { Say "On battery: plug in for comparable numbers, or keep it to measure battery behaviour." }

$hasGpu = (-not $CpuOnly) -and (@($asrDevices | Where-Object { $_.device_type -eq 'gpu' -or $_.device_type -eq 'igpu' }).Count -gt 0) `
    -and (@($llmDevices | Where-Object { $_.backend -ne 'CPU' }).Count -gt 0)
$placements = @('cpu')
if ($hasGpu) { $placements += 'gpu' ; Say "A GPU is usable through Vulkan; it will be measured too." } else { Say "No usable GPU: CPU only." }

# ---------- 2. Models ----------
$asrModels = @($config.asr)
$llmModels = @($config.llm)
if ($Quick) {
    $asrModels = @($config.asr | Where-Object { $_.id -eq 'qwen3-asr-0.6b' })
    $llmModels = @($config.llm | Where-Object { $_.id -eq 'qwen3.5-0.8b' })
}
function Get-Model($entry) {
    $target = Join-Path $here "models\$($entry.file)"
    if (Test-Path $target) { return $target }
    if ($SkipDownload) { throw "missing models\$($entry.file)" }
    foreach ($source in $config.sources) {
        $url = "$source/$($entry.path)"
        Say "Downloading $($entry.file) from $source ..."
        & curl.exe -fL --retry 3 -C - -o "$target.part" $url
        if ($LASTEXITCODE -eq 0) {
            Move-Item -Force "$target.part" $target
            return $target
        }
        Say "  that source did not answer; trying the next one"
    }
    throw "could not download $($entry.file)"
}
$paths = @{}
foreach ($entry in ($asrModels + $llmModels)) { $paths[$entry.id] = Get-Model $entry }

# ---------- 3. Clips ----------
$clips = @(Get-ChildItem (Join-Path $here 'clips') -Filter *.wav | Sort-Object Name)
if ($clips.Count -eq 0) {
    Say "No recordings in clips\; using a 35-second public sample. Real lectures give much better numbers."
    $sample = Join-Path $here 'clips\sample-dots.wav'
    foreach ($source in @('https://raw.githubusercontent.com/handy-computer/transcribe.cpp/main/samples/dots.wav')) {
        & curl.exe -fsL -o $sample $source
    }
    $clips = @(Get-Item $sample)
}
if ($Quick) { $clips = @($clips | Select-Object -First 1) }
$clipArgs = @()
foreach ($clip in $clips) { $clipArgs += @('--audio', "`"$($clip.FullName)`"") }
$togetherClip = $clips | Select-Object -First 1
$togetherSeconds = 0
Say "Clips: $(($clips | ForEach-Object { $_.Name }) -join ', ')"

# ---------- 4. Each model alone ----------
$sentencesEn = Join-Path $here 'sentences-en.txt'
$sentencesZh = Join-Path $here 'sentences-zh.txt'
foreach ($model in $asrModels) {
    foreach ($place in $placements) {
        $name = "asr-$($model.id)-$place"
        Say "Speech alone: $($model.id) on $place"
        $null = Run-Tool $asrExe (@('run', '--model', "`"$($paths[$model.id])`"", '--device', $place, '--json', "`"$(Join-Path $out "$name.json")`"") + $clipArgs) $name
    }
}
foreach ($model in $llmModels) {
    foreach ($place in $placements) {
        foreach ($direction in @(@{ file = $sentencesEn; target = 'zh'; tag = 'en-zh' }, @{ file = $sentencesZh; target = 'en'; tag = 'zh-en' })) {
            $name = "llm-$($model.id)-$place-$($direction.tag)"
            Say "Translation alone: $($model.id) on $place, $($direction.tag)"
            $null = Run-Tool $llmExe @('run', '--model', "`"$($paths[$model.id])`"", '--device', $place, '--target', $direction.target, '--sentences', "`"$($direction.file)`"", '--json', "`"$(Join-Path $out "$name.json")`"") $name
        }
    }
}

# ---------- 5. Both together, as during a lecture ----------
$sets = @($config.sets | Where-Object { $paths.ContainsKey($_.asr) -and $paths.ContainsKey($_.llm) })
$pairs = @()
foreach ($asrPlace in $placements) { foreach ($llmPlace in $placements) { $pairs += ,@($asrPlace, $llmPlace) } }
foreach ($set in $sets) {
    foreach ($pair in $pairs) {
        $asrPlace = $pair[0]; $llmPlace = $pair[1]
        $tag = "together-$($set.name)-asr_$asrPlace-llm_$llmPlace"
        Say "Together: $($set.name) set, speech on $asrPlace, translation on $llmPlace"
        # A sentence to translate every 4 seconds, for as long as the speech run takes.
        $llmJson = Join-Path $out "$tag-llm.json"
        $llmProcess = Start-Process -FilePath $llmExe -NoNewWindow -PassThru `
            -ArgumentList @('run', '--model', "`"$($paths[$set.llm])`"", '--device', $llmPlace, '--target', 'zh', '--sentences', "`"$sentencesEn`"", '--pace', '4', '--for', '100000', '--json', "`"$llmJson`"") `
            -RedirectStandardError (Join-Path $out "$tag-llm.stderr.txt") -RedirectStandardOutput (Join-Path $out "$tag-llm.stdout.txt")
        Start-Sleep -Seconds 8
        $null = Run-Tool $asrExe @('run', '--model', "`"$($paths[$set.asr])`"", '--device', $asrPlace, '--audio', "`"$($togetherClip.FullName)`"", '--json', "`"$(Join-Path $out "$tag-asr.json")`"") "$tag-asr"
        # Stop the translation loop. It only writes its report on a normal exit, so it runs with a
        # long --for and its own per-sentence lines are read from stderr instead.
        if (-not $llmProcess.HasExited) { Stop-Process -Id $llmProcess.Id -Force }
    }
}

# ---------- 6. Summary ----------
function Ms-From-Stderr($path) {
    if (-not (Test-Path $path)) { return @() }
    $values = @()
    foreach ($line in Get-Content $path -Encoding UTF8) {
        if ($line -match '^\s+(\d+)\s+ms\s+') { $values += [double]$Matches[1] }
    }
    return $values
}
function P90($values) {
    if ($values.Count -eq 0) { return $null }
    $sorted = $values | Sort-Object
    return $sorted[[math]::Round(($sorted.Count - 1) * 0.9)]
}

$lines = @()
$lines += "# Nomi Phase 0: $($system.computer)"
$lines += ""
$lines += "- $($system.manufacturer) $($system.model), $($system.os)"
$lines += "- $($system.cpu), $($system.cores) cores / $($system.threads) threads, $($system.memory_gb) GB"
foreach ($gpu in $gpus) { $lines += "- $($gpu.name), driver $($gpu.driver)" }
$lines += "- On battery: $onBattery"
$lines += ""
$lines += "## Speech alone"
$lines += "| Model | Device | Load | Load, interim off | Phrase p90 ms |"
$lines += "|---|---|---:|---:|---:|"
foreach ($model in $asrModels) { foreach ($place in $placements) {
    $r = Read-Result "asr-$($model.id)-$place"
    if ($r) { $p90 = ($r.clips | Measure-Object final_latency_ms_p90 -Maximum).Maximum; $lines += "| $($model.id) | $place ($($r.device)) | $([math]::Round($r.load, 2)) | $([math]::Round($r.load_without_interim, 2)) | $([math]::Round($p90)) |" }
    else { $lines += "| $($model.id) | $place | failed | | |" }
} }
$lines += ""
$lines += "## Translation alone"
$lines += "| Model | Device | Direction | Mean ms | p90 ms | Tokens/s |"
$lines += "|---|---|---|---:|---:|---:|"
foreach ($model in $llmModels) { foreach ($place in $placements) { foreach ($tag in @('en-zh', 'zh-en')) {
    $r = Read-Result "llm-$($model.id)-$place-$tag"
    if ($r) { $lines += "| $($model.id) | $place | $tag | $([math]::Round($r.total_ms_mean)) | $([math]::Round($r.total_ms_p90)) | $([math]::Round($r.tokens_per_second_mean, 1)) |" }
    else { $lines += "| $($model.id) | $place | $tag | failed | | |" }
} } }
$lines += ""
$lines += "## Together (speech + a translation every 4 s)"
$lines += "| Set | Speech on | Translation on | Speech load | Load, interim off | Translation p90 ms | Result |"
$lines += "|---|---|---|---:|---:|---:|---|"
$pass = $config.pass
foreach ($set in $sets) { foreach ($pair in $pairs) {
    $tag = "together-$($set.name)-asr_$($pair[0])-llm_$($pair[1])"
    $asr = Read-Result "$tag-asr"
    $p90 = P90 (Ms-From-Stderr (Join-Path $out "$tag-llm.stderr.txt"))
    if (-not $asr -or $null -eq $p90) { $lines += "| $($set.name) | $($pair[0]) | $($pair[1]) | failed | | | |"; continue }
    $result = 'Too slow'
    if ($asr.load -le $pass.live_with_interim.asr_load_max -and $p90 -le $pass.live_with_interim.translation_p90_ms_max) { $result = 'Live, with interim text' }
    elseif ($asr.load_without_interim -le $pass.live_without_interim.asr_load_without_interim_max -and $p90 -le $pass.live_without_interim.translation_p90_ms_max) { $result = 'Live, interim text off' }
    $lines += "| $($set.name) | $($pair[0]) | $($pair[1]) | $([math]::Round($asr.load, 2)) | $([math]::Round($asr.load_without_interim, 2)) | $([math]::Round($p90)) | $result |"
} }
$lines += ""
$lines += "Load = model time / audio time; under 1 keeps up, and the pass marks leave room for the rest of the PC."
$summary = Join-Path $out 'summary.md'
$lines | Set-Content $summary -Encoding UTF8
Say ""
Get-Content $summary -Encoding UTF8 | ForEach-Object { Write-Host $_ }

$zip = "$out.zip"
Compress-Archive -Path "$out\*" -DestinationPath $zip -Force
Say ""
Say "Done. Send this file back: $zip"
