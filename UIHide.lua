local ADDON_NAME, _ = ...

--constants
local LOAD_ADDONS = {
	"Chatter",
	"WorldQuestTracer",
	"Details",
}
local EVENT_FRAME = CreateFrame("frame", ADDON_NAME.."EventFrame", UIParent)

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
	--["CHAT_MSG_SYSTEM"] = true,
}
local CHAT_EVENTS = {}
--populates CHAT_EVENTS as a union of the other chat events tables
do
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

--filters that will be applied to all chat messages.  First return value will be added to tth, second will be or'ed to push and third will cause the function to return without any changes to the state or display
local FILTERS = {
	["name mention"] = function(currState, event, text, ...)
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
	["combat group filter"] = function(currState, event, ...)
		if GUILD_EVENTS[event] and InCombatLockdown() and IsInInstance() and not push then
			return 0, false, true
		end
	end,
	--[[	["online/offline/away message"] = function(currState, eventTable, event, text, ...)
		if event == "CHAT_MSG_SYSTEM" and (text:find("has come online") or text:find("has gone offline")) or text:find("Away") then
			return 0, false, true
		end
	end,]]
	["private mode"] = function(currState, event, text, ...)
		if currState.chat.privateMode and GUILD_EVENTS[event] then
			return 0, false, true
		end
	end,
	["instance combat filter"] = function(currState, event, text, ...)
		return 0, false
	end
}

local STATE_EVENTS = {
	["PLAYER_ENTERING_WORLD"] = true,
	["QUEST_WATCH_LIST_CHANGED"] = true
}

local BLANK_IS_AUTO_STATES = {
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
		chat = {
			showIfAuto = false,
		},
		tooltip = {
			showIfAuto = false,
		},
		bonusRoll = {
			showIfAuto = false
		}
	},
	["dungeon"] = {
		name = "dungeon",
		buffs = {
			showIfAuto = true,
		},
		map = {
			showIfAuto = true,
		},
		quests = {
			showIfAuto = false,
		},
		chat = {
			showIfAuto = false,
		},
		tooltip = {
			showIfAuto = false,
		},
		bonusRoll = {
			showIfAuto = false
		}
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
		chat = {
			showIfAuto = false,
		},
		tooltip = {
			showIfAuto = false,
		},
		bonusRoll = {
			showIfAuto = false
		}
	},
}
local INIT_STATE = {
	name = "uninitialised",
	buffs = {
		isManual = false,
		showIfAuto = true,
	},
	map = {
		isManual = false,
		showIfAuto = true,
	},
	quests = {
		isManual = false,
		showIfAuto = true,
	},
	chat = {
		isManual = false,
		showIfAuto = true,
		privateMode = false,
		hideTime = false,
		disableManualToggle = false,
	},
	tooltip = {
		isManual = false,
		showIfAuto = true,
	},
	bonusRoll = {
		isManual = false,
		isHidden = false,
	}
}


--locals
UIHideTooltipIsActive = true
UIHideHideBonusRolls = true
local UIHideBonusRollFrameHidden = false

--functions

--util
local deepUnion
deepUnion = function(oldTable, overrideTable)
	newTable = {}
	for k, v in pairs(overrideTable) do
		if type(v) == "table" then
			newTable[k] = deepUnion(oldTable[k], v)
		else
			newTable[k] = v
		end
	end
	for k, v in pairs(oldTable) do
		if not newTable[k] then
			if type(v) == "table" then
				newTable[k] = deepUnion({}}, v)
			else
				newTable[k] = v
			end
		end
	end
	return newTable
end

--display affecting
local function displayMapCluster(currState)
	if currState.buffs.isManual or currState.buffs.showIfAuto then
		BuffFrame:Show()
	else
		BuffFrame:Hide()
	end

	if currState.map.isManual or currState.map.showIfAuto then
		MinimapCluster:Show()
	else
		MinimapCluster:Hide()
	end

	if currState.quests.isManual or currState.quests.showIfAuto then
		ObjectiveTrackerFrame:Show()
	else
		ObjectiveTrackerFrame:Hide()
	end
	return currState
