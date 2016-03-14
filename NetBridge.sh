#!/bin/bash


# We need to be root to move files and start/stop services
if (( $EUID != 0 )); then
  echo ""
  echo "Please run with root privileges, e.g.:"
  echo "`whoami`@`hostname`:`pwd` $ sudo ${0}"
  echo ""
  exit
fi

# Automatically install what we need
if [[ ! $(type -P "hostapd") || ! $(type -P "udhcpd") ]]; then
  echo "It looks like this is the first time this script has been run."
  read -p "Install required packages? (y/N): " -n 1 -r
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
    echo ""
    exit 1
  fi
  echo
  apt-get install hostapd udhcpd || { echo "Error: Please install hostapd and dhcpd" 1>&2; exit 1;}
  service hostapd stop
  service udhcpd stop
  sed -i -e "s/DHCPD_ENABLED=\"no\"/#DHCPD_ENABLED=\"no\"/g" /etc/default/udhcpd
  sed -i -e "s/\#DAEMON_CONF=\"\"/DAEMON_CONF=\"\/etc\/hostapd\/hostapd.conf\"/g" /etc/default/hostapd
  update-rc.d hostapd disable > /dev/null 2>&1
  update-rc.d udhcpd disable > /dev/null 2>&1
  echo "Done..."
  echo
fi

# Valid int_dev: wlan eth ppp [bluetooth]
# Valid cli_dev: wlan eth [bluetooth]

all_dev="`ifconfig -a | sed 's/[ \t].*//;/^\(lo\|\)$/d'` ppp0 bnep0" # Get a list of all network devices, less 'lo'.
                                                                     #  Add ppp0 and bnep0 for testing (bnep0 will only appear when connected)
echo "Choose internet interface:"
select ans in $all_dev; do
  int_dev=$ans;
  if [ -n "$int_dev" ]; then
    break; # $int_dev not empty - i.e. choice made
  fi
done

echo ""
echo "$int_dev selected"
echo ""

all_dev=${all_dev/$int_dev/} # We can't use the same adapter twice, so remove from list
all_dev=${all_dev//ppp?/}    # We can't use the ppp# adapter as client, so remove from list
all_dev=${all_dev//bnep?/}   # This script can't use Bluetooth as client, so remove from list.

echo "Choose client interface:"
select ans in $all_dev; do
  cli_dev=$ans;
  if [ -n "$cli_dev" ]; then
    break; # $cli_dev not empty - i.e. choice made
  fi
done

echo ""
echo "$cli_dev selected"
echo ""


### If cli_dev=wlan, we need to configure the access point:
if [[ $cli_dev == wlan* ]]
then
  killall wpa_supplicant > /dev/null 2>&1 # Kill wpa_supplicant (session only; it interfers with wlan/AP config)
  cp `dirname "$0"`/hostapd.conf.1 /etc/hostapd/hostapd.conf
  sed -i -e "s/%%IFACE%%/$cli_dev/g" /etc/hostapd/hostapd.conf # Set adapter

  mac=`cat /sys/class/net/$cli_dev/address | tail -c 9`
  mac=${mac//:/}
  sed -i -e "s/%%SSID%%/raspberrypi-$mac/g" /etc/hostapd/hostapd.conf # Set SSID, using adapter MAC for uniqueness

  service hostapd start
fi

### If net_dev=wlan0, we need to configure the WLAN settings
# WiFi network details are configured in /etc/wpa_supplicant/wpa_supplicant.conf:
# network={
#     ssid=""
#     psk=""
# }


### If net_dev=ppp, we need to connect to cellular network
#if [[ $net_dev == ppp* ]]
#then
#  # Automatically install what we need
#  if [[ ! $(type -P "ppp") ]]; then
#    echo "Package ppp is not installed."
#    read -p "Install required package? (y/N): " -n 1 -r
#    if [[ ! $REPLY =~ ^[Yy]$ ]]
#    then
#      echo ""
#      exit 1
#    fi
#    echo
#    apt-get install ppp || { echo "Error: Please install ppp" 1>&2; exit 1;}
#    echo "Done..."
#    echo
#  fi
#  #sakis3g and config
#fi

if [[ $int_dev == bnep* ]]
then
  service bluetooth start # In case bluetooth daemon isn't running
  bt-device --list
  echo ""
  read -p "Enter MAC of target device: " bt_mac
  bt-network -c $bt_mac nap -d & # Connect - device must already be paired
  sleep 5 # Allowe time to connect
  dhclient $int_dev
fi


#Setup DHCP server

cp `dirname "$0"`/udhcpd.conf.1 /etc/udhcpd.conf
sed -i -e "s/%%IFACE%%/$cli_dev/g" /etc/udhcpd.conf # Set adapter

ifconfig $cli_dev 192.168.42.1

sh -c "echo 1 > /proc/sys/net/ipv4/ip_forward"

iptables -t nat -A POSTROUTING -o $int_dev -j MASQUERADE
iptables -A FORWARD -i $int_dev -o $cli_dev -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $cli_dev -o $int_dev -j ACCEPT

service udhcpd start

