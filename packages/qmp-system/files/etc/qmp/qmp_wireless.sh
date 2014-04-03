#!/bin/sh
#    Copyright (C) 2011 Fundacio Privada per a la Xarxa Oberta, Lliure i Neutral guifi.net
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
#   Pau Escrich <p4u@dabax.net>
#	Simó Albert i Beltran
#

##############################
# Global variables definition
##############################
QMP_PATH="/etc/qmp"
OWRT_WIRELESS_CONFIG="/etc/config/wireless"
TEMPLATE_BASE="$QMP_PATH/templates/wifi"
WIFI_DEFAULT_CONFIG="$QMP_PATH/templates/wifi/wireless.default.config"
TMP="/tmp"
QMPINFO="/etc/qmp/qmpinfo"

#######################
# Importing files
######################
SOURCE_WIRELESS=1
. $QMP_PATH/qmp_common.sh
[ -z "$SOURCE_NET" ] && . $QMP_PATH/qmp_network.sh
[ -z "$SOURCE_FUNCTIONS" ] && . $QMP_PATH/qmp_functions.sh

##############################
# Prepare wireless interface
#############################
# Prepare de WiFi interfaces
# First parameter: device

qmp_prepare_wireless_iface() {
	local device=$1
	qmp_uci_test wireless.$device && qmp_uci_del_raw wireless.$device
	qmp_uci_set_raw wireless.$device=wifi-iface
}

###################################
# Check channel for wifi interface
###################################
# First parameter: device
# Second parameter: channel
# Third parameter: mode (adhoc, ap, adhoc_ap)
# It returns the same channel if it is right, and the new one fixet if not

qmp_check_channel() {
		local dev="$1"
		local right_channel="$2"
		local channel="$(echo $2 | tr -d b+-)"
		local ht40="$(echo $2 | tr -d b[0-9])"
		local m11b="$(echo $2 | tr -d [0-9]+-)"
		local mode="$3"
		[ ! -z "$channel" ] && chaninfo="$($QMPINFO channels $1 | grep "^$channel ")"

		# Checking if some thing related with channel is wrong
		local wrong=0
		[ -z "$channel" ] || [ -z "$chaninfo" ] && wrong=1
		[ "$mode" == "adhoc" -o "$mode" == "adhoc_ap" ] && [ -z "$(echo $chaninfo | grep adhoc)" ] && wrong=1
		[ "$ht40" == "+" ] && [ -z "$(echo $chaninfo | grep +)" ] && wrong=1
		[ "$ht40" == "-" ] && [ -z "$(echo $chaninfo | grep -)" ] && wrong=1
		[ "$m11b" == "b" ] && [ $channel -gt 14 ] && wrong=1

		# If something wrong, asking for default parameter
		[ $wrong -ne 0 ] && right_channel="$(qmp_wifi_get_default channel $dev $mode)"

		echo "$right_channel"
}

#############################
# Configure driver from wifi
#############################
# This function reload modules from madwifi and mac80211
# Also depending on which driver is configured in config file, modifies the files from /etc/modules.d

qmp_configure_wifi_driver() {
	mac80211_modules="mac80211 ath ath5k ath9k_hw ath9k_common ath9k"
	madwifi_modules="ath_hal ath_ahb ath_pci"

	#Removing all modules
	echo "Removing wifi modules..."
	for m in $(qmp_reverse_order $mac80211_modules); do
		rmmod -f $m 2>/dev/null
	done
	for m in $(qmp_reverse_order $madwifi_modules); do
		rmmod -f $m 2>/dev/null
	done

	rmmod -a

	#Loading driver modules
	echo "Loading wifi modules..."
	driver="$(qmp_uci_get wireless.driver)"
	case $driver in
	"madwifi")
		mv /etc/modules.d/50-madwifi /etc/modules.d/22-madwifi 2>/dev/null
		for m in $madwifi_modules; do
			insmod $m
		done
		;;
	"mac80211")
		mv /etc/modules.d/22-madwifi /etc/modules.d/50-madwifi 2>/dev/null
		for m in $mac80211_modules; do
			insmod $m
		done
		;;
	*)
		qmp_error "Driver $driver not found"
		;;
	esac
}

########################
# Configure wifi device
########################
# Configure a wifi device according qmp config file
# Parameters are: 1-> qmp config id, 2-> device name

