local client = require "recipesched.client"
local api = client.getApi()
local executor = api.executor

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
	for _, id in ipairs(executor.getJobList()) do
		local job = executor.getJobInfo(id)
		print(FMT:format(fmtArgs(id, job)))
	end
end

local function printJobInfo(id)
	local job = executor.getJobInfo(id)
	if not job then
		print(("No such job: %q"):format(id))
		return
	end
	print(FMT:format(fmtArgs(id, job)))
	if job.finished and not job.success then
		print(job.reason)
	end
	for i, step in ipairs(job.steps) do
		print(("%1s %2d %s"):format((i > job.lastStep and " " or "V"), i, step.name))
	end
end

local id = ...
if id then
	printJobInfo(id)
else
	printJobList()
end
