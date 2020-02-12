#!/bin/bash

MY_USER=
SYS_LOCALE=
SSH_TCP_PORT=
SRV_IP=
SRV_FQDN=

# Add new user
function add_user()
{
    [[ ${EUID} = 0 ]] || { echo -e "Only root may add a user to the system\n"; exit 2; };

    read -s -p "· Repeat password: " password;
    
    [[ "x${password}" = "x${2}" ]] || { echo -e "\tPasswords doesn't match!\n"; exit 1; }
    
    local u="${1}";
    local p=$(perl -e 'print crypt($ARGV[0], "password")' "${2}");

    egrep "^${u}" /etc/passwd >/dev/null;
    [[ ${?} -eq 0 ]] && { echo -e "\n\tUser '${u}' exists!\n"; exit 1; }

    useradd -mUG operator,sudo,users -s /bin/bash -p ${p} ${u};
    [ $? -eq 0 ] || { echo -e "\tFailed to add a user!"; exit 1; }
    
    echo -e "\tUser has been added to system!";
    MY_USER="${u}";
}

# Set system locale
function set_locale()
{
    local l="${1-es}";
    
    [[ ${#l} -eq 2 && $(locale -a | grep ^${l}_${l^^}) ]] || l="es";
    
    SYS_LOCALE=${l};
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

# Get current ip address
function get_server_ip()
{
    local ip=$(ip addr show dev "$(awk '$2 == 00000000 { print $1 }' /proc/net/route)" | awk '$1 == "inet" { sub("/.*", "", $2); print $2 }');
    local ssh_data=(${SSH_CONNECTION});
    
    echo "${ip-ssh_data[2]}";
}

# Set system SSH port
function set_ssh_port()
{
    local p="${1-22}";

    [[ "${p,,}" = "r" ]] && p=$(get_rnd_num 33000 62000) || { [[ ${p} =~ ^[0-9]+$ ]] && p=${p} || p=22; };

    SSH_TCP_PORT="${p}";
}

# Set ip
function set_server_address()
{
    local i="${1}";

    [[ ${i} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo -e "\tThis isn't a valid IPv4 address!"; exit 1; };
    [[ $(ifconfig -a | grep "${i}") ]] || { echo -e "\tThis address does not belong to this server!"; exit 1; };
    
    SRV_IP="${i}";
    
    set_server_fqdn "${2}";
}

function set_server_fqdn()
{
    local f="${1}";
    
    [[ $(host "${f}" | grep "${SRV_IP}") ]] || { echo -e "\tThis FQDN doesn't resolves to given address!"; exit 1; };
    
    SRV_FQDN="${f}";
}

function get_setup_vars()
{
# User
    local username;
    local password;

    echo -e "\n1) Add a new user";
    read -p "· Enter login/username (e.g. dragon): " username;
    read -s -p "· Enter password: " password;
    
    add_user "${username}" "${password}";

# Locale
    local locale;
    
    echo -e "\n2) Set system locale to your language";
    read -p "· Enter a valid locale (en, es, fr, it, pt...) [es]: " locale;

    set_locale "${locale-es}";

# Server address
    local auto_ip="$(get_server_ip)";
    local auto_fqdn="$(hostname -f)";
    local ip;
    local fqdn;

    echo -e "\n3) Set server public address:";
    read -p "· Enter a public and reachable IPv4 address [${auto_ip}]: " ip;
    read -p "· FQDN for this server (must resolve to previous IPv4) [${auto_fqdn}]: " fqdn;
    
    set_server_address "${ip:-$auto_ip}" "${fqdn:-$auto_fqdn}";
    
    echo $SRV_IP
    echo $SRV_FQDN

# SSH
    local ssh_port;
    
    echo -e "\n4) Choose SSH port";
    read -p "· Enter a number (above 1024), [r] for random or leave blank for default [22]: " ssh_port;

    set_ssh_port "${ssh_port-22}";
}

get_setup_vars

exit 0;
