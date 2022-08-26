#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <clientprefs>
#include <regex>
#include <convar_class>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <sendproxy>
#include <dhooks>

#undef REQUIRE_PLUGIN
#include <proptricks>

#pragma newdecls required
#pragma semicolon 1

#define SPAWN_POINTS 16

typedef StopTimerCallback = function void (int data);
Function gH_AfterWarningMenu[MAXPLAYERS+1];

int gI_Ammo = -1;

bool gB_Hide[MAXPLAYERS+1];

int gI_PropColor[MAXPLAYERS + 1][3];
bool gB_ChooseColor[MAXPLAYERS + 1] = {false, ...};

// Cookies
Handle gH_HideCookie = null;
Handle gH_PropColorCookie = null;

// Cvars
Convar gCV_RespawnOnTeam = null;
Convar gCV_RespawnOnRestart = null;
Convar gCV_StartOnSpawn = null;
Convar gCV_AutoRespawn = null;
Convar gCV_PlayerOpacity = null;
Convar gCV_DropAll = null;
Convar gCV_SpectatorList = null;
Convar gCV_StopTimerWarning = null;
Convar gCV_TriggerFlags = null;

// External cvars
ConVar mp_humanteam = null;

// Modules
bool gB_Replay = false;
bool gB_Zones = false;
bool gB_SendProxy = false;

// Timer settings
propstrings_t gS_PropStrings[PROP_LIMIT];

// Chat settings
chatstrings_t gS_ChatStrings;

// Late load
bool gB_Late = false;

#include "proptricks/misc/misc-dhooks.sp"

public Plugin myinfo =
{
	name = "[PropTricks] Miscellaneous",
	author = "Haze",
	description = "Miscellaneous features for proptricks timer.",
	version = PROPTRICKS_VERSION,
	url = ""
}

