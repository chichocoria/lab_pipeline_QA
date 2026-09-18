#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script idempotente para crear recursos de Azure del laboratorio CI/CD.
# Si un recurso ya existe, lo omite. Si falla algo, se detiene.
# =============================================================================

# Variables configurables
RG="rg-lab-portalcorredor"
LOCATION="eastus"
PLAN="asp-lab-corredor"
APP="web-lab-corredor-back"
IDENTITY="id-lab-corredor-app"

# El nombre del Key Vault debe ser globalmente unico. Si ya existe una
# ejecucion previa, se reutiliza el mismo nombre buscandolo en el RG.
KV=$(az keyvault list --resource-group "$RG" --query "[?starts_with(name,'kv-lab-corredor-')].name | [0]" -o tsv 2>/dev/null || true)
if [ -z "$KV" ]; then
  KV="kv-lab-corredor-${RANDOM}"
fi

# Colores para la salida
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Obtener IDs actuales
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
TENANT_ID=$(az account show --query tenantId -o tsv)
USER_OID=$(az ad signed-in-user show --query id -o tsv)

info "Subscription ID: $SUBSCRIPTION_ID"
info "Tenant ID:       $TENANT_ID"
info "User OID:        $USER_OID"

# =============================================================================
# 1. Resource Group
# =============================================================================
if az group show --name "$RG" &>/dev/null; then
  warn "Resource Group '$RG' ya existe. Se omite la creacion."
else
  info "Creando Resource Group '$RG'..."
  az group create --name "$RG" --location "$LOCATION"
fi

# =============================================================================
# 2. App Service Plan
# =============================================================================
if az appservice plan show --name "$PLAN" --resource-group "$RG" &>/dev/null; then
  warn "App Service Plan '$PLAN' ya existe. Se omite la creacion."
else
  info "Creando App Service Plan '$PLAN'..."
  az appservice plan create \
    --name "$PLAN" \
    --resource-group "$RG" \
    --sku B1 \
    --is-linux \
    --number-of-workers 1
fi

# =============================================================================
# 3. Web App
# =============================================================================
if az webapp show --name "$APP" --resource-group "$RG" &>/dev/null; then
  warn "Web App '$APP' ya existe. Se omite la creacion."
else
  info "Creando Web App '$APP'..."
  az webapp create \
    --name "$APP" \
    --resource-group "$RG" \
    --plan "$PLAN" \
    --runtime "DOTNETCORE:8.0"
fi

# =============================================================================
# 4. Key Vault (sin RBAC de autorizacion para usar access policies)
# =============================================================================
if az keyvault show --name "$KV" --resource-group "$RG" &>/dev/null; then
  warn "Key Vault '$KV' ya existe. Se omite la creacion."
else
  info "Creando Key Vault '$KV'..."
  az keyvault create \
    --name "$KV" \
    --resource-group "$RG" \
    --location "$LOCATION" \
    --sku standard \
    --enable-rbac-authorization false
fi

# =============================================================================
# 5. Managed Identity asignada por el usuario
# =============================================================================
if az identity show --name "$IDENTITY" --resource-group "$RG" &>/dev/null; then
  warn "Managed Identity '$IDENTITY' ya existe. Se omite la creacion."
else
  info "Creando Managed Identity '$IDENTITY'..."
  az identity create --name "$IDENTITY" --resource-group "$RG"
fi

IDENTITY_ID=$(az identity show --name "$IDENTITY" --resource-group "$RG" --query id -o tsv)
CLIENT_ID=$(az identity show --name "$IDENTITY" --resource-group "$RG" --query clientId -o tsv)
PRINCIPAL_ID=$(az identity show --name "$IDENTITY" --resource-group "$RG" --query principalId -o tsv)

info "Managed Identity Client ID:  $CLIENT_ID"
info "Managed Identity Principal ID: $PRINCIPAL_ID"

# =============================================================================
# 6. Asignar identidad al App Service
# =============================================================================
info "Asignando identidad administrada al App Service '$APP'..."
az webapp identity assign \
  --name "$APP" \
  --resource-group "$RG" \
  --identities "$IDENTITY_ID"

