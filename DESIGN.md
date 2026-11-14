# lkt-nav2-debugger — 설계도 (DESIGN)

> **목적:** rviz·rqt를 **쉽게 "세팅"해주고 alias로 원워드 진입**하게 해주는 **셋업/런처 도구**. (ROS2 + Nav2 로봇 빠른 튜닝용.)
> **앱 안에서 시각화를 보지 않는다.** 보기는 네이티브 rviz/rqt 창. 앱은 *올바른 config·접속설정을 만들고, 올바른 도구로 열어주고, alias를 깔아주는 것*까지.
> 어느 프로젝트/패키지에도 쓰이게(토픽명 독립), 내부 Claude Code가 토픽을 자동으로 붙인다. `git clone` 한 번으로 띄운다.
>
> 작성 2026-11-15 · 구현 분담: **백엔드=Codex / 프론트 UI=Claude(frontend 스킬)** · 베이스라인 ROS2 Humble/Jazzy

---

## 0. grill로 확정된 결정 (8)

1. **실행 = distro 자동선택.** 호스트 distro(`jazzy`) == `target.ros_distro` → **네이티브**. 다르면(예: Orin=humble) → **공식 ROS 베이스로 빌드한 per-distro docker**(1회 빌드, 모든 타겟·템플릿 재사용). 커스텀 패널은 옵트인.
2. **패널 = 호스트 프로세스** (venv FastAPI, `127.0.0.1`). 컨테이너 아님(nmcli·ros2·docker·네이티브 rviz 직접 호출 위해).
3. **파라미터 편집 = `rqt_reconfigure`만.** Foxglove·Lichtblick·foxglove_bridge **전부 안 씀.** → **전송은 DDS 하나로 통일.**
4. **내부 Claude Code = ttyd로 브라우저 패널에 내장.** 토픽 자동채움·패치 수행. loopback 바인딩 + 인증.
5. **Wi-Fi 자동접속 = 저장된 NetworkManager 프로파일 `nmcli connection up <ssid>`만.** 비번은 앱이 저장/취급 안 함(처음 1회 OS서 수동연결).
6. **프론트 = 바닐라 HTML/CSS/JS** (빌드/노드 없음, FastAPI가 정적 서빙).
7. **토픽 자동채움 = Claude가 전부** + 사용자가 수동으로도 가능.
8. **v1 = 전부**, 아래 4단계 순서로 빌드(§13). 레포명 **`lkt-nav2-debugger`**.

---

## 1. 목표 / 비목표

### 목표
1. **rviz·rqt 쉬운 세팅**: 올바른 `.rviz`/perspective + 접속설정(CycloneDDS XML)을 자동 생성. 손으로 XML·토픽 안 만짐.
2. **원워드 진입(alias)**: 생성된 세팅을 alias로 묶어 한 단어로 네이티브 rviz/rqt 실행 — **핵심 산출물**.
3. **프로젝트 독립**: 로봇/패키지마다 다른 토픽명에 소스 수정 없이 붙음(토픽 역할매핑 + Claude 자동채움).
4. **타겟 전환**: 로봇/환경(LAN·Wi-Fi·서브넷·VPN)·distro마다 접속설정을 앱에서 바꿈.
5. **시나리오/블록**: mapping/obstacle/localization/loc+obstacle 블록 조합으로 `.rviz` 구성.
6. (결과) **edit→observe 루프 최단화**.

### 비목표 (YAGNI)
- **앱 안에서 시각화를 보지 않는다.** 뷰잉은 네이티브 rviz/rqt.
- 로봇 스택(Nav2/SLAM/드라이버)을 띄우지 않음. **관측·튜닝 전용**(로봇 재시작 안 함).
- 멀티로봇 fleet 동시관제 아님(한 번에 한 타겟).
- 뷰어/편집기를 새로 만들지 않음. 네이티브 Qt(RViz/rqt/Qt Designer)를 **열어줄 뿐**.
- **Foxglove·Lichtblick·rosbridge·foxglove_bridge 안 씀.**
- 클라우드/원격 서버 아님. **운영자 본인 워크스테이션 로컬 실행.**

---

## 2. 운영 모델 / 가정

