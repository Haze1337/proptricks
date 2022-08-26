static bool gB_StopChatSound = false;

void Natives_Define()
{
	CreateNative("PropTricks_GetWorldSpaceCenter", Native_GetWorldSpaceCenter);
	CreateNative("PropTricks_GetPropEntityIndex", Native_GetPropEntityIndex);
	CreateNative("PropTricks_ChangeClientProp", Native_ChangeClientProp);
	CreateNative("PropTricks_FinishMap", Native_FinishMap);
	CreateNative("PropTricks_GetClientProp", Native_GetClientProp);
	CreateNative("PropTricks_GetChatStrings", Native_GetChatStrings);
	CreateNative("PropTricks_GetClientTime", Native_GetClientTime);
	CreateNative("PropTricks_GetClientTrack", Native_GetClientTrack);
	CreateNative("PropTricks_GetDatabase", Native_GetDatabase);
	CreateNative("PropTricks_GetDB", Native_GetDB);
	CreateNative("PropTricks_GetOrderedProps", Native_GetOrderedProps);
	CreateNative("PropTricks_GetPropCount", Native_GetPropCount);
	CreateNative("PropTricks_GetPropSettings", Native_GetPropSettings);
	CreateNative("PropTricks_GetPropStrings", Native_GetPropStrings);
	CreateNative("PropTricks_GetTimeOffset", Native_GetTimeOffset);
	CreateNative("PropTricks_GetDistanceOffset", Native_GetTimeOffsetDistance);
	CreateNative("PropTricks_GetTimer", Native_GetTimer);
	CreateNative("PropTricks_GetTimerStatus", Native_GetTimerStatus);
	CreateNative("PropTricks_LogMessage", Native_LogMessage);
	CreateNative("PropTricks_PrintToChat", Native_PrintToChat);
	CreateNative("PropTricks_RestartTimer", Native_RestartTimer);
	CreateNative("PropTricks_StartTimer", Native_StartTimer);
	CreateNative("PropTricks_StopChatSound", Native_StopChatSound);
	CreateNative("PropTricks_StopTimer", Native_StopTimer);
}

public int Native_GetWorldSpaceCenter(Handle handler, int numParams)
{
	int entity = GetNativeCell(1);

	float vWSC[3];
	vWSC = WorldSpaceCenter(entity);
	SetNativeArray(2, vWSC, sizeof(vWSC));
}

public int Native_GetOrderedProps(Handle handler, int numParams)
{
	return SetNativeArray(1, gI_OrderedProps, GetNativeCell(2));
}

public int Native_GetDatabase(Handle handler, int numParams)
{
	return view_as<int>(CloneHandle(gH_SQL, handler));
}

public int Native_GetDB(Handle handler, int numParams)
{
	SetNativeCellRef(1, gH_SQL);
}

public int Native_GetTimer(Handle handler, int numParams)
{
	// 1 - client
	int client = GetNativeCell(1);

	// 2 - time
	SetNativeCellRef(2, gA_Timers[client].fTimer);
	SetNativeCellRef(3, gA_Timers[client].iProp);
	SetNativeCellRef(4, gA_Timers[client].bEnabled);
}

public int Native_GetClientTime(Handle handler, int numParams)
{
	return view_as<int>(gA_Timers[GetNativeCell(1)].fTimer);
}

public int Native_GetClientTrack(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iTrack;
}

public int Native_GetClientProp(Handle handler, int numParams)
{
	return gA_Timers[GetNativeCell(1)].iProp;
}

public int Native_GetPropEntityIndex(Handle handler, int numParams)
{
	int entity = gA_Timers[GetNativeCell(1)].iEntityIndex;
	return IsValidEdict(entity) && Phys_IsPhysicsObject(entity) ? entity : -1;
}

public int Native_GetTimerStatus(Handle handler, int numParams)
{
	return GetTimerStatus(GetNativeCell(1));
}

public int Native_StartTimer(Handle handler, int numParams)
{
	StartTimer(GetNativeCell(1), GetNativeCell(2));
}

public int Native_StopTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	bool bBypass = (numParams < 2 || view_as<bool>(GetNativeCell(2)));

	if(!bBypass)
	{
		bool bResult = true;
		Call_StartForward(gH_Forwards_OnStopPre);
		Call_PushCell(client);
		Call_PushCell(gA_Timers[client].iTrack);
		Call_Finish(bResult);

		if(!bResult)
		{
			return false;
		}
	}

	StopTimer(client);

	Call_StartForward(gH_Forwards_OnStop);
	Call_PushCell(client);
	Call_PushCell(gA_Timers[client].iTrack);
	Call_Finish();

	return true;
}

public int Native_ChangeClientProp(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int prop = GetNativeCell(2);
	bool force = view_as<bool>(GetNativeCell(3));
	bool manual = view_as<bool>(GetNativeCell(4));
	bool noforward = view_as<bool>(GetNativeCell(5));

	if(force)
	{
		if(noforward)
		{
			gA_Timers[client].iProp = prop;
		}

		else
		{
			CallOnPropChanged(client, gA_Timers[client].iProp, prop, manual);
		}

		return true;
	}

	return false;
}

