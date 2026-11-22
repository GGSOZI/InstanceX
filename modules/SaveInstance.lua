--[[
	SaveInstance module for Instance X
	Revived/Upgraded by DuaKNo | Dex ++ by Chillz | Dex by Moons

	Saves the place (or one object) as .rbxlx / .rbxmx into your executor's workspace folder.
	Needs: writefile (appendfile makes big saves lighter), HttpGet for the API dump (cached after the first run).

	local save = loadstring(game:HttpGet(".../modules/SaveInstance.lua"))()
	save({ Object = game, FilePath = "MyPlace", Decompile = true })
	save({ Object = workspace.Model, FilePath = "MyModel" })

	Options: Object, FilePath, Decompile, DecompileTimeout, DecompileIgnore, RemovePlayerCharacters,
	SavePlayers, NilInstances, IgnoreDefaultProps, ProgressCallback(done, total)
]]

local HttpService = game:GetService("HttpService")

local function viable(o)
	if o:IsA("ModuleScript") then return true end
	if o:IsA("LocalScript") then return o.RunContext == Enum.RunContext.Client or o.RunContext == Enum.RunContext.Legacy end
	if o:IsA("Script") then return o.RunContext == Enum.RunContext.Client end
	return false
end

local env = {
	writefile = writefile,
	appendfile = appendfile,
	getnilinstances = getnilinstances or get_nil_instances,
	gethiddenproperty = gethiddenproperty,
	decompile = decompile,
	isdecompile = function() return typeof(decompile) == "function" end,
	isViableDecompileScript = viable,
}

local API
local CACHE = "InstanceX_APIDump.json"

