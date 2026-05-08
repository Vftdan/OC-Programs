local client = require "recipesched.client"
local api = client.getApi()
local items = api.items
local recipes = api.recipes

items.reload()
recipes.reload()
