# Tekton Pipelines 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

Tekton Task로 Orbit CLI 빌드 게이트를 실행하는 예제입니다. 데몬 없이 이미지를 빌드하고 게이트가 그 이미지를 읽도록 **podman sidecar** 구성을 씁니다. 노드의 도커 소켓은 필요 없습니다.

| 순서 | 파일 | 용도 |
|:-:|---|---|
| 1 | (없음) | **dry-run.** 이 도구용 cli-test 파일은 없습니다. 아래 "1단계"처럼 `version`, `doctor`를 실행해 봅니다. |
| 2 | [`orbit-build-gate-task.yaml`](orbit-build-gate-task.yaml) | **본적용 템플릿.** 클러스터에 Task로 등록해 씁니다. 이미지를 판정하고(`scan image`), 올린 뒤 확정 digest를 보고합니다(`scan promote`). |

공통 사전 준비(CI 인증 키, CLI 이미지 digest, 레지스트리)와 공통 원칙은 [저장소 README](../README.md)에 있습니다.

- **JayeX(구 Jenkins X)**도 엔진이 Tekton이라 이 예제를 그대로 씁니다. 다만 JayeX의 기본 빌더는 Kaniko라서 템플릿의 `build` step만 달라집니다. Kaniko 기반 `build` step 예제는 TBD입니다.

## 사전 준비

### 자격을 Secret으로 만들기

```sh
kubectl -n orbit-ci create secret generic orbit-creds \
  --from-literal=ORBIT_CLIENT_ID='<client_id>' \
  --from-literal=ORBIT_CLIENT_SECRET='<client_secret>'
```

params의 `registry-login`을 `credentials`로 할 때만 레지스트리 자격도 만듭니다. `none`이면 필요 없습니다.

```sh
kubectl -n orbit-ci create secret generic registry-creds \
  --from-literal=REGISTRY_USERNAME='<레지스트리 사용자 이름>' \
  --from-literal=REGISTRY_TOKEN='<액세스 토큰>'
```

조직 ID와 서버 주소는 등록하지 않습니다. 인증 토큰과 CLI 이미지에 이미 들어 있습니다.

### 파이프라인 식별값 정하기

Tekton은 빌드 좌표를 **자동으로 인식하지 못합니다.** `--pipeline-ref`를 주지 않으면 그 빌드는 어느 빌드 이력에도 쌓이지 않으므로 다음 형태로 직접 정해서 고정합니다.

```text
{클러스터}/{네임스페이스}/{Task 또는 Pipeline 이름}

my-cluster/orbit-ci/orbit-build-gate
```

- 실행마다 바뀌는 값(TaskRun 이름, 커밋 SHA)을 넣지 않습니다. 그 자리는 `--ci-run-id`이고, 템플릿은 TaskRun 이름을 씁니다.
- 지정한 값은 CLI가 정규화하지 않습니다. canonical 형이 아니면(스킴 `https://`, 대문자, 빈 세그먼트, 앞뒤 공백) 서버가 `400`(`pipelineRef is not canonical`)으로 거부합니다.

## 1단계: dry-run

자격, 빌드 좌표, 이미지 좌표가 정상인지 Task를 돌리기 전에 확인합니다. 서버에 접속하지 않습니다. Docker가 있는 기계에서 실행합니다.

```sh
ORBIT_CLI_IMAGE='ghcr.io/oliveworks-io/orbit-cli:2.0.1@sha256:ce55fd53b389998ee2fa125ca6e5baf944384c1f9c56f5ff2c8e9bbe1e6aceca'
docker run --rm "$ORBIT_CLI_IMAGE" version
docker run --rm -e ORBIT_CLIENT_ID -e ORBIT_CLIENT_SECRET "$ORBIT_CLI_IMAGE" \
  doctor --pipeline-ref "my-cluster/orbit-ci/orbit-build-gate" \
         --source-ref   "github.com/example/myapp" \
         --image        "<본적용에 쓸 image-ref>"
```

마지막 줄이 `오류 0`이면 본적용으로 넘어갑니다. `scan file`로 서버 판정까지 확인하려면 [Jenkins](../jenkins)나 [GitLab CI](../gitlab-ci)의 cli-test를 씁니다.

## 2단계: 본적용 (`orbit-build-gate-task.yaml`)

1. 입력값을 정합니다. 맨 위 "여기만 바꿉니다" 블록의 `params` 기본값을 고치거나, 실행할 때 `--param`으로 넘깁니다. 자리표시(`<…>`)가 남아 있으면 build step(`registry-login`은 push step)에서 무엇을 넣어야 하는지 알려 주고 멈춥니다.

   | param | 값 | 채우지 않으면 |
   |---|---|---|
   | `image-ref` | 판정하고 올릴 이미지 참조(태그 포함). 예: `registry.example.com/team/myapp:<커밋>` | build에서 멈춤 |
   | `pipeline-ref` | 위 "파이프라인 식별값" | build에서 멈춤 |
   | `source-ref` | 소스 저장소 좌표. 예: `github.com/example/myapp` | build에서 멈춤 |
   | `registry-login` | `credentials`(Secret `registry-creds`로 로그인) 또는 `none`(로그인하지 않음) | push에서 멈춤 |
   | `git-commit` | 빌드한 소스의 전체 커밋 해시. 기본값이 없어 실행할 때마다 넘깁니다. | Task 시작 거부 |

   가입 없이 시연할 때는 `image-ref=ttl.sh/orbit/orbit-gate-hello-<임의 문자열>:1h`, `registry-login=none`입니다. ttl.sh에 올린 이미지는 누구나 받을 수 있습니다.
