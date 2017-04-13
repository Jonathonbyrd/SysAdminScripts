<#
.SYNOPSIS
	Add users to Email Retention Policy

.DESCRIPTION
	All user mailboxes are compared with the current Exchange location in the retentionpolicy. Missing mailboxes are added 
	to the retention policy

.REQUIREMENTS
	ConnectTo-Compliance.ps1
	Link: https://github.com/ruudmens/SysAdminScripts/tree/master/Connectors
	
	ConnectTo-ExchangeOnline.ps1
	Link: https://github.com/ruudmens/SysAdminScripts/tree/master/Connectors

.EXAMPLE
	None
   
.NOTES
	Version:        1.0
	Author:         R. Mens
	Blog:			http://lazyadmin.nl
	Creation Date:  13 apr 2017
	
.LINK
	
#>
#---------------------------------------------------------[Initialisations]--------------------------------------------------------

# Connect to Exchange Online
ConnectTo-ExchangeOnline

# Connect to Security and Compliance
ConnectTo-Compliance

#-----------------------------------------------------------[Execution]------------------------------------------------------------

#Get the Exchange Users
$ExchUsers = Get-Recipient -ResultSize Unlimited -RecipientType UserMailbox | where {( $_.Alias -notlike '#EXT#' ) -and ( $_.primarySmtpAddress -notlike '*.onmicrosoft.com' )} | select PrimarySmtpAddress | sort-object PrimarySmtpAddress

#Get the current users in the Retention Policy
$SecUsers = Get-RetentionCompliancePolicy -Identity '<PolicyName>' | Select-Object -ExpandProperty ExchangeLocation | foreach {$_.Name} | sort-object $_.Name
 
#Compare the two arrays
$notInSec = $ExchUsers.primarySmtpAddress | Where {$SecUsers -NotContains $_}
 
foreach ($user in $notInSec){
	#Add the users to the retention policy
    Set-RetentionCompliancePolicy -Identity '<PolicyName>' -AddExchangeLocation $user
}