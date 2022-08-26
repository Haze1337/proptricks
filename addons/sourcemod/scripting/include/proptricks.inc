/*
 * shavit's Timer - .inc file
 * by: shavit
 *
 * This file is part of shavit's Timer.
 *
 * This program is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, version 3.0, as published by the
 * Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but WITHOUT
 * ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
 * FOR A PARTICULAR PURPOSE. See the GNU General Public License for more
 * details.
 *
 * You should have received a copy of the GNU General Public License along with
 * this program. If not, see <http://www.gnu.org/licenses/>.
 *
*/

#if defined _proptricks_included
	#endinput
#endif
#define _proptricks_included

#define PROPTRICKS_VERSION "0.0.1"
#define PROP_LIMIT 256
#define MAX_ZONES 64
#define MAX_NAME_LENGTH_SQL 32

// HUD
#define HUD_NONE				0
#define HUD_MASTER				(1 << 0) // master setting
#define HUD_CENTER				(1 << 1) // show hud as hint text
#define HUD_ZONEHUD				(1 << 2) // show start/end zone hud
#define HUD_OBSERVE				(1 << 3) // show the HUD of the player you spectate
#define HUD_SPECTATORS			(1 << 4) // show list of spectators
#define HUD_KEYOVERLAY			(1 << 5) // show a key overlay
#define HUD_HIDEWEAPON			(1 << 6) // hide the player's weapon
#define HUD_TOPLEFT				(1 << 7) // show top left white HUD with WR/PB times
#define HUD_TIMELEFT			(1 << 8) // shows time left at right tside of the screen (css only)
#define HUD_2DVEL				(1 << 9) // shows 2d velocity
#define HUD_NOSOUNDS			(1 << 10) // disables sounds on personal best, world record etc

// status
enum TimerStatus
{
	Timer_Stopped,
	Timer_Running
};

enum ReplayStatus
{
	Replay_Start,
	Replay_Running,
	Replay_End,
	Replay_Idle
};

enum
{
	CPR_ByConVar = (1 << 0),
	CPR_NoTimer = (1 << 1),
	CPR_InStartZone = (1 << 2),
	CPR_NotOnGround = (1 << 3)
};

enum
{
	Zone_Start,
	Zone_End,
	Zone_Stop,
	ZONETYPES_SIZE
};

enum
{
	Track,
	Track2,
	Track3,
	Track4,
	Track5,
	TRACKS_SIZE
};

// for PropTricks_GetPropStrings
enum
{
	sPropName,
	sShortName,
	sModelPath,
	sChangeCommand,
	sSpecialString
};

// for PropTricks_GetChatStrings
enum
{
	sMessagePrefix,
	sMessageText,
	sMessageWarning,
	sMessageVariable,
	sMessageVariable2,
	sMessageProp
};

enum struct propstrings_t
{
	char sPropName[64];
	char sShortName[16];
	char sModelPath[256];
	char sChangeCommand[128];
	char sSpecialString[128];
}

enum struct propsettings_t
{
	float fMassScale;
	int iEnabled;
	bool bUnranked;
	bool bNoReplay;
	float fRankingMultiplier;
	int iOrdering;
}

enum struct chatstrings_t
{
	char sPrefix[64];
	char sText[16];
	char sWarning[16];
	char sVariable[16];
	char sVariable2[16];
	char sProp[16];
}

enum struct timer_snapshot_t
{
	bool bTimerEnabled;
	// fCurrentTime = (float(iFullTicks)+(iFractionalTicks/10000.0)+fZoneOffset[0])*GetTickInterval()
	float fCurrentTime;
	bool bClientPaused;
	int iProp;
	float fServerTime;
	int iTimerTrack;
	// used as a "tick fraction" basically
	float fZoneOffset[2];
	float fDistanceOffset[2];
	int iZoneIncrement; // convert to array for per zone offsets (?)

	int iFullTicks;
	int iFractionalTicks; // divide this by 10000.0 to get a fraction of a tick. whole ticks are moved to iFullTicks

	bool bPracticeMode;

	bool bJumped;

	int iLastButtons;
	float fLastAngle;
	int iLandingTick;
	MoveType iLastMoveType;
	float fStrafeWarning;
	float fLastInputVel[2];

	float fplayer_speedmod;
	float fNextFrameTime;
}

enum struct cp_cache_t
{
	float fPosition[3];
	float fAngles[3];
	float fVelocity[3];
	float fPropPosition[3];
	float fPropAngles[3];
	float fPropVelocity[3];
	float fPropAngularVelocity[3];
	MoveType iMoveType;
	float fStamina;
	bool bDucked;
	bool bDucking;
	float fDucktime; // m_flDuckAmount in csgo
	float fDuckSpeed; // m_flDuckSpeed in csgo; doesn't exist in css
	int iFlags;
	int iSerial;
	int iGroundEntity;
}

#if defined USES_CHAT_COLORS
// hardcoded colors
char gS_GlobalColorNames[][] =
{
	"{default}",
	"{team}",
	"{green}"
};

char gS_GlobalColors[][] =
{
	"\x01",
	"\x03",
	"\x04"
};
#endif

// connects synchronously to the bhoptimer database
// calls errors if needed
stock Database GetTimerDatabaseHandle()
{
	Database db = null;
	char sError[255];

	if(SQL_CheckConfig("proptricks"))
	{
		if((db = SQL_Connect("proptricks", true, sError, 255)) == null)
		{
			SetFailState("Timer startup failed. Reason: %s", sError);
		}
	}

	else
	{
		db = SQLite_UseDatabase("proptricks", sError, 255);
	}

	return db;
}

// figures out if the database is a mysql database
stock bool IsMySQLDatabase(Database db)
{
	char sDriver[8];
	db.Driver.GetIdentifier(sDriver, 8);

	return StrEqual(sDriver, "mysql", false);
}

stock bool IsValidClient(int client, bool bAlive = false)
{
	return (client >= 1 && client <= MaxClients && IsClientConnected(client) && IsClientInGame(client) && !IsClientSourceTV(client) && (!bAlive || IsPlayerAlive(client)));
}

stock bool IsValidProp(int entity)
{
	if(IsValidEdict(entity))
	{
		char sClassname[16];
		GetEntityClassname(entity, sClassname, sizeof(sClassname));
		return (StrContains(sClassname, "prop") != -1);
	}
	return false;
}

stock void GetTrackName(int client, int track, char[] output, int size)
{
	if(track < 0 || track >= TRACKS_SIZE)
	{
		FormatEx(output, size, "%T", "Track_Unknown", client);

		return;
	}

	static char sTrack[16];
	FormatEx(sTrack, 16, "Track_%d", track);
	FormatEx(output, size, "%T", sTrack, client);
}

stock int GetSpectatorTarget(int client)
{
	int target = client;

	if(IsClientObserver(client))
	{
		int iObserverMode = GetEntProp(client, Prop_Send, "m_iObserverMode");

		if(iObserverMode >= 3 && iObserverMode <= 5)
		{
			int iTarget = GetEntPropEnt(client, Prop_Send, "m_hObserverTarget");

			if(IsValidClient(iTarget, true))
			{
				target = iTarget;
			}
		}
	}

	return target;
}

stock void IPAddressToString(int ip, char[] buffer, int maxlen)
{
	FormatEx(buffer, maxlen, "%d.%d.%d.%d", ((ip >> 24) & 0xFF), ((ip >> 16) & 0xFF), ((ip >> 8) & 0xFF), (ip & 0xFF));
}

