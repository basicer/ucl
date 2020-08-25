local Value = require 'ucl.value'

local bit = _G.bit or _G.bit32 or require('bit32')
local unpack = table.unpack or _G.unpack


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


	['&&'] = { pres = 03, apply = function(a,b) return a ~= 0 and b ~= 0 and 1 or 0 end },
	['||'] = { pres = 02, apply = function(a,b) return a ~= 0 or b ~= 0 and 1 or 0 end },

	['&'] = { pres = 06, apply = bit.band },
	['|'] = { pres = 04, apply = bit.bor },

	['eq'] = { pres =07, apply = function(a,b) return a == b and 1 or 0 end },
	['ne'] = { pres =07, apply = function(a,b) return a ~= b and 1 or 0 end }
}

local mathfx = {
	acos  = math.acos,
	wide  = function(w) return w end,
	int   = function(n) return n - math.fmod(n, 1) end,
	round = function(f) return math.floor(0.5 + f) end,
	asin  = math.asin,
	atan  = math.atan,
	cos   = math.cos,
	cosh  = math.cosh,
	floor = math.floor,
	log   = math.log,
	fmod  = math.fmod,
	pow   = math.pow,
	sin   = math.sin,
	sinh  = math.sinh,
	ceil  = math.ceil,
	abs   = math.abs,
	tan   = math.tan,
	tanh  = math.tanh,
	exp   = math.exp,
	atan2 = math.atan2,
	log10 = math.log10,
	sqrt  = math.sqrt,
	hypot = function(a,b) return math.sqrt(a*a + b*b) end,
	double = tonumber,
	min = math.min,
	max = math.max,
	-- hypot = math.hypot,
}

local function climber(tokens, max, v)

	local acc

	local t = tokens.take()
	if type(t) == "table" then
		if t.type == "function" then
			local f = mathfx[t.name]

			if not f then error("unknown math function " .. t.name, 0) end
			local args = {}
			while not tokens.done() do
				local r, w = climber(tokens, 0)

				table.insert(args, r)
				if w ~= ',' then break end
			end
			acc = f(unpack(args))
		elseif t.type == "variable" then
			if not v.variables[t.name] then
				error('no such variable ' .. t.name, 0)
			end
			acc = v.variables[t.name].value.string
			acc = tonumber(acc) or acc
		elseif t.type == 'cmd' then
			acc = t.value:interp(v)
			acc = tonumber(acc.string) or acc.string
		end

	elseif t == '(' then
		local sub, reason = climber(tokens, 0, v)
		if reason ~= ')' then error("Unbalanced parens", 0) end
		acc = tonumber(sub)
	elseif t == '-' then
		acc = 0 - climber(tokens, 10000, v)
	elseif t == '+' then
		acc = climber(tokens, 10000, v)
	elseif t == '!' then
		acc = climber(tokens, 10000, v) == 0 and 1 or 0
	elseif t == '~' then
		acc = bit.bnot(climber(tokens, 10000, v))
	else
		acc = tonumber(t) or t
	end

	if max == 10000 then return acc end


	while not tokens.done() do
		local t = tokens.peek()

		if t == ')' or t == ',' then
			tokens.take()
			return acc, t
		end

		local op = ops[t]
		if not op then error("Unknown mathmatical operation: " .. t, 0) end

		if op.pres < max then return acc end

		tokens.take()
		local right, reason = climber(tokens, op.pres + 1, v)
		acc = op.apply(acc, right)

		if reason then return acc, reason end

	end
	return acc, true
end


local function expr(code, state)
	local tokens
	if type(code) == "table" then
		tokens = code.expr_tokens
	else
		tokens = require('ucl.tokenize').expr(code)
	end

	--code = Value.fromXString(code):interp(state).string
	--print("TOKENS", unpack(tokens))

	local idx = 1
	local tks = {
		take = function()
			idx = idx + 1
			return tokens[idx - 1]
		end,
		peek = function() return tokens[idx] end,
		done = function() return idx > #tokens end
	}

	local res, reason = climber(tks, 0, state)
	if reason == ')' then assert('Unbalanced parens', 0) end
	return res
end




return {
	expr = expr
}