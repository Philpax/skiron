module common.opcode;

import common.cpu;
import common.util;
import common.encoding;

enum OpcodeBitCount = 6;
enum OpcodeCount = (1 << OpcodeBitCount);

struct Opcode
{
	union
	{
		enum EncodingBitCount = 2;
		enum VariantBitCount = 2;
		enum OperandSizeBitCount = 2;

		mixin DefineEncoding!("A",
			"Used for three-register instructions.",
			ubyte,			"opcode",		OpcodeBitCount,
			"The opcode number.",
			Encoding,		"encoding",		EncodingBitCount,
			"The encoding in use.",
			Variant,		"variant",		VariantBitCount,
			"The variant/modifier to apply to register3.",
			Register,		"register1",	RegisterBitCount,
			"The destination register.",
			Register,		"register2",	RegisterBitCount,
			"The first source register.",
			Register,		"register3",	RegisterBitCount,
			"The second source register.",
			ubyte,			"_padding",		2,
			"",
			OperandSize,	"operandSize",	OperandSizeBitCount,
			"The sizes of the operands being used.",
		);

		mixin DefineEncoding!("B",
			"Used for one-register, one-immediate instructions.",
			ubyte,			"_opcode",		OpcodeBitCount,
			"",
			Encoding,		"_encoding",	EncodingBitCount,
			"",
			Variant,		"_variant",		VariantBitCount,
			"The variant/modifier to apply to immediateB.",
			Register,		"_register1",	RegisterBitCount,
			"The destination/source register.",
			int,			"immediateB",	14,
			"The encoded signed immediate value.",
			OperandSize,	"_operandSize",	OperandSizeBitCount,
			"",
		);

		mixin DefineEncoding!("B16",
			"Used for one-register, one-16-bit-immediate instructions. " ~
			"This is not a real encoding: it is the result of using Encoding B with an instruction that doesn't use operandSize.",
			ubyte,			"_opcode",		OpcodeBitCount,
			"",
			Encoding,		"_encoding",	EncodingBitCount,
			"",
			Variant,		"_variant",		VariantBitCount,
			"The variant/modifier to apply to immediateB.",
			Register,		"_register1",	RegisterBitCount,
			"The destination/source register.",
			uint,			"immediateB16",	16,
			"The unsigned 16-bit encoded immediate value.",
		);

		mixin DefineEncoding!("C",
			"Used for one-immediate instructions.",
			ubyte,			"_opcode",		OpcodeBitCount,
			"",
			Encoding,		"_encoding",	EncodingBitCount,
			"",
			Variant,		"_variant",		VariantBitCount,
			"The variant/modifier to apply to immediateC.",
			int,			"immediateC",	20,
			"The encoded signed immediate value.",
			OperandSize,	"_operandSize",	OperandSizeBitCount,
			"",
		);

		mixin DefineEncoding!("D",
			"Used for two-register, one-immediate instructions.",
			ubyte,			"_opcode",		OpcodeBitCount,
			"",
			Encoding,		"_encoding",	EncodingBitCount,
			"",
			Variant,		"_variant",		VariantBitCount,
			"",
			Register,		"_register1",	RegisterBitCount,
			"The destination register.",
			Register,		"_register2",	RegisterBitCount,
			"The source register.",
			int,			"immediateD",	8,
			"The encoded signed immediate value.",
			OperandSize,	"_operandSize",	OperandSizeBitCount,
			"",
		);

		uint value;
	}
}

static assert(Opcode.sizeof == uint.sizeof);

public:

enum OperandSize
{
	Byte,
	Dbyte,
	Qbyte
}

enum Variant
{
	Identity,
	ShiftLeft1,
	ShiftLeft2
}

enum Encoding
{
	A,
	B,
	C,
	D,
}

// Not the same as encoding; dictates how many operands there are
enum OperandFormat
{
	DstSrc,
	DstSrcSrc,
	DstImm,
	DstSrcImm,
	Label,
	None,
	Pseudo
}

struct OpcodeDescriptor
{
	string name;
	ubyte opcode;
	Encoding encoding;
	bool supportsOperandSize;
	OperandFormat operandFormat;
	string description;
}

auto PseudoOpcode(string name, string description)
{
	return OpcodeDescriptor(name, 0, Encoding.A, false, OperandFormat.Pseudo, description);
}

