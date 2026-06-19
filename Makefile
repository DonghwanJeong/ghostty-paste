# ghostty-paste — build & install automation
#
#   make build      release 바이너리 빌드(현재 아키텍처)
#   make universal  arm64+x86_64 유니버설 바이너리 빌드(릴리스용)
#   make install    빌드 + 설치 + LaunchAgent 등록(로그인 시 자동 실행)
#   make reload     데몬 재시작(권한 부여 후 등 변경 반영)
#   make uninstall  LaunchAgent 해제 + 바이너리 제거
#   make clean      빌드 산출물 정리
#
# 설치 위치는 PREFIX로 바꿀 수 있다:  make install PREFIX=/usr/local

PREFIX ?= $(HOME)/.local
BINDIR := $(PREFIX)/bin
BIN    := ghostty-paste

SRC          := src/ghostty-paste.swift
BUILD_BIN    := .build/$(BIN)
LABEL        := com.github.ghostty-paste
LAUNCH_DIR   := $(HOME)/Library/LaunchAgents
LAUNCH_AGENT := $(LAUNCH_DIR)/$(LABEL).plist
TEMPLATE     := launchagent/$(LABEL).plist.template
UID          := $(shell id -u)

.PHONY: build universal install reload uninstall clean

build:
	@mkdir -p .build
	swiftc -O -swift-version 5 $(SRC) -o $(BUILD_BIN)

universal:
	@mkdir -p .build
	swiftc -O -swift-version 5 -target arm64-apple-macos12  $(SRC) -o $(BUILD_BIN)-arm64
	swiftc -O -swift-version 5 -target x86_64-apple-macos12 $(SRC) -o $(BUILD_BIN)-x86_64
	lipo -create -output $(BUILD_BIN) $(BUILD_BIN)-arm64 $(BUILD_BIN)-x86_64
	@file $(BUILD_BIN)

install: build
	@mkdir -p $(BINDIR) $(LAUNCH_DIR)
	cp $(BUILD_BIN) $(BINDIR)/$(BIN)
	sed 's|__BINARY_PATH__|$(BINDIR)/$(BIN)|g' $(TEMPLATE) > $(LAUNCH_AGENT)
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	launchctl bootstrap gui/$(UID) $(LAUNCH_AGENT)
	@echo ""
	@echo "✅ 설치 완료 → $(BINDIR)/$(BIN)"
	@echo ""
	@echo "⚠️  마지막 한 단계: 손쉬운 사용(Accessibility) 권한을 켜야 동작합니다."
	@echo "   시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 에서"
	@echo "   $(BINDIR)/$(BIN) 를 추가하고 토글을 켜세요."
	@echo "   권한을 켠 뒤:  make reload"

reload:
	-launchctl kickstart -k gui/$(UID)/$(LABEL)
	@echo "🔄 ghostty-paste 재시작"

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	-rm -f $(LAUNCH_AGENT)
	-rm -f $(BINDIR)/$(BIN)
	@echo "🧹 제거 완료 (손쉬운 사용 권한 항목은 시스템 설정에서 직접 지우세요)"

clean:
	rm -rf .build
