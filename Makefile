# NES builds still use the upstream build scripts. No NES toolchain is needed here.
LOCAL_ASM := build/tools/sjasmplus/sjasmplus
SJASMPLUS ?= $(if $(wildcard $(LOCAL_ASM)),$(LOCAL_ASM),sjasmplus)
PYTHON ?= python3

.PHONY: sg1000 sg1000-tools sg1000-test
sg1000:
	$(PYTHON) sg1000/assets.py
	$(SJASMPLUS) --nologo --sym=build/sg1000/game.sym --raw=build/smb1.sg sg1000/game.asm

# Optional, explicit network step for systems without a packaged assembler.
sg1000-tools: $(LOCAL_ASM)
$(LOCAL_ASM):
	mkdir -p build/tools
	git clone --depth 1 --branch v1.21.1 https://github.com/z00m128/sjasmplus.git build/tools/sjasmplus
	$(MAKE) -C build/tools/sjasmplus USE_LUA=0

sg1000-test: sg1000
	$(PYTHON) sg1000/test_assets.py
	$(if $(GEARSYSTEM_CORE),$(PYTHON) sg1000/smoke.py "$(GEARSYSTEM_CORE)",@echo 'Set GEARSYSTEM_CORE to a Gearsystem libretro library to run the emulator test.')
