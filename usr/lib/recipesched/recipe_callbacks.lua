return {
	craft = function(ctx, args, amount)
		ctx.driver.craftersvc.craft(args.grid, amount)
	end,
	ddrone_deliver = function(ctx, args, amount)
		local order = {}
		for _, entry in ipairs(args.cart) do
			table.insert(order, {ref = entry.item, amount = amount * entry.amount})
		end
		ctx.driver.delivery.deliverDrone(args.destination, order)
	end,
	wired_deliver = function(ctx, args, amount)
		local order = {}
		for _, entry in ipairs(args.cart) do
			table.insert(order, {ref = entry.item, amount = amount * entry.amount})
		end
		ctx.driver.delivery.deliverWired(args.destination, order)
	end,
}