# =============================================================================
# 7. Dar permisos al usuario actual sobre Key Vault (para crear secretos)
# =============================================================================
info "Asignando rol 'Key Vault Secrets Officer' al usuario actual..."
az role assignment create \
  --role "Key Vault Secrets Officer" \
  --assignee-object-id "$USER_OID" \
  --assignee-principal-type User \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourcegroups/$RG/providers/Microsoft.KeyVault/vaults/$KV" \
  2>/dev/null || warn "El rol ya estaba asignado o la propagacion aun no termina."

# =============================================================================
# 8. Dar permisos a la Managed Identity sobre Key Vault (solo GET/LIST)
# =============================================================================
info "Asignando rol 'Key Vault Secrets User' a la Managed Identity..."
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee-object-id "$PRINCIPAL_ID" \
  --assignee-principal-type ServicePrincipal \
  --scope "/subscriptions/$SUBSCRIPTION_ID/resourcegroups/$RG/providers/Microsoft.KeyVault/vaults/$KV" \
  2>/dev/null || warn "El rol ya estaba asignado o la propagacion aun no termina."

# Esperar propagacion de roles (puede tardar unos segundos)
info "Esperando 15 segundos por la propagacion de roles..."
sleep 15

# =============================================================================
# 9. Crear secretos de ejemplo en Key Vault
# Las contrasenas usan comillas simples para evitar que bash interprete '!'
# =============================================================================
info "Creando secretos en Key Vault '$KV'..."

az keyvault secret set \
  --vault-name "$KV" \
  --name "DatabaseSettings--ConnectionString" \
  --value 'Server=tcp:lab-sql.database.windows.net;Database=LabDB;User ID=labuser;Password=P@ssw0rd123!;'

az keyvault secret set \
  --vault-name "$KV" \
  --name "Mailserver--Password" \
  --value 'lab-mail-password-2024!'

az keyvault secret set \
  --vault-name "$KV" \
  --name "ExternalServices--Sunat--ApiKey" \
  --value 'lab-sunat-api-key-2024!'

# =============================================================================
# 10. Configurar Application Settings del App Service
# =============================================================================
info "Configurando Application Settings del App Service '$APP'..."

az webapp config appsettings set \
  --name "$APP" \
  --resource-group "$RG" \
  --settings \
    "ASPNETCORE_ENVIRONMENT=QA" \
    "KeyVault__Name=$KV" \
    "DatabaseSettings__ConnectionString=@Microsoft.KeyVault(SecretUri=https://$KV.vault.azure.net/secrets/DatabaseSettings--ConnectionString/)" \
    "Mailserver__Password=@Microsoft.KeyVault(SecretUri=https://$KV.vault.azure.net/secrets/Mailserver--Password/)" \
    "ExternalServices__Sunat__ApiKey=@Microsoft.KeyVault(SecretUri=https://$KV.vault.azure.net/secrets/ExternalServices--Sunat--ApiKey/)"

# =============================================================================
# 11. Resumen final
# =============================================================================
echo ""
echo "=================================================================="
echo "  LABORATORIO CREADO CORRECTAMENTE"
echo "=================================================================="
echo "Web App URL:      https://$APP.azurewebsites.net"
echo "Key Vault Name:   $KV"
echo "Client ID:        $CLIENT_ID"
echo "Tenant ID:        $TENANT_ID"
echo "Subscription ID:  $SUBSCRIPTION_ID"
echo ""
echo "Configura estos valores como GitHub Secrets:"
echo "  AZURE_USER_ASSIGNED_CLIENT_ID = $CLIENT_ID"
echo "  AZURE_TENANT_ID               = $TENANT_ID"
echo "  AZURE_SUBSCRIPTION_ID         = $SUBSCRIPTION_ID"
echo ""
echo "Endpoints de prueba (despues del primer despliegue):"
echo "  https://$APP.azurewebsites.net/"
echo "  https://$APP.azurewebsites.net/health"
echo "  https://$APP.azurewebsites.net/config"
echo "=================================================================="
