#Listar as regiões: az account list-locations --output table
#Listar o nome da imagem: az vm image list --publisher "Canonical"

#VARIAVEIS
$Location="eastus2"
$ResourceGroupName="IGTI-Desafio2"
$vNetName="IGTI-vNet"
$NSGName="IGTI-NSG"
$networkaddr="10.199.0.0/16"
$subnetaddr="10.199.0.0/24"
$Bastionsubnetaddr="10.199.1.0/27"
$VM1Name="Ubuntu01"
$VM2Name="Ubuntu02"
$VMImage="UbuntuLTS"
$VMSize="Standard_B4ms"
$StorageAccountName=("0123456789abcdefghijklmnopqrstuvwxyz".tochararray() | Sort-Object {Get-Random})[0..8] -join ''
$StorageAccountName="igtidesafio2$StorageAccountName"
$StorageFileShareName="fileshare"
$AutomationStartTime =(Get-Date "11:00:00").AddDays(1)
$AutomationStopTime=(Get-Date "21:00:00").AddDays(1)
$AutomationTimeZone="America/Sao_Paulo"
$BackupStorageRedundancy="LocallyRedundant"
$ACRName=("0123456789abcdefghijklmnopqrstuvwxyz".tochararray() | Sort-Object {Get-Random})[0..8] -join ''
$ACRName="igtidesafio2acr$ACRName"
$ACRImageName="igtidesafio2image"
$ACRImageRelease="igtidesafio2image:v1"
$ACIName="igtidesafio2aci"
$KeyVaultName=("0123456789abcdefghijklmnopqrstuvwxyz".tochararray() | Sort-Object {Get-Random})[0..8] -join ''
$KeyVaultName="igtidesafio2kv$KeyVaultName"
$GitRepoACI="https://github.com/willianromao/acr-build-helloworld-node.git"
$GitRepoACIPath="acr-build-helloworld-node"
$AdminUsername=whoami
$AdminUsername=$AdminUsername.Split("\")[0]
$AdminPassword=("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".tochararray() | Sort-Object {Get-Random})[0..14] -join ''
$AdminPassword="$AdminPassword@@"
echo "Username: $AdminUsername" > Login.txt
echo "Password: $AdminPassword" >> Login.txt

# SUBSCRIPTION
$subscription=@(az account list --query [].id -o tsv)
if ($subscription.Count -gt 1)
{
    for ($arry=0; $arry -lt $subscription.Count; $arry++)
        { Write-Host "$arry -> "$subscription[$arry]" "}
    $arry=$arry - 1
    $Option = Read-Host "Selecione uma subscription de 0 a $arry"
    Write-Host "subscription selecionada: "$subscription[$Option]""
    $subscription=$subscription[$Option]
    az account set --subscription $subscription
    Write-Host ------------------------------
}

# RESOURCE GROUP
Write-Host Criando o RG $ResourceGroupName

az group create `
  --location $Location `
  --resource-group $ResourceGroupName `
  --output none

# AZURE POLICY
Write-Host ------------------------------
Write-Host Criando a Policy AutoTag

az policy assignment create `
  --display-name "AutoTag" `
  --policy "2a0e14a6-b0a6-4fab-991a-187a4f81c498" `
  --name "49c5950fee674b3cb1cf025a" `
  --params '{ \"tagName\": { \"value\": \"Area\" }, \"tagValue\": { \"value\": \"Engenharia\" } }' `
  --scope "/subscriptions/$subscription/resourceGroups/$ResourceGroupName" `
  --output none

# VNET E NSG
Write-Host ------------------------------
Write-Host Criando a vNet $vNetName

az network vnet create `
  --resource-group $ResourceGroupName `
  --name $vNetName `
  --subnet-name default  `
  --output none
  
az network vnet subnet update `
  --resource-group $ResourceGroupName `
  --name default `
  --vnet-name $vNetName `
  --service-endpoints Microsoft.Storage `
  --output none

az network nsg create `
  --resource-group $ResourceGroupName `
  --name $NSGName `
  --output none

az network nsg rule create `
  --resource-group $ResourceGroupName `
  --name HTTP-Allow `
  --nsg-name $NSGName `
  --protocol tcp `
  --direction inbound `
  --source-address-prefix '*' `
  --source-port-range '*' `
  --destination-address-prefix '*' `
  --destination-port-range 80 `
  --access allow `
  --priority 200 `
  --output none

az network vnet subnet update `
  --resource-group $ResourceGroupName `
  --vnet-name $vNetName `
  --name default `
  --network-security-group $NSGName `
  --output none

# STORAGE ACCOUT
Write-Host ------------------------------
Write-Host Criando a Storage Account $StorageAccountName

az storage account create `
  --name $StorageAccountName `
  --resource-group $ResourceGroupName `
  --kind StorageV2 `
  --location $Location `
  --sku Standard_LRS `
  --allow-blob-public-access false `
  --https-only true `
  --output none

az storage account network-rule add `
  --account-name $StorageAccountName `
  --resource-group $ResourceGroupName `
  --vnet-name $vNetName `
  --subnet default  `
  --output none

$StorageAccountKey = (az storage account keys list `
    --resource-group $ResourceGroupName `
    --account-name $StorageAccountName `
    --query "[0].value" -o tsv)

