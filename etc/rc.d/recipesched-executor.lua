local executor = require "recipesched.executor"
local thread = require "thread"

local ctx, thr
local shouldRun = false

local onExit

function start()
	shouldRun = true
	if not ctx then
		ctx = executor.makeExecutorContext()
		ctx.onKill = onExit
	else
		ctx.running = true
	end
	if not thr or thr:status() == "dead" then
		local oldCtx = ctx
		thr = thread.create(function()
			executor.executorEntry(oldCtx)
			onExit(oldCtx)
		end)
		thr:detach()
	elseif thr:status() == "suspended" then
		thr:resume()
	end
end

function onExit(oldCtx)
	if oldCtx ~= ctx then
		return
	end
	ctx = nil
	thr = nil
	if shouldRun then
		start()
	end
end

function stop()
	shouldRun = false
	if ctx then
		executor.stopExecutor(ctx)
	end
end

function kill()
	shouldRun = false
	if ctx then
		executor.stopExecutor(ctx, true)
	end
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
		return
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