public int Native_FinishMap(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	CalculateTickIntervalOffset(client, Zone_End);
	gA_Timers[client].fTimer += gA_Timers[client].fTimeOffset[Zone_Start];
	gA_Timers[client].fTimer -= GetTickInterval();
	gA_Timers[client].fTimer += gA_Timers[client].fTimeOffset[Zone_End];

	Action result = Plugin_Continue;
	Call_StartForward(gH_Forwards_OnFinishPre);
	Call_PushCell(client);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	Call_StartForward(gH_Forwards_OnFinish);
	Call_PushCell(client);

	int prop = 0;

	if(result == Plugin_Continue)
	{
		Call_PushCell(prop = gA_Timers[client].iProp);
		Call_PushCell(gA_Timers[client].fTimer);
		Call_PushCell(gA_Timers[client].iTrack);
	}

	float oldtime = 0.0;

	if(gB_WR)
	{
		oldtime = PropTricks_GetClientPB(client, prop, gA_Timers[client].iTrack);
	}

	Call_PushCell(oldtime);
	Call_Finish();

	StopTimer(client);
}

public any Native_GetTimeOffset(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int zonetype = GetNativeCell(2);

	if(zonetype > 1 || zonetype < 0)
	{
		return ThrowNativeError(32, "ZoneType is out of bounds");
	}
	return gA_Timers[client].fTimeOffset[zonetype];
}

public any Native_GetTimeOffsetDistance(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int zonetype = GetNativeCell(2);

	if(zonetype > 1 || zonetype < 0)
	{
		return ThrowNativeError(32, "ZoneType is out of bounds");
	}

	return gA_Timers[client].fDistanceOffset[zonetype];
}

public int Native_StopChatSound(Handle handler, int numParams)
{
	gB_StopChatSound = true;
}

public int Native_PrintToChat(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	static int iWritten = 0; // useless?

	char sBuffer[300];
	FormatNativeString(0, 2, 3, 300, iWritten, sBuffer);
	Format(sBuffer, 300, "%s %s%s", gS_ChatStrings.sPrefix, gS_ChatStrings.sText, sBuffer);

	if(client == 0)
	{
		PrintToServer("%s", sBuffer);

		return false;
	}

	if(!IsClientInGame(client))
	{
		gB_StopChatSound = false;

		return false;
	}

	Handle hSayText2 = StartMessageOne("SayText2", client, USERMSG_RELIABLE|USERMSG_BLOCKHOOKS);
	BfWrite bfmsg = UserMessageToBfWrite(hSayText2);
	bfmsg.WriteByte(client);
	bfmsg.WriteByte(!gB_StopChatSound);
	bfmsg.WriteString(sBuffer);

	EndMessage();

	gB_StopChatSound = false;

	return true;
}

public int Native_RestartTimer(Handle handler, int numParams)
{
	int client = GetNativeCell(1);
	int track = GetNativeCell(2);

	Call_StartForward(gH_Forwards_OnRestart);
	Call_PushCell(client);
	Call_PushCell(track);
	Call_Finish();

	StartTimer(client, track);
}

public int Native_GetPropCount(Handle handler, int numParams)
{
	return (gI_Props > 0)? gI_Props:-1;
}

public int Native_GetPropSettings(Handle handler, int numParams)
{
	if(GetNativeCell(3) != sizeof(propsettings_t))
	{
		return ThrowNativeError(200, "stylesettings_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(3), sizeof(propsettings_t));
	}
	return SetNativeArray(2, gA_PropSettings[GetNativeCell(1)], sizeof(propsettings_t));
}

public int Native_GetPropStrings(Handle handler, int numParams)
{
	int prop = GetNativeCell(1);
	int type = GetNativeCell(2);
	int size = GetNativeCell(4);

	switch(type)
	{
		case sPropName: return SetNativeString(3, gS_PropStrings[prop].sPropName, size);
		case sShortName: return SetNativeString(3, gS_PropStrings[prop].sShortName, size);
		case sModelPath: return SetNativeString(3, gS_PropStrings[prop].sModelPath, size);
		case sChangeCommand: return SetNativeString(3, gS_PropStrings[prop].sChangeCommand, size);
		case sSpecialString: return SetNativeString(3, gS_PropStrings[prop].sSpecialString, size);
	}

	return -1;
}

public int Native_GetChatStrings(Handle handler, int numParams)
{
	int iSize = GetNativeCell(2);

	if(iSize != sizeof(chatstrings_t))
	{
		return ThrowNativeError(200,
			"chatstrings_t does not match latest(got %i expected %i). "...
			"Please update your includes and recompile your plugins",
		iSize, sizeof(chatstrings_t));
	}

	return SetNativeArray(1, gS_ChatStrings, sizeof(gS_ChatStrings));
}

public int Native_LogMessage(Handle plugin, int numParams)
{
	char sPlugin[32];

	if(!GetPluginInfo(plugin, PlInfo_Name, sPlugin, 32))
	{
		GetPluginFilename(plugin, sPlugin, 32);
	}

	static int iWritten = 0;

	char sBuffer[300];
	FormatNativeString(0, 1, 2, 300, iWritten, sBuffer);

	LogToFileEx(gS_LogPath, "[%s] %s", sPlugin, sBuffer);
}