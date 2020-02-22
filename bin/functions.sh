#!/bin/bash

function setup_server()
{
get_secret_json
#    echo "$(get_port 22 0)";
}

# Utility functions
function get_rnd_num()
{
    local f=${1-0};
    local c=${2-65535};
    local r=$((${c}-${f}+1));
    local n=${RANDOM};

    let "n %= ${r}";

    echo "$((${n}+${f}))";
}

function get_port()
{
    local PORT_REGEX="^[0-9]{2,5}$";

    local d="${1-r}";       # Default value
    local l="${2-30000}";   # Low/min port
    local h="${3-64000}";   # High/max port
    local s                 # Selected port

    local msg="Select a port";
    
    if [[ ! "${l}" = "0" && ! "${h}" = "0" ]]; then
        msg="${msg} between ${l} and ${h}";
    elif [[ ! "${l}" = "0" ]]; then
        msg="${msg} greater than ${l}";
    elif [[ ! "${h}" = "0" ]]; then
        msg="${msg} smaller than ${h}";
    fi

    msg="${msg}, [r] for random.";
    
    [[ ! "${d}" = "0" ]] && msg="${msg} Press ENTER for default [${d}]";

    while [[ ! ${s} =~ $PORT_REGEX || ${s} < ${l} || ${s} > ${h} ]]; do
        read -r -p "${msg}: " s;

        s="$(echo ${s} | tr -d '\r')";

        [[ -z "${s}" ]] && s="${d}";
        [[ "${s,,}" = "r" ]] && s=$(get_rnd_num ${l} ${h});
        [[ "xX${s}" = "xX${d}" ]] && break;
    done

    echo "${s}";
}

function get_uuid()
{
    local id;
    local msg="${1}";
    local auto="${2}";
    local UUID_REGEX="^\{?[A-Z0-9]{8}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{12}\}?$";

    shopt -s nocasematch;
    while [[ ! ${id} =~ $UUID_REGEX ]]; do
        read -r -p "${msg}: " id;
        id="$(echo ${id} | tr -d '\r')";

        [[ "x${auto,,}" = "xauto" && "x${id}" = "x" ]] id="$(cat /proc/sys/kernel/random/uuid)";
    done
    shopt -u nocasematch;

    echo "${id}";

}

function get_secp256k1_key()
{
    local pkhex="${1}";
    
    if [[ -z "${pkhex}" || "x${pkhex}" = "x" ]]; then
        local pkbin="$(openssl ecparam -genkey -name secp256k1 | openssl ec -outform DER | tail -c +8 | head -c 32)";

        if type -P "xxd" &> /dev/null ; then
            pkhex="$(echo "${pkbin}" | xxd -p -c 32 | tr -d '\n[:space:]:' | xxd -r -p)";
        elif type -P "hexdump" &> /dev/null ; then
            pkhex="$(echo "${pkbin}" | hexdump -ve '32/1 "%02x"' | sed 's/\([0-9A-F]\{2\}\)/\\\\\\x\1/gI' | xargs printf)";
        else
            echo -e "Hex tool not found. Install xxd or hexdump and try again.";
            exit 1;
        fi
    
        pkhex="$(echo "${pkhex}" | base64)";
    fi
    
    echo "${pkhex}";
}

function get_hmac_id()
{
    local h="${1}";
    [[ -z "${h}" || "x${h}" = "x" ]] && h="$(tr -dc 'A-Z' < /dev/urandom | fold -w 12 | head -n 1)";

    echo "${h}";
}

function get_hmac_token()
{
    local h="${1}";
    [[ -z "${h}" || "x${h}" = "x" ]] && h="$(tr -dc 'A-Za-z0-9' < /dev/urandom | fold -w 43 | head -n 1)";

    echo "${h}";
}

function get_secret_json()
{
    local p="$(get_secp256k1_key)";
    local i="$(get_hmac_id)";
    local k="$(get_hmac_token)";

    echo "{\"private-key\":\"${p}\",\"hmac-id\":\"${i}\",\"hmac-key\":\"${k}\",\"registry-password\":\"\"}";
}
