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
Set-Const GIT_PATH 'git'
$global:PUBLISH_DIR = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('./publish')

function Get-NugetGlobalPackagesPath {
    param (
        [string] $NugetPath = $global:NUGET_PATH
    )
    return (Invoke-Expression "$NugetPath locals global-packages -list" | Out-String).Replace("global-packages:", "").Trim()
}

Set-Const NUGET_PACKAGES_ROOT (Get-NugetGlobalPackagesPath)

function Get-NugetLocalFeedPath {    
    if (Test-Path 'D:\LocalNugetPackages') {
        return 'D:\LocalNugetPackages';
    }
    $nlfd = Join-Path $env:TEMP 'LocalNugetPackages'
    if (-not (Test-Path $nlfd)) {
        New-Item -ItemType Directory -Path $nlfd
    }
    return $nlfd
}

Set-Const NUGET_LOCAL_FEED (Get-NugetLocalFeedPath)

function Get-SolutionFile {
    param (
        [string] $BaseDir = './'
    )
    return (Get-ChildItem -Path $BaseDir -Filter '*.sln' -Recurse -ErrorAction Stop | Select-Object -First 1).FullName
}

function Write-Label {
    param (
        [string][Parameter(Mandatory=$true)] $Label
    )
    Write-Host ">>> $Label >>>" -ForegroundColor Yellow
}

function Get-LastExecErrorAndExitIfExists {
    param (
        [string][Parameter(Mandatory=$true)] $Message
    )
    if ($LastExitCode -ne 0) {
        Write-Host $Message -ForegroundColor Red
        Exit $LastExitCode
    }
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
    Get-ChildItem $Path -Include bin,obj,publish,packages -Recurse | ForEach-Object {
        Remove-Item $_.FullName -Force -Recurse -ErrorAction SilentlyContinue
    }
}

function Write-AdditionalAssemblyInfo {
    param (
        [string] $GitPath = $global:GIT_PATH
    )
    $commit = (& $GitPath rev-parse HEAD)
    if (($LastExitCode -eq 0) -and ($commit -ne '')) {
        $date = Get-Date -Format "yyyy-MM-ddTHH:mm:ssK"
        $content = "[assembly: System.Reflection.AssemblyConfiguration(""$commit|$date"")]"
        Get-ChildItem './src' -Include '*.csproj' -Recurse | ForEach-Object {
            $file = Join-Path (Split-Path $_.FullName) 'AssemblyInfoGenerated.cs'
            $content | Set-Content -Path $file -Force
        }        
    }
}

function Invoke-Tests {
    param (
        [Parameter(Mandatory=$true)][string] $ProjectPattern,
        [string] $DotnetPath = $global:DOTNET_PATH,
        [ValidateSet('Debug', 'Release')][string] $Configuration = 'Release',
        [ValidateSet('quiet', 'minimal', 'normal', 'detailed', 'diagnostic')][string] $Verbosity = 'minimal',
        [string] $Filter # https://docs.microsoft.com/en-us/dotnet/core/tools/dotnet-test#filter-option-details
    )
    Get-ChildItem './test' -Include $ProjectPattern -Recurse | ForEach-Object {
        $projName = [System.IO.Path]::GetFileNameWithoutExtension($_.FullName)
        Write-Debug "Running tests $projName"
        if ($Filter -ne '') {
            & $DotnetPath test $_.FullName -c $Configuration -v $Verbosity --filter $Filter --no-build --no-restore /nologo
        } else {
            & $DotnetPath test $_.FullName -c $Configuration -v $Verbosity --no-build --no-restore /nologo
        }
        Get-LastExecErrorAndExitIfExists "One or more tests have failed while running $projName"
    }
}

function Publish-NuGetPackages {
    param (
        [string] $NuGetApiKey,
        [string] $NugetPath = $global:NUGET_PATH,
        [string] $NugetFeedUrl = $global:NUGET_FEED_URL,
        [string] $PackageDir = $global:PUBLISH_DIR        
    )
    $NuGetApiKey = if ($NuGetApiKey -ne '') {$NuGetApiKey} else {$env:NUGET_APIKEY_EVENTR}
    if (-not $NuGetApiKey) {
        Write-Host 'NuGet API key is not provided. Either pass it explicitly or set environment property NUGET_APIKEY_EVENTR.' -ForegroundColor Red
        Exit 1
    }
    Get-ChildItem $PackageDir -Include '*.nupkg' -Recurse | ForEach-Object {
        $nugetFilename = Split-Path $_.FullName -Leaf
        Write-Debug "Publishing $nugetFilename to NuGet"
        & $NugetPath push $_.FullName -k $NuGetApiKey -s $NugetFeedUrl
    }
}

function Publish-NuGetPackagesLocally {
    param (
        [string] $NugetPath = $global:NUGET_PATH,
        [string] $PackageDir = $global:PUBLISH_DIR,
        [string] $NugetLocalFeed = $global:NUGET_LOCAL_FEED,
        [string] $NugetPackagesRoot = $global:NUGET_PACKAGES_ROOT         
    )
    [regex]$rx = "^(?<name>[^\d]+)\.(?<ver>\d+(\.\d+)+)\.nupkg$"
    Get-ChildItem $PackageDir -Include '*.nupkg' -Recurse | ForEach-Object {
        $nugetFilename = Split-Path $_.FullName -Leaf
        $match = $rx.Match($nugetFilename)
        $name = $match.Groups['name'].Value
        $ver = $match.Groups['ver'].Value
        (& $NugetPath delete $name $ver -Source $NugetPackagesRoot -NonInteractive -Verbosity quiet) | Out-Null
        (& $NugetPath delete $name $ver -Source $NugetLocalFeed -NonInteractive -Verbosity quiet) | Out-Null
        & $NugetPath add $_.FullName -Source $NugetLocalFeed -NonInteractive
    }
}