qmp_configure_wifi_device() {
	echo ""
	echo "Configuring device $2"

	local id=$1
	local device="$(qmp_uci_get @wireless[$id].device)"

	# checking if device is configured as "none"
	local mode="$(qmp_uci_get @wireless[$id].mode)"
	[ "$mode" == "none" ] && { echo "Interface $device is not managed by the qMp system"; return; }

	# spliting channel in channel number and ht40 mode
	local channel_raw="$(qmp_uci_get @wireless[$id].channel)"
	local channel="$(echo $channel_raw | tr -d b+-)"

	# htmode and mode selection
	local ht40="$(echo $channel_raw | tr -d [0-9][A-z])"
	local mode11=""
	local htmode=""

	[ "$ht40" == "+" -o "$ht40" == "-" ] && {
		# Device is selected to use 40MHz channel
		htmode="HT40$ht40"

		[ $channel -lt 15 ] && {
		# If it is 2.4
			mode11="ng"
		} || {
		# If it is 5
			mode11="na"
		}

	} || { 
		m11b="$(echo $channel_raw | tr -d [0-9]+-)"
		m11n="$($QMPINFO modes $device | grep -c n)"
		[ "$m11b" == "b" ] && { 
			# Mode 11b is forced
			htmode=""
			mode11="b"
		} || [ $m11n -eq 0 ] && { 
			# Device is not 11n compatible
			htmode=""
			mode11="auto"
		} || {
			# Device is 11n compatible
			[ $channel -lt 15 ] && {
			# If it is 2.4
				htmode="HT20"
				mode11="ng"
			} || {
			# If it is 5
				htmode="HT20"
				mode11="na"
			}
		}
	}

	local mac="$(qmp_uci_get @wireless[$id].mac)"
	local name="$(qmp_uci_get @wireless[$id].name)"
	local driver="$(qmp_uci_get wireless.driver)"
	local country="$(qmp_uci_get wireless.country)"
	local mrate="$(qmp_uci_get wireless.mrate)"
	local bssid="$(qmp_uci_get wireless.bssid)"
	local txpower="$(qmp_uci_get @wireless[$id].txpower)"
	local network="$(qmp_get_virtual_iface $device)"
	local key="$(qmp_uci_get @wireless[$id].key)"	
	[ $(echo "$key" | wc -c) -lt 8 ] && encrypt="none" || encrypt="psk2"

	local dev_id="$(echo $device | tr -d [A-z])"
	dev_id=${dev_id:-$(date +%S)}
	local radio="radio$dev_id"

	echo "------------------------"
	echo "Device   $device"
	echo "Mac      $mac"
	echo "Mode     $mode"
	echo "Driver   $driver"
	echo "Channel  $channel"
	echo "Country  $country"
	echo "Network  $network"
	echo "Name     $name"
	echo "HTmode   $htmode"
	echo "11mode   $mode11"
	echo "Mrate    $mrate"
	echo "------------------------"

	local vap=0
	[ $mode == "adhoc_ap" ] && {
		mode="adhoc"
		vap=1
	}

	device_template="$TEMPLATE_BASE/device.$driver-$mode11"
	iface_template="$TEMPLATE_BASE/iface.$mode" 
	vap_template="$TEMPLATE_BASE/iface.ap"

	[ ! -f "$device_template" ] || [ ! -f "$iface_template" ]  && qmp_error "Template $template not found"

	cat $device_template | grep -v "^list " | sed \
	 -e s/"#QMP_RADIO"/"$radio"/ \
	 -e s/"#QMP_TYPE"/"$driver"/ \
	 -e s/"#QMP_MAC"/"$mac"/ \
	 -e s/"#QMP_CHANNEL"/"$channel"/ \
	 -e s/"#QMP_COUNTRY"/"$country"/ \
	 -e s/"#QMP_MRATE"/"$mrate"/ \
	 -e s/"#QMP_HTMODE"/"$htmode"/ \
	 -e s/"#QMP_TXPOWER"/"$txpower"/ > $TMP/qmp_wifi_device

	qmp_prepare_wireless_iface $device

	cat $iface_template | sed \
	 -e s/"#QMP_RADIO"/"$radio"/ \
	 -e s/"#QMP_DEVICE"/"$device"/ \
	 -e s/"#QMP_IFNAME"/"$device"/ \
	 -e s/"#QMP_SSID"/"$(echo "${name:0:32}" | sed -e 's|/|\\/|g')"/ \
	 -e s/"#QMP_BSSID"/"$bssid"/ \
	 -e s/"#QMP_NETWORK"/"$network"/ \
	 -e s/"#QMP_ENC"/"$encrypt"/ \
	 -e s/"#QMP_KEY"/"$key"/ \
	 -e s/"#QMP_MODE"/"$mode"/ > $TMP/qmp_wifi_iface


	# If virtual AP interface has to be configured
	[ "$vap" == "1" ] && {
		qmp_prepare_wireless_iface ${device}ap
		cat $vap_template | sed \
	 	 -e s/"#QMP_RADIO"/"$radio"/ \
		 -e s/"#QMP_DEVICE"/"${device}ap"/ \
		 -e s/"#QMP_IFNAME"/"${device}ap"/ \
		 -e s/"#QMP_SSID"/"${name}-AP"/ \
		 -e s/"#QMP_NETWORK"/"lan"/ \
		 -e s/"#QMP_ENC"/"$encrypt"/ \
		 -e s/"#QMP_KEY"/"$key"/ \
		 -e s/"#QMP_MODE"/"ap"/ >> $TMP/qmp_wifi_iface
	}

	qmp_uci_import $TMP/qmp_wifi_iface
	qmp_uci_import $TMP/qmp_wifi_device

	# List arguments (needed for HT capab)
	cat $device_template | grep "^list " | sed s/"^list "//g | sed \
	 -e s/"#QMP_RADIO"/"$radio"/ | while read l; do
		qmp_uci_add_list_raw $l
	done

	uci reorder wireless.$radio=0
	#uci reorder wireless.@wifi-iface[$index]=16
	uci commit wireless
}

