local addonName, addonTable = ...

--frames
local eventFrame = CreateFrame("frame", addonName.."eventFrame", UIParent)

--constants
local TTH_WHISPER = 3
local TTH_GROUP = 3
local TTH_GUILD = 3
local TTH_SYSTEM = 1

local PSH_WHISPER = true
local PSH_GROUP = true
local PSH_GUILD = false
local PSH_SYSTEM = false


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
local CHAT_EVENTS = {
	--whispers
	["CHAT_MSG_BN_WHISPER"] = {TTH_WHISPER, PSH_WHISPER, "whisper"},
	["CHAT_MSG_WHISPER"] = {TTH_WHISPER, PSH_WHISPER, "whisper"},

	--group
	--automatically populated through GROUP_EVENTS

	--guild
	--automatically populated through GUILD_EVENTS

	--system
	["CHAT_MSG_WHISPER_INFORM"] = {TTH_SYSTEM, PSH_SYSTEM, "system"},
	["CHAT_MSG_BN_WHISPER_INFORM"] = {TTH_SYSTEM, PSH_SYSTEM, "system"},
	["CHAT_MSG_IGNORED"] = {TTH_SYSTEM, PSH_SYSTEM, "system"},
	--["CHAT_MSG_SYSTEM"] = {TTH_SYSTEM, PSH_SYSTEM, "system"},

}
for event, eventTable in pairs(GROUP_EVENTS) do
	CHAT_EVENTS[event] = {TTH_GROUP, PSH_GROUP, "group"}
end
for event, eventTable in pairs(GUILD_EVENTS) do
	CHAT_EVENTS[event] = {TTH_GUILD, PSH_GUILD, "guild"}
end

local FILTERS = {
	["name mention"] = function(state, eventTable, event, text, ...)
		local names = {
			UnitName("player"):lower(),
			"stagger",
			"tank",
			"imogen",
			"immy"
		}
		for i, name in pairs(names) do
			if text:lower():find(name) then
				return 0, true
			end
		end
	end,
	["combat group filter"] = function(state, eventTable, event, ...)
		if GUILD_EVENTS[event] and InCombatLockdown() and IsInInstance() and not push then
			return 0, false, true
		end
	end,
	["online/offline/away message"] = function(state, eventTable, event, text, ...)
		if event == "CHAT_MSG_SYSTEM" and (text:find("has come online") or text:find("has gone offline")) or text:find("Away") then
			return 0, false, true
		end
	end,
	["private mode"] = function(state, eventTable, event, text, ...)
		if state.private and eventTable[3] == "guild" then
			return 0, false, true
		end
	end,
	["instance combat filter"] = function(state, eventTable, event, text, ...)
		return 0, false
	end
}

local STATES = {
	["default"] = {
		name = "default",
		chat = false,
		buff = false,
		map = false,
		quest = false,
		private = false
	},
	["dungeon"] = {
		name = "dungeon",
		chat = false,
		buff = true,
		map = true,
		quest = false,
		private = false
	},
	["questing"] = {
		name = "questing",
		chat = false,
		buff = false,
		map = true,
		quest = true,
		private = false
	}
}

STATE_EVENTS = {
	["PLAYER_ENTERING_WORLD"] = true,
	["QUEST_WATCH_LIST_CHANGED"] = true
}

--locals
UIHideTooltipIsActive = true
UIHideHideBonusRolls = true
local detailsShown = true
local state = {}
local isManual = {
	chat = true,
	buff = true,
	map = true,
	quest = true
}
local isShown = {
	chat = true,
	buff = true,
	map = true,
	quest = true
}
local chatHideTime = nil
local disableManualChatHide = false
local UIHideBonusRollFrameHidden = false


--functions
local function setState(targetState)
	for k, v in pairs(STATES[targetState]) do
		state[k] = v
	end
end

