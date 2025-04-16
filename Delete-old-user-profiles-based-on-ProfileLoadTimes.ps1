# DELETE OLD USER PROFILES BASED ON LocalProfileLoadTime and LocalProfileUnLoadTime IN WINDOWS REGISTRY

# - Gets a list of user profiles
# - Gets LocalProfileLoadTime and LocalProfileUnLoadTime for every profile
# - Tests if user is a domain user
# - Checks if username matches $ExcludeUsersList
# - Removes user profile from the list if not domain user, is exluded or if cannot get LocalProfileLoadTime and LocalProfileUnLoadTime
# - Tests if LocalProfileLoadTime and LocalProfileUnLoadTime are older than $MaxAgeInDays days.
# - Removes newer user profiles from the list
# - Deletes all user profiles which are still remaining and not filtered
   

# Skip user names
$ExcludeUsersList = @("asennus", "*ire", "mike", "*admin*")

# Delete profiles not used in $MaxAgeInDays
$MaxAgeInDays = 365*2

# Domain name. Checked against DOMAIN\username
$DomainName= "domain"

# 0 = ask user to confirm user file deletion.
$NoConfirm = 0

# ---------------------------------------------------------------------------------------------------------------------------------------------

# Get domain name, command Get-ADDomain not available by default
#$DomainName=Get-ADDomain -Current LocalComputer | Select-Object -ExpandProperty Name

# Add current users username to the list
$CurrentUserName=$env:username
$ExcludeUsersList = $ExcludeUsersList + $CurrentUserName

write-host "TEST 1 AND 2. Check if username is domain user and is not in exclude list." -ForegroundColor Green
write-host ""
write-host "Excluded usernames:"
$ExcludeUsersList
write-host ""

# Make an empty array
$profileInfos = @()

# How to get LoadTime and UnLoadTime: https://woshub.com/delete-old-user-profiles-gpo-powershell/
$profilelist = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList"
foreach ($p in $profilelist) {
    try {
        $objUser = (New-Object System.Security.Principal.SecurityIdentifier($p.PSChildName)).Translate([System.Security.Principal.NTAccount]).value
    } catch {
        $objUser = "[UNKNOWN]"
  }
    Remove-Variable -Force LTH,LTL,UTH,UTL -ErrorAction SilentlyContinue
    $LTH = '{0:X8}' -f (Get-ItemProperty -Path $p.PSPath -Name LocalProfileLoadTimeHigh -ErrorAction SilentlyContinue).LocalProfileLoadTimeHigh
    $LTL = '{0:X8}' -f (Get-ItemProperty -Path $p.PSPath -Name LocalProfileLoadTimeLow -ErrorAction SilentlyContinue).LocalProfileLoadTimeLow
    $UTH = '{0:X8}' -f (Get-ItemProperty -Path $p.PSPath -Name LocalProfileUnloadTimeHigh -ErrorAction SilentlyContinue).LocalProfileUnloadTimeHigh
    $UTL = '{0:X8}' -f (Get-ItemProperty -Path $p.PSPath -Name LocalProfileUnloadTimeLow -ErrorAction SilentlyContinue).LocalProfileUnloadTimeLow
    $LoadTime = if ($LTH -and $LTL) {
        # File times
        [datetime]::FromFileTimeUtc("0x$LTH$LTL") # Filetime is ticks since midnight January 1st 1601 (UTC).
        $LoadTimeHex = "0x$LTH$LTL"
    } else {
        $null
    }
    $UnloadTime = if ($UTH -and $UTL) {
        # File times
        [datetime]::FromFileTimeUtc("0x$UTH$UTL")
        $UnloadTimeHex = "0x$UTH$UTL"
    } else {
        $null
    }

    # Split by \ and take the last element.
    # Split account to half. DOMAIN\username -> DOMAIN and username.
    $UserName =  ($objUser -split "\\")[-1]
    $AccountPrefix = ($objUser -split "\\")[0]

    # Profile path. 
    $ProfileImagePath = (Get-ItemProperty -Path $p.PSPath -Name ProfileImagePath -ErrorAction SilentlyContinue).ProfileImagePath

    # TEST 1. Test if username is in exclude list.
    $Exclude = $false # Default
    ForEach ($AA in $ExcludeUsersList) {
        # * as a first character cauces an error 'parsing "*admin" - Quantifier {x,y} following nothing.' Adding prefix A fixex this.
        if ("A$UserName" -match "A$AA") {
           write-host "Username $UserName matches with exclude list ($AA). Set Exlude = $true"
           $Exclude = $true
        }
    }

    # TEST 2. Test if the account is a domain account. If not skip user profile with continue commamnd
    if ($AccountPrefix -eq $DomainName) {
        write-host "Account $objUser is a domain account."
    } else {
        write-host "Account $objUser is NOT a domain account. Set Exlude = $true"
        $Exclude = $true
    }

    # Add each profile with info to $profileInfos.
    $profileInfos += [pscustomobject][ordered]@{
        User = $objUser
        UserName = $UserName
        SID = $p.PSChildName
        Loadtime = $LoadTime
        LoadtimeHex = $LoadTimeHex
        UnloadTime = $UnloadTime
        UnloadTimeHex = $UnloadTimeHex
        AgeInDays = $null
        Exclude = $Exclude
        Delete = $null
        ProfileImagePath = $ProfileImagePath
    }
} 