stock int IPStringToAddress(const char[] ip)
{
	char sExplodedAddress[4][4];
	ExplodeString(ip, ".", sExplodedAddress, 4, 4, false);

	int iIPAddress =
			(StringToInt(sExplodedAddress[0]) << 24) |
			(StringToInt(sExplodedAddress[1]) << 16) |
			(StringToInt(sExplodedAddress[2]) << 8) |
			StringToInt(sExplodedAddress[3]);

	return iIPAddress;
}

// time formatting!
stock void FormatSeconds(float time, char[] newtime, int newtimesize, bool precise = true, bool nodecimal = false, bool full_hms = false)
{
	float fTempTime = time;

	if(fTempTime < 0.0)
	{
		fTempTime = -fTempTime;
	}

	int iRounded = RoundToFloor(fTempTime);
	int iSeconds = (iRounded % 60);
	float fSeconds = iSeconds + fTempTime - iRounded;

	char sSeconds[8];

	if (nodecimal)
	{
		FormatEx(sSeconds, 8, "%d", iSeconds);
	}
	else
	{
		FormatEx(sSeconds, 8, precise? "%.3f":"%.1f", fSeconds);
	}

	if (!full_hms && fTempTime < 60.0)
	{
		strcopy(newtime, newtimesize, sSeconds);
		FormatEx(newtime, newtimesize, "%s%s", (time < 0.0) ? "-":"", sSeconds);
	}
	else
	{
		int iMinutes = (iRounded / 60);

		if (!full_hms && fTempTime < 3600.0)
		{
			FormatEx(newtime, newtimesize, "%s%d:%s%s", (time < 0.0)? "-":"", iMinutes, (fSeconds < 10)? "0":"", sSeconds);
		}
		else
		{
			int iHours = (iMinutes / 60);
			iMinutes %= 60;

			FormatEx(newtime, newtimesize, "%s%d:%s%d:%s%s", (time < 0.0)? "-":"", iHours, (iMinutes < 10)? "0":"", iMinutes, (fSeconds < 10)? "0":"", sSeconds);
		}
	}
}

stock bool GuessBestMapName(ArrayList maps, const char[] input, char[] output, int size)
{
	if(maps.FindString(input) != -1)
	{
		strcopy(output, size, input);

		return true;
	}

	char sCache[128];

	for(int i = 0; i < maps.Length; i++)
	{
		maps.GetString(i, sCache, 128);

		if(StrContains(sCache, input) != -1)
		{
			strcopy(output, size, sCache);

			return true;
		}
	}

	return false;
}

/**
 * Called before proptricks-core processes the client's usercmd.
 * Before this is called, safety checks (fake/dead clients) happen.
 * Use this forward in modules that use OnPlayerRunCmd to avoid errors and unintended behavior.
 * If a module conflicts with buttons/velocity/angles being changed in proptricks-core, this forward is recommended.
 * This forward will NOT be called if a player's timer is paused.
 * 
 * @param client					Client index.
 * @param buttons					Buttons sent in the usercmd.
 * @param impulse					Impulse sent in the usercmd.
 * @param vel						A vector that contains the player's desired movement. vel[0] is forwardmove, vel[1] is sidemove.
 * @param angles					The player's requested viewangles. They will not necessarily be applied as SRCDS itself won't accept every value.
 * @param status					The player's timer status.
 * @param track						The player's timer track.
 * @param prop						The player's prop.
 * @param propsettings				A propsettings_t struct that contains the player's prop's settings.
 * @param mouse						Mouse direction (x, y).
 * @return							Plugin_Continue to let proptricks-core keep doing what it does, Plugin_Changed to pass different values.
 */
forward Action PropTricks_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int prop, propsettings_t propsettings, int mouse[2]);

/**
 * Called just before proptricks-core adds time to a player's timer.
 * This is the forward you should use to modify the player's timer smoothly.
 * A good example use case is timescaling.
 *
 * @param client					Client index.
 * @param time						The time to be added to the player's timer.
 * @param propsettings				A propsettings_t struct that contains the player's prop's settings.
 * @noreturn
 */
forward void PropTricks_OnTimeIncrement(int client, float &time, propsettings_t propsettings);

/**
 * Called just before proptricks-core adds time to a player's timer.
 * This is the forward you should use to modify the player's timer smoothly.
 * A good example use case is timescaling.
 *
 * @param client					Client index.
 * @param time						The time to be added to the player's timer.
 * @param propsettings				A propsettings_t struct that contains the player's prop's settings.
 * @noreturn
 */
forward void PropTricks_OnTimeIncrementPost(int client, float time, propsettings_t propsettings);

/**
 * Called when a player's timer starts.
 * (WARNING: Will be called every tick when the player stands at the start zone!)
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @return							Plugin_Continue to do nothing or anything else to not start the timer.
 */
forward Action PropTricks_OnStart(int client, int track);

/**
 * Called when a player uses the restart command.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void PropTricks_OnRestart(int client, int track);

/**
 * Called when a player uses the !end command.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void PropTricks_OnEnd(int client, int track);

/**
 * Called before a player's timer is stopped. (stop =/= finish a map)
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @return							False to prevent the timer from stopping.
 */
forward bool PropTricks_OnStopPre(int client, int track);

/**
 * Called when a player's timer stops. (stop =/= finish a map)
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
forward void PropTricks_OnStop(int client, int track);

/**
 * Called before a player finishes a map.
 *
 * @param client					Client index.
 * @return							Plugin_Continue to do nothing, Plugin_Changed to change the variables or anything else to stop the timer from finishing.
 */
forward Action PropTricks_OnFinishPre(int client);

/**
 * Called when a player finishes a map. (touches the end zone)
 *
 * @param client					Client index.
 * @param prop						Prop the record was done on.
 * @param time						Record time.
 * @param track						Timer track.
 * @param oldtime					The player's best time on the map before this finish.
 * @noreturn
 */
forward void PropTricks_OnFinish(int client, int prop, float time, int track, float oldtime);

/**
 * Like PropTricks_OnFinish, but after the insertion query was called.
 * Called from proptricks-wr
 *
 * @param client					Client index.
 * @param prop						Prop the record was done on.
 * @param time						Record time.
 * @param rank						Rank on map.
 * @param overwrite					1 - brand new record. 2 - update.
 * @param track						Timer track.
 * @param oldtime					The player's best time on the map before this finish.
 * @noreturn
 */
forward void PropTricks_OnFinish_Post(int client, int prop, float time, int rank, int overwrite, int track, float oldtime);

/**
 * Called when there's a new WR on the map.
 *
 * @param client					Client index.
 * @param prop						Prop the record was done on.
 * @param time						Record time.
 * @param track						Timer track.
 * @param oldwr						Time of the old WR. 0.0 if there's none.
 * @param oldtime					The player's best time on the map before this finish.
 * @noreturn
 */
forward void PropTricks_OnWorldRecord(int client, int prop, float time, int track, float oldwr, float oldtime);

/**
 * Called when an admin deletes a WR.
 *
 * @param prop						Prop the record was done on.
 * @param id						Record ID. -1 if mass deletion.
 * @param track						Timer track.
 * @param accountid					The account ID of the wr holder
 * @noreturn
 */
forward void PropTricks_OnWRDeleted(int prop, int id, int track, int accountid);

