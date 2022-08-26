#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <convar_class>
#include <vphysics>

#undef REQUIRE_PLUGIN
#include <proptricks>
#include <adminmenu>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#define REPLAY_FORMAT_V1 "{PROPTRICKSREPLAYFORMAT}{V1}"
#define REPLAY_FORMAT_SUBVERSION 0x04
#define CELLS_PER_FRAME 14 // origin[3], angles[2], buttons, flags, movetype, proporigin[3], propangles[3]
#define FRAMES_PER_WRITE 100 // amounts of frames to write per read/write call

// #define DEBUG

#pragma newdecls required
#pragma semicolon 1
#pragma dynamic 2621440

enum struct centralbot_cache_t
{
	int iClient;
	int iProp;
	ReplayStatus iReplayStatus;
	int iTrack;
	int iPlaybackSerial;
}

enum struct replaystrings_t
{
	char sClanTag[MAX_NAME_LENGTH];
	char sNameProp[MAX_NAME_LENGTH];
	char sCentralName[MAX_NAME_LENGTH];
	char sCentralProp[MAX_NAME_LENGTH];
	char sCentralPropTag[MAX_NAME_LENGTH];
	char sUnloaded[MAX_NAME_LENGTH];
}

enum struct framecache_t
{
	int iFrameCount;
	float fTime;
	char sReplayName[MAX_NAME_LENGTH];
	int iPreFrames;
}

enum
{
	iBotShooting_Attack1 = (1 << 0),
	iBotShooting_Attack2 = (1 << 1)
}

// custom cvar settings
char gS_ForcedCvars[][][] =
{
	{ "bot_quota", "{expected_bots}" },
	{ "bot_stop", "1" },
	{ "bot_quota_mode", "normal" },
	{ "mp_limitteams", "0" },
	{ "bot_join_after_player", "0" },
	{ "bot_chatter", "off" },
	{ "bot_flipout", "1" },
	{ "bot_zombie", "1" },
	{ "mp_autoteambalance", "0" },
	{ "bot_controllable", "0" }
};

// cache
char gS_ReplayFolder[PLATFORM_MAX_PATH];

int gI_ReplayTick[PROP_LIMIT];
int gI_TimerTick[PROP_LIMIT];
int gI_ReplayBotClient[PROP_LIMIT];
int gI_ReplayProps[PROP_LIMIT] = {-1, ...};
ArrayList gA_Frames[PROP_LIMIT][TRACKS_SIZE];
float gF_StartTick[PROP_LIMIT];
ReplayStatus gRS_ReplayStatus[PROP_LIMIT];
framecache_t gA_FrameCache[PROP_LIMIT][TRACKS_SIZE];

bool gB_ForciblyStopped = false;
Handle gH_ReplayTimers[PROP_LIMIT];

bool gB_Button[MAXPLAYERS+1];
int gI_PlayerFrames[MAXPLAYERS+1];
int gI_PlayerPrerunFrames[MAXPLAYERS+1];
int gI_PlayerTimerStartFrames[MAXPLAYERS+1];
bool gB_ClearFrame[MAXPLAYERS+1];
ArrayList gA_PlayerFrames[MAXPLAYERS+1];
int gI_Track[MAXPLAYERS+1];
float gF_LastInteraction[MAXPLAYERS+1];

bool gB_Late = false;

// forwards
Handle gH_OnReplayStart = null;
Handle gH_OnReplayEnd = null;
Handle gH_OnReplaysLoaded = null;
Handle gH_OnReplayPropCreated = null;

// server specific
float gF_Tickrate = 0.0;
char gS_Map[160];
int gI_ExpectedBots = 0;
centralbot_cache_t gA_CentralCache;

// how do i call this
bool gB_HideNameChange = false;
bool gB_DontCallTimer = false;

// plugin cvars
Convar gCV_Enabled = null;
Convar gCV_ReplayDelay = null;
Convar gCV_TimeLimit = null;
Convar gCV_DefaultTeam = null;
Convar gCV_BotShooting = null;
Convar gCV_BotPlusUse = null;
Convar gCV_BotWeapon = null;
Convar gCV_PlaybackCanStop = null;
Convar gCV_PlaybackCooldown = null;
Convar gCV_PlaybackPreRunTime = null;
Convar gCV_ClearPreRun = null;
Convar gCV_DynamicTimeSearch = null;
Convar gCV_DynamicTimeCheap = null;

// timer settings
int gI_Props = 0;
propstrings_t gS_PropStrings[PROP_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

// replay settings
replaystrings_t gS_ReplayStrings;

// admin menu
TopMenu gH_AdminMenu = null;
TopMenuObject gH_TimerCommands = INVALID_TOPMENUOBJECT;

// database related things
Database gH_SQL = null;

public Plugin myinfo =
{
	name = "[PropTricks] Replay Bot",
	author = "Haze",
	description = "A replay bot for proptricks timer.",
	version = PROPTRICKS_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("PropTricks_DeleteReplay", Native_DeleteReplay);
	CreateNative("PropTricks_GetReplayBotCurrentFrame", Native_GetReplayBotCurrentFrame);
	CreateNative("PropTricks_GetClientFrameCount", Native_GetClientFrameCount);
	CreateNative("PropTricks_GetReplayBotFirstFrame", Native_GetReplayBotFirstFrame);
	CreateNative("PropTricks_GetReplayBotIndex", Native_GetReplayBotIndex);
	CreateNative("PropTricks_GetReplayPropIndex", Native_GetReplayPropIndex);
	CreateNative("PropTricks_GetReplayBotProp", Native_GetReplayBotProp);
	CreateNative("PropTricks_GetReplayBotTrack", Native_GetReplayBotTrack);
	CreateNative("PropTricks_GetReplayData", Native_GetReplayData);
	CreateNative("PropTricks_GetReplayFrames", Native_GetReplayFrames);
	CreateNative("PropTricks_GetReplayFrameCount", Native_GetReplayFrameCount);
	CreateNative("PropTricks_GetReplayLength", Native_GetReplayLength);
	CreateNative("PropTricks_GetReplayName", Native_GetReplayName);
	CreateNative("PropTricks_GetReplayStatus", Native_GetReplayStatus);
	CreateNative("PropTricks_GetReplayTime", Native_GetReplayTime);
	CreateNative("PropTricks_IsReplayDataLoaded", Native_IsReplayDataLoaded);
	CreateNative("PropTricks_StartReplay", Native_StartReplay);
	CreateNative("PropTricks_ReloadReplay", Native_ReloadReplay);
	CreateNative("PropTricks_Replay_DeleteMap", Native_Replay_DeleteMap);
	CreateNative("PropTricks_SetReplayData", Native_SetReplayData);
	CreateNative("PropTricks_GetPlayerPreFrame", Native_GetPreFrame);
	CreateNative("PropTricks_SetPlayerPreFrame", Native_SetPreFrame);
	CreateNative("PropTricks_SetPlayerTimerFrame", Native_SetTimerFrame);
	CreateNative("PropTricks_GetPlayerTimerFrame", Native_GetTimerFrame);
	CreateNative("PropTricks_GetClosestReplayTime", Native_GetClosestReplayTime);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("proptricks-replay");

	gB_Late = late;

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if(!LibraryExists("proptricks-wr"))
	{
		SetFailState("proptricks-wr is required for the plugin to work.");
	}

	// admin menu
	if(LibraryExists("adminmenu") && ((gH_AdminMenu = GetAdminTopMenu()) != null))
	{
		OnAdminMenuReady(gH_AdminMenu);
	}
}

public void OnPluginStart()
{
	LoadTranslations("proptricks-common.phrases");
	LoadTranslations("proptricks-replay.phrases");

	// forwards
	gH_OnReplayStart = CreateGlobalForward("PropTricks_OnReplayStart", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplayEnd = CreateGlobalForward("PropTricks_OnReplayEnd", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_OnReplaysLoaded = CreateGlobalForward("PropTricks_OnReplaysLoaded", ET_Event);
	gH_OnReplayPropCreated = CreateGlobalForward("PropTricks_OnReplayPropCreated", ET_Event, Param_Cell, Param_Cell);

	// game specific
	gF_Tickrate = (1.0 / GetTickInterval());

	FindConVar("bot_quota").Flags &= ~FCVAR_NOTIFY;
	FindConVar("bot_stop").Flags &= ~FCVAR_CHEAT;

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		ConVar hCvar = FindConVar(gS_ForcedCvars[i][0]);

		if(hCvar != null)
		{
			if(StrEqual(gS_ForcedCvars[i][1], "{expected_bots}"))
			{
				UpdateBotQuota(0);
			}	

			else
			{
				hCvar.SetString(gS_ForcedCvars[i][1]);
			}

			hCvar.AddChangeHook(OnForcedConVarChanged);
		}
	}

	// late load
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i) && !IsFakeClient(i))
		{
			OnClientPutInServer(i);
		}
	}

	// plugin convars
	gCV_Enabled = new Convar("proptricks_replay_enabled", "1", "Enable replay bot functionality?", 0, true, 0.0, true, 1.0);
	gCV_ReplayDelay = new Convar("proptricks_replay_delay", "5.0", "Time to wait before restarting the replay after it finishes playing.", 0, true, 0.0, true, 10.0);
	gCV_TimeLimit = new Convar("proptricks_replay_timelimit", "7200.0", "Maximum amount of time (in seconds) to allow saving to disk.\nDefault is 7200 (2 hours)\n0 - Disabled");
	gCV_DefaultTeam = new Convar("proptricks_replay_defaultteam", "3", "Default team to make the bots join, if possible.\n2 - Terrorists/RED\n3 - Counter Terrorists/BLU", 0, true, 2.0, true, 3.0);
	gCV_BotShooting = new Convar("proptricks_replay_botshooting", "3", "Attacking buttons to allow for bots.\n0 - none\n1 - +attack\n2 - +attack2\n3 - both", 0, true, 0.0, true, 3.0);
	gCV_BotPlusUse = new Convar("proptricks_replay_botplususe", "1", "Allow bots to use +use?", 0, true, 0.0, true, 1.0);
	gCV_BotWeapon = new Convar("proptricks_replay_botweapon", "", "Choose which weapon the bot will hold.\nLeave empty to use the default.\nSet to \"none\" to have none.\nExample: weapon_usp");
	gCV_PlaybackCanStop = new Convar("proptricks_replay_pbcanstop", "1", "Allow players to stop playback if they requested it?", 0, true, 0.0, true, 1.0);
	gCV_PlaybackCooldown = new Convar("proptricks_replay_pbcooldown", "10.0", "Cooldown in seconds to apply for players between each playback they request/stop.\nDoes not apply to RCON admins.", 0, true, 0.0);
	gCV_PlaybackPreRunTime = new Convar("proptricks_replay_preruntime", "1.0", "Time (in seconds) to record before a player leaves start zone. (The value should NOT be too high)", 0, true, 0.0);
	gCV_ClearPreRun = new Convar("proptricks_replay_prerun_always", "1", "Record prerun frames outside the start zone?", 0, true, 0.0, true, 1.0);
	gCV_DynamicTimeCheap = new Convar("proptricks_replay_timedifference_cheap", "0.0", "0 - Disabled\n1 - only clip the search ahead to proptricks_replay_timedifference_search\n2 - only clip the search behind to players current frame\n3 - clip the search to +/- proptricks_replay_timedifference_search seconds to the players current frame", 0, true, 0.0, true, 3.0);
	gCV_DynamicTimeSearch = new Convar("proptricks_replay_timedifference_search", "0.0", "Time in seconds to search the players current frame for dynamic time differences\n0 - Full Scan\nNote: Higher values will result in worse performance", 0, true, 0.0);

	Convar.AutoExecConfig();

	// hooks
	HookEvent("player_spawn", Player_Event, EventHookMode_Pre);
	HookEvent("player_death", Player_Event, EventHookMode_Pre);
	HookEvent("player_connect", BotEvents, EventHookMode_Pre);
	HookEvent("player_disconnect", BotEvents, EventHookMode_Pre);
	HookEventEx("player_connect_client", BotEvents, EventHookMode_Pre);

	// name change suppression
	HookUserMessage(GetUserMessageId("SayText2"), Hook_SayText2, true);

	// commands
	RegAdminCmd("sm_deletereplay", Command_DeleteReplay, ADMFLAG_RCON, "Open replay deletion menu.");
	RegConsoleCmd("sm_replay", Command_Replay, "Opens the central bot menu. For admins: 'sm_replay stop' to stop the playback.");

	// database
	gH_SQL = GetTimerDatabaseHandle();
}

