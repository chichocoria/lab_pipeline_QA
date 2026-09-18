#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# Script para eliminar TODOS los recursos del laboratorio.
# ATENCION: esto borra el Resource Group y todo lo que contiene.
# =============================================================================

RG="rg-lab-portalcorredor"

read -p "¿Estas seguro de eliminar el Resource Group '$RG'? [s/N]: " confirm
if [[ "$confirm" != "s" && "$confirm" != "S" ]]; then
  echo "Cancelado."
  exit 0
fi

if az group show --name "$RG" &>/dev/null; then
  echo "Eliminando Resource Group '$RG'..."
  az group delete --name "$RG" --yes --no-wait
  echo "Eliminacion iniciada en segundo plano. Puede tardar varios minutos."
else
  echo "El Resource Group '$RG' no existe."
fi
