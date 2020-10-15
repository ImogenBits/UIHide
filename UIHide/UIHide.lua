local ADDON_NAME, _ = ...

------------------------------------------------------------------------------------------------------------------------------------------
--Change line 228 and 231 to noMouseAlpha = 0 in
--C:\Program Files (x86)\World of Warcraft\_retail_\Interface\Addons\Chatter\Libs\LibChatAnims\LibChatAnims.lua
------------------------------------------------------------------------------------------------------------------------------------------

--constants
local EVENT_FRAME = CreateFrame("frame", ADDON_NAME.."EventFrame", UIParent)
local BUFF_FRAME_POS = {
	default = {-205, -13},
	corner = {-13, -13},
}
--helper constants for the chat events
local TTH_WHISPER = 3
local TTH_GROUP = 3
local TTH_GUILD = 3
local TTH_SYSTEM = 1
local TTH_CUSTOM = 3

local PSH_WHISPER = true
local PSH_GROUP = true
local PSH_GUILD = false
local PSH_SYSTEM = false
local PSH_CUSTOM = false

local WHISPER_EVENTS = {
	["CHAT_MSG_BN_WHISPER"] = true,
	["CHAT_MSG_WHISPER"] = true,
}
local GROUP_EVENTS = {
	["CHAT_MSG_INSTANCE_CHAT"] = true,
	["CHAT_MSG_INSTANCE_CHAT_LEADER"] = true,
	["CHAT_MSG_PARTY"] = true,
	["CHAT_MSG_PARTY_LEADER"] = true,
	["CHAT_MSG_RAID"] = true,
	["CHAT_MSG_RAID_LEADER"] = true,
	["CHAT_MSG_RAID_WARNING"] = true,
}
local GUILD_EVENTS = {
	["CHAT_MSG_COMMUNITIES_CHANNEL"] = true,
	["CHAT_MSG_GUILD"] = true,
	["CHAT_MSG_OFFICER"] = true,
	["CHAT_MSG_GUILD_ACHIEVEMENT"] = true,
	["CHAT_MSG_ACHIEVEMENT"] = true,
}
local SYSTEM_EVENTS = {
	["CHAT_MSG_WHISPER_INFORM"] = true,
	["CHAT_MSG_BN_WHISPER_INFORM"] = true,
	["CHAT_MSG_IGNORED"] = true,
	--["CHAT_MSG_SYSTEM"] = true,
}
local CUSTOM_EVENTS = {
	["CUSTOM_CHAT_MSG_DUMP"] = true,
}
local CHAT_EVENTS = {}
do	--populates CHAT_EVENTS as a union of the other chat events tables
	for event, eventTable in pairs(WHISPER_EVENTS) do
		CHAT_EVENTS[event] = {TTH_WHISPER, PSH_WHISPER}
	end
	for event, eventTable in pairs(GROUP_EVENTS) do
		CHAT_EVENTS[event] = {TTH_GROUP, PSH_GROUP}
	end
	for event, eventTable in pairs(GUILD_EVENTS) do
		CHAT_EVENTS[event] = {TTH_GUILD, PSH_GUILD}
	end
	for event, eventTable in pairs(SYSTEM_EVENTS) do
		CHAT_EVENTS[event] = {TTH_SYSTEM, PSH_SYSTEM}
	end
	for event, eventTable in pairs(CUSTOM_EVENTS) do
		CHAT_EVENTS[event] = {TTH_CUSTOM, PSH_CUSTOM}
	end
end

--Events when the mapCluster state will be updated
local MAP_CLUSTER_STATE_EVENTS = {
	["PLAYER_ENTERING_WORLD"] = true,
	["QUEST_WATCH_LIST_CHANGED"] = true
}

--Deftault state info
local MAP_CLUSTER_IF_AUTO_STATES = {
	["default"] = {
		name = "default",
		buffs = {
			showIfAuto = false,
		},
		map = {
			showIfAuto = false,
		},
		quests = {
			showIfAuto = false,
		},
	},
	["dungeon"] = {
		name = "dungeon",
		buffs = {
			showIfAuto = true,
		},
		map = {
			showIfAuto = false,
		},
		quests = {
			showIfAuto = false,
		},
	},
	["questing"] = {
		name = "questing",
		buffs = {
			showIfAuto = false,
		},
		map = {
			showIfAuto = true,
		},
		quests = {
			showIfAuto = true,
		},
	},
}
local INIT_STATE = {
	mapCluster = {
		name = "uninitialised",
		buffs = {
			isManual = false,
			showIfAuto = false,
		},
		map = {
			isManual = false,
			showIfAuto = false,
		},
		quests = {
			isManual = false,
			showIfAuto = false,
		},
	},
	chat = {
		isManual = false,
		showIfAuto = false,
		privateMode = false,
		privateModeAuto = true,
		hideTime = false,
		disableManualToggle = false,
	},
	tooltip = {
		isManual = false,
		showIfAuto = false,
	},
}

