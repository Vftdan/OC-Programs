local executor = require "recipesched.executor"

local FMT = "%1s %10s %25.25s %2d/%2d"

local function stateChar(job)
	if not job.created then
		return "*"
	elseif job.active then
		return ">"
	elseif job.finished then
		if job.success then
			return "V"
		else
			return "X"
		end
	end
	return " "
end

local function fmtArgs(id, job)
	return stateChar(job), id, job.name, job.lastStep, #job.steps
end

local function printJobList()
	for id, job in pairs(executor.jobRegistry) do
		print(FMT:format(fmtArgs(id, job)))
	end
end

local function printJobInfo(id)
	local job = executor.jobRegistry[id]
	if not job then
		print(("No such job: %q"):format(id))
		return
	end
	print(FMT:format(fmtArgs(id, job)))
	if job.finished and not job.success then
		print(job.reason)
	end
end

local id = ...
if id then
	printJobInfo(id)
else
	printJobList()
end
