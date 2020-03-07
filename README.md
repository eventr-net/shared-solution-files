# Shared Solution Files
Contains files shared throughout the rest of projects within eventr

## Installation
- In new repository add **shared-solution-file** as git submodule; execute `git submodule add -b master git@github.com:eventr-net/shared-solution-files.git shared-solution-files`.
- Some files need to be copied to root of the repository; use `install_to_parent.ps1` script.
- Some files are used from within submodule directory (`functions.ps1`, `eventr.ruleset`, etc.)
- Others are templates (`src/Directory.Build.props`) that you can use at your leisure or not at all. You need to copy them manually at appropriate places and then you can modify them.
