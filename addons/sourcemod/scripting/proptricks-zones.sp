#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <convar_class>

#undef REQUIRE_PLUGIN
#include <proptricks>

#undef REQUIRE_EXTENSIONS
#include <cstrike>
#include <vphysics>

#pragma semicolon 1
#pragma dynamic 131072
#pragma newdecls required

#define ZONE_HEIGHT 128.0

Database gH_SQL = null;

char gS_Map[160];

char gS_ZoneNames[][] =
{
	"Start Zone", // starts timer
	"End Zone", // stops timer
	"Glitch Zone" // stops the player's timer
};

enum struct zone_cache_t
{
	bool bZoneInitialized;
	int iZoneType;
	int iZoneTrack; // 0 - main, 1 - bonus etc
	int iEntityID;
	int iDatabaseID;
	int iZoneFlags;
	int iZoneData;
}

enum struct zone_settings_t
{
	bool bVisible;
	int iRed;
	int iGreen;
	int iBlue;
	int iAlpha;
	float fWidth;
	bool bFlatZone;
}

enum
{
	ZF_ForceRender = (1 << 0)
};

bool gB_Connected = false;

int gI_ZoneType[MAXPLAYERS+1];

// 0 - nothing
// 1 - wait for E tap to setup first coord
// 2 - wait for E tap to setup second coord
// 3 - confirm
int gI_MapStep[MAXPLAYERS+1];

float gF_Modifier[MAXPLAYERS+1];
int gI_GridSnap[MAXPLAYERS+1];
bool gB_SnapToWall[MAXPLAYERS+1];
bool gB_CursorTracing[MAXPLAYERS+1];
int gI_ZoneFlags[MAXPLAYERS+1];
int gI_ZoneData[MAXPLAYERS+1];
bool gB_WaitingForChatInput[MAXPLAYERS+1];

// cache
float gV_Point1[MAXPLAYERS+1][3];
float gV_Point2[MAXPLAYERS+1][3];
float gV_WallSnap[MAXPLAYERS+1][3];
bool gB_Button[MAXPLAYERS+1];
bool gB_InsideZone[MAXPLAYERS+1][ZONETYPES_SIZE][TRACKS_SIZE];
bool gB_InsideZoneID[MAXPLAYERS+1][MAX_ZONES];
float gF_PrebuiltZones[TRACKS_SIZE][2][3];
int gI_ZoneTrack[MAXPLAYERS+1];
float gV_EditPoints[MAXPLAYERS+1][8][3];
int gI_ZoneIndex[MAXPLAYERS+1];
int gI_ChosenSide[MAXPLAYERS+1];
bool gB_EditType[MAXPLAYERS+1];
int gI_ZoneDatabaseID[MAXPLAYERS+1];

// zone cache
zone_settings_t gA_ZoneSettings[ZONETYPES_SIZE][TRACKS_SIZE];
zone_cache_t gA_ZoneCache[MAX_ZONES]; // Vectors will not be inside this array.
int gI_MapZones = 0;
float gV_MapZones[MAX_ZONES][2][3];
float gV_MapZones_Visual[MAX_ZONES][8][3];
float gV_ZoneCenter[MAX_ZONES][3];
int gI_EntityZone[4096];
bool gB_ZonesCreated = false;

char gS_BeamSprite[PLATFORM_MAX_PATH];
int gI_BeamSprite = -1;

// misc cache
bool gB_Late = false;

// cvars
Convar gCV_Interval = null;
Convar gCV_Offset = null;

// handles
Handle gH_DrawEverything = null;

// chat settings
chatstrings_t gS_ChatStrings;

// forwards
Handle gH_Forwards_EnterZone = null;
Handle gH_Forwards_LeaveZone = null;

#include "proptricks/zones/zones-sql.sp"
#include "proptricks/zones/zones-natives.sp"
#include "proptricks/zones/zones-menus.sp"
#include "proptricks/zones/zones-config.sp"

public Plugin myinfo =
{
	name = "[PropTricks] Zones",
	author = "Haze",
	description = "Zones for proptricks timer.",
	version = PROPTRICKS_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	Zones_DefineNatives();

	RegPluginLibrary("proptricks-zones");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("proptricks-common.phrases");
	LoadTranslations("proptricks-zones.phrases");

	// menu
	RegAdminCmd("sm_zones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu.");
	RegAdminCmd("sm_mapzones", Command_Zones, ADMFLAG_RCON, "Opens the mapzones menu. Alias of sm_zones.");

	RegAdminCmd("sm_deletezone", Command_DeleteZone, ADMFLAG_RCON, "Delete a mapzone");
	RegAdminCmd("sm_deleteallzones", Command_DeleteAllZones, ADMFLAG_RCON, "Delete all mapzones");

	RegAdminCmd("sm_modifier", Command_Modifier, ADMFLAG_RCON, "Changes the axis modifier for the zone editor. Usage: sm_modifier <number>");

	RegAdminCmd("sm_zoneedit", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone.");
	RegAdminCmd("sm_editzone", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone. Alias of sm_zoneedit.");
	RegAdminCmd("sm_modifyzone", Command_ZoneEdit, ADMFLAG_RCON, "Modify an existing zone. Alias of sm_zoneedit.");
	
	RegAdminCmd("sm_reloadzonesettings", Command_ReloadZoneSettings, ADMFLAG_ROOT, "Reloads the zone settings.");

	// events
	HookEvent("round_start", Round_Start);
	HookEvent("player_spawn", Player_Spawn);

	// forwards
	gH_Forwards_EnterZone = CreateGlobalForward("PropTricks_OnEnterZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_LeaveZone = CreateGlobalForward("PropTricks_OnLeaveZone", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	// cvars and stuff
	gCV_Interval = new Convar("proptricks_zones_interval", "1.0", "Interval between each time a mapzone is being drawn to the players.", 0, true, 0.5, true, 5.0);
	gCV_Offset = new Convar("proptricks_zones_offset", "0.5", "When calculating a zone's *VISUAL* box, by how many units, should we scale it to the center?\n0.0 - no downscaling. Values above 0 will scale it inward and negative numbers will scale it outwards.\nAdjust this value if the zones clip into walls.");

	gCV_Interval.AddChangeHook(OnConVarChanged);
	gCV_Offset.AddChangeHook(OnConVarChanged);

	Convar.AutoExecConfig();

	for(int i = 0; i < ZONETYPES_SIZE; i++)
	{
		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			gA_ZoneSettings[i][j].bVisible = true;
			gA_ZoneSettings[i][j].iRed = 255;
			gA_ZoneSettings[i][j].iGreen = 255;
			gA_ZoneSettings[i][j].iBlue = 255;
			gA_ZoneSettings[i][j].iAlpha = 255;
			gA_ZoneSettings[i][j].fWidth = 2.0;
			gA_ZoneSettings[i][j].bFlatZone = false;
		}
	}

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			OnClientPutInServer(i);
		}
	}

	SQL_DBConnect();
}

