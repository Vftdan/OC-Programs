local unicode = require "unicode"
local event = require "event"
local mtmenu = require "mtmenu"
local client = require "recipesched.client"
local api = client.getApi()

local planner = api.planner
local executor = api.executor
local items = api.items

local timers = {}

local jobCache = {}
local jobListCache = nil
local itemCache = {}
local itemListCache = nil

local function getJobInfo(id)
	local job = jobCache[id]
	if job then
		return job
	end
	job = executor.getJobInfo(id)
	jobCache[id] = job
	return job
end

local function getJobList()
	if jobListCache then
		return jobListCache
	end
	jobListCache = executor.getJobList()
	return jobListCache
end

-- TODO expose more generic items.lookupStacks and/or items.nameToSpecList
local function getItemInfo(key)
	local item = itemCache[key]
	if item then
		return item
	end
	item = items.getRegistryElement(key)
	itemCache[key] = item
	return item
end

local function getItemList()
	if itemListCache then
		return itemListCache
	end
	itemListCache = items.getRegistryKeys()
	return itemListCache
end

local function updateCache()
	jobListCache = executor.getJobList() or jobListCache
	for k, v in pairs(jobCache) do
		jobCache[k] = executor.getJobInfo(k) or v
	end
end

timers.cacheUpdate = event.timer(15, updateCache, math.huge)

local function wsub(ustr, beg, ed)
	ed = ed or -1
	if beg < 0 then
		beg = beg + 1 + unicode.wlen(ustr)
	end
	if ed < 0 then
		ed = ed + 1 + unicode.wlen(ustr)
	end
	while true do
		local amount = unicode.wlen(ustr) - ed
		if amount < 1 then
			break
		end
		ustr = unicode.sub(ustr, 1, -1 - amount)
	end
	local tw = ed - beg + 1
	while true do
		local amount = unicode.wlen(ustr) - tw
		if amount < 1 then
			break
		end
		ustr = unicode.sub(ustr, 1 + amount)
	end
	return ustr
end

local function concatRow(cells, colWidhs, sepWidths)
	local builder = {}
	for i, w in ipairs(colWidhs) do
		if i > 1 then
			table.insert(builder, (" "):rep(sepWidths[i - 1]))
		end
		local cell = tostring(cells[i])
		local defect = w - unicode.wlen(cell)
		if defect > 0 then
			cell = cell .. (" "):rep(defect)
		elseif defect < 0 then
			cell = wsub(cell, 1, w)
		end
		table.insert(builder, cell)
	end
	return table.concat(builder)
end

local function formatEntries(objs, cols, fieldsfmtf, footLeft, footRight)
	local width, height = mtmenu.getScreenSize()
	width = width - 1
	local minWidthSum, maxWidthSum, ncols = 0, 0, 0
	local actualWidths = {}
	local sepWidths = {}
	for _, col in ipairs(cols) do
		ncols = ncols + 1
		local w = col.width
		local mw = col.minWidth or w
		actualWidths[ncols] = w
		maxWidthSum = maxWidthSum + w
		minWidthSum = minWidthSum + mw
	end
	assert(ncols > 0)
	maxWidthSum = maxWidthSum + ncols - 1
	local extraSpace = width - maxWidthSum
	local maxExtraSpace = width - minWidthSum
	if extraSpace < ncols - 1 then
		if maxExtraSpace >= ncols - 1 then
			-- Shrink until we have 1 space between each column
			local remaining = ncols - 1 - extraSpace
			while remaining > 0 do
				for i, col in ipairs(cols) do
					if remaining < 1 then
						break
					end
					local mw = col.minWidth or col.width
					if actualWidths[i] > mw then
						actualWidths[i] = actualWidths[i] - 1
						remaining = remaining - 1
						extraSpace = extraSpace + 1
					end
				end
			end
		else
			-- Shrink maximally
			for i, col in ipairs(cols) do
				local mw = col.minWidth or col.width
				extraSpace = extraSpace + actualWidths[i] - mw
				actualWidths[i] = mw
			end
		end
	end
	if extraSpace < 0 then
		-- Shrink past minimal width towards uniform widths
		local remaining = -extraSpace
		local target = math.floor((minWidthSum - remaining) / ncols)
		for i in ipairs(cols) do
			local amount = actualWidths[i] - target
			if amount > 0 then
				if amount > remaining then
					amount = remaining
				end
				extraSpace = extraSpace + amount
				actualWidths[i] = actualWidths[i] - amount
				remaining = remaining - amount
			end
		end
	end
	if ncols > 1 then
		local sepWidth = math.floor(extraSpace / (ncols - 1))
		for i = 1, ncols - 2 do
			sepWidths[i] = sepWidth
		end
		sepWidths[ncols - 1] = extraSpace - sepWidth * (ncols - 2)
	end
	local result = {}
	local thead = {}
	for i = 1, ncols do
		thead[i] = cols[i].name
	end
	result.header = concatRow(thead, actualWidths, sepWidths)
	for i, obj in ipairs(objs) do
		local fields = fieldsfmtf(obj)
		local row = {}
		for j = 1, ncols do
			row[j] = fields[cols[j].key]
		end
		result[i] = concatRow(row, actualWidths, sepWidths)
	end
	local footWidths = {unicode.wlen(footLeft), unicode.wlen(footRight)}
	local footSepWidth = width - footWidths[1] - footWidths[2]
	for i = 1, 2 do
		if footSepWidth < 0 then
			local old = footWidths[i]
			local amount = math.min(old, -footSepWidth)
			footWidths[i] = old - amount
			footSepWidth = footSepWidth + amount
		end
	end
	result.status = concatRow({footLeft, footRight}, footWidths, {footSepWidth})
	return result
