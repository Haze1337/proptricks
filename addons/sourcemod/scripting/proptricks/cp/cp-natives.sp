void CheckPoints_DefineNatives()
{
	CreateNative("PropTricks_GetCheckpoint", Native_GetCheckpoint);
	CreateNative("PropTricks_SetCheckpoint", Native_SetCheckpoint);
	CreateNative("PropTricks_ClearCheckpoints", Native_ClearCheckpoints);
	CreateNative("PropTricks_TeleportToCheckpoint", Native_TeleportToCheckpoint);
	CreateNative("PropTricks_GetTotalCheckpoints", Native_GetTotalCheckpoints);
	CreateNative("PropTricks_OpenCheckpointMenu", Native_OpenCheckpointMenu);
	CreateNative("PropTricks_SaveCheckpoint", Native_SaveCheckpoint);
	CreateNative("PropTricks_GetCurrentCheckpoint", Native_GetCurrentCheckpoint);
	CreateNative("PropTricks_SetCurrentCheckpoint", Native_SetCurrentCheckpoint);
}

public any Native_GetCheckpoint(Handle plugin, int numParams)
{
	if(GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(4), sizeof(cp_cache_t));
	}
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);

	cp_cache_t cpcache;
	if(gA_Checkpoints[client].GetArray(index, cpcache, sizeof(cp_cache_t)))
	{
		SetNativeArray(3, cpcache, sizeof(cp_cache_t));
		return true;
	}

	return false;
}

public any Native_SetCheckpoint(Handle plugin, int numParams)
{
	if(GetNativeCell(4) != sizeof(cp_cache_t))
	{
		return ThrowNativeError(200, "cp_cache_t does not match latest(got %i expected %i). Please update your includes and recompile your plugins",
			GetNativeCell(4), sizeof(cp_cache_t));
	}
	int client = GetNativeCell(1);
	int position = GetNativeCell(2);

	cp_cache_t cpcache;
	GetNativeArray(3, cpcache, sizeof(cp_cache_t));

	if(position == -1)
	{
		position = gI_CurrentCheckpoint[client];
	}		

	if(position >= gA_Checkpoints[client].Length)
	{
		position = gA_Checkpoints[client].Length - 1;
	}

	gA_Checkpoints[client].SetArray(position, cpcache, sizeof(cp_cache_t));
	
	return true;
}

public any Native_ClearCheckpoints(Handle plugin, int numParams)
{
	ResetCheckpoints(GetNativeCell(1));
	return 0;
}

public any Native_TeleportToCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int position = GetNativeCell(2);
	bool suppress = GetNativeCell(3);

	TeleportToCheckpoint(client, position, suppress);
	return 0;
}

public any Native_GetTotalCheckpoints(Handle plugin, int numParams)
{
	return gA_Checkpoints[GetNativeCell(1)].Length;
}

public any Native_GetCurrentCheckpoint(Handle plugin, int numParams)
{
	return gI_CurrentCheckpoint[GetNativeCell(1)];
}

public any Native_SetCurrentCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int index = GetNativeCell(2);
	
	gI_CurrentCheckpoint[client] = index;
	return 0;
}

public any Native_OpenCheckpointMenu(Handle plugin, int numParams)
{
	CheckPoints_OpenMenu(GetNativeCell(1));
	return 0;
}

public any Native_SaveCheckpoint(Handle plugin, int numParams)
{
	int client = GetNativeCell(1);
	int iMaxCPs = MAXCP;

	bool bOverflow = gA_Checkpoints[client].Length >= iMaxCPs;

	// fight an exploit
	if(bOverflow)
	{
		return -1;
	}

	if(SaveCheckpoint(client, gA_Checkpoints[client].Length))
	{
		gI_CurrentCheckpoint[client] = gA_Checkpoints[client].Length;
	}


	return gI_CurrentCheckpoint[client];
}