/**
 * Called when a player changes their prop.
 * Note: Doesn't guarantee that the player is in-game or connected.
 *
 * @param client					Client index.
 * @param oldprop					Old prop.
 * @param newprop					New prop.
 * @param track						Timer track.
 * @param manual					Was the change manual, or assigned automatically?
 * @noreturn
 */
forward void PropTricks_OnPropChanged(int client, int oldprop, int newprop, int track, bool manual);

/**
 * Called when a player's prop being remove.
 * Note: Doesn't guarantee that the player is in-game or connected.
 *
 * @param client					Client index.
 * @param oldprop					Old Prop.
 * @param entity					Entity index.
 * @noreturn
 */
forward void PropTricks_OnPropRemovePre(int client, int oldprop, int entity);

/**
 * Called when a player's prop being created.
 * Note: Doesn't guarantee that the player is in-game or connected.
 *
 * @param client					Client index.
 * @param prop						Prop.
 * @param entity					Entity index.
 * @noreturn
 */
forward void PropTricks_OnPropCreated(int client, int prop, int entity);

/**
 * Called when a player changes their bhop track.
 *
 * @param client					Client index.
 * @param oldtrack					Old bhop track.
 * @param newtrack					New bhop track.
 * @noreturn
 */
forward void PropTricks_OnTrackChanged(int client, int oldtrack, int newtrack);

/**
 * Called when the props configuration finishes loading and it's ready to load everything into the cache.
 *
 * @param props					Amount of props loaded.
 * @noreturn
 */
forward void PropTricks_OnPropConfigLoaded(int props);

/**
 * Called when there's a successful connection to the database and it is ready to be used.
 * Called through proptricks-core after migrations have been applied, and after the attempt to create the default `users` table.
 *
 * @noreturn
 */
forward void PropTricks_OnDatabaseLoaded();

/**
 * Called when the chat messages configuration finishes loading and it's ready to load everything into the cache.
 *
 * @param strings					Chat strings object.
 * @noreturn
 */
forward void PropTricks_OnChatConfigLoaded(chatstrings_t strings);

/**
 * Called when a player teleports with checkpoints.
 *
 * @param client					Client index.
 * @param index						Checkpoint that was teleported to.
 * @return							Plugin_Continue to allow teleporting, anything else to prevent.
 */
forward Action PropTricks_OnTeleport(int client, int index);

/**
 * Called when a player teleports with checkpoints.
 *
 * @param client					Client index.
 * @param index						Checkpoint that was saved to.
 * @param overflow					Does this checkpoint shift the rest.
 * @return							Plugin_Continue to allow teleporting, anything else to prevent.
 */
forward Action PropTricks_OnSave(int client, int index);

/**
 * Called when a player deletes a checkpoint.
 *
 * @param client					Client index.
 * @param index						Checkpoint that will be deleted.
 * @return							Plugin_Continue to continue deletion, anything else to prevent.
 */
forward Action PropTricks_OnDelete(int client, int index);

/**
 * Called when a player enters a zone.
 *
 * @param client					Client index.
 * @param type						Zone type.
 * @param track						Zone track.
 * @param id						Zone ID.
 * @param entity					Zone trigger entity index.
 * @param data						Zone data if any.
 * @noreturn
 */
forward void PropTricks_OnEnterZone(int client, int type, int track, int id, int entity, int data);

/**
 * Called when a player leaves a zone.
 *
 * @param client					Client index.
 * @param type						Zone type.
 * @param track						Zone track.
 * @param id						Zone ID.
 * @param entity					Zone trigger entity index.
 * @param data						Zone data if any.
 * @noreturn
 */
forward void PropTricks_OnLeaveZone(int client, int type, int track, int id, int entity, int data);

/**
 * Called when a player gets the worst record in the server for the prop.
 * Note: Will be only called for ranked props.
 *
 * @param client					Client index.
 * @param prop						Prop the record was done on.
 * @param time						Record time.
 * @param track						Timer track.
 * @param oldtime					The player's best time on the map before this finish.
 * @noreturn
 */
forward void PropTricks_OnWorstRecord(int client, int prop, float time, int track, float oldtime);

/**
 * Gets called when a map's tier is assigned.
 * Only called once per map, if the rankings plugin is enabled.
 * The exception is if the admin changes the current map's tier.
 *
 * @param map						Map display name.
 * @param tier						Map's tier.
 * @noreturn
 */
forward void PropTricks_OnTierAssigned(const char[] map, int tier);

/**
 * Gets called when the server acknowledges the client's ranking status.
 * It is called after OnClientPostAdminCheck and at forced rank recalculations.
 *
 * @param client					Client index.
 * @param rank						Client's rank. (0 if unranked or unassigned)
 * @param points					Client's points. (0.0 if unranked or unassigned)
 * @param first						True if the forward is called after the initial connection, false if it is caused by recalculation.
 * @noreturn
 */
forward void PropTricks_OnRankAssigned(int client, int rank, float points, bool first);

/**
 * Called when replay playback starts.
 *
 * @param client					Client index for the bot.
 * @noreturn
 */
forward void PropTricks_OnReplayStart(int client);

/**
 * Called when replay playback ends.
 *
 * @param client					Client index for the bot.
 * @noreturn
 */
forward void PropTricks_OnReplayEnd(int client);

/**
 * Called when all replays files have been loaded.
 *
 * @noreturn
 */
forward void PropTricks_OnReplaysLoaded();

/**
 * Called when top left HUD updates.
 *
 * @param client					Client index that recieves the hud.
 * @param target					Client index that recieves the hud.
 * @param topleft					Reference to the HUD buffer.
 * @param topleftlength				Max length of the topleft buffer.
 * @return							Plugin_Handled or Plugin_Stop to block the HUD message from appearing. Anything else to pass along new values.
 */
forward Action PropTricks_OnTopLeftHUD(int client, int target, char[] topleft, int topleftlength);

/**
 * Called when a time offset is calculated
 *
 * @param client					Client index.
 * @param zonetype					Zone type (Zone_Start or Zone_End).
 * @param offset					Time offset from the given zone.
 * @param distance					Distance used in time offset.
 * @noreturn							
 */
forward void PropTricks_OnTimeOffsetCalculated(int client, int zonetype, float offset, float distance);

/**
 * Called before the timer finish message is printed to the users.
 *
 * @param client					Client index.
 * @param everyone					Is the message printed to everyone, or just the client?
 * @param overwrite					Modify the database? 0 - no. 1 - brand new record. 2 - new personal best.
 * @param rank						Rank on map.
 * @return							Plugin_Handled or Plugin_Stop to stop the message. Anything else to use new values.
 */
forward Action PropTricks_OnFinishMessage(int client, bool &everyone, int overwrite, int rank, char[] message, int maxlen);

/**
 * Called after the checkpoint menu has been made and before it's sent to the client.
 *
 * @param client					Client index.
 * @param segmented					If the menu was a segmented menu
 * @return							Plugin_Handled or Plugin_Stop to stop the menu.
 */
forward Action PropTricks_OnCheckPointMenuMade(int client, bool segmented);

/**
 * Called before a selection is processed in the main checkpoint menu.
 *
 * @param client					Client index.
 * @param param2					Second parameter in the callback, usually the item selected.
 * @param info						reference copy of the info string used in the callback
 * @param maxlength					length of the info buffer
 * @param currentCheckpoint			Clients current checkpoint
 * @param maxCPs					Max checkpoints the client can use
 * @return							Plugin_Continue to continue the callback.
 */
