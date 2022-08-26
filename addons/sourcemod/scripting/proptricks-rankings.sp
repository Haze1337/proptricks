#include <sourcemod>
#include <convar_class>

#undef REQUIRE_PLUGIN
#include <proptricks>

#undef REQUIRE_EXTENSIONS
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

// uncomment when done
// #define DEBUG

enum struct ranking_t
{
	int iRank;
	float fPoints;
	int iWRAmountAll;
}

Database gH_SQL = null;	

bool gB_Stats = false;
bool gB_Late = false;
bool gB_TierQueried = false;

int gI_Tier = 1;

char gS_Map[160];

ArrayList gA_ValidMaps = null;
StringMap gA_MapTiers = null;

Convar gCV_PointsPerTier = null;
Convar gCV_WeightingMultiplier = null;
Convar gCV_LastLoginRecalculate = null;
Convar gCV_MVPRankOnes = null;

ranking_t gA_Rankings[MAXPLAYERS+1];

int gI_RankedPlayers = 0;
Menu gH_Top100Menu = null;

Handle gH_Forwards_OnTierAssigned = null;
Handle gH_Forwards_OnRankAssigned = null;

// Timer settings.
chatstrings_t gS_ChatStrings;
int gI_Props = 0;
propsettings_t gA_PropSettings[PROP_LIMIT];
char gS_PropNames[PROP_LIMIT][64];
char gS_TrackNames[TRACKS_SIZE][32];

public Plugin myinfo =
{
	name = "[PropTricks] Rankings",
	author = "Haze",
	description = "Ranking system for proptricks timer.",
	version = PROPTRICKS_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	CreateNative("PropTricks_GetMapTier", Native_GetMapTier);
	CreateNative("PropTricks_GetMapTiers", Native_GetMapTiers);
	CreateNative("PropTricks_GetPoints", Native_GetPoints);
	CreateNative("PropTricks_GetRank", Native_GetRank);
	CreateNative("PropTricks_GetRankedPlayers", Native_GetRankedPlayers);
	CreateNative("PropTricks_Rankings_DeleteMap", Native_Rankings_DeleteMap);
	CreateNative("PropTricks_GetWRCount", Native_GetWRCount);
	
	RegPluginLibrary("proptricks-rankings");

	gB_Late = late;

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
	gH_Forwards_OnTierAssigned = CreateGlobalForward("PropTricks_OnTierAssigned", ET_Event, Param_String, Param_Cell);
	gH_Forwards_OnRankAssigned = CreateGlobalForward("PropTricks_OnRankAssigned", ET_Event, Param_Cell, Param_Cell, Param_Cell, Param_Cell);

	RegConsoleCmd("sm_tier", Command_Tier, "Prints the map's tier to chat.");
	RegConsoleCmd("sm_maptier", Command_Tier, "Prints the map's tier to chat. (sm_tier alias)");

	RegConsoleCmd("sm_rank", Command_Rank, "Show your or someone else's rank. Usage: sm_rank [name]");
	RegConsoleCmd("sm_top", Command_Top, "Show the top 100 players.");

	RegAdminCmd("sm_settier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_settier <tier>");
	RegAdminCmd("sm_setmaptier", Command_SetTier, ADMFLAG_RCON, "Change the map's tier. Usage: sm_setmaptier <tier> (sm_settier alias)");

	RegAdminCmd("sm_recalcmap", Command_RecalcMap, ADMFLAG_RCON, "Recalculate the current map's records' points.");

	RegAdminCmd("sm_recalcall", Command_RecalcAll, ADMFLAG_ROOT, "Recalculate the points for every map on the server. Run this after you change the ranking multiplier for a prop or after you install the plugin.");

	gCV_PointsPerTier = new Convar("proptricks_rankings_pointspertier", "50.0", "Base points to use for per-tier scaling.", 0, true, 1.0);
	
	gCV_WeightingMultiplier = new Convar("proptricks_rankings_weighting", "0.975", 
	"Weighing multiplier. 1.0 to disable weighting.\n" ...
	"Formula: p[1] * this^0 + p[2] * this^1 + p[3] * this^2 + ... + p[n] * this^(n-1)\n" ...
	"Restart server to apply.", 0, true, 0.01, true, 1.0);
	
	gCV_LastLoginRecalculate = new Convar("proptricks_rankings_llrecalc", "10080", 
	"Maximum amount of time (in minutes) since last login to recalculate points for a player.\n" ...
	"sm_recalcall does not respect this setting.\n" ...
	"0 - disabled, don't filter anyone", 0, true, 0.0);
	
	gCV_MVPRankOnes = new Convar("proptricks_rankings_mvprankones", "1", 
	"Set the players' amount of MVPs to the amount of #1 times they have.\n" ...
	"0 - Disabled\n" ...
	"1 - Enabled, for all props.", 0, true, 0.0, true, 1.0);

	Convar.AutoExecConfig();

	LoadTranslations("common.phrases");
	LoadTranslations("proptricks-common.phrases");
	LoadTranslations("proptricks-rankings.phrases");

	// tier cache
	gA_ValidMaps = new ArrayList(128);
	gA_MapTiers = new StringMap();

	if(gB_Late)
	{
		PropTricks_GetChatStrings(gS_ChatStrings);
	}
	
	CreateTimer(1.0, PropTricks_MVPs, 0, TIMER_REPEAT);

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		GetTrackName(LANG_SERVER, i, gS_TrackNames[i], 32);
	}
}

