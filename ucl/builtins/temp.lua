local env = require('ucl.env')
local Value = require('ucl.value')
local argparse = require('ucl.argparse')

local ReturnCode_Ok = 0
local ReturnCode_Error = 1
local ReturnCode_Return = 2
local ReturnCode_Break = 3
local ReturnCode_Continue = 4

local unpack = env.unpack
local ffi

return function(builtin)

function builtin.lua(interp, code)
	local fx, err = env.loadstring(code.string)
	local variables_proxy = setmetatable({}, {
		__index = function(self, k)
			local l =  interp.variables[k]
			return interp.variables[k].value
		end
	})
	if not fx then error(err, 0) end
	env.setfenv(fx, setmetatable({
		interp = interp,
		variables=variables_proxy,
		print=print,
		tokenize=require('ucl.tokenize').load,
		require=require,
		global=_G,
	}, {__index = _G}))
	return Value.from(fx())
end

local rx
local C
local readline = function(prompt)
	io.write(prompt)
	return io.read("*line")
end

local function add_history(s) end
local function read_history() end
local function write_history() end

local function load_replxx()
	rx = replxx.new()
	readline = function(s) return rx:input(s) end
	add_history = function(s) rx:history_add(s) end
end

local function load_ffi_readline(C)
	ffi.cdef[[
		char *readline(const char *);
		int	rl_initialize(void);
		int rl_attempted_completion_over;

		char * rl_line_buffer;


		typedef char **rl_completion_func_t (const char *, int, int);
		typedef char *rl_compentry_func_t (const char *, int);
		char **rl_completion_matches (const char *, rl_compentry_func_t *);
		rl_completion_func_t *rl_attempted_completion_function;

		void* malloc(size_t bytes);
		void free(void *);
		char * rl_completer_word_break_characters;

		void using_history(void);
		int add_history(const char *);
		int read_history(const char *filename);
		int write_history(const char *filename);

	]]

	
	
	local chars = " \t\n\"\\'`><=;|&{(["
	local c_str = ffi.new("char[?]", #chars)
	ffi.copy(c_str, chars)
	C.rl_completer_word_break_characters = c_str
	
	readline = function(prompt)
		local cstr = C.readline(prompt);
		if nil == cstr then return nil end
		local s = ffi.string(cstr);
		ffi.C.free(cstr)
		return s
	end

	add_history = function(s) return C.add_history(s) end
	write_history = function() return C.write_history(nil) end
	read_history = function() return C.read_history(nil) end
end

local rltype = 'gets'

if rawget(_G, "replxx") then
	load_replxx()
	rltype = 'replxx'
else
	local haveffi
	haveffi, ffi = pcall(require,'ffi')
	if haveffi then

		local ok
		ok, C = pcall(ffi.load, "readline")

		if ok then
			load_ffi_readline(C)
			rltype = 'readline'
		end
	end
end
rawset(_G, 'rltype', rltype)

function  builtin.read(interp, prompt)
	local interactive = interp.engine:interactive()
	if rx then
		rx:set_completion_callback(function(m, len, ...)
			local n = m:sub(-len)

			local words = interactive:complete(m, n)
			local out = {}
			for k,v in ipairs(words) do
				table.insert(out, Completion.new(v))
			end
			return out
		end)
		rx:set_hint_callback(function(text, len, ...)
			if #text > 14 then return {"faygo"} end
			if #text < 4 then return {} end
			return {
				text:sub(-len) .. " <- This is a hint: " .. table.concat({...}, "/"),
				"This is another hint",
				"Third hunt"
			}
		end)
	end

	if C then
		function C.rl_attempted_completion_function(word, startpos, endpos)
			C.rl_attempted_completion_over = 1
			local m = ffi.string(word)
			local buf = ffi.string(C.rl_line_buffer)

			local ll = ffi.string(C.rl_line_buffer)
			local words = interactive:complete(ll, word)

			local matcher = ffi.cast("rl_compentry_func_t*", function(text, idx) end)
			matcher:set(function(text, idx)
				if idx >= #words then
					return ffi.new('void*',nil)
				end
				local match = words[idx+1]
				local r = C.malloc(#match + 1)
				ffi.copy(r, match, #match + 1)
				return r
			end)
			return C.rl_completion_matches(word, matcher)
		end
	end


	interactive.add_history = add_history
	read_history()
	local r
	while true do
		local s = readline(env.colorize("{green-fg}%s>{/} ", prompt and prompt.string or interactive:prompt()))
		if s == nil then
			return Value.none, ReturnCode_Break
		end
		r = interactive:sline(s)
		if r then break end
	end
	write_history()
	if r ~= nil then 
		return Value.fromString(r)
	else
		return Value.none, ReturnCode_Break
	end
end

function builtin.loop(interp, body)
	local ret, retCode
	if not body then error("no body to loop?", 0) end
	while true do
		ret, retCode = interp:eval(body)
		if retCode == ReturnCode_Break then
			break;
		elseif retCode == ReturnCode_Continue then
		elseif retCode == ReturnCode_Ok then
		elseif retCode == nil then
		else
			return ret, retCode
		end
	end
	return Value.none
end

function builtin.print(interp, ...)
	print(...)
	return Value.none
end

end