public void OnLibraryAdded(const char[] name)
{
	if (strcmp(name, "adminmenu") == 0)
	{
		if ((gH_AdminMenu = GetAdminTopMenu()) != null)
		{
			OnAdminMenuReady(gH_AdminMenu);
		}
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if (strcmp(name, "adminmenu") == 0)
	{
		gH_AdminMenu = null;
		gH_TimerCommands = INVALID_TOPMENUOBJECT;
	}
}

void UpdateBotQuota(int quota)
{
	ConVar hCvar = FindConVar("bot_quota");
	hCvar.IntValue = gI_ExpectedBots = quota;
}

public void OnForcedConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	char sName[32];
	convar.GetName(sName, 32);

	for(int i = 0; i < sizeof(gS_ForcedCvars); i++)
	{
		if(StrEqual(sName, gS_ForcedCvars[i][0]))
		{
			if(StrEqual(gS_ForcedCvars[i][1], "{expected_bots}"))
			{
				convar.IntValue = gI_ExpectedBots;
			}

			else if(!StrEqual(newValue, gS_ForcedCvars[i][1]))
			{
				convar.SetString(gS_ForcedCvars[i][1]);
			}

			break;
		}
	}
}

public void OnAdminMenuCreated(Handle topmenu)
{
	if(gH_AdminMenu == null || (topmenu == gH_AdminMenu && gH_TimerCommands != INVALID_TOPMENUOBJECT))
	{
		return;
	}

	gH_TimerCommands = gH_AdminMenu.AddCategory("Timer Commands", CategoryHandler, "proptricks_admin", ADMFLAG_RCON);
}

public void CategoryHandler(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayTitle)
	{
		FormatEx(buffer, maxlength, "%T:", "TimerCommands", param);
	}

	else if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%T", "TimerCommands", param);
	}
}

public void OnAdminMenuReady(Handle topmenu)
{
	if((gH_AdminMenu = GetAdminTopMenu()) != null)
	{
		if(gH_TimerCommands == INVALID_TOPMENUOBJECT)
		{
			gH_TimerCommands = gH_AdminMenu.FindCategory("Timer Commands");

			if(gH_TimerCommands == INVALID_TOPMENUOBJECT)
			{
				OnAdminMenuCreated(topmenu);
			}
		}
		
		gH_AdminMenu.AddItem("sm_deletereplay", AdminMenu_DeleteReplay, gH_TimerCommands, "sm_deletereplay", ADMFLAG_RCON);
	}
}

public void AdminMenu_DeleteReplay(Handle topmenu, TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
	{
		FormatEx(buffer, maxlength, "%t", "DeleteReplayAdminMenu");
	}

	else if(action == TopMenuAction_SelectOption)
	{
		Command_DeleteReplay(param, 0);
	}
}

void UnloadReplay(int prop, int track)
{
	if(gA_CentralCache.iProp == prop && gA_CentralCache.iTrack == track)
	{
		StopCentralReplay(0);
	}

	gA_Frames[prop][track].Clear();
	gA_FrameCache[prop][track].iFrameCount = 0;
	gA_FrameCache[prop][track].fTime = 0.0;
	strcopy(gA_FrameCache[prop][track].sReplayName, MAX_NAME_LENGTH, "invalid");
	gA_FrameCache[prop][track].iPreFrames = 0;
	gI_ReplayTick[prop] = -1;

	if(gI_ReplayBotClient[prop] != 0)
	{
		UpdateReplayInfo(gI_ReplayBotClient[prop], prop, 0.0, track);
	}
}

public int Native_DeleteReplay(Handle handler, int numParams)
{
	char sMap[160];
	GetNativeString(1, sMap, 160);

	int iProp = GetNativeCell(2);
	int iTrack = GetNativeCell(3);
	int iSteamID = GetNativeCell(4);

	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", iTrack);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, iProp, gS_Map, sTrack);

	if(!DeleteReplay(iProp, iTrack, StrEqual(sMap, gS_Map), iSteamID))
	{
		return false;
	}

	return true;
}

public int Native_GetReplayBotFirstFrame(Handle handler, int numParams)
{
	SetNativeCellRef(2, gF_StartTick[GetNativeCell(1)]);
}

public int Native_GetReplayBotCurrentFrame(Handle handler, int numParams)
{
	return gI_ReplayTick[GetNativeCell(1)];
}

public int Native_GetReplayBotIndex(Handle handler, int numParams)
{
	return gA_CentralCache.iClient;
}

public int Native_GetReplayPropIndex(Handle handler, int numParams)
{
	return gA_CentralCache.iReplayStatus != Replay_Idle ? gI_ReplayProps[gA_CentralCache.iProp] : -1;
}

public int Native_IsReplayDataLoaded(Handle handler, int numParams)
{
	int prop = GetNativeCell(1);
	int track = GetNativeCell(2);

	return view_as<int>(gA_CentralCache.iClient != -1 && gA_CentralCache.iReplayStatus != Replay_Idle && gA_FrameCache[prop][track].iFrameCount > 0);
}

public int Native_StartReplay(Handle handler, int numParams)
{
	int prop = GetNativeCell(1);
	int track = GetNativeCell(2);
	float delay = GetNativeCell(3);
	int client = GetNativeCell(4);

	if(gA_FrameCache[prop][track].iFrameCount == 0)
	{
		return false;
	}

	gI_ReplayTick[prop] = 0;
	gI_TimerTick[prop] = 0;
	gA_CentralCache.iProp = prop;
	gA_CentralCache.iTrack = track;
	gA_CentralCache.iPlaybackSerial = GetClientSerial(client);
	gF_LastInteraction[client] = GetEngineTime();
	gI_ReplayBotClient[prop] = gA_CentralCache.iClient;
	gRS_ReplayStatus[prop] = gA_CentralCache.iReplayStatus = Replay_Start;
	TeleportToStart(gA_CentralCache.iClient, prop, track);
	gB_ForciblyStopped = false;

	float time = GetReplayLength(gA_CentralCache.iProp, track);

	UpdateReplayInfo(gA_CentralCache.iClient, prop, time, track);

	delete gH_ReplayTimers[prop];
	gH_ReplayTimers[prop] = CreateTimer((delay / 2.0), Timer_StartReplay, prop, TIMER_FLAG_NO_MAPCHANGE);

	return true;
}

