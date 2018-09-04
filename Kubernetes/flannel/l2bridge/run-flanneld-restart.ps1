Param(
    $ManagementIP = "172.20.36.242",
    $AddressPrefix = "10.244.2.0/24",
    $Gateway = "10.244.2.1"
)

# This is a copy from helper.psm1 except cleaning old network
function StartFlanneldNoClean($ipaddress, $NetworkName)
{
    #CleanupOldNetwork $NetworkName

    # Start FlannelD, which would recreate the network.
    # Expect disruption in node connectivity for few seconds
    pushd
    cd C:\flannel\
    [Environment]::SetEnvironmentVariable("NODE_NAME", (hostname).ToLower())
    start C:\flannel\flanneld.exe -ArgumentList "--kubeconfig-file=C:\k\config --iface=$ipaddress --ip-masq=1 --kube-subnet-mgr=1" -NoNewWindow
    popd

    WaitForNetwork $NetworkName
}

$BaseDir = "c:\k"
$helper = "c:\k\helper.psm1"
ipmo $helper

# Prepare Network & Start Infra services
$NetworkMode = "L2Bridge"
$NetworkName = "cbr0"

Write-Host "cleanup old network"
CleanupOldNetwork $NetworkName

ipmo C:\k\hns.psm1

# Due to an issue with flanneld, network cbr0 is created without a ManagementIP.
# We need to create cbr0 network with powershell and flanneld will use it.
if(!(Get-HnsNetwork | ? Name -EQ "cbr0"))
{
    Write-Host "create cbr0 network"
    New-HNSNetwork -Type $NetworkMode -AddressPrefix $AddressPrefix -Gateway $Gateway -Name $NetworkName -Verbose
}

Write-Host "Sleep for 10 seconds"
Start-Sleep 10

Write-Host "start flanneld"
StartFlanneldNoClean -ipaddress $ManagementIP -NetworkName $NetworkName
