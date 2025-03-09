#!/bin/bash

set -e

eval $(azd env get-values)

: ${NOPROMPT=false}
: ${VERBOSE=false}
: ${AZ_ARGS="-g $AZURE_RESOURCE_GROUP_NAME -n $AZURE_CONTAINER_APPS_APP_NAME"}
: ${AZ_REVISION=}
: ${AZ_REPLICA=}
: ${AZ_CONTAINER=nginx}

NL=$'\n'

msg() {
	echo ">>> $*" >&2
}

run() {
   	msg "Running: $@"
	"$@"
}

confirm() {
	if $NOPROMPT; then
		return
	fi
	read -p ">>> Continue? [y/N] " -n 1 -r >&2
	echo >&2
	case "$REPLY" in
		[yY]) return
	esac
	exit 1
}

app_hostnames() {
	HOSTNAMES=$(az containerapp hostname list $AZ_ARGS --query [].name -o tsv)
	if test -z "$HOSTNAMES"; then
		HOSTNAMES=$(az containerapp show $ARGS --query properties.configuration.ingress.fqdn -o tsv)
	fi
	echo $HOSTNAMES
}

cmd_meid_redirect() {
	HOSTS=$(app_hostnames)
	URIS=$(az ad app show --id $MS_CLIENT_ID --query web.redirectUris -o tsv)
	for HOST in $HOSTS; do
		URIS="https://${HOST}/.auth/login/aad/callback${NL}${URIS}"
	done
	URIS=$(echo "$URIS" | sort | uniq)
	msg "ME-ID App Client ID:    ${MS_CLIENT_ID}"
	msg "ME-ID App Redirect URI: ${URI}"
	msg "Updating new Redirect URIs:${NL}${URIS}"
	confirm
	run az ad app update --id $MS_CLIENT_ID --web-redirect-uris $URIS
}

cmd_meid_secret() {
	HOSTS=$(app_hostnames)
	CRED_TIME=$(date +%s)
	CRED_NAME="$HOSTS $CRED_TIME"
	msg "ME-ID App Client ID: ${MS_CLIENT_ID}"
	msg "Adding new Client Secret for $HOSTS"
	confirm
	msg "ME-ID App new credential name: $CRED_NAME"
	PASSWORD=$(az ad app credential reset --id $MS_CLIENT_ID --append --display-name "$CRED_NAME" --end-date 2299-12-31 --query password -o tsv 2>/dev/null)
	run az keyvault secret set --vault-name $AZURE_KEY_VAULT_NAME --name MS-CLIENT-SECRET --file <(echo -n "$PASSWORD") >/dev/null
	run az containerapp revision copy $AZ_ARGS --revision-suffix $CRED_TIME >/dev/null
}

cmd_data_get() {
	if test $# -lt 2; then
		msg 'Specify remote/local paths'
		exit 1
	fi
	run az storage file download --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p "$1" --dest "$2" >/dev/null
}

cmd_data_put() {
	if test $# -lt 2; then
		msg 'Specify remote/local paths'
		exit 1
	fi
	run az storage file upload --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME -s data -p "$1" --source "$2" >/dev/null
}

cmd_aca_show() {
	run az containerapp show -g $AZURE_RESOURCE_GROUP_NAME -n $AZURE_CONTAINER_APPS_APP_NAME
}

cmd_aca_revisions() {
	ARGS="$AZ_ARGS"
	if ! $VERBOSE; then
		ARGS="$ARGS --query [].{revision:name,created:properties.createdTime,state:properties.runningState,weight:properties.trafficWeight} -o table"
	fi
	run az containerapp revision list $ARGS
}

cmd_aca_replicas() {
	ARGS="$AZ_ARGS"
	if test -n "$AZ_REVISION"; then
		ARGS="$ARGS --revision $AZ_REVISION"
	fi
	if ! $VERBOSE; then
		ARGS="$ARGS --query [].{replica:name,created:properties.createdTime,state:properties.runningState} -o table"
	fi
	run az containerapp replica list $ARGS
}

cmd_aca_hostnames() {
	ARGS="$AZ_ARGS"
	if ! $VERBOSE; then
		ARGS="$ARGS --query [].{hostname:name} -o table"
	fi
	run az containerapp hostname list $ARGS
}