#############################
# Configure all wifi devices
#############################
#This function search for all wifi devices and leave them configured according qmp config file

qmp_configure_wifi() {

	echo "Backuping wireless config file to: $OWRT_WIRELESS_CONFIG.qmp_backup"
	cp $OWRT_WIRELESS_CONFIG $OWRT_WIRELESS_CONFIG.qmp_backup 2>/dev/null
	echo "" > $OWRT_WIRELESS_CONFIG

	local j=0
		
	while qmp_uci_test qmp.@wireless[$j]; do
		qmp_configure_wifi_device $j
		j=$(( $j + 1 ))
	done

	echo ""
	echo "Done: all WiFi devices configured"
}

####################
# Get default values
####################
# This function returns the default values
#  - first parameter: is always what are you asking for (mode, channel, name,...)
#  - second parameter: is device name, only needed by mode and channel
#  - third parameter: is configured mode, only needed by chanel

qmp_wifi_get_default() {
	local what="$1"
	local device="$2"

	# MODE
	# default mode depens on several things:
	#  if only 1 device = adhoc
	#  if only 1 bg device = ap
	#  else depending on index

	if [ "$what" == "mode" ]; then

		local devices=0
		local bg_devices=0
		for wd in $(qmp_get_wifi_devices); do
			devices=$(( $devices + 1 ))
			bg_devices=$(( $bg_devices + $($QMPINFO modes $wd | egrep "b|g" -c) ))
		done

		local index=$(echo $device | tr -d [A-z])

		#If only one device, using AP+ADHOC
		if [ $devices -eq 1 ]; then
			[ $bg_devices -eq 0 ] && echo "adhoc" || echo "adhoc_ap"
		else

		#If only one B/G device (2.4GHz) available, using it as AP+ADHOC
		bg_this_device=$($QMPINFO modes $device | egrep "b|g" -c)
		if [ $bg_this_device -eq 1 -a $bg_devices -eq 1 ]; then
			echo "adhoc_ap"
		else

		#If only one B/G device of two devices, using the non B/G one as adhoc
		if [ $bg_devices -eq 1 -a $devices -eq 2 ]; then
			echo "adhoc"
		else
		
		#If more than one device BG, using first for ADHOC+AP and the others for ADHOC
		if [ $devices -gt 1 ]; then
			[ $index == 0 ] && echo "adhoc_ap" || echo "adhoc"
		else
		
		#This should never happend
			echo "adhoc_ap"
		fi;fi;fi;fi

	# CHANNEL
	# Default channel depends on the card and on configured mode
	#  Highest channel -> adhoc or not-configured
	#  Lower channel -> ap

	elif [ "$what" == "channel" ]; then
		[ -z "$device" ] && qmp_error "Device not found?"
		local mode="$3"

		# we are using index var to put devices in different channels
		local index=$(echo $device | tr -d [A-z])
		index=${index:-0}
		
		# QMPINFO returns a list of avaiable channels in this format: 130 ht40+ adhoc
		# this is the command line used to get available channels from a device
		local channels_cmd="$QMPINFO channels $device"
		local num_channels=$($channels_cmd | wc -l)

		# number of channels for AP is 11 or the number of channels available if less
		local num_channels_ap=$num_channels
		[ $num_channels_ap -gt 11 ] && num_channels_ap=11

		# use 40 Mhz of channel size (802.11n)
		local ht40="" # ht40+/ht40-

		# channel AdHoc is the last available (qmp_tac = inverse order) plus index*2+1 (1 3 5 ...)
		[ "$mode" == "adhoc" ] || [ -z "$mode" ] && {

			#this is global
			ADHOC_INDEX=${ADHOC_INDEX:-0}
			
			channel_info="$(qmp_tac $channels_cmd | grep adhoc | awk NR==${ADHOC_INDEX}+${ADHOC_INDEX}*2+1)"
			
			ADHOC_INDEX=$(($ADHOC_INDEX+1))
			# c is the channel number, checking if it is 802.11bg
			# in such case it will be 1, 6 and 11 for performance and coexistence with other networks
			c="$(echo $channel_info | cut -d' ' -f1)"
			[ $c -lt 14 ] && {
				qmp_log "Using adhoc device in 802.11bg mode"
				if [ $c -lt 5 ]; then c=1                                                                                                 
				else if [ $c -lt 9 ]; then c=6                                                                                            
				else c=11
				fi; fi
			ADHOC_BG_USED="$c"
			channel_info="$c $(echo $channel_info | cut -d' ' -f2-)"

			} || {
				# let's see if we can use ht40 mode
				ht40="$(echo $channel_info | cut -d' ' -f2)"
			}
						
		}
		
		# channel AP = ( node_id + index*3 ) % ( num_channels_ap) + 1
		# channel is 1, 6 or 11 for coexistence and performance
		[ "$mode" = "ap" -o "$mode" = "adhoc_ap" ] && {

			AP_INDEX=${AP_INDEX:-0}

			# if there is only one wifi device, configure a static channel (it will be used as adhoc_ap)
			if [ $($QMPINFO devices wifi | wc -l) -eq 1 ]; then
				c=1
			else
				c=$(((($(qmp_get_dec_node_id)+$AP_INDEX*3) % $num_channels_ap) +1))
				AP_INDEX=$(($AP_INDEX+1))

				if [ $c -lt 5 ]; then c=1
				else if [ $c -lt 9 ]; then c=6
				else c=11
				fi; fi
			
				#if the resulting channel is used by adhoc, selecting another one
				[ -n "$ADHOC_BG_USED" ] && [ $ADHOC_BG_USED -eq $c ] && \
				( [ $c -lt 7 ] && c=$(($c+5)) || c=$(($c-5)) )
			fi

			channel_info="$($channels_cmd | awk NR==$c)"
		}
		
		# if there is some problem, channel 6 is used
		if [ -z "$channel_info" ]; then
			qmp_log "Warning, not usable channels found in device $device "
			[ "$1" == "channel" ] && echo "6"
			return
		fi

		channel="$(echo $channel_info | cut -d' ' -f1)"
		[ "$ht40" == "ht40+" ] && channel="${channel}+"
		[ "$ht40" == "ht40-" ] && channel="${channel}-"

		echo "$channel"

	# REST OF DEFAULT VAULES
	# The rest of default values are taken from the template
	else
		[ ! -f "$WIFI_DEFAULT_CONFIG" ] && qmp_error "Template not found $WIFI_DEFAULT_CONFIG"
		cat $WIFI_DEFAULT_CONFIG | grep $what | cut -d' ' -f2
	fi
}