public void OnConVarChanged(ConVar convar, const char[] oldValue, const char[] newValue)
{
	if(convar == gCV_Interval)
	{
		delete gH_DrawEverything;
		gH_DrawEverything = CreateTimer(gCV_Interval.FloatValue, PropTricks_DrawEverything, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	else if(convar == gCV_Offset && gI_MapZones > 0)
	{
		for(int i = 0; i < gI_MapZones; i++)
		{
			if(!gA_ZoneCache[i].bZoneInitialized)
			{
				continue;
			}

			gV_MapZones_Visual[i][0][0] = gV_MapZones[i][0][0];
			gV_MapZones_Visual[i][0][1] = gV_MapZones[i][0][1];
			gV_MapZones_Visual[i][0][2] = gV_MapZones[i][0][2];
			gV_MapZones_Visual[i][7][0] = gV_MapZones[i][1][0];
			gV_MapZones_Visual[i][7][1] = gV_MapZones[i][1][1];
			gV_MapZones_Visual[i][7][2] = gV_MapZones[i][1][2];

			CreateZonePoints(gV_MapZones_Visual[i], gCV_Offset.FloatValue);
		}
	}
}

bool InsideZone(int client, int type, int track)
{
	if(track != -1)
	{
		return gB_InsideZone[client][type][track];
	}

	else
	{
		for(int i = 0; i < TRACKS_SIZE; i++)
		{
			if(gB_InsideZone[client][type][i])
			{
				return true;
			}
		}
	}

	return false;
}

public void OnMapStart()
{
	if(!gB_Connected)
	{
		return;
	}

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	gI_MapZones = 0;
	ReloadPrebuiltZones();
	UnloadZones(0);
	ZonesDB_RefreshZones();
	
	Zones_LoadZonesConfig();
	
	PrecacheModel("models/props/cs_office/vending_machine.mdl");

	// draw
	// start drawing mapzones here
	if(gH_DrawEverything == null)
	{
		gH_DrawEverything = CreateTimer(gCV_Interval.FloatValue, PropTricks_DrawEverything, INVALID_HANDLE, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
	}

	if(gB_Late)
	{
		PropTricks_GetChatStrings(gS_ChatStrings);
	}
}

public void OnMapEnd()
{
	delete gH_DrawEverything;
}

public void OnEntityCreated(int entity, const char[] classname)
{
	if(StrEqual(classname, "trigger_multiple", false))
	{
		RequestFrame(Frame_HookTrigger, EntIndexToEntRef(entity));
	}
}

public void Frame_HookTrigger(any data)
{
	int entity = EntRefToEntIndex(data);

	if(entity == INVALID_ENT_REFERENCE)
	{
		return;
	}

	char sName[32];
	GetEntPropString(entity, Prop_Data, "m_iName", sName, 32);

	if(StrContains(sName, "mod_zone_") == -1)
	{
		return;
	}

	int zone = -1;
	int track = Track;

	if(StrContains(sName, "start") != -1)
	{
		zone = Zone_Start;
	}

	else if(StrContains(sName, "end") != -1)
	{
		zone = Zone_End;
	}

	if(zone != -1)
	{
		float maxs[3];
		GetEntPropVector(entity, Prop_Send, "m_vecMaxs", maxs);

		float origin[3];
		GetEntPropVector(entity, Prop_Send, "m_vecOrigin", origin);

		origin[2] -= (maxs[2] - 2.0); // so you don't get stuck in the ground
		
		gF_PrebuiltZones[track][zone] = origin;

		for(int i = 1; i <= MaxClients; i++)
		{
			gB_InsideZone[i][zone][track] = false;
		}

		SDKHook(entity, SDKHook_StartTouchPost, StartTouchPost_Trigger);
		SDKHook(entity, SDKHook_EndTouchPost, EndTouchPost_Trigger);
		SDKHook(entity, SDKHook_TouchPost, TouchPost_Trigger);
	}
}

public void PropTricks_OnChatConfigLoaded(chatstrings_t strings)
{
	gS_ChatStrings = strings;
}

void ClearZone(int index)
{
	for(int i = 0; i < 3; i++)
	{
		gV_MapZones[index][0][i] = 0.0;
		gV_MapZones[index][1][i] = 0.0;
		gV_ZoneCenter[index][i] = 0.0;
	}

	gA_ZoneCache[index].bZoneInitialized = false;
	gA_ZoneCache[index].iZoneType = -1;
	gA_ZoneCache[index].iZoneTrack = -1;
	gA_ZoneCache[index].iEntityID = -1;
	gA_ZoneCache[index].iDatabaseID = -1;
	gA_ZoneCache[index].iZoneFlags = 0;
	gA_ZoneCache[index].iZoneData = 0;
}

void UnhookEntity(int entity)
{
	SDKUnhook(entity, SDKHook_StartTouchPost, StartTouchPost);
	SDKUnhook(entity, SDKHook_EndTouchPost, EndTouchPost);
	SDKUnhook(entity, SDKHook_TouchPost, TouchPost);
}

void KillZoneEntity(int index)
{
	int entity = gA_ZoneCache[index].iEntityID;
	
	if(entity > MaxClients && IsValidEntity(entity))
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			for(int j = 0; j < TRACKS_SIZE; j++)
			{
				gB_InsideZone[i][gA_ZoneCache[index].iZoneType][j] = false;
			}

			gB_InsideZoneID[i][index] = false;
		}

		char sTargetname[32];
		GetEntPropString(entity, Prop_Data, "m_iName", sTargetname, 32);

		if(StrContains(sTargetname, "proptricks_zones_") == -1)
		{
			return;
		}

		UnhookEntity(entity);
		AcceptEntityInput(entity, "Kill");
	}
}

// 0 - all zones
void UnloadZones(int zone)
{
	for(int i = 0; i < MAX_ZONES; i++)
	{
		if((zone == 0 || gA_ZoneCache[i].iZoneType == zone) && gA_ZoneCache[i].bZoneInitialized)
		{
			KillZoneEntity(i);
			ClearZone(i);
		}
	}

	if(zone == 0)
	{
		gB_ZonesCreated = false;

		char sTargetname[32];
		int iEntity = INVALID_ENT_REFERENCE;

		while((iEntity = FindEntityByClassname(iEntity, "trigger_multiple")) != INVALID_ENT_REFERENCE)
		{
			GetEntPropString(iEntity, Prop_Data, "m_iName", sTargetname, 32);

			if(StrContains(sTargetname, "proptricks_zones_") != -1)
			{
				AcceptEntityInput(iEntity, "Kill");
			}
		}
	}

	return;
}

public void OnClientPutInServer(int client)
{
	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		for(int j = 0; j < ZONETYPES_SIZE; j++)
		{
			gB_InsideZone[client][j][i] = false;
		}
	}

	for(int i = 0; i < MAX_ZONES; i++)
	{
		gB_InsideZoneID[client][i] = false;
	}

	Reset(client);
}

