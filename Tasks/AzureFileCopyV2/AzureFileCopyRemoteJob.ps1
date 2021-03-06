$AzureFileCopyRemoteJob = {
    param(
        [string]$containerURL,
        [string]$targetPath,
        [string]$containerSasToken,
        [string]$additionalArguments,
        [string]$azCopyToolFileNamesString,
        [string]$azCopyToolFileContentsString,
        [switch]$CleanTargetBeforeCopy,
        [switch]$EnableDetailedLogging
    )

    function Write-DetailLogs
    {
        [CmdletBinding()]
        param(
            [string]$message
        )

        if($EnableDetailedLogging)
        {
            Write-Verbose $message
        }
    }

    function Get-AzCopyVerboseLogs
    {
        [CmdletBinding()]
        param(
            [bool]$isLogsPresent,
            [string]$logFilePath
        )

        if($isLogsPresent)
        {
            Write-DetailLogs (Get-Content -Path $logFilePath | Out-String)
        }
    }

    function Remove-AzCopyFolder
    {
        [CmdletBinding()]
        param([string]$azCopyLocation)

        $tempParentFolder = (Get-Item $azCopyLocation).Parent.FullName

        Get-ChildItem -Path $azCopyLocation -Recurse -Force | Remove-Item -Force -Recurse
        Remove-Item $azCopyLocation -Force
        Remove-Item $tempParentFolder -Force
    }

    try
    {
        $azCopyToolFileNames = $azCopyToolFileNamesString.Split(";")
        $azCopyToolFileContents = $azCopyToolFileContentsString.Split(";")

        $randomFolderName = "AFC_" + [guid]::NewGuid()
        $randomFolderPath = Join-Path -Path $env:windir -ChildPath "DtlDownloads\$randomFolderName"
        $azCopyDestinationPath = Join-Path -Path $randomFolderPath -ChildPath "AzCopy"

        Write-DetailLogs "Copying AzCopy tool files to location: $azCopyDestinationPath"
        New-Item -ItemType Directory -Force -Path $azCopyDestinationPath

        for($i=0; $i -lt $azCopyToolFileNames.Length; $i++)
        {
            $path = Join-Path -Path $azCopyDestinationPath -ChildPath $azCopyToolFileNames[$i]
            $content = [Convert]::FromBase64String($azCopyToolFileContents[$i])
            [System.IO.File]::WriteAllBytes($path, $content)
        }

        Write-DetailLogs "Copied AzCopy tool files"

        if($CleanTargetBeforeCopy)
        {
            Get-ChildItem -Path $targetPath -Recurse -Force | Remove-Item -Force -Recurse
            Write-DetailLogs "Destination location cleaned"
        }

        $azCopyExeLocation = Join-Path -Path $azCopyDestinationPath -ChildPath "AzCopy.exe"

        $logFileName = "AzCopyVerbose_" + [guid]::NewGuid() + ".log"
        $logFilePath = Join-Path -Path $azCopyDestinationPath -ChildPath $logFileName
        $useDefaultArguments = ($additionalArguments -eq "")

        if($useDefaultArguments)
        {
            # Adding default optional arguments:
            # /Z: Journal file Location
            # /V: AzCopy verbose logs file location
            # /S: Recursive copy
            # /Y: Suppresses all AzCopy confirmation prompts

            Write-DetailLogs "Using default AzCopy arguments for dowloading to VM"
            $additionalArguments = "/Z:`"$azCopyDestinationPath`" /V:`"$logFilePath`" /S /Y"
        }

        Write-DetailLogs "Executing command: & `"$azCopyExeLocation`" /Source:$containerURL /Dest:`"$targetPath`" /SourceSAS:`"*****`" $additionalArguments"

        $azCopyCommand = "& `"$azCopyExeLocation`" /Source:$containerURL /Dest:`"$targetPath`" /SourceSAS:`"$containerSasToken`" $additionalArguments"
        Invoke-Expression $azCopyCommand
    }
    catch
    {
        Write-Verbose "AzureFileCopyRemoteJob threw exception"
        throw
    }
    finally
    {
        # Print AzCopy.exe verbose logs
        Get-AzCopyVerboseLogs -isLogsPresent $useDefaultArguments -logFilePath $logFilePath -ErrorAction SilentlyContinue

        # Delete AzCopy tool folder
        Remove-AzCopyFolder -azCopyLocation $azCopyDestinationPath -ErrorAction SilentlyContinue
    }
}