#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <entity>

#undef REQUIRE_PLUGIN
#include <proptricks>

#pragma newdecls required
#pragma semicolon 1

public Plugin myinfo = 
{
	name = "Prop TP",
	author = "",
	description = "",
	version = "1.0",
	url = ""
}

public void OnPluginStart()
{	
	RegConsoleCmd("sm_proptp", Command_TeleportProp, "");
}

public Action Command_TeleportProp(int client, int args)
{
	int entity = PropTricks_GetPropEntityIndex(client);

	Menu menu = new Menu(Menu_Handler);
	
	menu.SetTitle("Prop Teleport\n");

	int flag = ITEMDRAW_DEFAULT;

	if(entity <= 0 || !IsValidEntity(entity))
	{
		flag = ITEMDRAW_DISABLED;
	}
	
	menu.AddItem("cursor", "Teleport At Cursor", flag);
	menu.AddItem("player", "Teleport At Player", flag);
	
	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);

	return Plugin_Handled;
}

public int Menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		int entity = PropTricks_GetPropEntityIndex(param1);

		if(entity <= 0 || !IsValidEntity(entity))
		{
			Command_TeleportProp(param1, 0);
			return 0;
		}

		if(StrEqual(sInfo, "cursor"))
		{
			ProcessBring(param1, entity, true);
			Command_TeleportProp(param1, 0);
		}
		else if(StrEqual(sInfo, "player"))
		{
			ProcessBring(param1, entity, false);
			Command_TeleportProp(param1, 0);
		}
	
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ProcessBring(int client, int target, bool cursor)
{

	PropTricks_StopTimer(client);

	float vPlayerOrigin[3], vAimPos[3];
	GetClientAbsOrigin(client, vPlayerOrigin);

	if(cursor)
	{
		GetAimPosition(client, vAimPos);

		if(vPlayerOrigin[2] + 62.0 < vAimPos[2])
		{
			vAimPos[2] -= 62.0;
		}

		vPlayerOrigin[2] += 56;
	}
	
	//TE_SetupBeamPoints(vPlayerOrigin, vAimPos, gI_BeamSprite, 0, 0, 0, 1.0, 4.0, 4.0, 0, 0.0, {140, 80, 200, 255}, 0);
	//TE_SendToAll(0.0);

	TeleportEntity(target, cursor ? vAimPos : vPlayerOrigin, NULL_VECTOR, view_as<float>({0.0, 0.0, 0.0}));
}

void GetAimPosition(int client, float aimpos[3])
{
	float vPlayerMaxs[3], vPlayerMins[3], pos[3];
	GetEntPropVector(client, Prop_Send, "m_vecMaxs", vPlayerMaxs);
	GetEntPropVector(client, Prop_Send, "m_vecMins", vPlayerMins);
	GetClientEyePosition(client, pos);
	GetClientEyeAngles(client, aimpos);

	TR_TraceRayFilter(pos, aimpos, MASK_SOLID, RayType_Infinite, TraceFilter_NoClients, client);

	if(TR_DidHit())
	{
		TR_GetEndPosition(aimpos);
	}

	TR_TraceHullFilter(pos, aimpos, vPlayerMins, vPlayerMaxs, MASK_SOLID, TraceFilter_NoClients, client);

	TR_GetEndPosition(aimpos);
}

public bool TraceFilter_NoClients(int entity, int contentsMask, any data)
{
	return (entity != data && !IsValidClient(data));
}