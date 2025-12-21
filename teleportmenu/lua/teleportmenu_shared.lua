return {
	netS = "teleportmenu_data",
	replicatedSvConVars = function()
		return {
			goto_rank = CreateConVar("sv_teleportmenu_goto_rank", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Restrict usage of 'goto' command.\n0 = no restriction\n1 = admin\n2 = superadmin", 0, 2),
			bring_rank = CreateConVar("sv_teleportmenu_bring_rank", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Restrict usage of 'teleportmenu_bring' command.\n0 = no restriction\n1 = admin\n2 = superadmin", 0, 2),
			teleport_rank = CreateConVar("sv_teleportmenu_teleport_rank", "2", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Restrict usage of 'teleportmenu_teleport' command.\n0 = no restriction\n1 = admin\n2 = superadmin", 0, 2),
			allow_in_non_sandbox = CreateConVar("sv_teleportmenu_allow_in_non_sandbox", "0", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Allow usage of Teleport Menu commands in non-sandbox derived gamemodes.", 0, 1),
			notify_targets = CreateConVar("sv_teleportmenu_notify_targets", "1", {FCVAR_ARCHIVE}, "Notify teleport targets when they are teleported or when someone teleports to their location.", 0, 1),
			chatcmdsenabled = CreateConVar("sv_teleportmenu_chatcmdsenabled", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Enable chat commands?", 0, 1),
			chatcmdsprefix = CreateConVar("sv_teleportmenu_chatcmdsprefix", "/", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Prefix for chat commands. Default: '/'"),
			cooldown = CreateConVar("sv_teleportmenu_cooldown", "0.75", {FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY}, "Cooldown for successful teleports in seconds. 0 to disable."),
			cooldown_ignore_admins = CreateConVar("sv_teleportmenu_cooldown_ignore_admins", "1", {FCVAR_ARCHIVE, FCVAR_REPLICATED}, "Should admins ignore the teleport cooldown?")
		}
	end,
	---@param plr Player
	---@param neededRank 0|1|2
	checkRank = function(plr, neededRank)
		if neededRank == 0 then
			return true
		elseif neededRank == 1 then
			return plr:IsAdmin() and true or "adminOnly"
		elseif neededRank == 2 then
			return plr:IsSuperAdmin() and true or "superadminOnly"
		end
	end
}