forward Action PropTricks_OnCheckpointMenuSelect(int client, int param2, char[] info, int maxlength, int currentCheckpoint, int maxCPs);

/**
 * Called before a sound is played by proptricks-sounds.
 *
 * @param client					Index of the client that triggered the sound event.
 * @param sound						Reference to the sound that will be played.
 * @param maxlength					Length of the sound buffer, always PLATFORM_MAX_PATH.
 * @param clients					Reference to the array of clients to receive the sound, maxsize of MaxClients.
 * @param count						Reference to the number of clients to receive the sound.
 * @return							Plugin_Handled or Plugin_Stop to block the sound from being played. Anything else to continue the operation.
 */
forward Action PropTricks_OnPlaySound(int client, char[] sound, int maxlength, int[] clients, int &count);

/**
 * Called before the server & timer handle the ProcessMovement method.
 *
 * @param client					Client Index.
 * @noreturn
 */
forward void PropTricks_OnProcessMovement(int client);

/**
 * Called After the server handles the ProcessMovement method, but before the timer handles the method.
 *
 * @param client					Client Index.
 * @noreturn
 */
forward void PropTricks_OnProcessMovementPost(int client);

/**
 * Returns the database handle the timer is using.
 *
 * @param hSQL						Handle to store the database on.
 * @noreturn
 */
 #pragma deprecated Use PropTricks_GetDatabase() instead.
native void PropTricks_GetDB(Database &hSQL);

/**
 * Returns bhoptimer's database handle.
 * Call within PropTricks_OnDatabaseLoaded. Safety is not guaranteed anywhere else!
 *
 * @return							Database handle.
 */
native Database PropTricks_GetDatabase();

/**
 * Starts the timer for a player.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
native void PropTricks_StartTimer(int client, int track);

/**
 * Restarts the timer for a player.
 * Will work as if the player just used sm_r.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
native void PropTricks_RestartTimer(int client, int track);

/**
 * Stops the timer for a player.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @param bypass					Bypass call to PropTricks_OnStopPre?
 * @return							True if the operation went through.
 */
native bool PropTricks_StopTimer(int client, bool bypass = true);

/**
 * Deletes all map records for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map						Map name.
 * @noreturn
 */
native void PropTricks_WR_DeleteMap(const char[] map);

/**
 * Deletes all map zones for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map						Map name.
 * @noreturn
 */
native void PropTricks_Zones_DeleteMap(const char[] map);

/**
 * Deletes all replays for the specified map.
 * Plugin will refresh if map is currently on.
 *
 * @param map						Map name.
 * @noreturn
 */
native void PropTricks_Replay_DeleteMap(const char[] map);

/**
 * Deletes tier setting for the specified map.
 * Points recalculation will run right after this is finished.
 *
 * @param map						Map name.
 * @noreturn
 */
native void PropTricks_Rankings_DeleteMap(const char[] map);

/**
 * Changes a player's prop.
 *
 * @param client					Client index.
 * @param prop						Prop.
 * @param force						Ignore prop permissions. This being true will bypass the `inaccessible` prop setting as well.
 * @param manual					Is it a manual prop change? (Was it caused by user interaction?)
 * @param noforward					Bypasses the call to `PropTricks_OnPropChanged`.
 * @return							False if failed due to lack of access, true otherwise.
 */
native bool PropTricks_ChangeClientProp(int client, int prop, bool force = false, bool manual = false, bool noforward = false);

/**
 * Finishes the map for a player, with their current timer stats.
 * Will not teleport the player to anywhere, it's handled inside the mapzones plugin.
 *
 * @param client					Client index.
 * @param track						Timer track.
 * @noreturn
 */
native void PropTricks_FinishMap(int client, int track);

/**
 * Stores the player's timer stats on variables
 *
 * @param client					Client index.
 * @param time						Time passed since the player started.
 * @param prop						Prop, check "enum prop"
 * @param started					Timer started?
 * @noreturn
 */
#pragma deprecated Use different natives or PropTricks_SaveSnapshot instead.
native void PropTricks_GetTimer(int client, float &time, int &prop, bool &started);

/**
 * Retrieve a client's current time.
 *
 * @param client					Client index.
 * @return							Current time.
 */
native float PropTricks_GetClientTime(int client);

/**
 * Retrieve the client's track. (Track_Main/Track_Bonus etc..)
 *
 * @param client					Client index.
 * @return							Timer track.
 */
native int PropTricks_GetClientTrack(int client);

/**
 * Retrieve a client's prop
 *
 * @param client					Client index.
 * @return							Prop.
 */
native int PropTricks_GetClientProp(int client);

/**
 * Retrieve a client's timer status
 *
 * @param client					Client index.
 * @return							See TimerStatus enum.
 */
native TimerStatus PropTricks_GetTimerStatus(int client);

/**
 * Saves the WR time for the current map on a variable.
 *
 * @param prop						Prop to get the WR for.
 * @param time						Reference to the time variable. 0.0 will be returned if no records.
 * @param track						Timer track.
 * @noreturn
 */
#pragma deprecated Use PropTricks_GetWorldRecord() instead.
native void PropTricks_GetWRTime(int prop, float &time, int track);

/**
 * Retrieves the world record for the given prop/track.
 *
 * @param prop						Prop to get the WR for.
 * @param track						Timer track.
 * @return							World record for the specified settings.
 */
native float PropTricks_GetWorldRecord(int prop, int track);

/**
 * Reloads WR leaderboards cache for the current map.
 *
 * @noreturn
 */
native void PropTricks_ReloadLeaderboards();

/**
 * Saves the WR's record ID for the current map on a variable.
 * Unused in base plugins, as of pre-1.4b.
 *
 * @param prop						Prop to get the WR for.
 * @param time						Reference to the time variable. 0.0 will be returned if no records.
 * @param track						Timer track.
 * @noreturn
 */
native void PropTricks_GetWRRecordID(int prop, int &recordid, int track);

/**
 * Saves the WR's player name on the map on a variable.
 *
 * @param prop						Prop to get the WR for.
 * @param wrname					Reference to the name variable.
 * @param wrmaxlength				Max length for the string.
 * @param track						Timer track.
 * @noreturn
 */
native void PropTricks_GetWRName(int prop, char[] wrname, int wrmaxlength, int track);

/**
 * Saves the player's personal best time on a variable.
 *
 * @param client					Client index.
 * @param prop						Prop to get the PB for.
 * @param time						Reference to the time variable. 0.0 will be returned if no personal record.
 * @param track						Timer track.
 * @noreturn
 */
#pragma deprecated Use PropTricks_GetClientPB() instead.
native void PropTricks_GetPlayerPB(int client, int prop, float &time, int track);

/**
 * Retrieves the best time of a player.
 *
 * @param client					Client index.
 * @param prop						Prop to get the PB for.
 * @param track						Timer track.
 * @return							Floating number of the player's best time for given prop/track.
 */
native float PropTricks_GetClientPB(int client, int prop, int track);

/**
 * Sets the cached pb directly for the given client, prop and track.
 *
 * @param client					Client index.
 * @param prop						Prop to get the PB for.
 * @param track						Timer track.
 * @param time						Time to set
 * @noreturn
 */
native void PropTricks_SetClientPB(int client, int prop, int track, float time);

/**
 * Retrieves the completions of a player.
 *
 * @param client					Client index.
 * @param prop						Prop to get the Completions for.
 * @param track						Timer track.
 * @return							Number of the player's Completions for given prop/track.
 */
