static DynamicHook gH_IsSpawnPointValid = null;

void MiscDhooks_Init()
{
	GameData hGameData = LoadGameConfigFile("proptricks.games");

	if(hGameData == null)
	{
		delete hGameData;
		return;
	}

	int iOffset = hGameData.GetOffset("CGameRules::IsSpawnPointValid");
	if(iOffset != -1)
	{
		gH_IsSpawnPointValid = new DynamicHook(iOffset, HookType_GameRules, ReturnType_Bool, ThisPointer_Ignore);
		gH_IsSpawnPointValid.AddParam(HookParamType_CBaseEntity);
		gH_IsSpawnPointValid.AddParam(HookParamType_CBaseEntity);
	}
	else
	{
		SetFailState("[Misc] Failed to get offset for \"CGameRules::IsSpawnPointValid\"");
	}

	delete hGameData;
}

void MiscDhooks_OnMapStart()
{
	gH_IsSpawnPointValid.HookGamerules(Hook_Post, Hook_IsSpawnPointValid);
}

public MRESReturn Hook_IsSpawnPointValid(Handle hReturn, Handle hParams)
{
	DHookSetReturn(hReturn, true);
	return MRES_Supercede;
}