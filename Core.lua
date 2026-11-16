local ADDON, ns = ...

local defaults = {
	show = "all",
	bars = false,
	vertical = false,
	size = 34,
	pulse = true,
	sound = false,
	minimum = 30,
	frame = { scale = 1, locked = true, default = { "CENTER", "CENTER", 0, -230 } },
}

local charDefaults = {
	hidden = {},
	items = {},
	spells = {},
}

ACore.New(ADDON, ns, { db = "ACooldownsDB", defaults = defaults, char = "ACooldownsCharDB", charDefaults = charDefaults })

function ns.TimeText(left)
	if left >= 3600 then return math.floor(left / 3600 + 0.5) .. "h" end
	if left >= 90 then return math.floor(left / 60 + 0.5) .. "m" end
	if left >= 10 then return tostring(math.floor(left + 0.5)) end
	return string.format("%.1f", left)
end

function ns.Options()
	local db = ns.db
	local UI = ns.UI
	local function changed() ns:Fire("OPTIONS") end
	local function mode(text, value)
		return {
			text = text, checked = db.show == value,
			func = function()
				db.show = value
				changed()
			end,
		}
	end
	local entries = {
		{ text = "ACooldowns", title = true },
		UI.Check(db.frame, "locked", "Lock position", changed),
		UI.Check(db, "bars", "Show as bars", changed),
		UI.Check(db, "vertical", "Stack vertically", changed),
		UI.Check(db, "pulse", "Pulse when ready", changed),
		UI.Check(db, "sound", "Sound when ready", changed),
		{ text = "Show", title = true },
		mode("Everything", "all"),
		mode("Only on cooldown", "cooling"),
		mode("Only when ready", "ready"),
		{ text = "Track spells from", title = true },
	}
	for _, n in ipairs({ 30, 60, 120, 300 }) do
		entries[#entries + 1] = {
			text = n .. " seconds", checked = db.minimum == n,
			func = function()
				db.minimum = n
				ns.Rescan()
			end,
		}
	end
	entries[#entries + 1] = { text = "Icon size", title = true }
	for _, s in ipairs({ 26, 30, 34, 40, 48 }) do
		entries[#entries + 1] = {
			text = tostring(s), checked = db.size == s,
			func = function()
				db.size = s
				changed()
			end,
		}
	end
	local hidden = {}
	for key, name in pairs(ns.chardb.hidden) do hidden[#hidden + 1] = { key, tostring(name) } end
	table.sort(hidden, function(a, b) return a[2] < b[2] end)
	if #hidden > 0 then
		entries[#entries + 1] = { text = "Hidden (click to show again)", title = true }
		for _, h in ipairs(hidden) do
			entries[#entries + 1] = {
				text = h[2],
				func = function()
					ns.chardb.hidden[h[1]] = nil
					ns.Rescan()
				end,
			}
		end
	end
	return entries
end

ACore.Register({
	name = "ACooldowns",
	title = "ACooldowns",
	slash = "/acd",
	desc = "cooldown tracker",
	toggle = function() ns.UI.Menu(ns.frame or ACoreMinimapButton or UIParent, ns.Options()) end,
})

local function idFrom(text)
	local id = text:match("item:(%d+)") or text:match("spell:(%d+)") or text:match("^(%d+)$")
	return tonumber(id), text:find("spell:", 1, true) ~= nil
end

SLASH_ACOOLDOWNS1 = "/acd"
SLASH_ACOOLDOWNS2 = "/acooldowns"
SlashCmdList["ACOOLDOWNS"] = function(msg)
	msg = (msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = msg:match("^(%S+)%s*(.*)$")
	cmd = (cmd or ""):lower()
	if cmd == "unlock" then
		ns.db.frame.locked = false
		ns:Fire("OPTIONS")
	elseif cmd == "lock" then
		ns.db.frame.locked = true
		ns:Fire("OPTIONS")
	elseif cmd == "reset" then
		ns.db.frame.pos = nil
		ns.db.frame.scale = 1
		ns:Fire("LAYOUT_RESET")
	elseif cmd == "add" or cmd == "spell" or cmd == "remove" then
		local id, isSpell = idFrom(rest or "")
		if not id then
			ns.Print("use /acd add <item id or link>, /acd spell <spell id>, /acd remove <id>")
			return
		end
		if cmd == "remove" then
			ns.chardb.items[id] = nil
			ns.chardb.spells[id] = nil
		elseif cmd == "spell" or isSpell then
			ns.chardb.spells[id] = true
		else
			ns.chardb.items[id] = true
		end
		ns.Rescan()
	else
		ns.UI.Menu(ns.frame or UIParent, ns.Options())
	end
end
