# 기타 CI, CI 없는 환경 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

CircleCI, Buildkite, Drone, TeamCity처럼 **Orbit CLI가 빌드 좌표를 자동으로 인식하지 못하는 CI**와, CI 없이 손으로 하는 빌드를 위한 예제입니다. Azure Pipelines는 자동 인식 대상이므로 이 예제를 쓰더라도 `--pipeline-ref`를 직접 지정하지 않습니다. 전용 예제가 있는 도구는 그쪽이 더 짧습니다: [Jenkins](../jenkins), [GitLab CI](../gitlab-ci), [GitHub Actions](../github-actions), [Tekton](../tekton).

| 순서 | 파일 | 용도 |
|:-:|---|---|
| 1 | (없음) | **dry-run.** 이 도구용 cli-test 파일은 없습니다. 아래 "1단계"처럼 `version`, `doctor`를 실행해 봅니다. |
| 2 | [`orbit-gate.sh`](orbit-gate.sh) | **본적용 템플릿.** CI의 빌드 단계에서 실행하거나 내용을 기존 스크립트에 붙입니다. 이미지를 판정하고(`scan image`), 올린 뒤 확정 digest를 보고합니다(`scan promote`). |

공통 사전 준비(CI 인증 키, CLI 이미지 digest, 레지스트리)와 공통 원칙은 [저장소 README](../README.md)에 있습니다.

## 사전 준비

### 자격을 환경변수로 넣기

| 변수 | 값 |
|---|---|
| `ORBIT_CLIENT_ID` | CI 인증 키의 client_id |
| `ORBIT_CLIENT_SECRET` | CI 인증 키의 client_secret |
| `REGISTRY_USERNAME` | 레지스트리 사용자 이름. `REGISTRY_LOGIN`이 `credentials`일 때만 |
| `REGISTRY_TOKEN` | 레지스트리 액세스 토큰. `REGISTRY_LOGIN`이 `credentials`일 때만 |

CI의 비밀 저장소에 넣고 주입합니다. `--client-secret` 옵션으로 넘기면 프로세스 목록에 노출됩니다.

**컨테이너는 러너의 환경변수를 물려받지 않습니다.** CI 변수로 등록했더라도 `-e`로 넘기지 않으면 CLI가 보지 못합니다. `인증 자격이 없다`로 중단되는 가장 흔한 원인입니다. 템플릿의 `-e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET`이 그 역할을 합니다.

> 비어 있는 변수를 `-e`로 넘기지 않습니다. `export ORBIT_ADDRESS=`처럼 비워 둔 줄 하나가 이미지에 들어 있는 서버 주소를 지웁니다.

로컬에서 손으로 실행할 때는 저장소 밖의 파일에 두고 읽습니다.

```sh
set -a; . ~/.config/orbit/creds; set +a     # chmod 600
```

### 파이프라인 식별값 정하기

이 환경에서 가장 중요한 결정입니다. `--pipeline-ref`를 주지 않으면 그 빌드는 어느 빌드 이력에도 쌓이지 않습니다. 다음 형태로 직접 정하고 고정합니다.

```text
{호스트}/{프로젝트 경로}/{파이프라인 정의}

circleci.com/example/myapp/build
buildkite.com/example/myapp/deploy
manual/example/myapp/release          ← 수동 빌드
```

- 실행마다 바뀌는 값(커밋, 빌드 번호, 브랜치)을 넣지 않습니다. 빌드마다 이력이 따로 만들어집니다. 그 자리는 `--ci-run-id`입니다.
- 지정한 값은 CLI가 정규화하지 않습니다. canonical 형이 아니면(스킴 `https://`, 대문자, 빈 세그먼트, 앞뒤 공백) 서버가 `400`(`pipelineRef is not canonical`)으로 거부하며, 오류 상세에 올바른 값이 함께 내려옵니다.

## 1단계: dry-run

자격, 빌드 좌표, 이미지 좌표가 정상인지 이미지를 만들지 않고 확인합니다. 서버에 접속하지 않습니다.

```sh
ORBIT_CLI_IMAGE='ghcr.io/oliveworks-io/orbit-cli:2.0.1@sha256:ce55fd53b389998ee2fa125ca6e5baf944384c1f9c56f5ff2c8e9bbe1e6aceca'
docker run --rm "$ORBIT_CLI_IMAGE" version
docker run --rm -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET "$ORBIT_CLI_IMAGE" \
  doctor --pipeline-ref "circleci.com/example/myapp/build" \
         --source-ref   "github.com/example/myapp" \
         --image        "<본적용에 쓸 IMAGE>:test"
```

마지막 줄이 `오류 0`이면 본적용으로 넘어갑니다. `scan file`로 서버 판정까지 확인하려면 [Jenkins](../jenkins)나 [GitLab CI](../gitlab-ci)의 cli-test를 씁니다.

## 2단계: 본적용 (`orbit-gate.sh`)

