local executor = require "recipesched.executor"
local planner = require "recipesched.planner"
local stock = require "recipesched.stock"
local thread = require "thread"

local JOB_POLL_DELAY = 10
local JOB_SUCCESS_DELAY = 5
local JOB_FAILURE_DELAY = 120

local lastStatus = "Not started"
local thr = nil
local shouldRun = false

local function trigger()
	local request = stock.composePlanRequest()
	if #request == 0 then
		return false
	end
	local plan = planner.planComplex(request)
	if not plan.success then
		error("Plan failure: " .. plan.reason)
	end
	local jobId = executor.registerJobFromPlan(plan)
	lastStatus = ("Polling job %q"):format(jobId)
	while shouldRun do
		local job = executor.getJobInfo(jobId)
		if job.finished then
			if not job.success then
				error(("Job %q execution failure: %s"):format(jobId, job.reason))
			end
			return true
		end
		os.sleep(JOB_POLL_DELAY)
	end
end

function start()
	shouldRun = true
	if not thr or thr:status() == "dead" then
		lastStatus = "Starting"
		thr = thread.create(function()
			while shouldRun do
				local ok, reason = pcall(trigger)
				if not ok then
					lastStatus = reason
				else
					if reason then
						lastStatus = "Success"
					else
						lastStatus = "Nothing to do"
					end
				end
				if shouldRun then
					os.sleep(ok and JOB_SUCCESS_DELAY or JOB_FAILURE_DELAY)
				end
			end
			lastStatus = "Stopped"
		end)
		thr:detach()
	elseif thr:status() == "suspended" then
		thr:resume()
	end
end

function stop()
	shouldRun = false
	lastStatus = "Stopping"
end

function status()
	if not thr then
		print("Not started")
		return
	end
	local s = thr:status()
	if s == "suspended" then
		print("Suspended?")
	elseif s == "dead" then
		if shouldRun then
			print("Dead")
		else
			print("Stopped")
		end
	else
		print(lastStatus)
	end
end
