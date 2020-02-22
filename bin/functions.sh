#!/bin/bash

function setup_server()
{
    echo "$(get_port 22)";
    
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
    
    [[ ! "${d}" = "0" ]] && msg="${msg} Press ENTER for default [${d}].";

    while [[ ! ${s} =~ $PORT_REGEX || ${s} < ${l} || ${s} > ${h} ]]; do
        read -r -p "${msg}: " s;

        s="$(echo ${s} | tr -d '\r')";

        [[ -z "${s}" ]] && s="${d}";
        [[ "${s,,}" = "r" ]] && s=$(get_rnd_num ${l} ${h});
    done

    echo "${s}";
}
