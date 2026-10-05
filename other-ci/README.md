# 기타 CI, CI 없는 환경 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

CircleCI, Buildkite, Drone, TeamCity처럼 **Orbit CLI가 빌드 좌표를 자동으로 인식하지 못하는 CI**와, CI 없이 손으로 하는 빌드를 위한 예제입니다. 전용 예제가 있는 도구는 그쪽이 더 짧습니다: [Jenkins](../jenkins), [GitLab CI](../gitlab-ci), [GitHub Actions](../github-actions), [Tekton](../tekton).

- 샘플 파일: [`orbit-gate.sh`](orbit-gate.sh)
- 공통 사전 준비(CI 인증 키, CLI 이미지 digest, 공통 원칙)는 [저장소 README](../README.md)를 먼저 읽습니다.

## 사전 준비

### 자격 두 개를 환경변수로 넣기

| 변수 | 값 |
|---|---|
| `ORBIT_CLIENT_ID` | CI 인증 키의 client_id |
| `ORBIT_CLIENT_SECRET` | CI 인증 키의 client_secret |

CI의 비밀 저장소에 넣고 주입합니다. `--client-secret` 옵션으로 넘기면 프로세스 목록에 노출됩니다.

**컨테이너는 러너의 환경변수를 물려받지 않습니다.** CI 변수로 등록했더라도 `-e`로 넘기지 않으면 CLI가 보지 못합니다. `GATE 오류`만 반복되는 가장 흔한 원인입니다. 샘플의 `-e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET`이 그 역할을 합니다.

> 비어 있는 변수를 `-e`로 넘기지 않습니다. `export ORBIT_ADDRESS=`처럼 비워 둔 줄 하나가 이미지에 들어 있는 서버 주소를 지웁니다.

로컬에서 손으로 실행할 때는 저장소 밖의 파일에 두고 읽습니다.

```sh
set -a; . ~/.config/orbit/creds; set +a     # chmod 600
```

### 파이프라인 식별값 정하기

이 환경에서 가장 중요한 결정입니다. `--pipeline-ref`를 주지 않으면 그 빌드는 어느 파이프라인 줄에도 쌓이지 않습니다. 다음 형태로 직접 정하고 고정합니다.

```text
{호스트}/{프로젝트 경로}/{파이프라인 정의}

circleci.com/example/myapp/build
buildkite.com/example/myapp/deploy
manual/example/myapp/release          ← 수동 빌드
```

- 실행마다 바뀌는 값(커밋, 빌드 번호, 브랜치)을 넣지 않습니다. 줄이 매번 갈라집니다. 그 자리는 `--ci-run-id`입니다.
- 지정한 값은 정규화되지 않습니다. 조직 안에서 표기를 통일합니다. 대소문자나 끝의 슬래시가 다르면 다른 줄로 쌓입니다.

## 샘플 사용법

1. [`orbit-gate.sh`](orbit-gate.sh)의 변수를 바꿉니다.
   - `IMAGE`, `ORBIT_CLI_IMAGE`(`<64자 hex>`에 digest), `PIPELINE_REF`, `SOURCE_REF`
2. CI 설정에서 스크립트를 빌드 단계로 실행하거나, 내용을 기존 스크립트에 붙입니다.
3. 실행합니다.

### 단계 설명

| 순서 | 하는 일 |
|:-:|---|
| 1 | 이미지를 만들어 로컬에만 둡니다(push하지 않음). |
| 2 | 최종 이미지 참조를 붙입니다. |
| 3 | 이미지를 스캔해 판정을 받고 결과를 `gate.json`에 저장합니다. |
| 4 | 종료 코드가 `0`이 아니면 스크립트를 중단합니다. |
| 5 | 판정을 통과한 이미지를 그대로 push합니다. |
| 6 | 선택. 확정 digest를 서버에 보고해 런타임 이미지와 연결합니다. |

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

먼저 `orbit doctor`를 실행합니다.

```sh
docker run --rm -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET \
  "$ORBIT_CLI_IMAGE" doctor --pipeline-ref "circleci.com/example/myapp/build"
```

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `--pipeline-ref`가 빠졌습니다. |
| 매 빌드가 다른 줄로 잡힘 | `--pipeline-ref`에 커밋이나 빌드 번호가 섞였습니다. |
| `sourceRef`가 비어 있음 | 없다는 경고는 나오지 않습니다. `--source-ref`를 지정합니다. |
| `permission denied … docker.sock` | `--group-add`가 빠졌습니다. |
| 취약점 0건으로 통과 | SBOM이 비었을 수 있습니다. 빌드 산출물이 이미지에 들어갔는지 확인합니다. |

## 다음 단계

- 컨테이너 없이 바이너리로 실행: TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
- 도입 초기에 차단하지 않고 판정만 확인하는 방법: TBD
