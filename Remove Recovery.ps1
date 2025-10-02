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

Function Remove-WinRE {
  
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
  if ($rec -eq $null) {
    throw "Error ### Recovery Partition Not exist"
  }

  "Check :: Ram Drive"
  $info = get_boot_info | ? { ($_).Is_ramdisk()} | ? description -eq $boot_name
  if (($info -eq $null) -or ($info.Count -eq 0)) {
    throw "Error ### Boot Item Not exist"
  }

  Write-Host
  foreach ($par in $rec) {
    "Remove Partition :: $($par.PartitionNumber)"
	Remove-Partition -DiskNumber $id -PartitionNumber $par.PartitionNumber -confirm:$False  -ErrorAction SilentlyContinue | out-null
  }
  
  foreach ($bi in $info) {
    "Remove Boot Info :: $($bi.identifier):"
	$bi.Remove_ID() | out-null
  }

  Write-Host "Done ....."
  Write-Host
  return
}

try {
  cls
  Write-Host
  Remove-WinRE
}
catch {
  cls
  Write-Host
  $Error[0].TargetObject
  Write-Host
}

pause
exit