public int Native_ReloadReplay(Handle handler, int numParams)
{
	int prop = GetNativeCell(1);

	gI_ReplayTick[prop] = -1;
	gF_StartTick[prop] = -65535.0;
	gRS_ReplayStatus[prop] = Replay_Idle;

	int track = GetNativeCell(2);

	char path[PLATFORM_MAX_PATH];
	GetNativeString(3, path, PLATFORM_MAX_PATH);

	delete gA_Frames[prop][track];
	gA_Frames[prop][track] = new ArrayList(CELLS_PER_FRAME);
	gA_FrameCache[prop][track].iFrameCount = 0;
	gA_FrameCache[prop][track].fTime = 0.0;
	strcopy(gA_FrameCache[prop][track].sReplayName, MAX_NAME_LENGTH, "invalid");
	gA_FrameCache[prop][track].iPreFrames = 0;

	bool loaded = false;

	if(strlen(path) > 0)
	{
		loaded = LoadReplay(prop, track, path);
	}

	else
	{
		loaded = DefaultLoadReplay(prop, track);
	}

	if(gA_CentralCache.iProp == prop && gA_CentralCache.iTrack == track)
	{
		StopCentralReplay(0);
	}

	return loaded;
}

public int Native_ReloadReplays(Handle handler, int numParams)
{
	int loaded = 0;

	for(int i = 0; i < gI_Props; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			if(PropTricks_ReloadReplay(i, j))
			{
				loaded++;
			}
		}
	}

	return loaded;
}

public int Native_SetReplayData(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	delete gA_PlayerFrames[client];

	ArrayList frames = view_as<ArrayList>(CloneHandle(GetNativeCell(2)));
	gA_PlayerFrames[client] = frames.Clone();
	delete frames;

	gI_PlayerFrames[client] = gA_PlayerFrames[client].Length;
}

public int Native_GetReplayData(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	ArrayList frames = null;

	if(gA_PlayerFrames[client] != null)
	{
		ArrayList temp = gA_PlayerFrames[client].Clone();
		frames = view_as<ArrayList>(CloneHandle(temp, handler));
		delete temp;
	}

	return view_as<int>(frames);
}

public int Native_GetReplayFrames(Handle handler, int numParams)
{
	int track = GetNativeCell(1);
	int prop = GetNativeCell(2);
	ArrayList frames = null;

	if(gA_Frames[track][prop] != null)
	{
		ArrayList temp = gA_Frames[track][prop].Clone();
		frames = view_as<ArrayList>(CloneHandle(temp, handler));
		delete temp;
	}

	return view_as<int>(frames);
}

public int Native_GetReplayFrameCount(Handle handler, int numParams)
{
	return gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].iFrameCount;
}

public int Native_GetClientFrameCount(Handle handler, int numParams)
{
	return gA_PlayerFrames[GetNativeCell(1)].Length;
}

public int Native_GetReplayLength(Handle handler, int numParams)
{
	return view_as<int>(GetReplayLength(GetNativeCell(1), GetNativeCell(2)));
}

public int Native_GetReplayName(Handle handler, int numParams)
{
	return SetNativeString(3, gA_FrameCache[GetNativeCell(1)][GetNativeCell(2)].sReplayName, GetNativeCell(4));
}

public int Native_GetReplayStatus(Handle handler, int numParams)
{
	return view_as<int>(gA_CentralCache.iReplayStatus);
}

public any Native_GetReplayTime(Handle handler, int numParams)
{
	int prop = GetNativeCell(1);
	int track = GetNativeCell(2);

	if(prop < 0 || track < 0)
	{
		return ThrowNativeError(200, "Prop/Track out of range");
	}

	if(gA_CentralCache.iReplayStatus == Replay_End)
	{
		return GetReplayLength(prop, track);
	}

	return float(gI_ReplayTick[prop] - gA_FrameCache[prop][track].iPreFrames) / gF_Tickrate;
}

public int Native_GetReplayBotProp(Handle handler, int numParams)
{
	return (gA_CentralCache.iReplayStatus == Replay_Idle) ? -1 : GetReplayProp(GetNativeCell(1));
}

public int Native_GetReplayBotTrack(Handle handler, int numParams)
{
	return GetReplayTrack(GetNativeCell(1));
}

public int Native_Replay_DeleteMap(Handle handler, int numParams)
{
	char sMap[160];
	GetNativeString(1, sMap, 160);

	for(int i = 0; i < gI_Props; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			char sTrack[4];
			FormatEx(sTrack, 4, "_%d", j);

			char sPath[PLATFORM_MAX_PATH];
			FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, i, sMap, sTrack);

			if(FileExists(sPath))
			{
				DeleteFile(sPath);
			}
		}
	}

	if(StrEqual(gS_Map, sMap, false))
	{
		OnMapStart();
	}
}

public int Native_GetPreFrame(Handle handler, int numParams)
{
	return gI_PlayerPrerunFrames[GetNativeCell(1)];
}

public int Native_GetTimerFrame(Handle handler, int numParams)
{
	return gI_PlayerTimerStartFrames[GetNativeCell(1)];
}

public int Native_SetPreFrame(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int preframes = GetNativeCell(2);

	gI_PlayerPrerunFrames[client] = preframes;
}

public int Native_SetTimerFrame(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int timerframes = GetNativeCell(2);

	gI_PlayerTimerStartFrames[client] = timerframes;
}

public int Native_GetClosestReplayTime(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int prop = GetNativeCell(2);
	int track = GetNativeCell(3);
	
	return view_as<int>(GetClosestReplayTime(client, prop, track));
}

public Action Cron(Handle Timer)
{
	if(!gCV_Enabled.BoolValue)
	{
		UpdateBotQuota(0);
		for(int i = 0; i < gI_Props; i++)
		{
			RemoveReplayProp(i);
		}

		return Plugin_Continue;
	}

	if(gA_CentralCache.iClient != -1)
	{
		if(gA_CentralCache.iProp != -1)
		{
			UpdateReplayInfo(gA_CentralCache.iClient, gA_CentralCache.iProp, -1.0, gA_CentralCache.iTrack);
		}

		else
		{
			UpdateReplayInfo(gA_CentralCache.iClient, 0, 0.0, 0);
		}
	}

	return Plugin_Continue;
}

bool LoadStyling()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/proptricks-replay.cfg");

	KeyValues kv = new KeyValues("proptricks-replay");
	
	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.GetString("clantag", gS_ReplayStrings.sClanTag, MAX_NAME_LENGTH, "<EMPTY CLANTAG>");
	kv.GetString("nameprop", gS_ReplayStrings.sNameProp, MAX_NAME_LENGTH, "<EMPTY NAMEPROP>");
	kv.GetString("centralname", gS_ReplayStrings.sCentralName, MAX_NAME_LENGTH, "<EMPTY CENTRALNAME>");
	kv.GetString("centralprop", gS_ReplayStrings.sCentralProp, MAX_NAME_LENGTH, "<EMPTY CENTRALPROP>");
	kv.GetString("centralproptag", gS_ReplayStrings.sCentralPropTag, MAX_NAME_LENGTH, "<EMPTY CENTRALPROPTAG>");
	kv.GetString("unloaded", gS_ReplayStrings.sUnloaded, MAX_NAME_LENGTH, "<EMPTY UNLOADED>");

	char sFolder[PLATFORM_MAX_PATH];
	kv.GetString("replayfolder", sFolder, PLATFORM_MAX_PATH, "{SM}/data/replaybot");

	delete kv;

	if(StrContains(sFolder, "{SM}") != -1)
	{
		ReplaceString(sFolder, PLATFORM_MAX_PATH, "{SM}/", "");
		BuildPath(Path_SM, sFolder, PLATFORM_MAX_PATH, "%s", sFolder);
	}
	
	strcopy(gS_ReplayFolder, PLATFORM_MAX_PATH, sFolder);

	return true;
}

public void OnMapStart()
{
	if(!LoadStyling())
	{
		SetFailState("Could not load the replay bots' configuration file. Make sure it exists (addons/sourcemod/configs/proptricks-replay.cfg) and follows the proper syntax!");
	}

	// VERY RARE CASE
	// this is required to not cause replays to break if we change map before playback starts, after it is requested
	for(int i = 0; i < PROP_LIMIT; i++)
	{
		gH_ReplayTimers[i] = null;
	}

	if(gB_Late)
	{
		PropTricks_OnPropConfigLoaded(-1);
		PropTricks_GetChatStrings(gS_ChatStrings);
	}

	gA_CentralCache.iClient = -1;
	gA_CentralCache.iProp = -1;
	gA_CentralCache.iReplayStatus = Replay_Idle;
	gA_CentralCache.iTrack = Track;
	gA_CentralCache.iPlaybackSerial = 0;

	gB_ForciblyStopped = false;

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	char sTempMap[PLATFORM_MAX_PATH];
	FormatEx(sTempMap, PLATFORM_MAX_PATH, "maps/%s.nav", gS_Map);

	if(!FileExists(sTempMap))
	{
		if(!FileExists("maps/base.nav"))
		{
			SetFailState("Plugin startup FAILED: \"maps/base.nav\" does not exist.");
		}

		File_Copy("maps/base.nav", sTempMap);

		ForceChangeLevel(gS_Map, ".nav file generate");

		return;
	}

	ServerCommand("bot_kick");
	UpdateBotQuota(0);

	if(!DirExists(gS_ReplayFolder))
	{
		CreateDirectory(gS_ReplayFolder, 511);
	}

	for(int i = 0; i < gI_Props; i++)
	{
		gI_ReplayTick[i] = -1;
		gF_StartTick[i] = -65535.0;
		gRS_ReplayStatus[i] = Replay_Idle;

		char sPath[PLATFORM_MAX_PATH];
		FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d", gS_ReplayFolder, i);

		if(!DirExists(sPath))
		{
			CreateDirectory(sPath, 511);
		}

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			delete gA_Frames[i][j];
			gA_Frames[i][j] = new ArrayList(CELLS_PER_FRAME);
			gA_FrameCache[i][j].iFrameCount = 0;
			gA_FrameCache[i][j].fTime = 0.0;
			strcopy(gA_FrameCache[i][j].sReplayName, MAX_NAME_LENGTH, "invalid");
			gA_FrameCache[i][j].iPreFrames = 0;

			DefaultLoadReplay(i, j);
		}

		Call_StartForward(gH_OnReplaysLoaded);
		Call_Finish();
	}

	UpdateBotQuota(1);
	ServerCommand("bot_add");

	CreateTimer(3.0, Cron, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

int CreateReplayProp(int prop)
{
	int entity = CreateEntityByName("prop_physics");

	if(entity == -1)
	{
		LogError("\"prop_physics\" creation failed");
		return -1;
	}

	DispatchKeyValue(entity, "model", gS_PropStrings[prop].sModelPath);
	DispatchSpawn(entity);
	
	Call_StartForward(gH_OnReplayPropCreated);
	Call_PushCell(prop);
	Call_PushCell(entity);
	Call_Finish();
	
	SetEntProp(entity, Prop_Data, "m_CollisionGroup", 2);
	SetEntityMoveType(entity, MOVETYPE_NOCLIP);
	return entity;
}

public void PropTricks_OnReplayPropCreated(int prop, int entity)
{
	if(IsValidEdict(entity))
	{
		//if(gA_CentralCache.iClient != -1)
		SetEntPropEnt(entity, Prop_Send, "m_PredictableID", gA_CentralCache.iClient);
	}
}

void RemoveReplayProp(int prop)
{
	int entity = gI_ReplayProps[prop];
	if(IsValidEdict(entity))
	{
		AcceptEntityInput(entity, "Kill");
		gI_ReplayProps[prop] = -1;
	}
}

public Action OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
	return Plugin_Handled;
}

