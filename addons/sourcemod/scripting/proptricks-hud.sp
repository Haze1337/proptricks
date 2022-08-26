#include <sourcemod>
#include <sdkhooks>
#include <clientprefs>
#include <convar_class>
#include <vphysics>

#undef REQUIRE_PLUGIN
#include <proptricks>

#pragma newdecls required
#pragma semicolon 1

// HUD2 - these settings will *disable* elements for the main hud
#define HUD2_TIME				(1 << 0)
#define HUD2_SPEED				(1 << 1)
#define HUD2_PROPSPEED			(1 << 2)
#define HUD2_PROP				(1 << 3)
#define HUD2_RANK				(1 << 4)
#define HUD2_TRACK				(1 << 5)
#define HUD2_SPLITPB			(1 << 6)
#define HUD2_MAPTIER			(1 << 7)
#define HUD2_TIMEDIFFERENCE		(1 << 8)
#define HUD2_TOPLEFT_RANK		(1 << 9)

#define HUD_DEFAULT				(HUD_MASTER|HUD_CENTER|HUD_ZONEHUD|HUD_OBSERVE|HUD_TOPLEFT|HUD_2DVEL|HUD_SPECTATORS)
#define HUD_DEFAULT2			(HUD2_TIMEDIFFERENCE)

#define MAX_HINT_SIZE 225

enum ZoneHUD
{
	ZoneHUD_None,
	ZoneHUD_Start,
	ZoneHUD_End
};

enum struct huddata_t
{
	int iTarget;
	float fTime;
	int iSpeed;
	int iPropSpeed;
	int iProp;
	int iTrack;
	int iRank;
	float fPB;
	float fWR;
	bool bReplay;
	TimerStatus iTimerStatus;
	ZoneHUD iZoneHUD;
}

// forwards
Handle gH_Forwards_OnTopLeftHUD = null;

// modules
bool gB_Replay = false;
bool gB_Sounds = false;
bool gB_Rankings = false;

// cache
int gI_Cycle = 0;
int gI_Props = 0;
char gS_Map[160];

Handle gH_HUDCookie = null;
Handle gH_HUDCookieMain = null;
int gI_HUDSettings[MAXPLAYERS+1];
int gI_HUD2Settings[MAXPLAYERS+1];
int gI_Buttons[MAXPLAYERS+1];
float gF_ConnectTime[MAXPLAYERS+1];
bool gB_FirstPrint[MAXPLAYERS+1];

bool gB_Late = false;

// hud handle
Handle gH_HUD = null;

// plugin cvars
Convar gCV_TicksPerUpdate = null;
Convar gCV_SpectatorList = null;
Convar gCV_SpecNameSymbolLength = null;
Convar gCV_DefaultHUD = null;
Convar gCV_DefaultHUD2 = null;
Convar gCV_EnableDynamicTimeDifference = null;

// timer settings
propstrings_t gS_PropStrings[PROP_LIMIT];
chatstrings_t gS_ChatStrings;

public Plugin myinfo =
{
	name = "[PropTricks] HUD",
	author = "Haze",
	description = "HUD for proptricks timer.",
	version = PROPTRICKS_VERSION,
	url = ""
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
	// forwards
	gH_Forwards_OnTopLeftHUD = CreateGlobalForward("PropTricks_OnTopLeftHUD", ET_Event, Param_Cell, Param_Cell, Param_String, Param_Cell);

	// natives
	CreateNative("PropTricks_ForceHUDUpdate", Native_ForceHUDUpdate);
	CreateNative("PropTricks_GetHUDSettings", Native_GetHUDSettings);

	// registers library, check "bool LibraryExists(const char[] name)" in order to use with other plugins
	RegPluginLibrary("proptricks-hud");

	gB_Late = late;

	return APLRes_Success;
}

