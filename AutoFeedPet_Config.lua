local AFP = AutoFeedPet
local loc

local config, blacklistFrame
local selectedBag, selectedBl
local bagRows, blRows = {}, {}
local bagScrollChild, blScrollChild
local queryTip
local RefreshBlacklistLists

local ROW_H = 22

local function DB()
	return AFP.GetDB()
end

local function Skin(frame)
	if not frame.SetBackdrop then
		return
	end
	frame:SetBackdrop({
		bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
		edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
		tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 },
	})
	frame:SetBackdropColor(0.05, 0.04, 0.02, 0.96)
	frame:SetBackdropBorderColor(0.55, 0.45, 0.2, 1)
end

local function GetInfo(itemID)
	local getInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
	return getInfo(itemID)
end

local function ItemIsUnknown(itemID)
	if not itemID then
		return false
	end
	local name, _, _, _, _, _, _, _, _, icon = GetInfo(itemID)
	return not name or not icon
end

-- Same idea as BotBags: SetHyperlink on a hidden tooltip asks the server for item data.
local function QueryItemFromServer(itemID)
	if not itemID then
		return
	end
	if C_Item and C_Item.RequestLoadItemDataByID then
		pcall(C_Item.RequestLoadItemDataByID, itemID)
	end
	local link = "item:" .. itemID .. ":0:0:0:0:0:0:0"
	if not queryTip then
		queryTip = CreateFrame("GameTooltip", "AutoFeedPetQueryTip", UIParent, "GameTooltipTemplate")
		queryTip:SetOwner(UIParent, "ANCHOR_NONE")
		queryTip:SetScript("OnTooltipSetItem", function()
			if RefreshBlacklistLists then
				RefreshBlacklistLists()
			end
		end)
	end
	queryTip:SetOwner(UIParent, "ANCHOR_NONE")
	pcall(queryTip.SetHyperlink, queryTip, link)
end

local function ItemName(itemID)
	local name, _, quality, _, _, _, _, _, _, icon = GetInfo(itemID)
	if not name and AFP.ITEM_NAMES and AFP.ITEM_NAMES[itemID] then
		name = AFP.ITEM_NAMES[itemID]
	end
	return name or ("#" .. itemID), icon or 134400, quality or 1
end

local function QualityColor(quality)
	if GetItemQualityColor then
		local r, g, b = GetItemQualityColor(quality)
		if r then
			return r, g, b
		end
	end
	return 1, 1, 1
end

local function MakeSaveButton(parent)
	local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	btn:SetSize(88, 24)
	btn:SetText(loc.save)
	btn:SetScript("OnClick", function()
		AFP.Print(loc.saved)
		if IsShiftKeyDown() then
			ReloadUI()
		end
	end)
	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:SetText(loc.save, 1, 1, 1)
		GameTooltip:AddLine(loc.saveTip, 0.9, 0.9, 0.9, true)
		GameTooltip:Show()
	end)
	btn:SetScript("OnLeave", GameTooltip_Hide)
	return btn
end

local function MakeCheck(parent, key, label)
	local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
	cb:SetSize(26, 26)
	cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	cb.text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
	cb.text:SetText(label)
	cb:SetScript("OnClick", function(self)
		local d = DB()
		if d then
			d[key] = self:GetChecked() and true or false
			AFP.RefreshHunger()
		end
	end)
	cb.key = key
	return cb
end