public void PropTricks_OnPropConfigLoaded(int props)
{
	if(props == -1)
	{
		props = PropTricks_GetPropCount();
	}

	for(int i = 0; i < props; i++)
	{
		//PropTricks_GetPropStrings(i, sClanTag, gS_PropStrings[i].sClanTag, sizeof(propstrings_t::sClanTag));
		PropTricks_GetPropStrings(i, sPropName, gS_PropStrings[i].sPropName, sizeof(propstrings_t::sPropName));
		PropTricks_GetPropStrings(i, sModelPath, gS_PropStrings[i].sModelPath, sizeof(propstrings_t::sModelPath));
		PropTricks_GetPropStrings(i, sShortName, gS_PropStrings[i].sShortName, sizeof(propstrings_t::sShortName));
	}

	gI_Props = props;
}

public void PropTricks_OnChatConfigLoaded(chatstrings_t strings)
{
	gS_ChatStrings = strings;
}

bool DefaultLoadReplay(int prop, int track)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, prop, gS_Map, sTrack);

	return LoadReplay(prop, track, sPath);
}

bool LoadCurrentReplayFormat(File file, int version, int prop, int track)
{
	char sMap[160];
	file.ReadString(sMap, 160);

	int iProp = 0;
	file.ReadUint8(iProp);

	int iTrack = 0;
	file.ReadUint8(iTrack);

	if(!StrEqual(sMap, gS_Map, false) || iProp != prop || iTrack != track)
	{
		delete file;
		
		return false;
	}
	
	file.ReadInt32(gA_FrameCache[prop][track].iPreFrames);

	// In case the replay was from when there could still be negative preframes
	if(gA_FrameCache[prop][track].iPreFrames < 0)
	{
		gA_FrameCache[prop][track].iPreFrames = 0;
	}

	int iTemp = 0;
	file.ReadInt32(iTemp);
	gA_FrameCache[prop][track].iFrameCount = iTemp;

	if(gA_Frames[prop][track] == null)
	{
		gA_Frames[prop][track] = new ArrayList(CELLS_PER_FRAME);
	}

	gA_Frames[prop][track].Resize(iTemp);

	file.ReadInt32(iTemp);
	gA_FrameCache[prop][track].fTime = view_as<float>(iTemp);

	int iSteamID = 0;
	file.ReadInt32(iSteamID);

	char sQuery[192];
	FormatEx(sQuery, 192, "SELECT name FROM users WHERE auth = %d;", iSteamID);

	DataPack hPack = new DataPack();
	hPack.WriteCell(prop);
	hPack.WriteCell(track);

	gH_SQL.Query(SQL_GetUserName_Callback, sQuery, hPack, DBPrio_High);

	int cells = CELLS_PER_FRAME;


	any[] aReplayData = new any[cells];

	for(int i = 0; i < gA_FrameCache[prop][track].iFrameCount; i++)
	{
		if(file.Read(aReplayData, cells, 4) >= 0)
		{
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[0]), 0);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[1]), 1);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[2]), 2);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[3]), 3);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[4]), 4);
			gA_Frames[prop][track].Set(i, view_as<int>(aReplayData[5]), 5);
			gA_Frames[prop][track].Set(i, view_as<int>(aReplayData[6]), 6);
			gA_Frames[prop][track].Set(i, view_as<int>(aReplayData[7]), 7);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[8]), 8);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[9]), 9);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[10]), 10);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[11]), 11);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[12]), 12);
			gA_Frames[prop][track].Set(i, view_as<float>(aReplayData[13]), 13);
		}
	}

	delete file;

	return true;
}

bool LoadReplay(int prop, int track, const char[] path)
{
	if(FileExists(path))
	{
		File fFile = OpenFile(path, "rb");

		char sHeader[64];

		if(!fFile.ReadLine(sHeader, 64))
		{
			delete fFile;

			return false;
		}

		TrimString(sHeader);
		char sExplodedHeader[2][64];
		ExplodeString(sHeader, ":", sExplodedHeader, 2, 64);

		if(StrEqual(sExplodedHeader[1], REPLAY_FORMAT_V1)) // hopefully, the last of them
		{
			return LoadCurrentReplayFormat(fFile, StringToInt(sExplodedHeader[0]), prop, track);
		}
	}

	return false;
}

bool SaveReplay(int prop, int track, float time, int steamid, char[] name, int preframes, ArrayList playerrecording, int timerstartframe)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, prop, gS_Map, sTrack);

	if(FileExists(sPath))
	{
		DeleteFile(sPath);
	}

	File fFile = OpenFile(sPath, "wb");
	fFile.WriteLine("%d:" ... REPLAY_FORMAT_V1, REPLAY_FORMAT_SUBVERSION);

	fFile.WriteString(gS_Map, true);
	fFile.WriteInt8(prop);
	fFile.WriteInt8(track);
	fFile.WriteInt32(timerstartframe - preframes);

	int iSize = playerrecording.Length;
	fFile.WriteInt32(iSize - preframes);
	fFile.WriteInt32(view_as<int>(time));
	fFile.WriteInt32(steamid);

	any aFrameData[CELLS_PER_FRAME];
	any aWriteData[CELLS_PER_FRAME * FRAMES_PER_WRITE];
	int iFramesWritten = 0;

	// How did I trigger this?
	if(gA_Frames[prop][track] == null)
	{
		gA_Frames[prop][track] = new ArrayList(CELLS_PER_FRAME);
	}
	else
	{
		gA_Frames[prop][track].Clear();
	}


	for(int i = preframes; i < iSize; i++)
	{
		playerrecording.GetArray(i, aFrameData, CELLS_PER_FRAME);
		gA_Frames[prop][track].PushArray(aFrameData);
		for(int j = 0; j < CELLS_PER_FRAME; j++)
		{
			aWriteData[(CELLS_PER_FRAME * iFramesWritten) + j] = aFrameData[j];
		}

		if(++iFramesWritten == FRAMES_PER_WRITE || i == iSize - 1)
		{
			fFile.Write(aWriteData, CELLS_PER_FRAME * iFramesWritten, 4);

			iFramesWritten = 0;
		}
	}

	delete fFile;

	gA_FrameCache[prop][track].iFrameCount = iSize - preframes;
	gA_FrameCache[prop][track].fTime = time;
	strcopy(gA_FrameCache[prop][track].sReplayName, MAX_NAME_LENGTH, name);
	gA_FrameCache[prop][track].iPreFrames = timerstartframe - preframes;
	
	return true;
}

bool DeleteReplay(int prop, int track, bool unload_replay = false, int accountid = 0)
{
	char sTrack[4];
	FormatEx(sTrack, 4, "_%d", track);

	char sPath[PLATFORM_MAX_PATH];
	FormatEx(sPath, PLATFORM_MAX_PATH, "%s/%d/%s%s.replay", gS_ReplayFolder, prop, gS_Map, sTrack);

	if(!FileExists(sPath))
	{
		return false;
	}

	if(accountid != 0)
	{
		File file = OpenFile(sPath, "wb");

		char szTemp[160];
		file.ReadString(szTemp, 160);

		int iTemp = 0;
		file.ReadUint8(iTemp);
		file.ReadUint8(iTemp);
		file.ReadInt32(iTemp);
		file.ReadInt32(iTemp);

		int iSteamID = 0;
		file.ReadInt32(iSteamID);

		delete file;
		
		if(accountid == iSteamID && !DeleteFile(sPath))
		{
			return false;
		}
	}
	else 
	{
		if(!DeleteFile(sPath))
		{
			return false;
		}
	}

	if(unload_replay)
	{
		UnloadReplay(prop, track);
	}

	return true;
}