public void PropTricks_OnChatConfigLoaded(chatstrings_t strings)
{
	gS_ChatStrings = strings;
}

public void PropTricks_OnPropConfigLoaded(int props)
{
	if(props == -1)
	{
		gI_Props = PropTricks_GetPropCount();
	}

	for(int i = 0; i < gI_Props; i++)
	{
		PropTricks_GetPropSettings(i, gA_PropSettings[i]);
		PropTricks_GetPropStrings(i, sPropName, gS_PropNames[i], 64);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "proptricks-stats"))
	{
		gB_Stats = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "proptricks-stats"))
	{
		gB_Stats = false;
	}
}

public void PropTricks_OnDatabaseLoaded()
{
	gH_SQL = GetTimerDatabaseHandle();

	if(!IsMySQLDatabase(gH_SQL))
	{
		SetFailState("MySQL is the only supported database engine for proptricks-rankings.");
	}

	char sQuery[256];
	FormatEx(sQuery, 256, "CREATE TABLE IF NOT EXISTS `maptiers` (`map` VARCHAR(128), `tier` INT NOT NULL DEFAULT 1, PRIMARY KEY (`map`)) ENGINE=INNODB;");

	gH_SQL.Query(SQL_CreateTable_Callback, sQuery, 0);
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings) error! Map tiers table creation failed. Reason: %s", error);

		return;
	}

	#if defined DEBUG
	PrintToServer("DEBUG: 0 (SQL_CreateTable_Callback)");
	#endif

	if(gI_Props == 0)
	{
		PropTricks_OnPropConfigLoaded(-1);
	}

	SQL_LockDatabase(gH_SQL);
	SQL_FastQuery(gH_SQL, "DELIMITER ;;");
	SQL_FastQuery(gH_SQL, "DROP PROCEDURE IF EXISTS UpdateAllPoints;;"); // old (and very slow) deprecated method
	SQL_FastQuery(gH_SQL, "DROP FUNCTION IF EXISTS GetWeightedPoints;;"); // this is here, just in case we ever choose to modify or optimize the calculation
	SQL_FastQuery(gH_SQL, "DROP FUNCTION IF EXISTS GetRecordPoints;;");

	bool bSuccess = true;

	RunLongFastQuery(bSuccess, "CREATE GetWeightedPoints",
		"CREATE FUNCTION GetWeightedPoints(steamid INT) " ...
		"RETURNS FLOAT " ...
		"READS SQL DATA " ...
		"BEGIN " ...
		"DECLARE p FLOAT; " ...
		"DECLARE total FLOAT DEFAULT 0.0; " ...
		"DECLARE mult FLOAT DEFAULT 1.0; " ...
		"DECLARE done INT DEFAULT 0; " ...
		"DECLARE cur CURSOR FOR SELECT points FROM playertimes WHERE auth = steamid AND points > 0.0 ORDER BY points DESC; " ...
		"DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1; " ...
		"OPEN cur; " ...
		"iter: LOOP " ...
			"FETCH cur INTO p; " ...
			"IF done THEN " ...
				"LEAVE iter; " ...
			"END IF; " ...
			"SET total = total + (p * mult); " ...
			"SET mult = mult * %f; " ...
		"END LOOP; " ...
		"CLOSE cur; " ...
		"RETURN total; " ...
		"END;;", gCV_WeightingMultiplier.FloatValue);

	RunLongFastQuery(bSuccess, "CREATE GetRecordPoints",
		"CREATE FUNCTION GetRecordPoints(rprop INT, rtrack INT, rtime FLOAT, rmap VARCHAR(128), pointspertier FLOAT, propmultiplier FLOAT) " ...
		"RETURNS FLOAT " ...
		"READS SQL DATA " ...
		"BEGIN " ...
		"DECLARE pwr, ppoints FLOAT DEFAULT 0.0; " ...
		"DECLARE ptier INT DEFAULT 1; " ...
		"SELECT tier FROM maptiers WHERE map = rmap INTO ptier; " ...
		"SELECT MIN(time) FROM playertimes WHERE map = rmap AND prop = rprop AND track = rtrack INTO pwr; " ...
		"IF rtrack > 0 THEN SET ptier = 1; END IF; " ...
		"SET ppoints = ((pointspertier * ptier) * 1.5) + (pwr / 15.0); " ...
		"IF rtime > pwr THEN SET ppoints = ppoints * (pwr / rtime); END IF; " ...
		"SET ppoints = ppoints * propmultiplier; " ...
		"IF rtrack > 0 THEN SET ppoints = ppoints * 0.25; END IF; " ...
		"RETURN ppoints; " ...
		"END;;");

	SQL_FastQuery(gH_SQL, "DELIMITER ;");
	SQL_UnlockDatabase(gH_SQL);

	if(!bSuccess)
	{
		return;
	}

	OnMapStart();

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			OnClientConnected(i);
		}
	}
}

