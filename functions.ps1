function Set-Const {
    param (
        [string][Parameter(Mandatory=$true)] $Name,
        [Parameter(Mandatory=$true)] $Value
    )
    if (-not (Test-Path variable:global:$Name)) {
        Set-Variable $Name -Scope Global -Option Constant -Value $Value
    } else {
        Write-Debug "const $Name is already defined"
    }
}

Set-Const DOTNET_PATH 'dotnet'
Set-Const NUGET_PATH 'nuget'
Set-Const NUGET_FEED_URL 'https://api.nuget.org/v3/index.json'
Set-Const PUBLISH_DIR ($ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('./publish'))

function Get-NugetGlobalPackagesPath {
    param (
        [string] $NugetPath = $global:NUGET_PATH
    )
    return (Invoke-Expression "$NugetPath locals global-packages -list" | Out-String).Replace("global-packages:", "").Trim()
}

Set-Const NUGET_PACKAGES_ROOT (Get-NugetGlobalPackagesPath)

function Write-Label {
    param (
        [string][Parameter(Mandatory=$true)] $Label
    )
    Write-Host ">>> $Label >>>" -ForegroundColor Yellow
}

function Write-NugetInfo {
    param (
        [string] $NugetPath = $global:NUGET_PATH
    )
    $NugetVersion = ((Invoke-Expression "$NugetPath help") | Select-Object -First 1 | Out-String).Replace("NuGet Version:", "").Trim()
    Write-Host "NuGet: $NugetPath ($NugetVersion)"
    Write-Host "NuGet locals:"
    (Invoke-Expression "$NugetPath locals all -list") | Write-Host -ForegroundColor DarkGray
}

function Write-DotnetInfo {
    param (
        [string] $DotnetPath = $global:DOTNET_PATH
    )
    $DotnetVersion = ((Invoke-Expression "$DotnetPath --version") | Out-String).Trim()
    Write-Host "Dotnet CLI: $DotnetPath ($DotnetVersion)"
}

function Write-BuildInfo {
    param (
        [string] $DotnetPath = $global:DOTNET_PATH,
        [string] $NugetPath = $global:NUGET_PATH,
        [string] $NugetPackagesRoot = $global:NUGET_PACKAGES_ROOT,
        [string] $PublishDir = $global:PUBLISH_DIR
    )
    Write-Host '>>> Build info >>>' -ForegroundColor Yellow
    $stack = Get-PSCallStack
    $firstFrame = $stack[($stack.Count - 1)]
    $cmdLine = $firstFrame.Position.Text
    Write-Host "Command: $cmdLine"
    Write-Host ("Running as: " + [System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
    Write-Host "Output: $PublishDir"
    Write-DotnetInfo -DotnetPath $DotnetPath
    Write-Host "NugetPackagesRoot: $NugetPackagesRoot"
    Write-NugetInfo -NugetPath $NugetPath
}

function Clear-SolutionDirectory {
    param (
        [string] $Path = './'
    )
    Write-Host '>>> Cleaning solution >>>' -ForegroundColor Yellow
    Get-ChildItem $Path -Include bin,obj,publish,packages -Recurse | ForEach-Object {
        Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
    }
}

function Publish-NuGetPackages {
    param (
        [string] $NuGetApiKey,
        [string] $NugetPath = $global:NUGET_PATH,
        [string] $NugetFeedUrl = $global:NUGET_FEED_URL,
        [string] $PackageDir = $global:PUBLISH_DIR        
    )
    $NuGetApiKey = if ($NuGetApiKey -ne '') {$NuGetApiKey} else {Get-Childitem env:NUGET_APIKEY_EVENTR}
    if (-not $NuGetApiKey) {
        Write-Error 'NuGet API key is not provided. Either pass it explicitly or set environment property NUGET_APIKEY_EVENTR.'
        Exit 1
    }

    Get-ChildItem $PackageDir -Include '*.nupkg' | ForEach-Object {
        $nugetFilename = Split-Path $_.FullName -Leaf
        Write-Host ">>> Publishing $nugetFilename to NuGet >>>" -ForegroundColor Yellow
        & $NugetPath push $_.FullName -k $NuGetApiKey -s $NugetFeedUrl
    }
}