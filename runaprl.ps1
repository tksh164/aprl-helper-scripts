#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Az.ResourceGraph'; ModuleVersion = '0.13.0' }
#Requires -Modules @{ ModuleName = 'Az.Accounts'; ModuleVersion = '2.13.1' }
#Requires -Modules @{ ModuleName = 'Az.Resources'; ModuleVersion = '6.7.0' }

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string] $QueriesFolderPath = './queries',

    [Parameter(Mandatory = $false)]
    [hashtable] $AssuredTagsToFilter = @{},

    [switch] $IncludeAssuredTags,

    [switch] $IncludeSkippedQueries
)

$ErrorActionPreference = 'Stop'

Import-Module -Name 'Az.ResourceGraph' -Force
Import-Module -Name 'Az.Accounts' -Force
Import-Module -Name 'Az.Resources' -Force

function Get-RecommendationIdFromFilePath
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    return [System.IO.Path]::GetFileNameWithoutExtension($FilePath).ToUpper()
}

function Get-ArgQuery
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $FilePath
    )

    $argQuery = [PSCustomObject] @{
        Id                = Get-RecommendationIdFromFilePath -FilePath $FilePath
        FilePath          = $FilePath
        QueryBody         = Get-Content -LiteralPath $FilePath -Encoding UTF8 -Raw
        IsAvailable       = $true
        UnavailableReason = ''
    }

    if ($argQuery.QueryBody.IndexOf('// under-development') -ge 0) {
        $argQuery.IsAvailable = $false
        $argQuery.UnavailableReason = 'under development'
    }
    elseif ($argQuery.QueryBody.IndexOf('// cannot-be-validated-with-arg') -ge 0) {
        $argQuery.IsAvailable = $false
        $argQuery.UnavailableReason = 'cannot be validated with ARG'
    }

    return $argQuery
}

function Invoke-ArgQuery
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject] $Query,

        [Parameter(Mandatory = $true)]
        [string] $SubscriptionId
    )

    $params = @{
        Query        = $Query.QueryBody
        Subscription = $SubscriptionId
        First        = 1000  # Maximum number of results retrieved at once
    }
    $response = Search-AzGraph @params
    do {
        $response | ForEach-Object -Process {
            return [PSCustomObject] @{
                'recommendationId' = $_.recommendationId
                'name'             = $_.name
                'id'               = $_.id
                'tags'             = $_.tags
                'param1'           = $_.param1
                'param2'           = $_.param2
                'param3'           = $_.param3
                'param4'           = $_.param4
                'param5'           = $_.param5
                'param6'           = $_.param6
                'assuredTags'      = ''
            }
        }
        $params.SkipToken = $response.SkipToken
        $response = Search-AzGraph @params
    } while ($response.SkipToken -ne $null)
}

function Invoke-PowerShellScript
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $PowerShellScriptFilePath
    )

    & $PowerShellScriptFilePath | ForEach-Object -Process {
        return [PSCustomObject] @{
            'recommendationId' = $_.recommendationId
            'name'             = $_.name
            'id'               = $_.id
            'tags'             = $_.tags
            'param1'           = $_.param1
            'param2'           = $_.param2
            'param3'           = $_.param3
            'param4'           = $_.param4
            'param5'           = $_.param5
            'param6'           = $_.param6
            'assuredTags'      = ''
        }
    }
}

function Get-UnavailableRecommendationResult
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string] $RecommendationId,

        [Parameter(Mandatory = $true)]
        [string] $UnavailableReason
    )

    return [PSCustomObject] @{
        'recommendationId' = '{0} ({1})' -f $RecommendationId, $UnavailableReason
        'name'             = ''
        'id'               = ''
        'tags'             = ''
        'param1'           = ''
        'param2'           = ''
        'param3'           = ''
        'param4'           = ''
        'param5'           = ''
        'param6'           = ''
        'assuredTags'      = ''
    }
}

function Get-ResourceTag
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][AllowEmptyString()]
        [string] $ResourceId
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId)) {
        return ''  # The resource ID is not available.
    }

    $resource = Get-TargetResource -ResourceId $ResourceId
    if ($resource -eq $null) {
        Write-Host -Object 'Skip the tag filtering because the actual target resource was not identified. This query result item will be included in the output (pass-through).' -ForegroundColor DarkYellow
        return New-Object -TypeName 'System.Collections.Generic.Dictionary[[string],[string]]'  # Set tag as empty.
    }

    if ($resource.Tags -eq $null) {
        return New-Object -TypeName 'System.Collections.Generic.Dictionary[[string],[string]]'  # Set an empty dictionary if there are no tags.
    }
    return $resource.Tags
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
        return Get-AzSubscription -SubscriptionId $resourceIdParts[2]  # For the target resource is a subscription.
    }
    elseif ($resourceIdParts.Length -gt 3) {
        return Get-AzResource -ResourceId $ResourceId
    }

    Write-Host -Object ('The resource ID "{0}" has an unexpected resource ID format.' -f $ResourceId) -ForegroundColor DarkYellow
    return $null
}