end
local function displayChat(currState)
	if currState.chat.isManual or currState.chat.showIfAuto then
		SELECTED_CHAT_FRAME.Show = SELECTED_CHAT_FRAME.ShowOld
		GeneralDockManager.Show = GeneralDockManager.ShowOld
		SELECTED_CHAT_FRAME:Show()
		GeneralDockManager:Show()
	else
		SELECTED_CHAT_FRAME.Show = SELECTED_CHAT_FRAME.ShowNew
		GeneralDockManager.Show = GeneralDockManager.ShowNew
		SELECTED_CHAT_FRAME:Hide()
		GeneralDockManager:Hide()
	end
	return currState
end
local function displayBonusRoll(currState)
	if currState.bonusRoll.isManual or currState.bonusRoll.showIfAuto then
		BonusRollFrame:Hide()
		return deepUnion(currState, {
			bonusRoll = {
				isHidden = true
			}
		})
	else
		BonusRollFrame:Show()
		return deepUnion(currState, {
			bonusRoll = {
				isHidden = false
			}
		})
	end
end
local function displayToolTip(currState)
	if not currState.tooltip.isManual then
		GameTooltip:Hide()
	end
	return currState
end

--event handlers
local function toggleMapCluster(currState)
	return displayMapCluster(deepUnion(currState, {
		buffs = {
			isManual = not currState.buffs.isManual,
		},
		map = {
			isManual = not currState.map.isManual,
		},
		quests = {
			isManual = not currState.quests.isManual,
		}
	}))
end
local function togglePrivateMode(currState)
	return deepUnion(currState, {
		chat = {
			privateMode = not currState.chat.privateMode
		}
	})
end
local function toggleTooltip(currState)
	return displayToolTip(deepUnion(currState, {
		tooltip = {
			isManual = not currState.tooltip.isManual
		}
	}))
end
local function toggleBonusRoll(currState)
	return deepUnion(currState, {
		bonusRoll = {
			isManual = not currState.bonusRoll.isManual,
		},
	})
end
local function updateState(currState)
	local instanceType, instanceDiff = select(2, GetInstanceInfo())
	local newStateName =	(instanceType ~= "none" and "dungeon")
						or	(GetNumQuestWatches() > 0 or GetNumWorldQuestWatches() > 0 or (WorldQuestTrackerQuestsHeader and WorldQuestTrackerQuestsHeader:IsShown()) and "questing")
						or	("default")
	return deepUnion(currState, BLANK_IS_AUTO_STATES[newStateName])
end
local function chatEventHandler(currState, self, event, ...)
	if not CHAT_EVENTS[event] or currState.chat.isManual then
		return currState
	end

	local tth, push = unpack(CHAT_EVENTS[event])

	--applies all filter functions
	for desc, filter in pairs(FILTERS) do
		local tthExtra, pushExtra, skip = filter(currState, event, ...)
		if skip then
			return currState
		end
		tth, push = tth + (tthExtra or 0), push or pushExtra
	end

	--makes the Windows WoW icon blink
	if push then
		FlashClientIcon()
	end

	--creates callback to hide chat again
	C_Timer.After(tth, UIHide.getStateFunc(function(currState)
		if currState.chat.hideTime and currState.chat.hideTime <= GetTime() + 0.5 then
			C_Timer.After(0.5, UIHide.getStateFunc(function(currState)
				return deepUnion(currState, {
					chat = {
						disableManualToggle = false,
					}.
				})
			end))
			return displayChat(deepUnion(currState, {
				chat = {
					showIfAuto = false,
					hideTime = false
					disableManualToggle = true,
				},
			}))
		end
	end))

	--actually shows chat
	return displayChat(deepUnion(currState, {
		chat = {
			showIfAuto = true,
			hideTime = GetTime() + tth,
		},
	}))
end