--filters that will be applied to all chat messages.  First return value will be added to tth, second will be or'ed to push and third will cause the function to return without any changes to the state or display
local FILTERS
do
	local playerNames = {
		UnitName("player"):lower(),
		"stagger",
		"imogen",
		"immy",
	}
	local systemPatterns = {
		"gains [%d,%.]+ artifact power",
		"you receive item:",
		"you are now away",
		"you are no longer away",
		"quest accepted",
		"received %d+",
		" completed.",
	}
	local combatPatterns = {
		"interrupt",
		"kick",
		"stun",
		"|Hspell:.+|h%[.-%]",
		"dispell",
	}
	FILTERS = {
		["mention"] = function(chatState, isMention, event, text, ...)
			for i, name in pairs(playerNames) do
				if text and text:lower():find(name) then
					return 0, true
				end
			end
		end,
		["guild msg in instance filter"] = function(chatState, isMention, event, ...)
			if GUILD_EVENTS[event] and not isMention and ((InCombatLockdown() and IsInInstance()) or C_ChallengeMode.IsChallengeModeActive()) then
				return 0, false, true
			end
		end,
		["private mode"] = function(chatState, isMention, event, text, ...)
			if (chatState.privateMode or chatState.privateModeAuto) and GUILD_EVENTS[event] and not isMention then
				return 0, false, true
			end
		end,
		["instance combat filter"] = function(chatState, isMention, event, text, ...)
			if GROUP_EVENTS[event] and IsInInstance() and text then
				local textLower = text:lower()
				if textLower:find("^%d+$") then
					return 0, false, true
				end
				if InCombatLockdown() then
					for i, pattern in ipairs(combatPatterns) do
						if textLower:find(pattern) then
							return 0, false, true
						end
					end
				end
			end
		end,
		["system filter"] = function(chatState, isMention, event, text,...)
			if SYSTEM_EVENTS[event] and text then
				local textLower = text:lower()
				for i, pattern in ipairs(systemPatterns) do
					if textLower:find(pattern) then
						return 0, false, true
					end
				end
			end
		end,
	}
end

--functions that update the actual displayed UI to look like the state dictates
local DISPLAY_FUNCS = {
	mapCluster = function(mapClusterState)
		if mapClusterState.map.isManual or mapClusterState.map.showIfAuto then
			MinimapCluster:Show()
			Minimap:Show()
		else
			MinimapCluster:Hide()
			Minimap:Hide()
		end
		
		if mapClusterState.buffs.isManual or mapClusterState.buffs.showIfAuto then
			BuffFrame:Show()
			BuffFrame:SetPoint("TOPRIGHT", unpack(BUFF_FRAME_POS[MinimapCluster:IsShown() and "default" or "corner"]))
		else
			BuffFrame:Hide()
		end

		if mapClusterState.quests.isManual or mapClusterState.quests.showIfAuto then
			ObjectiveTrackerFrame:Show()
		else
			ObjectiveTrackerFrame:Hide()
		end
	end,
	chat = function(chatState)
		if chatState.isManual or chatState.showIfAuto then
			SELECTED_CHAT_FRAME:ShowOld()
			GeneralDockManager:ShowOld()
		else
			SELECTED_CHAT_FRAME:Hide()
			GeneralDockManager:Hide()
		end
	end,
	tooltip = function(tooltipState)
		if not (tooltipState.isManual or tooltipState.showIfAuto) then
			GameTooltip:Hide()
		end
	end,
}

--local functions
--util
local copy
copy = function(val)
	if type(val) == "table" then
		local newTable = {}
		for k, v in pairs(val) do
			newTable[k] = copy(v)
		end
		return newTable
	else
		return val
	end
end
local merge
merge = function(data1, data2)
	if data2 == nil then
		return copy(data1)
	elseif type(data1) == "table" and type(data2) == "table" then
		local newTable = copy(data1)
		for k, v in pairs(data2) do
			newTable[k] = merge(data1[k], data2[k])
		end
		return newTable
	else
		return copy(data2)
	end
end
local function set(tbl)
	local setTbl = {}
	for k, v in pairs(tbl) do
		if type(k) == "number" then
			setTbl[v] = true
		else
			setTbl[k] = true
		end
	end
	return setTbl
end

