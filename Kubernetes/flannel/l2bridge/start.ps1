Param(
    [parameter(Mandatory = $true)] $ClusterCIDR,
    [parameter(Mandatory = $true)] $ManagementIP,
    [parameter(Mandatory = $true)] $KubeDnsServiceIP,
    [parameter(Mandatory = $true)] $ServiceCIDR,
    [ValidateSet("process", "hyperv")] $IsolationType = "process"
)

function DownloadFlannelBinaries()
{
    md c:\flannel -ErrorAction Ignore
    DownloadFile -Url  "https://github.com/song-jiang/flannel/raw/host-gw/dist/flanneld.exe" -Destination c:\flannel\flanneld.exe
}

function DownloadCniBinaries()
{
    Write-Host "Downloading CNI binaries"
    DownloadFlannelBinaries
    md $BaseDir\cni\config -ErrorAction Ignore
    md C:\etc\kube-flannel -ErrorAction Ignore

    DownloadFile -Url  "https://github.com/Microsoft/SDN/raw/master/Kubernetes/flannel/l2bridge/cni/l2bridge.exe" -Destination $BaseDir\cni\l2bridge.exe
    DownloadFile -Url  "https://github.com/Microsoft/SDN/raw/master/Kubernetes/flannel/l2bridge/cni/flannel.exe" -Destination $BaseDir\cni\flannel.exe
    DownloadFile -Url  "https://github.com/Microsoft/SDN/raw/master/Kubernetes/flannel/l2bridge/cni/host-local.exe" -Destination $BaseDir\cni\host-local.exe
    DownloadFile -Url  "https://github.com/Microsoft/SDN/raw/master/Kubernetes/flannel/l2bridge/net-conf.json" -Destination $BaseDir\net-conf.json
    cp $BaseDir\net-conf.json C:\etc\kube-flannel\net-conf.json
}

function DownloadWindowsKubernetesScripts()
{
    Write-Host "Downloading Windows Kubernetes scripts"
    DownloadFile -Url  https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/hns.psm1 -Destination $BaseDir\hns.psm1
    DownloadFile -Url  https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/InstallImages.ps1 -Destination $BaseDir\InstallImages.ps1
    DownloadFile -Url  https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/Dockerfile -Destination $BaseDir\Dockerfile
    DownloadFile -Url  https://github.com/Microsoft/SDN/raw/master/Kubernetes/windows/stop.ps1 -Destination $BaseDir\stop.ps1
    DownloadFile -Url  https://github.com/song-jiang/SDN/raw/song-cf/Kubernetes/flannel/l2bridge/start-kubelet.ps1 -Destination $BaseDir\start-Kubelet.ps1
    DownloadFile -Url  https://github.com/song-jiang/SDN/raw/song-cf/Kubernetes/flannel/l2bridge/start-kubeproxy.ps1 -Destination $BaseDir\start-Kubeproxy.ps1
}

function DownloadAllFiles()
{
    DownloadCniBinaries
    DownloadWindowsKubernetesScripts
}

function PrepareForUse()
{
    #Update Dockerfile for windows 1803
    $Exist1803 = cat c:\k\Dockerfile | findstr.exe 1803
    if (!$Exist1803)
    {
        Write-Host "Update dockerfile for 1803"

        (get-content c:\k\Dockerfile) | foreach-object {$_ -replace "nanoserver", "nanoserver:1803"} | set-content c:\k\Dockerfile
    }
}

function StartFlanneldWithLog($ipaddress, $NetworkName)
{
    # Start FlannelD, which would recreate the network.
    # Expect disruption in node connectivity for few seconds
    pushd
    cd C:\flannel\
    [Environment]::SetEnvironmentVariable("NODE_NAME", (hostname).ToLower())
    start-Process C:\flannel\flanneld.exe -ArgumentList "--kubeconfig-file=C:\k\config --iface=$ipaddress --ip-masq=1 --kube-subnet-mgr=1" -RedirectStandardOutput C:\k\flanneld.1.log -RedirectStandardError C:\k\flanneld.2.log
    popd

    WaitForNetwork $NetworkName
}

$BaseDir = "c:\k"
md $BaseDir -ErrorAction Ignore
$helper = "c:\k\helper.psm1"
if (!(Test-Path $helper))
{
    Invoke-WebRequest https://raw.githubusercontent.com/Microsoft/SDN/master/Kubernetes/windows/helper.psm1 -O c:\k\helper.psm1
}
ipmo $helper

# Download All the files
DownloadAllFiles
PrepareForUse

# Prepare POD infra Images
.\InstallImages.ps1

# Prepare Network & Start Infra services
$NetworkMode = "L2Bridge"
$NetworkName = "cbr0"

CleanupOldNetwork $NetworkName

ipmo C:\k\hns.psm1

# Create a L2Bridge to trigger a vSwitch creation. Do this only once
if(!(Get-HnsNetwork | ? Name -EQ "External"))
{
    Write-Host "`nStart creating vSwitch. Note: Connection may get lost for RDP, please reconnect...`n"
    New-HNSNetwork -Type $NetworkMode -AddressPrefix "192.168.255.0/30" -Gateway "192.168.255.1" -Name "External" -Verbose
    # Wait longer enough for vSwitch been created.
    Start-Sleep 10
}

Write-Host "`nStart kubelet...`n"
.\start-kubelet.ps1 -clusterCIDR $ClusterCIDR -KubeDnsServiceIP $KubeDnsServiceIP -serviceCIDR $ServiceCIDR -IsolationType $IsolationType -NetworkName $NetworkName
Write-Host "`nkubelet started`n"


Start-Sleep 10
Write-Host "`nStart flanneld...`n"
StartFlanneldWithLog -ipaddress $ManagementIP -NetworkName $NetworkName
Write-Host "`nflanneld started`n"

Start-Sleep 10
Write-Host "`nStart kube-proxy...`n"
.\start-kubeproxy.ps1 -NetworkName $NetworkName
Write-Host "`nkube-proxy started`n"


