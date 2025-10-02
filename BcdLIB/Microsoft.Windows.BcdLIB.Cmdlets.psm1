# Modify Windows BCD using Powershell - CodeProject
# https://www.codeproject.com/Articles/833655/Modify-Windows-BCD-using-Powershell

function Get-DosDevice {
Param(
  [Parameter(Mandatory=$true, Position=0)]
  $DriveLetter
  )
  
try {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class API {
  [DllImport("Kernel32.dll", EntryPoint = "QueryDosDeviceA", CharSet = CharSet.Ansi, SetLastError=true)]
  public static extern int QueryDosDevice (string lpDeviceName, System.Text.StringBuilder lpTargetPath, int ucchMax);
}
"@
}
catch {
}

	$sb = New-Object System.Text.StringBuilder(30)
    $ret = [API]::QueryDosDevice($DriveLetter, $sb, 30)

    if($ret -gt 0) {
        $sb.ToString()
    }
    return $null
}

Function Pharse_GUID {
   param (
     [parameter(Mandatory=$True)]
     [string] $Source
   )
   
   $Pattern = '^The entry(.*){(.*)}(.*)was successfully created.$'
   $Matches = [Regex]::Matches($Source ,$Pattern)
   if (!$Matches -or !($Matches.Success) -or !($Matches[0])) {
     return $null
   }
  
   try {
	  return $Matches[0].Groups[2].Value
   }
   catch {
     ## Nothing here
   }
  
  return $null
}

# Function to detect -
# if we have live OS running from VHD

