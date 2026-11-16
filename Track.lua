local _, ns = ...

local QUESTION = "Interface\\Icons\\INV_Misc_QuestionMark"
local GCD = 1.6

ns.list = {}

local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	if GetSpellInfo then return (GetSpellInfo(id)) end
end

local function spellIcon(id)
	local tex
	if C_Spell and C_Spell.GetSpellTexture then
		tex = C_Spell.GetSpellTexture(id)
	elseif GetSpellTexture then
		tex = GetSpellTexture(id)
	end
	return tex or QUESTION
end

local function baseCooldown(id)
	if not GetSpellBaseCooldown then return 0 end
	local ok, ms = pcall(GetSpellBaseCooldown, id)
	if ok and type(ms) == "number" and not ns.IsSecret(ms) then return ms / 1000 end
	return 0
end

local function bookSpells()
	local out = {}
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo then
		local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() or 0 do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if info and not info.shouldHide then
				for slot = (info.itemIndexOffset or 0) + 1, (info.itemIndexOffset or 0) + (info.numSpellBookItems or 0) do
					local ok, item = pcall(C_SpellBook.GetSpellBookItemInfo, slot, bank)
					if ok and type(item) == "table" and item.spellID and not item.isPassive and not item.isOffSpec then
						out[#out + 1] = item.spellID
					end
				end
			end
		end
	elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
		for tab = 1, GetNumSpellTabs() or 0 do
			local _, _, offset, count = GetSpellTabInfo(tab)
			for slot = (offset or 0) + 1, (offset or 0) + (count or 0) do
				local kind, id = GetSpellBookItemInfo(slot, "spell")
				if (kind == "SPELL" or kind == nil) and type(id) == "number" then
					if not (IsPassiveSpell and IsPassiveSpell(slot, "spell")) then out[#out + 1] = id end
				end
			end
		end
	end
	return out
end

local function itemInfo(id)
	local name, icon
	if C_Item and C_Item.GetItemInfo then
		name = C_Item.GetItemInfo(id)
	elseif GetItemInfo then
		name = GetItemInfo(id)
	end
	if C_Item and C_Item.GetItemIconByID then
		icon = C_Item.GetItemIconByID(id)
	elseif GetItemIcon then
		icon = GetItemIcon(id)
	end
	return name or ("Item " .. id), icon or QUESTION
end

local function usable(id)
	local fn = (C_Item and C_Item.GetItemSpell) or GetItemSpell
	if not fn then return true end
	local ok, name = pcall(fn, id)
	return ok and name ~= nil
end

function ns.Rescan()
	local list, seen = {}, {}
	local hidden = ns.chardb.hidden
	local function add(e)
		if seen[e.key] or hidden[e.key] then return end
		seen[e.key] = true
		list[#list + 1] = e
	end
	local byName = {}
	local function spell(id, forced)
		local name = spellName(id)
		if not name then return end
		local base = baseCooldown(id)
		if not forced and base < ns.db.minimum then return end
		local old = byName[name]
		if old then
			if id > old.id then old.id = id end
			return
		end
		local e = { key = "s:" .. name, kind = "spell", id = id, name = name, icon = spellIcon(id), base = base }
		byName[name] = e
		add(e)
	end
	for id in pairs(ns.chardb.spells) do spell(id, true) end
	for _, id in ipairs(bookSpells()) do spell(id) end
	for _, e in ipairs(list) do e.icon = spellIcon(e.id) end
	for _, slot in ipairs({ 13, 14 }) do
		local id = GetInventoryItemID and GetInventoryItemID("player", slot)
		if type(id) == "number" and usable(id) then
			local name, icon = itemInfo(id)
			add({ key = "i:" .. id, kind = "slot", slot = slot, id = id, name = name, icon = icon })
		end
	end
	local items = {}
	for id in pairs(ns.chardb.items) do items[#items + 1] = id end
	table.sort(items)
	for _, id in ipairs(items) do
		local name, icon = itemInfo(id)
		add({ key = "i:" .. id, kind = "item", id = id, name = name, icon = icon })
	end
	for _, e in ipairs(list) do
		local old = ns.byKey and ns.byKey[e.key]
		if old then e.ready, e.start, e.duration = old.ready, old.start, old.duration end
	end
	ns.byKey = {}
	for _, e in ipairs(list) do ns.byKey[e.key] = e end
	ns.list = list
	ns.Update()
	ns:Fire("LIST")
end

local function read(e)
	local start, duration, object
	if e.kind == "spell" then
		if C_Spell and C_Spell.GetSpellCooldown then
			local ok, info = pcall(C_Spell.GetSpellCooldown, e.id)
			if ok and type(info) == "table" then start, duration = info.startTime, info.duration end
		elseif GetSpellCooldown then
			start, duration = GetSpellCooldown(e.id)
		end
		if (ns.IsSecret(start) or ns.IsSecret(duration)) and C_Spell and C_Spell.GetSpellCooldownDuration then
			local ok, obj = pcall(C_Spell.GetSpellCooldownDuration, e.id)
			if ok then object = obj end
		end
	elseif e.kind == "slot" then
		if GetInventoryItemCooldown then start, duration = GetInventoryItemCooldown("player", e.slot) end
	else
		local fn = (C_Container and C_Container.GetItemCooldown) or (C_Item and C_Item.GetItemCooldown) or GetItemCooldown
		if fn then
			local ok, s, d = pcall(fn, e.id)
			if ok then start, duration = s, d end
		end
	end
	return start, duration, object
end

function ns.Update()
	local now = GetTime()
	local changed = false
	for _, e in ipairs(ns.list) do
		local start, duration, object = read(e)
		local was = e.ready
		if ns.IsSecret(start) or ns.IsSecret(duration) then
			e.secret, e.object = true, object
			e.start, e.duration = nil, nil
			e.ready = nil
		else
			e.secret, e.object = false, nil
			if type(start) ~= "number" or type(duration) ~= "number" or duration <= GCD or start <= 0 then
				if not (e.duration and e.start and e.start + e.duration > now + 0.05 and type(duration) == "number" and duration > 0 and duration <= GCD) then
					e.start, e.duration = 0, 0
				end
			else
				e.start, e.duration = start, duration
			end
			e.ready = not (e.duration > 0 and e.start + e.duration > now)
			if not e.ready then e.pending = true end
		end
		if was ~= e.ready then changed = true end
	end
	ns:Fire("COOLDOWNS", changed)
end

function ns.Left(e, now)
	if e.secret or not e.duration or e.duration <= 0 then return 0 end
	local left = e.start + e.duration - (now or GetTime())
	if left < 0 then left = 0 end
	return left
end

function ns.Visible()
	local out = {}
	local show = ns.db.show
	local now = GetTime()
	for _, e in ipairs(ns.list) do
		local cooling = not e.secret and ns.Left(e, now) > 0
		if e.secret or show == "all" or (show == "cooling" and cooling) or (show == "ready" and not cooling) then
			out[#out + 1] = e
		end
	end
	return out
end

function ns.Announce(e)
	local text
	if e.secret then
		text = e.name
	else
		local left = ns.Left(e)
		if left > 0 then
			text = e.name .. " ready in " .. ns.TimeText(left) .. (left < 90 and "s" or "")
		else
			text = e.name .. " is ready"
		end
	end
	local channel
	if IsInRaid and IsInRaid() then
		channel = "RAID"
	elseif IsInGroup and IsInGroup() then
		channel = "PARTY"
	end
	if not channel then
		ns.Print(text)
		return text
	end
	local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
	if send then pcall(send, text, channel) end
	return text, channel
end

function ns.AddFromCursor()
	if not GetCursorInfo then return false end
	local kind, a, _, d = GetCursorInfo()
	if kind == "item" and type(a) == "number" then
		ns.chardb.items[a] = true
		ns.chardb.hidden["i:" .. a] = nil
	elseif kind == "spell" and type(d) == "number" then
		ns.chardb.spells[d] = true
		local name = spellName(d)
		if name then ns.chardb.hidden["s:" .. name] = nil end
	else
		return false
	end
	if ClearCursor then ClearCursor() end
	ns.Rescan()
	return true
end

local function update() ns.Debounce("cd", 0.05, ns.Update) end
local function rescan() ns.Debounce("scan", 0.3, ns.Rescan) end

ns:Listen("LOGIN", function() ns.Rescan() end)
ns:On("SPELL_UPDATE_COOLDOWN", update)
ns:On("BAG_UPDATE_COOLDOWN", update)
ns:On("SPELL_UPDATE_CHARGES", update)
ns:On("PLAYER_ENTERING_WORLD", rescan)
ns:On("SPELLS_CHANGED", rescan)
ns:On("PLAYER_EQUIPMENT_CHANGED", rescan)
ns:On("GET_ITEM_INFO_RECEIVED", rescan)
