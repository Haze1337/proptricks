#include <sourcemod>
#include <geoip>
#include <convar_class>

#undef REQUIRE_PLUGIN
#include <proptricks>

#pragma newdecls required
#pragma semicolon 1

// macros
#define MAPSDONE 0
#define MAPSLEFT 1

// modules
bool gB_Rankings = false;

// database handle
Database gH_SQL = null;

// cache
bool gB_CanOpenMenu[MAXPLAYERS+1];
int gI_MapType[MAXPLAYERS+1];
int gI_Prop[MAXPLAYERS+1];
int gI_Track[MAXPLAYERS+1];
int gI_TargetSteamID[MAXPLAYERS+1];
int gI_LastPrintedSteamID[MAXPLAYERS+1];
char gS_TargetName[MAXPLAYERS+1][MAX_NAME_LENGTH];

// playtime things
float gF_PlaytimeStart[MAXPLAYERS+1];

bool gB_Late = false;

// timer settings
int gI_Props = 0;
propstrings_t gS_PropStrings[PROP_LIMIT];
propsettings_t gA_PropSettings[PROP_LIMIT];

// chat settings
chatstrings_t gS_ChatStrings;

public Plugin myinfo =
{
	name = "[PropTricks] Player Stats",
	author = "Haze",
	description = "Player stats for proptricks timer.",
	version = PROPTRICKS_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	RegPluginLibrary("proptricks-stats");

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
	// player commands
	RegConsoleCmd("sm_profile", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");
	RegConsoleCmd("sm_stats", Command_Profile, "Show the player's profile. Usage: sm_profile [target]");
	RegConsoleCmd("sm_mapsdone", Command_MapsDoneLeft, "Show maps that the player has finished. Usage: sm_mapsdone [target]");
	RegConsoleCmd("sm_mapsleft", Command_MapsDoneLeft, "Show maps that the player has not finished yet. Usage: sm_mapsleft [target]");
	RegConsoleCmd("sm_playtime", Command_Playtime, "Show the top playtime list.");

	// translations
	LoadTranslations("common.phrases");
	LoadTranslations("proptricks-common.phrases");
	LoadTranslations("proptricks-stats.phrases");
	
	gB_Rankings = LibraryExists("proptricks-rankings");

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsClientConnected(i) && IsClientInGame(i))
			{
				OnClientPutInServer(i);
			}
		}
	}

	// database
	gH_SQL = GetTimerDatabaseHandle();
	
	CreateTimer(2.5 * 60.0, PropTricks_SavePlaytime, 0, TIMER_REPEAT);
}

public void OnMapStart()
{
	if(gB_Late)
	{
		PropTricks_OnPropConfigLoaded(-1);
		PropTricks_GetChatStrings(gS_ChatStrings);
	}
}

public void PropTricks_OnPropConfigLoaded(int props)
{
	if(props == -1)
	{
		props = PropTricks_GetPropCount();
	}

	for(int i = 0; i < props; i++)
	{
		PropTricks_GetPropSettings(i, gA_PropSettings[i]);
		PropTricks_GetPropStrings(i, sPropName, gS_PropStrings[i].sPropName, sizeof(propstrings_t::sPropName));
		PropTricks_GetPropStrings(i, sShortName, gS_PropStrings[i].sShortName, sizeof(propstrings_t::sShortName));
	}

	gI_Props = props;
}

public void PropTricks_OnChatConfigLoaded(chatstrings_t strings)
{
	gS_ChatStrings = strings;
}

public void OnClientPutInServer(int client)
{
	gB_CanOpenMenu[client] = true;

	gF_PlaytimeStart[client] = GetEngineTime();
}