public Action Command_Modifier(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(args == 0)
	{
		PropTricks_PrintToChat(client, "%T", "ModifierCommandNoArgs", client);

		return Plugin_Handled;
	}

	char sArg1[16];
	GetCmdArg(1, sArg1, 16);

	float fArg1 = StringToFloat(sArg1);

	if(fArg1 <= 0.0)
	{
		PropTricks_PrintToChat(client, "%T", "ModifierTooLow", client);

		return Plugin_Handled;
	}

	gF_Modifier[client] = fArg1;

	PropTricks_PrintToChat(client, "%T %s%.01f%s.", "ModifierSet", client, gS_ChatStrings.sVariable, fArg1, gS_ChatStrings.sText);

	return Plugin_Handled;
}

void ReloadPrebuiltZones()
{
	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		gF_PrebuiltZones[i][Zone_Start] = NULL_VECTOR;
		gF_PrebuiltZones[i][Zone_End] = NULL_VECTOR;
	}

	char sTargetname[32];
	int iEntity = INVALID_ENT_REFERENCE;

	while((iEntity = FindEntityByClassname(iEntity, "trigger_multiple")) != INVALID_ENT_REFERENCE)
	{
		GetEntPropString(iEntity, Prop_Data, "m_iName", sTargetname, 32);

		if(StrContains(sTargetname, "mod_zone_") != -1)
		{
			Frame_HookTrigger(EntIndexToEntRef(iEntity));
		}
	}
}

public Action Command_ZoneEdit(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Reset(client);

	Zones_OpenEditMenu(client);
	
	return Plugin_Handled;
}

public Action Command_ReloadZoneSettings(int client, int args)
{
	Zones_LoadZonesConfig();

	ReplyToCommand(client, "Reloaded zone settings.");

	return Plugin_Handled;
}