write-host ""
write-host Profile count before exclusion is @($profileInfos).count

# Remove excluded user profiles and if file converterd to date time is $null.
$profileInfos = $profileInfos | Where-Object {$_.Exclude -ne $true} |  Where-Object {$_.LoadTime -ne $null} |  Where-Object {$_.UnLoadTime -ne $null}
$profileInfos

write-host Profile count after exclusion is @($profileInfos).count
write-host ""


# TEST 3. Test if user has not logged in or out in $MaxAgeInDays days.
write-host "TEST 3. Check if user has loggeg in or out in $($MaxAgeInDays) days" -ForegroundColor Green
write-host ""

# List profile if LoadTime or UnLoadTime unavailable.
if ( ($profileInfos | Where-Object {$_.LoadTime -eq $null -or $_.UnLoadTime -eq $null}).count -gt 0) {
    Write-Host LoadTime or UnLoadTime could not be found for the following profiles
    $profileInfos | Where-Object {$_.LoadTime -eq $null -or $_.UnLoadTime -eq $null}
}


$TimeNow = [datetime]::UtcNow # UTC
$TimeNowHex = ("{0:x}" -f $TimeNow.ToFileTime()).ToUpper()
foreach ($profile in $profileInfos) {
    write-host "$($profile.user)"
    write-host "LoadTime is $($profile.Loadtime) ($($profile.LoadtimeHex)), UnLoadTime is $($profile.UnLoadtime) ($($profile.UnLoadtimeHex)) "
    write-host "UtcNow is $($TimeNow) (0x$TimeNowHex)"
    $LargestDate = (get-date $profile.UnLoadtime), (get-date $profile.Loadtime) | sort-object | Select-Object -Last 1
    write-host "Largest of Loadtime and UnLoadtime is $LargestDate"
    $TimeDifference = $TimeNow - $LargestDate
    $profile.AgeInDays = $TimeDifference.TotalDays
    write-host "User has logged in or out $([math]::round($TimeDifference.TotalDays, 3)) days ago."

    # If TimeDifferent is over $MaxAgeInDays mark user profile for deletion.
    if ($TimeDifference.TotalDays -gt $MaxAgeInDays) {
        write-host "This is more than $($MaxAgeInDays) days. Profile IS marked for deletion." -ForegroundColor Red
        $profile.Delete = $true
    } else {
        $profile.Delete = $false
        write-host "This is less than $($MaxAgeInDays) days. Profile is NOT deleted."

    }
    write-host ""
}
# For safety let's remove all userprofile object which are not marked for deletion.
$profileInfos = $profileInfos | Where-Object {$_.Delete -eq $true}
$profileInfos
write-host Profile count after age check is @($profileInfos).count
write-host ""


# DELETION
write-host "DELETION of profiles older than  $($MaxAgeInDays) days" -ForegroundColor Green
write-host "Following profiles will be deleted!"

if ( @($profileInfos).count -le 0 ) { write-host ""; write-host "No profiles to delete!" -BackgroundColor DarkGreen }
else {

    $profileSizeGBAll = 0

    foreach ($profile in $profileInfos) {
        write-host "$($profile.username) "  -NoNewLine -ForegroundColor Red
        write-host "(age $([math]::round($profile.AgeInDays, 3)) days) "  -NoNewLine
        $profileSizeGB= (Get-ChildItem $profile.ProfileImagePath -Recurse -Force -ErrorAction SilentlyContinue |  Measure-Object -Property Length -Sum).sum/1GB
        $profileSizeGBAll += $profileSizeGB
        write-host "(size $([math]::round($profileSizeGB, 3)) GB) "
    }
    Write-Host "TOTAL SIZE: $([math]::round($profileSizeGBAll, 3)) GB"
}

write-host ""

# Confirm or not
if ($NoConfirm -eq 0) {
    # https://stackoverflow.com/questions/24649019/how-to-use-confirm-in-powershell
    while( -not ( ($choice = (Read-Host "Do you want to continue?")) -match "^(y|n)$")){ "Y or N ?"}
    if ($choice -eq "n" ) {
        write-host "Exiting..."
        Start-Sleep 2
        EXIT
    }
    write-host ""
}

foreach ($profile in $profileInfos) {
    if ($profile.Delete -eq $true) {
        #Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.SID -eq '$($Profile.SID)' } | Remove-CimInstance
        write-host "Deleting $($profile.user), SID=$($profile.SID)"
        write-host "Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.SID -eq "$($Profile.SID)" } "
        Get-CimInstance -Class Win32_UserProfile | Where-Object { $_.SID -eq "$($profile.SID)" } | Remove-CimInstance
    }

}

write-host "All done! Exiting..."
Start-Sleep 2
EXIT