cmd_aca_logs() {
	ARGS="$AZ_ARGS --container $AZ_CONTAINER"
	if test -n "$AZ_REVISION"; then
		ARGS="$ARGS --revision $AZ_REVISION"
	fi
	if test -n "$AZ_REPLICA"; then
		ARGS="$ARGS --replica $AZ_REPLICA"
	fi
	if ! $VERBOSE; then
		ARGS="$ARGS --format text"
	fi
	if test "$1" = 'follow'; then
		ARGS="$ARGS --follow"
	fi
	run az containerapp logs show $ARGS
}

cmd_aca_console() {
	ARGS="$AZ_ARGS --container $AZ_CONTAINER"
	if test -n "$AZ_REVISION"; then
		ARGS="$ARGS --revision $AZ_REVISION"
	fi
	if test -n "$AZ_REPLICA"; then
		ARGS="$ARGS --replica $AZ_REPLICA"
	fi
	CMD="$*"
	if test -z "$CMD"; then
		CMD=bash
	fi
	run az containerapp exec $ARGS --command "$CMD"
	run stty sane
}

cmd_aca_restart() {
	if test -z "$AZ_REVISION"; then
		AZ_REVISION=$(az containerapp show -g $AZURE_RESOURCE_GROUP_NAME -n $AZURE_CONTAINER_APPS_APP_NAME --query properties.latestRevisionName -o tsv)
	fi
	ARGS="$AZ_ARGS --revision $AZ_REVISION"
	msg "Restarting revision $AZ_REVISION..."
	confirm
	run az containerapp revision restart $ARGS
}

cmd_aca_lego() {
	export AZURE_AUTH_METHOD=cli
	export LEGO_DISABLE_CNAME_SUPPORT=true
	export LEGO_PATH=$(mktemp -d)
	if test "$DNS_RECORD_NAME" = '@'; then
		DNS_DOMAIN_NAME="${DNS_ZONE_NAME}"
	else
		DNS_DOMAIN_NAME="${DNS_RECORD_NAME}.${DNS_ZONE_NAME}"
	fi
    LEGO_CERT_PATH="${LEGO_PATH}/certificates/${DNS_DOMAIN_NAME}.crt"
	run az storage directory create --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME --share lego --name data >/dev/null
	run az storage file download-batch --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME --source lego/data --destination $LEGO_PATH
    if test -f "$LEGO_CERT_PATH"; then
        CMD="renew --renew-hook 'bash $0 aca-lego-hook'"
    else
        CMD="run --run-hook 'bash $0 aca-lego-hook'"
    fi
    eval run lego -a --server $LEGO_SERVER --email $LEGO_EMAIL --dns azuredns --dns.propagation-disable-ans -d "'$DNS_DOMAIN_NAME'" -d "'*.$DNS_DOMAIN_NAME'" --pfx "$CMD"
	rm -rf "$LEGO_PATH"
}

cmd_aca_lego_hook() {
	if test -z "$LEGO_CERT_PFX_PATH" -o -z "$LEGO_PATH"; then
		msg 'Missing LEGO_CERT_PFX_PATH or LEGO_PATH settings'
		exit 1
	fi
	run az keyvault certificate import --vault-name $AZURE_KEY_VAULT_NAME --name DNS-CERTIFICATE --file $LEGO_CERT_PFX_PATH --password changeit
	run az storage file upload-batch --only-show-errors --account-name $AZURE_STORAGE_ACCOUNT_NAME --source $LEGO_PATH --destination lego/data
}

cmd_portal_aca() {
	URL="https://portal.azure.com/#@${AZURE_TENANT_ID}/resource/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${AZURE_RESOURCE_GROUP_NAME}"
	run xdg-open "$URL"
}

cmd_portal_meid() {
	if test -z "$MS_TENANT_ID" -o -z "$MS_CLIENT_ID"; then
		msg 'Missing MS_TEANT_ID or MS_CLIENT_ID settings'
		exit 1
	fi
	URL="https://portal.azure.com/#@${MS_TENANT_ID}/view/Microsoft_AAD_RegisteredApps/ApplicationMenuBlade/~/Overview/appId/${MS_CLIENT_ID}"
	run xdg-open "$URL"
}

