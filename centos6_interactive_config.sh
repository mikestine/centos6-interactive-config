#!/bin/bash
# CentOS 6 Config Tool V2
# by Michael Stine, 2017




###
function ask_menu_or_quit {
  # ask to quit
  local choice_quit=""
  read -p "Press [Enter] to continue OR press [Q] to quit: " -n 1 -r -s choice_quit;
  if [[ $choice_quit =~ ^[Qq]$ ]]; then
    quit
  fi

}




###
function check_quit {
  local choice="$1"
  if [[ "$choice" =~ ^[Qq]$ ]]; then
    quit
  fi
}

###
function ask_network_restart {
  # if network has already started, ask to restart network
  local network_status="$(get_network_state)"
  local choice=""
  while ! [[ "$choice" =~ ^[Yy]$|^[Nn]$|^[Qq]$ ]]; do
    read -p "Network service is '$network_status', Restart Network Service? [y/n/(Q)uit] " -n 1 -r choice; printf "\n"; check_quit "$choice"
    if [[ $choice =~ ^[Yy]$ ]]; then
      service network restart
    fi
  done
}



function prompt_continue {
  printf "\n"
  read -n 1 -s -p "Press any key to continue"
}


###################################################################
###################################################################
# VM Prep resolves mac address collission problems when cloning

function set_hostname {
  local current_hostname="$(hostname)"
  local input_hostname=""

  read -p "ENTER Hostname: " -i "$current_hostname" -e input_hostname

  if [ "$input_hostname" !=  "$current_hostname" ]; then

    # temporarily changes hostname
    hostname "$input_hostname"

    # permanently change hostname, reboot required
    # update HOSTNAME variable in /etc/sysconfig/network
    if grep -q "HOSTNAME=" "/etc/sysconfig/network"; then
      sed -i "s/.*HOSTNAME=.*/HOSTNAME=${input_hostname}/" /etc/sysconfig/network
    else
      printf "HOSTNAME=${input_hostname}" >> /etc/sysconfig/network
    fi

    # update /etc/hosts - change 127.0.0.1
    if grep -q "127.0.0.1 " "/etc/hosts"; then
      sed -i "s/127.0.0.1 .*/127.0.0.1    localhost ${input_hostname}/" /etc/hosts
    else
      printf "127.0.0.1    localhost ${input_hostname}" >> /etc/hosts
    fi

    # update /etc/hosts - change IPV6 loopback address
    if grep -q "::1 " "/etc/hosts"; then
      sed -i "s/::1 .*/::1    localhost ${input_hostname}/" /etc/hosts
    else
      printf "::1    localhost ${input_hostname}" >> /etc/hosts
    fi

    printf "\nHostname change is temporary, and requires reboot to be permanent\n"
    prompt_continue

  fi
}

###################################################################
###################################################################
# VM Prep resolves mac address collission problems when cloning
function get_vmprep {
  if [ ! -f "/etc/udev/rules.d/70-persistent-net.rules" ]; then
    echo "Prepped"
  else
    echo "Not Prepped"
  fi
}

function set_vmprep {
  printf "\nRemoving File: /etc/udev/rules.d/70-persistent-net.rules \n\n"

  rm -fv /etc/udev/rules.d/70-persistent-net.rules;
}
###################################################################
###################################################################
# Network Service

# when enabled, sestatus returns
#   SELinux status:                 enabled
#   SELinuxfs mount:                /selinux
#   Current mode:                   enabled
#   ...

# when permissive, sestatus returns
#   SELinux status:                 enabled
#   SELinuxfs mount:                /selinux
#   Current mode:                   permissive
#   ...

# when disabled, sestatus returns
#   SELinux status:                 disabled

function get_selinux_state {
  local status="$(sestatus)"
  if [[ "$status" =~ ^SELinux\ .*disabled ]]; then
    echo "disabled"
  elif [[ "$status" =~ ^SELinux\ .*enabled  && "$status" =~ Current\ mode:.*permissive ]]; then
    echo "permissive"
  elif [[ "$status" =~ ^SELinux\ .*enabled  && "$status" =~ Current\ mode:.*enforcing ]]; then
    echo "enforcing"
  fi
}