end

local function showAlert(text, title)
	mtmenu.popup(("\n%s\n\nPress any key."):format(tostring(text)), title or "Alert")
	event.pull("key_down")
end

local function showConfirm(text, title)
	while true do
		mtmenu.popup(("\n%s\n\nPress y/n."):format(tostring(text)), title or "Confirm")
		local _, _, ch = event.pull("key_down")
		ch = string.char(ch or 0)
		if ch == "y" or ch == "Y" then
			return true
		elseif ch == "n" or ch == "N" then
			return false
		end
	end
end

local function showKeys(kvs)
	local leftWidth = 0
	for _, kv in ipairs(kvs) do
		leftWidth = math.max(leftWidth, unicode.wlen(kv[1]))
	end
	leftWidth = leftWidth + 3
	local lines = {}
	for _, kv in ipairs(kvs) do
		table.insert(lines, ("[%s]%s%s"):format(kv[1], (" "):rep(leftWidth - unicode.wlen(kv[1])), kv[2]))
	end
	showAlert(table.concat(lines, "\n"), "Key bindings")
end

local function alertPcall(f, ...)
	local result = table.pack(pcall(f, ...))
	if not result[1] then
		showAlert(result[2], "Error")
		return false
	end
	return table.unpack(result, 1, result.n)
end

local function confirmRetryLoopPcall(f, ...)
	while true do
		local result = table.pack(pcall(f, ...))
		if result[1] then
			return table.unpack(result, 1, result.n)
		end
		if not showConfirm(result[2], "Error, retry?") then
			return false
		end
	end
end

local function jobStateChar(job)
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

local function jobStateName(job)
	if not job.created then
		return "Compilation"
	elseif job.active then
		return "Running"
	elseif job.finished then
		if job.success then
			return "Success"
		else
			return ("Error: %s"):format(tostring(job.reason))
		end
	end
	return "Scheduled"
end

local colums = {}
local scenes = {}
local formatters = {}

local function showItemInfo(itemName)
	local item = getItemInfo(itemName)
	local lines = {}
	if not item then
		table.insert(lines, "Item unknown")
	else
		local kind = item.kind
		table.insert(lines, "Kind: " .. tostring(kind))
		if kind == "stack" then
			local stack = item.value
			if stack.label then
				table.insert(lines, "Visible name: " .. tostring(stack.label))
			end
			if stack.name then
				table.insert(lines, "MC id: " .. tostring(stack.name))
			end
			if stack.damage then
				table.insert(lines, "Damage: " .. tostring(stack.damage))
			end
			if stack.maxSize then
				table.insert(lines, "Stacks to: " .. tostring(stack.maxSize))
			end
		end
	end
	showAlert(table.concat(lines, "\n"), "Item information")
end

local function craftItem(itemName)
	local amount = tonumber(mtmenu.popupEntry("Amount of items:", "Crafting"))
	if not amount then
		showAlert("Cancelled")
		return
	end
	local plan = planner.planForItem(itemName, amount)
	if not plan.success then
		if showConfirm(tostring(plan.reason) .. "\nShow missing inputs?", "Plan failure") then
			scenes.failedPlan(plan)
		end
		return
	end
	local jobId, queuePos = executor.registerJobFromPlan(plan)
	jobListCache = nil
	showAlert(("Created job %s, position in queue #%d"):format(jobId, queuePos))
end

