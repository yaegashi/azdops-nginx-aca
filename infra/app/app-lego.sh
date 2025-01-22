#!/bin/sh
set -ex
if test -f "$LEGO_CERT_PFX_PATH"; then
    # Run as lego run/renew hook script
    # az issue workaround: https://github.com/microsoft/azure-container-apps/issues/502
    export APPSETTING_WEBSITE_SITE_NAME=azcli-workaround
    az login --identity --username $AZURE_CLIENT_ID
    az account set -s $AZURE_SUBSCRIPTION_ID
    az keyvault certificate import --vault-name $AZURE_KEY_VAULT_NAME --name DNS-CERTIFICATE --file $LEGO_CERT_PFX_PATH --password changeit
else
    # Run as lego run/renew command script
    LEGO_CERT_PATH="${LEGO_PATH}/certificates/${DNS_DOMAIN_NAME}.crt"
    if test -f "$LEGO_CERT_PATH"; then
        CMD="renew --renew-hook 'sh $0'"
    else
        CMD="run --run-hook 'sh $0'"
    fi
    # Use eval to expand single quotes in $CMD
    eval lego -a --email "$LEGO_EMAIL" --dns azuredns -d "$DNS_DOMAIN_NAME" -d "*.$DNS_DOMAIN_NAME" --pfx "$CMD"
fi
