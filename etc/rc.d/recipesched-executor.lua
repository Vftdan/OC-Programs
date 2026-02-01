local executor = require "recipesched.executor"
local thread = require "thread"

local ctx, thr

function start()
	if not ctx then
		ctx = executor.makeExecutorContext()
	else
		ctx.running = true
	end
	if not thr or thr:status() == "dead" then
		thr = thread.create(function()
			executor.executorEntry(ctx)
		end)
		thr:detach()
	elseif thr:status() == "suspended" then
		thr:resume()
	end
end

function stop()
	if ctx then
		ctx.running = false
	end
end

function stop()
	if ctx then
		ctx.running = false
	end
end

function kill()
	if not ctx then
		return
	end
	ctx.running = false
	thr:kill()
	executor.cleanupKilled(ctx)
end

function status()
	if not ctx or not thr then
		print("Not started")
	end
	local s = thr:status()
	if not ctx.running then
		if s == "running" then
			print("Stopping")
		else
			print("Stopped")
		end
	end
	if s == "suspended" then
		print("Suspended?")
	elseif s == "dead" then
		print("Dead")
	else
		print("Running")
	end
	if ctx.heldJob then
		print(("Executing job %q"):format(ctx.heldJob))
	end
end
