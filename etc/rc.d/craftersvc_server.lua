local service = require "craftersvc.server.service"
local robotPool = require "craftersvc.server.robotPool"

function start()
	service.registerRpc()
end

function stop()
	service.unregisterRpc()
end

function reload()
	service.loadConfig()
	robotPool.loadConfig()
end

function save()
	service.saveConfig()
	robotPool.saveConfig()
end

function addrobot(hostname)
	robotPool.addRobot(hostname)
end

function removerobot(hostname)
	robotPool.removeRobot(hostname)
end

function strategies()
	for _, name in ipairs(service.listStrategies()) do
		print(name)
	end
end

function use(name)
	service.useStrategy(name)
end

function help()
	print([[Subcommands:
start
stop
reload
save
addrobot <hostname>
removerobot <hostname>
strategies
use <strategy>
]])
end