local function showChat(show)
	isShown.chat = show
	if show then
		SELECTED_CHAT_FRAME:Show(true)
		GeneralDockManager:Show(true)
	else
		SELECTED_CHAT_FRAME:Hide()
		GeneralDockManager:Hide()
	end
end

local function updateAll()
	if isManual.buff or state.buff then
		isShown.buff = true
		BuffFrame:Show()
	else
		isShown.buff = false
		BuffFrame:Hide()
	end

	if isManual.map or state.map then
		isShown.map = true
		MinimapCluster:Show()
	else
		isShown.map = false
		MinimapCluster:Hide()
	end

	if isManual.quest or state.quest then
		isShown.quest = true
		ObjectiveTrackerFrame:Show()
	else
		isShown.quest = false
		ObjectiveTrackerFrame:Hide()
	end
end

local function updateState()
	local instanceType, instanceDiff = select(2, GetInstanceInfo())
	if instanceType ~= "none" then
		setState("dungeon")
	elseif GetNumQuestWatches() > 0 or GetNumWorldQuestWatches() > 0 or (WorldQuestTrackerQuestsHeader and WorldQuestTrackerQuestsHeader:IsShown()) then
		setState("questing")
	else
		setState("default")
	end
	updateAll()
end

function UIHideToggleManualMode(chat, map, quest, buff)
	if chat then
		if isManual.chat then
			isManual.chat = false
			showChat(false)
		else
			if isShown.chat then
				chatHideTime = nil
				showChat(false)
			else
				if not disableManualChatHide then
					isManual.chat = true
					showChat(true)
				end
			end
		end
	end
	if map then
		isManual.map = not isManual.map
	end
	if quest then
		isManual.quest = not isManual.quest
	end
	if buff then
		isManual.buff = not isManual.buff
	end

	updateAll()
end

function UIHideTogglePrivateMode()
	state.private = not state.private
	print("priave mode: "..(state.priave and "enabled" or "disabled"))
end

function UIHideToggleDetails()
	if detailsShown then
		DetailsBaseFrame1:Hide()
		DetailsRowFrame1:Hide()
	else
		DetailsBaseFrame1:Show()
		DetailsRowFrame1:Show()
	end
	detailsShown = not detailsShown
end

function UIHideToggleTooltip()
	UIHideTooltipIsActive = not UIHideTooltipIsActive
	if not UIHideTooltipIsActive then
		GameTooltip:Hide()
	end
end

--main
--ensures state is always populated
setState("default")

--loads "required" addons
local loaded, reason = LoadAddOn("Chatter")
if not loaded then
	print("Chatter not loaded, reason: ", reason)
end
loaded, reason = LoadAddOn("WorldQuestTracker")
if not loaded then
	print("WQT not loaded, reason: ", reason)
end

--modifies the chat frames so they can be fully controlled by this addon
local function newShowChat(self, force)
	if isManual.chat or force then
		self:ShowOld()
	end
end
for i = 1, NUM_CHAT_WINDOWS, 1 do
	if _G["ChatFrame"..i] then
		local curr = _G["ChatFrame"..i]
		curr.ShowOld = curr.Show
		curr.Show = newShowChat
		_G["ChatFrame"..i.."Tab"].noMouseAlpha = 0
	end
end
GeneralDockManager.ShowOld = GeneralDockManager.Show
GeneralDockManager.Show = newShowChat
FCF_StartAlertFlashOld = FCF_StartAlertFlash
FCF_StartAlertFlash = function() end
CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0
----------------------------------------------------------------
--Change line 228 and 231 to noMouseAlpha = 0 in
--C:\Program Files (x86)\World of Warcraft\_retail_\Interface\Addons\Chatter\Libs\LibChatAnims\LibChatAnims.lua
----------------------------------------------------------------
--aassssssssssssssssssss
--[[ChatFrame1Tab.SetAlphaOld = ChatFrame1Tab.SetAlpha
ChatFrame1Tab.SetAlpha = function(self, ...)
	print(self:GetName(), ...)
	if ... == 0.4 then
		aagfsdd[1] = 1
	end
	self:SetAlphaOld(...)
end]]


