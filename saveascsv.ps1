#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true, ValueFromPipeline = $true)]
    [PSCustomObject[]] $Result,

    [Parameter(Mandatory = $false)]
    [string] $OutputFilePath = './results.csv',

    [Parameter(Mandatory = $false)]
    [string] $Delimiter = ','
)

begin {
    $shouldPrintHeader = $true
}

process {
    $convertToCsvParams = @{
        Delimiter         = $Delimiter
        NoTypeInformation = $true
        #UseQuotes         = 'Always'  # For .NET based PowerShell
        #NoHeader          = -not $shouldPrintHeader  # For .NET based PowerShell
    }

    $outFileParams = @{
        LiteralPath = $OutputFilePath
        Encoding    = 'utf8'  # With BOM on Windows Powershell, Without BOM on .NET based PowerShell.
        Force       = $true
    }

    if ($shouldPrintHeader) {
        $Result | ConvertTo-Csv @convertToCsvParams | Out-File @outFileParams
        $shouldPrintHeader = $false
    }
    else {
        # For .NET based PowerShell
        #$Result | ConvertTo-Csv @convertToCsvParams | Out-File @outFileParams -Append

        # For Windows PowerShell
        $Result | ForEach-Object -Process {
            ($_.psobject.Properties.Value | ForEach-Object -Process {
                $escapedValue = $_ -replace '"','""'
                '"{0}"' -f $escapedValue
            }) -join ','
        } |
        Out-File @outFileParams -Append
    }
}

end {}
