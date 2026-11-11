-- Auto Feed Pet for WoW Forever.
-- Small movable reminder when the pet is hungry. Click it (or the unbound
-- "Feed Pet" keybind) to feed. No happy-state window, no auto-cast.

local ADDON = ...
local AFP = {}
_G.AutoFeedPet = AFP

local FEED_PET = 6991
local FEED_EFFECT = 1539
local HAPPY = 3
local ALERT_SOUND = "Interface\\AddOns\\AutoFeedPet\\feednow.mp3"

BINDING_HEADER_AUTOFEEDPET = "Auto Feed Pet"
_G["BINDING_NAME_CLICK AutoFeedPetButton:LeftButton"] = "Feed Pet"

local db
local panel, pending
local food
local feedBtns = {}
local MAX_FOODS = 5

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
		help = "/afp  — options.  /afp on | off | yellow on|off | chat on|off | sound | posreset",
		unhappy = "Unhappy",
		content = "Content",
		happy = "Happy",
		noFood = "No food in bags",
		eating = "Eating…",
		combat = "Out of combat to feed",
		tip = "Use a Feed button. Right-drag the header to move.",
		feedBtn = "Feed",
		posreset = "Window moved back to center.",
		soundOn = "Sound on.",
		soundOff = "Sound off.",
		config = "Auto Feed Pet",
		enabledOpt = "Enable addon",
		yellowOpt = "Show popup when pet is content (yellow)",
		soundOpt = "Play sound when popup appears",
		chatOpt = "Chat messages",
		blacklistBtn = "Blacklist…",
		resetPos = "Reset hunger popup",
		save = "Save",
		saveTip = "Click: save.\nShift-click: save and reload UI.",
		saved = "Saved.",
		blTitle = "Food blacklist",
		blList = "Blacklisted",
		bagList = "Food in bags",
		addBl = "Add to blacklist",
		removeBl = "Remove from blacklist",
		noBagFood = "No pet food in bags.",
		noBl = "Nothing blacklisted.",
		selectItem = "Select an item first.",
		addedBl = "Blacklisted %s.",
		removedBl = "Removed %s from blacklist.",
		queryUnknown = "Unknown item. Click to query the server.",
		querying = "Querying item %s…",
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
		tip = "Usa un botón Alimentar. Arrastra el encabezado con el derecho.",
		feedBtn = "Alimentar",
		posreset = "Ventana centrada de nuevo.",
		soundOn = "Sonido activado.",
		soundOff = "Sonido desactivado.",
		config = "Auto Feed Pet",
		enabledOpt = "Activar add-on",
		yellowOpt = "Mostrar aviso si la mascota está contenta (amarillo)",
		soundOpt = "Sonido al aparecer el aviso",
		chatOpt = "Mensajes de chat",
		blacklistBtn = "Lista negra…",
		resetPos = "Centrar aviso de hambre",
		save = "Guardar",
		saveTip = "Clic: guardar.\nMayús-clic: guardar y recargar.",
		saved = "Guardado.",
		blTitle = "Lista negra de comida",
		blList = "En la lista negra",
		bagList = "Comida en bolsas",
		addBl = "Añadir a la lista negra",
		removeBl = "Quitar de la lista negra",
		noBagFood = "No hay comida de mascota en las bolsas.",
		noBl = "Lista negra vacía.",
		selectItem = "Selecciona un objeto primero.",
		addedBl = "%s añadido a la lista negra.",
		removedBl = "%s quitado de la lista negra.",
		queryUnknown = "Objeto desconocido. Clic para consultar al servidor.",
		querying = "Consultando objeto %s…",
	},
}
L.esMX = L.esES
setmetatable(L, { __index = function(t) return t.enUS end })
local loc = L[GetLocale()] or L.enUS
AFP.L = loc

local FACE = {
	[1] = { loc.unhappy, 1, 0.25, 0.2, 0, 0.1875, 0, 0.359375 },
	[2] = { loc.content, 1, 0.82, 0.1, 0.1875, 0.375, 0, 0.359375 },
	[3] = { loc.happy, 0.35, 1, 0.35, 0.375, 0.5625, 0, 0.359375 },
}

local function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage("|cffaad372Auto Feed Pet|r: " .. msg)
end
AFP.Print = Print

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

-- Starter skip list; copied into SavedVariables once, then the player edits it.
local DEFAULT_BLACKLIST = {
	[6522] = true, -- Deviate Fish
	[6657] = true, -- Savory Deviate Delight (ninja / pirate)
	[251525] = true, -- Savory Whimsyfin Delight
}
AFP.DEFAULT_BLACKLIST = DEFAULT_BLACKLIST
AFP.ITEM_NAMES = {
	[6522] = "Deviate Fish",
	[6657] = "Savory Deviate Delight",
	[251525] = "Savory Whimsyfin Delight",
}

