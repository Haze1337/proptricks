#include "sourcemod"
#include "clientprefs"
#include "sdktools"
#include "sdkhooks"

#undef REQUIRE_EXTENSIONS
#include <vphysics>

#undef REQUIRE_PLUGIN
#include <proptricks>

public Plugin myinfo =
{
	name = "MASS TEST",
	author = "",
	description = "",
	version = "1.0",
	url = ""
}

bool gB_SlowDown[MAXPLAYERS + 1] = {false, ...};

public void OnPluginStart()
{
	RegConsoleCmd("+slowdown", Command_PlusSlowDown);
	RegConsoleCmd("-slowdown", Command_MinusSlowDown);
}

public void OnClientPutInServer(int client)
{
	gB_SlowDown[client] = false;
}

public Action Command_PlusSlowDown(int client, int args)
{
	gB_SlowDown[client] = true;

	return Plugin_Handled;
}

public Action Command_MinusSlowDown(int client, int args)
{
	gB_SlowDown[client] = false;

	return Plugin_Handled;
}

public Action OnPlayerRunCmd(int client, int &buttons)
{
	if(!IsPlayerAlive(client))
	{
		return Plugin_Continue;
	}

	int entity = PropTricks_GetPropEntityIndex(client);

	if(entity <= 0 || !IsValidEntity(entity))
	{
		return Plugin_Continue;
	}

	if(gB_SlowDown[client])
	{
		float vel[3], angvel[3];
		Phys_GetVelocity(entity, vel, angvel);

		angvel[0] *= 0.95;
		angvel[1] *= 0.95;
		angvel[2] *= 0.95;

		vel[0] *= 0.95;
		vel[1] *= 0.95;
		//vel[2] *= 0.95;

		Phys_SetVelocity(entity, vel, angvel);
		
	}

	return Plugin_Continue;
}