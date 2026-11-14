# lkt-nav2-debugger

rviz·rqt를 **쉽게 세팅**하고 **alias로 원워드 실행**해주는 ROS2 + Nav2 튜닝 셋업/런처 도구.
앱 안에서 시각화를 보지 않는다 — 네이티브 rviz/rqt 창을 "올바른 접속설정으로 열어주는 것"까지가 역할.

설계 전체: [`DESIGN.md`](DESIGN.md)

## 상태
- ✅ 프론트 UI v1 (`frontend/index.html`, 바닐라, mock + `/api` 폴백)
- ⏳ 백엔드 (FastAPI, Codex 구현 예정) — 프론트가 API 계약(§9)
- 분담: **백엔드=Codex / 프론트=Claude**

## 설치 (.deb 다운로드) — 가장 쉬움
git 클론·빌드 없이 Release의 `.deb`만 받아 설치한다.
```bash
wget https://github.com/dlrkdxor0821/lkt-nav2-debugger/releases/download/v0.1.1/lkt-nav2-debugger_0.1.1_all.deb
sudo apt install ./lkt-nav2-debugger_0.1.1_all.deb
lkt-nav2-debugger          # 실행(서버+브라우저). 앱 메뉴에도 'lkt-nav2-debugger'
```
제거: `sudo apt remove lkt-nav2-debugger`
최신 버전: https://github.com/dlrkdxor0821/lkt-nav2-debugger/releases

## 바로 실행 (개발, 소스에서)
```bash
./bin/lkt-nav2-debugger          # 프론트 서빙 + 브라우저 열림 (127.0.0.1:8777)
```

## 앱으로 설치
**user-level (sudo 불필요):**
```bash
./install.sh                     # ~/.local 에 런처+desktop+아이콘 등록
lkt-nav2-debugger                # 또는 앱 메뉴에서 실행
./install.sh --remove            # 제거
```
**.deb (시스템 설치):**
```bash
packaging/build-deb.sh 0.1.1     # dist/lkt-nav2-debugger_0.1.1_all.deb 생성
sudo dpkg -i dist/lkt-nav2-debugger_0.1.1_all.deb
lkt-nav2-debugger
```

## 구조
```
frontend/   # 바닐라 UI (Claude)
bin/        # 런처 (serve + open)
share/      # .desktop + icon
packaging/  # .deb 빌드
backend/    # FastAPI (Codex, 예정)
workspace/  # [gitignore] 사용자/생성물 (targets·templates·cyclonedds.xml·launch.sh)
```