void RunLongFastQuery(bool &success, const char[] func, const char[] query, any ...)
{
	char sQuery[2048];
	VFormat(sQuery, 2048, query, 4);

	if(!SQL_FastQuery(gH_SQL, sQuery))
	{
		char sError[255];
		SQL_GetError(gH_SQL, sError, 255);
		LogError("Timer (rankings, %s) error! Reason: %s", func, sError);

		success = false;
	}
}

public void OnClientConnected(int client)
{
	gA_Rankings[client].iRank = 0;
	gA_Rankings[client].fPoints = 0.0;
	gA_Rankings[client].iWRAmountAll = 0;
}

public void OnClientPostAdminCheck(int client)
{
	if(!IsFakeClient(client))
	{
		UpdateWRs(client);
		UpdatePlayerRank(client, true);
	}
}

public void OnMapStart()
{
	if (gH_SQL == null)
	{
		return;
	}
	
	// do NOT keep running this more than once per map, as UpdateAllPoints() is called after this eventually and locks up the database while it is running
	if(gB_TierQueried)
	{
		return;
	}

	#if defined DEBUG
	PrintToServer("DEBUG: 1 (OnMapStart)");
	#endif

	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	// Default tier.
	// I won't repeat the same mistake blacky has done with tier 3 being default..
	gI_Tier = 1;

	char sQuery[256];
	FormatEx(sQuery, 256, "SELECT tier FROM maptiers WHERE map = '%s';", gS_Map);
	gH_SQL.Query(SQL_GetMapTier_Callback, sQuery);

	gB_TierQueried = true;
}