// Forwards
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// spectator list
	RegConsoleCmd("sm_specs", Command_Specs, "Show a list of spectators.");
	RegConsoleCmd("sm_spectators", Command_Specs, "Show a list of spectators.");

	// spec
	RegConsoleCmd("sm_spec", Command_Spec, "Moves you to the spectators' team. Usage: sm_spec [target]");
	RegConsoleCmd("sm_spectate", Command_Spec, "Moves you to the spectators' team. Usage: sm_spectate [target]");

	// hide
	RegConsoleCmd("sm_hide", Command_Hide, "Toggle players' hiding.");
	RegConsoleCmd("sm_unhide", Command_Hide, "Toggle players' hiding.");
	gH_HideCookie = RegClientCookie("proptricks_hide", "Hide settings", CookieAccess_Protected);

	// tpto
	RegConsoleCmd("sm_tpto", Command_Teleport, "Teleport to another player. Usage: sm_tpto [target]");
	RegConsoleCmd("sm_goto", Command_Teleport, "Teleport to another player. Usage: sm_goto [target]");

	// weapons
	RegConsoleCmd("sm_usp", Command_Weapon, "Spawn a USP.");
	RegConsoleCmd("sm_glock", Command_Weapon, "Spawn a Glock.");
	RegConsoleCmd("sm_knife", Command_Weapon, "Spawn a knife.");

	gI_Ammo = FindSendPropInfo("CCSPlayer", "m_iAmmo");

	// noclip
	RegConsoleCmd("sm_nc", Command_Noclip, "Toggles noclip. (sm_p alias)");
	RegConsoleCmd("sm_noclipme", Command_Noclip, "Toggles noclip. (sm_p alias)");

	// prop color
	RegConsoleCmd("sm_color", Command_Color, "");
	gH_PropColorCookie = RegClientCookie("proptricks_propcolor", "Prop Color settings", CookieAccess_Protected);

	RegConsoleCmd("sm_hookent", Command_Hookent, "");

	AddCommandListener(CommandListener_Noclip, "+noclip");
	AddCommandListener(CommandListener_Noclip, "-noclip");

	// hook teamjoins
	AddCommandListener(Command_Jointeam, "jointeam");
	AddCommandListener(Command_Spectate, "spectate");

	// hooks
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_team", Event_PlayerNotifications, EventHookMode_Pre);
	HookEvent("player_death", Event_PlayerNotifications, EventHookMode_Pre);
	HookEvent("weapon_fire", Event_WeaponFire);

	AddCommandListener(Command_Drop, "drop");
	AddCommandListener(Command_Say, "say"); 

	AddTempEntHook("EffectDispatch", EffectDispatch);
	AddTempEntHook("World Decal", WorldDecal);

	// phrases
	LoadTranslations("common.phrases");
	LoadTranslations("proptricks-common.phrases");
	LoadTranslations("proptricks-misc.phrases");
	
	MiscDhooks_Init();

	// cvars and stuff
	gCV_RespawnOnTeam = new Convar("proptricks_misc_respawnonteam", "1", "Respawn whenever a player joins a team?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_RespawnOnRestart = new Convar("proptricks_misc_respawnonrestart", "1", "Respawn a dead player if they use the timer restart command?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_StartOnSpawn = new Convar("proptricks_misc_startonspawn", "1", "Restart the timer for a player after they spawn?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_AutoRespawn = new Convar("proptricks_misc_autorespawn", "1.5", "Seconds to wait before respawning player?\n0 - Disabled", 0, true, 0.0, true, 10.0);
	gCV_PlayerOpacity = new Convar("shavit_misc_playeropacity", "-1", "Player opacity (alpha) to set on spawn.\n-1 - Disabled\nValue can go up to 255. 0 for invisibility.", 0, true, -1.0, true, 255.0);
	gCV_DropAll = new Convar("proptricks_misc_dropall", "1", "Allow all weapons to be dropped?\n0 - Disabled\n1 - Enabled", 0, true, 0.0, true, 1.0);
	gCV_SpectatorList = new Convar("proptricks_misc_speclist", "1", "Who to show in !specs?\n0 - everyone\n1 - all admins (admin_speclisthide override to bypass)\n2 - players you can target", 0, true, 0.0, true, 2.0);
	gCV_StopTimerWarning = new Convar("proptricks_misc_stoptimerwarning", "900", "Time in seconds to display a warning before stopping the timer with noclip or !stop.\n0 - Disabled");
	gCV_TriggerFlags = new Convar("proptricks_misc_tflags", "0", "?", 0, true, 0.0, true, 1.0);

	Convar.AutoExecConfig();

	mp_humanteam = FindConVar("mp_humanteam");

	// modules
	gB_Replay = LibraryExists("proptricks-replay");
	gB_Zones = LibraryExists("proptricks-zones");
	gB_SendProxy = LibraryExists("sendproxy14");
	
	// late load
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);

				if(AreClientCookiesCached(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
		
		if(gB_SendProxy)
		{
			int entity = -1;
			while((entity = FindEntityByClassname(entity, "prop_*")) != -1)
			{
				OnPropSpawn(entity);
			}
		}
		
		PropTricks_GetChatStrings(gS_ChatStrings);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "proptricks-replay"))
	{
		gB_Replay = true;
	}

	else if(StrEqual(name, "proptricks-zones"))
	{
		gB_Zones = true;
	}

	else if(StrEqual(name, "sendproxy14"))
	{
		gB_SendProxy = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "proptricks-replay"))
	{
		gB_Replay = false;
	}

	else if(StrEqual(name, "proptricks-zones"))
	{
		gB_Zones = false;
	}

	else if(StrEqual(name, "sendproxy14"))
	{
		gB_SendProxy = false;
	}
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	char sSetting[16];

	GetClientCookie(client, gH_HideCookie, sSetting, sizeof(sSetting));
	if(strlen(sSetting) == 0)
	{
		SetClientCookie(client, gH_HideCookie, "0");
		gB_Hide[client] = false;
	}
	else
	{
		gB_Hide[client] = view_as<bool>(StringToInt(sSetting));
	}

	GetClientCookie(client, gH_PropColorCookie, sSetting, sizeof(sSetting));
	if(strlen(sSetting) == 0)
	{
		SetCookie(client, gH_PropColorCookie, 0xFFFFFF);
		gI_PropColor[client] = HEXtoRGB(0xFFFFFF);
	}
	else
	{
		gI_PropColor[client] = HEXtoRGB(StringToInt(sSetting));
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(gCV_TriggerFlags.BoolValue)
	{
		if(StrEqual(classname, "trigger_teleport") || StrEqual(classname, "trigger_push"))
		{
			SDKHook(entity, SDKHook_Spawn, OnTriggerSpawn);
		}
	}
	
	if(gB_SendProxy)
	{
		if(StrContains(classname, "prop_physics") != -1)
		{
			SDKHook(entity, SDKHook_Spawn, OnPropSpawn);
		}
	}
}

public Action OnTriggerSpawn(int entity)
{
	if(IsValidEntity(entity))
	{
		int spawnflags = GetEntProp(entity, Prop_Data, "m_spawnflags");

		if(spawnflags & 8 != 8)
		{
			SetEntProp(entity, Prop_Data, "m_spawnflags", spawnflags | 8);
		}
	}
}