native int PropTricks_GetClientCompletions(int client, int prop, int track);

/**
 * Get the amount of records on the current map/prop on a track.
 *
 * @param prop						Prop.
 * @param track						Timer track.
 * @return							Amount of records.
 */
native int PropTricks_GetRecordAmount(int prop, int track);

/**
 * Calculate potential rank for a given prop and time.
 *
 * @param prop						Prop.
 * @param time						Time to check for.
 * @param track						Timer track.
 * @return							Map rank.
 */
native int PropTricks_GetRankForTime(int prop, float time, int track);

/**
 * Retrieves the time of a record from a specified rank.
 *
 * @param prop						Prop.
 * @param rank						Rank to retrieve the time from.
 * @param track						Timer track.
 * @return							Record time. 0.0 if none.
 */
native float PropTricks_GetTimeForRank(int prop, int rank, int track);

/**
 * Checks if a mapzone exists.
 *
 * @param type						Mapzone type.
 * @param track						Mapzone track, -1 to ignore track.
 * @return							Boolean value.
 */
native bool PropTricks_ZoneExists(int type, int track);

/**
 * Checks if a player is inside a mapzone.
 *
 * @param client					Client index.
 * @param type						Mapzone type.
 * @param track						Mapzone track, -1 to ignore track.
 * @return							Boolean value.
 */
native bool PropTricks_InsideZone(int client, int type, int track);

/**
 * Gets the specified zone's data.
 *
 * @param zoneid					ID of the zone we query the data of.
 * @return							Zone data. 0 if none is specified.
 */
native int PropTricks_GetZoneData(int zoneid);

/**
 * Gets the specified zone's flags.
 *
 * @param zoneid					ID of the zone we query the flags of.
 * @return							Zone flags. 0 if none is specified.
 */
native int PropTricks_GetZoneFlags(int zoneid);

/**
 * Checks if a player is inside a mapzone.
 *
 * @param client					Client index.
 * @param type						Mapzone type.
 * @param track						Mapzone track, -1 to ignore track.
 * @param zoneid					Reference to variable that will hold the zone's ID.
 * @return							Boolean value.
 */
native bool PropTricks_InsideZoneGetID(int client, int type, int track, int &zoneid);

/**
 * Checks if a player is in the process of creating a mapzone.
 *
 * @param client					Client index.
 * @return							Boolean value.
 */
native bool PropTricks_IsClientCreatingZone(int client);

/**
 * Pauses a player's timer.
 *
 * @param client					Client index.
 * @noreturn
 */
native void PropTricks_PauseTimer(int client);

/**
 * Resumes a player's timer.
 *
 * @param client					Client index.
 * @param teleport					Should the player be teleported to their location prior to saving?
 * @noreturn
 */
native void PropTricks_ResumeTimer(int client, bool teleport = false);

/**
 * Gets a players time offset given a zone.
 *
 * @param client					Client index.
 * @param teleport					Zone type (Zone_Start or Zone_End).
 * @return							Time offset if any for the given zone type.
 */
native float PropTricks_GetTimeOffset(int client, int zonetype);

/**
 * Gets distance of a players distance offset given a zone.
 *
 * @param client					Client index.
 * @param teleport					Zone type (Zone_Start or Zone_End).
 * @return 							Distance offset if any for the given zone type/
 */
native float PropTricks_GetDistanceOffset(int client, int zonetype);

/**
 * Deletes the specified replay file.
 * Replay data will be unloaded if necessary.
 *
 * @param map						Map display name.
 * @param prop						prop.
 * @param track						Timer track.
 * @param accountid					Account ID to validate against, 0 to skip validation.
 * @return							true if replay existed, false if the steam id didn't match or the file didn't exist.
 */
native bool PropTricks_DeleteReplay(const char[] map, int prop, int track, int accountid = 0);

/**
 * Retrieves the engine time of the replay bot's first frame.
 *
 * @param prop						Prop.
 * @param time						Reference to save the time on.
 * @noreturn
 */
native void PropTricks_GetReplayBotFirstFrame(int prop, float &time);

/**
 * Retrieve the replay bot's client index.
 *
 * @return							Client index for the replay bot.
 */
native int PropTricks_GetReplayBotIndex();

/**
 * Retrieve the replay bot's prop entity index.
 *
 * @return							Prop entity index for the replay bot.
 */
native int PropTricks_GetReplayPropIndex();

/**
 * Retrieve the prop being played by the replay bot.
 *
 * @param client					Client index.
 * @return							Prop being played by the replay bot. -1 if it's a central replay bot that's idle.
 */
native int PropTricks_GetReplayBotProp(int client);

/**
 * Retrieve the timer track being played by the replay bot.
 *
 * @param client					Client index.
 * @return							Timer track replayed by the bot. -1 if it's not a bot.
 */
native int PropTricks_GetReplayBotTrack(int client);

/**
 * Retrieve the replay bot's current played frame.
 *
 * @param prop						Prop.
 * @return							Current played frame.
 */
native int PropTricks_GetReplayBotCurrentFrame(int prop);

/**
 * Retrieves a replay's frame count.
 *
 * @param prop						Prop.
 * @param track						Track.
 * @noreturn
 */
native int PropTricks_GetReplayFrameCount(int prop, int track);

/**
 * Retrieves the replay data for the given prop and track.
 *
 * @param prop						Prop.
 * @param track						Track.
 * @return							ArrayList with proper replay data, or null if there is no recorded data.
 */
native ArrayList PropTricks_GetReplayFrames(int prop, int track);

/**
 * Retrieves a client's frame count.
 *
 * @param client					Client Index.
 * @return							Current number of frames.
 */
native int PropTricks_GetClientFrameCount(int client);

/**
 * Retrieves a replay's total length in seconds.
 *
 * @param prop						Prop.
 * @param track						Track.
 * @noreturn
 */
native float PropTricks_GetReplayLength(int prop, int track);

/**
 * Retrieves an actively playing replay's time.
 *
 * @param prop						Prop.
 * @param track						Track. (ignored for non-central bots)
 * @noreturn
 */
native float PropTricks_GetReplayTime(int prop, int track);

/**
 * Retrieves a replay holder's name.
 *
 * @param prop						Prop.
 * @param track						Track.
 * @param buffer					Buffer string.
 * @param length					String length.
 * @noreturn
 */
native void PropTricks_GetReplayName(int prop, int track, char[] buffer, int length);

/**
 * Checks if there's loaded replay data for a bhop prop or not.
 *
 * @param prop						Prop.
 * @param track						Track.
 * @return							Boolean value of if there's loaded replay data.
 */
native bool PropTricks_IsReplayDataLoaded(int prop, int track);

/**
 * Gets player points.
 *
 * @param client					Client index.
 * @return							Points. 0.0 if unranked.
 */
native float PropTricks_GetPoints(int client);

/**
 * Gets player rank.
 *
 * @param client					Client index.
 * @return							Rank. 0 if unranked.
 */
native int PropTricks_GetRank(int client);

/**
 * Gets the amount of players with over 0 points.
 *
 * @return							Amount of ranked players.
 */
native int PropTricks_GetRankedPlayers();

/**
 * Force an HUD update for a player. Requires proptricks-hud.
 *
 * @param client					Client index.
 * @param spectators				Should also update it for the player's spectators?
 * @error							Error code 200 if client isn't valid.
 * @return							Amount of players that had their HUD updated (client + spectators) or -1 on error.
 */
