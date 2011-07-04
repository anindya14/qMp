#!/bin/sh

QMP_PATH="/etc/qmp"
OWRT_WIRELESS_CONFIG="/etc/config/wireless"
TEMPLATE_BASE="$QMP_PATH/templates/wireless" # followed by .driver.mode (wireless.mac80211.adhoc)
WIFI_DEFAULT_CONFIG="$QMP_PATH/templates/wireless.default.config"

#Importing files
. $QMP_PATH/qmp_common.sh

qmp_configure_wifi_driver() {
	driver="$(qmp_uci_get wireless.driver)"
	case $driver in
	"madwifi")
		mv /etc/modules.d/50-madwifi /etc/modules.d/22-madwifi 2>/dev/null
		;;
	"mac80211")
		mv /etc/modules.d/22-madwifi /etc/modules.d/50-madwifi 2>/dev/null
		;;
	*)
		qmp_error "Driver $driver not found"
		;;
	esac
}

qmp_configure_wifi_device() {
#Configure a wifi device according qmp config file
#Parameters are: 1-> qmp config id, 2-> device name

	echo ""
	echo "Configuring device $2"

	id=$1
	device=$2
	mac="$(qmp_uci_get @wireless[$id].mac)"
	channel="$(qmp_uci_get @wireless[$id].channel)"
	mode="$(qmp_uci_get @wireless[$id].mode)"
	name="$(qmp_uci_get @wireless[$id].name)"
	driver="$(qmp_uci_get wireless.driver)"
	country="$(qmp_uci_get wireless.country)"
	bssid="$(qmp_uci_get wireless.bssid)"
	
	echo "------------------------"
	echo "Mac: $mac"
	echo "Mode: $mode"
	echo "Driver: $driver"
	echo "Channel: $channel"
	echo "Country: $country"	
	echo "Name: $name"
	echo "------------------------"

	template="$TEMPLATE_BASE.$driver.$mode"

	[ ! -f "$template" ] && qmp_error "Template $template not found"

	cat $template | sed -e s/"#QMP_DEVICE"/"$device"/ \
	 -e s/"#QMP_TYPE"/"$driver"/ \
	 -e s/"#QMP_MAC"/"$mac"/ \
	 -e s/"#QMP_CHANNEL"/"$channel"/ \
	 -e s/"#QMP_COUNTRY"/"$country"/ \
	 -e s/"#QMP_SSID"/"$name"/ \
	 -e s/"#QMP_BSSID"/"$bssid"/ \
	 -e s/"#QMP_MODE"/"$mode"/ >> $OWRT_WIRELESS_CONFIG 
}

qmp_configure_wifi() {
#This function search for all wifi devices and leave them configured according qmp config file

	echo "Backuping wireless config file to: $OWRT_WIRELESS_CONFIG.qmp_backup"
	cp $OWRT_WIRELESS_CONFIG $OWRT_WIRELESS_CONFIG.qmp_backup
	echo "" > $OWRT_WIRELESS_CONFIG

	devices="$(qmp_get_wifi_devices)"
	macs="$(qmp_get_wifi_mac_devices)"
	i=1
	for d in $devices; do 
		m=$(echo $macs | cut -d' ' -f$i)
		j=0
		while [ ! -z "$(qmp_uci_get @wireless[$j])" ]; do
			configured_mac="$(qmp_uci_get @wireless[$j].mac | tr [A-Z] [a-z])"
			[ "$configured_mac" == "$m" ] && { qmp_configure_wifi_device $j $d ; break; }
			j=$(( $j + 1 ))
		done
		i=$(( $i + 1 ))
	done
	echo "Configuring driver..."
	qmp_configure_wifi_driver
	echo "Done. All devices configured according qmp configuration"
}

qmp_wifi_get_default() {
	[ ! -f "$WIFI_DEFAULT_CONFIG" ] && qmp_error "Template not found $WIFI_DEFAULT_CONFIG"
	cat $WIFI_DEFAULT_CONFIG | grep $1 | cut -d' ' -f2
}

qmp_configure_wifi_initial() {

	macs="$(qmp_get_wifi_mac_devices)"

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
				id_configured="$id_configured $j" 
				echo "Found configured device: $m"
				[ -z "$(qmp_uci_get @wireless[$j].channel)" ] && qmp_uci_set @wireless[$j].channel $(qmp_wifi_get_default channel)
	        	[ -z "$(qmp_uci_get @wireless[$j].mode)" ] && qmp_uci_set @wireless[$j].mode $(qmp_wifi_get_default mode)
        		[ -z "$(qmp_uci_get @wireless[$j].name)" ] && qmp_uci_set @wireless[$j].name $(qmp_wifi_get_default name)
				break
			fi
			j=$(( $j + 1 ))
		done
		
		[ $found -eq 0 ] && to_configure="$to_configure $m"
	done

	#Configuring devices not found before
	for m in $to_configure; do
		echo "Configuring device $m"
		#Looking for a free slot to put new configuration
		j=0
		while [ ! -z "$(echo $id_configured | grep $j)" ]; do j=$(( $j +1 )); done
		#Now we have a free slot, let's go to configure device
		[ -z "$(qmp_uci_get @wireless[$j])" ] && qmp_uci_add wireless
		[ -z "$(qmp_uci_get @wireless[$j].channel)" ] && qmp_uci_set @wireless[$j].channel $(qmp_wifi_get_default channel)
		[ -z "$(qmp_uci_get @wireless[$j].mode)" ] && qmp_uci_set @wireless[$j].mode $(qmp_wifi_get_default mode)
		[ -z "$(qmp_uci_get @wireless[$j].name)" ] && qmp_uci_set @wireless[$j].name $(qmp_wifi_get_default name)
		qmp_uci_set @wireless[$j].mac $m
		id_configured="$id_configured $j"
	done

	#Finally we are going to configure default parameters if they are not present
	[ -z "$(qmp_uci_get wireless)" ] && qmp_uci_set wireless qmp
	[ -z "$(qmp_uci_get wireless.driver)" ] && qmp_uci_set wireless.driver $(qmp_wifi_get_default driver)
	[ -z "$(qmp_uci_get wireless.country)" ] && qmp_uci_set wireless.country $(qmp_wifi_get_default country)
	[ -z "$(qmp_uci_get wireless.bssid)" ] && qmp_uci_set wireless.bssid $(qmp_wifi_get_default bssid)

}                        