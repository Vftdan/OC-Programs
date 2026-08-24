return {
	craft = function(ctx, args, amount)
		ctx.driverFeature.craft.craft(args.grid, amount)
	end,
	deliver = function(ctx, args, amount)
		local order = {}
		for _, entry in ipairs(args.cart) do
			table.insert(order, {ref = entry.item, amount = amount * entry.amount})
		end
		ctx.driverFeature.delivery.deliver(ctx.node.localName, order)
	end,
	noop = function(ctx, args, amount)
	end,
}
