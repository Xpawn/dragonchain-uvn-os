#!/bin/bash

# Console data
DC_ID=""
DC_TOKEN=""

# Instance data
DC_NODE_LEVEL=2
DC_NODE_SERVER=1
DC_NODE_INSTANCE=1

DC_PUBLIC_ID=""

# Server data
SRV_ADDRESS="";
SRV_TLS_SUPPORT="false";
SRV_FIRST_PORT=30000;

#
# Do not edit beyond this comment
#

[[ ${EUID} = 0 ]] && { echo -e "This script should be run as non root, with sudo privileges account!\n"; exit 1; }

# Secrets
HMAC_ID=""
HMAC_KEY=""
PRIVATE_KEY=""
I=0

if [[ -z "${PRIVATE_KEY}" ]]; then
    PRIVATE_KEY=$(openssl ecparam -genkey -name secp256k1 | openssl ec -outform DER | tail -c +8 | head -c 32 | xxd -p -c 32 | xxd -r -p | base64);
    sed -i 's/^PRIVATE_KEY=""$/PRIVATE_KEY="'"${PRIVATE_KEY}"'"/g' $(basename "${0}");
    ((I++))
fi

if [[ -z "${HMAC_ID}" ]]; then
    HMAC_ID=$(tr -dc 'A-Z' < /dev/urandom | fold -w 12 | head -n 1);
    sed -i 's/^HMAC_ID=""$/HMAC_ID="'"${HMAC_ID}"'"/g' $(basename "${0}");
    ((I++))
fi

if [[ -z "${HMAC_KEY}" ]]; then
    HMAC_KEY=$(tr -dc 'A-Za-z0-9' < /dev/urandom | fold -w 43 | head -n 1);
    sed -i 's/^HMAC_KEY=""$/HMAC_KEY="'"${HMAC_KEY}"'"/g' $(basename "${0}");
    ((I++))
fi

if [[ ${I} -eq 3 ]]; then
    SECRETS_AS_JSON="{\"private-key\":\"$PRIVATE_KEY\",\"hmac-id\":\"$HMAC_ID\",\"hmac-key\":\"$HMAC_KEY\",\"registry-password\":\"\"}";
    kubectl create secret generic -n dragonchain "d-${DC_ID}-secrets" --from-literal=SecretString="${SECRETS_AS_JSON}";
fi

# EndPoint
[[ "${SRV_TLS_SUPPORT}" == "true" ]] && DC_NODE_PROTOCOL="https" || DC_NODE_PROTOCOL="http";

DC_NODE_NAME="dc-l${DC_NODE_LEVEL}s${DC_NODE_SERVER}${DC_NODE_INSTANCE}";
DC_NODE_URL="${DC_NODE_PROTOCOL}://${SRV_ADDRESS}";
DC_NODE_PORT=$((${DC_NODE_INSTANCE} + ${SRV_FIRST_PORT} - 1));
DC_ENDPOINT="${DC_NODE_URL}:${DC_NODE_PORT}";

# Node data
echo -e "[${DC_NODE_NAME}]
LEVEL:      ${DC_NODE_LEVEL}
ADDRESS:    ${SRV_ADDRESS}
PORT:       ${DC_NODE_PORT}
SSL:        ${SRV_TLS_SUPPORT}

[BlockExplorer Info]
NODE NAME:  ${DC_NODE_NAME}
PUBLIC ID:  ${DC_PUBLIC_ID}
HMAC ID:    ${HMAC_ID}
HMAC KEY:   ${HMAC_KEY}
ENDPOINT:   ${DC_ENDPOINT}
\n"

helm upgrade --install ${DC_NODE_NAME} --namespace dragonchain dragonchain/dragonchain-k8s \
--set global.environment.DRAGONCHAIN_NAME="${DC_NODE_NAME}" \
--set global.environment.REGISTRATION_TOKEN="${DC_TOKEN}" \
--set global.environment.INTERNAL_ID="${DC_ID}" \
--set global.environment.DRAGONCHAIN_ENDPOINT="${DC_ENDPOINT}" \
--set-string global.environment.LEVEL=${DC_NODE_LEVEL} \
--set-string global.environment.TLS_SUPPORT="${SRV_TLS_SUPPORT}" \
--set service.port=${DC_NODE_PORT} \
--set dragonchain.storage.spec.storageClassName="microk8s-hostpath" \
--set redis.storage.spec.storageClassName="microk8s-hostpath" \
--set redisearch.storage.spec.storageClassName="microk8s-hostpath";

echo "Wait 30 seconds..."
sleep 15;

if [[ -z "${DC_PUBLIC_ID}" ]]; then
    MYPOD=$(kubectl get pod -n dragonchain -l app.kubernetes.io/component=webserver | tail -1 | awk '{print $1}');
    DC_PUBLIC_ID=$(kubectl exec -n dragonchain ${MYPOD} -- python3 -c "from dragonchain.lib.keys import get_public_id; print(get_public_id())");
    
    sed -i 's/^DC_PUBLIC_ID=""$/DC_PUBLIC_ID="'"${DC_PUBLIC_ID}"'"/g' $(basename "${0}");
    
    echo -e "\n$(curl -s https://matchmaking.api.dragonchain.com/registration/verify/$DC_PUBLIC_ID)\n\n";
fi

microk8s.kubectl get nodes && microk8s.kubectl get services && microk8s.kubectl get po,svc --namespace kube-system && sleep 1;

kubectl get pods -n dragonchain -l "dragonchainId=${DC_ID}";

exit 0
