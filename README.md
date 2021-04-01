# IGTI-Desafio2

## Desafio do segundo modulo do Bootcamp de Arquiteto Cloud Computing

## Sobre

O script foi criado em Powershell usando o Modulo AzureRM e o Azure CLI. 

## Topologia

![alt text](https://willianromaocursos.blob.core.windows.net/public/IGTI-Desafio2.png)

## Execução

Vá até o Portal do Azure e inicie uma sessão do Cloud Shell usando o terminal do Powershell e execute os comandos abaixo:

```powershell
git clone https://github.com/willianromao/IGTI-Desafio2.git
cd IGTI-Desafio2
./desafio2.ps1
```

### Observações

1-Após concluído o deploy do ambiente será necessário ativar o recurso Run As Account na conta do Azure Automation para que os scripts funcionem corretamente.

2-O agendamento do backup está comentado no script das linhas 466 a 478. O agendamento cria o travamento de segurança de 14 dias no Recovery Services Vault.
