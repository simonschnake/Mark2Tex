-- LPeg operations used by the parser grammars.
local record lpeg
	record Pattern
		metamethod __len: function(Pattern): Pattern
		metamethod __unm: function(Pattern): Pattern
		metamethod __add: function(Pattern, Pattern): Pattern
		metamethod __sub: function(Pattern, Pattern): Pattern
		metamethod __sub: function(integer, Pattern): Pattern
		metamethod __mul: function(Pattern, Pattern | integer): Pattern
		metamethod __pow: function(Pattern, integer): Pattern
		metamethod __div: function<R>(Pattern, function(): R): Pattern
		metamethod __div: function<A, R>(Pattern, function(A): R): Pattern
		metamethod __div: function<A, B, R>(Pattern, function(A, B): R): Pattern
		metamethod __div: function<A, B, C, R>(Pattern, function(A, B, C): R): Pattern
		metamethod __div: function<A, B, C, D, R>(Pattern, function(A, B, C, D): R): Pattern
		metamethod __div: function<A, B, C, R>(Pattern, function(A, B, C...): R): Pattern
		match: function(self, string): any
	end

	P: function(string | integer | Pattern): Pattern
	P: function({string | integer: Pattern}): Pattern
	R: function(string...): Pattern
	S: function(string): Pattern
	C: function(Pattern): Pattern
	Ct: function(Pattern): Pattern
	Cp: function(): Pattern
	Cmt: function<A, B, R>(Pattern, function(string, integer, A, B): (integer, R)): Pattern
	match: function(Pattern, string): any
	V: function(string): Pattern
end

return lpeg
