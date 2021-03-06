module common.encoding;

import std.bitmanip;
import std.meta;
import std.algorithm;

struct EncodingDescriptor
{
	struct Field
	{
		string type;
		string name;
		int size;
		string description;
	}

	string name;
	string description;
	Field[] fields;
}

private:
string removeUnderscored(string s)
{
	if (s.length && s[0] == '_')
		return "";
	else
		return s;
}

template encodingFilter(Args...)
{
	static if (Args.length > 4)
		alias encodingFilter = AliasSeq!(encodingFilter!(Args[0..4]), encodingFilter!(Args[4..$]));
	else
		alias encodingFilter = AliasSeq!(Args[0], removeUnderscored(Args[1]), Args[2]);
}

string encodingDocsMake(Args...)()
{
	import std.string : format;

	static if (Args.length)
	{
		auto name = Args[1];

		if (name[0] == '_')
			name = name[1..$];

		return `EncodingDescriptor.Field("%s", "%s", %s, "%s"), `.format(Args[0].stringof, name, Args[2], Args[3]) ~ encodingDocsMake!(Args[4..$]);
	}
	else
	{
		return ``;
	}
}

string encodingDocs(string Name, string Description, Args...)()
{
	import std.string : format;

	auto ret = `enum EncodingDocs` ~ Name ~ ` = EncodingDescriptor(`;
	ret ~= `"%s", "%s", [`.format(Name, Description);
	ret ~= encodingDocsMake!(Args);
	ret ~= "]);\n";
	return ret;
}

public:
string defineEncoding(string Name, string Description, Args...)()
{
	import std.string : format;
	import std.uni : toLower;

	auto ret = "struct %s { %s Opcode get() { return cast(Opcode)this; } alias get this; } %s %s;".format(Name, bitfields!(encodingFilter!Args), Name, Name.toLower());
	ret ~= encodingDocs!(Name, Description, Args);
	return ret;
}

mixin template DefineEncoding(alias encoding, string Description, Args...)
{
	import std.conv;
	mixin(defineEncoding!(to!string(encoding), Description, Args));
}

EncodingDescriptor[] getEncodings(Opcode)()
{
	return mixin({
		import std.string : format, join;
		import std.array : array;

		enum members = [__traits(allMembers, Opcode)]; 
		return "[%s]".format(
			members.filter!(a => a.startsWith("EncodingDocs"))
				   .map!(a => Opcode.stringof ~ "." ~ a)
				   .join(", ")
				   .array());
	}());
}