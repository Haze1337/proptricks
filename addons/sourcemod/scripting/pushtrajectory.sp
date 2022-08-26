#include "sourcemod"
#include "clientprefs"
#include "sdktools"
#include "sdkhooks"

#undef REQUIRE_PLUGIN
#include <proptricks>

bool gB_Enabled[MAXPLAYERS + 1];
bool gB_DrawAlways[MAXPLAYERS + 1];
bool gB_Visible[MAXPLAYERS + 1];

int gI_Beam = 0;

Handle gH_EnabledCookie = null;
Handle gH_DrawCookie = null;

public Plugin myinfo =
{
	name = "Centers",
	author = "GAMMACASE, Haze",
	description = "",
	version = "1.0",
	url = ""
}

public void OnPluginStart()
{
	RegConsoleCmd("sm_centers", Command_Trajectory);
	RegConsoleCmd("sm_tr", Command_Trajectory);
	RegConsoleCmd("sm_trajectory", Command_Trajectory);

	gH_EnabledCookie = RegClientCookie("trajectory_enabled", "trajectory_enabled", CookieAccess_Protected);
	gH_DrawCookie = RegClientCookie("trajectory_drawalways", "trajectory_drawalways", CookieAccess_Protected);

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsValidClient(i))
		{
			OnClientCookiesCached(i);
		}
	}
}

public void OnMapStart()
{
	AddFileToDownloadsTable("materials\\sprites\\zones6_beam_ignorez.vmt");
	gI_Beam = PrecacheModel("materials\\sprites\\zones6_beam_ignorez.vmt");

	CreateTimer(0.1, Timer_DrawTrajectory, .flags = TIMER_FLAG_NO_MAPCHANGE | TIMER_REPEAT);
}

public void OnClientPutInServer(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	gB_Visible[client] = false;

	if(!AreClientCookiesCached(client))
	{
		gB_Enabled[client] = false;
		gB_DrawAlways[client] = false;
	}
}

public void OnClientCookiesCached(int client)
{
	if(IsFakeClient(client))
	{
		return;
	}

	char sSetting[16];

	GetClientCookie(client, gH_EnabledCookie, sSetting, sizeof(sSetting));
	if(strlen(sSetting) == 0)
	{
		SetClientCookie(client, gH_EnabledCookie, "0");
		gB_Enabled[client] = false;
	}
	else
	{
		gB_Enabled[client] = view_as<bool>(StringToInt(sSetting));
	}

	GetClientCookie(client, gH_DrawCookie, sSetting, sizeof(sSetting));
	if(strlen(sSetting) == 0)
	{
		SetClientCookie(client, gH_DrawCookie, "0");
		gB_DrawAlways[client] = false;
	}
	else
	{
		gB_DrawAlways[client] = view_as<bool>(StringToInt(sSetting));
	}
}

public Action Command_Trajectory(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	Menu_Trajectory(client);

	return Plugin_Handled;
}

void Menu_Trajectory(int client)
{
	Menu menu = new Menu(MenuHandler_Trajectory);
	menu.SetTitle("Push Trajectory\n ");
	
	menu.AddItem("usage", gB_Enabled[client] ? "Enabled: [x]" : "Enabled: [ ]");
	menu.AddItem("draw", gB_DrawAlways[client] ? "Draw Always: [x]" : "Draw Always: [ ]");
	
	menu.Pagination = MENU_NO_PAGINATION;
	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int MenuHandler_Trajectory(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[16];
		menu.GetItem(param2, sInfo, 16);

		char sCookie[4];

		if(StrEqual(sInfo, "usage"))
		{
			gB_Enabled[param1] = !gB_Enabled[param1];

			IntToString(view_as<int>(gB_Enabled[param1]), sCookie, 4);
			SetClientCookie(param1, gH_EnabledCookie, sCookie);

			Menu_Trajectory(param1);
		}
		else if(StrEqual(sInfo, "draw"))
		{
			gB_DrawAlways[param1] = !gB_DrawAlways[param1];

			IntToString(view_as<int>(gB_DrawAlways[param1]), sCookie, 4);
			SetClientCookie(param1, gH_DrawCookie, sCookie);

			Menu_Trajectory(param1);
		}
	
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Timer_DrawTrajectory(Handle timer)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || IsFakeClient(i) || !gB_Enabled[i])
		{
			continue;
		}

		float vEyeAngles[3], vForward[3], vUp[3];
		GetClientEyeAngles(i, vEyeAngles);
		GetAngleVectors(vEyeAngles, vForward, NULL_VECTOR, vUp);

		float vSearchCenter[3];
		GetClientEyePosition(i, vSearchCenter);
		float vEnd[3];
		vEnd[0] = vSearchCenter[0] + vForward[0] * (96.0 * 1.0);
		vEnd[1] = vSearchCenter[1] + vForward[1] * (96.0 * 1.0);
		vEnd[2] = vSearchCenter[2] + vForward[2] * (96.0 * 1.0);
		TR_TraceRayFilter(vSearchCenter, vEnd, 0, RayType_EndPoint, TraceEntityFilterOnlyVPhysics);
		TR_GetEndPosition(vEnd);
		TR_EnumerateEntities(vSearchCenter, vEnd, PARTITION_NON_STATIC_EDICTS, RayType_EndPoint, HitProps, GetClientSerial(i));

		if(gB_DrawAlways[i])
		{
			DrawTrajectory(i, gB_Visible[i]);
			gB_Visible[i] = false;
		}
	} 
	
	return Plugin_Continue;
}

bool HitProps(int entity, any data)
{
	int client = GetClientFromSerial(data);

	char classname[64];
	GetEntityClassname(entity, classname, sizeof(classname));

	if(StrContains(classname, "prop") != -1)
	{
		if(PropTricks_GetPropEntityIndex(client) == entity)
		{
			if(gB_DrawAlways[client])
			{
				gB_Visible[client] = true;
			}
			else
			{
				DrawTrajectory(client, true);
			}
			return false;
		}
	}

	return true;
}

void DrawTrajectory(int client, bool visible)
{
	int entity = PropTricks_GetPropEntityIndex(client);
	if(entity <= 0)
	{
		return;
	}

	float fOrigin[3], fBoxOrigin[3], fTrajectory[3];
	GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", fBoxOrigin);
	GetClientAbsOrigin(client, fOrigin);
	
	SubtractVectors(fBoxOrigin, fOrigin, fTrajectory);
	NormalizeVector(fTrajectory, fTrajectory);
	fTrajectory[2] = 0.0;
	
	ScaleVector(fTrajectory, 100.0);
	AddVectors(fBoxOrigin, fTrajectory, fTrajectory);

	static int clr_red[4] = {255, 0, 0, 255};
	static int clr_green[4] = {0, 255, 0, 255};

	TE_SetupBeamPoints(fBoxOrigin, fTrajectory, gI_Beam, 0, 0, 0, 0.15, 4.0, 4.0, 0, 0.0, visible ? clr_green : clr_red, 0);
	TE_SendToClient(client);
}

bool TraceEntityFilterOnlyVPhysics(int entity, int contentsMask)
{
    return ((entity > MaxClients));// && Phys_IsPhysicsObject(entity));
}