public Action Command_Zones(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	if(!IsPlayerAlive(client))
	{
		PropTricks_PrintToChat(client, "%T", "ZonesCommand", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	Reset(client);

	Zones_OpenZonesMenu(client);

	return Plugin_Handled;
}

public Action Command_DeleteZone(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Zones_OpenDeleteMenu(client);
	
	return Plugin_Handled;
}

public Action Command_DeleteAllZones(int client, int args)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Zones_OpenDeleteAllZonesMenu(client);

	return Plugin_Handled;
}

void Reset(int client)
{
	gI_ZoneTrack[client] = Track;
	gF_Modifier[client] = 16.0;
	gI_MapStep[client] = 0;
	gI_GridSnap[client] = 16;
	gB_SnapToWall[client] = false;
	gB_CursorTracing[client] = true;
	gI_ZoneFlags[client] = 0;
	gI_ZoneData[client] = 0;
	gI_ZoneDatabaseID[client] = -1;
	gI_ZoneIndex[client] = -1;
	gI_ChosenSide[client] = -1;
	gB_EditType[client] = false;
	gB_WaitingForChatInput[client] = false;

	for(int i = 0; i < 3; i++)
	{
		gV_Point1[client][i] = 0.0;
		gV_Point2[client][i] = 0.0;
		gV_WallSnap[client][i] = 0.0;
	}
}

float[] SnapToGrid(float pos[3], int grid, bool third)
{
	float origin[3];
	origin = pos;

	origin[0] = float(RoundToNearest(pos[0] / grid) * grid);
	origin[1] = float(RoundToNearest(pos[1] / grid) * grid);
	
	if(third)
	{
		origin[2] = float(RoundToNearest(pos[2] / grid) * grid);
	}

	return origin;
}

bool SnapToWall(float pos[3], int client, float final[3])
{
	bool hit = false;

	float end[3];
	float temp[3];

	float prefinal[3];
	prefinal = pos;

	for(int i = 0; i < 4; i++)
	{
		end = pos;

		int axis = (i / 2);
		end[axis] += (((i % 2) == 1)? -gI_GridSnap[client]:gI_GridSnap[client]);

		TR_TraceRayFilter(pos, end, MASK_SOLID, RayType_EndPoint, TraceFilter_NoClients, client);

		if(TR_DidHit())
		{
			TR_GetEndPosition(temp);
			prefinal[axis] = temp[axis];
			hit = true;
		}
	}

	if(hit && GetVectorDistance(prefinal, pos) <= gI_GridSnap[client])
	{
		final = SnapToGrid(prefinal, gI_GridSnap[client], false);

		return true;
	}

	return false;
}

public bool TraceFilter_NoClients(int entity, int contentsMask, any data)
{
	return (entity != data && !IsValidClient(data));
}

float[] GetAimPosition(int client)
{
	float pos[3];
	GetClientEyePosition(client, pos);

	float angles[3];
	GetClientEyeAngles(client, angles);

	TR_TraceRayFilter(pos, angles, MASK_SHOT, RayType_Infinite, TraceFilter_NoClients, client);

	if(TR_DidHit())
	{
		float end[3];
		TR_GetEndPosition(end);

		return SnapToGrid(end, gI_GridSnap[client], true);
	}

	return pos;
}

public bool TraceFilter_World(int entity, int contentsMask)
{
	return (entity == 0);
}

public Action PropTricks_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int prop)
{
	if(gI_MapStep[client] > 0 && gI_MapStep[client] != 3 || gI_ChosenSide[client] != -1)
	{
		if((buttons & IN_USE) > 0)
		{
			if(!gB_Button[client])
			{
				float vPlayerOrigin[3];
				GetClientAbsOrigin(client, vPlayerOrigin);

				float origin[3];

				if(gB_CursorTracing[client])
				{
					origin = GetAimPosition(client);
				}

				else if(!(gB_SnapToWall[client] && SnapToWall(vPlayerOrigin, client, origin)))
				{
					origin = SnapToGrid(vPlayerOrigin, gI_GridSnap[client], false);
				}

				else
				{
					gV_WallSnap[client] = origin;
				}

				origin[2] = vPlayerOrigin[2];

				if(gI_MapStep[client] == 1)
				{
					gV_Point1[client] = origin;
					gV_Point1[client][2] += 1.0;

					Zones_ShowCreatingZonePanel(client, 2);
				}

				else if(gI_MapStep[client] == 2)
				{
					origin[2] += ZONE_HEIGHT;
					gV_Point2[client] = origin;

					gI_MapStep[client]++;

					Zones_CreateEditMenu(client);
				}
				
				else if(gI_ChosenSide[client] != -1)
				{
					static int axis[] =
					{
						0,	// Side Diagonal
						1,	// Side Diagonal
						0,	// Side Diagonal
						1,	// Side Diagonal
					};

					static int point[] =
					{
						1,	// Side Diagonal
						0,	// Side Diagonal
						0,	// Side Diagonal
						1,	// Side Diagonal
					};

					if(point[gI_ChosenSide[client]] == 1)
					{
						gV_Point1[client][axis[gI_ChosenSide[client]]] = origin[axis[gI_ChosenSide[client]]];
						gV_Point1[client][axis[gI_ChosenSide[client]]] += 1.0;
					}
					else
					{
						gV_Point2[client][axis[gI_ChosenSide[client]]] = origin[axis[gI_ChosenSide[client]]];
						gV_Point2[client][axis[gI_ChosenSide[client]]] += 1.0;
					}
				}
			}

			gB_Button[client] = true;
		}

		else
		{
			gB_Button[client] = false;
		}
	}

	return Plugin_Continue;
}

public bool TRFilter_NoPlayers(int entity, int mask, any data)
{
	return (entity != view_as<int>(data) || (entity < 1 || entity > MaxClients));
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if(gB_WaitingForChatInput[client] && gI_MapStep[client] == 3)
	{
		gI_ZoneData[client] = StringToInt(sArgs);

		Zones_CreateEditMenu(client);

		return Plugin_Handled;
	}

	return Plugin_Continue;
}

void GetAimPoint(int client, float[3] aimpos)
{
	float pos[3];
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, aimpos);

	TR_TraceRayFilter(pos, aimpos, MASK_SHOT, RayType_Infinite, TraceFilter_NoClients, client);
	
	if(TR_DidHit())
	{
		TR_GetEndPosition(aimpos);
	}
}