az storage share create `
  --name $StorageFileShareName `
  --account-name $StorageAccountName `
  --account-key $StorageAccountKey `
  --quota 100  `
  --output none

az storage account update `
  --name $StorageAccountName `
  --resource-group $ResourceGroupName `
  --default-action Deny   `
  --output none

# LOAD BALANCER
Write-Host ------------------------------
Write-Host Criando o LoadBalancer $ResourceGroupName-LB

az network public-ip create `
  --resource-group $ResourceGroupName `
  --name $ResourceGroupName-LB-pip `
  --sku Standard `
  --zone 3 `
  --version IPv4 `
  --output none
$LBpip=(az network public-ip show `
  --resource-group $ResourceGroupName `
  --name $ResourceGroupName-LB-pip `
  --query ipAddress `
  --output tsv)

az network lb create `
  --resource-group $ResourceGroupName `
  --name $ResourceGroupName-LB `
  --sku Standard `
  --public-ip-address $ResourceGroupName-LB-pip `
  --public-ip-address-allocation Static `
  --frontend-ip-name $ResourceGroupName-LB-frontend `
  --backend-pool-name $ResourceGroupName-LB-backend `
  --output none

az network lb probe create `
  --resource-group $ResourceGroupName `
  --lb-name $ResourceGroupName-LB `
  --name $ResourceGroupName-LB-HealthProbe `
  --protocol Http `
  --path / `
  --interval 5 `
  --port 80 `
  --output none

az network lb rule create `
  --resource-group $ResourceGroupName `
  --lb-name $ResourceGroupName-LB `
  --name $ResourceGroupName-LB-Rule `
  --protocol tcp `
  --frontend-port 80 `
  --backend-port 80 `
  --frontend-ip-name $ResourceGroupName-LB-frontend `
  --backend-pool-name $ResourceGroupName-LB-backend `
  --probe-name $ResourceGroupName-LB-HealthProbe `
  --output none

az network nic create `
  --resource-group $ResourceGroupName `
  --name $VM1Name-nic `
  --vnet-name $vNetName `
  --subnet default `
  --network-security-group $NSGName `
  --lb-name $ResourceGroupName-LB `
  --lb-address-pools $ResourceGroupName-LB-backend `
  --output none

az network nic create `
  --resource-group $ResourceGroupName `
  --name $VM2Name-nic `
  --vnet-name $vNetName `
  --subnet default `
  --network-security-group $NSGName `
  --lb-name $ResourceGroupName-LB `
  --lb-address-pools $ResourceGroupName-LB-backend `
  --output none

# VIRTUAL MACHINES
Write-Host ------------------------------
Write-Host Criando a Maquina Virtual $VM1Name

az vm create `
  --resource-group $ResourceGroupName `
  --name $VM1Name `
  --size $VMSize `
  --admin-username $AdminUsername `
  --admin-password $AdminPassword `
  --nic $VM1Name-nic `
  --image $VMImage `
  --zone 1 `
  --output none 
  
az vm disk attach `
  --resource-group $ResourceGroupName `
  --vm-name $VM1Name `
  --name $VM1Name-Extra `
  --new `
  --size-gb 100 `
  --output none

