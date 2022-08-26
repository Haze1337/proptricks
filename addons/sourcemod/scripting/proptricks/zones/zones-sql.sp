static bool gB_MySQL = false;

void SQL_DBConnect()
{
	gH_SQL = GetTimerDatabaseHandle();
	gB_MySQL = IsMySQLDatabase(gH_SQL);
	
	CreateTables();
}

void CreateTables()
{
	char sQuery[1024];
	FormatEx(sQuery, 1024,
		"CREATE TABLE IF NOT EXISTS `mapzones` (`id` INT AUTO_INCREMENT, `map` VARCHAR(128), `type` INT, `corner1_x` FLOAT, `corner1_y` FLOAT, `corner1_z` FLOAT, `corner2_x` FLOAT, `corner2_y` FLOAT, `corner2_z` FLOAT, `destination_x` FLOAT NOT NULL DEFAULT 0, `destination_y` FLOAT NOT NULL DEFAULT 0, `destination_z` FLOAT NOT NULL DEFAULT 0, `track` INT NOT NULL DEFAULT 0, `flags` INT NOT NULL DEFAULT 0, `data` INT NOT NULL DEFAULT 0, PRIMARY KEY (`id`))%s;",
		(gB_MySQL)? " ENGINE=INNODB":"");

	gH_SQL.Query(SQL_CreateTable_Callback, sQuery);
}

public void SQL_CreateTable_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zones module) error! Map zones' table creation failed. Reason: %s", error);

		return;
	}

	gB_Connected = true;
	
	OnMapStart();
}

public void SQL_DeleteMap_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zones deletemap) SQL query failed. Reason: %s", error);

		return;
	}

	if(view_as<bool>(data))
	{
		OnMapStart();
	}
}

void ZonesDB_RefreshZones()
{
	char sQuery[512];
	FormatEx(sQuery, 512,
		"SELECT type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, destination_x, destination_y, destination_z, track, %s, flags, data FROM mapzones WHERE map = '%s';",
		(gB_MySQL)? "id":"rowid", gS_Map);

	gH_SQL.Query(SQL_RefreshZones_Callback, sQuery, 0, DBPrio_High);
}

public void SQL_RefreshZones_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zone refresh) SQL query failed. Reason: %s", error);

		return;
	}

	gI_MapZones = 0;

	while(results.FetchRow())
	{
		int type = results.FetchInt(0);

		gV_MapZones[gI_MapZones][0][0] = gV_MapZones_Visual[gI_MapZones][0][0] = results.FetchFloat(1);
		gV_MapZones[gI_MapZones][0][1] = gV_MapZones_Visual[gI_MapZones][0][1] = results.FetchFloat(2);
		gV_MapZones[gI_MapZones][0][2] = gV_MapZones_Visual[gI_MapZones][0][2] = results.FetchFloat(3);
		gV_MapZones[gI_MapZones][1][0] = gV_MapZones_Visual[gI_MapZones][7][0] = results.FetchFloat(4);
		gV_MapZones[gI_MapZones][1][1] = gV_MapZones_Visual[gI_MapZones][7][1] = results.FetchFloat(5);
		gV_MapZones[gI_MapZones][1][2] = gV_MapZones_Visual[gI_MapZones][7][2] = results.FetchFloat(6);

		CreateZonePoints(gV_MapZones_Visual[gI_MapZones], gCV_Offset.FloatValue);

		gV_ZoneCenter[gI_MapZones][0] = (gV_MapZones[gI_MapZones][0][0] + gV_MapZones[gI_MapZones][1][0]) / 2.0;
		gV_ZoneCenter[gI_MapZones][1] = (gV_MapZones[gI_MapZones][0][1] + gV_MapZones[gI_MapZones][1][1]) / 2.0;
		gV_ZoneCenter[gI_MapZones][2] = (gV_MapZones[gI_MapZones][0][2] + gV_MapZones[gI_MapZones][1][2]) / 2.0;

		gA_ZoneCache[gI_MapZones].bZoneInitialized = true;
		gA_ZoneCache[gI_MapZones].iZoneType = type;
		gA_ZoneCache[gI_MapZones].iZoneTrack = results.FetchInt(10);
		gA_ZoneCache[gI_MapZones].iDatabaseID = results.FetchInt(11);
		gA_ZoneCache[gI_MapZones].iZoneFlags = results.FetchInt(12);
		gA_ZoneCache[gI_MapZones].iZoneData = results.FetchInt(13);
		gA_ZoneCache[gI_MapZones].iEntityID = -1;

		gI_MapZones++;
	}

	CreateZoneEntities();
}

