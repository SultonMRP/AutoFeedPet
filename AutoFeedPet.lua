-- Auto Feed Pet for WoW Forever.
-- Small movable reminder when the pet is hungry. Click it (or the unbound
-- "Feed Pet" keybind) to feed. No happy-state window, no auto-cast.

local ADDON = ...
local FEED_PET = 6991
local FEED_EFFECT = 1539
local HAPPY = 3
local ALERT_SOUND = "Interface\\AddOns\\AutoFeedPet\\feednow.mp3"

BINDING_HEADER_AUTOFEEDPET = "Auto Feed Pet"
_G["BINDING_NAME_CLICK AutoFeedPetButton:LeftButton"] = "Feed Pet"

local db
local panel, feed, pending
local food

local defaults = {
	enabled = true,
	feedOnYellow = true,
	chat = false,
	sound = true,
	pos = nil,
}

local L = {
	enUS = {
		on = "Enabled.",
		off = "Disabled.",
		status = "enabled=%s  yellow=%s  chat=%s  sound=%s",
		help = "/afp on | off | yellow on|off | chat on|off | sound | posreset",
		unhappy = "Unhappy",
		content = "Content",
		happy = "Happy",
		noFood = "No food in bags",
		eating = "Eating…",
		combat = "Out of combat to feed",
		tip = "Click to feed. Right-drag to move.",
		posreset = "Window moved back to center.",
		soundOn = "Sound on.",
		soundOff = "Sound off.",
	},
	esES = {
		on = "Activado.",
		off = "Desactivado.",
		status = "activado=%s  amarillo=%s  chat=%s  sound=%s",
		help = "/afp on | off | yellow on|off | chat on|off | sound | posreset",
		unhappy = "Descontenta",
		content = "Contenta",
		happy = "Feliz",
		noFood = "Sin comida en las bolsas",
		eating = "Comiendo…",
		combat = "Fuera de combate para alimentar",
		tip = "Clic para alimentar. Arrastra con el derecho para mover.",
		posreset = "Ventana centrada de nuevo.",
		soundOn = "Sonido activado.",
		soundOff = "Sonido desactivado.",
	},
}
L.esMX = L.esES
setmetatable(L, { __index = function(t) return t.enUS end })
local loc = L[GetLocale()] or L.enUS

local FACE = {
	[1] = { loc.unhappy, 1, 0.25, 0.2, 0, 0.1875, 0, 0.359375 },
	[2] = { loc.content, 1, 0.82, 0.1, 0.1875, 0.375, 0, 0.359375 },
	[3] = { loc.happy, 0.35, 1, 0.35, 0.375, 0.5625, 0, 0.359375 },
}

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffaad372Auto Feed Pet|r: " .. msg)
end

local function SpellName(spellID)
	if C_Spell and C_Spell.GetSpellName then
		local ok, name = pcall(C_Spell.GetSpellName, spellID)
		if ok and name then
			return name
		end
	end
	if GetSpellInfo then
		local ok, name = pcall(GetSpellInfo, spellID)
		if ok then
			return name
		end
	end
end

local function IsHunter()
	local _, class = UnitClass("player")
	return class == "HUNTER"
end

local function HasHunterPet()
	if not UnitExists("pet") or UnitIsDead("pet") or UnitIsDeadOrGhost("player") then
		return false
	end
	if HasPetUI then
		local ok, hasUI, isHunterPet = pcall(HasPetUI)
		if ok and hasUI ~= nil then
			return isHunterPet and true or false
		end
	end
	return IsHunter()
end

local function Happiness()
	if C_PetInfo and C_PetInfo.GetPetHappiness then
		local ok, h = pcall(C_PetInfo.GetPetHappiness)
		if ok and type(h) == "number" then
			return h
		end
	end
	if GetPetHappiness then
		local h = GetPetHappiness()
		if type(h) == "number" then
			return h
		end
	end
end

local function KnowsFeedPet()
	if C_SpellBook and C_SpellBook.IsSpellKnown then
		local ok, known = pcall(C_SpellBook.IsSpellKnown, FEED_PET)
		if ok then
			return known and true or false
		end
	end
	if IsPlayerSpell then
		return IsPlayerSpell(FEED_PET) and true or false
	end
	return true