function Is-VHD-System {
    param (
	 [ValidatePattern("^[a-zA-Z]$")]
     [parameter(Mandatory=$False)]
     [string] $Letter
    )

    if (!$Letter) {
	  $Letter = $($env:SystemDrive).TrimEnd(":\")
	}
    
    if (!$Letter) {
      return $null
    }

    $Match   = $null
    $Matches = $null
    $Loc_pat = '^([a-zA-Z]:\\)(.*)(.)(vhdx|vhd)$'
    $Dev_pat = '^(\\Device\\HarddiskVolume)([0-9]|[1-9][0-9])(\\)(.*)(vhdx|vhd)$'

    # Group [1] -> \Device\HarddiskVolume
    # Group [2] -> Volume_ID
    # Group [3] -> ... Ignore ...
    # Group [4] -> Path, Name
    # Group [5] -> Ext [must be vhd/vhdx]

    $info = Get_Boot_info
    $disk = Get-Partition -DriveLetter $Letter -ErrorAction SilentlyContinue | Get-disk 
    #$curr = $info | ? Boot_type -eq ([BootType]::Windows_Boot_Loader) | ? identifier -eq "{current}" | ? osdevice -eq "locate=\windows" | ? {!($_).Is_vhd() -and !($_).Is_ramdisk() -and !($_).Is_partition()}

    if (!$disk) {
      throw "error ### no such disk exist."
    }

    if ($disk.FriendlyName -ne 'Msft Virtual Disk') {
      return $false
    }

    if ($disk.Location -eq $null) {
      return $false
    }

    $Matches = [Regex]::Matches($disk.Location ,$Dev_pat)
    if ($Matches -and $Matches.Success){
      return $true
    }

    $Match = [Regex]::Matches($disk.Location ,$Loc_pat)
    if ($Match -and $Match.Success) {  
      # Case of VHDX mounted volume
      return $true
    }

    throw "error ### can't phrase regex."
}

# Function to detect path -
# of live OS running from VHD

function Get-VHD-Path {
	param (
	 [ValidatePattern("^[a-zA-Z]$")]
     [parameter(Mandatory=$False)]
     [string] $Letter
    )
	
	if (!$Letter) {
	  $Letter = $($env:SystemDrive).TrimEnd(":\")
	}
    
    if (!$Letter) {
      return $null
    }
    
    $Match   = $null
    $Matches = $null
    $Loc_pat = '^([a-zA-Z]:\\)(.*)(.)(vhdx|vhd)$'
    $Dev_pat = '^(\\Device\\HarddiskVolume)([0-9]|[1-9][0-9])(\\)(.*)(vhdx|vhd)$'

    # Group [1] -> \Device\HarddiskVolume
    # Group [2] -> Volume_ID
    # Group [3] -> ... Ignore ...
    # Group [4] -> Path, Name
    # Group [5] -> Ext [must be vhd/vhdx]

    $info = Get_Boot_info
    $disk = Get-Partition -DriveLetter $Letter -ErrorAction SilentlyContinue | Get-disk 
    #$curr = $info | ? Boot_type -eq ([BootType]::Windows_Boot_Loader) | ? identifier -eq "{current}" | ? osdevice -eq "locate=\windows" | ? {!($_).Is_vhd() -and !($_).Is_ramdisk() -and !($_).Is_partition()}

    if (!$disk) {
      throw "error ### no such disk exist."
    }

    if ($disk -and ($disk.FriendlyName -eq 'Msft Virtual Disk') -and $disk.Location) {
      
      $Match = [Regex]::Match($disk.Location ,$Loc_pat)
      if ($Match -and $Match.Success) {
        return $disk.Location
      }

      $Matches = [Regex]::Matches($disk.Location ,$Dev_pat)
      if (!$Matches -or !($Matches.Success) -or !($Matches[0])) {
        return $null
      }

      $Source = "$($Matches[0].Groups[1])$($Matches[0].Groups[2])"
      $Target = gwmi win32_volume| ? {$_.DriveLetter -and ((Get-DosDevice -DriveLetter $_.DriveLetter) -eq $Source)}
      $LeftOver = "$($Matches[0].Groups[4])$($Matches[0].Groups[5])"
      $vhdx_Loc = "$($Target.DriveLetter)\$($LeftOver)"
    }

    if ($Target -and $LeftOver){
      return $vhdx_Loc
    }

    return $null
}

# based on --> CMD file to add a VHD(x) boot object in BCD by MaloK
# https://www.tenforums.com/virtualization/193557-cmd-file-add-vhd-x-boot-object-bcd.html

Function Add_PARTITION_BOOT {
   param (

     [parameter(Mandatory=$True)]
     [string] $Name,
     
     [ValidatePattern("^[a-zA-Z]$")]
     [parameter(Mandatory=$True)]
     [string] $Letter,

     [parameter(Mandatory=$False)]
     [string] $Store,

     [parameter(Mandatory=$False)]
     [Bool] $Add_First
   )

  $store_Addin = $null
  if ($Store -and (Test-Path($Store))) {
    $store_Addin = "/store ""$Store"""
  }

  if (!(Test-Path("$($Letter):\Windows\system32\winload.efi"))) {
    return $false
  }
  
  ####
  $Device_ID = $null
  $Results   = $null
  
  $Results = cmd /c "bcdedit $($store_Addin) /create /d ""$($Name)"" /Device"  
  if ($Results) {
	$Device_ID = Pharse_GUID -Source $Results
  }
  
  if (!$Device_ID) {
	 Write-Host
	 write-host "ERROR ## Problem occurred"
     return $false
  }
  ####

  cmd /c "bcdedit $($store_Addin) /set {$($Device_ID)} device partition=$($letter):" *> $null

  ####
  $GUID = $null
  $Res  = $null
  
  $Res  = cmd /c "bcdedit $($store_Addin) /create /d ""$($Name)"" /application osloader"
  if ($Res) {
	$GUID = Pharse_GUID -Source $Res
  }
  
  if (!$GUID) {
	 Write-Host
	 write-host "ERROR ## Problem occurred"
     return $false
  }
  ####

  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} device partition=$($letter):,{$($Device_ID)}" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} osdevice partition=$($letter):,{$($Device_ID)}" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} systemroot \windows" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} path \Windows\system32\winload.efi" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} winpe no" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} detecthal yes" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} locale en-US" *> $null
  
  if ($Add_First) {
    cmd /c "bcdedit $($store_Addin) /displayorder {$($GUID)} /addfirst" *> $null
  } else {
    cmd /c "bcdedit $($store_Addin) /displayorder {$($GUID)} /addlast" *> $null
  }

  cmd /c "bcdedit $($store_Addin) /set {bootmgr} displaybootmenu True" *> $null
  cmd /c "bcdedit $($store_Addin) /set {bootmgr} timeout 5" *> $null

  return $true
}

