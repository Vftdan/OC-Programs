local os = require "os"
local config = require "craftersvc.common.config"

local ROBOTS_FILE = "/etc/craftersvc/robots.cfg"

local robots = {}
local robotsBusy = {}

local function addRobot(hostname)
	for _, old in ipairs(robots) do
		if old == hostname then
			return false
		end
	end
	table.insert(robots, hostname)
	return true
end

local function removeRobot(hostname)
	for i, old in ipairs(robots) do
		if old == hostname then
			table.remove(robots, i)
			return true
		end
	end
	return false
end

local function loadConfig()
	local lst = config.readConfig(ROBOTS_FILE, true)
	if lst then
		for i = #robots, 1, -1 do
			robots[i] = nil
		end
		for _, hostname in ipairs(lst) do
			addRobot(hostname)
		end
	end
end

local function saveConfig()
	config.writeConfig(ROBOTS_FILE, robots)
end

loadConfig()

local function withRobot(cb, waitAvailable, ...)
	repeat
		if #robots < 1 then
			error("No crafting robots registered")
		end
		for _, hostname in ipairs(robots) do
			local busy
			busy, robotsBusy[hostname] = robotsBusy[hostname], true
			if not busy then
				local result = table.pack(pcall(cb, hostname, ...))
				robotsBusy[hostname] = false
				if result[1] then
					return table.unpack(result, 2, result.n)
				else
					error(table.unpack(result, 2, result.n))
				end
			end
		end
		if waitAvailable then
			os.sleep(0.1)
		end
	until not waitAvailable
	error("All crafting robots are busy")
end

return {
	addRobot = addRobot,
	removeRobot = removeRobot,
	loadConfig = loadConfig,
	saveConfig = saveConfig,
	withRobot = withRobot,
}
