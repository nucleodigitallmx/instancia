#!/bin/bash
# =====================================================================
# SCRIPT DE REINTENTOS PARA CREACIÓN DE INSTANCIA ALWAYS FREE (OCI)
# =====================================================================

# Validar variables de entorno requeridas
if [ -z "$COMPARTMENT_ID" ] || [ -z "$SUBNET_ID" ] || [ -z "$SSH_PUBLIC_KEY" ]; then
    echo "Error: Las variables COMPARTMENT_ID, SUBNET_ID o SSH_PUBLIC_KEY no están definidas."
    exit 1
fi

# Guardar la llave pública en un archivo temporal requerido por la CLI de OCI
SSH_KEY_FILE="/tmp/authorized_keys.pub"
echo "$SSH_PUBLIC_KEY" > "$SSH_KEY_FILE"
chmod 600 "$SSH_KEY_FILE"

echo "=== Consultando Datos de Infraestructura en Monterrey ==="

# Obtener el primer Availability Domain de forma dinámica
AD_NAME=$(oci iam availability-domain list --compartment-id "$COMPARTMENT_ID" --query "data[0].name" --raw-output)
if [ -z "$AD_NAME" ]; then
    echo "Error: No se pudo obtener la Zona de Disponibilidad (Availability Domain)."
    exit 1
fi
echo "Zona de Disponibilidad detectada: $AD_NAME"

# Obtener dinámicamente el ID de la última imagen de Oracle Linux 8 para arquitectura x86_64
echo "Consultando última imagen oficial de Oracle Linux 8..."
IMAGE_ID=$(oci compute image list --compartment-id "$COMPARTMENT_ID" --operating-system "Oracle Linux" --operating-system-version "8" --shape "VM.Standard.E2.1.Micro" --query "data[0].id" --raw-output)
if [ -z "$IMAGE_ID" ]; then
    echo "Error: No se pudo encontrar un ID de imagen válido para Oracle Linux 8."
    exit 1
fi
echo "Imagen de Oracle Linux 8 seleccionada: $IMAGE_ID"

# Configuración del temporizador de seguridad de 5.5 horas (19800 segundos)
# Esto previene que el pipeline de GitHub Actions sea abortado de forma abrupta
MAX_DURATION=19800
START_TIME=$(date +%s)
ATTEMPT_COUNT=1

echo "=== Iniciando Bucle de Reintentos (Forma Gratuita: VM.Standard.E2.1.Micro) ==="

while true; do
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))

    if [ $ELAPSED -ge $MAX_DURATION ]; then
        echo "Límite de tiempo de ejecución de seguridad alcanzado (5.5 horas)."
        echo "Finalizando para evitar bloqueos. Por favor, reinicia el Workflow manualmente si es necesario."
        rm -f "$SSH_KEY_FILE"
        exit 0
    fi

    echo "--------------------------------------------------------"
    echo "Intento de creación número: $ATTEMPT_COUNT (Transcurrido: ${ELAPSED}s / ${MAX_DURATION}s)"
    echo "--------------------------------------------------------"

    ERROR_LOG="/tmp/oci_error.log"

    # Comando de creación de la instancia de cómputo Always Free
    RESPONSE=$(oci compute instance launch \
      --availability-domain "$AD_NAME" \
      --compartment-id "$COMPARTMENT_ID" \
      --shape "VM.Standard.E2.1.Micro" \
      --subnet-id "$SUBNET_ID" \
      --display-name "Instancia_Rescate_AlwaysFree" \
      --image-id "$IMAGE_ID" \
      --ssh-authorized-keys-file "$SSH_KEY_FILE" \
      2> "$ERROR_LOG")

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        echo "========================================================"
        echo "¡ÉXITO! La instancia gratuita ha sido creada."
        echo "========================================================"
        echo "Respuesta de OCI:"
        echo "$RESPONSE"
        rm -f "$SSH_KEY_FILE" "$ERROR_LOG"
        exit 0
    else
        echo "Intento fallido."
        echo "Error devuelto por la API de OCI:"
        cat "$ERROR_LOG"
        echo ""
        
        # Espera de 60 segundos regulada para no saturar las llamadas a la API
        echo "Esperando 60 segundos antes de realizar el próximo intento..."
        sleep 60
    fi

    ATTEMPT_COUNT=$((ATTEMPT_COUNT + 1))
done