Function Add_VHDX_BOOT {
   param (

     [parameter(Mandatory=$True)]
     [string] $Name,
     
     [parameter(Mandatory=$True)] 
     [string] $VHD_File,

     [parameter(Mandatory=$False)]
     [string] $Store,

     [parameter(Mandatory=$False)]
     [Bool] $Add_First
   )

  $store_Addin = $null
  if ($Store -and (Test-Path($Store))) {
    $store_Addin = "/store ""$Store"""
  }

  $Item = Get-ChildItem $VHD_File
  if (!$Item.Exists) {
    return $false
  }
  
  ####
  $Device_ID = $null
  $Results   = $null
  
  $Results = cmd /c "bcdedit $($store_Addin) /create /d ""$($Name)"" /Device"  
  if ($Results) {
	$Device_ID = Pharse_GUID -Source $Results
  }
  
  if (!$Device_ID) {
	 Write-Host
	 write-host "ERROR ## Problem occurred"
     return $false
  }
  ####

  $letter   = $item.PSDrive.Name
  $Sub_path = $item.FullName.Replace("$($item.PSDrive.Name):","")
  cmd /c "bcdedit $($store_Addin) /set {$($Device_ID)} device vhd=[$($letter):]""$($Sub_path)""" *> $null

  ####
  $GUID = $null
  $Res  = $null
  
  $Res  = cmd /c "bcdedit $($store_Addin) /create /d ""$($Name)"" /application osloader"
  if ($Res) {
	$GUID = Pharse_GUID -Source $Res
  }
  
  if (!$GUID) {
	 Write-Host
	 write-host "ERROR ## Problem occurred"
     return $false
  }
  ####

  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} device vhd=[$($letter):]""$($Sub_path)"",{$($Device_ID)}" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} osdevice vhd=[$($letter):]""$($Sub_path)"",{$($Device_ID)}" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} systemroot \windows" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} path \Windows\system32\winload.efi" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} winpe no" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} detecthal yes" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} locale en-US" *> $null
  
  if ($Add_First) {
    cmd /c "bcdedit $($store_Addin) /displayorder {$($GUID)} /addfirst" *> $null
  } else {
    cmd /c "bcdedit $($store_Addin) /displayorder {$($GUID)} /addlast" *> $null
  }

  cmd /c "bcdedit $($store_Addin) /set {bootmgr} displaybootmenu True" *> $null
  cmd /c "bcdedit $($store_Addin) /set {bootmgr} timeout 5" *> $null

  return $true
}

# Add_RAM_DRIVE_BOOT -Name Windows_10 -Wim_File \Sources\boot.wim -Sdi_File "\Boot\boot.sdi"                         | [BOOT]
# Add_RAM_DRIVE_BOOT -Name Windows_10 -Wim_File \Sources\boot.wim -Sdi_File "\Boot\boot.sdi" -Sdi_Partition_Letter E | [E]