local function IsBlacklisted(itemID)
	return db and db.blacklist and itemID and db.blacklist[itemID] and true or false
end
AFP.IsBlacklisted = IsBlacklisted

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

local function UsedCount(itemID)
	return (db and db.used and db.used[itemID]) or 0
end

local function FindFoods()
	if not (C_PetInfo and C_PetInfo.CanPetEatItem and C_Container and C_Container.GetContainerNumSlots) then
		return {}
	end
	local petLevel = UnitLevel("pet") or 1
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	local byID = {}
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
		for slot = 1, (ok and slots or 0) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID and not IsBlacklisted(itemID) then
				local okEat, canEat = pcall(C_PetInfo.CanPetEatItem, itemID)
				if okEat and canEat then
					local info = C_Container.GetContainerItemInfo(bag, slot) or {}
					local count = info.stackCount or 1
					local name, _, _, itemLevel = getInfo(itemID)
					local mage = IsMageFood(itemID, info)
					local score = math.abs((itemLevel or petLevel) - petLevel)
					local cur = byID[itemID]
					if not cur then
						byID[itemID] = {
							bag = bag,
							slot = slot,
							itemID = itemID,
							count = count,
							icon = info.iconFileID,
							name = name or info.itemName or ("#" .. itemID),
							mage = mage,
							score = score,
							used = UsedCount(itemID),
						}
					else
						cur.count = cur.count + count
					end
				end
			end
		end
	end
	local list = {}
	for _, e in pairs(byID) do
		table.insert(list, e)
	end
	table.sort(list, function(a, b)
		if a.used ~= b.used then
			return a.used > b.used
		end
		if a.mage ~= b.mage then
			return a.mage
		end
		if a.score ~= b.score then
			return a.score < b.score
		end
		return a.count > b.count
	end)
	local out = {}
	for i = 1, math.min(MAX_FOODS, #list) do
		out[i] = list[i]
	end
	return out
end

local function FindFood()
	return FindFoods()[1]
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

local function SetRow(row, item, spell)
	if not row then
		return
	end
	local btn = row.btn
	if item then
		row.itemID = item.itemID
		if item.icon then
			row.icon:SetTexture(item.icon)
			row.icon:Show()
		else
			row.icon:Hide()
		end
		row.label:SetText(string.format("%s x%d", item.name, item.count))
		row:Show()
		if btn and not InCombatLockdown() then
			btn.itemID = item.itemID
			btn:SetAttribute("type1", "macro")
			btn:SetAttribute("macrotext1", "/cast " .. spell .. "\n/use " .. item.bag .. " " .. item.slot)
			btn:Show()
		end
	else
		row.itemID = nil
		row:Hide()
		if btn and not InCombatLockdown() then
			btn.itemID = nil
			btn:SetAttribute("type1", nil)
			btn:SetAttribute("macrotext1", "")
			btn:Hide()
		end
	end
end

local function Build()
	if panel then
		return
	end

	panel = CreateFrame("Frame", "AutoFeedPetFrame", UIParent, "BackdropTemplate")
	panel:SetSize(260, 58)
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

	local header = CreateFrame("Frame", nil, panel)
	header:SetPoint("TOPLEFT", 4, -4)
	header:SetPoint("TOPRIGHT", -4, -4)
	header:SetHeight(36)
	header:EnableMouse(true)
	header:RegisterForDrag("LeftButton", "RightButton")
	header:SetScript("OnDragStart", function()
		panel:StartMoving()
	end)
	header:SetScript("OnDragStop", function()
		panel:StopMovingOrSizing()
		SavePosition()
	end)
	header:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
		GameTooltip:SetText(loc.tip, 1, 1, 1)
		GameTooltip:Show()
	end)
	header:SetScript("OnLeave", GameTooltip_Hide)
	panel.header = header

	panel.face = header:CreateTexture(nil, "ARTWORK")
	panel.face:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
	panel.face:SetSize(24, 24)
	panel.face:SetPoint("LEFT", 6, 0)

	panel.pet = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	panel.pet:SetPoint("TOPLEFT", 36, -2)
	panel.pet:SetPoint("RIGHT", -4, 0)
	panel.pet:SetJustifyH("LEFT")

	panel.mood = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.mood:SetPoint("TOPLEFT", panel.pet, "BOTTOMLEFT", 0, -1)
	panel.mood:SetPoint("RIGHT", -4, 0)
	panel.mood:SetJustifyH("LEFT")

	panel.status = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	panel.status:SetPoint("TOPLEFT", panel.mood, "BOTTOMLEFT", 0, -1)
	panel.status:SetPoint("RIGHT", -4, 0)
	panel.status:SetJustifyH("LEFT")

	panel:EnableMouse(true)
	panel:RegisterForDrag("LeftButton", "RightButton")
	panel:SetScript("OnDragStart", panel.StartMoving)
	panel:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		SavePosition()
	end)

	for i = 1, MAX_FOODS do
		local row = CreateFrame("Frame", nil, panel)
		row:SetHeight(22)
		row:Hide()
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(18, 18)
		row.icon:SetPoint("LEFT", 2, 0)
		row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
		row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
		row.label:SetPoint("RIGHT", -64, 0)
		row.label:SetJustifyH("LEFT")
		row:SetScript("OnEnter", function(self)
			if not self.itemID then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
			GameTooltip:Show()
		end)
		row:SetScript("OnLeave", GameTooltip_Hide)
		feedBtns[i] = row
	end

	ApplyPosition()
	panel:Hide()
