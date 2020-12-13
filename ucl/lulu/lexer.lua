local Value = require('ucl.value')
local env = require('ucl.env')

local StringView = {}

local Token = {
    Name = 1,
    String = 2,
    Comment = 3,
    Number = 4,
    OpenBracket = 5,
    CloseBracket = 6,
    OpenParen = 7,
    CloseParen = 8,
    OpenBrace = 9,
    CloseBrace = 10,
    Operator = 11,
    Semicolon = 12,
    Comma = 13,
    Colon = 14,
    Dot = 15,
    Elipse = 16,
    Equals = 17,
    Hash = 18,
    Minus = 19,

    And = 20,
    Break = 21,
    Do = 22,
    Else = 23,
    ElseIf = 24,
    End = 25,
    False = 26,
    For = 27,
    Function = 28,
    Goto = 29,
    If = 30,
    In = 31,
    Local = 32,
    Nil = 33,
    Not = 34,
    Or = 35,
    Repeat = 36,
    Return = 37,
    Then = 38,
    True = 39,
    Until = 40,
    While = 41,

    EOF = -1
}


local token_names = {
    [Token.Name] = "Name",
    [Token.String] = "String",
    [Token.Comment] = "Comment",
    [Token.Number] = "Number",
    [Token.OpenBracket] = "[",
    [Token.CloseBracket] = "]",
    [Token.OpenBrace] = "{",
    [Token.CloseBrace] = "}",
    [Token.OpenParen] = "(",
    [Token.CloseParen] = ")",
    [Token.Operator] = "Operator",
    [Token.Semicolon] = ";",
    [Token.Comma] = ",",
    [Token.Colon] = ":",
    [Token.Dot] = ".",
    [Token.Elipse] = "Elipse",
    [Token.Equals] = "=",
    [Token.Hash] = "#",
    [Token.Minus] = "-",

    [Token.And] = 'and',
    [Token.Break] = 'break',
    [Token.Do] = 'do',
    [Token.Else] = 'else',
    [Token.ElseIf] = 'elseif',
    [Token.End] = 'end',
    [Token.False] = 'false',
    [Token.For] = 'for',
    [Token.Function] = 'function',
    [Token.Goto] = 'goto',
    [Token.If] = 'if',
    [Token.In] = 'in',
    [Token.Local] = 'local',
    [Token.Nil] = 'nil',
    [Token.Not] = 'not',
    [Token.Or] = 'or',
    [Token.Repeat] = 'repeat',
    [Token.Return] = 'return',
    [Token.Then] = 'then',
    [Token.True] = 'true',
    [Token.Until] = 'until',
    [Token.While] = 'while',

    [Token.EOF] = 'EOF'
}


local state_mt = {}
function state_mt:peek()
	return self.source:sub(self.pos, self.pos), self.pos
end
function state_mt:done()
	return self.pos > self.right
end
function state_mt:eat(c)
    if self:peek() == c then 
        self.pos = self.pos + 1
        return true
    end
    return false
end
function state_mt:consumep(p)
	local m = {string.find(self.source, "^" .. p, self.pos)}
	if not m[1] then return false end
	local v = {self.source, m[1], m[2]}
	self.pos = m[2] + 1
	return v, select(2, env.unpack(m))
end
function state_mt:ws()
    return self:consumep("%s*")
end

local simple_tokens = {
    ['('] = Token.OpenParen,
    [')'] = Token.CloseParen,
    ['{'] = Token.OpenBrace,
    ['}'] = Token.CloseBrace,
    [':'] = Token.Colon,
    [','] = Token.Comma,
    [';'] = Token.Semicolon,
    ['#'] = Token.Hash,
}


local keywords = {
    ['and'] = Token.And,
    ['break'] = Token.Break,
    ['do'] = Token.Do,
    ['else'] = Token.Else,
    ['elseif'] = Token.ElseIf,
    ['end'] = Token.End,
    ['false'] = Token.False,
    ['for'] = Token.For,
    ['function'] = Token.Function,
    ['goto'] = Token.Goto,
    ['if'] = Token.If,
    ['in'] = Token.In,
    ['local'] = Token.Local,
    ['nil'] = Token.Nil,
    ['not'] = Token.Not,
    ['or'] = Token.Or,
    ['repeat'] = Token.Repeat,
    ['return'] = Token.Return,
    ['then'] = Token.Then,
    ['true'] = Token.True,
    ['until'] = Token.Until,
    ['while'] = Token.While
}