public void SQL_GetMapTier_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, get map tier) error! Reason: %s", error);

		return;
	}

	#if defined DEBUG
	PrintToServer("DEBUG: 2 (SQL_GetMapTier_Callback)");
	#endif

	if(results.RowCount > 0 && results.FetchRow())
	{
		gI_Tier = results.FetchInt(0);

		#if defined DEBUG
		PrintToServer("DEBUG: 3 (tier: %d) (SQL_GetMapTier_Callback)", gI_Tier);
		#endif

		RecalculateAll(gS_Map);
		UpdateAllPoints();

		#if defined DEBUG
		PrintToServer("DEBUG: 4 (SQL_GetMapTier_Callback)");
		#endif

		char sQuery[256];
		FormatEx(sQuery, 256, "SELECT map, tier FROM maptiers;", gS_Map);
		gH_SQL.Query(SQL_FillTierCache_Callback, sQuery, 0, DBPrio_High);
	}

	else
	{
		char sQuery[256];
		FormatEx(sQuery, 256, "REPLACE INTO maptiers (map, tier) VALUES ('%s', %d);", gS_Map, gI_Tier);
		gH_SQL.Query(SQL_SetMapTier_Callback, sQuery, gI_Tier, DBPrio_High);
	}
}

public void SQL_FillTierCache_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, fill tier cache) error! Reason: %s", error);

		return;
	}

	gA_ValidMaps.Clear();
	gA_MapTiers.Clear();

	while(results.FetchRow())
	{
		char sMap[160];
		results.FetchString(0, sMap, 160);

		int tier = results.FetchInt(1);

		gA_MapTiers.SetValue(sMap, tier);
		gA_ValidMaps.PushString(sMap);

		Call_StartForward(gH_Forwards_OnTierAssigned);
		Call_PushString(sMap);
		Call_PushCell(tier);
		Call_Finish();
	}

	SortADTArray(gA_ValidMaps, Sort_Ascending, Sort_String);
}

public void OnMapEnd()
{
	RecalculateAll(gS_Map);
	gB_TierQueried = false;
}

public Action PropTricks_MVPs(Handle timer)
{
	if (gCV_MVPRankOnes.IntValue == 0)
	{
		return Plugin_Continue;
	}

	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsValidClient(i))
		{
			CS_SetMVPCount(i, gA_Rankings[i].iWRAmountAll);
		}
	}

	return Plugin_Continue;
}

public Action Command_Tier(int client, int args)
{
	int tier = gI_Tier;

	char sMap[128];

	if(args == 0)
	{
		strcopy(sMap, 128, gS_Map);
	}
	
	else
	{
		GetCmdArgString(sMap, 128);
		if(!GuessBestMapName(gA_ValidMaps, sMap, sMap, 128) || !gA_MapTiers.GetValue(sMap, tier))
		{
			PropTricks_PrintToChat(client, "%t", "Map was not found", sMap);
			return Plugin_Handled;
		}
	}

	PropTricks_PrintToChat(client, "%T", "CurrentTier", client, gS_ChatStrings.sVariable, sMap, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Rank(int client, int args)
{
	int target = client;

	if(args > 0)
	{
		char sArgs[MAX_TARGET_LENGTH];
		GetCmdArgString(sArgs, MAX_TARGET_LENGTH);

		target = FindTarget(client, sArgs, true, false);

		if(target == -1)
		{
			return Plugin_Handled;
		}
	}

	if(gA_Rankings[target].fPoints == 0.0)
	{
		PropTricks_PrintToChat(client, "%T", "Unranked", client, gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText);

		return Plugin_Handled;
	}

	PropTricks_PrintToChat(client, "%T", "Rank", client, gS_ChatStrings.sVariable2, target, gS_ChatStrings.sText,
		gS_ChatStrings.sVariable, (gA_Rankings[target].iRank > gI_RankedPlayers)? gI_RankedPlayers:gA_Rankings[target].iRank, gS_ChatStrings.sText,
		gI_RankedPlayers,
		gS_ChatStrings.sVariable, gA_Rankings[target].fPoints, gS_ChatStrings.sText);

	return Plugin_Handled;
}

public Action Command_Top(int client, int args)
{
	if(gH_Top100Menu != null)
	{
		gH_Top100Menu.SetTitle("%T (%d)\n ", "Top100", client, gI_RankedPlayers);
		gH_Top100Menu.Display(client, 60);
	}

	return Plugin_Handled;
}

public int MenuHandler_Top(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);

		if(gB_Stats && !StrEqual(sInfo, "-1"))
		{
			PropTricks_OpenStatsMenu(param1, StringToInt(sInfo));
		}
	}

	return 0;
}

