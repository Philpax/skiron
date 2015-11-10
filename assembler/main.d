import std.exception;
import std.stdio;
import std.file;
import std.ascii;
import std.string;
import std.conv;
import std.traits;
import std.algorithm;
import std.array;
import std.path;

import core.stdc.stdlib;

import common.opcode;
import common.cpu;

struct Token
{
	enum Type
	{
		Identifier,
		Number,
		Register,
		Label,
		Byte,
		Dbyte,
		Qbyte
	}

	string fileName;
	int lineNumber;
	int column;

	Type type;
	string text;
	int number;

	string toString()
	{
		return "%s:%s".format(type, text);
	}
}

void error(Args...)(string text, auto ref Args args)
{
	writefln(text, args);
	exit(EXIT_FAILURE);
}

void errorIf(Args...)(bool condition, auto ref Args args)
{
	if (condition)
		error(args);
}

void error(Args...)(ref Token token, string text, auto ref Args args)
{
	writef("%s[%s,%s]: ", token.fileName, token.lineNumber, token.column);
	error(text, args);
}

void attemptTokeniseRegister(ref Token token)
{
	auto t = token.text;
	if (t == "ip")
	{
		token.type = Token.Type.Register;
		token.number = cast(int)Register.IP;
	}
	else if (t == "sp")
	{
		token.type = Token.Type.Register;
		token.number = cast(int)Register.SP;
	}
	else if (t == "bp")
	{
		token.type = Token.Type.Register;
		token.number = cast(int)Register.BP;
	}
	else if (t == "z")
	{
		token.type = Token.Type.Register;
		token.number = cast(int)Register.Z;
	}
	else if (t.startsWith("r") && t.length > 1 && t[1..$].all!isDigit)
	{
		token.type = Token.Type.Register;
		token.number = t[1..$].to!ubyte();
	}
}

Token[] tokenise(string input, string fileName)
{
	Token[] tokens;
	Token currentToken;

	int lineNumber = 0;
	int column = 0;

	void makeToken()
	{
		currentToken = Token();
		currentToken.fileName = fileName;
	}

	makeToken();

	void completeToken()
	{
		if (currentToken.text.length == 0)
			return;

		if (currentToken.type == Token.Type.Number)
			currentToken.number = currentToken.text.to!int();
		else if (currentToken.type == Token.Type.Identifier)
		{
			if (currentToken.text == "byte")
				currentToken.type = Token.Type.Byte;
			else if (currentToken.text == "dbyte")
				currentToken.type = Token.Type.Dbyte;
			else if (currentToken.text == "qbyte")
				currentToken.type = Token.Type.Qbyte;
			else
				currentToken.attemptTokeniseRegister();
		}

		currentToken.lineNumber = lineNumber;

		tokens ~= currentToken;
		makeToken();
	}

	bool lexingComment = false;
	foreach (line; input.lineSplitter)
	{
		++lineNumber;
		column = 0;

		lexingComment = false;
		currentToken.lineNumber = lineNumber;
		foreach (c; line)
		{
			++column;
			currentToken.column = column;

			if (lexingComment)
				break;

			if (c.isWhite())
			{
				completeToken();
			}
			else if (c == '#')
			{
				lexingComment = true;
			}
			else if (c == ',')
			{
				continue;
			}
			else if (currentToken.text.length == 0 && (c.isDigit() || c == '-'))
			{
				currentToken.type = Token.Type.Number;
				currentToken.text ~= c;
			}
			else if (currentToken.type == Token.Type.Number)
			{
				if (!c.isDigit())
					currentToken.error("Expected digit; got `%s`.", c);
				currentToken.text ~= c;
			}
			else if (currentToken.type == Token.Type.Identifier && (c.isAlphaNum() || c == '_'))
			{
				currentToken.text ~= c;
			}
			else if (currentToken.type == Token.Type.Identifier && c == ':')
			{
				currentToken.type = Token.Type.Label;
			}
			else
			{
				currentToken.error("Invalid character `%s` for token `%s`", c, currentToken.to!string());
			}
		}
		completeToken();
	}

	return tokens;
}

bool parseNumber(Int)(ref Token[] tokens, ref Int output)
	if (is(Int : int))
{
	auto token = tokens.front;
	if (token.type != Token.Type.Number)
		return false;

	output = cast(Int)token.number;
	tokens.popFront();
	return true;
}

bool parseSizePrefix(ref Token[] tokens, ref OperandSize output)
{
	auto token = tokens.front;

	if (token.type == Token.Type.Byte)
	{
		tokens.popFront();
		output = OperandSize.Byte;
	}
	else if (token.type == Token.Type.Dbyte)
	{
		tokens.popFront();
		output = OperandSize.Dbyte;
	}
	else if (token.type == Token.Type.Qbyte)
	{
		tokens.popFront();
		output = OperandSize.Qbyte;
	}
	else
	{
		output = OperandSize.Qbyte;
	}

	return true;
}