cmd_open() {
	HOSTS=$(app_hostnames)
	for HOST in $HOSTS; do
		if test "${HOST%%.*}" != "*"; then
			run xdg-open "https://${HOST}${APP_ROOT_PATH}"
			exit 0
		fi
	done
	msg 'No valid hostname found'
	exit 1
}

cmd_help() {
	msg "Usage: $0 <command> [options...] [args...]"
	msg "Options":
	msg "  --help,-h                  - Show this help"
	msg "  --no-prompt                - Do not ask for confirmation"
	msg "  --verbose, -v              - Show detailed output"
	msg "  --revision <name>          - Specify revision name"
	msg "  --replica <name>           - Specify replica name"
	msg "  --container <name>         - Specify container name"
	msg "Commands:"
	msg "  meid-redirect              - ME-ID: update app redirect URIs"
	msg "  meid-secret                - ME-ID: create new client secret"
	msg "  data-get <remote> <local>  - Data: download file"
	msg "  data-put <remote> <local>  - Data: upload file"
	msg "  aca-show                   - ACA: show app"
	msg "  aca-revisions              - ACA: list revisions"
	msg "  aca-replicas               - ACA: list replicas"
	msg "  aca-hostnames              - ACA: list hostnames"
	msg "  aca-restart                - ACA: restart revision"
	msg "  aca-logs [follow]          - ACA: show container logs"
	msg "  aca-console [command...]   - ACA: connect to container"
	msg "  aca-lego                   - ACA: LEGO certificate update"
	msg "  aca-lego-hook              - ACA: LEGO certificate update hook"
	msg "  portal-aca                 - Portal: open ACA resource group in browser"
	msg "  portal-meid                - Portal: open ME-ID app registration in browser"
	msg "  open                       - open app in browser"
	exit $1
}

OPTIONS=$(getopt -o hqv -l help -l no-prompt -l verbose -l revision: -l replica: -l container: -- "$@")
if test $? -ne 0; then
	cmd_help 1
fi

eval set -- "$OPTIONS"

while true; do
	case "$1" in
		-h|--help)
			cmd_help 0
			;;			
		--no-prompt)
			NOPROMPT=true
			shift
			;;
		-v|--verbose)
			VERBOSE=true
			shift
			;;
		--revision)
			AZ_REVISION=$2
			shift 2
			;;
		--replica)
			AZ_REPLICA=$2
			shift 2
			;;
		--container)
			AZ_CONTAINER=$2
			shift 2
			;;
		--)
			shift
			break
			;;
		*)
			msg "E: Invalid option: $1"
			cmd_help 1
			;;
	esac
done

if test $# -eq 0; then
	msg "E: Missing command"
	cmd_help 1
fi

case "$1" in
	meid-redirect)
		shift
		cmd_meid_redirect "$@"
		;;
	meid-secret)
		shift
		cmd_meid_secret "$@"
		;;
	data-get|download)
		shift
		cmd_data_get "$@"
		;;
	data-put|upload)
		shift
		cmd_data_put "$@"
		;;
	aca-show)
		shift
		cmd_aca_show "$@"
		;;
	aca-revisions)
		shift
		cmd_aca_revisions "$@"
		;;
	aca-replicas)
		shift
		cmd_aca_replicas "$@"
		;;
	aca-hostnames)
		shift
		cmd_aca_hostnames "$@"
		;;
	aca-logs)
		shift
		cmd_aca_logs "$@"
		;;
	aca-console)
		shift
		cmd_aca_console "$@"
		;;
	aca-restart)
		shift
		cmd_aca_restart "$@"
		;;
	aca-lego)
		shift
		cmd_aca_lego "$@"
		;;
	aca-lego-hook)
		shift
		cmd_aca_lego_hook "$@"
		;;
	portal-aca)
		shift
		cmd_portal_aca "$@"
		;;
	portal-meid)
		shift
		cmd_portal_meid "$@"
		;;
	open)
		shift
		cmd_open "$@"
		;;
	*)
		msg "E: Invalid command: $1"
		cmd_help 1
		;;
esac