--called from macros to effectively be keybindings
local function toggleMapCluster(mapClusterState)
	return {
		buffs = {
			isManual = not mapClusterState.buffs.isManual,
		},
		map = {
			isManual = not mapClusterState.map.isManual,
		},
		quests = {
			isManual = not mapClusterState.quests.isManual,
		}
	}
end
local function togglePrivateMode(chatState)
	print("private mode is: ", not chatState.privateMode and "on" or "off")
	return {privateMode = not chatState.privateMode}
end
local function toggleTooltip(tooltipState)
	return {isManual = not tooltipState.isManual}
end
local function toggleChat(chatState)
	if not chatState.disableManualToggle then
		if chatState.showIfAuto then
			return {showIfAuto = false, hideTime = false}
		else
			return {isManual = not chatState.isManual}
		end
	end
end

--event handlers
local function chatEventHandler(chatState, self, event, ...)
	if chatState.isManual then
		return
	end

	--applies all filter functions
	local isMention = select(2, FILTERS.mention(chatState, false, event, ...))
	local skip, tth, push = false, unpack(CHAT_EVENTS[event])

	for desc, filter in pairs(FILTERS) do
		local tthExtra, pushExtra, skipExtra = filter(chatState, isMention, event, ...)
		tth, push, skip = tth + (tthExtra or 0), push or pushExtra, skip or skipExtra
	end

	if skip then
		return
	end
	
	if push then
		FlashClientIcon()
	end

	--creates callback to hide chat again
	C_Timer.After(tth, UIHide:stateUpdateFunc(function(chatState)
		if chatState.hideTime and chatState.hideTime <= GetTime() + 0.1 then
			C_Timer.After(0.25, UIHide:stateUpdateFunc(function(chatState)
				return {disableManualToggle = false}
			end, "chat"))
			return {showIfAuto = false, hideTime = false, disableManualToggle = true}
		end
	end, "chat"))

	return {showIfAuto = true, hideTime = GetTime() + tth}
end

local function dungeonEventHandler(chatState, self, event, ...)
	return {privateModeAuto = IsInInstance() and C_ChallengeMode.IsChallengeModeActive()}
end

local function mapClusterEventHandler(mapClusterState, self, event, ...)
	local instanceType, instanceDiff = select(2, GetInstanceInfo())
	local newStateName = ""
	if instanceType ~= "none" then
		newStateName = "dungeon"
	elseif C_QuestLog.GetNumQuestWatches() > 0
		or C_QuestLog.GetNumWorldQuestWatches() > 0
		or GetNumTrackedAchievements() > 0
		or (WorldQuestTrackerQuestsHeader and WorldQuestTrackerQuestsHeader:IsShown()) then
		newStateName = "questing"
	else
		newStateName = "default"
	end
	return MAP_CLUSTER_IF_AUTO_STATES[newStateName]
end

local function tooltipEventHandler(tooltipState, self, event, ...)
	return {
		showIfAuto = (IsShiftKeyDown() and not InCombatLockdown())
					or (GameTooltip:GetOwner() ~= UIParent and not GameTooltip:GetUnit()),
	}
	--(InCombatLockdown() or not IsShiftKeyDown()) and (GameTooltip:GetOwner() == UIParent or GameTooltip:GetUnit())
end


--UIHide object
UIHide = {
	state = copy(INIT_STATE),
	eventFrame = EVENT_FRAME,

	stateFunc = function(self, func, stateKey)
		return function(...)
			return func(self.state[stateKey], ...)
		end
	end,
	stateUpdateFunc = function(self, func, stateKey)
		return function(...)
			local currState = self.state[stateKey]
			local newState = func(currState, ...)
			if newState then
				self.state[stateKey] = merge(currState, newState)
				DISPLAY_FUNCS[stateKey](self.state[stateKey])
			end
		end
	end,
	eventStateUpdateFunction = function(self, func, eventSet, stateKey)
		return self:stateUpdateFunc(function(state, self, event, ...)
			if eventSet[event] then
				return func(state, self, event, ...)
			end
		end, stateKey)
	end,
	registerEvents = function(self, handler, events, stateKey)
		local eventSet = set(events)
		for event in pairs(eventSet) do
			if not CUSTOM_EVENTS[event] then
				self.eventFrame:RegisterEvent(event)
			end
		end
		self.eventFrame:HookScript("OnEvent", self:eventStateUpdateFunction(handler, eventSet, stateKey))
	end,
}
UIHide.toggleMapCluster = UIHide:stateUpdateFunc(toggleMapCluster, "mapCluster")
UIHide.togglePrivateMode = UIHide:stateUpdateFunc(togglePrivateMode, "chat")
UIHide.toggleTooltip = UIHide:stateUpdateFunc(toggleTooltip, "tooltip")
UIHide.toggleChat = UIHide:stateUpdateFunc(toggleChat, "chat")