--UIHide object, only thing with access to gameState info
do
	local gameState = deepUnion(INIT_STATE, {})
	local function getStateFunc(func)
		return function(...)
			gameState = func(gameState, ...)
		end
	end

	UIHide = {
		toggleMapCluster = getStateFunc(toggleMapCluster),
		togglePrivateMode = getStateFunc(togglePrivateMode),
		toggleTooltip = getStateFunc(toggleTooltip),
		toggleChat = getStateFunc(toggleChat),
		toggleBonusRoll = getStateFunc(toggleBonusRoll),
		getStateFunc = getStateFunc, --NOT SURE IF THIS IS THE BEST SOLUTION
		gameState = gameState, --PURELY FOR DEBUG PURPOSES
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
local function newChatShow(self, force)
	if force then
		self:ShowOld()
	end
end
for i = 1, NUM_CHAT_WINDOWS, 1 do
	if _G["ChatFrame"..i] then
		local curr = _G["ChatFrame"..i]
		curr.ShowOld = curr.Show
		curr.ShowNew = curr.newChatShow
		curr.Show = newChatShow
		_G["ChatFrame"..i.."Tab"].noMouseAlpha = 0
	end
end
GeneralDockManager.ShowOld = GeneralDockManager.Show
GeneralDockManager.ShowNew = newChatShow
GeneralDockManager.Show = newChatShow
FCF_StartAlertFlashOld = FCF_StartAlertFlash
FCF_StartAlertFlash = function() end
CHAT_FRAME_TAB_SELECTED_NOMOUSE_ALPHA = 0
------------------------------------------------------------------------------------------------------------------------------------------
--Change line 228 and 231 to noMouseAlpha = 0 in
--C:\Program Files (x86)\World of Warcraft\_retail_\Interface\Addons\Chatter\Libs\LibChatAnims\LibChatAnims.lua
------------------------------------------------------------------------------------------------------------------------------------------

--chat frame automation
for event, eventTable in pairs(CHAT_EVENTS) do
	EVENT_FRAME:RegisterEvent(event)
end
EVENT_FRAME:HookScript("OnEvent", UIHide.getStateFunc(chatEventHandler))

--minimap, buff and quest frame automations
for event, _ in pairs(STATE_EVENTS) do
	EVENT_FRAME:RegisterEvent(event)
end
EVENT_FRAME:HookScript("OnEvent", UIHide.getStateFunc(function(currState, self, event, ...)
	if STATE_EVENTS[event] then
		return displayMapCluster(updateState(currState))
	else
		return currState
	end
end))

if WorldQuestTrackerQuestsHeader then
	WorldQuestTrackerQuestsHeader:HookScript("OnShow", UIHide.getStateFunc(function(currState)
		return displayMapCluster(updateState(currState))
	end))
	WorldQuestTrackerQuestsHeader:HookScript("OnHide", UIHide.getStateFunc(function(currState)
		return displayMapCluster(updateState(currState))
	end))
end

--tooltip 
GameTooltip:HookScript("OnShow", UIHide.getStateFunc(function(currState, self)
	if currState.tooltip.isManual or (not InCombatLockdown() and IsShiftKeyDown()) or select(2, self:GetPoint()) ~= TooltipMover then
	else
		self:Hide()
	end
	return currState
end))
EVENT_FRAME:RegisterEvent("MODIFIER_STATE_CHANGED")
EVENT_FRAME:HookScript("OnEvent", function(self, event, ...)	--intentionally not a function of the state
	if event == "MODIFIER_STATE_CHANGED" and (... == "LSHIFT" or ... == "RSHIFT") then
		if select(2, ...) == 1 then
			GameTooltip:Show()
		else
			GameTooltip:Hide()
		end
	end
end)

--BonusRoll
BonusRollFrame:HookScript("OnShow", UIHide.getStateFunc(function(currState, self, event, ...)
	if not currState.bonusRoll.isManual then
		self:Hide()
		return deepUnion(currState, {
			bonusRoll = {
				isHidden = true,
			},
		})
	end
end))
BonusRollFrame.IsShownOld = BonusRollFrame.IsShown
BonusRollFrame.IsShown = function(self)
	return BonusRollFrame:IsShownOld() or UIHideBonusRollFrameHidden
end
EVENT_FRAME:RegisterEvent("SPELL_CONFIRMATION_TIMEOUT")
EVENT_FRAME:HookScript("OnEvent", UIHide.getStateFunc(function(currState, self, event, ...)
	if event == "SPELL_CONFIRMATION_TIMEOUT" and select(2, ...) == LE_SPELL_CONFIRMATION_PROMPT_TYPE_BONUS_ROLL then
		return deepUnion(currState, {
			bonusRoll = {
				isHidden = false,
			},
		}
	else
		return currState
	end
end))

------------------------------------------------------------------------------------------------------------------------------------------
--THIS MIGHT BE SUPER WRONG
--initialization stuff
UIHide.toggleDetails()
UIHide.getStateFunc(function(currState)
	return displayChat(displayMapCluster(updateState(currState)))
end)()
------------------------------------------------------------------------------------------------------------------------------------------


------------------------------------------------------------------------------------------------------------------------------------------
------------------------------------------------------------------------------------------------------------------------------------------
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
