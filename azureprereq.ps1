# Declare your variables

$Sub1           = "Azure Subscription 1"
$RG1            = "HSoA-RG-01"
$Location1      = "West Europe"
$VNetName1      = "HSoA-VNET-01"
$VNetName2      = "HSoA-VNET-Infrastructure"
$VSubNetName1   = "HSoA-Subnet-01"
$VSubNetName2   = "Infrastructure"
$GWSubName1     = "GatewaySubnet"
$VNet1Prefix    = "192.168.100.0/22"
$VNet2Prefix    = "192.168.98.0/23"
$VSubNet1Prefix = "192.168.100.0/24"
$VSubNet2Prefix = "192.168.98.0/24"
$GWName1        = "HSoA-VNetGW-01"
$GWSubPrefix1   = "192.168.99.0/24"

$DNS1           = "192.168.1.13"

$GWIPName1     = "HSoA-VNetGW-01-IP"
$GWIPconfName1 = "gwipconf1"
$ConnectionName  = "Site2Site-VPN-VDEMO-Ostrobramska"
$LNGName       = "Site2SiteVPN-LocalNetGateway"
$LNGPrefix1   = "192.168.1.0/24"
$LNGPrefix2   = "192.168.252.0/24"
$LNGIP         = "83.144.96.2"

# Connect to your subscription and create a new resource group

Connect-AzAccount
$azsubscription = Select-AzSubscription -SubscriptionName $Sub1
New-AzResourceGroup -Name $RG1 -Location $Location1

# Create virtual networks / spoke vnet for Horizon Service

$VSubNet1 = New-AzVirtualNetworkSubnetConfig -Name $VSubNetName1 -AddressPrefix $VSubNet1Prefix 
$vnetHSoA = New-AzVirtualNetwork -Name $VNetName1 -ResourceGroupName $RG1 -Location $Location1 -AddressPrefix $VNet1Prefix -Subnet $VSubNet1 -DnsServer $DNS1

# Create virtual networks / hub vnet for A2S VPN

$VSubNet2 = New-AzVirtualNetworkSubnetConfig -Name $VSubNetName2 -AddressPrefix $VSubNet2Prefix
$GWSubNet1 = New-AzVirtualNetworkSubnetConfig -Name $GWSubName1 -AddressPrefix $GWSubPrefix1
$vnetInfra = New-AzVirtualNetwork -Name $VNetName2 -ResourceGroupName $RG1 -Location $Location1 -AddressPrefix $VNet2Prefix -Subnet $VSubNet2,$GWSubNet1 -DnsServer $DNS1

# Peer Infrastructure and VDI networks
Add-AzVirtualNetworkPeering -Name HSoA-to-Infra -VirtualNetwork $vnetHSoA -RemoteVirtualNetworkId $vnetInfra.Id -AllowForwardedTraffic -AllowGatewayTransit
Add-AzVirtualNetworkPeering -Name Infra-to-HSoA -VirtualNetwork $vnetInfra -RemoteVirtualNetworkId $vnetHSoA.Id -AllowForwardedTraffic -AllowGatewayTransit

# Create VPN gateway

$gwpip1    = New-AzPublicIpAddress -Name $GWIPName1 -ResourceGroupName $RG1 -Location $Location1 -AllocationMethod Dynamic
$vnet1     = Get-AzVirtualNetwork -Name $VNetName2 -ResourceGroupName $RG1
$subnet1   = Get-AzVirtualNetworkSubnetConfig -Name "$GWSubName1" -VirtualNetwork $vnet1
$gwipconf1 = New-AzVirtualNetworkGatewayIpConfig -Name $GWIPconfName1 -Subnet $subnet1 -PublicIpAddress $gwpip1

New-AzVirtualNetworkGateway -Name $GWName1 -ResourceGroupName $RG1 -Location $Location1 -IpConfigurations $gwipconf1 -GatewayType Vpn -VpnType RouteBased -GatewaySku VpnGw1

# Create local network gateway - definition of your on-prem network logic

New-AzLocalNetworkGateway -Name $LNGName -ResourceGroupName $RG1 -Location $Location1 -GatewayIpAddress $LNGIP -AddressPrefix $LNGPrefix1,$LNGPrefix2

# Create the S2S VPN connection

$vnet1gw = Get-AzVirtualNetworkGateway -Name $GWName1  -ResourceGroupName $RG1
$lng5gw  = Get-AzLocalNetworkGateway -Name $LNGName -ResourceGroupName $RG1

New-AzVirtualNetworkGatewayConnection -Name $ConnectionName -ResourceGroupName $RG1 -VirtualNetworkGateway1 $vnet1gw -LocalNetworkGateway2 $lng5gw -Location $Location1 -ConnectionType IPsec -SharedKey 'VMware1!VMware1!' -EnableBGP $False

# Create App Registration in Azure AD

$appName = "HZSAP"
$startDate = Get-Date
$endDate = (Get-Date).AddYears(3)
$HorizonServiceApp = New-AzureADApplication -DisplayName $appName
$KeyValue = New-AzureADApplicationPasswordCredential -ObjectId $HorizonServiceApp.ObjectId -CustomKeyIdentifier "HSoA-Key-1" -StartDate $startDate -EndDate $endDate

#Create text file with details for Horizon Cloud setup

$KeyValueDescription = "App Client Sectret Key Value:" | Out-File -FilePath .\AzureIDs-For-HZCloud.txt -Append
$KeyValue.Value | Out-File -FilePath .\AzureIDs-For-HZCloud.txt -Append
$AppIDDescription = "Application (Client) ID:" | Out-File -FilePath .\AzureIDs-For-HZCloud.txt -Append
$HorizonServiceApp.AppId | Out-File -FilePath .\AzureIDs-For-HZCloud.txt -Append
$AppIDDescription = "Object ID:" | Out-File -FilePath .\AzureIDs-For-HZCloud.txt -Append
$HorizonServiceApp.ObjectId | Out-File -FilePath .\AzureIDs-For-HZCloud.txt -Append
$AzTenantValueDescription = "TenantID:" | Out-File -FilePath .\AzureIDs-For-HZCloud.txt -Append
Get-AzTenant| Out-File -FilePath .\AzureIDs-For-HZCloud.txt -Append

#add permissions for service principal of the application

Start-Sleep -Seconds 5
$azsubscription = Select-AzSubscription -SubscriptionName $Sub1
$subid = $azsubscription.Subscription.Id
New-AzADServicePrincipal -ApplicationId $HorizonServiceApp.AppId
$ServicePrincipalId = Get-AzureADServicePrincipal -All $true | Where-Object {$_.DisplayName -eq $appName}
Start-Sleep -Seconds 5
New-AzRoleAssignment -ObjectId $ServicePrincipalId.ObjectId -RoleDefinitionName Contributor -Scope "/subscriptions/$subid"

#Register necessary Resource  Providers
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.Compute"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.insights"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.Network"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.Storage"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.KeyVault"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.Authorization"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.Resources"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.ResourceHealth"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.DBforPostgreSQL"
Register-AzureRmResourceProvider -ProviderNamespace "Microsoft.sql"
