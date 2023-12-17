<#
  .SYNOPSIS
    new_vm.ps1
  .DESCRIPTION
    New-VM with json config
  .INPUTS
    - cfg: json config.
  .OUTPUTS
    - 0: SUCCESS / 1: ERROR
  .Last Change : 2023/12/17 12:15:10.
#>
param([string]$cfg)

$ErrorActionPreference = "Stop"
$DebugPreference = "SilentlyContinue" # Continue SilentlyContinue Stop Inquire
# Enable-RunspaceDebug -BreakAll

<#
  .SYNOPSIS
    log
  .DESCRIPTION
    log message
  .INPUTS
    - msg
    - color
  .OUTPUTS
    - None
#>
function log {

  [CmdletBinding()]
  [OutputType([void])]
  param([string]$msg, [string]$color)
  trap {
    Write-Host "[log] Error $_" "Red"; throw $_
  }

  $now = Get-Date -f "yyyy/MM/dd HH:mm:ss.fff"
  if ($color) {
    Write-Host -ForegroundColor $color "${now} ${msg}"
  } else {
    Write-Host "${now} ${msg}"
  }
}

<#
  .SYNOPSIS
    Init
  .DESCRIPTION
    Init
  .INPUTS
    - None
  .OUTPUTS
    - None
#>
function Start-Init {

  [CmdletBinding()]
  [OutputType([void])]
  param()
  trap {
    log "[Start-Init] Error $_" "Red"; throw $_
  }

  log "[Start-Init] Start"

  $script:app = @{}

  $cmdFullPath = & {
    if ($env:__SCRIPTPATH) {
      return [System.IO.Path]::GetFullPath($env:__SCRIPTPATH)
    } else {
      return [System.IO.Path]::GetFullPath($script:MyInvocation.MyCommand.Path)
    }
  }
  $app.Add("cmdFile", $cmdFullPath)
  $app.Add("cmdDir", [System.IO.Path]::GetDirectoryName($app.cmdFile))
  $app.Add("cmdName", [System.IO.Path]::GetFileNameWithoutExtension($app.cmdFile))
  $app.Add("cmdFileName", [System.IO.Path]::GetFileName($app.cmdFile))

  $app.Add("pwd", [System.IO.Path]::GetFullPath((Get-Location).Path))

  # log
  $app.Add("now", (Get-Date -Format "yyyyMMddTHHmmssfffffff"))
  $app.Add("logDir", [System.IO.Path]::Combine($app.cmdDir, "logs"))
  $app.Add("logFile", [System.IO.Path]::Combine($app.logDir, "$($app.cmdName)_$($app.now).log"))
  $app.Add("logName", [System.IO.Path]::GetFileNameWithoutExtension($app.logFile))
  $app.Add("logFileName", [System.IO.Path]::GetFileName($app.logFile))
  New-Item -Force -ItemType Directory (Split-Path -Parent $app.logDir) > $null
  Start-Transcript $app.logFile

  # const value.
  $app.Add("cnst", @{
      SUCCESS = 0
      ERROR   = 1
    })

  # config.
  if ([string]::IsNullOrEmpty($cfg)) {
    $app.Add("cfgPath", [System.IO.Path]::Combine($app.cmdDir, "$($app.cmdName).json"))
  } else {
    $app.Add("cfgPath", $cfg)
  }
  if (!(Test-Path $app.cfgPath)) {
    log "$($app.cfgPath) is not found ! finish ..."
    $app.result = $app.cnst.ERROR
    exit $app.result
  }
  $json = Get-Content -Encoding utf8 $app.cfgPath | ConvertFrom-Json
  $app.Add("cfg", $json)

  # Init result
  $app.Add("result", $app.cnst.ERROR)

  log "[Start-Init] End"
}

<#
  .SYNOPSIS
    Main
  .DESCRIPTION
    Execute main
  .INPUTS
    - None
  .OUTPUTS
    - Result - 0 (SUCCESS), 1 (ERROR)
#>
function Start-Main {
  [CmdletBinding()]
  [OutputType([int])]
  param()

  try {
    Start-Init
    log "[Start-Main] Start"

    $vm = $app.cfg.vm | ConvertTo-Json | ConvertFrom-Json -AsHashtable
    $isExist = Get-VM -Name $vm.name -ErrorAction SilentlyContinue
    if ($isExist) {
      log "VM: [$($vm.name)] already exists ! finish ..."
      $app.result = $app.cnst.ERROR
      exit $app.result
    }
    if ($app.cfg.vm.newVHDPath) {
      New-Item -Force -ItemType Directory (Split-Path -Parent $app.cfg.vm.newVHDPath) > $null
      if (Test-Path $app.cfg.vm.newVHDPath) {
        Remove-Item -Force $app.cfg.vm.newVHDPath
      }
    }
    New-VM @vm
    Set-VMProcessor -VMName $app.cfg.vm.name -Count $app.cfg.cpu.count
    if ($app.cfg.cpu.exposeVirtualizationExtensions) {
      Set-VMProcessor -VMName $app.cfg.vm.name -ExposeVirtualizationExtensions $true
    }
    Set-VMMemory -VMName $app.cfg.vm.name -DynamicMemoryEnabled $true

    if ($app.cfg.network) {
      if ($app.cfg.network.macAddressSpoofing) {
        Get-VMNetworkAdapter -VMName $app.cfg.vm.name | Set-VMNetworkAdapter -MacAddressSpoofing On
      }
      if ($app.cfg.network.nic) {
        Get-VMNetworkAdapter -VMName $app.cfg.vm.name | Remove-VMNetworkAdapter
        $app.cfg.network.nic | ForEach-Object {
          $nic = $_
          Add-VMNetworkAdapter -VMName $app.cfg.vm.name -Name $nic.name -SwitchName $nic.vSwitch
        }
      }

    }

    if ($app.cfg.iso) {
      Add-VMDvdDrive -VMName $app.cfg.vm.name -Path $app.cfg.iso.path
      $drive = Get-VMDvdDrive -VMName $app.cfg.vm.name
      Set-VMFirmware -VMName $app.cfg.vm.name -FirstBootDevice $drive
    }

    $app.result = $app.cnst.SUCCESS
  } catch {
    log "Error ! $_" "Red"
    $app.result = $app.cnst.ERROR
  } finally {
    log "[Start-Main] End"
    Stop-Transcript
  }
}

# Call main.
Start-Main
exit $app.result


























































