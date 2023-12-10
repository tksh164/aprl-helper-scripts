# APRL helper scripts

Three helper scripts for the Azure Proactive Resiliency Library (APRL) KQL queries.

- The `getqueries.ps1` downloads APRL's KQL queries from the [APRL GitHub repository](https://github.com/Azure/Azure-Proactive-Resiliency-Library). Downloaded queries are stored in the `queries` folder in the current directory. The `queries` folder will be created if it does not exist.

- The `runqueries.ps1` executes the downloaded KQL queries in the `queries` folder against your Azure subscription.

    You must have completed [Connect-AzAccount](https://learn.microsoft.com/en-us/powershell/module/az.accounts/connect-azaccount) and [Set-AzContext](https://learn.microsoft.com/en-us/powershell/module/az.accounts/set-azcontext) correctly before run this script.
    
    This script requires [Az.ResourceGraph](https://www.powershellgallery.com/packages/Az.ResourceGraph), [Az.Accounts](https://www.powershellgallery.com/packages/Az.Accounts) and [Az.Resources](https://www.powershellgallery.com/packages/Az.Resources) modules. You can install those modules by the following command if you have not installed these modules.

    ```powershell
    Install-Module -Name 'Az.ResourceGraph', 'Az.Accounts', 'Az.Resources' -Repository 'PSGallery' -Scope AllUsers -Force
    ```

- The `saveascsv.ps1` saves the output from `runqueries.ps1` as CSV file. The default output file path is `./results.csv`.


## Prerequisites

- [Latest PowerShell](https://github.com/PowerShell/PowerShell) or Windows PowerShell 5.1
- The scripts tested on Windows, but the scripts may be run on other platforms as well. Feedback is welcome.


## Quick start

1. Download the APRL's KQL queries to your local filesystem.

    ```powershell
    PS C:\aprl> .\getqueries.ps1
    ```

2. Execute the APRL's KQL queries then save the result to the `./results.csv` file.

    ```powershell
    PS C:\aprl> .\runqueries.ps1 | .\saveascsv.ps1
    ```


## Usage examples

### getqueries.ps1

- Download the APRL's KQL queries to local filesystem.

    ```powershell
    PS C:\aprl> .\getqueries.ps1
    ```

### runqueries.ps1 and saveascsv.ps1

- Execute the APRL's KQL queries without saving the result to a file.

    ```powershell
    PS C:\aprl> .\runqueries.ps1
    ```

- Execute the APRL's KQL queries then showing the result in grid view.

    ```powershell
    PS C:\aprl> .\runqueries.ps1 | Out-GridView
    ```

- Execute the APRL's KQL queries then save the result to a CSV file using the standard PowerShell cmdlets.

    ```powershell
    PS C:\aprl> .\runqueries.ps1 | ConvertTo-Csv -NoTypeInformation | Out-File -LiteralPath './results.csv' -Encoding utf8 -Force
    ```

- Execute the APRL's KQL queries then save the result to a CSV file using the `saveascsv.ps1` script.

    ```powershell
    PS C:\aprl> .\runqueries.ps1 | .\saveascsv.ps1
    ```

## License

Copyright (c) 2023-present Takeshi Katano. All rights reserved. This software is released under the [MIT License](https://github.com/tksh164/aprl-helper-scripts/blob/main/LICENSE).

Disclaimer: The codes stored herein are my own personal codes and do not related my employer's any way.