function set_selinux_state {
  local choice=""
  while ! [[ "$choice" =~ ^[Ee]$|^[Pp]$|^[Dd]$|^[Bb]$ ]]; do
    read -p "SET SELinux state: (e)nforce, (p)ermissive, (d)isabled, or (b)ack (REBOOT REQUIRED) [e/p/d/b]? " -n 1 -r choice; printf "\n"
    if [[ $choice =~ ^[Ee]$ ]]; then
      sed -i "s/.*SELINUX=\w.*/SELINUX=enforcing/" /etc/selinux/config
      setenforce 1
      printf "\nSELinux is temporarily set to enforce.  After reboot, will be permanent. \n"
      prompt_continue
    elif [[ $choice =~ ^[Pp]$ ]]; then
      sed -i "s/.*SELINUX=\w.*/SELINUX=permissive/" /etc/selinux/config
      setenforce 0
      printf "\nSELinux is temporarily set to permissive.  After reboot, will be permanent. \n"
      prompt_continue
    elif [[ $choice =~ ^[Dd]$ ]]; then
      sed -i "s/.*SELINUX=\w.*/SELINUX=disabled/" /etc/selinux/config
      setenforce 0
      printf "\nSELinux will be set to permissive.  After reboot, will be disabled. \n"
      prompt_continue
    fi
  done

}

###################################################################
###################################################################
## Network config

# To get ip address, look at ifconfig of eth0, find the line containing
#   inet addr, print the second column of the line, begin on the 6th character
# To get static or dhcp, look at the value of BOOTPROTO in ifcfg-eth0 file

function get_network_config {
  local bootproto="$( cat "/etc/sysconfig/network-scripts/ifcfg-eth0" | sed -n -e 's/.*BOOTPROTO=//p' )"
  local ip="$(ifconfig eth0 | awk '/inet addr/{print substr($2,6)}')"

  if [[ "$bootproto" == "dhcp"  ]]; then
    echo "(dhcp) $ip"
  elif [[ "$bootproto" == "static" ]]; then
    #return ip address
    echo "(static) $ip"
  fi
}

function set_network_config {
  local choice=""
  while ! [[ "$choice" =~ ^[Dd]$|^[Ss]$|^[Bb]$ ]]; do
    read -p "Boot Protocol: (d)hcp, (s)tatic, or (b)ack [d/s/b] " -n 1 -r choice; printf "\n";
    if [[ $choice =~ ^[Dd]$ ]]; then
      set_network_config_dhcp
    elif [[ "$choice" =~ ^[Ss]$ ]]; then
      set_network_config_static
    fi
  done

}

function set_network_config_dhcp {
  printf "\nSetting Network Config to DHCP on eth0. \n\n"

  local eth0="/etc/sysconfig/network-scripts/ifcfg-eth0"
  local mac="$(cat /sys/class/net/eth0/address)"
cat > $eth0 <<EOF
DEVICE=eth0
HWADDR=$mac
TYPE=Ethernet
BOOTPROTO=dhcp
ONBOOT=YES
NM_CONTROLLED=no
USERCTL=no
EOF

  service network restart
  prompt_continue
}

function set_network_config_static {
  printf "\nSetting Network Config to STATIC on eth0. \n\n"

  local input_network_name=""
  local input_network_ipaddr=""
  local input_network_broadcast=""
  local input_network_netmask=""
  local input_network_gateway=""
  local input_network_dns1=""
  local input_network_dns1=""
  local eth0="/etc/sysconfig/network-scripts/ifcfg-eth0"
  local mac="$(cat /sys/class/net/eth0/address)"

  read -p "SET NETWORK NAME: " -i "System eth0" -e input_network_name
  read -p "SET IPADDR: " -i "10.102.215.999" -e input_network_ipaddr
  read -p "SET BROADCAST: " -i "10.102.215.255" -e input_network_broadcast
  read -p "SET NETMASK: " -i "255.255.255.0" -e input_network_netmask
  read -p "SET GATEWAY: " -i "10.102.215.1" -e input_network_gateway
  read -p "SET DNS1: " -i "170.20.134.160" -e input_network_dns1
  read -p "SET DNS2: " -i "170.20.76.236" -e input_network_dns1
cat > $eth0 <<EOF
DEVICE=eth0
HWADDR=$mac
TYPE=Ethernet
ONBOOT=yes
NM_CONTROLLED=no
USERCTL=no
BOOTPROTO=static
NAME=$input_network_name
IPADDR=$input_network_ipaddr
BROADCAST=$input_network_broadcast
NETMASK=$input_network_netmask
GATEWAY=$input_network_gateway
DNS1=$choice_network_dns1
DNS2=$choice_network_dns1
EOF

  service network restart
  prompt_continue
}



###################################################################
###################################################################
## IPTables

