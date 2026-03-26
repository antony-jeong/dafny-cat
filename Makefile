.PHONY: verify verify-extern build run clean

# Verify the core spec and implementation (no code generation).
verify:
	dafny verify cat.dfy

# Verify the entry-point layer (includes cat.dfy transitively).
verify-extern:
	dafny verify extern.dfy

# Build a runnable cat binary (C# / .NET).
#
# dafny build produces cat.cs (Dafny runtime inlined), cat.csproj (targeting
# net8.0 from the version bundled with Dafny), and a net8 binary.
# We then retarget to the locally installed SDK and rebuild.
DOTNET_VER := $(shell dotnet --version 2>/dev/null | cut -d. -f1)
DOTNET_TFM  = net$(DOTNET_VER).0

build:
	dafny build \
	  --unicode-char:false \
	  --no-verify \
	  --target:cs \
	  extern.dfy CatIO.cs \
	  -o cat
	sed -i '' \
	  's|<TargetFramework>net[0-9.]*</TargetFramework>|<TargetFramework>$(DOTNET_TFM)</TargetFramework>|' \
	  cat.csproj
	dotnet build cat.csproj -o . -v q --nologo

# Quick smoke test.
run: build
	echo "hello world" | ./cat | diff - /dev/stdin <<< "hello world"
	./cat Makefile | diff - Makefile
	@echo "smoke tests passed"

clean:
	rm -rf cat cat.dll cat.cs cat.csproj cat-cs.dtr dafny-cat.sln \
	       cat.deps.json cat.pdb cat.runtimeconfig.json obj/
