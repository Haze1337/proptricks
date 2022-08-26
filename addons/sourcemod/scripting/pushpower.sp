#include "sourcemod"
#include "sdktools"
#include "sdkhooks"
#include "clientprefs"

#undef REQUIRE_PLUGIN
#include <proptricks>

#define SNAME "[ThrowPower] "

#define ACTION_STAY_TIME (3 / GetTickInterval())
#define ACTIONS_TOTAL (5)
#define BOX_USE_DISTANCE (96.0)

public Plugin myinfo =
{
	name = "Throw Power",
	author = "GAMMA CASE",
	description = "Shows additional stats when you throw the box",
	version = "1.0.0",
	url = "https://steamcommunity.com/id/_GAMMACASE_/"
};

bool gPowerEnabled[MAXPLAYERS];

bool gCurrentlyHoldingUse[MAXPLAYERS];

Handle gHudSync;

Cookie gStateCookie;

enum struct ActionData
{
	int start_tick;
	float power;
	int ticks;
	
	void Clear()
	{
		this.start_tick = 0;
		this.power = 0.0;
		this.ticks = 0;
	}
}

ArrayList gUseActions[MAXPLAYERS];

int gLatestUseStateChange[MAXPLAYERS];

bool gLate;

public void OnPluginStart()
{
	RegConsoleCmd("sm_power", SM_Power);
	RegConsoleCmd("sm_throwpower", SM_Power);
	
	gStateCookie = new Cookie("tp_enabled", "Throw power state", CookieAccess_Protected);
	
	gHudSync = CreateHudSynchronizer();
	
	if(gLate)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(!IsClientInGame(i) || IsFakeClient(i) || !AreClientCookiesCached(i))
				continue;
			
			OnClientCookiesCached(i);
		}
	}
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gLate = late;
}

public void OnClientDisconnect(int client)
{
	ClearClientVariables(client);
}

public void OnClientCookiesCached(int client)
{
	ClearClientVariables(client);
	gUseActions[client] = new ArrayList(sizeof(ActionData));
	
	char buff[8];
	gStateCookie.Get(client, buff, sizeof(buff));
	
	gPowerEnabled[client] = !!StringToInt(buff);
}

void ClearClientVariables(int client)
{
	delete gUseActions[client];
	
	gPowerEnabled[client] = false;
	gCurrentlyHoldingUse[client] = false;
	gLatestUseStateChange[client] = 0;
}

public Action SM_Power(int client, int args)
{
	if(!client)
		return Plugin_Handled;
	
	gPowerEnabled[client] = !gPowerEnabled[client];
	
	char buff[8];
	IntToString(gPowerEnabled[client], buff, sizeof(buff));
	gStateCookie.Set(client, buff);
	
	PrintToChat(client, SNAME..."Status: %s", gPowerEnabled[client] ? "Enabled" : "Disabled");
	
	return Plugin_Handled;
}

public Action PropTricks_OnPushToggle(int client, bool pressed)
{
	int curr_tick = GetGameTickCount();

	//PrintToServer(SNAME..."PushToggle(%b)", pressed);
	
	if(gLatestUseStateChange[client] + 10 < curr_tick && pressed)
	{
		ActionData ad;
		ad.Clear();
		ad.start_tick = curr_tick;
		
		gUseActions[client].PushArray(ad);
		
		if(gUseActions[client].Length > ACTIONS_TOTAL)
			gUseActions[client].Erase(0);
	}
	
	gLatestUseStateChange[client] = curr_tick;
	gCurrentlyHoldingUse[client] = pressed;
}

public void PropTricks_OnPush(int client, int entity, float pushaway[3], float force)
{
	//PrintToServer(SNAME..."OnPush(%i, %i, [%.2f | %.2f | %.2f], %.2f)", client, entity, pushaway[0], pushaway[1], pushaway[2], force);
	
	if(gUseActions[client].Length == 0)
		return;
	
	int idx = gUseActions[client].Length - 1;
	
	ActionData ad;
	gUseActions[client].GetArray(idx, ad);
	ad.power += force;
	ad.ticks += 1;
	gUseActions[client].SetArray(idx, ad);
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon, int &subtype, int &cmdnum, int &tickcount, int &seed, int mouse[2])
{
	if(IsFakeClient(client) || !gPowerEnabled[client])
		return Plugin_Continue;
	
	if(tickcount % 5 == 0)
	{
		int ent = PropTricks_GetPropEntityIndex(client);
		
		if(ent <= 0 || !IsValidEntity(ent))
			return Plugin_Continue;
		
		float dir[3], force;
		CalculateForces(client, ent, dir, force);
		
		int color[3];
		if(IsInEyeRange(client, ent, BOX_USE_DISTANCE))
		{
			color = {0, 255, 0};
		}
		else
			color = {255, 0, 0};
		
		SetHudTextParams(0.25, 0.70, 0.2, color[0], color[1], color[2], 255, 0, 0.0, 0.0, 0.0);
		static char buff[512];
		buff[0] = '\0';
		
		ProcessActions(client);
		
		Format(buff, sizeof(buff), "Force: %.0f\n", force);
		FormatActionList(client, buff, sizeof(buff));
		
		ShowSyncHudText(client, gHudSync, buff);
	}
	
	return Plugin_Continue;
}

void ProcessActions(int client)
{
	int curr_tick = GetGameTickCount();
	int stay_time = RoundToNearest(ACTION_STAY_TIME);
	
	ActionData ad;
	for(int i = gUseActions[client].Length - 1; i >= 0; i--)
	{
		gUseActions[client].GetArray(i, ad);
		if(ad.start_tick + stay_time < curr_tick)
			gUseActions[client].Erase(i);
	}
}

void FormatActionList(int client, char[] buff, int size)
{
	if(gUseActions[client].Length == 0)
		return;
	
	ActionData ad;
	for(int i = gUseActions[client].Length - 1; i >= 0; i--)
	{
		gUseActions[client].GetArray(i, ad);
		
		Format(buff, size, "%sThrow [%i]: %.0f\n", buff, ad.ticks, ad.power);
	}
}