colums.jobs = {
	{name = "", key = "state", width = 1},
	{name = "Id", key = "id", width = 10},
	{name = "Item", key = "name", width = 80, minWidth = 8},
	{name = "Step", key = "step", width = 5},
}

function formatters.jobs(job)
	return {state = jobStateChar(job), id = job.id, name = job.name, step = ("%2d/%2d"):format(job.lastStep, #job.steps)}
end

function scenes.jobs()
	local running = true
	local cursor, char, key, state
	while running do
		local entries = {}
		for _, id in ipairs(getJobList()) do
			table.insert(entries, getJobInfo(id))
		end
		cursor, char, key, state = mtmenu.menu(formatEntries(entries, colums.jobs, formatters.jobs, ("%d Jobs"):format(#entries), "[H]elp"), state)
		local entry = nil
		if cursor and cursor > 0 and cursor <= #entries then
			entry = entries[cursor]
		end
		if key == 28 then
			if entry then
				alertPcall(scenes.jobInfo, entry)
			end
		elseif char == "h" then
			showKeys{
				{"Enter", "Open extended job info"},
				{"c", "Open item craft menu"},
				{"q", "Quit"},
			}
		elseif char == "c" then
			alertPcall(scenes.items)
		elseif char == "q" then
			running = false
		end
	end
end

colums.jobInfo = {
	{name = "", key = "state", width = 1},
	{name = "#", key = "index", width = 2},
	{name = "Recipe", key = "name", width = 80, minWidth = 3},
}

function formatters.jobInfo(stepInfo)
	return stepInfo
end

function scenes.jobInfo(job)
	local running = true
	local _, char, key, state
	while running and job do
		local entries = {}
		for i, step in ipairs(job.steps) do
			table.insert(entries, {index = i, state = i > job.lastStep and " " or "V", name = step.name})
		end
		_, char, key, state = mtmenu.menu(formatEntries(entries, colums.jobInfo, formatters.jobInfo, ("%d/%d Steps (%s)"):format(job.lastStep, #entries, jobStateName(job)), "[H]elp"), state)
		if char == "h" then
			showKeys{
				{"r", "Reload"},
				{"q", "Back"},
			}
		elseif char == "r" then
			jobCache[job.id] = nil
			job = getJobInfo(job.id)
		elseif char == "q" then
			running = false
		end
	end
end

colums.items = {
	{name = "Registry name", key = "key", width = 80, minWidth = 13},
	-- {name = "Kind", key = "kind", width = 8, minWidth = 4},
}

function formatters.items(entry)
	local value = entry.value
	return {key = entry.key, kind = value and value.kind or "?"}
end

function scenes.items()
	local running = true
	local cursor, char, key, state
	while running do
		local entries = {}
		for _, itemName in ipairs(getItemList()) do
			table.insert(entries, {key = itemName, value = itemCache[itemName]})  -- do not fetch the info yet
		end
		cursor, char, key, state = mtmenu.menu(formatEntries(entries, colums.items, formatters.items, ("%d Items defined"):format(#entries), "[H]elp"), state)
		local entry = nil
		if cursor and cursor > 0 and cursor <= #entries then
			entry = entries[cursor]
		end
		if key == 28 then
			if entry then
				alertPcall(craftItem, entry.key)
			end
		elseif char == "h" then
			showKeys{
				{"Enter", "Request item crafting"},
				{"i", "Show item information"},
				{"q", "Back"},
			}
		elseif char == "i" then
			if entry then
				alertPcall(showItemInfo, entry.key)
			end
		elseif char == "q" then
			running = false
		end
	end
end

colums.failedPlan = {
	{name = "Registry name", key = "item", width = 80, minWidth = 13},
	{name = "Missing amount", key = "amount", width = 15, minWidth = 14},
}

function formatters.failedPlan(entry)
	return entry
end

function scenes.failedPlan(plan)
	local running = true
	local cursor, char, key, state
	while running do
		local entries = plan.missingItems
		cursor, char, key, state = mtmenu.menu(formatEntries(entries, colums.failedPlan, formatters.failedPlan, ("Plan failure: %s"):format(plan.reason), "[H]elp"), state)
		local entry = nil
		if cursor and cursor > 0 and cursor <= #entries then
			entry = entries[cursor]
		end
		if char == "h" then
			showKeys{
				{"Enter", "Request item crafting"},
				{"i", "Show item information"},
				{"q", "Back"},
			}
		elseif char == "i" then
			if entry then
				alertPcall(showItemInfo, entry.item)
			end
		elseif char == "q" then
			running = false
		end
	end
end

confirmRetryLoopPcall(scenes.jobs)
for _, v in pairs(timers) do
	event.cancel(v)
end
