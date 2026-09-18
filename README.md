# Laboratorio CI/CD - Azure App Service + Key Vault

Este laboratorio es una versión reducida del otro proyecto. Su objetivo es practicar el mismo flujo de CI/CD que el proyecto grande pero sin la complejidad del código real.

## Qué se practica

- CI con GitHub Actions al hacer PR a `qa` o `main`.
- Creación automática de un GitHub Release con un ZIP.
- CD manual con `workflow_dispatch` que descarga el release y despliega a Azure App Service.
- Lectura de secretos desde **Azure Key Vault** usando una **Managed Identity asignada por el usuario**.
- Convención de variables de entorno con `__` (doble guion bajo).

---

## Estructura del laboratorio

```text
lab/
├── .github/
│   └── workflows/
│       ├── ci-back-qa-prod.yaml      # CI: build + release
│       └── deploybackend-qa.yaml     # CD: deploy a Azure
├── src/
│   └── LabCorredor.Api/
│       ├── appsettings.json
│       ├── appsettings.Development.json
│       ├── appsettings.Local.example.json
│       ├── appsettings.Production.json
│       ├── appsettings.QA.json
│       ├── LabCorredor.Api.csproj
│       └── Program.cs
├── .gitignore
├── LabCorredor.sln
└── README.md
```

---

## Requisitos previos

- Cuenta de GitHub.
- Suscripción de Azure (de prueba o pago por uso).
- Azure CLI instalado o usar **Azure Cloud Shell**.

---

## Paso 1: Crear los recursos en Azure

Ejecutar en Azure Cloud Shell o localmente (con `az login` previo):

```bash
# Variables
RG="rg-lab-portalcorredor"
LOCATION="eastus"
PLAN="asp-lab-corredor"
APP="web-lab-corredor-back"
KV="kv-lab-corredor-$RANDOM"
IDENTITY="id-lab-corredor-app"

# Grupo de recursos
az group create --name $RG --location $LOCATION

# App Service Plan (B1 es el más económico para pruebas)
az appservice plan create \
  --name $PLAN \
  --resource-group $RG \
  --sku B1 \
  --is-linux \
  --number-of-workers 1

# Web App con .NET 8
az webapp create \
  --name $APP \
  --resource-group $RG \
  --plan $PLAN \
  --runtime "DOTNETCORE:8.0"

# Key Vault
az keyvault create \
  --name $KV \
  --resource-group $RG \
  --location $LOCATION \
  --sku standard

# Identidad administrada asignada por el usuario
az identity create \
  --name $IDENTITY \
  --resource-group $RG

# Obtener IDs de la identidad
IDENTITY_ID=$(az identity show --name $IDENTITY --resource-group $RG --query id -o tsv)
CLIENT_ID=$(az identity show --name $IDENTITY --resource-group $RG --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show --name $IDENTITY --resource-group $RG --query principalId -o tsv)

# Asignar identidad al App Service
az webapp identity assign \
  --name $APP \
  --resource-group $RG \
  --identities $IDENTITY_ID

# Dar permiso a la identidad sobre Key Vault
az keyvault set-policy \
  --name $KV \
  --object-id $PRINCIPAL_ID \
  --secret-permissions get list

# Crear secretos de ejemplo en Key Vault
az keyvault secret set \
  --vault-name $KV \
  --name "DatabaseSettings--ConnectionString" \
  --value "Server=tcp:lab-sql.database.windows.net;Database=LabDB;User ID=labuser;Password=P@ssw0rd!;"

az keyvault secret set \
  --vault-name $KV \
  --name "Mailserver--Password" \
  --value "lab-mail-password-123"

az keyvault secret set \
  --vault-name $KV \
  --name "ExternalServices--Sunat--ApiKey" \
  --value "lab-sunat-apikey-456"

# Configurar Application Settings del App Service
az webapp config appsettings set \
  --name $APP \
  --resource-group $RG \
  --settings \
    "ASPNETCORE_ENVIRONMENT=QA" \
    "KeyVault__Name=$KV"

# Mostrar valores importantes
echo "Key Vault Name: $KV"
echo "Client ID:      $CLIENT_ID"
echo "Tenant ID:      $(az account show --query tenantId -o tsv)"
echo "Subscription ID:$(az account show --query id -o tsv)"
```

> Guardar los valores mostrados al final, se necesitan en el paso 3.

---

## Paso 2: Subir el código a GitHub

1. Crear un repositorio nuevo en GitHub (por ejemplo `lab-corredor-cicd`).
2. Subir el contenido de esta carpeta `lab/` a la raíz del nuevo repo.
3. Crear la rama `qa` desde `main`:

