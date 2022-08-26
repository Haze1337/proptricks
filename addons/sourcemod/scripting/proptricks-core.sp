#include <sourcemod>
#include <sdkhooks>
#include <clientprefs>
#include <dhooks>

#undef REQUIRE_EXTENSIONS
#include <vphysics>

#undef REQUIRE_PLUGIN
#define USES_CHAT_COLORS
#include <proptricks>

#pragma newdecls required
#pragma semicolon 1

enum struct playertimer_t
{
	bool bEnabled;
	bool bAuto;
	int iPushButton;
	float fTimer;
	int iProp;
	int iEntityIndex;
	int iTrack;
	float fTimeOffset[2];
	float fDistanceOffset[2];
	int iZoneIncrement;
}

// Database handle
Database gH_SQL = null;
bool gB_MySQL = false;

Handle gH_WorldSpaceCenter = null;

// Forwards
Handle gH_Forwards_OnStart = null;
Handle gH_Forwards_OnStop = null;
Handle gH_Forwards_OnStopPre = null;
Handle gH_Forwards_OnFinishPre = null;
Handle gH_Forwards_OnFinish = null;
Handle gH_Forwards_OnRestart = null;
Handle gH_Forwards_OnEnd = null;
Handle gH_Forwards_OnPropChanged = null;
Handle gH_Forwards_OnPropRemovePre = null;
Handle gH_Forwards_OnPropCreated = null;
Handle gH_Forwards_OnTrackChanged = null;
Handle gH_Forwards_OnPropConfigLoaded = null;
Handle gH_Forwards_OnDatabaseLoaded = null;
Handle gH_Forwards_OnChatConfigLoaded = null;
Handle gH_Forwards_OnUserCmdPre = null;
Handle gH_Forwards_OnTimeOffsetCalculated = null;
Handle gH_Forwards_OnProcessMovement = null;
Handle gH_Forwards_OnProcessMovementPost = null;
Handle gH_Forwards_OnPassEntityFilter = null;
Handle gH_Forwards_OnShouldCollide = null;
Handle gH_Forwards_OnPushToggle = null;
Handle gH_Forwards_OnPush = null;

StringMap gSM_PropCommands = null;

// Player timer variables
playertimer_t gA_Timers[MAXPLAYERS+1];

// Used for offsets
float gF_SmallestDist[MAXPLAYERS + 1];
float gF_Origin[MAXPLAYERS + 1][2][3];
float gF_Fraction[MAXPLAYERS + 1];

// Cookies
Handle gH_AutoBhopCookie = null;
Handle gH_PropCookie = null;
Handle gH_PushButtonCookie = null;

// Modules
bool gB_Zones = false;
bool gB_WR = false;
bool gB_Replay = false;
bool gB_Rankings = false;

// Cached cvars
bool gB_PropCookies = true;

// Server side
ConVar sv_turbophysics = null;
ConVar sv_pushaway_force = null;
ConVar sv_pushaway_max_force = null;

// Timer settings
bool gB_Registered = false;
int gI_Props = 0;
int gI_OrderedProps[PROP_LIMIT];
propstrings_t gS_PropStrings[PROP_LIMIT];
propsettings_t gA_PropSettings[PROP_LIMIT];

// Chat settings
chatstrings_t gS_ChatStrings;

// Misc cache
char gS_LogPath[PLATFORM_MAX_PATH];
char gS_DeleteMap[MAXPLAYERS+1][160];
int gI_WipePlayerID[MAXPLAYERS+1];
char gS_Verification[MAXPLAYERS+1][8];
bool gB_CookiesRetrieved[MAXPLAYERS+1];

// Late load
bool gB_Late = false;

#include "proptricks/core/core-sql.sp"
#include "proptricks/core/core-natives.sp"
#include "proptricks/core/core-dhooks.sp"
#include "proptricks/core/core-push.sp"
#include "proptricks/core/core-menus.sp"

public Plugin myinfo =
{
	name = "[PropTricks] Core",
	author = "Haze",
	description = "The core for proptricks timer.",
	version = PROPTRICKS_VERSION,
	url = ""
}