az vm extension set `
  --publisher Microsoft.Azure.Extensions `
  --version 2.0 `
  --name CustomScript `
  --vm-name $VM1Name `
  --resource-group $ResourceGroupName `
  --settings "{'commandToExecute':'apt-get -y update && apt-get -y install nginx && hostname > /var/www/html/index.html'}" `
  --output none

az vm extension set `
  --publisher Microsoft.Azure.Extensions `
  --version 2.0 `
  --name CustomScript `
  --vm-name $VM1Name `
  --resource-group $ResourceGroupName `
  --settings "{'commandToExecute':'mkdir /mnt/$StorageFileShareName && echo //$StorageAccountName.file.core.windows.net/$StorageFileShareName /mnt/$StorageFileShareName cifs nofail,vers=3.0,username=$StorageAccountName,password=$StorageAccountKey,dir_mode=0777,file_mode=0777,serverino >> /etc/fstab && mount -t cifs //$StorageAccountName.file.core.windows.net/$StorageFileShareName /mnt/$StorageFileShareName -o vers=3.0,username=$StorageAccountName,password=$StorageAccountKey,dir_mode=0777,file_mode=0777,serverino && hostname > /mnt/$StorageFileShareName/teste.txt  '}" `
  --output none

Write-Host ------------------------------
Write-Host Criando a Maquina Virtual $VM2Name

az vm create `
  --resource-group $ResourceGroupName `
  --name $VM2Name `
  --size $VMSize `
  --admin-username $AdminUsername `
  --admin-password $AdminPassword `
  --nic $VM2Name-nic `
  --image UbuntuLTS `
  --zone 2 `
  --output none

az vm disk attach `
  --resource-group $ResourceGroupName `
  --vm-name $VM2Name `
  --name $VM2Name-Extra `
  --new `
  --size-gb 100 `
  --output none

az vm extension set `
  --publisher Microsoft.Azure.Extensions `
  --version 2.0 `
  --name CustomScript `
  --vm-name $VM2Name `
  --resource-group $ResourceGroupName `
  --settings "{'commandToExecute':'apt-get -y update && apt-get -y install nginx && hostname > /var/www/html/index.html'}" `
  --output none

az vm extension set `
  --publisher Microsoft.Azure.Extensions `
  --version 2.0 `
  --name CustomScript `
  --vm-name $VM2Name `
  --resource-group $ResourceGroupName `
  --settings "{'commandToExecute':'mkdir /mnt/$StorageFileShareName && echo //$StorageAccountName.file.core.windows.net/$StorageFileShareName /mnt/$StorageFileShareName cifs nofail,vers=3.0,username=$StorageAccountName,password=$StorageAccountKey,dir_mode=0777,file_mode=0777,serverino >> /etc/fstab && mount -t cifs //$StorageAccountName.file.core.windows.net/$StorageFileShareName /mnt/$StorageFileShareName -o vers=3.0,username=$StorageAccountName,password=$StorageAccountKey,dir_mode=0777,file_mode=0777,serverino && hostname >> /mnt/$StorageFileShareName/teste.txt '}" `
  --output none

# AUTOMATION
Write-Host ------------------------------
Write-Host Criando o Azure Automation

az automation account create `
  --automation-account-name "$ResourceGroupName-Automation" `
  --resource-group $ResourceGroupName `
  --location "$Location" `
  --sku Free `
  --output none
  
az automation runbook create `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Start-$VM1Name `
  --resource-group $ResourceGroupName `
  --type PowerShell `
  --output none

cp ./Start.ps1 ./Start-$VM1Name.ps1 
echo "Start-AzureRmVM -Name $VM1Name -ResourceGroupName $ResourceGroupName" >> ./Start-$VM1Name.ps1 
az automation runbook replace-content `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Start-$VM1Name `
  --resource-group $ResourceGroupName `
  --content "@./Start-$VM1Name.ps1"  `
  --output none

az automation runbook create `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Start-$VM2Name `
  --resource-group $ResourceGroupName `
  --type PowerShell `
  --output none

cp ./Start.ps1 ./Start-$VM2Name.ps1 
echo "Start-AzureRmVM -Name $VM2Name -ResourceGroupName $ResourceGroupName" >> ./Start-$VM2Name.ps1 
az automation runbook replace-content `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Start-$VM2Name `
  --resource-group $ResourceGroupName `
  --content "@./Start-$VM2Name.ps1" `
  --output none

az automation runbook create `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Stop-$VM1Name `
  --resource-group $ResourceGroupName `
  --type PowerShell `
  --output none

cp ./Stop.ps1 ./Stop-$VM1Name.ps1 
echo "Stop-AzureRmVM -Name $VM1Name -ResourceGroupName $ResourceGroupName -force" >> ./Stop-$VM1Name.ps1 
az automation runbook replace-content `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Stop-$VM1Name `
  --resource-group $ResourceGroupName `
  --content "@./Stop-$VM1Name.ps1"  `
  --output none

