import std.stdio;
import std.exception;
import std.traits;
import std.file;
import std.string;
import std.conv;

import common.opcode;
import common.cpu;

void main(string[] args)
{
	enforce(args.length >= 2, "Expected at least one argument");
	auto opcodes = cast(Opcode[])std.file.read(args[1]);

	OpcodeDescriptor[ubyte] descriptors;

	foreach (member; EnumMembers!Opcodes)
		descriptors[member.opcode] = member;

	char[64] buffer;
	foreach (opcode; opcodes)
	{
		auto inst = opcode.disassemble(buffer);
		writeln(inst);
	}
}