#include <sourcemod>
#include <sdktools_functions>
#include <vphysics>

#undef REQUIRE_PLUGIN
#include <proptricks>

#pragma newdecls required
#pragma semicolon 1

#define MAXCP 1000

// Checkpoints
ArrayList gA_Checkpoints[MAXPLAYERS+1];
int gI_CurrentCheckpoint[MAXPLAYERS+1];

// Forwards
Handle gH_Forwards_OnSave = null;
Handle gH_Forwards_OnTeleport = null;
Handle gH_Forwards_OnDelete = null;
Handle gH_Forwards_OnCheckpointMenuMade = null;
Handle gH_Forwards_OnCheckpointMenuSelect = null;

// Chat settings
chatstrings_t gS_ChatStrings;

// Late load
bool gB_Late = false;

#include "proptricks/cp/cp-menu.sp"
#include "proptricks/cp/cp-natives.sp"

public Plugin myinfo =
{
	name = "[PropTricks] CheckPoints",
	author = "Haze",
	description = "",
	version = PROPTRICKS_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CheckPoints_DefineNatives();

	RegPluginLibrary("proptricks-cp");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	// Forwards
	gH_Forwards_OnSave = CreateGlobalForward("PropTricks_OnSave", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnTeleport = CreateGlobalForward("PropTricks_OnTeleport", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointMenuMade = CreateGlobalForward("PropTricks_OnCheckpointMenuMade", ET_Event, Param_Cell, Param_Cell);
	gH_Forwards_OnCheckpointMenuSelect = CreateGlobalForward("PropTricks_OnCheckpointMenuSelect", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell, Param_Cell, Param_Cell);
	gH_Forwards_OnDelete = CreateGlobalForward("PropTricks_OnDelete", ET_Event, Param_Cell, Param_Cell);

	// Checkpoints
	RegConsoleCmd("sm_cp", Command_Checkpoints, "Opens the checkpoints menu.");
	RegConsoleCmd("sm_cpmenu", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cp.");
	RegConsoleCmd("sm_checkpoints", Command_Checkpoints, "Opens the checkpoints menu. Alias for sm_cp.");

	RegConsoleCmd("sm_save", Command_Save, "Saves checkpoint.");
	RegConsoleCmd("sm_tele", Command_Tele, "Teleports to checkpoint. Usage: sm_tele [number]");
	
	LoadTranslations("proptricks-cp.phrases");

	// late load
	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);
			}
		}
		
		PropTricks_GetChatStrings(gS_ChatStrings);
	}
}

public void OnMapStart()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		ResetCheckpoints(i);
	}
}

public void OnMapEnd()
{
	for(int i = 1; i <= MaxClients; i++)
	{
		ResetCheckpoints(i);
	}
}

public void PropTricks_OnChatConfigLoaded(chatstrings_t strings)
{
	gS_ChatStrings = strings;
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	if(gA_Checkpoints[client] == null)
	{
		gA_Checkpoints[client] = new ArrayList(sizeof(cp_cache_t));	
	}
	else 
	{
		gA_Checkpoints[client].Clear();
	}
}

public void OnClientDisconnect(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	ResetCheckpoints(client);
	delete gA_Checkpoints[client];
}

void ResetCheckpoints(int client)
{
	if(gA_Checkpoints[client] != null)
	{
		gA_Checkpoints[client].Clear();
	}

	gI_CurrentCheckpoint[client] = 0;
}


public Action Command_Checkpoints(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	CheckPoints_OpenMenu(client);

	return Plugin_Handled;
}

