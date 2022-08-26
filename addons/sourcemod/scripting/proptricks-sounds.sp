#include <sdktools>
#include <convar_class>

#undef REQUIRE_PLUGIN
#include <proptricks>

#pragma newdecls required
#pragma semicolon 1

bool gB_HUD = false;

ArrayList gA_FirstSounds = null;
ArrayList gA_PersonalSounds = null;
ArrayList gA_WorldSounds = null;
ArrayList gA_WorstSounds = null;
ArrayList gA_NoImprovementSounds = null;
StringMap gSM_RankSounds = null;

// cvars
Convar gCV_MinimumWorst = null;
Convar gCV_Enabled = null;

Handle gH_OnPlaySound = null;

public Plugin myinfo =
{
	name = "[PropTricks] Sounds",
	author = "Haze",
	description = "Play custom sounds when timer-related events happen.",
	version = PROPTRICKS_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("proptricks-sounds");

	return APLRes_Success;
}

public void OnAllPluginsLoaded()
{
	if(!LibraryExists("proptricks-wr"))
	{
		SetFailState("proptricks-wr is required for the plugin to work.");
	}
}

public void OnPluginStart()
{
	// cache
	gA_FirstSounds = new ArrayList(PLATFORM_MAX_PATH);
	gA_PersonalSounds = new ArrayList(PLATFORM_MAX_PATH);
	gA_WorldSounds = new ArrayList(PLATFORM_MAX_PATH);
	gA_WorstSounds = new ArrayList(PLATFORM_MAX_PATH);
	gA_NoImprovementSounds = new ArrayList(PLATFORM_MAX_PATH);
	gSM_RankSounds = new StringMap();

	// modules
	gB_HUD = LibraryExists("proptricks-hud");

	// cvars
	gCV_MinimumWorst = new Convar("proptricks_sounds_minimumworst", "10", "Minimum amount of records to be saved for a \"worst\" sound to play.", 0, true, 1.0);
	gCV_Enabled = new Convar("proptricks_sounds_enabled", "1", "Enables/Disables functionality of the plugin", 0, true, 0.0, true, 1.0);

	Convar.AutoExecConfig();

	gH_OnPlaySound = CreateGlobalForward("PropTricks_OnPlaySound", ET_Event, Param_Cell, Param_String, Param_Cell, Param_Array, Param_CellByRef);
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "proptricks-hud"))
	{
		gB_HUD = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "proptricks-hud"))
	{
		gB_HUD = false;
	}
}

public void OnMapStart()
{
	gA_FirstSounds.Clear();
	gA_PersonalSounds.Clear();
	gA_WorldSounds.Clear();
	gA_WorstSounds.Clear();
	gA_NoImprovementSounds.Clear();
	gSM_RankSounds.Clear();

	char sFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sFile, PLATFORM_MAX_PATH, "configs/proptricks-sounds.cfg");

	File fFile = OpenFile(sFile, "r"); // readonly, unless i implement in-game editing

	if(fFile == null && gCV_Enabled.BoolValue)
	{
		SetFailState("Cannot open \"configs/proptricks-sounds.cfg\". Make sure this file exists and that the server has read permissions to it.");
	}

	else
	{
		char sLine[PLATFORM_MAX_PATH*2];
		char sDownloadString[PLATFORM_MAX_PATH];

		while(fFile.ReadLine(sLine, PLATFORM_MAX_PATH*2))
		{
			TrimString(sLine);

			if(sLine[0] != '\"')
			{
				continue;
			}

			ReplaceString(sLine, PLATFORM_MAX_PATH*2, "\"", "");

			char sExploded[2][PLATFORM_MAX_PATH];
			ExplodeString(sLine, " ", sExploded, 2, PLATFORM_MAX_PATH);

			if(StrEqual(sExploded[0], "first"))
			{
				gA_FirstSounds.PushString(sExploded[1]);
			}

			else if(StrEqual(sExploded[0], "personal"))
			{
				gA_PersonalSounds.PushString(sExploded[1]);
			}

			else if(StrEqual(sExploded[0], "world"))
			{
				gA_WorldSounds.PushString(sExploded[1]);
			}

			else if(StrEqual(sExploded[0], "worst"))
			{
				gA_WorstSounds.PushString(sExploded[1]);
			}

			else if(StrEqual(sExploded[0], "worse") || StrEqual(sExploded[0], "noimprovement"))
			{
				gA_NoImprovementSounds.PushString(sExploded[1]);
			}

			else
			{
				gSM_RankSounds.SetString(sExploded[0], sExploded[1]);
			}

			if(PrecacheSound(sExploded[1], true))
			{
				FormatEx(sDownloadString, PLATFORM_MAX_PATH, "sound/%s", sExploded[1]);
				AddFileToDownloadsTable(sDownloadString);
			}

			else
			{
				LogError("\"sound/%s\" could not be accessed.", sExploded[1]);
			}
		}
	}

	delete fFile;
}

