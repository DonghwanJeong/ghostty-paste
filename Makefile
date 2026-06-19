# ghostty-paste — build & install automation
#
#   make build       바이너리 빌드(현재 아키텍처)
#   make universal   arm64+x86_64 유니버설 바이너리 빌드(릴리스용)
#   make bundle      .app 번들로 패키징 + ad-hoc 서명
#   make install     빌드 + 번들 + 설치 + LaunchAgent 등록(로그인 시 자동 실행)
#   make reload      데몬 재시작
#   make reset-perm  손쉬운 사용 권한 초기화(tccutil) + 데몬 정지
#   make uninstall   LaunchAgent 해제 + 앱 제거
#   make clean       빌드 산출물 정리

BIN   := ghostty-paste
APP   := ghostty-paste.app
LABEL := com.github.ghostty-paste

SRC           := src/ghostty-paste.swift
BUILD_BIN     := .build/$(BIN)
BUILD_APP     := .build/$(APP)
APPDIR        := $(HOME)/Applications
INSTALLED_APP := $(APPDIR)/$(APP)
EXEC_PATH     := $(INSTALLED_APP)/Contents/MacOS/$(BIN)
LAUNCH_DIR    := $(HOME)/Library/LaunchAgents
LAUNCH_AGENT  := $(LAUNCH_DIR)/$(LABEL).plist
TEMPLATE      := launchagent/$(LABEL).plist.template
UID           := $(shell id -u)
LEGACY_BIN    := $(HOME)/.local/bin/$(BIN)   # 예전 bare-binary 설치 흔적

.PHONY: build universal bundle release install reload reset-perm uninstall clean

build:
	@mkdir -p .build
	swiftc -O -swift-version 5 $(SRC) -o $(BUILD_BIN)

universal:
	@mkdir -p .build
	swiftc -O -swift-version 5 -target arm64-apple-macos12  $(SRC) -o $(BUILD_BIN)-arm64
	swiftc -O -swift-version 5 -target x86_64-apple-macos12 $(SRC) -o $(BUILD_BIN)-x86_64
	lipo -create -output $(BUILD_BIN) $(BUILD_BIN)-arm64 $(BUILD_BIN)-x86_64
	@file $(BUILD_BIN)

# 릴리스용: 유니버설 바이너리를 .app으로 묶고 ad-hoc 서명 후 zip (CI에서 사용)
release: universal
	rm -rf $(BUILD_APP)
	mkdir -p $(BUILD_APP)/Contents/MacOS
	cp app/Info.plist $(BUILD_APP)/Contents/Info.plist
	cp $(BUILD_BIN) $(BUILD_APP)/Contents/MacOS/$(BIN)
	codesign --force --sign - $(BUILD_APP)
	cd .build && rm -f $(APP).zip && ditto -c -k --keepParent $(APP) $(APP).zip
	@echo "release zip → .build/$(APP).zip"

bundle: build
	rm -rf $(BUILD_APP)
	mkdir -p $(BUILD_APP)/Contents/MacOS
	cp app/Info.plist $(BUILD_APP)/Contents/Info.plist
	cp $(BUILD_BIN) $(BUILD_APP)/Contents/MacOS/$(BIN)
	codesign --force --sign - $(BUILD_APP)
	@echo "bundled & signed: $(BUILD_APP)"

install: bundle
	@mkdir -p $(APPDIR) $(LAUNCH_DIR)
	rm -rf $(INSTALLED_APP)
	cp -R $(BUILD_APP) $(INSTALLED_APP)
	-rm -f $(LEGACY_BIN)
	sed 's|__BINARY_PATH__|$(EXEC_PATH)|g' $(TEMPLATE) > $(LAUNCH_AGENT)
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	-: > /tmp/ghostty-paste.log
	launchctl bootstrap gui/$(UID) $(LAUNCH_AGENT)
	@echo ""
	@echo "✅ 설치 완료 → $(INSTALLED_APP)"
	@echo ""
	@echo "⚠️  손쉬운 사용(Accessibility) 권한을 켜야 동작합니다."
	@echo "   시스템 설정 → 개인정보 보호 및 보안 → 손쉬운 사용 목록에서"
	@echo "   'ghostty-paste'를 켜세요 (목록에 이름으로 자동 등록됩니다)."
	@echo "   안 보이면 시스템 설정을 완전히 종료(Cmd+Q) 후 다시 여세요."

reload:
	-launchctl kickstart -k gui/$(UID)/$(LABEL)
	@echo "🔄 ghostty-paste 재시작"

reset-perm:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	-tccutil reset Accessibility $(LABEL)
	@echo "🧽 손쉬운 사용 권한 초기화됨. 다시 설치하려면: make install"

uninstall:
	-launchctl bootout gui/$(UID)/$(LABEL) 2>/dev/null || true
	-rm -f $(LAUNCH_AGENT)
	-rm -rf $(INSTALLED_APP)
	-rm -f $(LEGACY_BIN)
	@echo "🧹 제거 완료 (손쉬운 사용 목록 항목은 시스템 설정에서 직접 지우세요)"

clean:
	rm -rf .build
