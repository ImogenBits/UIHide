local ADDON_NAME, _ = ...



------------------------------------------------------------------------------------------------------------------------------------------
--Change line 228 and 231 to noMouseAlpha = 0 in
--C:\Program Files (x86)\World of Warcraft\_retail_\Interface\Addons\Chatter\Libs\LibChatAnims\LibChatAnims.lua
------------------------------------------------------------------------------------------------------------------------------------------

--constants
local LOAD_ADDONS = {
	"Chatter",
	"WorldQuestTracker",
	"Details",
	"MBB",
}
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

local PSH_WHISPER = true
local PSH_GROUP = true
local PSH_GUILD = false
local PSH_SYSTEM = false

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
	["CHAT_MSG_SYSTEM"] = true,
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
	},
	bonusRoll = {
		isManual = false,
		isHidden = false,
	},
}

--filters that will be applied to all chat messages.  First return value will be added to tth, second will be or'ed to push and third will cause the function to return without any changes to the state or display
local FILTERS 
FILTERS = {
	["mention"] = function(chatState, isMention, event, text, ...)
		local names = {
			UnitName("player"):lower(),
			"stagger",
			"imogen",
			"immy"
		}
		for i, name in pairs(names) do
			if text:lower():find(name) then
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
		if GROUP_EVENTS[event] and IsInInstance() then
			local textLower = text:lower()
			if textLower:find("^%d+$") then
				return 0, false, true
			end
			if InCombatLockdown() then
				local patterns = {
					"interrupt",
					"kick",
					"stun",
					"|Hspell:.+|h%[.-%]",
				}
				for i, pattern in ipairs(patterns) do
					if textLower:find(pattern) then
						return 0, false, true
					end
				end
			end
		end
	end
}

