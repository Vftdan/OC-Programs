local service = require "craftersvc.robot.service"

function start()
	service.registerRpc()
end

function stop()
	service.unregisterRpc()
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
addserver <hostname>
removeserver <hostname>
]])
end