public Action OnPropSpawn(int entity)
{
	if(IsValidEntity(entity) 
	&& GetEntProp(entity, Prop_Data, "m_CollisionGroup") != 2 
	&& GetEntPropEnt(entity, Prop_Send, "m_PredictableID") != -1)
	{
		if(!SendProxy_IsHooked(entity, "m_CollisionGroup"))
		{
			SendProxy_Hook(entity, "m_CollisionGroup", Prop_Int, Hook_CollisionGroup, true);
		}

		if(!SendProxy_IsHooked(entity, "m_clrRender"))
		{
			SendProxy_Hook(entity, "m_clrRender", Prop_Int, Hook_ColorRender, true);
		}
	}
}

public Action Hook_CollisionGroup(const int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(IsValidProp(iEntity))
	{
		if(!IsValidClient(iClient, true) || PropTricks_GetPropEntityIndex(iClient) == iEntity)
		{
			return Plugin_Continue;
		}

		iValue = 2;
		return Plugin_Changed;
	}
	else
	{
		SendProxy_Unhook(iEntity, cPropName, Hook_CollisionGroup);
	}
	return Plugin_Continue;
}

public Action Hook_ColorRender(const int iEntity, const char[] cPropName, int &iValue, int iElement, int iClient)
{
	if(IsValidProp(iEntity))
	{
		if(!IsValidClient(iClient, true) || PropTricks_GetPropEntityIndex(iClient) != iEntity)
		{
			return Plugin_Continue;
		}

		iValue = RGBtoInvertedHEX(gI_PropColor[iClient]);
		return Plugin_Changed;
	}
	else
	{
		SendProxy_Unhook(iEntity, cPropName, Hook_ColorRender);
	}
	return Plugin_Continue;
}

int RGBtoInvertedHEX(int color[3])
{
	return color[0] | (color[1] << 8) | (color[2] << 16);
}

/*public Action Hook_RenderMode(const int iEntity, const char[] cPropName, int &iValue, const int iElement, const int iClient)
{
	if(IsValidProp(iEntity))
	{
		int client = GetEntPropEnt(iEntity, Prop_Send, "m_PredictableID");

		if(!IsValidClient(client, true) || PropTricks_GetPropEntityIndex(client) != iEntity)
		{
			return Plugin_Continue;
		}

		iValue = 3;
		return Plugin_Changed;
	}
	return Plugin_Continue;
}*/

public void PropTricks_OnPropCreated(int client, int prop, int entity)
{
	if(IsValidEdict(entity))
	{
		SDKHook(entity, SDKHook_SetTransmit, OnPropSetTransmit);
		SDKHook(entity, SDKHook_OnTakeDamage, OnPropTakeDamage);
	}
}

public void PropTricks_OnReplayPropCreated(int prop, int entity)
{
	if(IsValidEdict(entity))
	{
		SDKHook(entity, SDKHook_SetTransmit, OnPropSetTransmit);
		SDKHook(entity, SDKHook_OnTakeDamage, OnPropTakeDamage);
	}
}

public Action OnPropTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	return Plugin_Handled;
}

public void OnMapStart()
{
	MiscDhooks_OnMapStart();

	// create spawn points
	int iEntity = -1;

	if((iEntity = FindEntityByClassname(iEntity, "info_player_terrorist")) != -1 || // CS:S/CS:GO T
		(iEntity = FindEntityByClassname(iEntity, "info_player_counterterrorist")) != -1 || // CS:S/CS:GO CT
		(iEntity = FindEntityByClassname(iEntity, "info_player_start")) != -1)
	{
		float fOrigin[3], fAngles[3];
		GetEntPropVector(iEntity, Prop_Send, "m_vecOrigin", fOrigin);
		GetEntPropVector(iEntity, Prop_Data, "m_angAbsRotation", fAngles);

		for(int i = 1; i <= SPAWN_POINTS; i++)
		{
			for(int iTeam = 1; iTeam <= 2; iTeam++)
			{
				int iSpawnPoint = CreateEntityByName((iTeam == 1) ? "info_player_terrorist":"info_player_counterterrorist");

				if(DispatchSpawn(iSpawnPoint))
				{
					TeleportEntity(iSpawnPoint, fOrigin, fAngles, NULL_VECTOR);
				}
			}
		}
	}

	if(gB_Late)
	{
		PropTricks_OnPropConfigLoaded(-1);
		PropTricks_GetChatStrings(gS_ChatStrings);
	}
}

public void PropTricks_OnPropConfigLoaded(int props)
{
	if(props == -1)
	{
		props = PropTricks_GetPropCount();
	}

	for(int i = 0; i < props; i++)
	{
		PropTricks_GetPropStrings(i, sPropName, gS_PropStrings[i].sPropName, sizeof(propstrings_t::sPropName));
	}
}

