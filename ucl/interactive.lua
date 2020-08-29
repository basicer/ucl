local tokenize = require('ucl.tokenize')

local interactive_mt = {}

function interactive_mt:line(s)
	if not self.buffer then
		self.buffer = s
	else
		self.buffer = self.buffer .. "\n" .. s
	end

	local u, ast = tokenize.value(self.buffer)
	if #u.errors == 0 then
		if self.add_history then
			self.add_history(self.buffer)
		end
		self.buffer = false

		local _, rres = pcall(function()
			return self.engine:eval(ast)
		end)
		if rres ~= nil then
			print(rres)
		end
	end

end

function interactive_mt:prompt()
	return self.buffer and "   " or "ucl"
end

function interactive_mt:complete(m)
	local t = self.engine.commands
	local words = {}
	while t do
		for k,v in pairs(t) do
			if k:sub(1, #m) == m then
				table.insert(words, k)
			end
		end
		t = getmetatable(t)
		if t then t = t.__index end
	end
	return words
end

local function new(engine)
	return setmetatable({
		buffer = false,
		engine = engine,
	}, {__index=interactive_mt})
end


return {new=new}