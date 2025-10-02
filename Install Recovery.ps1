#Requires -Version 4
#Requires -RunAsAdministrator

$sdi_name  = "\Boot\boot.sdi"
$wim_name  = "\Sources\WinRe.wim"
$boot_name = "Recovery Enviroment"

Set-Location $PSScriptRoot

if (-not(
  Get-Module -ListAvailable | ? Name -match Microsoft.Windows.BcdLIB.Cmdlets)) {
  try {
    Import-Module ".\BcdLIB\Microsoft.Windows.BcdLIB.Cmdlets.psm1" -EA 1 | Out-Null	
  }
  catch {
    throw "Error ### Missing BCD Lib Files"
  }
  finally {
    cls
  }
}

Function Install-WinRE {

  "Check :: Drive ID"
  $id  = @(Get-Partition -DriveLetter C).DiskNumber
  if ($id -eq $null) {
    throw "Error ### Could not identify disk"
  }

  "Check :: VHD SYSTEM"
  $VHD = Is-VHD-System
  if ($VHD -eq 1) {
    throw "Error ### Live VHDX drive"
  }

  "Check :: Recovery partition"
  $rec  = Get-Disk $id | Get-Partition | ? Type -EQ 'Recovery'
  if ($rec -ne $null) {
    throw "Error ### Recovery Partition Already Installed"
  }

  "Check :: Ram Drive"
  $info = get_boot_info | ? { ($_).Is_ramdisk()} | ? description -eq $boot_name
  if (($info -ne $null) -and ($info.Count -ne 0)) {
    throw "Error ### Boot Item Already Installed"
  }

  Write-Host
  "Create New Partition"
  $rec = $null
  $rec = New-Partition -DiskNumber $id -Size (1*1024*1024*1024) -GptType "{de94bba4-06d1-4d40-a16a-bfd50179d6ac}" -AssignDriveLetter -ErrorAction SilentlyContinue
  if ($rec -eq $null) {
    throw "Error ### Could not create disk"
  }

  "Format Partition $($rec.DriveLetter):"
  Format-Volume -DriveLetter $rec.DriveLetter -FileSystem NTFS -Force -ErrorAction Stop | Out-Null
  
  "Copy Recovery Boot Files"
  New-Item -Name Boot    -Path "$($rec.DriveLetter):\" -ItemType directory | Out-Null
  New-Item -Name Sources -Path "$($rec.DriveLetter):\" -ItemType directory | Out-Null
  Copy-Item ".$($sdi_name)" "$($rec.DriveLetter):$($sdi_name)" -Force | Out-Null
  Copy-Item ".$($wim_name)" "$($rec.DriveLetter):$($wim_name)" -Force | Out-Null

  "Update Boot Store"
  Add_RAM_DRIVE_BOOT -Name $boot_name -Wim_File $wim_name -Sdi_File $sdi_name -Sdi_Partition_Letter $rec.DriveLetter -Add_First $true | Out-Null
  
  "Hide Partition  $($rec.DriveLetter):"
  Remove-PartitionAccessPath -DiskNumber $id -PartitionNumber $rec.PartitionNumber -Accesspath "$($rec.DriveLetter):" -ErrorAction SilentlyContinue | Out-Null
  
  # Ignore
  # $info = get_boot_info | ? { ($_).Is_ramdisk()} | ? description -eq $boot_name

  Write-Host "Done ....."
  Write-Host
  return
  
}

try {
  cls
  Write-Host
  Install-WinRE
}
catch {
  cls
  Write-Host
  $Error[0].TargetObject
  Write-Host
}

pause
exit