end

local function UnitHasSpellAura(unit, spellID)
	if not UnitExists(unit) then
		return false
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 40 do
			local data = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
			if not data then
				break
			end
			if data.spellId == spellID then
				return true
			end
		end
	end
	if UnitBuff then
		for i = 1, 40 do
			local name, _, _, _, _, _, _, _, _, id = UnitBuff(unit, i)
			if not name then
				break
			end
			if id == spellID then
				return true
			end
		end
	end
	local effect = SpellName(spellID)
	if effect and AuraUtil and AuraUtil.FindAuraByName then
		return AuraUtil.FindAuraByName(effect, unit) ~= nil
	end
	return false
end

local function PetIsEating()
	return UnitHasSpellAura("pet", FEED_EFFECT) or UnitHasSpellAura("player", FEED_EFFECT)
end

local function PlayerIsAFK()
	if UnitIsAFK then
		local ok, afk = pcall(UnitIsAFK, "player")
		if ok and afk then
			return true
		end
	end
	return false
end

local function NeedsFood()
	local h = Happiness()
	if not h then
		return false
	end
	if h <= 1 then
		return true
	end
	return h == 2 and db and db.feedOnYellow
end

-- Mage bread (pets that eat bread). Water IDs are omitted; CanPetEatItem also filters diet.
local MAGE_FOOD = {
	[5349] = true, -- Conjured Muffin
	[1113] = true, -- Conjured Bread
	[1114] = true, -- Conjured Rye
	[1487] = true, -- Conjured Pumpernickel
	[8075] = true, -- Conjured Sourdough
	[8076] = true, -- Conjured Sweet Roll
	[22895] = true, -- Conjured Cinnamon Roll
}

local conjuredCache = {}

local function TooltipIsConjured(itemID)
	if conjuredCache[itemID] ~= nil then
		return conjuredCache[itemID]
	end
	if not (ITEM_CONJURED and C_TooltipInfo and C_TooltipInfo.GetItemByID) then
		return false
	end
	local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
	if not ok or type(data) ~= "table" or type(data.lines) ~= "table" then
		return false
	end
	for _, line in ipairs(data.lines) do
		if line.leftText == ITEM_CONJURED then
			conjuredCache[itemID] = true
			return true
		end
	end
	conjuredCache[itemID] = false
	return false
end

local function IsMageFood(itemID, info)
	if MAGE_FOOD[itemID] then
		return true
	end
	if info and info.isConjured then
		return true
	end
	local name = info and info.itemName
	if type(name) == "string" and name:find("Conjured", 1, true) then
		return true
	end
	return TooltipIsConjured(itemID)
end

local function FindFood()
	if not (C_PetInfo and C_PetInfo.CanPetEatItem and C_Container and C_Container.GetContainerNumSlots) then
		return nil
	end
	local petLevel = UnitLevel("pet") or 1
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local best, bestScore, bestMage
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
		for slot = 1, (ok and slots or 0) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID then
				local okEat, canEat = pcall(C_PetInfo.CanPetEatItem, itemID)
				if okEat and canEat then
					local info = C_Container.GetContainerItemInfo(bag, slot) or {}
					local count = info.stackCount or 1
					local name, _, _, itemLevel = getInfo(itemID)
					local mage = IsMageFood(itemID, info)
					local score = math.abs((itemLevel or petLevel) - petLevel)
					local take
					if not best then
						take = true
					elseif mage and not bestMage then
						take = true
					elseif mage == bestMage and (score < bestScore or (score == bestScore and count > best.count)) then
						take = true
					end
					if take then
						best = {
							bag = bag,
							slot = slot,
							itemID = itemID,
							count = count,
							icon = info.iconFileID,
							name = name or info.itemName or ("#" .. itemID),
						}
						bestScore = score
						bestMage = mage
					end
				end
			end
		end
	end
	return best
end