//Forwards
public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	Natives_Define();

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("proptricks");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	CoreDhooks_Init();

	gH_Forwards_OnStart = CreateGlobalForward("PropTricks_OnStart", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnStop = CreateGlobalForward("PropTricks_OnStop", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnStopPre = CreateGlobalForward("PropTricks_OnStopPre", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnFinishPre = CreateGlobalForward("PropTricks_OnFinishPre", ET_Event, Param_Cell);
	gH_Forwards_OnFinish = CreateGlobalForward("PropTricks_OnFinish", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnRestart = CreateGlobalForward("PropTricks_OnRestart", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnEnd = CreateGlobalForward("PropTricks_OnEnd", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnPropChanged = CreateGlobalForward("PropTricks_OnPropChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnPropRemovePre = CreateGlobalForward("PropTricks_OnPropRemovePre", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnPropCreated = CreateGlobalForward("PropTricks_OnPropCreated", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnTrackChanged = CreateGlobalForward("PropTricks_OnTrackChanged", ET_Event, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnPropConfigLoaded = CreateGlobalForward("PropTricks_OnPropConfigLoaded", ET_Event, Param_Cell);
	gH_Forwards_OnDatabaseLoaded = CreateGlobalForward("PropTricks_OnDatabaseLoaded", ET_Event);
	gH_Forwards_OnChatConfigLoaded = CreateGlobalForward("PropTricks_OnChatConfigLoaded", ET_Event, Param_Array);
	gH_Forwards_OnUserCmdPre = CreateGlobalForward("PropTricks_OnUserCmdPre", ET_Event, Param_Cell, Param_CellByRef, Param_CellByRef, Param_Array, Param_Array, Param_Cell, Param_Cell, Param_Cell, Param_Array, Param_Array);
	gH_Forwards_OnTimeOffsetCalculated = CreateGlobalForward("PropTricks_OnTimeOffsetCalculated", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnProcessMovement = CreateGlobalForward("PropTricks_OnProcessMovement", ET_Event, Param_Cell);
	gH_Forwards_OnProcessMovementPost = CreateGlobalForward("PropTricks_OnProcessMovementPost", ET_Event, Param_Cell);
	gH_Forwards_OnPassEntityFilter = CreateGlobalForward("PropTricks_OnPassEntityFilter", ET_Event, Param_Cell, Param_Cell , Param_CellByRef);
	gH_Forwards_OnShouldCollide = CreateGlobalForward("PropTricks_OnShouldCollide", ET_Event, Param_Cell, Param_Cell , Param_CellByRef);
	gH_Forwards_OnPushToggle = CreateGlobalForward("PropTricks_OnPushToggle", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnPush = CreateGlobalForward("PropTricks_OnPush", ET_Event, Param_Cell, Param_Cell, Param_Array, Param_Cell);

	LoadTranslations("proptricks-core.phrases");
	LoadTranslations("proptricks-common.phrases");

	if(GetEngineVersion() != Engine_CSS)
	{
		SetFailState("This plugin was meant to be used in CS:S *only*.");
	}

	// Events
	HookEvent("player_death", Event_PlayerDeath);
	HookEvent("player_team", Event_PlayerTeam);
	HookEvent("player_spawn", Event_PlayerSpawn);

	// Autobhop toggle
	RegConsoleCmd("sm_auto", Command_AutoBhop, "Toggle autobhop.");
	RegConsoleCmd("sm_autobhop", Command_AutoBhop, "Toggle autobhop.");
	gH_AutoBhopCookie = RegClientCookie("proptricks_autobhop", "Autobhop cookie", CookieAccess_Protected);

	// Timer start
	RegConsoleCmd("sm_s", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_start", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_r", Command_StartTimer, "Start your timer.");
	RegConsoleCmd("sm_restart", Command_StartTimer, "Start your timer.");

	// Timer stop
	RegConsoleCmd("sm_stop", Command_StopTimer, "Stop your timer.");

	// Teleport to end
	RegConsoleCmd("sm_end", Command_TeleportEnd, "Teleport to endzone.");

	// Track
	RegConsoleCmd("sm_t", Command_Track, "Choose your track.");
	RegConsoleCmd("sm_track", Command_Track, "Choose your track.");

	// Prop
	RegConsoleCmd("sm_p", Command_Prop, "Choose your prop.");
	RegConsoleCmd("sm_prop", Command_Prop, "Choose your prop.");
	RegConsoleCmd("sm_props", Command_Prop, "Choose your prop.");
	gH_PropCookie = RegClientCookie("proptricks_prop", "Prop cookie", CookieAccess_Protected);
	
	RegConsoleCmd("sm_pb", Command_PushButton, "");
	RegConsoleCmd("sm_pushbutton", Command_PushButton, "");
	gH_PushButtonCookie = RegClientCookie("proptricks_pushbutton", "Push button cookie", CookieAccess_Protected);

	// Prop commands
	gSM_PropCommands = new StringMap();

	// Admin
	RegAdminCmd("sm_deletemap", Command_DeleteMap, ADMFLAG_ROOT, "Deletes all map data. Usage: sm_deletemap <map>");
	RegAdminCmd("sm_wipeplayer", Command_WipePlayer, ADMFLAG_BAN, "Wipes all bhoptimer data for specified player. Usage: sm_wipeplayer <steamid3>");

	// Logs
	BuildPath(Path_SM, gS_LogPath, PLATFORM_MAX_PATH, "logs/proptricks.log");

	CreateConVar("proptricks_version", PROPTRICKS_VERSION, "Plugin version.", (FCVAR_NOTIFY | FCVAR_DONTRECORD));

	sv_turbophysics = FindConVar("sv_turbophysics");
	sv_pushaway_force = FindConVar("sv_pushaway_force");
	sv_pushaway_max_force = FindConVar("sv_pushaway_max_force");

	gB_Zones = LibraryExists("proptricks-zones");
	gB_WR = LibraryExists("proptricks-wr");
	gB_Replay = LibraryExists("proptricks-replay");
	gB_Rankings = LibraryExists("proptricks-rankings");

	// database connections
	SQL_DBConnect();

	// late
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
	}
}

public void OnConfigsExecuted()
{
	if(sv_turbophysics != null)
	{
		sv_turbophysics.BoolValue = true;
	}
}

public void OnPluginEnd()
{
	Patch_OnPluginEnd();
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "proptricks-zones"))
	{
		gB_Zones = true;
	}

	else if(StrEqual(name, "proptricks-wr"))
	{
		gB_WR = true;
	}

	else if(StrEqual(name, "proptricks-replay"))
	{
		gB_Replay = true;
	}

	else if(StrEqual(name, "proptricks-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "proptricks-zones"))
	{
		gB_Zones = false;
	}

	else if(StrEqual(name, "proptricks-wr"))
	{
		gB_WR = false;
	}

	else if(StrEqual(name, "proptricks-replay"))
	{
		gB_Replay = false;
	}

	else if(StrEqual(name, "proptricks-rankings"))
	{
		gB_Rankings = false;
	}
}

public void OnMapStart()
{
	// props
	if(!LoadProps())
	{
		SetFailState("Could not load the props configuration file. Make sure it exists (addons/sourcemod/configs/proptricks-props.cfg) and follows the proper syntax!");
	}

	// messages
	if(!LoadMessages())
	{
		SetFailState("Could not load the chat messages configuration file. Make sure it exists (addons/sourcemod/configs/proptricks-messages.cfg) and follows the proper syntax!");
	}
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client) || !IsClientInGame(client))
	{
		return;
	}

	char sCookie[4];

	if(gH_AutoBhopCookie != null)
	{
		GetClientCookie(client, gH_AutoBhopCookie, sCookie, 4);
	}

	gA_Timers[client].bAuto = (strlen(sCookie) > 0)? view_as<bool>(StringToInt(sCookie)):true;

	int prop = 0;

	if(gB_PropCookies && gH_PropCookie != null)
	{
		GetClientCookie(client, gH_PropCookie, sCookie, 4);
		int newprop = StringToInt(sCookie);

		if(0 <= newprop < gI_Props)
		{
			prop = newprop;
		}
	}

	CallOnPropChanged(client, gA_Timers[client].iProp, prop, false);
	
	if(gH_PushButtonCookie != null)
	{
		GetClientCookie(client, gH_PushButtonCookie, sCookie, 4);
	}
	
	gA_Timers[client].iPushButton = (strlen(sCookie) > 0) ? StringToInt(sCookie) : IN_USE;

	gB_CookiesRetrieved[client] = true;
}

public void OnClientConnected(int client)
{
	gA_Timers[client].iEntityIndex = -1;
}

public void OnClientPutInServer(int client)
{
	StopTimer(client);

	if(!IsClientConnected(client) || IsFakeClient(client))
	{
		return;
	}

	gA_Timers[client].iTrack = 0;
	gA_Timers[client].iProp = 0;
	//gA_Timers[client].iEntityIndex = -1;
	strcopy(gS_DeleteMap[client], 160, "");

	gB_CookiesRetrieved[client] = false;

	if(AreClientCookiesCached(client))
	{
		OnClientCookiesCached(client);
	}

	SDKHook(client, SDKHook_PreThink, OnPreThink);
	SDKHook(client, SDKHook_PostThinkPost, OnPostThinkPost);

	SQL_TryToInsertUser(client);
}

public void OnClientDisconnect(int client)
{
	RequestFrame(StopTimer, client);
	RemoveProp(client);
}

public void OnPreThink(int client)
{
	FindEntities(client);
}

public void OnPostThinkPost(int client)
{
	gF_Origin[client][1] = gF_Origin[client][0];
	GetEntPropVector(client, Prop_Data, "m_vecOrigin", gF_Origin[client][0]);
	if(gA_Timers[client].iZoneIncrement == 1)
	{
		CalculateTickIntervalOffset(client, Zone_Start);
	}
}

public Action PropTricks_OnShouldCollide(int ent1, int ent2, bool& result)
{
	//Fix: func_clip_vphysics
	if((IsValidEntity(ent1) && GetEntPropEnt(ent1, Prop_Send, "m_PredictableID") != -1)
	&& (IsValidEntity(ent2) && GetEntPropEnt(ent2, Prop_Send, "m_PredictableID") != -1))
	{
		result = false;
		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action PropTricks_OnPassEntityFilter(int ent1, int ent2, bool& result)
{
	int client = -1;
	int prop = -1;

	if(IsValidClient(ent1) && IsValidEntity(ent2)
	&& GetEntPropEnt(ent2, Prop_Send, "m_PredictableID") != -1)
	{
		client = ent1;
		prop = ent2;
	}
	else if(IsValidClient(ent2) && IsValidEntity(ent1)
	&& GetEntPropEnt(ent1, Prop_Send, "m_PredictableID") != -1)
	{
		client = ent2;
		prop = ent1;
	}
	else
	{
		return Plugin_Continue;
	}

	if(PropTricks_GetPropEntityIndex(client) == prop)
	{
		return Plugin_Continue;
	}
	else
	{
		result = false;
		return Plugin_Handled;
	}
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsFakeClient(client))
	{
		return Plugin_Continue;
	}
	
	int entity = gA_Timers[client].iEntityIndex;

	if(!IsValidEdict(entity))
	{
		gA_Timers[client].iEntityIndex = -1;
		PropTricks_StopTimer(client, false);
	}
	else
	{
		if(GetEntPropEnt(entity, Prop_Send, "m_PredictableID") != client)
		{
			SetEntPropEnt(entity, Prop_Send, "m_PredictableID", client);
		}
	}

	// Wait till now to return so spectators can free-cam while paused...
	if(!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnUserCmdPre);
	Call_PushCell(client);
	Call_PushCellRef(buttons);
	Call_PushCellRef(impulse);
	Call_PushArrayEx(vel, 3, SM_PARAM_COPYBACK);
	Call_PushArrayEx(angles, 3, SM_PARAM_COPYBACK);
	Call_PushCell(GetTimerStatus(client));
	Call_PushCell(gA_Timers[client].iTrack);
	Call_PushCell(gA_Timers[client].iProp);
	Call_PushArray(gA_PropSettings[gA_Timers[client].iProp], sizeof(propsettings_t));
	Call_PushArrayEx(mouse, 2, SM_PARAM_COPYBACK);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return result;
	}
	
	if(gA_Timers[client].bAuto && ((buttons & IN_JUMP) > 0 && GetEntityMoveType(client) == MOVETYPE_WALK && !(GetEntProp(client, Prop_Send, "m_nWaterLevel") >= 2)))
	{
		int iOldButtons = GetEntProp(client, Prop_Data, "m_nOldButtons");
		SetEntProp(client, Prop_Data, "m_nOldButtons", (iOldButtons & ~IN_JUMP));
	}

	return Plugin_Continue;
}

//Events
public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client))
	{
		return;
	}

	RemoveProp(client);
	StopTimer(client);
}

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));
	
	//Happens when someone connected to the server, idk why, this is so shit
	//PrintToServer("player spawn: %d | %d | %s", client, GetClientTeam(client), IsPlayerAlive(client) ? "alive" : "dead");
	
	if(IsFakeClient(client))
	{
		return;
	}

	if(GetClientTeam(client) > 1)
	{
		if(PropTricks_GetPropEntityIndex(client) == -1)
		{
			int entity = CreateClientProp(client);
			if(entity != -1)
			{
				CallOnPropCreated(client, gA_Timers[client].iProp, entity);
			}
		}

		StopTimer(client);
	}
}