float[] GetSideCenter(int client, int side)
{
	float center[3] = {0.0, 0.0, 0.0};
	static int sidepairs[][] =
	{
		{ 0, 3 }, // Side Diagonal
		{ 2, 7 }, // Side Diagonal
		{ 6, 5 }, // Side Diagonal
		{ 4, 1 }  // Side Diagonal
	};

	/*static int toppairs[][] =
	{
		{ 1, 3 }, // Top
		{ 3, 7 }, // Top
		{ 7, 5 }, // Top
		{ 5, 1 }  // Top
	}

	static int downpairs[][] =
	{
		{ 0, 2 }, // Down
		{ 2, 6 }, // Down
		{ 6, 4 }, // Down 
		{ 4, 0 }  // Down
	}*/

	if(client != -1)
	{
		/*center[0] = (gV_MapZones_Visual[index][sidepairs[side][0]][0] + gV_MapZones_Visual[index][sidepairs[side][1]][0]) / 2;
		center[1] = (gV_MapZones_Visual[index][sidepairs[side][0]][1] + gV_MapZones_Visual[index][sidepairs[side][1]][1]) / 2;
		center[2] = (gV_MapZones_Visual[index][sidepairs[side][0]][2] + gV_MapZones_Visual[index][sidepairs[side][1]][2]) / 2;*/
		center[0] = (gV_EditPoints[client][sidepairs[side][0]][0] + gV_EditPoints[client][sidepairs[side][1]][0]) / 2;
		center[1] = (gV_EditPoints[client][sidepairs[side][0]][1] + gV_EditPoints[client][sidepairs[side][1]][1]) / 2;
		center[2] = (gV_EditPoints[client][sidepairs[side][0]][2] + gV_EditPoints[client][sidepairs[side][1]][2]) / 2;
	}
	return center;
}

/*static float centers[4][3];
if(!Yes)
{
	int sidepairs[][] =
	{
		{ 0, 3 },	// Side Diagonal
		{ 2, 7 },	// Side Diagonal
		{ 6, 5 },	// Side Diagonal
		{ 4, 1 },	// Side Diagonal
	};
	
	for(int i = 0; i < 4; i++)
	{
		centers[i][0] = (points[sidepairs[i][0]][0] + points[sidepairs[i][1]][0]) / 2;
		centers[i][1] = (points[sidepairs[i][0]][1] + points[sidepairs[i][1]][1]) / 2;
		centers[i][2] = (points[sidepairs[i][0]][2] + points[sidepairs[i][1]][2]) / 2;
		PrintToChatAll("%d center (%.2f %.2f %.2f)", i, centers[i][0],  centers[i][1],  centers[i][2]);
	}
	Yes = true;
}*/

public Action PropTricks_DrawEverything(Handle Timer)
{
	if(gI_MapZones == 0)
	{
		return Plugin_Continue;
	}

	static int iCycle = 0;
	static int iMaxZonesPerFrame = 5;

	if(iCycle >= gI_MapZones)
	{
		iCycle = 0;
	}

	for(int i = iCycle; i < gI_MapZones; i++)
	{
		if(gA_ZoneCache[i].bZoneInitialized)
		{
			int type = gA_ZoneCache[i].iZoneType;
			int track = gA_ZoneCache[i].iZoneTrack;

			if(gA_ZoneSettings[type][track].bVisible || (gA_ZoneCache[i].iZoneFlags & ZF_ForceRender) > 0)
			{
				DrawZone(gV_MapZones_Visual[i],
						GetZoneColors(type, track),
						RoundToCeil(float(gI_MapZones) / iMaxZonesPerFrame) * gCV_Interval.FloatValue,
						gA_ZoneSettings[type][track].fWidth,
						gA_ZoneSettings[type][track].bFlatZone,
						gV_ZoneCenter[i], track);
			}
		}

		if(++iCycle % iMaxZonesPerFrame == 0)
		{
			return Plugin_Continue;
		}
	}

	iCycle = 0;

	return Plugin_Continue;
}

int[] GetZoneColors(int type, int track, int customalpha = 0)
{
	int colors[4];
	colors[0] = gA_ZoneSettings[type][track].iRed;
	colors[1] = gA_ZoneSettings[type][track].iGreen;
	colors[2] = gA_ZoneSettings[type][track].iBlue;
	colors[3] = (customalpha > 0)? customalpha:gA_ZoneSettings[type][track].iAlpha;

	return colors;
}

public Action PropTricks_Draw(Handle Timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client == 0 || gI_MapStep[client] == 0)
	{
		Reset(client);

		return Plugin_Stop;
	}

	float vPlayerOrigin[3];
	GetClientAbsOrigin(client, vPlayerOrigin);

	float origin[3];

	if(gB_CursorTracing[client])
	{
		origin = GetAimPosition(client);
	}

	else if(!(gB_SnapToWall[client] && SnapToWall(vPlayerOrigin, client, origin)))
	{
		origin = SnapToGrid(vPlayerOrigin, gI_GridSnap[client], false);
	}

	else
	{
		gV_WallSnap[client] = origin;
	}

	if(gI_MapStep[client] == 1 || EmptyVector(gV_Point2[client]))
	{
		origin[2] = (vPlayerOrigin[2] + ZONE_HEIGHT);
	}

	else
	{
		origin = gV_Point2[client];
	}

	if(!EmptyVector(gV_Point1[client]) || !EmptyVector(gV_Point2[client]))
	{
		float points[8][3];
		points[0] = gV_Point1[client];
		points[7] = origin;
		CreateZonePoints(points, gCV_Offset.FloatValue);

		// This is here to make the zone setup grid snapping be 1:1 to how it looks when done with the setup.
		origin = points[7];
		
		for(int i = 0; i < 8; i++)
		{
			gV_EditPoints[client][i] = points[i];
		}

		int type = gI_ZoneType[client];
		int track = gI_ZoneTrack[client];

		DrawZone(points, GetZoneColors(type, track, 125), 0.1, gA_ZoneSettings[type][track].fWidth, false, origin, track, true);
	}

	if(gI_MapStep[client] != 3 && !EmptyVector(origin))
	{
		origin[2] -= ZONE_HEIGHT;

		TE_SetupBeamPoints(vPlayerOrigin, origin, gI_BeamSprite, 0, 0, 0, 0.1, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
		TE_SendToAll(0.0);

		// visualize grid snap
		float snap1[3];
		float snap2[3];

		for(int i = 0; i < 3; i++)
		{
			snap1 = origin;
			snap1[i] -= (gI_GridSnap[client] / 2);

			snap2 = origin;
			snap2[i] += (gI_GridSnap[client] / 2);

			TE_SetupBeamPoints(snap1, snap2, gI_BeamSprite, 0, 0, 0, 0.1, 1.0, 1.0, 0, 0.0, {255, 255, 255, 75}, 0);
			TE_SendToAll(0.0);
		}
	}

	return Plugin_Continue;
}