native int PropTricks_ForceHUDUpdate(int client, bool spectators);

/**
 * Opens the stats menu for a client.
 *
 * @param client					Client index.
 * @param steamid					Target Steam account ID to use.
 * @noreturn
 */
native void PropTricks_OpenStatsMenu(int client, int steamid);

/**
 * Retrieves the amount of #1 records a player has.
 * Result will depend on the value of `proptricks_stats_mvprankones`.
 * Called from proptricks-stats.
 *
 * @param client					Client index.
 * @noreturn
 */
native int PropTricks_GetWRCount(int client);

/**
* Saves the prop settings on `any` references.
*
* @param prop						Prop index.
* @param PropSettings				Reference to the settings array.
* @param size						Size of the PropSettings buffer, e.g sizeof(propsettings_t)
* @return							SP_ERROR_NONE on success, anything else on failure.
*/
native int PropTricks_GetPropSettings(int style, any[] PropSettings, int size = sizeof(propsettings_t));

/**
 * Saves the prop related strings on string references.
 *
 * @param prop						Prop index.
 * @param stringtype				String type to grab.
 * @param PropStrings				Reference to the string buffer.
 * @param size						Max length for the buffer.
 * @return							SP_ERROR_NONE on success, anything else on failure.
 */
native int PropTricks_GetPropStrings(int prop, int stringtype, char[] PropStrings, int size);

/**
 * Retrieves the amount of props in the server.
 *
 * @return							Amount of props or -1 if there's an error.
 */
native int PropTricks_GetPropCount();

/**
 * Gets an array with prop IDs in their configured menu ordering as specified in the styles config.
 *
 * @param arr						Reference to array to fill with prop IDs.
 * @param size						Array size.
 * @noreturn
 */
native void PropTricks_GetOrderedProps(int[] arr, int size);

/**
 * Saves chat related strings on string references.
 *
 * @param strings					Reference to the string buffer.
 * @param size						Max length for the buffer.
 * @return							SP_ERROR_NONE on success, anything else on failure.
 */
native int PropTricks_GetChatStrings(any[] strings, int size = sizeof(chatstrings_t));

/**
 * Gets the HUD settings of a player.
 * See the HUD_* defines for information.
 *
 * @param client					Client index.
 * @return							HUD settings.
 */
native int PropTricks_GetHUDSettings(int client);

/**
 * Sets a player's replay recording frames from a provided ArrayList.
 * To be used by save states/TAS etc.
 *
 * @param client					Client index.
 * @param data						ArrayList with proper replay data.
 * @noreturn
 */
native void PropTricks_SetReplayData(int client, ArrayList data);

/**
 * Saves a player's replay recording frames (if exists) into an ArrayList.
 * To be used by save states/TAS etc.
 *
 * @param client					Client index.
 * @return							ArrayList with proper replay data, or null if the player has no recorded data.
 */
native ArrayList PropTricks_GetReplayData(int client);

/**
 * Starts a replay given a prop and track. 
 * @param client					Client index.
 * @param prop						prop.
 * @param track						Timer track.
 * @noreturn							
 */
native void PropTricks_StartReplay(int prop, int track, float delay, int client = 1);

/**
 * Reloads a specific replay into the replay bot cache.
 * Note: Not guaranteed to work with legacy replay bots.
 *
 * @param prop						Replay prop.
 * @param track						Replay track.
 * @param restart					Restart the playback of the replay bot if it's playing?
 * @param path						Path to the replay file. Use `BuildPath(Path_SM, ...)` to generate one. Leave as empty to use default.
 * @return							Was the replay loaded?
 */ 
native bool PropTricks_ReloadReplay(int prop, int track, char[] path = "");

/**
 * Reloads all of the replays for the map.
 * Note: Not guaranteed to work with legacy replay bots.
 *
 * @param restart					Restart the playback of the replay bots?
 * @return							Amount of loaded replays.
 */
native int PropTricks_ReloadReplays();

/**
 * Gets time from replay frame that is closest to client.
 *
 * @param 				Client index.
 * @param				Client prop.
 * @param				Client track.
 * @return				Replay time.
 */
native float PropTricks_GetClosestReplayTime(int client, int prop, int track);

/**
 * Use this native to stop the click sound that plays upon chat messages.
 * Call it before each PropTricks_PrintToChat().
 * PropTricks_PrintToChatAll() is not guaranteed to disable the sound from playing.
 *
 * @noreturn
 */
native void PropTricks_StopChatSound();

/**
 * Marks a map as if it has built-in zones/buttons.
 *
 * @noreturn
 */
native void PropTricks_MarkKZMap();

/**
 * Lets us know if the map was marked as a KZ map.
 * KZ map: a map with built-in zones/buttons.
 * Does not necessarily mean that the map was designed for KZ gameplay.
 *
 * @return							Boolean value.
 */
native bool PropTricks_IsKZMap();

/**
 * Gets the map tier for a specified map.
 * Use the map's display name.
 *
 * @param map						Map to get the tier of.
 * @return							Map tier. 0 if no results were found.
 */
native int PropTricks_GetMapTier(const char[] map);

/**
 * Gets a StringMap that contains all the cached map tiers.
 * The returned StringMap must be deleted from memory after use!
 *
 * @return							StringMap with {const char[]: map, int: tier} structure.
 */
native StringMap PropTricks_GetMapTiers();

/**
 * Use this native when printing anything in chat if it's related to the timer.
 * This native will auto-assign colors and a chat prefix.
 *
 * @param client					Client index.
 * @param format					Formatting rules.
 * @param any						Variable number of format parameters.
 * @return							PrintToChat()
 */
native int PropTricks_PrintToChat(int client, const char[] format, any ...);

/**
 * Logs an entry to bhoptimer's log file.
 * (addons/sourcemod/logs/proptricks.log)
 *
 * @param format					Formatting rules.
 * @param any						Variable number of format parameters.
 * @noreturn
 */
native void PropTricks_LogMessage(const char[] format, any ...);

/**
 * Gets the total number of CPs that a client has saved
 *
 * @param client					Client index
 *
 * @return							Total number of checkpoints
 */
 native int PropTricks_GetTotalCheckpoints(int client);

/**
 * Gets CP data for a client at specified index
 *
 * @param client					Client index
 * @param index						Index of CP to get
 * @param cpcache					Buffer to store cp data in sizeof(cp_cache_t)
 * @param size						Size of the cpcache buffer, e.g sizeof(cp_cache_t)
 *
 * @noreturn
 */
native bool PropTricks_GetCheckpoint(int client, int index, any[] cpcache, int size = sizeof(cp_cache_t));

/**
 * Sets checkpoint data at the given index for the given client
 *
 * @param client					Client index
 * @param index						Index of CP to set, or -1 to push cp as last
 * @param cpcache					Buffer to store cp data in sizeof(cp_cache_t)
 * @param size						Size of the cpcache buffer, e.g sizeof(cp_cache_t)
 * @param cpcache					Buffer with cp data
 *
 * @noreturn
 */
native void PropTricks_SetCheckpoint(int client, int index, any[] cpcache, int size = sizeof(cp_cache_t));

/**
 * Teleports client to the checkpoint at given index
 *
 * @param client					Client index
 * @param index						Index of CP to teleport to
 * @param suppress					Supress checkpoint message
 *
 * @noreturn
 */
