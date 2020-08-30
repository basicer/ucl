local ucl = require 'ucl'
local env = require 'ucl.env'
local ffi

local readline = function(prompt)
	io.write(prompt)
	return io.read("*line")
end

local function add_history(s) end
local function read_history() end
local function write_history() end


local i = ucl.new()
i.flags.jit = 0
local interactive = i:interactive()

local function load_replxx()
	local rx = replxx.new()
	readline = function(s) return rx:input(s) end
	add_history = function(s) rx:history_add(s) end
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

	local matcher = ffi.cast("rl_compentry_func_t*", function(text, idx) end)
	
	local chars = " \t\n\"\\'`><=;|&{(["
	local c_str = ffi.new("char[?]", #chars)
	ffi.copy(c_str, chars)
	C.rl_completer_word_break_characters = c_str
	
	function C.rl_attempted_completion_function(word, startpos, endpos)
		C.rl_attempted_completion_over = 1
		local m = ffi.string(word)
		local buf = ffi.string(C.rl_line_buffer)

		local ll = ffi.string(C.rl_line_buffer)
		local words = interactive:complete(ll, word)

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

		local ok, C = pcall(ffi.load, "readline")

		if ok then
			load_ffi_readline(C)
			rltype = 'readline'
		end
	end
end

if arg[1] then
	i:eval(io.open(arg[1], 'r'):read("*a"))
	os.exit()
end

interactive.add_history = add_history
read_history()

local banner = {
	version = "0.1",
	load = env.loadstring and "+" or "-",
	bits = env.bit and "+" or "-",
	lua = env.lua,
	rltype = rltype,
	os = env.os
}

if env.tty then
	local banner = (([[

                               |
                       ##      |  Micro Command Language
     ##  ##    #####   ##      |
     ##  ##    ##      ##      |  Version: ${version}
     ######    #####   ####    |  ${lua} ${bits}bit ${load}load ${rltype}
         ###                   |

	]]):gsub('%${([^}]+)}', function(k)
		return banner[k]
	end))

	banner = env.colorize(banner:gsub("#", "{cyan-fg}{cyan-bg}#{/}"))
	print(banner)
end

repeat
	local line = readline(env.colorize("{green-fg}%s>{/} ", interactive:prompt()))
	if line ~= nil then
		interactive:line(line)
	end
until line == nil

print()
write_history()