local function next_token(s)
    local t = s:ws()
    local l = s.pos
    local c = s:peek()

    if s:done() then return false end

    local stk = simple_tokens[c]
    if stk then
        s.pos = s.pos + 1
        return {stk, l, l}
    elseif s:eat("=") then
        if s:eat("=") then
            return {Token.Operator, l, s.pos-1}
        end
        return {Token.Equals, l, l}
    elseif s:consumep("[0-9]+") then
        s:consumep("%.[0-9]+")
        return {Token.Number, l, s.pos-1}
    elseif s:eat("'") then
        while not s:done() do
            if s:eat("'") then break end
            if s:eat("\\") then s.pos = s.pos + 1 end
            s.pos = s.pos + 1
        end
        return {Token.String, l, s.pos-1, os=1, oe=1}
    elseif s:eat('"') then
        while not s:done() do
            if s:eat('"') then break end
            if s:eat("\\") then s.pos = s.pos + 1 end
            s.pos = s.pos + 1
        end
        return {Token.String, l, s.pos-1, os=1, oe=1}
    elseif s:eat("[") then
        if s:eat("[") then
            s:eat("\n")
            local os=s.pos-l

            while true do
                if s:done() then error('Unterminated [[ string', 0) end
                if s:eat(']') and s:eat("]") then break end
                s.pos = s.pos + 1
            end
            return {Token.String, l, s.pos-1, os=os, oe=2}
        end
        return {Token.OpenBracket, l, l}
    elseif s:eat("]") then
        return {Token.CloseBracket, l, l}
    elseif s:eat("-") then
        if s:eat("-") then
            -- Single Line Comment
            while s:peek() ~= "\n" and not s:done() do s.pos = s.pos + 1 end
            return {Token.Comment, l, s.pos-1}
        end
        return {Token.Minus, l, l}
    elseif s:eat(".") then
        if s:eat(".") then
            if s:eat(".") then return {Token.Elipse, l, l + 2} end
            return {Token.Operator, l, l + 1}
        end
        return {Token.Dot, l, l}
    elseif s:eat("*") or s:eat("/") or s:eat("+")  or s:eat("^") then
        return {Token.Operator, l, l}
    end

    local w = s:consumep("[a-zA-Z_][a-zA-Z_0-9]*")
    if w then
        local ww = w[1]:sub(w[2],w[3])
        if keywords[ww] then return {keywords[ww], l, s.pos-1} end
        return {Token.Name, l, s.pos-1}
    end
    error('Cant tokenize:' .. s.source:sub(s.pos))
end

local function find_lines(code)
    local line_offsets = {}
    local offset = 1
    while true do
        local found, o = string.find(code, "\n", offset, true)
        if found then
            table.insert(line_offsets, 1, o)
            offset = o+1
        else break end
    
    end
    return line_offsets
end

local function tokenize(code)
    if type(code) ~= "string" then code = tostring(code) end

    local s = setmetatable({
        source = code,
        pos = 1,
        right = #code
    }, {__index=state_mt})
    local tokens = {}
    local line_offsets = find_lines(code)
    local line = 1
    while true do
        local t
        t = next_token(s)
        while t and (#line_offsets > 0) and (t[2] - 1 >= line_offsets[#line_offsets]) do
            line = line + 1
            line_offsets[#line_offsets] = nil
        end       
        if t == false then break end
        t[4] = line
        table.insert(tokens, t)
    end

    return tokens
end



local color = {
    [Token.Comment] = 'gray',
    [Token.If] = 'crimson',
    [Token.Then] = 'crimson',
    [Token.Else] = 'crimson',
    [Token.ElseIf] = 'crimson',
    [Token.While] = 'crimson',
    [Token.Do] = 'crimson',
    [Token.End] = 'crimson',
    [Token.String] = 'green',
    
    [Token.Name] = 'cyan',
    
    [Token.Number] = 'purple',
    [Token.True] = 'purple',
    [Token.False] = 'purple',
    
    [Token.Equals] = 'crimson',
    [Token.Local] = 'crimson'
}

local function hilight(v, c)
    local code = v.string
    local tokens = tokenize(code)
    local parts = {}
    local line_offsets = find_lines(code)
    
    local wp = 1

    for i,t in ipairs(tokens) do
        while (#line_offsets > 0) and (t[2] - 1 >= line_offsets[#line_offsets]) do
            table.insert(parts, '\n')
            wp = line_offsets[#line_offsets]
            line_offsets[#line_offsets] = nil
        end

        while wp < t[2] - 1 do
            table.insert(parts, ' ');
            wp = wp + 1
        end
        table.insert(parts, c('{' .. (color[t[1]] or 'white') .. '-fg}%s{/}', code:sub(t[2], t[3])))
        wp = t[3]

        -- Newline is already in token text
        while (#line_offsets > 0)  and wp > line_offsets[#line_offsets] do line_offsets[#line_offsets] = nil end
    end


    return table.concat(parts, '')
end



return {
    tokenize = tokenize,
    Token = Token,
    token_names = token_names,
    hilight = hilight
}