function get_iptables_state {
  local iptables_status="Enabled"
  if [[ "$(service iptables status)" = "iptables: Firewall is not running." ]]; then iptables_status="Disabled"; fi
  echo "$iptables_status"
}

function set_iptables_state {
  local choice=""
  while ! [[ "$choice" =~ ^[Dd]$|^[Ss]$|^[Bb]$ ]]; do
    read -p "IPTables Service: (d)isable, (e)nable, or (b)ack [d/s/b] " -n 1 -r choice; printf "\n";
    if [[ $choice =~ ^[Dd]$ ]]; then
      set_iptables_state_disable
    elif [[ "$choice" =~ ^[Ss]$ ]]; then
      set_iptables_state_enable
    fi
  done
}

function set_iptables_state_disable {
  printf "\nDisabling IPTables \n\n"

  service iptables save
  service iptables stop
  chkconfig iptables off
  service ip6tables save
  service ip6tables stop
  chkconfig ip6tables off

  service iptables status
  service ip6tables status

  prompt_continue
}

function set_iptables_state_enable {
  printf "\Enabling IPTables \n\n"
  service iptables save
  service iptables restart
  chkconfig --level 345 iptables on
  service iptables save
  service ip6tables restart
  chkconfig --level 345 ip6tables on

  service iptables status
  service ip6tables status

  prompt_continue
}

###################################################################
###################################################################
# Global alias

function get_global_alias_state {
  if [ -e "/etc/profile.d/global_aliases.sh" ]; then
    echo "Exists"
  else
    echo "Does Not Exist"
  fi
}

function set_global_alias_state_add {

  printf "Created /etc/profile.d/global_aliases.sh\n\n"

cat > /etc/profile.d/global_aliases.sh <<EOF
#!/bin/bash
alias vi='vim'
alias vieth0='vim /etc/sysconfig/network-scripts/ifcfg-eth0'
alias vieth1='vim /etc/sysconfig/network-scripts/ifcfg-eth1'
EOF

  chmod 644 /etc/profile.d/global_aliases.sh
}

function set_global_alias_state_remove {
  rm -fv "/etc/profile.d/global_aliases.sh"
}

function set_global_alias_state {
  local choice=""
  while ! [[ "$choice" =~ ^[Aa]$|^[Rr]$|^[Bb]$ ]]; do

    read -p "Global Alias File: Cre(a)te, (r)emove, (b)ack [a/r/b]? " -n 1 -r choice; printf "\n\n"

    if [[ $choice =~ ^[Aa]$ ]]; then
      set_global_alias_state_add
      prompt_continue
    elif [[ $choice =~ ^[Rr]$ ]]; then
      set_global_alias_state_remove
      prompt_continue
    fi
  done
}


###################################################################
###################################################################
# SSH

function get_ssh_install {
  yum -q list installed openssh-server &>/dev/null && echo "installed" || echo "not installed"
}

function set_ssh_install {
  yum -y install openssh-server
  yum -y update openssh-server && yum -y upgrade openssh-server
}

function set_ssh_uninstall {
  yum -y remove openssh-server
}

  #elif (( $(ps -ef | grep -v grep | grep sshd | wc -l) > 0 )); then

function set_ssh_state_disable {
  service sshd stop
  service sshd status
  chkconfig sshd off
}

function set_ssh_state_enable {
  service sshd start
  service sshd status
  chkconfig sshd on
}

function get_ssh_state {

  if [ "$(get_ssh_install)" == "not installed" ]; then
    echo "[not installed]"
  elif [[ "$(service sshd status)" =~ .*running.* ]]; then
    echo "[installed] enabled"
  else
    echo "[installed] disabled"
  fi
}




function set_ssh_configure {
  if [ "$(get_ssh_install)" == "installed" ]; then
    local input_ssh_port=""
    local choice_restart_service=""

    read -p "SET SSH port: " -i "7800" -e input_ssh_port
    sed -i "s/.*Port .*/Port ${input_ssh_port}/" /etc/ssh/sshd_config

    read -p "Restart SSH Service [y/n]?" -n 1 -r choice_restart_service; printf "\n"
    if [[ $change_ssh =~ ^[Yy]$ ]]; then
      service sshd start
      service sshd status
      chkconfig sshd on
    fi
  else
    echo "SSH Is Not Installed"
  fi
}

