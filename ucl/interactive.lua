local tokenize = require('ucl.tokenize')
local env = require('ucl.env')

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

		local ok, rres = pcall(function()
			return self.engine:eval(ast)
		end)
		if ok then
			if rres ~= nil then
				print(rres)
			end
		else
			print(env.colorize('\n{red-fg}%s{/}\n', rres))
		end
	end

end

function interactive_mt:prompt()
	return self.buffer and "   " or "ucl"
end

function interactive_mt:info(s)
	local u, v = tokenize.value(s)
	local last = v
	local idx = 0
	local path = ">"
	while v do
		local ok = pcall(function()
			if v.type == "CList" then
				last = v
				v = v.cmdlist
				v = v[#v]
				path = path .. "C"
			elseif v.type == "List" then
				last = v
				v = v.list
				idx = #v
				v = v[idx]
				path = path .. "L"
			else
				error('out', 0)
			end
		end)
		if not ok then break end
	end
	if not v then v = last end
	--print("\n\n>>", path, v.string, last.type, idx)
	return {
		word = v.string,
		idx = idx,
		type = last.type
	}
end

function interactive_mt:complete(m, n)
	if m == nil then m = "" end

	local info
	if buffer then 
		info = self:info(self.buffer .. "\n" .. m)
	else
		info = self:info(m)
	end
	local target = info.word
	local t = self.engine.commands
	local words = {}
	while t do
		for k,v in pairs(t) do
			if k:sub(1, #target) == target then
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