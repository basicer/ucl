local Value = require 'ucl/value'

local ops = {
	['**'] = { pres = 14, apply = function(a,b) return math.pow(a,b) end },

	['*']  = { pres = 13, apply = function(a,b) return a * b end },
	['/']  = { pres = 13, apply = function(a,b) return a / b end },
	['%']  = { pres = 13, apply = function(a,b) return a % b end },

	['+']  = { pres = 12, apply = function(a,b) return a + b end },
	['-']  = { pres = 12, apply = function(a,b) return a - b end },
	
	['<<'] = { pres = 11, apply = function(a,b) return bit.lshift(a,b) end },
	['>>'] = { pres = 11, apply = function(a,b) return bit.arshift(a,b) end },

	['>']  = { pres = 10, apply = function(a,b) return a > b and 1 or 0 end },
	['<']  = { pres = 10, apply = function(a,b) return a < b and 1 or 0 end },
	['>='] = { pres = 10, apply = function(a,b) return a >= b and 1 or 0  end },
	['<='] = { pres = 10, apply = function(a,b) return a <= b and 1 or 0 end },

	['=='] = { pres = 09, apply = function(a,b) return a == b and 1 or 0 end },
	['!='] = { pres = 09, apply = function(a,b) return a ~= b and 1 or 0 end },


	['&&'] = { pres = 03, apply = function(a,b) return a and b and 1 or 0 end },
	['||'] = { pres = 02, apply = function(a,b) return a or b and 1 or 0 end },





}

local function climber(tokens, max)

	local acc

	local t = tokens.take()
	if t == '(' then 
		local sub, reason = climber(tokens, 0)
		if reason ~= ')' then error("Unbalanced parens", 0) end
		acc = tonumber(sub)
	elseif t == '-' then
	 	acc = 0 - climber(tokens, 10000)
	elseif t == '+' then
		acc = climber(tokens, 10000)
	else
		acc = tonumber(t)
	end

	if max == 10000 then return acc end


	while not tokens.done() do
		local t = tokens.peek()

		if t == ')' then
			tokens.take()
			return acc, ')' 
		end

		local op = ops[t]
		if not op then error("Unknown mathmatical operation: " .. t) end
		
		if op.pres < max then return acc end

		tokens.take()
		local right, reason = climber(tokens, op.pres - 1)
		acc = op.apply(acc, right)

		if reason == ')' then return acc, reason end

	end
	return acc, true
end

local function expr(code, state)
	if type(code) == "table" then
		code = code.string
	end

	local tokens = {}
	local i = 1
	while i <= #code do
		local a, b

		local sa, sb = code:find('^[%s\n]+', i)
		if sa then 
			i = sb + 1
		end

		if not a then a,b = code:find('^0x[0-9A-Fa-f]+', i) end
		if not a then a,b = code:find('^[0-9]+%.[0-9]*', i) end
		if not a then a,b = code:find('^[0-9]+', i) end
		if not a then a,b = code:find('^[!+%-%*/<>=()%%][<>=]?', i) end
		if not a then a,b = code:find('^[^%s]+', i) end

		if a then
			table.insert(tokens, code:sub(a,b))
			i = b + 1
		end

	end

	-- print('P', table.concat(tokens, ','))

	local idx = 1
	local tokens = {
		take = function()
			idx = idx + 1
			return tokens[idx - 1]
		end,
		peek = function() return tokens[idx] end,
		done = function() return idx > #tokens end 
	}

	local res, reason = climber(tokens, 0)
	if reason == ')' then assert('Unbalanced parens', 0) end
	return res
end




return expr