public void SQL_GetUserName_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int prop = data.ReadCell();
	int track = data.ReadCell();
	delete data;

	if(results == null)
	{
		LogError("Timer error! Get user name (replay) failed. Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		results.FetchString(0, gA_FrameCache[prop][track].sReplayName, MAX_NAME_LENGTH);
	}
}

public void OnClientPutInServer(int client)
{
	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		delete gA_PlayerFrames[client];
		gA_PlayerFrames[client] = new ArrayList(CELLS_PER_FRAME);
	}
	else
	{
		if(gA_CentralCache.iClient == -1)
		{
			UpdateReplayInfo(client, 0, 0.0, Track);
			gA_CentralCache.iClient = client;
		}
	}
}

public void OnEntityCreated(int entity, const char[] classname)
{
	// trigger_once | trigger_multiple.. etc
	// func_door | func_door_rotating
	if(StrContains(classname, "trigger_") != -1 || StrContains(classname, "_door") != -1)
	{
		SDKHook(entity, SDKHook_StartTouch, HookTriggers);
		SDKHook(entity, SDKHook_EndTouch, HookTriggers);
		SDKHook(entity, SDKHook_Touch, HookTriggers);
		SDKHook(entity, SDKHook_Use, HookTriggers);
	}
}

public Action HookTriggers(int entity, int other)
{
	if(gCV_Enabled.BoolValue && 1 <= other <= MaxClients && IsFakeClient(other))
	{
		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void FormatProp(const char[] source, int prop, bool central, float time, int track, char[] dest, int size)
{
	float fWRTime = GetReplayLength(prop, track);

	char sTime[16];
	FormatSeconds((time == -1.0)? fWRTime:time, sTime, 16);

	char sName[MAX_NAME_LENGTH];
	GetReplayName(prop, track, sName, MAX_NAME_LENGTH);
	
	char[] temp = new char[size];
	strcopy(temp, size, source);

	ReplaceString(temp, size, "{map}", gS_Map);

	if(central && gA_CentralCache.iReplayStatus == Replay_Idle)
	{
		ReplaceString(temp, size, "{prop}", gS_ReplayStrings.sCentralProp);
		ReplaceString(temp, size, "{proptag}", gS_ReplayStrings.sCentralPropTag);
	}

	else
	{
		ReplaceString(temp, size, "{prop}", gS_PropStrings[prop].sPropName);
		//ReplaceString(temp, size, "{proptag}", gS_PropStrings[prop].sClanTag);
	}
	
	ReplaceString(temp, size, "{time}", sTime);
	ReplaceString(temp, size, "{player}", sName);

	char sTrack[32];
	GetTrackName(LANG_SERVER, track, sTrack, 32);
	ReplaceString(temp, size, "{track}", sTrack);

	strcopy(dest, size, temp);
}

void UpdateReplayInfo(int client, int prop, float time, int track)
{
	if(!gCV_Enabled.BoolValue || !IsValidClient(client) || !IsFakeClient(client))
	{
		return;
	}

	SetEntProp(client, Prop_Data, "m_CollisionGroup", 2);
	SetEntityMoveType(client, MOVETYPE_NOCLIP);

	bool central = (gA_CentralCache.iClient == client);
	bool idle = (central && gA_CentralCache.iReplayStatus == Replay_Idle);

	char sTag[MAX_NAME_LENGTH];
	FormatProp(gS_ReplayStrings.sClanTag, prop, central, time, track, sTag, MAX_NAME_LENGTH);
	CS_SetClientClanTag(client, sTag);

	char sName[MAX_NAME_LENGTH];
	int iFrameCount = gA_FrameCache[prop][track].iFrameCount;
	
	if(central || iFrameCount > 0)
	{
		if(idle)
		{
			FormatProp(gS_ReplayStrings.sCentralName, prop, central, time, track, sName, MAX_NAME_LENGTH);
		}
		
		else
		{
			FormatProp(gS_ReplayStrings.sNameProp, prop, central, time, track, sName, MAX_NAME_LENGTH);
		}
	}

	else
	{
		FormatProp(gS_ReplayStrings.sUnloaded, prop, central, time, track, sName, MAX_NAME_LENGTH);
	}

	gB_HideNameChange = true;
	SetClientName(client, sName);

	int iScore = (iFrameCount > 0 || client == gA_CentralCache.iClient)? 2000:-2000;

	SetEntProp(client, Prop_Data, "m_iFrags", iScore);
	SetEntProp(client, Prop_Data, "m_iDeaths", 0);

	gB_DontCallTimer = true;

	if(!IsPlayerAlive(client))
	{
		CS_RespawnPlayer(client);
	}

	else
	{
		int iFlags = GetEntityFlags(client);

		if((iFlags & FL_ATCONTROLS) == 0)
		{
			SetEntityFlags(client, (iFlags | FL_ATCONTROLS));
		}
	}

	char sWeapon[32];
	gCV_BotWeapon.GetString(sWeapon, 32);

	if(strlen(sWeapon) > 0)
	{
		int iWeapon = GetEntPropEnt(client, Prop_Data, "m_hActiveWeapon");

		if(StrEqual(sWeapon, "none"))
		{
			if(iWeapon != -1 && IsValidEntity(iWeapon))
			{
				CS_DropWeapon(client, iWeapon, false);
				AcceptEntityInput(iWeapon, "Kill");
			}
		}

		else
		{
			char sClassname[32];

			if(iWeapon != -1 && IsValidEntity(iWeapon))
			{
				GetEntityClassname(iWeapon, sClassname, 32);

				if(!StrEqual(sWeapon, sClassname))
				{
					CS_DropWeapon(client, iWeapon, false);
					AcceptEntityInput(iWeapon, "Kill");
				}
			}

			else
			{
				GivePlayerItem(client, sWeapon);
			}
		}
	}

	if(GetClientTeam(client) != gCV_DefaultTeam.IntValue)
	{
		CS_SwitchTeam(client, gCV_DefaultTeam.IntValue);
	}
}

public void OnClientDisconnect(int client)
{
	if(IsClientSourceTV(client))
	{
		return;
	}

	if(!IsFakeClient(client))
	{
		ClearFrames(client);
		RequestFrame(DeleteFrames, client);
		ClearFrames(client);

		return;
	}

	if(gA_CentralCache.iClient == client)
	{
		gA_CentralCache.iClient = -1;

		return;
	}

	for(int i = 0; i < gI_Props; i++)
	{
		if(client == gI_ReplayBotClient[i])
		{
			gI_ReplayBotClient[i] = 0;

			break;
		}
	}
}

public void DeleteFrames(int client)
{
	delete gA_PlayerFrames[client];
}

public Action PropTricks_OnStart(int client)
{	
	gI_PlayerPrerunFrames[client] = gA_PlayerFrames[client].Length - RoundToFloor(gCV_PlaybackPreRunTime.FloatValue * gF_Tickrate);
	if(gI_PlayerPrerunFrames[client] < 0)
	{
		gI_PlayerPrerunFrames[client] = 0;
	}
	gI_PlayerTimerStartFrames[client] = gA_PlayerFrames[client].Length;

	if(!gB_ClearFrame[client])
	{
		if(!gCV_ClearPreRun.BoolValue)
		{
			ClearFrames(client);
		}
		gB_ClearFrame[client] = true;
	}

	else 
	{
		if(gA_PlayerFrames[client].Length >= RoundToFloor(gCV_PlaybackPreRunTime.FloatValue * gF_Tickrate))
		{
			gA_PlayerFrames[client].Erase(0);
			gI_PlayerFrames[client]--;
		}
	}

	return Plugin_Continue;
}

public void PropTricks_OnStop(int client)
{
	ClearFrames(client);
}

public void PropTricks_OnLeaveZone(int client, int type, int track, int id, int entity)
{
	if(type == Zone_Start)
	{
		gB_ClearFrame[client] = false;
	}
}

public void PropTricks_OnFinish(int client, int prop, float time, int track)
{
	if(!gCV_Enabled.BoolValue || (gCV_TimeLimit.FloatValue > 0.0 && time > gCV_TimeLimit.FloatValue))
	{
		return;
	}

	float length = GetReplayLength(prop, track);

	if(length > 0.0 && time > length)
	{
		return;
	}

	if(gI_PlayerFrames[client] == 0)
	{
		return;
	}
	
	int iSteamID = GetSteamAccountID(client);

	char sName[MAX_NAME_LENGTH];
	GetClientName(client, sName, MAX_NAME_LENGTH);
	ReplaceString(sName, MAX_NAME_LENGTH, "#", "?");

	SaveReplay(prop, track, time, iSteamID, sName, gI_PlayerPrerunFrames[client], gA_PlayerFrames[client], gI_PlayerTimerStartFrames[client]);

	if(gA_CentralCache.iProp == prop && gA_CentralCache.iTrack == track)
	{
		StopCentralReplay(0);
	}

	ClearFrames(client);
}

void ApplyFlags(int &flags1, int flags2, int flag)
{
	if((flags2 & flag) > 0)
	{
		flags1 |= flag;
	}

	else
	{
		flags2 &= ~flag;
	}
}

// OnPlayerRunCmd instead of PropTricks_OnUserCmdPre because bots are also used here.
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3])
{
	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(!IsPlayerAlive(client))
	{
		if((buttons & IN_USE) > 0)
		{
			if(!gB_Button[client] && GetSpectatorTarget(client) == gA_CentralCache.iClient)
			{
				OpenReplayMenu(client);
			}

			gB_Button[client] = true;
		}

		else
		{
			gB_Button[client] = false;
		}

		return Plugin_Continue;
	}


	float vecCurrentPosition[3], vecEyes[3], vecPropCurrentPosition[3], vecPropEyes[3];

	GetClientAbsOrigin(client, vecCurrentPosition);
	GetClientEyeAngles(client, vecEyes);

	int propindex = PropTricks_GetPropEntityIndex(client);

	if(propindex != -1)
	{
		GetEntPropVector(propindex, Prop_Data, "m_vecAbsOrigin", vecPropCurrentPosition);
		//PrintToChatAll("%f %f %f", vecPropCurrentPosition[0], vecPropCurrentPosition[1], vecPropCurrentPosition[2]);
		GetEntPropVector(propindex, Prop_Data, "m_angRotation", vecPropEyes); 
	}

	int prop = GetReplayProp(client);
	int track = GetReplayTrack(client);

	if(prop != -1)
	{
		int entity = gI_ReplayProps[prop];
		
		if(entity != 0 && IsValidEntity(entity))
		{
			buttons = 0;

			vel[0] = 0.0;
			vel[1] = 0.0;

			if(gA_Frames[prop][track] == null || gA_FrameCache[prop][track].iFrameCount <= 0) // if no replay is loaded
			{
				return Plugin_Changed;
			}

			if(gI_ReplayTick[prop] != -1 && gA_FrameCache[prop][track].iFrameCount >= 1)
			{
				float vecPosition[3];
				float vecAngles[3];
				float vecPropPosition[3];
				float vecPropAngles[3];

				if(gRS_ReplayStatus[prop] != Replay_Running)
				{
					bool bStart = (gRS_ReplayStatus[prop] == Replay_Start);

					int iFrame = (bStart)? 0:(gA_FrameCache[prop][track].iFrameCount - 1);

					vecPosition[0] = gA_Frames[prop][track].Get(iFrame, 0);
					vecPosition[1] = gA_Frames[prop][track].Get(iFrame, 1);
					vecPosition[2] = gA_Frames[prop][track].Get(iFrame, 2);

					vecAngles[0] = gA_Frames[prop][track].Get(iFrame, 3);
					vecAngles[1] = gA_Frames[prop][track].Get(iFrame, 4);

					vecPropPosition[0] = gA_Frames[prop][track].Get(iFrame, 8);
					vecPropPosition[1] = gA_Frames[prop][track].Get(iFrame, 9);
					vecPropPosition[2] = gA_Frames[prop][track].Get(iFrame, 10);

					vecPropAngles[0] = gA_Frames[prop][track].Get(iFrame, 11);
					vecPropAngles[1] = gA_Frames[prop][track].Get(iFrame, 12);
					vecPropAngles[2] = gA_Frames[prop][track].Get(iFrame, 13);
					
					if(bStart)
					{
						TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));
						TeleportEntity(entity, vecPropPosition, vecPropAngles, view_as<float>({0.0, 0.0, 0.0}));
					}

					else
					{
						float vecVelocity[3];//, vecPropVelocity[3];, vecPropAngularVelocity[3];
						
						MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
						ScaleVector(vecVelocity, gF_Tickrate);
						
						/*MakeVectorFromPoints(vecPropCurrentPosition, vecPropPosition, vecPropVelocity);
						ScaleVector(vecPropVelocity, gF_Tickrate);
						
						MakeVectorFromPoints(vecPropEyes, vecPropAngles, vecPropAngularVelocity);
						ScaleVector(vecPropAngularVelocity, gF_Tickrate);*/
						
						TeleportEntity(client, NULL_VECTOR, NULL_VECTOR, vecVelocity);
						TeleportEntity(entity, vecPropPosition, vecPropAngles, NULL_VECTOR);
						//Phys_SetVelocity(entity, vecPropVelocity, NULL_VECTOR);
					}

					return Plugin_Changed;
				}

				if(gI_ReplayTick[prop] >= gA_FrameCache[prop][track].iPreFrames)
				{
					++gI_TimerTick[prop];
				}			

				if(++gI_ReplayTick[prop] >= gA_FrameCache[prop][track].iFrameCount - 1)
				{
					gI_ReplayTick[prop] = 0;
					gI_TimerTick[prop] = 0;
					gRS_ReplayStatus[prop] = gA_CentralCache.iReplayStatus = Replay_End;

					delete gH_ReplayTimers[prop];
					gH_ReplayTimers[prop] = CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_EndReplay, prop, TIMER_FLAG_NO_MAPCHANGE);
					gA_CentralCache.iPlaybackSerial = 0;

					return Plugin_Changed;
				}

				if(gI_ReplayTick[prop] == 1)
				{
					gF_StartTick[prop] = GetEngineTime();
				}

				vecPosition[0] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 0);
				vecPosition[1] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 1);
				vecPosition[2] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 2);

				vecAngles[0] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 3);
				vecAngles[1] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 4);

				vecPropPosition[0] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 8);
				vecPropPosition[1] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 9);
				vecPropPosition[2] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 10);

				vecPropAngles[0] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 11);
				vecPropAngles[1] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 12);
				vecPropAngles[2] = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 13);

				buttons = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 5);

				if((gCV_BotShooting.IntValue & iBotShooting_Attack1) == 0)
				{
					buttons &= ~IN_ATTACK;
				}

				if((gCV_BotShooting.IntValue & iBotShooting_Attack2) == 0)
				{
					buttons &= ~IN_ATTACK2;
				}

				if(!gCV_BotPlusUse.BoolValue)
				{
					buttons &= ~IN_USE;
				}

				bool bWalk = false;
				MoveType mt = MOVETYPE_NOCLIP;

				int iReplayFlags = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 6);
				int iEntityFlags = GetEntityFlags(client);

				ApplyFlags(iEntityFlags, iReplayFlags, FL_ONGROUND);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_PARTIALGROUND);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_INWATER);
				ApplyFlags(iEntityFlags, iReplayFlags, FL_SWIM);

				SetEntityFlags(client, iEntityFlags);
				
				MoveType movetype = gA_Frames[prop][track].Get(gI_ReplayTick[prop], 7);

				if(movetype == MOVETYPE_LADDER)
				{
					mt = movetype;
				}

				else if(movetype == MOVETYPE_WALK && (iReplayFlags & FL_ONGROUND) > 0)
				{
					bWalk = true;
				}

				SetEntityMoveType(client, mt);

				float vecVelocity[3];//, vecPropVelocity[3];, vecPropAngularVelocity[3];
				
				MakeVectorFromPoints(vecCurrentPosition, vecPosition, vecVelocity);
				ScaleVector(vecVelocity, gF_Tickrate);
				
				/*MakeVectorFromPoints(vecPropCurrentPosition, vecPropPosition, vecPropVelocity);
				ScaleVector(vecPropVelocity, gF_Tickrate);
				
				MakeVectorFromPoints(vecPropEyes, vecPropAngles, vecPropAngularVelocity);
				ScaleVector(vecPropAngularVelocity, gF_Tickrate);*/

				if(gI_ReplayTick[prop] > 1 &&
					// replay is going above 50k speed, just teleport at this point
					(GetVectorLength(vecVelocity) > 50000.0 ||
					// bot is on ground.. if the distance between the previous position is much bigger (1.5x) than the expected according
					// to the bot's velocity, teleport to avoid sync issues
					(bWalk && GetVectorDistance(vecCurrentPosition, vecPosition) > GetVectorLength(vecVelocity) / gF_Tickrate * 1.5)))
				{
					TeleportEntity(client, vecPosition, vecAngles, NULL_VECTOR);
					TeleportEntity(entity, vecPropPosition, vecPropAngles, NULL_VECTOR);

					return Plugin_Changed;
				}

				TeleportEntity(client, NULL_VECTOR, vecAngles, vecVelocity);
				TeleportEntity(entity, vecPropPosition, vecPropAngles, NULL_VECTOR);
				//Phys_SetVelocity(entity, vecPropVelocity, NULL_VECTOR);

				return Plugin_Changed;
			}
		}
	}

	else if(PropTricks_GetTimerStatus(client) == Timer_Running)
	{
		gA_PlayerFrames[client].Resize(gI_PlayerFrames[client] + 1);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[0], 0);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[1], 1);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecCurrentPosition[2], 2);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecEyes[0], 3);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecEyes[1], 4);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], buttons, 5);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], GetEntityFlags(client), 6);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], GetEntityMoveType(client), 7);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecPropCurrentPosition[0], 8);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecPropCurrentPosition[1], 9);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecPropCurrentPosition[2], 10);

		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecPropEyes[0], 11);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecPropEyes[1], 12);
		gA_PlayerFrames[client].Set(gI_PlayerFrames[client], vecPropEyes[2], 13);


		gI_PlayerFrames[client]++;
	}

	return Plugin_Continue;
}

