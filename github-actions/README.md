# GitHub Actions 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

워크플로에 Orbit CLI 빌드 게이트를 붙이는 예제입니다. 워크플로를 새로 만들 필요는 없고, 기존 워크플로에 **빌드, 태그, 판정, push, 보고 스텝**을 끼워 넣습니다.

- 샘플 파일: [`orbit-gate.yml`](orbit-gate.yml) (저장소의 `.github/workflows/` 아래에 두는 형태입니다)
- 공통 사전 준비(CI 인증 키, CLI 이미지 digest, 공통 원칙)는 [저장소 README](../README.md)를 먼저 읽습니다.

## 사전 준비

### 자격 두 개 등록

`Settings` > `Secrets and variables` > `Actions`에서 등록합니다.

| 탭 | 이름 | 값 |
|---|---|---|
| **Variables** | `ORBIT_CLIENT_ID` | CI 인증 키의 client_id |
| **Secrets** | `ORBIT_CLIENT_SECRET` | CI 인증 키의 client_secret |

### 러너 조건

- Docker가 있는 러너가 필요합니다. `ubuntu-latest`(GitHub 호스티드 러너)를 기준으로 작성했습니다.
- 자체 호스팅 러너나 폐쇄망이면 CLI 이미지를 내부 레지스트리에 미러링합니다. TBD

## 샘플 사용법

1. [`orbit-gate.yml`](orbit-gate.yml)의 `env`에서 값을 바꿉니다.
   - `IMAGE`: 배포할 이미지 이름
   - `ORBIT_CLI_IMAGE`: `<64자 hex>` 자리에 확인한 digest 입력
2. 기존 워크플로에는 체크아웃 스텝 뒤에 `Build`, `Tag`, `Orbit Security`, `Push`, `Promote` 스텝을 끼워 넣고, 기존의 push 스텝은 샘플의 `Push` 스텝으로 바꿉니다.
3. 워크플로를 실행합니다.

### 스텝 설명

| 스텝 | 하는 일 |
|---|---|
| Build (load only) | `push: false`로 이미지를 만들어 로컬에만 둡니다. |
| Tag with final ref | 최종 이미지 참조(`IMAGE:커밋`)를 붙입니다. |
| Orbit Security | 이미지를 스캔해 판정을 받고 `gate.json`에 저장합니다. 종료 코드가 `0`이 아니면 스텝이 실패해 워크플로가 멈춥니다. |
| Push | 판정을 통과한 이미지를 그대로 push하고 확정 digest를 읽습니다. |
| Promote | 선택. 확정 digest를 서버에 보고해 런타임 이미지와 연결합니다. |

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

먼저 `orbit doctor`를 실행합니다.

```sh
docker run --rm \
  -e GITHUB_SERVER_URL -e GITHUB_REPOSITORY -e GITHUB_WORKFLOW_REF \
  -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET \
  "$ORBIT_CLI_IMAGE" doctor
```

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `-e GITHUB_*` 전달이 빠졌습니다. |
| `permission denied … docker.sock` | `--group-add`가 빠졌습니다. |
| `GATE 오류`만 반복 | 자격이 비어 판정이 일어나지 않았습니다. Variables와 Secrets 이름을 확인합니다. |
| 취약점 0건으로 통과 | SBOM이 비었을 수 있습니다. 빌드 산출물이 이미지에 들어갔는지 확인합니다. |
| Promote에서 `409` | 판정한 이미지와 push한 이미지가 다릅니다. |

## 다음 단계

- 멀티 아키텍처: TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
- 도입 초기에 차단하지 않고 판정만 확인하는 방법: TBD
