################################################################################################################################################################################
# Script to setup a load test for Power BI Reports
#-------------------------------------------------------------------
#
# PRE-REQUISITES:
# ---------------
# Access to PowerBI Service
# One or more reports deployed to a group workspace (not My Workspace)
# Script requires "RealisticLoadTest.html", "PBIReport.JSON" and "PBIToken.JSON" files provided in the package.
# 
# Expected Result:
# ----------------
# Once the inputs are provided, script will save a folder in the current working directory for each report with copy of above mentioned files configured with respective inputs.
# You should manually edit the PBIReport.JSON file in each subdirectory further define the configuration of that load test. Feel free to rename the subdirectories to a meaningful name.
################################################################################################################################################################################

#Variables declaration
$destinationDir = ''
$workingDir = $pwd.Path
$masterFilesExists = $true
$multiReportConfiguration = $true
$htmlFileName = 'RealisticLoadTest.html'
$filtersFileName = 'Filters.json' #MK specify the name of the file that contains the filters
$pageFileName = 'Page.json' #MK specify the name of the file that contains the page
$bookmarksFileName = 'Bookmarks.json' #MK specify the name of the file that contains the bookmarks
$reportConfig = @{}
$reports = @()
$user = @{}

# Regular expressions to match and update JSON files
$token_regex = '(?<=PBIToken\":\s*\").*?(?=\")'
$reportUrlRegex = '(?<=reportUrl\":\s*\").*?(?=\")'
$pageIDRegex = '\/\/"pageName".*"' # MK find page id parameter
$bookmarksRegex = '\/\/"bookmarkList".*]' # MK find bookmarks parameter
$noViewsRegex = '"numberOfViews":\s*(\d+),' # MK find number of views parameter
$filtersRegex = '"filters".*]' #MK find filters parameter
$thinkTimeRegex = '"thinkTimeSeconds":\s*(\d+),' # MK find think time parameter
$projectNameRegex = '"projectName":.*"'# MK find project name parameter

$noUsersRegex = '"numberOfUsers":\s*(\d+),' # ML find number of users parameter
$skuRegex = '"sku":.*"' # MK find sku parameter

#Function implementation to update token file
function UpdateTokenFile
{     
    $accessToken = Get-PowerBIAccessToken -AsString | % {$_.replace("Bearer ","").Trim()}
    $tokenJSONFile = Get-Content $(Join-Path $workingDir 'PBIToken.JSON') -raw;
    $new_TokenJSONFile = ($tokenJSONFile -replace $token_regex,$accessToken)
    $new_TokenJSONFile
    $destinationDir
    $new_TokenJSONFile | set-content $(Join-Path $destinationDir 'PBIToken.JSON')
}

#Function implementation to update report parameters file
function UpdateReportParameters
{
    $reportJSONFile = Get-Content $(Join-Path $workingDir 'PBIReport.JSON') -raw;
    $new_ReportJSONFile = ($reportJSONFile -replace $reportUrlRegex,$args[0]);
    $new_ReportJSONFile = ($new_ReportJSONFile -replace $noViewsRegex,('"numberOfViews": ' + $args[1] + ',')); # MK set number of views based on user input
    $new_ReportJSONFile = ($new_ReportJSONFile -replace $thinkTimeRegex,('"thinkTimeSeconds": '+ $args[2] + ',')); # MK set think time based on user input
    $new_ReportJSONFile = ($new_ReportJSONFile -replace $projectNameRegex,('"projectName": "' + $args[3] + '"')); # MK set think time based on user input

    $new_ReportJSONFile = ($new_ReportJSONFile -replace $noUsersRegex,('"numberOfUsers": ' + $args[4] + ',')); # ML set numbers of users based on user input
    $new_ReportJSONFile = ($new_ReportJSONFile -replace $skuRegex,('"sku": "' + $args[5] + '"')); # ML set capacity SKU based on workspace capacity

    $filtersJSONFile = Get-Content $(Join-Path $workingDir $filtersFileName) -raw; #MK get filters from the filter file
    $pageJSONFile = Get-Content $(Join-Path $workingDir $pageFileName) -raw; #MK get filters from the filter file
    $bookmarksJSONFile = Get-Content $(Join-Path $workingDir $bookmarksFileName) -raw; #MK get filters from the filter file
    #Write-Host $filtersJSONFile; #MK test to check filter file content
    $new_ReportJSONFile = ($new_ReportJSONFile -replace $filtersRegex, $filtersJSONFile); # MK add predefined filters to the reportJSON filter
    $new_ReportJSONFile = ($new_ReportJSONFile -replace $pageIDRegex, $pageJSONFile);
    $new_ReportJSONFile = ($new_ReportJSONFile -replace $bookmarksRegex, $bookmarksJSONFile);
    $new_ReportJSONFile
    $destinationDir
    $new_ReportJSONFile | set-content $(Join-Path $destinationDir 'PBIReport.JSON')
}