public Action Timer_EndReplay(Handle Timer, any data)
{
	gH_ReplayTimers[data] = null;

	int client = GetClientFromSerial(gA_CentralCache.iPlaybackSerial);

	if(client != 0)
	{
		gF_LastInteraction[client] = GetEngineTime();
	}

	gA_CentralCache.iPlaybackSerial = 0;

	if(gB_ForciblyStopped)
	{
		gB_ForciblyStopped = false;

		return Plugin_Stop;
	}
	
	if(gI_ReplayProps[data] != -1)
	{
		PrintToServer("Replay Prop Removed: %d", gI_ReplayProps[data]);
		RemoveReplayProp(data);
	}

	gI_ReplayTick[data] = 0;

	Call_StartForward(gH_OnReplayEnd);
	Call_PushCell(gI_ReplayBotClient[data]);
	Call_Finish();

	if(gI_ReplayBotClient[data] != gA_CentralCache.iClient)
	{
		gRS_ReplayStatus[data] = Replay_Start;

		delete gH_ReplayTimers[data];
		gH_ReplayTimers[data] = CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, data, TIMER_FLAG_NO_MAPCHANGE);
	}

	else
	{
		gRS_ReplayStatus[data] = gA_CentralCache.iReplayStatus = Replay_Idle;
		gI_ReplayBotClient[data] = 0;
	}

	return Plugin_Stop;
}

