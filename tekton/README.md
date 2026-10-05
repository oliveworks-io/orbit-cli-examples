# Tekton Pipelines 예제

> [!WARNING]
> 이 예제는 Orbit CLI 사용 방법을 보여 주기 위한 샘플이며, 보안 모범 사례나 표준 파이프라인 구성이 아닙니다. 권한 범위, 시크릿 처리, 러너 격리, 버전 고정 등은 단순화했거나 생략했을 수 있습니다. 그대로 운영에 적용하지 말고 조직의 정책에 맞게 검토하고 수정한 뒤 테스트 파이프라인에서 먼저 확인하십시오. 인증 정보(`client_secret` 등)는 코드에 넣지 말고 CI의 비밀 저장소로만 주입하십시오. 자세한 내용은 [저장소 README](../README.md)를 참고하십시오.

Tekton Task로 Orbit CLI 빌드 게이트를 실행하는 예제입니다. 데몬 없이 이미지를 빌드하고 게이트가 그 이미지를 읽도록 **podman sidecar** 구성을 씁니다. 노드의 도커 소켓은 필요 없습니다.

- 샘플 파일: [`orbit-build-gate-task.yaml`](orbit-build-gate-task.yaml)
- 공통 사전 준비(CI 인증 키, CLI 이미지 digest, 공통 원칙)는 [저장소 README](../README.md)를 먼저 읽습니다.
- **JayeX(구 Jenkins X)**도 엔진이 Tekton이라 이 예제를 그대로 씁니다. 다만 JayeX의 기본 빌더는 Kaniko라서 샘플의 `build` step만 달라집니다. Kaniko 기반 `build` step 예제는 TBD입니다.

## 사전 준비

### 자격을 Secret으로 만들기

```sh
kubectl -n orbit-ci create secret generic orbit-creds \
  --from-literal=ORBIT_CLIENT_ID='<client_id>' \
  --from-literal=ORBIT_CLIENT_SECRET='<client_secret>'
```

조직 ID와 서버 주소는 등록하지 않습니다. 인증 토큰과 CLI 이미지에 이미 들어 있습니다.

### 파이프라인 식별값 정하기

Tekton은 빌드 좌표를 **자동으로 인식하지 못합니다.** `--pipeline-ref`를 주지 않으면 그 빌드는 어느 파이프라인 줄에도 쌓이지 않으므로 다음 형태로 직접 정해서 고정합니다.

```text
{클러스터}/{네임스페이스}/{Task 또는 Pipeline 이름}

my-cluster/orbit-ci/orbit-build-gate
```

- 실행마다 바뀌는 값(TaskRun 이름, 커밋 SHA)을 넣지 않습니다. 그 자리는 `--ci-run-id`입니다.
- 지정한 값은 정규화되지 않습니다. 서버가 형식을 엄격히 검증하므로 `@ref`, 끝의 슬래시, 기본 포트를 붙이면 `400` 오류가 납니다.

## 샘플 사용법

1. [`orbit-build-gate-task.yaml`](orbit-build-gate-task.yaml)에서 값을 바꿉니다.
   - `gate` step의 `image`: `<64자 hex>`에 확인한 CLI 이미지 digest 입력
   - `params`의 `image-ref`, `pipeline-ref`
2. Task를 만듭니다.

   ```sh
   kubectl apply -f orbit-build-gate-task.yaml
   ```

3. 실행합니다.

   ```sh
   tkn task start orbit-build-gate -n orbit-ci \
     --param image-ref=registry.example.com/team/myapp:sha-abc1234 \
     --workspace name=source,emptyDir= --showlog
   ```

### step 설명

| step | 하는 일 |
|---|---|
| build | buildah로 이미지를 만들어 최종 참조로 태그합니다(push하지 않음). 플랫폼을 결과로 넘깁니다. |
| gate | CLI로 이미지를 스캔해 판정을 받고 `gate.json`에 저장합니다. 차단이어도 다음 step이 돌도록 `onError: continue`로 둡니다. |
| verdict | gate의 종료 코드를 읽어 `0`이 아니면 Task를 실패시킵니다. |

### 지켜야 할 것

1. **`--root`와 `--runroot`를 buildah와 podman이 똑같이** 씁니다. `--root`만 맞추면 실패합니다.
2. **`runAsUser: 0`**을 씁니다. 볼륨 위 스토리지에서 rootless는 mount 제약에 걸립니다.
3. **sidecar에 `readinessProbe`를 둡니다.** 소켓 준비 경합이 구조적으로 사라집니다. `sleep`으로 대신하지 않습니다.
4. **gate step은 `args`만 쓰고 `onError: continue`로 둡니다.** CLI 이미지에 셸이 없고, 차단돼도 verdict step이 돌아야 합니다.
5. **`--pipeline-ref`는 고정하고 `--ci-run-id`는 매번 다르게** 합니다.

## 동작 확인

| 확인할 것 | 정상 |
|---|---|
| `pipelineRef` | 직접 정한 값 그대로입니다. `system:`으로 시작하면 실패입니다. |
| `image` | `registry`, `namespace`, `name`, `tag`가 모두 차 있어야 합니다. |

## 문제 해결

먼저 `orbit doctor`를 실행합니다. gate step의 `args`를 `[doctor, --pipeline-ref=$(params.pipeline-ref)]`로 바꾸면 됩니다.

| 증상 | 조치 |
|---|---|
| `pipelineRef`가 `system:`으로 시작 | `--pipeline-ref`가 빠졌습니다. |
| `pipelineRef is not canonical`(`400`) | 오류가 알려 주는 `canonical` 값을 그대로 씁니다. |
| `database runroot … does not match` | `--runroot`가 컨테이너마다 다릅니다. |
| sidecar가 `ready`가 되지 않음 | probe의 소켓 경로와 `unix://` 경로를 맞춥니다. |
| 취약점 0건으로 통과 | SBOM이 비었을 수 있습니다. 빌드 산출물이 이미지에 들어갔는지 확인합니다. |

## 다음 단계

- 노드 도커 소켓을 쓰는 구성: TBD
- 데몬을 쓸 수 없는 경우(`scan file`, 런타임 이미지 매칭 제한): TBD
- push 후 digest 보고(`scan promote`): TBD
- 폐쇄망(`ORBIT_ADDRESS`, `ORBIT_ISSUER` 지정): [저장소 README](../README.md)의 "서버 주소와 발급자"
