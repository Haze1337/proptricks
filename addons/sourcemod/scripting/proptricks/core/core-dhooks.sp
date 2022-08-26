#define OS_WINDOWS 1

#define WINDOWS_OFFSET  0x81
#define LINUX_OFFSET    0x74

static Address g_PlayerUse = Address_Null;
static Address g_PatchOffset = Address_Null;

static int iByteToWrite = 0x85;
static int iPatchRestore = -1;

// Windows
// 0x35
// sub_100F3B10+34   A8 01                        test    al, 1           ; Logical Compare
// sub_100F3B10+34   A8 00                        test    al, 0           ; Logical Compare

// Linux
// 0x37
// PlayerUse(void)+31   F6 83 CC 0A 00 00 08      test    byte ptr [ebx+0ACCh], 8 ; Logical Compare
// PlayerUse(void)+31   F6 83 CC 0A 00 00 00      test    byte ptr [ebx+0ACCh], 0 ; Logical Compare

/*
#define WINDOWS_OFFSET  0xD7
#define LINUX_OFFSET    0x182

static Address g_PlayerUse = Address_Null;
static Address g_PatchOffset = Address_Null;

static int iBytesToWrite[4] = {0x00, 0x00, 0x00, 0x00};
static int iPatchRestore[4] = {-1, ...};
*/

// NEED TO PATCH DIFFERENT PLACE

// Windows
// D7
// 0B 40 00 02 MASK_SOLID
// 00 00 00 00 0x0

// Linux
// 182
// 0B 40 00 02 MASK_SOLID
// 00 00 00 00 0x0

void CoreDhooks_Init()
{
	GameData hGameData = new GameData("proptricks.games");

	if(hGameData == null)
	{
		SetFailState("Failed to load proptricks gamedata.");
	}

	Hook_ProcessMovement(hGameData);
	Hook_PassEntityFilter(hGameData);
	Hook_ShouldCollide(hGameData);

	PrepSDKCall_WorldSpaceCenter(hGameData);

	Patch_PlayerUse(hGameData);
	
	delete hGameData;
}

void Hook_ProcessMovement(GameData hGameData)
{
	StartPrepSDKCall(SDKCall_Static);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Signature, "CreateInterface");
	PrepSDKCall_AddParameter(SDKType_String, SDKPass_Pointer);
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Pointer, VDECODE_FLAG_ALLOWNULL);
	PrepSDKCall_SetReturnInfo(SDKType_PlainOldData, SDKPass_Plain);
	
	Handle hCreateInterface = EndPrepSDKCall();
	if(hCreateInterface == null)
	{
		SetFailState("Unable to prepare SDKCall for CreateInterface");
	}

	char sInterfaceName[64];
	if(!hGameData.GetKeyValue("IGameMovement", sInterfaceName, sizeof(sInterfaceName)))
	{
		SetFailState("Failed to get IGameMovement interface name");
	}

	Address pIGameMovement = SDKCall(hCreateInterface, sInterfaceName, 0);
	if(!pIGameMovement)
	{
		SetFailState("Failed to get IGameMovement pointer");
	}

	int offset = hGameData.GetOffset("ProcessMovement");
	if(offset == -1)
	{
		SetFailState("Failed to get ProcessMovement offset");
	}

	DynamicHook processMovement = new DynamicHook(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore);
	processMovement.AddParam(HookParamType_CBaseEntity);
	processMovement.AddParam(HookParamType_ObjectPtr);
	processMovement.HookRaw(Hook_Pre, pIGameMovement, DHook_ProcessMovement);

	DynamicHook processMovementPost = new DynamicHook(offset, HookType_Raw, ReturnType_Void, ThisPointer_Ignore);
	processMovementPost.AddParam(HookParamType_CBaseEntity);
	processMovementPost.AddParam(HookParamType_ObjectPtr);
	processMovementPost.HookRaw(Hook_Post, pIGameMovement, DHook_ProcessMovementPost);

	delete hCreateInterface;
}

public MRESReturn DHook_ProcessMovement(DHookParam hParams)
{
	int client = hParams.Get(1);

	Call_StartForward(gH_Forwards_OnProcessMovement);
	Call_PushCell(client);
	Call_Finish();

	return MRES_Ignored;
}

public MRESReturn DHook_ProcessMovementPost(DHookParam hParams)
{
	int client = hParams.Get(1);

	Call_StartForward(gH_Forwards_OnProcessMovementPost);
	Call_PushCell(client);
	Call_Finish();

	float frametime = GetGameFrameTime();

	if(!gA_Timers[client].bEnabled)
	{
		return MRES_Ignored;
	}

	float time = frametime;

	gA_Timers[client].iZoneIncrement++;
	
	gA_Timers[client].fTimer += time;
	
	return MRES_Ignored;
}

void Hook_PassEntityFilter(GameData hGameData)
{
	DynamicDetour hFunction = new DynamicDetour(Address_Null, CallConv_CDECL, ReturnType_Int, ThisPointer_Ignore); 
	hFunction.SetFromConf(hGameData, SDKConf_Signature, "PassServerEntityFilter");
	hFunction.AddParam(HookParamType_CBaseEntity);
	hFunction.AddParam(HookParamType_CBaseEntity);
	if(!hFunction.Enable(Hook_Post, DHook_PassEntityFilter))
	{
		SetFailState("Failed to detour PassEntityFilter.");
	}
}

