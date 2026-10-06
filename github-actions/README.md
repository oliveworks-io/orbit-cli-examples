# GitHub Actions 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

GitHub Actions 워크플로에 Orbit CLI 빌드 게이트를 붙이는 예제입니다.

| 순서 | 파일 | 용도 |
|:-:|---|---|
| 1 | (없음) | **dry-run.** 이 도구용 cli-test 파일은 없습니다. 아래 "1단계"처럼 로컬에서 `version`, `doctor`를 실행해 봅니다. |
| 2 | [`orbit-gate.yml`](orbit-gate.yml) | **본적용 템플릿.** 자기 저장소의 `.github/workflows/`에 복사해 씁니다. 이미지를 판정하고(`scan image`), 올린 뒤 확정 digest를 보고합니다(`scan promote`). |

공통 사전 준비(CI 인증 키, CLI 이미지 digest, 레지스트리)와 공통 원칙은 [저장소 README](../README.md)에 있습니다.

## 사전 준비

### 값 등록

`Settings` > `Secrets and variables` > `Actions`에서 등록합니다.

| 탭 | 이름 | 값 |
|---|---|---|
| **Variables** | `ORBIT_CLIENT_ID` | CI 인증 키의 client_id |
| **Secrets** | `ORBIT_CLIENT_SECRET` | CI 인증 키의 client_secret |
| **Variables** | `REGISTRY_USERNAME` | 레지스트리 사용자 이름. `REGISTRY_LOGIN`이 `credentials`일 때만 |
| **Secrets** | `REGISTRY_TOKEN` | 레지스트리 액세스 토큰. `REGISTRY_LOGIN`이 `credentials`일 때만 |
| **Variables** | `IMAGE`, `IMAGE_TAG`, `REGISTRY_LOGIN` | 본적용 입력값(선택). 여기에 넣으면 파일을 고치지 않아도 됩니다. |

### 러너 조건

- Docker가 있는 러너가 필요합니다. `ubuntu-latest`(GitHub 호스티드 러너)를 기준으로 작성했습니다.
- 자체 호스팅 러너나 폐쇄망이면 CLI 이미지를 내부 레지스트리에 미러링합니다. TBD
- 템플릿은 도커 소켓 그룹 ID를 셸에서 `stat`으로 잽니다. 자체 호스팅 러너가 dind 구성이면 이 측정이 실패하므로, 다른 템플릿처럼 컨테이너를 띄워 재는 방식으로 바꿉니다. [저장소 README](../README.md)의 공통 원칙 7번을 참고합니다.

## 1단계: dry-run (로컬)

자격과 CLI 이미지가 정상인지 CI를 거치지 않고 확인합니다. 서버에 접속하지 않습니다.

```sh
ORBIT_CLI_IMAGE='ghcr.io/oliveworks-io/orbit-cli:2.0.1@sha256:ce55fd53b389998ee2fa125ca6e5baf944384c1f9c56f5ff2c8e9bbe1e6aceca'
docker run --rm "$ORBIT_CLI_IMAGE" version
docker run --rm -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET "$ORBIT_CLI_IMAGE" doctor --image "<본적용에 쓸 IMAGE>:test"
```

- 로컬에는 GitHub의 환경변수가 없어 `doctor`의 파이프라인 식별값은 `system:…`(오류)로 나옵니다. 이 항목은 워크플로 안에서 실행될 때 해소되므로, 여기서는 자격과 이미지 좌표 항목만 봅니다.
- `scan file`로 서버 판정까지 확인하려면 [Jenkins](../jenkins)나 [GitLab CI](../gitlab-ci)의 cli-test를 씁니다.

## 2단계: 본적용 (`orbit-gate.yml`)

1. [`orbit-gate.yml`](orbit-gate.yml)을 자기 저장소의 `.github/workflows/`에 복사합니다. 이 저장소로 시연할 때는 fork한 뒤 같은 위치에 복사합니다.
2. 입력값을 정합니다. 같은 이름의 Variables로 넣거나, `env` 맨 위 "여기만 바꿉니다" 블록의 기본값을 고칩니다. 자리표시(`<…>`)가 남아 있으면 해당 스텝에서 무엇을 넣어야 하는지 알려 주고 멈춥니다.

   | 변수 | 값 | 채우지 않으면 |
   |---|---|---|
   | `IMAGE` | 판정하고 올릴 이미지. 예: `registry.example.com/team/myapp` | Tag 스텝에서 멈춤 |
   | `IMAGE_TAG` | 태그. 비우면 커밋 해시 | 커밋 해시 사용 |
   | `REGISTRY_LOGIN` | `credentials`(자격으로 로그인) 또는 `none`(로그인하지 않음) | Push 스텝에서 멈춤 |

   가입 없이 시연할 때는 `IMAGE=ttl.sh/orbit/orbit-gate-hello-<임의 문자열>`, `IMAGE_TAG=1h`, `REGISTRY_LOGIN=none`입니다. ttl.sh에 올린 이미지는 누구나 받을 수 있습니다.