bool parseRegister(ref Token[] tokens, ref ubyte output)
{
	auto token = tokens.front;
	if (token.type != Token.Type.Register)
		return false;

	output = cast(ubyte)token.number;
	tokens.popFront();
	return true;
}

bool parseLabel(ref Token[] tokens, uint[string] labels, ref uint output)
{
	auto token = tokens.front;
	if (token.type != Token.Type.Identifier)
		return false;

	auto ptr = token.text in labels;
	if (!ptr)
		return false;

	output = *ptr;
	tokens.popFront();

	return true;
}

struct Assembler
{
	Token[] tokens;
	uint[] output;
	uint[string] labels;
	OpcodeDescriptor[][string] descriptors;
	size_t repCount = 1;

	this(Token[] tokens)
	{
		this.tokens = tokens;

		foreach (member; EnumMembers!Opcodes)
			this.descriptors[member.name] ~= member;
	}

	void finishAssemble(Token[] tokens)
	{
		this.tokens = tokens;
		this.repCount = 1;
	}

	bool assembleDstSrc(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		OperandSize operandSize;
		ubyte register1, register2;
		if (!newTokens.parseSizePrefix(operandSize)) return false;
		if (!newTokens.parseRegister(register1)) return false;
		if (!newTokens.parseRegister(register2)) return false;

		Opcode opcode;
		opcode.opcode = descriptor.opcode;
		opcode.operandSize = operandSize;
		opcode.register1 = register1;
		opcode.register2 = register2;
		opcode.register3 = 0;

		foreach (_; 0..this.repCount)
			this.output ~= opcode.value;
		this.finishAssemble(newTokens);

		return true;
	}

	bool assembleDstSrcSrc(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		OperandSize operandSize;
		ubyte register1, register2, register3;
		if (!newTokens.parseSizePrefix(operandSize)) return false;
		if (!newTokens.parseRegister(register1)) return false;
		if (!newTokens.parseRegister(register2)) return false;
		if (!newTokens.parseRegister(register3)) return false;

		Opcode opcode;
		opcode.opcode = descriptor.opcode;
		opcode.register1 = register1;
		opcode.register2 = register2;
		opcode.register3 = register3;

		foreach (_; 0..this.repCount)
			this.output ~= opcode.value;
		this.finishAssemble(newTokens);

		return true;
	}

	bool assembleDstImm(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		ubyte register1;
		int immediate;
		if (!newTokens.parseRegister(register1)) return false;
		if (!newTokens.parseNumber(immediate)) return false;

		Opcode opcode;
		opcode.opcode = descriptor.opcode;
		opcode.register1 = register1;
		opcode.immediate = immediate;

		foreach (_; 0..this.repCount)
			output ~= opcode.value;
		this.finishAssemble(newTokens);

		return true;
	}

	bool assembleNone(const(OpcodeDescriptor)* descriptor)
	{
		Opcode opcode;
		opcode.opcode = descriptor.opcode;

		foreach (_; 0..this.repCount)
			this.output ~= opcode.value;

		return true;
	}

	bool assembleLabel(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		Opcode opcode;
		opcode.opcode = descriptor.opcode;

		uint offset;
		if (!newTokens.parseLabel(this.labels, offset)) return false;

		foreach (_; 0..this.repCount)
		{
			auto currentPosition = cast(int)(output.length * uint.sizeof);
			opcode.offset = offset - currentPosition - 4;
			this.output ~= opcode.value;
		}
		this.finishAssemble(newTokens);

		return true;
	}

	bool assemblePush(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		OperandSize operandSize;
		ubyte register;
		if (!newTokens.parseSizePrefix(operandSize)) return false;
		if (!newTokens.parseRegister(register)) return false;

		// Synthesize store, add
		Opcode add;
		add.opcode = Opcodes.AddB.opcode;
		add.register1 = Register.SP;
		add.immediate = -4;

		Opcode store;
		store.opcode = Opcodes.Store.opcode;
		store.operandSize = operandSize;
		store.register1 = Register.SP;
		store.register2 = register;

		foreach (_; 0..this.repCount)
		{
			this.output ~= add.value;
			this.output ~= store.value;
		}

		this.finishAssemble(newTokens);

		return true;
	}

	bool assemblePop(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		OperandSize operandSize;
		ubyte register;
		if (!newTokens.parseSizePrefix(operandSize)) return false;
		if (!newTokens.parseRegister(register)) return false;

		// Synthesize load, add
		Opcode load;
		load.opcode = Opcodes.Load.opcode;
		load.operandSize = operandSize;
		load.register1 = register;
		load.register2 = Register.SP;

		Opcode add;
		add.opcode = Opcodes.AddB.opcode;
		add.register1 = Register.SP;
		add.immediate = 4;

		foreach (_; 0..this.repCount)
		{
			this.output ~= load.value;
			this.output ~= add.value;
		}

		this.finishAssemble(newTokens);

		return true;
	}