--chat frame automation
for event, eventTable in pairs(CHAT_EVENTS) do
	eventFrame:RegisterEvent(event)
end
eventFrame:HookScript("OnEvent", function(self, event, ...)
	if not CHAT_EVENTS[event] or isManual.chat then
		return
	end

	local tth, push = unpack(CHAT_EVENTS[event])

	--applies all filter functions
	for desc, filter in pairs(FILTERS) do
		local tthExtra, pushExtra, skip = filter(state, CHAT_EVENTS[event], event, ...)
		if skip then
			return
		end
		tth, push = tth + (tthExtra or 0), push or pushExtra
	end

	--makes the Windows WoW icon blink
	if push then
		FlashClientIcon()
	end

	--creates callback to hide chat again
	chatHideTime = GetTime() + tth
	C_Timer.After(tth, function()
		if chatHideTime and chatHideTime <= GetTime() + 0.5 then
			showChat(false)
			disableManualChatHide = true
			C_Timer.After(0.5, function()
				disableManualChatHide = false
			end)
		end
	end)

	--actually shows chat
	showChat(true)
end)

--minimap, buff and quest frame automations
for event, _ in pairs(STATE_EVENTS) do
	eventFrame:RegisterEvent(event)
end
eventFrame:HookScript("OnEvent", function(self, event, ...)
	if STATE_EVENTS[event] then
		updateState()
	end
end)

if WorldQuestTrackerQuestsHeader then
	WorldQuestTrackerQuestsHeader:HookScript("OnShow", updateState)
	WorldQuestTrackerQuestsHeader:HookScript("OnHide", updateState)
end

--initialization stuff
UIHideToggleDetails()
updateState()
UIHideToggleManualMode(true, true, true, true)

--MBB updates once every 3 seconds while it's shown, this makes it update ASAP after it's shown
if MBB_OnUpdate then
	MBB_OnUpdate(2.99999)
end

--Debugging vars
UIH = {}
UIH.state = state
UIH.isManual = isManual
UIH.isShown = isShown


--OTHER STUFF

--Tooltip
GameTooltip:HookScript("OnShow", function(self)
	if not UIHideTooltipIsActive or (not InCombatLockdown() and IsShiftKeyDown()) or select(2, self:GetPoint()) ~= TooltipMover then
	else
		self:Hide()
	end
end)
eventFrame:RegisterEvent("MODIFIER_STATE_CHANGED")
eventFrame:HookScript("OnEvent", function(self, event, ...)
	if event == "MODIFIER_STATE_CHANGED" and (... == "LSHIFT" or ... == "RSHIFT") then
		if select(2, ...) == 1 then
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end
end)

--Ban Lu voicelines
MuteSoundFile(1593212)
MuteSoundFile(1593213)
MuteSoundFile(1593236)
for i = 1593216, 1593229, 1 do
	MuteSoundFile(i)
end

--BonusRoll
BonusRollFrame:HookScript("OnShow", function(self, event, ...)
	if UIHideHideBonusRolls then
		UIHideBonusRollFrameHidden = true
		self:Hide()
	end
end)
function UIHideToggleBonusRoll()
	UIHideHideBonusRolls = not UIHideHideBonusRolls
	if UIHideHideBonusRolls then
		UIHideBonusRollFrameHidden = true
		BonusRollFrame:Hide()
	else
		UIHideBonusRollFrameHidden = false
		BonusRollFrame:Show()
	end
end
BonusRollFrame.IsShownOld = BonusRollFrame.IsShown
BonusRollFrame.IsShown = function(self)
	return BonusRollFrame:IsShownOld() or UIHideBonusRollFrameHidden
end
eventFrame:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT")
eventFrame:HookScript("OnEvent", function(self, event, ...)
	if event == "SPELL_CONFIRMATION_TIMEOUT" and select(2, ...) == LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL then
		UIHideBonusRollFrameHidden = false
	end
end)