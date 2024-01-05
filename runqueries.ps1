#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Az.ResourceGraph'; ModuleVersion = '0.13.0' }
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.13.1' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.7.0' }

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string] $QueriesFolderPath = './queries',

    [Parameter(Mandatory = $false)]
    [hashtable] $TagsToFilter = @{},

    [switch] $IncludeTag,

    [switch] $IncludeSkippedQueries
)

$ErrorActionPreference = 'Stop'

Import-Module -Name 'Az.ResourceGraph' -Force
Import-Module -Name 'Az.Accounts' -Force
Import-Module -Name 'Az.Resources' -Force

function Get-Query
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    $returnValue = [PSCustomObject]@{
        Id                = [System.IO.Path]::GetFileNameWithoutExtension($FilePath).ToUpper()
        FilePath          = $FilePath
        QueryContent      = Get-Content -LiteralPath $FilePath -Encoding UTF8 -Raw
        IsAvailable       = $true
        UnavailableReason = ''
    }

    if ($returnValue.QueryContent.IndexOf('// under-development') -ge 0) {
        $returnValue.IsAvailable = $false
        $returnValue.UnavailableReason = 'under development'
    }
    # NOTE: workaround
    elseif ($returnValue.QueryContent.IndexOf('under-development') -ge 0) {
        $returnValue.IsAvailable = $false
        $returnValue.UnavailableReason = 'under development'
    }
    # NOTE: workaround
    elseif ($returnValue.QueryContent.IndexOf('//under development') -ge 0) {
        $returnValue.IsAvailable = $false
        $returnValue.UnavailableReason = 'under development'
    }
    elseif ($returnValue.QueryContent.IndexOf('// cannot-be-validated-with-arg') -ge 0) {
        $returnValue.IsAvailable = $false
        $returnValue.UnavailableReason = 'cannot be validated with ARG'
    }

    return $returnValue
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

    # Could not identified the resource.
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

    Write-Host -Object ('The resource ID "{0}" has an unexpected resource ID format.' -f $ResourceId) -ForegroundColor DarkYellow
    return $null
}

function Get-SerializedTags
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.Dictionary[[string],[string]]] $Tags
    )

    return ($Tags.Keys | ForEach-Object -Process { '{{"{0}":"{1}"}}' -f $_, $Tags[$_] }) -join ', '
}

$IncludeTag = if ($TagsToFilter.Count -gt 0) { $true } else { $IncludeTag }

$azureContext = Get-AzContext
Write-Host -Object ('The current Azure context is "{0}".' -f $azureContext.Name)

Get-ChildItem -Path $QueriesFolderPath -File -Filter '*.kql' -Recurse -Depth 5 | ForEach-Object -Process {
    $query = Get-Query -FilePath $_.FullName
    if ($query.IsAvailable) {
            Write-Host -Object ('{0,-10}: Invoking the query.' -f $query.Id) -ForegroundColor Cyan -NoNewline
            Write-Host -Object (' - "{0}"' -f $query.FilePath) -ForegroundColor DarkGray
            (Search-AzGraph -Query $query.QueryContent -Subscription $azureContext.Subscription.Id) | ForEach-Object -Process {
            Write-Verbose -Message ('Resource ID: {0}' -f $_.ResourceId)

            if ($IncludeTag) {
                $tagFilteringResult = Invoke-TagFiltering -ResourceId $_.ResourceId -TagsToFilter $TagsToFilter
                $shouldOutput = $tagFilteringResult.ShouldOutput
            }
            else {
                $shouldOutput = $true
            }

            if ($shouldOutput) {
                [PSCustomObject] @{
                    'recommendationId' = $_.recommendationId
                    'name'             = $_.name
                    'resourceId'       = $_.ResourceId
                    'tags'             = if ($IncludeTag) { Get-SerializedTags -Tags $tagFilteringResult.Tags } else { '' }
                    'param1'           = $_.param1
                    'param2'           = $_.param2
                    'param3'           = $_.param3
                    'param4'           = $_.param4
                    'param5'           = $_.param5
                    'param6'           = $_.param6
                }
            }
        }
    }
    else {
        Write-Host -Object ('{0,-10}: Skip invoking because it is {1}.' -f $query.Id, $query.UnavailableReason) -ForegroundColor Cyan -NoNewline
        Write-Host -Object (' - "{0}"' -f $query.FilePath) -ForegroundColor DarkGray
        if ($IncludeSkippedQueries) {
            [PSCustomObject] @{
                'recommendationId' = '{0} ({1})' -f $query.Id.ToLower(), $query.UnavailableReason
                'name'             = ''
                'resourceId'       = ''
                'tags'             = ''
                'param1'           = ''
                'param2'           = ''
                'param3'           = ''
                'param4'           = ''
                'param5'           = ''
                'param6'           = ''
            }
        }
    }
}
