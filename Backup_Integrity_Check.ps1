# Backup Integrity Check Version 0.3
cls
Function CheckBackupIntegrety {
    param (
        [Parameter(Mandatory=$true, ValueFromPipeline = $true)][string]$DIR,
        [string]$SRC_Host,
        [switch]$GridView,
        [switch]$DuplicateCheck
    )
    
    $NrFiles=(gci $DIR).count
    $OnePerc=100/$NrFiles
    $TAR_Hosts=@()
    $CSVColumnSort=@("RelativePath", "FileHash", "FileChanged")
    Write-Debug "CSVColumnSort contains: '$CSVColumnSort'"
    $Activity="Importing $NrFiles indexes"
    $Progress=0
    Write-Debug ">>> $Activity"

    $CSV_Content = @{}
    $i=0
    gci $DIR | ForEach-Object {
        $i++
        Write-Debug "Importing $($_.Name)"
        Write-Progress -Activity $Activity -Status "Importing Index $i : '$($_.Name)'" -PercentComplete $Progress
        Import-Csv $_ | ForEach-Object {
            If ($CSV_Content.ContainsKey($_.RelativePath)) {
                # Write-Debug "Add: $_"
                
                $TMP_Array=@($CSV_Content.Get_Item($_.RelativePath))
                $TMP_Array+=$_
                $CSV_Content.Set_Item($_.RelativePath, $TMP_Array)
            }
            Else { 
                # Write-Debug "New: $_"
                $CSV_Content.Add($_.RelativePath, $_)
            }
            
            If ($_.Hostname -and $TAR_Hosts -notcontains $_.Hostname -and $_.Hostname -notmatch $SRC_Host) {
               Write-Debug "Adding '$($_.Hostname)' to TAR_Hosts"
               $TAR_Hosts += $_.Hostname
               $CSVColumnSort += $_.Hostname
            }
        }
        $Progress=$Progress + $OnePerc
    }
    Write-Progress -Activity $Activity -Status "Done" -Completed
    Write-Debug "TAR_Hosts is: '$TAR_Hosts'"
    
    $Activity="Processing imported content"
    $Progress=0
    Write-Debug ">>> $Activity"
    
    $IntegretyResult = @()
    $TextInfo = (Get-Culture).TextInfo
    $origin = New-Object -Type DateTime -ArgumentList 1970, 1, 1, 0, 0, 0, 0
    
    $OnePerc=100/($CSV_Content.Keys.count)
    Write-Debug "One Percent is: $OnePerc"
    ForEach ($Key in $CSV_Content.Keys) {
        Write-Debug ">> Checking '$Key'"
        Write-Progress -Activity $Activity -PercentComplete $Progress
        $ResultLine = @{}
        Write-Debug "ResultLine has got '$($ResultLine.count)' keys"
        ForEach ($Column in $CSVColumnSort) {
            Write-Debug "Adding '$Column' to ResultLine"
            $ResultLine.Add($Column,"")  
        }
        Write-Debug "ResultLine has now got '$($ResultLine.count)' keys"
        ForEach ($TAR_Host in $TAR_Hosts) {    # Set default value for target hosts
            $ResultLine.Set_Item($TAR_Host,"File Missing")
        }
        
        $CSV_Content.$Key | ForEach-Object {
            If ($_.Hostname -match $SRC_Host) {
                Write-Debug "Setting Source values based on hostname: '$($_.Hostname)' `t -> '$($_.FileHash)'"
                $DateTime = get-date $origin.AddSeconds($_.FileChangeDate) -Format s
        
                $ResultLine.Set_Item("RelativePath", $_.RelativePath)
                $ResultLine.Set_Item("FileHash", $_.FileHash)
                $ResultLine.Set_Item("FileChanged", $DateTime)
            }
            ElseIf ($_.Hostname) {
                Write-Debug "Setting Target values based on hostname: '$($_.Hostname)' `t -> '$($_.FileHash)'"
                If ($_.FileHash) {
                    $ResultLine.Set_Item($_.Hostname, $_.FileHash)
                }
                Else {
                    Write-Debug "No Filehash, using FileChangeDate: '$($_.FileChangeDate)'"
                    $DateTime = get-date $origin.AddSeconds($_.FileChangeDate) -Format s
                    $ResultLine.Set_Item($_.Hostname, $DateTime)
                }
            }
            Else {
                Write-Warning "On processing '$Key', a skip occured on hostname value: '$($_.Hostname)'"
            }
        }
        
        Write-Debug ">> Comparing Target file hashes for '$Key'"
        $ResultLine.Add("IntegretyStatus","InSync")
        Write-Debug "ResultLine has eventually got '$($ResultLine.count)' keys"
        ForEach ($TAR_Host in $TAR_Hosts) {    # Compare hashes of Target
            Write-Debug "Target '$TAR_Host' Hash: '$($ResultLine.$TAR_Host)'"
            Write-Debug "Source '$SRC_Host' Hash: '$($ResultLine.FileHash)'"
            # Proces Source
            If ($ResultLine.FileHash.Length -eq 0) {
                Write-Debug "No Source hash for '$Key'"
                $ResultLine.Set_Item("IntegretyStatus","Missing Filehash on Source")
                If ($ResultLine.RelativePath.Length -eq 0) {
                    Write-Debug "RelativePath is missing, entering value based on table Key: '$Key'"
                    $ResultLine.Set_Item("RelativePath", $Key)
                }
                If ($ResultLine.FileChanged.Length -eq 0) {
                    Write-Debug "FileChanged is missing, expecting the file to not exist on source."
                    $ResultLine.Set_Item("IntegretyStatus","Sourcefile missing")
                    $ResultLine.Set_Item("FileHash", "File Missing")
                }
                Else {
                    $ResultLine.Set_Item("FileHash", "Filehash not stored")
                }
            }
            
            # Proces Target
            If ($ResultLine.$TAR_Host.Length -ne 0) {   # Changedate or Filehash available
                If ($ResultLine.$TAR_Host -match $ResultLine.FileHash) {
                    Write-Debug "Match on Hashvalues, leave IntegretyStatus unchanged"
                    $ResultLine.Set_Item($TAR_Host, "InSync")
                }
                ElseIf ($ResultLine.FileChanged) {  # If exists, there was a file on source
                    If ($ResultLine.$TAR_Host -match $ResultLine.FileChanged) {
                        $ResultLine.Set_Item($TAR_Host, "Equal File Changedate")
                    }
                    Else {
                        $ResultLine.Set_Item("IntegretyStatus","Out of Sync")
                    }
                }
                Else {
                    Write-Debug "Notting to compare with"
                }
            }
            Else {
                # Leave $ResultLine.$TAR_Host unchanged -> Missing
                Write-Debug "Empty Hash for Target host: $TAR_Host"
                $ResultLine.Set_Item("IntegretyStatus","Targetfile Missing")
            }
            
            Write-Debug "--"
        }   
        $IntegretyResult += New-Object PSObject -Property $ResultLine
        Write-Debug "-----"
        $Progress=$Progress + $OnePerc
    }
    Write-Progress -Activity $Activity -Status "Comparing hashvalue completed, writing content to file" -PercentComplete $Progress
    If ($GridView) { $IntegretyResult | Out-GridView }
    Else {
        $CSVTarget = $(gci $DIR | Where-Object {$_.Name -match $SRC_Host}).FullName.Replace('.csv','.result.csv')
        $CSVColumnSort+="IntegretyStatus"
        Write-Host "Result is written to: $CSVTarget"
        $IntegretyResult | Select-Object $CSVColumnSort | Export-Csv -Path "$CSVTarget" -NoTypeInformation
    }
    Write-Progress -Activity $Activity -Status "Done" -Completed
}


# CheckBackupIntegrety -DIR "$($env:USERPROFILE)\LogFiles\RasPi_Lely\BIA\Backup_Index.*.SHA256.csv" -SRC_Host "raspberrypi3"
CheckBackupIntegrety -DIR "$($env:USERPROFILE)\LogFiles\RasPi_Lely\BIA\SynoBackup_Index.*.SHA256.csv" -SRC_Host "DiskStation"
