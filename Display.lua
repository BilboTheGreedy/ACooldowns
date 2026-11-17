local _, ns = ...
local UI = ns.UI
local C = UI.colors

local frame
local icons, bars = {}, {}
local GAP = 4

local function tooltip(self)
	local e = self.entry
	if not e then return end
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local done = false
	if e.kind == "spell" and GameTooltip.SetSpellByID then
		done = pcall(GameTooltip.SetSpellByID, GameTooltip, e.id)
	elseif e.kind == "slot" and GameTooltip.SetInventoryItem then
		done = pcall(GameTooltip.SetInventoryItem, GameTooltip, "player", e.slot)
	elseif GameTooltip.SetItemByID then
		done = pcall(GameTooltip.SetItemByID, GameTooltip, e.id)
	end
	if not done then GameTooltip:AddLine(e.name, 1, 1, 1) end
	GameTooltip:AddLine("Shift-click: announce    Right-click: menu", 0.58, 0.6, 0.65)
	GameTooltip:Show()
end

local function click(self, button)
	local e = self.entry
	if not e then return end
	if ns.AddFromCursor() then return end
	if button == "RightButton" then
		local entries = {
			{ text = e.name, title = true },
			{ text = "Hide this", func = function()
				ns.chardb.hidden[e.key] = e.name
				ns.Rescan()
			end },
			{ text = "Announce", func = function() ns.Announce(e) end },
		}
		for _, o in ipairs(ns.Options()) do entries[#entries + 1] = o end
		UI.Menu(self, entries)
	elseif IsShiftKeyDown and IsShiftKeyDown() then
		ns.Announce(e)
	end
end

local function common(f)
	f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnClick", click)
	f:SetScript("OnReceiveDrag", function() ns.AddFromCursor() end)
	f:SetScript("OnDragStart", function() frame:StartDrag() end)
	f:SetScript("OnDragStop", function() frame:StopDrag() end)
	f:SetScript("OnEnter", tooltip)
	f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function createIcon()
	local f = CreateFrame("Button", nil, frame)
	f.tex = f:CreateTexture(nil, "ARTWORK")
	f.tex:SetAllPoints(f)
	f.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	f.edges = UI.Border(f, { 0, 0, 0, 1 })
	f.cd = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
	f.cd:SetAllPoints(f)
	f.time = UI.Text(f, "GameFontHighlight", "CENTER", { 1, 1, 1 })
	f.time:SetPoint("CENTER", 0, 0)
	f.glow = f:CreateTexture(nil, "OVERLAY")
	f.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
	f.glow:SetBlendMode("ADD")
	f.glow:SetPoint("CENTER")
	f.glow:Hide()
	common(f)
	return f
end

local function createBar()
	local b = UI.Bar(frame, 18)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetSize(18, 18)
	b.icon:SetPoint("RIGHT", b, "LEFT", -2, 0)
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
	b.hit = CreateFrame("Button", nil, b)
	b.hit:SetAllPoints(b)
	common(b.hit)
	return b
end

local function pulse(e)
	if not e.pending then return end
	e.pending = false
	if ns.db.pulse then e.pulse = GetTime() end
	if ns.db.sound and PlaySound then
		pcall(PlaySound, SOUNDKIT and SOUNDKIT.MAP_PING or 3175, "Master")
	end
end

local function paintIcon(f, e, now)
	local left = ns.Left(e, now)
	if e.secret then
		f.time:SetText("")
		f.tex:SetDesaturated(e.ready == false)
	elseif left > 0 then
		f.time:SetText(ns.db.text and ns.TimeText(left) or "")
		f.tex:SetDesaturated(true)
	else
		f.time:SetText("")
		f.tex:SetDesaturated(false)
	end
	if e.pulse then
		local t = (now - e.pulse) / 0.6
		if t >= 1 then
			e.pulse = nil
			f.glow:Hide()
		else
			local s = f:GetWidth() * (1.4 + t * 0.9)
			f.glow:SetSize(s, s)
			f.glow:SetAlpha(1 - t)
			f.glow:Show()
		end
	else
		f.glow:Hide()
	end
end

local function paintBar(b, e, now)
	local left = ns.Left(e, now)
	if e.secret and e.ready ~= true then
		b.right:SetText("")
		if e.ready == false then
			b:SetColor(0.85, 0.35, 0.3, 0.85)
		else
			b:SetColor(0.5, 0.5, 0.55, 0.8)
		end
	elseif left > 0 then
		b:SetMinMaxValues(0, e.duration)
		b:SetValue(left)
		b.right:SetText(ns.TimeText(left))
		b:SetColor(0.85, 0.35, 0.3, 0.85)
	else
		b:SetMinMaxValues(0, 1)
		b:SetValue(1)
		b.right:SetText("Ready")
		local glow = e.pulse and (now - e.pulse) < 0.6
		if e.pulse and not glow then e.pulse = nil end
		b:SetColor(glow and 1 or 0.3, glow and 1 or 0.75, glow and 0.6 or 0.35, 0.85)
	end
end

local shown = {}
local fighting = InCombatLockdown and InCombatLockdown() and true or false

local function layout()
	if not frame then return end
	local db = ns.db
	shown = ns.Visible()
	local size = db.size
	for _, f in ipairs(icons) do f:Hide() f.entry = nil end
	for _, b in ipairs(bars) do b:Hide() b.hit.entry = nil end
	local now = GetTime()
	if db.bars then
		local width = 170
		for i, e in ipairs(shown) do
			local b = bars[i]
			if not b then
				b = createBar()
				bars[i] = b
			end
			b.entry, b.hit.entry = e, e
			b:SetWidth(width)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", frame, "TOPLEFT", 20, -(i - 1) * 20)
			b.icon:SetTexture(e.icon)
			b.left:SetText(e.name)
			if e.secret and e.ready ~= true and e.object and b.SetTimerDuration then
				local interp = Enum and Enum.StatusBarInterpolation and Enum.StatusBarInterpolation.Immediate or 0
				local dir = Enum and Enum.StatusBarTimerDirection and Enum.StatusBarTimerDirection.RemainingTime or 1
				pcall(b.SetTimerDuration, b, e.object, interp, dir)
			end
			paintBar(b, e, now)
			b:Show()
		end
		frame:SetSize(width + 20, math.max(1, #shown) * 20 - 2)
	else
		local step = size + GAP
		for i, e in ipairs(shown) do
			local f = icons[i]
			if not f then
				f = createIcon()
				icons[i] = f
			end
			f.entry = e
			f:SetSize(size, size)
			f:ClearAllPoints()
			if db.vertical then
				f:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, -(i - 1) * step)
			else
				f:SetPoint("TOPLEFT", frame, "TOPLEFT", (i - 1) * step, 0)
			end
			f.tex:SetTexture(e.icon)
			if f.cd.SetHideCountdownNumbers then f.cd:SetHideCountdownNumbers(not e.secret) end
			if e.secret then
				if e.ready == true then
					f.cd:SetCooldown(0, 0)
				elseif e.object and f.cd.SetCooldownFromDurationObject then
					pcall(f.cd.SetCooldownFromDurationObject, f.cd, e.object)
				else
					pcall(f.cd.SetCooldown, f.cd, e.rawStart, e.rawDuration)
				end
			elseif e.duration and e.duration > 0 then
				f.cd:SetCooldown(e.start, e.duration)
			else
				f.cd:SetCooldown(0, 0)
			end
			paintIcon(f, e, now)
			f:Show()
		end
		local n = math.max(1, #shown)
		if db.vertical then
			frame:SetSize(size, n * step - GAP)
		else
			frame:SetSize(n * step - GAP, size)
		end
	end
	frame.handle:SetShown(not db.frame.locked)
	frame.empty:SetShown(#ns.list == 0 and not db.frame.locked)
	frame:SetShown(not db.combatOnly or fighting or not db.frame.locked)
end
ns.Layout = layout

local function tick()
	local now = GetTime()
	local expired = false
	for _, e in ipairs(ns.list) do
		if not e.secret and e.ready == false and ns.Left(e, now) <= 0 then
			e.ready = true
			expired = true
		end
		if e.ready and e.pending then pulse(e) end
	end
	if expired and ns.db.show ~= "all" then
		layout()
		return
	end
	if ns.db.bars then
		for i = 1, #shown do
			local b = bars[i]
			if b and b.entry then paintBar(b, b.entry, now) end
		end
	else
		for i = 1, #shown do
			local f = icons[i]
			if f and f.entry then paintIcon(f, f.entry, now) end
		end
	end
end
ns.Tick = tick

local function build()
	frame = CreateFrame("Frame", "ACooldownsFrame", UIParent)
	frame:SetSize(200, 34)
	UI.Movable(frame, ns.db.frame)
	ns.frame = frame
	local handle = CreateFrame("Button", nil, frame)
	handle:SetPoint("BOTTOMLEFT", frame, "TOPLEFT", 0, 2)
	handle:SetSize(150, 16)
	UI.Fill(handle, { 1, 0.82, 0, 0.25 })
	UI.Border(handle, C.accent)
	handle.label = UI.Text(handle, "GameFontNormalSmall", "CENTER", C.accent)
	handle.label:SetPoint("CENTER")
	handle.label:SetText("Cooldowns (drag)")
	handle:RegisterForDrag("LeftButton")
	handle:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	handle:SetScript("OnDragStart", function() frame:StartDrag() end)
	handle:SetScript("OnDragStop", function() frame:StopDrag() end)
	handle:SetScript("OnReceiveDrag", function() ns.AddFromCursor() end)
	handle:SetScript("OnClick", function(self, button)
		if ns.AddFromCursor() then return end
		if button == "RightButton" then UI.Menu(self, ns.Options()) end
	end)
	frame.handle = handle
	frame.empty = UI.Text(frame, "GameFontDisableSmall", "LEFT", C.dim)
	frame.empty:SetPoint("LEFT", 0, 0)
	frame.empty:SetText("Nothing tracked. Drop an item or spell on the handle.")
	local elapsed = 0
	frame:SetScript("OnUpdate", function(_, dt)
		elapsed = elapsed + (dt or 0)
		if elapsed < 0.1 then return end
		elapsed = 0
		tick()
	end)
end

ns:Listen("LIST", function()
	if not frame then build() end
	layout()
end)
ns:Listen("COOLDOWNS", function()
	if frame then layout() end
end)
ns:Listen("OPTIONS", function()
	if frame then layout() end
end)
ns:Listen("LAYOUT_RESET", function()
	if frame then frame:Restore() end
end)
ns:On("PLAYER_REGEN_DISABLED", function()
	fighting = true
	if frame then layout() end
end)
ns:On("PLAYER_REGEN_ENABLED", function()
	fighting = false
	if frame then layout() end
end)