az automation runbook create `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Stop-$VM2Name `
  --resource-group $ResourceGroupName `
  --type PowerShell `
  --output none

cp ./Stop.ps1 ./Stop-$VM2Name.ps1 
echo "Stop-AzureRmVM -Name $VM2Name -ResourceGroupName $ResourceGroupName -force" >> ./Stop-$VM2Name.ps1   
az automation runbook replace-content `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Stop-$VM2Name `
  --resource-group $ResourceGroupName `
  --content "@./Stop-$VM2Name.ps1" `
  --output none
  
az automation runbook publish `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Start-$VM1Name `
  --resource-group $ResourceGroupName `
  --no-wait `
  --output none

az automation runbook publish `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Start-$VM2Name `
  --resource-group $ResourceGroupName `
  --no-wait `
  --output none

az automation runbook publish `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Stop-$VM1Name `
  --resource-group $ResourceGroupName `
  --no-wait `
  --output none

az automation runbook publish `
  --automation-account-name "$ResourceGroupName-Automation" `
  --name Stop-$VM2Name `
  --resource-group $ResourceGroupName `
  --no-wait `
  --output none

New-AzureRMAutomationSchedule `
  -DayInterval 1 `
  -StartTime $AutomationStartTime `
  -AutomationAccountName $ResourceGroupName-Automation `
  -ResourceGroupName $ResourceGroupName `
  -Name "Start-Scheduler" `
  -TimeZone $AutomationTimeZone > $null

New-AzureRMAutomationSchedule `
  -DayInterval 1 `
  -StartTime $AutomationStopTime `
  -AutomationAccountName $ResourceGroupName-Automation `
  -ResourceGroupName $ResourceGroupName `
  -Name "Stop-Scheduler" `
  -TimeZone $AutomationTimeZone > $null

Register-AzureRMAutomationScheduledRunbook `
  -RunbookName Start-$VM1Name `
  -ScheduleName Start-Scheduler `
  -ResourceGroupName $ResourceGroupName `
  -AutomationAccountName $ResourceGroupName-Automation > $null

Register-AzureRMAutomationScheduledRunbook `
  -RunbookName Start-$VM2Name `
  -ScheduleName Start-Scheduler `
  -ResourceGroupName $ResourceGroupName `
  -AutomationAccountName $ResourceGroupName-Automation > $null

Register-AzureRMAutomationScheduledRunbook `
  -RunbookName Stop-$VM1Name `
  -ScheduleName Stop-Scheduler `
  -ResourceGroupName $ResourceGroupName `
  -AutomationAccountName $ResourceGroupName-Automation > $null

Register-AzureRMAutomationScheduledRunbook `
  -RunbookName Stop-$VM2Name `
  -ScheduleName Stop-Scheduler `
  -ResourceGroupName $ResourceGroupName `
  -AutomationAccountName $ResourceGroupName-Automation > $null

# BACKUP
Write-Host ------------------------------
Write-Host Criando o Recovery Services Vault

az backup vault create `
  --resource-group $ResourceGroupName `
  --name $ResourceGroupName-Vault `
  --location $Location `
  --output none
  
az backup policy create `
  --backup-management-type AzureIaasVM `
  --name $ResourceGroupName-Policy `
  --resource-group $ResourceGroupName `
  --vault-name $ResourceGroupName-Vault `
  --output none `
  --policy '{\"eTag\": null,\"id\":\"/Subscription/$subscription/resourceGroups/$ResourceGroupName/providers/Microsoft.RecoveryServices/vaults/$ResourceGroupName-Vault/backupPolicies/$ResourceGroupName-Policy\",\"location\": null,\"name\":\"$ResourceGroupName-Policy\",\"properties\":{\"backupManagementType\":\"AzureIaasVM\",\"instantRpDetails\":{\"azureBackupRgNamePrefix\":null,\"azureBackupRgNameSuffix\":null},\"instantRpRetentionRangeInDays\":2,\"protectedItemsCount\":0,\"retentionPolicy\":{\"dailySchedule\":{\"retentionDuration\":{\"count\":7,\"durationType\":\"Days\"},\"retentionTimes\":[\"2021-01-01T04:30:00+00:00\"]},\"monthlySchedule\": null,\"retentionPolicyType\":\"LongTermRetentionPolicy\",\"weeklySchedule\":null,\"yearlySchedule\":null},\"schedulePolicy\":{\"schedulePolicyType\":\"SimpleSchedulePolicy\",\"scheduleRunDays\":null,\"scheduleRunFrequency\":\"Daily\",\"scheduleRunTimes\":[\"2021-01-01T04:30:00+00:00\"],\"scheduleWeeklyFrequency\":0},\"timeZone\":\"UTC\"},\"resourceGroup\":\"$ResourceGroupName\",\"tags\":null,\"type\":\"Microsoft.RecoveryServices/vaults/backupPolicies\"}'
  
#az backup protection enable-for-vm `
#  --resource-group $ResourceGroupName `
#  --vault-name $ResourceGroupName-Vault `
#  --vm $VM1Name `
#  --policy-name $ResourceGroupName-Policy `
#  --output none