public void Event_PlayerTeam(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if(IsFakeClient(client))
	{
		return;
	}

	int team = event.GetInt("team");
	int oldteam = event.GetInt("oldteam");

	if(team == 0)
	{
		return;
	}

	if(team == 1)
	{
		RemoveProp(client);
	}
	else if(team + oldteam != 5)
	{
		if(PropTricks_GetPropEntityIndex(client) == -1)
		{
			int entity = CreateClientProp(client);
			if(entity != -1)
			{
				CallOnPropCreated(client, gA_Timers[client].iProp, entity);
			}
		}
	}

	StopTimer(client);
}

//Commands
public Action Command_AutoBhop(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	gA_Timers[client].bAuto = !gA_Timers[client].bAuto;

	if(gA_Timers[client].bAuto)
	{
		PropTricks_PrintToChat(client, "%T", "AutobhopEnabled", client, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);
	}

	else
	{
		PropTricks_PrintToChat(client, "%T", "AutobhopDisabled", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	char sAutoBhop[4];
	IntToString(view_as<int>(gA_Timers[client].bAuto), sAutoBhop, 4);
	SetClientCookie(client, gH_AutoBhopCookie, sAutoBhop);

	return Plugin_Handled;
}

public Action Command_Track(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	// allow !track <number>
	if(args > 0)
	{
		char sArgs[16];
		GetCmdArg(1, sArgs, sizeof(sArgs));
		int newtrack = StringToInt(sArgs) - 1;
		
		if(newtrack < 0 || newtrack >= TRACKS_SIZE)
		{
			return Plugin_Handled;
		}
		
		ChangeClientTrack(client, newtrack, true);
		return Plugin_Handled;
	}
	
	Menu_OpenTrack(client);
	
	return Plugin_Handled;
}

void ChangeClientTrack(int client, int newtrack, bool manual)
{
	if(!IsValidClient(client))
	{
		return;
	}

	if(manual)
	{
		if(!PropTricks_StopTimer(client, false))
		{
			return;
		}

		char sTrack[32];
		GetTrackName(client, newtrack, sTrack, 32);
		PropTricks_PrintToChat(client, "%T", "TrackSelection", client, gS_ChatStrings.sVariable, sTrack, gS_ChatStrings.sText);
	}

	CallOnTrackChanged(client, gA_Timers[client].iTrack, newtrack);

	if(gB_Zones && PropTricks_ZoneExists(Zone_Start, newtrack))
	{
		CallOnRestart(client, newtrack);
	}
}

public Action Command_Prop(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}
	
	// allow !prop <number>
	if (args > 0)
	{
		char sArgs[16];
		GetCmdArg(1, sArgs, sizeof(sArgs));
		int prop = StringToInt(sArgs) - 1;

		if (prop < 0 || prop >= PropTricks_GetPropCount())
		{
			return Plugin_Handled;
		}
		
		ChangeClientProp(client, prop, true);
		return Plugin_Handled;
	}

	Menu_OpenProp(client);

	return Plugin_Handled;
}

void ChangeClientProp(int client, int prop, bool manual)
{
	if(!IsValidClient(client))
	{
		return;
	}

	if(manual)
	{
		if(!PropTricks_StopTimer(client, false))
		{
			return;
		}

		PropTricks_PrintToChat(client, "%T", "PropSelection", client, gS_ChatStrings.sProp, gS_PropStrings[prop].sPropName, gS_ChatStrings.sText);
	}

	CallOnPropChanged(client, gA_Timers[client].iProp, prop, manual);

	if(gB_Zones && PropTricks_ZoneExists(Zone_Start, gA_Timers[client].iTrack))
	{
		CallOnRestart(client, gA_Timers[client].iTrack);
	}

	char sProp[4];
	IntToString(prop, sProp, 4);

	SetClientCookie(client, gH_PropCookie, sProp);
}

public Action Command_StartTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	int track = PropTricks_GetClientTrack(client);

	if(gB_Zones && PropTricks_ZoneExists(Zone_Start, track))
	{
		if(!PropTricks_StopTimer(client, false))
		{
			return Plugin_Handled;
		}

		if(!IsValidEdict(gA_Timers[client].iEntityIndex))
		{
			int entity = CreateClientProp(client);
			if(entity != -1)
			{
				CallOnPropCreated(client, gA_Timers[client].iProp, entity);
			}
		}

		CallOnRestart(client, track);
	}

	else
	{
		char sTrack[32];
		GetTrackName(client, track, sTrack, 32);

		PropTricks_PrintToChat(client, "%T", "StartZoneUndefined", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, sTrack, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_StopTimer(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	PropTricks_StopTimer(client, false);

	return Plugin_Handled;
}

public Action Command_TeleportEnd(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	int track = PropTricks_GetClientTrack(client);

	if(gB_Zones && PropTricks_ZoneExists(Zone_End, track))
	{
		if(PropTricks_StopTimer(client, false))
		{
			Call_StartForward(gH_Forwards_OnEnd);
			Call_PushCell(client);
			Call_PushCell(track);
			Call_Finish();
		}
	}

	else
	{
		PropTricks_PrintToChat(client, "%T", "EndZoneUndefined", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}

	return Plugin_Handled;
}

public Action Command_DeleteMap(int client, int args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_deletemap <map>\nOnce a map is chosen, \"sm_deletemap confirm\" to run the deletion.");

		return Plugin_Handled;
	}

	char sArgs[160];
	GetCmdArgString(sArgs, 160);

	if(StrEqual(sArgs, "confirm") && strlen(gS_DeleteMap[client]) > 0)
	{
		if(gB_WR)
		{
			PropTricks_WR_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all records for %s.", gS_DeleteMap[client]);
		}

		if(gB_Zones)
		{
			PropTricks_Zones_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all zones for %s.", gS_DeleteMap[client]);
		}

		if(gB_Replay)
		{
			PropTricks_Replay_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all replay data for %s.", gS_DeleteMap[client]);
		}

		if(gB_Rankings)
		{
			PropTricks_Rankings_DeleteMap(gS_DeleteMap[client]);
			ReplyToCommand(client, "Deleted all rankings for %s.", gS_DeleteMap[client]);
		}

		ReplyToCommand(client, "Finished deleting data for %s.", gS_DeleteMap[client]);
		strcopy(gS_DeleteMap[client], 160, "");
	}

	else
	{
		strcopy(gS_DeleteMap[client], 160, sArgs);
		ReplyToCommand(client, "Map to delete is now %s.\nRun \"sm_deletemap confirm\" to delete all data regarding the map %s.", gS_DeleteMap[client], gS_DeleteMap[client]);
	}

	return Plugin_Handled;
}

public Action Command_WipePlayer(int client, int args)
{
	if(args == 0)
	{
		ReplyToCommand(client, "Usage: sm_wipeplayer <steamid3>\nAfter entering a SteamID, you will be prompted with a verification captcha.");

		return Plugin_Handled;
	}

	char sArgString[32];
	GetCmdArgString(sArgString, 32);

	if(strlen(gS_Verification[client]) == 0 || !StrEqual(sArgString, gS_Verification[client]))
	{
		ReplaceString(sArgString, 32, "[U:1:", "");
		ReplaceString(sArgString, 32, "]", "");

		gI_WipePlayerID[client] = StringToInt(sArgString);

		if(gI_WipePlayerID[client] <= 0)
		{
			PropTricks_PrintToChat(client, "Entered SteamID ([U:1:%s]) is invalid. The range for valid SteamIDs is [U:1:1] to [U:1:2147483647].", sArgString);

			return Plugin_Handled;
		}

		char sAlphabet[] = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890!@#";
		strcopy(gS_Verification[client], 8, "");

		for(int i = 0; i < 5; i++)
		{
			gS_Verification[client][i] = sAlphabet[GetRandomInt(0, sizeof(sAlphabet) - 1)];
		}

		PropTricks_PrintToChat(client, "Preparing to delete all user data for SteamID %s[U:1:%d]%s. To confirm, enter %s!wipeplayer %s",
			gS_ChatStrings.sVariable, gI_WipePlayerID[client], gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_Verification[client]);
	}

	else
	{
		PropTricks_PrintToChat(client, "Deleting data for SteamID %s[U:1:%d]%s...",
			gS_ChatStrings.sVariable, gI_WipePlayerID[client], gS_ChatStrings.sText);

		DeleteUserData(client, gI_WipePlayerID[client]);

		strcopy(gS_Verification[client], 8, "");
		gI_WipePlayerID[client] = -1;
	}

	return Plugin_Handled;
}

public Action Command_PushButton(int client, int args)
{
	Menu_OpenPushButton(client);
	
	return Plugin_Handled;
}

int GetTimerStatus(int client)
{
	if(!gA_Timers[client].bEnabled)
	{
		return view_as<int>(Timer_Stopped);
	}

	return view_as<int>(Timer_Running);
}

void StartTimer(int client, int track)
{
	if(!IsValidClient(client, true) || GetClientTeam(client) < 2 || IsFakeClient(client) || !gB_CookiesRetrieved[client])
	{
		return;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnStart);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish(result);

	if(result == Plugin_Continue)
	{
		gA_Timers[client].iZoneIncrement = 0;

		if(gA_Timers[client].iTrack != track)
		{
			ChangeClientTrack(client, track, false);
		}

		gA_Timers[client].bEnabled = true;
		gA_Timers[client].fTimer = 0.0;
		gA_Timers[client].fTimeOffset[Zone_Start] = 0.0;
		gA_Timers[client].fTimeOffset[Zone_End] = 0.0;
		gA_Timers[client].fDistanceOffset[Zone_Start] = 0.0;
		gA_Timers[client].fDistanceOffset[Zone_End] = 0.0;
	}

	else if(result == Plugin_Handled || result == Plugin_Stop)
	{
		gA_Timers[client].bEnabled = false;
	}
}

void StopTimer(int client)
{
	if(!IsValidClient(client) || IsFakeClient(client))
	{
		return;
	}

	gA_Timers[client].bEnabled = false;
	gA_Timers[client].fTimer = 0.0;
}

bool LoadProps()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/proptricks-props.cfg");

	KeyValues kv = new KeyValues("proptricks-props");

	if(!kv.ImportFromFile(sPath) || !kv.GotoFirstSubKey())
	{
		delete kv;

		return false;
	}

	int i = 0;

	do
	{
		kv.GetString("name", gS_PropStrings[i].sPropName, sizeof(propstrings_t::sPropName), "<MISSING PROP NAME>");
		kv.GetString("shortname", gS_PropStrings[i].sShortName, sizeof(propstrings_t::sShortName), "<MISSING SHORT PROP NAME>");
		kv.GetString("modelpath", gS_PropStrings[i].sModelPath, sizeof(propstrings_t::sModelPath), "<MISSING PROP MODEL PATH>");
		kv.GetString("command", gS_PropStrings[i].sChangeCommand, sizeof(propstrings_t::sChangeCommand), "");
		kv.GetString("specialstring", gS_PropStrings[i].sSpecialString, sizeof(propstrings_t::sSpecialString), "");

		gA_PropSettings[i].fMassScale =  kv.GetFloat("massscale", 1.00);
		gA_PropSettings[i].iEnabled = kv.GetNum("enabled", 1);
		gA_PropSettings[i].bUnranked = view_as<bool>(kv.GetNum("unranked", 0));
		gA_PropSettings[i].bNoReplay = view_as<bool>(kv.GetNum("noreplay", 0));
		gA_PropSettings[i].fRankingMultiplier = kv.GetFloat("rankingmultiplier", 1.00);
		gA_PropSettings[i].iOrdering = kv.GetNum("ordering", i);

		if(gA_PropSettings[i].iEnabled <= 0)
		{
			gA_PropSettings[i].bNoReplay = true;
			gA_PropSettings[i].fRankingMultiplier = 0.0;
			gA_PropSettings[i].iEnabled = -1;
		}

		if(!gB_Registered && strlen(gS_PropStrings[i].sChangeCommand) > 0)
		{
			char sPropCommands[32][32];
			int iCommands = ExplodeString(gS_PropStrings[i].sChangeCommand, ";", sPropCommands, 32, 32, false);

			char sDescription[128];
			FormatEx(sDescription, 128, "Change prop to %s.", gS_PropStrings[i].sPropName);

			for(int x = 0; x < iCommands; x++)
			{
				TrimString(sPropCommands[x]);
				StripQuotes(sPropCommands[x]);

				char sCommand[32];
				FormatEx(sCommand, 32, "sm_%s", sPropCommands[x]);

				gSM_PropCommands.SetValue(sCommand, i);

				RegConsoleCmd(sCommand, Command_PropChange, sDescription);
			}
		}
		gI_OrderedProps[i] = i++;
	}

	while(kv.GotoNextKey());

	delete kv;

	gI_Props = i;
	gB_Registered = true;

	SortCustom1D(gI_OrderedProps, gI_Props, SortAscending_PropOrder);

	Call_StartForward(gH_Forwards_OnPropConfigLoaded);
	Call_PushCell(gI_Props);
	Call_Finish();

	return true;
}

public int SortAscending_PropOrder(int index1, int index2, const int[] array, any hndl)
{
	int iOrder1 = gA_PropSettings[index1].iOrdering;
	int iOrder2 = gA_PropSettings[index2].iOrdering;

	if(iOrder1 < iOrder2)
	{
		return -1;
	}
	
	return (iOrder1 == iOrder2) == false;
}

public Action Command_PropChange(int client, int args)
{
	char sCommand[128];
	GetCmdArg(0, sCommand, 128);

	int prop = 0;

	if(gSM_PropCommands.GetValue(sCommand, prop))
	{
		ChangeClientProp(client, prop, true);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void ReplaceColors(char[] string, int size)
{
	for(int x = 0; x < sizeof(gS_GlobalColorNames); x++)
	{
		ReplaceString(string, size, gS_GlobalColorNames[x], gS_GlobalColors[x]);
	}

	ReplaceString(string, size, "{RGB}", "\x07");
	ReplaceString(string, size, "{RGBA}", "\x08");
}

bool LoadMessages()
{
	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, PLATFORM_MAX_PATH, "configs/proptricks-messages.cfg");

	KeyValues kv = new KeyValues("proptricks-messages");

	if(!kv.ImportFromFile(sPath))
	{
		delete kv;

		return false;
	}

	kv.JumpToKey("CS:S");

	kv.GetString("prefix", gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix), "\x075E70D0[Timer]");
	kv.GetString("text", gS_ChatStrings.sText, sizeof(chatstrings_t::sText), "\x07FFFFFF");
	kv.GetString("warning", gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning), "\x07AF2A22");
	kv.GetString("variable", gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable), "\x077FD772");
	kv.GetString("variable2", gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2), "\x07276F5C");
	kv.GetString("prop", gS_ChatStrings.sProp, sizeof(chatstrings_t::sProp), "\x07DB88C2");

	delete kv;

	ReplaceColors(gS_ChatStrings.sPrefix, sizeof(chatstrings_t::sPrefix));
	ReplaceColors(gS_ChatStrings.sText, sizeof(chatstrings_t::sText));
	ReplaceColors(gS_ChatStrings.sWarning, sizeof(chatstrings_t::sWarning));
	ReplaceColors(gS_ChatStrings.sVariable, sizeof(chatstrings_t::sVariable));
	ReplaceColors(gS_ChatStrings.sVariable2, sizeof(chatstrings_t::sVariable2));
	ReplaceColors(gS_ChatStrings.sProp, sizeof(chatstrings_t::sProp));

	Call_StartForward(gH_Forwards_OnChatConfigLoaded);
	Call_PushArray(gS_ChatStrings, sizeof(gS_ChatStrings));
	Call_Finish();

	return true;
}