public void PropTricks_OnChatConfigLoaded(chatstrings_t strings)
{
	gS_ChatStrings = strings;
}

public Action PropTricks_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int prop)
{
	bool bNoclip = (GetEntityMoveType(client) == MOVETYPE_NOCLIP);

	if(bNoclip)
	{
		if(status == Timer_Running)
		{
			PropTricks_StopTimer(client);
		}
	}

	return Plugin_Continue;
}

public void OnClientPutInServer(int client)
{
	SDKHook(client, SDKHook_SetTransmit, OnSetTransmit);
	SDKHook(client, SDKHook_WeaponDrop, OnWeaponDrop);
	SDKHook(client, SDKHook_OnTakeDamage, OnTakeDamage);

	if(IsFakeClient(client))
	{
		return;
	}

	if(!AreClientCookiesCached(client))
	{
		gB_Hide[client] = false;
	}
}

public void OnClientDisconnect(int client)
{
	int entity = -1;

	while((entity = FindEntityByClassname(entity, "weapon_*")) != -1)
	{
		if(GetEntPropEnt(entity, Prop_Send, "m_hOwnerEntity") == client)
		{
			RequestFrame(RemoveWeapon, EntIndexToEntRef(entity));
		}
	}
}

public Action OnTakeDamage(int victim, int attacker)
{
	if(gB_Hide[victim])
	{
		SetEntPropVector(victim, Prop_Send, "m_vecPunchAngle", NULL_VECTOR);
		SetEntPropVector(victim, Prop_Send, "m_vecPunchAngleVel", NULL_VECTOR);
	}

	return Plugin_Handled;
}

public void OnWeaponDrop(int client, int entity)
{
	AcceptEntityInput(entity, "Kill");
}

public Action OnSetTransmit(int entity, int client)
{
	if(gB_Hide[client] && client != entity && (!IsClientObserver(client) || (GetEntProp(client, Prop_Send, "m_iObserverMode") != 6 &&
		GetEntPropEnt(client, Prop_Send, "m_hObserverTarget") != entity)))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action OnPropSetTransmit(int entity, int other)
{
	if(IsValidEdict(entity) && IsValidClient(other))
	{
		int clientprop = GetEntPropEnt(entity, Prop_Send, "m_PredictableID");
		
		if(gB_Hide[other] && other != clientprop && (!IsClientObserver(other) || (GetEntProp(other, Prop_Send, "m_iObserverMode") != 6 &&
			GetEntPropEnt(other, Prop_Send, "m_hObserverTarget") != clientprop)))
		{
			return Plugin_Handled;
		}
	}

	return Plugin_Continue;
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(IsChatTrigger())
	{
		// hide commands
		return Plugin_Handled;
	}

	if(sArgs[0] == '!' || sArgs[0] == '/')
	{
		bool bUpper = false;

		for(int i = 0; i < strlen(sArgs); i++)
		{
			if(IsCharUpper(sArgs[i]))
			{
				bUpper = true;

				break;
			}
		}

		if(bUpper)
		{
			char sCopy[32];
			strcopy(sCopy, 32, sArgs[1]);

			FakeClientCommandEx(client, "sm_%s", sCopy);

			return Plugin_Stop;
		}
	}

	return Plugin_Continue;
}

public Action PropTricks_OnStart(int client)
{
	if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		return Plugin_Stop;
	}

	return Plugin_Continue;
}

public bool PropTricks_OnStopPre(int client, int track)
{
	if(ShouldDisplayStopWarning(client))
	{
		OpenStopWarningMenu(client, DoStopTimer);

		return false;
	}

	return true;
}

public void PropTricks_OnWorldRecord(int client, int prop, float time, int track)
{
	char sUpperCase[64];
	strcopy(sUpperCase, 64, gS_PropStrings[prop].sPropName);

	for(int i = 0; i < strlen(sUpperCase); i++)
	{
		if(!IsCharUpper(sUpperCase[i]))
		{
			sUpperCase[i] = CharToUpper(sUpperCase[i]);
		}
	}

	char sTrack[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);
	
	PropTricks_PrintToChatAll("%s[%s]%s %t", gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText, "WRNotice", gS_ChatStrings.sWarning, sUpperCase);
}

public void PropTricks_OnRestart(int client, int track)
{
	SetEntPropFloat(client, Prop_Send, "m_flStamina", 0.0);
	
	if(!gCV_RespawnOnRestart.BoolValue)
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
		{
			CS_SwitchTeam(client, 2);
		}
		else
		{
			CS_SwitchTeam(client, 3);
		}

		CS_RespawnPlayer(client);

		if(gCV_RespawnOnRestart.BoolValue)
		{
			RestartTimer(client, track);
		}
	}
}

