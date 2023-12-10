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

function Get-TargetResource
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceId
    )

    $resourceIdParts = $ResourceId.Split('/')
    if (($resourceIdParts.Length -eq 3) -and ($resourceIdParts[1] -eq 'subscriptions') -and
        ([Text.RegularExpressions.Regex]::Match($resourceIdParts[2], '^[a-z0-9]{8}-([a-z0-9]{4}-){3}[a-z0-9]{12}$').Success)) {
        return Get-AzSubscription -SubscriptionId $resourceIdParts[2]
    }
    elseif ($resourceIdParts.Length -gt 3) {
        return Get-AzResource -ResourceId $ResourceId
    }

    Write-Host -Object ('The resource ID "{0}" has an unexpected resource ID format.'-f $ResourceId) -ForegroundColor DarkYellow
    return $null
}

function Invoke-TagFiltering
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $ResourceId,

        [Parameter(Mandatory = $true)]
        [hashtable] $TagsToFilter
    )

    $resource = Get-TargetResource -ResourceId $ResourceId

    if ($resource -eq $null) {
        Write-Host -Object 'Skip the tag filtering because the actual target resource was not identified. This query result item will be included in the output (pass-through).' -ForegroundColor DarkYellow
        return @{
            ShouldOutput = $true
            Tags         = New-Object -TypeName 'System.Collections.Generic.Dictionary[[string],[string]]'  # Set tag as empty.
        }
    }

    # No tags are specified for filtering.
    if ($TagsToFilter.Keys.Count -eq 0) {
        return @{
            ShouldOutput = $true
            Tags         = if ($resource.Tags -ne $null) {
                $resource.Tags
            }
            else {
                New-Object -TypeName 'System.Collections.Generic.Dictionary[[string],[string]]'  # No tags.
            }
        }
    }

    # TODO: Tag finding can be skippped if the resource has no tags.

    # Filter by tags.
    $shouldOutput = $false
    foreach ($filterTagName in $TagsToFilter.Keys) {
        if ($resource.Tags.Keys -contains $filterTagName) {
            if ($resource.Tags[$filterTagName] -eq $TagsToFilter[$filterTagName]) {
                Write-Verbose -Message ('The specified tag was matched on {0}. Resource tag = {{"{1}":"{2}"}}, Filtering tag = {{"{1}":"{3}"}}.' -f $_.ResourceId, $filterTagName, $resource.Tags[$filterTagName], $TagsToFilter[$filterTagName])
                $shouldOutput = $true
                break
            }
        }
    }

    return @{
        ShouldOutput = $shouldOutput
        Tags         = $resource.Tags
    }
}

$azureContext = Get-AzContext
Write-Verbose -Message ('The current Azure context is "{0}".' -f $azureContext.Name)

Get-ChildItem -Path $QueriesFolderPath -File -Filter '*.kql' -Recurse -Depth 3 | ForEach-Object -Process {
    Write-Host -Object ('Invoking a query with "{0}".' -f $_.FullName) -ForegroundColor Cyan
    $query = Get-QueryFileContent -FilePath $_.FullName
    if ($query.Length -gt 0) {
        (Search-AzGraph -Query $query -Subscription $azureContext.Subscription.Id) | ForEach-Object -Process {
            $tagFilteringResult = Invoke-TagFiltering -ResourceId $_.ResourceId -TagsToFilter $TagsToFilter
            if ($tagFilteringResult.ShouldOutput) {
                Write-Verbose -Message ('Resource ID: {0}' -f $_.ResourceId)
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
