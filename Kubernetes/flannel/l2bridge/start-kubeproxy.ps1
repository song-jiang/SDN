Param(
    $NetworkName = "cbr0"
)

$env:KUBE_NETWORK=$NetworkName.ToLower()
ipmo c:\k\hns.psm1
Get-HnsPolicyList | Remove-HnsPolicyList

$argList = @("--hostname-override=$(hostname)","--v=4","--proxy-mode=kernelspace","--kubeconfig=""c:\k\config""")
Start-Process -FilePath c:\k\kube-proxy.exe -ArgumentList $argList -RedirectStandardOutput C:\k\kube-proxy.1.log -RedirectStandardError C:\k\kube-proxy.2.log