// Events
public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		if(gCV_StartOnSpawn.BoolValue)
		{
			int track = PropTricks_GetClientTrack(client);
			RestartTimer(client, track);
		}
	}

	SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	
	if(gCV_PlayerOpacity.IntValue != -1)
	{
		SetEntityRenderMode(client, RENDER_TRANSCOLOR);
		SetEntityRenderColor(client, 255, 255, 255, gCV_PlayerOpacity.IntValue);
	}
}

public Action Event_PlayerNotifications(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(!IsFakeClient(client))
	{
		if(gCV_AutoRespawn.FloatValue > 0.0 && StrEqual(name, "player_death"))
		{
			CreateTimer(gCV_AutoRespawn.FloatValue, Respawn, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	int iEntity = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");

	if(iEntity != INVALID_ENT_REFERENCE)
	{
		AcceptEntityInput(iEntity, "Kill");
	}

	return Plugin_Continue;
}

public void Event_WeaponFire(Event event, const char[] name, bool dB)
{
	char sWeapon[16];
	event.GetString("weapon", sWeapon, 16);

	if(StrContains(sWeapon, "usp") != -1 || StrContains(sWeapon, "hpk") != -1 || StrContains(sWeapon, "glock") != -1)
	{
		int client = GetClientOfUserId(event.GetInt("userid"));
		SetWeaponAmmo(client, GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon"));
	}
}

//Commands
public Action Command_Hookent(int client, int args)
{
	int entity = GetClientAimTarget(client, false);
	if(IsValidEdict(entity))
	{
		PrintToChat(client, "%d", GetEntPropEnt(entity, Prop_Send, "m_PredictableID"));
		SetEntPropEnt(entity, Prop_Send, "m_PredictableID", -1);
		SDKHook(entity, SDKHook_SetTransmit, OnPropSetTransmit);
	}

	return Plugin_Handled;
}

public Action Command_Jointeam(int client, const char[] command, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	char arg1[8];
	GetCmdArg(1, arg1, 8);

	int iTeam = StringToInt(arg1);
	int iHumanTeam = GetHumanTeam();

	if(iHumanTeam != 0 && iTeam != 0)
	{
		iTeam = iHumanTeam;
	}

	bool bRespawn = false;

	switch(iTeam)
	{
		case 2:
		{
			// if T spawns are available in the map
			if(FindEntityByClassname(-1, "info_player_terrorist") != -1)
			{
				bRespawn = true;
				CleanSwitchTeam(client, 2, true);
			}
		}

		case 3:
		{
			// if CT spawns are available in the map
			if(FindEntityByClassname(-1, "info_player_counterterrorist") != -1)
			{
				bRespawn = true;
				CleanSwitchTeam(client, 3, true);
			}
		}

		// if they chose to spectate, i'll force them to join the spectators
		case 1:
		{
			CleanSwitchTeam(client, 1, false);
		}

		default:
		{
			bRespawn = true;
			CleanSwitchTeam(client, GetRandomInt(2, 3), true);
		}
	}

	if(gCV_RespawnOnTeam.BoolValue && bRespawn)
	{
		CS_RespawnPlayer(client);
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action Command_Spectate(int client, const char[] command, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Continue;
	}

	Command_Spec(client, 0);
	return Plugin_Stop;
}

public Action Command_Hide(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gB_Hide[client] = !gB_Hide[client];

	char sCookie[4];
	IntToString(view_as<int>(gB_Hide[client]), sCookie, 4);
	SetClientCookie(client, gH_HideCookie, sCookie);

	if(gB_Hide[client])
	{
		PropTricks_PrintToChat(client, "%T", "HideEnabled", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}

	else
	{
		PropTricks_PrintToChat(client, "%T", "HideDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_Spec(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	CleanSwitchTeam(client, 1, false);

	int target = -1;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, false, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	else if(gB_Replay)
	{
		target = PropTricks_GetReplayBotIndex();
	}

	if(IsValidClient(target, true))
	{
		SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", target);
	}

	return Plugin_Handled;
}

public Action Command_Teleport(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		int iTarget = FindTarget(client, sArgs, false, false);

		if(iTarget == -1)
		{
			return Plugin_Handled;
		}

		Teleport(client, GetClientSerial(iTarget));
	}

	else
	{
		Menu menu = new Menu(MenuHandler_Teleport);
		menu.SetTitle("%T", "TeleportMenuTitle", client);

		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsValidClient(i, true) || i == client)
			{
				continue;
			}

			char serial[16];
			IntToString(GetClientSerial(i), serial, 16);

			char sName[MAX_NAME_LENGTH];
			GetClientName(i, sName, MAX_NAME_LENGTH);

			menu.AddItem(serial, sName);
		}

		menu.ExitButton = true;
		menu.Display(client, 60);
	}

	return Plugin_Handled;
}

public int MenuHandler_Teleport(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(!Teleport(param1, StringToInt(sInfo)))
		{
			Command_Teleport(param1, 0);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Weapon(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		PropTricks_PrintToChat(client, "%T", "WeaponAlive", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int iSlot = CS_SLOT_SECONDARY;
	char sWeapon[32];

	if(StrContains(sCommand, "usp", false) != -1)
	{
		strcopy(sWeapon, 32, "weapon_usp");
	}

	else if(StrContains(sCommand, "glock", false) != -1)
	{
		strcopy(sWeapon, 32, "weapon_glock");
	}

	else
	{
		strcopy(sWeapon, 32, "weapon_knife");
		iSlot = CS_SLOT_KNIFE;
	}

	int iWeapon = GetPlayerWeaponSlot(client, iSlot);

	if(iWeapon != -1)
	{
		RemovePlayerItem(client, iWeapon);
		AcceptEntityInput(iWeapon, "Kill");
	}

	iWeapon = GivePlayerItem(client, sWeapon);
	FakeClientCommand(client, "use %s", sWeapon);

	if(iSlot != CS_SLOT_KNIFE)
	{
		SetWeaponAmmo(client, iWeapon);
	}

	return Plugin_Handled;
}

public Action Command_Noclip(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		PropTricks_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(GetEntityMoveType(client) != MOVETYPE_NOCLIP)
	{
		if(!ShouldDisplayStopWarning(client))
		{
			PropTricks_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}

		else
		{
			OpenStopWarningMenu(client, DoNoclip);
		}
	}

	else
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	return Plugin_Handled;
}

public Action Command_Specs(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client) && !IsClientObserver(client))
	{
		PropTricks_PrintToChat(client, "%T", "SpectatorInvalid", client);

		return Plugin_Handled;
	}

	int iObserverTarget = client;

	if(IsClientObserver(client))
	{
		iObserverTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");
	}

	if(args > 0)
	{
		char sTarget[MAX_TARGET_LENGTH];
		GetCmdArgString(sTarget, MAX_TARGET_LENGTH);

		int iNewTarget = FindTarget(client, sTarget, false, false);

		if(iNewTarget == -1)
		{
			return Plugin_Handled;
		}

		if(!IsPlayerAlive(iNewTarget))
		{
			PropTricks_PrintToChat(client, "%T", "SpectateDead", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

			return Plugin_Handled;
		}

		iObserverTarget = iNewTarget;
	}

	int iCount = 0;
	bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);
	char sSpecs[192];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1)
		{
			continue;
		}

		if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
			(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
		{
			continue;
		}

		if(GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == iObserverTarget)
		{
			iCount++;

			if(iCount == 1)
			{
				FormatEx(sSpecs, 192, "%s%N", gS_ChatStrings.sVariable2, i);
			}

			else
			{
				Format(sSpecs, 192, "%s%s, %s%N", sSpecs, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, i);
			}
		}
	}

	if(iCount > 0)
	{
		PropTricks_PrintToChat(client, "%T", "SpectatorCount", client, gS_ChatStrings.sVariable2, iObserverTarget, gS_ChatStrings.sText, gS_ChatStrings.sVariable, iCount, gS_ChatStrings.sText, sSpecs);
	}

	else
	{
		PropTricks_PrintToChat(client, "%T", "SpectatorCountZero", client, gS_ChatStrings.sVariable2, iObserverTarget, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

static const char sColors[][] = {
	"Default",
	"Red",
	"Green",
	"Blue",
	"Yellow",
	"Orange",
	"Pink",
	"Aqua"
};

static int iColors[][3] = {
	{255, 255, 255},
	{255, 0, 0},
	{0, 255, 0},
	{0, 0, 255},
	{255, 255, 0},
	{255, 165, 0},
	{255, 192, 203},
	{0, 255, 255}
};

public Action Command_Color(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	ColorMenu(client, 0);

	return Plugin_Handled;
}

void ColorMenu(int client, int item)
{
	Menu menu = new Menu(MenuHandler_Color);
	//menu.SetTitle("%T", "TeleportMenuTitle", client);
	menu.SetTitle("Prop Preference");

	char sInfo[8];
	for(int i = 0; i < sizeof(sColors); i++)
	{
		IntToString(i, sInfo, 8);

		int iFlag = ITEMDRAW_DEFAULT;
		if(gI_PropColor[client][0] == iColors[i][0] && gI_PropColor[client][1] == iColors[i][1] && gI_PropColor[client][2] == iColors[i][2])
		{
			iFlag = ITEMDRAW_DISABLED;
		}

		menu.AddItem(sInfo, sColors[i], iFlag);
	}

	char sCustom[32];
	FormatEx(sCustom, sizeof(sCustom), "Custom: [%06X]", RGBtoHEX(gI_PropColor[client]));
	menu.AddItem("custom", sCustom);

	menu.ExitButton = true;
	menu.DisplayAt(client, item, 60);
}

public int MenuHandler_Color(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		if(StrEqual(sInfo, "custom"))
		{
			PropTricks_PrintToChat(param1, "Current value: \x07%06X[%06X]", RGBtoHEX(gI_PropColor[param1]), RGBtoHEX(gI_PropColor[param1]));
			PropTricks_PrintToChat(param1, "Enter a hexadecimal value:");
			gB_ChooseColor[param1] = true;
		}
		else
		{
			int index = StringToInt(sInfo);
			gI_PropColor[param1] = iColors[index];
			SetCookie(param1, gH_PropColorCookie, RGBtoHEX(gI_PropColor[param1]));
		}
		ColorMenu(param1, GetMenuSelectionPosition());
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Say(int client, const char[] command, int args)
{
	if(gB_ChooseColor[client])
	{
		char text[64];
		GetCmdArg(1, text, sizeof(text));
		
		Regex hRegex = new Regex("^[A-Fa-f0-9]{6}$");
		hRegex.Match(text);
		
		if(!hRegex.MatchCount())
		{
			PropTricks_PrintToChat(client, "This is an invalid value.");
			gB_ChooseColor[client] = false;

			ColorMenu(client, 0);

			delete hRegex;
			return Plugin_Handled;
		}

		delete hRegex;
		
		int HexValue = StringToInt(text, 16);
		gI_PropColor[client] = HEXtoRGB(HexValue);
		SetCookie(client, gH_PropColorCookie, RGBtoHEX(gI_PropColor[client]));

		PropTricks_PrintToChat(client, "Color was changed to: \x07%06X[%06X]", RGBtoHEX(gI_PropColor[client]), RGBtoHEX(gI_PropColor[client]));
		gB_ChooseColor[client] = false;

		ColorMenu(client, 0);
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

int[] HEXtoRGB(int hexValue)
{
	int color[3];
	color[0] = ((hexValue >> 16) & 0xFF);
	color[1] = ((hexValue >> 8) & 0xFF);
	color[2] = ((hexValue) & 0xFF);

	return color; 
}

int RGBtoHEX(int color[3])
{
	return (color[0] << 16) | (color[1] << 8) | color[2];
}

// Utils
int GetHumanTeam()
{
	char sTeam[8];
	mp_humanteam.GetString(sTeam, 8);

	if(StrEqual(sTeam, "t", false) || StrEqual(sTeam, "red", false))
	{
		return 2;
	}

	else if(StrEqual(sTeam, "ct", false) || StrContains(sTeam, "blu", false) != -1)
	{
		return 3;
	}

	return 0;
}

void CleanSwitchTeam(int client, int team, bool change = false)
{
	if(change)
	{
		CS_SwitchTeam(client, team);
	}

	else
	{
		ChangeClientTeam(client, team);
	}
}

void RemoveWeapon(any data)
{
	if(IsValidEntity(data))
	{
		AcceptEntityInput(data, "Kill");
	}
}

bool Teleport(int client, int targetserial)
{
	if(!IsPlayerAlive(client))
	{
		PropTricks_PrintToChat(client, "%T", "TeleportAlive", client);

		return false;
	}

	int iTarget = GetClientFromSerial(targetserial);

	if(PropTricks_InsideZone(client, Zone_Start, -1) || PropTricks_InsideZone(client, Zone_End, -1))
	{
		PropTricks_PrintToChat(client, "%T", "TeleportInZone", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	if(iTarget == 0)
	{
		PropTricks_PrintToChat(client, "%T", "TeleportInvalidTarget", client);

		return false;
	}

	float vecPosition[3];
	GetClientAbsOrigin(iTarget, vecPosition);

	PropTricks_StopTimer(client);

	TeleportEntity(client, vecPosition, NULL_VECTOR, NULL_VECTOR);

	return true;
}

void SetWeaponAmmo(int client, int weapon)
{
	int iAmmo = GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType");
	SetEntData(client, gI_Ammo + (iAmmo * 4), 255, 4, true);
}

bool ShouldDisplayStopWarning(int client)
{
	return (gCV_StopTimerWarning.BoolValue && PropTricks_GetTimerStatus(client) != Timer_Stopped && PropTricks_GetClientTime(client) > gCV_StopTimerWarning.FloatValue);
}

void DoNoclip(int client)
{
	PropTricks_StopTimer(client);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);
}

void DoStopTimer(int client)
{
	PropTricks_StopTimer(client);
}

void OpenStopWarningMenu(int client, StopTimerCallback after)
{
	gH_AfterWarningMenu[client] = after;

	Menu hMenu = new Menu(MenuHandler_StopWarning);
	hMenu.SetTitle("%T\n ", "StopTimerWarning", client);

	char sDisplay[64];
	FormatEx(sDisplay, 64, "%T", "StopTimerYes", client);
	hMenu.AddItem("yes", sDisplay);

	FormatEx(sDisplay, 64, "%T", "StopTimerNo", client);
	hMenu.AddItem("no", sDisplay);

	hMenu.ExitButton = true;
	hMenu.Display(client, 30);
}

public int MenuHandler_StopWarning(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		if(StrEqual(sInfo, "yes"))
		{
			Call_StartFunction(null, gH_AfterWarningMenu[param1]);
			Call_PushCell(param1);
			Call_Finish();
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action CommandListener_Noclip(int client, const char[] command, int args)
{
	if(!IsValidClient(client, true))
	{
		return Plugin_Handled;
	}

	if(command[0] == '+')
	{
		if(!ShouldDisplayStopWarning(client))
		{
			PropTricks_StopTimer(client);
			SetEntityMoveType(client, MOVETYPE_NOCLIP);
		}

		else
		{
			OpenStopWarningMenu(client, DoNoclip);
		}
	}

	else if(GetEntityMoveType(client) == MOVETYPE_NOCLIP)
	{
		SetEntityMoveType(client, MOVETYPE_WALK);
	}

	return Plugin_Handled;
}

public Action Respawn(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(IsValidClient(client) && !IsPlayerAlive(client) && GetClientTeam(client) >= 2)
	{
		CS_RespawnPlayer(client);

		if(gCV_RespawnOnRestart.BoolValue)
		{
			int track = PropTricks_GetClientTrack(client);
			RestartTimer(client, track);
		}
	}

	return Plugin_Handled;
}

void RestartTimer(int client, int track)
{
	if(gB_Zones && PropTricks_ZoneExists(Zone_Start, track))
	{
		PropTricks_RestartTimer(client, track);
	}
}

public Action EffectDispatch(const char[] te_name, const Players[], int numClients, float delay)
{
	int iEffectIndex = TE_ReadNum("m_iEffectName");

	char sEffectName[32];
	GetEffectName(iEffectIndex, sEffectName, 32);

	if(StrEqual(sEffectName, "csblood"))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

public Action WorldDecal(const char[] te_name, const Players[], int numClients, float delay)
{
	float vecOrigin[3];
	TE_ReadVector("m_vecOrigin", vecOrigin);

	int nIndex = TE_ReadNum("m_nIndex");

	char sDecalName[32];
	GetDecalName(nIndex, sDecalName, 32);

	if(StrContains(sDecalName, "decals/blood") == 0 && StrContains(sDecalName, "_subrect") != -1)
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

int GetEffectName(int index, char[] sEffectName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("EffectDispatch");
	}

	return ReadStringTable(table, index, sEffectName, maxlen);
}

int GetDecalName(int index, char[] sDecalName, int maxlen)
{
	static int table = INVALID_STRING_TABLE;

	if(table == INVALID_STRING_TABLE)
	{
		table = FindStringTable("decalprecache");
	}

	return ReadStringTable(table, index, sDecalName, maxlen);
}

public Action Command_Drop(int client, const char[] command, int argc)
{
	if(!gCV_DropAll.BoolValue || !IsValidClient(client))
	{
		return Plugin_Continue;
	}

	int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

	if(iWeapon != -1 && IsValidEntity(iWeapon) && GetEntPropEnt(iWeapon, Prop_Send, "m_hOwnerEntity") == client)
	{
		CS_DropWeapon(client, iWeapon, true);
	}

	return Plugin_Handled;
}

stock void SetCookie(int client, Handle hCookie, int n)
{
	char sCookie[64];
	IntToString(n, sCookie, sizeof(sCookie));
	SetClientCookie(client, hCookie, sCookie);
}