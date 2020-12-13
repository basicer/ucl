--luacheck: no unused

local tokenize = require('ucl.tokenize')
local env = require('ucl.env')

local function colorize(fmt, ...)
	local text = fmt:gsub("{([^{}}]+)}", function(k)
		local codes = {
			['normal'] = "\027[0",
			['bold']   = "\027[1",
			['dim']    = "\027[2",
			['i']      = "\027[3",
			['u']      = "\027[4",
			['blink']  = "\027[5",
			['inverse']= "\027[7",

			['black-fg']   = "\027[30m",
			['red-fg']     = "\027[31m",
			['green-fg']   = "\027[32m",
			['yellow-fg']  = "\027[33m",
			['blue-fg']    = "\027[34m",
			['magenta-fg'] = "\027[35m",
			['cyan-fg']    = "\027[36m",
			['white-fg']   = "\027[37m",
			['default-fg'] = "\027[37m",
			['gray-fg']    = "\027[90m",
			
			['crimson-fg']    = "\027[91m",
			['lime-fg']       = "\027[92m",
			['gold-fg']       = "\027[93m",
			['purple-fg']     = "\027[94m",
			['pink-fg']       = "\027[95m",
			['turquoise-fg']  = "\027[96m",
			['bright-fg']     = "\027[97m",


			['black-bg']   = "\027[40m",
			['red-bg']     = "\027[41m",
			['green-bg']   = "\027[42m",
			['yellow-bg']  = "\027[43m",
			['blue-bg']    = "\027[44m",
			['magenta-bg'] = "\027[45m",
			['cyan-bg']    = "\027[46m",
			['white-bg']   = "\027[47m",
			['default-bg'] = "\027[47m",

			['/'] =  "\027[0m"
		}
		if env.color then
			return codes[k]
		elseif codes[k] then
			return ''
		end
	end):format(...)
	if env.color then
		return text .. "\027[0m"
	else
		return text
	end
end

local interactive_mt = {}

function interactive_mt:colorize(...)
	return colorize(...)
end

function interactive_mt:sline(s)
	if s then
		if not self.buffer then
			self.buffer = s
		else
			self.buffer = self.buffer .. "\n" .. s
		end
	end

	if not self.buffer then return false end
	local u, ast = tokenize.value(self.buffer)
	if #u.errors == 0 then
		if self.add_history then
			self.add_history(self.buffer)
		end
		local line = self.buffer
		self.buffer = false
		return line
	end
	return false
end

function interactive_mt:line(s)
	local r = self:sline(s)
	if not r then return false end
	local ok, rres = pcall(function()
		return self.engine:eval(r)
	end)
	if ok then
		if rres ~= nil then
			print(rres)
		end
	else
		print(colorize('\n{red-fg}%s{/}\n', rres))
	end
end

function interactive_mt:prompt()
	return self.buffer and "   " or "ucl"
end

function interactive_mt:info(s)
	local _, v = tokenize.value(s)
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
	if self.buffer then
		info = self:info(self.buffer .. "\n" .. m)
	else
		info = self:info(m)
	end
	local target = info.word
	local t = self.engine.commands
	local words = {}
	while t do
		for k,_ in pairs(t) do
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



function interactive_mt:banner()
	local banner = {
		version = "0.3",
		load = env.loadstring and "+" or "-",
		bits = pcall(env.bit.band, 1, 1) and "+" or "-",
		lua = env.lua,
		rltype = _G.rltype,
		os = env.os
	}

	if env.tty then
		local str = (([[
	                               |
	                       ##      |  Micro Command Language
	     ##  ##    #####   ##      |
	     ##  ##    ##      ##      |  Version: ${version}
	     ######    #####   ####    |  ${lua} ${bits}bit ${load}load ${rltype}
	         ###                   |
	                               |
		]]):gsub('%${([^}]+)}', function(k)
			return banner[k]
		end))

		return colorize(str:gsub("#", "{cyan-fg}{cyan-bg}#{/}"))
	end
end

return {new=new, colorize=colorize}