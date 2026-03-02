local netserver = require "recipesched.netserver"

function start()
	netserver.registerRpc()
end

function stop()
	netserver.unregisterRpc()
end