1. 스크립트 맨 위 "여기만 바꿉니다" 블록의 값을 정합니다. 같은 이름의 환경변수로 넘기면 파일을 고치지 않아도 됩니다. 자리표시(`<…>`)가 남아 있으면 해당 구간에서 무엇을 넣어야 하는지 알려 주고 멈춥니다.

   | 변수 | 값 | 채우지 않으면 |
   |---|---|---|
   | `IMAGE` | 판정하고 올릴 이미지. 예: `registry.example.com/team/myapp` | 태그 구간에서 멈춤 |
   | `IMAGE_TAG` | 태그. 비우면 커밋 해시 | 커밋 해시 사용 |
   | `REGISTRY_LOGIN` | `credentials`(자격으로 로그인) 또는 `none`(로그인하지 않음) | push 구간에서 멈춤 |
   | `PIPELINE_REF`, `SOURCE_REF` | 빌드 좌표(위 "파이프라인 식별값 정하기") | 판정 구간에서 멈춤 |
   | `CI_RUN_ID` | CI의 실행 번호(예: CircleCI는 `CIRCLE_BUILD_NUM`) | 실행 시각 사용 |

   가입 없이 시연할 때는 `IMAGE=ttl.sh/orbit/orbit-gate-hello-<임의 문자열>`, `IMAGE_TAG=1h`, `REGISTRY_LOGIN=none`입니다. ttl.sh에 올린 이미지는 누구나 받을 수 있습니다.
2. 자기 프로젝트라면 빌드 구간의 빌드 대상(`docker build … .`)을 자기 Dockerfile에 맞춥니다.
3. 저장소 루트에서 실행합니다. CI라면 빌드 단계에서 `sh other-ci/orbit-gate.sh`를 실행합니다.

| 순서 | 하는 일 |
|:-:|---|
| 1 | 이미지를 만들어 로컬에만 둡니다(push하지 않음). |
| 2 | 최종 이미지 참조(`IMAGE:IMAGE_TAG`, 태그를 비우면 커밋 해시)를 붙입니다. `IMAGE`를 채우지 않았으면 멈춥니다. |
| 3 | 이미지를 스캔해 판정을 받고 `gate.json`에 저장합니다. 종료 코드가 `0`이 아니면 중단합니다. |
| 4 | 판정한 이미지를 그대로 올립니다. `REGISTRY_LOGIN`이 `credentials`면 로그인합니다. |
| 5 | `gate.json`의 requestId와 push된 digest를 보고합니다. 값이 없으면 건너뜁니다. |

구간은 서로의 결과 변수에 기대지 않아 필요 없는 구간은 지워도 됩니다(빌드·태그는 남겨 둡니다).

### 지켜야 할 것

1. **`--pipeline-ref`를 고정값으로** 줍니다. 이 환경에서는 사실상 필수입니다.
2. **판정 전에 최종 참조로 태그**합니다. 하지 않으면 이미지 좌표가 `docker.io/library/…:candidate`로 남습니다.
3. **`--ci-run-id`는 실행마다 다르게** 합니다. 반대로 `--pipeline-ref`는 고정합니다.
4. **`0`이 아니면 중단**합니다. `2`(오류)도 통과가 아닙니다.

## 동작 확인

| 확인할 것 | 정상 |
|---|---|
| `pipelineRef` | 직접 정한 값 그대로입니다. `system:`으로 시작하면 실패입니다. |
| `image` | `registry`, `namespace`, `name`, `tag`가 모두 차 있어야 합니다. |
| 종료 코드 | `0` 통과, `1` 차단, `2` 오류(통과 아님) |

## 문제 해결

먼저 1단계의 `doctor`를 다시 실행해 좌표와 자격 해석 결과를 봅니다.

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `--pipeline-ref`가 빠졌습니다. |
| `IMAGE를 설정하십시오`로 멈춤 | `IMAGE`를 환경변수나 스크립트 블록에 넣습니다. |
| `PIPELINE_REF와 SOURCE_REF를 설정하십시오`로 멈춤 | 빌드 좌표를 넣습니다. |
| `REGISTRY_LOGIN을 정하십시오`로 멈춤 | `credentials` 또는 `none`을 넣습니다. |
| 매 빌드가 다른 이력으로 쌓임 | `--pipeline-ref`에 커밋이나 빌드 번호가 섞였습니다. |
| `sourceRef`가 비어 있음 | 없다는 경고는 나오지 않습니다. `--source-ref`를 지정합니다. |
| `permission denied … docker.sock` | `--group-add`가 빠졌습니다. |
| `분석된 패키지가 0개다`로 중단됨(`2`) | 이미지에서 패키지를 찾지 못했습니다. 빌드 산출물이 이미지에 들어갔는지 확인합니다. 빈 SBOM은 통과시키지 않습니다. |

## 다음 단계

- 컨테이너 없이 바이너리로 실행: TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
- 도입 초기에 차단하지 않고 판정만 확인하는 방법: TBD
