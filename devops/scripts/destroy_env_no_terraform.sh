#!/bin/bash

# This script deletes a specific deployment of TRE including resource
# groups of the managment (ops) part, core as well as all workspace ones.
# It's doing this by finding all resource groups that start with the same
# name as the core one!
# If possible it will purge the keyvault making it possible to reuse the same
# TRE_ID for a later deployment.

set -o errexit
set -o pipefail
# set -o xtrace

function usage() {
    cat <<USAGE

    Usage: $0 --core-tre-rg "something" [--no-wait]

    Options:
        --core-tre-rg   The core resource group name of the TRE.
        --no-wait       Doesn't wait for delete operations to complete and exits asap.
USAGE
    exit 1
}

# if no arguments are provided, return usage function
if [ $# -eq 0 ]; then
    usage # run usage function
fi

no_wait=false

while [ "$1" != "" ]; do
    case $1 in
    --core-tre-rg)
        shift
        core_tre_rg=$1
        ;;
    --no-wait)
        no_wait=true
        ;;
    *)
        echo "Unexpected argument: '$1'"
        usage
        ;;
    esac

    if [[ -z "$2" ]]; then
      # if no more args then stop processing
      break
    fi

    shift # remove the current value for `$1` and use the next
done

# done with processing args and can set this
set -o nounset

if [[ -z ${core_tre_rg:-} ]]; then
    echo "Core TRE resource group name wasn't provided"
    usage
fi

no_wait_option=""
if ${no_wait}
then
  no_wait_option="--no-wait"
fi

locks=$(az group lock list -g ${core_tre_rg} --query [].id -o tsv)
if [ ! -z "${locks:-}" ]
then
  az resource lock delete --ids ${locks}
fi

# purge keyvault if possible (makes it possible to reuse the same tre_id later)
# this has to be done before we delete the resource group since we don't wait for it to complete
if [[ $(az keyvault list --resource-group ${core_tre_rg} --query '[?proterties.enablePurgeProtection==null] | length (@)') != 0 ]]; then
  tre_id=${core_tre_rg#"rg-"}
  keyvault_name="kv-${tre_id}"

  echo "Deleting keyvault: ${keyvault_name}"
  az keyvault delete --name ${keyvault_name} --resource-group ${core_tre_rg}

  echo "Purging keyvault: ${keyvault_name}"
  az keyvault purge --name ${keyvault_name}
fi

# this will find the mgmt, core resource groups as well as any workspace ones
az group list --query "[?starts_with(name, '${core_tre_rg}')].[name]" -o tsv |
while read -r rg_item; do
  echo "Deleting resource group: ${rg_item}"
  az group delete --resource-group "${rg_item}" --yes ${no_wait_option}
done