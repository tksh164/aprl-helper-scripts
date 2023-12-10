#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Az.ResourceGraph'; ModuleVersion = '0.13.0' }
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.13.1' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.7.0' }

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string] $QueriesFolderPath = './queries',

    [Parameter(Mandatory = $false)]
    [hashtable] $TagsToFilter = @{}
)

$ErrorActionPreference = 'Stop'

Import-Module -Name 'Az.ResourceGraph' -Force
Import-Module -Name 'Az.Accounts' -Force
Import-Module -Name 'Az.Resources' -Force

function Get-QueryFileContent
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    $query = Get-Content -LiteralPath $FilePath -Encoding UTF8 -Raw
    $query = $query -replace '\W*//.*',''            # Remove comments.
    $query = $query -replace 'under-development',''  # Workaround for non-commented out comments.

    return $query.Trim()
}

function Invoke-TagFiltering
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [hashtable] $TagsToFilter,

        [Parameter(Mandatory = $true)]
        [string] $ResourceId
    )

    $resourceIdParts = $ResourceId.Split('/')
    if (($resourceIdParts.Length -eq 3) -and ($resourceIdParts[1] -eq 'subscriptions') -and
        ([Text.RegularExpressions.Regex]::Match($resourceIdParts[2], '^[a-z0-9]{8}-([a-z0-9]{4}-){3}[a-z0-9]{12}$').Success)) {
        $resource = Get-AzSubscription -SubscriptionId $resourceIdParts[2]
    }
    elseif ($resourceIdParts.Length -gt 3) {
        $resource = Get-AzResource -ResourceId $ResourceId
    }
    else {
        Write-Host -Object ('Skipped filtering by tag because the resouce ID format was unexpected. The resource ID was "{0}".' -f $ResourceId) -ForegroundColor DarkYellow
        return @{
            Result = $true
            Tags   = New-Object -TypeName 'System.Collections.Generic.Dictionary[[string],[string]]'  # No tags.
        }
    }

    # No tag filters.
    if ($TagsToFilter.Keys.Count -eq 0) {
        return @{
            Result = $true
            Tags   = $resource.Tags
        }
    }

    # Filter by tags.
    $shouldOutResult = $false
    foreach ($filterTagName in $TagsToFilter.Keys) {
        if ($resource.Tags.Keys -contains $filterTagName) {
            if ($resource.Tags[$filterTagName] -eq $TagsToFilter[$filterTagName]) {
                Write-Verbose -Message ('The specified tag was matched on {0}. Resource tag = {{"{1}":"{2}"}}, Filtering tag = {{"{1}":"{3}"}}.' -f $_.ResourceId, $filterTagName, $resource.Tags[$filterTagName], $TagsToFilter[$filterTagName])
                $shouldOutResult = $true
                break
            }
        }
    }

    return @{
        Result = $shouldOutResult
        Tags   = $resource.Tags
    }
}

$azureContext = Get-AzContext
Write-Verbose -Message ('The current Azure context is "{0}".' -f $azureContext.Name)

Get-ChildItem -Path $QueriesFolderPath -File -Filter '*.kql' -Recurse -Depth 3 | ForEach-Object -Process {
    Write-Host -Object ('Invoking a query with "{0}".' -f $_.FullName) -ForegroundColor Cyan
    $query = Get-QueryFileContent -FilePath $_.FullName
    if ($query.Length -gt 0) {
        (Search-AzGraph -Query $query -Subscription $azureContext.Subscription.Id) | ForEach-Object -Process {
            $tagFilteringResult = Invoke-TagFiltering -TagsToFilter $TagsToFilter -ResourceId $_.ResourceId
            if ($tagFilteringResult.Result) {
                [PSCustomObject] @{
                    'recommendationId' = $_.recommendationId
                    'name'             = $_.name
                    'resourceId'       = $_.ResourceId
                    'param1'           = $_.param1
                    'param2'           = $_.param2
                    'param3'           = $_.param3
                    'param4'           = $_.param4
                    'param5'           = $_.param5
                    'param6'           = $_.param6
                    'tags'             = ($tagFilteringResult.Tags.Keys | ForEach-Object -Process { '{{"{0}":"{1}"}}' -f $_, $tagFilteringResult.Tags[$_] }) -join ', '
                }
            }
        }
    }
}