local function MakeWindow(name, width, height, title)
	local frame = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	frame:SetSize(width, height)
	frame:SetFrameStrata("DIALOG")
	frame:SetToplevel(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:SetClampedToScreen(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	Skin(frame)
	frame:SetPoint("CENTER")
	local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	text:SetPoint("TOP", 0, -12)
	text:SetText(title)
	frame.title = text
	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	frame:Hide()
	tinsert(UISpecialFrames, name)
	return frame
end

local function ClearRows(list)
	for _, row in ipairs(list) do
		row:Hide()
	end
end

local function GetRow(list, parent, index, onClick)
	local row = list[index]
	if row then
		return row
	end
	row = CreateFrame("Button", nil, parent)
	row:SetHeight(ROW_H)
	row:SetPoint("LEFT", 2, 0)
	row:SetPoint("RIGHT", -2, 0)
	row.icon = row:CreateTexture(nil, "ARTWORK")
	row.icon:SetSize(18, 18)
	row.icon:SetPoint("LEFT", 2, 0)
	row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
	row.label:SetPoint("RIGHT", -4, 0)
	row.label:SetJustifyH("LEFT")
	row.hl = row:CreateTexture(nil, "HIGHLIGHT")
	row.hl:SetAllPoints()
	row.hl:SetColorTexture(1, 0.82, 0.1, 0.18)
	row:SetScript("OnClick", function(self)
		if ItemIsUnknown(self.itemID) then
			QueryItemFromServer(self.itemID)
			AFP.Print(string.format(loc.querying, tostring(self.itemID)))
		end
		onClick(self)
	end)
	row:SetScript("OnEnter", function(self)
		if not self.itemID then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		if ItemIsUnknown(self.itemID) then
			GameTooltip:SetText(ItemName(self.itemID), 1, 1, 1)
			GameTooltip:AddLine(loc.queryUnknown, 1, 0.3, 0.3, true)
		else
			local ok = pcall(GameTooltip.SetItemByID, GameTooltip, self.itemID)
			if not ok then
				GameTooltip:SetHyperlink("item:" .. self.itemID .. ":0:0:0:0:0:0:0")
			end
		end
		GameTooltip:Show()
	end)
	row:SetScript("OnLeave", GameTooltip_Hide)
	list[index] = row
	return row
end

local function FillList(child, rows, items, selectedID, setter)
	ClearRows(rows)
	local y = -2
	for i, entry in ipairs(items) do
		local row = GetRow(rows, child, i, function(self)
			setter(self.itemID)
		end)
		local name, icon, quality = ItemName(entry.id)
		local r, g, b = QualityColor(quality)
		row.itemID = entry.id
		row.icon:SetTexture(icon)
		if entry.count then
			row.label:SetText(string.format("%s  x%d", name, entry.count))
		else
			row.label:SetText(name)
		end
		row.label:SetTextColor(r, g, b)
		row:ClearAllPoints()
		row:SetPoint("TOPLEFT", 0, y)
		row:SetPoint("TOPRIGHT", 0, y)
		if selectedID and selectedID == entry.id then
			row:SetAlpha(1)
			if not row.sel then
				row.sel = row:CreateTexture(nil, "BACKGROUND")
				row.sel:SetAllPoints()
				row.sel:SetColorTexture(0.4, 0.7, 1, 0.25)
			end
			row.sel:Show()
		elseif row.sel then
			row.sel:Hide()
		end
		row:Show()
		y = y - ROW_H
	end
	child:SetHeight(math.max(40, (#items * ROW_H) + 8))
end

local function BagFoods()
	local seen, list = {}, {}
	if not (C_Container and C_Container.GetContainerNumSlots) then
		return list
	end
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local ok, slots = pcall(C_Container.GetContainerNumSlots, bag)
		for slot = 1, (ok and slots or 0) do
			local itemID = C_Container.GetContainerItemID(bag, slot)
			if itemID and not seen[itemID] then
				local canEat
				if C_PetInfo and C_PetInfo.CanPetEatItem then
					local okEat, eat = pcall(C_PetInfo.CanPetEatItem, itemID)
					canEat = okEat and eat
				end
				if canEat then
					seen[itemID] = true
					local info = C_Container.GetContainerItemInfo(bag, slot) or {}
					table.insert(list, { id = itemID, count = info.stackCount or 1 })
				end
			elseif itemID and seen[itemID] then
				local info = C_Container.GetContainerItemInfo(bag, slot) or {}
				for _, e in ipairs(list) do
					if e.id == itemID then
						e.count = e.count + (info.stackCount or 1)
						break
					end
				end
			end
		end
	end
	table.sort(list, function(a, b)
		local na = ItemName(a.id)
		local nb = ItemName(b.id)
		return na < nb
	end)
	return list
end

local function BlacklistItems()
	local d = DB()
	local list = {}
	if d and type(d.blacklist) == "table" then
		for id in pairs(d.blacklist) do
			if d.blacklist[id] then
				table.insert(list, { id = tonumber(id) or id })
			end
		end
	end
	table.sort(list, function(a, b)
		return ItemName(a.id) < ItemName(b.id)
	end)
	return list
end

RefreshBlacklistLists = function()
	if not blacklistFrame or not blScrollChild then
		return
	end
	FillList(blScrollChild, blRows, BlacklistItems(), selectedBl, function(id)
		selectedBl = id
		selectedBag = nil
		RefreshBlacklistLists()
	end)
	FillList(bagScrollChild, bagRows, BagFoods(), selectedBag, function(id)
		selectedBag = id
		selectedBl = nil
		RefreshBlacklistLists()
	end)
end

local function MakeColumn(parent, title, x, y, w, h)
	local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	label:SetPoint("TOPLEFT", x, y)
	label:SetText(title)
	local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	box:SetPoint("TOPLEFT", x, y - 18)
	box:SetSize(w, h)
	Skin(box)
	local scroll = CreateFrame("ScrollFrame", nil, box, "UIPanelScrollFrameTemplate")
	scroll:SetPoint("TOPLEFT", 6, -6)
	scroll:SetPoint("BOTTOMRIGHT", -28, 6)
	local child = CreateFrame("Frame", nil, scroll)
	child:SetSize(w - 36, h)
	scroll:SetScrollChild(child)
	return child
end

local function BuildBlacklist()
	if blacklistFrame then
		return
	end
	blacklistFrame = MakeWindow("AutoFeedPetBlacklist", 560, 420, loc.blTitle)
	blacklistFrame:SetPoint("CENTER", 40, -20)
	blScrollChild = MakeColumn(blacklistFrame, loc.blList, 14, -40, 250, 280)
	bagScrollChild = MakeColumn(blacklistFrame, loc.bagList, 292, -40, 250, 280)

	local add = CreateFrame("Button", nil, blacklistFrame, "UIPanelButtonTemplate")
	add:SetSize(160, 24)
	add:SetPoint("BOTTOMLEFT", 14, 44)
	add:SetText(loc.addBl)
	add:SetScript("OnClick", function()
		local d = DB()
		if not d then
			return
		end
		local id = selectedBag
		if not id then
			AFP.Print(loc.selectItem)
			return
		end
		d.blacklist = d.blacklist or {}
		d.blacklist[id] = true
		selectedBl = id
		selectedBag = nil
		AFP.Print(string.format(loc.addedBl, ItemName(id)))
		AFP.RefreshHunger()
		RefreshBlacklistLists()
	end)

	local remove = CreateFrame("Button", nil, blacklistFrame, "UIPanelButtonTemplate")
	remove:SetSize(180, 24)
	remove:SetPoint("LEFT", add, "RIGHT", 8, 0)
	remove:SetText(loc.removeBl)
	remove:SetScript("OnClick", function()
		local d = DB()
		if not d or not d.blacklist then
			return
		end
		local id = selectedBl or selectedBag
		if not id or not d.blacklist[id] then
			AFP.Print(loc.selectItem)
			return
		end
		d.blacklist[id] = nil
		AFP.Print(string.format(loc.removedBl, ItemName(id)))
		selectedBl = nil
		AFP.RefreshHunger()
		RefreshBlacklistLists()
	end)

	local save = MakeSaveButton(blacklistFrame)
	save:SetPoint("BOTTOMRIGHT", -14, 12)

	blacklistFrame:SetScript("OnShow", RefreshBlacklistLists)
	local ev = CreateFrame("Frame", nil, blacklistFrame)
	ev:RegisterEvent("BAG_UPDATE_DELAYED")
	ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
	ev:SetScript("OnEvent", function()
		if blacklistFrame:IsShown() then
			RefreshBlacklistLists()
		end
	end)
end

local function BuildConfig()
	if config then
		return
	end
	config = MakeWindow("AutoFeedPetConfig", 360, 280, loc.config)

	local y = -48
	local function place(cb)
		cb:SetPoint("TOPLEFT", 18, y)
		y = y - 28
	end
	config.checks = {
		MakeCheck(config, "enabled", loc.enabledOpt),
		MakeCheck(config, "feedOnYellow", loc.yellowOpt),
		MakeCheck(config, "sound", loc.soundOpt),
		MakeCheck(config, "chat", loc.chatOpt),
	}
	for _, cb in ipairs(config.checks) do
		place(cb)
	end

	local bl = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
	bl:SetSize(140, 24)
	bl:SetPoint("TOPLEFT", 22, y - 8)
	bl:SetText(loc.blacklistBtn)
	bl:SetScript("OnClick", function()
		BuildBlacklist()
		if blacklistFrame:IsShown() then
			blacklistFrame:Hide()
		else
			blacklistFrame:Show()
			RefreshBlacklistLists()
		end
	end)

	local reset = CreateFrame("Button", nil, config, "UIPanelButtonTemplate")
	reset:SetSize(160, 24)
	reset:SetPoint("LEFT", bl, "RIGHT", 8, 0)
	reset:SetText(loc.resetPos)
	reset:SetScript("OnClick", function()
		if AFP.ResetPosition then
			AFP.ResetPosition()
		end
	end)

	local save = MakeSaveButton(config)
	save:SetPoint("BOTTOMRIGHT", -14, 12)

	config:SetScript("OnShow", function()
		local d = DB()
		if not d then
			return
		end
		for _, cb in ipairs(config.checks) do
			cb:SetChecked(d[cb.key] and true or false)
		end
	end)
end

function AFP.ToggleConfig()
	loc = AFP.L
	if not DB() then
		return
	end
	BuildConfig()
	if config:IsShown() then
		config:Hide()
		if blacklistFrame then
			blacklistFrame:Hide()
		end
	else
		config:Show()
	end
end