public void PropTricks_OnFinish(int client, int prop, float time, int track, float oldtime)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	if(oldtime != 0.0 && time > oldtime && gA_NoImprovementSounds.Length != 0)
	{
		char sSound[PLATFORM_MAX_PATH];
		gA_NoImprovementSounds.GetString(GetRandomInt(0, gA_NoImprovementSounds.Length - 1), sSound, PLATFORM_MAX_PATH);

		PlayEventSound(client, false, sSound);
	}
}

public void PropTricks_OnFinish_Post(int client, int prop, float time, int rank, int overwrite, int track, float oldtime)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	float fOldTime = PropTricks_GetClientPB(client, prop, track);

	char sSound[PLATFORM_MAX_PATH];
	bool bEveryone = false;

	char sRank[8];
	IntToString(rank, sRank, 8);

	if((time < fOldTime || fOldTime == 0.0) && gSM_RankSounds.GetString(sRank, sSound, PLATFORM_MAX_PATH))
	{
		bEveryone = true;
	}

	else if(gA_WorldSounds.Length != 0 && rank == 1)
	{
		bEveryone = true;

		gA_WorldSounds.GetString(GetRandomInt(0, gA_WorldSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}

	else if(gA_PersonalSounds.Length != 0 && time < fOldTime)
	{
		gA_PersonalSounds.GetString(GetRandomInt(0, gA_PersonalSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}

	else if(gA_FirstSounds.Length != 0 && overwrite == 1)
	{
		gA_FirstSounds.GetString(GetRandomInt(0, gA_FirstSounds.Length - 1), sSound, PLATFORM_MAX_PATH);
	}

	if(StrContains(sSound, ".") != -1) // file has an extension?
	{
		PlayEventSound(client, bEveryone, sSound);
	}
}

public void PropTricks_OnWorstRecord(int client, int prop, float time, int track, float oldtime)
{
	if(!gCV_Enabled.BoolValue)
	{
		return;
	}

	if(gA_WorstSounds.Length != 0 && PropTricks_GetRecordAmount(prop, track) >= gCV_MinimumWorst.IntValue)
	{
		char sSound[PLATFORM_MAX_PATH];
		gA_WorstSounds.GetString(GetRandomInt(0, gA_WorstSounds.Length - 1), sSound, PLATFORM_MAX_PATH);

		if(StrContains(sSound, ".") != -1)
		{
			PlayEventSound(client, false, sSound);
		}
	}
}

void PlayEventSound(int client, bool everyone, char sound[PLATFORM_MAX_PATH])
{
	int[] clients = new int[MaxClients];
	int count = 0;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || (gB_HUD && (PropTricks_GetHUDSettings(i) & HUD_NOSOUNDS) > 0))
		{
			continue;
		}

		if(everyone)
		{
			clients[count++] = i;

			continue;
		}

		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		// add player and their spectators
		if(i == client || (IsClientObserver(i) && (iObserverMode >= 3 || iObserverMode <= 5) && GetEntPropEnt(i, Prop_Send, "m_hObserverTarget") == client))
		{
			clients[count++] = i;
		}
	}


	Action result = Plugin_Continue;
	Call_StartForward(gH_OnPlaySound);
	Call_PushCell(client);
	Call_PushStringEx(sound, PLATFORM_MAX_PATH, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
	Call_PushCell(PLATFORM_MAX_PATH);
	Call_PushArrayEx(clients, MaxClients, SM_PARAM_COPYBACK);
	Call_PushCellRef(count);
	Call_Finish(result);

	if(result != Plugin_Continue && result != Plugin_Changed)
	{
		return;
	}

	if(count > 0)
	{
		EmitSound(clients, count, sound);
	}
}
