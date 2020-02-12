#!/bin/bash

# ToDo (containers)
#   cgroups
#   hugepages

# ToDo
#   Ask for user data

export LC_CTYPE=C

cd /tmp;

# Check for root
[[ ${EUID} = 0 ]] || { echo -e "This script should be run as root\n"; exit 2; }

MY_USER=
SYS_LOCALE=
SSH_TCP_PORT=
SRV_IP=
SRV_FQDN=
DC_INSTALL_PATH=.dragonchain-installer/uvn-os

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

function config_complete()
{
    [[ -z "${MY_USER}" || -z "${SYS_LOCALE}" || -z "${SSH_TCP_PORT}" || -z "${SRV_IP}" ]] && { echo -e "Config is not complete. Try again, please."; exit 1; };

    sys_update
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

function sys_update()
{
    apt update && apt -y full-upgrade && apt upgrade && apt autoclean && apt -y autoremove && sleep .1 && sys_tools
}

function sys_tools()
{
    apt install -y fail2ban rkhunter checksecurity dnsutils iotop \
zram-tools screen certbot gpg dump mc ufw curl jq openssl xxd snapd && sleep .1 && rkhunter --propupd && sleep .1 && sys_config
}

function sys_config()
{
    echo 'ALLOCATION=256' > /etc/default/zramswap;

    echo -e "\n\npre-hook = ufw allow http\npost-hook = ufw delete allow http\n" >> /etc/letsencrypt/cli.ini;

    # L10N
    local locale="${SYS_LOCALE,,}_${SYS_LOCALE^^}";
    local locale_alt="en_US";
    
    [[ "x${SYS_LOCALE,,}" = "xen" ]] && locale_alt="es_ES";

    echo ': "${LANG:=$locale.utf8}"; export LANG' >> /etc/profile;
    echo -e '$locale_alt.UTF-8 UTF-8\nlocale.UTF-8 UTF-8\n' > /etc/locale.gen;

    cat >/etc/default/locale <<EOL
LANGUAGE="locale.UTF-8:${SYS_LOCALE,,}"
LC_TIME="locale.UTF-8"
LC_MESSAGES="POSIX"
LC_COLLATE="C"
EOL

    cat > /etc/apt/apt.conf.d/999-local <<- EOT
DPkg::Pre-Invoke{"mount -o remount,exec /tmp";};
DPkg::Post-Invoke {"mount -o remount,noexec /tmp";};
EOT

    sed -i '/^\/dev\/sr0/d' /etc/fstab;

    locale-gen && dpkg-reconfigure tzdata;

    systemctl set-default multi-user.target;
    systemctl disable autovt@.service remote-fs.target;

    # Groups
    groupadd -r hugetlbfs;
    groupadd -r wheel;
    sed -i 's/^# auth\s*required\s*pam_wheel.so$/auth required pam_wheel.so/g' /etc/pam.d/su;
}

# Snap
snap install core && snap install microk8s --channel=1.18/edge --classic;
snap alias microk8s.kubectl kubectl;

PATH=${PATH}:/snap/bin;



# User
useradd -mUG hugetlbfs,microk8s,operator,sudo,users,wheel ${MY_USER};
passwd ${MY_USER};
chmod 0750 /home/${MY_USER};

DC_BASE_PATH=/home/${MY_USER}/${DC_INSTALL_PATH};
SYS_BACKUP_PATH=${DC_BASE_PATH}/backup;

[[ ! -d "${DC_BASE_PATH}" ]] && { mkdir -pm 0750 "${DC_BASE_PATH}"; chmod 0750 "$(dirname ${DC_BASE_PATH})"; }

[[ ! -d "${SYS_BACKUP_PATH}" ]] && mkdir -pm 0750 "${SYS_BACKUP_PATH}";

cd ${DC_BASE_PATH} && mkdir -pm 0750 .tmp && cd .tmp;

# Kernel
wget https://raw.githubusercontent.com/Xpawn/estaribel/master/etc/sysctl.d/999-local.conf;
cat /proc/meminfo > meminfo;

MEMTOTAL=$(awk '/MemTotal/ { print $2 * 1024 }' meminfo);
SHMMAX=$(echo ${MEMTOTAL} - 1 | bc);
SHMALL=$(echo "${SHMMAX} / $(getconf PAGE_SIZE)" | bc);

sed -i "s/# kernel.shmmax/kernel.shmmax = ${SHMMAX}/g" 999-local.conf;
sed -i "s/# kernel.shmall/kernel.shmall = ${SHMALL}/g" 999-local.conf;

chmod 0644 999-local.conf && mv 999-local.conf /etc/sysctl.d/999-local.conf;

# Limits (ToDo)

# SSH
wget https://raw.githubusercontent.com/Xpawn/estaribel/master/etc/ssh/sshd_config;

sed -i "s/Port 22/Port ${SSH_TCP_PORT}/g" sshd_config;
sed -i "s/# ListenAddress 127\.0\.0\.1/ListenAddress 127\.0\.0\.1/g" sshd_config;
sed -i "s/# ListenAddress 0\.0\.0\.0/ListenAddress ${SRV_IP}/g" sshd_config;

mv /etc/ssh/sshd_config ${SYS_BACKUP_PATH}/;
chmod 0644 sshd_config && mv sshd_config /etc/ssh/sshd_config;

# FireWall
ufw --force enable; ufw default allow outgoing; ufw default allow routed; ufw allow in on cni0; ufw allow out on cni0; ufw allow ${SSH_TCP_PORT};

# Install dir ownership
chown -R ${MY_USER}:${MY_USER} /home/${MY_USER};

# K8s
su - ${MY_USER} -s /bin/bash;

microk8s.status --wait-ready && microk8s.enable storage && microk8s.enable dns && sleep 3;
microk8s.enable helm3 && sleep 1 && microk8s.enable registry && sleep 2;

sudo snap alias microk8s.helm3 helm;

echo '{"kind":"Namespace","apiVersion":"v1","metadata":{"name":"dragonchain","labels":{"name":"dragonchain"}}}' | kubectl create -f -;

helm repo add dragonchain https://dragonchain-charts.s3.amazonaws.com && helm repo update;

# Final check
microk8s.kubectl get nodes && microk8s.kubectl get services && microk8s.kubectl get po,svc --namespace kube-system;

# Say Good Bye!
exit 0