public Action Command_SetTier(int client, int args)
{
	char sArg[8];
	GetCmdArg(1, sArg, 8);
	
	int tier = StringToInt(sArg);

	if(args == 0 || tier < 1 || tier > 10)
	{
		ReplyToCommand(client, "%T", "ArgumentsMissing", client, "sm_settier <tier> (1-10)");

		return Plugin_Handled;
	}

	gI_Tier = tier;
	gA_MapTiers.SetValue(gS_Map, tier);

	Call_StartForward(gH_Forwards_OnTierAssigned);
	Call_PushString(gS_Map);
	Call_PushCell(tier);
	Call_Finish();

	PropTricks_PrintToChat(client, "%T", "SetTier", client, gS_ChatStrings.sVariable2, tier, gS_ChatStrings.sText);

	char sQuery[256];
	FormatEx(sQuery, 256, "REPLACE INTO maptiers (map, tier) VALUES ('%s', %d);", gS_Map, tier);

	gH_SQL.Query(SQL_SetMapTier_Callback, sQuery);

	return Plugin_Handled;
}

public void SQL_SetMapTier_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, set map tier) error! Reason: %s", error);

		return;
	}

	RecalculateAll(gS_Map);
}

public Action Command_RecalcMap(int client, int args)
{
	RecalculateAll(gS_Map);
	UpdateAllPoints();

	ReplyToCommand(client, "Done.");

	return Plugin_Handled;
}

public Action Command_RecalcAll(int client, int args)
{
	ReplyToCommand(client, "- Started recalculating points for all maps. Check console for output.");

	Transaction trans = new Transaction();

	for(int i = 0; i < gI_Props; i++)
	{
		char sQuery[192];
			
		if(gA_PropSettings[i].bUnranked || gA_PropSettings[i].fRankingMultiplier == 0.0)
		{
			FormatEx(sQuery, 192, "UPDATE playertimes SET points = 0 WHERE prop = %d;", i);
		}
		else
		{
			FormatEx(sQuery, 192, "UPDATE playertimes SET points = GetRecordPoints(%d, track, time, map, %.1f, %.3f) WHERE prop = %d;", i, gCV_PointsPerTier.FloatValue, gA_PropSettings[i].fRankingMultiplier, i);
		}
	
		trans.AddQuery(sQuery);
	}

	gH_SQL.Execute(trans, Trans_OnRecalcSuccess, Trans_OnRecalcFail, (client == 0)? 0:GetClientSerial(client));

	return Plugin_Handled;
}

public void Trans_OnRecalcSuccess(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	int client = (data == 0)? 0:GetClientFromSerial(data);

	if(client != 0)
	{
		SetCmdReplySource(SM_REPLY_TO_CONSOLE);
	}

	ReplyToCommand(client, "- Finished recalculating all points. Recalculating user points, top 100 and user cache.");

	UpdateAllPoints(true);
	UpdateTop100();

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i) && IsClientAuthorized(i))
		{
			UpdateWRs(client);
			UpdatePlayerRank(i, false);
		}
	}

	ReplyToCommand(client, "- Done.");
}

public void Trans_OnRecalcFail(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (rankings) error! Recalculation failed. Reason: %s", error);
}

void RecalculateAll(const char[] map)
{
	#if defined DEBUG
	LogError("DEBUG: 5 (RecalculateAll)");
	#endif

	for(int i = 0; i < TRACKS_SIZE; i++)
	{
		for(int j = 0; j < gI_Props; j++)
		{
			if(gA_PropSettings[j].bUnranked)
			{
				continue;
			}
			
			RecalculateMap(map, i, j);
		}
	}
}

public void PropTricks_OnFinish_Post(int client, int prop, float time, int rank, int overwrite, int track)
{
	RecalculateMap(gS_Map, track, prop);
}

