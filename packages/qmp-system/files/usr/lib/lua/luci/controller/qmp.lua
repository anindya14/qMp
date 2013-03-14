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

module("luci.controller.qmp", package.seeall)

function index()

	-- Making qmp as default
	local root = node()
	root.target = alias("qmp")
	root.index  = true

	-- Main window with auth enabled
	overview = entry({"qmp"}, template("admin_status/index"), "qMp", 1)
	overview.dependent = false
	overview.sysauth = "root"
	overview.sysauth_authenticator = "htmlauth"

	-- Rest of entries
	entry({"qmp","status"}, template("admin_status/index"), "Status", 2).dependent=false

	entry({"qmp","configuration"}, cbi("qmp/wizard"), "Configuration", 4).dependent=false
	entry({"qmp","configuration","wizard"}, cbi("qmp/wizard"), "Wizard", 1).dependent=false
	entry({"qmp","configuration","network"}, cbi("qmp/network"), "Network", 2).dependent=false
	entry({"qmp","configuration","network","advanced"}, cbi("qmp/network_adv"), "Advanced networking", 1).dependent=false
	entry({"qmp","configuration","wifi"}, cbi("qmp/wireless"), "WiFi", 3).dependent=false
	entry({"qmp","configuration","node"}, cbi("qmp/node"), "Node", 4).dependent=false

	entry({"qmp","tools"}, call("action_tools"), "Tools", 5).dependent=false
	entry({"qmp","tools","tools"}, call("action_tools"), "Tools", 1).dependent=false           
	entry({"qmp","tools","splash"}, call("action_splash"), "Splash", 2).dependent=false
	entry({"qmp","tools","map"}, call("action_map"), "Map", 3).dependent=false

	entry({"qmp","about"}, call("action_status"), "About", 9).dependent=false
end

function action_status()
	package.path = package.path .. ";/etc/qmp/?.lua"
	local qmp = require "qmpinfo"
	local ipv4 = qmp.get_ipv4()
	local hostname = qmp.get_hostname()
	local uname = qmp.get_uname()
	local version = qmp.get_version() 

	luci.template.render("qmp/overview",{ipv4=ipv4,hostname=hostname,uname=uname,version=version})
end

function action_tools()
	package.path = package.path .. ";/etc/qmp/?.lua"
	local qmp = require "qmpinfo"
	local nodes = qmp.nodes()
	local key = qmp.get_key()
	luci.template.render("qmp/tools",{nodes=nodes,key=key})
end

function action_splash()
	luci.template.render("qmp/splash")
end

function action_map()
	luci.template.render("qmp/b6m")
end
