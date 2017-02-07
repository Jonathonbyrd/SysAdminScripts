#requires -version 4
<#
.SYNOPSIS
  
.DESCRIPTION
  Generate a new name for a computer and add it to domain
  
  You don't need to have the Active Directory module installed, it will pull it from the Domain Controller
  WinRM is used to connect to the domain controller
  Credentials are stored in a securestring txt file.

  New computer name is generated based on the number from the last added computer in the domain, 
  prefix set in the config file and a deviceType prefix set in the config file.

  Config file settings / explanation:
	  "desktopPrefix": "PC",			// Prefix for desktop computer
	  "domain" : "domain.local",		// Local domain, used for adding the computer
	  "domainController": "19.168.0.1", // Ip address of the domaincontroller, used for trusted hosts
	  "filter": "(|(CN=LT*)(CN=PC*))",  // Searchbase filter to find last computer
	  "laptopPrefix": "LT",				// Prefix for notebooks
	  "lastAddedComputersAmount": 5,	// Amount of computer to return when no name can be found
	  "numberOfCharacters": 4,			// Number of characters to get to generate a new number. For example: COMP-SITE-PC3371 < results in 3371
	  "searchBaseOU": "OU=Computers,OU=SITE,DC=DOMAIN,DC=Local",   // OU to search for all computers, used to validate if computername doesn't exists in domain
	  "newComputerOU": "OU=Deploy,OU=Computers,OU=SITE,DC=DOMAIN,DC=Local",  // OU to place new computer in
	  "prefix": ""						// Prefix for all computers, example "COMP-SITE-"

.PARAMETER <Parameter_Name>
    None
.INPUTS
  config.json is required in the same folder as this script.
  securestring.txt is required in the same folder as this script.
.OUTPUTS
  None
.NOTES
  Version:        1.0
  Author:         R. Mens
  Creation Date:  1 February 2017
  Purpose/Change: Initial script development
  
.EXAMPLE
  Just run the script with elevated powershell
  
  From a batFile
	Powershell Set-ExecutionPolicy Unrestricted
	Powershell -NoExit -File D:\joinDomainAndRename.ps1
#>


#----------------------------------------------------------[Declarations]----------------------------------------------------------

#Get the config file
$config = Get-Content $PSScriptRoot"\config.json" -Raw | ConvertFrom-Json

#---------------------------------------------------------[Initialisations]--------------------------------------------------------
#Enable WinRM remote administrating
Set-ItemProperty –Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System –Name LocalAccountTokenFilterPolicy –Value 1 -Type DWord
Try
{
    Enable-PSRemoting -Force
}
catch
{}
#Set trusted hosts to you domain controller
Set-Item WSMan:\localhost\Client\TrustedHosts  –Value $config.domainController -Force

<# 
	CREDENTIALS

	For importing the ActiveDirectory module from the domain controller we need AD credentials.
	You can store the password in a "secure" string, but you will have to add a key for it. The key
	is used to decrypted the password string.

	To create the secure string use the following command:
		
		$SecureString = ConvertTo-SecureString -String "password" -AsPlainText -Force
		$EncryptedPassword = ConvertFrom-SecureString -SecureString $SecureString -Key $Key
		Set-Content -Path ".\securestring.txt" -Value $EncryptedPassword

	Alternative is to enter the password everytime when running the script.
#>
$domain = $config.domain
$user = "Administrator"
$key = (3,4,2,3,56,34,254,222,1,12,5,23,42,54,33,124,1,34,2,7,6,5,35,12)
$encryptedPw = Get-Content $PSScriptRoot"\securestring.txt"
$SecureString = ConvertTo-SecureString -String $encryptedPw -Key $key
$username = "$domain\$user"
$cred = New-Object System.Management.Automation.PSCredential($username,$SecureString)

#Initiate Remote PS Session to local DC
$ADPowerShell = New-PSSession -ComputerName $config.domainController -Credential $cred
 
# Import-Module ActiveDirectory
write-host "Importing Active Directory PowerShell Commandlets"
Invoke-Command -Session $ADPowerShell -scriptblock { import-module ActiveDirectory }
Import-PSSession -Session $ADPowerShell -Module ActiveDirectory -AllowClobber -ErrorAction Stop

Clear-Host
#-----------------------------------------------------------[Functions]------------------------------------------------------------

<#
	Add the computer to the domain, rename it, place it in a specific OU and reboot it when done.
#>
Function Add-ComputerToDomain
{
	PARAM(
		[parameter(Mandatory=$true)]
		[string]$name,
		[parameter(Mandatory=$false)]
		[string]$ou
	)
	PROCESS
	{
		Try
		{
			Add-Computer -NewName $name -Credential $cred -DomainName $config.domain -OUPath $ou -Restart  -Force
		}
		Catch
		{
			Write-Error "Something went wrong while adding the computer $_"
		}
	}
}

<#
	Generates the new computername
	1. Get that last added computer from the domain in the given OU.
		Example: PC3361
	2. Strip the computer name so only the number is left and convert it to INT.
		Example: 3361
	3. Create the new computername with the prefix and deviceType specific prefix.
	4. Check if the device does not exists in the domain, if not return the new name.

#>
Function Get-NewComputerName
{
	PROCESS
	{
		$lastComputer = Get-LastComputerNames -amount 1 -ou $config.searchBaseOU -filter $config.filter
		$lastNumber = [convert]::ToInt32($lastComputer.Name.Substring($lastComputer.Name.Length - $config.numberOfCharacters, $config.numberOfCharacters), 10)
	
		$newComputerName =  New-ComputerName -number ($lastNumber + 1) -deviceType $deviceType -prefix $config.prefix -desktopPrefix $config.desktopPrefix -laptopPrefix $config.laptopPrefix
		
		If ((Get-DeviceByName -name $newComputerName) -eq $false)
		{
			Return $newComputerName
		}
		Return $false
	}
}

