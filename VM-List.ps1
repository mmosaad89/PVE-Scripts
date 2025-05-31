# Define Proxmox server details
$proxmoxServer = Read-Host "Please enter your username Proxmomx node FQDN"
$port = "8006"
$username =  Read-Host "Please enter your username ex test@pve"
$password =  Read-Host "Please enter your password"

# Define the API endpoint
$apiUrl = "https://$($proxmoxServer):$($port)/api2/json"

# Function to authenticate and get a ticket and CSRF token
function Get-ProxmoxTicket {
    param (
        [string]$username,
        [string]$password
    )
    $authUrl = "$($apiUrl)/access/ticket"
    $authBody = @{
        username = $username
        password = $password
    } | ConvertTo-Json

    $response = Invoke-RestMethod -Uri $authUrl -Method Post -Body $authBody -ContentType "application/json" -SkipCertificateCheck
    return $response.data
}

# Function to get VMs from Proxmox
function Get-ProxmoxVMs {
    param (
        [string]$ticket,
        [string]$csrfToken
    )
    $vmsUrl = "$($apiUrl)/cluster/resources?type=vm"
    $headers = @{
        "Cookie" = "PVEAuthCookie=$($ticket)"
        "CSRFPreventionToken" = $csrfToken
    }
    $response = Invoke-RestMethod -Uri $vmsUrl -Method Get -Headers $headers -SkipCertificateCheck
    return $response.data
}

# Function to get VM configuration including datastore
function Get-ProxmoxVMConfig {
    param (
        [string]$node,
        [string]$vmid,
        [string]$ticket,
        [string]$csrfToken
    )
    $vmConfigUrl = "$($apiUrl)/nodes/$($node)/qemu/$($vmid)/config"
    $headers = @{
        "Cookie" = "PVEAuthCookie=$ticket"
        "CSRFPreventionToken" = $csrfToken
    }
    $response = Invoke-RestMethod -Uri $vmConfigUrl -Method Get -Headers $headers -SkipCertificateCheck
    return $response.data
}

# Authenticate and get the ticket and CSRF token
$authData = Get-ProxmoxTicket -username $username -password $password
$ticket = $authData.ticket
$csrfToken = $authData.CSRFPreventionToken

# Get all VMs
$vms = Get-ProxmoxVMs -ticket $ticket -csrfToken $csrfToken

# Create a list to store VM and datastore information
$vmList = @()

# Loop through each VM and get its datastore
foreach ($vm in $vms) {
    if ($vm.type -eq "qemu" -or $vm.type -eq "lxc") {
        $node = $vm.node
        $vmid = $vm.vmid
        $vmConfig = Get-ProxmoxVMConfig -node $node -vmid $vmid -ticket $ticket -csrfToken $csrfToken
        $CPUType = $vmConfig.cpu
        $CoreCount = $vmConfig.cores
        $CPUNuma = $vmConfig.numa
        $memory = $vmConfig.memory
        $HW = $vmConfig.machine
        $OS = $vmConfig.ostype
        $backupConf = $vmConfig.agent

        # Extract the datastore from the VM configuration
        # $datastore = $vmConfig | Where-Object { $_.key -like "ide2" -or $_.key -like "scsi0" -or $_.key -like "virtio0" } | Select-Object -ExpandProperty value -First 1
        $datastore = $vmConfig.scsi0
        $datastore = $datastore -split ":" | Select-Object -Index 0
        # Add VM and datastore information to the list
        $vmList += [PSCustomObject]@{
            VMID      = $vmid
            Name      = $vm.name
            Node      = $node
            Datastore = $datastore
            CPUType = $CPUType
            CoreCount = $CoreCount
            NumaState = $CPUNuma
            Memory = $memory
            VMHW = $HW
            OS = $OS
            Backup = $backupConf
        }
    }
}

# Export the list to an Excel file
$excelFilePath = ".\ProdVMs.xlsx"
$vmList | Export-Excel -Path $excelFilePath -AutoSize -TableName "ProxmoxVMs"

Write-Output "VM and datastore information saved to $excelFilePath"