local function loadAPI()
	if API then return API end
	local raw
	if isfile and readfile and isfile(CACHE) then
		local ok, r = pcall(readfile, CACHE)
		if ok and type(r) == "string" and #r > 1000 then raw = r end
	end
	if not raw then
		local urls = {
			"https://raw.githubusercontent.com/MaximumADHD/Roblox-Client-Tracker/roblox/API-Dump.json",
			"https://raw.githubusercontent.com/CloneTrooper1019/Roblox-Client-Tracker/roblox/API-Dump.json",
		}
		for _, u in ipairs(urls) do
			local ok, r = pcall(function() return game:HttpGet(u) end)
			if ok and type(r) == "string" and #r > 1000 then raw = r break end
		end
		if not raw then error("could not download the Roblox API dump") end
		if writefile then pcall(writefile, CACHE, raw) end
	end
	local data = HttpService:JSONDecode(raw)
	local classes = {}
	for _, c in ipairs(data.Classes) do
		local props = {}
		for _, m in ipairs(c.Members) do
			if m.MemberType == "Property" then
				local tags = {}
				if m.Tags then
					for _, t in ipairs(m.Tags) do
						if type(t) == "string" then tags[t] = true end
					end
				end
				props[#props + 1] = { Name = m.Name, ValueType = m.ValueType, Serialization = m.Serialization, Tags = tags }
			end
		end
		classes[c.Name] = { Name = c.Name, Superclass = c.Superclass, Properties = props }
	end
	for _, c in pairs(classes) do c.Superclass = classes[c.Superclass] end
	API = { Classes = classes }
	return API
end

local function builtinsave(obj, filepath, options)
	options = options or {}
	local writefile_, appendfile_ = env.writefile, env.appendfile
	if not writefile_ then error("this executor has no writefile") end
	if not API or not API.Classes then error("the Roblox API dump is not loaded yet, wait a few seconds and try again") end

	local Players = game:GetService("Players")
	local CollectionService = game:GetService("CollectionService")
	local isPlace = obj == game
	local ext = isPlace and ".rbxlx" or ".rbxmx"

	local path = tostring(filepath or "saved")
	for _, e in ipairs({".txt", ".rbxlx", ".rbxmx", ".rbxl", ".rbxm"}) do
		if path:lower():sub(-#e) == e then path = path:sub(1, #path - #e) end
	end
	path = path:gsub("[*?:<>|\"]+", ""):sub(1, 150)
	if path == "" then path = "saved" end
	local fullPath = path .. ext

	-- text helpers
	local XML = { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;", ["'"] = "&apos;" }
	local function esc(s)
		s = tostring(s):gsub("[\0-\8\11\12\14-\31]", "")
		return (s:gsub("[&<>\"']", XML))
	end
	local function cdata(s)
		s = tostring(s):gsub("[\0-\8\11\12\14-\31]", "")
		s = s:gsub("]]>", "]]]]><![CDATA[>")
		return "<![CDATA[" .. s .. "]]>"
	end
	local function fnum(n)
		if n ~= n then return "NAN" end
		if n == math.huge then return "INF" end
		if n == -math.huge then return "-INF" end
		if n == math.floor(n) and math.abs(n) < 1e15 then return string.format("%d", n) end
		return string.format("%.9g", n)
	end
	local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	local function b64(s)
		local out = {}
		for i = 1, #s, 3 do
			local a, b, c = s:byte(i, i + 2)
			local n = a * 65536 + (b or 0) * 256 + (c or 0)
			local c1, c2, c3, c4 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64, math.floor(n / 64) % 64, n % 64
			out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
				.. (b and B64:sub(c3 + 1, c3 + 1) or "=") .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
		end
		return table.concat(out)
	end

	local ids, kids, order = {}, {}, 0
	local lastYield = os.clock()
	local function slice()
		if os.clock() - lastYield > 0.03 then
			task.wait()
			lastYield = os.clock()
		end
	end

	-- what to keep
	local camera = workspace.CurrentCamera
	local playerChars = {}
	if options.RemovePlayerCharacters ~= false then
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then playerChars[p.Character] = true end
		end
	end
	local function keep(o)
		local cn = o.ClassName
		if not API.Classes[cn] then return false end
		if cn == "Player" and not options.SavePlayers then return false end
		if o == camera then return false end
		if playerChars[o] then return false end
		return true
	end

	local function build(o)
		order += 1
		ids[o] = "RBX" .. order
		local list = {}
		local okC, ch = pcall(o.GetChildren, o)
		if okC then
			for _, c in ipairs(ch) do
				if keep(c) then list[#list + 1] = c end
			end
		end
		kids[o] = list
		for _, c in ipairs(list) do build(c) end
		slice()
	end

	local roots = {}
	if isPlace then
		local names = {
			"Workspace", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "StarterGui", "StarterPack", "StarterPlayer",
			"SoundService", "Teams", "Chat", "TextChatService", "MaterialService", "LocalizationService", "TestService",
			"VoiceChatService", "ServerScriptService", "ServerStorage",
		}
		if options.SavePlayers then table.insert(names, 1, "Players") end
		for _, n in ipairs(names) do
			local okS, svc = pcall(function() return game:FindService(n) end)
			if okS and svc then roots[#roots + 1] = svc end
		end
		if options.NilInstances and env.getnilinstances then
			local okN, nils = pcall(env.getnilinstances)
			if okN and type(nils) == "table" and #nils > 0 then
				local holder = Instance.new("Folder")
				holder.Name = "NilInstances"
				ids[holder] = "RBXNIL"
				local list = {}
				for _, n in ipairs(nils) do
					if typeof(n) == "Instance" and keep(n) then list[#list + 1] = n end
				end
				for _, n in ipairs(list) do build(n) end
				kids[holder] = list
				roots[#roots + 1] = holder
			end
		end
	else
		roots[1] = obj
	end
	for _, r in ipairs(roots) do
		if not ids[r] then build(r) end
	end
	local total = order

	-- properties
	local propCache = {}
	local function propsFor(cn)
		local c = propCache[cn]
		if c then return c end
		c = {}
		local seen = {}
		local cls = API.Classes[cn]
		while cls do
			for _, p in ipairs(cls.Properties) do
				if not seen[p.Name] then
					seen[p.Name] = true
					local s, vt = p.Serialization, p.ValueType
					if s and s.CanSave and vt and not (p.Tags and p.Tags.Deprecated) then
						c[#c + 1] = p
					end
				end
			end
			cls = cls.Superclass
		end
		propCache[cn] = c
		return c
	end

	local function contentUrl(x)
		if typeof(x) == "Content" then
			local okU, u = pcall(function() return x.Uri end)
			return okU and type(u) == "string" and u or ""
		end
		return tostring(x or "")
	end

	local function ser(name, v, vt)
		local t = typeof(v)
		local head = ' name="' .. esc(name) .. '"'
		if t == "string" then
			if vt == "Content" or vt == "ContentId" then
				if v == "" then return "<Content" .. head .. "><null></null></Content>" end
				return "<Content" .. head .. "><url>" .. esc(v) .. "</url></Content>"
			end
			return "<string" .. head .. ">" .. esc(v) .. "</string>"
		elseif t == "Content" then
			local u = contentUrl(v)
			if u == "" then return "<Content" .. head .. "><null></null></Content>" end
			return "<Content" .. head .. "><url>" .. esc(u) .. "</url></Content>"
		elseif t == "boolean" then
			return "<bool" .. head .. ">" .. (v and "true" or "false") .. "</bool>"
		elseif t == "number" then
			local tag = (vt == "int" and "int") or (vt == "int64" and "int64") or (vt == "double" and "double") or "float"
			return "<" .. tag .. head .. ">" .. fnum(v) .. "</" .. tag .. ">"
		elseif t == "EnumItem" then
			return "<token" .. head .. ">" .. v.Value .. "</token>"
		elseif t == "BrickColor" then
			return "<int" .. head .. ">" .. v.Number .. "</int>"
		elseif t == "Vector3" then
			return "<Vector3" .. head .. "><X>" .. fnum(v.X) .. "</X><Y>" .. fnum(v.Y) .. "</Y><Z>" .. fnum(v.Z) .. "</Z></Vector3>"
		elseif t == "Vector2" then
			return "<Vector2" .. head .. "><X>" .. fnum(v.X) .. "</X><Y>" .. fnum(v.Y) .. "</Y></Vector2>"
		elseif t == "Color3" then
			return "<Color3" .. head .. "><R>" .. fnum(v.R) .. "</R><G>" .. fnum(v.G) .. "</G><B>" .. fnum(v.B) .. "</B></Color3>"
		elseif t == "CFrame" then
			local c = { v:GetComponents() }
			local tags = { "X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22" }
			local out = { "<CoordinateFrame" .. head .. ">" }
			for i, tg in ipairs(tags) do out[#out + 1] = "<" .. tg .. ">" .. fnum(c[i]) .. "</" .. tg .. ">" end
			out[#out + 1] = "</CoordinateFrame>"
			return table.concat(out)
		elseif t == "UDim2" then
			return "<UDim2" .. head .. "><XS>" .. fnum(v.X.Scale) .. "</XS><XO>" .. fnum(v.X.Offset) .. "</XO><YS>" .. fnum(v.Y.Scale) .. "</YS><YO>" .. fnum(v.Y.Offset) .. "</YO></UDim2>"
		elseif t == "UDim" then
			return "<UDim" .. head .. "><S>" .. fnum(v.Scale) .. "</S><O>" .. fnum(v.Offset) .. "</O></UDim>"
		elseif t == "Rect" then
			return "<Rect2D" .. head .. "><min><X>" .. fnum(v.Min.X) .. "</X><Y>" .. fnum(v.Min.Y) .. "</Y></min><max><X>" .. fnum(v.Max.X) .. "</X><Y>" .. fnum(v.Max.Y) .. "</Y></max></Rect2D>"
		elseif t == "NumberRange" then
			return "<NumberRange" .. head .. ">" .. fnum(v.Min) .. " " .. fnum(v.Max) .. " </NumberRange>"
		elseif t == "NumberSequence" then
			local out = {}
			for _, k in ipairs(v.Keypoints) do out[#out + 1] = fnum(k.Time) .. " " .. fnum(k.Value) .. " " .. fnum(k.Envelope) .. " " end
			return "<NumberSequence" .. head .. ">" .. table.concat(out) .. "</NumberSequence>"
		elseif t == "ColorSequence" then
			local out = {}
			for _, k in ipairs(v.Keypoints) do
				out[#out + 1] = fnum(k.Time) .. " " .. fnum(k.Value.R) .. " " .. fnum(k.Value.G) .. " " .. fnum(k.Value.B) .. " 0 "
			end
			return "<ColorSequence" .. head .. ">" .. table.concat(out) .. "</ColorSequence>"
		elseif t == "Font" then
			return "<Font" .. head .. "><Family><url>" .. esc(contentUrl(v.Family)) .. "</url></Family><Weight>" .. v.Weight.Value .. "</Weight><Style>" .. v.Style.Name .. "</Style></Font>"
		elseif t == "PhysicalProperties" then
			return "<PhysicalProperties" .. head .. "><CustomPhysics>true</CustomPhysics><Density>" .. fnum(v.Density) .. "</Density><Friction>" .. fnum(v.Friction)
				.. "</Friction><Elasticity>" .. fnum(v.Elasticity) .. "</Elasticity><FrictionWeight>" .. fnum(v.FrictionWeight) .. "</FrictionWeight><ElasticityWeight>"
				.. fnum(v.ElasticityWeight) .. "</ElasticityWeight></PhysicalProperties>"
		elseif t == "Instance" then
			return "<Ref" .. head .. ">" .. (ids[v] or "null") .. "</Ref>"
		end
		return nil
	end

	local skipTypes = {
		ProtectedString = true, BinaryString = true, SharedString = true, Color3uint8 = true, Tags = true, Attributes = true,
		UniqueId = true, SecurityCapabilities = true, QDir = true, QFont = true,
	}
	local ghp = env.gethiddenproperty or gethiddenproperty
	local function read(o, name)
		local ok, v = pcall(function() return o[name] end)
		if ok then return true, v end
		if ghp then
			local ok2, v2 = pcall(ghp, o, name)
			if ok2 then return true, v2 end
		end
		return false
	end
	local function propFrag(o, p)
		local vt = p.ValueType
		if skipTypes[vt.Name] or p.Name == "Source" then return nil end
		local ok, v = read(o, p.Name)
		if not ok then return nil end
		if v == nil then
			if vt.Category == "Class" then return '<Ref name="' .. esc(p.Name) .. '">null</Ref>' end
			return nil
		end
		local okS, s = pcall(ser, p.Name, v, vt.Name)
		if okS then return s end
		return nil
	end

	local ignoreDefaults = options.IgnoreDefaultProps ~= false
	local alwaysKeep = { Name = true, Size = true, CFrame = true, MeshId = true, TextureID = true, TextureId = true }
	local defCache = {}
	local function defaultsFor(cn)
		local d = defCache[cn]
		if d ~= nil then return d or nil end
		local okI, inst = pcall(Instance.new, cn)
		if not okI or typeof(inst) ~= "Instance" then
			defCache[cn] = false
			return nil
		end
		d = {}
		for _, p in ipairs(propsFor(cn)) do
			local s = propFrag(inst, p)
			if s then d[p.Name] = s end
		end
		pcall(inst.Destroy, inst)
		defCache[cn] = d
		return d
	end

	-- scripts
	local canDecompile = env.isdecompile and env.isdecompile()
	local timeout = tonumber(options.DecompileTimeout) or 10
	local function ignored(o)
		local list = options.DecompileIgnore
		if type(list) ~= "table" or #list == 0 then return false end
		local a = o
		while a and a ~= game do
			for _, nm in ipairs(list) do
				if nm ~= "" and (a.Name == nm or a.ClassName == nm) then return true end
			end
			a = a.Parent
		end
		return false
	end
	local function getSource(o)
		if options.Decompile ~= false and canDecompile and not ignored(o) and (not env.isViableDecompileScript or env.isViableDecompileScript(o)) then
			local result, done
			task.spawn(function()
				local ok, r = pcall(env.decompile, o)
				if ok and type(r) == "string" then result = r end
				done = true
			end)
			local t0 = os.clock()
			while not done and os.clock() - t0 < timeout do task.wait() end
			if result and result ~= "" then return result end
			return "-- could not decompile " .. o.Name .. (done and " (empty result)" or " (timed out)")
		end
		local ok, s = pcall(function() return o.Source end)
		if ok and type(s) == "string" and s ~= "" then return s end
		return "-- source not available for " .. o.Name
	end

	local function pivotFrag(cf)
		local c = { cf:GetComponents() }
		local tags = { "X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22" }
		local out = { '<OptionalCoordinateFrame name="WorldPivotData"><CFrame>' }
		for i, tg in ipairs(tags) do out[#out + 1] = "<" .. tg .. ">" .. fnum(c[i]) .. "</" .. tg .. ">" end
		out[#out + 1] = "</CFrame></OptionalCoordinateFrame>"
		return table.concat(out)
	end

	local function itemProps(o)
		local cn = o.ClassName
		local out = {}
		local defs = ignoreDefaults and defaultsFor(cn) or nil
		for _, p in ipairs(propsFor(cn)) do
			local s = propFrag(o, p)
			if s and not (defs and defs[p.Name] == s and not alwaysKeep[p.Name]) then
				out[#out + 1] = s
			end
		end
		pcall(function()
			if o:IsA("BasePart") and cn ~= "Terrain" then
				local c = o.Color
				local r, g, b = math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5)
				out[#out + 1] = '<Color3uint8 name="Color3uint8">' .. string.format("%d", 4278190080 + r * 65536 + g * 256 + b) .. "</Color3uint8>"
			end
		end)
		pcall(function()
			if cn == "MeshPart" and ghp then
				local v = ghp(o, "InitialSize")
				if typeof(v) == "Vector3" then out[#out + 1] = ser("InitialSize", v, "Vector3") end
			end
		end)
		pcall(function()
			if o:IsA("Model") and not o.PrimaryPart then out[#out + 1] = pivotFrag(o.WorldPivot) end
		end)
		pcall(function()
			local tags = CollectionService:GetTags(o)
			if #tags > 0 then out[#out + 1] = '<BinaryString name="Tags">' .. b64(table.concat(tags, "\0")) .. "</BinaryString>" end
		end)
		if o:IsA("LuaSourceContainer") then
			out[#out + 1] = '<ProtectedString name="Source">' .. cdata(getSource(o)) .. "</ProtectedString>"
		end
		return out
	end

	-- output
	local useAppend = appendfile_ ~= nil
	local buf, bufLen, started, all = {}, 0, false, {}
	local function flush()
		if #buf == 0 then return end
		local chunk = table.concat(buf)
		buf, bufLen = {}, 0
		if not started then
			writefile_(fullPath, chunk)
			started = true
		else
			appendfile_(fullPath, chunk)
		end
	end
	local function emit(s)
		buf[#buf + 1] = s
		bufLen += #s
		if useAppend and bufLen > 750000 then flush() end
	end

	local done = 0
	local function writeItem(o)
		emit('<Item class="' .. esc(o.ClassName) .. '" referent="' .. ids[o] .. '"><Properties>')
		local okP, props = pcall(itemProps, o)
		if okP then
			for _, f in ipairs(props) do emit(f) end
		end
		emit("</Properties>")
		for _, c in ipairs(kids[o]) do writeItem(c) end
		emit("</Item>")
		done += 1
		if done % 150 == 0 then
			slice()
			if options.ProgressCallback then pcall(options.ProgressCallback, done, total) end
		end
	end

	emit('<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">')
	emit('<Meta name="ExplicitAutoJoints">true</Meta><External>null</External><External>nil</External>')
	for _, r in ipairs(roots) do writeItem(r) end
	emit("</roblox>")

	if useAppend then
		flush()
	else
		writefile_(fullPath, table.concat(buf))
	end
	if options.ProgressCallback then pcall(options.ProgressCallback, total, total) end
	return fullPath
end


return function(options)
	options = options or {}
	loadAPI()
	local obj = options.Object or game
	local path = options.FilePath or options.FileName or ("Place_" .. game.PlaceId)
	return builtinsave(obj, path, options)
end
