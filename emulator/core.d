module emulator.core;

public import common.cpu;
public import common.opcode;

import common.debugging;

import emulator.state;
import emulator.instruction;

import std.traits : EnumMembers;
import std.algorithm : map;
import std.conv : to;
import std.string : format, join;

string generateOpcodeRunners()
{
	import std.array : empty;
	import std.string : replace;

	enum sizedTemplate = q{
	void run%s(Type = uint)(ref Core core, Opcode opcode)
	{
		%s;
	}
};

	string ret;

	foreach (member; EnumMembers!Opcodes)
	{
		if (member.operation.empty)
			continue;

		auto operation = member.operation.replace("$dst = ", "core.dst!Type(opcode) = cast(Type)(")
										 .replace("$imm", "core.immediate(opcode)")
										 .replace("$src1", "core.src1!Type(opcode)")
										 .replace("$src2", "core.src2!Type(opcode)")
										 .replace("$dst", "core.dst!Type(opcode)")
										 .replace("$src", "core.src!Type(opcode)")
										 ;

		operation ~= ")";
		ret ~= sizedTemplate.format(member.to!string(), operation);
	}

	return ret;
}

string generateOpcodeSwitch()
{
	string s = "";
	bool first = true;

	foreach (member; EnumMembers!Opcodes)
	{
		enum memberName = member.to!string();

		static if (member.pseudoOpcode)
		{
			static assert(!__traits(compiles, mixin("&run" ~ memberName)),
				memberName ~ " must not have an opcode runner; it is a pseudoinstruction");
			static assert(!__traits(compiles, mixin("&run" ~ memberName ~ "!uint")),
				memberName ~ " must not have an opcode runner; it is a pseudoinstruction");
			continue;
		}
		else
		{
			if (!first) {
				s ~= "else ";
			}
			first = false;

			if (member.operandFormat.supportsOperandSize)
			{
				s ~= format(
`if (opcode.a.opcode == Opcodes.%1$s.opcode && opcode.a.encoding == Encoding.%2$s) {
	final switch (opcode.a.operandSize)
	{
		case OperandSize.Byte:
			this.run%1$s!ubyte(opcode);
			break;
		case OperandSize.Byte2:
			this.run%1$s!ushort(opcode);
			break;
		case OperandSize.Byte4:
			this.run%1$s!uint(opcode);
			break;
	}
}`,
				memberName, member.encoding);
			}
			else
			{
				s ~= format(
`if (opcode.a.opcode == Opcodes.%1$s.opcode && opcode.a.encoding == Encoding.%2$s) {
	this.run%1$s(opcode);
}`,
				memberName, member.encoding);
			}
		}
	}
	return s;
}

string generateRegisterProperties()
{
	import std.uni : toLower;

	return [EnumMembers!Register].map!((a) {
		return
`	@property ref uint %s()
	{
		return this.registers[Register.%s];
	}
`.format(a.to!string.toLower(), a.to!string());
	}).join('\n');
}

@nogc:
nothrow:

mixin(generateOpcodeRunners());

struct Core
{
@nogc:
nothrow:
	State* state;
	ubyte[] memory;
	RegisterType[RegisterExtendedCount] registers;
	bool running = true;

	// Changed by debugger
	bool paused = false;
	bool doStep = false;

	uint id;

	@disable this();
	this(ref State state, uint id, bool paused)
	{
		this.state = &state;
		this.memory = state.memory;
		this.id = id;
		this.paused = paused;
	}

	~this() {}

	mixin(generateRegisterProperties());

	void step()
	{
		if (this.paused && !this.doStep)
			return;

		auto opcode = *cast(Opcode*)&this.memory[this.ip];
		this.ip += uint.sizeof;

		this.z = 0;

		mixin(generateOpcodeSwitch());

		if (this.doStep)
		{
			this.sendState();
			this.doStep = false;
		}
	}

	void sendState()
	{
		this.state.sendMessage!CoreState(this.id, !this.paused && this.running, this.registers);
	}
}

ref Type dst(Type = uint)(ref Core core, Opcode opcode)
{
	return *cast(Type*)&core.registers[opcode.a.register1];
}

Type doVariant(Type = uint)(Opcode opcode, Type value)
{
	final switch (opcode.a.variant)
	{
		case Variant.Identity:
			return value;
		case Variant.ShiftLeft1:
			return cast(Type)(value << 1);
		case Variant.ShiftLeft2:
			return cast(Type)(value << 2);
	}
}

int immediate(ref Core core, Opcode opcode)
{
	final switch (opcode.a.encoding)
	{
		case Encoding.A:
			assert(0);
		case Encoding.B:
			return opcode.doVariant(opcode.b.immediate);
		case Encoding.C:
			return opcode.doVariant(opcode.c.immediate);
		case Encoding.D:
			return opcode.doVariant(opcode.d.immediate);
	}
}

Type src1(Type = uint)(ref Core core, Opcode opcode)
{
	return opcode.doVariant(cast(Type)core.registers[opcode.a.register2]);
}

Type src2(Type = uint)(ref Core core, Opcode opcode)
{
	return opcode.doVariant(cast(Type)core.registers[opcode.a.register3]);
}

alias src = src1;