void DrawZone(float points[8][3], int color[4], float life, float width, bool flat, float center[3], int track, bool forcedraw = false)
{
	static int pairs[][] =
	{
		{ 0, 2 }, // Down
		{ 2, 6 }, // Down
		{ 6, 4 }, // Down 
		{ 4, 0 }, // Down
		{ 0, 1 }, // Vertical
		{ 2, 3 }, // Vertical
		{ 4, 5 }, // Vertical
		{ 6, 7 }, // Vertical
		{ 1, 3 }, // Top
		{ 3, 7 }, // Top
		{ 7, 5 }, // Top
		{ 5, 1 }  // Top
	};

	int[] clients = new int[MaxClients];
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && !IsFakeClient(i))
		{
			if(!forcedraw)
			{
				int target = GetSpectatorTarget(i);
				int clienttrack = PropTricks_GetClientTrack(target);
				
				if(PropTricks_GetReplayBotIndex() == target)
				{
					clienttrack = PropTricks_GetReplayBotTrack(target);
				}
				
				if(clienttrack != track)
				{
					continue;
				}
			}

			float eyes[3];
			GetClientEyePosition(i, eyes);

			if(GetVectorDistance(eyes, center) <= 1024.0 ||
				(TR_TraceRayFilter(eyes, center, CONTENTS_SOLID, RayType_EndPoint, TraceFilter_World) && !TR_DidHit()))
			{
				clients[count++] = i;
			}
		}
	}

	for(int i = 0; i < ((flat)? 4:12); i++)
	{
		TE_SetupBeamPoints(points[pairs[i][0]], points[pairs[i][1]], gI_BeamSprite, 0, 0, 0, life, width, width, 0, 0.0, color, 0);
		TE_Send(clients, count, 0.0);
	}
}

// original by blacky
// creates 3d box from 2 points
void CreateZonePoints(float point[8][3], float offset = 0.0)
{
	// calculate all zone edges
	for(int i = 1; i < 7; i++)
	{
		for(int j = 0; j < 3; j++)
		{
			point[i][j] = point[((i >> (2 - j)) & 1) * 7][j];
		}
	}

	// apply beam offset
	if(offset != 0.0)
	{
		float center[2];
		center[0] = ((point[0][0] + point[7][0]) / 2);
		center[1] = ((point[0][1] + point[7][1]) / 2);

		for(int i = 0; i < 8; i++)
		{
			for(int j = 0; j < 2; j++)
			{
				if(point[i][j] < center[j])
				{
					point[i][j] += offset;
				}

				else if(point[i][j] > center[j])
				{
					point[i][j] -= offset;
				}
			}
		}
	}
}

