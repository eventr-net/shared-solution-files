Push-Location (Split-Path -Path $MyInvocation.MyCommand.Definition -Parent)
Copy-Item '.gitattributes' -Destination '..' -Force
Copy-Item '.gitignore' -Destination '..' -Force
Copy-Item '.editorconfig' -Destination '..' -Force
Copy-Item 'LICENSE' -Destination '..' -Force
Copy-Item 'CODEOWNERS' -Destination '..' -Force
$BuildDest = '..\build.ps1'
if (-not (Test-Path -Path $BuildDest)) {
    Copy-Item 'build-template.ps1' -Destination $BuildDest
}
Pop-Location