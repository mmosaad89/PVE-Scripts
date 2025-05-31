# Variable initialization
$nsxaddr = Read-Host "Please enter your username NSX FQDN"

# Requsting user Inpusts
$user = Read-Host "NSX Username"
$pass = Read-Host "NSX Password" 

# Setting API Constants
$pair = "$($user):$($pass)"
$encodedCreds = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{ Authorization = "Basic $encodedCreds" }
$rules = @{}

# Retrive DFW Sections
$response = Invoke-WebRequest -Uri $nsxaddr/policy/api/v1/infra/domains/default/security-policies -Method Get -Headers $headers  -SkipCertificateCheck
$DFWSections = $response.Content | ConvertFrom-Json

# Loop Through DFW Sections
foreach ($DFWSection in $DFWSections.results) {
    # $DFWSection = $DFWSections.results[0] # Debugger
    $sectionRules = Invoke-WebRequest -Uri $nsxaddr/policy/api/v1/infra/domains/default/security-policies/$($DFWSection.id)/rules/ -Method Get -Headers $headers  -SkipCertificateCheck
    $rules = $sectionRules.Content | ConvertFrom-Json
    
    #Loop through section details and get rule action,direction,source,destination
    foreach ($rule in $rules.results){
        # $rule = $rules.results[0] # debugger
        $ruleName = $rule.display_name.replace(' ','')
        $ruleDescription = $rule.description
        $ipSetout = $("`n [IPSET $($ruleName)src] # $($ruleDescription) `n")

        try {
            if ($([String]$rule.source_groups) -eq 'ANY'){
                $ipSetout =[string]::Concat($ipSetout,"0.0.0.0/0")
                $ipSetout  >> .\ipsets.txt
                $ipSetout = ''
            }
            else { 
                foreach ($source in $rule.source_groups){
                    try {
                        # $source = $rule.source_groups[0] # Debugger
                        $SGquery = Invoke-WebRequest -Uri $nsxaddr/policy/api/v1$($source)/members/ip-addresses -Method Get -Headers $headers  -SkipCertificateCheck
                        $Groupmember = $SGquery.Content | ConvertFrom-Json
                        foreach ($ip in $Groupmember.results ) {
                            $ipSetout += "$ip`n"
                        }
                    }
                    catch {
                        $(Get-Date -Format u ) + ": error occured while getting members if SG: " + $destination >>.\DFWNSX2PVE.log
                        $(Get-Date -Format u )+ ": Status Code :"+ $SGquery.StatusCode >>.\DFWNSX2PVE.log
                        $(Get-Date -Format u )+": Status Description :"+ $SGquery.StatusDescription >>.\DFWNSX2PVE.log
                    }
                }
                $ipSetout  >> .\ipsets.txt
                $ipSetout = ''
            }
            # Loop through Destination and get effective members
            $ipSetout = "`n [IPSET $($ruleName)dst] # $($ruleDescription) `n"
            if ($([String]$rule.destination_groups) -eq 'ANY'){
                $ipSetout =[string]::Concat($ipSetout,"0.0.0.0/0")
                $ipSetout  >> .\ipsets.txt
                $ipSetout = ''
            }
            else {
                foreach ($destination in $rule.destination_groups){
                    try {
                        # $destination = $rule.destination_groups[0] # Debugger
                        $SGquery = Invoke-WebRequest -Uri $nsxaddr/policy/api/v1$($destination)/members/ip-addresses -Method Get -Headers $headers  -SkipCertificateCheck
                        $Groupmember = $SGquery.Content | ConvertFrom-Json
                        foreach ($ip in $Groupmember.results ) {
                            $ipSetout += "$ip`n"
                        }
                    }
                    catch {
                        $(Get-Date -Format u ) + ": error occured while getting members if SG: " + $destination >>.\DFWNSX2PVE.log
                        $(Get-Date -Format u )+ ": Status Code :"+ $SGquery.StatusCode >>.\DFWNSX2PVE.log
                        $(Get-Date -Format u )+": Status Description :"+ $SGquery.StatusDescription >>.\DFWNSX2PVE.log
                        }
                }
                $ipSetout  >> .\ipsets.txt
                $ipSetout = ''
            }
        }
        catch {
            $(Get-Date -Format u ) + ": error occured while getting Section Rules " + $DFWSection.display_name >>.\DFWNSX2PVE.log
            $(Get-Date -Format u )+ ": Status Code :"+ $sectionRules.StatusCode >>.\DFWNSX2PVE.log
            $(Get-Date -Format u )+": Status Description :"+ $sectionRules.StatusDescription >>.\DFWNSX2PVE.log

        }
    
            "IN $($($rule.action).Replace('ALLOW','ACCEPT')) -source +dc/$($($ruleName).ToLower())src -dest +dc/$($($ruleName).ToLower())dst -log nolog # $($DFWSection.sequence_number)" >> .\DFWRules.txt
            #"OUT $($($rule.action).Replace('ALLOW','ACCEPT')) -source +dc/$($($ruleName).ToLower())src -dest +dc/$($($ruleName).ToLower())dst -log nolog # $($DFWSection.sequence_number)" >> .\DFWRules.txt

    } 
}

# Define the path to the input and output files
$inputFile = ".\DFWRules.txt"
$outputFile = ".\outputfile.txt"

# Create an empty hash table to store unique lines
$hashTable = @{}

# Read the input file line by line
Get-Content $inputFile | ForEach-Object {
    # Check if the line is already in the hash table
    if (-not $hashTable.ContainsKey($_)) {
        # If not, add it to the hash table and write it to the output file
        $hashTable[$_] = $true
        $_ | Out-File -FilePath $outputFile -Append
    }
}


$allRule = Import-Csv -Path .\outputfile.txt -Delimiter " " -Header 'Direction','Action','Source','SourceIPset','Dest','DestIPSET','log', ' Level' , 'comment', 'sequance'
$sortedRules = $allRule | Sort-Object -Property sequance
$allRule | Export-Csv -Path .\sortedRules.csv -NoTypeInformation