void RecalculateMap(const char[] map, const int track, const int prop)
{
	#if defined DEBUG
	PrintToServer("Recalculating points. (%s, %d, %d)", map, track, prop);
	#endif

	char sQuery[256];
	FormatEx(sQuery, 256, "UPDATE playertimes SET points = GetRecordPoints(%d, %d, time, '%s', %.1f, %.3f) WHERE prop = %d AND track = %d AND map = '%s';",
		prop, track, map, gCV_PointsPerTier.FloatValue, gA_PropSettings[prop].fRankingMultiplier, prop, track, map);

	gH_SQL.Query(SQL_Recalculate_Callback, sQuery, 0, DBPrio_High);

	#if defined DEBUG
	PrintToServer("Sent query.");
	#endif
}

public void SQL_Recalculate_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	if(results == null)
	{
		LogError("Timer (rankings, recalculate map points) error! Reason: %s", error);

		return;
	}

	#if defined DEBUG
	PrintToServer("Recalculated.");
	#endif
}

void UpdateAllPoints(bool recalcall = false)
{
	#if defined DEBUG
	LogError("DEBUG: 6 (UpdateAllPoints)");
	#endif

	char sQuery[256];

	if(recalcall || gCV_LastLoginRecalculate.IntValue == 0)
	{
		FormatEx(sQuery, 256, "UPDATE users SET points = GetWeightedPoints(auth) WHERE auth IN (SELECT DISTINCT auth FROM playertimes);");
	}

	else
	{
		FormatEx(sQuery, 256, "UPDATE users SET points = GetWeightedPoints(auth) WHERE lastlogin > %d AND auth IN (SELECT DISTINCT auth FROM playertimes);",
			(GetTime() - gCV_LastLoginRecalculate.IntValue * 60));
	}
	
	gH_SQL.Query(SQL_UpdateAllPoints_Callback, sQuery);
}

public void SQL_UpdateAllPoints_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update all points) error! Reason: %s", error);

		return;
	}

	UpdateRankedPlayers();
}

void UpdateWRs(int client)
{
	gA_Rankings[client].iWRAmountAll = 0;
	
	int iSteamID = 0;

	if((iSteamID = GetSteamAccountID(client)) != 0)
	{
		char sQuery[512];

		FormatEx(sQuery, 512,
			"SELECT COUNT(*) FROM playertimes a JOIN (SELECT MIN(time) time, map, prop FROM playertimes GROUP by map, prop, track) b ON a.time = b.time AND a.map = b.map AND a.prop = b.prop WHERE auth = %d;",
			iSteamID);

		gH_SQL.Query(SQL_UpdateWRs_Callback, sQuery, GetClientSerial(client));
	}
}

public void SQL_UpdateWRs_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (get WR amount) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0 || !results.FetchRow())
	{
		return;
	}

	int iWRs = results.FetchInt(0);

	if(gCV_MVPRankOnes.IntValue != 0)
	{
		CS_SetMVPCount(client, iWRs);
	}

	gA_Rankings[client].iWRAmountAll = iWRs;
}

void UpdatePlayerRank(int client, bool first)
{
	gA_Rankings[client].iRank = 0;
	gA_Rankings[client].fPoints = 0.0;

	int iSteamID = 0;

	if((iSteamID = GetSteamAccountID(client)) != 0)
	{
		// if there's any issue with this query,
		// add "ORDER BY points DESC " before "LIMIT 1"
		char sQuery[512];
		FormatEx(sQuery, 512, "SELECT u2.points, COUNT(*) FROM users u1 JOIN (SELECT points FROM users WHERE auth = %d) u2 WHERE u1.points >= u2.points;",
			iSteamID);

		DataPack hPack = new DataPack();
		hPack.WriteCell(GetClientSerial(client));
		hPack.WriteCell(first);

		gH_SQL.Query(SQL_UpdatePlayerRank_Callback, sQuery, hPack, DBPrio_Low);
	}
}

