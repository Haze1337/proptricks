void Menu_OpenProp(int client)
{
	Menu menu = new Menu(PropMenu_Handler);
	menu.SetTitle("%T", "PropMenuTitle", client);

	for(int i = 0; i < gI_Props; i++)
	{
		int iProp = gI_OrderedProps[i];
		
		if(gA_PropSettings[iProp].iEnabled == -1)
		{
			continue;
		}
		
		char sInfo[8];
		IntToString(iProp, sInfo, 8);

		char sDisplay[64];

		float time = 0.0;

		if(gB_WR)
		{
			time = PropTricks_GetWorldRecord(iProp, gA_Timers[client].iTrack);
		}

		if(time > 0.0)
		{
			char sTime[32];
			FormatSeconds(time, sTime, 32, false);

			char sWR[8];
			strcopy(sWR, 8, "WR");

			FormatEx(sDisplay, 64, "%s - %s: %s", gS_PropStrings[iProp].sPropName, sWR, sTime);
		}

		else
		{
			strcopy(sDisplay, 64, gS_PropStrings[iProp].sPropName);
		}

		menu.AddItem(sInfo, sDisplay, (gA_Timers[client].iProp == iProp)? ITEMDRAW_DISABLED:ITEMDRAW_DEFAULT);
	}

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		menu.AddItem("-1", "Nothing");
	}

	else if(menu.ItemCount <= 9)
	{
		menu.Pagination = MENU_NO_PAGINATION;
	}

	menu.ExitButton = true;
	menu.Display(client, 20);
}

public int PropMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		char info[16];
		menu.GetItem(param2, info, 16);

		int prop = StringToInt(info);

		if(prop == -1)
		{
			PropTricks_PrintToChat(param1, "%T", "NoProps", param1, gS_ChatStrings.sWarning, gS_ChatStrings.sText);
			
			return 0;
		}

		ChangeClientProp(param1, prop, true);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void Menu_OpenTrack(int client)
{
	Menu menu = new Menu(TrackMenu_Handler);
	menu.SetTitle("%T", "TrackMenuTitle", client);

	for(int iTrack = 0; iTrack < TRACKS_SIZE; iTrack++)
	{
		char sInfo[8];
		IntToString(iTrack, sInfo, 8);

		char sDisplay[64];
		GetTrackName(client, iTrack, sDisplay, sizeof(sDisplay));
		menu.AddItem(sInfo, sDisplay, (gA_Timers[client].iTrack != iTrack) ? ITEMDRAW_DEFAULT:ITEMDRAW_DISABLED);
	}

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "PropNothing", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 30);
}

public int TrackMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsValidClient(param1))
		{
			return 0;
		}

		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);

		int newtrack = StringToInt(sInfo);

		if(newtrack == -1)
		{
			return 0;
		}
		
		ChangeClientTrack(param1, newtrack, true);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}

void Menu_OpenPushButton(int client)
{
	Menu menu = new Menu(PushButtonMenu_Handler);
	menu.SetTitle("%T", "PushButtonMenuTitle", client);
	
	

	// should NEVER happen
	if(menu.ItemCount == 0)
	{
		char sMenuItem[64];
		FormatEx(sMenuItem, 64, "%T", "PropNothing", client);
		menu.AddItem("-1", sMenuItem);
	}

	menu.ExitButton = true;
	menu.Display(client, 30);
}

public int PushButtonMenu_Handler(Menu menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_Select)
	{
		if(!IsValidClient(param1))
		{
			return 0;
		}

		char sInfo[8];
		menu.GetItem(param2, sInfo, 8);
	}

	else if(action == MenuAction_End)
	{
		delete menu;
	}

	return 0;
}