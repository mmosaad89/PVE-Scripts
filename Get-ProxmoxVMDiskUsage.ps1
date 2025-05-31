# Define Proxmox server details
$proxmoxServer = Read-Host "Please enter your username Proxmomx node FQDN"
$port = "8006"
$username =  Read-Host "Please enter your username ex test@pve"
$password =  Read-Host "Please enter your password"

# Define the API endpoint
$apiUrl = "https://${proxmoxServer}:${port}/api2/json"

# Function to authenticate and get a ticket
function Get-ProxmoxTicket {
    param (
        [string]$username,
        [string]$password
    )

    $authUrl = "$apiUrl/access/ticket"
    $authBody = @{
        username = $username
        password = $password
    } | ConvertTo-Json

    $authResponse = Invoke-RestMethod -Uri $authUrl -Method Post -Body $authBody -ContentType "application/json" -SkipCertificateCheck
    return $authResponse.data
}

# Authenticate and get the ticket
$ticket = Get-ProxmoxTicket -username $username -password $password
$headers = @{
    "CSRFPreventionToken" = $ticket.CSRFPreventionToken
    "Cookie" = "PVEAuthCookie=$($ticket.ticket)"
}

# total disks allocatioed to VM from vm config
function GetAllDisks-Size {
    param (
        [PSCustomObject]$VMData
    )
    $totalSizeGB = 0
    # Get all properties of the PSCustomObject
    $properties = $VMData.PSObject.Properties

    foreach ($property in $properties) {
        $value = $property.Value
        if ($value -match 'size=(\d+)([GTMK]?)') {
            $sizeValue = [double]$matches[1]
            $sizeUnit = $matches[2]

            switch ($sizeUnit) {
                'T' { $sizeGB = $sizeValue * 1024 }  # Convert terabytes to gigabytes
                'G' { $sizeGB = $sizeValue }         # Already in gigabytes
                'M' { $sizeGB = $sizeValue / 1024 }  # Convert megabytes to gigabytes
                'K' { $sizeGB = $sizeValue / (1024 * 1024) }  # Convert kilobytes to gigabytes
                default { $sizeGB = $sizeValue }     # Assume gigabytes if no unit is specified
            }
            $totalSizeGB += $sizeGB
        }
    }
    return $totalSizeGB
}

# Function to get VM Configurations
function Get-VMConfig {
    param (
        [string]$node
    )
    # $node = $nodeName 

    $vmsUrl = "$apiUrl/nodes/$node/qemu"
    $vmsResponse = Invoke-RestMethod -Uri $vmsUrl -Headers $headers -Method Get -SkipCertificateCheck
    $vmDetails = @()


    foreach ($vm in $vmsResponse.data) {
        # $vm  = $vmsResponse.data[8]
        $vmId = $vm.vmid
        $vmName = $vm.name
        $vmConfigUrl = "$apiUrl/nodes/$node/qemu/$vmId/config"
        $vmConfigResponse = Invoke-RestMethod -Uri $vmConfigUrl -Headers $headers -Method Get -SkipCertificateCheck
        $CPUType = $vmConfigResponse.data.cpu
        $CoreCount = $vmConfigResponse.data.cores
        $CPUNuma = $vmConfigResponse.data.numa
        $memory = $vmConfigResponse.data.memory
        $HW = $vmConfigResponse.data.machine
        $OS = $vmConfigResponse.data.ostype
        $backupConf = $vmConfigResponse.data.agent

        # Extract disk size from VM configuration
        $diskSize = GetAllDisks-Size($vmConfigResponse.data)
        # Add VM info to the array
        $vmDetails += [PSCustomObject]@{
            Node    = $node
            VMID    = $vmId
            VMName  = $vmName
            DiskSizeGB = $diskSize 
            CPUType = $CPUType
            CoreCount = $CoreCount
            NumaState = $CPUNuma
            Memory = $memory
            VMHW = $HW
            OS = $OS
            Backup = $backupConf
        }
    }

    return $vmDetails
}

# Get all nodes
$nodesUrl = "$apiUrl/nodes"
$nodesResponse = Invoke-RestMethod -Uri $nodesUrl -Headers $headers -Method Get -SkipCertificateCheck

# Collect VMs details across all nodes
$allVMInfo = @()
foreach ($node in $nodesResponse.data) {
    # $node = $nodesResponse.data[1]
    $nodeName = $node.node
    $nodeVMInfo = Get-VMConfig -node $nodeName
    $allVMInfo += $nodeVMInfo
}

# Export the data to an Excel file
$outputFile = "PMX-VM-Details19.3.2025.xlsx"
$allVMInfo | Export-Excel -Path $outputFile -AutoSize -TableName "VMDiskUsage" -WorksheetName "VM Disk Usage"

Write-Output "VM disk usage data exported to $outputFile"