native void PropTricks_TeleportToCheckpoint(int client, int index, bool suppress = false);

/**
 * Clears all saved checkpoints for the specified client
 *
 * @param client					Client index
 *
 * @noreturn
 */
native void PropTricks_ClearCheckpoints(int client);

/**
 * Opens checkpoint menu for a client
 *
 * @param client					Client index
 *
 * @noreturn
 */
native void PropTricks_OpenCheckpointMenu(int client);

/**
 * Gets the replay status
 *
 *
 * @return							Replay's status
 */
native ReplayStatus PropTricks_GetReplayStatus();

/**
 * Saves a new checkpoint and returns the new checkpoint index
 *
 * @param client					Client index
 *
 * @return							The new current checkpoint
 */
native int PropTricks_SaveCheckpoint(int client);

/**
 * Gets the current checkpoint index.
 *
 * @param client					Client index
 *
 * @return							The current checkpoint
 */
native int PropTricks_GetCurrentCheckpoint(int client);

/**
 * Sets the current checkpoint index.
 *
 * @param client					Client index
 * @param index						New index to use
 *
 * @noreturn
 */
native void PropTricks_SetCurrentCheckpoint(int client, int index);

/*
 * returns the number of preframes in the players current run.
 *
 * @param client					Client index
 *
 * @return 							Preframe count
 */
native int PropTricks_GetPlayerPreFrame(int client);

/*
 * returns the number of timer preframes in the players current run.
 *
 * @param client					Client index
 *
 * @return 							Timer preframe count
 */
 native int PropTricks_GetPlayerTimerFrame(int client);

/*
 * Sets player's preframe length.
 *
 * @param client					Client index
 * @param PreFrame					PreFrame length
 * @param TimerPreFrame				Timer start frame length
 *
 * @noreturn
 */
native void PropTricks_SetPlayerPreFrame(int client, int PreFrame);

/*
 * Sets player's timer preframe length.
 *
 * @param client					Client index
 * @param TimerPreFrame				Timer start frame length
 *
 * @noreturn
 */
native void PropTricks_SetPlayerTimerFrame(int client, int TimerPreFrame);

/*
 * Retrieve a client's prop's entity index
 *
 * @param client					Client index
 * 
 * @return							Prop
 */
native int PropTricks_GetPropEntityIndex(int client);

/*
 * ...
 *
 * @param entity					Entity index
 * @param wsc						World Space Center
 * 
 * @noreturn
 */
native void PropTricks_GetWorldSpaceCenter(int entity, float wsc[3]);

// called when the game performs collision checks through traces (only for traces using filters)
// return something other than Plugin_Continue to have the game use the result parameter
// note: any code in this forward should be very performant, the game will use many filtered traces per player per game frame
forward Action PropTricks_OnPassEntityFilter(int ent1, int ent2, bool& result);

// called when the game is performing vphysics collision checks between entities
// return something other than Plugin_Continue to have the game use the result parameter
forward Action PropTricks_OnShouldCollide(int ent1, int ent2, bool& result);

forward Action PropTricks_OnPushToggle(int client, bool pressed);

forward void PropTricks_OnPush(int client, int entity, float pushaway[3], float force);

forward void PropTricks_OnReplayPropCreated(int prop, int entity);

// same as PropTricks_PrintToChat() but loops through the whole server
// code stolen from the base halflife.inc file
stock void PropTricks_PrintToChatAll(const char[] format, any ...)
{
	char buffer[300];

	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientInGame(i))
		{
			SetGlobalTransTarget(i);
			VFormat(buffer, 300, format, 2);
			PropTricks_PrintToChat(i, "%s", buffer);
		}
	}
}

static KeyValues kv = null;

// Retrieves accountid from STEAM_X:Y:Z, [U:1:123], and 765xxxxxxxxxxxxxx
stock int SteamIDToAccountID(const char[] sInput)
{
	char sSteamID[32];
	strcopy(sSteamID, sizeof(sSteamID), sInput);
	ReplaceString(sSteamID, 32, "\"", "");
	TrimString(sSteamID);

	if (StrContains(sSteamID, "STEAM_") != -1)
	{
		ReplaceString(sSteamID, 32, "STEAM_", "");

		char parts[3][11];
		ExplodeString(sSteamID, ":", parts, 3, 11);

		// Let X, Y and Z constants be defined by the SteamID: STEAM_X:Y:Z.
		// Using the formula W=Z*2+Y, a SteamID can be converted:
		return StringToInt(parts[2]) * 2 + StringToInt(parts[1]);
	}
	else if (StrContains(sSteamID, "U:1:") != -1)
	{
		ReplaceString(sSteamID, 32, "[", "");
		ReplaceString(sSteamID, 32, "U:1:", "");
		ReplaceString(sSteamID, 32, "]", "");

		return StringToInt(sSteamID);
	}
	else if (StrContains(sSteamID, "765") == 0)
	{
		return SteamID64ToAccountID(sSteamID);
	}

	return 0;
}

stock void AccountIDToSteamID64Num(int accountid, int num[2])
{
	num[0] = accountid;
	//       universe  | type      | instance
	num[1] = (1 << 24) | (1 << 20) | 1; // 0x01100001
}

stock void AccountIDToSteamID64(int accountid, char[] buf, int buflen)
{
	int num[2];
	AccountIDToSteamID64Num(accountid, num);
	SteamID64ToString(num, buf, buflen);
}

stock void AccountIDToSteamID2(int accountid, char[] buf, int buflen)
{
	FormatEx(buf, buflen, "STEAM_0:%d:%d", accountid&1, (accountid>>1) & 0x7FFFFFFF);
}

stock void AccountIDToSteamID3(int accountid, char[] buf, int buflen)
{
	FormatEx(buf, buflen, "[U:1:%d]", accountid);
}

stock void SteamID64ToString(int num[2], char[] buf, int buflen)
{
	if (kv == null)
		kv = new KeyValues("fuck sourcemod");

	kv.SetUInt64(NULL_STRING, num);
	kv.GetString(NULL_STRING, buf, buflen);
}

stock int SteamID64ToAccountID(const char[] steamid64)
{
	if (kv == null)
		kv = new KeyValues("fuck sourcemod");

	int num[2];
	kv.SetString(NULL_STRING, steamid64);
	kv.GetUInt64(NULL_STRING, num);
	return num[0]; // & 0x7FFFFFFF;
}

stock bool IsInEyeRange(int client, int entity, float distance)
{
    float pos[3], angs[3], fwd[3], end[3];
    
    GetClientEyePosition(client, pos);
    GetClientEyeAngles(client, angs)
    GetAngleVectors(angs, fwd, NULL_VECTOR, NULL_VECTOR);
    
    ScaleVector(fwd, 96.0);
    AddVectors(pos, fwd, end);
    
    TR_TraceRayFilter(pos, end, MASK_SOLID, RayType_EndPoint, UseTrace_Filter, entity);
    
    return TR_DidHit() && TR_GetEntityIndex() == entity;
}

static bool UseTrace_Filter(int entity, int contentsMask, int ent)
{
    return entity == ent;
}