Function Add_RAM_DRIVE_BOOT {
   param (

     [parameter(Mandatory=$True)]
     [string] $Name,
     
     [parameter(Mandatory=$True)]
     [ValidatePattern("^(\\)(.*)(\\)(.*)(.wim|.esd|.swm)$")]
     [string] $Wim_File,

     [parameter(Mandatory=$True)]
     [ValidatePattern("^(\\)(.*)(\\)(.*)(.sdi)$")]
     [string] $Sdi_File,

     [parameter(Mandatory=$False)]
     [string] $Store,

     [ValidatePattern("^[a-zA-Z]$")]
     [parameter(Mandatory=$False)]
     [string] $Sdi_Partition_Letter,

     [parameter(Mandatory=$False)]
     [Bool] $Add_First
   )

  $store_Addin = $null
  if ($Store -and (Test-Path($Store))) {
    $store_Addin = "/store ""$Store"""
  }
  
  if ($Wim_File -and $Sdi_Partition_Letter) {
    $Wim_path = "$($Sdi_Partition_Letter):$($Wim_File)"
    if (!(Test-Path($Wim_path))) {
      Write-Host
	  write-host "ERROR ## Wim File not exist"
      return $false
    }
  }

  if ($Sdi_File -and $Sdi_Partition_Letter) {
    $sdi_path = "$($Sdi_Partition_Letter):$($Sdi_File)"
    if (!(Test-Path($sdi_path))) {
      Write-Host
	  write-host "ERROR ## Sdi File not exist"
      return $false
    }
  }

  if (!$Store -and !$Sdi_Partition_Letter) {
    Write-Host
	write-host "ERROR ## For local Boot store, you must use a Specific Partition"
    return $false
  }

  ####
  $Device_ID = $null
  $Results   = $null
  
  $Results = cmd /c "bcdedit $($store_Addin) /create /d ""$($Name)"" /Device"

  if ($Results) {
	$Device_ID = Pharse_GUID -Source $Results
  }
  
  if (!$Device_ID) {
	 Write-Host
	 write-host "ERROR ## Problem occurred"
     return $false
  }
  ####
  if ($Sdi_Partition_Letter) {
    cmd /c "bcdedit $($store_Addin) /set {$($Device_ID)} ramdisksdidevice PARTITION=$($Sdi_Partition_Letter):" *> $null
  } else {
    cmd /c "bcdedit $($store_Addin) /set {$($Device_ID)} ramdisksdidevice BOOT" *> $null
  }

  cmd /c "bcdedit $($store_Addin) /set {$($Device_ID)} ramdisksdipath ""$($Sdi_File)""" *> $null

  ####
  $GUID = $null
  $Res  = $null

  $Res  = cmd /c "bcdedit $($store_Addin) /create /d ""$($Name)"" /application osloader"
  if ($Res) {
	$GUID = Pharse_GUID -Source $Res
  }
  
  if (!$GUID) {
	 Write-Host
	 write-host "ERROR ## Problem occurred"
     return $false
  }
  ####
   if ($Sdi_Partition_Letter) {
    cmd /c "bcdedit $($store_Addin) /set {$($GUID)} device ramdisk=[$($Sdi_Partition_Letter):]""$($Wim_File)"",{$($Device_ID)}" *> $null
    cmd /c "bcdedit $($store_Addin) /set {$($GUID)} osdevice ramdisk=[$($Sdi_Partition_Letter):]""$($Wim_File)"",{$($Device_ID)}" *> $null
  } else {
    cmd /c "bcdedit $($store_Addin) /set {$($GUID)} device ramdisk=[boot]""$($Wim_File)"",{$($Device_ID)}"  *> $null
    cmd /c "bcdedit $($store_Addin) /set {$($GUID)} osdevice ramdisk=[boot]""$($Wim_File)"",{$($Device_ID)}" *> $null
  }

  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} bootmenupolicy Standard" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} systemroot \windows" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} path \windows\system32\boot\winload.efi" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} inherit {bootloadersettings}" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} winpe yes" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} detecthal yes" *> $null
  cmd /c "bcdedit $($store_Addin) /set {$($GUID)} locale en-US" *> $null

  if ($Add_First) {
    cmd /c "bcdedit $($store_Addin) /displayorder {$($GUID)} /addfirst" *> $null
  } else {
    cmd /c "bcdedit $($store_Addin) /displayorder {$($GUID)} /addlast" *> $null
  }

  cmd /c "bcdedit $($store_Addin) /set {bootmgr} displaybootmenu True" *> $null
  cmd /c "bcdedit $($store_Addin) /set {bootmgr} timeout 5" *> $null

  return $true
}

enum BootType {
    unknown = 0
    Firmware_Application_101fffff = 1
    Resume_from_Hibernate = 2
    Firmware_Boot_Manager = 3
    Windows_Boot_Manager = 4
    Windows_Boot_Loader = 5
    Windows_Memory_Tester = 6
    EMS_Settings = 7
    Debugger_Settings = 8
    RAM_Defects = 9
    Global_Settings = 10
    Boot_Loader_Settings = 11
    Resume_Loader_Settings = 12
    Hypervisor_Settings = 13
    Device_options = 14
    Windows_Legacy_OS_Loader = 15
}

