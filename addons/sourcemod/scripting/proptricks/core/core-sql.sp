void SQL_DBConnect()
{
	gH_SQL = GetTimerDatabaseHandle();
	gB_MySQL = IsMySQLDatabase(gH_SQL);

	// support unicode names
	if(!gH_SQL.SetCharset("utf8mb4"))
	{
		gH_SQL.SetCharset("utf8");
	}

	CreateUsersTable();
}

void CreateUsersTable()
{
	char sQuery[1024];

	if(gB_MySQL)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `users`" ...
			"(`auth` INT NOT NULL," ...
			"`name` VARCHAR(32) COLLATE 'utf8mb4_general_ci'," ...
			"`ip` INT," ...
			"`lastlogin` INT NOT NULL DEFAULT -1," ...
			"`points` FLOAT NOT NULL DEFAULT 0," ...
			"`playtime` FLOAT NOT NULL DEFAULT 0, PRIMARY KEY (`auth`), INDEX `points` (`points`), INDEX `lastlogin` (`lastlogin`)) ENGINE=INNODB;");
	}

	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"CREATE TABLE IF NOT EXISTS `users`" ...
			"(`auth` INT NOT NULL PRIMARY KEY," ...
			"`name` VARCHAR(32), `ip` INT," ...
			"`lastlogin` INTEGER NOT NULL DEFAULT -1," ...
			"`playtime` FLOAT NOT NULL DEFAULT 0," ...
			"`points` FLOAT NOT NULL DEFAULT 0);");
	}

	gH_SQL.Query(SQL_CreateUsersTable_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_CreateUsersTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer error! Users' data table creation failed. Reason: %s", error);

		return;
	}

	Call_StartForward(gH_Forwards_OnDatabaseLoaded);
	Call_Finish();
}

void SQL_TryToInsertUser(int client)
{
	int iSteamID = GetSteamAccountID(client);

	if(iSteamID == 0)
	{
		KickClient(client, "%T", "VerificationFailed", client);

		return;
	}

	char sName[MAX_NAME_LENGTH_SQL];
	GetClientName(client, sName, MAX_NAME_LENGTH_SQL);
	ReplaceString(sName, MAX_NAME_LENGTH_SQL, "#", "?"); // to avoid this: https://user-images.githubusercontent.com/3672466/28637962-0d324952-724c-11e7-8b27-15ff021f0a59.png

	int iLength = ((strlen(sName) * 2) + 1);
	char[] sEscapedName = new char[iLength];
	gH_SQL.Escape(sName, sEscapedName, iLength);

	char sIPAddress[64];
	GetClientIP(client, sIPAddress, 64);
	int iIPAddress = IPStringToAddress(sIPAddress);

	int iTime = GetTime();

	char sQuery[512];

	if(gB_MySQL)
	{
		FormatEx(sQuery, sizeof(sQuery),
			"INSERT INTO users (auth, name, ip, lastlogin) VALUES (%d, '%s', %d, %d) ON DUPLICATE KEY UPDATE name = '%s', ip = %d, lastlogin = %d;", 
			iSteamID, sEscapedName, iIPAddress, iTime, sEscapedName, iIPAddress, iTime);
	}

	else
	{
		FormatEx(sQuery, sizeof(sQuery),
			"REPLACE INTO users (auth, name, ip, lastlogin) VALUES (%d, '%s', %d, %d);",
			iSteamID, sEscapedName, iIPAddress, iTime);
	}

	gH_SQL.Query(SQL_InsertUser_Callback, sQuery, GetClientSerial(client));
}

void DeleteUserData(int client, const int iSteamID)
{
	if(gB_Replay)
	{
		char sQueryGetWorldRecords[256];
		FormatEx(sQueryGetWorldRecords, sizeof(sQueryGetWorldRecords),
			"SELECT map, id, prop, track FROM playertimes WHERE auth = %d;",
			iSteamID);

		DataPack hPack = new DataPack();
		hPack.WriteCell(client);
		hPack.WriteCell(iSteamID);

		gH_SQL.Query(SQL_DeleteUserData_GetRecords_Callback, sQueryGetWorldRecords, hPack, DBPrio_High);
	}

	else
	{
		char sQueryDeleteUserTimes[256];
		FormatEx(sQueryDeleteUserTimes, sizeof(sQueryDeleteUserTimes),
			"DELETE FROM playertimes WHERE auth = %d;",
			iSteamID);

		DataPack hSteamPack = new DataPack();
		hSteamPack.WriteCell(iSteamID);
		hSteamPack.WriteCell(client);

		gH_SQL.Query(SQL_DeleteUserTimes_Callback, sQueryDeleteUserTimes, hSteamPack, DBPrio_High);
	}
}

