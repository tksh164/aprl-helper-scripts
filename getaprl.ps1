#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string] $QueriesFolderPath = './queries',

    [Parameter(Mandatory = $false)]
    [string] $WorkFolderPath = '.'
)

$ErrorActionPreference = 'Stop'

$aprlZipDownloadUri = 'https://codeload.github.com/Azure/Azure-Proactive-Resiliency-Library/zip/refs/heads/main'

$zipFilePath = Join-Path -Path $WorkFolderPath -ChildPath 'aprl.zip'
Write-Host -Object ('Downloading the APRL contents to "{0}"...' -f $zipFilePath) -ForegroundColor Cyan
Invoke-WebRequest -Method Get -Uri $aprlZipDownloadUri -OutFile $zipFilePath
Unblock-File -LiteralPath $zipFilePath

$zipExpandedFolderPath = Join-Path -Path ([IO.Path]::GetDirectoryName($zipFilePath)) -ChildPath ([IO.Path]::GetFileNameWithoutExtension($zipFilePath))
Write-Host -Object ('Expanding the APRL contents to "{0}"...' -f $zipExpandedFolderPath) -ForegroundColor Cyan
Expand-Archive -Path $zipFilePath -DestinationPath $zipExpandedFolderPath -Force

Write-Host -Object ('Extracting the APRL queries to "{0}"...' -f $QueriesFolderPath) -ForegroundColor Cyan
$subFolderPath = [IO.Path]::Combine('Azure-Proactive-Resiliency-Library-main', 'docs', 'content', 'services')
$queryFileSearchBasePath = Join-Path -Path $zipExpandedFolderPath -ChildPath $subFolderPath
#'*.kql', '*.ps1' | ForEach-Object -Process {
'*.kql' | ForEach-Object -Process {
    $filter = $_
    Get-ChildItem -Path $queryFileSearchBasePath -File -Filter $filter -Recurse -Depth 5 | ForEach-Object -Process {
        $sourceFilePath = $_.FullName
        $destinationChildPath = $sourceFilePath.Substring($sourceFilePath.LastIndexOf($subFolderPath) + $subFolderPath.Length + 1)
        $destinationFilePath = Join-Path -Path $QueriesFolderPath -ChildPath $destinationChildPath
        New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($destinationFilePath)) -Force | Out-Null
        Move-Item -LiteralPath $sourceFilePath -Destination $destinationFilePath -Force
    }
}

Write-Verbose -Message ('Trying cleaning up the working files and folders ("{0}", "{1}").' -f $zipFilePath, $zipExpandedFolderPath)
Remove-Item -LiteralPath $zipFilePath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $zipExpandedFolderPath -Recurse -Force -ErrorAction SilentlyContinue

Write-Host -Object ('Done. The APRL queries are stored in "{0}".' -f $QueriesFolderPath) -ForegroundColor Cyan