- 패널은 **운영자 워크스테이션(디스플레이 있는 로컬 PC)** 호스트 프로세스. 버튼으로 띄운 rviz/rqt는 **그 PC 데스크톱에 네이티브 창**(브라우저 안 아님). 브라우저 안에 있는 건 **config 폼 + ttyd Claude 터미널**뿐.
- 호스트엔 이미 `ros2`·`rviz2`(jazzy)·`docker`·`tmux` 있음(확인됨). 설치 추가 = venv + FastAPI deps + `ttyd`.
- 로봇엔 ROS2 스택이 돌고 있음. 앱은 **아무 로봇 프로세스도 안 띄움**(순수 관측). → foxglove_bridge 같은 것도 로봇에 안 띄움.
- 랩탑↔로봇 **RMW 동일**(`rmw_cyclonedds_cpp`), **전송 = DDS 단일.**

### 2.1 실행 모델 (distro 자동선택) — 핵심
```
host_distro = jazzy (확인됨)
for 실행 in (rviz, rqt):
  if target.ros_distro == host_distro:   네이티브  (source /opt/ros/jazzy + env + rviz2/rqt)   # 빠름, docker X
  else (예: humble Orin):                docker    (ros:<target_distro>-desktop 베이스 이미지)   # 타입/플러그인 정확 호환
```
- **cross-distro 주의(정직):** 표준 메시지(`sensor_msgs`·`nav_msgs`·`geometry_msgs`·`tf2_msgs`·`visualization_msgs`·`std_msgs`)는 jazzy↔humble 잘 보임. **`nav2_msgs` 커스텀타입**(`particle_cloud`, `costmap_raw`, `voxel_grid`, `collision_monitor_state`)·**커스텀 msg**·**커스텀 RViz 플러그인**은 버전 안 맞으면 안 보이거나 안 올라감 → 그때 **docker(로봇 distro)** 로 해결.
- docker 이미지 = **공식 ROS 베이스**로 자급자족 빌드(사용자 private 베이스 의존 X). **distro당 1개**, 1회 빌드, 재사용. 커스텀 패널(`tron_rviz_panels`) 필요하면 **소스에서 빌드하는 옵트인 레이어**.

---

## 3. 시스템 개요

```
운영자 워크스테이션(로컬 PC, 호스트)                         로봇(예: Orin, humble)
┌───────────────────────────────────────────────┐        ┌──────────────────────────┐
│ lkt-nav2-debugger 패널 (FastAPI 호스트프로세스 127.0.0.1)│        │ ROS2 스택 (Nav2/SLAM/드라이버)│
│  ├─ Targets / Connection(폼): distro·domain·    │        │  /scan /cloud_registered   │
│  │   wifi SSID·DDS peer·interface               │        │  /global_costmap/... 등     │
│  ├─ Templates(블록조립 → .rviz) / Topic(.rviz 읽기쓰기)│    └────────────┬─────────────┘
│  ├─ Generate → workspace/<target>/(cyclonedds.xml,│                   │ DDS(CycloneDDS)
│  │   launch.sh, *.perspective) + alias 설치      │  ◀── DDS ──────────┘  (멀티캐스트/유니캐스트)
│  └─ ttyd+tmux iframe → Claude Code (토픽 자동채움·패치)│
│                                                 │
│ 버튼이 띄우는 것(네이티브 or docker, distro로 자동):       │
│  ├─ rviz2 -d <template>.rviz   (네이티브 창)      │
│  └─ rqt_reconfigure            (param 편집)       │
└───────────────────────────────────────────────┘
```

