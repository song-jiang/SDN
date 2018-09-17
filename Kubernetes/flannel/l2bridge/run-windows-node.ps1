[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$ip = Get-NetIpaddress | Where InterfaceAlias -Like '*Ethernet 2*' | where AddressFamily -EQ IPV4

pushd
cd c:\k
.\start.ps1 -ClusterCIDR 10.244.0.0/16 -ServiceCIDR 10.96.0.0/12 -KubeDnsServiceIP 10.96.0.10 -ManagementIP $ip.IPAddress
popd
