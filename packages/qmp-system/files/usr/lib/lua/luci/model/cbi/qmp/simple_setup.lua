--[[
    Copyright (C) 2011 Fundacio Privada per a la Xarxa Oberta, Lliure i Neutral guifi.net

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program; if not, write to the Free Software Foundation, Inc.,
    51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

    The full GNU General Public License is included in this distribution in
    the file called "COPYING".
--]]

local sys = require "luci.sys"
local http = require "luci.http"
local ip = require "luci.ip"
local util = require "luci.util"
local uci  = require "luci.model.uci"
local uciout = uci.cursor()

package.path = package.path .. ";/etc/qmp/?.lua"
qmpinfo = require "qmpinfo"

m = SimpleForm("qmp_tmp", translate("qMp simple setup"))

local roaming_help
roaming_help = m:field(DummyValue,"roaming_help")
roaming_help:depends("_netmode","roaming")
roaming_help.rawhtml = true
roaming_help.default = "This page provides a simple way to configure the basic settings of a qMp node.<br/> <br/>Roaming mode is used for quick, temporal deployments. \
User devices connected to the network can roam between\ Access Points without loosing connectivity. However, they can not see other user devices connected to the Mesh.<br/> <br/>"
local community_help
community_help = m:field(DummyValue,"community_help")
community_help:depends("_netmode","community")
community_help.rawhtml = true

community_help.default = "This page provides a simple way to configure the basic settings of a qMp node.<br/> <br/>Community mode is used for static, long-term deployments \
(such as community networks). User devices connected to the network get an IP address from a specific range and are accessible from the rest of the Mesh. \
However, roaming between stations is not possible.<br/> <br/>"

netmode = m:field(ListValue, "_netmode",translate("Network mode"),translate("Choose \"community\" mode for community networks and long-term deployments.<br/>\"Roaming\" mode \
is best for quick, temporal network setups."))
netmode:value("community","community")
netmode:value("roaming","roaming")

local networkmode
if uciout:get("qmp","roaming","ignore") == "1" then
	local ipv4 = uciout:get("qmp","networks","bmx6_ipv4_address")
	local ipv4mask = string.find(ipv4,"/")
	if ipv4mask ~= nil then
		ipv4 = string.sub(ipv4,1,ipv4mask-1)
	end
	if ipv4 == uciout:get("qmp","networks","lan_address") then
		networkmode="community"
	end
else
	networkmode="roaming"
end
netmode.default=networkmode

nodeip_roaming =  m:field(Value, "_nodeip_roaming", translate("IP address"),
translate("Main IPv4 address for this node. This IP must be unique in the Mesh network. <br/>Leave it blank to get a random one."))
nodeip_roaming:depends("_netmode","roaming")

local rip = uciout:get("qmp","networks","bmx6_ipv4_address")
if rip == nil or #rip < 7 then
	rip = uciout:get("bmx6","general","tun4Address")
	if rip == nil or #rip < 7 then 
		rip = ""
	end
end 

nodeip_roaming.default=rip

nodename = m:field(Value, "_nodename", translate("Node name"),
translate("The name of this node. Four hex numbers will be appended, according the the device's MAC address."))

nodename:depends("_netmode","community")
nodename.default="qMp"
if uciout:get("qmp","node","community_id") ~= nil then
	nodename.default=uciout:get("qmp","node","community_id")
end

nodeip = m:field(Value, "_nodeip", translate("IP address"),
translate("Main IPv4 address for this node. This IP must be unique in the Mesh network. It will be used in the LAN for end users."))

nodeip:depends("_netmode","community")
nodeip.default = "10.30."..util.trim(util.exec("echo $((($(date +%M)*$(date +%S)%254)+1))"))..".1"

nodemask = m:field(Value, "_nodemask",translate("Network mask"),
translate("Network mask to be used with the IPv4 address above. This mask will be used in the LAN for end users."))
nodemask:depends("_netmode","community")
nodemask.default = "255.255.255.0"

if networkmode == "community" then
	nodeip.default=uciout:get("qmp","networks","lan_address")
	nodemask.default=uciout:get("qmp","networks","lan_netmask")
end

-- Get list of devices {{ethernet}{wireless}}
devices = qmpinfo.get_devices()

-- Ethernet devices
nodedevs_eth = {}

local function is_a(dev, what)
	local x
	for x in util.imatch(uciout:get("qmp", "interfaces", what)) do
        	if dev == x then
        		return true
        	end
        end
	return false
end