public Action Timer_StartReplay(Handle Timer, any data)
{
	gH_ReplayTimers[data] = null;

	if(gRS_ReplayStatus[data] == Replay_Running || gB_ForciblyStopped)
	{
		return Plugin_Stop;
	}

	Call_StartForward(gH_OnReplayStart);
	Call_PushCell(gI_ReplayBotClient[data]);
	Call_Finish();

	gRS_ReplayStatus[data] = gA_CentralCache.iReplayStatus = Replay_Running;

	return Plugin_Stop;
}

public void Player_Event(Event event, const char[] name, bool dontBroadcast)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client))
	{
		event.BroadcastDisabled = true;

		if(!gB_DontCallTimer)
		{
			CreateTimer(0.10, DelayedUpdate, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
		}

		gB_DontCallTimer = false;
	}
}

public Action DelayedUpdate(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return Plugin_Stop;
	}

	UpdateReplayInfo(client, GetReplayProp(client), -1.0, GetReplayTrack(client));

	return Plugin_Stop;
}

public Action BotEvents(Event event, const char[] name, bool dontBroadcast)
{
	if(!gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	if(event.GetBool("bot"))
	{
		int client = GetClientOfUserId(event.GetInt("userid"));

		if(1 <= client <= MaxClients && IsClientInGame(client) && IsFakeClient(client) && !IsClientSourceTV(client))
		{
			int iProp = GetReplayProp(client);

			if(iProp != -1)
			{
				UpdateReplayInfo(client, iProp, -1.0, GetReplayTrack(client));
			}
		}

		event.BroadcastDisabled = true;

		return Plugin_Changed;
	}

	return Plugin_Continue;
}

public Action Hook_SayText2(UserMsg msg_id, any msg, const int[] players, int playersNum, bool reliable, bool init)
{
	if(!gB_HideNameChange || !gCV_Enabled.BoolValue)
	{
		return Plugin_Continue;
	}

	// caching usermessage type rather than call it every time
	static UserMessageType um = view_as<UserMessageType>(-1);

	if(um == view_as<UserMessageType>(-1))
	{
		um = GetUserMessageType();
	}

	char sMessage[24];

	if(um == UM_Protobuf)
	{
		Protobuf pbmsg = msg;
		pbmsg.ReadString("msg_name", sMessage, 24);
		delete pbmsg;
	}

	else
	{
		BfRead bfmsg = msg;
		bfmsg.ReadByte();
		bfmsg.ReadByte();
		bfmsg.ReadString(sMessage, 24);
		delete bfmsg;
	}

	if(StrEqual(sMessage, "#Cstrike_Name_Change"))
	{
		gB_HideNameChange = false;

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void ClearFrames(int client)
{
	if(gA_PlayerFrames[client])
	{
		gA_PlayerFrames[client].Clear();
	}
	gI_PlayerFrames[client] = 0;
	gI_PlayerPrerunFrames[client] = 0;
	gI_PlayerTimerStartFrames[client] = 0;
}

public void PropTricks_OnWRDeleted(int prop, int id, int track, int accountid)
{
	float time = PropTricks_GetWorldRecord(prop, track);

	if(gA_FrameCache[prop][track].iFrameCount > 0 && GetReplayLength(prop, track) - gF_Tickrate <= time) // -0.1 to fix rounding issues
	{
		DeleteReplay(prop, track, true, accountid);
	}
}

public Action Command_DeleteReplay(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(DeleteReplay_Callback);
	menu.SetTitle("%T", "DeleteReplayMenuTitle", client);

	for(int iProp = 0; iProp < gI_Props; iProp++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			if(gA_FrameCache[iProp][j].iFrameCount == 0)
			{
				continue;
			}

			char sInfo[8];
			FormatEx(sInfo, 8, "%d;%d", iProp, j);

			float time = GetReplayLength(iProp, j);

			char sTrack[32];
			GetTrackName(client, j, sTrack, 32);

			char sDisplay[64];

			if(time > 0.0)
			{
				char sTime[32];
				FormatSeconds(time, sTime, 32, false);

				FormatEx(sDisplay, 64, "%s (%s) - %s", gS_PropStrings[iProp].sPropName, sTrack, sTime);
			}

			else
			{
				FormatEx(sDisplay, 64, "%s (%s)", gS_PropStrings[iProp].sPropName, sTrack);
			}

			menu.AddItem(sInfo, sDisplay);
		}
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "ReplaysUnavailable", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 20);

	return Plugin_Handled;
}

public int DeleteReplay_Callback(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		char sExploded[2][4];
		ExplodeString(sInfo, ";", sExploded, 2, 4);
		
		int prop = StringToInt(sExploded[0]);

		if(prop == -1)
		{
			return 0;
		}

		gI_Track[param1] = StringToInt(sExploded[1]);

		Menu submenu = new Menu(DeleteConfirmation_Callback);
		submenu.SetTitle("%T", "ReplayDeletionConfirmation", param1, gS_PropStrings[prop].sPropName);

		char sMenuItem[64];

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", param1);
			submenu.AddItem("-1", sMenuItem);
		}

		FormatEx(sMenuItem, 64, "%T", "MenuResponseYes", param1);
		submenu.AddItem(sInfo, sMenuItem);

		for(int i = 1; i <= GetRandomInt(2, 4); i++)
		{
			FormatEx(sMenuItem, 64, "%T", "MenuResponseNo", param1);
			submenu.AddItem("-1", sMenuItem);
		}

		submenu.ExitButton = true;
		submenu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int DeleteConfirmation_Callback(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[4];
		menu.GetItem(param2, sInfo, 4);
		int prop = StringToInt(sInfo);

		if(DeleteReplay(prop, gI_Track[param1]))
		{
			char sTrack[32];
			GetTrackName(param1, gI_Track[param1], sTrack, 32);

			LogAction(param1, param1, "Deleted replay for %s on map %s. (Track: %s)", gS_PropStrings[prop].sPropName, gS_Map, sTrack);

			PropTricks_PrintToChat(param1, "%T (%s%s%s)", "ReplayDeleted", param1, gS_ChatStrings.sProp, gS_PropStrings[prop].sPropName, gS_ChatStrings.sText, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
		}

		else
		{
			PropTricks_PrintToChat(param1, "%T", "ReplayDeleteFailure", param1, gS_ChatStrings.sProp, gS_PropStrings[prop].sPropName, gS_ChatStrings.sText);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Replay(int client, int args)
{
	if(!IsValidClient(client) || gA_CentralCache.iClient == -1)
	{
		return Plugin_Handled;
	}

	if(GetClientTeam(client) > 1)
	{
		ChangeClientTeam(client, CS_TEAM_SPECTATOR);
	}

	SetEntPropEnt(client, Prop_Send, "m_hObserverTarget", gA_CentralCache.iClient);

	if(CanStopCentral(client))
	{
		char arg[8];
		GetCmdArg(1, arg, 8);

		if(StrEqual(arg, "stop"))
		{
			StopCentralReplay(client);

			return Plugin_Handled;
		}
	}

	return OpenReplayMenu(client);
}

Action OpenReplayMenu(int client)
{
	Menu menu = new Menu(MenuHandler_Replay);
	menu.SetTitle("%T\n ", "CentralReplayTrack", client);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		bool records = false;

		for(int j = 0; j < gI_Props; j++)
		{
			if(gA_FrameCache[j][i].iFrameCount > 0)
			{
				records = true;

				continue;
			}
		}

		char sInfo[8];
		IntToString(i, sInfo, 8);

		char sTrack[32];
		GetTrackName(client, i, sTrack, 32);

		menu.AddItem(sInfo, sTrack, (records)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	menu.ExitButton = true;
	menu.Display(client, 60);

	return Plugin_Handled;
}

public int MenuHandler_Replay(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		// avoid an exploit
		if(param2 >= 0 && param2 < TRACKS_SIZE)
		{
			OpenReplaySubMenu(param1, param2);
		}
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void OpenReplaySubMenu(int client, int track, int item = 0)
{
	gI_Track[client] = track;

	char sTrack[32];
	GetTrackName(client, track, sTrack, 32);

	Menu menu = new Menu(MenuHandler_ReplaySubmenu);
	menu.SetTitle("%T (%s)\n ", "CentralReplayTitle", client, sTrack);

	if(CanStopCentral(client))
	{
		char sDisplay[64];
		FormatEx(sDisplay, 64, "%T", "CentralReplayStop", client);

		menu.AddItem("stop", sDisplay, (gA_CentralCache.iReplayStatus != Replay_Idle)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	for(int iProp = 0; iProp < gI_Props; iProp++)
	{
		char sInfo[8];
		IntToString(iProp, sInfo, 8);

		float time = GetReplayLength(iProp, track);

		char sDisplay[64];

		if(time > 0.0)
		{
			char sTime[32];
			FormatSeconds(time, sTime, 32, false);

			FormatEx(sDisplay, 64, "%s - %s", gS_PropStrings[iProp].sPropName, sTime);
		}

		else
		{
			strcopy(sDisplay, 64, gS_PropStrings[iProp].sPropName);
		}

		menu.AddItem(sInfo, sDisplay, (gA_FrameCache[iProp][track].iFrameCount > 0)? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "ERROR");
	}

	menu.ExitBackButton = true;
	menu.DisplayAt(client, item, 60);
}

public int MenuHandler_ReplaySubmenu(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);

		if(StrEqual(info, "stop") && CanStopCentral(param1))
		{
			StopCentralReplay(param1);
			OpenReplaySubMenu(param1, gI_Track[param1]);

			return 0;
		}

		int prop = StringToInt(info);

		if(prop == -1 || gA_FrameCache[prop][gI_Track[param1]].iFrameCount == 0 || gA_CentralCache.iClient <= 0)
		{
			return 0;
		}

		if(gA_CentralCache.iReplayStatus != Replay_Idle)
		{
			PropTricks_PrintToChat(param1, "%T", "CentralReplayPlaying", param1);

			OpenReplaySubMenu(param1, gI_Track[param1], GetMenuSelectionPosition());
		}

		else
		{
			if(gI_ReplayProps[prop] == -1)
			{
				gI_ReplayProps[prop] = CreateReplayProp(prop);
				PrintToServer("Replay Prop Created: %d", gI_ReplayProps[prop]);
			}
			
			gI_ReplayTick[prop] = 0;
			gI_TimerTick[prop] = 0;
			gA_CentralCache.iProp = prop;
			gA_CentralCache.iTrack = gI_Track[param1];
			gA_CentralCache.iPlaybackSerial = GetClientSerial(param1);
			gF_LastInteraction[param1] = GetEngineTime();
			gI_ReplayBotClient[prop] = gA_CentralCache.iClient;
			gRS_ReplayStatus[prop] = gA_CentralCache.iReplayStatus = Replay_Start;
			TeleportToStart(gA_CentralCache.iClient, prop, gI_Track[param1]);
			gB_ForciblyStopped = false;

			float time = GetReplayLength(gA_CentralCache.iProp, gI_Track[param1]);

			UpdateReplayInfo(gA_CentralCache.iClient, prop, time, gI_Track[param1]);

			delete gH_ReplayTimers[prop];
			gH_ReplayTimers[prop] = CreateTimer((gCV_ReplayDelay.FloatValue / 2.0), Timer_StartReplay, prop, TIMER_FLAG_NO_MAPCHANGE);
		}
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenReplayMenu(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

bool CanStopCentral(int client)
{
	return (CheckCommandAccess(client, "sm_deletereplay", ADMFLAG_RCON) ||
			(gCV_PlaybackCanStop.BoolValue &&
			GetClientSerial(client) == gA_CentralCache.iPlaybackSerial &&
			GetEngineTime() - gF_LastInteraction[client] > gCV_PlaybackCooldown.FloatValue));
}

void TeleportToStart(int client, int prop, int track)
{
	if(gA_FrameCache[prop][track].iFrameCount == 0)
	{
		return;
	}

	float vecPosition[3];
	vecPosition[0] = gA_Frames[prop][track].Get(0, 0);
	vecPosition[1] = gA_Frames[prop][track].Get(0, 1);
	vecPosition[2] = gA_Frames[prop][track].Get(0, 2);

	float vecAngles[3];
	vecAngles[0] = gA_Frames[prop][track].Get(0, 3);
	vecAngles[1] = gA_Frames[prop][track].Get(0, 4);

	int entity = gI_ReplayProps[prop];

	float vecPropPosition[3];
	vecPropPosition[0] = gA_Frames[prop][track].Get(0, 8);
	vecPropPosition[1] = gA_Frames[prop][track].Get(0, 9);
	vecPropPosition[2] = gA_Frames[prop][track].Get(0, 10);

	float vecPropAngles[3];
	vecPropAngles[0] = gA_Frames[prop][track].Get(0, 11);
	vecPropAngles[1] = gA_Frames[prop][track].Get(0, 12);
	vecPropAngles[2] = gA_Frames[prop][track].Get(0, 13);

	TeleportEntity(client, vecPosition, vecAngles, view_as<float>({0.0, 0.0, 0.0}));
	TeleportEntity(entity, vecPropPosition, vecPropAngles, view_as<float>({0.0, 0.0, 0.0}));
}

void StopCentralReplay(int client)
{
	if(client > 0)
	{
		PropTricks_PrintToChat(client, "%T", "CentralReplayStopped", client);
	}

	int prop = gA_CentralCache.iProp;
	int player = GetClientFromSerial(gA_CentralCache.iPlaybackSerial);

	if(player != 0)
	{
		gF_LastInteraction[player] = GetEngineTime();
	}

	gRS_ReplayStatus[prop] = gA_CentralCache.iReplayStatus = Replay_Idle;
	gI_ReplayTick[prop] = 0;
	gI_ReplayBotClient[prop] = 0;
	gF_StartTick[prop] = -65535.0;
	gA_CentralCache.iProp = 0;
	gB_ForciblyStopped = true;
	gA_CentralCache.iPlaybackSerial = 0;

	if(gA_CentralCache.iClient != -1)
	{
		TeleportToStart(gA_CentralCache.iClient, prop, gA_CentralCache.iTrack);
	}
	
	if(gI_ReplayProps[prop] != -1)
	{
		PrintToServer("Replay Prop Removed: %d", gI_ReplayProps[prop]);
		RemoveReplayProp(prop);
	}

	UpdateReplayInfo(client, 0, 0.0, gA_CentralCache.iTrack);
}

int GetReplayProp(int client)
{
	if(!IsFakeClient(client) || IsClientSourceTV(client))
	{
		return -1;
	}
	if(gA_CentralCache.iProp == -1)
	{
		return 0;
	}

	return gA_CentralCache.iProp;
}

int GetReplayTrack(int client)
{
	if(!IsFakeClient(client) || IsClientSourceTV(client))
	{
		return -1;
	}

	return gA_CentralCache.iTrack;
}

float GetReplayLength(int prop, int track)
{
	if(gA_FrameCache[prop][track].iFrameCount == 0)
	{
		return 0.0;
	}
	
	return gA_FrameCache[prop][track].fTime;
}

void GetReplayName(int prop, int track, char[] buffer, int length)
{
	strcopy(buffer, length, gA_FrameCache[prop][track].sReplayName);
}

float GetClosestReplayTime(int client, int prop, int track)
{
	int iLength = gA_Frames[prop][track].Length;
	int iPreframes = gA_FrameCache[prop][track].iPreFrames;
	int iSearch = RoundToFloor(gCV_DynamicTimeSearch.FloatValue * (1.0 / GetTickInterval()));
	int iPlayerFrames = gA_PlayerFrames[client].Length - gI_PlayerPrerunFrames[client];
	
	int iStartFrame = iPlayerFrames - iSearch;
	int iEndFrame = iPlayerFrames + iSearch;
	
	if(iSearch == 0)
	{
		iStartFrame = 0;
		iEndFrame = iLength - 1;
	}

	else
	{
		// Check if the search behind flag is off
		if(iStartFrame < 0 || gCV_DynamicTimeCheap.IntValue & 2 == 0)
		{
			iStartFrame = 0;
		}
		
		// check if the search ahead flag is off
		if(iEndFrame >= iLength || gCV_DynamicTimeCheap.IntValue & 1 == 0)
		{
			iEndFrame = iLength - 1;
		}
	}


	float fReplayPos[3];
	int iClosestFrame;
	// Single.MaxValue
	float fMinDist = view_as<float>(0x7f7fffff);

	float fClientPos[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", fClientPos);

	for(int frame = iStartFrame; frame < iEndFrame; frame++)
	{
		gA_Frames[prop][track].GetArray(frame, fReplayPos, 3);

		float dist = GetVectorDistance(fClientPos, fReplayPos, true);
		if(dist < fMinDist)
		{
			fMinDist = dist;
			iClosestFrame = frame;
		}
	}


	// out of bounds
	if(iClosestFrame == 0 || iClosestFrame == iEndFrame)
	{
		return -1.0;
	}
	
	// inside start zone
	if(iClosestFrame < iPreframes)
	{
		return 0.0;
	}

	float frametime = GetReplayLength(prop, track) / float(gA_FrameCache[prop][track].iFrameCount - iPreframes);
	float timeDifference = (iClosestFrame - iPreframes)  * frametime;

	// Hides the hud if we are using the cheap search method and too far behind to be accurate
	if(iSearch > 0 && gCV_DynamicTimeCheap.BoolValue)
	{
		float preframes = float(gI_PlayerTimerStartFrames[client] - gI_PlayerPrerunFrames[client]) / (1.0 / GetTickInterval());
		if(PropTricks_GetClientTime(client) - timeDifference >= gCV_DynamicTimeSearch.FloatValue - preframes)
		{
			return -1.0;
		}
	}

	return timeDifference;
}

/*
 * Copies file source to destination
 * Based on code of javalia:
 * http://forums.alliedmods.net/showthread.php?t=159895
 *
 * @param source		Input file
 * @param destination	Output file
 */
bool File_Copy(const char[] source, const char[] destination)
{
	File file_source = OpenFile(source, "rb");

	if(file_source == null)
	{
		return false;
	}

	File file_destination = OpenFile(destination, "wb");

	if(file_destination == null)
	{
		delete file_source;

		return false;
	}

	int buffer[32];
	int cache = 0;

	while(!IsEndOfFile(file_source))
	{
		cache = ReadFile(file_source, buffer, 32, 1);

		file_destination.Write(buffer, cache, 1);
	}

	delete file_source;
	delete file_destination;

	return true;
}