class Boot_info {
    [Object]$raw
    [BootType]$Boot_type
    [int]$hypervisordebugport
    [int]$debugport
    [int]$baudrate
    [int]$hypervisorbaudrate
    [int]$timeout
    [string]$debugtype
    [string]$filedevice
    [string]$filepath
    [string]$identifier
    [string]$device
    [string]$path
    [string]$description
    [string]$locale
    [string]$osdevice
    [string]$inherit
    [string]$testsigning
    [string]$recoverysequence
    [string]$displaymessageoverride
    [string]$recoveryenabled
    [string]$isolatedcontext
    [string]$allowedinmemorysettings
    [string]$nx
    [string]$bootmenupolicy
    [string]$systemroot
    [string]$resumeobject
    [string]$hypervisordebugtype
    [string]$hypervisorlaunchtype
    [string]$bootems
    [string]$badmemoryaccess
    [string]$winpe
    [string]$default
    [string]$debugoptionenabled
    [string]$displayorder
    [string]$toolsdisplayorder
    [string]$displaybootmenu
    [string]$detecthal
    [string]$ramdisksdidevice
    [string]$ramdisksdipath

    [bool]Is_vhd(){
      if ($this.Boot_type -eq [BootType]::Windows_Boot_Loader) {
        
        # case Device Match VHD
        if ($this.osdevice -and ($this.Device -match 'vhd')) {
          return $true
        }

        # case {CURRENT} with universal Path & C drive is actualy a VHD disk
        if ($this.identifier -and ($this.identifier -eq '{current}') -and (!$this.Is_ramdisk()) -and (!$this.Is_partition()) -and (Is-VHD-System C)) {
          return $true
        }
      }
      return $false
    }

    [bool]Is_ramdisk(){
      if ($this.Boot_type -eq [BootType]::Windows_Boot_Loader) {
        if ($this.osdevice -and ($this.Device -match 'ramdisk'))
        {
          return $true
        }
      }
      return $false
    }

    [bool]Is_partition(){
      if ($this.Boot_type -eq [BootType]::Windows_Boot_Loader) {
        if ($this.osdevice -and ($this.Device -match 'partition'))
        {
          return $true
        }
      }
      return $false
    }

    [bool]Validate_vhd_Path(){
      $file_Path = $null
      $file_Path = $this.Get_VHD_Path()

      if ($file_Path -and (Test-path($file_Path))) {
          return $true
      }
      return $false
    }

    [string]Get_VHD_Path(){
      if ($this.Is_vhd() -and $this.device ) {

        # case of LiveOs Mounted VHD
        if ($this.device -match "^(.*)(Windows)(.*)(winload)(.efi|.exe)$") {
          try {
            return Get-VHD-Path C
          }
            catch {
          }
        }

        # case of Normal VHD :: PATH GUID
        $Pattern = "(^(vhd=\[)([a-zA-Z]:)\](.*)(.vhd|.vhdx)(,{.*})$)"
        $Matches = [Regex]::Matches($this.device, $Pattern)
        if ($Matches -and $Matches.Success -and $Matches[0]) {
          $ltr = $Matches[0].Groups[3].Value
          $loc = $Matches[0].Groups[4].Value
          $ext = $Matches[0].Groups[5].Value
          return "$($ltr)$($loc)$($ext)"
        }

        # case of Normal VHD :: PATH
        $Pattern = "(^(vhd=\[)([a-zA-Z]:)\](.*)(.vhd|.vhdx)$)"
        $Matches = [Regex]::Matches($this.device, $Pattern)
        if ($Matches -and $Matches.Success -and $Matches[0]) {
          $ltr = $Matches[0].Groups[3].Value
          $loc = $Matches[0].Groups[4].Value
          $ext = $Matches[0].Groups[5].Value
          return "$($ltr)$($loc)$($ext)"
        }
      }
      return $null
    }