function Test-ResourceTagsAndFilterTagsMatching
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)][AllowEmptyString()]
        [string] $ResourceId,

        [Parameter(Mandatory = $true)]
        [hashtable] $AssuredTagsToFilter
    )

    if ([string]::IsNullOrWhiteSpace($ResourceId)) {
        return $true  # Pass-through an unavailable recommendation result.
    }

    $shouldOutput = $false
    foreach ($tagNameToFilter in $AssuredTagsToFilter.Keys) {
        if ($_.assuredTags.Keys -contains $tagNameToFilter) {
            $assuredTagValue = $_.assuredTags[$tagNameToFilter]
            $tagValueToFilter = $AssuredTagsToFilter[$tagNameToFilter]
            if ($assuredTagValue -eq $tagValueToFilter) {
                Write-Verbose -Message ('The specified tag was matched on {0}. Resource tag = {{"{1}":"{2}"}}, Filtering tag = {{"{1}":"{3}"}}.' -f $ResourceId, $tagNameToFilter, $assuredTagValue, $tagValueToFilter)
                $shouldOutput = $true
                break
            }
        }
    }

    if (-not $shouldOutput) {
        Write-Verbose -Message ('The specified tag was not matched on {0}.' -f $_.id)
    }
    return $shouldOutput
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

# Include the assured tags if the assured tags to filter are specified.
$IncludeAssuredTags = if ($AssuredTagsToFilter.Count -gt 0) { $true } else { $IncludeAssuredTags }

$azureContext = Get-AzContext
Write-Host -Object ('The current Azure context is "{0}".' -f $azureContext.Name)

Get-ChildItem -Path $QueriesFolderPath -File -Filter '*.kql' -Recurse -Depth 5 | ForEach-Object -Process {
    $kqlQueryFilePath = $_.FullName

    $recommendationId = Get-RecommendationIdFromFilePath -FilePath $kqlQueryFilePath
    Write-Host -Object ('{0,-10}: ' -f $recommendationId) -ForegroundColor Cyan -NoNewline

    $query = Get-ArgQuery -FilePath $kqlQueryFilePath
    if ($query.IsAvailable) {
        Write-Host -Object 'Invoking the KQL query.' -ForegroundColor Cyan -NoNewline
        Write-Host -Object (' - "{0}"' -f $Query.FilePath) -ForegroundColor DarkGray
        return Invoke-ArgQuery -Query $query -SubscriptionId $azureContext.Subscription.Id
    }
    else {
        $psScriptFilePath = Join-Path -Path ([System.IO.Path]::GetDirectoryName($kqlQueryFilePath)) -ChildPath ([System.IO.Path]::GetFileNameWithoutExtension($kqlQueryFilePath) + '.ps1')
        if (Test-Path -LiteralPath $psScriptFilePath -PathType Leaf) {
            Write-Host -Object 'Invoking the PowerShell script.' -ForegroundColor Cyan -NoNewline
            Write-Host -Object (' - "{0}"' -f $psScriptFilePath) -ForegroundColor DarkGray
            return Invoke-PowerShellScript -PowerShellScriptFilePath $psScriptFilePath
        }
        else {
            Write-Host -Object ('Skip this recommendation because it is {0}.' -f $query.UnavailableReason) -ForegroundColor Cyan -NoNewline
            Write-Host -Object (' - "{0}"' -f $Query.FilePath) -ForegroundColor DarkGray
            if ($IncludeSkippedQueries) {
                return Get-UnavailableRecommendationResult -RecommendationId $recommendationId -UnavailableReason $query.UnavailableReason
            }
        }
    }
} |
ForEach-Object -Process {
    if (-not [string]::IsNullOrWhiteSpace($_.id)) {
        Write-Verbose -Message ('Resource ID: {0}' -f $_.id)
    }
    if ($IncludeAssuredTags) {
        $_.assuredTags = Get-ResourceTag -ResourceId $_.id
    }
    return $_
} |
Where-Object -FilterScript {
    if ($AssuredTagsToFilter.Keys.Count -eq 0) { return $true } # No tags are specified for filtering.
    return Test-ResourceTagsAndFilterTagsMatching -ResourceId $_.id -AssuredTagsToFilter $AssuredTagsToFilter
} |
ForEach-Object -Process {
    $_.assuredTags = if ([string]::IsNullOrWhiteSpace($_.assuredTags)) { '' } else { Get-SerializedTags -Tags $_.assuredTags }
    return $_
}
