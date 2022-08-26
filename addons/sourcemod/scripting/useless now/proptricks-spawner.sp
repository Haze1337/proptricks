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
	name = "[PropTricks] Controller",
	author = "Haze",
	description = "",
	version = PROPTRICKS_VERSION,
	url = ""
}

int gI_PropType[MAXPLAYERS + 1];

static char gS_PropNames[][] = {
	"Small Box",
	"Medium Box",
	"Pallet",
	"Antique Chair",
	"Console Box",
	"Citizen Radio",
	"Oil Drum",
	"Clip Board",
	"Paint Can"
};

static char gS_PropModels[][] = {
	"models/props_junk/wood_crate001a.mdl",
	"models/props_junk/wood_crate002a.mdl",
	"models/props_junk/wood_pallet001a.mdl",
	"models/props/de_inferno/chairantique.mdl",
	"models/props_c17/consolebox01a.mdl",
	"models/props_lab/citizenradio.mdl",
	"models/props_c17/oildrum001.mdl",
	"models/props_lab/clipboard.mdl",
	"models/props_junk/metal_paintcan001b.mdl"
};

public void OnPluginStart()
{	
	RegAdminCmd("sm_spawnprop", Command_SpawnProp, ADMFLAG_ROOT, "");
	RegAdminCmd("sm_removeprop", Command_RemoveProp, ADMFLAG_ROOT, "");
}

public void OnClientPutInServer(int client)
{
	gI_PropType[client] = 0;
}

public Action Command_SpawnProp(int client, int args)
{
	SpawnPropMenu(client, 0);
	return Plugin_Handled;
}

public Action Command_RemoveProp(int client, int args)
{
	int entity = GetClientAimTarget(client, false);
	
	if(entity == -1)
	{
		return Plugin_Handled;
	}
	
	if(IsValidEdict(entity))
	{
		char sClassname[64];
		GetEntityClassname(entity, sClassname, sizeof(sClassname));
		if(StrContains(sClassname, "prop_") > -1)
		{
			RemoveEdict(entity);
		}
	}
	return Plugin_Handled;
}

void SpawnPropMenu(int client, int item)
{
	Menu menu = new Menu(Menu_Handler);
	
	menu.SetTitle("Prop Spawner\n");
	
	char sDisplay[64];
	FormatEx(sDisplay, sizeof(sDisplay), "Type: %s\n ", gI_PropType[client] ? "physics_multiplayer" : "physics");
	menu.AddItem("type", sDisplay);
	
	char sInfo[4];
	for(int i = 0; i < sizeof(gS_PropNames); i++)
	{
		IntToString(i, sInfo, sizeof(sInfo));
		menu.AddItem(sInfo, gS_PropNames[i]);
	}
	
	menu.ExitButton = true;
	menu.DisplayAt(client, item, MENU_TIME_FOREVER);
}

public int Menu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);
		
		if(StrEqual(sInfo, "type"))
		{
			gI_PropType[param1] = !gI_PropType[param1];
		}
		else
		{
			float vEyePosition[3], vEyeAngles[3], vEnd[3];
			GetClientEyePosition(param1, vEyePosition);
			GetClientEyeAngles(param1, vEyeAngles);
			TR_TraceRayFilter(vEyePosition, vEyeAngles, MASK_SOLID, RayType_Infinite, TraceFilter, param1);
			TR_GetEndPosition(vEnd);
			
			int entity = CreateEntityByName(gI_PropType[param1] ? "prop_physics_multiplayer" : "prop_physics");

			if(entity == -1)
			{
				LogError("\"prop\" creation failed");

				return 0;
			}
			
			SetEntPropEnt(entity, Prop_Send, "m_PredictableID", param1);
			
			float vPropAngles[3];
			TR_GetPlaneNormal(INVALID_HANDLE, vPropAngles);
			GetVectorAngles(vPropAngles, vPropAngles);
			vPropAngles[0] += 90.0;
			int model = StringToInt(sInfo);
			DispatchKeyValue(entity, "model", gS_PropModels[model]);
			if(gI_PropType[param1])
			{
				DispatchKeyValue(entity, "spawnflags", "260");
			}
			DispatchSpawn(entity);
			TeleportEntity(entity, vEnd, vPropAngles, NULL_VECTOR);
		}
		SpawnPropMenu(param1, GetMenuSelectionPosition());
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public bool TraceFilter(int entity, int contentsMask, any data)
{
	return (entity != data);
}