function set_ssh_state {
  local choice=""
  while ! [[ "$choice" =~ ^[Qq]$ ]]; do
    clear
    echo "SSH Status: $(get_ssh_state)"
    read -p "(i)nstall, (u)ninstall, (e)nable, (d)isable, (c)onfigure, (q)uit [i/u/e/d/c/q]? " -n 1 -r choice; printf "\n\n"

    if [[ $choice =~ ^[Ii]$ ]]; then
      set_ssh_install
      prompt_continue
    elif [[ $choice =~ ^[Uu]$ ]]; then
      set_ssh_uninstall
      prompt_continue
    elif [[ $choice =~ ^[Ee]$ ]]; then
      set_ssh_state_enable
      prompt_continue
    elif [[ $choice =~ ^[Dd]$ ]]; then
      set_ssh_state_disable
      prompt_continue
    elif [[ $choice =~ ^[Cc]$ ]]; then
      set_ssh_configure
      prompt_continue
    fi
  done

}



###################################################################
###################################################################
# Network Service
function get_network_state {
  # when network service is running 'service network status' command outputs
  #Configured devices:
  #lo eth0
  #Currently active devices:
  #lo eth0ç

  # when service is stopped, output looks like
  #Configured devices:
  #lo eth0
  #Currently active devices:

  #count lines = 4 to see if devices are active
  if [ "$( echo "$(service network status)" | wc -l )" -eq "4" ]; then
    echo "STARTED"
  else
    echo "STOPPED"
  fi
}

function set_network_state {
  local choice=""
  while ! [[ "$choice" =~ ^[Rr]$|^[Ss]$|^[Tt]$|^[Aa]$|^[Bb]$ ]]; do

    read -p "Network Service: (r)estart, (s)tart, s(t)op, st(a)tus, (b)ack [r/s/t/a/b]? " -n 1 -r choice; printf "\n\n"

    if [[ $choice =~ ^[Rr]$ ]]; then
      service network restart
      prompt_continue
    elif [[ $choice =~ ^[Ss]$ ]]; then
      service network start
      prompt_continue
    elif [[ $choice =~ ^[Tt]$ ]]; then
      service network stop
      prompt_continue
    elif [[ $choice =~ ^[Aa]$ ]]; then
      service network status
      prompt_continue
    fi
  done

}
###################################################################
###################################################################
## reboot machine
function choice_reboot {
  # ask to reboot machine
  local choice=""
  while ! [[ "$choice" =~ ^[Yy]$|^[Nn]$ ]]; do
    read -p "Reboot Now? [y/n] " -n 1 -r choice; printf "\n";
    if [[ $choice =~ ^[Yy]$ ]]; then
      reboot -h now
      quit
    fi
  done
}
###################################################################
###################################################################
## quit script
function quit {
  printf "Quitting...\n\n"
  exit
}
###################################################################
###################################################################
# main function
function main {




  local option=""
  while :
  do
    clear



    cat<<EOF
==========================
Cent OS 6 Tool V2.0x
by Michael Stine, 20170517
--------------------------
Please enter your choice:
1) Hostname: $(hostname)
2) VMPrep: $(get_vmprep)
3) SELinux: $(get_selinux_state)
4) Network Config: $(get_network_config)
5) IPTables: $(get_iptables_state)
6) Global Aliases File: $(get_global_alias_state)
7) SSH: $(get_ssh_state)
N) Network Service: $(get_network_state)
R) Reboot NOW
q) Quit
--------------------------

EOF
    # read
    # -r        Backslash  does not act as an escape character.  The backslash is considered to be part of the line. In particular, a backslash-newline pair can not be used as a line continuation.
    # -n nchars
    #           read returns after reading nchars characters rather than waiting for a complete line of input.
    # -s        Silent mode. If input is coming from a terminal, characters are not echoed.
    # -p prompt
    #           Display prompt on standard error, without a trailing newline, before attempting to read
    #           any input. The prompt is displayed only if input is coming from a terminal.
    # -i        text	Use TEXT as the initial text for Readline
    #  If no names are supplied, the line read is assigned to the variable REPLY. The return code is zero, unless end-of-file is encountered or read times out.
    printf ">"
    read -n 1 -r option; printf "\n"
    case "$option" in
      "1") set_hostname ;;
      "2") set_vmprep ;;
      "3") set_selinux_state ;;
      "4") set_network_config ;;
      "5") set_iptables_state ;;
      "6") set_global_alias_state ;;
      "7") set_ssh_state ;;
      "N") set_network_state ;;
      "R") choice_reboot ;;
      [qQ]) quit ;;
    esac
    sleep .2
  done

}

main
