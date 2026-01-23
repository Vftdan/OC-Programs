local service = require "craftersvc.robot.service"

function start()
	service.registerRpc()
end

function stop()
	service.unregisterRpc()
end

function reload()
	service.loadConfig()
end

function save()
	service.saveConfig()
end

function addserver(hostname)
	service.addServer(hostname)
end

function removeserver(hostname)
	service.removeServer(hostname)
end

function help()
	print([[Subcommands:
start
stop
reload
save
addserver <hostname>
removeserver <hostname>
]])
end
