if not CLIENT then return end

---@module "lua/teleportmenu_shared"
local shared = include "teleportmenu_shared.lua"

local netS = shared.netS
local checkRank = shared.checkRank

---@enum (key) ChatStrings
local strings = {
	goto_noSpace     = "No space around $2 to place you! Use noclip to bypass this check.",
	goto_caller      = "Teleported to $2!",
	goto_target      = "$1 teleported to you!",

	bring_noSpace    = "No space around you to place $1! Try again at a more open area.",
	bring_caller     = "Teleported $1 to you!",
	bring_plr        = "$1 teleported you to themself!",

	teleport_noSpace = "No space around $2 to place $1! Try again when the target is at a more open area.",
	teleport_caller  = "Teleported $1 to $2!",
	teleport_plr     = "You were teleported to $2!",
	teleport_target  = "$1 was teleported to you!",

	notFound         = "No matches found for [$1]!",
	multipleFound    = "Multiple matches found for [$1]!",

	cmdGotoUsage     = "Usage: goto <name>",
	cmdBringUsage    = "Usage: bring <name>",
	cmdTeleportUsage = "Usage: teleport <name> <name>",

	sboxOnly         = "Teleport Menu commands can only be used in Sandbox-derived gamemodes on this server!",
	adminOnly        = "You must be an admin to use this!",
	superadminOnly   = "You must be a superadmin to use this!",
	noPlayers        = "You're the only one here!",
	cooldown         = "Cooling down!"
}

---@param str string
---@param replace string
---@param with any
local function replaceInStr(str, replace, with)
	return str:gsub("("..replace..")", tostring(with))
end

---@param str ChatStrings|any
---@param alert boolean?
local function message(str, alert, arg1, arg2)
	str = strings[str] or tostring(str)

	str = replaceInStr(str, "$1", arg1)
	str = replaceInStr(str, "$2", arg2)

	LocalPlayer():PrintMessage(HUD_PRINTTALK, str)

	if alert then
		surface.PlaySound("friends/message.wav")
	end
end

-- Receive response message from server
net.Receive(netS, function(length)
	local str = net.ReadString()
	local alert = net.ReadBit() == 1 and true or false
	local rawarg1 = net.ReadUInt(32)-1
	local rawarg2 = net.ReadUInt(32)-1

	local arg1 = Player(rawarg1) ~= NULL and Player(rawarg1):Name()
	local arg2 = Player(rawarg2) ~= NULL and Player(rawarg2):Name()

	message(str, alert, arg1, arg2)
end)

local sv_cvar = shared.replicatedSvConVars()
local cl_cvar = {
	cmenuicon = CreateClientConVar("cl_teleportmenu_cmenuicon", "1", true, false, "Should icons for goto & bring be added to the context menu in sandbox? Requires reload/reconnect.\nNOTE: The icon is not created on singleplayer!", 0, 1),
	recentlimit = CreateClientConVar("cl_teleportmenu_recentlimit", "5", true, false, "How many recent entries to keep in dropdown? 0 to disable.", 0, 128)
}

---@param s string|number
---@return Player? found, boolean? multiple
local function getPlayerByNameOrUid(s)
	if type(s) == "number" then
		local plr = Player(s)
		return plr ~= NULL and plr or nil
	end

	s = s:lower()
	local found
	for _, plr in ipairs(player.GetAll()) do
		local name = plr:Name():lower()
		if s == name then
			-- direct match
			return plr
		end

		if name:find(s, 1, true) then
			-- partial match; continue searching for another match
			if not found then
				found = plr
			else
				return found, true
			end
		end
	end

	return found
end

---@param cmd string
---@param args string[]
local function tpCmd(_, cmd, args)
	if not GAMEMODE.IsSandboxDerived and sv_cvar.allow_in_non_sandbox:GetInt() == 0 then
		return message("sboxOnly")
	end

	local caller = LocalPlayer()

	if not args[1] then return end
	local arg1, arg1_multi = getPlayerByNameOrUid(args[1])
	if not arg1 then
		return message("notFound", true, args[1])
	elseif arg1_multi then
		return message("multipleFound", true, args[1])
	end

	local plr, target

	cmd = cmd:lower():gsub("(teleportmenu_)", "", 1)

	local canUse = checkRank(caller,
							(cmd == "goto" and sv_cvar.goto_rank or
								cmd == "bring" and sv_cvar.bring_rank or
								cmd == "teleport" and sv_cvar.teleport_rank):GetInt())
	if canUse ~= true then
		return message(canUse, true)
	end

	if cmd == "goto" then
		plr, target = caller, arg1
	elseif cmd == "bring" then
		plr, target = arg1, caller
	elseif cmd == "teleport" then
		if not args[2] then return end

		local arg2, arg2_multi = getPlayerByNameOrUid(args[2])
		if not arg2 then
			message("notFound", true, args[2])
			return
		elseif arg2_multi then
			message("multipleFound", true, args[2])
			return
		end

		plr, target = arg1, arg2
	end

	-- send request to server
	net.Start(netS)
	net.WriteUInt(plr:UserID(), 32)
	net.WriteUInt(target:UserID(), 32)
	net.WriteUInt((
		cmd == "goto" and 0 or
		cmd == "bring" and 1 or
		cmd == "teleport" and 2 or
		3 -- fallback, this should never be picked normally.
	), 2)
	net.SendToServer()
