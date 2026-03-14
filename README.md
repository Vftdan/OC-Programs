## Client

### Installation

 - Ensure that `minitel` and `mtrpc` are installed
 - Install the files specified in [.client.files.txt](.client.files.txt)
 - Create a file named `/etc/recipesched/client.cfg` with contents of the form:

```lua
server = "SERVER_HOSTNAME"
```

### Interface

#### Command-line

 - `recipesched-craft-item <ITEM_NAME> <[AMOUNT=1]>` try to schedule a craft of at lest AMOUNT items specified in the server's `items.cfg`
 - `recipesched-jobs` list all scheduled jobs with brief information
 - `recipesched-jobs <JOB_ID>` show an extended information for a specific job
 - `recipesched-reload` ask the server to re-read its `items.cfg` and `recipes.cfg`

#### API

Get the API table via:

```lua
local client = require "recipesched.client"
local api = client.getApi()
```

Methods:

 - `api.items.reload(): boolean` ask the server to re-read its `items.cfg`, returns `true` on success
 - `api.items.getRegistryElement(name: string): Item` get the item table by its registry name
 - `api.items.getRegistryKeys(): string[]` get an array with all registered item names
 - `api.recipes.reload(): boolean` ask the server to re-read its `recipes.cfg`, returns `true` on success
 - `api.recipes.getRegistryElement(name: string): Recipe` get the recipe table by its registry name
 - `api.recipes.getRegistryKeys(): string[]` get an array with all registered recipe names
 - `api.planner.planForItem(name: string[, amount=1: number]): Plan` calculate a table with a crafting plan for at least the specified number of the specified item
 - `api.executor.registerJobFromPlan(plan: Plan): string, number` add a crafring job corresponding to the plan and add to the scheduler queue, returns the job id and the current position in the queue
 - `api.executor.getJobInfo(id: string): Job` get a deep copy of the job by its id without irrelevant/non-serializeable fields
 - `api.executor.getJobList(): string[]` get an array with all not yet deleted job ids