public Action Command_Save(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	int iMaxCPs = MAXCP;
	bool bOverflow = gA_Checkpoints[client].Length >= iMaxCPs;
	int index = gA_Checkpoints[client].Length;

	if(index > iMaxCPs)
	{
		index = iMaxCPs;
	}

	if(bOverflow)
	{
		PropTricks_PrintToChat(client, "%T", "MiscCheckpointsOverflow", client, index, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	if(SaveCheckpoint(client, index))
	{
		gI_CurrentCheckpoint[client] = gA_Checkpoints[client].Length;
		PropTricks_PrintToChat(client, "%T", "MiscCheckpointsSaved", client, gI_CurrentCheckpoint[client], gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}


	return Plugin_Handled;
}

public Action Command_Tele(int client, int args)
{
	if(client == 0)
	{
		ReplyToCommand(client, "This command may be only performed in-game.");

		return Plugin_Handled;
	}

	int index = gI_CurrentCheckpoint[client];

	if(args > 0)
	{
		char arg[4];
		GetCmdArg(1, arg, 4);

		int parsed = StringToInt(arg);

		if(0 < parsed <= MAXCP)
		{
			index = parsed;
		}
	}

	TeleportToCheckpoint(client, index, true);

	return Plugin_Handled;
}

bool SaveCheckpoint(int client, int index)
{
	if(!IsValidClient(client))
	{
		return false;
	}

	int target = GetSpectatorTarget(client);
	int iFlags = GetEntityFlags(client);
	
	if(target == client && !IsPlayerAlive(client))
	{
		PropTricks_PrintToChat(client, "%T", "CommandAliveSpectate", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return false;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnSave);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_Finish(result);
	
	if(result != Plugin_Continue)
	{
		return false;
	}

	gI_CurrentCheckpoint[client] = index;

	cp_cache_t cpcache;
	GetClientAbsOrigin(target, cpcache.fPosition);
	GetClientEyeAngles(target, cpcache.fAngles);
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", cpcache.fVelocity);

	int entity = PropTricks_GetPropEntityIndex(client);
	if(IsValidEdict(entity))
	{
		GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", cpcache.fPropPosition);
		GetEntPropVector(entity, Prop_Data, "m_angRotation", cpcache.fPropAngles); 
		Phys_GetVelocity(entity, cpcache.fPropVelocity, cpcache.fPropAngularVelocity); 
	}

	cpcache.iMoveType = GetEntityMoveType(target);

	if(IsFakeClient(target))
	{
		iFlags |= FL_CLIENT;
		iFlags |= FL_AIMTARGET;
		iFlags &= ~FL_ATCONTROLS;
		iFlags &= ~FL_FAKECLIENT;

		cpcache.fStamina = 0.0;
		cpcache.iGroundEntity = -1;
	}
	else
	{
		cpcache.fStamina = GetEntPropFloat(target, Prop_Send, "m_flStamina");
		cpcache.iGroundEntity = GetEntPropEnt(target, Prop_Data, "m_hGroundEntity");
	}

	cpcache.iFlags = iFlags;

	cpcache.bDucked = view_as<bool>(GetEntProp(target, Prop_Send, "m_bDucked"));
	cpcache.bDucking = view_as<bool>(GetEntProp(target, Prop_Send, "m_bDucking"));
	cpcache.fDucktime = GetEntPropFloat(target, Prop_Send, "m_flDucktime");

	cpcache.iSerial = GetClientSerial(target);

	gA_Checkpoints[client].Push(0);
	gA_Checkpoints[client].SetArray(index, cpcache);
	
	return true;
}

void TeleportToCheckpoint(int client, int index, bool suppressMessage)
{
	if(index < 1 || index > MAXCP)
	{
		return;
	}

	cp_cache_t cpcache;

	if(index > gA_Checkpoints[client].Length)
	{
		PropTricks_PrintToChat(client, "%T", "MiscCheckpointsEmpty", client, index, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		return;
	}

	gA_Checkpoints[client].GetArray(index - 1, cpcache, sizeof(cp_cache_t));

	if(IsNullVector(cpcache.fPosition))
	{
		return;
	}

	if(!IsPlayerAlive(client))
	{
		PropTricks_PrintToChat(client, "%T", "CommandAlive", client, gS_ChatStrings.sVariable, gS_ChatStrings.sText);

		return;
	}

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnTeleport);
	Call_PushCell(client);
	Call_PushCell(index - 1);
	Call_Finish(result);
	
	if(result != Plugin_Continue)
	{
		return;
	}

	PropTricks_StopTimer(client);

	MoveType mt = cpcache.iMoveType;

	if(mt == MOVETYPE_LADDER || mt == MOVETYPE_WALK)
	{
		SetEntityMoveType(client, mt);
	}

	SetEntityFlags(client, cpcache.iFlags);
	SetEntPropEnt(client, Prop_Data, "m_hGroundEntity", cpcache.iGroundEntity);
	SetEntPropFloat(client, Prop_Send, "m_flStamina", cpcache.fStamina);
	SetEntProp(client, Prop_Send, "m_bDucked", cpcache.bDucked);
	SetEntProp(client, Prop_Send, "m_bDucking", cpcache.bDucking);
	SetEntPropFloat(client, Prop_Send, "m_flDucktime", cpcache.fDucktime);

	TeleportEntity(client, cpcache.fPosition, cpcache.fAngles, cpcache.fVelocity);

	int entity = PropTricks_GetPropEntityIndex(client);
	if(IsValidEdict(entity))
	{
		TeleportEntity(entity, cpcache.fPropPosition, cpcache.fPropAngles, view_as<float>({0.0, 0.0, 0.0}));
		Phys_SetVelocity(entity, cpcache.fPropVelocity, cpcache.fPropAngularVelocity);
	}
	
	if(!suppressMessage)
	{
		PropTricks_PrintToChat(client, "%T", "MiscCheckpointsTeleported", client, index, gS_ChatStrings.sVariable, gS_ChatStrings.sText);
	}
}

bool DeleteCheckpoint(int client, int index)
{
	Action result = Plugin_Continue;

	Call_StartForward(gH_Forwards_OnDelete);
	Call_PushCell(client);
	Call_PushCell(index);
	Call_Finish(result);

	if(result != Plugin_Continue)
	{
		return false;
	}

	gA_Checkpoints[client].Erase(index);

	return true;
}