stock void CalculateForces(int client, int entity, float direction[3], float &force)
{
    float ent_center[3], center[3];
#if defined GetWorldSpaceCenter
    GetWorldSpaceCenter(entity, ent_center);
    GetWorldSpaceCenter(client, center);
#else
    PropTricks_GetWorldSpaceCenter(entity, ent_center);
    PropTricks_GetWorldSpaceCenter(client, center);
#endif
    
    SubtractVectors(ent_center, center, direction);
    direction[2] = 0.0;
    
    float dist = NormalizeVector(direction, direction);
    if(dist < 1.0)
        dist = 1.0;
    
    static ConVar sv_pushaway_force, sv_pushaway_max_force;
    
    if(!sv_pushaway_force)
        sv_pushaway_force = FindConVar("sv_pushaway_force");
    
    if(!sv_pushaway_max_force)
        sv_pushaway_max_force = FindConVar("sv_pushaway_max_force");
    
    force = sv_pushaway_force.FloatValue / dist;
    if(force > sv_pushaway_max_force.FloatValue)
        force = sv_pushaway_max_force.FloatValue;
}

public SharedPlugin __pl_proptricks =
{
	name = "proptricks",
	// SM bug? commented until it's fixed
	// file = "proptricks-core.smx",
#if defined REQUIRE_PLUGIN
	required = 1
#else
	required = 0
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_proptricks_SetNTVOptional()
{
	MarkNativeAsOptional("PropTricks_GetWorldSpaceCenter");
	MarkNativeAsOptional("PropTricks_GetPropEntityIndex");
	MarkNativeAsOptional("PropTricks_ChangeClientProp");
	MarkNativeAsOptional("PropTricks_DeleteReplay");
	MarkNativeAsOptional("PropTricks_FinishMap");
	MarkNativeAsOptional("PropTricks_ForceHUDUpdate");
	MarkNativeAsOptional("PropTricks_FormatChat");
	MarkNativeAsOptional("PropTricks_GetClientProp");
	MarkNativeAsOptional("PropTricks_GetChatStrings");
	MarkNativeAsOptional("PropTricks_GetClientPB");
	MarkNativeAsOptional("PropTricks_SetClientPB");
	MarkNativeAsOptional("PropTricks_GetClientTime");
	MarkNativeAsOptional("PropTricks_GetClientTrack");
	MarkNativeAsOptional("PropTricks_GetDatabase");
	MarkNativeAsOptional("PropTricks_GetDB");
	MarkNativeAsOptional("PropTricks_GetHUDSettings");
	MarkNativeAsOptional("PropTricks_GetMapTier");
	MarkNativeAsOptional("PropTricks_GetMapTiers");
	MarkNativeAsOptional("PropTricks_GetPlayerPB");
	MarkNativeAsOptional("PropTricks_GetPoints");
	MarkNativeAsOptional("PropTricks_GetRank");
	MarkNativeAsOptional("PropTricks_GetRankedPlayers");
	MarkNativeAsOptional("PropTricks_GetRankForTime");
	MarkNativeAsOptional("PropTricks_GetRecordAmount");
	MarkNativeAsOptional("PropTricks_GetReplayBotCurrentFrame");
	MarkNativeAsOptional("PropTricks_GetClientFrameCount");
	MarkNativeAsOptional("PropTricks_GetReplayBotFirstFrame");
	MarkNativeAsOptional("PropTricks_GetReplayBotIndex");
	MarkNativeAsOptional("PropTricks_GetReplayBotProp");
	MarkNativeAsOptional("PropTricks_GetReplayBotTrack");
	MarkNativeAsOptional("PropTricks_GetReplayData");
	MarkNativeAsOptional("PropTricks_GetReplayFrameCount");
	MarkNativeAsOptional("PropTricks_GetReplayFrames");
	MarkNativeAsOptional("PropTricks_GetReplayLength");
	MarkNativeAsOptional("PropTricks_GetReplayName");
	MarkNativeAsOptional("PropTricks_GetReplayStatus");
	MarkNativeAsOptional("PropTricks_GetReplayTime");
	MarkNativeAsOptional("PropTricks_GetPropCount");
	MarkNativeAsOptional("PropTricks_GetOrderedProps");
	MarkNativeAsOptional("PropTricks_GetPropSettings");
	MarkNativeAsOptional("PropTricks_GetPropStrings");
	MarkNativeAsOptional("PropTricks_GetTimeOffset");
	MarkNativeAsOptional("PropTricks_GetDistanceOffset");
	MarkNativeAsOptional("PropTricks_GetTimeForRank");
	MarkNativeAsOptional("PropTricks_GetTimer");
	MarkNativeAsOptional("PropTricks_GetTimerStatus");
	MarkNativeAsOptional("PropTricks_GetWorldRecord");
	MarkNativeAsOptional("PropTricks_GetWRCount");
	MarkNativeAsOptional("PropTricks_GetWRName");
	MarkNativeAsOptional("PropTricks_GetWRRecordID");
	MarkNativeAsOptional("PropTricks_GetWRTime");
	MarkNativeAsOptional("PropTricks_GetZoneData");
	MarkNativeAsOptional("PropTricks_GetZoneFlags");
	MarkNativeAsOptional("PropTricks_HijackAngles");
	MarkNativeAsOptional("PropTricks_InsideZone");
	MarkNativeAsOptional("PropTricks_InsideZoneGetID");
	MarkNativeAsOptional("PropTricks_IsClientCreatingZone");
	MarkNativeAsOptional("PropTricks_IsReplayDataLoaded");
	MarkNativeAsOptional("PropTricks_OpenStatsMenu");
	MarkNativeAsOptional("PropTricks_PrintToChat");
	MarkNativeAsOptional("PropTricks_Rankings_DeleteMap");
	MarkNativeAsOptional("PropTricks_ReloadLeaderboards");
	MarkNativeAsOptional("PropTricks_ReloadReplay");
	MarkNativeAsOptional("PropTricks_ReloadReplays");
	MarkNativeAsOptional("PropTricks_Replay_DeleteMap");
	MarkNativeAsOptional("PropTricks_RestartTimer");
	MarkNativeAsOptional("PropTricks_SetReplayData");
	MarkNativeAsOptional("PropTricks_StartReplay");
	MarkNativeAsOptional("PropTricks_StartTimer");
	MarkNativeAsOptional("PropTricks_StopChatSound");
	MarkNativeAsOptional("PropTricks_StopTimer");
	MarkNativeAsOptional("PropTricks_WR_DeleteMap");
	MarkNativeAsOptional("PropTricks_ZoneExists");
	MarkNativeAsOptional("PropTricks_Zones_DeleteMap");
	MarkNativeAsOptional("PropTricks_GetTotalCheckpoints");
	MarkNativeAsOptional("PropTricks_GetCheckpoint");
	MarkNativeAsOptional("PropTricks_SetCheckpoint");
	MarkNativeAsOptional("PropTricks_TeleportToCheckpoint");
	MarkNativeAsOptional("PropTricks_ClearCheckpoints");
	MarkNativeAsOptional("PropTricks_OpenCheckpointMenu");
	MarkNativeAsOptional("PropTricks_SaveCheckpoint");
	MarkNativeAsOptional("PropTricks_GetCurrentCheckpoint");
	MarkNativeAsOptional("PropTricks_SetCurrentCheckpoint");
	MarkNativeAsOptional("PropTricks_GetPlayerPreFrame");
	MarkNativeAsOptional("PropTricks_GetPlayerTimerFrame");
	MarkNativeAsOptional("PropTricks_SetPlayerPreFrame");
	MarkNativeAsOptional("PropTricks_GetClosestReplayTime");
	MarkNativeAsOptional("PropTricks_SetPlayerTimerFrame");
}
#endif