end

-- Console commands
concommand.Add("teleportmenu_goto", tpCmd, nil, "Teleport to another player's location.")
concommand.Add("teleportmenu_bring", tpCmd, nil, "Teleport another player to your location.")
concommand.Add("teleportmenu_teleport", tpCmd, nil, "Teleport a player to another player's location.")

-- Chat commands
hook.Add("OnPlayerChat", "teleportmenu_chatcmds", function(plr, str)
	if sv_cvar.chatcmdsenabled:GetInt() == 0 then return end
	if plr ~= LocalPlayer() then return end

	local pfx = sv_cvar.chatcmdsprefix:GetString()
	if #pfx == 0 or str:sub(1, #pfx) == pfx then
		str = str:lower()
		if str:find("^"..pfx.."goto") then
			local _, _, targetName = str:find("^"..pfx.."goto (%S+)")
			if targetName then
				tpCmd(nil, "goto", {targetName})
			else
				message("cmdGotoUsage")
			end
		elseif str:find("^"..pfx.."bring") then
			local _, _, targetName = str:find("^"..pfx.."bring (%S+)")
			if targetName then
				tpCmd(nil, "bring", {targetName})
			else
				message("cmdBringUsage")
			end
		elseif str:find("^"..pfx.."teleport") then
			local _, _, plrName, targetName = str:find("^"..pfx.."teleport (%S+) (%S+)")
			if plrName and targetName then
				tpCmd(nil, "teleport", {plrName, targetName})
			else
				message("cmdTeleportUsage")
			end
		end
	end
end)

-- Context menu icon
if cl_cvar.cmenuicon:GetInt() > 0 and game.MaxPlayers() > 1 then
	local recentList = {goto = {}, bring = {}}

	---@param t any[]
	local function findInList(t, uid)
		for i = 1, #t do
			if t[i] == uid then
				return i
			end
		end
		return nil
	end

	---@param cmd "goto"|"bring"
	---@param menu DMenu
	---@param callback function
	local function addPlayersToMenu(cmd, menu, callback)
		local recent = recentList[cmd]

		local localplr = LocalPlayer()
		local cr = checkRank(localplr, sv_cvar[cmd.."_rank"]:GetInt())
		if cr ~= true then
			local opt = menu:AddOption(strings[cr])
			opt:SetEnabled(false)
			return
		end

		local plrs = player.GetAll()
		if #plrs <= 1 then
			local opt = menu:AddOption(strings.noPlayers)
			opt:SetEnabled(false)
			return
		end

		local recentLimit = cl_cvar.recentlimit:GetInt()

		if #recent > recentLimit then
			-- remove recent entries over the limit
			for i = recentLimit+1, #recent do
				recent[i] = nil
			end
		end

		---@param plr Player
		---@param callback2 function
		local function addPlayer(plr, callback2)
			local name, uid = plr:Name(), plr:UserID()
			local opt = menu:AddOption(name, callback2)
			local avatar = vgui.Create("AvatarImage", opt)
			avatar:SetSize(16, 16)
			avatar:SetPos(3, 3)
			avatar:SetPlayer(plr, 32)
			avatar:SetMouseInputEnabled(false)
			opt:SetTooltip(("[%s|%s|%s]"):format(name, uid, plr:SteamID()))
		end

		if #recent > 0 then
			for i = 1, #recent do
				local plr = Player(recent[i])
				if IsValid(plr) then
					local uid = plr:UserID()
					addPlayer(plr, function()
						table.remove(recent, i)
						table.insert(recent, 1, uid)
						callback(uid)
					end)
				end
			end

			menu:AddSpacer()
		end

		for _, plr in ipairs(plrs) do
			local uid = plr:UserID()
			if plr ~= localplr and not findInList(recent, uid) then
				addPlayer(plr, function()
					table.insert(recent, 1, uid)
					callback(uid)
				end)
			end
		end
	end

	list.Set("DesktopWindows", "playertp_goto", {
		title = "Go to player...",
		icon = "icon64/teleportmenu_goto.png",
		init = function()
			local menu = vgui.Create("DMenu")
			addPlayersToMenu("goto", menu, function(id)
				tpCmd(nil, "goto", {id})
				surface.PlaySound("garrysmod/ui_click.wav")
			end)

			local x, y = input.GetCursorPos()
			menu:Open(x, y, nil, g_ContextMenu)

			surface.PlaySound("garrysmod/ui_return.wav")
		end
	})

	list.Set("DesktopWindows", "playertp_bring", {
		title = "Bring player...",
		icon = "icon64/teleportmenu_bring.png",
		init = function()
			local menu = vgui.Create("DMenu")
			addPlayersToMenu("bring", menu, function(id)
				tpCmd(nil, "bring", {id})
				surface.PlaySound("garrysmod/ui_click.wav")
			end)

			local x, y = input.GetCursorPos()
			menu:Open(x, y, nil, g_ContextMenu)

			surface.PlaySound("garrysmod/ui_return.wav")
		end
	})