int CreateClientProp(int client)
{
	int entity = CreateEntityByName("prop_physics");

	if(entity == -1)
	{
		LogError("\"prop_physics\" creation failed");
		return -1;
	}

	int prop = gA_Timers[client].iProp;

	//m_iParent - AcceptEntityInput(ent, "SetParent", client);
	if(GetEntPropEnt(entity, Prop_Send, "m_PredictableID") == -1)
	{
		SetEntPropEnt(entity, Prop_Send, "m_PredictableID", client);
		
		gA_Timers[client].iEntityIndex = entity;

		DispatchKeyValue(entity, "model", gS_PropStrings[prop].sModelPath);
		DispatchKeyValueFloat(entity, "massscale", gA_PropSettings[prop].fMassScale);
		DispatchSpawn(entity);
		
		if(!PropTricks_ZoneExists(Zone_Start, PropTricks_GetClientTrack(client)))
		{
			static int spawnpoint = -1;
			static float vOrigin[3];
			if(spawnpoint == -1)
			{
				if((spawnpoint = FindEntityByClassname(spawnpoint, "info_player_*")) != -1)
				{
					GetEntPropVector(spawnpoint, Prop_Data, "m_vecOrigin", vOrigin);
				}
			}
			TeleportEntity(entity, vOrigin, NULL_VECTOR, NULL_VECTOR);
		}
	}
	return entity;
}