public void OnPluginStart()
{
	LoadTranslations("proptricks-common.phrases");
	LoadTranslations("proptricks-hud.phrases");

	// prevent errors in case the replay bot isn't loaded
	gB_Replay = LibraryExists("proptricks-replay");
	gB_Sounds = LibraryExists("proptricks-sounds");
	gB_Rankings = LibraryExists("proptricks-rankings");

	// HUD handle
	gH_HUD = CreateHudSynchronizer();

	// plugin convars
	gCV_TicksPerUpdate = new Convar("proptricks_hud_ticksperupdate", "5", "How often (in ticks) should the HUD update?\nPlay around with this value until you find the best for your server.\nThe maximum value is your tickrate.", 0, true, 1.0, true, (1.0 / GetTickInterval()));
	gCV_SpectatorList = new Convar("proptricks_hud_speclist", "1", "Who to show in the specators list?\n0 - everyone\n1 - all admins (admin_speclisthide override to bypass)\n2 - players you can target", 0, true, 0.0, true, 2.0);
	gCV_EnableDynamicTimeDifference = new Convar("proptricks_hud_timedifference", "0", "Enabled dynamic time differences in the hud", 0, true, 0.0, true, 1.0);
	gCV_SpecNameSymbolLength = new Convar("proptricks_hud_specnamesymbollength", "32", "Maximum player name length that should be displayed in spectators panel", 0, true, 0.0, true, float(MAX_NAME_LENGTH));

	char defaultHUD[8];
	IntToString(HUD_DEFAULT, defaultHUD, 8);
	gCV_DefaultHUD = new Convar("proptricks_hud_default", defaultHUD, "Default HUD settings as a bitflag\n"
		..."HUD_MASTER				1\n"
		..."HUD_CENTER				2\n"
		..."HUD_ZONEHUD				4\n"
		..."HUD_OBSERVE				8\n"
		..."HUD_SPECTATORS			16\n"
		..."HUD_KEYOVERLAY			32\n"
		..."HUD_HIDEWEAPON			64\n"
		..."HUD_TOPLEFT				128\n"
		..."HUD_TIMELEFT			256\n"
		..."HUD_2DVEL				512\n"
		..."HUD_NOSOUNDS			1024");
		
	IntToString(HUD_DEFAULT2, defaultHUD, 8);
	gCV_DefaultHUD2 = new Convar("proptricks_hud2_default", defaultHUD, "Default HUD2 settings as a bitflag\n"
		..."HUD2_TIME				1\n"
		..."HUD2_SPEED				2\n"
		..."HUD2_PROPSPEED			4\n"
		..."HUD2_PROP				8\n"
		..."HUD2_RANK				16\n"
		..."HUD2_TRACK				32\n"
		..."HUD2_SPLITPB			64\n"
		..."HUD2_MAPTIER			128\n"
		..."HUD2_TIMEDIFFERENCE		256\n"
		..."HUD2_TOPLEFT_RANK		512");

	Convar.AutoExecConfig();

	// commands
	RegConsoleCmd("sm_hud", Command_HUD, "Opens the HUD settings menu.");

	// hud togglers
	RegConsoleCmd("sm_keys", Command_Keys, "Toggles key display.");
	RegConsoleCmd("sm_showmykeys", Command_Keys, "Toggles key display. (alias for sm_keys)");
	RegConsoleCmd("sm_showkeys", Command_Keys, "Toggles key display. (alias for sm_keys)");

	RegConsoleCmd("sm_hideweapon", Command_HideWeapon, "Toggles weapon hiding.");
	RegConsoleCmd("sm_hideweap", Command_HideWeapon, "Toggles weapon hiding. (alias for sm_hideweapon)");
	RegConsoleCmd("sm_hidewep", Command_HideWeapon, "Toggles weapon hiding. (alias for sm_hideweapon)");

	RegConsoleCmd("sm_truevel", Command_TrueVel, "Toggles 2D ('true') velocity.");
	RegConsoleCmd("sm_truvel", Command_TrueVel, "Toggles 2D ('true') velocity. (alias for sm_truevel)");
	RegConsoleCmd("sm_2dvel", Command_TrueVel, "Toggles 2D ('true') velocity. (alias for sm_truevel)");

	// cookies
	gH_HUDCookie = RegClientCookie("proptricks_hud_setting", "HUD settings", CookieAccess_Protected);
	gH_HUDCookieMain = RegClientCookie("proptricks_hud_settingmain", "HUD settings for hint text.", CookieAccess_Protected);

	if(gB_Late)
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(IsValidClient(i))
			{
				OnClientPutInServer(i);

				if(AreClientCookiesCached(i) && !IsFakeClient(i))
				{
					OnClientCookiesCached(i);
				}
			}
		}
	}
}

public void OnMapStart()
{
	GetCurrentMap(gS_Map, 160);
	GetMapDisplayName(gS_Map, gS_Map, 160);

	if(gB_Late)
	{
		PropTricks_OnPropConfigLoaded(-1);
		PropTricks_GetChatStrings(gS_ChatStrings);
	}
}

public void OnLibraryAdded(const char[] name)
{
	if(StrEqual(name, "proptricks-replay"))
	{
		gB_Replay = true;
	}

	else if(StrEqual(name, "proptricks-sounds"))
	{
		gB_Sounds = true;
	}

	else if(StrEqual(name, "proptricks-rankings"))
	{
		gB_Rankings = true;
	}
}

public void OnLibraryRemoved(const char[] name)
{
	if(StrEqual(name, "proptricks-replay"))
	{
		gB_Replay = false;
	}

	else if(StrEqual(name, "proptricks-sounds"))
	{
		gB_Sounds = false;
	}

	else if(StrEqual(name, "proptricks-rankings"))
	{
		gB_Rankings = false;
	}
}

public void OnConfigsExecuted()
{
	ConVar sv_hudhint_sound = FindConVar("sv_hudhint_sound");

	if(sv_hudhint_sound != null)
	{
		sv_hudhint_sound.SetBool(false);
	}
}

public void PropTricks_OnPropConfigLoaded(int props)
{
	if(props == -1)
	{
		props = PropTricks_GetPropCount();
	}

	gI_Props = props;

	for(int i = 0; i < props; i++)
	{
		PropTricks_GetPropStrings(i, sPropName, gS_PropStrings[i].sPropName, sizeof(propstrings_t::sPropName));
	}
}

public Action PropTricks_OnUserCmdPre(int client, int &buttons, int &impulse, float vel[3], float angles[3], TimerStatus status, int track, int prop)
{
	gI_Buttons[client] = buttons;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(i == client || (IsValidClient(i) && GetSpectatorTarget(i) == client))
		{
			TriggerHUDUpdate(i, true);
		}
	}

	return Plugin_Continue;
}

public void PropTricks_OnChatConfigLoaded(chatstrings_t strings)
{
	gS_ChatStrings = strings;
}

