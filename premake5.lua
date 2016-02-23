solution "skiron"
	configurations { "release", "debug", "unittest" }

	project "emulator"
		kind "ConsoleApp"
		language "D"
		targetdir "bin"
		debugdir "bin"

		files { "common/**.d", "emulator/**.d" }

		filter "configurations:unittest"
			flags { "UnitTest" }

	project "assembler"
		kind "ConsoleApp"
		language "D"
		targetdir "bin"
		debugdir "bin"

		files { "common/**.d", "assembler/**.d" }

		filter "configurations:unittest"
			flags { "UnitTest" }

	project "disassembler"
		kind "ConsoleApp"
		language "D"
		targetdir "bin"
		debugdir "bin"

		files { "common/**.d", "disassembler/**.d" }

		filter "configurations:unittest"
			flags { "UnitTest" }

	project "docgen"
		kind "ConsoleApp"
		language "D"
		targetdir "bin"
		debugdir "bin"

		files { "common/**.d", "docgen/**.d" }

		filter "action:vs*"
			postbuildcommands "chdir bin && docgen && chdir ../"

		filter "action:not vs*"
			postbuildcommands "{CHDIR} bin && ./docgen"

		filter {}

		filter "configurations:unittest"
			flags { "UnitTest" }