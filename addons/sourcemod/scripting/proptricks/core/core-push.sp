static bool gB_Visible[MAXPLAYERS + 1];

void FindEntities(int client)
{
	bool bPressed = false;

	if(GetClientButtons(client) & IN_USE) //gA_Timers[client].iPushButton
	{
		bPressed = true;
	}

	if(bPressed)
	{
		float vEyeAngles[3], vForward[3], vUp[3];
		GetClientEyeAngles(client, vEyeAngles);
		GetAngleVectors(vEyeAngles, vForward, NULL_VECTOR, vUp);

		float vSearchCenter[3];
		GetClientEyePosition(client, vSearchCenter);
		float vEnd[3];
		vEnd[0] = vSearchCenter[0] + vForward[0] * (96.0 * 1.0);
		vEnd[1] = vSearchCenter[1] + vForward[1] * (96.0 * 1.0);
		vEnd[2] = vSearchCenter[2] + vForward[2] * (96.0 * 1.0);
		TR_TraceRayFilter(vSearchCenter, vEnd, 0, RayType_EndPoint, TraceEntityFilterOnlyVPhysics);
		TR_GetEndPosition(vEnd);
		//TE_SetupBeamPoints(vSearchCenter, vEnd, gI_BeamSprite, 0, 0, 0, 4.0, 4.0, 4.0, 0, 0.0, {255, 0, 0, 255}, 0);
		//TE_SendToAll(0.0);
		
		TR_EnumerateEntities(vSearchCenter, vEnd, PARTITION_NON_STATIC_EDICTS, RayType_EndPoint, HitProps, GetClientSerial(client));
	}

	PushEmulation(client, gB_Visible[client], bPressed);
	gB_Visible[client] = false;
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
			gB_Visible[client] = true;
			return false;
		}
	}
	return true;
}

void PushEmulation(int client, bool bIsVisible, bool bPressed)
{
	static bool bLastPush[MAXPLAYERS + 1] = {false, ...};
	bool bPush = bIsVisible && bPressed;

	if(bPush != bLastPush[client])
	{
		Action result = Plugin_Continue;
		Call_StartForward(gH_Forwards_OnPushToggle);
		Call_PushCell(client);
		Call_PushCell(bPush);
		Call_Finish(result);

		if(result != Plugin_Continue)
		{
			return;
		}
	}

	bLastPush[client] = bPush;

	if(!bIsVisible)
	{
		return;
	}

	int entity = PropTricks_GetPropEntityIndex(client);
	if(entity <= 0)
	{
		return;
	}

	if(IsValidEntity(entity))
	{
		float vPushAway[3], vWSC[3], vWSCE[3];
		vWSC = WorldSpaceCenter(client);
		vWSCE = WorldSpaceCenter(entity);

		vPushAway[0] = (vWSCE[0] - vWSC[0]);
		vPushAway[1] = (vWSCE[1] - vWSC[1]);
		vPushAway[2] = 0.0;

		/*if(vWSC[2] < vWSCE[2])
		{
			vPushAway[2] = (vWSCE[2] - vWSC[2]);
		}*/

		float flDist = NormalizeVector(vPushAway, vPushAway);
		flDist = MAX(flDist, 1.0);

		float flForce = sv_pushaway_force.FloatValue / flDist;
		flForce = MIN(flForce, sv_pushaway_max_force.FloatValue);

		vPushAway[0] *= flForce;
		vPushAway[1] *= flForce;

		/*if(vWSC[2] < vWSCE[2])
		{
			vPushAway[2] *= flForce;
		}*/

		Phys_ApplyForceOffset(entity, vPushAway, vWSC);

		Call_StartForward(gH_Forwards_OnPush);
		Call_PushCell(client);
		Call_PushCell(entity);
		Call_PushArray(vPushAway, sizeof(vPushAway));
		Call_PushCell(flForce);
		Call_Finish();

		//float vVelocity[3], vAngularVelocity[3];
		//Phys_GetVelocity(entity, vVelocity, vAngularVelocity);
		//vVelocity[2] = 0.0;
		//PrintToChatAll("Speed: %.3f | %.3f", GetVectorLength(vVelocity),  GetVectorLength(vAngularVelocity));
		//PrintToChatAll("%.2f %.2f %.2f | %.2f %.2f %.2f ", vVelocity[0], vVelocity[1], vVelocity[2], vAngularVelocity[0], vAngularVelocity[1], vAngularVelocity[2]);
	}
}

stock float MAX(float a, float b)
{
	return a > b ? a : b;
}

stock float MIN(float a, float b)
{
	return a < b ? a : b;
}

bool TraceEntityFilterOnlyVPhysics(int entity, int contentsMask)
{
    return ((entity > MaxClients) && Phys_IsPhysicsObject(entity));
}

float[] WorldSpaceCenter(int entity)
{
	float pos[3];
	if (gH_WorldSpaceCenter)
		SDKCall(gH_WorldSpaceCenter, entity, pos);
	else GetEntPropVector(entity, Prop_Data, "m_vecAbsOrigin", pos);	// If it doesn't exist then fall back to vecOrigin

	return pos;
}