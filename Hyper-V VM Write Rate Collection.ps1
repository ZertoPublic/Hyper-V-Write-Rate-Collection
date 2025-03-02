#requires -RunAsAdministrator
#requires -Version 5.0 

<#
.SYNOPSIS
This script is designed to enable VM Resource Metering on all VMs in SCVMM and determine the average write rate of each VM assuming a 4K write size for each write transaction.
.DESCRIPTION
Leveraging SCVMM cmdlets, this script must be run on the SCVMM machine and will enable VM Resource Metering on all VMs. Once resource metering is enabled, the script will run for a predefiend time period ($TotalRunTimeinHours) and poll the SCVMM server 
at the defined poll interval ($PollIntervalinSeconds).  The script will take the write values gathered during each poll and calculuate the write rate using am assumed 4K write block size per write transaction. The write rate averages will be 
written to a CSV file ($AverageCSV) and the raw data collected at each poll cycle will be stored in another CSV file ($RawDataCSV). The script will disable VM Resource Metering on all VMs before it completes.
.EXAMPLE
Examples of script execution
.VERSION
This script requires Powershell 5.0 or higher.
This script does not use the Zerto Rest API, so no specific Zerto version is required.
.LEGAL
Legal Disclaimer:
 
----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
 
In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages. The entire risk arising out of the use or
performance of the sample scripts and documentation remains with you.
----------------------
#>

################ Variables for your script ######################
$PollIntervalinSeconds = 10
$TotalRunTimeinHours = 1
$AverageCSV = "C:\Averages.csv"
$RawDataCSV = "C:\RawData.csv"


########################################################################################################################
# Nothing to configure below this line - Starting the main function of the script
########################################################################################################################

Write-Host -ForegroundColor Yellow "Informational line denoting start of script GOES HERE." 
Write-Host -ForegroundColor Yellow "   Legal Disclaimer:
----------------------
This script is an example script and is not supported under any Zerto support program or service.
The author and Zerto further disclaim all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose.
In no event shall Zerto, its authors or anyone else involved in the creation, production or delivery of the scripts be liable for any damages whatsoever (including, without 
limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or the inability 
to use the sample scripts or documentation, even if the author or Zerto has been advised of the possibility of such damages.  The entire risk arising out of the use or 
performance of the sample scripts and documentation remains with you.
----------------------
"

# Enable VM Resource Metering on all VMs
get-vm | Enable-VMResourceMetering

$AppStartTime = get-Date
Write-host "App Start Time:" $AppStartTime
$AppEndTime = $AppStartTime.addhours($TotalRunTimeinHours)
Write-host "App End Time:"$AppEndTime
write-host ""

$CurrentTime = get-date
while($CurrentTime -lt $AppEndTime)
{
    $AllVMDataStart = Get-VM | Measure-VM | Select VMName,AggregatedDiskDataWritten
    $PollStart = get-date

    Sleep $PollIntervalinSeconds

    $AllVMDataEnd = Get-VM | Measure-VM | Select VMName,AggregatedDiskDataWritten
    $PollEnd = get-date

    Start-job -ScriptBlock {

                    $AllVMDataStart = $args[0]
                    $PollStart = $args[1]
                    $AllVMDataEnd = $args[2]
                    $PollEnd = $args[3]
                    $RawDataCSV = $args[4]

        foreach($VMDataStart in $AllVMDataStart)
        {
            $VMName = $VMDataStart.VMName
            Write-host "VM Name:" $VMName
            Write-host "Start Data:" $VMDataStart.AggregatedDiskDataWritten
            Write-host "Start Time:" $PollStart
            $VMDataEnd = $AllVMDataEnd | where{$_.VMName -eq $VMDataStart.VMName}
            Write-host "End Data:" $VMDataEnd.AggregatedDiskDataWritten
            Write-host "End Time:" $Pollend

            $DataDifference = $VMDataEnd.AggregatedDiskDataWritten - $VMDataStart.AggregatedDiskDataWritten
            Write-host "Data Difference:" $DataDifference

            $TimeDifference = [math]::Round(($PollEnd - $PollStart).TotalSeconds,2)
            Write-host "Time Difference:"$TimeDifference

            $WriteKBps = [math]::Round(($DataDifference*4) /$TimeDifference,2)
            Write-host "KBps:"$WriteKBps
            write-host ""

            [pscustomobject]@{'VMName'="$VMName";'KBps'="$WriteKBps";'StartTime'=$PollStart;'EndTime'=$PollEnd} | export-csv -LiteralPath $RawDataCSV -NoTypeInformation -Append
        }
    } -ArgumentList $AllVMDataStart,$PollStart,$AllVMDataEnd,$PollEnd,$RawDataCSV 

    $CurrentTime = get-date
}

#Import RawDataCSV
$ImportedCSV = Import-csv -Path $RawDataCSV 

$UniqueList = $ImportedCSV | Select-Object -Unique -Property VMName -ExpandProperty VMName

Foreach($VM in $UniqueList)
{
    $CalculatedValues = $ImportedCSV | where{$_.VMName -eq $VM} | Measure-Object "KBps" -Average -Maximum -Minimum

    $AvgKBps = $CalculatedValues.Average
    $MinKBps = $CalculatedValues.Minimum
    $MaxKBps = $CalculatedValues.Maximum

    [pscustomobject]@{'VMName'="$VM";'Avg_KBps'=$AvgKBps;'Min_KBps'=$MinKBps;'Max_KBps'=$MaxKBps} | export-csv -LiteralPath $AverageCSV -NoTypeInformation -append
}
# Disable VM Resource Metering on all VMs
get-vm | Disable-VMResourceMetering