end

-- Settings panel
---@param panel DForm
local function cmenuUtilityMenu(panel)
	panel:Help("Clientside context menu options for Teleport Menu.")
	panel:Help("Client CVars are prefixed with \"cl_teleportmenu_\"!\nConCommands are prefixed with \"teleportmenu_\"!")

	panel:CheckBox("Show context menu icon", "cl_teleportmenu_cmenuicon")
	panel:ControlHelp(cl_cvar.cmenuicon:GetHelpText())

	panel:NumSlider("Maximum recents", "cl_teleportmenu_recentlimit", 0, 128, 0)
	panel:ControlHelp(cl_cvar.recentlimit:GetHelpText())
end

---@param panel DForm
local function serverUtilityMenu(panel)
	local isHost = LocalPlayer():IsListenServerHost()

	panel:Help("Server settings for Teleport Menu. Can only be changed by the host.")
	panel:Help("Server CVars are prefixed with \"sv_teleportmenu_\"!")

	panel:Help("\nPermissions required for commands:")
	local function add_rank_combobox(name, cvar_name)
		local label = vgui.Create("DLabel")
		label:SetText(name)
		label:SetDark(true)

		local combobox = vgui.Create("DComboBox")
		combobox:SetSortItems(false)
		combobox:SetEnabled(isHost)
		combobox:Dock(FILL)
		combobox:AddChoice("Everyone", "0")
		combobox:AddChoice("Admins only", "1")
		combobox:AddChoice("Superadmins only", "2")
		local cvar = GetConVar(cvar_name)
		combobox:ChooseOptionID(math.Clamp(cvar:GetInt()+1, 1, 3))
		function combobox:OnSelect(i, v, d)
			RunConsoleCommand(cvar_name, d)
		end

		panel:AddItem(label, combobox)

	end
	add_rank_combobox("Go to", "sv_teleportmenu_goto_rank")
	add_rank_combobox("Bring", "sv_teleportmenu_bring_rank")
	add_rank_combobox("Teleport", "sv_teleportmenu_teleport_rank")

	panel:NumSlider("Cooldown", "sv_teleportmenu_cooldown", 0, 30, 2):SetEnabled(isHost)
	panel:ControlHelp(sv_cvar.cooldown:GetHelpText())

	panel:CheckBox("Admins ignore cooldowns", "sv_teleportmenu_cooldown_ignore_admins"):SetEnabled(isHost)
	panel:ControlHelp(sv_cvar.cooldown_ignore_admins:GetHelpText())

	panel:CheckBox("Allow in non-sandbox gamemodes", "sv_teleportmenu_allow_in_non_sandbox"):SetEnabled(isHost)
	panel:ControlHelp(sv_cvar.allow_in_non_sandbox:GetHelpText())

	panel:CheckBox("Notify teleport targets", "sv_teleportmenu_notify_targets"):SetEnabled(isHost)
	panel:ControlHelp(sv_cvar.notify_targets:GetHelpText())

	panel:CheckBox("Enable chat commands", "sv_teleportmenu_chatcmdsenabled"):SetEnabled(isHost)
	panel:ControlHelp(sv_cvar.chatcmdsenabled:GetHelpText())

	panel:TextEntry("Command prefix", "sv_teleportmenu_chatcmdsprefix"):SetEnabled(isHost)
	panel:ControlHelp(sv_cvar.chatcmdsprefix:GetHelpText())

	panel:Help("Chat commands:\n  goto <name> - Teleport to player\n  bring <name> - Teleport player to you\n  teleport <name> <name> - Teleport first player to the second.")
end

hook.Add("PopulateToolMenu", "teleportmenu_options_menus", function()
	spawnmenu.AddToolMenuOption("Utilities", "teleportmenu", "cmenu", "Context Menu Icon", "", "", cmenuUtilityMenu)
	spawnmenu.AddToolMenuOption("Utilities", "teleportmenu", "server", "Server", "", "", serverUtilityMenu)
end)

hook.Add("AddToolMenuCategories", "teleportmenu_options_categories", function()
	spawnmenu.AddToolCategory("Utilities", "teleportmenu", "Teleport Menu")
end)
