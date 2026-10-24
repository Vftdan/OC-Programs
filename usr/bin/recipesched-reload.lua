local client = require "recipesched.client"
local api = client.getApi()
local items = api.items
local recipes = api.recipes
local infra = api.infra
local stock = api.stock

items.reload()
recipes.reload()
infra.reload()
stock.reload()
