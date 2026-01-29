return {
	load = function(name)
		return require ("recipesched.driver." .. name)
	end,
}