--functions that update the actual displayed UI to look like the state dictates
local DISPLAY_FUNCS = {
	mapCluster = function(mapClusterState)
		if mapClusterState.map.isManual or mapClusterState.map.showIfAuto then
			MinimapCluster:Show()
		else
			MinimapCluster:Hide()
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
		if not tooltipState.isManual and (InCombatLockdown() or not IsShiftKeyDown()) and (GameTooltip:GetOwner() == UIParent or GameTooltip:GetUnit()) then
			GameTooltip:Hide()
		end
	end,
	bonusRoll = function(bonusRollState)
		if bonusRollState.isManual then
			BonusRollFrame:Show()
		else
			BonusRollFrame:Hide()
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

--called from macros to be quasi keybindings
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
local function toggleBonusRoll(bonusRollState)
	return {isManual = not bonusRollState.isManual}
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
	--ignores events that aren't related to this event handler
	if not CHAT_EVENTS[event] or chatState.isManual then
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
	C_Timer.After(tth, UIHide.getStateUpdateFunc(function(chatState)
		if chatState.hideTime and chatState.hideTime <= GetTime() + 0.1 then
			C_Timer.After(0.25, UIHide.getStateUpdateFunc(function(chatState)
				return {disableManualToggle = false}
			end, "chat"))
			return {showIfAuto = false, hideTime = false, disableManualToggle = true}
		end
	end, "chat"))

	return {showIfAuto = true, hideTime = GetTime() + tth}
end

--api calls
local function getCurrMapClusterIfAutoState()
	local instanceType, instanceDiff = select(2, GetInstanceInfo())
	local newStateName = ""
	if instanceType ~= "none" then
		newStateName = "dungeon"
	elseif GetNumQuestWatches() > 0
		or GetNumWorldQuestWatches() > 0
		or GetNumTrackedAchievements() > 0
		or (WorldQuestTrackerQuestsHeader and WorldQuestTrackerQuestsHeader:IsShown()) then
		newStateName = "questing"
	else
		newStateName = "default"
	end
	return MAP_CLUSTER_IF_AUTO_STATES[newStateName]
end


--UIHide object, only thing with access to gameState info
do
	local gameState = copy(INIT_STATE) --Aasdasdagas

	local function getStateUpdateFunc(func, stateKey)
		return function(...)
			local currState = gameState[stateKey]
			local newState = func(currState, ...)
			if newState then
				gameState[stateKey] = merge(currState, newState)
				DISPLAY_FUNCS[stateKey](gameState[stateKey])
			end
		end
	end
	local function getStateFunc(func, stateKey)
		return function(...)
			return func(gameState[stateKey], ...)
		end
	end

	UIHide = {
		--called from macros to be essentially keybindings
		toggleMapCluster = getStateUpdateFunc(toggleMapCluster, "mapCluster"),
		togglePrivateMode = getStateUpdateFunc(togglePrivateMode, "chat"),
		toggleTooltip = getStateUpdateFunc(toggleTooltip, "tooltip"),
		toggleChat = getStateUpdateFunc(toggleChat, "chat"),
		toggleBonusRoll = getStateUpdateFunc(toggleBonusRoll, "bonusRoll"),

		getStateUpdateFunc = getStateUpdateFunc,
		getStateFunc = getStateFunc,

		gameState = gameState,	--DEBUG
		merge = merge,			--DEBUG
		toggleDetails = function()
			if not DetailsBaseFrame1 then
				return
			end
			if DetailsBaseFrame1:IsShown() then
				DetailsBaseFrame1:Hide()
				DetailsRowFrame1:Hide()
			else
				DetailsBaseFrame1:Show()
				DetailsRowFrame1:Show()
			end
		end,
	}
end


--main

--loads "required" addons
for i, loadAddonName in ipairs(LOAD_ADDONS) do
	local loaded, reason = LoadAddOn(loadAddonName)
	if not loaded then
		print(loadAddonName, " not loaded, reason: ", reason)
	end
end

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
		curr.Show = UIHide.getStateFunc(ShowNew, "chat")
		_G["ChatFrame"..i.."Tab"].noMouseAlpha = 0
	end
end
GeneralDockManager.ShowOld = GeneralDockManager.Show
GeneralDockManager.Show = UIHide.getStateFunc(ShowNew, "chat")
FCF_StartAlertFlashOld = FCF_StartAlertFlash
FCF_StartAlertFlash = function() end
CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0

--chat frame automation
for event, eventTable in pairs(CHAT_EVENTS) do
	EVENT_FRAME:RegisterEvent(event)
end
EVENT_FRAME:HookScript("OnEvent", UIHide.getStateUpdateFunc(chatEventHandler, "chat"))
--enables private mode while in dungeons
EVENT_FRAME:RegisterEvent("PLAYER_ENTERING_WORLD")
EVENT_FRAME:RegisterEvent("CHALLENGE_MODE_START")
EVENT_FRAME:RegisterEvent("CHALLENGE_MODE_COMPLETED")
EVENT_FRAME:HookScript("OnEvent", UIHide.getStateUpdateFunc(function(chatState, self, event, ...)
	if event == "PLAYER_ENTERING_WORLD" or event == "CHALLENGE_MODE_START" or event == "CHALLENGE_MODE_COMPLETED" then
		return {privateModeAuto = IsInInstance() and C_ChallengeMode.IsChallengeModeActive()}
	end
end, "chat"))

--minimap, buff and quest frame automations
for event, _ in pairs(MAP_CLUSTER_STATE_EVENTS) do
	EVENT_FRAME:RegisterEvent(event)
end
EVENT_FRAME:HookScript("OnEvent", UIHide.getStateUpdateFunc(function(mapClusterState, self, event, ...)
	if MAP_CLUSTER_STATE_EVENTS[event] then
		return getCurrMapClusterIfAutoState()
	end
end, "mapCluster"))

if WorldQuestTrackerQuestsHeader then
	WorldQuestTrackerQuestsHeader:HookScript("OnShow", UIHide.getStateUpdateFunc(function(mapClusterState)
		return getCurrMapClusterIfAutoState()
	end, "mapCluster"))
	WorldQuestTrackerQuestsHeader:HookScript("OnHide", UIHide.getStateUpdateFunc(function(mapClusterState)
		return getCurrMapClusterIfAutoState()
	end, "mapCluster"))
end

--tooltip 
GameTooltip:HookScript("OnShow", UIHide.getStateUpdateFunc(function() return {} end, "tooltip"))
EVENT_FRAME:RegisterEvent("MODIFIER_STATE_CHANGED")
EVENT_FRAME:HookScript("OnEvent", UIHide.getStateUpdateFunc(function() return {} end, "tooltip"))

--bonusRoll
BonusRollFrame:HookScript("OnShow", UIHide.getStateUpdateFunc(function(bonusRollState, self, event, ...)
	if not bonusRollState.isManual then
		return {isHidden = true}
	end
end, "bonusRoll"))
BonusRollFrame.IsShownOld = BonusRollFrame.IsShown
BonusRollFrame.IsShown = UIHide.getStateFunc(function(bonusRollState, self)
	return BonusRollFrame:IsShownOld() or bonusRollState.isHidden
end, "bonusRoll")
EVENT_FRAME:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT")
EVENT_FRAME:HookScript("OnEvent", UIHide.getStateUpdateFunc(function(bonusRollState, self, event, ...)
	if event == "SPELL_CONFIRMATION_TIMEOUT" and select(2, ...) == LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL then
		return {isHidden = false}
	end
end, "bonusRoll"))

------------------------------------------------------------------------------------------------------------------------------------------
--initialization stuff
UIHide.toggleDetails()

UIHide.getStateUpdateFunc(getCurrMapClusterIfAutoState, "mapCluster")()
UIHide.getStateUpdateFunc(function() return {} end, "chat")()
------------------------------------------------------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------------------------------------------------------
--OTHER STUFF

--Ban Lu voicelines
MuteSoundFile(1593212)
MuteSoundFile(1593213)
MuteSoundFile(1593236)
for i = 1593216, 1593229, 1 do
	MuteSoundFile(i)
end

--MBB updates once every 3 seconds while it's shown, this makes it update ASAP after it's shown
if MBB_OnUpdate then
	MBB_OnUpdate(2.99999)
end

--EJ shows +15 level rewards instead of baseline mythic
C_EncounterJournal.SetPreviewMythicPlusLevel(15)

--Completing World Quests wont show alert
WorldQuestCompleteAlertSystem.alwaysReplace = false
WorldQuestCompleteAlertSystem.maxAlerts = 0