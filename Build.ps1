
$ModuleName = "F7History"
$ModulePath = "./Output/${ModuleName}"

# Assume this is the first build
$build = 0

$psd1Content = Get-Content $($ModulePath + "/$($ModuleName).psd1") -Raw -ErrorAction SilentlyContinue
if ($psd1Content) {
    # Extract the ModuleVersion from the .psd1 content using regular expression
    if ($psd1Content -match "ModuleVersion\s+=\s+'(.*?)'") {
        $prevVersion = $Matches[1]
        $prevVersionParts = $prevVersion -split '\.'
        $build = [int]$prevVersionParts[3] + 1
        $ModuleVersion = "{0}.{1}.{2}.{3}" -f $prevVersionParts[0], $prevVersionParts[1], $prevVersionParts[2], $build
    } else {
       throw "ModuleVersion not found in the old .psd1 file."
    }
} else {
    "No previous version found. Assuming this is the first build."
    # Get the ModuleVersion using dotnet-gitversion
    $prevVersion = dotnet-gitversion /showvariable MajorMinorPatch
    $ModuleVersion = "$($prevVersion).$($build)"
}

# Ensure latest ConsoleGuiTools
$PsdPath = "./Source/$($ModuleName).psd1"
$ocgvModule = "Microsoft.PowerShell.ConsoleGuiTools"
"Patching $PsdPath with latest ConsoleGuiTools version"
$psd1Content = Get-Content $PsdPath -Raw -ErrorAction SilentlyContinue
if ($psd1Content -match "RequiredVersion\s+=\s+'(.*?)'\s+# Generated by Build.ps1") {
    "Found $ocgvModule RequiredVersion in ${PsdPath}: ${Matches[1]}"

    # Find new version of ConsoleGuiTools in 'local' repository
    $localRepository = Get-PSRepository | Where-Object { $_.Name -eq 'local' }
    if ($localRepository) {
        $localRepositoryPath = $localRepository | Select-Object -ExpandProperty SourceLocation
        $ocgvVersion = Get-ChildItem "${localRepositoryPath}/${ocgvModule}*.nupkg" | Select-Object -ExpandProperty Name | Sort-Object -Descending | Select-Object -First 1
        if ($ocgvVersion -match "$ocgvModule.(.*?).nupkg") {
            $ocgvVersion = $Matches[1]
        } else {
            throw "No $ocgvModule packages found in ${localRepository}."
        }
        "Latest '$ocgvModule` in 'local' repository: " + $ocgvVersion

    } else {
        throw "Local repository not found."
    }

    "Rewriting $PsdPath with new Required `Microsoft.PowerShell.ConsoleGuiTools` Version: $ocgvVersion"
    $updatedpsd1Content = $psd1Content -replace "'(.*?)'\s+# Generated by Build.ps1", "'$ocgvVersion' # Generated by Build.ps1"
    $updatedpsd1Content | Out-File -FilePath $PsdPath -Encoding ascii
} else {
   throw "RequiredVersion not found in the old .psd1 file."
}

"New ModuleVersion: $ModuleVersion"

$OldModule = Get-Module $ModuleName -ErrorAction SilentlyContinue
if ($OldModule) {
    "Removing $ModuleName $($OldModule.Version)"
    Remove-Item $ModulePath -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
    Remove-Module Microsoft.PowerShell.ConsoleGuiTools
    Uninstall-Module -Name $ModuleName -Force -ErrorAction SilentlyContinue
}

$localRepository = Get-PSRepository | Where-Object { $_.Name -eq 'local' }
if ($localRepository) {    
    $localRepositoryPath = $localRepository | Select-Object -ExpandProperty SourceLocation
    "  Un-publishing $ModuleName $($OldModule.Version) from local repository at $localRepositoryPath"
    Remove-Item "${localRepositoryPath}/${ModuleName}*.nupkg" -Recurse -Force -ErrorAction SilentlyContinue
}

"Building $ModuleName $ModuleVersion to $ModulePath"
Build-Module -SemVer $ModuleVersion -OutputDirectory ".${ModulePath}" -SourcePath ./Source

if ($localRepository) {    
    "  Removing  $ModuleName"
    Remove-Module $ModuleName -Force -ErrorAction SilentlyContinue
    "  Publishing  $ModuleName to local repository at $localRepositoryPath"
    Publish-Module -Path $ModulePath -Repository 'local' -ErrorAction Stop
    "  Installing  $ModuleName to local repository at $localRepositoryPath"
    Install-Module -Name $ModuleName -Repository 'local' -Force
    Import-Module $ModuleName 
    "$ModuleName $(Get-Module $ModuleName | Select-Object -ExpandProperty Version) installed and imported."
}