public void PropTricks_OnRestart(int client, int track)
{
	int iIndex = -1;

	// standard zoning
	if((iIndex = GetZoneIndex(Zone_Start, track)) != -1)
	{
		float fCenter[3];
		fCenter[0] = gV_ZoneCenter[iIndex][0];
		fCenter[1] = gV_ZoneCenter[iIndex][1];
		fCenter[2] = gV_MapZones[iIndex][0][2];

		int entity = PropTricks_GetPropEntityIndex(client);
		if(IsValidEdict(entity))
		{
			Phys_SetVelocity(entity, view_as<float>({0.0, 0.0, 0.0}), view_as<float>({0.0, 0.0, 0.0}));
			float vMaxs[3];
			GetEntPropVector(entity, Prop_Send, "m_vecMaxs", vMaxs);
			fCenter[2] += vMaxs[2];
			TeleportEntity(entity, fCenter, view_as<float>({0.0, 0.0, 0.0}), view_as<float>({0.0, 0.0, 0.0}));
			fCenter[2] += vMaxs[2];
			TeleportEntity(client, fCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
		else
		{
			TeleportEntity(client, fCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
		}
	}

	// prebuilt map zones
	else if(!EmptyVector(gF_PrebuiltZones[track][Zone_Start]))
	{
		TeleportEntity(client, gF_PrebuiltZones[track][Zone_Start], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	}

	PropTricks_StartTimer(client, track);
}

public void PropTricks_OnEnd(int client, int track)
{
	int iIndex = -1;

	if((iIndex = GetZoneIndex(Zone_End, track)) != -1)
	{
		float fCenter[3];
		fCenter[0] = gV_ZoneCenter[iIndex][0];
		fCenter[1] = gV_ZoneCenter[iIndex][1];
		fCenter[2] = gV_MapZones[iIndex][0][2];

		TeleportEntity(client, fCenter, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	}

	else if(!EmptyVector(gF_PrebuiltZones[track][Zone_End]))
	{
		TeleportEntity(client, gF_PrebuiltZones[track][Zone_End], NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
	}
}

bool EmptyVector(float vec[3])
{
	return (IsNullVector(vec) || (vec[0] == 0.0 && vec[1] == 0.0 && vec[2] == 0.0));
}

// returns -1 if there's no zone
int GetZoneIndex(int type, int track, int start = 0)
{
	if(gI_MapZones == 0)
	{
		return -1;
	}

	for(int i = start; i < gI_MapZones; i++)
	{
		if(gA_ZoneCache[i].bZoneInitialized && gA_ZoneCache[i].iZoneType == type && (gA_ZoneCache[i].iZoneTrack == track || track == -1))
		{
			return i;
		}
	}

	return -1;
}

public void Player_Spawn(Event event, const char[] name, bool dontBroadcast)
{
	Reset(GetClientOfUserId(event.GetInt("userid")));
}

public void Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	gB_ZonesCreated = false;

	RequestFrame(Frame_CreateZoneEntities);
}

public void Frame_CreateZoneEntities(any data)
{
	CreateZoneEntities();
}

float Abs(float input)
{
	if(input < 0.0)
	{
		return -input;
	}

	return input;
}

public void CreateZoneEntities()
{
	if(gB_ZonesCreated)
	{
		return;
	}

	for(int i = 0; i < gI_MapZones; i++)
	{
		for(int j = 1; j <= MaxClients; j++)
		{
			for(int k = 0; k < TRACKS_SIZE; k++)
			{
				gB_InsideZone[j][gA_ZoneCache[i].iZoneType][k] = false;
			}

			gB_InsideZoneID[j][i] = false;
		}

		if(gA_ZoneCache[i].iEntityID != -1)
		{
			KillZoneEntity(i);

			gA_ZoneCache[i].iEntityID = -1;
		}

		if(!gA_ZoneCache[i].bZoneInitialized)
		{
			continue;
		}

		int entity = CreateEntityByName("trigger_multiple");

		if(entity == -1)
		{
			LogError("\"trigger_multiple\" creation failed, map %s.", gS_Map);

			continue;
		}

		DispatchKeyValue(entity, "wait", "0");
		DispatchKeyValue(entity, "spawnflags", "4097");
		
		if(!DispatchSpawn(entity))
		{
			LogError("\"trigger_multiple\" spawning failed, map %s.", gS_Map);

			continue;
		}

		ActivateEntity(entity);
		SetEntityModel(entity, "models/props/cs_office/vending_machine.mdl");
		SetEntProp(entity, Prop_Send, "m_fEffects", 32);

		TeleportEntity(entity, gV_ZoneCenter[i], NULL_VECTOR, NULL_VECTOR);

		float distance_x = Abs(gV_MapZones[i][0][0] - gV_MapZones[i][1][0]) / 2;
		float distance_y = Abs(gV_MapZones[i][0][1] - gV_MapZones[i][1][1]) / 2;
		float distance_z = Abs(gV_MapZones[i][0][2] - gV_MapZones[i][1][2]) / 2;

		float min[3];
		min[0] = -distance_x;
		min[1] = -distance_y;
		min[2] = -distance_z;
		SetEntPropVector(entity, Prop_Send, "m_vecMins", min);

		float max[3];
		max[0] = distance_x;
		max[1] = distance_y;
		max[2] = distance_z;
		SetEntPropVector(entity, Prop_Send, "m_vecMaxs", max);

		SetEntProp(entity, Prop_Send, "m_nSolidType", 2);

		SDKHook(entity, SDKHook_StartTouchPost, StartTouchPost);
		SDKHook(entity, SDKHook_EndTouchPost, EndTouchPost);
		SDKHook(entity, SDKHook_TouchPost, TouchPost);

		gI_EntityZone[entity] = i;
		gA_ZoneCache[i].iEntityID = entity;

		char sTargetname[32];
		FormatEx(sTargetname, 32, "proptricks_zones_%d_%d", gA_ZoneCache[i].iZoneTrack, gA_ZoneCache[i].iZoneType);
		DispatchKeyValue(entity, "targetname", sTargetname);

		gB_ZonesCreated = true;
	}
}

public void StartTouchPost(int entity, int other)
{
	if(gI_EntityZone[entity] == -1 || !gA_ZoneCache[gI_EntityZone[entity]].bZoneInitialized)
	{
		return;
	}

	if(!IsValidEdict(other))
	{
		return;
	}
	
	int client = GetEntPropEnt(other, Prop_Send, "m_PredictableID");

	if(!IsValidClient(client, false) || PropTricks_GetPropEntityIndex(client) != other)
	{
		return;
	}

	if(gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack != PropTricks_GetClientTrack(client))
	{
		return;
	}

	TimerStatus status = PropTricks_GetTimerStatus(client);

	switch(gA_ZoneCache[gI_EntityZone[entity]].iZoneType)
	{
		case Zone_Stop:
		{
			if(status != Timer_Stopped)
			{
				PropTricks_StopTimer(client);
				PropTricks_PrintToChat(client, "%T", "ZoneStopEnter", client, gS_ChatStrings.sWarning, gS_ChatStrings.sVariable2, gS_ChatStrings.sWarning);
			}
		}

		case Zone_End:
		{
			if(status != Timer_Stopped && PropTricks_GetClientTrack(client) == gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack)
			{
				PropTricks_FinishMap(client, gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack);
			}
		}
	}

	gB_InsideZone[client][gA_ZoneCache[gI_EntityZone[entity]].iZoneType][gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack] = true;
	gB_InsideZoneID[client][gI_EntityZone[entity]] = true;

	Call_StartForward(gH_Forwards_EnterZone);
	Call_PushCell(client);
	Call_PushCell(gA_ZoneCache[gI_EntityZone[entity]].iZoneType);
	Call_PushCell(gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack);
	Call_PushCell(gI_EntityZone[entity]);
	Call_PushCell(entity);
	Call_PushCell(gA_ZoneCache[gI_EntityZone[entity]].iZoneData);
	Call_Finish();
}

public void EndTouchPost(int entity, int other)
{
	if(gI_EntityZone[entity] == -1 || gI_EntityZone[entity] >= sizeof(gA_ZoneCache))
	{
		return;
	}

	if(!IsValidEdict(other))
	{
		return;
	}

	int client = GetEntPropEnt(other, Prop_Send, "m_PredictableID");

	if(!IsValidClient(client, false) || PropTricks_GetPropEntityIndex(client) != other)
	{
		return;
	}

	int entityzone = gI_EntityZone[entity];
	int type = gA_ZoneCache[entityzone].iZoneType;
	int track = gA_ZoneCache[entityzone].iZoneTrack;

	gB_InsideZone[client][type][track] = false;
	gB_InsideZoneID[client][entityzone] = false;

	Call_StartForward(gH_Forwards_LeaveZone);
	Call_PushCell(client);
	Call_PushCell(type);
	Call_PushCell(track);
	Call_PushCell(entityzone);
	Call_PushCell(entity);
	Call_PushCell(gA_ZoneCache[entityzone].iZoneData);
	Call_Finish();
}

//Shit method needs to be rewritten | Maybe not
public void PropTricks_OnPropRemovePre(int client, int prop, int entity)
{
	if(PropTricks_InsideZone(client, Zone_End, -1))
	{
		int zoneid = -1;
		int track = PropTricks_GetClientTrack(client);
		
		if(PropTricks_InsideZoneGetID(client, Zone_End, track, zoneid))
		{
			gB_InsideZone[client][Zone_End][track] = false;
			gB_InsideZoneID[client][zoneid] = false;
		}
	}
}

public void TouchPost(int entity, int other)
{
	if(gI_EntityZone[entity] == -1 || !gA_ZoneCache[gI_EntityZone[entity]].bZoneInitialized)
	{
		return;
	}

	if(!IsValidEdict(other))
	{
		return;
	}
	int client = GetEntPropEnt(other, Prop_Send, "m_PredictableID");

	if(!IsValidClient(client, false) || PropTricks_GetPropEntityIndex(client) != other)
	{
		return;
	}

	if(gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack != PropTricks_GetClientTrack(client))
	{
		return;
	}

	// do precise stuff here, this will be called *A LOT*
	switch(gA_ZoneCache[gI_EntityZone[entity]].iZoneType)
	{
		case Zone_Start:
		{
			// start timer instantly for main track, but require bonuses to have the current timer stopped
			// so you don't accidentally step on those while running
			if(PropTricks_GetTimerStatus(client) == Timer_Stopped || PropTricks_GetClientTrack(client) != Track)
			{
				PropTricks_StartTimer(client, gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack);
			}

			else if(gA_ZoneCache[gI_EntityZone[entity]].iZoneTrack == Track)
			{
				PropTricks_StartTimer(client, Track);
			}
		}
	}
}

public void Phys_OnObjectSleep(int entity)
{
	if(IsValidProp(entity))
	{
		int client = GetEntPropEnt(entity, Prop_Send, "m_PredictableID");

		if(!IsValidClient(client, true) || PropTricks_GetPropEntityIndex(client) != entity)
		{
			return;
		}

		if(PropTricks_InsideZone(client, Zone_Start, -1))
		{
			Phys_Wake(entity);
		}
	}
}

public void StartTouchPost_Trigger(int entity, int other)
{
	if(other < 1 || other > MaxClients || IsFakeClient(other))
	{
		return;
	}

	int zone = -1;
	int track = Track;

	if(GetZoneIndex(zone, track) != -1)
	{
		return;
	}

	TimerStatus status = PropTricks_GetTimerStatus(other);

	if(zone == Zone_End && status != Timer_Stopped && PropTricks_GetClientTrack(other) == track)
	{
		PropTricks_FinishMap(other, track);
	}

	gB_InsideZone[other][zone][track] = true;

	Call_StartForward(gH_Forwards_EnterZone);
	Call_PushCell(other);
	Call_PushCell(zone);
	Call_PushCell(track);
	Call_PushCell(0);
	Call_PushCell(entity);
	Call_Finish();
}

public void EndTouchPost_Trigger(int entity, int other)
{
	if(other < 1 || other > MaxClients || IsFakeClient(other))
	{
		return;
	}

	int zone = -1;
	int track = Track;

	if(GetZoneIndex(zone, track) != -1)
	{
		return;
	}

	gB_InsideZone[other][zone][track] = false;

	Call_StartForward(gH_Forwards_LeaveZone);
	Call_PushCell(other);
	Call_PushCell(zone);
	Call_PushCell(track);
	Call_PushCell(0);
	Call_PushCell(entity);
	Call_Finish();
}

public void TouchPost_Trigger(int entity, int other)
{
	if(other < 1 || other > MaxClients || IsFakeClient(other))
	{
		return;
	}

	int zone = -1;
	int track = Track;

	if(GetZoneIndex(zone, track) != -1)
	{
		return;
	}

	if(zone == Zone_Start)
	{
		if(PropTricks_GetTimerStatus(other) == Timer_Stopped || PropTricks_GetClientTrack(other) != Track)
		{
			PropTricks_StartTimer(other, track);
		}

		else if(track == Track)
		{
			PropTricks_StartTimer(other, Track);
		}
	}
}