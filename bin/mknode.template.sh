#!/bin/bash

export LC_CTYPE=C

# Require unprivileged user...
[[ ${EUID} = 0 ]] && { echo -e "This script should be run as non root, with sudo privileges account!\n"; exit 2; }

[[ -f "./.dc-installer-env" ]] && . ./.dc-installer-env;

#UVN_OS_VERSION=;
#DC_BASE_PATH=;

# Dragonchain
DC_CHAIN=
DC_TOKEN=

# Node
NODE_LEVEL=
NODE_NAME=
NODE_ADDR="${SRV_FQDN}";
NODE_PORT=
NODE_URL=

# Authentication hash/key
HMAC=

# Install dir
#[[ ! -d "${DC_BASE_PATH}" ]] && { mkdir -pm 0750 "${DC_BASE_PATH}"; chmod 0750 "$(dirname $##{DC_BASE_PATH})"; }

#cd ${DC_BASE_PATH};

# Retrieve installer env vars from disk
function get_env()
{
    [[ -f "${DC_ENV}" ]] && source "${DC_ENV}";
}

# Private key
function gen_secp256k1_key()
{
    # ToDo: Find alternatives. Split (gen/parse)
    #echo "`openssl ecparam -genkey -name secp256k1 | openssl ec -outform DER | tail -c +8 | head -c 32 | xxd -p -c 32 | xxd -r -p | base64`";
    echo "`openssl ecparam -genkey -name secp256k1 | openssl ec -outform DER | tail -c +8 | head -c 32 |  base64`";
}

# HMAC JSON data
function gen_hmac()
{
    local h="${1}";

    if [[ -z "${h}" || "x${h}" = "x" ]]; then
        local p="$(gen_secp256k1_key)";
        local i=$(tr -dc 'A-Z' < /dev/urandom | fold -w 12 | head -n 1);
        local k=$(tr -dc 'A-Za-z0-9' < /dev/urandom | fold -w 43 | head -n 1);

        echo "{\"private-key\":\"${p}\",\"hmac-id\":\"${i}\",\"hmac-key\":\"${k}\",\"registry-password\":\"\"}";
    fi
}

# Chain UUID 
function check_uuid()
{
    local id;
    local msg="${1}";
    local UUID_REGEX="^\{?[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}\}?$";

    shopt -s nocasematch;
    while [[ ! ${id} =~ $UUID_REGEX ]]; do
        read -r -p "${msg}: " id;
        id="$(echo ${id} | tr -d '\r')";
    done
    shopt -u nocasematch;

    echo "${id}";
}

# Get random number between range
function get_rnd_num()
{
    local f=${1-0};
    local c=${2-65535};
    local r=$((${c}-${f}+1));
    local n=${RANDOM};

    let "n %= ${r}";

    echo "$((${n}+${f}))";
}

# Node end-point port
function set_node_port()
{
    local p="${1-30000}";

    [[ "${p,,}" = "r" ]] && p=$(get_rnd_num 30000 32000) || { [[ ${p} =~ ^[0-9]+$ ]] && p=${p} || p=30000; };

    echo "${p}";
}

# Node name
function set_node_name()
{
    local n="${1-dc}";
    local l="${2-2}";
    
    [[ ${n} =~ ^[A-Z0-9\-]{1,12}$ ]] && n="${n}" || n="dc-l${l}-$(date +"%N" | tail -c 6)";
    
    echo "${n}";
}

# Kube secrets
function set_node_secrets()
{
    local nsec="d-${DC_CHAIN}-secrets";
    local csec="d-${DC_CHAIN}-cert";

    [[ -z "${DC_CHAIN}" ]] && { echo -e "Dragonchain Chain ID can't be empty\n"; exit 2; }
    
    get_hmac

    if [[ ! $(kubectl get secret -n dragonchain "${nsec}") ]]; then
        kubectl create secret generic -n dragonchain "${nsec}" --from-literal=SecretString="${HMAC}";

        if [[ ! -z "${NODE_ADDR}" && ! $(kubectl get secret -n dragonchain "${csec}") ]]; then
            # ToDo: Find better way
            sudo /snap/bin/kubectl create secret tls -n dragonchain "${csec}" \
--cert=/etc/letsencrypt/live/${NODE_ADDR}/fullchain.pem \
--key=/etc/letsencrypt/live/${NODE_ADDR}/privkey.pem;
        fi
        
        sleep .1;
    fi
}