public void OnClientPutInServer(int client)
{
	gB_FirstPrint[client] = false;

	if(IsFakeClient(client))
	{
		SDKHook(client, SDKHook_PostThinkPost, PostThinkPost);
	}
}

public void PostThinkPost(int client)
{
	int buttons = GetClientButtons(client);

	if(gI_Buttons[client] != buttons)
	{
		gI_Buttons[client] = buttons;

		for(int i = 1; i <= MaxClients; i++)
		{
			if(i != client && (IsValidClient(i) && GetSpectatorTarget(i) == client))
			{
				TriggerHUDUpdate(i, true);
			}
		}
	}
}

public void OnClientCookiesCached(int client)
{
	char sHUDSettings[8];
	GetClientCookie(client, gH_HUDCookie, sHUDSettings, 8);

	if(strlen(sHUDSettings) == 0)
	{
		gCV_DefaultHUD.GetString(sHUDSettings, 8);

		SetClientCookie(client, gH_HUDCookie, sHUDSettings);
		gI_HUDSettings[client] = gCV_DefaultHUD.IntValue;
	}

	else
	{
		gI_HUDSettings[client] = StringToInt(sHUDSettings);
	}

	GetClientCookie(client, gH_HUDCookieMain, sHUDSettings, 8);

	if(strlen(sHUDSettings) == 0)
	{
		gCV_DefaultHUD2.GetString(sHUDSettings, 8);

		SetClientCookie(client, gH_HUDCookieMain, sHUDSettings);
		gI_HUD2Settings[client] = gCV_DefaultHUD2.IntValue;
	}

	else
	{
		gI_HUD2Settings[client] = StringToInt(sHUDSettings);
	}
}

public void Player_ChangeClass(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(event.GetInt("userid"));

	if((gI_HUDSettings[client] & HUD_MASTER) > 0 && (gI_HUDSettings[client] & HUD_CENTER) > 0)
	{
		CreateTimer(0.5, PropTricks_FillerHintText, GetClientSerial(client), TIMER_FLAG_NO_MAPCHANGE);
	}
}

public void Teamplay_Round_Start(Event event, const char[] name, bool dontBroadcast)
{
	CreateTimer(0.5, PropTricks_FillerHintTextAll, 0, TIMER_FLAG_NO_MAPCHANGE);
}

public Action PropTricks_FillerHintTextAll(Handle timer, any data)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(IsClientConnected(i) && IsClientInGame(i))
		{
			FillerHintText(i);
		}
	}

	return Plugin_Stop;
}

public Action PropTricks_FillerHintText(Handle timer, any data)
{
	int client = GetClientFromSerial(data);

	if(client != 0)
	{
		FillerHintText(client);
	}

	return Plugin_Stop;
}

void FillerHintText(int client)
{
	PrintHintText(client, "...");
	gF_ConnectTime[client] = GetEngineTime();
	gB_FirstPrint[client] = true;
}

