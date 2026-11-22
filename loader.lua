--[[
	Instance X loader
	Revived/Upgraded by DuaKNo | Dex ++ by Chillz | Dex by Moons

	loadstring(game:HttpGet("https://raw.githubusercontent.com/GGSOZI/InstanceX/main/loader.lua"))()
]]

local USER, REPO, BRANCH = "GGSOZI", "InstanceX", "main"

local base = ("https://raw.githubusercontent.com/%s/%s/%s/"):format(USER, REPO, BRANCH)
getgenv().InstanceX_Base = base

local function notify(text)
	pcall(function()
		game:GetService("StarterGui"):SetCore("SendNotification", { Title = "Instance X", Text = text, Duration = 6 })
	end)
end

local src
for _ = 1, 3 do
	local ok, body = pcall(function() return game:HttpGet(base .. "Instance_X.lua", true) end)
	if ok and type(body) == "string" and #body > 1000 then
		src = body
		break
	end
	task.wait(1)
end

if not src then
	notify("Could not download Instance X, check your connection.")
	return
end

local fn, err = loadstring(src, "=InstanceX")
if not fn then
	warn("[Instance X] failed to load: " .. tostring(err))
	notify("Instance X failed to load, see the console.")
	return
end

fn()
