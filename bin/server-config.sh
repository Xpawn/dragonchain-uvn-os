#!/bin/bash

# ToDo
#   K8s cluster
#       cgroups
#       hugepages
#   Sanitize user input

export LC_CTYPE=C

# Check for root
[[ ${EUID} = 0 ]] || { echo -e "This script must be run as root\n"; exit 2; }

UVN_OS_VERSION='0.21b';

MY_USER=
MY_PUBKEY=
MY_EMAIL=
MY_TMP=

IS_READY=

SYS_PASSAUTH=
SYS_LOCALE=
SYS_BACKUP_PATH=

SSH_TCP_PORT=
SRV_IP=
SRV_FQDN=

SELF_PATH=$(pwd);

DC_ENV=${SELF_PATH}/.dc-installer-env;
DC_BASE_PATH=.dragonchain-installer/uvn-os;
DC_INSTALL_PATH=

MEMTOTAL=$(awk '/MemTotal/ { print $2 * 1024 }' /proc/meminfo);

# Save installer env vars to disk
function set_env()
{
    cat > "${DC_ENV}" <<EOL
MY_USER=${MY_USER}
MY_EMAIL=${MY_EMAIL}
MY_PUBKEY=${MY_PUBKEY}
SYS_LOCALE=${SYS_LOCALE}
SSH_TCP_PORT=${SSH_TCP_PORT}
SRV_IP=${SRV_IP}
SRV_FQDN=${SRV_FQDN}
DC_INSTALL_PATH=${DC_INSTALL_PATH}
SYS_BACKUP_PATH=${SYS_BACKUP_PATH}
MEMTOTAL=${MEMTOTAL}
UVN_OS_VERSION=${UVN_OS_VERSION}
EOL
}

# Retrieve installer env vars from disk
function get_env()
{
    [[ -f "${DC_ENV}" ]] && source "${DC_ENV}";
}

# Add new user
function add_user()
{
    [[ ${EUID} = 0 ]] || { echo -e "Only root may add a user to the system\n"; exit 2; };

    echo -e "";
    read -s -p "· Repeat password: " password;

    [[ "x${password}" = "x${2}" ]] || { echo -e "\tPasswords doesn't match!\n"; exit 1; }

    local u="${1}";
    local p=$(perl -e 'print crypt($ARGV[0], "password")' "${2}");

    egrep "^${u}" /etc/passwd >/dev/null;
    [[ ${?} -eq 0 ]] && { echo -e "\n\tUser '${u}' exists!\n"; exit 1; }

    useradd -mUG operator,sudo,users -s /bin/bash -p ${p} ${u};
    [ $? -eq 0 ] || { echo -e "\tFailed to add a user!"; exit 1; }

    echo -e "\n\tUser has been added to system!";

    MY_USER="${u}";
    MY_TMP="${2}";

    set_env
}

