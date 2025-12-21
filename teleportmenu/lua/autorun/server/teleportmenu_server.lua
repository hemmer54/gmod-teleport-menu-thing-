if not SERVER then return end

-- send shared script to clients
AddCSLuaFile("teleportmenu_shared.lua")

---@module "lua/teleportmenu_shared"
local shared = include "teleportmenu_shared.lua"

-- Table containing last teleport timestamp for each player for debouncing/cooldowns
---@type table<number, number>
local debounce = {}

local netS = shared.netS
local checkRank = shared.checkRank
util.AddNetworkString(netS)

local logstrings = {
	goto         = "%s teleported to %s.",
	bring        = "%s teleported %s to themself.",
	teleport     = "%s teleported %s to %s.",
	invalidrank  = "%s tried to use command '%s' with insufficient permissions!",
	invalidplr   = "%s tried to use command '%s' with invalid targets!"
}

---@param str string
---@param ... any
local function log(str, ...)
	return MsgN("[teleportmenu] ", (logstrings[str] or str):format(...))
end

local sv_cvar = shared.replicatedSvConVars()
sv_cvar.log_teleports = CreateConVar("sv_teleportmenu_log_teleports", "1", {FCVAR_ARCHIVE, FCVAR_PROTECTED}, "Print to server log when anyone uses a Teleport Menu command successfully. Doesn't affect error logging.", 0, 1)

---@param plr Player
---@param str ChatStrings|string
---@param alert boolean? Sound alert
---@param arg1 number?
---@param arg2 number?
local function sendMessage(plr, str, alert, arg1, arg2)
	if not plr or plr == NULL then
		error("Player expected for sendMessage()!")
	else
		net.Start(netS)
		net.WriteString(str)
		net.WriteBit(alert and true or false)
		net.WriteUInt(arg1 and arg1+1 or 0, 32)
		net.WriteUInt(arg2 and arg2+1 or 0, 32)
		net.Send(plr)
	end
end

---@param ent Entity
---@param pos Vector
local function checkIfValidPos(ent, pos)
	local tr = util.TraceEntity({start=pos, endpos=pos, mask=MASK_PLAYERSOLID, collisiongroup=COLLISION_GROUP_PLAYER, filter={ent}}, ent)

	if tr.HitWorld or (tr.Entity ~= NULL) then
		return false
	end

	return true
end

-- Offsets to check for. Is multiplied by target collision box
local checks = {
	-- check cardinal directions first and again with a 0.2 vertical offset
	Vector(2,0,0), Vector(2,0,0.2),
	Vector(-2,0,0), Vector(-2,0,0.2),
	Vector(0,2,0), Vector(0,2,0.2),
	Vector(0,-2,0), Vector(0,-2,0.2),
	-- check directly above
	Vector(0,0,2)
}

---@param caller Player
---@param plr Player
---@param target Player
---@param cmd string
local function teleport(caller, plr, target, cmd)
	local function getTargetPos(ignoreBlocker)
		local targetPos = target:GetPos()
		local cbMin, cbMax = target:GetCollisionBounds()
		local width, height = cbMax.x*1.1, cbMax.z -- slightly larger horizontal offset prevents the collision check from hitting the target itself
		local sizeVector = Vector(width, width, height)

		for _, checkVectorMod in ipairs(checks) do
			local newPos = targetPos + sizeVector * checkVectorMod

			if ignoreBlocker or checkIfValidPos(plr, newPos) then
				return newPos
			end
		end

		-- couldn't find valid position
		return false
	end

	local noclip = (not plr:GetPhysicsObject():IsCollisionEnabled() and not plr:InVehicle()) and true or false
	local newPos = getTargetPos() or (noclip and getTargetPos(true))

	if not newPos then
		sendMessage(caller, cmd.."_noSpace", true, plr:UserID(), target:UserID())
		return
	end

	plr:ExitVehicle()
	plr:SetPos(newPos)

	-- Notify players & log to console
	local callerUid = caller ~= NULL and caller:UserID() or 0
	local notifyTargets = sv_cvar.notify_targets:GetInt() > 0
	local logTps = sv_cvar.log_teleports:GetInt() > 0
	if cmd == "goto" then
		sendMessage(caller, "goto_caller", false, nil, target:UserID())
		if notifyTargets then
			sendMessage(target, "goto_target", false, callerUid, nil)
		end
		if logTps then
			log("goto", caller:Name(), target:Name())
		end

	elseif cmd == "bring" then
		sendMessage(caller, "bring_caller", false, plr:UserID(), nil)
		if notifyTargets then
			sendMessage(plr, "bring_plr", false, callerUid, nil)
		end
		if logTps then
			log("bring", caller:Name(), target:Name())
		end

	elseif cmd == "teleport" then
		sendMessage(caller, "teleport_caller", false, plr:UserID(), target:UserID())
		if notifyTargets then
			sendMessage(plr, "teleport_plr", false, plr:UserID(), target:UserID())
			sendMessage(target, "teleport_target", false, plr:UserID(), target:UserID())
		end
		if logTps then
			log("teleport", caller:Name(), plr:Name(), target:Name())
		end

	end

	return true
end

net.Receive(netS, function(length, caller)
	local plrUid = net.ReadUInt(32)
	local targetUid = net.ReadUInt(32)
	local cmdI = net.ReadUInt(2)

	local ts_now = os.clock()
	local ts_last = debounce[caller:UserID()] or 0

	if ts_now < ts_last+sv_cvar.cooldown:GetFloat() then
		if sv_cvar.cooldown_ignore_admins:GetInt() == 0 or checkRank(caller, 1) ~= true then
			sendMessage(caller, "cooldown", true)
			return
		end
	end

	local cmd = (
		cmdI == 1 and "bring" or
		cmdI == 2 and "teleport" or
		"goto")

	if cmd == "goto" then
		plrUid = caller:UserID()
	elseif cmd == "bring" then
		targetUid = caller:UserID()
	end

	local canUse = checkRank(caller, sv_cvar[cmd.."_rank"]:GetInt())
	if canUse ~= true then
		return log("invalidrank", caller:Name(), cmd)
	end

	if not GAMEMODE.IsSandboxDerived and sv_cvar.allow_in_non_sandbox:GetInt() == 0 then
		return
	end

	local plr, target = Player(plrUid), Player(targetUid)
	if plr == NULL or target == NULL then
		return log("invalidplr", caller:Name(), cmd)
	end

	if teleport(caller, plr, target, cmd) then
		-- Update debounce timestamp
		debounce[caller:UserID()] = ts_now
	end
end)
