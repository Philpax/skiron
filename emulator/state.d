module emulator.state;

public import common.cpu;
public import common.opcode;

import emulator.memory;
import emulator.arithmetic;
import emulator.controlflow;

import core.stdc.stdlib;
import core.stdc.stdio;

string generateOpcodeSwitch()
{
	import std.traits, std.string, std.conv;
	string s = 
`final switch (opcode.opcode)
{
`;
	foreach (member; EnumMembers!Opcodes)
	{
		if (member.operandFormat == OperandFormat.Pseudo)
			continue;

		if (member.supportsOperandSize)
		{
			s ~= format(
`case Opcodes.%1$s.opcode:
	final switch (opcode.operandSize)
	{
		case OperandSize.Byte:
			this.run%1$s!ubyte(opcode);
			break;
		case OperandSize.Dbyte:
			this.run%1$s!ushort(opcode);
			break;
		case OperandSize.Qbyte:
			this.run%1$s!uint(opcode);
			break;
	}
	break;
`, 
			member.to!string());
		}
		else
		{
			s ~= format(
`case Opcodes.%1$s.opcode:
	this.run%1$s(opcode);
	break;
`, 
			member.to!string());
		}
	}
	s ~= "}\n";
	return s;
}

@nogc:
nothrow:

struct Core
{
@nogc:
nothrow:
	State* state;
	ubyte[] memory;
	uint[RegisterCount+1] registers;
	bool running = true;
	bool printOpcodes = true;
	bool printRegisters = true;
	uint id;

	@disable this();
	this(ref State state, uint id)
	{
		this.state = &state;
		this.memory = state.memory;
		this.id = id;
	}

	~this() {}

	@property ref uint ip()
	{
		return this.registers[Register.IP];
	}

	@property ref uint sp()
	{
		return this.registers[Register.SP];
	}

	@property ref uint bp()
	{
		return this.registers[Register.BP];
	}

	@property ref uint ra()
	{
		return this.registers[Register.RA];
	}

	@property ref uint flags()
	{
		return this.registers[Register.Flags];
	}

	void step()
	{
		auto oldRegisters = this.registers;
		auto opcode = Opcode(*cast(uint*)&this.memory[this.ip]);

		if (this.printOpcodes)
		{
			char[64] buffer;
			auto inst = opcode.disassemble(buffer);
			printf("C%i %i: %.*s\n", this.id, this.ip, inst.length, inst.ptr);
		}

		this.ip += uint.sizeof;

		mixin(generateOpcodeSwitch());
		if (this.printRegisters)
		{
			char[8] name;
			bool first = true;
			foreach (index; 0 .. oldRegisters.length)
			{
				auto oldValue = oldRegisters[index];
				auto newValue = this.registers[index];

				if (oldValue == newValue)
					continue;

				auto reg = registerName(cast(ubyte)index, name);

				if (!first)
					printf(", ");

				printf("%.*s %X -> %X", reg.length, reg.ptr, oldValue, newValue);
				first = false;
			}

			printf("\n");
		}
	}
}

struct State
{
@nogc:
nothrow:
	ubyte[] memory;
	Core[] cores;

	@disable this();

	this(uint memorySize, uint coreCount)
	{
		this.memory = cast(ubyte[])malloc(memorySize)[0..memorySize];
		this.cores = (cast(Core*)malloc(coreCount * Core.sizeof))[0..coreCount];

		uint index = 0;
		foreach (ref core; this.cores)
		{
			core = Core(this, index++);
		}
	}

	~this()
	{
		foreach (ref core; this.cores)
			core.__dtor();

		free(this.cores.ptr);
		free(this.memory.ptr);
	}

	void run()
	{
		import std.algorithm;

		while (this.cores.any!(a => a.running))
		{
			foreach (ref core; this.cores)
				core.step();
		}
	}
}

Type getDst(Type = uint)(ref Core core, Opcode opcode)
{
	return cast(Type)core.registers[opcode.register1];
}

void setDst(Type = uint, IncomingType)(ref Core core, Opcode opcode, IncomingType value)
{
	if (opcode.register1 == Register.Z)
		return;
	else
		*cast(Type*)&core.registers[opcode.register1] = cast(Type)value;
}

Type doVariant(Type = uint)(Opcode opcode, Type value)
{
	final switch (opcode.variant)
	{
		case Variant.Identity:
			return value;
		case Variant.ShiftLeft1:
			return cast(Type)(value << 1);
		case Variant.ShiftLeft2:
			return cast(Type)(value << 2);
	}
}

int getImmediate(ref Core core, Opcode opcode)
{
	const descriptor = opcode.opcode.opcodeToDescriptor();
	final switch (descriptor.encoding)
	{
		case Encoding.A:
			assert(0);
		case Encoding.B:
			return opcode.doVariant(opcode.immediate16);
		case Encoding.C:
			return opcode.doVariant(opcode.immediate23);
		case Encoding.D:
			return opcode.doVariant(opcode.immediate9);
	}
}

Type getSrc(Type = uint)(ref Core core, Opcode opcode)
{
	return opcode.doVariant(cast(Type)core.registers[opcode.register2]);
}

Type getSrc1(Type = uint)(ref Core core, Opcode opcode)
{
	return cast(Type)core.registers[opcode.register2];
}

Type getSrc2(Type = uint)(ref Core core, Opcode opcode)
{
	return opcode.doVariant(cast(Type)core.registers[opcode.register3]);
}