bool RemoveProp(int client)
{
	bool retvalue = false;

	int entity = gA_Timers[client].iEntityIndex;
	if(entity > 0 && IsValidEdict(entity))
	{
		Call_StartForward(gH_Forwards_OnPropRemovePre);
		Call_PushCell(client);
		Call_PushCell(gA_Timers[client].iProp);
		Call_PushCell(entity);
		Call_Finish();

		gA_Timers[client].iEntityIndex = -1;
		retvalue = AcceptEntityInput(entity, "Kill");
	}
	return retvalue;
}

// reference: https://github.com/momentum-mod/game/blob/5e2d1995ca7c599907980ee5b5da04d7b5474c61/mp/src/game/server/momentum/mom_timer.cpp#L388
void CalculateTickIntervalOffset(int client, int zonetype)
{
	float localOrigin[3];
	GetEntPropVector(client, Prop_Send, "m_vecOrigin", localOrigin);
	float maxs[3];
	float mins[3];
	float vel[3];
	GetEntPropVector(client, Prop_Send, "m_vecMins", mins);
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", maxs);
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);

	gF_SmallestDist[client] = 0.0;

	if (zonetype == Zone_Start)
	{
		TR_EnumerateEntitiesHull(localOrigin, gF_Origin[client][1], mins, maxs, PARTITION_TRIGGER_EDICTS, TREnumTrigger, client);
	}
	else
	{
		TR_EnumerateEntitiesHull(gF_Origin[client][0], localOrigin, mins, maxs, PARTITION_TRIGGER_EDICTS, TREnumTrigger, client);
	}

	float offset = gF_Fraction[client] * GetTickInterval();

	gA_Timers[client].fTimeOffset[zonetype] = offset;
	gA_Timers[client].fDistanceOffset[zonetype] = gF_SmallestDist[client];

	Call_StartForward(gH_Forwards_OnTimeOffsetCalculated);
	Call_PushCell(client);
	Call_PushCell(zonetype);
	Call_PushCell(offset);
	Call_PushCell(gF_SmallestDist[client]);
	Call_Finish();

	gF_SmallestDist[client] = 0.0;
}