	bool assembleLoadI(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		ubyte register;
		uint value;

		if (!newTokens.parseRegister(register)) return false;
		if (!(newTokens.parseNumber(value) || newTokens.parseLabel(this.labels, value)))
			return false;

		// Synthesize loadui, loadli
		Opcode loadui;
		loadui.opcode = Opcodes.LoadUi.opcode;
		loadui.register1 = register;
		loadui.immediate = (value >> 16) & 0xFFFF;

		Opcode loadli;
		loadli.opcode = Opcodes.LoadLi.opcode;
		loadli.register1 = register;
		loadli.immediate = value & 0xFFFF;

		foreach (_; 0..this.repCount)
		{
			this.output ~= loadui.value;
			this.output ~= loadli.value;
		}

		this.finishAssemble(newTokens);

		return true;
	}

	bool assembleDb(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		int value;
		if (!newTokens.parseNumber(value)) return false;

		if (this.repCount % 4 != 0)
			throw new Exception("Expected 4-byte alignment compatibility for db");

		auto b = cast(ubyte)value;

		foreach (i; 0..this.repCount/4)
			output ~= b || b << 8 || b << 16 || b << 24;

		this.finishAssemble(newTokens);

		return true;
	}

	bool assembleRep(const(OpcodeDescriptor)* descriptor)
	{
		auto newTokens = this.tokens;

		int repCount;
		if (!newTokens.parseNumber(repCount)) return false;
		this.repCount = repCount;
		this.tokens = newTokens;

		return true;
	}
}

alias AssembleFunction = bool delegate(ref Assembler assembler, const(OpcodeDescriptor)* descriptor);
auto generatePseudoAssemble()
{
	string ret = "[";

	foreach (member; EnumMembers!Opcodes)
	{
		static if (member.operandFormat == OperandFormat.Pseudo)
		{
			ret ~= (`"%s" : (ref Assembler assembler, const(OpcodeDescriptor)* descriptor) ` ~
				`=> assembler.assemble%s(descriptor), `).format(member.name, member.to!string);
		}
	}

	ret ~= "]";

	return ret;
}

immutable AssembleFunction[string] PseudoAssemble;

// Use a module constructor to work around not being able to initialize AAs in module scope
static this()
{
	PseudoAssemble = mixin(generatePseudoAssemble());
} 

uint[] assemble(Token[] tokens)
{
	auto assembler = Assembler(tokens);
	while (!assembler.tokens.empty)
	{
		auto token = assembler.tokens.front;

		if (token.type == Token.Type.Identifier)
		{
			auto matchingDescriptors = token.text in assembler.descriptors;
			if (!matchingDescriptors)
				token.error("No matching opcode found for `%s`.", token.text);

			bool foundMatching = false;

			string generateSwitchStatement()
			{
				string s =
`final switch (descriptor.operandFormat)
{
`;
				foreach (member; EnumMembers!OperandFormat)
				{
					if (member == OperandFormat.Pseudo)
						continue;

					s ~= format(
`case OperandFormat.%1$s:
	foundMatching |= assembler.assemble%1$s(&descriptor);
	break;
`,
					member.to!string());
				}

				s ~= 
`case OperandFormat.Pseudo:
	foundMatching |= PseudoAssemble[token.text](assembler, &descriptor);
	break;
}
`;
				return s;
			}

			assembler.tokens.popFront();
			foreach (descriptor; *matchingDescriptors)
			{
				mixin (generateSwitchStatement());

				if (foundMatching) 
					break;
			}
			if (!foundMatching)
				token.error("No valid overloads for `%s` found.", token.text);
		}
		else if (token.type == Token.Type.Label)
		{
			auto text = token.text;
			if (text in assembler.labels)
				token.error("Redefining label `%s`", text);
			assembler.labels[text] = cast(uint)(assembler.output.length * uint.sizeof);
			assembler.tokens.popFront();
		}
		else
		{
			token.error("Unhandled token: %s.", token.to!string());
		}
	}

	return assembler.output;
}

void main(string[] args)
{
	errorIf(args.length < 2, "expected at least one argument");
	string inputPath = args[1];
	errorIf(!inputPath.exists(), "%s: No such file or directory", inputPath);
	string outputPath = args.length >= 3 ? args[2] : inputPath.setExtension("bin");

	auto input = inputPath.readText();
	auto tokens = input.tokenise(inputPath);
	auto output = tokens.assemble();

	std.file.write(outputPath, output);
}