#verify if current working directory have master files. If not, prompt user for path of the files.
while($masterFilesExists)
{
    if(!(Test-Path -path $(Join-Path $workingDir $htmlFileName)) -and !(Test-Path -path $(Join-Path $workingDir 'PBIReport.JSON')) -and !(Test-Path -path $(Join-Path $workingDir 'PBIToken.JSON')))
    {
        Write-Host "The current working directory ($workingDir) doesn't have the master files required to proceed further." -ForegroundColor Yellow
        $workingDir = Read-Host -Prompt "Enter the directory path having master files"
    }
    else
    {     
     $masterFilesExists = $false   
    }
}

[int]$reportCount = Read-Host "How many reports you want to configure?"
[int]$noViews = Read-Host "How many views you want to generate per report?"
[int]$noUsers = Read-Host "How many users do you want to replicate?"
[int]$thinkTime = Read-Host "How much think time between interaction? (sec)"
$projectName = Read-Host "What is the name of the project?"
$increment = 1
while($reportCount -gt 0)
{
    Write-Host "Gathering inputs for report $increment" -ForegroundColor Red
    
    # Get required inputs from user
    Write-Host "Select Id to authenticate to Power BI" -ForegroundColor Yellow
    $user = Login-PowerBI
    $user

    #Accessing list of workspaces
    $workSpaceList = Get-PowerBIWorkspace
    #can add my workspace and then not specify the WorkspaceId switch when we list reports below... TODO


    $workSpaceCounter = 1
    foreach($workSpace in $workSpaceList)
    {
        Write-Host "[$($workSpaceCounter)]" -ForegroundColor Yellow -NoNewline
        Write-Host " - $($workSpace.Id) - $($workSpace.Name)" -ForegroundColor Green
        ++$workSpaceCounter
    }

    $workSpaceSelection = Read-Host "
    
    Select Work space index from above"

    #Get the capacity SKU being used

    Write-Host "
    Retrieving capacity information...
    "
    
    $WorkspaceCapacityId = (Get-PowerBIWorkspace -Id $($workSpaceList[$workSpaceSelection-1].Id)).CapacityId
    $Capacity = (Get-PowerBICapacity | where Id -eq $WorkspaceCapacityId).DisplayName
    $CapacitySku = (Get-PowerBICapacity | where Id -eq $WorkspaceCapacityId).Sku

    if ($null -eq $WorkspaceCapacityId)
    {
        Write-Host "
        No capacity detected, or you do not have sufficient access.
        "
    }
    else
    {
    Write-Host "Workspace is using Capacity $($Capacity) with SKU $($CapacitySku)"
    }

    #Accessing reports from selected work space
    Write-Host "Listing all reports from the selected work space" -ForegroundColor Yellow
    $reportList = Get-PowerBIReport -WorkspaceId $($workSpaceList[$workSpaceSelection-1].Id)

    $reportCounter = 1
    foreach($report in $reportList)
    {
        Write-Host "[$($reportCounter)]" -ForegroundColor Yellow -NoNewline
        Write-Host " - $($report.Id) - $($report.Name)" -ForegroundColor Green
        ++$reportCounter
    }

    $reportSelection = Read-Host "Select report index from above"

    $reportUrl = $($reportList[$reportSelection-1].EmbedUrl) #Read-Host -Prompt 'Enter Report Embed URL'
    $reportName = $($reportList[$reportSelection-1].Name)
    $workspaceName = $($workspaceList[$workspaceSelection-1].Name)
    $reportList[$reportSelection-1]


    #Creating sub-folder to create a report set
    $currentDate = get-date -f MM-dd-yy_HHmmss
    $destinationDir = new-item -Path $workingDir -Name "$($workspaceName) - $($reportName) - $($currentDate)" -ItemType directory

    #Copy master html file into the new directory
    Copy-Item $(Join-Path $workingDir $htmlFileName) -Destination $destinationDir

    #Function call to update Token file
    UpdateTokenFile

    #Function call to update report parameters file
    UpdateReportParameters $reportUrl $noViews $thinkTime $projectName $noUsers $CapacitySku
    
    $reportConfig.WorkSpace = $($workSpaceList[$workSpaceSelection-1].Name)
    $reportConfig.ReportName = $($reportList[$reportSelection-1].Name)
    $reportConfig.ConfiguredReportPath = $(Join-Path $destinationDir $htmlFileName)
    $reportConfig.SessionsToRun = $instances
    
    $reports += New-Object PSobject -Property $reportConfig
    --$reportCount
    $increment++
}
Write-Host "Listing reports configuration" -ForegroundColor Yellow
$reports | Format-Table -AutoSize

"You should manually edit the PBIReport.JSON file in each subdirectory further define the configuration of that load test. Feel free to rename the subdirectories to a meaningful name."

"When ready, run Run_Load_Test_Only.ps1 to launch the test"

"At least every 60 minutes you will need to run Update_Token_Only.ps1"


