#!/bin/bash

# CentOS7-template

# To generate a SHA-512 password hash with random salt value do:
# yum -y install epel-release
# yum -y install python36
# python36 -c 'import crypt; print(crypt.crypt("desired_password", crypt.mksalt(crypt.METHOD_SHA512)))'

######### you probably want to change these #########
PASS='$6$G/niFHkAcnCb9Xwg$v0rPvBLu1Wv5EylMOFz6vAGgG0KsCKgBUGbsOUMdvYupRSovyBO8qm//JfvlYn3.orbH9nia4IahekXYkMFtT/'
USERNAME='admin'
GROUPNAME='remoteadmin'
declare -a NTPS=("2.europe.pool.ntp.org" "3.europe.pool.ntp.org")
PACKAGES="vim htop mc"
#####################################################

# yum log path
YUMLOG=$PWD/${0##*/}.yumlog

# Fancy bracketed notifications
OK="\e[1m[  \e[92mOK  \e[39m]\e[0m\t"
WARN="\e[1m[ \e[93mWARN \e[39m]\e[0m\t"
FAIL="\e[1m[ \e[91mFAIL \e[39m]\e[0m\t"
INFO="\e[1m[ \e[96mINFO \e[39m]\e[0m\t"
ADDINF="\t\t ╚══"

[[ $(id -u) -eq 0 ]] || { echo >&2 "Must be root to run this script"; exit 1; }

cat << "EOF"
   ___         _    ___  ___ ____   _                  _      _       
  / __|___ _ _| |_ / _ \/ __|__  | | |_ ___ _ __  _ __| |__ _| |_ ___ 
 | (__/ -_) ' \  _| (_) \__ \ / /  |  _/ -_) '  \| '_ \ / _` |  _/ -_)
  \___\___|_||_\__|\___/|___//_/    \__\___|_|_|_| .__/_\__,_|\__\___|
                                                 |_|                  
EOF

# arg $1 should be service string
function disable_service {
	if systemctl list-unit-files --full -all | grep -Fq "$1.service"
	then    
		if systemctl is-enabled $1 --quiet
		then
			systemctl stop $1
			if systemctl is-active $1 --quiet
			then
				echo -e "$FAIL stopping service $1"
			else
				systemctl disable $1
				if systemctl is-enabled $1 --quiet
				then
					echo -e "$FAIL disabling service $1"
				else
					echo -e "$OK disabling service $1"
				fi
			fi
		else
			echo -e "$WARN $1 is already disabled"
		fi
	else
		echo -e "$WARN disabling service $1"
		echo -e "$ADDINF it doesn't appear to be installed"
	fi
}

function enable_service {
	if systemctl list-unit-files --full -all | grep -Fq "$1.service"
	then
		if systemctl is-enabled $1 --quiet
		then
			echo -e "$WARN $1 is already enabled"
		else
			systemctl enable $1
			systemctl start $1
			if systemctl is-enabled $1 --quiet
			then
				if systemctl is-active $1 --quiet
				then
					echo -e "$OK enabling and running service $1"
				else
					echo -e "$FAIL enabling and running service $1"
					echo -e "$ADDINF it's enabled but didn't start"
				fi
			else
				echo -e "$FAIL enabling service $1"
			fi
		fi
	else
		echo -e "$FAIL enabling service $1"
		echo -e "$ADDINF it doesn't appear to be installed"
	fi
}

# Disable firewald
disable_service "firewalld"

# Disable SELinux
if grep -Fxq "SELINUX=enforcing" "/etc/selinux/config"
then
	sed -i '/SELINUX=enforcing/s/^/#/' '/etc/selinux/config'
	sed -i '/#SELINUX=enforcing/a SELINUX=disabled'	'/etc/selinux/config'
	setenforce 0
	if grep -Fxq "SELINUX=disabled" "/etc/selinux/config"
		then
			echo -e "$OK disabling SELinux"
			echo -e "$ADDINF SELinux will remain enabled, but in permissive mode until reboot"
		else
			echo -e "$FAIL disabling SELinux"
	fi
else
	if selinuxenabled
	then
		echo -e "$WARN SELinux appears to be disabled in config, but running"
		echo -e "$ADDINF SELinux remains enabled, but in permissive mode until reboot"
	else
		echo -e "$WARN SELinux appears to be disabled"
	fi
fi

# Set hostname and add IP to /etc/hosts
if [ $# -eq 2 ]
then
	HOSTNAME=$2
	hostnamectl set-hostname $HOSTNAME
	echo -e "$OK setting hostname to $HOSTNAME"
	IP=$(ip route get 1 | awk '{print $NF;exit}')
	if grep -Pxq "^$IP\t$HOSTNAME" "/etc/hosts"
	then
		echo -e "$WARN hostname entry already present in /etc/hosts"
	else
		echo -e "$IP\t$HOSTNAME" >> "/etc/hosts"
		echo -e "$OK adding $IP $HOSTNAME to /etc/hosts"
	fi
fi

# Add user
USER_GROUP_FAIL=false
if id "$USERNAME" >/dev/null 2>&1
then
	echo -e "$WARN user $USERNAME already exists"
else
	useradd srcadmin
	usermod -p $PASS $USERNAME
	if id "$USERNAME" >/dev/null 2>&1
	then
		echo -e "$OK adding user $USERNAME"
	else
		USER_GROUP_FAIL=true
		echo -e "$FAIL adding user $USERNAME"
	fi
fi

# Add group
if grep -q -E "^${GROUPNAME}:" /etc/group
then
	echo -e "$WARN group $GROUPNAME already exists"
else
	groupadd $GROUPNAME
	if grep -q -E "^${GROUPNAME}:" /etc/group
	then
		echo -e "$OK adding group $GROUPNAME"
	else
		USER_GROUP_FAIL=true
		echo -e "$FAIL adding group $GROUPNAME"
	fi
fi

# Add user to group
if [ "$USER_GROUP_FAIL" = false ]
then
	if id -nG "$USERNAME" | grep -qw "$GROUPNAME"
	then
    echo -e "$WARN user $USERNAME already belongs to $GROUPNAME group"
	else
		usermod -aG $GROUPNAME $USERNAME
		if id -nG "$USERNAME" | grep -qw "$GROUPNAME"
		then
			echo -e "$OK adding user $USERNAME to group $GROUPNAME"
		else
			echo -e "$FAIL adding user $USERNAME to group $GROUPNAME"
		fi
	fi
else
	echo -e "$FAIL adding user $USERNAME to group $GROUPNAME"
	echo -e "$ADDINF User or group doesn't exist"
fi

# enable root without password for $GROUPNAME members
if grep -q "^%wheel" "/etc/sudoers"
then
	# comment out %wheel
	sed -i '/^%wheel/s/^/#/' '/etc/sudoers'
	if grep -q "^%wheel" "/etc/sudoers"
	then
		echo -e "$FAIL disabling wheel"
	else
		echo -e "$OK disabling wheel"
	fi
	# add NOPASSWD: ALL to $GROUPNAME
	if grep -q "^%$GROUPNAME" "/etc/sudoers"
	then
		echo -e "$WARN $GROUPNAME already has NOPASSWD: ALL set"
	else
		sed -i '/## Same thing without a password/a %remoteadmin\tALL=(ALL)\tNOPASSWD: ALL'	'/etc/sudoers'
		if grep -q "^%$GROUPNAME" "/etc/sudoers"
		then
			echo -e "$OK adding NOPASSWD: ALL to $GROUPNAME"
		else
			echo -e "$FAIL adding NOPASSWD: ALL to $GROUPNAME"
		fi
	fi
else
	# wheel already commented out, check %$GROUPNAME
	if grep -q "^%$GROUPNAME" "/etc/sudoers"
	then
		echo -e "$WARN $GROUPNAME already has NOPASSWD: ALL set"
	else
		sed -i '/## Same thing without a password/a %remoteadmin\tALL=(ALL)\tNOPASSWD: ALL'	'/etc/sudoers'
		if grep -q "^%$GROUPNAME" "/etc/sudoers"
		then
			echo -e "$OK adding NOPASSWD: ALL to $GROUPNAME"
		else
			echo -e "$FAIL adding NOPASSWD: ALL to $GROUPNAME"
		fi
	fi
fi

# bashrc additions
function append_to_bashrc {
	echo -e '
# setup script additions
if [ $(id -u) -eq 0 ];
then # you are root, set red colour prompt
\tPS1="\\[$(tput bold ; tput setaf 1)\\]\\h:\\w #\\[$(tput sgr0)\\] "
else # normal
\tPS1="\\[$(tput setaf 2)\\]\\u@\\h:\\w>\\[$(tput sgr0)\\] "
fi
#HISTCONTROL=ignoreboth
HISTSIZE=50000
HISTTIMEFORMAT="%d.%m.%Y %H:%M:%S "\n' >> "$1"
}

# colorful bash prompt and history
function bashrc {
	if grep -q "^# setup script additions" "$1"
		then
			echo -e "$WARN $1 already has script additions"
		else
			append_to_bashrc "$1"
			if grep -q "^# setup script additions" "$1"
			then
				echo -e "$OK adding script additions to $1"
			else
				echo -e "$FAIL adding script additions to $1"
			fi
	fi
}

bashrc "/home/$USERNAME/.bashrc"
bashrc "/root/.bashrc"

# install ntp and enable epel-release repo
echo -e "$INFO installing ntp and enabling epel-release if needed (tail -f $YUMLOG)"
yum -yq install ntp epel-release &> $YUMLOG
echo -e "$OK ╚══ done"

# remove default centos NTP servers
NTP_ERROR=false
if grep -Pq '^server \d.centos.pool.ntp.org iburst' '/etc/ntp.conf'
then
	sed -i '/^server [[:digit:]].centos.pool.ntp.org iburst/s/^/#/' '/etc/ntp.conf'
	if grep -Pq '^server \d.centos.pool.ntp.org iburst' '/etc/ntp.conf'
	then
		NTP_ERROR=true
		echo -e "$FAIL removing centos ntp servers"
	else
		echo -e "$OK removing centos ntp servers"
	fi
fi

# add custom NTP servers
if [ "$NTP_ERROR" = false ]
then
	# reverse elements in array
	min=0
	max=$(( ${#NTPS[@]} -1 ))
	while [[ min -lt max ]]
	do
			# swap current first and last elements
			x="${NTPS[$min]}"
			NTPS[$min]="${NTPS[$max]}"
			NTPS[$max]="$x"
			# move closer
			(( min++, max-- ))
	done

	for ntp in "${NTPS[@]}"
	do
		if grep -Pq "^server $ntp iburst" "/etc/ntp.conf"
		then
			echo -e "$WARN $ntp already present in ntp.conf"
		else
			sed -i "/# Please consider joining the pool/a server $ntp iburst" "/etc/ntp.conf"
			if grep -Pq "^server $ntp iburst" "/etc/ntp.conf"
			then
				echo -e "$OK adding $ntp to ntp.conf"
			else
				echo -e "$FAIL adding $ntp to ntp.conf"
			fi
		fi
	done
else
	echo -e "$WARN skipping addition of ntp servers"
fi

# disable chronyd
disable_service "chronyd"

# enable ntpd
enable_service "ntpd"

# update all packets
echo -e "$INFO preforming yum update (tail -f $YUMLOG)"
yum -yq update &>> $YUMLOG
echo -e "$OK ╚══ done"

# install additional packages
echo -e "$INFO installing additional packages if needed (tail -f $YUMLOG)"
yum -yq install $PACKAGES &>> $YUMLOG
echo -e "$OK ╚══ done"

exit 0

# MIT License
#
# Copyright (c) 2018 Istok Lenarčič

# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