public void SQL_DeleteUserData_GetRecords_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack hPack = view_as<DataPack>(data);
	hPack.Reset();
	int client = hPack.ReadCell();
	int iSteamID = hPack.ReadCell();
	delete hPack;

	if(results == null)
	{
		LogError("Timer error! Failed to wipe user data (wipe | get player records). Reason: %s", error);

		return;
	}

	Transaction hTransaction = new Transaction();

	while(results.FetchRow())
	{
		char map[160];
		results.FetchString(0, map, sizeof(map));

		int id = results.FetchInt(1);
		int prop = results.FetchInt(2);
		int track = results.FetchInt(3);

		char sQueryGetWorldRecordID[256];
		FormatEx(sQueryGetWorldRecordID, sizeof(sQueryGetWorldRecordID),
			"SELECT id FROM playertimes WHERE map = '%s' AND prop = %d AND track = %d ORDER BY time LIMIT 1;",
			map, prop, track);

		DataPack hTransPack = new DataPack();
		hTransPack.WriteString(map);
		hTransPack.WriteCell(id);
		hTransPack.WriteCell(prop);
		hTransPack.WriteCell(track);

		hTransaction.AddQuery(sQueryGetWorldRecordID, hTransPack);
	}

	DataPack hSteamPack = new DataPack();
	hSteamPack.WriteCell(iSteamID);
	hSteamPack.WriteCell(client);

	gH_SQL.Execute(hTransaction, Trans_OnRecordCompare, INVALID_FUNCTION, hSteamPack, DBPrio_High);
}

public void Trans_OnRecordCompare(Database db, any data, int numQueries, DBResultSet[] results, any[] queryData)
{
	DataPack hPack = view_as<DataPack>(data);
	hPack.Reset();
	int iSteamID = hPack.ReadCell();

	int client = 0;
	// Check if the target is in game
	for(int index = 1; index <= MaxClients; index++)
	{
		if(IsValidClient(index) && !IsFakeClient(index))
		{
			if(iSteamID == GetSteamAccountID(index))
			{
				client = index;
				break;
			}
		}
	}

	for(int i = 0; i < numQueries; i++)
	{
		DataPack hQueryPack = view_as<DataPack>(queryData[i]);
		hQueryPack.Reset();
		char sMap[32];
		hQueryPack.ReadString(sMap, sizeof(sMap));

		int iRecordID = hQueryPack.ReadCell();
		int iProp = hQueryPack.ReadCell();
		int iTrack = hQueryPack.ReadCell();
		delete hQueryPack;

		if(client > 0)
		{
			PropTricks_SetClientPB(client, iProp, iTrack, 0.0);
		}

		if(results[i] != null && results[i].FetchRow())
		{
			int iWR = results[i].FetchInt(0);

			if(iWR == iRecordID)
			{
				PropTricks_DeleteReplay(sMap, iProp, iTrack, iSteamID);
			}
		}
	}

	char sQueryDeleteUserTimes[256];
	FormatEx(sQueryDeleteUserTimes, sizeof(sQueryDeleteUserTimes),
		"DELETE FROM playertimes WHERE auth = %d;",
		iSteamID);

	gH_SQL.Query(SQL_DeleteUserTimes_Callback, sQueryDeleteUserTimes, hPack, DBPrio_High);
}

public void SQL_DeleteUserTimes_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack hPack = view_as<DataPack>(data);
	hPack.Reset();
	int iSteamID = hPack.ReadCell();

	if(results == null)
	{
		LogError("Timer error! Failed to wipe user data (wipe | delete user times). Reason: %s", error);

		delete hPack;

		return;
	}

	char sQueryDeleteUsers[256];
	FormatEx(sQueryDeleteUsers, sizeof(sQueryDeleteUsers), "DELETE FROM users WHERE auth = %d;",
		iSteamID);

	gH_SQL.Query(SQL_DeleteUserData_Callback, sQueryDeleteUsers, hPack, DBPrio_High);
}

public void SQL_DeleteUserData_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	DataPack hPack = view_as<DataPack>(data);
	hPack.Reset();
	int iSteamID = hPack.ReadCell();
	int client = hPack.ReadCell();
	delete hPack;

	if(results == null)
	{
		LogError("Timer error! Failed to wipe user data (wipe | delete user data, id [U:1:%d]). Reason: %s", error, iSteamID);

		return;
	}

	PropTricks_LogMessage("%L - wiped user data for [U:1:%d].", client, iSteamID);
	PropTricks_ReloadLeaderboards();
	PropTricks_PrintToChat(client, "Finished wiping timer data for user %s[U:1:%d]%s.", gS_ChatStrings.sVariable, iSteamID, gS_ChatStrings.sText);
}

public void SQL_InsertUser_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		int client = GetClientFromSerial(data);

		if(client == 0)
		{
			LogError("Timer error! Failed to insert a disconnected player's data to the table. Reason: %s", error);
		}

		else
		{
			LogError("Timer error! Failed to insert \"%N\"'s data to the table. Reason: %s", client, error);
		}

		return;
	}
}