qmp_reset_wifi() {
	#Generating default wifi configuration
	country="$(uci get qmp.wireless.country 2>/dev/null)"
	country="${country:-00}"

	mv /etc/config/wireless /tmp/wireless.old
	wifi detect | sed s/"disabled 1"/"country $country"/g > /etc/config/wireless

	wifi
}

qmp_configure_wifi_initial() {

	#First we are going to configure default parameters if they are not present
	[ -z "$(qmp_uci_get wireless)" ] && qmp_uci_set wireless qmp
	[ -z "$(qmp_uci_get wireless.driver)" ] && qmp_uci_set wireless.driver $(qmp_wifi_get_default driver)
	[ -z "$(qmp_uci_get wireless.country)" ] && qmp_uci_set wireless.country $(qmp_wifi_get_default country)
	[ -z "$(qmp_uci_get wireless.bssid)" ] && qmp_uci_set wireless.bssid $(qmp_wifi_get_default bssid)
	[ -z "$(qmp_uci_get wireless.mrate)" ] && qmp_uci_set wireless.mrate $(qmp_wifi_get_default mrate)

	#Changing to configured countrycode
	iw reg set $(qmp_uci_get wireless.country)

	macs="$(qmp_get_wifi_mac_devices | sort -u)"

	#Looking for configured devices
	id_configured=""
	to_configure=""
	for m in $macs; do
		found=0
		j=0
		while [ ! -z "$(qmp_uci_get @wireless[$j])" ]; do
			configured_mac="$(qmp_uci_get @wireless[$j].mac | tr [A-Z] [a-z])"
			if [ "$configured_mac" == "$m" ]; then
				#If we found configured device, we are going to check all needed parameters
				found=1
				device="$(qmp_get_dev_from_wifi_mac $m)"
				id_configured="$id_configured $j"
				echo "Found configured device: $m"
			        [ -z "$(qmp_uci_get @wireless[$j].mode)" ] && qmp_uci_set @wireless[$j].mode $(qmp_wifi_get_default mode $device)
        			[ -z "$(qmp_uci_get @wireless[$j].name)" ] && qmp_uci_set @wireless[$j].name $(qmp_wifi_get_default name)
				[ -z "$(qmp_uci_get @wireless[$j].txpower)" ] && qmp_uci_set @wireless[$j].txpower $(qmp_wifi_get_default txpower)

				# If channel is configured, we are going to check it
				# if not, using default one
				sleep 1 && mode="$(qmp_uci_get @wireless[$j].mode)"
				channel="$(qmp_uci_get @wireless[$j].channel)"
				if [ -z "$channel" ]; then
					 qmp_uci_set @wireless[$j].channel $(qmp_wifi_get_default channel $device $mode)

				else
					newchan="$(qmp_check_channel $device $channel $mode)"
					if [ "$newchan" != "$channel" ]; then
						qmp_log Warning: "Channel $channel for device $device in mode $mode is not right, using default one"
						qmp_uci_set @wireless[$j].channel $newchan
					fi
				fi

				qmp_uci_set @wireless[$j].device $device
				break
			fi
			j=$(( $j + 1 ))
		done

		[ $found -eq 0 ] && to_configure="$to_configure $m"
	done

	#Configuring devices not found before
	for m in $to_configure; do
		device=$(qmp_get_dev_from_wifi_mac $m)
		echo "Configuring device: $device | $m"
		#Looking for a free slot to put new configuration
		j=0
		while [ ! -z "$(echo $id_configured | grep $j)" ]; do j=$(( $j +1 )); done
		#Now we have a free slot, let's go to configure device
		[ -z "$(qmp_uci_get @wireless[$j])" ] && qmp_uci_add wireless
		[ -z "$(qmp_uci_get @wireless[$j].mode)" ] && qmp_uci_set @wireless[$j].mode $(qmp_wifi_get_default mode $device)
		[ -z "$(qmp_uci_get @wireless[$j].name)" ] && qmp_uci_set @wireless[$j].name $(qmp_wifi_get_default name)
		[ -z "$(qmp_uci_get @wireless[$j].txpower)" ] && qmp_uci_set @wireless[$j].txpower $(qmp_wifi_get_default txpower)
		sleep 1 && mode="$(qmp_uci_get @wireless[$j].mode)"
		channel="$(qmp_uci_get @wireless[$j].channel)"
		[ -z "$channel" ] && channel=$(qmp_wifi_get_default channel $device $mode)
		qmp_uci_set @wireless[$j].channel "$(qmp_check_channel $device $channel $mode)"
		qmp_uci_set @wireless[$j].mac $m
		qmp_uci_set @wireless[$j].device $device
		id_configured="$id_configured $j"
	done
}