function id_node()
{
    echo "";
    #DC_PUBLIC_ID=$(kubectl exec -n dragonchain $(kubectl get pod -n dragonchain | grep "${DC_NODE_NAME}-webserver" | awk '{print $1}') -- python3 -c "from dragonchain.lib.keys import get_public_id; print(get_public_id())");
}

function validate_node()
{
echo "";
#curl -s https://matchmaking.api.dragonchain.com/registration/verify/${DC_PUBLIC_ID}
}

function helm_install()
{
    helm upgrade --install ${NODE_NAME} --namespace dragonchain dragonchain/dragonchain-k8s \
--set global.environment.DRAGONCHAIN_NAME="${NODE_NAME}" \
--set global.environment.REGISTRATION_TOKEN="${DC_TOKEN}" \
--set global.environment.INTERNAL_ID="${DC_CHAIN}" \
--set global.environment.DRAGONCHAIN_ENDPOINT="${NODE_URL}:${NODE_PORT}" \
--set-string global.environment.LEVEL=${NODE_LEVEL} \
--set-string global.environment.TLS_SUPPORT="true" \
--set service.port=${NODE_PORT} \
--set dragonchain.storage.spec.storageClassName="microk8s-hostpath" \
--set redis.storage.spec.storageClassName="microk8s-hostpath" \
--set redisearch.storage.spec.storageClassName="microk8s-hostpath";

    sleep .1;
    
    #kubectl get pod -n dragonchain -l "dragonchainId=ccaf4cb5-8638-4210-ae50-982b398613df"
}

function check_setup()
{
    [[ -z "${DC_CHAIN}" || -z "${DC_TOKEN}" || -z "${NODE_LEVEL}" || -z "${NODE_NAME}" || -z "${NODE_PORT}" ]] && { echo -e "\nConfig is not complete. Try again, please ...\n"; setup; return; } || set_env;
}

function setup()
{
    # Matchmaking
    if [[ -z "${DC_CHAIN}" || -z "${DC_TOKEN}" ]]; then
        echo -e "\n1) Chain configuration details, from console.dragonchain.com";
        
        [[ -z "${DC_CHAIN}" ]] && DC_CHAIN="$(check_uuid '· Chain ID: ')";
        [[ -z "${DC_TOKEN}" ]] && DC_TOKEN="$(check_uuid '· Matchmaking Token ID: ')";

        echo -e "";
    fi
    
    # Node config
    if [[ -z "${NODE_LEVEL}" || -z "${NODE_NAME}" || -z "${NODE_PORT}" ]]; then
        echo -e "\n2) Node configuration";
        
        if [[ -z "${NODE_LEVEL}" ]]; then
            local node_level;
            read -p "· Node Level (L2, L3, L4) [2]: " node_level;
            [[ ${node_level} =~ ^[2-4]{1}$ ]] && node_level=${node_level} || node_level=2;
            NODE_LEVEL=${node_level};
        fi
        
        if [[ -z "${NODE_NAME}" ]]; then
            read -p "· Node Name (no spaces), blank for random name [dc-lLEVEL-rnd]: " node_name;
            # ToDo: Check if a node with same name already exists
            NODE_NAME="$(set_node_name ${node_name} ${NODE_LEVEL})";
        fi
        
        if [[ -z "${NODE_PORT}" ]]; then
            read -p "· Node Port, between 30000 and 32000, [r] for random, blank for default [30000]: " node_port;
        
            NODE_PORT="$(set_node_port ${node_port-30000})";
            
            # Firewall rule
            sudo ufw allow ${NODE_PORT}/tcp;
        fi
        
        [[ -z "${NODE_URL}" ]] && NODE_URL="https://${NODE_ADDR}";

        echo -e "";
    fi
}


setup

# kubectl describe pod nginx-deployment-1370807587-fz9sd
#https://kubernetes.io/docs/tasks/debug-application-cluster/#example-debugging-pending-pods

#mknode_script

# save kube config
# alias cmd
# echo cheatsheet

