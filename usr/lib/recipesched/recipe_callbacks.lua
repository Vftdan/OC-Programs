return {
	craft = function(ctx, args, amount)
		ctx.driver.craftersvc.craft(args.grid, amount)
	end,
}
