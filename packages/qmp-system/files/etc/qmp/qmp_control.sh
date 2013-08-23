# Copyright (C) 2011 Fundacio Privada per a la Xarxa Oberta, Lliure i Neutral guifi.net
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License along
#    with this program; if not, write to the Free Software Foundation, Inc.,
#    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
#    The full GNU General Public License is included in this distribution in
#    the file called "COPYING".
#
# Contributors:
#	Pau Escrich <p4u@dabax.net>
#	Simó Albert i Beltran
#

QMP_PATH="/etc/qmp"

. $QMP_PATH/qmp_common.sh
. $QMP_PATH/qmp_functions.sh
. $QMP_PATH/qmp_gw.sh
. $QMP_PATH/qmp_wireless.sh
. $QMP_PATH/qmp_network.sh
. $QMP_PATH/qmp_update.sh

offer_default_gw() {
	qmp_gw_default offer $1
	qmp_gw_apply
}

search_default_gw() {
	qmp_gw_default search $1
	qmp_gw_apply
}

disable_default_gw() {
	qmp_gw_default disable $1
	qmp_gw_apply
}

reset_wifi() {
	qmp_reset_wifi
	configure_wifi
}

configure_wifi() {
	qmp_configure_wifi_initial
	qmp_configure_wifi
	/etc/init.d/network reload
	if /etc/init.d/gwck enabled
	then
		/etc/init.d/gwck restart
	fi
}

configure_gw() {
	qmp_gw_apply
}

apply_netserver() {
	[ "$(qmp_uci_get networks.netserver)" == "1" ] && qmp_enable_netserver || qmp_disable_netserver
}

configure_network() {
	qmp_configure
	[ -f "/etc/init.d/olsrd" ] && /etc/init.d/olsrd restart
	bmx6 -c --configReload || /etc/init.d/bmx6 restart
	/etc/init.d/network reload
	if /etc/init.d/gwck enabled
	then
		/etc/init.d/gwck restart
	fi
	/etc/init.d/dnsmasq restart
	apply_netserver
	qmp_restart_firewall
}

configure_system() {
	qmp_configure_system
	/etc/init.d/uhttpd restart
}

enable_ns_ppt() {
	echo 8 > /sys/class/gpio/export
	echo out > /sys/class/gpio/gpio8/direction
	echo 1 > /sys/class/gpio/gpio8/value
}

publish_hna() {
	[ -z "$1" ] && help
	qmp_publish_hna_bmx6 $1 $2
}

unpublish_hna() {
	[ -z "$1" ] && help
	qmp_unpublish_hna_bmx6 $1
}

upgrade() {
	qmp_update_upgrade_system $1 && hard_reboot
}

hard_reboot() {
	echo "System is gonna be rebooted now!"
	echo 1 > /proc/sys/kernel/sysrq
	echo b > /proc/sysrq-trigger 
}

configure_all() {
	configure_system
	configure_wifi
	configure_network	
	apply_netserver
}

safe_apply() {
	[ -e "/tmp/qmp.save.tar.gz" ] && echo "Found saved state at /tmp/qmp.save.tar.gz. Make sure you want to use it!" \
	|| { 
		echo "Cannot found saved state, saving it..."
		save_state
	}
	
	touch /tmp/qmp.safe.test
	echo "------------------------------------------------------------------------------------"
	echo "File /tmp/qmp.safe.test has been created, after configuring the system you will have 
	180 seconds to remove it or the previous state will be recovered"
	echo "------------------------------------------------------------------------------------"
	
	read -p'Do you agree?[y,N] ' a
	[ "$a" != "y" ] && return
	
	configure_all
	
	( sleep 180
		[ -e "/tmp/qmp.safe.test" ] && {
			cp -f /etc/config/qmp /tmp/qmp.wrong
			recover_state
			cp -f /tmp/qmp.wrong /etc/config/qmp.wrong
			hard_reboot
		} || rm -f "/tmp/qmp.safe.test"
	) &
}

save_state() {
	echo "Saving state at $(date) in file /tmp/qmp.save.tar.gz"
	rm -f /tmp/qmp.save.tar.gz 2>/dev/null
	(cd /overlay/etc && tar czf /tmp/qmp.save.tar.gz .)
	[ ! -e /tmp/qmp.save.tar.gz ] && echo "ERROR: cannot save state, exiting..." && exit 1
}

recover_state() {
	echo "Recovering state at $(date) from /tmp/qmp.save.tar.gz"
	[ -e "/tmp/qmp.save.tar.gz" ] && tar xvzf /tmp/qmp.save.tar.gz -C /overlay/etc/ \
	|| echo "Cannot recover state because it has not been saved before"
}

help() {
	echo "Use: $0 <function> [params]"
		
	echo ""
	echo "Configuration:"
	echo " configure_all			: Configure and apply all settings"
	echo " configure_network		: Configure and apply network settings"
	echo " configure_system 		: Configure and apply system settings (qmp.node section and so on)"
	echo " configure_wifi			: Configure all WiFi devices"
	echo " reset_wifi			: Reset, rescan and configure all the WiFi devices"
	echo " configure_gw			: Configure and apply gateways settings"
	
	echo ""
	echo "Safe configuration:"
	echo " save_state			: Saves current state of configuration files"
	echo " recover_state			: Recovers previous saved state"
	echo " safe_apply			: Performs a safe configure_all. If something wrong it comes back to old state"
	
	echo ""
	echo "Gateways:"
	echo " offer_default_gw [ipv4|ipv6]	: Offers default gw to the network IPv4 or IPv6, both versions if no value"
	echo " search_default_gw [ipv4|ipv6]	: Search for a default gw in the network IPv4 or IPv6, both versions if no value"
	echo " disable_default_gw [ipv4|ipv6]	: Disables the search/offer of default GW IPv4 and/or IPv6"
	echo " publish_hna			: Publish an IP range (v4 or v6): publish_hna <IP/NETMASK> [ID]"
	echo " unpublish_hna			: Unpublish a current HNA: unpublish_hna <ID>"

	echo ""
	echo "Other:"
	echo " apply_netserver  		: Start/stop nerserver depending on qmp configuration"
	echo " enable_ns_ppt			: Enable POE passtrought from NanoStation M2/5 devices. Be careful with this option!"
	echo " upgrade [URL]			: Upgrade system. By default to the last version, but image url can be provided to force"
	echo " hard_reboot			: Performs a hard reboot (using kernel sysrq)"
	
	echo ""
	exit 0
}


[ -z "$1" ] && help

echo "executing function $1"
$@