<#
	Get the last n amount of comuters in soecified OU
	Returns name and date created.
#>
Function Get-LastComputerNames
{
	PARAM(
		[parameter(Mandatory=$false)]
		[int]$amount = 1,
		[parameter(Mandatory=$false)]
		[string]$ou,
		[parameter(Mandatory=$false)]
		[string]$filter
	)
	PROCESS
	{
		$computers = Get-ADComputer -Properties Name,Created -SearchBase $ou -LdapFilter $filter | sort Created | select -last $amount
		$result =
		foreach ($computer in $computers)
			{
				 New-Object PSObject -Property @{
					Name = $computer.Name
					Created = $computer.Created
				}
			}
        Return $result
	}
}

<#
	Get computer with specified name to check if it exists
	Return $true|$false
#>
Function Get-DeviceByName
{
	PARAM(
		[parameter(Mandatory=$true)]
		[string]$name
	)
	PROCESS
	{
		if ((Get-ADComputer -Filter "name -eq '$name'") -eq $null) {
			Return $false
		}
		Return $true
	}
}

<#
	Get the device type based on WMI SystemEnclosure
	Returns Desktop|Laptop
#>
Function Get-DeviceType
{
	PARAM(
		[parameter(Mandatory=$true)]
		[string]$computer = 'localhost'
	)
	PROCESS
	{
		$result = 'Desktop'	
		if (Get-WmiObject -Class win32_systemenclosure -ComputerName $computer | Where-Object { $_.chassistypes -eq 9 -or $_.chassistypes -eq 10 -or $_.chassistypes -eq 14})
		{ 
			$result = 'Laptop' 
		}
		Return $result
	}
}

<#
	Generate new computername with specified prefix and device prefix
	Return new computername
#>
Function New-ComputerName
{
	PARAM(
		[parameter(Mandatory=$true)]
		[int]$number,
		[parameter(Mandatory=$false)]
		[ValidateSet("Desktop","Laptop")]
		[string]$deviceType,
		[parameter(Mandatory=$false)]
		[string]$prefix,
		[parameter(Mandatory=$false)]
		[string]$desktopPrefix,
		[parameter(Mandatory=$false)]
		[string]$laptopPrefix
	)
	PROCESS
	{	
		$newPrefix = $null

		If ($deviceType -ne $null) 
		{
			if ($deviceType -eq 'Desktop')
			{
				$newPrefix = ($prefix + $desktopPrefix)
			}
			else 
			{
				$newPrefix = ($prefix + $laptopPrefix)
			}
		}
		Return ($newPrefix + $number)
	}
}

#
# ------------------------  INIT ----------------------#
#

#Get DeviceType (computer / laptop)
$deviceType = Get-DeviceType -computer 'localhost'
$newComputerName = Get-NewComputerName

#No able to generate name, most likely last added computer in domain is an old computer that is rejoined.
#User needs to specify an alternative number, show last n added computers
If ($newComputerName -eq $false) 
{
	Write-Host "Unable to create a new device name. Last added devices to domain are: " -ForegroundColor Red
	Get-LastComputerNames -amount $config.lastAddedComputersAmount -ou $config.searchBaseOU -filter $config.filter | Select-Object Name,Created |  Format-Table
	Write-Host "Please enter a new number for this device : " -ForegroundColor Yellow

	$manualEntry = Read-Host 'Number '
	$newComputerName =  New-ComputerName -number $manualEntry -deviceType $deviceType -desktopPrefix $config.desktopPrefix -laptopPrefix $config.laptopPrefix
}

Write-Host ("New device name is: " + $newComputerName) -ForegroundColor Yellow

#Confirm new name, if ok add it to domain, else ask new name and validate it.
Do 
{
	#Confirm new name
	$title = "Check the name"
	$message = "Is name ok? Choose YES to add it the domain"
	$yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", "Yes"
	$no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", "No"

	$options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
	$result = $host.ui.PromptForChoice($title, $message, $options, 0) 
	
	#New name is approved by the user
	if ($result -eq 0) 
	{
		Add-ComputerToDomain -name $newComputerName -ou $config.newComputerOU
	}
	else
	{
		#New name is rejected by the user
		Write-Host ("Last " + $config.lastAddedComputersAmount + " computers added to the domain are:") -ForegroundColor Yellow

		Get-LastComputerNames -amount $config.lastAddedComputersAmount -ou $config.searchBaseOU -filter $config.filter | Select-Object Name,Created |  Format-List 
		
		#Keep asking for a new name until we have a valided one
		Do
		{
			if ($nameAlreadyExists) 
			{
				Write-Host 'Name already exists, choose another' -ForegroundColor red
			}

			$manualEntry = Read-Host 'Number '
			$newComputerName =  New-ComputerName -number $manualEntry -deviceType $deviceType -desktopPrefix $config.desktopPrefix -laptopPrefix $config.laptopPrefix
			$nameAlreadyExists = Get-DeviceByName -name $newComputerName
		}
		While ($nameAlreadyExists -eq $true)

		Write-Host ("New device name is: " + $newComputerName) -ForegroundColor Yellow
	}    
}
While ($result -eq 1)

#Computer added.
Write-Host "Computer add to domain and reboot initiated" -ForegroundColor Green