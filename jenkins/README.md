# Jenkins 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

Declarative Pipeline에 Orbit CLI 빌드 게이트를 붙이는 예제입니다. 파이프라인을 새로 만들 필요는 없고, 기존 파이프라인에 **Tag, Orbit Security, Promote 단계**를 끼워 넣습니다.

- 샘플 파일: [`Jenkinsfile`](Jenkinsfile)
- 공통 사전 준비(CI 인증 키, CLI 이미지 digest, 공통 원칙)는 [저장소 README](../README.md)를 먼저 읽습니다.

## 사전 준비

### 자격 두 개 등록

`Manage Jenkins` > `Credentials` > 대상 도메인 > `Add Credentials`에서 두 개를 등록합니다.

| ID | Kind | Secret |
|---|---|---|
| `orbit-client-id` | **Secret text** | CI 인증 키의 client_id |
| `orbit-client-secret` | **Secret text** | CI 인증 키의 client_secret |

> 반드시 `Secret text`로 등록합니다. Username/Password로 등록하면 `credentials()`가 `_USR`, `_PSW` 접미 변수를 만들어 변수 이름이 어긋납니다.

### 에이전트 조건

- Docker를 실행할 수 있는 에이전트가 필요합니다(도커 소켓 `/var/run/docker.sock` 사용).
- CLI 이미지를 내려받을 수 있어야 합니다. 폐쇄망이면 내부 레지스트리에 미러링합니다. TBD

## 샘플 사용법

1. [`Jenkinsfile`](Jenkinsfile)의 `environment`에서 값을 바꿉니다.
   - `IMAGE`: 배포할 이미지 이름
   - `ORBIT_CLI_IMAGE`: `<64자 hex>` 자리에 확인한 digest 입력
2. 기존 Jenkinsfile의 빌드 단계를 샘플의 `Build`, `Tag`, `Orbit Security`, `Push`, `Promote` 순서로 맞춥니다.
3. 파이프라인을 실행합니다.

### 단계 설명

| 단계 | 하는 일 |
|---|---|
| Build | 이미지를 만들어 로컬에만 둡니다(push하지 않음). |
| Tag | 최종 이미지 참조(`IMAGE:커밋`)를 붙입니다. |
| Orbit Security | 이미지를 스캔해 판정을 받습니다. 종료 코드가 `0`이 아니면 `error()`로 중단합니다. 결과는 `gate.json`에 저장합니다. |
| Push | 판정을 통과한 이미지를 그대로 push하고 확정 digest를 읽습니다. |
| Promote | 선택. 확정 digest를 서버에 보고해 런타임 이미지와 연결합니다. |

### 지켜야 할 것

1. **빌드는 push 없이** 합니다. 판정 전에 올라가면 게이트의 의미가 없습니다.
2. **판정 전에 최종 참조로 태그**합니다. 하지 않으면 이미지 좌표가 `docker.io/library/…:candidate`로 남습니다.
3. **`returnStatus: true`를 씁니다.** 쓰지 않으면 `sh`가 차단(exit 1)에서 바로 죽어 결과를 볼 수 없습니다.
4. **`0`이 아니면 `error()`로 중단**합니다. `2`(오류)도 통과가 아닙니다.

## 동작 확인

파이프라인을 한 번 실행하고 `gate.json`에서 확인합니다.

| 확인할 것 | 정상 |
|---|---|
| `pipelineRef` | `jenkins.example.com/myapp-release`처럼 Jenkins 주소와 잡 이름으로 시작합니다. `system:`으로 시작하면 실패입니다. |
| `sourceRef` | `GIT_URL`이 있어야 채워집니다. |
| `image` | `registry`, `namespace`, `name`, `tag`가 모두 차 있어야 합니다. |

> `GIT_URL`, `GIT_COMMIT`은 `checkout scm` 없이 수동으로 `git`을 호출하는 파이프라인에서는 주입되지 않을 수 있습니다.

## 문제 해결

먼저 `orbit doctor`를 실행합니다. 서버에 접속하지 않고 좌표와 자격 해석 결과만 보여 줍니다.

```groovy
sh '''docker run --rm \
  -e JENKINS_URL -e JOB_NAME -e GIT_URL -e GIT_COMMIT \
  -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET \
  "$ORBIT_CLI_IMAGE" doctor'''
```

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `-e JENKINS_URL`, `-e JOB_NAME`이 빠졌습니다. |
| `sourceRef`가 비어 있음 | `checkout scm`을 쓰거나 `--source-ref`를 지정합니다. |
| 자격 변수에 `_USR`, `_PSW`가 붙음 | Credentials 유형을 `Secret text`로 바꿉니다. |
| 차단인데 단계가 그냥 실패함 | `returnStatus: true`가 빠졌습니다. |
| 취약점 0건으로 통과 | SBOM이 비었을 수 있습니다. 빌드 산출물이 이미지에 들어갔는지 확인합니다. |
| Promote에서 `409` | 판정한 이미지와 push한 이미지가 다릅니다. 다시 빌드해서 올리지 않았는지 확인합니다. |

## 다음 단계

- 쿠버네티스 에이전트: TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
- 도입 초기에 차단하지 않고 판정만 확인하는 방법: TBD