local function ApplyPosition()
	if not panel then
		return
	end
	panel:ClearAllPoints()
	local p = db and db.pos
	if p and p[1] then
		panel:SetPoint(p[1], UIParent, p[2] or p[1], p[3] or 0, p[4] or 0)
	else
		panel:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
	end
end

local function SavePosition()
	if not panel or not db then
		return
	end
	local point, _, relPoint, x, y = panel:GetPoint(1)
	db.pos = { point, relPoint, x, y }
end

local function PlayAlertSound()
	if not db or not db.sound then
		return
	end
	if PlaySoundFile then
		pcall(PlaySoundFile, ALERT_SOUND, "Master")
	end
end

local function ResetPosition()
	if db then
		db.pos = nil
	end
	ApplyPosition()
	Print(loc.posreset)
end

local function SetMacro(text)
	if not feed or InCombatLockdown() then
		return
	end
	if text then
		feed:SetAttribute("type1", "macro")
		feed:SetAttribute("macrotext1", text)
	else
		feed:SetAttribute("type1", nil)
		feed:SetAttribute("macrotext1", "")
	end
end

local function Build()
	if panel then
		return
	end

	panel = CreateFrame("Frame", "AutoFeedPetFrame", UIParent, "BackdropTemplate")
	panel:SetSize(250, 58)
	panel:SetFrameStrata("HIGH")
	panel:SetClampedToScreen(true)
	panel:SetMovable(true)
	if panel.SetBackdrop then
		panel:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 16, edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		panel:SetBackdropColor(0.05, 0.04, 0.02, 0.94)
		panel:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
	end

	panel.face = panel:CreateTexture(nil, "ARTWORK")
	panel.face:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
	panel.face:SetSize(24, 24)
	panel.face:SetPoint("LEFT", 10, 0)

	panel.pet = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.pet:SetPoint("TOPLEFT", 40, -8)
	panel.pet:SetPoint("RIGHT", -10, 0)
	panel.pet:SetJustifyH("LEFT")

	panel.mood = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.mood:SetPoint("TOPLEFT", panel.pet, "BOTTOMLEFT", 0, -1)
	panel.mood:SetPoint("RIGHT", -10, 0)
	panel.mood:SetJustifyH("LEFT")

	panel.food = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.food:SetPoint("TOPLEFT", panel.mood, "BOTTOMLEFT", 0, -1)
	panel.food:SetPoint("RIGHT", -10, 0)
	panel.food:SetJustifyH("LEFT")

	ApplyPosition()
	panel:Hide()
end

local function BuildFeed()
	if feed or InCombatLockdown() or not panel then
		return
	end

	feed = CreateFrame("Button", "AutoFeedPetButton", panel, "SecureActionButtonTemplate")
	feed:SetAllPoints(panel)
	feed:RegisterForClicks("AnyUp", "AnyDown")
	feed:RegisterForDrag("RightButton")
	feed:SetAttribute("useOnKeyDown", false)
	feed:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	feed:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		SavePosition()
	end)
	feed:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(loc.tip, 1, 1, 1)
		if food then
			GameTooltip:AddLine(string.format("%s x%d", food.name, food.count), 0.9, 0.9, 0.9)
		end
		GameTooltip:Show()
	end)
	feed:SetScript("OnLeave", GameTooltip_Hide)
end

local function EnsureFrames()
	Build()
	BuildFeed()
end

local function ShouldShow()
	if not db or not db.enabled then
		return false
	end
	if PlayerIsAFK() then
		return false
	end
	if not HasHunterPet() or not KnowsFeedPet() then
		return false
	end
	return NeedsFood()
end