enum Opcodes
{
	// Memory
	Load	= OpcodeDescriptor("load",		0, Encoding.A, true,  OperandFormat.DstSrc,
		"Loads the value located in `[src]` into `dst`."),
	Store 	= OpcodeDescriptor("store",		1, Encoding.A, true,  OperandFormat.DstSrc,
		"Stores the value located in `src` into `[dst]`."),
	LoadLi	= OpcodeDescriptor("loadli",	2, Encoding.B, false, OperandFormat.DstImm,
		"Load the immediate into the lower half of `src`."),
	LoadUi	= OpcodeDescriptor("loadui",	3, Encoding.B, false, OperandFormat.DstImm,
		"Load the immediate into the upper half of `src`."),
	// Arithmetic
	AddA	= OpcodeDescriptor("add",		4, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Add `src1` and `src2` together, and store the result in `dst`."),
	AddB	= OpcodeDescriptor("add",		5, Encoding.B, true, OperandFormat.DstImm,
		"Add the immediate to `dst`, and store the result in `dst`."),
	AddD	= OpcodeDescriptor("add",		6, Encoding.D, true, OperandFormat.DstSrcImm,
		"Add the immediate to `src`, and store the result in `dst`."),
	Sub		= OpcodeDescriptor("sub",		7, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Subtract `src2` from `src1`, and store the result in `dst`."),
	Mul		= OpcodeDescriptor("mul",		8, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Multiply `src1` by `src2`, and store the result in `dst`."),
	Div		= OpcodeDescriptor("div",		9, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Divide `src1` by `src2`, and store the result in `dst`."),
	Not		= OpcodeDescriptor("not",		10, Encoding.A, false, OperandFormat.DstSrc,
		"Bitwise-NOT `src`, and store the result in `dst`."),
	And		= OpcodeDescriptor("and",		11, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Bitwise-AND `src1` with `src2`, and store the result in `dst`."),
	Or		= OpcodeDescriptor("or",		12, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Bitwise-OR `src1` with `src2`, and store the result in `dst`."),
	Xor		= OpcodeDescriptor("xor",		13, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Bitwise-XOR `src1` with `src2`, and store the result in `dst`."),
	Shl		= OpcodeDescriptor("shl",		14, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Shift `src1` by `src2` bits to the left, and store the result in `dst`."),
	Shr		= OpcodeDescriptor("shr",		15, Encoding.A, true,  OperandFormat.DstSrcSrc,
		"Shift `src1` by `src2` bits to the right, and store the result in `dst`."),
	// Control flow
	Cmp		= OpcodeDescriptor("cmp",		16, Encoding.A, true,  OperandFormat.DstSrc,
		"Compare `dst` to `src`, and update the flags register appropriately."),
	J		= OpcodeDescriptor("j",			17, Encoding.C, false, OperandFormat.Label,
		"Jump to the given label unconditionally."),
	Je		= OpcodeDescriptor("je",		18, Encoding.C, false, OperandFormat.Label,
		"If the zero flag is set, jump to the given label."),
	Jne		= OpcodeDescriptor("jne",		19, Encoding.C, false, OperandFormat.Label,
		"If the zero flag is not set, jump to the given label."),
	Jgt		= OpcodeDescriptor("jgt",		20, Encoding.C, false, OperandFormat.Label,
		"If the greater flag is set, jump to the given label."),
	Jlt		= OpcodeDescriptor("jlt",		21, Encoding.C, false, OperandFormat.Label,
		"If the less flag is set, jump to the given label."),
	Call	= OpcodeDescriptor("call",		22, Encoding.C, false, OperandFormat.Label,
		"Store the current instruction pointer in `ra`, and then jump to the given label."),
	Halt	= OpcodeDescriptor("halt",		OpcodeCount-1, Encoding.A, false, OperandFormat.None,
		"Halt operation."),
	// Pseudoinstructions
	Push	= PseudoOpcode("push",
		"Push the given register onto the stack (i.e. `add sp, -4; store sp, register`)."),
	Pop		= PseudoOpcode("pop",
		"Pop the given register from the stack (i.e. `load register, sp; add sp, 4`)."),
	CallSv	= PseudoOpcode("callsv",
		"Push the current return address, call the given label, and pop the return address."),
	LoadI	= PseudoOpcode("loadi",
		"Load the given 32-bit immediate, or label, into a register."),
	Dw		= PseudoOpcode("dw",
		"Create a word containing `arg2`."),
	Rep		= PseudoOpcode("rep",
		"Repeat the following instruction `arg1` times."),
	Jr		= PseudoOpcode("jr",
		"Jump to the given register."),
	Move	= PseudoOpcode("move",
		"Copy the value in `src` to `dst`."),
}

unittest
{
	Opcode opcode;
	opcode.opcode = Opcodes.Load.opcode;
	opcode.register1 = cast(Register)0;
	opcode.register2 = cast(Register)1;
	opcode.register3 = cast(Register)2;

	assert(opcode.opcode == Opcodes.Load.opcode);
	assert(opcode.register1 == cast(Register)0);
	assert(opcode.register2 == cast(Register)1);
	assert(opcode.register3 == cast(Register)2);
}

string generateOpcodeToDescriptor()
{
	import std.traits, std.string, std.conv;

	string ret =
`final switch (opcode)
{
`;

	foreach (member; EnumMembers!Opcodes)
	{
		if (member.operandFormat == OperandFormat.Pseudo)
			continue;

		ret ~= "case Opcodes.%s.opcode: return Opcodes.%s;\n".format(
			member.to!string(), member.to!string());
	}

	ret ~= `}`;

	return ret;
}

OpcodeDescriptor opcodeToDescriptor(ubyte opcode) @nogc nothrow
{
	mixin(generateOpcodeToDescriptor());
}

char[] disassemble(Opcode opcode, char[] output) @nogc nothrow
{
	import common.cpu : registerName;

	char[16][3] buffers;

	auto descriptor = opcode.opcode.opcodeToDescriptor();

	string sizePrefix = "";
	if (descriptor.supportsOperandSize)
	{
		import core.stdc.stdio;
		final switch (opcode.operandSize)
		{
		case OperandSize.Byte:
			sizePrefix = "byte ";
			break;
		case OperandSize.Dbyte:
			sizePrefix = "dbyte ";
			break;
		case OperandSize.Qbyte:
			sizePrefix = "qbyte ";
			break;
		}
	}

	string variant;
	final switch (opcode.variant)
	{
	case Variant.Identity:
		variant = "";
		break;
	case Variant.ShiftLeft1:
		variant = " << 1";
		break;
	case Variant.ShiftLeft2:
		variant = " << 2";
		break;
	}

	final switch (descriptor.operandFormat)
	{
	case OperandFormat.DstSrc:
		auto reg1 = opcode.register1.registerName(buffers[0]);
		auto reg2 = opcode.register2.registerName(buffers[1]);

		return "%s %s%s, %s%s".sformat(output, descriptor.name, sizePrefix, reg1, reg2, variant);
	case OperandFormat.DstSrcSrc:
		auto reg1 = opcode.register1.registerName(buffers[0]);
		auto reg2 = opcode.register2.registerName(buffers[1]);
		auto reg3 = opcode.register3.registerName(buffers[2]);

		return "%s %s%s, %s, %s%s".sformat(output, descriptor.name, sizePrefix, reg1, reg2, reg3, variant);
	case OperandFormat.DstImm:
		auto reg1 = opcode.register1.registerName(buffers[0]);

		if (descriptor.supportsOperandSize)
			return "%s %s, %s%s".sformat(output, descriptor.name, reg1, opcode.immediateB, variant);
		else
			return "%s %s%s, %s%s".sformat(output, descriptor.name, sizePrefix, reg1, opcode.immediateB16, variant);
	case OperandFormat.DstSrcImm:
		auto reg1 = opcode.register1.registerName(buffers[0]);
		auto reg2 = opcode.register2.registerName(buffers[1]);

		return "%s %s%s, %s, %s%s".sformat(output, descriptor.name, sizePrefix, reg1, reg2, opcode.immediateD, variant);
	case OperandFormat.Label:
		return "%s %s".sformat(output, descriptor.name, opcode.immediateC);
	case OperandFormat.None:
		return "%s".sformat(output, descriptor.name);
	case OperandFormat.Pseudo:
		return output;
	}

	return output;
}

string disassemble(Opcode opcode)
{
	char[256] buffer;
	return opcode.disassemble(buffer).idup;
}

unittest
{
	Opcode opcode;
	opcode.opcode = Opcodes.Load.opcode;
	opcode.register1 = cast(Register)0;
	opcode.register2 = cast(Register)1;
	opcode.variant = Variant.ShiftLeft2;

	char[64] buffer;
	auto slice = opcode.disassemble(buffer);

	assert(slice == "load byte r0, r1 << 2");
	assert(opcode.disassemble == slice);
}