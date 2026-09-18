# Laboratorio CI/CD - Azure App Service + Key Vault

Este laboratorio es una versión reducida del proyecto **Portal Corredor**. Su objetivo es practicar el mismo flujo de CI/CD que el proyecto grande pero sin la complejidad del código real.

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
├── scripts/
│   ├── create-azure-resources.sh     # Script idempotente para crear recursos
│   └── delete-azure-resources.sh     # Script para limpiar recursos
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

El laboratorio incluye un script idempotente que:

- Omite recursos que ya existan.
- Usa **RBAC** en lugar de access policies para Key Vault.
- Crea secretos de ejemplo.
- Configura Application Settings con referencias a Key Vault.
- Muestra al final los valores para configurar en GitHub Secrets.

### Opción A: Script automatizado (recomendada)

Subir `scripts/create-azure-resources.sh` a Azure Cloud Shell o ejecutarlo localmente (requiere `az login`):

```bash
cd lab/scripts
chmod +x create-azure-resources.sh
./create-azure-resources.sh
```

El script imprime al final algo como:

```text
Key Vault Name:   kv-lab-corredor-16698
Client ID:        adbcf612-1c50-4dea-994b-6ca562b43d2e
Tenant ID:        bede8a65-db66-48bb-8fac-2b44a389f86f
Subscription ID:  d4e1cec3-29c3-42ab-85d2-b34626adfb59
```

Guardar estos valores, se necesitan en el paso 3.

### Opción B: Comandos manuales

Si prefieres crear paso a paso, los comandos equivalentes están en `scripts/create-azure-resources.sh`.

### Limpiar recursos

Para borrar todo el laboratorio:

```bash
cd lab/scripts
chmod +x delete-azure-resources.sh
./delete-azure-resources.sh
```

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