local function Refresh()
	EnsureFrames()
	if not panel then
		return
	end

	local show = ShouldShow()
	if not show then
		if not InCombatLockdown() then
			SetMacro(nil)
			panel:Hide()
		end
		return
	end

	local h = Happiness() or 2
	local face = FACE[h] or FACE[2]
	local r, g, b = face[2], face[3], face[4]
	panel.pet:SetText(UnitName("pet") or "?")
	panel.mood:SetText(string.format("|cff%02x%02x%02x%s|r", r * 255, g * 255, b * 255, face[1]))
	panel.face:SetTexCoord(face[5], face[6], face[7], face[8])
	if panel.SetBackdropBorderColor then
		panel:SetBackdropBorderColor(r, g, b, 1)
	end

	food = FindFood()
	local eating = PetIsEating()
	local combat = InCombatLockdown() or UnitAffectingCombat("player")
	if eating then
		panel.food:SetText(loc.eating)
	elseif combat then
		panel.food:SetText(loc.combat)
	elseif food then
		local icon = food.icon and ("|T" .. food.icon .. ":12:12|t ") or ""
		panel.food:SetText(string.format("%s%s x%d", icon, food.name, food.count))
	else
		panel.food:SetText("|cffff6060" .. loc.noFood .. "|r")
	end

	local justOpened = not panel:IsShown()
	if not InCombatLockdown() then
		panel:Show()
	elseif not panel:IsShown() then
		return
	end
	if justOpened then
		PlayAlertSound()
	end

	if not InCombatLockdown() then
		BuildFeed()
		if feed and food and not eating then
			local spell = SpellName(FEED_PET) or "Feed Pet"
			SetMacro("/cast " .. spell .. "\n/use " .. food.bag .. " " .. food.slot)
		else
			SetMacro(nil)
		end
	end
end

local function Schedule(delay)
	if pending then
		return
	end
	pending = true
	C_Timer.After(delay or 0.2, function()
		pending = false
		Refresh()
	end)
end

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("PLAYER_REGEN_DISABLED")
f:RegisterEvent("UNIT_HAPPINESS")
f:RegisterEvent("UNIT_PET")
f:RegisterEvent("PET_UI_UPDATE")
f:RegisterEvent("BAG_UPDATE_DELAYED")
f:RegisterEvent("PLAYER_FLAGS_CHANGED")
f:RegisterEvent("UNIT_AURA")

f:SetScript("OnEvent", function(_, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON then
			return
		end
		AutoFeedPetDB = AutoFeedPetDB or {}
		for k, v in pairs(defaults) do
			if AutoFeedPetDB[k] == nil then
				AutoFeedPetDB[k] = v
			end
		end
		db = AutoFeedPetDB
		C_Timer.NewTicker(15, Refresh)
		return
	end
	if event == "UNIT_PET" and arg1 ~= "player" then
		return
	end
	if event == "PLAYER_FLAGS_CHANGED" and arg1 and arg1 ~= "player" then
		return
	end
	if event == "UNIT_AURA" and arg1 ~= "pet" and arg1 ~= "player" then
		return
	end
	Schedule(event == "PLAYER_ENTERING_WORLD" and 3 or 0.2)
end)

SLASH_AUTOFEEDPET1 = "/afp"
SLASH_AUTOFEEDPET2 = "/autofeedpet"
SlashCmdList.AUTOFEEDPET = function(msg)
	msg = strtrim(strlower(msg or ""))
	db = db or AutoFeedPetDB or defaults
	if msg == "on" or msg == "enable" then
		db.enabled = true
		Print(loc.on)
		Schedule(0.05)
	elseif msg == "off" or msg == "disable" then
		db.enabled = false
		Print(loc.off)
		Schedule(0.05)
	elseif msg == "posreset" or msg == "reset" then
		ResetPosition()
	elseif msg == "yellow on" then
		db.feedOnYellow = true
		Print("yellow=on")
		Schedule(0.05)
	elseif msg == "yellow off" then
		db.feedOnYellow = false
		Print("yellow=off")
		Schedule(0.05)
	elseif msg == "chat on" then
		db.chat = true
		Print("chat=on")
	elseif msg == "chat off" then
		db.chat = false
		Print("chat=off")
	elseif msg == "sound" then
		db.sound = not db.sound
		Print(db.sound and loc.soundOn or loc.soundOff)
	elseif msg == "sound on" then
		db.sound = true
		Print(loc.soundOn)
	elseif msg == "sound off" then
		db.sound = false
		Print(loc.soundOff)
	else
		Print(string.format(loc.status, tostring(db.enabled), tostring(db.feedOnYellow), tostring(db.chat), tostring(db.sound)))
		Print(loc.help)
	end
end