void ToggleHUD(int client, int hud, bool chat)
{
	if(!(1 <= client <= MaxClients))
	{
		return;
	}

	char sCookie[16];
	gI_HUDSettings[client] ^= hud;
	IntToString(gI_HUDSettings[client], sCookie, 16);
	SetClientCookie(client, gH_HUDCookie, sCookie);

	if(chat)
	{
		char sHUDSetting[64];

		switch(hud)
		{
			case HUD_MASTER: FormatEx(sHUDSetting, 64, "%T", "HudMaster", client);
			case HUD_CENTER: FormatEx(sHUDSetting, 64, "%T", "HudCenter", client);
			case HUD_ZONEHUD: FormatEx(sHUDSetting, 64, "%T", "HudZoneHud", client);
			case HUD_OBSERVE: FormatEx(sHUDSetting, 64, "%T", "HudObserve", client);
			case HUD_SPECTATORS: FormatEx(sHUDSetting, 64, "%T", "HudSpectators", client);
			case HUD_KEYOVERLAY: FormatEx(sHUDSetting, 64, "%T", "HudKeyOverlay", client);
			case HUD_HIDEWEAPON: FormatEx(sHUDSetting, 64, "%T", "HudHideWeapon", client);
			case HUD_TOPLEFT: FormatEx(sHUDSetting, 64, "%T", "HudTopLeft", client);
			case HUD_2DVEL: FormatEx(sHUDSetting, 64, "%T", "Hud2dVel", client);
			case HUD_NOSOUNDS: FormatEx(sHUDSetting, 64, "%T", "HudNoRecordSounds", client);
		}

		if((gI_HUDSettings[client] & hud) > 0)
		{
			PropTricks_PrintToChat(client, "%T", "HudEnabledComponent", client,
				gS_ChatStrings.sVariable, sHUDSetting, gS_ChatStrings.sText, gS_ChatStrings.sVariable2, gS_ChatStrings.sText);
		}

		else
		{
			PropTricks_PrintToChat(client, "%T", "HudDisabledComponent", client,
				gS_ChatStrings.sVariable, sHUDSetting, gS_ChatStrings.sText, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
		}
	}
}

public Action Command_HideWeapon(int client, int args)
{
	ToggleHUD(client, HUD_HIDEWEAPON, true);

	return Plugin_Handled;
}

public Action Command_TrueVel(int client, int args)
{
	ToggleHUD(client, HUD_2DVEL, true);

	return Plugin_Handled;
}

public Action Command_Keys(int client, int args)
{
	ToggleHUD(client, HUD_KEYOVERLAY, true);

	return Plugin_Handled;
}

public Action Command_HUD(int client, int args)
{
	return ShowHUDMenu(client, 0);
}

Action ShowHUDMenu(int client, int item)
{
	if(!IsValidClient(client))
	{
		return Plugin_Handled;
	}

	Menu menu = new Menu(MenuHandler_HUD, MENU_ACTIONS_DEFAULT|MenuAction_DisplayItem);
	menu.SetTitle("%T", "HUDMenuTitle", client);

	char sInfo[16];
	char sHudItem[64];
	FormatEx(sInfo, 16, "!%d", HUD_MASTER);
	FormatEx(sHudItem, 64, "%T", "HudMaster", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_CENTER);
	FormatEx(sHudItem, 64, "%T", "HudCenter", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_ZONEHUD);
	FormatEx(sHudItem, 64, "%T", "HudZoneHud", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_OBSERVE);
	FormatEx(sHudItem, 64, "%T", "HudObserve", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_SPECTATORS);
	FormatEx(sHudItem, 64, "%T", "HudSpectators", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_KEYOVERLAY);
	FormatEx(sHudItem, 64, "%T", "HudKeyOverlay", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_HIDEWEAPON);
	FormatEx(sHudItem, 64, "%T", "HudHideWeapon", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_TOPLEFT);
	FormatEx(sHudItem, 64, "%T", "HudTopLeft", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "!%d", HUD_2DVEL);
	FormatEx(sHudItem, 64, "%T", "Hud2dVel", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Sounds)
	{
		FormatEx(sInfo, 16, "!%d", HUD_NOSOUNDS);
		FormatEx(sHudItem, 64, "%T", "HudNoRecordSounds", client);
		menu.AddItem(sInfo, sHudItem);
	}

	// HUD2 - disables selected elements
	FormatEx(sInfo, 16, "@%d", HUD2_TIME);
	FormatEx(sHudItem, 64, "%T", "HudTimeText", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Replay)
	{
		FormatEx(sInfo, 16, "@%d", HUD2_TIMEDIFFERENCE);
		FormatEx(sHudItem, 64, "%T", "HudTimeDifference", client);
		menu.AddItem(sInfo, sHudItem);
	}

	FormatEx(sInfo, 16, "@%d", HUD2_SPEED);
	FormatEx(sHudItem, 64, "%T", "HudSpeedText", client);
	menu.AddItem(sInfo, sHudItem);
	
	FormatEx(sInfo, 16, "@%d", HUD2_PROPSPEED);
	FormatEx(sHudItem, 64, "%T", "HudPropSpeedText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_PROP);
	FormatEx(sHudItem, 64, "%T", "HudPropText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_RANK);
	FormatEx(sHudItem, 64, "%T", "HudRankText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_TRACK);
	FormatEx(sHudItem, 64, "%T", "HudTrackText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_SPLITPB);
	FormatEx(sHudItem, 64, "%T", "HudSplitPbText", client);
	menu.AddItem(sInfo, sHudItem);

	FormatEx(sInfo, 16, "@%d", HUD2_TOPLEFT_RANK);
	FormatEx(sHudItem, 64, "%T", "HudTopLeftRankText", client);
	menu.AddItem(sInfo, sHudItem);

	if(gB_Rankings)
	{
		FormatEx(sInfo, 16, "@%d", HUD2_MAPTIER);
		FormatEx(sHudItem, 64, "%T", "HudMapTierText", client);
		menu.AddItem(sInfo, sHudItem);
	}

	menu.ExitButton = true;
	menu.DisplayAt(client, item, 60);

	return Plugin_Handled;
}

public int MenuHandler_HUD(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char sCookie[16];
		menu.GetItem(param2, sCookie, 16);

		int type = (sCookie[0] == '!')? 1:2;
		ReplaceString(sCookie, 16, "!", "");
		ReplaceString(sCookie, 16, "@", "");

		int iSelection = StringToInt(sCookie);

		if(type == 1)
		{
			gI_HUDSettings[param1] ^= iSelection;
			IntToString(gI_HUDSettings[param1], sCookie, 16);
			SetClientCookie(param1, gH_HUDCookie, sCookie);
		}

		else
		{
			gI_HUD2Settings[param1] ^= iSelection;
			IntToString(gI_HUD2Settings[param1], sCookie, 16);
			SetClientCookie(param1, gH_HUDCookieMain, sCookie);
		}

		ShowHUDMenu(param1, GetMenuSelectionPosition());
	}

	else if(action == MenuAction_DisplayItem)
	{
		char sInfo[16];
		char sDisplay[64];
		int prop = 0;
		menu.GetItem(param2, sInfo, 16, prop, sDisplay, 64);

		int type = (sInfo[0] == '!')? 1:2;
		ReplaceString(sInfo, 16, "!", "");
		ReplaceString(sInfo, 16, "@", "");

		if(type == 1)
		{
			Format(sDisplay, 64, "[%s] %s", ((gI_HUDSettings[param1] & StringToInt(sInfo)) > 0)? "＋":"－", sDisplay);
		}

		else
		{
			Format(sDisplay, 64, "[%s] %s", ((gI_HUD2Settings[param1] & StringToInt(sInfo)) == 0)? "＋":"－", sDisplay);
		}

		return RedrawMenuItem(sDisplay);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

public void OnGameFrame()
{
	if((GetGameTickCount() % gCV_TicksPerUpdate.IntValue) == 0)
	{
		Cron();
	}
}

void Cron()
{
	if(++gI_Cycle >= 65535)
	{
		gI_Cycle = 0;
	}


	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsValidClient(i) || IsFakeClient(i) || (gI_HUDSettings[i] & HUD_MASTER) == 0)
		{
			continue;
		}

		TriggerHUDUpdate(i);
	}
}

void TriggerHUDUpdate(int client, bool keysonly = false) // keysonly because CS:S lags when you send too many usermessages
{
	if(!keysonly)
	{
		UpdateMainHUD(client);
		SetEntProp(client, Prop_Data, "m_bDrawViewmodel", ((gI_HUDSettings[client] & HUD_HIDEWEAPON) > 0)? 0:1);
		UpdateTopLeftHUD(client, true);
	}

	if(!keysonly)
	{
		UpdateKeyHint(client);
	}

	UpdateCenterKeys(client);
}

void AddHUDLine(char[] buffer, int maxlen, const char[] line, int lines)
{
	if(lines > 0)
	{
		Format(buffer, maxlen, "%s\n%s", buffer, line);
	}
	else
	{
		StrCat(buffer, maxlen, line);
	}
}


int AddHUDToBuffer(int client, huddata_t data, char[] buffer, int maxlen)
{
	int iLines = 0;
	char sLine[128];

	if(data.bReplay)
	{
		if(data.iProp != -1 && PropTricks_GetReplayStatus() != Replay_Idle && data.fTime <= data.fWR && PropTricks_IsReplayDataLoaded(data.iProp, data.iTrack))
		{
			char sTrack[32];

			if((gI_HUD2Settings[client] & HUD2_TRACK) == 0)
			{
				GetTrackName(client, data.iTrack, sTrack, 32);
				Format(sTrack, 32, "(%s) ", sTrack);
			}

			if((gI_HUD2Settings[client] & HUD2_PROP) == 0)
			{
				FormatEx(sLine, 128, "%s %s%T", gS_PropStrings[data.iProp].sPropName, sTrack, "ReplayText", client);
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}

			char sPlayerName[MAX_NAME_LENGTH];
			PropTricks_GetReplayName(data.iProp, data.iTrack, sPlayerName, MAX_NAME_LENGTH);
			AddHUDLine(buffer, maxlen, sPlayerName, iLines);
			iLines++;

			if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
			{
				char sTime[32];
				FormatSeconds(data.fTime, sTime, 32, false);

				char sWR[32];
				FormatSeconds(data.fWR, sWR, 32, false);

				FormatEx(sLine, 128, "%s / %s\n(%.1f％)", sTime, sWR, ((data.fTime < 0.0 ? 0.0 : data.fTime / data.fWR) * 100));
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}
			
			bool bSpeed = (gI_HUD2Settings[client] & HUD2_SPEED) == 0;
			bool bPropSpeed = (gI_HUD2Settings[client] & HUD2_PROPSPEED) == 0;
			if(bSpeed || bPropSpeed)
			{
				if(bSpeed)
				{
					FormatEx(sLine, 128, "%d", data.iSpeed);
				}

				if(bSpeed && bPropSpeed)
				{
					StrCat(sLine, 128, " |");
				}

				if(bPropSpeed)
				{
					Format(sLine, 128, "%s %d", sLine, data.iPropSpeed);
				}
				AddHUDLine(buffer, maxlen, sLine, iLines);
				iLines++;
			}
		}

		else
		{
			FormatEx(sLine, 128, "%T", "NoReplayData", client);
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		return iLines;
	}

	if((gI_HUDSettings[client] & HUD_ZONEHUD) > 0 && data.iZoneHUD != ZoneHUD_None)
	{
		if(gB_Rankings && (gI_HUD2Settings[client] & HUD2_MAPTIER) == 0)
		{
			FormatEx(sLine, 128, "%T", "HudZoneTier", client, PropTricks_GetMapTier(gS_Map));
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}

		if(data.iZoneHUD == ZoneHUD_Start)
		{
			FormatEx(sLine, 128, "%T ", "HudInStartZone", client, data.iSpeed, data.iPropSpeed);
		}

		else
		{
			FormatEx(sLine, 128, "%T ", "HudInEndZone", client, data.iSpeed, data.iPropSpeed);
		}

		AddHUDLine(buffer, maxlen, sLine, iLines);

		return ++iLines;
	}

	if(data.iTimerStatus != Timer_Stopped)
	{
		if((gI_HUD2Settings[client] & HUD2_PROP) == 0)
		{
			AddHUDLine(buffer, maxlen, gS_PropStrings[data.iProp].sPropName, iLines);
			iLines++;
		}

		if((gI_HUD2Settings[client] & HUD2_TIME) == 0)
		{
			char sTime[32];
			FormatSeconds(data.fTime, sTime, 32, false);

			char sTimeDiff[32];
			
			if(gB_Replay && gCV_EnableDynamicTimeDifference.BoolValue && PropTricks_GetReplayFrameCount(data.iProp, data.iTrack) != 0 && (gI_HUD2Settings[client] & HUD2_TIMEDIFFERENCE) == 0)
			{
				float fClosestReplayTime = PropTricks_GetClosestReplayTime(data.iTarget, data.iProp, data.iTrack);

				if(fClosestReplayTime != -1.0)
				{
					float fDifference = data.fTime - fClosestReplayTime;
					FormatSeconds(fDifference, sTimeDiff, 32, false);
					Format(sTimeDiff, 32, " (%s%s)", (fDifference >= 0.0)? "+":"", sTimeDiff);
				}
			}

			if((gI_HUD2Settings[client] & HUD2_RANK) == 0)
			{
				FormatEx(sLine, 128, "%T: %s%s (%d)", "HudTimeText", client, sTime, sTimeDiff, data.iRank);
			}

			else
			{
				FormatEx(sLine, 128, "%T: %s%s", "HudTimeText", client, sTime, sTimeDiff);
			}
			
			AddHUDLine(buffer, maxlen, sLine, iLines);
			iLines++;
		}
	}

	bool bSpeed = (gI_HUD2Settings[client] & HUD2_SPEED) == 0;
	bool bPropSpeed = (gI_HUD2Settings[client] & HUD2_PROPSPEED) == 0;
	if(bSpeed || bPropSpeed)
	{
		// timer: Speed: %d
		// no timer: straight up number
		if(data.iTimerStatus != Timer_Stopped)
		{
			FormatEx(sLine, 128, "%T:", "HudSpeedText", client);
			if(bSpeed)
			{
				Format(sLine, 128, "%s %d", sLine, data.iSpeed);
			}

			if(bSpeed && bPropSpeed)
			{
				StrCat(sLine, 128, " |");
			}

			if(bPropSpeed)
			{
				Format(sLine, 128, "%s %d", sLine, data.iPropSpeed);
			}
		}

		else
		{
			if(bSpeed)
			{
				FormatEx(sLine, 128, "%d", data.iSpeed);
			}

			if(bSpeed && bPropSpeed)
			{
				StrCat(sLine, 128, " |");
			}

			if(bPropSpeed)
			{
				Format(sLine, 128, "%s %d", sLine, data.iPropSpeed);
			}
		}

		AddHUDLine(buffer, maxlen, sLine, iLines);
		iLines++;
	}

	if(data.iTimerStatus != Timer_Stopped && (gI_HUD2Settings[client] & HUD2_TRACK) == 0)
	{
		char sTrack[32];
		GetTrackName(client, data.iTrack, sTrack, 32);

		AddHUDLine(buffer, maxlen, sTrack, iLines);
		iLines++;
	}

	return iLines;
}

void UpdateMainHUD(int client)
{
	int target = GetSpectatorTarget(client);

	if((gI_HUDSettings[client] & HUD_CENTER) == 0 || ((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target))
	{
		return;
	}

	float fSpeed[3], vVelocity[3], vAngularVelocity[3];
	GetEntPropVector(target, Prop_Data, "m_vecVelocity", fSpeed);
	int entity = IsFakeClient(target) ? PropTricks_GetReplayPropIndex() : PropTricks_GetPropEntityIndex(target);
	if(IsValidEdict(entity))
	{
		Phys_GetVelocity(entity, vVelocity, vAngularVelocity);
	}

	float fSpeedHUD = ((gI_HUDSettings[client] & HUD_2DVEL) == 0)? GetVectorLength(fSpeed):(SquareRoot(Pow(fSpeed[0], 2.0) + Pow(fSpeed[1], 2.0)));
	float fPropSpeedHUD = ((gI_HUDSettings[client] & HUD_2DVEL) == 0)? GetVectorLength(vVelocity):(SquareRoot(Pow(vVelocity[0], 2.0) + Pow(vVelocity[1], 2.0)));
	bool bReplay = (gB_Replay && IsFakeClient(target));
	ZoneHUD iZoneHUD = ZoneHUD_None;
	int iReplayProp = 0;
	int iReplayTrack = 0;
	float fReplayTime = 0.0;
	float fReplayLength = 0.0;

	if(!bReplay)
	{
		if(PropTricks_InsideZone(target, Zone_Start, -1))
		{
			iZoneHUD = ZoneHUD_Start;
		}
		
		else if(PropTricks_InsideZone(target, Zone_End, -1))
		{
			iZoneHUD = ZoneHUD_End;
		}
	}

	else
	{
		iReplayProp = PropTricks_GetReplayBotProp(target);
		iReplayTrack = PropTricks_GetReplayBotTrack(target);

		if(iReplayProp != -1)
		{
			fReplayTime = PropTricks_GetReplayTime(iReplayProp, iReplayTrack);
			fReplayLength = PropTricks_GetReplayLength(iReplayProp, iReplayTrack);
		}
	}

	huddata_t huddata;
	huddata.iTarget = target;
	huddata.iSpeed = RoundToNearest(fSpeedHUD);
	huddata.iPropSpeed = RoundToNearest(fPropSpeedHUD);
	huddata.iZoneHUD = iZoneHUD;
	huddata.iProp = (bReplay)? iReplayProp:PropTricks_GetClientProp(target);
	huddata.iTrack = (bReplay)? iReplayTrack:PropTricks_GetClientTrack(target);
	huddata.fTime = (bReplay)? fReplayTime:PropTricks_GetClientTime(target);
	huddata.iRank = (bReplay)? 0:PropTricks_GetRankForTime(huddata.iProp, huddata.fTime, huddata.iTrack);
	huddata.fPB = (bReplay)? 0.0:PropTricks_GetClientPB(target, huddata.iProp, huddata.iTrack);
	huddata.fWR = (bReplay)? fReplayLength:PropTricks_GetWorldRecord(huddata.iProp, huddata.iTrack);
	huddata.iTimerStatus = (bReplay)? Timer_Running:PropTricks_GetTimerStatus(target);
	huddata.bReplay = bReplay;

	char sBuffer[512];

	if(AddHUDToBuffer(client, huddata, sBuffer, 512) > 0)
	{
		PrintHintText(client, "%s", sBuffer);
	}
}

void UpdateCenterKeys(int client)
{
	if((gI_HUDSettings[client] & HUD_KEYOVERLAY) == 0)
	{
		return;
	}

	int target = GetSpectatorTarget(client);

	if(((gI_HUDSettings[client] & HUD_OBSERVE) == 0 && client != target) || !IsValidClient(target) || IsClientObserver(target))
	{
		return;
	}

	int buttons = gI_Buttons[target];

	char sCenterText[64];
	FormatEx(sCenterText, 64, "　%s　　%s\n　　 %s\n%s　 %s 　%s\n　%s　　%s",
		(buttons & IN_JUMP) > 0? "Ｊ":"ｰ", (buttons & IN_DUCK) > 0? "Ｃ":"ｰ",
		(buttons & IN_FORWARD) > 0? "Ｗ":"ｰ", (buttons & IN_MOVELEFT) > 0? "Ａ":"ｰ",
		(buttons & IN_BACK) > 0? "Ｓ":"ｰ", (buttons & IN_MOVERIGHT) > 0? "Ｄ":"ｰ",
		(buttons & IN_LEFT) > 0? "Ｌ":" ", (buttons & IN_RIGHT) > 0? "Ｒ":" ");

	int prop = (IsFakeClient(target))? PropTricks_GetReplayBotProp(target):PropTricks_GetClientProp(target);

	if(!(0 <= prop < gI_Props))
	{
		prop = 0;
	}

	PrintCenterText(client, "%s", sCenterText);
}

void UpdateTopLeftHUD(int client, bool wait)
{
	if((!wait || gI_Cycle % 25 == 0) && (gI_HUDSettings[client] & HUD_TOPLEFT) > 0)
	{
		int target = GetSpectatorTarget(client);

		int track = 0;
		int prop = 0;

		if(!IsFakeClient(target))
		{
			prop = PropTricks_GetClientProp(target);
			track = PropTricks_GetClientTrack(target);
		}

		else
		{
			prop = PropTricks_GetReplayBotProp(target);
			track = PropTricks_GetReplayBotTrack(target);
		}

		if(!(0 <= prop < gI_Props) || !(0 <= track <= TRACKS_SIZE))
		{
			return;
		}

		float fWRTime = PropTricks_GetWorldRecord(prop, track);

		if(fWRTime != 0.0)
		{
			char sWRTime[16];
			FormatSeconds(fWRTime, sWRTime, 16);

			char sWRName[MAX_NAME_LENGTH];
			PropTricks_GetWRName(prop, sWRName, MAX_NAME_LENGTH, track);

			char sTopLeft[128];
			FormatEx(sTopLeft, 128, "WR: %s (%s)", sWRTime, sWRName);

			float fTargetPB = PropTricks_GetClientPB(target, prop, track);
			char sTargetPB[64];
			FormatSeconds(fTargetPB, sTargetPB, 64);
			Format(sTargetPB, 64, "%T: %s", "HudBestText", client, sTargetPB);

			float fSelfPB = PropTricks_GetClientPB(client, prop, track);
			char sSelfPB[64];
			FormatSeconds(fSelfPB, sSelfPB, 64);
			Format(sSelfPB, 64, "%T: %s", "HudBestText", client, sSelfPB);

			if((gI_HUD2Settings[client] & HUD2_SPLITPB) == 0 && target != client)
			{
				if(fTargetPB != 0.0)
				{
					if((gI_HUD2Settings[client]& HUD2_TOPLEFT_RANK) == 0)
					{
						Format(sTopLeft, 128, "%s\n%s (#%d) (%N)", sTopLeft, sTargetPB, PropTricks_GetRankForTime(prop, fTargetPB, track), target);
					}
					else 
					{
						Format(sTopLeft, 128, "%s\n%s (%N)", sTopLeft, sTargetPB, target);
					}
				}

				if(fSelfPB != 0.0)
				{
					if((gI_HUD2Settings[client]& HUD2_TOPLEFT_RANK) == 0)
					{
						Format(sTopLeft, 128, "%s\n%s (#%d) (%N)", sTopLeft, sSelfPB, PropTricks_GetRankForTime(prop, fSelfPB, track), client);
					}
					else 
					{
						Format(sTopLeft, 128, "%s\n%s (%N)", sTopLeft, sSelfPB, client);
					}
				}
			}

			else if(fSelfPB != 0.0)
			{
				Format(sTopLeft, 128, "%s\n%s (#%d)", sTopLeft, sSelfPB, PropTricks_GetRankForTime(prop, fSelfPB, track));
			}

			Action result = Plugin_Continue;
			Call_StartForward(gH_Forwards_OnTopLeftHUD);
			Call_PushCell(client);
			Call_PushCell(target);
			Call_PushStringEx(sTopLeft, 128, SM_PARAM_STRING_COPY, SM_PARAM_COPYBACK);
			Call_PushCell(128);
			Call_Finish(result);
			
			if(result != Plugin_Continue && result != Plugin_Changed)
			{
				return;
			}

			SetHudTextParams(0.01, 0.01, 2.5, 255, 255, 255, 255, 0, 0.0, 0.0, 0.0);
			ShowSyncHudText(client, gH_HUD, "%s", sTopLeft);
		}
	}
}

void UpdateKeyHint(int client)
{
	if((gI_Cycle % 10) == 0 && ((gI_HUDSettings[client] & HUD_TIMELEFT) > 0 || (gI_HUDSettings[client] & HUD_OBSERVE) > 0))
	{
		char sMessage[256];
		int iTimeLeft = -1;

		if((gI_HUDSettings[client] & HUD_TIMELEFT) > 0 && GetMapTimeLeft(iTimeLeft) && iTimeLeft > 0)
		{
			FormatEx(sMessage, 256, (iTimeLeft > 60)? "%T: %d minutes":"%T: <1 minute", "HudTimeLeft", client, (iTimeLeft / 60), "HudTimeLeft", client);
		}

		int target = GetSpectatorTarget(client);

		if(IsValidClient(target) && (target == client || (gI_HUDSettings[client] & HUD_OBSERVE) > 0))
		{
			if((gI_HUDSettings[client] & HUD_SPECTATORS) > 0)
			{
				int[] iSpectatorClients = new int[MaxClients];
				int iSpectators = 0;
				bool bIsAdmin = CheckCommandAccess(client, "admin_speclisthide", ADMFLAG_KICK);

				for(int i = 1; i <= MaxClients; i++)
				{
					if(i == client || !IsValidClient(i) || IsFakeClient(i) || !IsClientObserver(i) || GetClientTeam(i) < 1 || GetSpectatorTarget(i) != target)
					{
						continue;
					}

					if((gCV_SpectatorList.IntValue == 1 && !bIsAdmin && CheckCommandAccess(i, "admin_speclisthide", ADMFLAG_KICK)) ||
						(gCV_SpectatorList.IntValue == 2 && !CanUserTarget(client, i)))
					{
						continue;
					}

					iSpectatorClients[iSpectators++] = i;
				}

				if(iSpectators > 0)
				{
					Format(sMessage, 256, "%s%s%spectators (%d):", sMessage, (strlen(sMessage) > 0)? "\n\n":"", (client == target)? "S":"Other S", iSpectators);
					char sName[MAX_NAME_LENGTH];
					
					for(int i = 0; i < iSpectators; i++)
					{
						if(i == 7)
						{
							Format(sMessage, 256, "%s\n...", sMessage);

							break;
						}

						GetClientName(iSpectatorClients[i], sName, sizeof(sName));
						ReplaceString(sName, sizeof(sName), "#", "?");
						TrimPlayerName(sName, sName, sizeof(sName));
						Format(sMessage, 256, "%s\n%s", sMessage, sName);
					}
				}
			}
		}

		if(strlen(sMessage) > 0)
		{
			Handle hKeyHintText = StartMessageOne("KeyHintText", client);
			BfWriteByte(hKeyHintText, 1);
			BfWriteString(hKeyHintText, sMessage);
			EndMessage();
		}
	}
}

public int PanelHandler_Nothing(Menu m, MenuAction action, int param1, int param2)
{
	// i don't need anything here
	return 0;
}

public void PropTricks_OnPropChanged(int client, int oldprop, int newprop, int track, bool manual)
{
	if(IsClientInGame(client))
	{
		UpdateTopLeftHUD(client, false);
	}
}

public int Native_ForceHUDUpdate(Handle handler, int numParams)
{
	int[] clients = new int[MaxClients];
	int count = 0;

	int client = GetNativeCell(1);

	if(client < 0 || client > MaxClients || !IsClientInGame(client))
	{
		ThrowNativeError(200, "Invalid client index %d", client);

		return -1;
	}

	clients[count++] = client;

	if(view_as<bool>(GetNativeCell(2)))
	{
		for(int i = 1; i <= MaxClients; i++)
		{
			if(i == client || !IsValidClient(i) || GetSpectatorTarget(i) != client)
			{
				continue;
			}

			clients[count++] = client;
		}
	}

	for(int i = 0; i < count; i++)
	{
		TriggerHUDUpdate(clients[i]);
	}

	return count;
}

public int Native_GetHUDSettings(Handle handler, int numParams)
{
	int client = GetNativeCell(1);

	if(client < 0 || client > MaxClients)
	{
		ThrowNativeError(200, "Invalid client index %d", client);

		return -1;
	}

	return gI_HUDSettings[client];
}

// https://forums.alliedmods.net/showthread.php?t=216841
void TrimPlayerName(const char[] name, char[] outname, int len)
{
	int count, finallen;
	for(int i = 0; name[i]; i++)
	{
		count += ((name[i] & 0xc0) != 0x80) ? 1 : 0;
		
		if(count <= gCV_SpecNameSymbolLength.IntValue)
		{
			outname[i] = name[i];
			finallen = i;
		}
	}
	
	outname[finallen + 1] = '\0';
	
	if(count > gCV_SpecNameSymbolLength.IntValue)
		Format(outname, len, "%s...", outname);
}