    [int]Remove_ID(){
      if (!$this.identifier) {
        return 2
      }

      $result = start "bcdedit" -args " /delete $($this.identifier)" -Wait -WindowStyle Hidden -PassThru
      #write-host "Exit code :: $($result.ExitCode)"
      return  ($result.ExitCode -as [Int])
    }

    [int]Remove_ID([string] $Store){
      if (!$this.identifier) {
        return 2
      }

      $result = start "bcdedit" -args "/store $($Store) /delete $($this.identifier)" -Wait -WindowStyle Hidden -PassThru
      #write-host "Exit code :: $($result.ExitCode)"
      return  ($result.ExitCode -as [Int])
    }
}

function Update_Last_Access {
   param (
      [Boot_info] $data,
      [string] $last_Access,
      [string] $value
   )
   if ($last_Access -and $value) {
        switch ($last_Access)
        {
            "identifier" {$data.identifier += $value }
            "device" {$data.device  += $value }
            "path" {$data.path  += $value }
            "description" {$data.description += $value }
            "locale" {$data.locale += $value }
            "osdevice" {$data.osdevice += $value }
            "inherit" {$data.inherit += $value }
			"testsigning" {$data.testsigning += $value }
            "recoverysequence" {$data.recoverysequence += $value }
            "displaymessageoverride" {$data.displaymessageoverride += $value }
            "recoveryenabled" {$data.recoveryenabled += $value }
            "isolatedcontext" {$data.isolatedcontext += $value }
            "allowedinmemorysettings" {$data.allowedinmemorysettings += $value }
            "nx" {$data.nx += $value }
            "bootmenupolicy" {$data.bootmenupolicy += $value }
            "systemroot" {$data.systemroot += $value }
            "resumeobject" {$data.resumeobject += $value }
            "hypervisordebugtype" {$data.hypervisordebugtype += $value }
            "hypervisordebugport" {$data.hypervisordebugport += $value }
            "hypervisorbaudrate" {$data.hypervisorbaudrate += $value }
            "baudrate" {$data.baudrate += $value }
            "debugport" {$data.debugport += $value }
            "timeout" {$data.timeout += $value }
            "resumeobject" {$data.resumeobject += $value }
            "bootems" {$data.bootems += $value }
            "badmemoryaccess" {$data.badmemoryaccess += $value }
            "hypervisorlaunchtype" {$data.hypervisorlaunchtype += $value }
            "winpe" {$data.winpe += $value }
            "debugtype" {$data.debugtype += $value }
            "default" {$data.default += $value }
            "debugoptionenabled" {$data.debugoptionenabled += $value }
            "filepath" {$data.filepath += $value }
            "filedevice" {$data.filedevice += $value }
            "displayorder" {$data.displayorder += $value }
            "toolsdisplayorder" {$data.toolsdisplayorder += $value }
            "displaybootmenu" {$data.displaybootmenu += $value }
            "detecthal" {$data.detecthal += $value }
            "ramdisksdidevice" {$data.ramdisksdidevice += $value }
            "ramdisksdipath" {$data.ramdisksdipath += $value }
        }
   }
}