public void OnClientDisconnect(int client)
{
	if (gH_SQL == null || IsFakeClient(client) || !IsClientAuthorized(client))
	{
		return;
	}

	Transaction trans = null;
	SavePlaytime(client, GetEngineTime(), trans);

	if (trans != null)
	{
		gH_SQL.Execute(trans, Trans_SavePlaytime_Success, Trans_SavePlaytime_Failure);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "proptricks-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "proptricks-rankings"))
	{
		gB_Rankings = false;
	}
}

public void Trans_SavePlaytime_Success(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
}

public void Trans_SavePlaytime_Failure(Database db, any data, int numQueries, const char[] error, int failIndex, any[] queryData)
{
	LogError("Timer (stats save playtime) SQL query %d/%d failed. Reason: %s", failIndex, numQueries, error);
}

void SavePlaytime(int client, float now, Transaction &trans)
{
	int iSteamID = GetSteamAccountID(client);

	if (iSteamID == 0)
	{
		// how HOW HOW
		return;
	}
	
	char sQuery[256];
	
	if (gF_PlaytimeStart[client] <= 0.0)
	{
		return;
	}

	float diff = now - gF_PlaytimeStart[client];
	gF_PlaytimeStart[client] = now;

	if (diff <= 0.0)
	{
		return;
	}

	FormatEx(sQuery, sizeof(sQuery), "UPDATE `users` SET playtime = playtime + %f WHERE auth = %d;", diff, iSteamID);

	if (trans == null)
	{
		trans = new Transaction();
	}

	trans.AddQuery(sQuery);
}

public Action PropTricks_SavePlaytime(Handle timer, any data)
{
	if (gH_SQL == null)
	{
		return Plugin_Continue;
	}

	Transaction trans = null;

	for (int i = 1; i <= MaxClients; i++)
	{
		if (!IsValidClient(i) || !IsClientAuthorized(i))
		{
			continue;
		}

		SavePlaytime(i, GetEngineTime(), trans);
	}

	if (trans != null)
	{
		gH_SQL.Execute(trans, Trans_SavePlaytime_Success, Trans_SavePlaytime_Failure);
	}

	return Plugin_Continue;
}

public Action Command_Playtime(int client, int args)
{
	if (!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	char sQuery[512];
	FormatEx(sQuery, sizeof(sQuery),
		"SELECT auth, name, playtime, -1 as ownrank FROM users WHERE playtime > 0 " ...
		"UNION " ...
		"SELECT -1, '', u2.playtime, COUNT(*) as ownrank FROM users u1 JOIN (SELECT playtime FROM users WHERE auth = %d) u2 WHERE u1.playtime >= u2.playtime;",
		GetSteamAccountID(client));
	
	gH_SQL.Query(SQL_TopPlaytime_Callback, sQuery, GetClientSerial(client), DBPrio_Normal);

	return Plugin_Handled;
}

public void SQL_TopPlaytime_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if (results == null || !results.RowCount)
	{
		LogError("Timer (!playtime) SQL query failed. Reason: %s", error);
		return;
	}

	int client = GetClientFromSerial(data);

	if (client < 1)
	{
		return;
	}

	Menu menu = new Menu(PlaytimeMenu_Handler);

	char sOwnPlaytime[16];
	int own_rank = 0;
	int rank = 1;

	while (results.FetchRow())
	{
		char sSteamID[20];
		results.FetchString(0, sSteamID, sizeof(sSteamID));

		char sName[PLATFORM_MAX_PATH];
		results.FetchString(1, sName, sizeof(sName));

		float fPlaytime = results.FetchFloat(2);
		char sPlaytime[16];
		FormatSeconds(fPlaytime, sPlaytime, sizeof(sPlaytime), false, true, true);

		int iOwnRank = results.FetchInt(3);

		if (iOwnRank != -1)
		{
			own_rank = iOwnRank;
			sOwnPlaytime = sPlaytime;
		}
		else
		{
			char sDisplay[128];
			FormatEx(sDisplay, sizeof(sDisplay), "#%d - %s - %s", rank++, sPlaytime, sName);
			menu.AddItem(sSteamID, sDisplay, ITEMDRAW_DEFAULT);
		}
	}
	menu.SetTitle("%T\n%T (#%d): %s", "Playtime", client, "YourPlaytime", client, own_rank, sOwnPlaytime);

	if (menu.ItemCount <= 9)
	{
		menu.Pagination = MENU_NO_PAGINATION;
	}

	menu.ExitButton = true;
	menu.Display(client, MENU_TIME_FOREVER);
}

public int PlaytimeMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_Select)
	{
		char info[20];
		menu.GetItem(param2, info, sizeof(info));
		FakeClientCommand(param1, "sm_profile [U:1:%s]", info);
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_MapsDoneLeft(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	int target = client;
	int iSteamID = 0;

	if(args > 0)
	{
		char sArgs[64];
		GetCmdArgString(sArgs, 64);

		iSteamID = SteamIDToAccountID(sArgs);

		if (iSteamID < 1)
		{
			target = FindTarget(client, sArgs, true, false);

			if (target == -1)
			{
				return Plugin_Handled;
			}
		}
		else
		{
			FormatEx(gS_TargetName[client], sizeof(gS_TargetName[]), "[U:1:%d]", iSteamID);
		}
	}

	if (iSteamID < 1)
	{
		GetClientName(target, gS_TargetName[client], MAX_NAME_LENGTH);
		iSteamID = GetSteamAccountID(target);
	}

	gI_TargetSteamID[client] = iSteamID;

	char sCommand[16];
	GetCmdArg(0, sCommand, 16);

	GetClientName(target, gS_TargetName[client], MAX_NAME_LENGTH);
	ReplaceString(gS_TargetName[client], MAX_NAME_LENGTH, "#", "?");

	Menu menu = new Menu(MenuHandler_MapsDoneLeft);

	if(StrEqual(sCommand, "sm_mapsdone"))
	{
		gI_MapType[client] = MAPSDONE;
		menu.SetTitle("%T\n ", "MapsDoneOnProp", client, gS_TargetName[client]);
	}

	else
	{
		gI_MapType[client] = MAPSLEFT;
		menu.SetTitle("%T\n ", "MapsLeftOnProp", client, gS_TargetName[client]);
	}

	int[] props = new int[gI_Props];
	PropTricks_GetOrderedProps(props, gI_Props);

	for(int i = 0; i < gI_Props; i++)
	{
		int iProp = props[i];

		if(gA_PropSettings[iProp].bUnranked || gA_PropSettings[iProp].iEnabled == -1)
		{
			continue;
		}
		
		char sInfo[8];
		IntToString(iProp, sInfo, 8);
		menu.AddItem(sInfo, gS_PropStrings[iProp].sPropName);
	}

	menu.Display(client, 30);

	return Plugin_Handled;
}

public int MenuHandler_MapsDoneLeft(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		gI_Prop[param1] = StringToInt(sInfo);

		Menu submenu = new Menu(MenuHandler_MapsDoneLeft_Track);
		submenu.SetTitle("%T\n ", "SelectTrack", param1);

		for(int i = 0; i < TRACKS_SIZE; i++)
		{
			IntToString(i, sInfo, 8);

			char sTrack[32];
			GetTrackName(param1, i, sTrack, 32);
			submenu.AddItem(sInfo, sTrack);
		}

		submenu.Display(param1, 30);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_MapsDoneLeft_Track(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
		gI_Track[param1] = StringToInt(sInfo);

		ShowMaps(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public Action Command_Profile(int client, int args)
{
	if(client == 0)
	{
		return Plugin_Handled;
	}

	int target = client;
	int iSteamID = 0;

	if(args > 0)
	{
		char sArgs[64];
		GetCmdArgString(sArgs, 64);

		iSteamID = SteamIDToAccountID(sArgs);

		if (iSteamID < 1)
		{
			target = FindTarget(client, sArgs, true, false);

			if (target == -1)
			{
				return Plugin_Handled;
			}
		}
	}

	gI_TargetSteamID[client] = (iSteamID > 0) ? iSteamID : GetSteamAccountID(target);

	return OpenStatsMenu(client, gI_TargetSteamID[client]);
}

Action OpenStatsMenu(int client, int steamid)
{
	// no spam please
	if(!gB_CanOpenMenu[client])
	{
		return Plugin_Handled;
	}

	// big ass query, looking for optimizations
	char sQuery[2048];

	if(gB_Rankings)
	{
		FormatEx(sQuery, 2048, "SELECT a.clears, b.maps, c.wrs, d.name, d.ip, d.lastlogin, d.playtime, d.points, e.rank FROM " ...
				"(SELECT COUNT(*) clears FROM (SELECT map FROM playertimes WHERE auth = %d AND track = 0 GROUP BY map) s) a " ...
				"JOIN (SELECT COUNT(*) maps FROM (SELECT map FROM mapzones WHERE track = 0 AND type = 0 GROUP BY map) s) b " ...
				"JOIN (SELECT COUNT(*) wrs FROM playertimes a JOIN (SELECT MIN(time) time, map FROM playertimes GROUP by map, prop) b ON a.time = b.time AND a.map = b.map WHERE auth = %d) c " ...
				"JOIN (SELECT name, ip, lastlogin, playtime, FORMAT(points, 2) points FROM users WHERE auth = %d) d " ...
				"JOIN (SELECT COUNT(*) rank FROM users as u1 JOIN (SELECT points FROM users WHERE auth = %d) u2 WHERE u1.points >= u2.points) e " ...
			"LIMIT 1;", steamid, steamid, steamid, steamid);
	}

	else
	{
		FormatEx(sQuery, 2048, "SELECT a.clears, b.maps, c.wrs, d.name, d.ip, d.lastlogin, d.playtime FROM " ...
				"(SELECT COUNT(*) clears FROM (SELECT map FROM playertimes WHERE auth = %d AND track = 0 GROUP BY map) s) a " ...
				"JOIN (SELECT COUNT(*) maps FROM (SELECT map FROM mapzones WHERE track = 0 AND type = 0 GROUP BY map) s) b " ...
				"JOIN (SELECT COUNT(*) wrs FROM playertimes a JOIN (SELECT MIN(time) time, map FROM playertimes GROUP by map, prop) b ON a.time = b.time AND a.map = b.map WHERE auth = %d) c " ...
				"JOIN (SELECT name, ip, lastlogin, playtime FROM users WHERE auth = %d) d " ...
			"LIMIT 1;", steamid, steamid, steamid);
	}

	gB_CanOpenMenu[client] = false;
	gH_SQL.Query(OpenStatsMenuCallback, sQuery, GetClientSerial(client), DBPrio_Low);

	return Plugin_Handled;
}

public void OpenStatsMenuCallback(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);
	gB_CanOpenMenu[client] = true;

	if(results == null)
	{
		LogError("Timer (statsmenu) SQL query failed. Reason: %s", error);

		return;
	}

	if(client == 0)
	{
		return;
	}

	if(results.FetchRow())
	{
		// create variables
		int iClears = results.FetchInt(0);
		int iTotalMaps = results.FetchInt(1);
		int iWRs = results.FetchInt(2);
		
		results.FetchString(3, gS_TargetName[client], MAX_NAME_LENGTH);
		ReplaceString(gS_TargetName[client], MAX_NAME_LENGTH, "#", "?");
	
		int iIPAddress = results.FetchInt(4);
		char sIPAddress[32];
		IPAddressToString(iIPAddress, sIPAddress, 32);

		char sCountry[64];

		if(!GeoipCountry(sIPAddress, sCountry, 64))
		{
			strcopy(sCountry, 64, "Local Area Network");
		}

		int iLastLogin = results.FetchInt(5);
		char sLastLogin[32];
		FormatTime(sLastLogin, 32, "%Y-%m-%d %H:%M:%S", iLastLogin);
		Format(sLastLogin, 32, "%T: %s", "LastLogin", client, (iLastLogin != -1)? sLastLogin:"N/A");
		
		float fPlaytime = results.FetchFloat(6);
		char sPlaytime[16];
		FormatSeconds(fPlaytime, sPlaytime, sizeof(sPlaytime), false, true, true);

		char sPoints[16];
		char sRank[16];

		if(gB_Rankings)
		{
			results.FetchString(7, sPoints, 16);
			results.FetchString(8, sRank, 16);
		}

		char sRankingString[64];

		if(gB_Rankings)
		{
			if(StringToInt(sRank) > 0 && StringToInt(sPoints) > 0)
			{
				FormatEx(sRankingString, 64, "\n%T: #%s/%d\n%T: %s", "Rank", client, sRank, PropTricks_GetRankedPlayers(), "Points", client, sPoints);
			}

			else
			{
				FormatEx(sRankingString, 64, "\n%T: %T", "Rank", client, "PointsUnranked", client);
			}
		}

		if(iClears > iTotalMaps)
		{
			iClears = iTotalMaps;
		}

		char sClearString[128];
		FormatEx(sClearString, 128, "%T: %d/%d (%.01f%%)", "MapCompletions", client, iClears, iTotalMaps, ((float(iClears) / iTotalMaps) * 100.0));

		Menu menu = new Menu(MenuHandler_ProfileHandler);
		menu.SetTitle("%s's %T. [U:1:%d]\n%T: %s\n%s\n%s\n%T: %s\n%T: %d%s\n \n",
			gS_TargetName[client], "Profile", client, gI_TargetSteamID[client], "Country", client, sCountry, sLastLogin, sClearString, "Playtime", client, sPlaytime, "WorldRecords", client, iWRs, sRankingString);

		int[] props = new int[gI_Props];
		PropTricks_GetOrderedProps(props, gI_Props);

		for(int i = 0; i < gI_Props; i++)
		{
			int iProp = props[i];

			if(gA_PropSettings[iProp].bUnranked || gA_PropSettings[iProp].iEnabled == -1)
			{
				continue;
			}
			
			char sInfo[4];
			IntToString(iProp, sInfo, 4);

			menu.AddItem(sInfo, gS_PropStrings[iProp].sPropName);
		}

		// should NEVER happen
		if(menu.ItemCount == 0)
		{
			char sMenuItem[64];
			FormatEx(sMenuItem, 64, "%T", "NoRecords", client);
			menu.AddItem("-1", sMenuItem);
		}

		menu.ExitButton = true;
		menu.Display(client, 20);
	}

	else
	{
		PropTricks_PrintToChat(client, "%T", "StatsMenuFailure", client, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
	}
	
	if (GetSteamAccountID(client) != gI_TargetSteamID[client] && gI_LastPrintedSteamID[client] != gI_TargetSteamID[client])
	{
		gI_LastPrintedSteamID[client] = gI_TargetSteamID[client];
		char steam2[40];
		AccountIDToSteamID2(gI_TargetSteamID[client], steam2, sizeof(steam2));
		char steam64[40];
		AccountIDToSteamID64(gI_TargetSteamID[client], steam64, sizeof(steam64));
		PropTricks_PrintToChat(client, "%s: %s%s %s[U:1:%d]%s %s", gS_TargetName[client], gS_ChatStrings.sVariable, steam2, gS_ChatStrings.sText, gI_TargetSteamID[client], gS_ChatStrings.sVariable2, steam64);
	}
}

public int MenuHandler_ProfileHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];

		menu.GetItem(param2, sInfo, 32);
		gI_Prop[param1] = StringToInt(sInfo);

		Menu submenu = new Menu(MenuHandler_TypeHandler);
		submenu.SetTitle("%T", "MapsMenu", param1, gS_PropStrings[gI_Prop[param1]].sShortName);

		for(int j = 0; j < TRACKS_SIZE; j++)
		{
			char sTrack[32];
			GetTrackName(param1, j, sTrack, 32);

			char sMenuItem[64];
			FormatEx(sMenuItem, 64, "%T (%s)", "MapsDone", param1, sTrack);

			char sNewInfo[32];
			FormatEx(sNewInfo, 32, "%d;0", j);
			submenu.AddItem(sNewInfo, sMenuItem);

			FormatEx(sMenuItem, 64, "%T (%s)", "MapsLeft", param1, sTrack);
			FormatEx(sNewInfo, 32, "%d;1", j);
			submenu.AddItem(sNewInfo, sMenuItem);
		}

		submenu.ExitBackButton = true;
		submenu.Display(param1, 20);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public int MenuHandler_TypeHandler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[32];
		menu.GetItem(param2, sInfo, 32);

		char sExploded[2][4];
		ExplodeString(sInfo, ";", sExploded, 2, 4);

		gI_Track[param1] = StringToInt(sExploded[0]);
		gI_MapType[param1] = StringToInt(sExploded[1]);

		ShowMaps(param1);
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStatsMenu(param1, gI_TargetSteamID[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void ShowMaps(int client)
{
	if(!gB_CanOpenMenu[client])
	{
		return;
	}

	char sQuery[512];

	if(gI_MapType[client] == MAPSDONE)
	{
		FormatEx(sQuery, 512,
			"SELECT a.map, a.time, a.id, COUNT(b.map) + 1 rank, a.points FROM playertimes a LEFT JOIN playertimes b ON a.time > b.time AND a.map = b.map AND a.prop = b.prop AND a.track = b.track WHERE a.auth = %d AND a.prop = %d AND a.track = %d GROUP BY a.map, a.time, a.id, a.points ORDER BY a.%s;",
			gI_TargetSteamID[client], gI_Prop[client], gI_Track[client], (gB_Rankings)? "points DESC":"map");
	}

	else
	{
		if(gB_Rankings)
		{
			FormatEx(sQuery, 512,
				"SELECT DISTINCT m.map, t.tier FROM mapzones m LEFT JOIN maptiers t ON m.map = t.map WHERE m.type = 0 AND m.track = %d AND m.map NOT IN (SELECT DISTINCT map FROM playertimes WHERE auth = %d AND prop = %d AND track = %d) ORDER BY m.map;",
				gI_Track[client], gI_TargetSteamID[client], gI_Prop[client], gI_Track[client]);
		}

		else
		{
			FormatEx(sQuery, 512,
				"SELECT DISTINCT map FROM mapzones WHERE type = 0 AND track = %d AND map NOT IN (SELECT DISTINCT map FROM playertimes WHERE auth = %d AND prop = %d AND track = %d) ORDER BY map;",
				gI_Track[client], gI_TargetSteamID[client], gI_Prop[client], gI_Track[client]);
		}
	}

	gB_CanOpenMenu[client] = false;
	
	gH_SQL.Query(ShowMapsCallback, sQuery, GetClientSerial(client), DBPrio_High);
}

public void ShowMapsCallback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (ShowMaps SELECT) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	gB_CanOpenMenu[client] = true;

	int rows = results.RowCount;

	char sTrack[32];
	GetTrackName(client, gI_Track[client], sTrack, 32);

	Menu menu = new Menu(MenuHandler_ShowMaps);

	if(gI_MapType[client] == MAPSDONE)
	{
		menu.SetTitle("%T (%s)", "MapsDoneFor", client, gS_PropStrings[gI_Prop[client]].sShortName, gS_TargetName[client], rows, sTrack);
	}

	else
	{
		menu.SetTitle("%T (%s)", "MapsLeftFor", client, gS_PropStrings[gI_Prop[client]].sShortName, gS_TargetName[client], rows, sTrack);
	}

	while(results.FetchRow())
	{
		char sMap[192];
		results.FetchString(0, sMap, 192);

		char sRecordID[192];
		char sDisplay[256];

		if(gI_MapType[client] == MAPSDONE)
		{
			float time = results.FetchFloat(1);
			int rank = results.FetchInt(3);

			char sTime[32];
			FormatSeconds(time, sTime, 32);

			float points = results.FetchFloat(4);

			if(gB_Rankings && points > 0.0)
			{
				FormatEx(sDisplay, 192, "[#%d] %s - %s (%.03f %T)", rank, sMap, sTime, points, "MapsPoints", client);
			}

			else
			{
				FormatEx(sDisplay, 192, "[#%d] %s - %s", rank, sMap, sTime);
			}

			int iRecordID = results.FetchInt(2);
			IntToString(iRecordID, sRecordID, 192);
		}

		else
		{
			strcopy(sDisplay, 192, sMap);

			if(gB_Rankings)
			{
				int iTier = results.FetchInt(1);

				if(results.IsFieldNull(1) || iTier == 0)
				{
					iTier = 1;
				}

				Format(sDisplay, 192, "%s (Tier %d)", sMap, iTier);
			}

			strcopy(sRecordID, 192, sMap);
		}

		menu.AddItem(sRecordID, sDisplay);
	}

	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "NoResults", client);
		menu.AddItem("nope", sMenuItem);
	}

	menu.ExitBackButton = true;
	menu.Display(client, 60);
}

public int MenuHandler_ShowMaps(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sInfo[192];
		menu.GetItem(param2, sInfo, 192);

		if(StrEqual(sInfo, "nope"))
		{
			OpenStatsMenu(param1, gI_TargetSteamID[param1]);

			return 0;
		}

		else if(StringToInt(sInfo) == 0)
		{
			FakeClientCommand(param1, "sm_nominate %s", sInfo);

			return 0;
		}
		

		char sQuery[512];
		FormatEx(sQuery, 512, "SELECT u.name, p.time, p.prop, u.auth, p.date, p.map, p.points FROM playertimes p JOIN users u ON p.auth = u.auth WHERE p.id = '%s' LIMIT 1;", sInfo);

		gH_SQL.Query(SQL_SubMenu_Callback, sQuery, GetClientSerial(param1));
	}

	else if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		OpenStatsMenu(param1, gI_TargetSteamID[param1]);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void SQL_SubMenu_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (STATS SUBMENU) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	Menu hMenu = new Menu(SubMenu_Handler);

	char sName[MAX_NAME_LENGTH];
	int iSteamID = 0;
	char sMap[192];

	if(results.FetchRow())
	{
		// 0 - name
		results.FetchString(0, sName, MAX_NAME_LENGTH);

		// 1 - time
		float time = results.FetchFloat(1);
		char sTime[16];
		FormatSeconds(time, sTime, 16);

		char sDisplay[128];
		FormatEx(sDisplay, 128, "%T: %s", "Time", client, sTime);
		hMenu.AddItem("-1", sDisplay);

		// 2 - prop
		int prop = results.FetchInt(2);
		FormatEx(sDisplay, 128, "%T: %s", "Prop", client, gS_PropStrings[prop].sPropName);
		hMenu.AddItem("-1", sDisplay);

		// 3 - steamid3
		iSteamID = results.FetchInt(3);

		// 5 - map
		results.FetchString(5, sMap, 192);

		float points = results.FetchFloat(6);

		if(gB_Rankings && points > 0.0)
		{
			FormatEx(sDisplay, 192, "%T: %.03f", "Points", client, points);
			hMenu.AddItem("-1", sDisplay);
		}

		// 4 - date
		char sDate[32];
		results.FetchString(4, sDate, 32);

		if(sDate[4] != '-')
		{
			FormatTime(sDate, 32, "%Y-%m-%d %H:%M:%S", StringToInt(sDate));
		}

		FormatEx(sDisplay, 128, "%T: %s", "Date", client, sDate);
		hMenu.AddItem("-1", sDisplay);
	}

	char sFormattedTitle[256];
	FormatEx(sFormattedTitle, 256, "%s [U:1:%d]\n--- %s:", sName, iSteamID, sMap);

	hMenu.SetTitle(sFormattedTitle);
	hMenu.ExitBackButton = true;
	hMenu.Display(client, 20);
}

public int SubMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Cancel && param2 == MenuCancel_ExitBack)
	{
		ShowMaps(param1);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

