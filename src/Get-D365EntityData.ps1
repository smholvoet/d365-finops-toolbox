<#
    # depends on https://github.com/d365collaborative/d365fo.integrations

   #TODO
    .SYNOPSIS
        
    .DESCRIPTION
        
    .PARAMETER param
        
    .EXAMPLE
        
    .LINK
        
    .NOTES 
#>
function Get-D365EntityData {

    process {
        try {
            # Entity
            $EntityName = "MyEntity"

            # Filters
            $StartDate = '2021-01-01T12:00:00Z'
            $EndDate =   '2021-12-31T12:00:00Z'
            $Company =   'dat'
            $Filters = @("TransDate ge $StartDate",
                         "TransDate le $EndDate",
                         "dataAreaId eq '$Company'")

            $ExportResult = Get-D365ODataEntityData -EntityName $EntityName `
                                                    -Filter $Filters `
                                                    -TraverseNextLink `
                                                    -CrossCompany `
                                                    -Verbose

            if ($null -ne $ExportResult) {
                Write-Host "🟢 Exporting $($EntityName.Length) rows..."
                $ExportResult | Export-Csv "$PWD\$($Company)-$($EntityName).csv" -NoTypeInformation `
                                                                                 -Append `
                                                                                 -Verbose
            }
            else {
                Write-Host "🟠 No records found, nothing to export..."
            }
        }
        catch {
            # _handleException $_
        }
    }
}

Get-D365EntityData