bool TREnumTrigger(int entity, int client) {

	if (entity <= MaxClients) {
		return true;
	}

	char classname[32];
	GetEntityClassname(entity, classname, sizeof(classname));

	//the entity is a zone
	if(StrContains(classname, "trigger_multiple") > -1)
	{
		TR_ClipCurrentRayToEntity(MASK_ALL, entity);

		float start[3];
		TR_GetStartPosition(INVALID_HANDLE, start);

		float end[3];
		TR_GetEndPosition(end);

		float distance = GetVectorDistance(start, end);
		gF_SmallestDist[client] = distance;
		gF_Fraction[client] = TR_GetFraction();

		return false;
	}
	return true;
}

void CallOnRestart(int client, int track)
{
	Call_StartForward(gH_Forwards_OnRestart);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish();
}

void CallOnPropCreated(int client, int prop, int entity)
{
	Call_StartForward(gH_Forwards_OnPropCreated);
	Call_PushCell(client);
	Call_PushCell(prop);
	Call_PushCell(entity);
	Call_Finish();
}

void CallOnTrackChanged(int client, int oldtrack, int newtrack)
{
	Call_StartForward(gH_Forwards_OnTrackChanged);
	Call_PushCell(client);
	Call_PushCell(oldtrack);
	Call_PushCell(newtrack);
	Call_Finish();

	gA_Timers[client].iTrack = newtrack;
}

void CallOnPropChanged(int client, int oldprop, int newprop, bool manual)
{
	Call_StartForward(gH_Forwards_OnPropChanged);
	Call_PushCell(client);
	Call_PushCell(oldprop);
	Call_PushCell(newprop);
	Call_PushCell(gA_Timers[client].iTrack);
	Call_PushCell(manual);
	Call_Finish();

	RemoveProp(client);

	gA_Timers[client].iProp = newprop;

	if(gB_Registered && manual)
	{
		if(IsValidClient(client, true))
		{
			int entity = CreateClientProp(client);
			if(entity != -1)
			{
				CallOnPropCreated(client, newprop, entity);
			}
		}
	}
}