end

local function BuildFeed()
	if InCombatLockdown() or not panel then
		return
	end
	for i = 1, MAX_FOODS do
		local row = feedBtns[i]
		if row and not row.btn then
			local name = (i == 1) and "AutoFeedPetButton" or ("AutoFeedPetButton" .. i)
			local btn = CreateFrame("Button", name, row, "SecureActionButtonTemplate, UIPanelButtonTemplate")
			btn:SetSize(56, 20)
			btn:SetPoint("RIGHT", 0, 0)
			btn:SetText(loc.feedBtn)
			btn:RegisterForClicks("AnyUp", "AnyDown")
			btn:SetAttribute("useOnKeyDown", false)
			btn:SetScript("PostClick", function(self)
				if self.itemID and db then
					db.used = db.used or {}
					db.used[self.itemID] = (db.used[self.itemID] or 0) + 1
				end
			end)
			btn:Hide()
			row.btn = btn
		end
	end
end

local function EnsureFrames()
	Build()
	BuildFeed()
end

local function InCombat()
	return InCombatLockdown() or UnitAffectingCombat("player")
end

local function HidePopup()
	if not panel then
		return
	end
	if not InCombatLockdown() then
		for i = 1, MAX_FOODS do
			SetRow(feedBtns[i], nil)
		end
	end
	panel:Hide()
	panel:SetAlpha(1)
end

local function ShouldShow()
	if not db or not db.enabled then
		return false
	end
	if InCombat() then
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

	if InCombat() then
		HidePopup()
		return
	end

	local show = ShouldShow()
	if not show then
		HidePopup()
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

	local foods = FindFoods()
	food = foods[1]
	local eating = PetIsEating()
	local n = (not eating and #foods > 0) and #foods or 0
	if eating then
		panel.status:SetText(loc.eating)
	elseif n == 0 then
		panel.status:SetText("|cffff6060" .. loc.noFood .. "|r")
	else
		panel.status:SetText("")
	end

	local justOpened = not panel:IsShown()
	if not InCombatLockdown() then
		panel:SetWidth(280)
		panel:SetHeight(44 + 24 * math.max(n, 1))
		panel:Show()
	elseif not panel:IsShown() then
		return
	end
	if justOpened then
		PlayAlertSound()
	end

	if not InCombatLockdown() then
		BuildFeed()
		local spell = SpellName(FEED_PET) or "Feed Pet"
		for i = 1, MAX_FOODS do
			local row = feedBtns[i]
			if row then
				row:ClearAllPoints()
				row:SetPoint("TOPLEFT", 10, -40 - (i - 1) * 24)
				row:SetPoint("TOPRIGHT", -10, -40 - (i - 1) * 24)
				if n > 0 and foods[i] then
					SetRow(row, foods[i], spell)
				else
					SetRow(row, nil)
				end
			end
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

function AFP.GetDB()
	return db
end

function AFP.RefreshHunger()
	Refresh()
end

AFP.ResetPosition = ResetPosition

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
		if type(db.blacklist) ~= "table" then
			db.blacklist = {}
			for id in pairs(DEFAULT_BLACKLIST) do
				db.blacklist[id] = true
			end
		end
		db.blacklist[43571] = nil -- Magic Eater is Wrath-only; was added by mistake
		if type(db.used) ~= "table" then
			db.used = {}
		end
		C_Timer.NewTicker(15, Refresh)
		return
	end
	if event == "PLAYER_REGEN_DISABLED" then
		HidePopup()
		return
	end
	if event == "PLAYER_REGEN_ENABLED" then
		Schedule(0.15)
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
	elseif msg == "help" then
		Print(string.format(loc.status, tostring(db.enabled), tostring(db.feedOnYellow), tostring(db.chat), tostring(db.sound)))
		Print(loc.help)
	else
		if AFP.ToggleConfig then
			AFP.ToggleConfig()
		end
	end
end