for i,v in ipairs(devices.eth) do
        tmp = m:field(ListValue, "_" .. v, v)
	tmp:value("Mesh")
	tmp:value("Lan")
	tmp:value("Wan")

	if is_a(v, "lan_devices") then
		tmp.default = "Lan"
	elseif is_a(v, "wan_devices") then
		tmp.default = "Wan"
	elseif is_a(v, "mesh_devices") then
		tmp.default = "Mesh"
	end

	nodedevs_eth[i] = {v,tmp}
end

-- Wireless devices
nodedevs_wifi = {}

for i,v in ipairs(devices.wifi) do
	tmp = m:field(ListValue, "_" .. v, v)
	tmp:value("Mesh")
	tmp:value("AP")
	tmp.default = ""

	if is_a(v,"lan_devices") then
		-- If the device is in lan_devices, it is AP mode
		tmp.default = "AP"
	else
		-- Check if the device is adhoc_ap mode, then Mode=AP MeshAll=1
		uciout:foreach("qmp","wireless", function (s)
			if s.device == v then
				if s.mode == "adhoc_ap" then
					tmp.default = "AP"
				end
			end

		end)

		-- If it is not adhoc_ap it is only mesh
		if tmp.default == "" then tmp.default = "Mesh" end
	end

	nodedevs_wifi[i] = {v,tmp}
end

meshall = m:field(Flag, "_meshall", translate("Use mesh in all devices"),translate("If this option is enabled, all the node's network devices will be used for meshing (recommended)"))
meshall.default = "1"

function netmode.write(self, section, value)
	local name = nodename:formvalue(section)
	local mode = netmode:formvalue(section)
	local nodeip = nodeip:formvalue(section)
	local nodemask = nodemask:formvalue(section)
	local nodeip_roaming = nodeip_roaming:formvalue(section)
	
	if mode == "community" then
		uciout:set("qmp","roaming","ignore","1")
		uciout:set("qmp","networks","publish_lan","1")
		uciout:set("qmp","networks","lan_address",nodeip)
		uciout:set("qmp","networks","bmx6_ipv4_address",ip.IPv4(nodeip,nodemask):string())
		uciout:set("qmp","networks","lan_netmask",nodemask)
		uciout:set("qmp","node","community_id",name)

	else
		uciout:set("qmp","roaming","ignore","0")
		uciout:set("qmp","networks","publish_lan","0")
		uciout:set("qmp","networks","lan_address","172.30.22.1")
		uciout:set("qmp","networks","lan_netmask","255.255.0.0")
		uciout:set("qmp","networks","bmx6_ipv4_prefix24","10.202.0")
		uciout:set("qmp","networks","olsr6_ipv4_address","")
		uciout:set("qmp","networks","olsr6_ipv4_prefix24","10.201")
		if nodeip_roaming == nil then
			uciout:set("qmp","networks","bmx6_ipv4_address","")
		else
			uciout:set("qmp","networks","bmx6_ipv4_address",nodeip_roaming)
		end

	end

	local i,v,devmode,devname
	local lan_devices = ""
	local wan_devices = ""
	local mesh_devices = ""
	local meshall = meshall:formvalue(section)

	for i,v in ipairs(nodedevs_eth) do
		devmode = v[2]:formvalue(section)
		devname = v[1]

		if devmode == "Lan" then
			lan_devices = lan_devices..devname.." "
		elseif devmode == "Wan" then
			wan_devices = wan_devices..devname.." "
		end
		if devmode == "Mesh" or meshall == "1" then
			mesh_devices = mesh_devices..devname.." "
		end
	end

	for i,v in ipairs(nodedevs_wifi) do
		devmode = v[2]:formvalue(section)
		devname = v[1]

		if (devmode == "AP" and meshall == "1") or devmode == "Mesh" then
			mesh_devices = mesh_devices..devname.." "
		elseif devmode == "AP" and meshall ~= "1" then
			lan_devices = lan_devices..devname.." "
		end

		function setmode(s)
			if s.device == devname then
				if devmode == "AP" and meshall == "1" then 
					uciout:set("qmp",s['.name'],"mode","adhoc_ap")
				elseif devmode == "AP" then
					uciout:set("qmp",s['.name'],"mode","ap")
				else
					uciout:set("qmp",s['.name'],"mode","adhoc") end
			end
		end
		uciout:foreach("qmp","wireless",setmode)
	end

	uciout:set("qmp","interfaces","lan_devices",lan_devices)
	uciout:set("qmp","interfaces","wan_devices",wan_devices)
	uciout:set("qmp","interfaces","mesh_devices",mesh_devices)

	uciout:commit("qmp")
	apply()
end

function apply(self)
	http.redirect("/luci-static/resources/qmp/wait_long.html")
        luci.sys.call('(qmpcontrol configure_wifi ; qmpcontrol configure_network) &')
end


return m