2. Task를 만듭니다.

   ```sh
   kubectl apply -f orbit-build-gate-task.yaml
   ```

3. 실행합니다. `source` 워크스페이스에는 빌드할 저장소(Dockerfile 포함)가 체크아웃되어 있어야 합니다.

   ```sh
   tkn task start orbit-build-gate -n orbit-ci \
     --param image-ref=ttl.sh/orbit/orbit-gate-hello-<임의 문자열>:1h \
     --param pipeline-ref=my-cluster/orbit-ci/orbit-build-gate \
     --param source-ref=github.com/example/myapp \
     --param registry-login=none \
     --param git-commit=<전체 커밋 해시> \
     --workspace name=source,claimName=<저장소를 체크아웃한 PVC> --showlog
   ```

| step | 하는 일 |
|---|---|
| build | 입력값을 검사하고, buildah로 이미지를 만들어 최종 참조로 태그합니다(push하지 않음). 플랫폼을 결과로 넘깁니다. |
| gate | CLI로 이미지를 스캔해 판정을 받고 `gate.json`에 저장합니다. 차단이어도 다음 step이 돌도록 `onError: continue`로 둡니다. |
| verdict | gate의 종료 코드를 읽어 `0`이 아니면 Task를 실패시킵니다. |
| push | 판정한 이미지를 그대로 올리고(`registry-login`이 `credentials`면 `registry-creds`로 로그인), digest와 `gate.json`의 requestId를 결과로 넘깁니다. |
| promote | push가 넘긴 digest와 requestId를 보고합니다. |

Tekton은 다른 step의 결과를 참조하면 그 step이 반드시 있어야 합니다. 그래서 **build를 지우면 gate도, push를 지우면 promote도 함께 지웁니다.** 나머지 step은 따로 지워도 됩니다.

### 지켜야 할 것

1. **`--root`와 `--runroot`를 buildah와 podman이 똑같이** 씁니다. `--root`만 맞추면 실패합니다.
2. **`runAsUser: 0`**을 씁니다. 볼륨 위 스토리지에서 rootless는 mount 제약에 걸립니다.
3. **sidecar에 `readinessProbe`를 둡니다.** 소켓 준비 경합이 구조적으로 사라집니다. `sleep`으로 대신하지 않습니다.
4. **CLI step은 `args`만 씁니다.** CLI 이미지에 셸이 없습니다. gate step은 차단돼도 verdict step이 돌도록 `onError: continue`로 둡니다.
5. **`--pipeline-ref`는 고정하고 `--ci-run-id`는 매번 다르게** 합니다.
6. **`source-ref`와 `git-commit`을 넘깁니다.** Tekton은 소스 좌표를 자동으로 얻지 못하고 gate step에는 `.git`도 없습니다. 빠지면 소스 좌표가 경고 없이 비어서 나갑니다.

## 동작 확인

| 확인할 것 | 정상 |
|---|---|
| `pipelineRef` | 직접 정한 값 그대로입니다. `system:`으로 시작하면 실패입니다. |
| `image` | `registry`, `namespace`, `name`, `tag`가 모두 차 있어야 합니다. |

## 문제 해결

먼저 1단계의 `doctor`를 다시 실행해 좌표와 자격 해석 결과를 봅니다. 클러스터 안에서 점검하려면 gate step의 `args`를 `[doctor, --pipeline-ref=$(params.pipeline-ref), --source-ref=$(params.source-ref), --image=$(params.image-ref)]`로 잠시 바꿉니다.

| 증상 | 조치 |
|---|---|
| `params의 image-ref, pipeline-ref, source-ref를 설정하십시오`로 멈춤 | 세 params를 채웁니다. |
| `params의 registry-login을 정하십시오`로 멈춤 | `credentials` 또는 `none`을 넣습니다. |
| `pipelineRef`가 `system:`으로 시작 | `--pipeline-ref`가 빠졌습니다. |
| `pipelineRef is not canonical`(`400`) | 오류가 알려 주는 `canonical` 값을 그대로 씁니다. |
| `database runroot … does not match` | `--runroot`가 컨테이너마다 다릅니다. |
| sidecar가 `ready`가 되지 않음 | probe의 소켓 경로와 `unix://` 경로를 맞춥니다. |
| `분석된 패키지가 0개다`로 중단됨(`2`) | 이미지에서 패키지를 찾지 못했습니다. 빌드 산출물이 이미지에 들어갔는지 확인합니다. 빈 SBOM은 통과시키지 않습니다. |

## 다음 단계

- 노드 도커 소켓을 쓰는 구성: TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