3. 자기 프로젝트라면 Build 스텝의 `context`를 자기 Dockerfile 위치에 맞춥니다.
4. main에 push해 워크플로를 실행합니다.

| 스텝 | 하는 일 |
|---|---|
| Build (load only) | `push: false`로 이미지를 만들어 로컬에만 둡니다. |
| Tag with final ref | 최종 이미지 참조(`IMAGE:IMAGE_TAG`, 태그를 비우면 커밋 해시)를 붙입니다. `IMAGE`를 채우지 않았으면 멈춥니다. |
| Orbit Security (scan image) | 이미지를 스캔해 판정을 받고 `gate.json`에 저장한 뒤 출력합니다. 종료 코드가 `0`이 아니면 멈춥니다. |
| Upload gate result | `gate.json`을 artifact(`orbit-gate`)로 보관합니다. 차단·오류여도 실행됩니다. 차단 사유는 이 출력이 유일한 기록입니다. |
| Push | 판정한 이미지를 그대로 올립니다. `REGISTRY_LOGIN`이 `credentials`면 로그인합니다. |
| Orbit Promote (scan promote) | `gate.json`의 requestId와 push된 digest를 보고합니다. 값이 없으면 건너뜁니다. |

스텝은 서로의 출력에 기대지 않아 필요 없는 스텝은 지워도 됩니다(Build·Tag는 남겨 둡니다).

### 지켜야 할 것

1. **빌드는 `push: false`**로 합니다. 판정 전에 레지스트리에 올라가면 게이트의 의미가 없습니다.
2. **판정 전에 최종 참조로 태그**합니다. 하지 않으면 이미지 좌표가 `docker.io/library/…:candidate`로 남습니다.
3. **판정한 그 이미지를 그대로 push**합니다. 다시 빌드해서 올리면 digest가 어긋납니다.

## 동작 확인

워크플로를 한 번 실행하고 `gate.json` 출력에서 확인합니다.

| 확인할 것 | 정상 |
|---|---|
| `pipelineRef` | `github.com/…/.github/workflows/…yml`처럼 GitHub 주소로 시작합니다. `system:`으로 시작하면 실패입니다. |
| `image` | `registry`, `namespace`, `name`, `tag`가 모두 차 있어야 합니다. |
| `image.platform` | 러너의 아키텍처와 같아야 합니다(`linux/amd64`, ARM 러너면 `linux/arm64`). |
| 스텝 결과 | 통과면 성공, 차단이면 워크플로가 여기서 멈춥니다. |

## 문제 해결

워크플로 안에서 점검하려면 Tag 스텝 앞에 아래 스텝을 잠시 넣습니다. 서버에 접속하지 않고 좌표와 자격 해석 결과만 보여 줍니다.

```yaml
      - name: Orbit Doctor
        env:
          ORBIT_CLIENT_ID: ${{ vars.ORBIT_CLIENT_ID }}
          ORBIT_CLIENT_SECRET: ${{ secrets.ORBIT_CLIENT_SECRET }}
        run: docker run --rm $ORBIT_ENV_ARGS "$ORBIT_CLI_IMAGE" doctor --image "$IMAGE:${IMAGE_TAG:-$GITHUB_SHA}"
```

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `-e GITHUB_*` 전달이 빠졌습니다. |
| `IMAGE를 설정하십시오`로 멈춤 | Variables의 `IMAGE`나 `env`의 기본값을 채웁니다. |
| `REGISTRY_LOGIN을 정하십시오`로 멈춤 | `credentials` 또는 `none`을 넣습니다. |
| `permission denied … docker.sock` | `--group-add`가 빠졌습니다. |
| `인증 자격이 없다`로 중단됨 | 자격이 컨테이너에 전달되지 않았습니다. Variables와 Secrets 이름, `-e` 전달을 확인합니다. |
| `분석된 패키지가 0개다`로 중단됨(`2`) | 이미지에서 패키지를 찾지 못했습니다. 빌드 산출물이 이미지에 들어갔는지 확인합니다. 빈 SBOM은 통과시키지 않습니다. |
| Promote에서 `409` | 판정한 이미지와 push한 이미지가 다릅니다. |

## 다음 단계

- 멀티 아키텍처: TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
- 도입 초기에 차단하지 않고 판정만 확인하는 방법: TBD