public MRESReturn DHook_PassEntityFilter(DHookReturn hReturn, DHookParam hParams)
{
	if(!hParams.IsNull(1) && !hParams.IsNull(2))
	{
		int iEntity1 = hParams.Get(1);
		int iEntity2 = hParams.Get(2);

		if(iEntity1 == iEntity2)
		{
			return MRES_Ignored;
		}

		int funcresult = hReturn.Value;
		
		if(gH_Forwards_OnPassEntityFilter)
		{
			Action result = Plugin_Continue;
			
			/* Start function call */
			Call_StartForward(gH_Forwards_OnPassEntityFilter);

			/* Push parameters one at a time */
			Call_PushCell(iEntity1);
			Call_PushCell(iEntity2);
			Call_PushCellRef(funcresult);

			/* Finish the call, get the result */
			Call_Finish(result);
			
			if (result == Plugin_Handled)
			{
				hReturn.Value = funcresult;
				return MRES_Supercede;
			}
		}
	}

	return MRES_Ignored;
} 

void Hook_ShouldCollide(GameData hGameData)
{
	DynamicDetour hFunction = new DynamicDetour(Address_Null, CallConv_THISCALL, ReturnType_Int, ThisPointer_Ignore); 
	hFunction.SetFromConf(hGameData, SDKConf_Signature, "CCollisionEvent::ShouldCollide");
	hFunction.AddParam(HookParamType_Int);
	hFunction.AddParam(HookParamType_Int);
	hFunction.AddParam(HookParamType_CBaseEntity);
	hFunction.AddParam(HookParamType_CBaseEntity);
	if(!hFunction.Enable(Hook_Post, DHook_ShouldCollide))
	{
		SetFailState("Failed to detour CCollisionEvent::ShouldCollide.");
	}
}

public MRESReturn DHook_ShouldCollide(DHookReturn hReturn, DHookParam hParams)
{
	if(!hParams.IsNull(3) && !hParams.IsNull(4))
	{
		int iEntity1 = hParams.Get(3);
		int iEntity2 = hParams.Get(4);

		if(iEntity1 == iEntity2)
		{
			return MRES_Ignored;
		}

		int funcresult = hReturn.Value;
		
		if(gH_Forwards_OnShouldCollide)
		{
			Action result = Plugin_Continue;
			
			/* Start function call */
			Call_StartForward(gH_Forwards_OnShouldCollide);

			/* Push parameters one at a time */
			Call_PushCell(iEntity1);
			Call_PushCell(iEntity2);
			Call_PushCellRef(funcresult);

			/* Finish the call, get the result */
			Call_Finish(result);
			
			if (result == Plugin_Handled)
			{
				hReturn.Value = funcresult;
				return MRES_Supercede;
			}
		}
	}

	return MRES_Ignored;
}

void PrepSDKCall_WorldSpaceCenter(GameData hGameData)
{
	StartPrepSDKCall(SDKCall_Entity);
	PrepSDKCall_SetFromConf(hGameData, SDKConf_Virtual, "WorldSpaceCenter");
	PrepSDKCall_SetReturnInfo(SDKType_Vector, SDKPass_ByRef);
	gH_WorldSpaceCenter = EndPrepSDKCall();
	if (gH_WorldSpaceCenter == null)
	{
		LogError("Could not initialize call to WorldSpaceCenter. Falling back to m_vecOrigin.");
	}
}

void Patch_PlayerUse(GameData hGameData)
{
	int iOS = hGameData.GetOffset("OS");
	if(iOS == -1)
	{
		SetFailState("Failed to get OS offset");
	}

	g_PatchOffset = view_as<Address>((iOS == OS_WINDOWS) ? WINDOWS_OFFSET : LINUX_OFFSET);

	g_PlayerUse = hGameData.GetAddress("CBasePlayer::PlayerUse");
	if(g_PlayerUse == Address_Null)
	{
		SetFailState("Failed to get CBasePlayer::PlayerUse Address");
	}

	g_PlayerUse += g_PatchOffset;

	/*
	Address iTempAddress = g_PlayerUse;
	for(int i = 0; i < sizeof(iBytesToWrite); i++)
	{
		iPatchRestore[i] = LoadFromAddress(iTempAddress, NumberType_Int8);
		PrintToServer("Before: 0x%02X", iPatchRestore[i]);
		StoreToAddress(iTempAddress, iBytesToWrite[i], NumberType_Int8);
		PrintToServer("After: 0x%02X", LoadFromAddress(iTempAddress, NumberType_Int8));
		iTempAddress++;
	}
	*/

	iPatchRestore = LoadFromAddress(g_PlayerUse, NumberType_Int8);
	PrintToServer("Before: 0x%02X", iPatchRestore);
	StoreToAddress(g_PlayerUse, iByteToWrite, NumberType_Int8);
	PrintToServer("After: 0x%02X", LoadFromAddress(g_PlayerUse, NumberType_Int8));
}

void Patch_OnPluginEnd()
{
	// Restore the original instructions, if we patched them.
	if(g_PlayerUse != Address_Null)
	{
		/*
		for(int i = 0; i < sizeof(iPatchRestore); i++)
		{
			if(iPatchRestore[i] != -1)
			{
				PrintToServer("Restore: 0x%02X", iPatchRestore[i]);
				StoreToAddress(g_PlayerUse, iPatchRestore[i], NumberType_Int8);
				g_PlayerUse++;
			}
		}
		*/

		PrintToServer("Restore: 0x%02X", iPatchRestore);
		StoreToAddress(g_PlayerUse, iPatchRestore, NumberType_Int8);
	}
}