#!/bin/bash

export LC_CTYPE=C;

# Check for root
[[ ${EUID} = 0 ]] || { echo -e "This script must be run as root\n"; exit 2; }

# · Script vars
VERSION="0.23b";

WKDIR="${HOME}/.dc-installer";

PATH_BCK="${WKDIR}/.var/backup";
PATH_LIB="${WKDIR}/.var/lib";
PATH_TMP="${WKDIR}/.var/tmp";

CONFIG="${PATH_TMP}/env.conf";
CONFIG_VARS="U_LOGIN U_PASSWD U_MAIL U_PUBKEY S_LOCALE S_IPV4 S_FQDN S_SSH_PORT S_SSH_PUBKEY S_SSH_PWAUTH S_UPGRADE S_TOOLS";

LIB_COMMON="fn.common.sh";
LIB_SETUP="fn.setup.sh";