```bash
git checkout -b qa
git push origin qa
```

---

## Paso 3: Configurar GitHub Secrets

En el repo nuevo, ir a:

```text
Settings → Secrets and variables → Actions → New repository secret
```

Crear estos secrets:

| Nombre | Valor |
|--------|-------|
| `AZURE_USER_ASSIGNED_CLIENT_ID` | Client ID de la identidad administrada |
| `AZURE_TENANT_ID` | Tenant ID de Azure |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID de Azure |

---

## Paso 4: Probar el flujo CI/CD

### 4.1 Crear un Pull Request a `qa`

1. Crear una rama feature desde `qa`:

```bash
git checkout -b feature/mi-primer-cambio
```

2. Hacer un cambio menor (por ejemplo, modificar el mensaje en `Program.cs`).
3. Hacer push y crear PR a `qa`.

```bash
git push origin feature/mi-primer-cambio
```

4. En GitHub, mergear el PR a `qa`.

Esto dispara automáticamente `CI-Lab-Corredor-QA-Prod`, que:

- Compila la API.
- Crea el ZIP `lab-corredor-api-v1.0.0.zip`.
- Crea un GitHub Release con tag `v1.0.0`.

### 4.2 Desplegar a Azure App Service

1. Ir a **Actions → Deploy-Lab-Corredor-QA → Run workflow**.
2. Dejar el campo `deploy_version` vacío para usar la versión del `.csproj` (`1.0.0`).
3. Ejecutar el workflow.

Esto:

- Descarga el release `v1.0.0`.
- Se autentica en Azure con la Managed Identity.
- Despliega el ZIP al App Service.

---

## Paso 5: Verificar el despliegue

Esperar unos minutos y probar:

```text
https://web-lab-corredor-back.azurewebsites.net/
https://web-lab-corredor-back.azurewebsites.net/health
https://web-lab-corredor-back.azurewebsites.net/config
```

El endpoint `/config` debe mostrar los secretos enmascarados, por ejemplo:

```json
{
  "databaseConnectionString": "Ser...rd!;",
  "mailserverPassword": "lab...123",
  "sunatApiKey": "lab...456",
  "keyVaultName": "kv-lab-corredor-XXXXX"
}
```

Si alguno dice `(vacío)`, significa que no llegó correctamente desde Key Vault o las Application Settings.

---

## Posibles problemas y soluciones

| Problema | Causa probable | Solución |
|----------|---------------|----------|
| El deploy falla con error de autenticación de Azure | El federated credential no está configurado o el secret es incorrecto | Revisar `AZURE_USER_ASSIGNED_CLIENT_ID`, `AZURE_TENANT_ID` y `AZURE_SUBSCRIPTION_ID` |
| `/config` muestra `(vacío)` | Key Vault no tiene el secreto o la identidad no tiene permiso | Revisar `az keyvault secret list` y `az keyvault set-policy` |
| El App Service no arranca | La identidad no tiene acceso al Key Vault o falta alguna app setting | Revisar logs en **Monitoring → Log stream** del App Service |
| No se encuentra el release | El tag no coincide con la versión del `.csproj` | Asegurar que el release tenga tag `v1.0.0` |

---

## Próximos experimentos sugeridos

1. Cambiar la versión en `LabCorredor.Api.csproj`, mergear a `qa` y desplegar la nueva versión.
2. Agregar un nuevo secreto en Key Vault, exponerlo por `/config` y ver cómo llega sin redeploy del código.
3. Probar el mismo flujo con una PR a `main`.
4. Simular PROD cambiando el nombre del App Service en `deploybackend-qa.yaml`.

---

## Diferencias clave con el proyecto grande

| Aspecto | Proyecto grande | Este laboratorio |
|---------|-----------------|------------------|
| Proyecto .NET | `Portal.Corredor.Web` | `LabCorredor.Api` |
| App Service | `web-portalcorredor-back` | `web-lab-corredor-back` |
| Recursos Azure | Existentes en suscripción de Crecer | Se crean con los comandos de arriba |
| Runner | `self-hosted` | `ubuntu-latest` (runner de GitHub) |
| Código | API completa con lógica de negocio | 3 endpoints simples |

---

## Referencias

- [GitHub Actions: azure/login](https://github.com/Azure/login)
- [GitHub Actions: azure/webapps-deploy](https://github.com/Azure/webapps-deploy)
- [Azure Key Vault references in App Service](https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references)
- [ASP.NET Core configuration](https://learn.microsoft.com/en-us/aspnet/core/fundamentals/configuration/)
