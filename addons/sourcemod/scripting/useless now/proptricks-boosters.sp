#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <outputinfo>
#include <vphysics>

#pragma newdecls required

#undef REQUIRE_PLUGIN
#include <proptricks>

//#define DEBUG

public Plugin myinfo = 
{
	name = "[PropTricks] BaseVel Boosters",
	author = "Haze",
	description = "",
	version = "1.0",
	url = "http://steamcommunity.com/id/0x0134/"
};

//"m_OnEndTouchAll", "m_OnStartTouchAll"
static char sMultipleOutputs[][] = { "m_OnTrigger", "m_OnEndTouch", "m_OnStartTouch" };
static SDKHookType iMultipleOutputs[] = { SDKHook_Touch, SDKHook_EndTouch, SDKHook_StartTouch };
int gI_BaseVelocity[2048][3];

//Other
bool gB_LateLoad = false;
//------------

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	gB_LateLoad = late;
	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	HookEvent("round_start", OnRoundStart, EventHookMode_Pre);
}

public void OnPluginStart()
{
	if(gB_LateLoad)
	{
		int entity;
		while ((entity = FindEntityByClassname(entity, "trigger_*")) != -1)
		{
			HookTriggers(entity);
		}
	}
}

public Action OnRoundStart(Event event, char[] name, bool dontBroadcast)
{
	int entity;
	while ((entity = FindEntityByClassname(entity, "trigger_*")) != -1)
	{
		HookTriggers(entity);
	}
}

void HookTriggers(int entity)
{
	char sClassname[64];
	GetEntityClassname(entity, sClassname, 64);
	if(StrEqual(sClassname, "trigger_multiple"))
	{
		for(int j = 0; j < sizeof(sMultipleOutputs); j++)
		{
			int count = GetOutputActionCount(entity, sMultipleOutputs[j]);
			for(int i = 0; i < count; i++)
			{
				char sParameter[32];
				GetOutputActionParameter(entity, sMultipleOutputs[j], i, sParameter, sizeof(sParameter));
				
				if(StrContains(sParameter, "basevelocity") != -1)
				{
					char sExplodeString[4][8];
					ExplodeString(sParameter, " ", sExplodeString, 4, 8);
					gI_BaseVelocity[entity][0] = StringToInt(sExplodeString[1]);
					gI_BaseVelocity[entity][1] = StringToInt(sExplodeString[2]);
					gI_BaseVelocity[entity][2] = StringToInt(sExplodeString[3]);
					SDKHook(entity, iMultipleOutputs[j], EndTouchFix);
				}
			}
		}
	}
}

public Action EndTouchFix(int entity, int other)
{
	//PrintToChatAll("%d %d", entity, other);
	if(IsValidEntity(other) && Phys_IsPhysicsObject(other))
	{
		float vVelocity[3], vAngularVelocity[3];
		Phys_GetVelocity(other, vVelocity, vAngularVelocity);
		//PrintToChatAll("%f %f %f", vVelocity[0], vVelocity[1], vVelocity[2]);
		vVelocity[0] = vVelocity[0] + gI_BaseVelocity[entity][0];
		vVelocity[1] = vVelocity[1] + gI_BaseVelocity[entity][1];
		vVelocity[2] = vVelocity[2] + gI_BaseVelocity[entity][2];
		//PrintToChatAll("%d %d %d", gI_BaseVelocity[entity][0], gI_BaseVelocity[entity][1], gI_BaseVelocity[entity][2]);
		Phys_SetVelocity(other, vVelocity, vAngularVelocity);
		//PrintToChatAll("%f %f %f", vVelocity[0], vVelocity[1], vVelocity[2]);
	}
	return Plugin_Continue;
}