function Get_Boot_info {

    Param (
      [STRING]
      $path
    )

    if ($path -and (!(Test-Path($path)))) {
      return $null
    }

    $addin = $null
    if ($path) {
      $addin = "/store ""$($path)"""
    }

    $nl =    [System.Environment]::NewLine
    $store = (cmd /c "bcdedit $($addin) /enum ALL") | Out-String  #combine into one string
    $List =  $store -split "$nl$nl"                               #split the entries, only empty new lines
    $arr =   [System.Collections.ArrayList]::new()

    $List | % {
        $obj = $_ -Split $nl
        $bi = [Boot_info]::new()
		$bi.raw = $obj

        switch ($obj[0])
        {
            "Firmware Boot Manager" {$bi.Boot_type = [BootType]::Firmware_Boot_Manager}
            "Windows Boot Manager" {$bi.Boot_type = [BootType]::Windows_Boot_Manager}
            "Firmware Application (101fffff)" {$bi.Boot_type = [BootType]::Firmware_Application_101fffff}
            "Windows Boot Loader" {$bi.Boot_type = [BootType]::Windows_Boot_Loader}
            "Resume from Hibernate" {$bi.Boot_type = [BootType]::Resume_from_Hibernate}
            "Windows Memory Tester" {$bi.Boot_type = [BootType]::Windows_Memory_Tester}
            "EMS Settings" {$bi.Boot_type = [BootType]::EMS_Settings}
            "Debugger Settings" {$bi.Boot_type = [BootType]::Debugger_Settings}
            "RAM Defects" {$bi.Boot_type = [BootType]::RAM_Defects}
            "Global Settings" {$bi.Boot_type = [BootType]::Global_Settings}
            "Boot Loader Settings" {$bi.Boot_type = [BootType]::Boot_Loader_Settings}
            "Hypervisor Settings" {$bi.Boot_type = [BootType]::Hypervisor_Settings}
            "Resume Loader Settings" {$bi.Boot_type = [BootType]::Resume_Loader_Settings}
            "Device options" {$bi.Boot_type = [BootType]::Device_options}
			"Windows Legacy OS Loader" {$bi.Boot_type = [BootType]::Windows_Legacy_OS_Loader}
            default {$bi.Boot_type = [BootType]::unknown}
        }

        switch ($obj[1])
        {
            "Firmware Boot Manager" {$bi.Boot_type = [BootType]::Firmware_Boot_Manager}
            "Windows Boot Manager" {$bi.Boot_type = [BootType]::Windows_Boot_Manager}
            "Firmware Application (101fffff)" {$bi.Boot_type = [BootType]::Firmware_Application_101fffff}
            "Windows Boot Loader" {$bi.Boot_type = [BootType]::Windows_Boot_Loader}
            "Resume from Hibernate" {$bi.Boot_type = [BootType]::Resume_from_Hibernate}
            "Windows Memory Tester" {$bi.Boot_type = [BootType]::Windows_Memory_Tester}
            "EMS Settings" {$bi.Boot_type = [BootType]::EMS_Settings}
            "Debugger Settings" {$bi.Boot_type = [BootType]::Debugger_Settings}
            "RAM Defects" {$bi.Boot_type = [BootType]::RAM_Defects}
            "Global Settings" {$bi.Boot_type = [BootType]::Global_Settings}
            "Boot Loader Settings" {$bi.Boot_type = [BootType]::Boot_Loader_Settings}
            "Hypervisor Settings" {$bi.Boot_type = [BootType]::Hypervisor_Settings}
            "Device options" {$bi.Boot_type = [BootType]::Device_options}
			"Windows Legacy OS Loader" {$bi.Boot_type = [BootType]::Windows_Legacy_OS_Loader}
            "Resume Loader Settings" {$bi.Boot_type = [BootType]::Resume_Loader_Settings}
        }

        $last_Access = $null
        ForEach ($itm in $obj)
        {
			$raw    = [regex]::Replace($itm, "\s+", " ")
            $data   = $raw.Split(' ')
            switch ($data[0])
            {
                "identifier" {$bi.identifier = $raw.Substring($data[0].Length+1); $last_Access='identifier'}
                "device" {if ($data[1] -ne 'options') {$bi.device  = $raw.Substring($data[0].Length+1); $last_Access='device'}}
                "path" {$bi.path  = $raw.Substring($data[0].Length+1); $last_Access='path'}
                "description" {$bi.description  = $raw.Substring($data[0].Length+1); $last_Access='description'}
                "locale" {$bi.locale = $raw.Substring($data[0].Length+1); $last_Access='locale'}
                "osdevice" {$bi.osdevice = $raw.Substring($data[0].Length+1); $last_Access='osdevice'}
                "inherit" {$bi.inherit = $raw.Substring($data[0].Length+1); $last_Access='inherit'}
                "testsigning" {$bi.testsigning = $raw.Substring($data[0].Length+1); $last_Access='testsigning'}
                "recoverysequence" {$bi.recoverysequence = $raw.Substring($data[0].Length+1); $last_Access='recoverysequence'}
                "displaymessageoverride" {$bi.displaymessageoverride = $raw.Substring($data[0].Length+1); $last_Access='displaymessageoverride'}
                "recoveryenabled" {$bi.recoveryenabled = $raw.Substring($data[0].Length+1); $last_Access='recoveryenabled'}
                "isolatedcontext" {$bi.isolatedcontext = $raw.Substring($data[0].Length+1); $last_Access='isolatedcontext'}
                "allowedinmemorysettings" {$bi.allowedinmemorysettings = $raw.Substring($data[0].Length+1); $last_Access='allowedinmemorysettings'}
                "nx" {$bi.nx = $raw.Substring($data[0].Length+1); $last_Access='nx'}
                "bootmenupolicy" {$bi.bootmenupolicy = $raw.Substring($data[0].Length+1); $last_Access='bootmenupolicy'}
                "systemroot" {$bi.systemroot = $raw.Substring($data[0].Length+1); $last_Access='systemroot'}
                "resumeobject" {$bi.resumeobject = $raw.Substring($data[0].Length+1); $last_Access='resumeobject'}
                "hypervisordebugtype" {$bi.hypervisordebugtype = $raw.Substring($data[0].Length+1); $last_Access='hypervisordebugtype'}
                "hypervisordebugport" {$bi.hypervisordebugport = $data[1] -as [INT]; $last_Access='hypervisordebugport'}
                "hypervisorbaudrate" {$bi.hypervisorbaudrate = $data[1] -as [INT]; $last_Access='hypervisorbaudrate'}
                "baudrate" {$bi.baudrate = $data[1] -as [INT]; $last_Access='baudrate'}
                "debugport" {$bi.debugport = $data[1] -as [INT]; $last_Access='debugport'}
                "timeout" {$bi.timeout = $data[1] -as [INT]; $last_Access='timeout'}
                "bootems" {$bi.bootems = $raw.Substring($data[0].Length+1); $last_Access='bootems'}
                "badmemoryaccess" {$bi.badmemoryaccess = $raw.Substring($data[0].Length+1); $last_Access='badmemoryaccess'}
                "hypervisorlaunchtype" {$bi.hypervisorlaunchtype = $raw.Substring($data[0].Length+1); $last_Access='hypervisorlaunchtype'}
                "winpe" {$bi.winpe = $raw.Substring($data[0].Length+1); $last_Access='winpe'}
                "debugtype" {$bi.debugtype = $raw.Substring($data[0].Length+1); $last_Access='debugtype'}
                "default" {$bi.default = $raw.Substring($data[0].Length+1); $last_Access='default'}
                "debugoptionenabled" {$bi.debugoptionenabled = $raw.Substring($data[0].Length+1); $last_Access='debugoptionenabled'}
                "filepath" {$bi.filepath = $raw.Substring($data[0].Length+1); $last_Access='filepath'}
                "filedevice" {$bi.filedevice = $raw.Substring($data[0].Length+1); $last_Access='filedevice'}
                "displayorder" {$bi.displayorder = $raw.Substring($data[0].Length+1); $last_Access='displayorder'}
                "toolsdisplayorder" {$bi.toolsdisplayorder = $raw.Substring($data[0].Length+1); $last_Access='toolsdisplayorder'}
                "displaybootmenu" {$bi.displaybootmenu = $raw.Substring($data[0].Length+1); $last_Access='displaybootmenu'}
                "detecthal" {$bi.detecthal = $raw.Substring($data[0].Length+1); $last_Access='detecthal'}
                "ramdisksdidevice" {$bi.ramdisksdidevice = $raw.Substring($data[0].Length+1); $last_Access='ramdisksdidevice'}
                "ramdisksdipath" {$bi.ramdisksdipath = $raw.Substring($data[0].Length+1); $last_Access='ramdisksdipath'}
                "Boot" {continue}
                "Debugger" {continue}
                "EMS" {continue}
                "Firmware" {continue}
                "Global" {continue}
                "Hypervisor"{continue}
                "RAM" {continue}
                "Resume" {continue}
                "Windows" {continue}
                default { Update_last_access -Data $bi -last_Access $last_Access -value $data }
            }
        }
        $arr.Add($bi) | out-null
    }
  
    return $arr
}