public void SQL_UpdatePlayerRank_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack hPack = view_as<DataPack>(data);
	hPack.Reset();

	int iSerial = hPack.ReadCell();
	bool bFirst = view_as<bool>(hPack.ReadCell());
	delete hPack;

	if(results == null)
	{
		LogError("Timer (rankings, update player rank) error! Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(iSerial);

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		gA_Rankings[client].fPoints = results.FetchFloat(0);
		gA_Rankings[client].iRank = (gA_Rankings[client].fPoints > 0.0)? results.FetchInt(1):0;

		Call_StartForward(gH_Forwards_OnRankAssigned);
		Call_PushCell(client);
		Call_PushCell(gA_Rankings[client].iRank);
		Call_PushCell(gA_Rankings[client].fPoints);
		Call_PushCell(bFirst);
		Call_Finish();
	}
}

void UpdateRankedPlayers()
{
	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT COUNT(*) count FROM users WHERE points > 0.0;");

	gH_SQL.Query(SQL_UpdateRankedPlayers_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_UpdateRankedPlayers_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update ranked players) error! Reason: %s", error);

		return;
	}

	if(results.FetchRow())
	{
		gI_RankedPlayers = results.FetchInt(0);

		UpdateTop100();
	}
}

void UpdateTop100()
{
	char sQuery[512];
	FormatEx(sQuery, 512, "SELECT auth, name, FORMAT(points, 2) FROM users WHERE points > 0.0 ORDER BY points DESC LIMIT 100;");
	gH_SQL.Query(SQL_UpdateTop100_Callback, sQuery, 0, DBPrio_Low);
}

public void SQL_UpdateTop100_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings, update top 100) error! Reason: %s", error);

		return;
	}

	if(gH_Top100Menu != null)
	{
		delete gH_Top100Menu;
	}

	gH_Top100Menu = new Menu(MenuHandler_Top);

	int row = 0;

	while(results.FetchRow())
	{
		if(row > 100)
		{
			break;
		}

		char sSteamID[32];
		results.FetchString(0, sSteamID, 32);

		char sName[MAX_NAME_LENGTH];
		results.FetchString(1, sName, MAX_NAME_LENGTH);

		char sPoints[16];
		results.FetchString(2, sPoints, 16);

		char sDisplay[96];
		FormatEx(sDisplay, 96, "#%d - %s (%s)", (++row), sName, sPoints);
		gH_Top100Menu.AddItem(sSteamID, sDisplay);
	}

	if(gH_Top100Menu.ItemCount == 0)
	{
		char sDisplay[64];
		FormatEx(sDisplay, 64, "%t", "NoRankedPlayers");
		gH_Top100Menu.AddItem("-1", sDisplay);
	}

	gH_Top100Menu.ExitButton = true;
}

public int Native_GetMapTier(Handle handler, int numParams)
{
	int tier = 0;

	char sMap[128];
	GetNativeString(1, sMap, 128);

	if(!gA_MapTiers.GetValue(sMap, tier))
	{
		return 0;
	}

	return tier;
}

public int Native_GetMapTiers(Handle handler, int numParams)
{
	return view_as<int>(CloneHandle(gA_MapTiers, handler));
}

public int Native_GetPoints(Handle handler, int numParams)
{
	return view_as<int>(gA_Rankings[GetNativeCell(1)].fPoints);
}

public int Native_GetRank(Handle handler, int numParams)
{
	return gA_Rankings[GetNativeCell(1)].iRank;
}

public int Native_GetRankedPlayers(Handle handler, int numParams)
{
	return gI_RankedPlayers;
}

public int Native_Rankings_DeleteMap(Handle handler, int numParams)
{
	char sMap[160];
	GetNativeString(1, sMap, 160);

	char sQuery[256];
	FormatEx(sQuery, 256, "DELETE FROM maptiers WHERE map = '%s';", sMap);
	gH_SQL.Query(SQL_DeleteMap_Callback, sQuery, StrEqual(gS_Map, sMap, false), DBPrio_High);
}

public void SQL_DeleteMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (rankings deletemap) SQL query failed. Reason: %s", error);

		return;
	}

	if(view_as<bool>(data))
	{
		gI_Tier = 1;
		
		UpdateAllPoints();
		UpdateRankedPlayers();
	}
}

public int Native_GetWRCount(Handle handler, int numParams)
{
	return gA_Rankings[GetNativeCell(1)].iWRAmountAll;
}