### 구성요소
| 구성요소 | 역할 | 신규/재사용 | 담당 |
|---|---|---|---|
| 패널 백엔드 | FastAPI(호스트). config 읽기/쓰기, 생성기, nmcli, `docker`/`ros2` 실행, 그래프 조회 | **신규(얇게)** | Codex |
| Config/UI | 바닐라 폼 6화면(§9.1) | **신규** | **Claude** |
| 생성기 | target.yaml → CycloneDDS XML, launch.sh, .rviz(블록조립), .perspective | **신규(핵심)** | Codex |
| 런처 `launch.sh` | wifi up·재시도·복귀·ping·env·네이티브/도커 실행 | **신규(=tron-rviz 일반화)** | Codex |
| rviz2 / rqt_reconfigure | 시각화 / param 편집. 네이티브 or per-distro docker | 재사용 | — |
| 블록 라이브러리 | 재사용 Display/Panel 조각(역할별) | **신규(seed 추출)** | Codex |
| 토픽 resolver | `.rviz`의 토픽 필드 읽기/쓰기, 역할↔타입 | **신규(핵심)** | Codex |
| ttyd+tmux Claude | 브라우저 내장 터미널, 토픽 자동채움·패치 | 재사용(claude-terminal 패턴) | Codex |

---

## 4. 설정 모델

### 4.1 `workspace/targets/<name>.yaml` (gitignore) — 타겟(로봇+환경)
```yaml
name: orin-01
description: "TRON1 Orin, 서오릉"
connectivity:
  env: lan-wifi            # lan-wired | lan-wifi | cross-subnet | vpn
  ros_distro: humble        # ← 네이티브 vs docker 자동판정 (호스트=jazzy)
  robot_address: 10.192.1.3
  tailscale_address: 100.97.132.16   # (있으면)
  ros_domain_id: 43
  rmw: rmw_cyclonedds_cpp
  discovery: static-peers    # multicast | static-peers | discovery-server
  interface: wlo1
  local_ip: 10.192.1.217
  peers: ["10.192.1.3", "100.97.132.16"]
  wifi:                      # 저장된 NM 프로파일만 사용(비번 저장 X)
    ssid: TRON2A_416_5G
    auto_connect: true
    expected_ip: 10.192.1.217
    restore_on_exit: true
# 토픽은 여기 저장 안 함 — 토픽의 원본은 각 템플릿 .rviz (§4.2).
```

### 4.2 역할 카탈로그 + **`.rviz`가 토픽의 원본 (single source of truth)**
**설정 페이지와 실제 `.rviz`가 따로 놀면 안 된다.** 토픽의 **원본은 각 템플릿 `.rviz` 파일**. 토픽 페이지는 선택한 `.rviz`를 **읽어** 현재 토픽을 역할과 함께 표시하고, 편집하면 **그 `.rviz`에 되쓴다**(구조/주석 보존 = `ruamel.yaml`류). 별도 canonical 저장소 없음 → **프론트·백·파일 한 소스.**

`roles.yaml`(커밋) = **휴리스틱 카탈로그**(역할↔기대 메시지타입, 2D/3D·QoS). Claude 자동채움·2D/3D 해소의 *근거*일 뿐, 토픽 값 저장소 아님.
```yaml
# roles.yaml : 역할↔기대타입. 실제 토픽은 .rviz에서 읽고 .rviz에 씀.
roles:
  tf:                 { type: tf2_msgs/TFMessage }
  robot_pose:         { type: [PoseWithCovarianceStamped, Odometry] }
  speed_cmd:          { type: [Twist, TwistStamped] }     # Humble/Jazzy=Twist, Kilted+=TwistStamped 자동감지
  speed_measured:     { type: nav_msgs/Odometry }
  scan_2d:            { type: sensor_msgs/LaserScan }
  cloud_live:         { type: sensor_msgs/PointCloud2 }
  map_grid:           { type: nav_msgs/OccupancyGrid }
  map_cloud:          { type: sensor_msgs/PointCloud2 }
  slam_graph:         { type: visualization_msgs/MarkerArray }
  global_costmap:     { type: nav_msgs/OccupancyGrid }
  local_costmap:      { type: nav_msgs/OccupancyGrid }
  voxel_grid:         { type: nav2_msgs/VoxelGrid }        # ⚠ cross-distro 주의
  footprint:          { type: geometry_msgs/PolygonStamped }
  global_plan:        { type: nav_msgs/Path }
  local_plan:         { type: nav_msgs/Path }
  ctrl_trajectories:  { type: visualization_msgs/MarkerArray }
  collision_polygons: { type: geometry_msgs/PolygonStamped }
  amcl_particles:     { type: nav2_msgs/ParticleCloud, qos: best_effort }   # ⚠ Best-Effort + cross-distro
  amcl_pose:          { type: geometry_msgs/PoseWithCovarianceStamped }
  loc_confidence:     { type: std_msgs/Float32 }           # 3D 정합 fitness (plot)
  init_pose:          { type: geometry_msgs/PoseWithCovarianceStamped }
```
> **함정(생성기/resolver 필수):** ① particlecloud·costmap·scan은 **QoS Best-Effort**(불일치=빈화면). ② `cmd_vel` Twist↔TwistStamped 버전분기 **런타임 감지**. ③ costmap param 노드 `/local_costmap/local_costmap`·`/global_costmap/global_costmap` + 레이어 접두 `inflation_layer.`. ④ 2D(AMCL)↔3D(ICP 정합) 역할은 감지 타입으로 선택.