# Set system locale
function set_locale()
{
    local l="${1-es}";

    [[ ${#l} -eq 2 && $(locale -a | grep ^${l}_${l^^}) ]] || l="es";

    SYS_LOCALE=${l};

    set_env
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
    
    set_env
}

# Set ip
function set_server_address()
{
    local i="${1}";

    [[ ${i} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo -e "\tThis isn't a valid IPv4 address!"; exit 1; };
    [[ $(ifconfig -a | grep "${i}") ]] || { echo -e "\tThis address does not belong to this server!"; exit 1; };
    
    SRV_IP="${i}";
    
    set_env
    
    set_server_fqdn "${2}";
}

# Server FQDN
function set_server_fqdn()
{
    local f="${1}";
    
    [[ $(host "${f}" | grep "${SRV_IP}") ]] || { echo -e "\tThis FQDN doesn't resolves to given address!"; exit 1; };
    
    SRV_FQDN="${f}";
    
    set_env
}

function set_email()
{
    local m="${1}";

    [[ "${m}" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,11}$ ]] || { echo -e "\tThis isn't a valid e-mail address!"; exit 1; };
    
    MY_EMAIL="${m}";
    
    set_env
}

# function set_sshkey()
# {
# 
# }

function config_complete()
{
    [[ -z "${MY_USER}" || -z "${SYS_LOCALE}" || -z "${SSH_TCP_PORT}" || -z "${MY_EMAIL}" || -z "${SRV_IP}" ]] && { echo -e "\nConfig is not complete. Try again, please ...\n"; uvn_os_setup; return; } || set_env;

    sys_update
}

function uvn_os_setup()
{
    # User
    if [[ -z "${MY_USER}" ]]; then
        local username;
        local password;

        echo -e "\n1) Add a new user";
        read -p "· Enter login/username (e.g. dragon): " username;
        read -s -p "· Enter password: " password;
        
        add_user "${username}" "${password}";

        [[ $? -eq 0 ]] || exit 1;
    fi

    # Locale
    if [[ -z "${SYS_LOCALE}" ]]; then
        local locale;
        
        echo -e "\n2) Set system locale to your language";
        read -p "· Enter a valid locale (en, es, fr, it, pt...) [es]: " locale;

        set_locale "${locale-es}";

        [[ $? -eq 0 ]] || exit 1;
    fi

    # Server address
    if [[ -z "${SRV_IP}" ]]; then
        local auto_ip="$(get_server_ip)";
        local auto_fqdn="$(hostname -f)";
        local ip;
        local fqdn;

        echo -e "\n3) Set server public address:";
        read -p "· Enter a public and reachable IPv4 address [${auto_ip}]: " ip;
        read -p "· FQDN for this server (must resolve to previous IPv4) [${auto_fqdn}]: " fqdn;
        
        set_server_address "${ip:-$auto_ip}" "${fqdn:-$auto_fqdn}";
        
        [[ $? -eq 0 ]] || exit 1;
    fi

    # SSH
    if [[ -z "${SSH_TCP_PORT}" ]]; then
        local ssh_port;
        local pubkey;
        local passauth;

        echo -e "\n4) SSH Security & Hardening";
        read -p "· Public Key Authentication, paste your key to Enable or empty to disable PubKeyAuth: " pubkey;
        
        if [[ ! -z ${pubkey} ]]; then
            read -p "· Disable PasswordAuthentication? (higer security=Y) [N]: " passauth;

            MY_PUBKEY="${pubkey-n}";
            SYS_PASSAUTH="${passauth-n}";
        fi

        read -p "· SSH port, enter a number (above 1024), [r] for random or leave blank for default [22]: " ssh_port;

        set_ssh_port "${ssh_port-22}";
    fi

    # E-mail for notifications
    if [[ -z "${MY_EMAIL}" ]]; then
        local email;

        echo -e "\n5) Server notifications & warnings";
        read -p "· E-mail address: " email;

        set_email "${email}";
    fi

    config_complete
}

function sys_update()
{
    apt update && apt -y full-upgrade && apt upgrade && apt autoclean && apt -y autoremove && sleep .1;

    [[ $? -eq 0 ]] && sys_tools || exit 1;
}

function sys_tools()
{
    apt install -y fail2ban rkhunter checksecurity dnsutils iotop \
zram-tools screen certbot gpg dump mc ufw curl jq openssl xxd snapd && sleep .1 && rkhunter --propupd && sleep .1;

    [[ $? -eq 0 ]] && sys_config || exit 1;
}

function sys_config()
{
    [[ $(grep '^ALLOCATION=256' "/etc/default/zramswap") ]] || echo 'ALLOCATION=256' > /etc/default/zramswap;
    
    [[ $(grep 'ufw allow http' "/etc/letsencrypt/cli.ini") ]] || echo -e "\n\npre-hook = ufw allow http\npost-hook = ufw delete allow http\n" >> /etc/letsencrypt/cli.ini;

    # L10N
    if [[ ! $(grep 'export LANG' "/etc/profile") ]]; then
        local locale="${SYS_LOCALE,,}_${SYS_LOCALE^^}";
        local locale_alt="en_US";
        
    
        [[ "x${SYS_LOCALE,,}" = "xen" ]] && locale_alt="es_ES";

        echo -e "\n: \${LANG:=${locale}.UTF-8}; export LANG" >> /etc/profile;
        echo -e "${locale}.UTF-8 UTF-8\n${locale_alt}.UTF-8 UTF-8\n" > /etc/locale.gen;

        cat >/etc/default/locale <<EOL
LANG="${locale}.UTF-8"
LANGUAGE="${locale}:${SYS_LOCALE,,}"
LC_TIME="${locale}.UTF-8"
LC_MESSAGES="POSIX"
LC_COLLATE="C"
EOL
        dpkg-reconfigure --frontend=noninteractive locales;
        update-locale LANG=${locale}.UTF-8;

        # echo "Europe/Madrid" > /etc/timezone && dpkg-reconfigure -f noninteractive tzdata
        dpkg-reconfigure tzdata;
    fi

    # Runlevel
    systemctl set-default multi-user.target;
    systemctl disable remote-fs.target;
    
    # Mount points
    if [[ ! -f "/etc/apt/apt.conf.d/999-local" ]]; then
        cat > /etc/apt/apt.conf.d/999-local <<- EOT
DPkg::Pre-Invoke{"mount -o remount,exec /tmp";};
DPkg::Post-Invoke {"mount -o remount,noexec /tmp";};
EOT
        sed -i '/^\/dev\/sr0/d' /etc/fstab;
        sed -i 's/errors=remount-ro/rw,noatime,journal_checksum,errors=remount-ro/g' /etc/fstab;
    fi

    [[ -f "/usr/share/systemd/tmp.mount" && ! -f "/etc/systemd/system/tmp.mount" ]] && cp -aux /usr/share/systemd/tmp.mount /etc/systemd/system/;
    
    sleep .1;
    
    if [[ -f "/etc/systemd/system/tmp.mount" ]]; then
        [[ $(grep 'Options' "/etc/systemd/system/tmp.mount" | grep 'noexec') ]] || sed -i 's/^Options=/Options=noexec,/g' /etc/systemd/system/tmp.mount;
        
        systemctl enable tmp.mount;
    fi

    # FireWall
    [[ -z "${SSH_TCP_PORT}" ]] || ufw --force enable && ufw default allow outgoing && ufw default allow routed && ufw allow in on cni0 && ufw allow out on cni0 && ufw allow ${SSH_TCP_PORT};
    
    # Snap
    [[ $(snap list core 2> grep '^core') ]] || snap install core;
    [[ $(snap list microk8s 2> grep -q 'microk8s') ]]  || snap install microk8s --channel=1.18/edge --classic;
    
    snap alias microk8s.kubectl kubectl;
    
    # Groups
    [[ $(grep 'hugetlbfs' "/etc/group") ]] || groupadd -r hugetlbfs;
    [[ $(grep 'wheel' "/etc/group") ]] || groupadd -r wheel;

    sed -i 's/^# auth\s*required\s*pam_wheel.so$/auth required pam_wheel.so/g' /etc/pam.d/su;

    # Certificate
    mkcert;
    
    # User
    if [[ ! -z "${MY_USER}" ]]; then
        [[ $(groups ${MY_USER} | grep 'hugetlbfs') ]] || gpasswd -a ${MY_USER} hugetlbfs;
        [[ $(groups ${MY_USER} | grep 'wheel') ]] || gpasswd -a ${MY_USER} wheel;
        [[ $(groups ${MY_USER} | grep 'microk8s') ]] || gpasswd -a ${MY_USER} microk8s;

        chmod 0750 /home/${MY_USER};
        mkdir -pm 0700 /home/${MY_USER}/.ssh;
        touch /home/${MY_USER}/.ssh/authorized_keys && chmod 0600 /home/${MY_USER}/.ssh/authorized_keys;
        chown -R ${MY_USER}:${MY_USER} /home/${MY_USER};
        
        set_installer_files
    fi
}

function mkcert()
{
    [[ ! -z "${MY_EMAIL}" ]] && certbot register --agree-tos --no-eff-email -m ${MY_EMAIL};

    sleep .1;
    certbot certonly --standalone --preferred-challenges http -d ${SRV_FQDN};
}

# System & Installer files
function set_installer_files()
{
    DC_INSTALL_PATH=/home/${MY_USER}/${DC_BASE_PATH};
    SYS_BACKUP_PATH=${DC_INSTALL_PATH}/backup;

    set_env
    
    [[ ! -d "${DC_INSTALL_PATH}" ]] && { mkdir -pm 0750 "${DC_INSTALL_PATH}"; chmod 0750 "$(dirname ${DC_INSTALL_PATH})"; }
    [[ ! -d "${SYS_BACKUP_PATH}" ]] && mkdir -pm 0750 "${SYS_BACKUP_PATH}";

    cd ${DC_INSTALL_PATH} && cp -aux ${DC_ENV} .

    wget https://raw.githubusercontent.com/Xpawn/dragonchain-uvn-os/master/bin/mknode.template && chmod 0755 mknode.template;
    
    mkdir -pm 0750 .tmp && cd .tmp;
    
    # Limits (ToDo)
    
    # SysCtl
    wget https://raw.githubusercontent.com/Xpawn/estaribel/master/etc/sysctl.d/999-local.conf;
    
    SHMMAX=$(echo ${MEMTOTAL} - 1 | bc);
    SHMALL=$(echo "${SHMMAX} / $(getconf PAGE_SIZE)" | bc);

    sed -i "s/# kernel.shmmax/kernel.shmmax = ${SHMMAX}/g" 999-local.conf;
    sed -i "s/# kernel.shmall/kernel.shmall = ${SHMALL}/g" 999-local.conf;
    chmod 0644 999-local.conf && mv 999-local.conf /etc/sysctl.d/;
    
    # SSH
    wget https://raw.githubusercontent.com/Xpawn/estaribel/master/etc/ssh/sshd_config;
    
    sed -i "s/# ListenAddress 127\.0\.0\.1/ListenAddress 127\.0\.0\.1/g" sshd_config;
    sed -i "s/# ListenAddress 0\.0\.0\.0/ListenAddress ${SRV_IP}/g" sshd_config;
    sed -i "s/Port 22/Port ${SSH_TCP_PORT}/g" sshd_config;

    if [[ ! -z "${MY_PUBKEY}" && ! "x${MY_PUBKEY,,}" = "xn" ]]; then
        echo "${MY_PUBKEY}" >> /home/${MY_USER}/.ssh/authorized_keys;
        sed -i "s/# AuthenticationMethods/AuthenticationMethods/g" sshd_config;
        sed -i "s/# PubkeyAuthentication/PubkeyAuthentication/g" sshd_config;

        [[ "x${SYS_PASSAUTH,,}" = "xy" ]] && sed -i "s/# PasswordAuthentication/PasswordAuthentication/g" sshd_config;
    fi
    
    cp -aux /etc/ssh/sshd_config ${SYS_BACKUP_PATH}/;
    chmod 0644 sshd_config && mv sshd_config /etc/ssh/sshd_config;
    
    sleep 1 && systemctl restart ssh;
    
    config_microk8s && sleep 1;
    
    chown -R ${MY_USER}:${MY_USER} /home/${MY_USER};
}

# K8s
function config_microk8s()
{
    PATH=${PATH}:/snap/bin;
    local kube='{"kind":"Namespace","apiVersion":"v1","metadata":{"name":"dragonchain","labels":{"name":"dragonchain"}}}';
    
    snap alias microk8s.helm3 helm;

    runuser -l  ${MY_USER} -c 'microk8s.status --wait-ready && sleep .1;';
    su - ${MY_USER} -c "echo '${MY_TMP}' | sudo -S /snap/bin/microk8s.enable storage dns helm3 registry";
    runuser -l  ${MY_USER} -c "/snap/bin/helm repo add dragonchain https://dragonchain-charts.s3.amazonaws.com && /snap/bin/helm repo update; echo '${kube}' | /snap/bin/kubectl create -f -";
    MY_TMP="";
    
    sleep .1 && show_kube;
}

# Final check
function show_kube()
{
    echo -e "";

    runuser -l  ${MY_USER} -c 'microk8s.kubectl get nodes && microk8s.kubectl get services && microk8s.kubectl get po,svc --namespace kube-system;';
    
    echo -e "";
    
    IS_READY="Y";
}

# Self delete
function sayonara()
{
    [[ ! -z "${IS_READY}" && "x${IS_READY}" = "xY" ]] || { echo -e "Something went wrong ...\n"; exit 1; }

    echo -e "\n\nConfig done!\n\nThis script will be deleted now.\n";
    echo -e "Wait for reboot...\n";
    (cd ${SELF_PATH}; rm ${DC_ENV} ${0};);

    sleep 3 && shutdown -r now;
}

clear;
uvn_os_setup && sayonara

exit 0