void ZonesDB_DeleteZone(int client, int id)
{
	PropTricks_LogMessage("%L - deleted %s (id %d) from map `%s`.", client, gS_ZoneNames[gA_ZoneCache[id].iZoneType], gA_ZoneCache[id].iDatabaseID, gS_Map);

	char sQuery[256];
	FormatEx(sQuery, 256, "DELETE FROM mapzones WHERE %s = %d;", (gB_MySQL)? "id":"rowid", gA_ZoneCache[id].iDatabaseID);

	DataPack hDatapack = new DataPack();
	hDatapack.WriteCell(GetClientSerial(client));
	hDatapack.WriteCell(gA_ZoneCache[id].iZoneType);

	gH_SQL.Query(SQL_DeleteZone_Callback, sQuery, hDatapack);
}

public void SQL_DeleteZone_Callback(Database db, DBResultSet results, const char[] error, DataPack data)
{
	data.Reset();
	int client = GetClientFromSerial(data.ReadCell());
	int type = data.ReadCell();

	delete data;

	if(results == null)
	{
		LogError("Timer (single zone delete) SQL query failed. Reason: %s", error);

		return;
	}

	UnloadZones(type);
	ZonesDB_RefreshZones();

	if(client == 0)
	{
		return;
	}

	PropTricks_PrintToChat(client, "%T", "ZoneDeleteSuccessful", client, gS_ChatStrings.sVariable, gS_ZoneNames[type], gS_ChatStrings.sText);
}

void ZonesDB_DeleteAllZones(int client, const char[] sMap)
{
	PropTricks_LogMessage("%L - deleted all zones from map `%s`.", client, sMap);

	char sQuery[256];
	FormatEx(sQuery, 256, "DELETE FROM mapzones WHERE map = '%s';", sMap);

	gH_SQL.Query(SQL_DeleteAllZones_Callback, sQuery, GetClientSerial(client));
}

public void SQL_DeleteAllZones_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (single zone delete) SQL query failed. Reason: %s", error);

		return;
	}

	UnloadZones(0);

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	PropTricks_PrintToChat(client, "%T", "ZoneDeleteAllSuccessful", client);
}

void ZonesDB_InsertZone(int client)
{
	int iType = gI_ZoneType[client];
	int iIndex = GetZoneIndex(iType, gI_ZoneTrack[client]);
	bool bInsert = (gI_ZoneDatabaseID[client] == -1 && (iIndex == -1 || iType >= Zone_Stop));

	char sQuery[512];

	if(bInsert) // insert
	{
		PropTricks_LogMessage("%L - added %s to map `%s`.", client, gS_ZoneNames[iType], gS_Map);

		FormatEx(sQuery, 512,
			"INSERT INTO mapzones (map, type, corner1_x, corner1_y, corner1_z, corner2_x, corner2_y, corner2_z, track, flags, data) VALUES ('%s', %d, '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', '%.03f', %d, %d, %d);",
			gS_Map, iType, gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gI_ZoneTrack[client], gI_ZoneFlags[client], gI_ZoneData[client]);
	}

	else // update
	{
		PropTricks_LogMessage("%L - updated %s in map `%s`.", client, gS_ZoneNames[iType], gS_Map);

		if(gI_ZoneDatabaseID[client] == -1)
		{
			for(int i = 0; i < gI_MapZones; i++)
			{
				if(gA_ZoneCache[i].bZoneInitialized && gA_ZoneCache[i].iZoneType == iType && gA_ZoneCache[i].iZoneTrack == gI_ZoneTrack[client])
				{
					gI_ZoneDatabaseID[client] = gA_ZoneCache[i].iDatabaseID;
				}
			}
		}

		FormatEx(sQuery, 512,
			"UPDATE mapzones SET corner1_x = '%.03f', corner1_y = '%.03f', corner1_z = '%.03f', corner2_x = '%.03f', corner2_y = '%.03f', corner2_z = '%.03f', track = %d, flags = %d, data = %d WHERE %s = %d;",
			gV_Point1[client][0], gV_Point1[client][1], gV_Point1[client][2], gV_Point2[client][0], gV_Point2[client][1], gV_Point2[client][2], gI_ZoneTrack[client], gI_ZoneFlags[client], gI_ZoneData[client], (gB_MySQL)? "id":"rowid", gI_ZoneDatabaseID[client]);
	}

	gH_SQL.Query(SQL_InsertZone_Callback, sQuery, GetClientSerial(client));
}

public void SQL_InsertZone_Callback(Database db, DBResultSet results, const char[] error, any data)
{
	if(results == null)
	{
		LogError("Timer (zone insert) SQL query failed. Reason: %s", error);

		return;
	}

	int client = GetClientFromSerial(data);

	if(client == 0)
	{
		return;
	}

	UnloadZones(0);
	ZonesDB_RefreshZones();
	Reset(client);
}