### 4.3 역할 스키마 (시나리오 매핑)
`M`mapping·`O`obstacle·`L`localization·`∀`상시. viz: 3D/plot/text.

| 역할 | msg 타입 | 기본 토픽 예 | 시나리오 | viz |
|---|---|---|---|---|
| tf | tf2_msgs/TFMessage | /tf,/tf_static | ∀ | 3D+text |
| speed_cmd | Twist/TwistStamped | /cmd_vel | ∀ | plot |
| speed_measured | nav_msgs/Odometry | /odom | ∀ | plot |
| scan_2d | sensor_msgs/LaserScan | /scan | M,O,L | 3D |
| cloud_live | sensor_msgs/PointCloud2 | /cloud_registered,/livox/* | M,O,L | 3D |
| map_grid/map_cloud | OccupancyGrid / PointCloud2 | /map,/laser_map | M,L | 3D |
| slam_graph | visualization_msgs/MarkerArray | /slam_toolbox/graph_visualization | M | 3D |
| global/local_costmap | nav_msgs/OccupancyGrid | /*/costmap | O | 3D |
| voxel_grid | nav2_msgs/VoxelGrid | /local_costmap/voxel_grid | O | 3D |
| footprint | geometry_msgs/PolygonStamped | /*/published_footprint | O,∀ | 3D |
| global/local_plan | nav_msgs/Path | /plan,/local_plan | O | 3D |
| ctrl_trajectories | visualization_msgs/MarkerArray | /trajectories(MPPI) | O | 3D |
| collision_polygons/state | PolygonStamped / nav2_msgs/CollisionMonitorState | /collision_monitor/* | O | 3D/text |
| amcl_particles(2D) | nav2_msgs/ParticleCloud (BestEffort) | /particle_cloud | L | 3D |
| amcl_pose(2D) | PoseWithCovarianceStamped | /amcl_pose | L | 3D+text |
| loc_confidence(정합,3D) | std_msgs/Float32 | /localization_3d_confidence 등 | L | plot+text |
| init_pose | PoseWithCovarianceStamped | /initialpose | L | 3D(입력) |

> 사용자 스택 = **3D LiDAR(Livox)** → `loc_confidence`(정합 fitness plot)가 localization 최우선 표시.

---

## 5. 시나리오(블록 조합 프리셋)
각 프리셋 = 어떤 블록(역할)을 어떤 순서로. 내장 seed 템플릿으로 제공.
1. **mapping**: map → 라이브 scan/cloud 오버레이 → tf → trajectory → slam_graph → speed.
2. **obstacle**: local_costmap → global_costmap → footprint → scan/cloud → global_plan → local_plan → ctrl_trajectories → voxel_grid → collision → speed.
3. **localization(3D)**: loc_confidence(정합) plot → registered cloud vs map_cloud → pose → tf → init_pose. (2D면 particle_cloud → amcl_pose 공분산 → scan over map.)
4. **localization+obstacle**: loc 신호 최상단 → local_costmap+footprint → scan → plans → ctrl_trajectories → collision → tf → speed.

**증상→param 치트시트**(프리셋 옆에 노출): 벽 긁음→`inflation_radius`↑ / 멀리 돎→`inflation_radius`↓·`cost_scaling_factor`↑ / 계획이 장애물 붙음→`cost_scaling_factor`↑·MPPI `CostCritic.cost_weight`↑ / local plan 떨림→RPP `lookahead_dist`↑·MPPI `PathAlignCritic.cost_weight`↑ / 컨트롤러 느림→MPPI `time_steps`·`batch_size`↓ / (3D loc) fitness 낮음→voxel leaf↓·게이트완화·재seed·ICP iter↑.

## 5.1 템플릿 = 재사용 블록 라이브러리 + 조립 (편집은 네이티브 Qt가)
핵심:
1. **자체 편집기 안 만듦.** "편집" 누르면 대상에 맞는 **네이티브 Qt 도구를 그 파일로 열어줌**: RViz(`.rviz`) / rqt(`.perspective`) / Qt Designer(`.ui`, 커스텀 패널). 사용자가 Qt Designer 능숙 → 이게 맞음.
2. **템플릿 = 재사용 "블록".** `tron rviz`의 라이다·맵·costmap, `tron_rviz_panels`(Health/Control/MapCoord/Lidar8/TopicValue)처럼 **역할 단위 블록**.
3. **조립 = 블록을 옵션처럼 골라 추가** → `workspace/templates/<name>.rviz` 생성(이름 설정). **토픽 붙이기는 내부 Claude Code가**(§8), 수동도 가능.

- **블록 라이브러리** `blocks/<id>.frag`(커밋) — RViz Display 하나/패널 하나 조각(역할 대응, 토픽 플레이스홀더). seed = 사용자 기존 `.rviz`/`tron_rviz_panels`에서 추출.
- **흐름**: New(이름+블록선택) → 조립 초안 `.rviz` → Claude가 토픽 바인딩 → (선택) RViz 열어 미세조정·저장 → alias 실행.

---

## 6. 연결/전송 생성 (DDS 전용)
앱이 `targets/<name>.yaml`에서 **CycloneDDS XML 생성** → `workspace/<target>/cyclonedds.xml`, `CYCLONEDDS_URI=file://…`로 주입.
- `lan-wired`: `AllowMulticast=default`, 도메인만(멀티홈이면 `<NetworkInterface>` 명시).
- `lan-wifi`/`cross-subnet`/`vpn`: `AllowMulticast=false` + `<NetworkInterface>` + `<Peers>` + `<ParticipantIndex>auto</ParticipantIndex>`.
- **인터페이스 자동바인딩**: 타겟 IP ↔ 로컬 NIC 서브넷 매칭(`100.x`→tailscale0, `10.192.1.x`→해당 NIC).
- **검증**: `ROS_DOMAIN_ID`≤101, 포트(`7400+250·domain`) 표시, **실행 전 ping/UDP reachability**, env 변경 후 `ros2 daemon stop`.

**LAN+VPN 동시 템플릿(실전, `cyclonedds_tron1.xml` 기반):**
```xml
<CycloneDDS><Domain id="any">
  <General>
    <Interfaces>
      <NetworkInterface address="10.192.1.217"/>   <!-- 로봇망 NIC 로컬 IP -->
      <NetworkInterface name="tailscale0"/>          <!-- VPN -->
    </Interfaces>
    <AllowMulticast>false</AllowMulticast>
    <FragmentSize>1344B</FragmentSize><MaxMessageSize>1400B</MaxMessageSize>
  </General>
  <Discovery>
    <ParticipantIndex>auto</ParticipantIndex><MaxAutoParticipantIndex>100</MaxAutoParticipantIndex>
    <Peers><Peer Address="localhost"/><Peer Address="10.192.1.3"/><Peer Address="100.97.132.16"/></Peers>
  </Discovery>
  <Internal><SocketReceiveBufferSize min="10MB"/><SocketSendBufferSize min="10MB"/></Internal>
</Domain></CycloneDDS>
```
(대안: FastDDS Discovery Server `ROS_DISCOVERY_SERVER` — pure-env. v1 기본은 CycloneDDS.)

---

## 7. 파라미터 편집 = `rqt_reconfigure`
- 네이티브(호스트=타겟 distro) 또는 docker(mismatch). 앱은 버튼으로 **띄워주기만**.
- Nav2 param **대부분 라이브 set 즉시 반영**(dyn handler). 단 costmap은 `/local_costmap/local_costmap`·레이어 접두, 컨트롤러 `FollowPath.<Critic>.…`, 플래너 `GridBased.…`. **정적(재시작 필요)**: plugin 리스트·frames·BT XML·behavior_server 다수.
- rqt 한계(사용자 주의): 노드목록 동적이라 핀고정 약함, param-without-default면 노드 통째 사라지는 버그, sync 호출 hang. → 앱은 "띄워주기"만 하고 이 한계는 rqt 본래 것.
- **v1은 param 영속(yaml 왕복) 미포함** — rqt는 저장 안 함. 필요 시 후속(ruamel 기반 params.yaml 왕복, `nav2_config` 참고)으로.

---

## 8. 내부 Claude Code(ttyd) 토픽 자동채움
1. 타겟 접속 확립(wifi/DDS) 후, ttyd+tmux의 Claude Code가 **호스트 ROS env 공유**로 라이브 그래프 조회: `ros2 topic list -t`, `ros2 node info`.
2. **Claude가 전부 바인딩**: 역할↔메시지타입(roles.yaml)으로 `.rviz`의 각 Display 토픽 필드를 실토픽으로 기입. 중복 타입/이름 휴리스틱도 Claude가 판단. 결과를 `workspace/templates/<name>.rviz`에 씀.
3. **수동도 가능**: 토픽 페이지(§9.1-④)에서 사람이 직접 토픽 선택/수정 → 같은 `.rviz`에 기록.
4. 경계: Claude는 **읽기+`.rviz` 파일 편집**. 로봇 param 쓰기/실행은 사람 확인 게이트.
- ttyd: `ttyd -W -i 127.0.0.1 -c user:pass tmux new -A -s tuner` → iframe. **loopback+인증**(§10 보안).

---

## 9. 백엔드 (FastAPI 호스트 프로세스) — Codex

엔드포인트(최소):
| 메서드 | 경로 | 동작 |
|---|---|---|
| GET | `/api/targets` | 타겟 목록 |
| GET/PUT | `/api/targets/{name}` | 타겟 yaml 읽기/쓰기(검증) |
| POST | `/api/targets/{name}/preflight` | wifi 상태·reachability·domain·RMW·포트 검증 |
| POST | `/api/targets/{name}/discover` | `ros2 topic list -t`/`node info` → 토픽·타입 목록 |
| GET | `/api/templates` · POST `/api/templates` | 템플릿 목록 / New(이름+블록선택→`.rviz` 조립) |
| GET/PUT | `/api/templates/{name}/topics` | **그 `.rviz` 읽어 토픽 반환 / 편집 되쓰기** |
| POST | `/api/templates/{name}/autofill` | Claude 자동채움 트리거(또는 ttyd 안내) |
| POST | `/api/templates/{name}/edit` | 네이티브 Qt 열기(rviz2/rqt/designer) |
| POST | `/api/generate` | `{target}` → cyclonedds.xml + launch.sh + .perspective 생성 |
| POST | `/api/aliases/install` | `~/.bash_aliases` 멱등 블록 기록(절대경로) |
| POST | `/api/launch` | `{target, kind}` kind∈{`rviz:<template>`,`rqt`} → 네이티브/도커 자동 실행 |
| GET | `/api/status` | 실행중·연결 상태 |

백엔드 모듈: `generators/`(cyclonedds xml·launch.sh·.rviz 블록조립·alias), `graph.py`(ros2 introspect), `net.py`(nmcli up/retry/restore·ping), `rviz_io.py`(.rviz 토픽 read/write, ruamel), `runner.py`(네이티브 vs docker 실행 선택). 모든 subprocess는 **arg-vector**(`shell=True` 금지).

### 9.1 UI 화면 (바닐라) — Claude
1. **Targets** — 목록/선택/새로/복제.
2. **Connection**(폼) — env·distro·robot IP·tailscale·domain·rmw·discovery·interface·**wifi SSID/자동접속/expected_ip/복귀**. 버튼: Connect(wifi+preflight)·도달성·상태.
3. **Templates(블록조립)** — 블록 체크박스 조립+이름 → `.rviz` 생성, **"Attach topics(Claude)"**, **"Edit"→RViz/`.rviz`·Qt Designer/`.ui`·rqt/`.perspective` 열림**, Rename/Clone/Delete.
4. **Topic map** — 선택 템플릿 `.rviz` 읽어 Display별 현재 토픽+역할 표시, 편집=그 `.rviz`에 되쓰기. 라이브 토픽 드롭다운·2D/3D·QoS.
5. **Generate & Launch** — Generate, Install aliases, Launch 버튼(`rviz:<template>`/`rqt`)+실행상태.
6. **Terminal** — ttyd iframe의 Claude Code.

---

## 10. 배포 / 패키징 / 보안
- **`git clone && ./run`**(또는 `just up`) → venv 생성·deps 설치·`ttyd` 확인/설치 → FastAPI `--host 127.0.0.1` → 브라우저 안내.
- docker는 **distro-mismatch rviz/rqt 이미지에만**(공식 베이스, per-distro, lazy build). 패널 자체는 호스트.
- **alias/런처**:
  - `generate` → `workspace/<target>/`(gitignore)에 `cyclonedds.xml`·`launch.sh`·`*.perspective`·조립된 `.rviz`.
  - `launch.sh <kind>`(= `tron-rviz` 일반화): **(a)** wifi `nmcli connection up <ssid>` 5회 재시도+`expected_ip` 확인 **(b)** PREV_CONN 저장 `trap EXIT` 복귀(Y/n) **(c)** `ping -c1 -W3 <robot>` **(d)** `ROS_DOMAIN_ID/RMW/CYCLONEDDS_URI` export 후 네이티브 `rviz2 -d …`/`rqt` 또는 `docker run`. `--net-only`로 (a)-(c)만도.
  - `install.sh`가 `~/.bash_aliases`에 **멱등 마커 블록**으로 기록(절대경로), 디스패처 `tune <target> <kind>` + 선택적 개별 alias(`tune-rviz-<target>-<tpl>` 등).
- **보안(RCE급 표면):** 전부 **loopback**(FastAPI·ttyd `-i 127.0.0.1`), **ttyd 인증**(`-c user:pass`/토큰)·`-W` 단일 터미널·비-root, 원격은 SSH/Tailscale 터널만. `docker run`은 **호스트서**(DinD/소켓마운트 회피) + kind 화이트리스트. X11 `xhost +SI:localuser:$USER`·종료시 `xhost -`. config 쓰기 서버검증(pydantic), subprocess arg-vector. **rqt는 라이브 로봇 param 쓰기(remote-write)** — 어느 실로봇인지 명시·확인.

## 10.1 레포 폴더 구조 & .gitignore
```
lkt-nav2-debugger/
├── README.md  DESIGN.md  CODEX-PLAN.md  .gitignore
├── run  (또는 Justfile)  install.sh      # venv+deps+ttyd, 호스트 실행, alias 주입
├── backend/            # [Codex] FastAPI: app.py, generators/, graph.py, net.py, rviz_io.py, runner.py
├── frontend/           # [Claude] 바닐라 HTML/CSS/JS (빌드 없음)
├── docker/             # distro별 Dockerfile(공식 ROS 베이스 + rviz/rqt/nav2); 커스텀패널은 옵트인
├── blocks/             # [커밋] 재사용 블록(seed): lidar/map/costmap/plan/footprint/collision/speed/정합/mapcoord/health
├── roles.yaml          # [커밋] 역할↔타입 휴리스틱 카탈로그
├── templates/seed/     # [커밋] 내장 4 시나리오 .rviz
├── examples/target.example.yaml  # [커밋] 예시(실 IP/SSID 없음)
└── workspace/          # ★[GITIGNORE 통째] 사용자/생성물
    ├── targets/<name>.yaml        # 실 IP·SSID·domain
    ├── templates/<name>.rviz      # 사용자 템플릿(Qt서 편집)
    ├── <target>/                  # cyclonedds.xml, launch.sh, *.perspective
    └── .gitkeep
```
```gitignore
/workspace/
!/workspace/.gitkeep
.venv/
__pycache__/
*.pyc
.env
.env.*
*.token
.DS_Store
```
> 비번/토큰 미저장(wifi=NM 프로파일, 패널 토큰은 `.env` gitignore). 공유할 템플릿만 `templates/seed/`로 복사·커밋.

---

## 11. 재사용 지도 (만들 것 vs 재사용)
| 영역 | 재사용 | 만들 것 |
|---|---|---|
| 시각화 | **RViz2**(네이티브/도커) | — |
| param | **rqt_reconfigure**(네이티브/도커) | — |
| 브라우저 터미널 | **ttyd+tmux**(xterm.js), claude-terminal 패턴 | — |
| 토픽 aliasing | launch-time remap(`--ros-args -r`), topic_tools relay(필요시) | 기본 remap |
| cross-distro | 공식 ROS docker 이미지 | per-distro Dockerfile |
| 고유(얇게) | — | FastAPI 런처·생성기·**토픽 resolver(.rviz io)**·블록조립·launch.sh·바닐라 UI |
> **안 씀:** Foxglove, Lichtblick, rosbridge, foxglove_bridge.

---

## 12. 리스크 / 함정
- **cross-distro(jazzy↔humble)**: 표준 msg OK, nav2_msgs 커스텀타입·커스텀 msg·커스텀 플러그인은 docker(로봇 distro)로. (§2.1)
- QoS Best-Effort 역할 / cmd_vel Twist↔TwistStamped / costmap 이중노드·레이어 접두 / 2D·3D 분기 (§4.2).
- `CYCLONEDDS_URI` 잘못되면 조용히 멀티캐스트 폴백 → 생성 XML·경로 검증·유효설정 로그.
- wifi: **저장된 NM 프로파일 전제**(없으면 "OS서 1회 연결" 안내). 비번 미취급.
- X11 전제: 패널은 디스플레이 있는 로컬 PC(헤드리스 비목표).
- rqt 라이브 param = **remote-write**: 잘못된 타겟 방지 가드.
- 커스텀 패널 docker 이식성: 공식베이스엔 없음 → 소스빌드 옵트인 레이어.

## 13. 빌드 순서

**레이어 순서(먼저): 프론트 → 백엔드.** 구현은 **프론트(Claude)부터** 시작한다. §9 API 계약에 대고 **mock 데이터**로 6화면(§9.1)을 먼저 만들어 UX를 확정 → 그 프론트+계약이 **Codex 백엔드 스펙**이 된다. 이후 Codex가 §9 엔드포인트를 그 계약대로 구현(mock→real). 프론트는 처음부터 `fetch('/api/...')`를 쓰되, 백엔드 부재 시 `window.MOCK` 폴백으로 단독 동작.

**기능(수직) 순서 — 백엔드 구현 시 Codex가 따를 순서:**
1. **타겟+접속(wifi/DDS/distro) + generate(cyclonedds.xml·launch.sh·alias) + 네이티브 rqt/rviz 실행**(seed `.rviz`). ← 즉시 유용(tron-rviz 일반화).
2. **distro-mismatch docker 자동**(humble Orin ↔ jazzy 호스트).
3. **템플릿**(블록 조립→`.rviz`, "편집"=네이티브 Qt) + **토픽 페이지**(`.rviz` 읽기/쓰기).
4. **ttyd Claude 터미널 + 자동채움**.

## 14. 참고 출처
- Nav2 param/튜닝: navigation2#956 · mppi_controller/README · docs.nav2.org · automaticaddison nav2 tuning · sutharsan-311/nav2_config(후속 yaml 왕복 참고)
- DDS: cyclonedds.io config_file_reference · docs.ros Improved-Dynamic-Discovery · tuw-robotics/ros2_cyclonedds_wireguard
- 시나리오 viz: docs.nav2.org costmap_2d/mppi/collision_monitor · slam_toolbox · FAST_LIO_LOCALIZATION(정합 fitness)
- 터미널: tsl0922/ttyd · Filip-Kin/claude-terminal
- 현행 자산(일반화 대상): `~/.local/bin/tron-rviz`, `rviz_tron1.sh`, `cyclonedds_tron1.xml`, `jetson-002-rviz-monitor/`, `tron_rviz_panels`
```
