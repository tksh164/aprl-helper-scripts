#Requires -Version 5.1

[CmdletBinding()]
param (
    [Parameter(Mandatory = $false)]
    [string] $QueriesFolderPath = './queries',

    [Parameter(Mandatory = $false)]
    [int] $MaxQueryIdToTry = 50
)

$ErrorActionPreference = 'Stop'

$repoBaseUriRaw = 'https://raw.githubusercontent.com/Azure/Azure-Proactive-Resiliency-Library/main/docs/content/services'
$services = @{
    'ai-ml' = @(
        @{
            Service = 'databricks'
            Prefix  = 'dbw'
        }
    )
    'compute' = @(
        @{
            Service = 'compute-gallery'
            Prefix  = 'cg'
        },
        @{
            Service = 'image-templates'
            Prefix  = 'it'
        },
        @{
            Service = 'site-recovery'
            Prefix  = 'asr'
        },
        @{
            Service = 'virtual-machine-scale-sets'
            Prefix  = 'vmss'
        },
        @{
            Service = 'virtual-machines'
            Prefix  = 'vm'
        }
    )
    'container' = @(
        @{
            Service = 'aks'
            Prefix  = 'aks'
        },
        @{
            Service = 'container-registry'
            Prefix  = 'cr'
        }
    )
    'database' = @(
        @{
            Service = 'cosmosdb'
            Prefix  = 'cosmos'
        },
        @{
            Service = 'db-for-postgresql'
            Prefix  = 'psql'
        },
        @{
            Service = 'redis-cache'
            Prefix  = 'redis'
        },
        @{
            Service = 'sqldb'
            Prefix  = 'sqldb'
        }
    )
    'general' = @()
    'hybrid' = @()
    'integration' = @(
        @{
            Service = 'api-management'
            Prefix  = 'apim'
        },
        @{
            Service = 'event-grid'
            Prefix  = 'evg'
        },
        @{
            Service = 'event-hub'
            Prefix  = 'evhns'
        }
    )
    'iot' = @(
        @{
            Service = 'iot-hub'
            Prefix  = 'ioth'
        }
    )
    'management' = @(
        @{
            Service = 'automation-account'
            Prefix  = 'aa'
        },
        @{
            Service = 'management-group'
            Prefix  = 'mg'
        }
    )
    'migration' = @(
        @{
            Service = 'azure-backup'
            Prefix  = 'bk'
        }
    )
    'monitoring' = @(
        @{
            Service = 'application-insights'
            Prefix  = 'appi'
        },
        @{
            Service = 'log-analytics'
            Prefix  = 'log'
        }
    )
    'networking' = @(
        @{
            Service = 'application-gateway'
            Prefix  = 'agw'
        },
        @{
            Service = 'expressroute-circuits'
            Prefix  = 'erc'
        },
        @{
            Service = 'expressroute-gateway'
            Prefix  = 'erg'
        },
        @{
            Service = 'firewall'
            Prefix  = 'afw'
        },
        @{
            Service = 'front-door'
            Prefix  = 'afd'
        },
        @{
            Service = 'general-networking'
            Prefix  = 'nw'
        },
        @{
            Service = 'load-balancer'
            Prefix  = 'lb'
        },
        @{
            Service = 'network-security-group'
            Prefix  = 'nsg'
        },
        @{
            Service = 'network-watcher'
            Prefix  = 'nw'
        },
        @{
            Service = 'private-endpoints'
            Prefix  = 'pep'
        },
        @{
            Service = 'public-ip'
            Prefix  = 'pip'
        },
        @{
            Service = 'route-table'
            Prefix  = 'rt'
        },
        @{
            Service = 'traffic-manager'
            Prefix  = 'traf'
        },
        @{
            Service = 'virtual-networks'
            Prefix  = 'vnet'
        },
        @{
            Service = 'vpn-gateway'
            Prefix  = 'vpng'
        },
        @{
            Service = 'web-application-firewall'
            Prefix  = 'waf'
        }
    )
    'security' = @(
        @{
            Service = 'key-vault'
            Prefix  = 'kv'
        }
    )
    'specialized-workloads' = @()
    'storage' = @(
        @{
            Service = 'azure-netapp-files'
            Prefix  = 'anf'
        },
        @{
            Service = 'storage-account'
            Prefix  = 'st'
        }
    )
    'web' = @(
        @{
            Service = 'app-service-plan'
            Prefix  = 'asp'
        },
        @{
            Service = 'signalr'
            Prefix  = 'sigr'
        },
        @{
            Service = 'web-app'
            Prefix  = 'app'
        }
    )
}

$services.Keys | ForEach-Object -Process {
    $serviceCategory = $_

    $services[$serviceCategory] | ForEach-Object -Process {
        $service = $_.Service
        $prefix = $_.Prefix

        foreach ($queryId in 1..$MaxQueryIdToTry) {
            $uri = '{0}/{1}/{2}/code/{3}-{4}/{3}-{4}.kql' -f $repoBaseUriRaw, $serviceCategory, $service, $prefix, $queryId
            $subfolderPath = Join-Path -Path (Join-Path -Path $QueriesFolderPath -ChildPath $serviceCategory) -ChildPath $service
            $filePath = Join-Path -Path $subfolderPath -ChildPath ([IO.Path]::GetFileName($uri))
    
            try {
                $response = Invoke-WebRequest -Uri $uri -Method Get -UseBasicParsing -ErrorAction Stop
                $statusCode = [int] $response.StatusCode

                if ($statusCode -eq 200) {
                    Write-Host -Object ('Downloading query file from "{0}" to "{1}".' -f $uri, $filePath) -ForegroundColor Cyan
                    New-Item -ItemType Directory -Path $subfolderPath -Force | Out-Null
                    Set-Content -LiteralPath $filePath -Value $response.Content -Encoding UTF8 -Force
                    Write-Verbose -Message ('Successfully downloaded a query file to "{0}" from "{1}".' -f $filePath, $uri)
                }
                else {
                    Write-Waring -Message ('Failed to download a query file from "{0}" with status code {1}.' -f $uri, $statusCode)
                }
            }
            catch {
                $statusCodeOnException = [int] $_.Exception.Response.StatusCode
                if ($statusCodeOnException -eq 404) {
                    Write-Verbose -Message ('Reached to the 404 File Not Found on "{0}".' -f $uri)
                    break
                }
                else {
                    throw $_
                }
            }
        }
    }
}