#az backup protection enable-for-vm `
#  --resource-group $ResourceGroupName `
#  --vault-name $ResourceGroupName-Vault `
#  --vm $VM2Name `
#  --policy-name $ResourceGroupName-Policy `
#  --output none

# CONTAINERS
Write-Host ------------------------------
Write-Host Criando a ACR e KeyVault

az acr create `
  --resource-group $ResourceGroupName `
  --name $ACRName `
  --sku Basic `
  --output none

git clone $GitRepoACI 1> $null 2> $null

az acr build `
  --registry $ACRName `
  --image $ACRImageRelease ./$GitRepoACIPath `
  --output none 1> $null 2> $null

az keyvault create `
  --resource-group $ResourceGroupName `
  --name $KeyVaultName `
  --output none 
  
az keyvault secret set `
  --vault-name $KeyVaultName `
  --name pull-pwd `
  --value $(az ad sp create-for-rbac `
  --name $ACRName-pull `
  --scopes $(az acr show --name $ACRName --query id --output tsv) `
  --role acrpull `
  --query password `
  --output tsv) `
  --output none 1> $null 2> $null
				
az keyvault secret set `
  --vault-name $KeyVaultName `
  --name pull-usr `
  --value $(az ad sp show --id http://$ACRName-pull --query appId --output tsv) `
  --output none 
	
$KeyVaultUser=(az keyvault secret show --vault-name $KeyVaultName --name pull-usr --query value -o tsv)
$KeyVaultPass=(az keyvault secret show --vault-name $KeyVaultName --name pull-pwd --query value -o tsv)

Write-Host ------------------------------
Write-Host Montando o disco extra das VMs

az vm extension set `
  --publisher Microsoft.Azure.Extensions `
  --version 2.0 `
  --name CustomScript `
  --vm-name $VM1Name `
  --resource-group $ResourceGroupName `
  --settings "{'commandToExecute':'sudo parted /dev/sdc --script mklabel gpt mkpart xfspart xfs 0% 100% && sudo mkfs.xfs /dev/sdc1 && sudo partprobe /dev/sdc1 && sudo mkdir /mnt/$VM1Name-Extra && sudo mount /dev/sdc1 /mnt/$VM1Name-Extra && sudo echo /dev/sdc1  /mnt/$VM1Name-Extra   xfs   defaults,nofail   1   2 >> /etc/fstab'}" `
  --output none
  
az vm extension set `
  --publisher Microsoft.Azure.Extensions `
  --version 2.0 `
  --name CustomScript `
  --vm-name $VM2Name `
  --resource-group $ResourceGroupName `
  --settings "{'commandToExecute':'sudo parted /dev/sdc --script mklabel gpt mkpart xfspart xfs 0% 100% && sudo mkfs.xfs /dev/sdc1 && sudo partprobe /dev/sdc1 && sudo mkdir /mnt/$VM2Name-Extra && sudo mount /dev/sdc1 /mnt/$VM2Name-Extra && sudo echo /dev/sdc1  /mnt/$VM2Name-Extra   xfs   defaults,nofail   1   2 >> /etc/fstab'}" `
  --output none

Write-Host ------------------------------
Write-Host Criando o Container no ACI

$ContainerURL=(az container create `
    --resource-group $ResourceGroupName `
    --name $ACIName `
    --image "$ACRName.azurecr.io/$ACRImageRelease" `
    --registry-login-server "$ACRName.azurecr.io" `
    --registry-username $KeyVaultUser `
    --registry-password $KeyVaultPass `
    --dns-name-label $ACRName `
    --query "{FQDN:ipAddress.fqdn}" `
    --output tsv) 

Write-Host ------------------------------
Write-Host Deploy Finalizado!
echo "VM Username: $AdminUsername"
echo "VM Password: $AdminPassword"
echo "LoadBalancer: http://$LBpip/"
echo "Container: http://$ContainerURL/"