--main

--modifies the chat frames so other stuff doesn't mess with them
local function ShowNew(chatState, self)
	if chatState.isManual or chatState.showIfAuto then
		self:ShowOld()
	end
end
for i = 1, NUM_CHAT_WINDOWS, 1 do
	if _G["ChatFrame"..i] then
		local curr = _G["ChatFrame"..i]
		curr.ShowOld = curr.Show
		curr.Show = UIHide:stateFunc(ShowNew, "chat")
		_G["ChatFrame"..i.."Tab"].noMouseAlpha = 0
	end
end
GeneralDockManager.ShowOld = GeneralDockManager.Show
GeneralDockManager.Show = UIHide.stateFunc(ShowNew, "chat")
FCF_StartAlertFlashOld = FCF_StartAlertFlash
FCF_StartAlertFlash = function() end
CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0

--chat frame automation
UIHide:registerEvents(chatEventHandler, CHAT_EVENTS, "chat")

--enables private mode while in dungeons
UIHide:registerEvents(dungeonEventHandler, {"PLAYER_ENTERING_WORLD", "CHALLENGE_MODE_START", "CHALLENGE_MODE_COMPLETED"}, "chat")

--minimap, buff and quest frame automations
UIHide:registerEvents(mapClusterEventHandler, MAP_CLUSTER_STATE_EVENTS, "mapCluster")

if WorldQuestTrackerQuestsHeader then
	WorldQuestTrackerQuestsHeader:HookScript("OnShow", UIHide:stateUpdateFunc(mapClusterEventHandler, "mapCluster"))
	WorldQuestTrackerQuestsHeader:HookScript("OnHide", UIHide:stateUpdateFunc(mapClusterEventHandler, "mapCluster"))
end

--tooltip 
GameTooltip:HookScript("OnShow", UIHide:stateUpdateFunc(tooltipEventHandler, "tooltip"))
UIHide:registerEvents(tooltipEventHandler, {"MODIFIER_STATE_CHANGED"}, "tooltip")

------------------------------------------------------------------------------------------------------------------------------------------
--initialization stuff

UIHide:stateUpdateFunc(mapClusterEventHandler, "mapCluster")()
UIHide:stateUpdateFunc(function() return {} end, "chat")()
------------------------------------------------------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------------------------------------------------------
--* OTHER STUFF

--* Ban Lu voicelines
do
	MuteSoundFile(1593212)
	MuteSoundFile(1593213)
	MuteSoundFile(1593236)
	for i = 1593216, 1593229, 1 do
		MuteSoundFile(i)
	end
end

--* MBB updates once every 3 seconds while it's shown, this makes it update ASAP after it's shown
do
	if MBB_OnUpdate then
		MBB_OnUpdate(2.99999)
		if IsAddOnLoaded("SexyMap") then
			MBB_SetButtonPosition = function() end
		end
	end
end

--* Completing World Quests wont show alert
do
	WorldQuestCompleteAlertSystem.alwaysReplace = false
	WorldQuestCompleteAlertSystem.maxAlerts = 0
end

--* Moves dungeon progress frame out of the way of debuffs
do
	EVENT_FRAME:RegisterEvent("UNIT_AURA")
	EVENT_FRAME:HookScript("OnEvent", function(self, event, ...)
		if event == "UNIT_AURA" then
			local mapXPos = select(2, MinimapCluster:GetSize())
			if BuffFrame:IsShown() and BuffFrame.bottomEdgeExtent > mapXPos + 20 then
				ObjectiveTrackerFrame:SetPoint("TOPRIGHT", MinimapCluster, "BOTTOMRIGHT", -12, -(BuffFrame.bottomEdgeExtent - mapXPos + 5))
			end
		end
	end)
end

--* Opens the Talent pane when you open the spec frame
do
	EVENT_FRAME:RegisterEvent("ADDON_LOADED")
	EVENT_FRAME:HookScript("OnEvent", function(self, event, ...)
		if event == "ADDON_LOADED" and ... == "Blizzard_TalentUI" then
			PlayerTalentFrame:HookScript("OnShow", function(self)
				PlayerTalentFrame_Open()
			end)
		end
	end)
end

--* /dump shows chat
do
	LoadAddOn("Blizzard_DebugTools")
	hooksecurefunc("DevTools_DumpCommand", UIHide:stateUpdateFunc(function(chatState, msg, Editbox)
		return chatEventHandler(chatState, Editbox, "CUSTOM_CHAT_MSG_DUMP", "")
	end, "chat"))
end